import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../services/billing/premium.dart';
import '../services/growth/analytics.dart';
import '../study/analysis.dart';
import '../study/error_insights.dart';
import '../study/question_types.dart';
import '../study/study_state.dart';
import '../study/tr_error_log.dart';
import '../study/year_plan.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import 'lesson_screen.dart';
import 'paywall_screen.dart';

/// Detaylı hata analizi. Everyone sees the summary and their most frequent
/// mistake; Premium opens the rest: weak topics and types, the weekly
/// trend, Türk hata kalıpları with the learner's own sentences, the topic ×
/// type heat map, the exam score estimate and a weekly plan whose items
/// each start a targeted drill. Without Premium the rest is drawn from the
/// learner's own data but blurred, under a "Premium ile aç" card.
class ErrorAnalysisScreen extends ConsumerStatefulWidget {
  const ErrorAnalysisScreen({super.key});

  @override
  ConsumerState<ErrorAnalysisScreen> createState() => _ErrorAnalysisScreenState();
}

class _ErrorAnalysisScreenState extends ConsumerState<ErrorAnalysisScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(premiumProvider)) {
        logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.errorAnalysis));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseProvider).value;
    if (course == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detaylı hata analizi')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final premium = ref.watch(premiumProvider);
    final insights = ErrorInsights(
      log: ref.watch(studyLogProvider).answers,
      titles: {for (final u in course.units) u.id: u.title},
      trLog: ref.watch(trErrorLogProvider),
      errorStats: ref.watch(progressProvider.select((p) => p.errorStats)),
      today: dayKey(ref.watch(clockProvider)()),
    );
    final estimate = _estimate(ref, insights);
    final locked = [
      _WeakPoints(insights),
      _Trend(insights),
      _Patterns(insights.patterns),
      _HeatMapCard(insights.heat),
      ?estimate,
      _Plan(insights: insights, course: course, enabled: premium),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Detaylı hata analizi')),
      body: ListView(
        key: const Key('analysis-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!insights.ready)
            _Empty(insights)
          else ...[
            _Summary(insights),
            const SizedBox(height: 12),
            _TopError(insights),
            const SizedBox(height: 20),
            if (premium)
              for (final w in locked) ...[w, const SizedBox(height: 16)]
            else
              _LockedPreview(insights: insights, hasEstimate: estimate != null, children: locked),
          ],
          if (!insights.ready && insights.patterns.isNotEmpty) ...[
            const SizedBox(height: 16),
            premium
                ? _Patterns(insights.patterns)
                : _LockedPreview(
                    insights: insights,
                    hasEstimate: false,
                    children: [_Patterns(insights.patterns)],
                  ),
          ],
        ],
      ),
    );
  }

  /// The score estimate card for a YDS or LGS learner, else null.
  Widget? _estimate(WidgetRef ref, ErrorInsights insights) {
    final track = ref.watch(trackProvider).id;
    final log = ref.watch(studyLogProvider).answers;
    if (track == 'yds') {
      final score = estimateScore(
        log.where(isYdsAnswer).toList(),
        halfMocks: halfMockNodes(ref.watch(yearPlanProvider).value),
        mix: ExamMix.of(ref.watch(progressProvider).studyPlan?.exam),
      );
      return _EstimateCard.yds(score);
    }
    if (track == 'lgs') return _EstimateCard.lgs(estimateLgsNet(log));
    return null;
  }
}

