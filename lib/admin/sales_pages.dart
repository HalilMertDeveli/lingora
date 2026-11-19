/// Çenebaz staff only: quote requests from the /kurumsal page ("Talepler") and
/// 30-day trial seat codes ("Deneme kodu"). Server side: functions/src/sales.ts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'admin_api.dart';
import 'admin_app.dart';
import 'widgets.dart';

final leadsProvider = FutureProvider.autoDispose<List<Lead>>((ref) {
  final api = ref.watch(adminApiProvider);
  if (api == null) return const [];
  return api.listLeads();
});

class LeadsPage extends ConsumerWidget {
  const LeadsPage({super.key});

  Future<void> _trial(BuildContext context, WidgetRef ref, Lead lead) async {
    await showTrialFlow(context, ref, org: lead.org, students: lead.students, leadId: lead.id);
    ref.invalidate(leadsProvider);
  }

  Future<void> _note(BuildContext context, WidgetRef ref, Lead lead) async {
    final c = TextEditingController(text: lead.note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Not: ${lead.org}'),
        content: TextField(
          key: const Key('lead-note-field'),
          controller: c,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Ör. Perşembe 14.00 demo',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (note == null || !context.mounted) return;
    await runAction(context, () => ref.read(adminApiProvider)!.updateLead(lead.id, note: note));
    ref.invalidate(leadsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Lead lead) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${lead.org} talebi silinsin mi?'),
        content: const Text('Kişinin iletişim bilgileri kalıcı olarak silinir (ör. KVKK silme talebi).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            key: const Key('lead-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: Brand.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, () => ref.read(adminApiProvider)!.deleteLead(lead.id), done: 'Talep silindi.');
    ref.invalidate(leadsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talepler'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => ref.invalidate(leadsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (leads) {
        AsyncData(value: final list) when list.isEmpty => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Henüz talep yok. Kurumsal sayfadaki form doldurulunca burada görünür.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        AsyncData(value: final list) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '${list.where((l) => l.status == LeadStatus.yeni).length} yeni talep · toplam ${list.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final l in list)
              _LeadCard(
                lead: l,
                onStatus: (s) async {
                  await runAction(context, () => ref.read(adminApiProvider)!.updateLead(l.id, status: s));
                  ref.invalidate(leadsProvider);
                },
                onNote: () => _note(context, ref, l),
                onTrial: () => _trial(context, ref, l),
                onDelete: () => _delete(context, ref, l),
              ),
          ],
        ),
        AsyncError(:final error) => Center(
          child: Text(error is AdminException ? error.message : 'Talepler yüklenemedi.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.onStatus,
    required this.onNote,
    required this.onTrial,
    required this.onDelete,
  });

  final Lead lead;
  final void Function(LeadStatus) onStatus;
  final VoidCallback onNote;
  final VoidCallback onTrial;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final contact = [l.phone, l.email].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      key: Key('lead-${l.id}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Brand.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.org, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                DropdownButton<LeadStatus>(
                  key: Key('lead-status-${l.id}'),
                  value: l.status,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in LeadStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) {
                    if (s != null && s != l.status) onStatus(s);
                  },
                ),
              ],
            ),
            Text(
              '${l.name} · ${l.city} · ${l.students} öğrenci · ${fmtDate(l.createdAt)}',
              style: TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 4),
            SelectableText(contact, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (l.message.isNotEmpty) ...[const SizedBox(height: 6), Text(l.message)],
            if (l.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Not: ${l.note}', style: TextStyle(color: Brand.primary)),
            ],
            if (l.trialBatch != null)
              Text('Deneme partisi: ${l.trialBatch}', style: TextStyle(color: Brand.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('lead-trial-${l.id}'),
                  onPressed: onTrial,
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Deneme kodu üret'),
                ),
                TextButton.icon(
                  onPressed: onNote,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Not'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: Brand.error),
                  label: Text('Sil', style: TextStyle(color: Brand.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the org and seat counts, creates the codes, shows them.
Future<void> showTrialFlow(
  BuildContext context,
  WidgetRef ref, {
  String org = '',
  int students = 20,
  String? leadId,
}) async {
  final input = await showDialog<({String org, int students, int teachers})>(
    context: context,
    builder: (_) => TrialDialog(org: org, students: students),
  );
  if (input == null || !context.mounted) return;
  final codes = await runAction(
    context,
    () => ref
        .read(adminApiProvider)!
        .createTrial(org: input.org, students: input.students, teachers: input.teachers, leadId: leadId),
  );
  if (codes == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => TrialCodesDialog(org: input.org, trial: codes),
  );
}

class TrialDialog extends StatefulWidget {
  const TrialDialog({super.key, this.org = '', this.students = 20});
  final String org;
  final int students;

  @override
  State<TrialDialog> createState() => _TrialDialogState();
}

class _TrialDialogState extends State<TrialDialog> {
  static const maxStudents = 60;
  late final _org = TextEditingController(text: widget.org);
  late final _students = TextEditingController(text: '${widget.students.clamp(1, maxStudents)}');
  int _teachers = 1;
  String? _error;

  void _save() {
    final org = _org.text.trim();
    final n = int.tryParse(_students.text.trim());
    if (org.length < 2 || org.length > 60) return setState(() => _error = 'Kurum adı 2–60 karakter olmalı.');
    if (n == null || n < 0 || n > maxStudents) {
      return setState(() => _error = 'Öğrenci koltuğu 0–$maxStudents arası olmalı.');
    }
    Navigator.pop(context, (org: org, students: n, teachers: _teachers));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('30 günlük deneme kodu'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Her koltuk için ayrı bir lisans kodu üretilir. Kodlar 30 gün sonra kendiliğinden biter; '
            'Premium da o gün kapanır.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('trial-org'),
            controller: _org,
            decoration: const InputDecoration(labelText: 'Kurum adı', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('trial-students'),
            controller: _students,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Öğrenci koltuğu (en fazla $maxStudents)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Öğretmen koltuğu'),
              const Spacer(),
              SegmentedButton<int>(
                segments: [
                  for (final n in [1, 2, 3]) ButtonSegment(value: n, label: Text('$n')),
                ],
                selected: {_teachers},
                onSelectionChanged: (s) => setState(() => _teachers = s.first),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Brand.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(key: const Key('trial-create'), onPressed: _save, child: const Text('Kodları üret')),
    ],
  );
}

class TrialCodesDialog extends StatelessWidget {
  const TrialCodesDialog({super.key, required this.org, required this.trial});
  final String org;
  final TrialCodes trial;

  /// Plain text to paste into a message to the school: one code per line.
  String get text => [
    '$org · Çenebaz deneme kodları (son gün ${fmtDate(trial.expiresAt)})',
    for (final c in trial.codes) '${TrialCodes.pretty(c.code)}  ${c.teacher ? 'Öğretmen' : 'Öğrenci'}',
  ].join('\n');

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${trial.codes.length} deneme kodu hazır'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Son gün: ${fmtDate(trial.expiresAt)} · parti ${trial.batch}\n'
            'Kodları kurumun yetkilisine iletin. Öğretmen kodunu girer ve sınıf açar; öğrenciler kendi '
            'kodlarını Profil → "Lisans kodu gir" ile girer.',
          ),
          const SizedBox(height: 12),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Brand.line),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  key: const Key('trial-codes-text'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kodlar kopyalandı.')));
        },
        icon: const Icon(Icons.copy),
        label: const Text('Hepsini kopyala'),
      ),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
    ],
  );
}
