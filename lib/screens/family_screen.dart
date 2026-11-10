import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/family.dart';
import '../services/billing/premium.dart';
import '../services/firebase/firebase_providers.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'paywall_screen.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Family plan: the owner shares an invite code and manages members; others
/// redeem a code; members can leave.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  final _code = TextEditingController();
  FamilyInfo? _info;
  bool _loading = false;
  bool _working = false;
  String? _error;
  String? _notice;

  FamilyBackend? get _backend => ref.read(familyBackendProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final backend = _backend;
    if (backend == null || ref.read(currentUidProvider) == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await backend.getFamily();
      if (mounted) setState(() => _info = info);
    } on FamilyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function(FamilyBackend b) action, {String? done}) async {
    final backend = _backend;
    if (backend == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      await action(backend);
      if (mounted) setState(() => _notice = done);
      await _load();
    } on FamilyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _redeem() => _run((b) async {
    final e = await b.redeem(_code.text);
    ref.read(premiumControllerProvider.notifier).applyServer(e);
    _code.clear();
  }, done: 'Aileye katıldın, Premium açıldı. 🎉');

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(familyBackendProvider);
    final uid = ref.watch(currentUidProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Aile planı')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Aile planında bir kişi yıllık ödeme yapar, $familySeats kişiye kadar herkes kendi hesabıyla '
              'Premium kullanır. İlerlemeler ayrı kalır; kimse diğerinin çalışmasını görmez.',
              style: TextStyle(color: Brand.muted, height: 1.35),
            ),
            SizedBox(height: 16),
            if (backend == null)
              _Box(
                'Aile planı hesap ve sunucu bağlantısı gerektirir. Bu sürümde sunucu bağlantısı açık değil; '
                'uygulamanın bulut özellikli sürümünde kullanılabilecek.',
              )
            else if (uid == null)
              _Box(
                'Aile planına katılmak ya da aileni yönetmek için önce Profil > Hesap bölümünden giriş yap.',
              )
            else if (_loading && _info == null)
              Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else ...[
              if (_error != null) _Box(_error!, color: Brand.errorBg),
              if (_notice != null) _Box(_notice!, color: Brand.successBg),
              ...switch (_info?.role ?? FamilyRole.none) {
                FamilyRole.owner => _owner(_info!),
                FamilyRole.member => _member(_info!),
                FamilyRole.none => _none(),
              },
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _owner(FamilyInfo info) => [
    Text('Ailen', style: Theme.of(context).textTheme.titleLarge),
    SizedBox(height: 4),
    Text(
      '${info.members.length + 1}/${info.seats} kişi · '
      '${info.active && info.expiresAt != null ? 'plan ${_date(info.expiresAt!)} tarihine kadar geçerli' : 'plan sona erdi'}',
      style: TextStyle(color: Brand.muted),
    ),
    SizedBox(height: 10),
    _MemberTile(name: 'Sen (yönetici)', trailing: null),
    for (final m in info.members)
      _MemberTile(
        name: m.displayName ?? 'Lingora üyesi',
        subtitle: m.joinedAt == null ? null : 'Katıldı: ${_date(m.joinedAt!)}',
        trailing: IconButton(
          tooltip: 'Aileden çıkar',
          icon: Icon(Icons.person_remove_rounded, color: Brand.error),
          onPressed: _working
              ? null
              : () async {
                  final ok = await _confirm(
                    'Aileden çıkarılsın mı?',
                    '${m.displayName ?? 'Bu üye'} aile planından çıkarılacak ve Premium erişimi hemen sona '
                        'erecek. İlerlemesi silinmez.',
                    'Çıkar',
                  );
                  if (ok) await _run((b) => b.removeMember(m.uid), done: 'Üye aileden çıkarıldı.');
                },
        ),
      ),
    SizedBox(height: 18),
    Text('Davet kodu', style: Theme.of(context).textTheme.titleLarge),
    SizedBox(height: 6),
    if (!info.active)
      _Box('Plan sona erdiği için yeni kişi davet edilemez. Aboneliğini yenileyince kod oluşturabilirsin.')
    else if (info.freeSeats <= 0)
      _Box('Ailen dolu. Yeni birini eklemek için önce bir üyeyi çıkar.')
    else ...[
      if (info.code case final code?)
        TapCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '${code.substring(0, 4)}-${code.substring(4)}',
                      key: ValueKey('family-code'),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                    if (info.codeExpiresAt != null)
                      Text(
                        '${_date(info.codeExpiresAt!)} tarihine kadar geçerli · ${info.freeSeats} boş yer',
                        style: TextStyle(color: Brand.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kopyala',
                icon: Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(SnackBar(content: Text('Kod kopyalandı.')));
                },
              ),
            ],
          ),
        ),
      SizedBox(height: 8),
      Text(
        'Kodu yalnızca ailenle paylaş. Kodu giren kişi Profil > Aile planı bölümünden ailene katılır.',
        style: TextStyle(color: Brand.muted, fontSize: 12),
      ),
      SizedBox(height: 10),
      PressableButton(
        key: ValueKey('family-new-code'),
        label: info.code == null ? 'DAVET KODU OLUŞTUR' : 'YENİ KOD OLUŞTUR',
        color: Brand.primary,
        onPressed: _working ? null : () => _run((b) => b.createInvite()),
      ),
    ],
  ];

  List<Widget> _member(FamilyInfo info) => [
    _Box(
      '${info.ownerName ?? 'Bir Lingora kullanıcısının'} aile planındasın. Premium'
      '${info.expiresAt == null ? '' : ' ${_date(info.expiresAt!)} tarihine kadar'} açık.',
      color: Brand.successBg,
    ),
    PressableButton(
      label: 'AİLEDEN AYRIL',
      outlined: true,
      color: Brand.error,
      foreground: Brand.error,
      onPressed: _working
          ? null
          : () async {
              final ok = await _confirm(
                'Aileden ayrılınsın mı?',
                'Aile planından gelen Premium erişimin hemen sona erer. İlerlemen silinmez.',
                'Ayrıl',
              );
              if (ok) await _run((b) => b.leave(), done: 'Aile planından ayrıldın.');
            },
    ),
  ];

  List<Widget> _none() => [
    Text('Davet kodun var mı?', style: Theme.of(context).textTheme.titleLarge),
    SizedBox(height: 8),
    TextField(
      key: ValueKey('family-code-field'),
      controller: _code,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Davet kodu',
        hintText: 'ABCD-EFGH',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _redeem(),
    ),
    SizedBox(height: 10),
    PressableButton(
      key: ValueKey('family-join'),
      label: _working ? 'BEKLENİYOR…' : 'AİLEYE KATIL',
      color: Brand.primary,
      onPressed: _working ? null : _redeem,
    ),
    SizedBox(height: 22),
    Text('Aile planı satın al', style: Theme.of(context).textTheme.titleLarge),
    SizedBox(height: 6),
    Text(
      'Aile planını satın alan kişi yönetici olur ve davet kodu oluşturur.',
      style: TextStyle(color: Brand.muted),
    ),
    SizedBox(height: 10),
    PressableButton(
      label: 'AİLE PLANINI GÖR',
      outlined: true,
      color: Brand.primary,
      foreground: Brand.primary,
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PaywallScreen(showFamily: true)),
        );
        if (mounted) await _load();
      },
    ),
  ];
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.name, this.subtitle, required this.trailing});
  final String name;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(child: Icon(Icons.person_rounded)),
    title: Text(name, style: TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: trailing,
  );
}

class _Box extends StatelessWidget {
  const _Box(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(color: color ?? Brand.surface, borderRadius: BorderRadius.circular(14)),
    child: Text(text, style: TextStyle(height: 1.35)),
  );
}