/// Colour for an accuracy: red under 50%, orange under 75%, else green.
Color accuracyColor(BuildContext context, double accuracy) {
  final p = context.palette;
  return accuracy < 0.5
      ? p.error
      : accuracy < 0.75
      ? p.accent
      : p.success;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.emoji,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final String emoji;
  final Widget child;

  @override
  Widget build(BuildContext context) => TapCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(icon: icon, emoji: emoji, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

// ---------------------------------------------------------------- free part

class _Empty extends StatelessWidget {
  const _Empty(this.insights);
  final ErrorInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = insights.lessonsToGo;
    return TapCard(
      key: const Key('analysis-empty'),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Mascot(mood: Mood.think, size: 110),
          const SizedBox(height: 12),
          Text(
            '$n ders daha çöz, analizin açılsın',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Hangi konuda ve hangi soru tipinde zorlandığını, haftadan haftaya neyin düzeldiğini '
            've sana özel bir çalışma planını burada göreceksin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (insights.answered / minAnswersForInsights).clamp(0, 1)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) =>
                  LinearProgressIndicator(value: v, minHeight: 10, color: p.primary, backgroundColor: p.line),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${insights.answered} / $minAnswersForInsights soru',
            style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.insights);
  final ErrorInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final acc = insights.accuracy;
    final delta = insights.week.deltaPoints;
    return TapCard(
      key: const Key('analysis-summary'),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _Ring(value: acc, color: accuracyColor(context, acc), size: 104),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('GENEL DOĞRULUK'),
                const SizedBox(height: 6),
                _Stat(label: 'Çözülen soru', value: '${insights.answered}'),
                _Stat(label: 'Yanlış', value: '${insights.wrong}', color: p.error),
                _Stat(label: 'Bu hafta', value: '${insights.week.thisWeek.answered} soru'),
                if (delta != null) ...[const SizedBox(height: 6), _DeltaChip(delta)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: context.palette.muted, fontSize: 13)),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    ),
  );
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip(this.points);
  final int points;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = points > 0
        ? p.success
        : points < 0
        ? p.error
        : p.muted;
    final text = points == 0
        ? 'Geçen haftayla aynı'
        : '${points > 0 ? '▲' : '▼'} ${points.abs()} puan, geçen haftaya göre';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// A donut showing [value] (0–1), with the percentage in the middle.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.color, this.size = 96});
  final double value;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(v, color, context.palette.line),
        child: Center(
          child: Text(
            '%${(v * 100).round()}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * 0.24),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, 2 * pi, false, base);
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -pi / 2, 2 * pi * value.clamp(0, 1), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

/// Free: the learner's most frequent mistake: their top Türk hata kalıbı
/// with their own sentence, else their weakest topic.
class _TopError extends StatelessWidget {
  const _TopError(this.insights);
  final ErrorInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pattern = insights.patterns.firstOrNull;
    final weak = insights.weakTopics.firstOrNull ?? insights.weakTypes.firstOrNull;
    return Container(
      key: const Key('analysis-top-error'),
      child: _Card(
        title: 'En sık hatan',
        icon: Icons.priority_high_rounded,
        emoji: '🎯',
        child: pattern != null
            ? _PatternBody(pattern, compact: true)
            : weak != null
            ? Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: weak.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text:
                          ': ${weak.answered} sorunun ${weak.wrong} tanesi yanlış (%${weak.percent} doğru).',
                    ),
                  ],
                ),
              )
            : Text('Şimdilik belirgin bir hata kalıbın yok. Böyle devam!', style: TextStyle(color: p.muted)),
      ),
    );
  }
}

