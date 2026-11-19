import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legal_links.dart';
import '../theme.dart';
import 'consent_sheet.dart';
import 'invite_nudge.dart' show inviteVisible;
import 'invite_screen.dart';

/// Profil: "Arkadaşını davet et" (when the Remote Config flag is on) and
/// "Gizlilik" (analytics consent).
class GrowthProfileSection extends ConsumerWidget {
  const GrowthProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    // No referral UI in Çocuk modu.
    final referral = inviteVisible(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (referral) ...[
          const SizedBox(height: 24),
          Text('Arkadaşını getir', style: t.titleLarge),
          const SizedBox(height: 12),
          TapCard(
            key: const ValueKey('profile-invite'),
            color: Brand.accentBg,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InviteScreen())),
            child: Row(
              children: [
                const Glyph(emoji: '🎁', icon: Icons.card_giftcard_rounded, size: 34),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'İkiniz de 1 hafta Premium kazanın',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text('Arkadaşın katılıp ilk dersini bitirince ödül ikinize de tanımlanır.'),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Brand.primary),
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
