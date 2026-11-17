import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../theme.dart';
import 'kurum.dart';
import 'teacher_screen.dart';

String kurumDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// "Okul ve kurum" in Profil: the org license, the classes the student
/// joined and, for teachers, the class panel. Hidden without Firebase.
class KurumSection extends ConsumerWidget {
  const KurumSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(kurumApiProvider) == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final license = ref.watch(orgLicenseProvider).value;
    final now = ref.read(clockProvider)();
    final active = license != null && license.activeAt(now);
    final classes = ref.watch(myClassesProvider).value ?? const <ClassRoom>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        key: const Key('kurum-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Okul ve kurum', style: t.titleLarge),
          const SizedBox(height: 8),
          if (active)
            _Row(
              key: const Key('kurum-license'),
              icon: Icons.verified_rounded,
              emoji: '🏫',
              title: '${license.org} · ${license.role.label} lisansı',
              subtitle: 'Premium ${kurumDate(license.expiresAt)} tarihine kadar kurumundan.',
            )
          else
            _Row(
              key: const Key('kurum-redeem'),
              icon: Icons.key_rounded,
              emoji: '🔑',
              title: 'Lisans kodu gir',
              subtitle: 'Okulun ya da kurumun sana bir lisans kodu verdiyse Premium buradan açılır.',
              onTap: () => showDialog<void>(context: context, builder: (_) => const RedeemLicenseDialog()),
            ),
          const SizedBox(height: 8),
          for (final c in classes) ...[
            _Row(
              key: Key('kurum-class-${c.code}'),
              icon: Icons.groups_rounded,
              emoji: '👩‍🏫',
              title: c.name,
              subtitle:
                  '${c.teacherName} · ${c.org}. Öğretmenin serini, ünitelerini ve hata türlerini görür.',
              onTap: () => _confirmLeave(context, ref, c),
            ),
            const SizedBox(height: 8),
          ],
          if (classes.length < maxClassesPerStudent)
            _Row(
              key: const Key('kurum-join'),
              icon: Icons.group_add_rounded,
              emoji: '🙋',
              title: 'Sınıf koduyla katıl',
              subtitle: 'Öğretmeninin verdiği 8 karakterlik kodu gir.',
              onTap: () => showDialog<void>(context: context, builder: (_) => const JoinClassDialog()),
            ),
          if (active && license.isTeacher) ...[
            const SizedBox(height: 8),
            _Row(
              key: const Key('kurum-teacher'),
              icon: Icons.co_present_rounded,
              emoji: '📋',
              title: 'Öğretmen paneli',
              subtitle: 'Sınıf aç, kodu paylaş, öğrencilerinin ilerlemesini gör.',
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeacherScreen())),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref, ClassRoom c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.name),
        content: Text(
          '${c.teacherName} bu sınıfta senin serini, tamamladığın üniteleri, haftalık XP\'ni ve en sık '
          'hata türlerini görüyor. E-postanı, telefonunu, notlarını ve günlüğünü görmez.\n\n'
          'Sınıftan ayrılırsan öğretmenin artık ilerlemeni göremez.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kapat')),
          TextButton(
            key: const Key('kurum-leave'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sınıftan ayrıl'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(kurumApiProvider)?.leaveClass(c.code);
    } on KurumException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TapCard(
    onTap: onTap,
    child: Row(
      children: [
        IconBadge(icon: icon, emoji: emoji),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
            ],
          ),
        ),
        if (onTap != null) Icon(Icons.chevron_right, color: Brand.muted),
      ],
    ),
  );
}

/// A one-field dialog that runs [onSubmit] and shows its Turkish error.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({
    required this.title,
    required this.intro,
    required this.codeLabel,
    required this.submitLabel,
    required this.onSubmit,
    this.nameLabel,
    this.initialName = '',
  });

  final String title;
  final String intro;
  final String codeLabel;
  final String submitLabel;
  final String? nameLabel;
  final String initialName;

  /// Returns the success text.
  final Future<String> Function(String code, String name) onSubmit;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  late final _name = TextEditingController(text: widget.initialName);
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (widget.nameLabel != null && (name.isEmpty || name.length > 24)) {
      setState(() => _error = 'Adın 1–24 karakter olmalı.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.onSubmit(_code.text, name);
      if (mounted) setState(() => _done = done);
    } on KurumException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = const KurumException('offline').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: _done != null
        ? Text(_done!, key: const Key('kurum-dialog-done'))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.intro, style: TextStyle(color: Brand.muted, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('kurum-code-field'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: widget.codeLabel),
              ),
              if (widget.nameLabel != null) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('kurum-name-field'),
                  controller: _name,
                  maxLength: 24,
                  decoration: InputDecoration(labelText: widget.nameLabel),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('kurum-dialog-error'),
                    style: TextStyle(color: Brand.error),
                  ),
                ),
            ],
          ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(_done != null ? 'Tamam' : 'Vazgeç')),
      if (_done == null)
        FilledButton(
          key: const Key('kurum-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.submitLabel),
        ),
    ],
  );
}

class RedeemLicenseDialog extends ConsumerWidget {
  const RedeemLicenseDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _CodeDialog(
    title: 'Lisans kodu',
    intro:
        'Kurumunun verdiği 12 karakterlik kodu gir (ör. ABCD-EFGH-JKLM). Kod tek kişiliktir; '
        'girdiğinde hesabına bağlanır.',
    codeLabel: 'Lisans kodu',
    submitLabel: 'Etkinleştir',
    onSubmit: (code, _) async {
      final api = ref.read(kurumApiProvider);
      if (api == null) throw const KurumException('offline');
      final l = await api.redeem(code);
      return '${l.org} lisansın etkin. Premium ${kurumDate(l.expiresAt)} tarihine kadar açık.'
          '${l.isTeacher ? ' Öğretmen panelini Profil\'de bulabilirsin.' : ''}';
    },
  );
}

class JoinClassDialog extends ConsumerWidget {
  const JoinClassDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _CodeDialog(
    title: 'Sınıfa katıl',
    intro:
        'Öğretmenin bu sınıfta yalnızca serini, tamamladığın üniteleri, haftalık XP\'ni ve en sık '
        'hata türlerini görür; e-postanı ve telefonunu görmez. Adın olarak ilk adını ya da '
        'öğretmeninin tanıyacağı bir takma ad yaz.',
    codeLabel: 'Sınıf kodu',
    submitLabel: 'Katıl',
    nameLabel: 'Öğretmeninin göreceği adın',
    initialName: ref.read(kurumNameHintProvider).split(' ').first,
    onSubmit: (code, name) async {
      final api = ref.read(kurumApiProvider);
      if (api == null) throw const KurumException('offline');
      final room = await api.joinClass(code, name: name, stats: ref.read(classStatsProvider));
      return '${room.name} sınıfına katıldın. ${room.teacherName} ilerlemeni görebilir.';
    },
  );
}
