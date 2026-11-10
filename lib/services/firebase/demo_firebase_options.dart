import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_config.dart';

/// Hand-written options for the `demo-lingora` project. They only work with
/// the Local Emulator Suite: the API key and app ids are placeholders that
/// the emulators accept and real Firebase rejects.
FirebaseOptions demoFirebaseOptions({TargetPlatform? platform}) {
  final p = kIsWeb ? null : (platform ?? defaultTargetPlatform);
  final appId = switch (p) {
    TargetPlatform.android => '1:000000000000:android:0000000000000000000000',
    TargetPlatform.iOS || TargetPlatform.macOS => '1:000000000000:ios:0000000000000000000000',
    _ => '1:000000000000:web:0000000000000000000000',
  };
  return FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: appId,
    messagingSenderId: '000000000000',
    projectId: demoProjectId,
    storageBucket: '$demoProjectId.appspot.com',
    iosBundleId: 'com.lingora.lingora',
  );
}
