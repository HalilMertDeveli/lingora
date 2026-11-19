import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/rehearsal.dart';
import '../../services/rehearsal_service.dart';
import '../../services/speech.dart';
import '../../services/voice_recorder.dart';
import '../../theme.dart';
import '../../services/growth/analytics_events.dart' show PaywallPlacement;
import '../paywall_screen.dart';
import '../../services/billing/products.dart';
import 'rehearsal_analysis_screen.dart';

/// Paywall placement (analytics) for every Mülakat Provası gate.
const rehearsalPlacement = PaywallPlacement.interviewRehearsal;

/// Minimum words per answer before moving on (the server needs a few
/// sentences to say anything useful).
const minAnswerWords = 3;

String newRehearsalId(DateTime now) => 'r${now.millisecondsSinceEpoch.toRadixString(36)}';

/// Answers [questions] one by one in the learner's own words: by voice
/// (recorded to a local file, with the phone's speech recognition writing
/// the transcript) or by typing. No options to pick from. At the end the
/// answers are analysed and the analysis opens.
/// Set when this phone recorded only silence next to speech recognition:
/// later answers are not recorded, so the recognizer hears all of them.
const recordingOffKey = 'prova_recording_off_v1';

/// Pause before the recognizer is started again while recording.
const listenRestartDelay = Duration(milliseconds: 400);

/// Silent recognizer restarts allowed in a row before it is left off.
const maxSilentRestarts = 5;

class RehearsalAnswerScreen extends ConsumerStatefulWidget {
  const RehearsalAnswerScreen({
    super.key,
    required this.kind,
    required this.questions,
    this.title,
    this.taskId,
  }) : retrySession = null;

  /// Analyses a saved [session] whose analysis failed earlier.
  RehearsalAnswerScreen.retry({super.key, required RehearsalSession session})
    : kind = session.kind,
      questions = const [],
      title = 'Analiz',
      taskId = null,
      retrySession = session;

  final RehearsalKind kind;
  final List<InterviewQuestion> questions;
  final String? title;

  /// A study task this rehearsal completes (the retell), once analysed.
  final String? taskId;
  final RehearsalSession? retrySession;

  @override
  ConsumerState<RehearsalAnswerScreen> createState() => _RehearsalAnswerScreenState();
}

class _RehearsalAnswerScreenState extends ConsumerState<RehearsalAnswerScreen> {
  late final String _id = widget.retrySession?.id ?? newRehearsalId(ref.read(clockProvider)());
  final _answers = <RehearsalAnswer>[];
  final _text = TextEditingController();
  int _index = 0;
  bool _recording = false;

  /// The microphone was used on this screen: before that, [speechIssue] still
  /// holds another screen's problem ("Seni duyamadım" on arrival, QA).
  bool _listened = false;
  bool _typing = false;
  bool _hint = false;
  int _retakes = 0;
  String? _audio;
  String _heardBefore = '';
  bool _analysing = false;
  String? _error;
  bool _needsPremium = false;

  /// A step is running: a second tap (on "Bitir ve analiz et" or "Tekrar
  /// dene") must not add the answer twice or spend a second analysis.
  bool _advancing = false;

  late final VoiceRecorder _recorder = ref.read(voiceRecorderProvider);
  late final SpeechService _speechService = ref.read(speechProvider);

  /// Recognizer restarts in a row that heard nothing.
  int _silentRestarts = 0;
  bool _inFlight = false;

  /// Something would be lost by leaving now.
  bool get _hasWork => _answers.isNotEmpty || _text.text.trim().isNotEmpty || _audio != null || _recording;

