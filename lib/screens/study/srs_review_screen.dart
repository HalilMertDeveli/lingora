import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_repository.dart';
import '../../data/practice.dart';
import '../../data/progress.dart';
import '../../study/review_queue.dart';
import '../../theme.dart';
import '../../ui/motion.dart';
import '../lesson_screen.dart';
import 'methods_screen.dart';

/// Opens "Tekrar kartları" full screen.
Future<void> openReviewCards(BuildContext context, {int newPerDay = defaultNewWordsPerDay}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => SrsReviewScreen(newPerDay: newPerDay)),
    );

/// Today's queue for the open course.
final reviewQueueProvider = Provider.family<ReviewQueue?, int>((ref, newPerDay) {
  final course = ref.watch(courseProvider).value;
  if (course == null) return null;
  final today = dayKey(ref.watch(clockProvider)());
  return reviewQueue(
    course,
    ref.watch(progressProvider),
    today: today,
    newPerDay: newPerDay,
    ydsCards: ref.watch(ydsVocabProvider).value ?? const [],
  );
});

/// "Tekrar kartları": word cards due today and the day's new words, recalled
/// before they are turned ("Hatırladın mı?"), then the error notebook's
/// questions that are due, solved again.
class SrsReviewScreen extends ConsumerStatefulWidget {
  const SrsReviewScreen({super.key, this.newPerDay = defaultNewWordsPerDay});
  final int newPerDay;

  @override
  ConsumerState<SrsReviewScreen> createState() => _SrsReviewScreenState();
}

class _SrsReviewScreenState extends ConsumerState<SrsReviewScreen> {
  /// Fixed when the screen opens, so cards do not move under the learner.
  ReviewQueue? _queue;
  late List<WordCard> _cards;
  final _fresh = <String>{};
  int _pos = 0;
  bool _shown = false;
  int _reviewed = 0;

  /// Cards answered "Hatırlamadım" come back once at the end.
  final _again = <String>{};

  void _take(ReviewQueue q) {
    _queue = q;
    _cards = [...q.cards];
    _fresh.addAll(q.fresh.map((c) => c.id));
  }

  String _next(String id, bool known) {
    final box = ref.read(progressProvider).wordBox[id] ?? 0;
    final next = known ? (box + 1).clamp(0, reviewIntervals.length - 1) : (box - 2).clamp(0, box);
    final days = reviewIntervals[next];
    if (days == 0) return 'bugün';
    if (days < 30) return '$days gün';
    return '${days ~/ 30} ay';
  }

  void _grade(bool known) {
    final c = _cards[_pos];
    ref.read(progressProvider.notifier).learnWord(c.id, known: known);
    setState(() {
      _reviewed++;
      if (!known && _again.add(c.id)) _cards.add(c);
      _pos++;
      _shown = false;
    });
  }

  void _solveMistakes() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LessonScreen(
          nodeId: 'practice',
          title: 'Hata defteri',
          items: _queue!.mistakes,
          color: Brand.error,
          mode: LessonMode.practice,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_queue == null) {
      final q = ref.watch(reviewQueueProvider(widget.newPerDay));
      if (q == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      _take(q);
    }
    final t = Theme.of(context).textTheme;
    final finished = _pos >= _cards.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tekrar kartları'),
        actions: [
          IconButton(
            tooltip: 'Aralıklı tekrar nedir?',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => openMethods(context, focus: 'spacing'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: _cards.isEmpty ? 1 : (_pos / _cards.length).clamp(0, 1).toDouble(),
            color: Brand.success,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_queue!.reviewDay)
                Container(
                  key: const Key('srs-review-day'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Bugün tekrar günü: yeni kelime azaltıldı'),
                ),
              Expanded(child: finished ? _done(t) : _card(_cards[_pos], t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _done(TextTheme t) {
    final mistakes = _queue!.mistakes.length;
    final nothing = _reviewed == 0 && mistakes == 0;
    return Column(
      key: const Key('srs-done'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✅', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        Text(
          nothing ? 'Bugünlük kart yok' : 'Kelime kartları bitti',
          textAlign: TextAlign.center,
          style: t.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          nothing
              ? 'Kelime dersi bitirdikçe yeni kartlar gelir.'
              : '$_reviewed kart tekrarlandı. Bildiğin kart daha geç, bilmediğin daha erken geri gelecek.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 24),
        if (mistakes > 0) ...[
          PressableButton(
            key: const Key('srs-mistakes'),
            label: 'HATA DEFTERİ ($mistakes SORU)',
            onPressed: _solveMistakes,
          ),
          const SizedBox(height: 10),
        ],
        PressableButton(label: 'BİTİR', outlined: mistakes > 0, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _card(WordCard c, TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _Chip(
            label: _fresh.contains(c.id) && !_again.contains(c.id) ? 'YENİ' : 'TEKRAR',
            color: _fresh.contains(c.id) ? Brand.accent : Brand.primary,
          ),
          const Spacer(),
          Text('${_pos + 1} / ${_cards.length}', style: TextStyle(color: Brand.muted)),
        ],
      ),
      Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.en,
                key: const Key('srs-front'),
                textAlign: TextAlign.center,
                style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: Brand.ink),
              ),
              const SizedBox(height: 16),
              _shown
                  ? Column(
                      children: [
                        Text(
                          c.tr,
                          key: const Key('srs-back'),
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(color: Brand.tone(Brand.primary)),
                        ),
                        if (c.example case final ex?) ...[
                          const SizedBox(height: 12),
                          Text(
                            ex,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Brand.muted, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      'Önce anlamını aklından söyle, sonra kartı çevir.',
                      key: const Key('srs-hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Brand.muted),
                    ),
            ],
          ),
        ),
      ),
      if (!_shown)
        PressableButton(
          key: const Key('srs-show'),
          label: 'CEVABI GÖSTER',
          onPressed: () => setState(() => _shown = true),
        )
      else ...[
        Text('Hatırladın mı?', textAlign: TextAlign.center, style: t.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _GradeButton(
                key: const Key('srs-again'),
                label: 'Hatırlamadım',
                interval: _next(c.id, false),
                color: Brand.error,
                onTap: () => _grade(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GradeButton(
                key: const Key('srs-good'),
                label: 'Hatırladım',
                interval: _next(c.id, true),
                color: Brand.success,
                onTap: () => _grade(true),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Brand.tone(color), borderRadius: BorderRadius.circular(10)),
    child: Text(
      label,
      style: TextStyle(color: onColor(Brand.tone(color)), fontWeight: FontWeight.w900, fontSize: 12),
    ),
  );
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    super.key,
    required this.label,
    required this.interval,
    required this.color,
    required this.onTap,
  });
  final String label;
  final String interval;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w900, color: Brand.tone(color)),
        ),
        Text('sonraki: $interval', style: TextStyle(color: Brand.muted, fontSize: 12)),
      ],
    ),
  );
}
