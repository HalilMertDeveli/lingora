import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../data/progress.dart';
import '../data/quests.dart';
import '../exercises/common.dart' show SpeakerButton;
import '../exercises/speak_exercise.dart' show speakPassRatio;
import '../models/pronunciation.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_result_screen.dart';

Future<List<PronUnit>> loadPronUnits(AssetBundle bundle) async =>
    parsePronUnits(await bundle.loadString('assets/pronunciation/units.json'));

final pronUnitsProvider = FutureProvider<List<PronUnit>>((ref) => loadPronUnits(rootBundle));

Color get _coachColor => Brand.tone(const Color(0xFFFF7A1A));

/// Card at the top of the Konuş tab that opens the coach.
class PronunciationEntryCard extends StatelessWidget {
  const PronunciationEntryCard({super.key});

  @override
  Widget build(BuildContext context) => PopIn(
    from: 0.9,
    child: TapCard(
      color: _coachColor,
      selected: true,
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PronunciationScreen())),
      child: Row(
        children: [
          Glyph(emoji: '👄', icon: Icons.record_voice_over_outlined, size: 34, color: _coachColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Telaffuz koçu', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'th, w/v, ship/sheep… Türklerin zorlandığı sesleri dinle ve söyle.',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _coachColor),
        ],
      ),
    ),
  );
}

