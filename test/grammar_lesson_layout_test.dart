import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/formula_colors.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/grammar_lesson.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/grammar_path_screen.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _lessons = (jsonDecode(File('assets/notes/lessons.json').readAsStringSync()) as List)
    .map((l) => GrammarLesson.fromJson(l as Map<String, dynamic>))
    .toList();

const _noNotes = NotesBundle(words: [], topics: [], diaryPrompts: []);

Formula _formula(List<List<String>> parts, String example) =>
    Formula.fromJson({'label': 't', 'parts': parts, 'example': example});

String _show(List<ExampleSegment> segs) =>
    segs.where((s) => s.role != null).map((s) => '${s.text.trim()}:${s.role!.name}').join(' | ');

void main() {
  group('example colours follow the formula', () {
    test('simple sentence', () {
      final f = _formula([
        ['Subject', 's'],
        ['Verb', 'v'],
        ['Object', 'o'],
      ], 'We speak Turkish.');
      expect(_show(colorExample(f)), 'We:subject | speak:verb | Turkish.:object');
    });

    test('literal parts, clitics and negatives', () {
      expect(
        _show(
          colorExample(
            _formula([
              ['Subject', 's'],
              ["will ('ll)", 'aux'],
              ['V1', 'v'],
              ['O / C', 'o'],
            ], "I'll call you tonight."),
          ),
        ),
        "I:subject | 'll:aux | call:verb | you tonight.:object",
      );
      expect(
        _show(
          colorExample(
            _formula([
              ['Subject', 's'],
              ["don't / doesn't", 'neg'],
              ['V1', 'v'],
              ['Object', 'o'],
            ], "She doesn't drink coffee."),
          ),
        ),
        "She:subject | doesn't:negative | drink:verb | coffee.:object",
      );
    });

    test('questions and multi-word subjects', () {
      expect(
        _show(
          colorExample(
            _formula([
              ['Where / What / How', 'q'],
              ['am / is / are', 'v'],
              ['Subject', 's'],
            ], 'Where is the meeting room?'),
          ),
        ),
        'Where:question | is:verb | the meeting room?:subject',
      );
    });

    test('clauses split at the comma', () {
      expect(
        _show(
          colorExample(
            _formula([
              ['If', 'x'],
              ['Subject + V1', 's'],
              ['Subject + V1', 'v'],
            ], 'If you heat water to 100 degrees, it boils.'),
          ),
        ),
        'If:other | you heat water to 100 degrees,:subject | it boils.:verb',
      );
    });

    test('every example in the notebook keeps its text and gets colours', () {
      var formulas = 0;
      for (final l in _lessons) {
        for (final f in l.formulas) {
          if (f.example == null) continue;
          formulas++;
          final segs = colorExample(f);
          expect(segs.map((s) => s.text).join(), f.example, reason: f.example);
          expect(segs.where((s) => s.role != null), isNotEmpty, reason: f.example);
        }
      }
      expect(formulas, greaterThan(200));
    });
  });

  group('lesson screen fits small screens and large text', () {
    Future<void> pump(WidgetTester tester, GrammarLesson lesson, {required AppMode mode}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      Brand.apply(mode == AppMode.kid ? Palette.kidLight : Palette.adultLight);
      addTearDown(() => Brand.apply(Palette.adultLight));
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(mode: mode),
            home: GrammarLessonScreen(lesson: lesson, notes: _noNotes),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final mode in AppMode.values) {
      testWidgets('formula and "Biz nasıl söylüyoruz?" steps (${mode.name})', (tester) async {
        final lesson = _lessons.firstWhere((l) => l.formulas.isNotEmpty);
        await pump(tester, lesson, mode: mode);
        final next = find.textContaining(RegExp(r'^(Devam|DEVAM)$'));
        var colours = <Color?>{};
        for (var i = 0; i < 6 && find.text('Biz nasıl söylüyoruz?').evaluate().isEmpty; i++) {
          final example = find.byKey(const ValueKey('formula-example'));
          if (example.evaluate().isNotEmpty) {
            final span = tester.widget<Text>(example).textSpan! as TextSpan;
            colours = {for (final c in span.children!) (c as TextSpan).style?.color};
          }
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        // The formula example is painted with the chips' colours.
        expect(colours, containsAll([roleColors[PartRole.subject], roleColors[PartRole.verb]]));
        expect(find.text('Biz nasıl söylüyoruz?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
