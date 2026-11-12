import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_config.dart';

/// Firebase start-up (`initFirebase`), overridden in `main()`: resolves to
/// whether Firebase is ready. The app does not wait for it; everything that
/// needs Firebase watches [firebaseReadyProvider] and starts once it is true.
final firebaseInitProvider = FutureProvider<bool>((ref) async => false);

/// True once Firebase was initialised; false until then, and by default so
/// tests and local builds never touch Firebase.
final firebaseReadyProvider = Provider<bool>((ref) => ref.watch(firebaseInitProvider).value ?? false);

/// Firebase Auth, or null when Firebase is off.
final firebaseAuthProvider = Provider<FirebaseAuth?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseAuth.instance : null,
);

/// Firestore, or null when Firebase is off.
final firestoreProvider = Provider<FirebaseFirestore?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseFirestore.instance : null,
);

/// Callable Cloud Functions in [functionsRegion], or null when Firebase is off.
final functionsProvider = Provider<FirebaseFunctions?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseFunctions.instanceFor(region: functionsRegion) : null,
);

/// The signed-in user, without Firebase types so UI and tests stay simple.
class AppUser {
  const AppUser({
    required this.uid,
    this.isAnonymous = true,
    this.email,
    this.displayName,
    this.phoneNumber,
    this.providers = const [],
  });

  factory AppUser.fromFirebase(User u) => AppUser(
    uid: u.uid,
    isAnonymous: u.isAnonymous,
    email: u.email,
    displayName: u.displayName,
    phoneNumber: u.phoneNumber,
    providers: [for (final p in u.providerData) p.providerId],
  );

  final String uid;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final String? phoneNumber;

  /// Linked sign-in providers, e.g. `password`, `google.com`.
  final List<String> providers;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.isAnonymous == isAnonymous &&
      other.email == email &&
      other.displayName == displayName &&
      other.phoneNumber == phoneNumber &&
      other.providers.join(',') == providers.join(',');

  @override
  int get hashCode => Object.hash(uid, isAnonymous, email, displayName, phoneNumber, providers.join(','));
}

/// Current user (null when signed out or Firebase is off).
final authStateProvider = StreamProvider<AppUser?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return Stream.value(null);
  return auth.userChanges().map((u) => u == null ? null : AppUser.fromFirebase(u)).distinct();
});

/// Uid of the current user, or null.
final currentUidProvider = Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);
