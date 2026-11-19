import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/placement.dart' show Cefr;
import '../data/level_report.dart';
import '../data/notes_repository.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../services/billing/premium.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/level_certificate.dart';
import '../ui/share_card.dart';
import '../ui/mascot.dart';
import 'grammar_path_screen.dart' show GrammarLessonScreen, grammarLessonsProvider, levelColor, lessonNodeId;
import 'level_test_screen.dart';
import 'listening_screen.dart';
import 'paywall_screen.dart';
import 'reading_screen.dart';
import 'study/srs_review_screen.dart';

/// Listening nodes of the general course (for study suggestions). Tests
/// override it.
final karneListeningNodesProvider = FutureProvider<List<PathNode>>((ref) async {
  final course = await loadCourse(rootBundle, defaultTrackId);
  return [
    for (final s in course.sections)
      for (final n in s.nodes)
        if (n.listening != null) n,
  ];
});

/// Seviye Karnesi: the latest monthly result (free) and, with Premium, the
/// month-by-month chart, skill trends and next month's suggestions.
class LevelReportScreen extends ConsumerWidget {
  const LevelReportScreen({super.key, this.justFinished = false});

  /// Opened right after a test: says so on top.
  final bool justFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = sortedReports(ref.watch(progressProvider.select((p) => p.levelReports)));
    final now = ref.watch(clockProvider)();
    final premium = ref.watch(premiumProvider);
    final latest = reports.lastOrNull;
    final previous = reports.length > 1 ? reports[reports.length - 2] : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Seviye Karnesi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (latest == null)
            const _Empty()
          else ...[
            if (justFinished)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Mascot(mood: Mood.cheer, size: 56, decorative: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Test bitti! İşte bu ayın karnesi.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            _CurrentCard(report: latest),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('karne-certificate'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CertificateScreen(
                    name: ref.read(myDisplayNameProvider),
                    report: latest,
                    kid: Brand.isKid,
                  ),
                ),
              ),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Sertifikayı gör ve paylaş'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('karne-share-card'),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShareCardScreen())),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(latest == null ? 'Serini paylaş' : 'Paylaşım kartı oluştur'),
          ),
          const SizedBox(height: 12),
          _NextTest(reports: reports, now: now),
          if (latest != null) ...[
            const SizedBox(height: 24),
            if (premium) ...[
              const SectionLabel('AY AY SEVİYEN'),
              const SizedBox(height: 8),
              TapCard(child: LevelHistoryChart(reports: reports)),
              const SizedBox(height: 20),
              const SectionLabel('GEÇEN AYDAN BU YANA'),
              const SizedBox(height: 8),
              _Trends(current: latest, previous: previous),
              const SizedBox(height: 20),
              const SectionLabel('GELECEK AY İÇİN ÖNERİLER'),
              const SizedBox(height: 8),
              _Suggestions(report: latest),
            ] else
              const _Locked(),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        const Mascot(mood: Mood.think, size: 90, decorative: true),
        const SizedBox(height: 12),
        Text('Henüz karnen yok', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Ayda bir, 15 dakikalık testle dil bilgisi, kelime, okuma ve dinlemeni ölç. '
          'Tahmini CEFR seviyeni ve paylaşılabilir sertifikanı al.',
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: Brand.muted),
        ),
      ],
    );
  }
}

