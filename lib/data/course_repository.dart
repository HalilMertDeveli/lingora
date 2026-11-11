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
  return course.withSections(await loadSections(bundle, id, after: course));
}

/// Section files of course [id] found in the asset manifest, sorted by file
/// name. A missing, unreadable or broken file (bad JSON, wrong shape, an id
/// already used earlier in the path) is skipped and logged, never fatal.
Future<List<Section>> loadSections(AssetBundle bundle, String id, {Course? after}) async {
  final prefix = 'assets/courses/$id/';
  final List<String> paths;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    paths = manifest.listAssets().where((p) => p.startsWith(prefix) && p.endsWith('.json')).toList()..sort();
  } catch (e) {
    debugPrint('Bölümler bulunamadı ($id): $e');
    return const [];
  }
  final unitIds = <String>{...?after?.units.map((u) => u.id)};
  final nodeIds = <String>{...?after?.allNodes.map((n) => n.id)};
  final sectionIds = <String>{...?after?.sections.map((s) => s.id)};
  final sections = <Section>[];
  for (final path in paths) {
    try {
      final section = Section.fromFile(jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>);
      final units = section.units.map((u) => u.id);
      final nodes = section.nodes.map((n) => n.id);
      final clash = [
        if (sectionIds.contains(section.id)) section.id,
        ...units.where(unitIds.contains),
        ...nodes.where(nodeIds.contains),
      ];
      if (section.units.isEmpty) throw const FormatException('ünite yok');
      if (clash.isNotEmpty) throw FormatException('tekrarlanan id: ${clash.take(5).join(', ')}');
      if (units.toSet().length != units.length || nodes.toSet().length != nodes.length) {
        throw const FormatException('dosya içinde tekrarlanan id');
      }
      sectionIds.add(section.id);
      unitIds.addAll(units);
      nodeIds.addAll(nodes);
      sections.add(section);
    } catch (e) {
      debugPrint('Bölüm atlandı ($path): $e');
    }
  }
  return sections;
}

Future<Exam> loadExam(AssetBundle bundle, String id) async {
  final raw = await bundle.loadString('assets/exams/$id.json');
  return Exam.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// The selected track, falling back to the general course for unknown ids.
final trackProvider = Provider<Track>(
  (ref) => trackById(ref.watch(progressProvider.select((p) => p.trackId))),
);

/// Course for the learning path: the selected course, or the general course
/// while an exam track is selected.
final courseProvider = FutureProvider<Course>((ref) {
  final track = ref.watch(trackProvider);
  return loadCourse(rootBundle, track.kind == TrackKind.course ? track.id : defaultTrackId);
});

final examProvider = FutureProvider.family<Exam, String>((ref, id) => loadExam(rootBundle, id));
