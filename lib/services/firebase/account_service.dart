import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_config.dart';
import 'firebase_providers.dart';

/// Error shown to the user, already in Turkish.
class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign-in, upgrade and sign-out. Upgrading an anonymous user links the new
/// credential to the same uid, so the cloud copy of the progress is kept. If
/// the account already exists, we sign into it instead; the progress on this
/// device is then merged into that account by the sync (nothing is lost).
class AccountService {
  AccountService(this._auth, {Future<AuthCredential?> Function()? googleCredential})
    : _googleCredential = googleCredential ?? _nativeGoogleCredential;

  final FirebaseAuth _auth;
  final Future<AuthCredential?> Function() _googleCredential;

  User? get _user => _auth.currentUser;

  Future<void> signInAnonymously() => _guard(() async {
    await _auth.signInAnonymously();
  });

  /// Creates an e-mail account (keeping the current anonymous progress).
  Future<void> registerWithEmail(String email, String password) => _guard(() async {
    final cred = EmailAuthProvider.credential(email: email.trim(), password: password);
    final user = _user;
    if (user != null && user.isAnonymous) {
      await user.linkWithCredential(cred);
    } else {
      await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    }
  });

  Future<void> signInWithEmail(String email, String password) => _guard(() async {
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  });

  /// Google sign-in; links to the anonymous user when possible.
  Future<void> signInWithGoogle() => _guard(() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      final user = _user;
      if (user != null && user.isAnonymous) {
        try {
          await user.linkWithPopup(provider);
          return;
        } on FirebaseAuthException catch (e) {
          if (!_alreadyInUse(e)) rethrow;
        }
      }
      await _auth.signInWithPopup(provider);
      return;
    }
    final cred = await _googleCredential();
    if (cred == null) return; // cancelled
    await _linkOrSignIn(cred);
  });

  Future<void> _linkOrSignIn(AuthCredential cred) async {
    final user = _user;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithCredential(cred);
        return;
      } on FirebaseAuthException catch (e) {
        if (!_alreadyInUse(e)) rethrow;
        // The account exists: switch to it; local progress merges on sync.
        await _auth.signInWithCredential(e.credential ?? cred);
        return;
      }
    }
    await _auth.signInWithCredential(cred);
  }

  /// Signs out. A new anonymous user is created right after, so the app
  /// keeps working; progress stays on this device.
  Future<void> signOut() => _guard(() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  });

  static bool _alreadyInUse(FirebaseAuthException e) =>
      e.code == 'credential-already-in-use' || e.code == 'email-already-in-use';

  static bool _googleReady = false;

  static Future<AuthCredential?> _nativeGoogleCredential() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(serverClientId: googleServerClientId.isEmpty ? null : googleServerClientId);
      _googleReady = true;
    }
    if (!g.supportsAuthenticate()) {
      throw const AccountException('Google ile giriş bu cihazda desteklenmiyor.');
    }
    try {
      final account = await g.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AccountException('Google kimlik bilgisi alınamadı.');
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  static Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AccountException(authErrorTr(e.code));
    } catch (e) {
      debugPrint('Account error: $e');
      throw const AccountException('Bir sorun oluştu. Lütfen tekrar dene.');
    }
  }
}

/// Turkish message for a Firebase Auth error code.
String authErrorTr(String code) => switch (code) {
  'invalid-email' => 'E-posta adresi geçerli değil.',
  'user-not-found' || 'wrong-password' || 'invalid-credential' => 'E-posta ya da şifre hatalı.',
  'email-already-in-use' => 'Bu e-posta ile zaten bir hesap var. "Giriş yap"ı dene.',
  'credential-already-in-use' => 'Bu hesap başka bir kullanıcıya bağlı.',
  'weak-password' => 'Şifre en az 6 karakter olmalı.',
  'network-request-failed' => 'İnternet bağlantısı yok. Bağlanınca tekrar dene.',
  'too-many-requests' => 'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.',
  'operation-not-allowed' => 'Bu giriş yöntemi henüz açık değil.',
  'user-disabled' => 'Bu hesap devre dışı bırakılmış.',
  'requires-recent-login' => 'Güvenlik için lütfen yeniden giriş yap.',
  _ => 'Giriş yapılamadı ($code).',
};

/// Account actions, or null when Firebase is off.
final accountServiceProvider = Provider<AccountService?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth == null ? null : AccountService(auth);
});

/// Keeps a user signed in: when Firebase is on and nobody is signed in, an
/// anonymous account is created (retried every 30 s while offline).
final autoAnonymousSignInProvider = Provider<void>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return;
  final user = ref.watch(authStateProvider);
  if (user is! AsyncData<AppUser?> || user.value != null) return;
  Timer? retry;
  ref.onDispose(() => retry?.cancel());
  auth.signInAnonymously().catchError((Object e) {
    debugPrint('Anonymous sign-in failed, retrying: $e');
    retry = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    return Future<UserCredential>.error(e);
  }).ignore();
});
