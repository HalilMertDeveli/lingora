import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/progress.dart';
import '../services/billing/premium.dart';
import '../services/growth/analytics_events.dart' show PaywallPlacement;
import '../study/study_state.dart';
import '../study/tr_error_log.dart';
import '../study/weekly_coach.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/premium_offer.dart';
import 'error_analysis_screen.dart' show openFocusDrill;

const _months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// "10–16 Kas" for two `dayKey`s.
String coachRange(String from, String to) {
  final a = DateTime.parse(from), b = DateTime.parse(to);
  return a.month == b.month
      ? '${a.day}–${b.day} ${_months[b.month - 1]}'
      : '${a.day} ${_months[a.month - 1]} – ${b.day} ${_months[b.month - 1]}';
}

/// Haftalık koç mesajı on Öğren and Pratik: shown during the week after a
/// week with enough practice, until closed. Premium sees the top 3 mistakes,
/// what improved and a focus that starts with one tap; free users see the
/// week's numbers and the first mistake, the rest under a Premium card.
/// Çocuk modu gets Pofuduk (through [Mascot]) and no AI.
class WeeklyCoachCard extends ConsumerWidget {
  const WeeklyCoachCard({super.key, this.top = 0, this.bottom = 16});

  /// Space above and under the card, only when it shows.
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider).value;
    if (course == null) return const SizedBox.shrink();
    final titles = {for (final u in course.units) u.id: u.title};
    final log = ref.watch(studyLogProvider).answers;
    final msg = buildWeeklyCoach(
      log: log,
      titles: titles,
      trLog: ref.watch(trErrorLogProvider),
      now: ref.watch(clockProvider)(),
    );
    if (msg == null || ref.watch(weeklyCoachSeenProvider) == msg.weekKey) return const SizedBox.shrink();
    final premium = ref.watch(premiumProvider);
    final p = context.palette;

    void startFocus() => openFocusDrill(
      context,
      course,
      msg.focus!,
      wrongKeys: {
        for (final a in log)
          if (!a.correct) a.key,
      },
      seenUnits: {...log.map((a) => a.unitId).whereType<String>()},
    );

    final details = <Widget>[
      for (final (i, t) in msg.top.indexed)
        if (i > 0) _PatternRow(index: i, pattern: t),
      if (msg.improved != null) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.trending_up_rounded, size: 18, color: p.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                msg.improved!,
                key: const Key('coach-improved'),
                style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.3),
              ),
            ),
          ],
        ),
      ],
      if (msg.focus case final f?) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bu haftanın odağı',
                      style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      f.label,
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w900),
                    ),
                    Text(f.detail, style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (f.drillable) ...[
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('coach-start'),
                  // The theme's buttons are full width; this one sits in a row.
                  style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                  onPressed: premium ? startFocus : null,
                  child: const Text('BAŞLA', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Container(
        key: const Key('weekly-coach'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.primary.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Mascot(mood: Mood.cheer, size: 48, decorative: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Haftalık koç mesajın',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: p.ink),
                      ),
                      Text(
                        '${coachRange(msg.from, msg.to)} · ${msg.answered} soru · ${msg.activeDays} gün',
                        key: const Key('coach-stats'),
                        style: TextStyle(color: p.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('coach-close'),
                  tooltip: 'Kapat',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: p.muted),
                  onPressed: () => ref.read(weeklyCoachSeenProvider.notifier).dismiss(msg.weekKey),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (msg.top.isEmpty)
                    Text(
                      'Bu hafta hata yapmadın, harika! Aynı tempoyla devam.',
                      style: TextStyle(color: p.success, fontWeight: FontWeight.w700),
                    )
                  else ...[
                    Text(
                      'En sık hataların',
                      style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    _PatternRow(index: 0, pattern: msg.top.first),
                  ],
                  if (premium)
                    ...details
                  else if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ExcludeSemantics(
                      child: ClipRRect(
                        key: const Key('coach-locked'),
                        borderRadius: BorderRadius.circular(10),
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: IgnorePointer(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: details),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const PremiumOfferCard(
                      placement: PaywallPlacement.weeklyCoach,
                      dense: true,
                      icon: Icons.event_note_rounded,
                      title: 'Haftanın tam koç mesajı Premium\'da',
                      body: 'En sık 3 hatan, neyin düzeldiği ve tek dokunuşla başlayan odak alıştırması.',
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
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({required this.index, required this.pattern});
  final int index;
  final CoachPattern pattern;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: Key('coach-pattern-$index'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: p.error.withValues(alpha: 0.14),
            child: Text(
              '${index + 1}',
              style: TextStyle(color: p.error, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pattern.label,
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w800),
            ),
          ),
          Text(pattern.detail, style: TextStyle(color: p.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
