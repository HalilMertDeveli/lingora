import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'admin_api.dart';

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// "2026-11-09" -> "09.11.2026".
String fmtDayKey(String? key) {
  if (key == null || key.length != 10) return '—';
  return '${key.substring(8)}.${key.substring(5, 7)}.${key.substring(0, 4)}';
}

/// Runs a server action; shows its Turkish error (or [done]) in a snack bar.
/// Returns null when it failed.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await action();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return r;
  } on AdminException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Brand.error));
    return null;
  }
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.translate_rounded, color: Brand.primary, size: 30),
        SizedBox(width: 8),
        Text(
          'Dilbaz',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Brand.ink),
        ),
        SizedBox(width: 6),
        Text(
          'Kurumsal',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w400, color: Brand.primary),
        ),
      ],
    ),
  );
}

class CenteredCard extends StatelessWidget {
  const CenteredCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Brand.line),
            ),
            child: Padding(padding: const EdgeInsets.all(28), child: child),
          ),
        ),
      ),
    ),
  );
}

/// A join code with a copy button.
class CodeChip extends StatelessWidget {
  const CodeChip({super.key, required this.code});
  final String code;

  String get _pretty => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  @override
  Widget build(BuildContext context) => InputChip(
    avatar: const Icon(Icons.vpn_key_outlined, size: 18),
    label: SelectableText(
      _pretty,
      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.5),
    ),
    deleteIcon: const Icon(Icons.copy, size: 18),
    deleteButtonTooltipMessage: 'Kopyala',
    onDeleted: () {
      Clipboard.setData(ClipboardData(text: _pretty));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_pretty kopyalandı.')));
    },
  );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.hint, this.icon, this.color});
  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
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
                if (icon != null) Icon(icon, size: 18, color: color ?? Brand.muted),
                if (icon != null) const SizedBox(width: 6),
                Expanded(
                  child: Text(label, style: TextStyle(color: Brand.muted)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color ?? Brand.ink),
            ),
            if (hint != null) Text(hint!, style: TextStyle(color: Brand.muted, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) Text(subtitle!, style: TextStyle(color: Brand.muted)),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}
