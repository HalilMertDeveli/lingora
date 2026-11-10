import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exam_pack_repository.dart';
import '../data/progress.dart';
import '../models/exam.dart';
import '../models/exam_pack.dart';
import '../services/billing/exam_packs.dart';
import '../services/billing/premium.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'exam_screen.dart';
import 'paywall_screen.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

/// Exam home card for a one-time exam pack: full mock exams when unlocked,
/// otherwise what the pack contains, its store price and how to unlock it.
class ExamPackSection extends ConsumerStatefulWidget {
  const ExamPackSection({super.key, required this.exam, required this.pack});
  final Exam exam;
  final ExamPack pack;

  @override
  ConsumerState<ExamPackSection> createState() => _ExamPackSectionState();
}

class _ExamPackSectionState extends ConsumerState<ExamPackSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted || ref.read(examPackUnlockedProvider(widget.pack.examId))) return;
      ref.read(examPackControllerProvider.notifier).loadProducts();
    });
  }

  Future<void> _start(ExamPackContent content, FullMock mock) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${content.title}\n${mock.title}'),
        content: Text(
          '${mock.questions.length} soru, ${mock.minutes} dakika. Süre gerçek sınavdaki gibi işler ve '
          'durdurulamaz; süre bitince deneme kendiliğinden biter. Soruları boş bırakabilir, '
          'önceki sorulara dönebilirsin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Başla')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ExamSessionScreen(
          exam: widget.exam,
          questions: mock.questions,
          mock: true,
          title: mock.title,
          minutes: mock.minutes,
          pack: content,
          fullMock: mock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(examPackControllerProvider.select((s) => s.justPurchased), (_, bought) {
      if (bought == null) return;
      ref.read(examPackControllerProvider.notifier).acknowledge();
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('${bought.title} açıldı. Başarılar! 🎉')));
    });
    final unlocked = ref.watch(examPackUnlockedProvider(widget.pack.examId));
    final content = ref.watch(examPackContentProvider(widget.pack));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Tam denemeler', style: Theme.of(context).textTheme.titleLarge)),
            if (unlocked)
              Icon(Icons.lock_open_rounded, color: Brand.success)
            else
              Icon(Icons.lock_rounded, color: Brand.muted),
          ],
        ),
        SizedBox(height: 4),
        Text(widget.pack.summary, style: TextStyle(color: Brand.muted)),
        SizedBox(height: 10),
        content.when(
          // No spinner: the asset loads in a moment, and an endless animation
          // would keep widget tests from settling.
          loading: () => SizedBox(height: 48),
          error: (e, _) => Text('Deneme paketi yüklenemedi: $e'),
          data: (c) => unlocked ? _mockList(c) : _locked(c),
        ),
      ],
    );
  }

  Widget _mockList(ExamPackContent c) {
    final best = ref.watch(progressProvider.select((p) => p.examBest));
    return Column(
      children: [
        for (final m in c.mocks)
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: TapCard(
              key: ValueKey('full-mock-${m.id}'),
              onTap: () => _start(c, m),
              child: Row(
                children: [
                  Icon(Icons.assignment_rounded, color: Brand.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${m.questions.length} soru · ${m.minutes} dk'
                          '${best[m.id] == null ? '' : ' · en iyi %${best[m.id]}'}',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, color: Brand.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _locked(ExamPackContent c) {
    final s = ref.watch(examPackControllerProvider);
    final ctrl = ref.read(examPackControllerProvider.notifier);
    final product = s.product(widget.pack);
    final pending = s.pending.contains(widget.pack.examId);
    final busy = s.busy == widget.pack;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.card,
        border: Border.all(color: Brand.line, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.pack.title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          SizedBox(height: 6),
          Text(c.description, style: TextStyle(height: 1.35)),
          SizedBox(height: 10),
          for (final line in [
            'Gerçek sınav süresiyle tam deneme',
            'Net ve puan tahmini',
            'Konu konu başarı dökümü',
            'Yanlış ve boşların Türkçe çözümleri',
          ])
            Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.check_rounded, size: 18, color: Brand.success),
                  SizedBox(width: 6),
                  Expanded(child: Text(line, style: TextStyle(fontSize: 13))),
                ],
              ),
            ),
          SizedBox(height: 6),
          Text(
            'Tek seferlik ödeme, abonelik değil. Premium üyelerde paket zaten açıktır. Konu pratiği ve '
            'günlük mini deneme ücretsiz kalır.',
            style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.35),
          ),
          SizedBox(height: 12),
          if (pending)
            _Info('Ödemen onay bekliyor. Onaylanınca paket kendiliğinden açılır.')
          else if (s.storeAvailable == false)
            _Info('Satın alma bu cihazda şu an kullanılamıyor. Paketi aldıysan geri yükleyebilirsin.'),
          if (s.error != null) _Info(s.error!, color: Brand.errorBg),
          if (s.message != null) _Info(s.message!),
          PressableButton(
            key: ValueKey('buy-pack-${widget.pack.examId}'),
            label: busy
                ? 'BEKLENİYOR…'
                : product == null
                ? 'PAKETİ SATIN AL'
                : 'SATIN AL · ${product.price}',
            color: Brand.primary,
            onPressed: product != null && !busy && !pending && s.busy == null
                ? () => ctrl.buy(widget.pack)
                : null,
          ),
          SizedBox(height: 8),
          PressableButton(
            label: 'PREMIUM İLE AÇ',
            outlined: true,
            color: Brand.primary,
            foreground: Brand.primary,
            onPressed: () => requirePremium(context, ref, PremiumFeature.unlimitedMockExams),
          ),
          Center(
            child: TextButton(
              onPressed: s.busy == null ? () => ctrl.restore(widget.pack) : null,
              child: Text('Satın alımları geri yükle'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.only(bottom: 10),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(color: color ?? Brand.accentBg, borderRadius: BorderRadius.circular(14)),
    child: Text(text, style: TextStyle(fontSize: 13)),
  );
}

String _fmtNet(double n) {
  final s = n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  return s.replaceAll('.', ',');
}

/// Result of a full mock exam: score/net, topic breakdown, and review of
/// wrong and blank answers with Turkish explanations.
class FullMockResultScreen extends StatefulWidget {
  const FullMockResultScreen({
    super.key,
    required this.pack,
    required this.mock,
    required this.answers,
    required this.xp,
    required this.duration,
  });

  final ExamPackContent pack;
  final FullMock mock;
  final Map<int, int> answers;
  final int xp;
  final Duration duration;

  @override
  State<FullMockResultScreen> createState() => _FullMockResultScreenState();
}

class _FullMockResultScreenState extends State<FullMockResultScreen> {
  bool _onlyMistakes = true;

  @override
  Widget build(BuildContext context) {
    final qs = widget.mock.questions;
    final r = MockScore.of(qs, widget.answers, widget.pack.scoring);
    final good = r.correct >= qs.length * 0.7;
    final minutes = widget.duration.inMinutes;
    final headline = switch (widget.pack.scoring) {
      ExamScoring.yds => 'Tahmini puan: ${_fmtNet(double.parse(r.score!.toStringAsFixed(2)))}',
      ExamScoring.lgs => 'İngilizce neti: ${_fmtNet(r.net)} / ${qs.length}',
    };
    final note = switch (widget.pack.scoring) {
      ExamScoring.yds =>
        'YDS/YÖKDİL\'de her doğru 1,25 puandır, yanlışlar doğruları götürmez. Tahmin bu denemeye göredir; '
            'gerçek sınavda puan ÖSYM tarafından hesaplanır.',
      ExamScoring.lgs =>
        'LGS\'de 3 yanlış 1 doğruyu götürür. LGS puanı tüm derslerin netleriyle hesaplandığı için yalnızca '
            'İngilizce netini gösteriyoruz.',
    };
    final review = [
      for (var i = 0; i < qs.length; i++)
        if (!_onlyMistakes || widget.answers[i] != qs[i].answer) i,
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(20),
                children: [
                  Center(child: Mascot(mood: good ? Mood.cheer : Mood.think, size: 100)),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      '${widget.pack.title} · ${widget.mock.title}',
                      style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 4),
                  Center(
                    child: Text(
                      headline,
                      key: ValueKey('mock-headline'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: good ? Brand.success : Brand.primary,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${r.correct} doğru · ${r.wrong} yanlış · ${r.blank} boş · net ${_fmtNet(r.net)} · '
                      '$minutes dk · +${widget.xp} XP',
                      style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(note, style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.35)),
                  SizedBox(height: 18),
                  Text('Konu dökümü', style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: 8),
                  for (final e in r.topics.entries)
                    _TopicRow(
                      title: widget.pack.sectionTitle(e.key),
                      correct: e.value.correct,
                      wrong: e.value.wrong,
                      total: e.value.total,
                    ),
                  SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Cevapları incele', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      FilterChip(
                        label: Text('Yalnız yanlış/boş'),
                        selected: _onlyMistakes,
                        onSelected: (v) => setState(() => _onlyMistakes = v),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  if (review.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Hiç yanlışın ya da boşun yok. Harika! 🎉'),
                    ),
                  for (final i in review) _ReviewCard(index: i, q: qs[i], picked: widget.answers[i]),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: PressableButton(label: 'DEVAM', onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.title, required this.correct, required this.wrong, required this.total});
  final String title;
  final int correct;
  final int wrong;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : correct / total;
    final color = ratio >= 0.7 ? Brand.success : (ratio >= 0.4 ? Brand.accent : Brand.error);
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(
                '$correct/$total',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          SizedBox(height: 4),
          GlossyProgress(value: ratio, color: color, height: 10),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.index, required this.q, required this.picked});
  final int index;
  final ExamQuestion q;
  final int? picked;

  @override
  Widget build(BuildContext context) {
    final ok = picked == q.answer;
    final color = picked == null ? Brand.muted : (ok ? Brand.success : Brand.error);
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: TapCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          shape: Border(),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(
              picked == null ? Icons.remove : (ok ? Icons.check : Icons.close),
              color: color,
              size: 18,
            ),
          ),
          title: Text('${index + 1}. ${q.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            picked == null
                ? 'Boş · doğru: ${_letters[q.answer]}'
                : 'Senin: ${_letters[picked!]} · doğru: ${_letters[q.answer]}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (q.passage != null) ...[
              Text(q.passage!, style: TextStyle(color: Brand.muted, height: 1.4, fontSize: 13)),
              SizedBox(height: 8),
            ],
            Text(q.text, style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  '${_letters[i]}) ${q.options[i]}',
                  style: TextStyle(
                    fontWeight: i == q.answer ? FontWeight.w800 : FontWeight.w500,
                    color: i == q.answer ? Brand.success : (i == picked ? Brand.error : Brand.ink),
                  ),
                ),
              ),
            SizedBox(height: 6),
            Text(q.explanation, style: TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
