// Synthetic 3× content for start-up measurements (see tool/perf/README.md).
//
//   dart run tool/perf/triple_content.dart   # rewrites assets/courses in place
//   dart run tool/build_course_index.dart    # outlines for the tripled files
//   ... build and measure ...
//   git checkout -- assets/courses assets/course_index
//
// Every unit of every course file gets two copies right after the originals
// (ids suffixed "_x2", "_x3"), so each section, and so the path the learner
// sees, is three times as long. test/startup_perf_test.dart uses the same
// [tripleFile].
import 'dart:convert';
import 'dart:io';

/// [file] (a course or section file) with each unit list three times as long.
Map<String, dynamic> tripleFile(Map<String, dynamic> file) {
  final units = (file['units'] as List).cast<Map<String, dynamic>>();
  return {
    ...file,
    'units': [
      ...units,
      for (final copy in const ['_x2', '_x3'])
        for (final u in units) _copyUnit(u, copy),
    ],
  };
}

Map<String, dynamic> _copyUnit(Map<String, dynamic> unit, String suffix) => {
  ...unit,
  'id': '${unit['id']}$suffix',
  'nodes': [
    for (final n in (unit['nodes'] as List).cast<Map<String, dynamic>>()) {...n, 'id': '${n['id']}$suffix'},
  ],
};

void main() {
  for (final f in Directory('assets/courses').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    f.writeAsStringSync(jsonEncode(tripleFile(json)));
  }
  stdout.writeln('İçerik üç katına çıkarıldı (geri al: git checkout -- assets/courses assets/course_index).');
}
