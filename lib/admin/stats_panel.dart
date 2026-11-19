import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/firebase_providers.dart';
import '../theme.dart';

/// Panel: the owner's daily/weekly sales and usage counts (Çenebaz staff only).
///
/// Data: `getStats` callable over `stats/daily/days/{yyyy-mm-dd}`
/// (functions/src/stats.ts). Aggregated counts only, no user data.
/// Owner guide and the GA4 funnel: docs/panel-istatistik.md.

/// One Turkish calendar day of counters.
class StatsDayData {
  const StatsDayData(this.day, this.counts);

  factory StatsDayData.fromJson(Map<String, Object?> j) {
    final raw = j['counts'];
    final counts = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num) counts['${e.key}'] = v.toInt();
      }
    }
    return StatsDayData('${j['day']}', counts);
  }

  final String day;
  final Map<String, int> counts;

  int operator [](String key) => counts[key] ?? 0;
  bool has(String key) => counts.containsKey(key);
}

class StatsData {
  const StatsData({required this.days, required this.premiumActiveNow});
  final List<StatsDayData> days; // oldest first
  final int premiumActiveNow;
}

abstract interface class StatsApi {
  Future<StatsData> load({int days = 63});
}

class CallableStatsApi implements StatsApi {
  CallableStatsApi(this._functions);
  final FirebaseFunctions _functions;

  @override
  Future<StatsData> load({int days = 63}) async {
    final res = await _functions.httpsCallable('getStats').call<Object?>({'days': days});
    final r = Map<String, Object?>.from(res.data as Map);
    return StatsData(
      days: [
        for (final d in (r['days'] as List? ?? const []))
          StatsDayData.fromJson(Map<String, Object?>.from(d as Map)),
      ],
      premiumActiveNow: (r['premiumActiveNow'] as num?)?.toInt() ?? 0,
    );
  }
}

final statsApiProvider = Provider<StatsApi?>((ref) {
  final f = ref.watch(functionsProvider);
  return f == null ? null : CallableStatsApi(f);
});

final statsDataProvider = FutureProvider<StatsData>((ref) => ref.watch(statsApiProvider)!.load());

/// Counter names (stats.ts) in table order, with their column titles.
const statsColumns = <(String, String)>[
  ('first_open', 'Kurulum\n(ilk açılış)'),
  ('first_lesson', 'İlk ders\nbitti'),
  ('paywall_view', 'Paywall\ngörüldü'),
  ('purchase_start', 'Satın alma\nbaşladı'),
  ('purchase_verified', 'Satın alma\ndoğrulandı'),
];

/// A row of the table: a day or a 7-day week.
class StatsRow {
  const StatsRow({required this.label, required this.counts, this.premiumActive, this.d1, this.d7});

  final String label;
  final Map<String, int> counts;

  /// Active Premium at the end of the period (null: no snapshot yet).
  final int? premiumActive;

  /// Share of the period's installs that came back on day 1 / day 7
  /// (null: not measurable yet or no installs).
  final double? d1;
  final double? d7;
}

double? _ratio(int part, int whole) => whole <= 0 ? null : part / whole;

/// Daily rows (newest first). D1 of day X = return_d1 on X+1 / installs on
/// X; D7 = return_d7 on X+7 / installs on X. Days whose return day is not
/// in [days] (still in the future) get null.
List<StatsRow> dailyRows(List<StatsDayData> days) {
  final rows = <StatsRow>[];
  for (var i = days.length - 1; i >= 0; i--) {
    final d = days[i];
    rows.add(
      StatsRow(
        label: d.day,
        counts: {for (final (k, _) in statsColumns) k: d[k]},
        premiumActive: d.has('premium_active') ? d['premium_active'] : null,
        d1: i + 1 < days.length ? _ratio(days[i + 1]['return_d1'], d['first_open']) : null,
        d7: i + 7 < days.length ? _ratio(days[i + 7]['return_d7'], d['first_open']) : null,
      ),
    );
  }
  return rows;
}

