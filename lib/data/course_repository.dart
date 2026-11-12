import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/startup_trace.dart';
import '../models/course.dart';
import '../models/exam.dart';
import 'catalog.dart';
import 'progress.dart';

/// Loads `assets/courses/<id>.json` plus its section files,
/// `assets/courses/<id>/NN_slug.json`, in file-name order (see
/// [assembleSections]).
///
/// The files are only read here; decoding and building the course run in a
/// background isolate, so even a very big course never holds up a frame.
Future<Course> loadCourse(AssetBundle bundle, String id) async {
  final main = await bundle.load('assets/courses/$id.json');
  final paths = await sectionPaths(bundle, id);
  final files = await Future.wait(paths.map((p) => _loadOrNull(bundle, p)));
  final course = await compute(_parseCourse, (main: main, paths: paths, files: files));
  StartupTrace.mark('course_full');
  return course;
}

/// Every section of course [id]: [after]'s sections followed by the section
/// files (see [assembleSections]). Parsed in a background isolate.
Future<List<Section>> loadSections(AssetBundle bundle, String id, {Course? after}) async {
  final paths = await sectionPaths(bundle, id);
  final files = await Future.wait(paths.map((p) => _loadOrNull(bundle, p)));
  return compute(_parseSections, (paths: paths, files: files, after: after));
}

/// The learning path's outline of course [id], from
/// `assets/course_index/<id>.json` (made by tool/build_course_index.dart):
/// every section, unit and step, without exercises, dialogues and topic
/// guides. A few percent of the course, so the path can be drawn right away
/// however long the course grows.
///
/// Null when there is no outline, it cannot be read, or it was made from
/// other files than the asset manifest lists: then use [loadCourse].
Future<Course?> loadCourseOutline(AssetBundle bundle, String id) async {
  try {
    final assets = (await AssetManifest.loadFromAssetBundle(bundle)).listAssets();
    StartupTrace.mark('asset_manifest');
    final indexPath = 'assets/course_index/$id.json';
    if (!assets.contains(indexPath)) return null;
    final paths = _sectionPathsIn(assets, id);
    final index = _decode(await bundle.load(indexPath)) as Map<String, dynamic>;
    if (index['format'] != outlineFormat ||
        !listEquals((index['files'] as List).cast<String>(), ['assets/courses/$id.json', ...paths])) {
      debugPrint('Ders özeti eski ($id): dart run tool/build_course_index.dart');
      return null;
    }
    final course = Course.fromJson(index['course'] as Map<String, dynamic>);
    final sections = index['sections'] as List;
    return _withSections(
      course,
      assembleSections([
        for (final (i, path) in paths.indexed)
          (path: path, json: () => sections[i] ?? (throw const FormatException('okunamadı'))),
      ], after: course),
      outline: true,
    );
  } catch (e) {
    debugPrint('Ders özeti okunamadı ($id): $e');
    return null;
  }
}

/// Outline file format written by tool/build_course_index.dart.
const outlineFormat = 1;

/// Asset paths of the section files of course [id], sorted by file name;
/// empty when the asset manifest cannot be read.
Future<List<String>> sectionPaths(AssetBundle bundle, String id) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    StartupTrace.mark('asset_manifest');
    return _sectionPathsIn(manifest.listAssets(), id);
  } catch (e) {
    debugPrint('Bölümler bulunamadı ($id): $e');
    return const [];
  }
}

List<String> _sectionPathsIn(List<String> assets, String id) {
  final prefix = 'assets/courses/$id/';
  return assets.where((p) => p.startsWith(prefix) && p.endsWith('.json')).toList()..sort();
}

Future<ByteData?> _loadOrNull(AssetBundle bundle, String path) async {
  try {
    return await bundle.load(path);
  } catch (e) {
    debugPrint('Bölüm atlandı ($path): $e');
    return null;
  }
}

Object? _decode(ByteData data) =>
    jsonDecode(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));

Iterable<({String path, Object? Function() json})> _sectionFiles(List<String> paths, List<ByteData?> files) =>
    [
      for (final (i, path) in paths.indexed)
        (path: path, json: () => _decode(files[i] ?? (throw const FormatException('okunamadı')))),
    ];

Course _parseCourse(({ByteData main, List<String> paths, List<ByteData?> files}) a) {
  final course = Course.fromJson(_decode(a.main) as Map<String, dynamic>);
  return _withSections(course, assembleSections(_sectionFiles(a.paths, a.files), after: course));
}

List<Section> _parseSections(({List<String> paths, List<ByteData?> files, Course? after}) a) =>
    assembleSections(_sectionFiles(a.paths, a.files), after: a.after);

/// [course] with [sections] (all of them, see [assembleSections]).
Course _withSections(Course course, List<Section> sections, {bool outline = false}) =>
    listEquals(sections, course.sections) && outline == course.outline
    ? course
    : Course(
        id: course.id,
        title: course.title,
        fromLang: course.fromLang,
        learningLang: course.learningLang,
        sections: sections,
        outline: outline,
      );

