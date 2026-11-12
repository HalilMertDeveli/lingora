import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/match_exercise.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/speech.dart';

import 'widget_test.dart' show FakeSpeech;

void main() {
  testWidgets('long glosses wrap instead of being cut off', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const ex = Exercise(
      type: ExerciseType.match,
      pairs: [
        ('aktarmak, transfer etmek', 'transfer'),
        ('barındırmak, yer sağlamak', 'accommodate'),
        ('ev', 'house'),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [speechProvider.overrideWithValue(FakeSpeech())],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatchExercise(ex: ex, locked: false, onReady: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final text in ['aktarmak, transfer etmek', 'barındırmak, yer sağlamak', 'house']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    }
    expect(tester.takeException(), isNull);
  });
}
