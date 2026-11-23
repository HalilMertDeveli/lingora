import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../services/contacts/contact_matching.dart';
import '../services/contacts/contacts_source.dart';
import '../services/friends.dart';
import '../services/growth/referral.dart';
import '../theme.dart';
import 'friend_name_prompt.dart';
import 'friends_screen.dart';

/// Play link shared with phone-book contacts who do not use Çenebaz.
const dilmacPlayLink = 'https://play.google.com/store/apps/details?id=com.cenebaz.app';

/// Invitation for a contact who is not on Çenebaz: the Play link and, when
/// there is one, the user's friend code to type after installing.
String contactInviteText(String? friendCode) =>
    "Çenebaz'da birlikte İngilizce çalışalım, ortak seri yapalım! Uygulamayı indir: $dilmacPlayLink"
    "${friendCode == null ? '' : ' Sonra Arkadaşlar bölümüne kodumu yaz: $friendCode'}";

enum _Stage { intro, loading, denied, blocked, done, error }

/// "Rehberden bul": people in the phone book who use Çenebaz (and chose to
/// be findable by number), friend requests to them and invitations for the
/// rest. The phone book stays on the phone; only salted hashes of the
/// numbers are looked up (docs/arkadaslar.md).
class ContactsFriendsScreen extends ConsumerStatefulWidget {
  const ContactsFriendsScreen({super.key});

  @override
  ConsumerState<ContactsFriendsScreen> createState() => _ContactsFriendsScreenState();
}

class _ContactsFriendsScreenState extends ConsumerState<ContactsFriendsScreen> {
  _Stage _stage = _Stage.intro;
  ContactBook? _book;
  final _busy = <String>{};

  Future<void> _search() async {
    final api = ref.read(friendsApiProvider);
    if (api == null) return;
    final source = ref.read(contactsSourceProvider);
    setState(() => _stage = _Stage.loading);
    try {
      final access = await source.requestAccess();
      if (access != ContactsAccess.granted) {
        if (mounted) {
          setState(() => _stage = access == ContactsAccess.denied ? _Stage.denied : _Stage.blocked);
        }
        return;
      }
      final book = await findContactsOnApp(api, await source.load());
      if (mounted) {
        setState(() {
          _book = book;
          _stage = _Stage.done;
        });
      }
    } on Object {
      if (mounted) setState(() => _stage = _Stage.error);
    }
  }

