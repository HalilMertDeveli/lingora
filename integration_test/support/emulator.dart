// Helpers for the sign-in integration tests: the Firebase Emulator Suite's
// REST endpoints and a "device" (its own FirebaseApp, storage and providers).
//
// Everything here talks to the `demo-lingora` emulator project only. The
// real project (dilbaz-3392e) is never touched: the apps are created with
// demoFirebaseOptions() and pointed at the emulators before any call.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/services/billing/billing_service.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/billing_backends_firebase.dart';
import 'package:lingora/services/firebase/demo_firebase_options.dart';
import 'package:lingora/services/firebase/firebase_config.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/firebase/progress_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REST access to the Auth and Firestore emulators (admin rights through
/// the `Bearer owner` token, which only the emulators accept).
class Emulators {
  Emulators([String? host]) : host = host ?? emulatorHost();
  final String host;

  static const _project = demoProjectId;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  Uri _auth(String path) => Uri.parse('http://$host:$authEmulatorPort$path');
  Uri _fs(String path) => Uri.parse('http://$host:$firestoreEmulatorPort$path');
  String get _docs => '/v1/projects/$_project/databases/(default)/documents';

  Future<Object?> _send(String method, Uri uri, [Object? body]) async {
    final req = await _http.openUrl(method, uri);
    req.headers.set('Authorization', 'Bearer owner');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 300) throw HttpException('$method $uri → ${res.statusCode}: $text');
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text; // e.g. the Firestore emulator's "Ok"
    }
  }

  /// True when both emulators answer.
  Future<bool> reachable() async {
    try {
      await _send('GET', _auth('/emulator/v1/projects/$_project/config'));
      await _send('GET', _fs('/'));
      return true;
    } on Object {
      return false;
    }
  }

  /// Waits until both emulators answer (CI starts them right before the
  /// tests). Throws with the host and ports when they never do.
  Future<void> waitReady({Duration timeout = const Duration(seconds: 90)}) async {
    final end = DateTime.now().add(timeout);
    while (!await reachable()) {
      if (DateTime.now().isAfter(end)) {
        throw StateError(
          'Firebase emulators not reachable at $host (auth $authEmulatorPort, firestore '
          '$firestoreEmulatorPort). Start them first: '
          'firebase emulators:start --only auth,firestore --project $_project',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Creates an e-mail/password account directly in the Auth emulator and
  /// returns its uid (for tests that only need the account to exist).
  Future<String> createEmailUser(String email, String password) async {
    final res = await _send(
      'POST',
      _auth('/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key'),
      {'email': email, 'password': password, 'returnSecureToken': true},
    ) as Map;
    return res['localId'] as String;
  }

  /// Deletes every account and document.
  Future<void> reset() async {
    await _send('DELETE', _auth('/emulator/v1/projects/$_project/accounts'));
    await _send('DELETE', _fs('/emulator/v1/projects/$_project/databases/(default)/documents'));
  }

  /// Writes an active `entitlements/{uid}` (what verifyPurchase would do), so
  /// the Firestore rules accept the user's cloud backup.
  Future<void> grantPremium(String uid, {Duration valid = const Duration(days: 30)}) =>
      _send('PATCH', _fs('$_docs/entitlements/$uid'), {
        'fields': {
          'active': {'booleanValue': true},
          'productId': {'stringValue': 'dilbaz_premium_monthly'},
          'source': {'stringValue': 'test'},
          'expiresAt': {'timestampValue': DateTime.now().toUtc().add(valid).toIso8601String()},
        },
      });

  /// `users/{uid}` as plain JSON, or null when it does not exist.
  Future<Map<String, Object?>?> userDoc(String uid) async {
    final raw = await _send('GET', _fs('$_docs/users/$uid'));
    if (raw is! Map) return null;
    return _fields(raw['fields'] as Map? ?? const {});
  }

  /// Node ids completed in the cloud copy of [uid]'s progress.
  Future<Set<String>> cloudCompleted(String uid) async {
    final doc = await userDoc(uid);
    final progress = doc?['progress'];
    if (progress is! Map) return {};
    return {...(progress['completed'] as Map? ?? const {}).keys.cast<String>()};
  }

  /// The SMS code the Auth emulator "sent" to [phone] (E.164), newest first.
  Future<String> smsCode(String phone) async {
    for (var i = 0; i < 50; i++) {
      final raw = await _send('GET', _auth('/emulator/v1/projects/$_project/verificationCodes')) as Map?;
      final codes = [
        for (final c in (raw?['verificationCodes'] as List? ?? const []))
          if ((c as Map)['phoneNumber'] == phone) c['code'] as String,
      ];
      if (codes.isNotEmpty) return codes.last;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('No SMS code for $phone');
  }

  static Map<String, Object?> _fields(Map<Object?, Object?> f) => {
    for (final e in f.entries) '${e.key}': _value(e.value as Map),
  };

  static Object? _value(Map<Object?, Object?> v) {
    if (v.containsKey('mapValue')) return _fields((v['mapValue'] as Map)['fields'] as Map? ?? const {});
    if (v.containsKey('arrayValue')) {
      return [for (final x in ((v['arrayValue'] as Map)['values'] as List? ?? const [])) _value(x as Map)];
    }
    if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
    if (v.containsKey('nullValue')) return null;
    return v.values.first;
  }
}

/// A Google ID token the Auth emulator accepts (unsigned JSON claims).
AuthCredential fakeGoogleCredential(String sub, String email) => GoogleAuthProvider.credential(
  idToken: jsonEncode({'sub': sub, 'email': email, 'email_verified': true, 'name': 'Test $sub'}),
);

int _devices = 0;

/// One phone running Dilbaz: its own FirebaseApp (so its own signed-in
/// user and Firestore cache), empty storage and the app's providers.
///
/// Only one device may be alive at a time (SharedPreferences is global);
/// call [close] before starting the next one.
class TestDevice {
  TestDevice._(this.app, this.auth, this.db, this.prefs, this.container);

  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final SharedPreferences prefs;
  final ProviderContainer container;

  /// Starts a device with clean storage. [authPort]/[firestorePort] can point
  /// at a closed port to simulate "no connection".
  static Future<TestDevice> start({
    required Emulators emu,
    Future<AuthCredential?> Function()? google,
    int authPort = authEmulatorPort,
    int firestorePort = firestoreEmulatorPort,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'device-${DateTime.now().microsecondsSinceEpoch}-${_devices++}',
      options: demoFirebaseOptions(),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator(emu.host, authPort);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.useFirestoreEmulator(emu.host, firestorePort);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        firebaseReadyProvider.overrideWithValue(true),
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        functionsProvider.overrideWithValue(null),
        billingServiceProvider.overrideWithValue(UnavailableBillingService()),
        // The real entitlement watcher (entitlements/{uid}); no purchases.
        entitlementBackendProvider.overrideWith((ref) {
          final uid = ref.watch(currentUidProvider);
          if (uid == null) return null;
          return FirebaseEntitlementBackend(
            call: (name, _) => throw UnsupportedError('$name is not used in these tests'),
            firestore: db,
            uid: uid,
          );
        }),
        accountServiceProvider.overrideWithValue(
          _RetryingAccountService(auth, google: google, retry: authPort == authEmulatorPort),
        ),
        syncDebounceProvider.overrideWithValue(const Duration(milliseconds: 300)),
        syncRetryProvider.overrideWithValue(const Duration(seconds: 2)),
      ],
    );
    // What LingoraApp keeps alive.
    container.listen(progressSyncProvider, (_, _) {});
    container.listen(premiumControllerProvider, (_, _) {});
    return TestDevice._(app, auth, db, prefs, container);
  }

  AccountService get account => container.read(accountServiceProvider)!;
  Progress get progress => container.read(progressProvider);
  SyncState get sync => container.read(progressSyncProvider).state;
  bool get premium => container.read(premiumProvider);
  AppUser? get user => container.read(authStateProvider).value;

  /// Finishes a lesson like the lesson screen does.
  void finishLesson(String nodeId) =>
      container.read(progressProvider.notifier).completeNode(nodeId, xp: 10, correct: 8, answered: 10);

  /// Waits for the automatic anonymous account.
  Future<String> guest() async {
    // Up to one retry of autoAnonymousSignInProvider (30 s) after a hiccup.
    await until(() => user != null, 'anonymous sign-in', timeout: const Duration(seconds: 75));
    expectTrue(user!.isAnonymous, 'first user is a guest');
    return user!.uid;
  }

  Future<void> close() async {
    // The app is kept: deleting a FirebaseApp on Android makes the plugin
    // fail for apps created afterwards ("FirebaseApp was deleted").
    container.dispose();
    await db.disableNetwork();
  }
}

/// Polls [condition] (real time) until it holds.
Future<void> until(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Like [until], for async checks (e.g. reading the emulator).
Future<void> untilAsync(
  Future<bool> Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void expectTrue(bool v, String what) {
  if (!v) throw StateError('Expected: $what');
}

/// The app's AccountService, retrying a call once when the connection to the
/// emulator dropped. Android reuses keep-alive connections that the Auth
/// emulator has already closed (e.g. after [Emulators.reset]), which fails
/// one request with "Software caused connection abort". Real users see the
/// "no internet" message and tap again; the tests do the same.
class _RetryingAccountService extends AccountService {
  _RetryingAccountService(super.auth, {Future<AuthCredential?> Function()? google, required this.retry})
    : super(googleCredential: google);

  /// False for the deliberately offline device.
  final bool retry;

  Future<T> _again<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AccountException catch (e) {
      if (!retry || !e.message.startsWith('İnternet bağlantısı yok')) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return run();
    }
  }

  @override
  Future<void> signInAnonymously() => _again(super.signInAnonymously);
  @override
  Future<void> registerWithEmail(String email, String password) =>
      _again(() => super.registerWithEmail(email, password));
  @override
  Future<void> signInWithEmail(String email, String password) =>
      _again(() => super.signInWithEmail(email, password));
  @override
  Future<void> sendPasswordResetEmail(String email) => _again(() => super.sendPasswordResetEmail(email));
  @override
  Future<void> signInWithGoogle() => _again(super.signInWithGoogle);
  @override
  Future<String?> startPhoneSignIn(String rawPhone) => _again(() => super.startPhoneSignIn(rawPhone));
  @override
  Future<void> confirmPhoneCode(String verificationId, String code) =>
      _again(() => super.confirmPhoneCode(verificationId, code));
  @override
  Future<void> signOut() => _again(super.signOut);
}
