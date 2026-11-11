import 'package:flutter/material.dart';

import '../services/firebase/account_service.dart';
import '../theme.dart';
import '../ui/mascot.dart';

/// "Giriş yap / Hesap oluştur": e-mail + password, password reset, and
/// Google or phone sign-in, in the mascot orange. Pops with `true` on success.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.service, this.register = false});
  final AccountService service;

  /// Opens on "Hesap oluştur" instead of "Giriş yap".
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  late bool _register = widget.register;
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done, bool close = true}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      if (close) Navigator.of(context).pop(true);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'E-posta adresini kontrol et.');
      return;
    }
    if (_register && _password.text != _password2.text) {
      setState(() => _error = 'Şifreler aynı değil.');
      return;
    }
    _run(
      () => _register
          ? widget.service.registerWithEmail(_email.text, _password.text)
          : widget.service.signInWithEmail(_email.text, _password.text),
      done: _register ? 'Hesabın oluşturuldu.' : 'Giriş yapıldı.',
    );
  }

  void _forgot() => _run(
    () => widget.service.sendPasswordResetEmail(_email.text),
    done: 'Şifre sıfırlama bağlantısı ${_email.text.trim()} adresine gönderildi.',
    close: false,
  );

  Future<void> _phone() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => PhoneSignInDialog(widget.service));
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      key: const ValueKey('auth-screen'),
      backgroundColor: p.card,
      appBar: AppBar(backgroundColor: p.card, elevation: 0, scrolledUnderElevation: 0),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _register ? 'Hesabını oluştur' : 'Tekrar hoş geldin!',
                              style: t.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _register
                                  ? 'İlerlemen hesabına bağlansın, telefonunu değiştirsen de kaybolmasın.'
                                  : 'Öğrenmeye kaldığın yerden devam edelim.',
                              style: t.bodyLarge?.copyWith(color: p.muted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Pofuduk with his phone: the account illustration.
                      Image.asset(
                        pofudukAccount,
                        key: const Key('auth-illustration'),
                        width: context.isKid ? 104 : 80,
                        height: context.isKid ? 104 : 80,
                        semanticLabel: 'Pofuduk ve telefonu',
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _ModeSwitch(
                    register: _register,
                    onChanged: _busy
                        ? null
                        : (r) => setState(() {
                            _register = r;
                            _error = null;
                          }),
                  ),
                  const SizedBox(height: 20),
                  _Label('E-posta'),
                  _Field(
                    key: const ValueKey('auth-email'),
                    controller: _email,
                    icon: Icons.mail_outline_rounded,
                    hint: 'ornek@eposta.com',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    action: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  _Label('Şifre'),
                  _Field(
                    key: const ValueKey('auth-password'),
                    controller: _password,
                    icon: Icons.lock_outline_rounded,
                    hint: _register ? 'En az 6 karakter' : 'Şifren',
                    obscure: _hidden,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    action: _register ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: _register ? null : (_) => _submit(),
                    trailing: IconButton(
                      key: const ValueKey('auth-toggle-password'),
                      tooltip: _hidden ? 'Şifreyi göster' : 'Şifreyi gizle',
                      icon: Icon(
                        _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: p.mascot,
                      ),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 16),
                    _Label('Şifre (tekrar)'),
                    _Field(
                      key: const ValueKey('auth-password2'),
                      controller: _password2,
                      icon: Icons.lock_outline_rounded,
                      hint: 'Şifreni tekrar yaz',
                      obscure: _hidden,
                      autofillHints: const [AutofillHints.newPassword],
                      action: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('auth-forgot'),
                        style: TextButton.styleFrom(foregroundColor: p.mascot),
                        onPressed: _busy ? null : _forgot,
                        child: const Text('Şifremi unuttum', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        key: const ValueKey('auth-error'),
                        style: TextStyle(color: p.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: p.line)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('ya da şununla devam et', style: TextStyle(color: p.muted)),
                      ),
                      Expanded(child: Divider(color: p.line)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ProviderButton(
                          key: const ValueKey('auth-google'),
                          label: 'Google',
                          // Google's own "G" mark, unaltered, on white (see docs/assets.md).
                          leading: Container(
                            width: 28,
                            height: 28,
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Image.asset('assets/brand/google_g.png', semanticLabel: 'Google logosu'),
                          ),
                          onPressed: _busy ? null : () => _run(widget.service.signInWithGoogle),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProviderButton(
                          key: const ValueKey('auth-phone'),
                          label: 'Telefon',
                          leading: Icon(Icons.smartphone_rounded, color: p.mascot, size: 26),
                          onPressed: _busy ? null : _phone,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const ValueKey('auth-submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.mascot,
                    foregroundColor: p.onMascot,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: p.onMascot),
                        )
                      : Text(_register ? 'Hesap oluştur' : 'Giriş yap'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.register, required this.onChanged});
  final bool register;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tab(String label, bool value, Key key) {
      final on = register == value;
      return Expanded(
        child: Material(
          color: on ? p.card : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          elevation: on ? 1 : 0,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: on ? p.mascot : p.muted),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          tab('Giriş yap', false, const ValueKey('auth-mode-signin')),
          tab('Hesap oluştur', true, const ValueKey('auth-mode-register')),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.action,
    this.onSubmitted,
    this.trailing,
  });
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: action,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: !obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: p.mascotBg,
        prefixIcon: Icon(icon, color: p.mascot),
        suffixIcon: trailing,
        enabledBorder: border(p.mascot.withValues(alpha: 0.55), 1),
        focusedBorder: border(p.mascot, 2),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({super.key, required this.label, required this.leading, required this.onPressed});
  final String label;
  final Widget leading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

/// Two steps: phone number, then the 6-digit SMS code. Pops with `true`
/// once signed in.
class PhoneSignInDialog extends StatefulWidget {
  const PhoneSignInDialog(this.service, {super.key});
  final AccountService service;

  @override
  State<PhoneSignInDialog> createState() => _PhoneSignInDialogState();
}

class _PhoneSignInDialogState extends State<PhoneSignInDialog> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _step(Future<void> Function() run) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await run();
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _step(() async {
    final id = await widget.service.startPhoneSignIn(_phone.text);
    if (!mounted) return;
    if (id == null) {
      Navigator.pop(context, true); // verified automatically
    } else {
      setState(() => _verificationId = id);
    }
  });

  Future<void> _confirm() => _step(() async {
    await widget.service.confirmPhoneCode(_verificationId!, _code.text);
    if (mounted) Navigator.pop(context, true);
  });

  @override
  Widget build(BuildContext context) {
    final codeStep = _verificationId != null;
    final p = context.palette;
    return AlertDialog(
      title: const Text('Telefonla giriş'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!codeStep)
            TextField(
              key: const ValueKey('phone-number'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Telefon numarası', hintText: '0532 123 45 67'),
            )
          else ...[
            Text('${_phone.text} numarasına gelen 6 haneli kodu gir.', style: TextStyle(color: p.muted)),
            TextField(
              key: const ValueKey('phone-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'SMS kodu'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: p.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        if (codeStep)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _verificationId = null),
            child: const Text('Numarayı değiştir'),
          ),
        FilledButton(
          onPressed: _busy ? null : (codeStep ? _confirm : _sendCode),
          child: Text(codeStep ? 'Onayla' : 'Kod gönder'),
        ),
      ],
    );
  }
}