/// Weekly rows (newest first): 7-day blocks ending with the last day. D1/D7
/// use only the block's install days whose return day is already known.
List<StatsRow> weeklyRows(List<StatsDayData> days) {
  final rows = <StatsRow>[];
  for (var end = days.length; end - 7 >= 0; end -= 7) {
    final start = end - 7;
    final counts = {for (final (k, _) in statsColumns) k: 0};
    int? premium;
    var r1 = 0, i1 = 0, r7 = 0, i7 = 0;
    for (var i = start; i < end; i++) {
      final d = days[i];
      for (final (k, _) in statsColumns) {
        counts[k] = counts[k]! + d[k];
      }
      if (d.has('premium_active')) premium = d['premium_active'];
      if (i + 1 < days.length) {
        r1 += days[i + 1]['return_d1'];
        i1 += d['first_open'];
      }
      if (i + 7 < days.length) {
        r7 += days[i + 7]['return_d7'];
        i7 += d['first_open'];
      }
    }
    rows.add(
      StatsRow(
        label: '${days[start].day} – ${days[end - 1].day}',
        counts: counts,
        premiumActive: premium,
        d1: _ratio(r1, i1),
        d7: _ratio(r7, i7),
      ),
    );
  }
  return rows;
}

String percent(double? v) => v == null ? '–' : '%${(v * 100).round()}';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  bool _weekly = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(statsDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çenebaz · Panel'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => ref.invalidate(statsDataProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e is FirebaseFunctionsException && e.code == 'permission-denied'
                    ? 'Bu sayfayı yalnızca Çenebaz ekibi görebilir.'
                    : 'İstatistikler yüklenemedi.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(statsDataProvider),
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
        data: (s) => _body(context, s),
      ),
    );
  }

  Widget _body(BuildContext context, StatsData s) {
    final t = Theme.of(context).textTheme;
    final rows = _weekly ? weeklyRows(s.days) : dailyRows(s.days);
    final last7 = weeklyRows(s.days).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Tile(
              label: 'Aktif Premium (şu an)',
              value: '${s.premiumActiveNow}',
              key: const ValueKey('stat-premium'),
            ),
            if (last7 != null) ...[
              _Tile(label: 'Kurulum (son 7 gün)', value: '${last7.counts['first_open']}'),
              _Tile(label: 'Doğrulanan satın alma (7 gün)', value: '${last7.counts['purchase_verified']}'),
              _Tile(
                label: 'İlk ders / kurulum (7 gün)',
                value: percent(_ratio(last7.counts['first_lesson']!, last7.counts['first_open']!)),
              ),
              _Tile(
                label: 'Satın alma başladı / paywall (7 gün)',
                value: percent(_ratio(last7.counts['purchase_start']!, last7.counts['paywall_view']!)),
              ),
              _Tile(label: 'D1 / D7 (yaklaşık)', value: '${percent(last7.d1)} / ${percent(last7.d7)}'),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(_weekly ? 'Haftalık' : 'Günlük', style: t.titleLarge),
            const Spacer(),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Günlük')),
                ButtonSegment(value: true, label: Text('Haftalık')),
              ],
              selected: {_weekly},
              onSelectionChanged: (v) => setState(() => _weekly = v.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const ValueKey('stats-table'),
              columns: [
                DataColumn(label: Text(_weekly ? 'Hafta' : 'Gün')),
                for (final (_, title) in statsColumns) DataColumn(label: Text(title), numeric: true),
                const DataColumn(label: Text('Aktif\nPremium'), numeric: true),
                const DataColumn(label: Text('D1'), numeric: true),
                const DataColumn(label: Text('D7'), numeric: true),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(r.label)),
                      for (final (k, _) in statsColumns) DataCell(Text('${r.counts[k]}')),
                      DataCell(Text(r.premiumActive?.toString() ?? '–')),
                      DataCell(Text(percent(r.d1))),
                      DataCell(Text(percent(r.d7))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Günler Türkiye saatine göredir. Kurulum, ilk ders, paywall, satın alma başlangıcı ve D1/D7 '
          'yalnızca analiz izni veren kullanıcılardan, cihaz başına bir kez sayılır (paywall ve satın alma '
          'başlangıcı günde bir kez). Doğrulanan satın almalar ve aktif Premium sunucudan gelir ve herkesi '
          'kapsar. D1: kurulumdan sonraki gün geri dönenlerin oranı; D7: 7. gün. Gelir için Play Console, '
          'ayrıntılı huni için Firebase Analytics (docs/panel-istatistik.md).',
          style: TextStyle(color: Brand.muted, height: 1.4),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Brand.muted)),
          ],
        ),
      ),
    ),
  );
}
