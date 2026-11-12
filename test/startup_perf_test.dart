// Start-up scaling: with three times today's content (every unit copied
// twice, tool/perf/triple_content.dart) the learning path still starts from a
// small outline, and the path builds only the sections that are open.
//
// Times here are debug-mode (JIT) numbers on the test machine, so the budgets
// are loose; they catch "the outline grew with the lesson content" or "the
// path builds every section" regressions. Release timings on a device:
// tool/perf/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/path_map.dart' show UnitBand;
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/build_course_index.dart' as index_tool;
import '../tool/perf/triple_content.dart';
import 'course_index_test.dart' show expectSameOutline;
import 'sections_test.dart' show FakeBundle;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

/// Course [id] with every file tripled, plus its outline, as a bundle.
({FakeBundle bundle, int contentBytes, int outlineBytes}) tripled(String id) {
  final paths = ['assets/courses/$id.json', ...index_tool.sectionFiles(id)];
  final files = {
    for (final p in paths)
      p: jsonEncode(tripleFile(jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>)),
  };
  final outline = jsonEncode(index_tool.buildIndex(id, (p) => files[p], files: paths.skip(1).toList()));
  return (
    bundle: FakeBundle({...files, 'assets/course_index/$id.json': outline}),
    contentBytes: files.values.fold(0, (sum, f) => sum + utf8.encode(f).length),
    outlineBytes: utf8.encode(outline).length,
  );
}

int _ms(Stopwatch s) => s.elapsedMilliseconds;

/// Unit bands in the path (not the pinned one on top).
final _bands = find.byWidgetPredicate((w) => w is UnitBand && !w.compact);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final id in ['tr_en', 'exam_yds']) {
    test('$id ×3: the outline stays small and fast, and matches the full course', () async {
      final fixture = tripled(id);
      final today = await loadCourseOutline(rootBundle, id);

      // Warm up the code paths once, then time.
      await loadCourseOutline(fixture.bundle, id);
      final outlineTime = Stopwatch()..start();
      final outline = await loadCourseOutline(fixture.bundle, id);
      outlineTime.stop();
      final fullTime = Stopwatch()..start();
      final full = await loadCourse(fixture.bundle, id);
      fullTime.stop();

      // ignore: avoid_print
      print(
        '$id ×3: ${full.units.length} ünite, içerik ${fixture.contentBytes ~/ 1024} KB, '
        'özet ${fixture.outlineBytes ~/ 1024} KB; özet ${_ms(outlineTime)} ms, tam kurs ${_ms(fullTime)} ms',
      );
      expect(outline, isNotNull);
      expect(full.units.length, today!.units.length * 3);
      expectSameOutline(outline!, full);
      // The outline holds no lesson content: a few percent of the course.
      expect(fixture.outlineBytes, lessThan(fixture.contentBytes ~/ 10));
      expect(_ms(outlineTime), lessThan(400));
    });
  }

  group('path ×3', () {
    late Course outline;
    setUpAll(() async {
      outline = (await loadCourseOutline(tripled('tr_en').bundle, 'tr_en'))!;
    });

    Future<int> pumpPath(WidgetTester tester, Progress p) async {
      SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(p.toJson())});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final clock = Stopwatch()..start();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            courseOutlineProvider.overrideWith((ref) async => outline),
            prefsProvider.overrideWithValue(prefs),
            speechProvider.overrideWithValue(FakeSpeech()),
            notificationServiceProvider.overrideWithValue(FakeNotifications()),
          ],
          child: const LingoraApp(),
        ),
      );
      await tester.pump();
      await tester.pump();
      clock.stop();
      return _ms(clock);
    }

    testWidgets('a new learner: only section 1 is built', (tester) async {
      final ms = await pumpPath(tester, const Progress(onboarded: true, remindersEnabled: false));
      final s1 = outline.sections.first.units.length;
      // ignore: avoid_print
      print('yol ×3, yeni öğrenci: ${_bands.evaluate().length} ünite bandı, $ms ms');
      expect(_bands, findsNWidgets(s1));
      expect(outline.units.length, greaterThan(s1 * 3));
    });

    testWidgets('a learner in section 4: the finished sections stay folded', (tester) async {
      final done = {
        for (final s in outline.sections.take(3))
          for (final n in s.nodes) n.id: 1,
      };
      final ms = await pumpPath(tester, Progress(onboarded: true, remindersEnabled: false, completed: done));
      final s4 = outline.sections[3].units.length;
      // ignore: avoid_print
      print('yol ×3, 4. bölüm: ${_bands.evaluate().length} ünite bandı, $ms ms');
      expect(_bands, findsNWidgets(s4));
    });
  });
}
