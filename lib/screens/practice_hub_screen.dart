import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../nav/tab_navigator.dart';
import '../nav/top_bar.dart';
import '../services/billing/premium.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import 'conversation_screen.dart';
import 'error_analysis_screen.dart';
import 'exam_screen.dart';
import 'lesson_screen.dart';
import 'notes_screen.dart';
import 'paywall_screen.dart';
import 'placement_screen.dart';
import 'pronunciation_screen.dart';
import 'reading_screen.dart';
import 'speed_match_screen.dart';
import 'study/srs_review_screen.dart';
import 'study/today_screen.dart';
import '../study/review_queue.dart';

/// "Pratik" tab: every practice tool in one place, whatever track is open.
///
/// Tools that are a page of their own (Konuşma, Okuma, Telaffuz…) open inside
/// the tab with a back arrow; drills (Hatalarını çalış, Hızlı eşleştirme,
/// Seviye testi) open full screen.
class PracticeHubScreen extends ConsumerWidget {
  const PracticeHubScreen({super.key});

  /// A page inside the Pratik tab with its own title and back arrow.
  static void openPage(BuildContext context, String title, Widget body) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final track = ref.watch(trackProvider);
    final course = ref.watch(courseProvider).value;
    final premium = ref.watch(premiumProvider);
    final today = dayKey(ref.watch(clockProvider)());
    // The error notebook: questions come back after 1, 3, 7 and 21 days.
    // They resolve in the open course (an exam path keeps its own).
    final mistakeQueue = course == null ? const <LessonItem>[] : mistakeItems(course, p.mistakesDue(today));
    final mistakes = mistakeQueue.length;
    // A study plan sets the day's new words (the week's new words / 6).
    final plan = ref.watch(todayPlanProvider);
    final newPerDay = plan == null ? defaultNewWordsPerDay : newWordsPerDay(plan.week, plan.year);
    final cards = ref.watch(reviewQueueProvider(newPerDay));
    final cardCount = cards == null ? 0 : cards.cards.length;

