// YDS reading sections and their half mocks: ys6 "Okuma evi 1" (Faz 1b) and ys8 "Okuma evi 2" (Faz 2b).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (file, units, lesson texts, test texts, extra reading lists required on text lessons)
const _sections = [
  ('assets/courses/exam_yds/06_okuma_evi_1.json', 6, 36, 12, <String>[]),
  ('assets/courses/exam_yds/08_okuma_evi_2.json', 10, 60, 20, ['ys7', 'ys5']),
];

void main() {
  for (final (file, unitCount, lessonCount, testCount, lists) in _sections) {
    group(
      'YDS okuma evi ${file.split('/').last}',
      skip: File(file).existsSync() ? false : 'not shipped yet',
      () {
        late final Map<String, dynamic> section =
            jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
        late final List<Map<String, dynamic>> units = (section['units'] as List).cast<Map<String, dynamic>>();
        List<Map<String, dynamic>> nodes(Map<String, dynamic> u) =>
            (u['nodes'] as List).cast<Map<String, dynamic>>();
        List<Map<String, dynamic>> ex(Map<String, dynamic> n) =>
            ((n['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>();

        test('parallel section of $unitCount units with ${lessonCount + testCount} reading texts', () {
          expect((section['section'] as Map)['parallel'], isTrue);
          expect(units, hasLength(unitCount));
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
          expect(lessonTexts, hasLength(lessonCount));
          expect(testTexts, hasLength(testCount));
        });

        test('text lessons carry reading metadata for the library and the reading counter', () {
          for (final u in units) {
            for (final n in nodes(u).take(3)) {
              final r = n['reading'] as Map?;
              expect(r, isNotNull, reason: '${n['id']}');
              expect(['fen', 'saglik', 'sosyal'], contains(r!['field']), reason: '${n['id']}');
              expect(r['words'], isA<int>(), reason: '${n['id']}');
              expect(r['cefr'], isA<String>(), reason: '${n['id']}');
              for (final b in lists) {
                expect(r[b], isA<List>(), reason: '${n['id']} reading.$b');
              }
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
      },
    );
  }
}
