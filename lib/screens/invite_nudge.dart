import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_settings.dart';
import '../data/progress.dart';
import '../services/growth/analytics.dart';
import '../services/growth/referral.dart';
import '../services/growth/remote_flags.dart';
import '../theme.dart';
import 'invite_screen.dart';

/// Opens the system share sheet with the invite message and Play link.
Future<void> shareInvite(WidgetRef ref, InviteInfo info) async {
  logEvent(ref, AnalyticsEvent.inviteShare());
  await SharePlus.instance.share(ShareParams(text: inviteShareText(info), subject: 'Dilmaç daveti'));
}

/// Whether the invite programme may be shown at all: the Remote Config flag
/// is on and the app is not in Çocuk modu (no referral UI for children).
bool inviteVisible(WidgetRef ref) =>
    ref.watch(remoteFlagsProvider.select((f) => f.referralEnabled)) &&
    !ref.watch(appSettingsProvider.select((s) => s.isKid));

/// Where a nudge appears (also its key suffix).
enum InviteNudgePlace { perfectLesson, streak }

/// "Arkadaşını getir" card after a perfect lesson or in the streak
/// celebration. At most one every [gapDays] days so it never nags, never in
/// Çocuk modu, and nothing outside a ProviderScope.
class InviteNudge extends StatelessWidget {
  const InviteNudge({super.key, required this.place});
  final InviteNudgePlace place;

  static const gapDays = 3;
  static const shownKey = 'growth.invite_nudge.shown_ms';

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return const SizedBox.shrink();
    }
    return _InviteNudgeBody(place: place);
  }
}

class _InviteNudgeBody extends ConsumerStatefulWidget {
  const _InviteNudgeBody({required this.place});
  final InviteNudgePlace place;

  @override
  ConsumerState<_InviteNudgeBody> createState() => _InviteNudgeBodyState();
}

class _InviteNudgeBodyState extends ConsumerState<_InviteNudgeBody> {
  late final bool _show;

  @override
  void initState() {
    super.initState();
    // Decided once, so a rebuild does not make it disappear or re-count.
    final prefs = ref.read(prefsProvider);
    final now = ref.read(clockProvider)();
    final last = prefs.getInt(InviteNudge.shownKey);
    final due = last == null ||
        now.difference(DateTime.fromMillisecondsSinceEpoch(last)) >= const Duration(days: InviteNudge.gapDays);
    final flags = ref.read(remoteFlagsProvider);
    _show = due && flags.referralEnabled && !ref.read(appSettingsProvider).isKid;
    if (_show) prefs.setInt(InviteNudge.shownKey, now.millisecondsSinceEpoch);
  }

  Future<void> _share() async {
    final service = ref.read(referralServiceProvider);
    if (service != null) {
      try {
        final info = await service.myInvite(deviceId: ref.read(installIdProvider)).timeout(const Duration(seconds: 6));
        await shareInvite(ref, info);
        return;
      } on Object {
        // Fall through to the invite screen, which explains the problem.
      }
    }
    if (mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InviteScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final title = switch (widget.place) {
      InviteNudgePlace.perfectLesson => 'Harika gidiyorsun! Bir arkadaşını da getir',
      InviteNudgePlace.streak => 'Seriyi arkadaşınla birlikte sürdür',
    };
    return Container(
      key: ValueKey('invite-nudge-${widget.place.name}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Brand.accentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.accent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          const Glyph(emoji: '🎁', icon: Icons.card_giftcard_rounded, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                Text(
                  'O ilk dersini bitirince ikiniz de 1 hafta Premium kazanın.',
                  style: TextStyle(color: Brand.muted, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey('invite-nudge-share'),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Davet et', style: TextStyle(fontWeight: FontWeight.w900)),
            onPressed: _share,
          ),
        ],
      ),
    );
  }
}