  Future<void> _request(ContactOnApp c) async {
    // The request carries the sender's name: ask for one if there is none.
    if (!await ensureFriendName(context, ref)) return;
    final api = ref.read(friendsApiProvider);
    if (api == null || !mounted) return;
    setState(() => _busy.add(c.uid));
    try {
      final result = await api.sendRequest(c.uid);
      if (!mounted) return;
      if (result == RequestResult.friends) {
        await offerSharedStreak(
          context,
          api,
          pairId: pairIdOf(api.uid, c.uid),
          friendUid: c.uid,
          name: c.name,
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${c.name} için arkadaşlık isteği gönderildi.')));
      }
    } on FriendException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(c.uid));
    }
  }

  Future<void> _invite() async {
    // The invitation may carry the friend code, which shows the name.
    if (!await ensureFriendName(context, ref)) return;
    final api = ref.read(friendsApiProvider);
    if (api == null) return;
    String text;
    try {
      // The referral code (both get Premium days) when Cloud Functions
      // answer; otherwise the friend code.
      final referral = ref.read(referralServiceProvider);
      if (referral == null) throw StateError('no referral');
      text = inviteShareText(await referral.myInvite().timeout(const Duration(seconds: 4)));
    } on Object {
      String? code;
      try {
        code = await api.myCode().timeout(const Duration(seconds: 4));
      } on Object {
        code = null;
      }
      text = contactInviteText(code);
    }
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Çenebaz daveti'));
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(friendsApiProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Rehberden bul')),
      body: SafeArea(
        child: api == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: FriendsBox(
                  icon: Icons.group_rounded,
                  text: 'Rehberden arkadaş bulmak için bir Çenebaz hesabıyla giriş yap.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_stage != _Stage.done) ...[
                    Text('Rehberindeki arkadaşlarını bul', style: t.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Rehberin telefonunda kalır. Numaralar telefonunda tek yönlü bir şifreyle (hash) '
                      'karıştırılır; yalnızca bu şifreler, numarasıyla bulunmayı seçen Çenebaz kullanıcılarıyla '
                      'karşılaştırılır. Hiçbir isim ya da numara sunucuya yüklenmez.',
                      style: TextStyle(color: Brand.muted, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ..._body(api, t),
                  const SizedBox(height: 24),
                  const DiscoverableTile(),
                ],
              ),
      ),
    );
  }

  List<Widget> _body(FriendsApi api, TextTheme t) {
    switch (_stage) {
      case _Stage.intro:
        return [
          FilledButton.icon(
            key: const ValueKey('contacts-search'),
            onPressed: _search,
            icon: const Icon(Icons.contacts_rounded),
            label: const Text('Rehberden bul'),
          ),
        ];
      case _Stage.loading:
        return const [
          Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          ),
        ];
      case _Stage.denied:
      case _Stage.blocked:
        return [
          const FriendsBox(
            key: ValueKey('contacts-denied'),
            icon: Icons.lock_outline_rounded,
            text: 'Rehber izni verilmedi. Sorun değil: arkadaşlarını 8 haneli kodla eklemeye devam edebilirsin.',
          ),
          const SizedBox(height: 12),
          if (_stage == _Stage.blocked)
            OutlinedButton(
              onPressed: () => ref.read(contactsSourceProvider).openSettings(),
              child: const Text('Ayarlardan izin ver'),
            )
          else
            OutlinedButton(onPressed: _search, child: const Text('Yeniden dene')),
          TextButton(
            key: const ValueKey('contacts-use-code'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Kodla ekle'),
          ),
        ];
      case _Stage.error:
        return [
          const FriendsBox(
            icon: Icons.cloud_off_rounded,
            text: 'Şu an aranamadı. İnternetini kontrol edip yeniden dene.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _search, child: const Text('Yeniden dene')),
        ];
      case _Stage.done:
        return _results(api, t);
    }
  }

  List<Widget> _results(FriendsApi api, TextTheme t) {
    final book = _book!;
    final friends = {...?ref.watch(friendshipsProvider).value?.map((f) => f.friendUid)};
    final outgoing = {...?ref.watch(outgoingRequestsProvider).value?.map((r) => r.to)};
    final incoming = {
      for (final r in ref.watch(incomingRequestsProvider).value ?? const <FriendRequest>[]) r.from: r,
    };
    return [
      Text("Çenebaz'da olanlar", style: t.titleMedium),
      const SizedBox(height: 8),
      if (book.onApp.isEmpty)
        const FriendsBox(
          key: ValueKey('contacts-none'),
          icon: Icons.search_off_rounded,
          text: 'Rehberinde, numarasıyla bulunmayı açmış bir Çenebaz kullanıcısı yok. Aşağıdan davet edebilirsin.',
        ),
      for (final c in book.onApp)
        _ContactRow(
          key: ValueKey('contact-on-app-${c.uid}'),
          name: c.name,
          color: Brand.primary,
          subtitle: outgoing.contains(c.uid) && !friends.contains(c.uid) ? 'İstek gönderildi' : null,
          action: friends.contains(c.uid)
              ? const Chip(label: Text('Arkadaşsınız'))
              : incoming[c.uid] != null
              ? FilledButton(
                  key: ValueKey('contact-accept-${c.uid}'),
                  style: compactButton,
                  onPressed: () => acceptFriendRequest(context, ref, incoming[c.uid]!),
                  child: const Text('Kabul et'),
                )
              : outgoing.contains(c.uid)
              ? OutlinedButton(
                  key: ValueKey('contact-pending-${c.uid}'),
                  style: compactButton,
                  onPressed: () => api
                      .deleteRequest(FriendRequest(from: api.uid, to: c.uid, name: '', avatar: ''))
                      .catchError((_) {}),
                  child: const Text('Geri al'),
                )
              : FilledButton.icon(
                  key: ValueKey('contact-request-${c.uid}'),
                  style: compactButton,
                  onPressed: _busy.contains(c.uid) ? null : () => _request(c),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('İstek gönder'),
                ),
        ),
      if (book.truncated)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Rehberinin ilk $maxContactLookups numarasına bakıldı.',
            style: TextStyle(color: Brand.muted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 20),
      Text('Davet et', style: t.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Bu kişiler Çenebaz kullanmıyor ya da numarasıyla bulunmayı açmamış.',
        style: TextStyle(color: Brand.muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      for (final c in book.others.take(300))
        _ContactRow(
          name: c.name,
          color: Brand.muted,
          action: TextButton.icon(
            key: ValueKey('contact-invite-${c.name}'),
            style: compactButton,
            onPressed: _invite,
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Davet et'),
          ),
        ),
    ];
  }
}

/// Buttons sized to their label (the app theme makes buttons full width).
const compactButton = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 40)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
);

/// One phone-book entry: initial, name (and a note), an action on the right.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    super.key,
    required this.name,
    required this.color,
    required this.action,
    this.subtitle,
  });
  final String name;
  final Color color;
  final Widget action;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        _Initial(name: name, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) Text(subtitle!, style: TextStyle(color: Brand.muted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        action,
      ],
    ),
  );
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final first = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        first,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// "Telefon numaramla bulunabilirim": off by default. Only an account with
/// a number verified by phone sign-in can turn it on; the rules check the
/// hash against that verified number.
class DiscoverableTile extends ConsumerStatefulWidget {
  const DiscoverableTile({super.key});

  @override
  ConsumerState<DiscoverableTile> createState() => _DiscoverableTileState();
}

class _DiscoverableTileState extends ConsumerState<DiscoverableTile> {
  FriendsApi? _for;
  bool? _on;
  bool _busy = false;

  void _load(FriendsApi? api) {
    _for = api;
    _on = null;
    if (api == null || api.verifiedPhone == null) return;
    unawaited(
      api.discoverable().then(
        (v) {
          if (mounted && _for == api) setState(() => _on = v ?? false);
        },
        onError: (Object _) {
          if (mounted && _for == api) setState(() => _on = false);
        },
      ),
    );
  }

  Future<void> _set(FriendsApi api, bool on) async {
    setState(() => _busy = true);
    try {
      await api.setDiscoverable(on);
      if (mounted) setState(() => _on = on);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedilemedi. İnternetini kontrol edip yeniden dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(friendsApiProvider);
    if (Brand.isKid || api == null) return const SizedBox.shrink();
    if (api != _for) _load(api);
    final verified = api.verifiedPhone != null;
    return SwitchListTile(
      key: const ValueKey('discoverable-switch'),
      contentPadding: EdgeInsets.zero,
      value: _on ?? false,
      onChanged: !verified || _busy || _on == null ? null : (v) => _set(api, v),
      title: const Text('Telefon numaramla bulunabilirim'),
      subtitle: Text(
        verified
            ? 'Açıkken numaranı rehberinde kayıtlı olan Çenebaz kullanıcıları seni bulup arkadaşlık isteği '
                  'gönderebilir. Numaran açık hâliyle saklanmaz.'
            : 'Bu seçenek, numarasını telefonla girişte doğrulamış hesaplarda açılır.',
        style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.3),
      ),
    );
  }
}
