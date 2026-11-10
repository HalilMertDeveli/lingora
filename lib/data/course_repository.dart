import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';

Future<Course> loadCourse(AssetBundle bundle, String id) async {
  final raw = await bundle.loadString('assets/courses/$id.json');
  return Course.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

final courseProvider = FutureProvider<Course>(
  (ref) => loadCourse(rootBundle, 'tr_en'),
);
