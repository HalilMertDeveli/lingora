// YDS Faz 1b (docs/sinav/yds-faz1-icerik.md §3–4): ys6 "Okuma evi 1" and its diagnostic half mock.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _file = 'assets/courses/exam_yds/06_okuma_evi_1.json';

void main() {
  group('YDS okuma evi 1', skip: File(_file).existsSync() ? false : 'not shipped yet', () {
    late final Map<String, dynamic> section =
        jsonDecode(File(_file).readAsStringSync()) as Map<String, dynamic>;
    late final List<Map<String, dynamic>> units = (section['units'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> nodes(Map<String, dynamic> u) =>
        (u['nodes'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> ex(Map<String, dynamic> n) =>
        ((n['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>();

    test('parallel section of 6 units with 48 reading texts (36 in lessons, 12 in tests)', () {
      expect((section['section'] as Map)['parallel'], isTrue);
      expect(units, hasLength(6));
      final lessonTexts = <String>{}, testTexts = <String>{};
      for (final u in units) {
        for (final n in nodes(u)) {
          for (final e in ex(n)) {
            if (e['qtype'] != 'reading') continue;
            if (n['type'] == 'lesson') lessonTexts.add(e['passage'] as String);
            if (n['type'] == 'test') testTexts.add(e['passage'] as String);
          }
        }
      }
      expect(lessonTexts, hasLength(36));
      expect(testTexts, hasLength(12));
    });

    test('text lessons carry reading metadata for the library and the reading counter', () {
      for (final u in units) {
        for (final n in nodes(u).take(3)) {
          final r = n['reading'] as Map?;
          expect(r, isNotNull, reason: '${n['id']}');
          expect(['fen', 'saglik', 'sosyal'], contains(r!['field']), reason: '${n['id']}');
          expect(r['words'], isA<int>(), reason: '${n['id']}');
          expect(r['cefr'], isA<String>(), reason: '${n['id']}');
        }
      }
    });

    test('the section ends with a fixed 40-question diagnostic mock in the YDS distribution', () {
      final mock = nodes(units.last).last;
      expect(mock['type'], 'mock');
      expect([mock['examId'], mock['size'], mock['minutes']], ['yds', 40, 90]);
      final qs = ex(mock);
      expect(qs, hasLength(40));
      final counts = <String, int>{};
      for (final q in qs) {
        expect(q['type'], 'choice');
        expect((q['options'] as List), hasLength(5));
        counts[q['qtype'] as String] = (counts[q['qtype']] ?? 0) + 1;
      }
      expect(counts, {
        'vocabulary': 3, 'grammar': 5, 'cloze': 5, 'sentenceCompletion': 5, 'translation': 3, //
        'reading': 8, 'dialogue': 3, 'restatement': 2, 'paragraphCompletion': 2, 'irrelevantSentence': 4,
      });
    });

    test('every choice question names its YDS question type', () {
      const qtypes = {
        'vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue', //
        'restatement', 'paragraphCompletion', 'irrelevantSentence',
      };
      for (final u in units) {
        for (final n in nodes(u)) {
          for (final e in ex(n).where((e) => e['type'] == 'choice')) {
            expect(qtypes, contains(e['qtype']), reason: '${n['id']} ${e['question']}');
          }
        }
      }
    });
  });
}
