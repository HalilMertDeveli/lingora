// Cold-start measurement entry point (see tool/perf/README.md).
//
// Seeds an onboarded learner on the first run, then starts the real app, so
// every later cold start goes straight to the learning path:
//
//   flutter build apk --release -t tool/perf/startup_main.dart \
//     --dart-define=LINGORA_STARTUP_TRACE=true \
//     --dart-define=PERF_TRACK=yds --dart-define=PERF_DONE_UNITS=20
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

const _track = String.fromEnvironment('PERF_TRACK', defaultValue: 'tr_en');
const _doneUnits = int.fromEnvironment('PERF_DONE_UNITS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('progress_v1') == null) {
    final course = await loadExamPath(rootBundle, _track) ?? await loadCourse(rootBundle, _track);
    final done = {
      for (final u in course.units.take(_doneUnits))
        for (final n in u.nodes) n.id: 1,
    };
    await prefs.setString(
      'progress_v1',
      jsonEncode({'onboarded': true, 'trackId': _track, 'completed': done}),
    );
    debugPrint('PERF seeded $_track with ${done.length} finished steps');
  }
  await app.main();
}
