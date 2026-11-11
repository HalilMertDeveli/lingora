// Course sections: loading section files, the lock rule, "Bölüme atla" and
// the placement test opening a section. Uses the fixture section in
// test/fixtures/tr_en/ (never shipped in the app).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

const _fixture = 'test/fixtures/tr_en/02_gunluk_hayat.json';

/// Serves [files] (asset key → file contents) plus a matching AssetManifest.bin.
class FakeBundle extends CachingAssetBundle {
  FakeBundle(this.files, {List<String> extraManifest = const []})
    : manifest = [...files.keys, ...extraManifest];
  final Map<String, String> files;
  final List<String> manifest;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final k in manifest)
          k: [
            {'asset': k},
          ],
      })!;
    }
    final text = files[key];
    if (text == null) throw FlutterError('Asset yok: $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

String _read(String path) => File(path).readAsStringSync();

Future<Course> _courseWithFixture() => loadCourse(
  FakeBundle({
    'assets/courses/tr_en.json': _read('assets/courses/tr_en.json'),
    'assets/courses/tr_en/02_gunluk_hayat.json': _read(_fixture),
  }),
  'tr_en',
);

Progress _done(Iterable<String> ids) => Progress(onboarded: true, completed: {for (final id in ids) id: 1});

void main() {
  group('loading', () {
    test('tr_en.json is section 1 "Temeller" with unchanged ids', () async {
      final course = await loadCourse(rootBundle, 'tr_en');
      final s1 = course.sections.first;
      expect((s1.id, s1.index, s1.title, s1.cefr, s1.implicit), ('s1', 1, 'Temeller', 'A1', false));
      expect(s1.grammar, isNotEmpty);
      expect(s1.units, hasLength(12));
      expect(course.units.first.nodes.first.id, 'u1l1');
      expect(s1.exam?.id, 'u12t');
      // The shipped folder holds no fixture.
      expect(course.sections.map((s) => s.title), isNot(contains(contains('örnek'))));
    });

    test('courses without section metadata get one hidden section', () async {
      final course = await loadCourse(rootBundle, 'pro_tourism');
      expect(course.sections, hasLength(1));
      expect(course.sections.single.implicit, isTrue);
      expect(course.sections.single.units, course.units);
    });

    test('section files are found in the manifest, sorted and merged', () async {
      final course = await _courseWithFixture();
      expect(course.sections.map((s) => s.id), ['s1', 's2']);
      expect(course.units, hasLength(13));
      expect(course.units.last.id, 's2u1');
      expect(course.allNodes.last.id, 's2u1c');
      expect(course.sections[1].grammar, contains('present simple'));
    });

    test('a missing, broken or clashing file is skipped, never fatal', () async {
      final fixture = jsonDecode(_read(_fixture)) as Map<String, dynamic>;
      final clash = jsonDecode(_read(_fixture)) as Map<String, dynamic>
        ..['section'] = {...fixture['section'] as Map, 'id': 's9', 'index': 9};
      final course = await loadCourse(
        FakeBundle(
          {
            'assets/courses/tr_en.json': _read('assets/courses/tr_en.json'),
            'assets/courses/tr_en/02_gunluk_hayat.json': _read(_fixture),
            'assets/courses/tr_en/03_bozuk.json': '{"section": {"id": "s3", ',
            'assets/courses/tr_en/04_bos.json':
                '{"section": {"id": "s4", "index": 4, "title": "x"}, "units": []}',
            'assets/courses/tr_en/09_tekrar.json': jsonEncode(clash),
          },
          extraManifest: ['assets/courses/tr_en/05_yok.json'],
        ),
        'tr_en',
      );
      expect(course.sections.map((s) => s.id), ['s1', 's2']);
    });

    test('no asset manifest means no extra sections', () async {
      final course = await loadCourse(_NoManifest(_read('assets/courses/tr_en.json')), 'tr_en');
      expect(course.sections.map((s) => s.id), ['s1']);
    });
  });

  group('lock rule', () {
    late Course course;
    late Section s1, s2;
    setUp(() async {
      course = await _courseWithFixture();
      (s1, s2) = (course.sections[0], course.sections[1]);
    });

    test('section 2 opens when section 1\'s exam is passed', () {
      const fresh = Progress(onboarded: true);
      expect(sectionOpen(course, s1, fresh), isTrue);
      expect(sectionOpen(course, s2, fresh), isFalse);
      expect(activeNodes(course, fresh).keys, ['s1']);
      expect(currentNode(course, fresh)?.id, 'u1l1');

      final passed = _done([for (final n in s1.nodes.take(s1.nodes.length - 1)) n.id]);
      expect(passed.isDone('u12t'), isTrue);
      expect(sectionOpen(course, s2, passed), isTrue);
      // The chest of section 1 is still to open; the path focuses section 2.
      expect(activeNodes(course, passed).map((k, n) => MapEntry(k, n.id)), {'s1': 'u12c', 's2': 's2u1l1'});
      expect(currentNode(course, passed)?.id, 's2u1l1');
    });

    test('"Bölüme atla" or the placement test open a section and those before it', () {
      final skipped = _done([sectionPassId(2)]);
      expect(sectionOpen(course, s2, skipped), isTrue);
      expect(currentNode(course, skipped)?.id, 's2u1l1');
      expect(activeNodes(course, skipped)['s1']?.id, 'u1l1', reason: 'earlier lessons stay playable');
      // A key for a section that is not shipped yet opens everything up to it.
      expect(sectionOpen(course, s2, _done([sectionPassId(5)])), isTrue);
    });

    test('progress share per section', () {
      expect(sectionProgress(s2, const Progress()), 0);
      expect(sectionProgress(s2, _done(['s2u1l1'])), closeTo(1 / 7, 1e-9));
      expect(sectionProgress(s2, _done(s2.nodes.map((n) => n.id))), 1);
    });

    test('the skip exam has 15 mixed questions from the section, no speaking', () {
      final items = sectionSkipItems(s2, Random(3));
      expect(items, hasLength(sectionSkipSize));
      expect(items.map((i) => i.key).toSet(), hasLength(sectionSkipSize));
      expect(items.every((i) => i.key.startsWith('s2u1l')), isTrue);
      expect(items.any((i) => i.ex.type == ExerciseType.speak), isFalse);
      // Every lesson is represented.
      expect({for (final i in items) i.key.split('#').first}, hasLength(4));
    });
  });

  group('placement', () {
    List<String> idsFor(Cefr? level) => recommend(
      level: level,
      reason: LearnReason.general,
      courseUnits: const [],
      lessons: const [],
    ).knownNodeIds;

    test('A2 opens section 3, B1 section 5, B2 section 7', () {
      expect(placementSection(null), isNull);
      expect(placementSection(Cefr.a1), isNull);
      expect(placementSection(Cefr.a2), 3);
      expect(placementSection(Cefr.b1), 5);
      expect(placementSection(Cefr.b2), 7);
      expect(idsFor(Cefr.a2), contains('section_s3'));
      expect(idsFor(Cefr.b1), contains('section_s5'));
      expect(idsFor(Cefr.b2), contains('section_s7'));
      expect(idsFor(Cefr.a1).where((id) => id.startsWith('section_')), isEmpty);
    });

    test('the plan names the section only when it is shipped', () {
      PlacementRecommendation rec(int count) => recommend(
        level: Cefr.b1,
        reason: LearnReason.general,
        courseUnits: const [],
        lessons: const [],
        sectionCount: count,
      );
      expect(rec(1).openSection, isNull);
      expect(rec(2).openSection, 2);
      expect(rec(8).openSection, 5);
    });

    test('applying an A2 result opens section 2 of the fixture course', () async {
      final course = await _courseWithFixture();
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(await _prefs({}))]);
      addTearDown(c.dispose);
      applyPlacement(
        c.read(progressProvider.notifier),
        recommend(level: Cefr.a2, reason: LearnReason.general, courseUnits: const [], lessons: const []),
      );
      expect(sectionOpen(course, course.sections[1], c.read(progressProvider)), isTrue);
    });
  });

  group('path screen', () {
    Future<void> pump(WidgetTester tester, Course course, Progress p) async {
      SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(p.toJson())});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            courseProvider.overrideWith((ref) async => course),
            prefsProvider.overrideWithValue(prefs),
            speechProvider.overrideWithValue(FakeSpeech()),
            notificationServiceProvider.overrideWithValue(FakeNotifications()),
          ],
          child: const LingoraApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    const fresh = Progress(onboarded: true, remindersEnabled: false);

    testWidgets('section header, summary and the skip exam', (tester) async {
      final course = await tester.runAsync(_courseWithFixture);
      await pump(tester, course!, fresh);
      expect(find.text('Bölüm 1 · A1 · Temeller'), findsOneWidget);

      final header = find.byKey(const Key('section-s2'));
      await tester.scrollUntilVisible(header, 600, scrollable: find.byType(Scrollable).first);
      expect(find.text('Bölüm 2 · A1 · Günlük hayat'), findsOneWidget);
      expect(find.descendant(of: header, matching: find.text('Kilitli')), findsOneWidget);

      await tester.tap(header);
      await tester.pumpAndSettle();
      final summary = find.byKey(const Key('section-summary-s2'));
      expect(summary, findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('1 ünite · 0 / 4 ders')), findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('present simple')), findsOneWidget);

      await tester.tap(find.byKey(const Key('section-skip')));
      await tester.pumpAndSettle();
      expect(find.text('BÖLÜME ATLA'), findsOneWidget);
      // Nothing is recorded until the exam is passed.
      final container = ProviderScope.containerOf(tester.element(find.text('BÖLÜME ATLA')));
      expect(container.read(progressProvider).completed, isEmpty);
    });

    testWidgets('a skipped-to section is open and its first lesson is current', (tester) async {
      final course = await tester.runAsync(_courseWithFixture);
      await pump(tester, course!, fresh.copyWith(completed: {sectionPassId(2): 1}));
      final header = find.byKey(const Key('section-s2'));
      await tester.scrollUntilVisible(header, 600, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: header, matching: find.text('%0')), findsOneWidget);
      // Two open sections: two playable steps.
      expect(find.text(sentenceCaseStart), findsNWidgets(2));
    });

    testWidgets('a locked section starts folded and unfolds on request', (tester) async {
      final course = await tester.runAsync(_courseWithFixture);
      await pump(tester, course!, fresh);
      final toggle = find.byKey(const ValueKey('section-toggle-s2'));
      await tester.scrollUntilVisible(toggle, 600, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('s2u1l1')), findsNothing);
      expect(find.text('1 üniteye göz at'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s2u1l1')), findsOneWidget);
      expect(find.text('Üniteleri gizle'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s2u1l1')), findsNothing);
    });

    testWidgets('an open section is unfolded without a toggle', (tester) async {
      final course = await tester.runAsync(_courseWithFixture);
      await pump(tester, course!, fresh.copyWith(completed: {sectionPassId(2): 1}));
      expect(find.byKey(const ValueKey('section-toggle-s2')), findsNothing);
      // s2u1l1 is the current node (it carries the focus key, not its id).
      expect(find.text('Sabah rutini', skipOffstage: false), findsWidgets);
    });

    testWidgets('a locked section explains how to open it', (tester) async {
      final course = await tester.runAsync(_courseWithFixture);
      await pump(tester, course!, fresh);
      final toggle = find.byKey(const ValueKey('section-toggle-s2'));
      await tester.scrollUntilVisible(toggle, 600, scrollable: find.byType(Scrollable).first);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final lesson = find.descendant(
        of: find.byKey(const ValueKey('s2u1l1')),
        matching: find.text('Sabah rutini'),
      );
      await tester.scrollUntilVisible(lesson, 600, scrollable: find.byType(Scrollable).first);
      // Move it clear of the pinned unit band at the top.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
      await tester.pumpAndSettle();
      await tester.tap(lesson);
      await tester.pump();
      expect(find.textContaining('Bu bölüm kilitli'), findsOneWidget);
    });
  });
}

/// "BAŞLA" in adult mode.
const sentenceCaseStart = 'Başla';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

class _NoManifest extends CachingAssetBundle {
  _NoManifest(this.base);
  final String base;
  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/courses/tr_en.json') return ByteData.sublistView(utf8.encode(base));
    throw FlutterError('Asset yok: $key');
  }
}