  @override
  void initState() {
    super.initState();
    _recorder;
    _speechService;
    final retry = widget.retrySession;
    if (retry != null) {
      _answers.addAll(retry.answers);
      _analysing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _analyse());
    }
  }

  InterviewQuestion get _q => widget.questions[_index];
  bool get _last => _index == widget.questions.length - 1;

  @override
  void dispose() {
    // Leaving while recording (back, app closed): the microphone must stop.
    // No ref here (the element is going away): the services were kept.
    if (_recording) {
      _recorder.cancel();
      _speechService.stopListening();
    }
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    _silentRestarts = 0;
    if (_recording) {
      await _stop();
      return;
    }
    final speech = ref.read(speechProvider);
    if (!await speech.canListen) {
      if (!mounted) return;
      setState(() => _typing = true);
      return;
    }
    if (_audio != null || _text.text.trim().isNotEmpty) _retake();
    final recorded =
        !(ref.read(prefsProvider).getBool(recordingOffKey) ?? false) &&
        await ref.read(voiceRecorderProvider).start('${_id}_$_index');
    if (!mounted) return;
    setState(() {
      _recording = true;
      _listened = true;
      _audio = recorded ? '' : null;
      _heardBefore = _text.text.trim();
    });
    _listen();
  }

  /// The recognizer stops after a pause; while the learner is still
  /// answering it is started again and the text keeps growing.
  void _listen() {
    final speech = ref.read(speechProvider);
    var heard = false;
    speech.listen(
      onWords: (w) {
        if (!mounted) return;
        heard = true;
        _silentRestarts = 0;
        setState(() => _text.text = [_heardBefore, w].where((s) => s.isNotEmpty).join(' '));
      },
      onDone: () {
        if (!mounted || !_recording) return;
        _heardBefore = _text.text.trim();
        // A recognizer that stops at once ("busy" on Samsung, no network)
        // must not be restarted in a tight loop: wait a moment, and give up
        // after a few silent tries (the recording itself goes on and the
        // learner can type).
        if (!heard && ++_silentRestarts > maxSilentRestarts) return;
        Future<void>.delayed(listenRestartDelay, () {
          if (mounted && _recording) _listen();
        });
      },
    );
  }

  Future<void> _stop() async {
    final started = _audio != null; // the recorder said it was recording
    setState(() => _recording = false);
    await ref.read(speechProvider).stopListening();
    final path = await ref.read(voiceRecorderProvider).stop();
    if (!mounted) return;
    setState(() => _audio = path);
    if (started && path == null && !ref.read(prefsProvider).containsKey(recordingOffKey)) {
      // This phone gives the microphone to speech recognition only: record
      // no more, so the recognizer always hears the whole answer.
      ref.read(prefsProvider).setBool(recordingOffKey, true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Bu telefon konuşma tanıma sırasında ses kaydına izin vermiyor; cevapların yazıya dökülerek saklanacak.',
          ),
        ),
      );
    }
  }

  /// Throws the current answer away: counts as help (not unaided).
  void _retake() {
    final old = _audio;
    if (old != null && old.isNotEmpty) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
    setState(() {
      _retakes++;
      _audio = null;
      _text.clear();
    });
  }

  Future<void> _next() async {
    if (_advancing || _inFlight) return;
    _advancing = true;
    try {
      await _nextStep();
    } finally {
      _advancing = false;
    }
  }

  Future<void> _nextStep() async {
    if (_recording) await _stop();
    final text = _text.text.trim();
    _answers.add(
      RehearsalAnswer(
        questionId: _q.id,
        question: _q.text,
        answer: text,
        audioPath: (_audio?.isEmpty ?? true) ? null : _audio,
        typed: _audio == null || _audio!.isEmpty,
        retakes: _retakes,
        hintShown: _hint,
      ),
    );
    if (!_last) {
      setState(() {
        _index++;
        _listened = false;
        _text.clear();
        _audio = null;
        _hint = false;
        _retakes = 0;
      });
      return;
    }
    await _analyse();
  }

  Future<void> _analyse() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _analyseOnce();
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _analyseOnce() async {
    final store = ref.read(rehearsalProvider.notifier);
    final earlier = ref.read(rehearsalProvider);
    var session =
        widget.retrySession ??
        RehearsalSession(id: _id, kind: widget.kind, at: ref.read(clockProvider)(), answers: _answers);
    // Saved first: the recording and transcript are kept even if the analysis fails.
    store.putSession(session);
    setState(() {
      _analysing = true;
      _error = null;
      _needsPremium = false;
    });
    try {
      final analysis = await ref
          .read(rehearsalServiceProvider)
          .analyze(
            RehearsalRequest(
              id: _id,
              kind: widget.kind,
              answers: _answers,
              previousTags: widget.kind == RehearsalKind.first ? const [] : _earlier(earlier).tags,
              previousGaps: widget.kind == RehearsalKind.first ? const [] : _earlier(earlier).gaps,
            ),
          );
      session = session.withAnalysis(analysis);
      store.putSession(session);
      final task = widget.taskId;
      if (task != null) {
        final help = TaskAttempt()
          ..hints = _answers.where((a) => a.hintShown).length
          ..retries = _answers.fold(0, (n, a) => n + a.retakes);
        store.completeTask(task, 'Projeni yeniden anlattın (${session.wordCount} kelime)', help);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => RehearsalAnalysisScreen(sessionId: session.id)),
      );
    } on RehearsalException catch (e) {
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _error = e.message;
        _needsPremium = e.premiumRequired;
      });
    } on Object {
      // Never a spinner forever: the answers are saved, the learner may retry.
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _error = 'Bir sorun oldu. Cevabın kaydedildi, tekrar dene.';
      });
    }
  }

  /// Leaving halfway: the answers are not analysed and their recordings
  /// (kept only on this phone) are deleted, so nothing is left behind.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Provadan çıkılsın mı?'),
        content: const Text('Bu provadaki cevapların ve ses kayıtların silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Devam et')),
          TextButton(
            key: const Key('prova-leave'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    if (_recording) await _stop();
    for (final path in [for (final a in _answers) a.audioPath, _audio]) {
      if (path == null || path.isEmpty) continue;
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    _answers.clear();
    _text.clear();
    _audio = null;
    if (mounted) Navigator.of(context).pop();
  }

  /// Tags and gaps of the analyses before this one (not its own on a retry).
  ({List<String> tags, List<String> gaps}) _earlier(RehearsalState s) {
    final before = RehearsalState(
      sessions: [
        for (final x in s.sessions)
          if (x.id != _id) x,
      ],
    );
    return (tags: before.earlierTags, gaps: before.earlierGaps);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final words = countWords(_text.text);
    final title = widget.title ?? 'Mülakat provası';
    if (_analysing || _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Cevabın inceleniyor…', textAlign: TextAlign.center),
                    ],
                  )
                : Column(
                    key: const Key('prova-error'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      if (_needsPremium)
                        FilledButton(
                          onPressed: () async {
                            final gate = await requirePremium(
                              context,
                              ref,
                              PremiumFeature.interviewRehearsal,
                              placement: rehearsalPlacement,
                            );
                            if (gate == GateResult.premium) await _analyse();
                          },
                          child: const Text('Premium ile devam et'),
                        )
                      else
                        FilledButton(onPressed: _analyse, child: const Text('Tekrar dene')),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cevabımı kaydet, sonra bakarım'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_hasWork,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Soru ${_index + 1} / ${widget.questions.length} · ${_q.category.label}',
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _q.text,
                      key: const Key('prova-question'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Soruyu dinle',
                    icon: const Icon(Icons.volume_up_rounded),
                    onPressed: () => ref.read(speechProvider).say(_q.text),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Kendi cümlelerinle cevap ver. Şık yok; yanlış yapmaktan korkma, hatalarından çalışacağız.',
                style: TextStyle(color: p.muted),
              ),
              if (_hint) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('prova-hint-text'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.accentBg, borderRadius: BorderRadius.circular(12)),
                  child: Text('İpucu: ${_q.hintTr}'),
                ),
              ],
              const SizedBox(height: 20),
              if (!_typing) ...[
                Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: speechLevel,
                    builder: (context, level, _) => GestureDetector(
                      key: const Key('prova-mic'),
                      onTap: _toggleMic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 96 + (_recording ? level * 24 : 0),
                        height: 96 + (_recording ? level * 24 : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _recording ? p.error : p.primary,
                        ),
                        child: Icon(
                          _recording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _recording
                        ? 'Dinliyorum… bitince dur\'a bas.'
                        : _audio != null
                        ? 'Kaydedildi. Metni kontrol et, gerekirse düzelt.'
                        : 'Mikrofona dokun ve anlat.',
                    style: TextStyle(color: p.muted),
                  ),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: speechIssue,
                  builder: (context, issue, _) => issue == null || !_listened
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            issue,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.error),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('prova-answer-field'),
                controller: _text,
                minLines: 4,
                maxLines: 10,
                maxLength: 1500,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _typing ? 'Cevabını yaz (İngilizce)' : 'Söylediklerin (dökümü)',
                  border: const OutlineInputBorder(),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: const Key('prova-type'),
                    icon: Icon(_typing ? Icons.mic_rounded : Icons.keyboard_rounded),
                    label: Text(_typing ? 'Sesle cevapla' : 'Yazarak cevapla'),
                    onPressed: () async {
                      if (_recording) await _stop();
                      setState(() => _typing = !_typing);
                    },
                  ),
                  if (!_hint)
                    TextButton.icon(
                      key: const Key('prova-hint'),
                      icon: const Icon(Icons.lightbulb_outline_rounded),
                      label: const Text('İpucu'),
                      onPressed: () => setState(() => _hint = true),
                    ),
                  if (_text.text.isNotEmpty && !_recording)
                    TextButton.icon(
                      key: const Key('prova-retake'),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Baştan'),
                      onPressed: _retake,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('prova-next'),
                onPressed: words >= minAnswerWords ? _next : null,
                child: Text(_last ? 'Bitir ve analiz et' : 'Sonraki soru'),
              ),
              if (words < minAnswerWords && _text.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Biraz daha anlat (en az $minAnswerWords kelime).',
                    style: TextStyle(color: p.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
