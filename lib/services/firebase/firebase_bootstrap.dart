import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'demo_firebase_options.dart';
import 'firebase_config.dart';
import 'firebase_options_prod.dart';

/// Initialises Firebase for [mode]. Returns true when Firebase is ready.
///
/// Never throws: any failure (missing config, no network on first start…)
/// is logged and the app simply stays local-only.
Future<bool> initFirebase(FirebaseMode mode) async {
  if (mode == FirebaseMode.off) return false;
  try {
    final options = mode == FirebaseMode.emulator
        ? demoFirebaseOptions()
        : DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    if (mode == FirebaseMode.emulator) await _useEmulators();
    return true;
  } catch (e, st) {
    debugPrint('Firebase disabled, staying offline: $e');
    debugPrintStack(stackTrace: st, maxFrames: 5);
    return false;
  }
}

Future<void> _useEmulators() async {
  final host = emulatorHost();
  await FirebaseAuth.instance.useAuthEmulator(host, authEmulatorPort);
  FirebaseFirestore.instance.useFirestoreEmulator(host, firestoreEmulatorPort);
  FirebaseFunctions.instanceFor(region: functionsRegion).useFunctionsEmulator(host, functionsEmulatorPort);
}
