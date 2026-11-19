import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../services/firebase/account_service.dart';
import '../services/firebase/firebase_providers.dart';
import '../theme.dart';
import 'auth_screen.dart';

/// Until when "Sonra" hides the card (milliseconds since epoch).
const accountNudgeUntilKey = 'account_nudge_until_v1';

/// How long "Sonra" hides the card.
const accountNudgeSnooze = Duration(days: 3);

/// Card on top of the path for guests: progress lives only on this phone
/// until they sign in. Hidden without Firebase, for signed-in learners, while
/// the guest account is still being created, and for a few days after
/// "Sonra".
class AccountNudgeCard extends ConsumerStatefulWidget {
  const AccountNudgeCard({super.key});

  /// Whether the card would show now (the reminder card waits behind it).
  static bool visible(WidgetRef ref) {
    if (ref.watch(accountServiceProvider) == null) return false;
    final user = ref.watch(authStateProvider).value;
    if (user == null || !user.isAnonymous) return false;
    // Asked after the first lesson, when there is progress to keep.
    if (ref.watch(progressProvider.select((p) => p.lessonsDone)) == 0) return false;
    final until = ref.watch(prefsProvider).getInt(accountNudgeUntilKey) ?? 0;
    return ref.watch(clockProvider)().millisecondsSinceEpoch >= until;
  }

  @override
  ConsumerState<AccountNudgeCard> createState() => _AccountNudgeCardState();
}

class _AccountNudgeCardState extends ConsumerState<AccountNudgeCard> {
  bool _hidden = false;

  void _later() {
    final now = ref.read(clockProvider)();
    ref.read(prefsProvider).setInt(accountNudgeUntilKey, now.add(accountNudgeSnooze).millisecondsSinceEpoch);
    setState(() => _hidden = true);
  }

  Future<void> _signIn(AccountService service) async {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: service)));
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden || !AccountNudgeCard.visible(ref)) return const SizedBox.shrink();
    final service = ref.watch(accountServiceProvider)!;
    final p = ref.watch(progressProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TapCard(
        key: const ValueKey('account-nudge'),
        selected: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: Brand.primary, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'İlerlemeni kaybetme',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p.lessonsDone == 1
                  ? 'İlk dersin bitti! Şu an misafirsin; ilerlemen yalnızca bu telefonda. Giriş yap, '
                        'telefonunu değiştirsen de kaldığın yerden devam et.'
                  : p.lessonsDone > 0
                  ? 'Şu an misafirsin; ${p.lessonsDone} dersin yalnızca bu telefonda. Giriş yap, telefonunu '
                        'değiştirsen de kaldığın yerden devam et.'
                  : 'Şu an misafirsin; ilerlemen yalnızca bu telefonda. Google, e-posta ya da telefonla giriş '
                        'yap, telefonunu değiştirsen de kaybolmasın.',
              style: TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('account-nudge-later'),
                    onPressed: _later,
                    child: const Text('Sonra'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('account-nudge-sign-in'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _signIn(service),
                    child: const Text('Giriş yap'),
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
