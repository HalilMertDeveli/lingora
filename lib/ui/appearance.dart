import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../theme.dart';

/// Profil > Görünüm: Çocuk modu switch and light/dark choice.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    final t = Theme.of(context).textTheme;
    return TapCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('kid-mode-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text('Çocuk modu', style: t.titleMedium),
            subtitle: Text('Maskot, emojiler ve kutlamalarla daha eğlenceli görünüm.', style: t.bodySmall),
            value: s.isKid,
            onChanged: (v) => n.setMode(v ? AppMode.kid : AppMode.adult),
          ),
          const SizedBox(height: 8),
          Text('Tema', style: t.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<ThemePref>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemePref.system,
                label: Text('Sistem'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemePref.light,
                label: Text('Açık'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(value: ThemePref.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {s.theme},
            onSelectionChanged: (v) => n.setTheme(v.first),
          ),
        ],
      ),
    );
  }
}