    void fullScreen(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));

    return ScrollToTopOnReselect(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Pratik', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Konuş, oku, tekrar et. Hiçbiri can ya da ceza harcamaz.',
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 16),
          // The YDS daily plan; other tracks see it once a plan exists.
          if (track.id == 'yds' || p.studyPlan != null) ...[const TodayCard(), const SizedBox(height: 16)],
          const SectionLabel('KONUŞ VE DİNLE'),
          const SizedBox(height: 8),
          _HubTile(
            key: const Key('hub-conversation'),
            icon: Icons.forum_rounded,
            emoji: '💬',
            color: Brand.primary,
            image: 'assets/brand/video.png',
            title: 'Konuşma',
            subtitle: 'Gerçek sahnelerde sohbet et, hataların Türkçe açıklansın',
            onTap: () => openPage(context, 'Konuşma', const ConversationHomeScreen()),
          ),
          _HubTile(
            key: const Key('hub-pronunciation'),
            icon: Icons.record_voice_over_outlined,
            emoji: '👄',
            color: Brand.streak,
            title: 'Telaffuz koçu',
            subtitle: 'th, w/v, ship/sheep: zor sesleri dinle ve söyle',
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const PronunciationScreen())),
          ),
          const SizedBox(height: 8),
          const SectionLabel('TEKRAR'),
          const SizedBox(height: 8),
          _HubTile(
            key: const Key('hub-cards'),
            icon: Icons.style_rounded,
            emoji: '🔁',
            color: Brand.success,
            title: 'Tekrar kartları',
            subtitle: cardCount == 0
                ? 'Kelime dersi bitirdikçe kartların gelir'
                : 'Bugün $cardCount kart: aralıklı tekrar',
            badge: cardCount > 0 ? '$cardCount' : null,
            onTap: () => openReviewCards(context, newPerDay: newPerDay),
          ),
          _HubTile(
            key: const Key('hub-mistakes'),
            icon: Icons.fitness_center_rounded,
            emoji: '💪',
            color: Brand.primary,
            title: 'Hatalarını çalış',
            subtitle: mistakes > 0
                ? '$mistakes soru bugün tekrar zamanında'
                : p.mistakes.isEmpty
                ? 'Şu an çalışılacak hata yok'
                : 'Hata defterinde ${p.mistakes.length} soru, sırası gelince döner',
            badge: mistakes > 0 ? '$mistakes' : null,
            onTap: mistakeQueue.isEmpty
                ? null
                : () => fullScreen(
                    LessonScreen(
                      nodeId: 'practice',
                      title: 'Hatalarını çalış',
                      items: mistakeQueue,
                      color: Brand.primary,
                      mode: LessonMode.practice,
                    ),
                  ),
          ),
          _HubTile(
            key: const Key('hub-speed'),
            icon: Icons.timer_rounded,
            emoji: '⏱️',
            color: Brand.accent,
            title: 'Hızlı eşleştirme',
            subtitle: '$speedMatchSeconds saniyede kelime eşleştir',
            onTap: course == null ? null : () => fullScreen(SpeedMatchScreen(pool: _pool(course, p))),
          ),
          _HubTile(
            key: const Key('hub-errors'),
            icon: premium ? Icons.insights_rounded : Icons.lock_rounded,
            emoji: '🔎',
            color: Brand.error,
            title: 'Hata analizi',
            subtitle: 'Türklerin sık yaptığı hatalardan hangileri sende var',
            onTap: () async {
              final gate = await requirePremium(context, ref, PremiumFeature.errorAnalytics);
              if (gate == GateResult.premium && context.mounted) {
                logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.errorAnalysis));
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const ErrorAnalysisScreen()));
              }
            },
          ),
          const SizedBox(height: 8),
          const SectionLabel('OKU VE YAZ'),
          const SizedBox(height: 8),
          _HubTile(
            key: const Key('hub-reading'),
            icon: Icons.auto_stories_outlined,
            emoji: '📚',
            color: Brand.success,
            title: 'Okuma hikâyeleri',
            subtitle: 'Türkçe açıklamalı kısa hikâyeler',
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const ReadingLibraryScreen())),
          ),
          if (track.kind != TrackKind.notes)
            _HubTile(
              key: const Key('hub-notes'),
              icon: Icons.sticky_note_2_outlined,
              emoji: '📝',
              color: const Color(0xFF2F80ED),
              title: 'Notlarım',
              subtitle: 'Kendi kelimelerin, gramer notların ve günlüğün',
              onTap: () => openPage(context, 'Notlarım', const NotesHomeScreen()),
            ),
          const SizedBox(height: 8),
          const SectionLabel('SINAVLAR VE SEVİYE'),
          const SizedBox(height: 8),
          // The selected exam's question bank and mock exams (its study path
          // is in the Öğren tab).
          if (track.kind == TrackKind.exam) ...[
            _HubTile(
              key: const Key('hub-bank'),
              icon: Icons.quiz_rounded,
              emoji: '🗂️',
              color: Brand.primary,
              title: 'Soru bankası',
              subtitle: '${track.title}: konu konu soru çöz, her sorudan sonra açıklama',
              onTap: () => openPage(
                context,
                'Soru bankası',
                ExamHomeScreen(key: ValueKey('bank-${track.id}'), examId: track.id, view: ExamHomeView.bank),
              ),
            ),
            _HubTile(
              key: const Key('hub-mocks'),
              icon: Icons.timer_rounded,
              emoji: '⏱️',
              color: Brand.accent,
              title: 'Deneme sınavları',
              subtitle: 'Mini deneme ve tam deneme paketleri',
              onTap: () => openPage(
                context,
                'Deneme sınavları',
                ExamHomeScreen(
                  key: ValueKey('mocks-${track.id}'),
                  examId: track.id,
                  view: ExamHomeView.mocks,
                ),
              ),
            ),
          ],
          for (final e in examCatalog)
            if (e.id != track.id)
              _HubTile(
                key: Key('hub-exam-${e.id}'),
                icon: trackIcon(e),
                emoji: e.emoji,
                color: Brand.primary,
                title: e.title,
                subtitle: 'Konu pratiği, mini deneme ve sınav paketleri',
                onTap: () => openPage(context, e.title, ExamHomeScreen(key: ValueKey(e.id), examId: e.id)),
              ),
          _HubTile(
            key: const Key('hub-placement'),
            icon: Icons.speed_rounded,
            emoji: '🎯',
            color: Brand.primary,
            title: 'Seviye testi',
            subtitle: 'Seviyeni ölç, sana uygun yerden başla',
            onTap: () => fullScreen(const PlacementIntroScreen()),
          ),
        ],
      ),
    );
  }

  static List<(String, String)> _pool(Course course, Progress p) => vocabularyPool(course, p);
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    super.key,
    required this.icon,
    required this.emoji,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.image,
  });
  final IconData icon;

  /// Owner-supplied picture shown instead of the icon (e.g. the scene icon).
  final String? image;
  final String emoji;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: TapCard(
        onTap: onTap,
        child: Row(
          children: [
            if (image != null)
              Image.asset(image!, width: 44, height: 44, filterQuality: FilterQuality.medium)
            else
              IconBadge(icon: icon, emoji: emoji, color: Brand.tone(color), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Brand.tone(color), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  badge!,
                  style: TextStyle(color: onColor(Brand.tone(color)), fontWeight: FontWeight.w900),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: Brand.muted),
          ],
        ),
      ),
    ),
  );
}