/// Every section of the course: the sections of [after] (the course file)
/// followed by [files], the section files in file-name order.
///
/// A file `NN_slug.json` is a new section. A file `NNx_slug.json` with
/// `{"extends": "sN", "units": [...]}` appends units to the end of section sN,
/// which must come earlier (it sorts after `NN_slug.json`); the section exam
/// stays the last test of sN's own file (see [Section.extendedWith]).
///
/// A missing, unreadable or broken file (bad JSON, wrong shape, an id already
/// used earlier in the path, an unknown section to extend) is skipped and
/// logged, never fatal. [json] throws for a file that could not be read.
List<Section> assembleSections(Iterable<({String path, Object? Function() json})> files, {Course? after}) {
  final sections = <Section>[...?after?.sections];
  final unitIds = <String>{...?after?.units.map((u) => u.id)};
  final nodeIds = <String>{...?after?.allNodes.map((n) => n.id)};
  final sectionIds = <String>{...?after?.sections.map((s) => s.id)};
  for (final file in files) {
    try {
      final json = file.json() as Map<String, dynamic>;
      final target = json['extends'] as String?;
      final List<Unit> fileUnits;
      Section? section;
      var at = -1;
      if (target != null) {
        at = sections.indexWhere((s) => s.id == target);
        if (at < 0) throw FormatException('genişletilecek bölüm yok: $target');
        fileUnits = (json['units'] as List).map((u) => Unit.fromJson(u as Map<String, dynamic>)).toList();
      } else {
        section = Section.fromFile(json);
        if (sectionIds.contains(section.id)) throw FormatException('tekrarlanan id: ${section.id}');
        fileUnits = section.units;
      }
      final units = fileUnits.map((u) => u.id);
      final nodes = [for (final u in fileUnits) ...u.nodes.map((n) => n.id)];
      final clash = [...units.where(unitIds.contains), ...nodes.where(nodeIds.contains)];
      if (fileUnits.isEmpty) throw const FormatException('ünite yok');
      if (clash.isNotEmpty) throw FormatException('tekrarlanan id: ${clash.take(5).join(', ')}');
      if (units.toSet().length != units.length || nodes.toSet().length != nodes.length) {
        throw const FormatException('dosya içinde tekrarlanan id');
      }
      unitIds.addAll(units);
      nodeIds.addAll(nodes);
      if (section != null) {
        sectionIds.add(section.id);
        sections.add(section);
      } else {
        sections[at] = sections[at].extendedWith(fileUnits);
      }
    } catch (e) {
      debugPrint('Bölüm atlandı (${file.path}): $e');
    }
  }
  return sections;
}

/// Whether exam track [examTrackId] ships a study path. Asks the asset
/// manifest only, so it costs nothing at start-up.
Future<bool> hasExamPath(AssetBundle bundle, String examTrackId) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets().contains('assets/courses/${examPathId(examTrackId)}.json');
  } catch (e) {
    debugPrint('Sınav yolu yok ($examTrackId): $e');
    return false;
  }
}

/// The study path of exam track [examTrackId] (LGS → `exam_lgs`), or null
/// when it is not shipped (yet) or cannot be read: the exam track then shows
/// its question bank home as before.
Future<Course?> loadExamPath(AssetBundle bundle, String examTrackId) async {
  try {
    // Ask the manifest first: a missing file is the normal case, not an error.
    if (!await hasExamPath(bundle, examTrackId)) return null;
    return await loadCourse(bundle, examPathId(examTrackId));
  } catch (e) {
    debugPrint('Sınav yolu yok ($examTrackId): $e');
    return null;
  }
}

Future<Exam> loadExam(AssetBundle bundle, String id) async {
  final raw = await bundle.loadString('assets/exams/$id.json');
  return Exam.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// The selected track, falling back to the general course for unknown ids.
final trackProvider = Provider<Track>(
  (ref) => trackById(ref.watch(progressProvider.select((p) => p.trackId))),
);

/// Study path of an exam track by track id; null without one.
final examPathProvider = FutureProvider.family<Course?, String>((ref, id) => loadExamPath(rootBundle, id));

/// Whether an exam track has a study path (see [hasExamPath]).
final hasExamPathProvider = FutureProvider.family<bool, String>((ref, id) => hasExamPath(rootBundle, id));

/// Course for the learning path: the selected course, an exam track's study
/// path (its progress is kept apart by its own node ids), or the general
/// course for an exam track without a path and for the other tracks.
///
/// The full course, with every lesson. The path itself is drawn from
/// [courseOutlineProvider].
final courseProvider = FutureProvider<Course>((ref) async {
  final track = ref.watch(trackProvider);
  if (track.kind == TrackKind.exam) {
    final path = await ref.watch(examPathProvider(track.id).future);
    if (path != null) return path;
  }
  return loadCourse(rootBundle, track.kind == TrackKind.course ? track.id : defaultTrackId);
});

/// What the learning path draws: the outline of [courseProvider]'s course
/// (see [loadCourseOutline]), or the full course when there is no usable
/// outline. The path loads the full course in the background once it is on
/// screen, and opens steps from it.
///
/// Tests that override [courseProvider] with their own course override this
/// one too.
final courseOutlineProvider = FutureProvider<Course>((ref) async {
  final track = ref.watch(trackProvider);
  final exam = track.kind == TrackKind.exam && await ref.watch(hasExamPathProvider(track.id).future);
  final id = exam
      ? examPathId(track.id)
      : track.kind == TrackKind.course
      ? track.id
      : defaultTrackId;
  final outline = await loadCourseOutline(rootBundle, id);
  if (outline != null) {
    StartupTrace.mark('course_outline');
    return outline;
  }
  return ref.watch(courseProvider.future);
});

final examProvider = FutureProvider.family<Exam, String>((ref, id) => loadExam(rootBundle, id));
