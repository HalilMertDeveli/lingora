import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/practice.dart';
import '../data/progress.dart';
import '../data/stoic.dart';
import '../nav/flow.dart';
import '../theme.dart';
import '../data/wallet.dart' show GoldReason;
import '../services/billing/premium.dart' show premiumProvider;
import '../services/billing/premium_perks.dart' show paywallPacerProvider;
import '../services/growth/analytics.dart' show PaywallPlacement;
import '../ui/premium_offer.dart';
import '../ui/gold_coin.dart';
import '../ui/my_avatar.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/stoic_card.dart';
import 'invite_nudge.dart';
import 'sync_status_line.dart';

/// Accuracy from which the end screen cheers (big hop) instead of a wave.
const successAccuracy = 90;

/// Screens that follow the result in the end-of-session chain
/// (docs/arayuz-referans.md, "Oturum sonu kutlama zinciri"): the streak when
/// any of them moved, the daily goal and quests, then the streak when it grew
/// today.
List<EndStep> celebrationSteps(LessonReward reward) => [
  if (hasQuestStep(reward)) (next) => QuestProgressScreen(reward: reward, onContinue: next),
  if (reward.streakExtended) (next) => StreakCelebrationScreen(streak: reward.streak, onContinue: next),
];

/// Whether [reward] moved the daily goal or a daily quest.
bool hasQuestStep(LessonReward reward) => reward.questProgress.any((q) => q.moved);

/// First screen of the chain: the XP counter, accuracy and time.
class LessonResultScreen extends StatefulWidget {
  const LessonResultScreen({
    super.key,
    required this.reward,
    required this.accuracy,
    required this.duration,
    required this.perfect,
    this.bestCombo = 0,
    this.headline,
    this.onContinue,
    this.showStreak = true,
    this.showQuests = true,
    this.quote,
    this.stoicStats,
  });

  final LessonReward reward;

  /// Stoic saying under the results (Profil > Stoacı sözler); none when null.
  final StoicQuote? quote;

  /// Lessons today and right answers so far, shown with [quote].
  final StoicStats? stoicStats;
  final int accuracy;
  final Duration duration;
  final bool perfect;
  final int bestCombo;

  /// Overrides the default "Ders tamamlandı!" title.
  final String? headline;

  /// "Devam": the next end-of-lesson screen; closes the screen when null.
  final VoidCallback? onContinue;

  /// False when a separate streak screen follows.
  final bool showStreak;

  /// False when a separate daily quest screen follows.
  final bool showQuests;

  @override
  State<LessonResultScreen> createState() => _LessonResultScreenState();
}

