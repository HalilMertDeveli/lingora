import 'package:flutter/foundation.dart';

/// How the app talks to Firebase, chosen at build time with
/// `--dart-define=LINGORA_FIREBASE=emulator|prod`.
///
/// The default is [FirebaseMode.off]: Firebase is never initialised and the
/// app keeps all progress on the device, exactly like before.
enum FirebaseMode {
  off,
  emulator,
  prod;

  static FirebaseMode parse(String? raw) => switch (raw?.trim().toLowerCase()) {
    'emulator' || 'emu' || 'local' => FirebaseMode.emulator,
    'prod' || 'production' || 'on' => FirebaseMode.prod,
    _ => FirebaseMode.off,
  };

  /// The mode this build was compiled with.
  static FirebaseMode get fromEnvironment => parse(const String.fromEnvironment('LINGORA_FIREBASE'));
}

/// Demo project used with the Local Emulator Suite. `demo-*` ids never touch
/// real Google servers.
const demoProjectId = 'demo-lingora';

/// Region of the callable Cloud Functions (see functions/ in the repo).
const functionsRegion = String.fromEnvironment('LINGORA_FUNCTIONS_REGION', defaultValue: 'europe-west1');

/// Emulator ports (firebase.json defaults).
const authEmulatorPort = 9099;
const firestoreEmulatorPort = 8080;
const functionsEmulatorPort = 5001;

/// Host of the emulators as seen from the app. Android emulators reach the
/// development machine at 10.0.2.2; override with
/// `--dart-define=LINGORA_EMULATOR_HOST=192.168.1.20` for a real phone.
String emulatorHost({TargetPlatform? platform}) {
  const override = String.fromEnvironment('LINGORA_EMULATOR_HOST');
  if (override.isNotEmpty) return override;
  if (kIsWeb) return 'localhost';
  return (platform ?? defaultTargetPlatform) == TargetPlatform.android ? '10.0.2.2' : 'localhost';
}

/// Web client id for Google Sign-In on Android (the "Web client" OAuth id of
/// the real project). Optional when google-services.json provides it.
const googleServerClientId = String.fromEnvironment('LINGORA_GOOGLE_SERVER_CLIENT_ID');
