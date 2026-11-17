// "Neden yanlış?" (deneme): Turkish glosses of exam options, read from
// assets/option_glosses/ beside the content, shown under each option only
// after a wrong answer.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/option_glosses.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/screens/exam_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

const _choice = Exercise(
  type: ExerciseType.choice,
  question: 'Farmers depend on an ancient ---- system that carries water to their fields.',
  options: ['emission', 'archive', 'irrigation', 'expedition', 'pottery'],
  answerIndex: 2,
  explanation: 'Su taşıyan sistem sulama sistemidir.',
);

const _gloss = {
  'tr': ['salım, yayım', 'arşiv', 'sulama', 'keşif gezisi', 'çömlekçilik'],
  'why': [
    'Olmaz: salım su taşımaz.',
    'Olmaz: arşiv belge saklar.',
    'Doğru: tarlaya su taşıyan sistem sulamadır.',
    'Olmaz: keşif gezisi bir sistem değildir.',
    'Olmaz: çömlek suyla taşımaz.',
  ],
};

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object?> glosses = const {},
  AppMode mode = AppMode.adult,
  Brightness brightness = Brightness.light,
  Size size = const Size(420, 900),
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 17, 9)),
      optionGlossesProvider.overrideWith((ref) async => OptionGlosses(glosses)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(mode: mode, brightness: brightness),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

LessonScreen _lesson(Exercise ex) =>
    LessonScreen(nodeId: 'ys1u1l1', title: 'Test', items: [(key: 'ys1u1l1#0', ex: ex)], color: Brand.primary);

Future<void> _answer(WidgetTester tester, int option) async {
  await tester.tap(find.byKey(Key('choice-option-$option')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('check')));
  await tester.pumpAndSettle();
}

void main() {
  group('gloss data', () {
    test('a gloss must match the option count, else it is ignored', () {
      expect(OptionGloss.parse(_gloss, 5)!.trOf(2), 'sulama');
      expect(OptionGloss.parse(_gloss, 5)!.whyOf(2), startsWith('Doğru'));
      expect(OptionGloss.parse(_gloss, 4), isNull);
      expect(OptionGloss.parse({'tr': List.filled(5, ' ')}, 5), isNull);
      expect(OptionGloss.parse('nonsense', 5), isNull);
      // Only a reason, no Turkish: still shown.
      final whyOnly = OptionGloss.parse({'why': _gloss['why']}, 5)!;
      expect((whyOnly.trOf(0), whyOnly.whyOf(0) != null), (null, true));
    });

    test('a broken file gives no glosses instead of an error', () {
      expect(OptionGlosses.decode('{not json'), isEmpty);
      expect(OptionGlosses.decode('[1,2]'), isEmpty);
      expect(OptionGlosses.decode('{"items": {"a#0": {}}}').keys, ['a#0']);
    });

    test('the YDS file fits its questions: two units and one half mock, every option', () {
      final file =
          jsonDecode(File('assets/option_glosses/yds.json').readAsStringSync()) as Map<String, dynamic>;
      final glosses = OptionGlosses(file['items'] as Map<String, dynamic>);
      final questions = <String, Exercise>{};
      void read(String path) {
        final j = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        for (final u in j['units'] as List) {
          for (final n in (u as Map)['nodes'] as List) {
            final node = PathNode.fromJson(n as Map<String, dynamic>);
            for (final (i, ex) in node.exercises.indexed) {
              if (ex.type == ExerciseType.choice) questions['${node.id}#$i'] = ex;
            }
          }
        }
      }

      read('assets/courses/exam_yds.json');
      read('assets/courses/exam_yds/06_okuma_evi_1.json');
      final wanted = questions.keys.where((k) => RegExp(r'^ys1u11?[lt]\d*#|^ys6u6m#').hasMatch(k)).toList();
      expect(wanted.length, greaterThanOrEqualTo(150));
      expect(glosses.length, wanted.length);
      for (final k in wanted) {
        final ex = questions[k]!;
        final g = glosses.of(k, ex.options.length);
        expect(g, isNotNull, reason: k);
        // The right option always says why; every option has a reason.
        expect(g!.whyOf(ex.answerIndex!), startsWith('Doğru'), reason: k);
        for (var i = 0; i < ex.options.length; i++) {
          expect(g.whyOf(i), isNotNull, reason: '$k/$i');
          expect(g.whyOf(i)!.length, lessThanOrEqualTo(120), reason: '$k/$i');
          expect((g.trOf(i) ?? '').length, lessThanOrEqualTo(140), reason: '$k/$i');
        }
      }
    });
  });

  group('lesson choice', () {
    testWidgets('a wrong pick opens every option\'s Turkish and says why the pick fails', (tester) async {
      await _pump(tester, _lesson(_choice), glosses: {'ys1u1l1#0': _gloss});
      // Not before answering.
      expect(find.byKey(const Key('option-gloss-toggle')), findsNothing);
      await _answer(tester, 0);
      expect(find.byKey(const Key('option-gloss-toggle')), findsOneWidget);
      expect(find.text('Neden yanlış?'), findsOneWidget);
      for (final tr in _gloss['tr']!) {
        expect(find.text(tr), findsOneWidget);
      }
      // Reasons only for the right option and the wrong pick.
      expect(find.byKey(const Key('option-gloss-why')), findsNWidgets(2));
      expect(find.text('Olmaz: salım su taşımaz.'), findsOneWidget);
      expect(find.text('Doğru: tarlaya su taşıyan sistem sulamadır.'), findsOneWidget);
      // The explanation stays where it was.
      expect(find.text(_choice.explanation!), findsOneWidget);

      await tester.tap(find.byKey(const Key('option-gloss-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('sulama'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a right pick renders no gloss at all: no Turkish, no reason, no toggle', (tester) async {
      await _pump(tester, _lesson(_choice), glosses: {'ys1u1l1#0': _gloss});
      await _answer(tester, 2);
      expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
      expect(find.byKey(const Key('option-gloss-toggle')), findsNothing);
      expect(find.text('Neden yanlış?'), findsNothing);
      expect(find.byKey(const Key('option-gloss-tr')), findsNothing);
      expect(find.byKey(const Key('option-gloss-why')), findsNothing);
      for (final tr in _gloss['tr']!) {
        expect(find.text(tr), findsNothing);
      }
      // The content's own explanation is still there.
      expect(find.text(_choice.explanation!), findsOneWidget);
    });

    testWidgets('no gloss: nothing extra, nothing breaks', (tester) async {
      await _pump(tester, _lesson(_choice));
      await _answer(tester, 0);
      expect(find.byKey(const Key('feedback-wrong')), findsOneWidget);
      expect(find.byKey(const Key('option-gloss-toggle')), findsNothing);
      expect(find.byKey(const Key('option-gloss-tr')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a gloss for other options (content changed) is not shown', (tester) async {
      await _pump(
        tester,
        _lesson(_choice),
        glosses: {
          'ys1u1l1#0': {
            'tr': ['a', 'b', 'c', 'd'],
          },
        },
      );
      await _answer(tester, 0);
      expect(find.byKey(const Key('option-gloss-toggle')), findsNothing);
    });

    for (final (mode, brightness) in [(AppMode.kid, Brightness.dark), (AppMode.adult, Brightness.dark)]) {
      testWidgets('long sentence options wrap without overflow ($mode, $brightness, narrow phone)', (
        tester,
      ) async {
        final sentence =
            'Although the committee had been warned repeatedly about the rising costs of the project, '
            'it decided to go ahead without asking for a second independent assessment.';
        final long = Exercise(
          type: ExerciseType.choice,
          question: 'Which sentence is closest in meaning?',
          options: List.filled(5, sentence),
          answerIndex: 4,
          explanation: 'Açıklama.',
        );
        await _pump(
          tester,
          _lesson(long),
          mode: mode,
          brightness: brightness,
          size: const Size(360, 780),
          glosses: {
            'ys1u1l1#0': {
              'tr': List.filled(
                5,
                'Kurul projenin artan maliyetleri konusunda defalarca uyarılmış olsa da ' * 2,
              ),
              'why': List.filled(
                5,
                'Olmaz: metinde böyle bir neden-sonuç ilişkisi kurulmuyor, anlam kayıyor. ' * 2,
              ),
            },
          },
        );
        await _answer(tester, 0);
        expect(find.byKey(const Key('option-gloss-tr')), findsNWidgets(5));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('exam practice', () {
    const q = ExamQuestion(
      id: 'ys6u6m#0',
      text: 'After the storm, workers tried to ---- the fallen trees from the road.',
      options: ['attract', 'divide', 'remove', 'preserve', 'exceed'],
      answer: 2,
      explanation: 'remove ... from = bir yerden kaldırmak.',
    );
    const exam = Exam(
      id: 'yds',
      title: 'YDS',
      description: '',
      optionCount: 5,
      mockSize: 1,
      mockMinutes: 5,
      sections: [],
    );

    testWidgets('instant feedback shows the options\' Turkish after a mistake', (tester) async {
      await _pump(
        tester,
        const ExamSessionScreen(exam: exam, questions: [q], mock: false, title: 'Konu pratiği'),
        glosses: {
          'ys6u6m#0': {
            'tr': ['çekmek', 'bölmek', 'kaldırmak', 'korumak', 'aşmak'],
            'why': ['Olmaz: çekmek ters anlam.', '', 'Doğru: remove from = kaldırmak.', '', ''],
          },
        },
      );
      expect(find.text('kaldırmak'), findsNothing);
      await tester.tap(find.byKey(const Key('exam-option-0')));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.text('kaldırmak'), findsOneWidget);
      expect(find.text('aşmak'), findsOneWidget);
      expect(find.text('Olmaz: çekmek ters anlam.'), findsOneWidget);
      expect(find.byKey(const Key('option-gloss-why')), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a right answer in practice shows no gloss', (tester) async {
      await _pump(
        tester,
        const ExamSessionScreen(exam: exam, questions: [q], mock: false, title: 'Konu pratiği'),
        glosses: {
          'ys6u6m#0': {
            'tr': ['çekmek', 'bölmek', 'kaldırmak', 'korumak', 'aşmak'],
          },
        },
      );
      await tester.tap(find.byKey(const Key('exam-option-2')));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.text('Doğru!'), findsOneWidget);
      expect(find.byKey(const Key('option-gloss-toggle')), findsNothing);
      expect(find.text('kaldırmak'), findsNothing);
    });
  });
}
