import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/progress.dart';
import '../services/firebase/account_service.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/friends.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/shop_visuals.dart';
import 'auth_screen.dart';
import 'friend_profile_screen.dart';

/// Text shared with a friend: the code and where to type it.
String friendShareText(String code) =>
    "Dilmaç'ta birlikte İngilizce çalışalım! Uygulamada Lig > Arkadaşlar'a gir ve kodumu yaz: $code";

/// "Arkadaşlar": the user's code, adding a friend by code, the friend list
/// with the shared streak and preset cheers. Free; no penalties, no ads.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _code = TextEditingController();
  Future<String>? _myCode;
  FriendsApi? _codeFor;
  bool _busy = false;
  String? _error;
  String? _added;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _add(FriendsApi api) async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _added = null;
    });
    try {
      final name = await api.addFriend(_code.text);
      _code.clear();
      if (mounted) setState(() => _added = name);
    } on FriendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = const FriendException('offline').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(friendsApiProvider);
    if (api != _codeFor) {
      _codeFor = api;
      _myCode = api?.myCode();
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Arkadaşlar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Birlikte çalışın, seriyi birlikte büyütün',
              style: t.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'İkiniz de aynı gün günlük hedefinizi tamamlayınca ortak seriniz bir artar. '
              'Bir gün kaçarsa seri yeniden başlar; ceza yok. Arkadaşına destek ya da tebrik gönderebilirsin.',
              style: TextStyle(color: Brand.muted, height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (Brand.isKid)
              const _Box(
                key: ValueKey('friends-kid'),
                icon: Icons.child_care_rounded,
                text:
                    'Çocuk modunda arkadaş ekleme kapalı. Bir yetişkin Profil > Görünüm bölümünden '
                    'Çocuk modunu kapatabilir.',
              )
            else if (api == null)
              const _NoAccount()
            else ...[
              _myCodeCard(),
              const SizedBox(height: 20),
              Text('Arkadaş ekle', style: t.titleMedium),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('friend-code-field'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(friendCodeLength),
                ],
                decoration: InputDecoration(
                  hintText: 'Arkadaşının 8 haneli kodu',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _add(api),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('friend-add'),
                onPressed: _busy ? null : () => _add(api),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_busy ? 'Ekleniyor…' : 'Ekle'),
              ),
              if (_added != null) ...[
                const SizedBox(height: 10),
                _Box(
                  icon: Icons.celebration_rounded,
                  color: Brand.successBg,
                  text: '$_added ile artık arkadaşsınız!',
                ),
              ],
              const SizedBox(height: 24),
              Text('Arkadaşların', style: t.titleMedium),
              const SizedBox(height: 8),
              const _FriendList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _myCodeCard() => FutureBuilder<String>(
    future: _myCode,
    builder: (context, snap) {
      final code = snap.data;
      return TapCard(
        child: Column(
          children: [
            Text(
              'Senin kodun',
              style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (code != null)
              SelectableText(
                code,
                key: const ValueKey('friend-my-code'),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4),
              )
            else if (snap.hasError)
              Text('Kod alınamadı. İnternetini kontrol et.', style: TextStyle(color: Brand.error))
            else
              const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
            if (code != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Kod kopyalandı')));
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Kopyala'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('friend-share'),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: friendShareText(code), subject: 'Dilmaç arkadaşlık daveti'),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Paylaş'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _NoAccount extends ConsumerWidget {
  const _NoAccount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(accountServiceProvider);
    final user = ref.watch(authStateProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Box(
          icon: Icons.group_rounded,
          text:
              'Arkadaş eklemek için ücretsiz bir Dilmaç hesabı gerekir (Google, e-posta ya da telefon). '
              'Misafir kullanımda arkadaş listen telefonla birlikte kaybolurdu.',
        ),
        if (service != null && user != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('friends-sign-in'),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Giriş yap / Hesap oluştur'),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: service))),
          ),
        ],
      ],
    );
  }
}

class _FriendList extends ConsumerWidget {
  const _FriendList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendshipsProvider);
    return friends.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _Box(icon: Icons.cloud_off_rounded, text: 'Arkadaş listesi yüklenemedi.'),
      data: (list) {
        if (list == null || list.isEmpty) {
          return const _Box(
            key: ValueKey('friends-empty'),
            icon: Icons.waving_hand_rounded,
            text: 'Henüz arkadaşın yok. Kodunu paylaş ya da bir arkadaşının kodunu yaz.',
          );
        }
        final today = friendDay(ref.watch(clockProvider)());
        final sorted = [...list]..sort((a, b) => b.streakOn(today).compareTo(a.streakOn(today)));
        return Column(
          children: [for (final f in sorted) _FriendCard(friend: f, today: today)],
        );
      },
    );
  }
}

class _FriendCard extends ConsumerWidget {
  const _FriendCard({required this.friend, required this.today});
  final Friendship friend;
  final int today;

  Future<void> _remove(BuildContext context, FriendsApi api) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Arkadaşlıktan çıkar'),
        content: Text('${friend.name} listenden çıkarılsın mı? Ortak seriniz silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çıkar')),
        ],
      ),
    );
    if (ok == true) await api.remove(friend.pairId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(friendsApiProvider);
    final cheers = ref.watch(cheersProvider(friend.pairId)).value ?? const <Cheer>[];
    final profile = ref.watch(friendProfileProvider(friend.friendUid)).value;
    final me = api?.uid;
    final received = [
      for (final c in cheers)
        if (c.from == friend.friendUid) c.kind,
    ];
    final sent = {
      for (final c in cheers)
        if (c.from == me) c.kind,
    };
    final streak = friend.streakOn(today);
    final both = friend.meDone(today) && friend.friendDone(today);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        key: ValueKey('friend-${friend.friendUid}'),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => FriendProfileScreen(friend: friend))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The friend's own photo and name (profiles/{uid}) in their
                // Mağaza frame, their Mağaza avatar without a photo; the
                // animal and the name saved with the friendship otherwise.
                StyledAvatar(
                  key: ValueKey('friend-avatar-${friend.friendUid}'),
                  photo: profile?.photo,
                  size: 44,
                  avatarId: profile?.showcase?.avatar,
                  frameId: profile?.showcase?.frame,
                  fallback: CircleAvatar(
                    radius: 22,
                    backgroundColor: Brand.surface,
                    child: Text(friend.avatar, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? friend.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        friend.best > 0
                            ? 'En iyi ortak seri: ${friend.best} gün'
                            : 'Ortak seriniz bugün başlayabilir',
                        style: TextStyle(color: Brand.muted, fontSize: 12),
                      ),
                      if (profile?.showcase?.items.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        ShowcaseStrip(showcase: profile!.showcase, size: 22),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.local_fire_department, color: streak > 0 ? Brand.streak : Brand.line),
                Text(
                  '$streak',
                  key: ValueKey('friend-streak-${friend.friendUid}'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: streak > 0 ? Brand.streak : Brand.muted,
                  ),
                ),
                if (api != null)
                  PopupMenuButton<String>(
                    tooltip: 'Seçenekler',
                    onSelected: (_) => _remove(context, api),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remove', child: Text('Arkadaşlıktan çıkar')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _GoalChip(label: 'Sen', done: friend.meDone(today)),
                _GoalChip(label: friend.name, done: friend.friendDone(today)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              both
                  ? 'Bugün ikiniz de hedefinizi tamamladınız. Seri güvende!'
                  : friend.friendDone(today)
                  ? '${friend.name} bugünkü hedefini tamamladı. Sıra sende!'
                  : friend.meDone(today)
                  ? 'Sen hazırsın. ${friend.name} hedefini tamamlayınca seri artar.'
                  : 'İkiniz de bugünkü hedefi tamamlayınca seri bir artar.',
              style: TextStyle(color: Brand.muted, height: 1.3),
            ),
            if (received.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final k in received)
                Text(
                  '${k.emoji} ${friend.name}: ${k.label}',
                  key: ValueKey('cheer-in-${k.name}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
            if (api != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in CheerKind.values)
                    ActionChip(
                      key: ValueKey('cheer-${friend.friendUid}-${k.name}'),
                      avatar: Text(k.emoji),
                      label: Text(sent.contains(k) ? '${k.label} ✓' : k.label),
                      onPressed: sent.contains(k)
                          ? null
                          : () async {
                              try {
                                await api.sendCheer(friend, k, today);
                              } on Object {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Gönderilemedi, yeniden dene.')),
                                  );
                                }
                              }
                            },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
      color: done ? Brand.success : Brand.muted,
      size: 18,
    ),
    label: Text(done ? '$label: hedef tamam' : '$label: bugün henüz değil'),
  );
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color ?? Brand.surface, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: Brand.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}
