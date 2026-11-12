// Shipped YDS sections never change shape (YDS Faz 3, conductor's condition on PR #64): new content goes into
// new sections only. A learner who finished ys1–ys10 keeps every section at 100 %, every section open and
// every node done after new sections (ys11 …) are added.
// test/fixtures/yds_shipped_nodes.json freezes the node ids of ys1–ys8 (end of Faz 2) and ys9–ys10 (Faz 3a/3b).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/sections.dart';

import 'study_test.dart' show readCourse;

void main() {
  final frozen = (jsonDecode(File('test/fixtures/yds_shipped_nodes.json').readAsStringSync()) as Map).map(
    (k, v) => MapEntry(k as String, (v as List).cast<String>()),
  );
  final course = readCourse('exam_yds');
  final byId = {for (final s in course.sections) s.id: s};

  test('ys1–ys10 keep exactly their shipped nodes: none added, removed or reordered', () {
    for (final MapEntry(key: id, value: ids) in frozen.entries) {
      final section = byId[id];
      expect(section, isNotNull, reason: id);
      expect(section!.nodes.map((n) => n.id).toList(), ids, reason: '$id changed shape');
    }
  });

  test('a learner who finished ys1–ys10 stays at 100 %, with every section open', () {
    final done = Progress(
      completed: {
        for (final ids in frozen.values)
          for (final n in ids) n: 1,
      },
    );
    for (final id in frozen.keys) {
      final section = byId[id]!;
      expect(sectionProgress(section, done), 1.0, reason: id);
      expect(section.nodes.every((n) => done.isDone(n.id)), isTrue, reason: id);
    }
    // New sections (side paths) are open too, and nothing in them is required to keep the old ones whole.
    for (final section in course.sections) {
      expect(sectionOpen(course, section, done), isTrue, reason: section.id);
    }
  });
}
