// YDS Faz 2 infrastructure (docs/sinav/yds-faz2-icerik.md): question types
// named in pack and bank questions, and full cards that take a bridge card's
// place keeping its progress key. Also checks the shipped content's qtype
// values and card ids, so content PRs fail early.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/review_queue.dart';

import 'study_test.dart' show readCourse;

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final yds = readCourse('exam_yds');

  test('a pack or bank question\'s own qtype comes first', () {
    final q = ExamQuestion.fromJson({
      'id': 'yds_m9_q41',
      'section': 'yds_vocab',
      'qtype': 'reading',
      'text': 'According to the passage ----.',
      'options': ['a', 'b', 'c', 'd', 'e'],
      'answer': 0,
      'explanation': 'x',
    });
    expect(examQuestionType(q), QType.reading);
    // Without it the section decides, as before.
    final old = ExamQuestion.fromJson({...q.toTestJson(), 'qtype': null});
    expect(examQuestionType(old), QType.vocabulary);
  });

  test('every qtype in the shipped content is a known type', () {
    final bad = <String>[];
    void check(String where, Object? qtype) {
      if (qtype != null && QType.byName(qtype as String) == null) bad.add('$where: $qtype');
    }

    for (final u in yds.units) {
      for (final n in u.nodes) {
        for (final ex in n.exercises) {
          check(n.id, ex.qtype);
        }
      }
    }
    for (final m in _json('assets/exam_packs/yds_full.json')['mocks'] as List) {
      for (final q in (m as Map)['questions'] as List) {
        check((q as Map)['id'] as String, q['qtype']);
      }
    }
    expect(bad, isEmpty, reason: bad.take(10).join('\n'));
  });

  test('a full card for a bridge word keeps the bridge key, however its id is written', () {
    final lesson = yds.allNodes.firstWhere((n) => n.vocab);
    final unit = yds.units.firstWhere((u) => u.nodes.contains(lesson));
    final (_, en) = lesson.exercises.firstWhere((e) => e.type == ExerciseType.match).pairs.first;
    final bridge = wordCardId(ydsWordPrefix, en);
    final full = VocabEntry.fromJson({
      'id': 'ydm_${en.toUpperCase().replaceAll(' ', '-')}',
      'word': en,
      'pos': 'noun',
      'topic': unit.id,
      'senses': [
        {'tr': 'zengin anlam', 'def': 'meaning'},
      ],
      'examples': [
        {'en': 'An example.', 'tr': 'Bir örnek.', 'context': 'akademik', 'target': en},
      ],
    });
    final p = Progress(completed: {lesson.id: 1}, wordBox: {bridge: 4});
    final cards = courseWordCards(yds, p, ydsCards: [full]);
    final card = cards.singleWhere((c) => c.en.toLowerCase() == en.toLowerCase());
    expect((card.id, card.tr), (bridge, 'zengin anlam'));
    expect(p.wordBox[card.id], 4, reason: 'progress carries over');
  });

  test('shipped yds.json: card ids are unique and ydm_ ids match their word', () {
    final entries = [
      for (final e in _json('assets/vocab/yds.json')['entries'] as List)
        VocabEntry.fromJson(e as Map<String, dynamic>),
    ];
    expect(entries.map((e) => e.id).toSet().length, entries.length);
    final off = [
      for (final e in entries)
        if (e.id.startsWith(ydsWordPrefix) && e.id != wordCardId(ydsWordPrefix, e.word))
          '${e.id} ≠ ${e.word}',
    ];
    expect(off, isEmpty, reason: off.take(10).join('\n'));
  });
}

extension on ExamQuestion {
  Map<String, Object?> toTestJson() => {
    'id': id,
    'section': section,
    'text': text,
    'options': options,
    'answer': answer,
    'explanation': explanation,
  };
}
