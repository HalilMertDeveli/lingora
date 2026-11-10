import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/models/grammar_lesson.dart';
import 'package:lingora/screens/grammar_path_screen.dart' show grammarLessonsProvider;
import 'package:lingora/screens/placement_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final _bank = parsePlacementBank(File('assets/placement/questions.json').readAsStringSync());
final _course = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);
final _lessons = [
  for (final l in jsonDecode(File('assets/notes/lessons.json').readAsStringSync()) as List)
    GrammarLesson.fromJson(l as Map<String, dynamic>),
];

/// Reads assets straight from disk, synchronously decoded for fake async.
class _FileBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();

  @override
  void evict(String key) {}
}

Future<void> _pump(WidgetTester tester, Map<String, Object> prefs) async {
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
        courseProvider.overrideWith((ref) async => _course),
        placementBankProvider.overrideWith((ref) async => _bank),
        placementCourseUnitsProvider.overrideWith(
          (ref) async => [
            for (final u in _course.units) [for (final n in u.nodes) n.id],
          ],
        ),
        grammarLessonsProvider.overrideWith((ref) async => _lessons),
        notesProvider.overrideWith((ref) => loadNotes(_FileBundle())),
        examProvider.overrideWith(
          (ref, id) async => Exam.fromJson(
            jsonDecode(File('assets/exams/$id.json').readAsStringSync()) as Map<String, dynamic>,
          ),
        ),
        prefsProvider.overrideWithValue(p),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
      ],
      child: const LingoraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Answers every question: right when [right] is true, otherwise "Bilmiyorum".
Future<int> _answerAll(WidgetTester tester, {required bool right}) async {
  var asked = 0;
  while (find.text('Kontrol et').evaluate().isNotEmpty) {
    asked++;
    if (right) {
      final q = _bank.firstWhere((q) => find.text(q.prompt).evaluate().isNotEmpty);
      final choice = find.byKey(ValueKey('placement_choice_${q.answer}'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
    } else {
      await tester.tap(find.text('Bilmiyorum'));
    }
    await tester.pumpAndSettle();
    expect(right ? find.text('Doğru!') : find.textContaining('Doğrusu:'), findsOneWidget);
    await tester.ensureVisible(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
  }
  return asked;
}

Future<Progress> _saved() async {
  final raw = (await SharedPreferences.getInstance()).getString('progress_v1')!;
  return Progress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<void> _toLevelStep(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
  }
  expect(find.text('Neden İngilizce öğreniyorsun?'), findsOneWidget);
  expect(find.text('Sıfırdan başla'), findsOneWidget);
}

void main() {
  testWidgets('onboarding placement test skips known parts and picks the track', (tester) async {
    await _pump(tester, {});
    await _toLevelStep(tester);
    await tester.tap(find.text('Akademik / YDS'));
    await tester.pump();
    await tester.tap(find.text('Seviyeni ölç'));
    await tester.pumpAndSettle();

    final asked = await _answerAll(tester, right: true);
    expect(asked, inInclusiveRange(placementMinQuestions, placementMaxQuestions));
    expect(find.text('Tahmini seviyen: C1 · İleri'), findsOneWidget);
    expect(find.text('YDS / YÖKDİL'), findsOneWidget);
    await tester.tap(find.text('Bu planla başla'));
    await tester.pumpAndSettle();

    final p = await _saved();
    expect(p.onboarded, isTrue);
    expect(p.trackId, 'yds');
    expect(p.isDone('u12c'), isTrue);
    expect(p.isDone('gl_past_modals'), isTrue);
    expect(p.totalXp, 0);
    expect(find.text('Bu planla başla'), findsNothing);
  });

  testWidgets('a beginner is told it is fine to start from scratch', (tester) async {
    await _pump(tester, {});
    await _toLevelStep(tester);
    await tester.tap(find.text('Seviyeni ölç'));
    await tester.pumpAndSettle();
    await _answerAll(tester, right: false);
    expect(find.text('Sıfırdan başlıyoruz'), findsOneWidget);
    await tester.tap(find.text('Bu planla başla'));
    await tester.pumpAndSettle();

    expect(find.text('Merhaba!'), findsOneWidget);
    final p = await _saved();
    expect(p.trackId, 'tr_en');
    expect(p.completed, isEmpty);
  });

  testWidgets('closing the test returns to onboarding', (tester) async {
    await _pump(tester, {});
    await _toLevelStep(tester);
    await tester.tap(find.text('Seviyeni ölç'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Testi kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Neden İngilizce öğreniyorsun?'), findsOneWidget);
  });

  testWidgets('the test can be retaken from the profile', (tester) async {
    await _pump(tester, {
      'progress_v1': '{"onboarded": true, "remindersEnabled": false}',
      'placement_v1': '{"level": null, "reason": "school", "day": "2026-01-01"}',
    });
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    // Other profile cards (e.g. frequent mistakes) can push this one below the fold.
    await tester.scrollUntilVisible(
      find.text('Son sonuç: Başlangıç'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Son sonuç: Başlangıç'), findsOneWidget);
    await tester.ensureVisible(find.text('Seviyeni ölç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seviyeni ölç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genel'));
    await tester.tap(find.text('Teste başla'));
    await tester.pumpAndSettle();
    await _answerAll(tester, right: true);
    await tester.tap(find.text('Bu planla başla'));
    await tester.pumpAndSettle();

    expect(find.text('Notlarım seçildi.'), findsOneWidget);
    expect(find.text('Son sonuç: C1 · İleri'), findsOneWidget);
    expect((await _saved()).trackId, 'notes');
  });
}
