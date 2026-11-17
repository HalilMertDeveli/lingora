// Leveled units of the professional courses: Yazılımcı Dersleri (pro_dev),
// İş Görüşmesi (i5–i10) and Turizm (t6–t11). Each unit runs from A2 to B2
// and has three lessons, a story, a listening piece and a topic guide with
// its patterns and "Biz nasıl söylüyoruz?". The grammar path is untouched. Full content rules: tool/content/check_pro.mjs.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/voice_key.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/listening.dart';
import 'package:lingora/models/course.dart';

import 'widget_test.dart' show pumpApp;

const _newUnits = {
  'pro_dev': ['y1', 'y2', 'y3', 'y4', 'y5', 'y6', 'y7'],
  'pro_interview': ['i5', 'i6', 'i7', 'i8', 'i9', 'i10'],
  'pro_tourism': ['t6', 't7', 't8', 't9', 't10', 't11'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Yazılımcı Dersleri is a course track with the MESLEK badge', () {
    final t = trackById('pro_dev');
    expect(t.id, 'pro_dev');
    expect(t.kind, TrackKind.course);
    expect(t.badge, 'MESLEK');
    expect(courseCatalog.map((t) => t.id), contains('pro_dev'));
  });

  for (final MapEntry(key: id, value: unitIds) in _newUnits.entries) {
    group(id, () {
      late Course course;
      setUpAll(() async => course = await loadCourse(rootBundle, id));

      test('the new units are on the path, in order, after the old ones', () {
        final ids = course.units.map((u) => u.id).toList();
        expect(ids.sublist(ids.length - unitIds.length), unitIds);
        expect(course.sections.single.implicit, isTrue);
      });

      test('levels climb from A2 to B2', () {
        const order = ['A2', 'B1', 'B2'];
        final levels = [
          for (final u in course.units.where((u) => unitIds.contains(u.id)))
            u.nodes.singleWhere((n) => n.type == NodeType.listening).listening!.cefr,
        ];
        expect(levels.first, 'A2');
        expect(levels.last, 'B2');
        for (var i = 1; i < levels.length; i++) {
          expect(
            order.indexOf(levels[i]),
            greaterThanOrEqualTo(order.indexOf(levels[i - 1])),
            reason: '$levels',
          );
        }
      });

      test('each unit: three lessons, a story, a listening piece before the test, a guide', () {
        for (final u in course.units.where((u) => unitIds.contains(u.id))) {
          expect(u.nodes.map((n) => n.type), [
            NodeType.lesson,
            NodeType.lesson,
            NodeType.story,
            NodeType.lesson,
            NodeType.listening,
            NodeType.test,
            NodeType.chest,
          ], reason: u.id);
          expect(u.hasGuide, isTrue, reason: u.id);
          expect(u.guide, contains('Biz nasıl söylüyoruz?'), reason: u.id);
          for (final h in ['## Kalıplar', '## Sık yapılan hatalar', '## İpucu']) {
            expect(u.guide, contains(h), reason: u.id);
          }
          for (final n in u.nodes.where((n) => n.type == NodeType.lesson)) {
            expect(n.exercises.length, inInclusiveRange(8, 10), reason: n.id);
          }
        }
      });

      test('story voices match the speakers: every avatar picks a voice, the same one each time', () {
        for (final u in course.units.where((u) => unitIds.contains(u.id))) {
          final story = u.nodes.singleWhere((n) => n.type == NodeType.story);
          final voices = <String, Voice>{};
          for (final s in story.steps.where((s) => s.speaker != null)) {
            final v = voiceForAvatar(s.avatar);
            expect(v, isNotNull, reason: '${story.id} ${s.speaker} ${s.avatar}');
            expect(voices.putIfAbsent(s.speaker!, () => v!), v, reason: '${story.id} ${s.speaker}');
          }
        }
      });

      test('listening pieces follow the rules of their level', () {
        for (final u in course.units.where((u) => unitIds.contains(u.id))) {
          final p = u.nodes.singleWhere((n) => n.type == NodeType.listening).listening!;
          final r = ListeningRules.of(p.cefr);
          expect(p.lines.length, inInclusiveRange(r.minLines, r.maxLines), reason: u.id);
          expect(dialogueWords(p), inInclusiveRange(r.minWords, r.maxWords), reason: u.id);
          expect(p.questions.length, inInclusiveRange(r.minQuestions, r.maxQuestions), reason: u.id);
          expect(p.speakers.map((s) => s.female).toSet(), {true, false}, reason: u.id);
          for (final s in p.speakers) {
            expect(voiceForAvatar(s.avatar) == Voice.matilda, s.female, reason: '${u.id} ${s.name}');
          }
          for (final q in p.questions) {
            expect(q.choices, contains(q.answer), reason: '${u.id} ${q.prompt}');
            if (q.kind != ListeningQuestionKind.who) {
              expect(p.lines[q.line!].text.toLowerCase(), contains(q.key!.toLowerCase()), reason: u.id);
            }
          }
          if (r.needsInference) {
            expect(p.idioms, isNotEmpty, reason: u.id);
            expect(
              p.questions.any((q) => q.skill == 'inference' || q.skill == 'attitude'),
              isTrue,
              reason: u.id,
            );
          }
        }
      });
    });
  }

  test('the Yazılımcı Dersleri outline draws its units without the lessons', () async {
    final outline = await loadCourseOutline(rootBundle, 'pro_dev');
    expect(outline, isNotNull);
    expect(outline!.units.map((u) => u.id), _newUnits['pro_dev']);
    expect(outline.units.every((u) => u.hasGuide), isTrue);
  });

  testWidgets('the top bar names the Yazılımcı Dersleri track', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboarded": true, "trackId": "pro_dev"}'});
    expect(find.text('Yazılımcı Dersleri'), findsWidgets);
  });
}
