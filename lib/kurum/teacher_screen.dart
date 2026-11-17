import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';
import '../theme.dart';
import 'kurum.dart';

String errorLabel(String name) => TrErrorCategory.byName(name)?.label ?? name;

/// The class's most common mistake kinds: how many students have each in
/// their top three, most common first.
List<(String, int)> classTopErrors(List<ClassMember> members, [int count = 3]) {
  final counts = <String, int>{};
  for (final m in members) {
    for (final e in m.stats.topErrors) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
  }
  final list = counts.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return list.take(count).toList();
}

/// Öğretmen paneli: the teacher's classes and a button to open a new one.
class TeacherScreen extends ConsumerWidget {
  const TeacherScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final license = ref.read(orgLicenseProvider).value;
    final api = ref.read(kurumApiProvider);
    if (license == null || api == null) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _NewClassDialog(teacherName: ref.read(kurumNameHintProvider)),
    );
    if (result == null) return;
    try {
      await api.createClass(name: result.$1, teacherName: result.$2, org: license.org);
    } on KurumException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(teacherClassesProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Öğretmen paneli')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('teacher-new-class'),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Sınıf aç'),
      ),
      body: SafeArea(
        child: switch (classes) {
          AsyncData(value: final list) when list.isEmpty => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Henüz sınıfın yok. "Sınıf aç" ile bir sınıf oluştur; uygulama sana 8 karakterlik bir '
              'kod verir. Öğrencilerin Profil → "Sınıf koduyla katıl" ile bu kodu girer.',
              style: t.bodyLarge,
            ),
          ),
          AsyncData(value: final list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final c in list) ...[
                TapCard(
                  key: Key('teacher-class-${c.code}'),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ClassScreen(code: c.code))),
                  child: Row(
                    children: [
                      const IconBadge(icon: Icons.groups_rounded, emoji: '🏫'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              'Kod: ${c.code}${c.open ? '' : ' · katılım kapalı'}',
                              style: TextStyle(color: Brand.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Brand.muted),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          AsyncError() => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sınıflar yüklenemedi. İnternet bağlantını kontrol et.'),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _NewClassDialog extends StatefulWidget {
  const _NewClassDialog({required this.teacherName});
  final String teacherName;

  @override
  State<_NewClassDialog> createState() => _NewClassDialogState();
}

class _NewClassDialogState extends State<_NewClassDialog> {
  final _name = TextEditingController();
  late final _teacher = TextEditingController(text: widget.teacherName);

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    super.dispose();
  }

  bool get _valid {
    final n = _name.text.trim(), tn = _teacher.text.trim();
    return n.isNotEmpty && n.length <= 40 && tn.isNotEmpty && tn.length <= 24;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeni sınıf'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('class-name-field'),
          controller: _name,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Sınıf adı (ör. 8-A İngilizce)'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('class-teacher-field'),
          controller: _teacher,
          maxLength: 24,
          decoration: const InputDecoration(labelText: 'Öğrencilerin göreceği adınız'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        key: const Key('class-create'),
        onPressed: _valid ? () => Navigator.pop(context, (_name.text.trim(), _teacher.text.trim())) : null,
        child: const Text('Oluştur'),
      ),
    ],
  );
}

/// One class: its code, whether it is open and every student's summary.
class ClassScreen extends ConsumerWidget {
  const ClassScreen({super.key, required this.code});
  final String code;

  Future<void> _remove(BuildContext context, WidgetRef ref, ClassMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.name} çıkarılsın mı?'),
        content: const Text(
          'Öğrenci sınıftan çıkar ve ilerlemesi artık size gelmez. Kodla yeniden katılmasını '
          'istemiyorsanız katılımı kapatın.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            key: const Key('member-remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(kurumApiProvider)!.removeMember(code, m.uid));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ClassRoom c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} silinsin mi?'),
        content: const Text(
          'Sınıf ve öğrencilerin bu sınıftaki özetleri silinir. Öğrencilerin kendi '
          'ilerlemesi kendilerinde kalır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            key: const Key('class-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(kurumApiProvider)!.deleteClass(c.code));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on KurumException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(teacherClassesProvider).value?.where((c) => c.code == code).firstOrNull;
    final members = ref.watch(classMembersProvider(code));
    final now = ref.read(clockProvider)();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(room?.name ?? 'Sınıf'),
        actions: [
          if (room != null)
            IconButton(
              key: const Key('class-delete'),
              tooltip: 'Sınıfı sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, room),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TapCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sınıf kodu', style: TextStyle(color: Brand.muted, fontSize: 13)),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          code,
                          key: const Key('class-code'),
                          style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 4),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kopyala',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Kod kopyalandı.')));
                        },
                      ),
                      IconButton(
                        tooltip: 'Paylaş',
                        icon: const Icon(Icons.share_rounded),
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text:
                                '${room?.name ?? 'Sınıfımıza'} katılmak için Dilmaç uygulamasında Profil → '
                                '"Sınıf koduyla katıl" bölümüne şu kodu gir: $code',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (room != null)
                    SwitchListTile(
                      key: const Key('class-open'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Yeni öğrenci katılabilir'),
                      subtitle: const Text(
                        'Herkes katıldıktan sonra kapatın; kod başkasına geçse de kimse giremez.',
                      ),
                      value: room.open,
                      onChanged: (v) => _run(context, () => ref.read(kurumApiProvider)!.setOpen(code, v)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            switch (members) {
              AsyncData(value: final list) when list.isEmpty => Text(
                'Henüz öğrenci yok. Kodu paylaşın; öğrenciler katıldıkça burada görünür.',
                style: t.bodyLarge,
              ),
              AsyncData(value: final list) => _MembersView(
                members: list,
                now: now,
                onRemove: (m) => _remove(context, ref, m),
              ),
              AsyncError() => const Text('Öğrenciler yüklenemedi. İnternet bağlantını kontrol et.'),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
    );
  }
}

class _MembersView extends StatelessWidget {
  const _MembersView({required this.members, required this.now, required this.onRemove});

  final List<ClassMember> members;
  final DateTime now;
  final void Function(ClassMember) onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = classTopErrors(members);
    final weekTotal = members.fold<int>(0, (s, m) => s + m.stats.weekXpAt(now));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${members.length} öğrenci · bu hafta toplam $weekTotal XP', style: t.titleMedium),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Sınıfın en sık hataları', style: TextStyle(color: Brand.muted, fontSize: 13)),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (name, n) in top)
                Chip(key: Key('class-error-$name'), label: Text('${errorLabel(name)} · $n öğrenci')),
            ],
          ),
        ],
        const SizedBox(height: 12),
        for (final m in members) ...[
          TapCard(
            key: Key('member-${m.uid}'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '🔥 ${m.stats.streak} gün seri · ${m.stats.unitsDone} ünite · '
                        '${m.stats.lessonsDone} ders · bu hafta ${m.stats.weekXpAt(now)} XP',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (m.stats.topErrors.isNotEmpty)
                        Text(
                          'Sık hata: ${m.stats.topErrors.map(errorLabel).join(', ')}',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('member-remove-${m.uid}'),
                  tooltip: 'Sınıftan çıkar',
                  icon: Icon(Icons.person_remove_outlined, color: Brand.muted),
                  onPressed: () => onRemove(m),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
