import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/profile_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
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

Future<SharedPreferences> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
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
      ],
      child: MaterialApp(theme: buildTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
  return p;
}

LessonScreen _lesson(Exercise ex) =>
    LessonScreen(nodeId: 'test', title: 'Test', items: [(key: 'test#0', ex: ex)], color: Brand.primary);

Future<void> _build(WidgetTester tester, List<String> words) async {
  for (final w in words) {
    await tester.tap(find.text(w));
    await tester.pump();
  }
  await tester.tap(find.text('Kontrol et'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wrong translation explains the Turkish habit behind it', (tester) async {
    final prefs = await _pump(
      tester,
      _lesson(
        const Exercise(
          type: ExerciseType.translate,
          text: 'Ben bir öğrenciyim.',
          lang: 'tr',
          answers: ['I am a student', "I'm a student"],
          tokens: ['I', 'am', 'a', 'student', 'teacher'],
        ),
      ),
    );
    await _build(tester, ['I', 'am', 'student']);

    expect(find.text('Doğru cevap:'), findsOneWidget);
    expect(find.text('Neden yanlış?'), findsOneWidget);
    expect(find.text(TrErrorCategory.article.label), findsOneWidget);
    expect(find.textContaining('Ben öğretmenim'), findsOneWidget);

    final saved = jsonDecode(prefs.getString('progress_v1')!) as Map<String, dynamic>;
    expect(saved['errorStats'], {'article': 1});
  });

  testWidgets('without a matching rule the missing words are shown', (tester) async {
    await _pump(
      tester,
      _lesson(
        const Exercise(
          type: ExerciseType.translate,
          text: 'İyi geceler',
          lang: 'tr',
          answers: ['Good night'],
          tokens: ['Good', 'night', 'morning'],
        ),
      ),
    );
    await _build(tester, ['Good', 'morning']);
    expect(find.text('Neden yanlış?'), findsOneWidget);
    expect(find.text('Eksik: night · Fazla: morning'), findsOneWidget);
  });

  testWidgets('Turkish answers get no English explanation', (tester) async {
    await _pump(
      tester,
      _lesson(
        const Exercise(
          type: ExerciseType.translate,
          text: 'Good night',
          lang: 'en',
          answers: ['İyi geceler'],
          tokens: ['İyi', 'geceler', 'sabahlar'],
        ),
      ),
    );
    await _build(tester, ['İyi', 'sabahlar']);
    expect(find.text('Doğru cevap:'), findsOneWidget);
    expect(find.text('Neden yanlış?'), findsNothing);
  });

  testWidgets('profile shows the most frequent mistakes with a tip', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: ProfileScreen()),
      prefs: {
        'progress_v1': jsonEncode({
          'onboarded': true,
          'remindersEnabled': false,
          'errorStats': {'article': 5, 'toBe': 2, 'preposition': 3, 'spelling': 1},
        }),
      },
    );
    expect(find.text('Sık yaptığın hatalar'), findsOneWidget);
    expect(find.text(TrErrorCategory.article.label), findsOneWidget);
    expect(find.text(TrErrorCategory.preposition.label), findsOneWidget);
    expect(find.text(TrErrorCategory.toBe.label), findsOneWidget);
    expect(find.text(TrErrorCategory.spelling.label), findsNothing); // top 3 only
    expect(find.text('5 kez'), findsOneWidget);
    expect(find.text('İpucu: ${TrErrorCategory.article.tip}'), findsOneWidget);
  });

  testWidgets('profile explains the empty mistakes card', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: ProfileScreen()),
      prefs: {'progress_v1': '{"onboarded": true, "remindersEnabled": false}'},
    );
    expect(find.textContaining('Henüz kayıtlı hata yok'), findsOneWidget);
  });

  test('error categories are counted once per check and persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final n = c.read(progressProvider.notifier);
    n.recordTrErrors(detectTrErrors('I am agree. He go to home.'));
    n.recordTrErrors(detectTrErrors('She like tea.'));
    n.recordTrErrors(const []);
    final p = c.read(progressProvider);
    expect(p.errorStats, {'toBe': 1, 'thirdPerson': 2, 'preposition': 1});
    expect(p.topErrorCategories(1).single, (TrErrorCategory.thirdPerson, 2));
    final restored = Progress.fromJson(jsonDecode(prefs.getString('progress_v1')!) as Map<String, dynamic>);
    expect(restored.errorStats, p.errorStats);
  });
}