/// The latest result: estimated level, skills measured, raw counts.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.report});
  final LevelReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final level = report.overall;
    final measured = [
      for (final s in LevelSkill.values)
        if (report.skills.containsKey(s)) s,
    ];
    final missing = [
      for (final s in LevelSkill.values)
        if (!report.skills.containsKey(s)) s,
    ];
    return TapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                key: const Key('karne-level'),
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: level == null ? Brand.line : levelColor(level.code),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  level?.code ?? 'A1↓',
                  style: TextStyle(
                    color: level == null ? Brand.ink : onColor(levelColor(level.code)),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TAHMİNİ SEVİYE',
                      style: t.labelMedium?.copyWith(color: Brand.muted, letterSpacing: 1),
                    ),
                    Text(level == null ? 'A1 öncesi' : '${level.code} · ${level.name}', style: t.titleLarge),
                    Text(longDateTr(report.date), style: TextStyle(color: Brand.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final s in measured) _SkillRow(skill: s, score: report.skills[s]!),
          const SizedBox(height: 6),
          Text(
            'Ölçülen beceriler: ${measured.map((s) => s.title).join(', ')}. '
            '${missing.isEmpty ? '' : '${missing.map((s) => s.title).join(', ')} bu ay ölçülmedi. '}'
            '${report.total} sorudan ${report.right} doğru.',
            style: t.bodySmall?.copyWith(color: Brand.muted),
          ),
          const SizedBox(height: 4),
          Text(
            'Bu, beceri başına $levelTestPerSkill soruluk kısa bir uyarlamalı testten çıkan bir tahmindir; '
            'resmî bir CEFR belgesi değildir. Genel seviye, ölçülen becerilerin ortancasıdır.',
            style: t.bodySmall?.copyWith(color: Brand.muted),
          ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.score});
  final LevelSkill skill;
  final SkillScore score;

  @override
  Widget build(BuildContext context) {
    final rank = levelRank(score.level);
    final color = score.level == null ? Brand.muted : levelColor(score.level!.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text(skill.emoji, style: const TextStyle(fontSize: 18))),
          SizedBox(
            width: 86,
            child: Text(skill.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Row(
              children: [
                for (var i = 1; i <= Cefr.values.length; i++)
                  Expanded(
                    child: Container(
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: i <= rank ? color : Brand.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              '${levelLabel(score.level)} · ${score.right}/${score.total}',
              textAlign: TextAlign.right,
              style: TextStyle(color: Brand.ink, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextTest extends StatelessWidget {
  const _NextTest({required this.reports, required this.now});
  final List<LevelReport> reports;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (canTakeLevelTest(reports, now)) {
      return OutlinedButton.icon(
        key: const Key('karne-start-test'),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const LevelTestIntroScreen())),
        icon: const Icon(Icons.speed_rounded),
        label: Text(reports.isEmpty ? 'Aylık testi başlat (≈15 dk)' : 'Bu ayın testini çöz (≈15 dk)'),
      );
    }
    final days = daysUntilLevelTest(reports, now);
    return Container(
      key: const Key('karne-next-test'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.event_rounded, color: Brand.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sonraki test ${longDateTr(nextLevelTestDay(reports)!)} tarihinde açılır ($days gün sonra). '
              'Test ayda bir kez çözülür.',
              style: TextStyle(color: Brand.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Teaser of the Premium part for free users.
class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return TapCard(
      key: const Key('karne-locked'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: Brand.primary),
              const SizedBox(width: 8),
              Text('Premium karne', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in const [
            '📈 Ay ay seviye grafiğin',
            '↗️ Geçen aydan bu yana beceri gidişatın',
            '🎯 Gelecek ay için derslerden çalışma önerileri',
          ])
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const PaywallScreen(feature: PremiumFeature.levelReport),
              ),
            ),
            child: const Text("Premium'u incele"),
          ),
        ],
      ),
    );
  }
}

/// Overall and per-skill level per month, one dot per report.
class LevelHistoryChart extends StatelessWidget {
  const LevelHistoryChart({super.key, required this.reports});
  final List<LevelReport> reports;

  /// At most this many months are drawn (the latest ones).
  static const months = 12;

  @override
  Widget build(BuildContext context) {
    final shown = reports.length <= months ? reports : reports.sublist(reports.length - months);
    if (shown.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'İlk karnen hazır. Grafik ikinci aydan itibaren çizilir; gelecek ayki testten sonra gidişatını burada göreceksin.',
          style: TextStyle(color: Brand.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const Key('karne-chart'),
          height: 180,
          child: CustomPaint(
            size: Size.infinite,
            painter: _HistoryPainter(
              reports: shown,
              line: Brand.line,
              ink: Brand.muted,
              overall: Brand.primary,
              skillColors: _skillColors,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legend('Genel', Brand.primary, thick: true),
            for (final s in LevelSkill.values) _legend(s.title, _skillColors[s]!),
          ],
        ),
      ],
    );
  }

  static Map<LevelSkill, Color> get _skillColors => {
    LevelSkill.grammar: Brand.tone(const Color(0xFF3D8BFD)),
    LevelSkill.vocabulary: Brand.tone(const Color(0xFF22A06B)),
    LevelSkill.reading: Brand.tone(const Color(0xFFF08C00)),
    LevelSkill.listening: Brand.tone(const Color(0xFFD6336C)),
  };

  Widget _legend(String label, Color c, {bool thick = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: thick ? 4 : 2, color: c),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: Brand.muted)),
    ],
  );
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.reports,
    required this.line,
    required this.ink,
    required this.overall,
    required this.skillColors,
  });

  final List<LevelReport> reports;
  final Color line;
  final Color ink;
  final Color overall;
  final Map<LevelSkill, Color> skillColors;

  static const _labels = ['<A1', 'A1', 'A2', 'B1', 'B2', 'C1'];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 32.0, bottom = 20.0, top = 8.0, right = 8.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double y(int rank) => top + h - h * rank / (_labels.length - 1);
    double x(int i) => left + (reports.length == 1 ? w / 2 : w * i / (reports.length - 1));

    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var r = 0; r < _labels.length; r++) {
      canvas.drawLine(Offset(left, y(r)), Offset(size.width - right, y(r)), grid);
      _text(canvas, _labels[r], Offset(0, y(r) - 7), 11);
    }
    for (var i = 0; i < reports.length; i++) {
      final d = reports[i].date;
      _text(canvas, monthNamesTr[d.month - 1], Offset(x(i) - 10, size.height - 14), 10);
    }

    void series(int? Function(LevelReport r) rankOf, Color c, double width) {
      final paint = Paint()
        ..color = c
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      Offset? prev;
      for (var i = 0; i < reports.length; i++) {
        final rank = rankOf(reports[i]);
        if (rank == null) {
          prev = null;
          continue;
        }
        final p = Offset(x(i), y(rank));
        if (prev != null) canvas.drawLine(prev, p, paint);
        canvas.drawCircle(p, width + 1, Paint()..color = c);
        prev = p;
      }
    }

    for (final e in skillColors.entries) {
      series(
        (r) => r.skills[e.key] == null ? null : levelRank(r.skills[e.key]!.level),
        e.value.withValues(alpha: 0.7),
        1.5,
      );
    }
    series((r) => levelRank(r.overall), overall, 3);
  }

  void _text(Canvas canvas, String s, Offset at, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: ink, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => old.reports != reports || old.overall != overall;
}

