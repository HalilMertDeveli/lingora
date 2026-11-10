import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../billing/premium.dart';
import 'remote_flags.dart';

/// Decides whether the paywall should open by itself after a lesson.
///
/// Rules (Remote Config): never for Premium users; only after
/// `paywall_after_lessons` finished lessons (0 = never), then again only
/// after that many more lessons **and** `paywall_cooldown_days` days. It is
/// always closable and the lesson path never depends on it.
class PaywallTrigger {
  PaywallTrigger(this._ref);
  final Ref _ref;

  static const _lastDayKey = 'paywall.auto.day';
  static const _lastLessonsKey = 'paywall.auto.lessons';

  /// Call once a lesson has been recorded. Returns true (and remembers it)
  /// when the paywall should be shown now.
  bool takeAfterLesson() {
    if (_ref.read(premiumProvider)) return false;
    final flags = _ref.read(remoteFlagsProvider);
    final every = flags.paywallAfterLessons;
    if (every <= 0) return false;
    final done = _ref.read(progressProvider).lessonsDone;
    final prefs = _ref.read(prefsProvider);
    final lastLessons = prefs.getInt(_lastLessonsKey) ?? 0;
    if (done < every || done - lastLessons < every) return false;
    final now = _ref.read(clockProvider)();
    final lastDay = DateTime.tryParse(prefs.getString(_lastDayKey) ?? '');
    if (lastDay != null && now.difference(lastDay).inDays < flags.paywallCooldownDays) return false;
    prefs.setInt(_lastLessonsKey, done);
    prefs.setString(_lastDayKey, now.toIso8601String());
    return true;
  }
}

final paywallTriggerProvider = Provider<PaywallTrigger>(PaywallTrigger.new);
