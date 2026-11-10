import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../org/org.dart';
import '../theme.dart';
import 'admin_api.dart';
import 'admin_app.dart';
import 'catalog.dart';
import 'csv.dart';
import 'download.dart';
import 'widgets.dart';

final orgReportProvider = FutureProvider.family<OrgReport, String>(
  (ref, orgId) => ref.watch(adminApiProvider)!.report(orgId),
);

/// Lessons, grammar lessons and exams a teacher can assign.
final assignTargetsProvider = FutureProvider<List<AssignTarget>>((ref) => loadAssignTargets(rootBundle));

/// Clock for "son 7 gün" and due dates; overridden in tests.
final adminClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

enum _Section {
  overview('Genel bakış', Icons.dashboard_outlined),
  people('Kişiler', Icons.people_outline),
  classes('Sınıflar', Icons.groups_2_outlined),
  assignments('Ödevler', Icons.assignment_outlined),
  codes('Davet kodları', Icons.vpn_key_outlined);

  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

class OrgDashboard extends ConsumerStatefulWidget {
  const OrgDashboard({super.key, required this.orgId});
  final String orgId;

  @override
  ConsumerState<OrgDashboard> createState() => _OrgDashboardState();
}

class _OrgDashboardState extends ConsumerState<OrgDashboard> {
  _Section _section = _Section.overview;

