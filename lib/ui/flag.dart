import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../theme.dart';

/// A small flag image (owner-supplied set, see docs/assets.md) with soft
/// corners and a hairline border so white stripes stay visible on cards.
class FlagIcon extends StatelessWidget {
  const FlagIcon(this.asset, {super.key, this.width = 28});
  final String asset;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 2 / 3,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(width * 0.14),
      border: Border.all(color: context.palette.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.asset(
      asset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ColoredBox(color: context.palette.surface),
    ),
  );
}

/// "Aksan": the English voice reads in an American or a British accent.
/// Shown in the course drawer under the English courses.
class AccentPicker extends ConsumerWidget {
  const AccentPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(appSettingsProvider).accent;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Sesli okuma aksanı',
            style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
          ),
          for (final a in Accent.values)
            ChoiceChip(
              key: Key('accent-${a.name}'),
              selected: a == accent,
              showCheckmark: false,
              avatar: FlagIcon(a.flag, width: 22),
              label: Text(a.label),
              onSelected: (_) => ref.read(appSettingsProvider.notifier).setAccent(a),
            ),
        ],
      ),
    );
  }
}

/// Turizm İngilizcesi: "Misafirlerin nereden geliyor?" Guests from all these
/// countries talk to a Turkish hotel or restaurant in English; ticking them
/// is a reminder that one course covers them all.
class GuestFlagsCard extends ConsumerWidget {
  const GuestFlagsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guests = ref.watch(appSettingsProvider).guests;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TapCard(
        key: const Key('guest-flags'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Misafirlerin nereden geliyor?', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              guests.isEmpty
                  ? 'Hepsiyle ortak dilin İngilizce. Karşılaştıklarını işaretle.'
                  : '${guests.length} ülkeden misafir: resepsiyon, restoran ve rehberlik dersleri hepsinde işine yarar.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(key: code, value: name) in guestCountries.entries)
                  FilterChip(
                    key: Key('guest-$code'),
                    selected: guests.contains(code),
                    showCheckmark: false,
                    avatar: FlagIcon(flagAsset(code), width: 22),
                    label: Text(name),
                    onSelected: (_) => ref.read(appSettingsProvider.notifier).toggleGuest(code),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
