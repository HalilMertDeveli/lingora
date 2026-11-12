// The 1-year YDS plan (assets/plans/yds_1_yil.json) names its mocks by id: half and section mocks by path
// node id, full mocks by pack mock id. Every id the plan names that is already shipped must exist with
// the size and time the plan gives (YDS Faz 3 acceptance 3); every half-mock node of ys10/ys11 must be in the plan.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _read(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final plan = _read('assets/plans/yds_1_yil.json');
  final weeks = (plan['weeks'] as List).cast<Map<String, dynamic>>();
  final planMocks = [
    for (final w in weeks)
      for (final m in ((w['mocks'] as List?) ?? const []).cast<Map<String, dynamic>>()) (w, m),
  ];

  // Mock nodes of the YDS path.
  final nodes = <String, Map<String, dynamic>>{};
  for (final f in [
    File('assets/courses/exam_yds.json'),
    ...Directory('assets/courses/exam_yds')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json')),
  ]) {
    for (final u in _read(f.path)['units'] as List) {
      for (final n in ((u as Map)['nodes'] as List).cast<Map<String, dynamic>>()) {
        if (n['type'] == 'mock') nodes[n['id'] as String] = n;
      }
    }
  }
  final packMocks = {
    for (final m in _read('assets/exam_packs/yds_full.json')['mocks'] as List)
      (m as Map)['id'] as String: m as Map<String, dynamic>,
  };

  // Sections that are shipped (ys1 … ysN); a plan node of a later section is written in a later phase.
  final shipped = {
    'ys1',
    for (final f in Directory('assets/courses/exam_yds').listSync().whereType<File>())
      if (RegExp(r'(\d\d)_').firstMatch(f.uri.pathSegments.last) case final m?) 'ys${int.parse(m.group(1)!)}',
  };

  test('plan half and section mocks point at shipped mock nodes of the same size', () {
    for (final (w, m) in planMocks) {
      final id = m['nodeId'] as String?;
      if (m['kind'] == 'full' || m['kind'] == 'check' || id == null) continue;
      if (!shipped.contains(RegExp(r'^ys\d+').stringMatch(id))) continue;
      final node = nodes[id];
      expect(node, isNotNull, reason: 'week ${w['week']}: no mock node $id');
      // A half mock's node carries its own fixed questions (size 40, 90 min).
      if (m['kind'] == 'half') {
        expect([node!['size'], node['minutes']], [m['size'], m['minutes']], reason: 'week ${w['week']} $id');
        expect((node['exercises'] as List?) ?? const [], hasLength(m['size'] as int), reason: id);
      }
    }
  });

  test('plan full mocks that are shipped match the pack (80 questions, 180 minutes)', () {
    for (final (w, m) in planMocks.where((x) => x.$2['kind'] == 'full')) {
      final mock = packMocks[m['id']];
      if (mock == null) continue; // written in a later phase
      expect(
        (mock['questions'] as List),
        hasLength(m['size'] as int),
        reason: 'week ${w['week']} ${m['id']}',
      );
      expect(mock['minutes'], m['minutes'], reason: 'week ${w['week']} ${m['id']}');
    }
  });

  // Faz 3d: half mocks inside a section (ys10u3m/u5m/u7m) and the Ara denemeler side path (ys11u1m–u3m)
  // must each be scheduled in the plan as a half mock of the same size.
  test('every half-mock node of ys10 and ys11 is in the plan as a half mock', () {
    final half = {
      for (final (_, m) in planMocks)
        if (m['kind'] == 'half') m['nodeId']: m,
    };
    final ids = nodes.keys.where((k) => RegExp(r'^ys1[01]u\d+m$').hasMatch(k) && nodes[k]!['size'] == 40);
    for (final id in ids) {
      expect(half, contains(id), reason: '$id is not a half mock in the plan');
      expect([half[id]!['size'], half[id]!['minutes']], [40, 90], reason: id);
    }
    // ys11 is shipped in Faz 3d: its three half mocks (plan weeks 22, 24, 27) must all exist.
    if (shipped.contains('ys11')) expect(ids, containsAll(['ys11u1m', 'ys11u2m', 'ys11u3m']));
  });
}
