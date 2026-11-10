/// Lingora's analytics event taxonomy (documented in docs/analitik.md).
///
/// Every event is built here, so names and parameters stay consistent and
/// nothing personal can slip in: parameters are short enums, content ids
/// (lesson/track ids) or small numbers. Never names, e-mails, free text,
/// invite codes or user ids.
library;

/// App areas counted by [AnalyticsEvent.featureUse].
enum AppFeature {
  aiChat('ai_chat'),
  demoChat('demo_chat'),
  reading('reading'),
  pronunciation('pronunciation'),
  examPractice('exam_practice'),
  mockExam('mock_exam'),
  errorAnalysis('error_analysis'),
  grammar('grammar');

  const AppFeature(this.id);
  final String id;
}

/// Where a paywall was opened from (`paywall_view.placement`).
abstract final class PaywallPlacement {
  static const profile = 'profile';
  static const afterLessons = 'after_lessons';
  static const aiChat = 'ai_chat';
  static const mockExam = 'mock_exam';
  static const errorAnalysis = 'error_analysis';
}

class AnalyticsEvent {
  const AnalyticsEvent._(this.name, [this.params = const {}]);

  final String name;
  final Map<String, Object> params;

  // Onboarding ---------------------------------------------------------------

  /// An onboarding page was shown. [step]: welcome, course, goal, level.
  factory AnalyticsEvent.onboardingStep(String step, int index) =>
      AnalyticsEvent._('onboarding_step', {'step': step, 'index': index});

  /// Placement test started from onboarding.
  factory AnalyticsEvent.placementStart() => const AnalyticsEvent._('placement_start');

  /// Onboarding finished. [method]: placement or scratch.
  factory AnalyticsEvent.onboardingComplete({
    required String method,
    required int dailyGoal,
    required String track,
  }) => AnalyticsEvent._('onboarding_complete', {'method': method, 'daily_goal': dailyGoal, 'track': track});

  // Learning -----------------------------------------------------------------

  /// [mode]: lesson, test (unit test) or practice (mistakes review).
  factory AnalyticsEvent.lessonStart(String lessonId, {required String mode}) =>
      AnalyticsEvent._('lesson_start', {'lesson_id': _clip(lessonId), 'mode': mode});

  /// [accuracy] in percent (0–100), [durationSec] rounded to seconds.
  factory AnalyticsEvent.lessonFinish(
    String lessonId, {
    required String mode,
    required int accuracy,
    required int xp,
    int? durationSec,
  }) => AnalyticsEvent._('lesson_finish', {
    'lesson_id': _clip(lessonId),
    'mode': mode,
    'accuracy': accuracy.clamp(0, 100),
    'xp': xp,
    'duration_s': ?durationSec,
  });

  /// A course track was chosen. [source]: onboarding, home.
  factory AnalyticsEvent.trackChosen(String track, {required String source}) =>
      AnalyticsEvent._('track_chosen', {'track': _clip(track), 'source': source});

  factory AnalyticsEvent.featureUse(AppFeature f) => AnalyticsEvent._('feature_use', {'feature': f.id});

  // Monetisation -------------------------------------------------------------

  /// See [PaywallPlacement]; [variant] comes from Remote Config.
  factory AnalyticsEvent.paywallView({required String placement, required String variant}) =>
      AnalyticsEvent._('paywall_view', {'placement': placement, 'variant': variant});

  factory AnalyticsEvent.paywallClose({required String placement, required String variant}) =>
      AnalyticsEvent._('paywall_close', {'placement': placement, 'variant': variant});

  /// The buy button was pressed. [plan]: monthly or yearly.
  factory AnalyticsEvent.purchaseStart({required String plan, required String placement}) =>
      AnalyticsEvent._('purchase_start', {'plan': plan, 'placement': placement});

  /// A new subscription started with a free trial.
  factory AnalyticsEvent.trialStart({required String plan, required int trialDays}) =>
      AnalyticsEvent._('trial_start', {'plan': plan, 'trial_days': trialDays});

  /// A new paid subscription (no trial).
  factory AnalyticsEvent.purchase({required String plan}) =>
      AnalyticsEvent._('purchase', {'plan': plan, 'item_id': 'lingora_premium_$plan'});

  /// "Restore purchases" finished; [found] whether something was restored.
  factory AnalyticsEvent.purchaseRestore({required bool found}) =>
      AnalyticsEvent._('purchase_restore', {'found': found ? 1 : 0});

  // Churn signals ------------------------------------------------------------

  /// The app was opened after [daysAway] (≥ 2) days without practice.
  factory AnalyticsEvent.sessionReturn(int daysAway) =>
      AnalyticsEvent._('session_return', {'days_away': daysAway > 60 ? 60 : daysAway});

  /// A streak of [length] days was broken (noticed at app start).
  factory AnalyticsEvent.streakLost(int length) => AnalyticsEvent._('streak_lost', {'length': length});

  /// Premium was active and is no longer (cancelled, expired, refunded).
  factory AnalyticsEvent.premiumLapsed({required String source}) =>
      AnalyticsEvent._('premium_lapsed', {'source': source});

  // Referral -----------------------------------------------------------------

  factory AnalyticsEvent.inviteShare() => const AnalyticsEvent._('invite_share');

  /// [result]: ok, or an error code such as invalid_code, own_code, already_redeemed.
  factory AnalyticsEvent.inviteRedeem(String result) =>
      AnalyticsEvent._('invite_redeem', {'result': _clip(result)});

  /// Every event name, for docs and tests.
  static const names = [
    'onboarding_step',
    'placement_start',
    'onboarding_complete',
    'lesson_start',
    'lesson_finish',
    'track_chosen',
    'feature_use',
    'paywall_view',
    'paywall_close',
    'purchase_start',
    'trial_start',
    'purchase',
    'purchase_restore',
    'session_return',
    'streak_lost',
    'premium_lapsed',
    'invite_share',
    'invite_redeem',
  ];

  static String _clip(String s) => s.length <= 100 ? s : s.substring(0, 100);

  @override
  String toString() => '$name$params';
}
