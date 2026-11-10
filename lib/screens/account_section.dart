import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/products.dart';
import '../services/firebase/account_service.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/firebase/progress_sync.dart';
import '../theme.dart';
import 'paywall_screen.dart';

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
      SyncState.synced => (Icons.cloud_done, Brand.success, 'İlerlemem buluta yedeklendi'),
      SyncState.pending => (
        Icons.cloud_upload_outlined,
        Brand.accent,
        'İnternet gelince buluta yedeklenecek',
      ),
      SyncState.syncing => (Icons.cloud_sync_outlined, Brand.primary, 'Bulutla eşitleniyor…'),
      SyncState.error => (Icons.cloud_off, Brand.error, 'Yedekleme şu an yapılamadı, tekrar denenecek'),
      SyncState.premiumOnly => (Icons.lock_outline, Brand.muted, "Buluta yedekleme Premium'a özel"),
      _ => (Icons.cloud_off, Brand.muted, 'Hesap hazırlanıyor…'),
    };
    final signedIn = user != null && !user.isAnonymous;
    final premiumOnly = sync.state == SyncState.premiumOnly;
    return TapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(
            icon: signedIn ? Icons.verified_user : Icons.person_outline,
            color: signedIn ? Brand.primary : Brand.muted,
            title: signedIn ? (user.email ?? user.displayName ?? 'Giriş yapıldı') : 'Misafir hesabı',
            subtitle: switch ((signedIn, premiumOnly)) {
              (true, false) => 'Başka bir cihazda aynı hesapla giriş yaparak devam edebilirsin.',
              (true, true) => 'Ligler için hesabın hazır. İlerlemen bu cihazda saklanıyor.',
              (false, false) => 'Hesabını bağla, ilerlemen telefonunu değiştirsen de kaybolmasın.',
              (false, true) => 'Hesabını bağla; ligler ücretsiz, bulut yedekleme Premium ile.',
            },
          ),
          const SizedBox(height: 12),
          _Line(
            icon: icon,
            color: color,
            title: label,
            subtitle: premiumOnly ? 'Ücretsiz planda ilerlemen bu cihazda güvende kalır.' : null,
          ),
          if (premiumOnly) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('account-premium-backup'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Premium ile buluta yedekle'),
              onPressed: () => requirePremium(context, ref, PremiumFeature.cloudBackup),
            ),
          ],
          if (service != null) ...[
            const SizedBox(height: 12),
            if (!signedIn) ...[
              FilledButton.icon(
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Google ile bağla'),
                onPressed: () => _run(context, service.signInWithGoogle),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.mail_outline),
                label: const Text('E-posta ile bağla / giriş yap'),
                onPressed: () => showDialog<void>(context: context, builder: (_) => _EmailDialog(service)),
              ),
            ] else
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

class _EmailDialog extends StatefulWidget {
  const _EmailDialog(this.service);
  final AccountService service;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool register}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      register
          ? await widget.service.registerWithEmail(_email.text, _password.text)
          : await widget.service.signInWithEmail(_email.text, _password.text);
      if (mounted) Navigator.pop(context);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('E-posta ile hesap'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-posta'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Şifre (en az 6 karakter)'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Brand.error)),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      TextButton(onPressed: _busy ? null : () => _submit(register: false), child: const Text('Giriş yap')),
      FilledButton(
        onPressed: _busy ? null : () => _submit(register: true),
        child: const Text('Hesap oluştur'),
      ),
    ],
  );
}
