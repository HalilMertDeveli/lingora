import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/firebase_providers.dart';
import '../theme.dart';
import 'admin_api.dart';
import 'dashboard.dart';
import 'widgets.dart';

/// The panel's server API, or null when Firebase is off.
final adminApiProvider = Provider<AdminApi?>((ref) {
  final f = ref.watch(functionsProvider);
  return f == null ? null : CallableAdminApi(f);
});

/// Email/password sign-in for the panel (org admins and teachers).
abstract interface class AdminAuth {
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class FirebaseAdminAuth implements AdminAuth {
  FirebaseAdminAuth(this._auth);
  final FirebaseAuth _auth;

  @override
  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> signUp(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

final adminAuthProvider = Provider<AdminAuth?>((ref) {
  final a = ref.watch(firebaseAuthProvider);
  return a == null ? null : FirebaseAdminAuth(a);
});

final orgListProvider = FutureProvider<OrgList>((ref) {
  ref.watch(currentUidProvider); // reload on account change
  return ref.watch(adminApiProvider)!.listOrgs();
});

/// The app's colours and type, but desktop-sized buttons (the app's are
/// full-width, which breaks rows of actions).
ThemeData _panelTheme() {
  final base = buildTheme();
  ButtonStyle compact(ButtonStyle? s) =>
      (s ?? const ButtonStyle()).copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 44)));
  return base.copyWith(
    scaffoldBackgroundColor: Brand.surface,
    filledButtonTheme: FilledButtonThemeData(style: compact(base.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: compact(base.outlinedButtonTheme.style)),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lingora Kurumsal',
    debugShowCheckedModeBanner: false,
    theme: _panelTheme(),
    locale: const Locale('tr'),
    home: const AdminGate(),
  );
}

/// Firebase off → explanation; signed out → sign-in; else the org picker.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adminApiProvider) == null) {
      return const CenteredCard(
        child: Text(
          'Panel Firebase bağlantısı olmadan çalışmaz. '
          '--dart-define=LINGORA_FIREBASE=prod (ya da emulator) ile derleyin.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final user = ref.watch(authStateProvider);
    return switch (user) {
      AsyncData(value: final u?) when !u.isAnonymous => const OrgPickerPage(),
      AsyncLoading() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      _ => const SignInPage(),
    };
  }
}

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _authMessage(Object e) {
    final code = e is FirebaseAuthException ? e.code : '';
    return switch (code) {
      'invalid-email' => 'E-posta adresi geçersiz.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' => 'E-posta ya da şifre hatalı.',
      'email-already-in-use' => 'Bu e-postayla zaten bir hesap var. Giriş yapın.',
      'weak-password' => 'Şifre en az 6 karakter olmalı.',
      'too-many-requests' => 'Çok fazla deneme yapıldı. Biraz sonra tekrar deneyin.',
      _ => 'Giriş yapılamadı. Bağlantınızı kontrol edip tekrar deneyin.',
    };
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 6) {
      setState(() => _error = 'E-posta adresinizi ve en az 6 karakterli şifrenizi girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(adminAuthProvider)!;
    try {
      _signUp ? await auth.signUp(email, _password.text) : await auth.signIn(email, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = _authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Önce e-posta adresinizi yazın.');
      return;
    }
    try {
      await ref.read(adminAuthProvider)!.resetPassword(email);
      if (mounted) setState(() => _error = 'Şifre sıfırlama bağlantısı $email adresine gönderildi.');
    } catch (e) {
      if (mounted) setState(() => _error = _authMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => CenteredCard(
    child: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandTitle(),
          const SizedBox(height: 8),
          Text(
            _signUp ? 'Yönetici hesabı oluşturun' : 'Kurum paneline giriş',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-posta', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('password'),
            controller: _password,
            obscureText: true,
            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Brand.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_signUp ? 'Hesap oluştur' : 'Giriş yap'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _signUp = !_signUp;
                  _error = null;
                }),
                child: Text(_signUp ? 'Hesabım var' : 'Yeni hesap oluştur'),
              ),
              if (!_signUp) TextButton(onPressed: _reset, child: const Text('Şifremi unuttum')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Panelde yalnızca öğrenme ilerlemesi (ders, XP, seri, ödev) görünür. '
            'Çalışanların ve öğrencilerin günlükleri, notları ve sohbetleri paylaşılmaz.',
            style: TextStyle(color: Brand.muted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// Lingora staff see every org; an org admin or teacher goes straight to
/// their org; a fresh account enters its admin code first.
class OrgPickerPage extends ConsumerWidget {
  const OrgPickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(orgListProvider);
    return list.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => CenteredCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(e is AdminException ? e.message : 'Kurumlar yüklenemedi.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(orgListProvider), child: const Text('Tekrar dene')),
            TextButton(
              onPressed: () => ref.read(adminAuthProvider)?.signOut(),
              child: const Text('Çıkış yap'),
            ),
          ],
        ),
      ),
      data: (l) {
        if (!l.lingoraAdmin && l.orgs.length == 1) return OrgDashboard(orgId: l.orgs.single.id);
        if (!l.lingoraAdmin) return const JoinAsAdminPage();
        return StaffOrgsPage(orgs: l.orgs);
      },
    );
  }
}

class JoinAsAdminPage extends ConsumerStatefulWidget {
  const JoinAsAdminPage({super.key});

  @override
  ConsumerState<JoinAsAdminPage> createState() => _JoinAsAdminPageState();
}

class _JoinAsAdminPageState extends ConsumerState<JoinAsAdminPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (code.length != 8 || _name.text.trim().isEmpty) {
      setState(() => _error = 'Size verilen 8 karakterli kodu ve adınızı girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminApiProvider)!.joinWithCode(code, _name.text.trim());
      ref.invalidate(orgListProvider);
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CenteredCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandTitle(),
        const SizedBox(height: 16),
        const Text(
          'Bu hesap henüz bir kuruma bağlı değil. Lingora ekibinin size verdiği yönetici kodunu '
          '(ya da kurumunuzun öğretmen kodunu) girin.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('admin-code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Kod',
            hintText: 'K7QM-3XPA',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('admin-name'),
          controller: _name,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Adınız soyadınız', border: OutlineInputBorder()),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: Brand.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _join, child: const Text('Kuruma bağlan')),
        TextButton(onPressed: () => ref.read(adminAuthProvider)?.signOut(), child: const Text('Çıkış yap')),
      ],
    ),
  );
}

/// Lingora staff: all orgs, create one, change seats or plan end.
class StaffOrgsPage extends ConsumerWidget {
  const StaffOrgsPage({super.key, required this.orgs});
  final List<OrgSummary> orgs;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<OrgFormResult>(context: context, builder: (_) => const OrgFormDialog());
    if (input == null || !context.mounted) return;
    final code = await runAction(
      context,
      () => ref
          .read(adminApiProvider)!
          .createOrg(
            name: input.name,
            isSchool: input.isSchool,
            seats: input.seats,
            planExpiresAt: input.expires,
          ),
    );
    ref.invalidate(orgListProvider);
    if (code == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kurum oluşturuldu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu yönetici kodunu kurumun yetkilisine iletin. Panelde hesap açıp kodu girecek:'),
            const SizedBox(height: 12),
            CodeChip(code: code),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, OrgSummary o) async {
    final input = await showDialog<OrgFormResult>(
      context: context,
      builder: (_) => OrgFormDialog(initial: o),
    );
    if (input == null || !context.mounted) return;
    await runAction(
      context,
      () => ref
          .read(adminApiProvider)!
          .updateOrg(o.id, name: input.name, seats: input.seats, planExpiresAt: input.expires),
      done: 'Kurum güncellendi.',
    );
    ref.invalidate(orgListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Lingora Kurumsal · Kurumlar'),
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ref.invalidate(orgListProvider),
          icon: const Icon(Icons.refresh),
        ),
        TextButton(onPressed: () => ref.read(adminAuthProvider)?.signOut(), child: const Text('Çıkış')),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _create(context, ref),
      icon: const Icon(Icons.add_business),
      label: const Text('Yeni kurum'),
    ),
    body: orgs.isEmpty
        ? const Center(child: Text('Henüz kurum yok. "Yeni kurum" ile başlayın.'))
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final o in orgs)
                Card(
                  child: ListTile(
                    leading: Icon(o.isSchool ? Icons.school : Icons.apartment, color: Brand.primary),
                    title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${o.typeLabel} · ${o.seatsUsed}/${o.seats} koltuk · plan bitişi ${fmtDate(o.planExpiresAt)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Koltuk ve plan',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(context, ref, o),
                    ),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => OrgDashboard(orgId: o.id))),
                  ),
                ),
            ],
          ),
  );
}

