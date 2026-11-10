import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/exam.dart';
import 'catalog.dart';
import 'progress.dart';

Future<Course> loadCourse(AssetBundle bundle, String id) async {
  final raw = await bundle.loadString('assets/courses/$id.json');
  return Course.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
