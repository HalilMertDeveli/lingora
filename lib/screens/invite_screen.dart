import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../services/growth/analytics.dart';
import '../services/growth/referral.dart';
import '../theme.dart';

/// "Arkadaşını davet et": the user's code, a share button and a field to
/// redeem a friend's code. Both sides get 7 days of Premium.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _code = TextEditingController();
  Future<InviteInfo>? _info;
  bool _busy = false;
  String? _error;
  bool _redeemed = false;

  @override
  void initState() {
    super.initState();
    _info = ref.read(referralServiceProvider)?.myInvite();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _share(InviteInfo info) async {
    logEvent(ref, AnalyticsEvent.inviteShare());
    await SharePlus.instance.share(ShareParams(text: inviteShareText(info), subject: 'Lingora daveti'));
  }

  Future<void> _redeem(ReferralService service) async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service.redeem(code, deviceId: ref.read(installIdProvider));
      logEvent(ref, AnalyticsEvent.inviteRedeem('ok'));
      if (mounted) setState(() => _redeemed = true);
    } on ReferralException catch (e) {
      logEvent(ref, AnalyticsEvent.inviteRedeem(e.reason));
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = const ReferralException('offline').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(referralServiceProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Arkadaşını davet et')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text('🎁', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Birlikte öğrenin, ikiniz de kazanın', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text(
              'Arkadaşın Lingora\'ya katılıp kodunu girdiğinde ikiniz de 7 gün Premium kazanırsınız. '
              'Ödeme bilgisi istenmez, süre bitince kendiliğinden ücretsiz sürüme dönülür.',
              style: TextStyle(color: Brand.muted, height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (service == null)
              const _Box(
                icon: Icons.cloud_off_rounded,
                text:
                    'Davet programı için internet bağlantısı ve bir Lingora hesabı gerekir. '
                    'Profil > Hesap bölümünden hesabını bağlayıp tekrar dene.',
              )
            else ...[
              _myCode(context),
              const SizedBox(height: 24),
              Text('Davet kodun mu var?', style: t.titleMedium),
              const SizedBox(height: 8),
              if (_redeemed)
                const _Box(
                  icon: Icons.celebration_rounded,
                  color: Brand.successBg,
                  text: 'Kod kabul edildi! 7 günlük Premium birkaç saniye içinde hesabına tanımlanır.',
                )
              else ...[
                TextField(
                  key: const ValueKey('invite-code-field'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Örn. K7M3QXA',
                    errorText: _error,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _redeem(service),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _busy ? null : () => _redeem(service),
                  child: Text(_busy ? 'Kontrol ediliyor…' : 'Kodu kullan'),
                ),
              ],
            ],
            const SizedBox(height: 24),
            const Text(
              'Kurallar: Kod yalnızca yeni hesaplarda (ilk 14 gün), hesap ve cihaz başına bir kez kullanılabilir. '
              'Davet eden kişi ayda en fazla 5 ödül kazanır. Kötüye kullanımda ödüller geri alınabilir.',
              style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myCode(BuildContext context) => FutureBuilder<InviteInfo>(
    future: _info,
    builder: (context, snap) {
      if (snap.hasError) {
        final e = snap.error;
        return _Box(
          icon: Icons.error_outline_rounded,
          color: Brand.errorBg,
          text: e is ReferralException ? e.message : const ReferralException('offline').message,
        );
      }
      final info = snap.data;
      if (info == null) {
        return const Center(
          child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        );
      }
      return TapCard(
        child: Column(
          children: [
            const Text('Senin davet kodun', style: TextStyle(color: Brand.muted)),
            const SizedBox(height: 4),
            SelectableText(
              info.code,
              key: const ValueKey('invite-code'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4),
            ),
            const SizedBox(height: 4),
            Text(
              'Bu ay ${info.rewardedThisMonth}/${info.maxPerMonth} ödül kazandın.',
              style: const TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Kopyala'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: info.code));
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(const SnackBar(content: Text('Kod kopyalandı')));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Paylaş'),
                    onPressed: () => _share(info),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.icon, required this.text, this.color = Brand.surface});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: Brand.ink),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}
