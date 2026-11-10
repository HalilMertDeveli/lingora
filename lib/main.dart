import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/progress.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/firebase/firebase_bootstrap.dart';
import 'services/firebase/firebase_config.dart';
import 'services/firebase/firebase_providers.dart';
import 'services/firebase/progress_sync.dart';
import 'services/billing/premium.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Off unless built with --dart-define=LINGORA_FIREBASE=emulator|prod.
  final firebaseReady = await initFirebase(FirebaseMode.fromEnvironment);
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        firebaseReadyProvider.overrideWithValue(firebaseReady),
      ],
      child: const LingoraApp(),
    ),
  );
}

class LingoraApp extends ConsumerWidget {
  const LingoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the cloud sync alive (does nothing when Firebase is off).
    ref.listen(progressSyncProvider, (_, _) {});
    final onboarded = ref.watch(progressProvider.select((p) => p.onboarded));
    // Start listening to the store at launch: Google Play re-delivers
    // unacknowledged or pending purchases right after start-up.
    ref.listen(premiumControllerProvider, (_, _) {});
    return MaterialApp(
      title: 'Lingora',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
