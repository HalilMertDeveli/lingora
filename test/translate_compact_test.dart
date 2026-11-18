import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/translate_exercise.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/theme.dart';

/// QA on a 720x1280 phone (640 dp tall): the last row of the word bank sat
/// under the "Kontrol et" bar. Short screens get tighter gaps.
final _ex = Exercise.fromJson({
  'type': 'translate',
  'text': 'Şu anda bir bankada çalışıyorum.',
  'answers': ['I currently work at a bank.'],
  'tokens': ['I', 'currently', 'work', 'at', 'a', 'bank', 'school', 'the', 'works'],
});

Future<double> _height(WidgetTester tester, Size screen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = screen;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light),
      builder: (_, child) =>
          PaletteScope(palette: Palette.of(AppMode.adult, Brightness.light), child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TranslateExercise(key: UniqueKey(), ex: _ex, locked: false, onReady: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(TranslateExercise)).height;
}

void main() {
  testWidgets('short phone: the exercise is at least 50 dp shorter', (tester) async {
    final tall = await _height(tester, const Size(360, 800));
    final short = await _height(tester, const Size(360, 640));
    expect(tall - short, greaterThanOrEqualTo(50));
    expect(tester.takeException(), isNull);
  });
}
