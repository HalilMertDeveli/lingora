import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_repository.dart';
import '../../data/practice.dart';
import '../../data/gold_wallet.dart';
import '../../data/notes_repository.dart';
import '../../data/progress.dart';
import '../../data/review_grade.dart';
import '../../study/daily_plan.dart' show inMaintenance;
import '../../study/mistake_cards.dart';
import '../../study/review_card_data.dart';
import '../../study/review_queue.dart';
import '../../study/year_plan.dart';
import '../../theme.dart';
import '../../ui/mascot.dart';
import '../../ui/motion.dart';
import '../../ui/review_card.dart';
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
    // After the year plan, new cards come from every bank, not only the
    // units reached.
    everyUnit: ref.watch(inMaintenanceProvider),
    // Cards come from the learner's own wrong answers, not from every word
    // (old auto-made cards of never-missed words are simply not shown).
    cards: mistakeWordCards(ref.watch(progressProvider.select((p) => p.mistakeCards))),
  );
});

/// Whether the learner's year plan is over and "Bugün" runs maintenance
/// weeks (yds-faz4-icerik: lessons never run out).
final inMaintenanceProvider = Provider<bool>((ref) {
  final plan = ref.watch(progressProvider.select((p) => p.studyPlan));
  final year = ref.watch(yearPlanProvider).value;
  return plan != null && year != null && inMaintenance(plan, year);
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

/// Gold for a finished review session: a little more for more known cards.
/// Paid once a day (wallet key `review:<day>`).
int reviewGold(int known) => min(15, 3 + known ~/ 3);

class _SrsReviewScreenState extends ConsumerState<SrsReviewScreen> {
  /// Fixed when the screen opens, so cards do not move under the learner.
  ReviewQueue? _queue;
  late List<WordCard> _cards;
  final _fresh = <String>{};
  int _pos = 0;
  int _reviewed = 0;

  /// The first grade of each card: what the summary counts.
  final _first = <String, ReviewGrade>{};
  int _gold = 0;

  /// Cards answered "Bilmiyordum" come back once at the end.
  final _again = <String>{};

  void _take(ReviewQueue q) {
    _queue = q;
    _cards = [...q.cards];
    _fresh.addAll(q.fresh.map((c) => c.id));
  }

  String _interval(String id, ReviewGrade g) =>
      intervalLabel(scheduleReview(ref.read(progressProvider).wordBox[id], g).days);

  void _grade(ReviewGrade g) {
    final c = _cards[_pos];
    ref.read(progressProvider.notifier).gradeWord(c.id, g, countNew: true);
    _first.putIfAbsent(c.id, () => g);
    setState(() {
      _reviewed++;
      if (g == ReviewGrade.again && _again.add(c.id)) _cards.add(c);
      _pos++;
    });
    if (_pos >= _cards.length) _payGold();
  }

  void _payGold() {
    if (_first.isEmpty) return;
    final known = _first.values.where((g) => g.known).length;
    final amount = reviewGold(known);
    final today = dayKey(ref.read(clockProvider)());
    final paid = ref.read(goldWalletProvider).earn(amount, GoldReason.other, onceKey: 'review:$today');
    setState(() => _gold = paid ? amount : 0);
    if (paid) SessionFx.celebrate();
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
    final finished = _pos >= _cards.length;
    final progress = _cards.isEmpty ? 1.0 : (_pos / _cards.length).clamp(0.0, 1.0);
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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GlossyProgress(
                      key: const Key('srs-progress'),
                      value: progress,
                      color: Brand.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${min(_pos + 1, _cards.length)} / ${_cards.length}',
                    style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_queue!.reviewDay)
                Container(
                  key: const Key('srs-review-day'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Bugün tekrar günü: yeni kelime azaltıldı'),
                ),
              Expanded(child: finished ? _done() : _deck()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deck() {
    final c = _cards[_pos];
    final entries = entryIndex(ref.watch(ydsVocabProvider).value ?? const []);
    final notes = ref.watch(notesProvider).value;
    final fresh = _fresh.contains(c.id) && !_again.contains(c.id);
    return ReviewDeck(
      key: ValueKey('card-$_pos'),
      card: reviewCardFor(
        c,
        entries: entries,
        notes: notes,
        why: ref.read(progressProvider).mistakeCard(c.id)?.why,
      ),
      behind: _cards.length - _pos - 1,
      color: Brand.primary,
      badge: (label: fresh ? 'YENİ' : 'TEKRAR', color: fresh ? Brand.accent : Brand.primary),
      intervalOf: (g) => _interval(c.id, g),
      onGrade: _grade,
    );
  }

  Widget _done() {
    final mistakes = _queue!.mistakes.length;
    final nothing = _reviewed == 0;
    return SingleChildScrollView(
      key: const Key('srs-done'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          if (nothing)
            EmptyState(
              message: mistakes == 0
                  ? 'Bugünlük kart yok. Derslerde yanlış yaptığın kelime ve kalıplar burada kart olur.'
                  : 'Bugünlük kelime kartı yok; hata defterinde soruların seni bekliyor.',
            )
          else
            ReviewSummary(
              total: _first.length,
              known: _first.values.where((g) => g.known).length,
              gold: _gold,
              color: Brand.primary,
              message: 'Bildiğin kart daha geç, bilmediğin daha erken geri gelecek.',
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
          PressableButton(
            label: 'BİTİR',
            outlined: mistakes > 0,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
