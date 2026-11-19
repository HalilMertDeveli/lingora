import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/firebase_providers.dart';
import '../services/question_reports.dart';
import '../theme.dart';

/// Reports shown at once (newest first).
const reportsPageSize = 200;

/// Staff-only list of "Bildir" reports (firestore.rules: only isStaff()
/// reads `reports/`). Null without Firebase.
final reportsProvider = StreamProvider.family<List<ReportEntry>, ReportStatus?>((ref, status) {
  final db = ref.watch(firestoreProvider);
  if (db == null) return Stream.value(const []);
  Query<Map<String, dynamic>> q = db.collection('reports');
  if (status != null) q = q.where('status', isEqualTo: status.code);
  return q
      .orderBy('createdAt', descending: true)
      .limit(reportsPageSize)
      .snapshots()
      .map((s) => [for (final d in s.docs) ReportEntry.fromDoc(d.id, d.data())]);
});

/// Sets a report's triage status (rules: staff, these three fields only).
Future<void> setReportStatus(FirebaseFirestore db, String id, ReportStatus status, String uid) => db
    .collection('reports')
    .doc(id)
    .update({'status': status.code, 'statusAt': FieldValue.serverTimestamp(), 'statusBy': uid});

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  /// Null: every status.
  ReportStatus? _filter = ReportStatus.fresh;

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportsProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in [null, ...ReportStatus.values])
                  ChoiceChip(
                    key: Key('reports-filter-${s?.code ?? 'all'}'),
                    label: Text(s?.label ?? 'Tümü'),
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (reports) {
              AsyncData(value: final list) when list.isEmpty => const Center(
                child: Text('Bu durumda bildirim yok.'),
              ),
              AsyncData(value: final list) => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ReportCard(entry: list[i]),
              ),
              AsyncError(:final error) => Center(child: Text('Bildirimler yüklenemedi: $error')),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

String _when(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.entry});
  final ReportEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final e = entry;
    final db = ref.watch(firestoreProvider);
    final uid = ref.watch(currentUidProvider);
    return Card(
      key: Key('report-${e.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(e.reason.label, style: t.titleMedium)),
                Text(_when(e.createdAt), style: TextStyle(color: Brand.muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            if (e.question case final q?) Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(
              'Soru: ${e.questionId} · Ders: ${e.lessonId}'
              '${e.track == null ? '' : ' · Kurs: ${e.track}'} · Sürüm: ${e.appVersion}',
              style: TextStyle(color: Brand.muted, fontSize: 12),
            ),
            if (e.answer != null || e.correct != null)
              Text(
                'Kullanıcının cevabı: ${e.answer ?? '—'}'
                '${e.correct == null ? '' : (e.correct! ? ' (doğru sayıldı)' : ' (yanlış sayıldı)')}',
              ),
            if (e.note case final n?) ...[
              const SizedBox(height: 6),
              Text('Not: $n', style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            SegmentedButton<ReportStatus>(
              key: Key('report-status-${e.id}'),
              segments: [for (final s in ReportStatus.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {e.status},
              onSelectionChanged: db == null || uid == null
                  ? null
                  : (s) async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await setReportStatus(db, e.id, s.first, uid);
                      } catch (err) {
                        messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $err')));
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
