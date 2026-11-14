import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/account_service.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/firebase/progress_sync.dart';
import '../theme.dart';
import 'auth_screen.dart';

/// "Hesap" card in Profil: account status, cloud backup state and
/// sign-in / sign-out actions.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(progressSyncProvider);
    if (sync.state == SyncState.off) {
      return TapCard(
        child: _Line(
          icon: Icons.phone_android,
          color: Brand.muted,
          title: 'Bu cihazda saklanıyor',
          subtitle: 'Bulut yedekleme bu sürümde kapalı. İlerlemen yalnızca bu cihazda.',
        ),
      );
    }
    final user = ref.watch(authStateProvider).value;
    final service = ref.watch(accountServiceProvider);
    final (icon, color, label) = switch (sync.state) {
      SyncState.synced => (Icons.cloud_done, Brand.success, 'İlerlemen hesabına kaydedildi'),
      SyncState.pending => (
        Icons.cloud_upload_outlined,
        Brand.accent,
        'İnternet gelince hesabına kaydedilecek',
      ),
      SyncState.syncing => (Icons.cloud_sync_outlined, Brand.primary, 'Hesabınla eşitleniyor…'),
      SyncState.error => (Icons.cloud_off, Brand.error, 'Şu an kaydedilemedi, tekrar denenecek'),
      SyncState.guest => (Icons.phone_android, Brand.muted, 'İlerlemen yalnızca bu telefonda'),
      _ => (Icons.cloud_off, Brand.muted, 'Hesap hazırlanıyor…'),
    };
    final signedIn = user != null && !user.isAnonymous;

    return TapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(
            icon: signedIn ? Icons.verified_user : Icons.person_outline,
            color: signedIn ? Brand.primary : Brand.muted,
            title: signedIn
                ? (user.email ?? user.phoneNumber ?? user.displayName ?? 'Giriş yapıldı')
                : 'Misafir hesabı',
            subtitle: signedIn
                ? 'Başka bir telefonda aynı hesapla giriş yap; ilerlemen seninle gelir.'
                : 'Google, e-posta ya da telefonla giriş yap; telefonunu değiştirsen de ilerlemen kaybolmaz.',
          ),
          const SizedBox(height: 12),
          _Line(icon: icon, color: color, title: label),
          if (service != null) ...[
            const SizedBox(height: 12),
            if (!signedIn)
              FilledButton.icon(
                key: const ValueKey('account-sign-in'),
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.mascot,
                  foregroundColor: Brand.onMascot,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Giriş yap / Hesap oluştur'),
                // Not before the guest account exists: an anonymous sign-in
                // still in flight would replace the account signed into here.
                onPressed: user == null
                    ? null
                    : () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: service))),
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Çıkış yap'),
                onPressed: () => _run(context, service.signOut),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on AccountException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.title, this.subtitle});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 28),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(color: Brand.muted, fontSize: 13)),
          ],
        ),
      ),
    ],
  );
}
