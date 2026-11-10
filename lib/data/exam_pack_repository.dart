import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exam_pack.dart';
import '../services/billing/products.dart';

Future<ExamPackContent> loadExamPack(AssetBundle bundle, ExamPack pack) async {
  final raw = await bundle.loadString(pack.asset);
  return ExamPackContent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Full mock exams of a pack. The content ships with the app; the UI only
/// opens it when the pack is unlocked (see `examPackUnlockedProvider`).
final examPackContentProvider = FutureProvider.family<ExamPackContent, ExamPack>(
  (ref, pack) => loadExamPack(rootBundle, pack),
);
