// Builds the course outlines in assets/course_index/ (see
// lib/data/course_index.dart): every course's units and steps without their
// exercises, dialogues and topic guides, so the learning path can be drawn
// at start-up without parsing the whole course.
//
//   dart run tool/build_course_index.dart          # writes the outlines
//   dart run tool/build_course_index.dart --check  # exit 1 when out of date
//
// Run it after changing anything in assets/courses/. test/course_index_test.dart
// fails while an outline is out of date.
import 'dart:convert';
import 'dart:io';

/// Bump when the outline shape changes (lib/data/course_index.dart reads it).
const indexFormat = 1;

const coursesDir = 'assets/courses';
const indexDir = 'assets/course_index';

void main(List<String> args) {
  final check = args.contains('--check');
  final stale = <String>[];
  final ids =
      Directory(coursesDir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.json'))
          .map((n) => n.substring(0, n.length - 5))
          .toList()
        ..sort();
  for (final id in ids) {
    final text = '${const JsonEncoder.withIndent(null).convert(buildIndex(id, readFile))}\n';
    final out = File('$indexDir/$id.json');
    // Line endings may differ on a Windows checkout (core.autocrlf).
    if (out.existsSync() && out.readAsStringSync().replaceAll('\r\n', '\n') == text) continue;
    stale.add(id);
    if (!check) {
      out
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
  }
  // Outlines of courses that no longer exist.
  final dir = Directory(indexDir);
  if (dir.existsSync()) {
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json') || ids.contains(name.substring(0, name.length - 5))) continue;
      stale.add(name);
      if (!check) f.deleteSync();
    }
  }
  if (check && stale.isNotEmpty) {
    stderr.writeln(
      'Ders özetleri eski: ${stale.join(', ')}. Çalıştır: dart run tool/build_course_index.dart',
    );
    exit(1);
  }
  stdout.writeln(stale.isEmpty ? 'Ders özetleri güncel.' : 'Güncellendi: ${stale.join(', ')}');
}

String? readFile(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : null;
}

/// Section files of course [id] (`assets/courses/<id>/*.json`), sorted.
List<String> sectionFiles(String id) {
  final dir = Directory('$coursesDir/$id');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => '$coursesDir/$id/${f.uri.pathSegments.last}')
      .where((p) => p.endsWith('.json'))
      .toList()
    ..sort();
}

/// The outline of course [id]: `{"format", "files", "course", "sections"}`.
/// "files" lists the asset paths it was made from; the app falls back to the
/// full course when its asset manifest lists other files.
/// [files] defaults to the section files on disk.
Map<String, Object?> buildIndex(String id, String? Function(String path) read, {List<String>? files}) {
  final mainPath = '$coursesDir/$id.json';
  files ??= sectionFiles(id);
  final sections = <Object?>[];
  for (final path in files) {
    final text = read(path);
    Object? json;
    try {
      json = text == null ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    // A broken file stays in the list as null: the app skips it, as it does
    // when it reads the course itself.
    sections.add(json is Map<String, dynamic> ? outlineFile(json) : null);
  }
  return {
    'format': indexFormat,
    'files': [mainPath, ...files],
    'course': outlineFile(jsonDecode(read(mainPath)!) as Map<String, dynamic>),
    'sections': sections,
  };
}

/// A course or section file without lesson content.
Map<String, Object?> outlineFile(Map<String, dynamic> file) => {
  for (final e in file.entries)
    e.key: e.key == 'units' && e.value is List ? [for (final u in e.value as List) outlineUnit(u)] : e.value,
};

Object? outlineUnit(Object? unit) {
  if (unit is! Map<String, dynamic>) return unit;
  final guide = unit['guide'];
  return {
    for (final e in unit.entries)
      if (e.key != 'guide')
        e.key: e.key == 'nodes' && e.value is List
            ? [for (final n in e.value as List) outlineNode(n)]
            : e.value,
    if (guide is String && guide.trim().isNotEmpty) 'hasGuide': true,
  };
}

Object? outlineNode(Object? node) {
  if (node is! Map<String, dynamic>) return node;
  return {
    for (final e in node.entries)
      if (e.key != 'exercises' && e.key != 'steps') e.key: e.value,
  };
}
