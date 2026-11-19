import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/admin/stats_panel.dart';

/// 14 days, 2026-11-06 … 2026-11-19, oldest first.
List<StatsDayData> sample() => [
  for (var i = 0; i < 14; i++)
    StatsDayData('2026-11-${(6 + i).toString().padLeft(2, '0')}', {
      'first_open': 10,
      'first_lesson': 6,
      'paywall_view': 8,
      'purchase_start': 2,
      'purchase_verified': 1,
      'return_d1': 4,
      'return_d7': 2,
      'premium_active': 100 + i,
    }),
];

class FakeStatsApi implements StatsApi {
  @override
  Future<StatsData> load({int days = 63}) async => StatsData(days: sample(), premiumActiveNow: 120);
}

void main() {
  test('day rows: newest first, D1/D7 from later days, null when not known yet', () {
    final rows = dailyRows(sample());
    expect(rows.first.label, '2026-11-19');
    expect(rows.first.d1, isNull, reason: 'tomorrow unknown');
    expect(rows.first.d7, isNull);
    expect(rows[1].d1, closeTo(0.4, 1e-9));
    expect(rows[1].d7, isNull);
    expect(rows[7].d7, closeTo(0.2, 1e-9));
    expect(rows.first.premiumActive, 113);
    expect(rows.first.counts['purchase_verified'], 1);
  });

  test('no installs → no retention; missing snapshot → null', () {
    final rows = dailyRows([
      const StatsDayData('2026-11-01', {'return_d1': 0}),
      const StatsDayData('2026-11-02', {'return_d1': 3}),
    ]);
    expect(rows.last.d1, isNull);
    expect(rows.last.premiumActive, isNull);
    expect(rows.last.counts['first_open'], 0);
  });

  test('week rows sum 7 days and use only measurable cohorts', () {
    final rows = weeklyRows(sample());
    expect(rows, hasLength(2));
    expect(rows.first.label, '2026-11-13 – 2026-11-19');
    expect(rows.first.counts['first_open'], 70);
    expect(rows.first.counts['purchase_start'], 14);
    expect(rows.first.premiumActive, 113);
    // 6 of the 7 install days have a known next day: 24 / 60.
    expect(rows.first.d1, closeTo(0.4, 1e-9));
    // None of the last week's installs reached day 7 yet.
    expect(rows.first.d7, isNull);
    expect(rows.last.d7, closeTo(0.2, 1e-9));
    expect(percent(rows.last.d7), '%20');
    expect(percent(null), '–');
  });

  test('parses the callable payload and ignores junk', () {
    final d = StatsDayData.fromJson({
      'day': '2026-11-19',
      'counts': {'first_open': 3, 'premium_active': 2.0, 'day': '2026-11-19', 'updatedAt': null},
    });
    expect(d.counts, {'first_open': 3, 'premium_active': 2});
  });

  testWidgets('page shows tiles, the table and switches to weeks', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [statsApiProvider.overrideWithValue(FakeStatsApi())],
        child: const MaterialApp(home: StatsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Çenebaz · Panel'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('stat-premium')), matching: find.text('120')),
      findsOneWidget,
    );
    expect(find.text('2026-11-19'), findsOneWidget);
    await tester.tap(find.text('Haftalık'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-13 – 2026-11-19'), findsOneWidget);
    expect(find.text('2026-11-19'), findsNothing);
  });
}