  void _export(OrgReport r) {
    final csv = membersCsv(r);
    final now = ref.read(adminClockProvider)();
    final name =
        'lingora-${r.org.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-'
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
    if (!downloadText(name, csv)) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('CSV'),
          content: SingleChildScrollView(child: SelectableText(csv)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(orgReportProvider(widget.orgId));
    final r = report.value;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          r == null ? 'Lingora Kurumsal' : '${r.org.name} · ${r.isAdmin ? 'Yönetici' : 'Öğretmen'}',
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(orgReportProvider(widget.orgId)),
          ),
          if (r != null)
            TextButton.icon(
              onPressed: () => _export(r),
              icon: const Icon(Icons.download),
              label: const Text('CSV indir'),
            ),
          if (r?.staff != true)
            TextButton(onPressed: () => ref.read(adminAuthProvider)?.signOut(), child: const Text('Çıkış')),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            selectedIndex: _section.index,
            onDestinationSelected: (i) => setState(() => _section = _Section.values[i]),
            labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [
              for (final s in _Section.values)
                NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (report) {
              AsyncData(value: final r) => _body(r),
              AsyncError(:final error) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error is AdminException ? error.message : 'Rapor yüklenemedi.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => ref.invalidate(orgReportProvider(widget.orgId)),
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(OrgReport r) => switch (_section) {
    _Section.overview => OverviewSection(report: r),
    _Section.people => PeopleSection(report: r),
    _Section.classes => ClassesSection(report: r),
    _Section.assignments => AssignmentsSection(report: r),
    _Section.codes => CodesSection(report: r),
  };
}

/// Reloads the report after a change.
void _reload(WidgetRef ref, OrgReport r) => ref.invalidate(orgReportProvider(r.org.id));

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------- overview ----

class OverviewSection extends ConsumerWidget {
  const OverviewSection({super.key, required this.report});
  final OrgReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final now = ref.watch(adminClockProvider)();
    final weekAgo = _dayKey(now.subtract(const Duration(days: 6)));
    final learners = r.members.where((m) => m.role != OrgRole.admin).toList();
    final active = learners.where((m) => (m.lastActiveDay ?? '').compareTo(weekAgo) >= 0).length;
    final daysLeft = r.org.planExpiresAt.difference(now).inDays;
    final totalAssigned = r.assignments.fold(0, (s, a) => s + a.total);
    final totalDone = r.assignments.fold(0, (s, a) => s + a.done);
    final top = [...learners]..sort((a, b) => b.weekXp.compareTo(a.weekXp));
    final quiet = learners.where((m) => (m.lastActiveDay ?? '').compareTo(weekAgo) < 0).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionHeader(
          title: 'Genel bakış',
          subtitle: '${r.org.typeLabel} · ${r.isAdmin ? 'tüm kişiler' : 'sınıflarınız'}',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatCard(
              label: 'Koltuk',
              value: '${r.org.seatsUsed} / ${r.org.seats}',
              hint: r.org.seatsUsed >= r.org.seats
                  ? 'Boş koltuk kalmadı'
                  : '${r.org.seats - r.org.seatsUsed} boş',
              icon: Icons.event_seat_outlined,
            ),
            StatCard(
              label: 'Plan bitişi',
              value: fmtDate(r.org.planExpiresAt),
              hint: daysLeft < 0 ? 'Süresi doldu' : '$daysLeft gün kaldı',
              icon: Icons.event_outlined,
              color: daysLeft < 30 ? Brand.error : null,
            ),
            StatCard(
              label: 'Son 7 günde aktif',
              value: '$active / ${learners.length}',
              icon: Icons.local_fire_department_outlined,
              color: Brand.streak,
            ),
            StatCard(
              label: 'Tamamlanan ders',
              value: '${learners.fold(0, (s, m) => s + m.lessonsDone)}',
              hint: 'toplam',
              icon: Icons.check_circle_outline,
              color: Brand.success,
            ),
            StatCard(
              label: 'Ödev tamamlama',
              value: totalAssigned == 0 ? '—' : '%${(totalDone * 100 / totalAssigned).round()}',
              hint: '$totalDone / $totalAssigned',
              icon: Icons.assignment_turned_in_outlined,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _ListCard(
              title: 'Bu haftanın en çalışkanları',
              empty: 'Henüz kimse çalışmadı.',
              rows: [
                for (final m in top.take(5).where((m) => m.weekXp > 0)) (m.displayName, '${m.weekXp} XP'),
              ],
            ),
            _ListCard(
              title: 'Bir haftadır girmeyenler',
              empty: 'Herkes bu hafta çalıştı. 🎉',
              rows: [for (final m in quiet.take(8)) (m.displayName, 'son: ${fmtDayKey(m.lastActiveDay)}')],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Gizlilik: Lingora yalnızca ders, XP, seri ve ödev durumunu paylaşır. Günlükler, kişisel notlar, '
          'kelime listeleri ve yapay zekâ sohbetleri kurumla paylaşılmaz.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.rows, required this.empty});
  final String title;
  final List<(String, String)> rows;
  final String empty;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 380,
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Brand.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (rows.isEmpty) Text(empty, style: const TextStyle(color: Brand.muted)),
            for (final (a, b) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(a)),
                    Text(b, style: const TextStyle(color: Brand.muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// --------------------------------------------------------------- people ----

class PeopleSection extends ConsumerStatefulWidget {
  const PeopleSection({super.key, required this.report});
  final OrgReport report;

  @override
  ConsumerState<PeopleSection> createState() => _PeopleSectionState();
}

class _PeopleSectionState extends ConsumerState<PeopleSection> {
  String _query = '';
  String? _classId;
  int _sort = 0;
  bool _asc = true;

  OrgReport get r => widget.report;

  List<MemberRow> get _rows {
    final q = _query.toLowerCase();
    final rows = r.members
        .where((m) => q.isEmpty || m.displayName.toLowerCase().contains(q))
        .where((m) => _classId == null || m.classIds.contains(_classId))
        .toList();
    int cmp(MemberRow a, MemberRow b) => switch (_sort) {
      0 => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      1 => a.role.index.compareTo(b.role.index),
      2 => a.lessonsDone.compareTo(b.lessonsDone),
      3 => a.totalXp.compareTo(b.totalXp),
      4 => a.weekXp.compareTo(b.weekXp),
      5 => a.streak.compareTo(b.streak),
      6 => (a.lastActiveDay ?? '').compareTo(b.lastActiveDay ?? ''),
      _ => a.assignmentsDone.compareTo(b.assignmentsDone),
    };
    rows.sort((a, b) => _asc ? cmp(a, b) : cmp(b, a));
    return rows;
  }

  Future<void> _action(MemberRow m, String action) async {
    final api = ref.read(adminApiProvider)!;
    final orgId = r.org.id;
    switch (action) {
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('${m.displayName} kurumdan çıkarılsın mı?'),
            content: const Text(
              'Koltuğu boşalır ve kurumdan gelen Premium biter. Kişinin kendi ilerlemesi silinmez.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çıkar')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        await runAction(context, () => api.removeMember(orgId, m.uid), done: '${m.displayName} çıkarıldı.');
      case 'classes':
        await showDialog<void>(
          context: context,
          builder: (_) => _MemberClassesDialog(report: r, member: m),
        );
      default:
        final role = OrgRole.parse(action);
        await runAction(
          context,
          () => api.setRole(orgId, m.uid, role),
          done: 'Rol güncellendi: ${role.label}.',
        );
    }
    _reload(ref, r);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    DataColumn col(String label, {bool numeric = false}) => DataColumn(
      label: Text(label),
      numeric: numeric,
      onSort: (i, asc) => setState(() {
        _sort = i;
        _asc = asc;
      }),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionHeader(
          title: 'Kişiler',
          subtitle: '${r.members.length} kişi · yalnızca öğrenme ilerlemesi gösterilir',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'İsimle ara',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (r.classes.isNotEmpty)
              DropdownButton<String?>(
                value: _classId,
                hint: const Text('Tüm sınıflar'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tüm sınıflar')),
                  for (final c in r.classes) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _classId = v),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Brand.line),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sort,
              sortAscending: _asc,
              columns: [
                col('Ad Soyad'),
                col('Rol'),
                col('Ders', numeric: true),
                col('XP', numeric: true),
                col('7 gün XP', numeric: true),
                col('Seri', numeric: true),
                col('Son aktif'),
                col('Ödev'),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final m in rows)
                  DataRow(
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              m.synced
                                  ? m.classIds.map(r.className).where((n) => n.isNotEmpty).join(', ')
                                  : 'Uygulama henüz eşitlenmedi',
                              style: const TextStyle(color: Brand.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(m.role.label)),
                      DataCell(Text('${m.lessonsDone}')),
                      DataCell(Text('${m.totalXp}')),
                      DataCell(Text('${m.weekXp}')),
                      DataCell(Text(m.streak > 0 ? '🔥 ${m.streak}' : '0')),
                      DataCell(Text(fmtDayKey(m.lastActiveDay))),
                      DataCell(
                        Text(
                          m.assignments.isEmpty
                              ? '—'
                              : '${m.assignmentsDone}/${m.assignments.length}'
                                    '${m.assignmentsLate > 0 ? ' · ${m.assignmentsLate} gecikti' : ''}',
                          style: TextStyle(color: m.assignmentsLate > 0 ? Brand.error : null),
                        ),
                      ),
                      DataCell(
                        PopupMenuButton<String>(
                          tooltip: 'İşlemler',
                          onSelected: (a) => _action(m, a),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'classes', child: Text('Sınıflarını düzenle')),
                            if (r.isAdmin) ...[
                              const PopupMenuDivider(),
                              for (final role in OrgRole.values)
                                if (role != m.role)
                                  PopupMenuItem(value: role.name, child: Text('Rolü yap: ${role.label}')),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Kurumdan çıkar', style: TextStyle(color: Brand.error)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Kimse yok. Davet kodları bölümünden kod oluşturup paylaşın.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _MemberClassesDialog extends ConsumerStatefulWidget {
  const _MemberClassesDialog({required this.report, required this.member});
  final OrgReport report;
  final MemberRow member;

  @override
  ConsumerState<_MemberClassesDialog> createState() => _MemberClassesDialogState();
}

class _MemberClassesDialogState extends ConsumerState<_MemberClassesDialog> {
  late final Set<String> _in = {...widget.member.classIds};

  Future<void> _toggle(ClassInfo c, bool add) async {
    final ok = await runAction(
      context,
      () => ref
          .read(adminApiProvider)!
          .setClassMember(widget.report.org.id, c.id, widget.member.uid, add: add)
          .then((_) => true),
    );
    if (ok == true && mounted) setState(() => add ? _in.add(c.id) : _in.remove(c.id));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.member.displayName} · sınıflar'),
    content: SizedBox(
      width: 360,
      child: widget.report.classes.isEmpty
          ? const Text('Önce Sınıflar bölümünden bir sınıf oluşturun.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in widget.report.classes)
                  CheckboxListTile(
                    value: _in.contains(c.id),
                    title: Text(c.name),
                    subtitle: c.teacherName.isEmpty ? null : Text(c.teacherName),
                    onChanged: (v) => _toggle(c, v ?? false),
                  ),
              ],
            ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
  );
}

// -------------------------------------------------------------- classes ----

class ClassesSection extends ConsumerWidget {
  const ClassesSection({super.key, required this.report});
  final OrgReport report;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final teachers = report.members.where((m) => m.role != OrgRole.member).toList();
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _ClassDialog(teachers: report.isAdmin ? teachers : const []),
    );
    if (result == null || !context.mounted) return;
    await runAction(
      context,
      () => ref.read(adminApiProvider)!.createClass(report.org.id, result.$1, teacherUid: result.$2),
      done: '${result.$1} oluşturuldu.',
    );
    _reload(ref, report);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ClassInfo c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${c.name} silinsin mi?'),
        content: const Text('Sınıfın ödevleri ve davet kodları da silinir. Öğrenciler kurumda kalır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      () => ref.read(adminApiProvider)!.deleteClass(report.org.id, c.id),
      done: 'Silindi.',
    );
    _reload(ref, report);
  }

  Future<void> _newCode(BuildContext context, WidgetRef ref, ClassInfo c) async {
    final code = await runAction(
      context,
      () => ref.read(adminApiProvider)!.createCode(report.org.id, OrgRole.member, classId: c.id),
    );
    _reload(ref, report);
    if (code == null || !context.mounted) return;
    await showCodeDialog(context, code, '${c.name} öğrencileri bu kodla katılır.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      SectionHeader(
        title: 'Sınıflar',
        subtitle: report.org.isSchool
            ? 'Sınıflar ve şubeler'
            : 'Ekipler ve departmanlar (ör. Resepsiyon, Restoran)',
        action: FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Yeni sınıf'),
        ),
      ),
      if (report.classes.isEmpty) const Text('Henüz sınıf yok. Ödev vermek için önce bir sınıf oluşturun.'),
      for (final c in report.classes)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Brand.line),
          ),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.groups_2)),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${c.memberCount} kişi'
              '${c.teacherName.isEmpty ? '' : ' · Öğretmen: ${c.teacherName}'}'
              ' · ${report.assignments.where((a) => a.classId == c.id).length} ödev',
            ),
            trailing: Wrap(
              children: [
                TextButton.icon(
                  onPressed: () => _newCode(context, ref, c),
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Katılım kodu'),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: () => _delete(context, ref, c),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ClassDialog extends StatefulWidget {
  const _ClassDialog({required this.teachers});
  final List<MemberRow> teachers;

  @override
  State<_ClassDialog> createState() => _ClassDialogState();
}

class _ClassDialogState extends State<_ClassDialog> {
  final _name = TextEditingController();
  String? _teacher;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeni sınıf'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('class-name'),
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Ad (ör. 8-A, Resepsiyon)'),
          ),
          if (widget.teachers.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _teacher,
              decoration: const InputDecoration(labelText: 'Öğretmen / sorumlu'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Yok (yönetici yönetir)')),
                for (final t in widget.teachers) DropdownMenuItem(value: t.uid, child: Text(t.displayName)),
              ],
              onChanged: (v) => setState(() => _teacher = v),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isNotEmpty) Navigator.pop(context, (_name.text.trim(), _teacher));
        },
        child: const Text('Oluştur'),
      ),
    ],
  );
}

// ---------------------------------------------------------- assignments ----

class AssignmentsSection extends ConsumerWidget {
  const AssignmentsSection({super.key, required this.report});
  final OrgReport report;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => AssignmentDialog(report: report),
    );
    if (created == true) _reload(ref, report);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AssignmentInfo a) async {
    await runAction(
      context,
      () => ref.read(adminApiProvider)!.deleteAssignment(report.org.id, a.id),
      done: 'Ödev kaldırıldı.',
    );
    _reload(ref, report);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(adminClockProvider)();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionHeader(
          title: 'Ödevler',
          subtitle: 'Ders, gramer konusu ya da deneme; son tarihli',
          action: FilledButton.icon(
            onPressed: report.classes.isEmpty ? null : () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Yeni ödev'),
          ),
        ),
        if (report.classes.isEmpty)
          const Text('Ödev vermek için önce Sınıflar bölümünden bir sınıf oluşturun.'),
        if (report.classes.isNotEmpty && report.assignments.isEmpty) const Text('Henüz ödev yok.'),
        for (final a in report.assignments)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Brand.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${a.kind.label} · ${report.className(a.classId)} · son gün ${fmtDate(a.dueAt)}'
                          '${a.dueAt.isBefore(now) ? ' (geçti)' : ''}',
                          style: const TextStyle(color: Brand.muted),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: a.total == 0 ? 0 : a.done / a.total,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                          color: Brand.success,
                          backgroundColor: Brand.line,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('${a.done}/${a.total} tamamladı', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    tooltip: 'Kaldır',
                    onPressed: () => _delete(context, ref, a),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class AssignmentDialog extends ConsumerStatefulWidget {
  const AssignmentDialog({super.key, required this.report});
  final OrgReport report;

  @override
  ConsumerState<AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends ConsumerState<AssignmentDialog> {
  late String _classId = widget.report.classes.first.id;
  AssignmentKind _kind = AssignmentKind.lesson;
  AssignTarget? _target;
  final _title = TextEditingController();
  late DateTime _due = () {
    final d = ref.read(adminClockProvider)().add(const Duration(days: 7));
    return DateTime(d.year, d.month, d.day, 23, 59);
  }();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _target;
    if (t == null) return;
    setState(() => _busy = true);
    final id = await runAction(
      context,
      () => ref
          .read(adminApiProvider)!
          .createAssignment(
            widget.report.org.id,
            classId: _classId,
            kind: t.kind,
            targetId: t.targetId,
            courseId: t.courseId,
            title: _title.text.trim().isEmpty ? t.title : _title.text.trim(),
            dueAt: _due,
          ),
      done: 'Ödev verildi.',
    );
    if (!mounted) return;
    if (id != null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(assignTargetsProvider).value ?? const <AssignTarget>[];
    final options = targets.where((t) => t.kind == _kind).toList();
    return AlertDialog(
      title: const Text('Yeni ödev'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _classId,
              decoration: const InputDecoration(labelText: 'Sınıf'),
              items: [
                for (final c in widget.report.classes) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _classId = v ?? _classId),
            ),
            const SizedBox(height: 16),
            SegmentedButton<AssignmentKind>(
              segments: [
                for (final k in AssignmentKind.values) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _target = null;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AssignTarget>(
              key: ValueKey(_kind),
              isExpanded: true,
              initialValue: _target,
              decoration: const InputDecoration(labelText: 'İçerik'),
              items: [
                for (final t in options)
                  DropdownMenuItem(
                    value: t,
                    child: Text('${t.group} · ${t.title}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (t) => setState(() {
                _target = t;
                if (t != null) _title.text = t.title;
              }),
            ),
            TextField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Başlık (öğrenciler bunu görür)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Son gün'),
              subtitle: Text(fmtDate(_due)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final now = ref.read(adminClockProvider)();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _due,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _due = DateTime(d.year, d.month, d.day, 23, 59));
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _target == null || _busy ? null : _save, child: const Text('Ödevi ver')),
      ],
    );
  }
}

// ---------------------------------------------------------------- codes ----

Future<void> showCodeDialog(BuildContext context, String code, String note) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('Yeni kod'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(note),
        const SizedBox(height: 12),
        CodeChip(code: code),
        const SizedBox(height: 12),
        const Text(
          'Uygulamada: Profil → Kurum koduyla katıl. Her katılım bir koltuk kullanır.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
  ),
);

class CodesSection extends ConsumerWidget {
  const CodesSection({super.key, required this.report});
  final OrgReport report;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(OrgRole, String?)>(
      context: context,
      builder: (_) => _CodeDialog(report: report),
    );
    if (result == null || !context.mounted) return;
    final code = await runAction(
      context,
      () => ref.read(adminApiProvider)!.createCode(report.org.id, result.$1, classId: result.$2),
    );
    _reload(ref, report);
    if (code == null || !context.mounted) return;
    await showCodeDialog(
      context,
      code,
      '${result.$1.label} kodu${result.$2 == null ? '' : ' · ${report.className(result.$2!)}'}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(adminApiProvider)!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionHeader(
          title: 'Davet kodları',
          subtitle: 'Kodu paylaşın; çalışan ya da öğrenci uygulamada Profil → Kurum koduyla katıl.',
          action: FilledButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Yeni kod'),
          ),
        ),
        if (report.codes.isEmpty) const Text('Etkin kod yok.'),
        for (final c in report.codes)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Brand.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CodeChip(code: c.code),
                  Text(
                    '${c.role.label}${c.classId.isEmpty ? '' : ' · ${report.className(c.classId)}'} · '
                    '${c.uses} kez kullanıldı',
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final fresh = await runAction(context, () => api.rotateCode(c.code));
                      _reload(ref, report);
                      if (fresh != null && context.mounted) {
                        await showCodeDialog(context, fresh, 'Eski kod artık çalışmaz.');
                      }
                    },
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Yenile'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await runAction(
                        context,
                        () => api.revokeCode(c.code),
                        done: '${c.pretty} iptal edildi.',
                      );
                      _reload(ref, report);
                    },
                    icon: const Icon(Icons.block, color: Brand.error),
                    label: const Text('İptal et', style: TextStyle(color: Brand.error)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.report});
  final OrgReport report;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  late OrgRole _role = OrgRole.member;
  late String? _classId = widget.report.isAdmin ? null : widget.report.classes.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final roles = r.isAdmin ? OrgRole.values : const [OrgRole.member];
    return AlertDialog(
      title: const Text('Yeni davet kodu'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<OrgRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Katılan kişinin rolü'),
              items: [for (final role in roles) DropdownMenuItem(value: role, child: Text(role.label))],
              onChanged: (v) => setState(() {
                _role = v ?? _role;
                if (_role == OrgRole.admin) _classId = null;
              }),
            ),
            if (_role != OrgRole.admin && r.classes.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Sınıf'),
                items: [
                  if (r.isAdmin) const DropdownMenuItem(value: null, child: Text('Sınıfsız')),
                  for (final c in r.classes) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _classId = v),
              ),
            const SizedBox(height: 12),
            Text(
              _role == OrgRole.admin
                  ? 'Yöneticiler paneli kullanır, koltuk harcamaz ve Premium almaz.'
                  : 'Her katılan bir koltuk kullanır ve plan bitişine kadar Premium alır.',
              style: const TextStyle(color: Brand.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: !r.isAdmin && _classId == null ? null : () => Navigator.pop(context, (_role, _classId)),
          child: const Text('Oluştur'),
        ),
      ],
    );
  }
}
