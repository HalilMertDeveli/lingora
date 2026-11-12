import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/common.dart';

void main() {
  test('stableShuffle keeps every item and gives the same order for the same seed', () {
    const items = ['a', 'b', 'c', 'd'];
    final once = stableShuffle(items, 'I ___ to school.');
    expect(once.toSet(), items.toSet());
    expect(stableShuffle(items, 'I ___ to school.'), once);
    expect(items, ['a', 'b', 'c', 'd'], reason: 'the input list is not changed');
  });

  test('the correct option is not always shown first', () {
    // Content files often list the answer first; after shuffling it should
    // land first only about as often as chance allows.
    var total = 0, first = 0;
    final files = [
      File('assets/courses/tr_en.json'),
      ...Directory('assets/courses/tr_en')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json')),
    ];
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final unit in json['units'] as List) {
        for (final node in (unit as Map)['nodes'] as List) {
          for (final ex in ((node as Map)['exercises'] as List?) ?? const []) {
            final e = ex as Map;
            if (e['type'] != 'fillBlank') continue;
            final choices = ((e['choices'] as List?) ?? const []).cast<String>();
            if (choices.length < 3 || !choices.contains(e['answer'])) continue;
            total++;
            if (stableShuffle(choices, e['text'] as String).first == e['answer']) first++;
          }
        }
      }
    }
    expect(total, greaterThan(500));
    expect(first / total, lessThan(0.45), reason: '$first of $total fill-in-the-blank answers shown first');
  });
}
