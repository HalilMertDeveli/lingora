import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../services/notifications.dart';
import '../theme.dart';

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Turns reminders on after asking the OS for permission. If permission is
/// denied, reminders stay off and the user is told why.
Future<void> enableReminders(BuildContext context, WidgetRef ref) async {
  final granted = await ref.read(notificationServiceProvider).requestPermission();
  ref.read(progressProvider.notifier).setReminders(enabled: granted);
  if (!granted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bildirim izni verilmedi. Telefon ayarlarından açabilirsin.')),
    );
  }
}

Future<void> pickReminderTime(BuildContext context, WidgetRef ref) async {
  final current = ref.read(progressProvider).reminderMinutes;
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    helpText: 'Hatırlatma saati',
    builder: (c, child) =>
        MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (picked != null) {
    ref.read(progressProvider.notifier).setReminders(minutes: picked.hour * 60 + picked.minute);
  }
}

/// One-time card on the learning path asking whether to enable reminders.
class ReminderPromptCard extends ConsumerWidget {
  const ReminderPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    if (p.remindersEnabled != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TapCard(
        selected: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: Brand.primary, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Her gün hatırlatayım mı?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Saat ${formatMinutes(p.reminderMinutes)}\'da, o gün ders yapmadıysan kısa bir hatırlatma gönderirim. '
              'Saati profilden değiştirebilirsin.',
              style: const TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => ref.read(progressProvider.notifier).setReminders(enabled: false),
                    child: const Text('Şimdi değil'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => enableReminders(context, ref),
                    child: const Text('Aç'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Notification settings block for the profile screen.
class ReminderSettings extends ConsumerWidget {
  const ReminderSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final on = p.remindersEnabled == true;
    final notifier = ref.read(progressProvider.notifier);
    return TapCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_rounded, color: Brand.primary),
            title: const Text('Günlük hatırlatma', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('O gün ders yapmadıysan'),
            value: on,
            onChanged: (v) => v ? enableReminders(context, ref) : notifier.setReminders(enabled: false),
          ),
          ListTile(
            enabled: on,
            leading: const Icon(Icons.schedule_rounded, color: Brand.primary),
            title: const Text('Saat', style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: Text(
              formatMinutes(p.reminderMinutes),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.primary),
            ),
            onTap: () => pickReminderTime(context, ref),
          ),
        ],
      ),
    );
  }
}
