import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/exam.dart';
import 'catalog.dart';
import 'progress.dart';

/// Loads `assets/courses/<id>.json` plus its section files,
/// `assets/courses/<id>/NN_slug.json`, in file-name order (see [loadSections]).
Future<Course> loadCourse(AssetBundle bundle, String id) async {
  final raw = await bundle.loadString('assets/courses/$id.json');
  final course = Course.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  final sections = await loadSections(bundle, id, after: course);
  if (listEquals(sections, course.sections)) return course;
  return Course(
    id: course.id,
    title: course.title,
    fromLang: course.fromLang,
    learningLang: course.learningLang,
    sections: sections,
  );
}

/// Every section of course [id]: the sections of [after] (the course file)
/// followed by the section files found in the asset manifest, sorted by file
/// name.
///
/// A file `NN_slug.json` is a new section. A file `NNx_slug.json` with
/// `{"extends": "sN", "units": [...]}` appends units to the end of section sN,
/// which must come earlier (it sorts after `NN_slug.json`); the section exam
/// stays the last test of sN's own file (see [Section.extendedWith]).
///
/// A missing, unreadable or broken file (bad JSON, wrong shape, an id already
/// used earlier in the path, an unknown section to extend) is skipped and
/// logged, never fatal.
Future<List<Section>> loadSections(AssetBundle bundle, String id, {Course? after}) async {
  final sections = <Section>[...?after?.sections];
  final prefix = 'assets/courses/$id/';
  final List<String> paths;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    paths = manifest.listAssets().where((p) => p.startsWith(prefix) && p.endsWith('.json')).toList()..sort();
  } catch (e) {
    debugPrint('Bölümler bulunamadı ($id): $e');
    return sections;
  }
  final unitIds = <String>{...?after?.units.map((u) => u.id)};
  final nodeIds = <String>{...?after?.allNodes.map((n) => n.id)};
  final sectionIds = <String>{...?after?.sections.map((s) => s.id)};
  for (final path in paths) {
    try {
      final json = jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>;
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
      debugPrint('Bölüm atlandı ($path): $e');
    }
  }
  return sections;
}

/// The study path of exam track [examTrackId] (LGS → `exam_lgs`), or null
/// when it is not shipped (yet) or cannot be read: the exam track then shows
/// its question bank home as before.
Future<Course?> loadExamPath(AssetBundle bundle, String examTrackId) async {
  final id = examPathId(examTrackId);
  try {
    // Ask the manifest first: a missing file is the normal case, not an error.
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    if (!manifest.listAssets().contains('assets/courses/$id.json')) return null;
    return await loadCourse(bundle, id);
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

/// Course for the learning path: the selected course, an exam track's study
/// path (its progress is kept apart by its own node ids), or the general
/// course for an exam track without a path and for the other tracks.
final courseProvider = FutureProvider<Course>((ref) async {
  final track = ref.watch(trackProvider);
  if (track.kind == TrackKind.exam) {
    final path = await ref.watch(examPathProvider(track.id).future);
    if (path != null) return path;
  }
  return loadCourse(rootBundle, track.kind == TrackKind.course ? track.id : defaultTrackId);
});

final examProvider = FutureProvider.family<Exam, String>((ref, id) => loadExam(rootBundle, id));
