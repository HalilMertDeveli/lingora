// "Yazamıyorum, kelimelerden seç": a dinle-yaz exercise can switch from the
// keyboard to building the sentence from word tiles (the same word bank the
// translate exercise uses).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/common.dart';
import 'package:lingora/exercises/listen_exercise.dart';
import 'package:lingora/exercises/translate_exercise.dart';
import 'package:lingora/exercises/word_bank.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';

class _Speech implements SpeechService {
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

final _listen = Exercise.fromJson({
  'type': 'listen',
  'text': 'Good morning',
  'answers': ['Good morning'],
});

class _Probe {
  Grader? grader;
  String text = '';
}

Future<_Probe> _pump(WidgetTester tester, Widget Function(_Probe p) build) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final probe = _Probe();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [speechProvider.overrideWithValue(_Speech())],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        builder: (_, child) =>
            PaletteScope(palette: Palette.of(AppMode.adult, Brightness.light), child: child!),
        home: Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: build(probe)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return probe;
}

Widget _listenWidget(_Probe p, {Exercise? ex, bool locked = false}) => ListenExercise(
  ex: ex ?? _listen,
  locked: locked,
  onReady: (g) => p.grader = g,
  onText: (t) => p.text = t,
);

Finder _tile(String w) =>
    find.descendant(of: find.byKey(const Key('word-bank-tiles')), matching: find.text(w));
Finder _answered(String w) =>
    find.descendant(of: find.byKey(const Key('word-bank-answer')), matching: find.text(w));

void main() {
  group('sentenceBank', () {
    test('tiles drop outer punctuation and keep apostrophes', () {
      expect(sentenceTiles("Today I'm going to test the new feature."), [
        'Today',
        "I'm",
        'going',
        'to',
        'test',
        'the',
        'new',
        'feature',
      ]);
      expect(sentenceTiles('Good morning, thank you!'), ['Good', 'morning', 'thank', 'you']);
    });

    test('the sentence words plus distractors that are not in it, always the same', () {
      final bank = sentenceBank('You are a teacher');
      expect(bank, containsAll(['You', 'are', 'a', 'teacher']));
      expect(bank.length, 4 + 3);
      final extra = [...bank]..removeWhere(['You', 'are', 'a', 'teacher'].contains);
      expect(extra.map((w) => w.toLowerCase()).toSet().intersection({'you', 'are', 'a', 'teacher'}), isEmpty);
      expect(sentenceBank('You are a teacher'), bank);
      // Short sentences get two distractors; confusers come first.
      final short = sentenceBank('Good morning');
      expect(short.length, 4);
      expect(short, containsAll(['Good', 'morning', 'well', 'evening']));
    });
  });

  group('ListenExercise', () {
    testWidgets('typing mode is the default and still checks typed answers', (tester) async {
      final p = await _pump(tester, _listenWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const Key('word-bank-tiles')), findsNothing);
      expect(find.text('Yazamıyorum, kelimelerden seç'), findsOneWidget);
      expect(p.grader, isNull);

      await tester.enterText(find.byType(TextField), 'good morning!');
      expect(p.text, 'good morning!');
      expect(p.grader!(), isTrue);
      await tester.enterText(find.byType(TextField), 'good night');
      expect(p.grader!(), isFalse);
    });

    testWidgets('switches to the word bank and builds a correct sentence', (tester) async {
      final p = await _pump(tester, _listenWidget);
      await tester.tap(find.byKey(const Key('listen-use-bank')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('listen-use-keyboard')), findsOneWidget);
      expect(p.grader, isNull);

      await tester.tap(_tile('Good'));
      await tester.pumpAndSettle();
      await tester.tap(_tile('morning'));
      await tester.pumpAndSettle();
      expect(p.text, 'Good morning');
      expect(p.grader!(), isTrue);
      expect(find.bySemanticsLabel('Cevap satırı: Good morning'), findsOneWidget);

      // Tapping an answered tile puts it back in the bank.
      await tester.tap(_answered('Good'));
      await tester.pumpAndSettle();
      expect(p.text, 'morning');
      expect(_answered('Good'), findsNothing);
      expect(p.grader!(), isFalse);
      await tester.tap(_answered('morning'));
      await tester.pumpAndSettle();
      expect(p.grader, isNull);
    });

    testWidgets('a wrong order or a distractor is wrong', (tester) async {
      final p = await _pump(tester, _listenWidget);
      await tester.tap(find.byKey(const Key('listen-use-bank')));
      await tester.pumpAndSettle();
      await tester.tap(_tile('morning'));
      await tester.pumpAndSettle();
      await tester.tap(_tile('Good'));
      await tester.pumpAndSettle();
      expect(p.grader!(), isFalse);

      await tester.tap(_answered('morning'));
      await tester.pumpAndSettle();
      await tester.tap(_tile('evening'));
      await tester.pumpAndSettle();
      expect(p.text, 'Good evening');
      expect(p.grader!(), isFalse);
    });

    testWidgets('back to the keyboard keeps what was typed', (tester) async {
      final p = await _pump(tester, _listenWidget);
      await tester.enterText(find.byType(TextField), 'good mor');
      await tester.tap(find.byKey(const Key('listen-use-bank')));
      await tester.pumpAndSettle();
      expect(p.grader, isNull);
      await tester.tap(find.byKey(const Key('listen-use-keyboard')));
      await tester.pumpAndSettle();
      expect(find.text('good mor'), findsOneWidget);
      expect(p.text, 'good mor');
      expect(p.grader!(), isFalse);
    });

    testWidgets('after checking there is no switch and tiles do nothing', (tester) async {
      await _pump(tester, (p) => _listenWidget(p, locked: true));
      expect(find.byKey(const Key('listen-use-bank')), findsNothing);
    });

    testWidgets('a long sentence fits a 720x1600 phone in word-bank mode', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(720, 1600);
      addTearDown(tester.view.reset);
      final long = Exercise.fromJson({
        'type': 'listen',
        'text': 'Yesterday I worked on the search page with my new colleagues.',
        'answers': ['Yesterday I worked on the search page with my new colleagues.'],
      });
      final p = await _pump(tester, (p) => _listenWidget(p, ex: long));
      await tester.tap(find.byKey(const Key('listen-use-bank')));
      await tester.pumpAndSettle();
      for (final w in sentenceTiles(long.text!)) {
        await tester.tap(_tile(w).first);
        await tester.pumpAndSettle();
      }
      expect(p.grader!(), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('TranslateExercise still builds its answer from the shared word bank', (tester) async {
    final ex = Exercise.fromJson({
      'type': 'translate',
      'text': 'Günaydın',
      'lang': 'tr',
      'answers': ['Good morning'],
      'tokens': ['Good', 'morning', 'night'],
    });
    final p = await _pump(
      tester,
      (p) =>
          TranslateExercise(ex: ex, locked: false, onReady: (g) => p.grader = g, onText: (t) => p.text = t),
    );
    await tester.tap(_tile('Good'));
    await tester.pumpAndSettle();
    await tester.tap(_tile('morning'));
    await tester.pumpAndSettle();
    expect(p.text, 'Good morning');
    expect(p.grader!(), isTrue);
    await tester.tap(_answered('morning'));
    await tester.pumpAndSettle();
    expect(p.text, 'Good');
    expect(p.grader!(), isFalse);
  });
}
