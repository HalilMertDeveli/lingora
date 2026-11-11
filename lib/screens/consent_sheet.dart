import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/growth/analytics.dart';
import '../theme.dart';

/// KVKK-friendly explanation shown before asking (and in Profil).
const analyticsConsentText =
    'Dilbaz\'ı geliştirmek için hangi ekranların kullanıldığını ve nerede zorlanıldığını '
    'anonim olarak ölçmek istiyoruz (ör. "ders bitti", "okuma açıldı"). '
    'Adın, e-postan, yazdıkların, ses kayıtların ve konum bilgin gönderilmez; reklam '
    'kimliği kullanılmaz ve veriler reklam için kullanılmaz. Veriler Google Firebase Analytics '
    'ile işlenir. İzin vermesen de uygulamanın tamamını kullanabilirsin; kararını istediğin '
    'zaman Profil > Gizlilik bölümünden değiştirebilirsin.';

/// Asks once, with two equal choices and no pre-selected answer.
Future<void> askAnalyticsConsent(BuildContext context, WidgetRef ref) async {
  final allowed = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: IconBadge(icon: Icons.insights_rounded, emoji: '📊', size: 52),
            ),
            const SizedBox(height: 8),
            Text(
              'Anonim kullanım istatistikleri',
              style: Theme.of(c).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(analyticsConsentText, style: TextStyle(height: 1.4)),
            const SizedBox(height: 6),
            Text(
              'Ayrıntılar: Gizlilik Politikası (Profil > Gizlilik).',
              style: TextStyle(color: Brand.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('consent-no'),
                    onPressed: () => Navigator.of(c).pop(false),
                    child: const Text('İzin verme'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('consent-yes'),
                    onPressed: () => Navigator.of(c).pop(true),
                    child: const Text('İzin ver'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (allowed != null) ref.read(analyticsConsentProvider.notifier).set(allowed);
}

/// Wraps the first screen and asks for analytics consent once, right at the
/// start (before onboarding), only in builds where analytics exists.
class ConsentGate extends ConsumerStatefulWidget {
  const ConsentGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends ConsumerState<ConsentGate> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    if (_asked || !mounted || !ref.read(shouldAskAnalyticsConsentProvider)) return;
    _asked = true;
    await askAnalyticsConsent(context, ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Profil > Gizlilik: change the analytics decision at any time.
class AnalyticsConsentTile extends ConsumerWidget {
  const AnalyticsConsentTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(analyticsSinkProvider) == null) {
      return TapCard(
        child: Text(
          'Bu sürümde kullanım istatistiği toplanmıyor. İlerlemen ve notların yalnızca bu cihazda '
          '(ve açtıysan kendi hesabının bulut yedeğinde) tutulur.',
          style: TextStyle(color: Brand.muted),
        ),
      );
    }
    final allowed = ref.watch(analyticsConsentProvider) ?? false;
    return TapCard(
      child: SwitchListTile(
        key: const ValueKey('analytics-consent-switch'),
        contentPadding: EdgeInsets.zero,
        value: allowed,
        onChanged: (v) => ref.read(analyticsConsentProvider.notifier).set(v),
        title: const Text('Anonim kullanım istatistikleri', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text(
          'Ad, e-posta, yazdıkların ve ses kayıtları gönderilmez; reklam için kullanılmaz. '
          'Kapatırsan cihazdaki analiz kimliği de silinir.',
          style: TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
