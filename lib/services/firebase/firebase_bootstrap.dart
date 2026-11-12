import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'demo_firebase_options.dart';
import 'firebase_config.dart';
import 'firebase_options_prod.dart';

/// Name of the FirebaseApp used with the emulators. On Android the default
/// app is created natively from google-services.json (the real project)
/// before any Dart code runs, so the demo project needs an app of its own.
const emulatorAppName = 'lingora-emulator';

FirebaseApp? _app;

/// The app the providers use: the emulator app in emulator mode, otherwise
/// the default app.
FirebaseApp get lingoraFirebaseApp => _app ?? Firebase.app();

/// Initialises Firebase for [mode]. Returns true when Firebase is ready.
///
/// Never throws: any failure (missing config, no network on first start…)
/// is logged and the app simply stays local-only.
Future<bool> initFirebase(FirebaseMode mode) async {
  if (mode == FirebaseMode.off) return false;
  try {
    if (mode == FirebaseMode.emulator) {
      _app =
          Firebase.apps.where((a) => a.name == emulatorAppName).firstOrNull ??
          await Firebase.initializeApp(name: emulatorAppName, options: demoFirebaseOptions());
      await _useEmulators(_app!);
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    return true;
  } catch (e, st) {
    debugPrint('Firebase disabled, staying offline: $e');
    debugPrintStack(stackTrace: st, maxFrames: 5);
    return false;
  }
}

Future<void> _useEmulators(FirebaseApp app) async {
  final host = emulatorHost();
  await FirebaseAuth.instanceFor(app: app).useAuthEmulator(host, authEmulatorPort);
  FirebaseFirestore.instanceFor(app: app).useFirestoreEmulator(host, firestoreEmulatorPort);
  FirebaseFunctions.instanceFor(
    app: app,
    region: functionsRegion,
  ).useFunctionsEmulator(host, functionsEmulatorPort);
}