class _LessonResultScreenState extends State<LessonResultScreen> {
  @override
  void initState() {
    super.initState();
    SessionFx.celebrate();
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.reward;
    final t = Theme.of(context).textTheme;
    final mm = widget.duration.inMinutes.toString();
    final ss = (widget.duration.inSeconds % 60).toString().padLeft(2, '0');
    final goalDone = reward.todayXp >= reward.dailyGoal;
    final success = widget.perfect || widget.accuracy >= successAccuracy;
    const step = Duration(milliseconds: 140);
    var delay = const Duration(milliseconds: 350);
    Duration next() => delay += step;

    return Scaffold(
      key: const Key('lesson-result'),
      body: TeaCelebration(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                // Celebration: Pofuduk (both modes) puts on his sunglasses for a
                // strong lesson and dances otherwise.
                Pofuduk(mood: success ? Mood.cheer : Mood.happy, size: Brand.isKid ? 150 : 124),
                const SizedBox(height: 8),
                PopIn(
                  delay: const Duration(milliseconds: 150),
                  child: Text(
                    widget.headline ?? (widget.perfect ? 'Kusursuz ders!' : 'Ders tamamlandı!'),
                    style: t.headlineSmall?.copyWith(color: Brand.isKid ? Brand.primary : Brand.ink),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _Tile(
                      'TOPLAM XP',
                      Icons.bolt,
                      Brand.xp,
                      next(),
                      CountUp(
                        key: const Key('xp-counter'),
                        value: reward.xp,
                        prefix: '+',
                        style: _Tile.valueStyle,
                        duration: const Duration(milliseconds: 1100),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Tile(
                      'DOĞRULUK',
                      Icons.track_changes,
                      Brand.success,
                      next(),
                      CountUp(value: widget.accuracy, prefix: '%', style: _Tile.valueStyle),
                    ),
                    const SizedBox(width: 10),
                    _Tile(
                      'SÜRE',
                      Icons.timer_outlined,
                      Brand.info,
                      next(),
                      Text('$mm:$ss', style: _Tile.valueStyle),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Altın earned with this lesson: "+N altın" pops in and counts up.
                if (reward.goldTotal > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // The learner's own avatar and frame cheer the gold in.
                      const _ResultAvatar(),
                      Flexible(
                        child: GoldGain(
                          amount: reward.goldTotal,
                          delay: next(),
                          label: goldBreakdown(reward),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (reward.freezesUsed > 0)
                  _Banner(
                    delay: next(),
                    color: Brand.info,
                    icon: Icons.ac_unit_rounded,
                    text: reward.freezesUsed == 1
                        ? 'Seri dondurma serini korudu.'
                        : '${reward.freezesUsed} seri dondurma serini korudu.',
                  ),
                if (widget.bestCombo >= 3)
                  _Banner(
                    delay: next(),
                    color: Brand.streak,
                    icon: Icons.whatshot_rounded,
                    text: 'En uzun seri: ${widget.bestCombo} doğru üst üste',
                  ),
                if (widget.showStreak && reward.streakExtended)
                  _Banner(
                    delay: next(),
                    color: Brand.streak,
                    icon: Icons.local_fire_department,
                    text: reward.streak == 1
                        ? 'Seri başladı! Yarın da gel.'
                        : '${reward.streak} günlük seri!',
                  ),
                if (widget.showQuests)
                  for (final q in reward.questsCompleted)
                    _Banner(
                      delay: next(),
                      color: Brand.success,
                      icon: Icons.task_alt,
                      text: 'Görev tamamlandı: ${q.title}',
                      trailing: 'Ödül hazır',
                    ),
                const SizedBox(height: 10),
                Text(
                  goalDone
                      ? 'Günlük hedef tamam: ${reward.todayXp} / ${reward.dailyGoal} XP'
                      : 'Günlük hedef: ${reward.todayXp} / ${reward.dailyGoal} XP',
                  style: TextStyle(
                    color: goalDone ? Brand.success : Brand.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                // Where this lesson is saved: phone only, account, or waiting.
                const SyncStatusLine(center: true),
                if (widget.quote case final quote?) ...[
                  const SizedBox(height: 16),
                  Flexible(
                    flex: 3,
                    child: PopIn(
                      delay: next(),
                      from: 0.9,
                      child: SingleChildScrollView(
                        child: StoicResultCard(quote: quote, stats: widget.stoicStats),
                      ),
                    ),
                  ),
                ],
                // A perfect run is a good moment to bring a friend (paced, never for kids).
                if (widget.perfect && widget.quote == null) ...[
                  const SizedBox(height: 14),
                  // Scrolls instead of overflowing on short screens (with the sync line).
                  const Flexible(
                    child: SingleChildScrollView(child: InviteNudge(place: InviteNudgePlace.perfectLesson)),
                  ),
                ],
                const Spacer(),
                PressableButton(
                  label: 'DEVAM',
                  onPressed: widget.onContinue ?? () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Second screen when the lesson started or extended a streak: the flame
/// pops in, the day count rolls over and this week's days light up.
class StreakCelebrationScreen extends StatefulWidget {
  const StreakCelebrationScreen({super.key, required this.streak, this.onContinue, this.today});
  final int streak;
  final VoidCallback? onContinue;

  /// "Today" for the week row; now by default.
  final DateTime? today;

  @override
  State<StreakCelebrationScreen> createState() => _StreakCelebrationScreenState();
}

class _StreakCelebrationScreenState extends State<StreakCelebrationScreen> {
  static const _days = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];

  @override
  void initState() {
    super.initState();
    SessionFx.celebrate();
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.streak;
    final today = widget.today ?? DateTime.now();
    final lit = min(streak, 7);
    return Scaffold(
      key: const Key('streak-celebration'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Pofuduk(mood: Mood.happy, size: Brand.isKid ? 130 : 110),
              const SizedBox(height: 8),
              PopIn(from: 0.2, child: Icon(Icons.local_fire_department, color: Brand.streak, size: 84)),
              CountUp(
                key: const Key('streak-counter'),
                from: max(0, streak - 1),
                value: streak,
                duration: const Duration(milliseconds: 700),
                style: TextStyle(color: Brand.streak, fontSize: 56, fontWeight: FontWeight.w900, height: 1),
              ),
              const SizedBox(height: 6),
              Text(
                streak == 1 ? 'Seri başladı!' : '$streak günlük seri!',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              // The last seven days; today is the right-most dot.
              TapCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 6; i >= 0; i--)
                      _DayDot(
                        label: _days[today.subtract(Duration(days: i)).weekday - 1],
                        on: i < lit,
                        today: i == 0,
                        delay: Duration(milliseconds: 300 + (6 - i) * 90),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                switch (streak) {
                  1 => 'Yarın da kısa bir ders yaparsan serin büyür.',
                  7 => 'Tam bir hafta! Alışkanlık oturmaya başladı.',
                  30 => 'Bir ay boyunca her gün. Bu gerçek bir başarı!',
                  100 => '100 gün! Çok az kişi buraya kadar geliyor.',
                  _ => 'Her gün biraz: en etkili öğrenme yolu bu.',
                },
                key: const Key('streak-message'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
              ),
              if (streakOfferMilestones.contains(streak)) ...[
                const SizedBox(height: 16),
                _MilestoneOffer(streak: streak),
              ] else if (streak >= 3) ...[
                const SizedBox(height: 16),
                const InviteNudge(place: InviteNudgePlace.streak),
              ],
              const Spacer(),
              PressableButton(
                label: 'DEVAM',
                onPressed: widget.onContinue ?? () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.on, required this.today, required this.delay});
  final String label;
  final bool on;
  final bool today;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? Brand.streak : Brand.surface,
        border: Border.all(color: today ? Brand.streak : Brand.line, width: 2),
      ),
      child: on ? Icon(Icons.check_rounded, size: 18, color: onColor(Brand.streak)) : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: today ? Brand.streak : Brand.muted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        if (on) PopIn(delay: delay, child: dot) else dot,
      ],
    );
  }
}

/// Third screen: today's goal and daily quests fill from where they were
/// before the lesson to where they are now, one after another.
class QuestProgressScreen extends StatefulWidget {
  const QuestProgressScreen({super.key, required this.reward, this.onContinue});
  final LessonReward reward;
  final VoidCallback? onContinue;

  /// Time each bar takes to fill, and the gap between bars.
  static const fill = Duration(milliseconds: 700);
  static const stagger = Duration(milliseconds: 350);

  @override
  State<QuestProgressScreen> createState() => _QuestProgressScreenState();
}

class _QuestProgressScreenState extends State<QuestProgressScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.reward.questsCompleted.isNotEmpty) SessionFx.celebrate();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reward;
    final t = Theme.of(context).textTheme;
    var i = 0;
    Duration nextDelay() => QuestProgressScreen.stagger * (++i);
    final anyDone = r.questsCompleted.isNotEmpty;
    return Scaffold(
      key: const Key('quest-progress'),
      body: TeaCelebration(
        active: anyDone,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(child: Mascot(mood: anyDone ? Mood.cheer : Mood.happy, size: 110, react: true)),
                const SizedBox(height: 8),
                Text(
                  anyDone ? 'Görev tamamlandı!' : 'Günlük görevler',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall,
                ),
                const SizedBox(height: 20),
                _QuestBar(
                  key: const Key('quest-bar-goal'),
                  icon: Icons.flag_rounded,
                  color: Brand.accent,
                  title: 'Günlük hedef',
                  before: r.todayXpBefore,
                  after: r.todayXp,
                  target: r.dailyGoal,
                  unit: ' XP',
                  delay: nextDelay(),
                ),
                for (final q in r.questProgress)
                  _QuestBar(
                    key: Key('quest-bar-${q.quest.id}'),
                    icon: q.after >= q.quest.target ? Icons.task_alt : Icons.radio_button_unchecked,
                    color: Brand.success,
                    title: q.quest.title,
                    before: q.before,
                    after: q.after,
                    target: q.quest.target,
                    delay: nextDelay(),
                    trailing: q.completedNow ? 'Ödül hazır' : null,
                  ),
                const Spacer(),
                PressableButton(
                  label: 'DEVAM',
                  onPressed: widget.onContinue ?? () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestBar extends StatefulWidget {
  const _QuestBar({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.before,
    required this.after,
    required this.target,
    required this.delay,
    this.unit = '',
    this.trailing,
  });
  final IconData icon;
  final Color color;
  final String title;
  final int before;
  final int after;
  final int target;
  final Duration delay;
  final String unit;
  final String? trailing;

  @override
  State<_QuestBar> createState() => _QuestBarState();
}

class _QuestBarState extends State<_QuestBar> {
  late double _value = _ratio(widget.before);
  bool _started = false;

  double _ratio(int v) => widget.target <= 0 ? 1 : (v / widget.target).clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _value = _ratio(widget.after);
      return;
    }
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _value = _ratio(widget.after));
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final done = widget.after >= widget.target;
    final shown = done ? widget.target : widget.after;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TapCard(
        child: Row(
          children: [
            Icon(widget.icon, color: widget.color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleSmall)),
                      Text(
                        '$shown / ${widget.target}${widget.unit}',
                        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _value),
                    duration: reduced ? Duration.zero : QuestProgressScreen.fill,
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => GlossyProgress(value: v, height: 14, color: widget.color),
                  ),
                  if (widget.trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: PopIn(
                        delay: widget.delay + QuestProgressScreen.fill,
                        child: Text(
                          widget.trailing!,
                          style: TextStyle(color: widget.color, fontWeight: FontWeight.w800),
                        ),
                      ),
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

/// Gentle break reminder after a run of lessons (see BreakTracker): Pofuduk
/// meditates and offers a tea break (both modes); never blocks learning.
class BreakReminderScreen extends StatelessWidget {
  const BreakReminderScreen({super.key, this.onContinue});
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('break-reminder'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            Pofuduk(mood: Mood.calm, size: Brand.isKid ? 170 : 140),
            const SizedBox(height: 12),
            Text('Kısa bir çay molası?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              'Art arda birkaç ders yaptın, harika!\n'
              'Birkaç dakika gözlerini dinlendir, bir çay iç; öğrendiklerin yerine otursun.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            PressableButton(label: 'TAMAM', onPressed: onContinue ?? () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
  );
}

/// Shown when a unit test ends below the pass mark.
class TestFailedScreen extends StatelessWidget {
  const TestFailedScreen({super.key, required this.accuracy, this.onRetry});
  final int accuracy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            const Mascot(mood: Mood.sad, size: 150, react: true),
            const SizedBox(height: 12),
            Text('Az kaldı!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              '%$accuracy doğru yaptın. Geçmek için %$testPassPercent gerekiyor.\n'
              'Sık takıldığın sorular "Hatalarını çalış" listesine eklenir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            if (onRetry != null) ...[
              PressableButton(label: 'TEKRAR DENE', onPressed: onRetry),
              const SizedBox(height: 12),
            ],
            PressableButton(
              label: 'ŞİMDİLİK ÇIK',
              outlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shown when a skip exam ("Atlama sınavı") runs out of hearts. Nothing on
/// the path changes; the tone stays friendly.
class SkipFailedScreen extends StatelessWidget {
  const SkipFailedScreen({
    super.key,
    required this.correct,
    required this.answered,
    required this.unit,
    this.onRetry,
  });

  final int correct;
  final int answered;

  /// A unit skip exam (else a section one).
  final bool unit;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('skip-failed'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            const Mascot(mood: Mood.calm, size: 150, react: true),
            const SizedBox(height: 12),
            Text(
              'Canların bitti, hiç sorun değil',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              '$answered sorunun $correct tanesini doğru yaptın. '
              '${unit ? 'Bu ünite' : 'Bu bölüm'} yerinde duruyor: derslerle devam edebilir '
              'ya da sınavı istediğin zaman yeniden deneyebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            if (onRetry != null) ...[
              PressableButton(key: const Key('skip-retry'), label: 'YENİDEN DENE', onPressed: onRetry),
              const SizedBox(height: 12),
            ],
            PressableButton(
              key: const Key('skip-back'),
              label: 'YOLA DÖN',
              outlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.delay,
    required this.color,
    required this.icon,
    required this.text,
    this.trailing,
  });
  final Duration delay;
  final Color color;
  final IconData icon;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: PopIn(
      delay: delay,
      from: 0.85,
      child: TapCard(
        selected: true,
        color: color,
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.icon, this.color, this.delay, this.value);
  final String label;
  final IconData icon;
  final Color color;
  final Duration delay;
  final Widget value;

  static TextStyle get valueStyle => TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Brand.ink);

  @override
  Widget build(BuildContext context) => Expanded(
    child: PopIn(delay: delay, child: context.isKid ? _kid() : _adult(context)),
  );

  // Reference-style stat tile in both modes: a coloured frame with the label
  // on it and the value on a card inside.
  Widget _adult(BuildContext context) => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.md + 2)),
    padding: const EdgeInsets.fromLTRB(2, 5, 2, 2),
    child: Column(
      children: [
        Text(
          sentenceCase(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: onColor(color), fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(Radii.md)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              value,
            ],
          ),
        ),
      ],
    ),
  );

  Widget _kid() => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(13)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 4),
              value,
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Ders 5 · Hatasız 3 · Günlük hedef 10" under the gold gain.
String goldBreakdown(LessonReward r) => [
  for (final (reason, amount) in r.gold)
    '${switch (reason) {
      GoldReason.lesson => 'Ders',
      GoldReason.perfect => 'Hatasız',
      GoldReason.dailyGoal => 'Günlük hedef',
      GoldReason.streak => 'Seri ödülü',
      GoldReason.quest => 'Görev',
      GoldReason.league => 'Lig',
      GoldReason.rewardedAd => 'Bonus',
      GoldReason.other => 'Ödül',
      GoldReason.premium => 'Premium ×2',
    }} $amount',
].join(' · ');

/// The learner's avatar and frame next to the gold. Nothing outside a
/// ProviderScope (widget tests that build the screen alone).
/// Streak lengths whose celebration carries a soft Premium offer.
const streakOfferMilestones = {7, 30, 100};

/// Under a 7 / 30 / 100-day streak: a gentle Premium card (the streak
/// freezes keep such a streak safe). Not for Premium, Çocuk modu, or a few
/// days after the paywall was closed; nothing outside a ProviderScope.
class _MilestoneOffer extends StatelessWidget {
  const _MilestoneOffer({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return const SizedBox.shrink();
    }
    return Consumer(
      builder: (context, ref, _) {
        ref.watch(premiumProvider);
        if (!ref.read(paywallPacerProvider).canOffer) return const SizedBox.shrink();
        return PremiumOfferCard(
          placement: PaywallPlacement.streakMilestone,
          icon: Icons.ac_unit_rounded,
          title: '$streak günlük serini Premium ile koru',
          body: 'Her ay 2 seri dondurma, 2 kat altın ve her yanlışın açıklaması.',
        );
      },
    );
  }
}

class _ResultAvatar extends StatelessWidget {
  const _ResultAvatar();

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(right: 10),
      child: MyAvatar(key: ValueKey('result-avatar'), size: 48),
    );
  }
}
