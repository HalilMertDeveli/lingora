// YDS Faz 3d (docs/sinav/yds-faz3-icerik.md § F3d): ys11 "Ara denemeler", a side path with the half mocks the
// plan schedules for weeks 22, 24 and 27. Each unit is a mixed review (4 lessons of 10–12 choice items, a
// 15-question test, a chest) that ends with its 40-question, 90-minute half mock.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _file = 'assets/courses/exam_yds/11_ara_denemeler.json';

void main() {
  group('YDS ara denemeler (ys11)', skip: File(_file).existsSync() ? false : 'not shipped yet', () {
    late final Map<String, dynamic> data = jsonDecode(File(_file).readAsStringSync()) as Map<String, dynamic>;
    late final List<Map<String, dynamic>> units = (data['units'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> nodes(Map<String, dynamic> u) =>
        (u['nodes'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> ex(Map<String, dynamic> n) =>
        ((n['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>();

    test('parallel side path, index 11, three units', () {
      final s = data['section'] as Map;
      expect([s['id'], s['index'], s['parallel'], s['title']], ['ys11', 11, true, 'Ara denemeler']);
      expect(units.map((u) => u['id']), ['ys11u1', 'ys11u2', 'ys11u3']);
    });

    test('each unit: 4 review lessons, a 15-question test, a chest, then its half mock', () {
      const titles = ['Yarım deneme 2', 'Yarım deneme 3', 'Yarım deneme 4'];
      for (final (i, u) in units.indexed) {
        final id = u['id'];
        final ns = nodes(u);
        expect(ns.map((n) => n['type']), [
          'lesson',
          'lesson',
          'lesson',
          'lesson',
          'test',
          'chest',
          'mock',
        ], reason: '$id');
        for (final l in ns.take(4)) {
          expect(ex(l).length, inInclusiveRange(10, 12), reason: '${l['id']}');
          expect(ex(l).every((e) => e['type'] == 'choice'), isTrue, reason: '${l['id']}');
        }
        expect(ex(ns[4]), hasLength(15), reason: '$id test');
        final mock = ns.last;
        expect(mock['id'], '${id}m');
        expect(mock['title'], titles[i]);
        expect([mock['examId'], mock['size'], mock['minutes']], ['yds', 40, 90]);
        expect(ex(mock), hasLength(40));
      }
    });

    test('every choice has five options, a qtype and a Turkish explanation', () {
      for (final u in units) {
        for (final n in nodes(u)) {
          for (final e in ex(n)) {
            expect((e['options'] as List), hasLength(5), reason: '${n['id']} ${e['question']}');
            expect(e['qtype'], isA<String>(), reason: '${n['id']}');
            expect((e['explanation'] as String).length, greaterThan(40), reason: '${n['id']}');
          }
        }
      }
    });
  });
}
