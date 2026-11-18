import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legal_links.dart';
import '../services/growth/remote_flags.dart';
import '../theme.dart';
import 'consent_sheet.dart';
import 'invite_screen.dart';

/// Profil: "Arkadaşını davet et" (when the Remote Config flag is on) and
/// "Gizlilik" (analytics consent).
class GrowthProfileSection extends ConsumerWidget {
  const GrowthProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final referral = ref.watch(remoteFlagsProvider.select((f) => f.referralEnabled));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (referral) ...[
          const SizedBox(height: 24),
          Text('Arkadaşını davet et', style: t.titleLarge),
          const SizedBox(height: 12),
          TapCard(
            key: const ValueKey('profile-invite'),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InviteScreen())),
            child: Row(
              children: [
                const Glyph(emoji: '🎁', icon: Icons.card_giftcard_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Arkadaşını davet et: o katılınca ikiniz de 7 gün Premium kazanın.',
                    style: TextStyle(color: Brand.muted),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Brand.muted),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Gizlilik', style: t.titleLarge),
        const SizedBox(height: 12),
        const AnalyticsConsentTile(),
        const SizedBox(height: 12),
        TapCard(
          key: const ValueKey('privacy-policy-link'),
          onTap: () => openExternalLink(context, privacyPolicyUrl),
          child: Row(
            children: [
              const Glyph(emoji: '🔒', icon: Icons.privacy_tip_outlined),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Gizlilik Politikası', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.open_in_new_rounded, color: Brand.muted),
            ],
          ),
        ),
      ],
    );
  }
}
