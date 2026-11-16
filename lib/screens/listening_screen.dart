import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/listening.dart';
import '../data/progress.dart';
import '../exercises/common.dart' show stableShuffle;
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_result_screen.dart';

enum _Phase { listen, questions, transcript }

/// A listening piece ([NodeType.listening]): the learner first only listens
/// to a 30–60 second dialogue (text hidden; slower at 0.75×, as often as they
/// like), then answers its questions, then sees the text with each speaker in
/// their own colour and can hear any line again. No hearts and no penalty: a
/// wrong answer can be tried again, the piece gives its XP like a lesson.
class ListeningScreen extends ConsumerStatefulWidget {
  const ListeningScreen({
    super.key,
    required this.node,
    required this.color,
    this.gap = const Duration(milliseconds: 350),
  });

  final PathNode node;
  final Color color;

  /// Pause between two lines.
  final Duration gap;

  @override
  ConsumerState<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends ConsumerState<ListeningScreen> {
  late final ListeningPiece _piece = widget.node.listening!;
  late final LinePlayer _player = ref.read(linePlayerProvider);
  final DateTime _started = DateTime.now();

  _Phase _phase = _Phase.listen;
  double _rate = 1;

  /// The dialogue was heard to the end at least once.
  bool _heard = false;
  bool _playing = false;

  /// Line being played, or null.
  int? _current;

  /// Bumped to cancel a running playback.
  int _run = 0;

  int _question = 0;
  String? _picked;
  bool? _pickedRight;
  int _right = 0;
  int _wrong = 0;
  int _shake = 0;
  final Set<int> _translated = {};

  @override
  void dispose() {
    _run++;
    _player.stopLine();
    super.dispose();
  }

  Color _colorOf(String speaker) => (_piece.speaker(speaker)?.female ?? true) ? Brand.accent : Brand.info;

  Future<void> _say(int i) => _player.sayLine(
    _piece.lines[i].text,
    rate: _rate,
    pitch: pitchFor(female: _piece.speaker(_piece.lines[i].speaker)?.female ?? true),
  );

  /// Plays the dialogue from [from] to the end.
  Future<void> _playAll({int from = 0}) async {
    final run = ++_run;
    setState(() => _playing = true);
    for (var i = from; i < _piece.lines.length; i++) {
      if (run != _run || !mounted) return;
      setState(() => _current = i);
      await _say(i);
      if (run != _run || !mounted) return;
      if (widget.gap > Duration.zero && i < _piece.lines.length - 1) await Future<void>.delayed(widget.gap);
    }
    if (run != _run || !mounted) return;
    setState(() {
      _playing = false;
      _current = null;
      _heard = true;
    });
  }

  void _stop() {
    _run++;
    _player.stopLine();
    setState(() {
      _playing = false;
      _current = null;
    });
  }

  /// Plays one line of the transcript and shows its translation.
  void _tapLine(int i) {
    _run++;
    setState(() {
      _playing = false;
      _current = i;
      _translated.contains(i) ? _translated.remove(i) : _translated.add(i);
    });
    _say(i);
  }

  void _toQuestions() {
    _stop();
    setState(() => _phase = _Phase.questions);
  }

  ListeningQuestion get _q => _piece.questions[_question];

  void _answer(String choice) {
    if (_pickedRight == true) return;
    final right = choice == _q.answer;
    setState(() {
      _picked = choice;
      _pickedRight = right;
      if (right) {
        _right++;
      } else {
        _wrong++;
        _shake++;
      }
    });
    right ? Haptics.success() : Haptics.error();
  }

  void _nextQuestion() {
    if (_playing) _stop();
    setState(() {
      _picked = null;
      _pickedRight = null;
      if (_question < _piece.questions.length - 1) {
        _question++;
      } else {
        _phase = _Phase.transcript;
      }
    });
  }

  void _finish() {
    _stop();
    final answered = _right + _wrong;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          widget.node.id,
          xp: widget.node.rewardXp,
          answered: answered,
          correct: _right,
          perfect: _wrong == 0,
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: answered == 0 ? 100 : (_right * 100 / answered).round(),
          duration: DateTime.now().difference(_started),
          perfect: _wrong == 0,
          headline: 'Dinleme tamamlandı!',
        ),
      ),
    );
  }

  double get _progress => switch (_phase) {
    _Phase.listen => _heard ? 0.25 : 0.1,
    _Phase.questions => 0.25 + 0.65 * (_question + (_pickedRight == true ? 1 : 0)) / _piece.questions.length,
    _Phase.transcript => 1,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Brand.muted),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: GlossyProgress(value: _progress, color: widget.color),
                  ),
                  TextButton(
                    key: const Key('listening-speed'),
                    onPressed: () => setState(() => _rate = _rate == 1 ? 0.75 : 1),
                    child: Text(_rate == 1 ? '1×' : '0.75×'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_phase) {
                _Phase.listen => _listenView(),
                _Phase.questions => _questionView(),
                _Phase.transcript => _transcriptView(),
              },
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: switch (_phase) {
                _Phase.listen => PressableButton(
                  key: const Key('listening-to-questions'),
                  label: 'SORULARA GEÇ',
                  color: widget.color,
                  onPressed: _heard ? _toQuestions : null,
                ),
                _Phase.questions => PressableButton(
                  label: _question < _piece.questions.length - 1 ? 'DEVAM' : 'METNİ GÖR',
                  color: widget.color,
                  onPressed: _pickedRight == true ? _nextQuestion : null,
                ),
                _Phase.transcript => PressableButton(label: 'BİTİR', color: widget.color, onPressed: _finish),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _speakerChip(ListeningSpeaker s, {bool speaking = false}) {
    final c = s.female ? Brand.accent : Brand.info;
    return AnimatedScale(
      scale: speaking ? 1.12 : 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: speaking ? c : Colors.transparent, width: 3),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: c.withValues(alpha: 0.15),
              child: Text(s.avatar, style: const TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.name,
            style: TextStyle(color: c, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _listenView() {
    final speaking = _current == null ? null : _piece.lines[_current!].speaker;
    final secs = ListeningRules.of(_piece.cefr).seconds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(widget.node.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${_piece.cefr} · ≈$secs sn · ${_piece.lines.length} replik',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Metin gizli. Önce dikkatle dinle; sonra ${_piece.questions.length} soru gelecek, '
          'metni en sonda göreceksin.',
          key: const Key('listening-hint'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (final s in _piece.speakers) _speakerChip(s, speaking: s.name == speaking)],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _piece.lines.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _current ? 22 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i == _current ? _colorOf(_piece.lines[i].speaker) : Brand.line,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: FilledButton(
              key: const Key('listening-play'),
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: widget.color,
                padding: EdgeInsets.zero,
              ),
              onPressed: _playing ? _stop : () => _playAll(),
              child: Icon(
                _playing ? Icons.stop_rounded : (_heard ? Icons.replay_rounded : Icons.headphones_rounded),
                size: 44,
                color: onColor(widget.color),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _playing
              ? 'Dinleniyor…'
              : _heard
              ? 'Tekrar dinleyebilir ya da sorulara geçebilirsin.'
              : 'Başlamak için dokun',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _questionView() {
    final q = _q;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Soru ${_question + 1} / ${_piece.questions.length}',
                style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              key: const Key('listening-replay'),
              icon: Icon(_playing ? Icons.stop_rounded : Icons.replay_rounded),
              label: Text(_playing ? 'Durdur' : 'Tekrar dinle'),
              onPressed: _playing ? _stop : () => _playAll(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Shake(
          trigger: _shake,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      q.kind == ListeningQuestionKind.who
                          ? Icons.record_voice_over_rounded
                          : Icons.help_rounded,
                      color: Brand.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(q.prompt, style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                if (q.quote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '“${q.quote}”',
                      style: const TextStyle(
                        fontSize: 17,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (q.kind == ListeningQuestionKind.trueFalse)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Doğru mu, yanlış mı?', style: TextStyle(color: Brand.muted)),
                  ),
                const SizedBox(height: 12),
                for (final c
                    in q.kind == ListeningQuestionKind.choice
                        ? stableShuffle(q.choices, q.prompt)
                        : q.choices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TapCard(
                      selected: _picked == c,
                      color: _pickedRight == true ? Brand.success : Brand.error,
                      onTap: () => _answer(c),
                      child: Row(
                        children: [
                          if (q.kind == ListeningQuestionKind.who) ...[
                            Text(_piece.speaker(c)?.avatar ?? '🙂', style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(c, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_pickedRight != null)
          Row(
            children: [
              Mascot(mood: _pickedRight! ? Mood.happy : Mood.think, size: 56, decorative: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _pickedRight!
                      ? 'Doğru! Kulağın iyi.'
                      : 'Olmadı. İstersen tekrar dinle, sonra yeniden dene.',
                  style: TextStyle(
                    color: _pickedRight! ? Brand.success : Brand.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _transcriptView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Metin', style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(
              key: const Key('listening-replay-all'),
              icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(_playing ? 'Durdur' : 'Hepsini dinle'),
              onPressed: _playing ? _stop : () => _playAll(),
            ),
          ],
        ),
        Text('Bir satıra dokun: tekrar duy ve çevirisini gör.', style: TextStyle(color: Brand.muted)),
        const SizedBox(height: 14),
        for (var i = 0; i < _piece.lines.length; i++) _line(i),
        if (_piece.idioms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Bu parçadaki kalıplar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final idiom in _piece.idioms)
                Chip(label: Text(idiom), backgroundColor: Brand.accentBg, side: BorderSide.none),
            ],
          ),
        ],
      ],
    );
  }

  Widget _line(int i) {
    final l = _piece.lines[i];
    final s = _piece.speaker(l.speaker);
    final right = _piece.speakers.indexOf(s ?? _piece.speakers.first).isOdd;
    final c = _colorOf(l.speaker);
    final active = _current == i;
    final showTr = _translated.contains(i) && l.translation != null;
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: c.withValues(alpha: 0.15),
      child: Text(s?.avatar ?? '🙂', style: const TextStyle(fontSize: 22)),
    );
    final bubble = Flexible(
      child: GestureDetector(
        key: Key('listening-line-$i'),
        onTap: () => _tapLine(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: active ? 0.22 : 0.10),
            border: Border.all(color: c.withValues(alpha: active ? 1 : 0.5), width: 2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(right ? 18 : 4),
              bottomRight: Radius.circular(right ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.speaker,
                style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(l.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: showTr
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(l.translation!, style: TextStyle(color: Brand.muted)),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: right
            ? [const SizedBox(width: 32), bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble, const SizedBox(width: 32)],
      ),
    );
  }
}
