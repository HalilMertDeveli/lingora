// Course outlines (assets/course_index/, tool/build_course_index.dart): they
// must match the course files, or the path would be drawn from stale data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/build_course_index.dart' as index_tool;
import 'sections_test.dart' show FakeBundle;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

/// Course ids with a file in assets/courses/.
List<String> courseIds() =>
    Directory('assets/courses')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .map((n) => n.substring(0, n.length - 5))
        .toList()
      ..sort();

/// [outline] shows the same path as [full]: sections, units and steps with
/// everything the path draws, but no lesson content.
void expectSameOutline(Course outline, Course full) {
  expect(outline.outline, isTrue);
  expect(full.outline, isFalse);
  expect(outline.id, full.id);
  expect(outline.title, full.title);
  expect(outline.sections.map((s) => s.id), full.sections.map((s) => s.id));
  for (final (i, s) in full.sections.indexed) {
    final o = outline.sections[i];
    expect(
      [o.index, o.title, o.cefr, o.description, o.grammar, o.implicit],
      [s.index, s.title, s.cefr, s.description, s.grammar, s.implicit],
    );
  }
  expect(outline.units.length, full.units.length);
  for (final (i, u) in full.units.indexed) {
    final o = outline.units[i];
    expect(
      [o.id, o.title, o.description, o.color, o.theme, o.hasGuide],
      [u.id, u.title, u.description, u.color, u.theme, u.hasGuide],
      reason: u.id,
    );
    expect(o.guide, isNull, reason: u.id);
    expect(o.nodes.length, u.nodes.length, reason: u.id);
    for (final (j, n) in u.nodes.indexed) {
      final m = o.nodes[j];
      expect(
        [m.id, m.type, m.title, m.description, m.rewardXp, m.examId, m.size, m.minutes, m.packId, m.mockId],
        [n.id, n.type, n.title, n.description, n.rewardXp, n.examId, n.size, n.minutes, n.packId, n.mockId],
        reason: n.id,
      );
      expect(m.exercises, isEmpty, reason: n.id);
      expect(m.steps, isEmpty, reason: n.id);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every course has an up-to-date outline (dart run tool/build_course_index.dart)', () {
    for (final id in courseIds()) {
      final built = '${jsonEncode(index_tool.buildIndex(id, index_tool.readFile))}\n';
      final file = File('assets/course_index/$id.json');
      expect(file.existsSync(), isTrue, reason: 'assets/course_index/$id.json yok');
      expect(
        file.readAsStringSync().replaceAll('\r\n', '\n') == built,
        isTrue,
        reason: '$id özeti eski: dart run tool/build_course_index.dart',
      );
    }
  });

  for (final id in courseIds()) {
    test('$id: the shipped outline draws the same path as the full course', () async {
      final outline = await loadCourseOutline(rootBundle, id);
      expect(outline, isNotNull);
      expectSameOutline(outline!, await loadCourse(rootBundle, id));
    });
  }

  group('falls back to the full course', () {
    Map<String, String> files() => {
      'assets/courses/tr_en.json': File('assets/courses/tr_en.json').readAsStringSync(),
      'assets/course_index/tr_en.json': jsonEncode(
        index_tool.buildIndex('tr_en', index_tool.readFile, files: const []),
      ),
    };

    test('outline made from the same files is used', () async {
      final outline = await loadCourseOutline(FakeBundle(files()), 'tr_en');
      expect(outline?.sections.map((s) => s.id), ['s1']);
    });

    test('a section file the outline does not know about', () async {
      final bundle = FakeBundle(files(), extraManifest: ['assets/courses/tr_en/09_yeni.json']);
      expect(await loadCourseOutline(bundle, 'tr_en'), isNull);
    });

    test('no outline, or a broken one', () async {
      expect(
        await loadCourseOutline(FakeBundle(files()..remove('assets/course_index/tr_en.json')), 'tr_en'),
        isNull,
      );
      expect(
        await loadCourseOutline(
          FakeBundle(files()..['assets/course_index/tr_en.json'] = '{"format": 1'),
          'tr_en',
        ),
        isNull,
      );
      expect(
        await loadCourseOutline(
          FakeBundle(files()..['assets/course_index/tr_en.json'] = '{"format": 99, "files": []}'),
          'tr_en',
        ),
        isNull,
      );
    });
  });

  testWidgets('a step tapped on the outline path opens with its lessons', (tester) async {
    final main = File('assets/courses/tr_en.json').readAsStringSync();
    final full = Course.fromJson(jsonDecode(main) as Map<String, dynamic>);
    final outline = await tester.runAsync(
      () => loadCourseOutline(
        FakeBundle({
          'assets/courses/tr_en.json': main,
          'assets/course_index/tr_en.json': jsonEncode(
            index_tool.buildIndex('tr_en', index_tool.readFile, files: const []),
          ),
        }),
        'tr_en',
      ),
    );
    expect(outline!.allNodes.first.exercises, isEmpty);

    SharedPreferences.setMockInitialValues({'progress_v1': '{"onboarded": true}'});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courseProvider.overrideWith((ref) async => full),
          courseOutlineProvider.overrideWith((ref) async => outline),
          prefsProvider.overrideWithValue(prefs),
          speechProvider.overrideWithValue(FakeSpeech()),
          notificationServiceProvider.overrideWithValue(FakeNotifications()),
        ],
        child: const LingoraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selamlaşma'), findsOneWidget);
    await tester.tap(find.text('Hadi, bir çay daha!'));
    await tester.pumpAndSettle();
    expect(find.text('“merhaba” hangisi?'), findsOneWidget);
  });
}