/// Per-skill change since last month's report.
class _Trends extends StatelessWidget {
  const _Trends({required this.current, required this.previous});
  final LevelReport current;
  final LevelReport? previous;

  @override
  Widget build(BuildContext context) {
    final prev = previous;
    if (prev == null) {
      return Text(
        'Karşılaştırma gelecek ayki testten sonra burada görünür.',
        style: TextStyle(color: Brand.muted),
      );
    }
    final overallDelta = levelRank(current.overall) - levelRank(prev.overall);
    return TapCard(
      key: const Key('karne-trends'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${longDateTr(prev.date)} → ${longDateTr(current.date)}',
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _row('⭐', 'Genel', levelLabel(prev.overall), levelLabel(current.overall), overallDelta),
          for (final s in LevelSkill.values)
            if (current.skills[s] case final now?)
              prev.skills[s] == null
                  ? _row(s.emoji, s.title, 'ölçülmedi', levelLabel(now.level), null)
                  : _row(
                      s.emoji,
                      s.title,
                      levelLabel(prev.skills[s]!.level),
                      levelLabel(now.level),
                      skillChange(current, prev, s),
                    ),
        ],
      ),
    );
  }

  Widget _row(String emoji, String title, String before, String after, int? delta) {
    final (icon, color, word) = switch (delta) {
      null => (Icons.remove_rounded, Brand.muted, ''),
      > 0 => (Icons.trending_up_rounded, Brand.success, '+$delta seviye'),
      < 0 => (Icons.trending_down_rounded, Brand.error, '$delta seviye'),
      _ => (Icons.trending_flat_rounded, Brand.muted, 'aynı'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text(emoji, style: const TextStyle(fontSize: 18))),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('$before → $after', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Icon(icon, color: color, size: 20),
          SizedBox(
            width: 70,
            child: Text(
              word,
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Next month: the two weakest measured skills, each linked to existing
/// lessons at the level to aim at.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.report});
  final LevelReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final suggestions = studySuggestions(report);
    final lessons = ref.watch(grammarLessonsProvider).value ?? const [];
    final notes = ref.watch(notesProvider).value;
    final listening = ref.watch(karneListeningNodesProvider).value ?? const [];
    void push(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));

    final tiles = <Widget>[];
    for (final sg in suggestions) {
      final why = '${sg.skill.title} en zayıf becerilerinden; hedef ${sg.target.code}.';
      switch (sg.skill) {
        case LevelSkill.grammar:
          final picks = lessons.where((l) => l.level == sg.target.code && !p.isDone(lessonNodeId(l))).take(2);
          for (final l in picks) {
            tiles.add(
              _tile(
                '${l.emoji} ${l.title}',
                'Gramer Yolu · ${l.level}. $why',
                notes == null ? null : () => push(GrammarLessonScreen(lesson: l, notes: notes)),
              ),
            );
          }
        case LevelSkill.listening:
          final picks = listening.where((n) => n.cefr == sg.target.code && !p.isDone(n.id)).take(2);
          for (final n in picks) {
            tiles.add(
              _tile(
                '🎧 ${n.title}',
                'Dinleme · ${n.cefr}. $why',
                () => push(ListeningScreen(node: n, color: Brand.primary)),
              ),
            );
          }
        case LevelSkill.reading:
          tiles.add(
            _tile(
              '📖 Okuma hikâyeleri',
              'Seviyene uygun kısa hikâyeler. $why',
              () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const ReadingLibraryScreen())),
            ),
          );
        case LevelSkill.vocabulary:
          tiles.add(
            _tile('🔤 Tekrar kartları', 'Her gün kelime tekrarı. $why', () => openReviewCards(context)),
          );
      }
    }
    if (tiles.isEmpty) {
      return Text('Harika gidiyorsun; bu ay için özel bir öneri yok.', style: TextStyle(color: Brand.muted));
    }
    return Column(key: const Key('karne-suggestions'), children: tiles);
  }

  Widget _tile(String title, String subtitle, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TapCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    ),
  );
}

/// Small card for the profile: latest level and a way into the karne.
class LevelReportProfileCard extends ConsumerWidget {
  const LevelReportProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = sortedReports(ref.watch(progressProvider.select((p) => p.levelReports)));
    final latest = reports.lastOrNull;
    return TapCard(
      key: const Key('profile-karne'),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LevelReportScreen())),
      child: Row(
        children: [
          IconBadge(icon: Icons.insights_rounded, emoji: '📈', color: Brand.tone(Brand.primary), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seviye Karnesi', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  latest == null
                      ? 'Aylık testle seviyeni ölç, sertifikanı paylaş'
                      : 'Tahmini seviye ${levelLabel(latest.overall)} · ${longDateTr(latest.date)}',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    );
  }
}