class OrgFormResult {
  const OrgFormResult(this.name, this.isSchool, this.seats, this.expires);
  final String name;
  final bool isSchool;
  final int seats;
  final DateTime expires;
}

class OrgFormDialog extends StatefulWidget {
  const OrgFormDialog({super.key, this.initial});
  final OrgSummary? initial;

  @override
  State<OrgFormDialog> createState() => _OrgFormDialogState();
}

class _OrgFormDialogState extends State<OrgFormDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _seats = TextEditingController(text: '${widget.initial?.seats ?? 20}');
  late bool _school = widget.initial?.isSchool ?? false;
  late DateTime _expires = widget.initial?.planExpiresAt ?? DateTime.now().add(const Duration(days: 365));
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _seats.dispose();
    super.dispose();
  }

  void _save() {
    final seats = int.tryParse(_seats.text.trim());
    if (_name.text.trim().length < 2 || seats == null || seats < 1) {
      setState(() => _error = 'Kurum adını ve koltuk sayısını girin.');
      return;
    }
    Navigator.pop(context, OrgFormResult(_name.text.trim(), _school, seats, _expires));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Yeni kurum' : 'Kurumu düzenle'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Kurum adı'),
          ),
          if (widget.initial == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Kurum / şirket'), icon: Icon(Icons.apartment)),
                  ButtonSegment(value: true, label: Text('Okul'), icon: Icon(Icons.school)),
                ],
                selected: {_school},
                onSelectionChanged: (s) => setState(() => _school = s.first),
              ),
            ),
          TextField(
            controller: _seats,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Koltuk (lisans) sayısı'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Plan bitişi'),
            subtitle: Text(fmtDate(_expires)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _expires,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 3 * 365)),
              );
              if (d != null) setState(() => _expires = DateTime(d.year, d.month, d.day, 23, 59));
            },
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: Brand.error)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _save, child: const Text('Kaydet')),
    ],
  );
}
