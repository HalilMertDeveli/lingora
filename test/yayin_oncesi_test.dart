// Yayın öncesi: ebeveyn gözetimli modda yapay zekâ yok, Crashlytics izinle,
// uygulama içi değerlendirme isteğinin sıklık kuralları.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/growth/crash_reporting.dart';
import 'package:lingora/services/growth/review_prompt.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/writing.dart';
import 'package:shared_preferences/shared_preferences.dart';

var _now = DateTime(2026, 11, 19, 12);

class _FakeReview implements ReviewRequester {
  int asked = 0;
  bool available = true;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> request() async => asked++;
}

class _FakeCrash implements CrashSink {
  final records = <String>[];
  final enabled = <bool>[];
  final users = <String>[];
  int deleted = 0;

  @override
  Future<void> record(Object error, StackTrace? stack, {required bool fatal, String? reason}) async =>
      records.add('$error|$fatal|$reason');
  @override
  Future<void> recordFlutterError(FlutterErrorDetails details, {required bool fatal}) async =>
      records.add('flutter:${details.exception}');
  @override
  Future<void> setCollectionEnabled(bool on) async => enabled.add(on);
  @override
  Future<void> setUserId(String uid) async => users.add(uid);
  @override
  Future<void> deleteUnsent() async => deleted++;
}

Future<(ProviderContainer, _FakeReview)> _container({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final review = _FakeReview();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      clockProvider.overrideWithValue(() => _now),
      reviewRequesterProvider.overrideWithValue(review),
    ],
  );
  addTearDown(c.dispose);
  return (c, review);
}

int _ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  setUp(() => _now = DateTime(2026, 11, 19, 12));

  group('Ebeveyn gözetimli mod', () {
    test('no AI: scripted conversation, demo rehearsal, no AI writing feedback', () async {
      final (c, _) = await _container();
      c.read(appSettingsProvider.notifier).setMode(AppMode.kid);
      expect(c.read(conversationServiceProvider), isA<DemoConversationService>());
      expect(c.read(conversationServiceProvider).isLive, isFalse);
      expect(c.read(rehearsalServiceProvider), isA<DemoRehearsalService>());
      expect(c.read(writingServiceProvider), isNull);
    });

    test('is presented as parent-led, never as a children\'s app', () {
      expect(AppMode.kid.label, 'Ebeveyn gözetimli');
      expect(AppMode.kid.label.toLowerCase(), isNot(contains('çocuk')));
    });
  });

  group('Değerlendirme isteği', () {
    final firstSeen = {ReviewPolicy.firstSeenKey: _ms(DateTime(2026, 11, 1))};

    test('happy moments', () {
      expect(
        reviewMomentFor(perfect: false, unitTest: true, streak: 1, streakExtended: false),
        ReviewMoment.levelUp,
      );
      expect(
        reviewMomentFor(perfect: false, unitTest: false, streak: 7, streakExtended: true),
        ReviewMoment.streak7,
      );
      expect(reviewMomentFor(perfect: false, unitTest: false, streak: 6, streakExtended: true), isNull);
      expect(reviewMomentFor(perfect: false, unitTest: false, streak: 9, streakExtended: false), isNull);
      expect(
        reviewMomentFor(perfect: true, unitTest: false, streak: 2, streakExtended: true),
        ReviewMoment.perfectLesson,
      );
      expect(reviewMomentFor(perfect: false, unitTest: false, streak: 2, streakExtended: true), isNull);
    });

    test('never in the first 3 days', () async {
      final (c, review) = await _container(
        prefs: {ReviewPolicy.firstSeenKey: _ms(_now.subtract(const Duration(days: 2)))},
      );
      expect(await maybeAskForReview(c.read(_refProvider), ReviewMoment.perfectLesson), isFalse);
      _now = _now.add(const Duration(days: 1, minutes: 1));
      expect(await maybeAskForReview(c.read(_refProvider), ReviewMoment.perfectLesson), isTrue);
      expect(review.asked, 1);
    });

    test('nothing recorded yet (no first launch) asks nothing', () async {
      final (c, review) = await _container();
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isFalse);
      c.read(reviewPolicyProvider).markFirstSeen(_now);
      c.read(reviewPolicyProvider).markFirstSeen(_now.add(const Duration(days: 9)));
      _now = _now.add(const Duration(days: 3));
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isTrue);
      expect(review.asked, 1);
    });

    test('at most once per 30 days', () async {
      final (c, review) = await _container(prefs: firstSeen);
      final ask = c.read(reviewPromptProvider);
      expect(await ask(ReviewMoment.streak7), isTrue);
      _now = _now.add(const Duration(days: 29));
      expect(await ask(ReviewMoment.perfectLesson), isFalse);
      _now = _now.add(const Duration(days: 1));
      expect(await ask(ReviewMoment.perfectLesson), isTrue);
      expect(review.asked, 2);
    });

    test('never in Ebeveyn gözetimli mod', () async {
      final (c, review) = await _container(prefs: firstSeen);
      c.read(appSettingsProvider.notifier).setMode(AppMode.kid);
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isFalse);
      expect(review.asked, 0);
    });

    test('never right after a paywall', () async {
      final (c, review) = await _container(prefs: firstSeen);
      c.read(reviewPolicyProvider).markPaywall(_now.subtract(const Duration(minutes: 10)));
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isFalse);
      _now = _now.add(const Duration(hours: 1));
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isTrue);
      expect(review.asked, 1);
    });

    test('store sheet unavailable: nothing is marked, the next moment may ask', () async {
      final (c, review) = await _container(prefs: firstSeen);
      review.available = false;
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isFalse);
      review.available = true;
      expect(await c.read(reviewPromptProvider)(ReviewMoment.levelUp), isTrue);
    });
  });

  group('Crashlytics', () {
    setUp(CrashReporter.reset);
    tearDown(CrashReporter.reset);

    test('nothing is sent without consent; declining deletes unsent reports', () {
      final sink = _FakeCrash();
      CrashReporter.attach(sink);
      CrashReporter.nonFatal(StateError('x'), null, reason: 'billing_buy');
      expect(sink.records, isEmpty);
      CrashReporter.setConsent(false);
      expect(sink.enabled, [false]);
      expect(sink.deleted, 1);
      CrashReporter.nonFatal(StateError('y'), null, reason: 'billing_buy');
      expect(sink.records, isEmpty);
    });

    test('with consent: collection on, errors recorded, buffered ones flushed', () {
      final sink = _FakeCrash();
      CrashReporter.setConsent(true);
      CrashReporter.nonFatal(StateError('early'), null, reason: 'progress_upload');
      CrashReporter.attach(sink);
      expect(sink.enabled, [true]);
      expect(sink.records.single, contains('early|false|progress_upload'));
      CrashReporter.setUser('uid-1');
      expect(sink.users, ['uid-1']);
    });

    test('errors before the answer wait, then go out on "İzin ver"', () {
      final sink = _FakeCrash();
      CrashReporter.attach(sink);
      CrashReporter.nonFatal(StateError('a'), null, reason: 'account');
      CrashReporter.setConsent(true);
      expect(sink.records.single, contains('a|false|account'));
    });

    test('the uid follows sign-in only with consent', () async {
      final sink = _FakeCrash();
      CrashReporter.attach(sink);
      CrashReporter.setUser('uid-2');
      expect(sink.users, isEmpty);
    });
  });
}

/// A plain provider to get a [Ref] for [maybeAskForReview] in tests.
final _refProvider = Provider<Ref>((ref) => ref);
