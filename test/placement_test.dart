import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/grammar_lesson.dart';
import 'package:lingora/screens/grammar_path_screen.dart' show lessonNodeId;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final bank = parsePlacementBank(File('assets/placement/questions.json').readAsStringSync());
  final course = Course.fromJson(
    jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final units = [
    for (final u in course.units) [for (final n in u.nodes) n.id],
  ];
  final lessons = [
    for (final l in jsonDecode(File('assets/notes/lessons.json').readAsStringSync()) as List)
      GrammarLesson.fromJson(l as Map<String, dynamic>),
  ];

  /// Runs a whole test, answering right when [knows] says so.
  PlacementSession run(bool Function(PlacementQuestion q) knows) {
    final s = PlacementSession(bank);
    while (!s.isFinished) {
      final q = s.current!;
      s.answer(knows(q) ? q.answer : (q.answer + 1) % q.choices.length);
    }
    return s;
  }

  group('placement content', () {
    test('about 45 valid, original-looking questions', () {
      expect(bank.length, inInclusiveRange(40, 60));
      expect(bank.map((q) => q.id).toSet().length, bank.length);
      for (final q in bank) {
        expect(q.choices.length, 4, reason: q.id);
        expect(q.choices.toSet().length, 4, reason: q.id);
        expect(q.answer, inInclusiveRange(0, 3), reason: q.id);
        expect(q.prompt.trim(), isNotEmpty, reason: q.id);
        expect(q.explanation.length, greaterThan(20), reason: q.id);
        expect(q.id.startsWith(q.level.code.toLowerCase()), isTrue, reason: q.id);
        if (q.skill == PlacementSkill.reading) expect(q.passage, isNotNull, reason: q.id);
      }
    });

    test('every level has every skill, enough for a full test', () {
      for (final level in Cefr.values) {
        final at = bank.where((q) => q.level == level).toList();
        expect(at.length, greaterThanOrEqualTo(8), reason: level.code);
        for (final skill in PlacementSkill.values) {
          expect(at.where((q) => q.skill == skill).length, greaterThanOrEqualTo(2), reason: '$level $skill');
        }
      }
    });

    test('answers are spread over all positions', () {
      final positions = {for (final q in bank) q.answer};
      expect(positions, {0, 1, 2, 3});
    });
  });

  group('adaptive steps', () {
    test('starts at A2, goes up when right and down when wrong', () {
      final s = PlacementSession(bank);
      expect(s.current!.level, Cefr.a2);
      s.answer(s.current!.answer);
      expect(s.current!.level, Cefr.b1);
      s.answer(s.current!.answer);
      expect(s.current!.level, Cefr.b2);
      s.answer(-1);
      expect(s.current!.level, Cefr.b1);
      s.answer(-1);
      s.answer(-1);
      expect(s.current!.level, Cefr.a1);
      s.answer(-1);
      expect(s.current!.level, Cefr.a1, reason: 'stays at the floor');
    });

    test('never repeats a question and rotates skills', () {
      final s = run((q) => q.level.index <= Cefr.b1.index);
      final ids = s.answers.map((a) => a.$1.id).toList();
      expect(ids.toSet().length, ids.length);
      for (var i = 1; i < s.answers.length; i++) {
        if (s.answers[i].$1.level == s.answers[i - 1].$1.level) {
          expect(s.answers[i].$1.skill, isNot(s.answers[i - 1].$1.skill));
        }
      }
    });

    test('length stays within 12–14 and settles early at the edges', () {
      final top = run((_) => true);
      expect(top.answers.length, placementMinQuestions);
      expect(top.answers.last.$1.level, Cefr.c1);
      final bottom = run((_) => false);
      expect(bottom.answers.length, inInclusiveRange(placementMinQuestions, placementMaxQuestions));
      final middle = run((q) => q.level.index <= Cefr.a2.index);
      expect(middle.answers.length, inInclusiveRange(placementMinQuestions, placementMaxQuestions));
      expect(() => middle.answer(0), throwsStateError);
    });

    test('estimates the level a simulated learner really has', () {
      expect(run((_) => true).estimate, Cefr.c1);
      expect(run((_) => false).estimate, isNull);
      for (final level in Cefr.values) {
        expect(run((q) => q.level.index <= level.index).estimate, level, reason: level.code);
      }
    });
  });

  group('level estimate edges', () {
    test('needs two right answers and a 60% hit rate', () {
      expect(estimateLevel(const []), isNull);
      expect(estimateLevel(const [(Cefr.c1, true)]), isNull);
      expect(estimateLevel(const [(Cefr.b1, true), (Cefr.b1, true), (Cefr.b1, false)]), Cefr.b1);
      expect(
        estimateLevel(const [(Cefr.b2, true), (Cefr.b2, true), (Cefr.b2, false), (Cefr.b2, false)]),
        isNull,
        reason: '50% is not enough',
      );
      expect(
        estimateLevel(const [
          (Cefr.a2, true),
          (Cefr.a2, true),
          (Cefr.b1, true),
          (Cefr.b1, true),
          (Cefr.b1, true),
          (Cefr.b1, false),
          (Cefr.b1, false),
        ]),
        Cefr.b1,
        reason: 'exactly 60% passes',
      );
      expect(
        estimateLevel(const [(Cefr.a1, true), (Cefr.a1, true), (Cefr.c1, true), (Cefr.c1, false)]),
        Cefr.a1,
      );
    });
  });

  group('recommendation', () {
    PlacementRecommendation rec(Cefr? level, LearnReason reason) =>
        recommend(level: level, reason: reason, courseUnits: units, lessons: lessons);

    test('track follows the reason, with basics first for beginners', () {
      expect(rec(null, LearnReason.school).trackId, 'lgs');
      expect(rec(Cefr.b2, LearnReason.school).trackId, 'lgs');
      expect(rec(Cefr.a1, LearnReason.academic).trackId, defaultTrackId);
      expect(rec(Cefr.a1, LearnReason.academic).nextTrackId, 'yds');
      expect(rec(Cefr.a2, LearnReason.academic).trackId, 'yds');
      expect(rec(null, LearnReason.work).trackId, defaultTrackId);
      expect(rec(Cefr.b1, LearnReason.work).trackId, 'pro_interview');
      expect(rec(Cefr.a2, LearnReason.tourism).trackId, 'pro_tourism');
      expect(rec(null, LearnReason.tourism).nextTrackId, 'pro_tourism');
      expect(rec(Cefr.a2, LearnReason.general).trackId, defaultTrackId);
      expect(rec(Cefr.b1, LearnReason.general).trackId, notesTrack.id);
      for (final r in LearnReason.values) {
        for (final l in [null, ...Cefr.values]) {
          final p = rec(l, r);
          expect(allTracks.map((t) => t.id), contains(p.trackId));
          if (p.nextTrackId != null) expect(allTracks.map((t) => t.id), contains(p.nextTrackId));
        }
      }
    });

    test('beginners skip nothing', () {
      final p = rec(null, LearnReason.general);
      expect(p.knownNodeIds, isEmpty);
      expect(p.knownUnits, 0);
      expect(p.knownLessons, 0);
    });

    test('known units and lessons grow with the level', () {
      final a1 = rec(Cefr.a1, LearnReason.general);
      expect(a1.knownUnits, 4);
      expect(a1.knownLessons, 0);
      expect(a1.knownNodeIds, containsAll(['u1l1', 'u4c']));
      expect(a1.knownNodeIds, isNot(contains('u5l1')));

      final a2 = rec(Cefr.a2, LearnReason.general);
      expect(a2.knownUnits, 9);
      expect(a2.knownNodeIds, isNot(contains('u10l1')), reason: 'A2 keeps the last units');
      final a1Lessons = lessons.where((l) => l.level == 'A1' && l.unit.startsWith('A1'));
      expect(a2.knownLessons, a1Lessons.length);
      expect(a2.knownNodeIds, containsAll(a1Lessons.map(lessonNodeId)));

      final c1 = rec(Cefr.c1, LearnReason.academic);
      expect(c1.knownUnits, course.units.length);
      expect(c1.knownNodeIds, contains('gl_past_modals'));
      expect(c1.knownNodeIds, isNot(contains('gl_inversion')), reason: 'C1 lessons stay open');
      expect(c1.knownNodeIds, isNot(contains('gl_translation_table')), reason: 'workshops are kept');
      expect(c1.knownNodeIds.toSet().length, c1.knownNodeIds.length);
    });

    test('grammar node ids match the grammar path', () {
      for (final l in lessons) {
        expect(grammarNodeId(l), lessonNodeId(l));
      }
    });

    test('level summaries are written for every outcome', () {
      for (final l in [null, ...Cefr.values]) {
        expect(levelSummary(l), isNotEmpty);
      }
    });
  });

  group('applying', () {
    Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 10, 12)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('sets the track and marks nodes known without XP or streak', () async {
      final c = await container({'progress_v1': '{"onboarded": true, "completed": {"u1l1": 3}}'});
      final plan = recommend(
        level: Cefr.a2,
        reason: LearnReason.academic,
        courseUnits: units,
        lessons: lessons,
      );
      applyPlacement(c.read(progressProvider.notifier), plan);
      final p = c.read(progressProvider);
      expect(p.trackId, 'yds');
      expect(p.isDone('u9c'), isTrue);
      expect(p.isDone('u10l1'), isFalse);
      expect(p.isDone('gl_to_be_present'), isTrue);
      expect(p.completed['u1l1'], 3, reason: 'existing counts are kept');
      expect(p.totalXp, 0);
      expect(p.streak, 0);
      expect(p.lessonsDone, 0);
    });

    test('remembers the last result', () async {
      final c = await container();
      expect(c.read(placementProvider), isNull);
      c.read(placementProvider.notifier).save(Cefr.b1, LearnReason.work);
      final prefs = await SharedPreferences.getInstance();
      final again = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(again.dispose);
      final record = again.read(placementProvider)!;
      expect(record.level, Cefr.b1);
      expect(record.reason, LearnReason.work);
      expect(record.day, '2026-11-10');
    });
  });
}