/// "Telaffuz koçu": list of sound units.
class PronunciationScreen extends ConsumerWidget {
  const PronunciationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(pronUnitsProvider);
    final progress = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Telaffuz koçu')),
      body: units.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Üniteler yüklenemedi: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(
              children: [
                const Mascot(mood: Mood.think, size: 76, decorative: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Türkçede olmayan ya da farklı çıkan İngilizce sesleri tek tek çalışalım. '
                    'Önce nasıl yapıldığını oku, sonra dinle ve söyle.',
                    style: TextStyle(color: Brand.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final (i, u) in list.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PopIn(
                  delay: Duration(milliseconds: 40 * min(i, 8)),
                  from: 0.9,
                  child: _UnitTile(unit: u, done: progress.isDone(u.nodeId)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.done});
  final PronUnit unit;
  final bool done;

  @override
  Widget build(BuildContext context) => TapCard(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PronunciationUnitScreen(unit: unit)),
    ),
    child: Row(
      children: [
        Text(unit.emoji, style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(unit.title, style: Theme.of(context).textTheme.titleMedium)),
                  const SizedBox(width: 6),
                  Text(
                    unit.sound,
                    style: TextStyle(color: _coachColor, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(unit.summary, style: TextStyle(color: Brand.muted, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        done
            ? Icon(Icons.check_circle_rounded, color: Brand.success)
            : Icon(Icons.chevron_right_rounded, color: Brand.muted),
      ],
    ),
  );
}

enum _Kind { explain, listen, speak }

class _Step {
  const _Step.explain() : kind = _Kind.explain, pair = null, target = '', targetTr = '';
  const _Step.listen(MinimalPair this.pair, {required this.target}) : kind = _Kind.listen, targetTr = '';
  const _Step.speak(this.target, this.targetTr, {this.pair}) : kind = _Kind.speak;

  final _Kind kind;
  final MinimalPair? pair;

  /// Listening: the word that is played. Speaking: what the user says.
  final String target;
  final String targetTr;
}

/// Friendly Turkish feedback for a speaking attempt. [pair] lets us say
/// which word it sounded like when the user hit the partner instead.
String speakFeedback({required String target, required String heard, MinimalPair? pair}) {
  if (heard.trim().isEmpty) return 'Seni duyamadım. Biraz daha yüksek ve yavaş söyleyip tekrar dene.';
  final score = spokenSimilarity(target, heard);
  if (score >= 1) return 'Harika! Çok net anlaşıldı.';
  if (pair != null) {
    final other = normalizeAnswer(target) == normalizeAnswer(pair.a) ? pair.b : pair.a;
    if (spokenSimilarity(other, heard) >= 1) {
      return 'Bunu “$other” gibi duydum. Açıklamadaki ağız konumunu hatırla ve bir daha dene.';
    }
  }
  if (score >= speakPassRatio) {
    return 'Güzel, neredeyse tamam! Kaçan kelimeyi bir kez dinle, sonra tekrar söyle.';
  }
  return 'Ben “$heard” duydum. Yavaş dinle ve tekrar dene; acele yok.';
}

/// One unit: explanation, "Hangisini duydun?" drills, then "Söyle" drills.
class PronunciationUnitScreen extends ConsumerStatefulWidget {
  const PronunciationUnitScreen({super.key, required this.unit});
  final PronUnit unit;

  @override
  ConsumerState<PronunciationUnitScreen> createState() => _PronunciationUnitScreenState();
}

class _PronunciationUnitScreenState extends ConsumerState<PronunciationUnitScreen> {
  final _started = DateTime.now();
  final _rand = Random();
  late final SpeechService _speech = ref.read(speechProvider);
  late final List<_Step> _steps = [
    const _Step.explain(),
    for (final p in u.pairs) _Step.listen(p, target: _rand.nextBool() ? p.a : p.b),
    for (final p in u.pairs.take(2)) _Step.speak(p.a, p.aTr, pair: p),
    for (final s in u.sentences.take(2)) _Step.speak(s.en, s.tr),
  ];

  int _i = 0;

  // Listening.
  String? _picked;
  int _listenCorrect = 0;
  int _shake = 0;

  // Speaking.
  bool _listening = false;
  bool _attempted = false;
  bool _micUnavailable = false;
  String _heard = '';
  bool _passedThis = false;
  int _speakPassed = 0;

  PronUnit get u => widget.unit;
  _Step get _step => _steps[_i];
  int get _listenTotal => u.pairs.length;

  @override
  void dispose() {
    if (_listening) _speech.stopListening();
    super.dispose();
  }

  void _next() {
    if (_listening) _speech.stopListening();
    if (_passedThis) _speakPassed++;
    if (_i + 1 >= _steps.length) {
      _finish();
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _listening = false;
      _attempted = false;
      _heard = '';
      _passedThis = false;
    });
    if (_step.kind != _Kind.explain) _speech.say(_step.target);
  }

  void _pick(String word) {
    if (_picked != null) return;
    final right = word == _step.target;
    setState(() {
      _picked = word;
      if (right) {
        _listenCorrect++;
      } else {
        _shake++;
      }
    });
    right ? Haptics.success() : Haptics.error();
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stopListening();
      return;
    }
    if (!await _speech.canListen) {
      if (mounted) setState(() => _micUnavailable = true);
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await _speech.listen(
      onWords: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: () {
        if (!mounted) return;
        final passed = _heard.isNotEmpty && spokenSimilarity(_step.target, _heard) >= speakPassRatio;
        setState(() {
          _listening = false;
          _attempted = true;
          _passedThis = _passedThis || passed;
        });
        passed ? Haptics.success() : Haptics.tap();
      },
    );
  }

  void _finish() {
    final perfect = _listenCorrect == _listenTotal;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          u.nodeId,
          xp: 10 + _listenCorrect + _speakPassed,
          answered: _listenTotal,
          correct: _listenCorrect,
          perfect: perfect,
          stats: {QuestMetric.listen: _listenCorrect},
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: _listenTotal == 0 ? 100 : (_listenCorrect * 100 / _listenTotal).round(),
          duration: DateTime.now().difference(_started),
          perfect: perfect,
          headline: '${u.title} tamam!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _step;
    final isLast = _i == _steps.length - 1;
    final label = switch (s.kind) {
      _ when isLast => 'BİTİR',
      _Kind.explain => 'ALIŞTIRMAYA BAŞLA',
      _Kind.speak when !_attempted && !_micUnavailable => 'ATLA',
      _ => 'DEVAM',
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Brand.muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: GlossyProgress(value: (_i + 1) / _steps.length, color: _coachColor),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                layoutBuilder: (c, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?c]),
                child: ListView(
                  key: ValueKey(_i),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    switch (s.kind) {
                      _Kind.explain => _explain(),
                      _Kind.listen => _listen(s),
                      _Kind.speak => _speak(s),
                    },
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: PressableButton(
                label: label,
                color: _coachColor,
                onPressed: s.kind == _Kind.listen && _picked == null ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String kicker, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: TextStyle(color: _coachColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ],
    ),
  );

  Widget _box({required Color color, required IconData icon, required String title, required String text}) =>
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _explain() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          PopIn(child: Text(u.emoji, style: const TextStyle(fontSize: 56))),
          const SizedBox(width: 12),
          Expanded(child: _title('SES  ${u.sound}', u.title)),
        ],
      ),
      const Text('Nasıl söylenir?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      for (final (i, h) in u.how.indexed)
        PopIn(
          delay: Duration(milliseconds: 80 * (i + 1)),
          from: 0.9,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: _coachColor,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: onColor(_coachColor), fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(h, style: const TextStyle(height: 1.35))),
              ],
            ),
          ),
        ),
      _box(
        color: const Color(0xFF2F80ED),
        icon: Icons.translate_rounded,
        title: 'Türkçeyle farkı',
        text: u.turkish,
      ),
      _box(
        color: Brand.error,
        icon: Icons.hearing_disabled_rounded,
        title: 'Sık yapılan hata',
        text: u.mistake,
      ),
      const SizedBox(height: 18),
      const Text('Kulağını alıştır', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      for (final p in u.pairs.take(3))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: _hearChip(p.a, p.aTr)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('≠', style: TextStyle(color: Brand.muted, fontSize: 18)),
              ),
              Expanded(child: _hearChip(p.b, p.bTr)),
            ],
          ),
        ),
    ],
  );

  Widget _hearChip(String word, String tr) => TapCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    onTap: () => _speech.say(word),
    child: Row(
      children: [
        Icon(Icons.volume_up_rounded, color: _coachColor, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(word, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Brand.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _listen(_Step s) {
    final p = s.pair!;
    final picked = _picked;
    final right = picked == s.target;
    Widget option(String word, String tr) {
      final isTarget = word == s.target;
      final color = picked == null
          ? null
          : isTarget
          ? Brand.success
          : (word == picked ? Brand.error : null);
      return TapCard(
        selected: color != null,
        color: color,
        onTap: picked == null ? () => _pick(word) : null,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(
          children: [
            Text(word, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            if (picked != null) Text(tr, style: TextStyle(color: Brand.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('DİNLE', 'Hangisini duydun?'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpeakerButton(text: s.target, size: 88),
            const SizedBox(width: 20),
            SpeakerButton(text: s.target, size: 56, slow: true),
          ],
        ),
        const SizedBox(height: 28),
        Shake(
          trigger: _shake,
          child: Row(
            children: [
              Expanded(child: option(p.a, p.aTr)),
              const SizedBox(width: 12),
              Expanded(child: option(p.b, p.bTr)),
            ],
          ),
        ),
        if (picked != null) ...[
          const SizedBox(height: 20),
          PopIn(
            child: Row(
              children: [
                Mascot(mood: right ? Mood.cheer : Mood.think, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    right
                        ? 'Doğru! “${s.target}” dedim. Kulağın bu farkı yakalıyor.'
                        : 'Bu sefer “${s.target}” dedim. Bu iki ses çok yakın; ikisini art arda dinle.',
                    style: TextStyle(
                      color: right ? Brand.success : Brand.ink,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!right) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _hearChip(p.a, p.aTr)),
                const SizedBox(width: 12),
                Expanded(child: _hearChip(p.b, p.bTr)),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _speak(_Step s) {
    final feedback = _attempted ? speakFeedback(target: s.target, heard: _heard, pair: s.pair) : null;
    final good = _attempted && _heard.isNotEmpty && spokenSimilarity(s.target, _heard) >= speakPassRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('KONUŞ', 'Söyle'),
        Row(
          children: [
            SpeakerButton(text: s.target),
            const SizedBox(width: 8),
            SpeakerButton(text: s.target, slow: true, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.target, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  if (s.targetTr.isNotEmpty) Text(s.targetTr, style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (_micUnavailable)
          PopIn(
            child: _box(
              color: Brand.accent,
              icon: Icons.mic_off_rounded,
              title: 'Mikrofon kullanılamıyor',
              text: 'Sorun değil: kelimeyi dinle, yüksek sesle birkaç kez tekrar et ve devam et.',
            ),
          )
        else ...[
          Center(
            child: Pulse(
              enabled: _listening,
              child: Material(
                color: _listening ? Brand.error : _coachColor,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggleMic,
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: onColor(_listening ? Brand.error : _coachColor),
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _listening
                ? 'Dinliyorum…'
                : _attempted
                ? (_heard.isEmpty ? '' : '“$_heard”')
                : 'Mikrofona dokun ve söyle',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontSize: 16),
          ),
        ],
        if (feedback != null) ...[
          const SizedBox(height: 16),
          PopIn(
            key: ValueKey(feedback + _heard),
            child: Row(
              children: [
                Mascot(mood: good ? Mood.cheer : Mood.think, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feedback,
                    style: TextStyle(
                      color: good ? Brand.success : Brand.ink,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
