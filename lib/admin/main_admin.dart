// Lingora Kurumsal web panel. Build and deploy (docs/kurumsal.md):
//
//   flutter build web -t lib/admin/main_admin.dart --dart-define=LINGORA_FIREBASE=prod \
//     -o <repo>/build/admin
//   firebase deploy --only hosting:admin
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/firebase_bootstrap.dart';
import '../services/firebase/firebase_config.dart';
import '../services/firebase/firebase_providers.dart';
import 'admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ready = await initFirebase(FirebaseMode.fromEnvironment);
  runApp(ProviderScope(overrides: [firebaseReadyProvider.overrideWithValue(ready)], child: const AdminApp()));
}
