import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/stoic.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentSpeech implements SpeechService {
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async {}
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async =>
      onDone();
  @override
  Future<void> stopListening() async {}
}

class _NoNotifications implements NotificationService {
  @override
  void Function(String? payload)? get onTap => null;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> apply(List<PlannedNotification> plan) async {}
}

final List<StoicQuote> _shipped = parseStoicQuotes(File(stoicAsset).readAsStringSync());

Future<SharedPreferences> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(p),
        speechProvider.overrideWithValue(_SilentSpeech()),
        notificationServiceProvider.overrideWithValue(_NoNotifications()),
        stoicQuotesProvider.overrideWith((ref) async => _shipped),
      ],
      child: MaterialApp(theme: buildTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
  return p;
}

/// Six "select" questions; the right answer is always "cat".
LessonScreen _lesson() => LessonScreen(
  nodeId: 'stoic-test',
  title: 'Test',
  color: Brand.primary,
  items: [
    for (var i = 0; i < 6; i++)
      (
        key: 'stoic-test#$i',
        ex: const Exercise(
          type: ExerciseType.select,
          prompt: 'kedi',
          answer: 'cat',
          choices: [Choice('cat', ''), Choice('dog', '')],
        ),
      ),
  ],
);

Future<void> _answerRight(WidgetTester tester) => _answer(tester, 'cat');

Future<void> _answerWrong(WidgetTester tester) => _answer(tester, 'dog');

Future<void> _answer(WidgetTester tester, String word) async {
  await tester.tap(find.text(word).last);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('check')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feedback-continue')));
  await tester.pumpAndSettle();
}

void main() {
  group('quote data', () {
    test('at least 40 short quotes, every field filled, ids unique', () {
      expect(_shipped.length, greaterThanOrEqualTo(40));
      expect(_shipped.map((q) => q.id).toSet().length, _shipped.length);
      for (final q in _shipped) {
        for (final f in [q.id, q.ref, q.en, q.tr]) {
          expect(f.trim(), isNotEmpty, reason: q.id);
        }
        expect(StoicQuote.authorNames, contains(q.author), reason: q.id);
        expect(StoicQuote.workNames, contains(q.work), reason: q.id);
        expect(q.source, isNot(contains('null')));
        expect(q.en.split(' ').length, lessThanOrEqualTo(30), reason: '${q.id} is too long for A2–B1');
        expect(q.tr, isNot(equals(q.en)), reason: q.id);
      }
    });

    test('all three Stoics are there, and enough plain ones for Çocuk modu', () {
      expect(_shipped.map((q) => q.author).toSet(), {'marcus', 'seneca', 'epictetus'});
      expect(_shipped.where((q) => q.kid).length, greaterThanOrEqualTo(10));
    });

    test('source reads like a citation', () {
      final q = _shipped.firstWhere((q) => q.id == 'ma-5-1');
      expect(q.source, 'Marcus Aurelius, Kendime Düşünceler 5.1');
    });

    test('the asset folder is in pubspec', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/quotes/'));
      final raw = jsonDecode(File(stoicAsset).readAsStringSync()) as Map<String, dynamic>;
      expect(raw['quotes'], isA<List<dynamic>>());
    });
  });

  group('rotation', () {
    test('no quote comes back within the recent window', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final picks = [for (var i = 0; i < 30; i++) pickStoicQuote(p, _shipped, kid: false, seed: i * 7)!.id];
      for (var i = 0; i < picks.length; i++) {
        final window = picks.sublist(i < stoicRecentWindow ? 0 : i - stoicRecentWindow, i);
        expect(window, isNot(contains(picks[i])), reason: 'pick $i repeated');
      }
      expect(p.getStringList(stoicRecentKey)!.last, picks.last);
    });

    test('Çocuk modu only gets the plain quotes and still rotates', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final kidCount = _shipped.where((q) => q.kid).length;
      final picks = [for (var i = 0; i < kidCount; i++) pickStoicQuote(p, _shipped, kid: true, seed: i)!];
      expect(picks.every((q) => q.kid), isTrue);
      expect(picks.map((q) => q.id).toSet().length, kidCount);
    });
  });

  group('setting', () {
    test('on by default and survives a restart', () {
      expect(const AppSettings().stoicQuotes, isTrue);
      expect(AppSettings.fromJson(const {}).stoicQuotes, isTrue);
      final off = const AppSettings().copyWith(stoicQuotes: false);
      expect(AppSettings.fromJson(off.toJson()).stoicQuotes, isFalse);
    });
  });

  group('lesson', () {
    testWidgets('no quote card during the lesson; quote and progress only on the result', (tester) async {
      final prefs = await _pump(tester, _lesson());
      await _answerWrong(tester);
      await _answerWrong(tester);
      for (var i = 0; i < 8; i++) {
        if (find.byKey(const Key('lesson-result')).evaluate().isNotEmpty) break;
        expect(find.byType(BottomSheet), findsNothing, reason: 'nothing opens over the lesson');
        expect(prefs.getStringList(stoicRecentKey), isNull, reason: 'no quote picked mid-lesson');
        await _answerRight(tester);
      }
      expect(find.byKey(const Key('lesson-result')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-stoic')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-stoic-stats')), findsOneWidget);
      expect(find.text('Bugün 1 ders'), findsOneWidget);
      expect(find.text('Toplam 6 doğru'), findsOneWidget);
      expect(find.textContaining('— '), findsOneWidget);
      expect(prefs.getStringList(stoicRecentKey), hasLength(1));
    });

    testWidgets('turned off in Profil: no quote on the result', (tester) async {
      await _pump(
        tester,
        _lesson(),
        prefs: {AppSettingsNotifier.key: jsonEncode(const AppSettings(stoicQuotes: false).toJson())},
      );
      for (var i = 0; i < 6; i++) {
        await _answerRight(tester);
      }
      expect(find.byKey(const Key('lesson-result')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-stoic')), findsNothing);
    });

    testWidgets('Profil switch turns the quotes off', (tester) async {
      final prefs = await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: AppearanceSettings())),
      );
      final tile = find.byKey(const ValueKey('stoic-switch'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final saved = jsonDecode(prefs.getString(AppSettingsNotifier.key)!) as Map<String, dynamic>;
      expect(saved['stoicQuotes'], isFalse);
    });
  });
}
