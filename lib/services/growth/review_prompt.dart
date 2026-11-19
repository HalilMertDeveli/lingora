import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_settings.dart';
import '../../data/progress.dart';

/// A happy moment that may ask for a Google Play review.
enum ReviewMoment { perfectLesson, levelUp, streak7 }

/// The store's own review sheet. [InAppReviewRequester] on phones; tests use
/// a fake.
abstract class ReviewRequester {
  Future<bool> isAvailable();
  Future<void> request();
}

class InAppReviewRequester implements ReviewRequester {
  final _r = InAppReview.instance;

  @override
  Future<bool> isAvailable() => _r.isAvailable();

  @override
  Future<void> request() => _r.requestReview();
}

/// Null off Android/iOS (desktop, web, tests).
final reviewRequesterProvider = Provider<ReviewRequester?>(
  (ref) => !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? InAppReviewRequester() : null,
);

/// When Dilmaç may ask for a review:
/// - only at a happy moment ([ReviewMoment]),
/// - never in the first [settleIn] after the first launch,
/// - at most once per [cooldown],
/// - never in Ebeveyn gözetimli mod (AppMode.kid),
/// - never within [afterPaywall] of a paywall.
///
/// Google Play also rate-limits the sheet itself and may show nothing; the
/// app never knows whether it was shown or what was rated.
class ReviewPolicy {
  ReviewPolicy(this._prefs);
  final SharedPreferences _prefs;

  static const firstSeenKey = 'review.firstSeen';
  static const lastAskedKey = 'review.lastAsked';
  static const lastPaywallKey = 'review.lastPaywall';

  static const settleIn = Duration(days: 3);
  static const cooldown = Duration(days: 30);
  static const afterPaywall = Duration(hours: 1);

  DateTime? _at(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Remembers the first launch (once). Called from `main()`.
  void markFirstSeen(DateTime now) {
    if (_prefs.getInt(firstSeenKey) == null) _prefs.setInt(firstSeenKey, now.millisecondsSinceEpoch);
  }

  void markPaywall(DateTime now) => _prefs.setInt(lastPaywallKey, now.millisecondsSinceEpoch);

  void markAsked(DateTime now) => _prefs.setInt(lastAskedKey, now.millisecondsSinceEpoch);

  bool canAsk(DateTime now, {required bool kid}) {
    if (kid) return false;
    final first = _at(firstSeenKey);
    if (first == null || now.difference(first) < settleIn) return false;
    final asked = _at(lastAskedKey);
    if (asked != null && now.difference(asked) < cooldown) return false;
    final paywall = _at(lastPaywallKey);
    if (paywall != null && now.difference(paywall) < afterPaywall) return false;
    return true;
  }
}

final reviewPolicyProvider = Provider<ReviewPolicy>((ref) => ReviewPolicy(ref.watch(prefsProvider)));

/// Asks for a review at [moment] when [ReviewPolicy] allows it. Returns
/// whether the store sheet was requested. Never throws.
Future<bool> maybeAskForReview(Ref ref, ReviewMoment moment) async {
  final requester = ref.read(reviewRequesterProvider);
  final policy = ref.read(reviewPolicyProvider);
  final now = ref.read(clockProvider)();
  if (requester == null || !policy.canAsk(now, kid: ref.read(appSettingsProvider).isKid)) return false;
  try {
    if (!await requester.isAvailable()) return false;
    policy.markAsked(now);
    await requester.request();
    return true;
  } on Object catch (e) {
    if (kDebugMode) debugPrint('review prompt: $e');
    return false;
  }
}

/// The happy moment of a finished lesson, or null. A unit test passed is the
/// "level up"; a streak counts from 7 days.
ReviewMoment? reviewMomentFor({
  required bool perfect,
  required bool unitTest,
  required int streak,
  required bool streakExtended,
}) {
  if (unitTest) return ReviewMoment.levelUp;
  if (streakExtended && streak >= 7) return ReviewMoment.streak7;
  if (perfect) return ReviewMoment.perfectLesson;
  return null;
}

/// Widget-side entry: [maybeAskForReview] through the app's container.
final reviewPromptProvider = Provider<Future<bool> Function(ReviewMoment)>(
  (ref) =>
      (moment) => maybeAskForReview(ref, moment),
);