/// Without Premium: the Premium cards built from the learner's own data,
/// blurred, under a card that says what is in them and opens the paywall.
class _LockedPreview extends ConsumerWidget {
  const _LockedPreview({required this.insights, required this.hasEstimate, required this.children});
  final ErrorInsights insights;
  final bool hasEstimate;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final found = [
      if (insights.weakTopics.isNotEmpty || insights.weakTypes.isNotEmpty)
        '${insights.weakTopics.length + insights.weakTypes.length} zayıf nokta',
      if (insights.trends.isNotEmpty) '${insights.trends.length} düzelen hata',
      if (insights.patterns.isNotEmpty) '${insights.patterns.length} Türk hata kalıbı',
      if (!insights.heat.isEmpty) '${insights.heat.rows.length}×${insights.heat.cols.length} ısı haritası',
      if (hasEstimate) 'tahmini sınav puanı',
      if (insights.focus.isNotEmpty) '${insights.focus.length} maddelik çalışma planı',
    ];
    return Column(
      key: const Key('analysis-locked'),
      children: [
        TapCard(
          color: p.primary,
          selected: true,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              IconBadge(icon: Icons.lock_rounded, emoji: '🔒', size: 44, color: p.primary),
              const SizedBox(height: 10),
              const Text(
                'Analizinin geri kalanı hazır',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                found.isEmpty
                    ? 'Zayıf konuların, haftalık gidişatın ve sana özel çalışma planın.'
                    : 'Senin verilerinden çıkardık: ${found.join(', ')}.',
                key: const Key('analysis-teaser'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, height: 1.35),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('analysis-unlock'),
                  onPressed: () => requirePremium(context, ref, PremiumFeature.errorAnalytics),
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Premium ile aç'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ExcludeSemantics(
          child: IgnorePointer(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.75, 1],
              ).createShader(r),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Column(
                  children: [
                    for (final w in children) ...[w, const SizedBox(height: 16)],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- premium part

class _WeakPoints extends StatelessWidget {
  const _WeakPoints(this.insights);
  final ErrorInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget group(String label, List<Bucket> list, String empty) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Text(empty, style: TextStyle(color: p.muted, fontSize: 13))
        else
          for (final b in list) _Bar(bucket: b),
      ],
    );
    return Container(
      key: const Key('analysis-weak'),
      child: _Card(
        title: 'Zayıf noktaların',
        subtitle: 'En az $minAnswersForWeak soru çözdüğün konu ve tipler, en düşük doğruluk önce.',
        icon: Icons.trending_down_rounded,
        emoji: '🧩',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group('GRAMER KONULARI', insights.weakTopics, 'Konu bazında zayıf nokta yok.'),
            const SizedBox(height: 14),
            group('SORU TİPLERİ', insights.weakTypes, 'Soru tipi bazında zayıf nokta yok.'),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.bucket});
  final Bucket bucket;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = accuracyColor(context, bucket.accuracy);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bucket.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '%${bucket.percent}',
                style: TextStyle(fontWeight: FontWeight.w900, color: c),
              ),
              Text('  ${bucket.correct}/${bucket.answered}', style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: bucket.accuracy),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) =>
                  LinearProgressIndicator(value: v, minHeight: 9, color: c, backgroundColor: p.line),
            ),
          ),
        ],
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend(this.insights);
  final ErrorInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = insights.week;
    return Container(
      key: const Key('analysis-trend'),
      child: _Card(
        title: 'Gidişat',
        subtitle: 'Son 14 günün günlük doğruluğu ve bu hafta / geçen hafta.',
        icon: Icons.show_chart_rounded,
        emoji: '📈',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 92, child: _DailyBars(insights.daily)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _WeekBox(label: 'Geçen hafta', bucket: w.lastWeek),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WeekBox(label: 'Bu hafta', bucket: w.thisWeek, highlight: true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionLabel('ZAMANLA DÜZELENLER'),
            const SizedBox(height: 8),
            if (insights.trends.isEmpty)
              Text(
                'Henüz belirgin bir düzelme yok. İki hafta düzenli çalışınca hangi hatanın azaldığını '
                'burada göreceksin.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
              )
            else
              for (final t in insights.trends)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.south_east_rounded, color: p.success, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${t.label} ',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              TextSpan(text: 'hatan %${t.dropPercent} azaldı'),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        t.trCategory != null
                            ? '${(t.before * 100).round()} → ${(t.after * 100).round()} / 100 metin'
                            : '%${(t.before * 100).round()} → %${(t.after * 100).round()} yanlış',
                        style: TextStyle(color: p.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars(this.days);
  final List<Bucket?> days;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final most = days.fold<int>(1, (m, b) => max(m, b?.answered ?? 0));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, b) in days.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: b == null ? 'Çalışma yok' : '%${b.percent} doğru · ${b.answered} soru',
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: b == null ? 0 : 0.25 + 0.75 * b.answered / most),
                      duration: Duration(milliseconds: 500 + 30 * i),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => Container(
                        height: b == null ? 4 : 70 * v,
                        decoration: BoxDecoration(
                          color: b == null ? p.line : accuracyColor(context, b.accuracy),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    i == days.length - 1 ? 'Bugün' : (i % 3 == 1 ? '${days.length - 1 - i}g' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: TextStyle(color: p.muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekBox extends StatelessWidget {
  const _WeekBox({required this.label, required this.bucket, this.highlight = false});
  final String label;
  final Bucket bucket;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = highlight ? p.primary : p.muted;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? p.primary.withValues(alpha: 0.5) : p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            bucket.answered == 0 ? '—' : '%${bucket.percent}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: highlight ? p.primary : null),
          ),
          Text(
            bucket.answered == 0 ? 'çalışma yok' : '${bucket.answered} soru · ${bucket.wrong} yanlış',
            style: TextStyle(color: p.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Patterns extends StatefulWidget {
  const _Patterns(this.patterns);
  final List<TrPattern> patterns;

  @override
  State<_Patterns> createState() => _PatternsState();
}

class _PatternsState extends State<_Patterns> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = _all ? widget.patterns : widget.patterns.take(3).toList();
    return Container(
      key: const Key('analysis-patterns'),
      child: _Card(
        title: 'Türk hata kalıpların',
        subtitle: 'Yazdıklarında Türk hata dedektörünün yakaladıkları.',
        icon: Icons.translate_rounded,
        emoji: '🇹🇷',
        child: widget.patterns.isEmpty
            ? Text(
                'Henüz yakalanmış bir kalıp yok. Çeviri, günlük ve sohbette yazdıkça burada '
                'kendi cümlelerinle görünecek.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, pt) in shown.indexed) ...[
                    if (i > 0) Divider(height: 24, color: p.line),
                    _PatternBody(pt),
                  ],
                  if (widget.patterns.length > 3)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _all = !_all),
                        child: Text(_all ? 'Daha az göster' : 'Tüm kalıplar (${widget.patterns.length})'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One Türk hata kalıbı: the learner's sentence with the wrong part
/// marked, the fix, the short rule and why Turkish speakers do it.
class _PatternBody extends StatelessWidget {
  const _PatternBody(this.pattern, {this.compact = false});
  final TrPattern pattern;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (rule, habit) = trRuleAndHabit[pattern.category]!;
    final ex = pattern.example;
    Widget line(String tag, Widget body, Color c) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              tag,
              style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                pattern.category.label,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: p.isDark ? 0.22 : 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${pattern.count} kez',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),
        if (ex == null)
          line(
            'Örnek',
            Text(
              'Bir sonraki bu tür hatanda kendi cümlen burada görünecek.',
              style: TextStyle(color: p.muted, fontStyle: FontStyle.italic, fontSize: 13),
            ),
            p.muted,
          )
        else ...[
          line('Sen', _marked(context, ex.text ?? ex.wrong, ex.wrong), p.error),
          line(
            'Doğrusu',
            Text(
              ex.corrected,
              style: TextStyle(color: p.success, fontWeight: FontWeight.w700),
            ),
            p.success,
          ),
        ],
        line('Kural', Text(rule, style: const TextStyle(fontSize: 13.5, height: 1.3)), p.primary),
        if (!compact)
          line('Neden?', Text(habit, style: TextStyle(fontSize: 13, height: 1.35, color: p.muted)), p.accent),
      ],
    );
  }

  /// [text] with [part] struck through in red.
  Widget _marked(BuildContext context, String text, String part) {
    final p = context.palette;
    final i = part.isEmpty ? -1 : text.toLowerCase().indexOf(part.toLowerCase());
    final bad = TextStyle(
      color: p.error,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.lineThrough,
      decorationColor: p.error,
    );
    if (i < 0) return Text(text, style: bad);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(text: text.substring(i, i + part.length), style: bad),
          TextSpan(text: text.substring(i + part.length)),
        ],
      ),
    );
  }
}

class _HeatMapCard extends StatelessWidget {
  const _HeatMapCard(this.heat);
  final HeatMap heat;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('analysis-heatmap'),
      child: _Card(
        title: 'Isı haritası',
        subtitle: 'Konu × soru tipi doğruluğu. %50 altı kareler en çok puan kaybettiğin yerler; soluk kare az soru demek.',
        icon: Icons.grid_view_rounded,
        emoji: '🗺️',
        child: heat.isEmpty
            ? Text('Isı haritası için birkaç farklı konudan soru çöz.', style: TextStyle(color: p.muted))
            : Column(
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      const labelW = 104.0;
                      final cellW = ((c.maxWidth - labelW) / heat.cols.length).clamp(44.0, 90.0);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: labelW),
                                for (final col in heat.cols)
                                  SizedBox(
                                    width: cellW,
                                    child: Text(
                                      col.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.muted,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final row in heat.rows)
                              Row(
                                children: [
                                  SizedBox(
                                    width: labelW,
                                    child: Text(
                                      row.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  for (final col in heat.cols)
                                    _HeatCell(bucket: heat.cell(row.key, col.key), width: cellW),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (label, acc) in const [('<%50', 0.3), ('%50–74', 0.6), ('%75+', 0.9)]) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: accuracyColor(context, acc),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.bucket, required this.width});
  final Bucket? bucket;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = bucket;
    final c = b == null ? p.line : accuracyColor(context, b.accuracy);
    // Fewer answers: a paler square (less sure).
    final strength = b == null ? 0.35 : (0.35 + 0.65 * min(1, b.answered / 10)).toDouble();
    return Tooltip(
      message: b == null ? 'Soru yok' : '%${b.percent} doğru · ${b.answered} soru',
      child: Container(
        width: width - 4,
        height: 38,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.withValues(alpha: strength), p.card),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          b == null ? '' : '%${b.percent}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: onColor(Color.alphaBlend(c.withValues(alpha: strength), p.card)),
          ),
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard._({
    required this.exam,
    required this.low,
    required this.high,
    required this.scale,
    required this.unit,
    required this.method,
    this.basis = 0,
  });

  factory _EstimateCard.yds(ScoreRange? s) => _EstimateCard._(
    exam: 'YDS',
    low: s?.low,
    high: s?.high,
    scale: 100,
    unit: 'puan',
    basis: s?.basis ?? 0,
    method: s == null
        ? 'Tahmin için en az $minAnswersForEstimate YDS sorusu çözmelisin.'
        : !s.fromMocks
        ? 'Alıştırmalarındaki her soru tipinin doğruluğu, tipin sınavdaki soru sayısıyla tartıldı '
              '(${s.basis} soru). İlk tam denemeden sonra netleşir.'
        : s.halfMocksOnly
        ? 'Yarım denemelerine göre (${s.basis} soru). Yarım deneme gerçeğinden kolay, aralık bu yüzden geniş.'
        : 'Son en fazla 3 tam denemenin ağırlıklı ortalaması (${s.basis} soru), yenisi daha ağır basar.',
  );

  factory _EstimateCard.lgs(NetRange? n) => _EstimateCard._(
    exam: 'LGS İngilizce',
    low: n?.low,
    high: n?.high,
    scale: lgsQuestions,
    unit: 'net',
    basis: n?.basis ?? 0,
    method: n == null
        ? 'Tahmin için en az $minAnswersForLgs LGS sorusu çözmelisin.'
        : 'Son ${n.basis} LGS sorusundaki doğruluğun; LGS kuralıyla 3 yanlış 1 doğruyu götürür, '
              'boş bırakılan soru olmadığı varsayıldı. Aralık, soru sayına göre %95 güven payı.',
  );

  final String exam;
  final int? low;
  final int? high;
  final int scale;
  final String unit;
  final String method;
  final int basis;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lo = low, hi = high;
    return Container(
      key: const Key('analysis-estimate'),
      child: _Card(
        title: 'Tahmini $exam ${unit == 'net' ? 'neti' : 'puanı'}',
        subtitle: 'Tahminidir, ± payıyla. Gerçek sonucu sınavın kendisi belirler.',
        icon: Icons.speed_rounded,
        emoji: '🎓',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lo != null && hi != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    lo == hi ? '$lo' : '$lo–$hi',
                    key: const Key('estimate-range'),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, color: p.primary),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '$unit / $scale  ·  ±${((hi - lo) / 2).toStringAsFixed((hi - lo).isEven ? 0 : 1)}',
                        style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return SizedBox(
                    height: 18,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          top: 6,
                          bottom: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        Positioned(
                          left: w * lo / scale,
                          width: max(8, w * (hi - lo) / scale),
                          top: 2,
                          bottom: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.6), p.primary]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: TextStyle(color: p.muted, fontSize: 11)),
                  Text('$scale', style: TextStyle(color: p.muted, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text('Nasıl hesaplandı? $method', style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

class _Plan extends ConsumerWidget {
  const _Plan({required this.insights, required this.course, required this.enabled});
  final ErrorInsights insights;
  final Course course;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final items = insights.focus;
    return Container(
      key: const Key('analysis-plan'),
      child: _Card(
        title: 'Bu hafta şunlara odaklan',
        subtitle: 'Zayıf noktalarına göre hazırlandı. Her biri tek dokunuşla 5–10 soruluk alıştırma.',
        icon: Icons.flag_rounded,
        emoji: '🗓️',
        child: items.isEmpty
            ? Text(
                'Şu an odaklanman gereken belirgin bir zayıf nokta yok. Harika!',
                style: TextStyle(color: p.muted),
              )
            : Column(
                children: [
                  for (final (i, f) in items.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(f.detail, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.3)),
                              ],
                            ),
                          ),
                          if (f.drillable) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              key: Key('focus-drill-$i'),
                              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                              onPressed: enabled ? () => _drill(context, f) : null,
                              child: const Text('Başla'),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _drill(BuildContext context, FocusItem f) {
    final items = drillItems(
      course,
      unitId: f.unitId,
      typeKey: f.typeKey,
      wrongKeys: insights.wrongKeys,
      seenUnits: insights.seenUnits,
    );
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${f.label}: bu kursta yeterli soru bulunamadı.')));
      return;
    }
    final color = course.units.where((u) => u.id == f.unitId).firstOrNull?.color ?? Brand.error;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LessonScreen(
          nodeId: 'targeted_review',
          title: '${f.label} alıştırması',
          items: items,
          color: Brand.tone(color),
          mode: LessonMode.practice,
          logSource: 'targeted',
        ),
      ),
    );
  }
}
