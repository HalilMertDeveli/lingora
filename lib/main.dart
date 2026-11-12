import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/frame_stats.dart';
import 'core/startup_trace.dart';
import 'data/app_settings.dart';
import 'data/progress.dart';
import 'screens/consent_sheet.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/firebase/firebase_bootstrap.dart';
import 'services/firebase/firebase_config.dart';
import 'services/firebase/billing_backends_firebase.dart';
import 'services/firebase/firebase_providers.dart';
import 'services/firebase/progress_sync.dart';
import 'services/billing/exam_packs.dart';
import 'services/billing/premium.dart';
import 'services/growth/growth.dart';
import 'services/speech.dart';
import 'theme.dart';
import 'ui/motion.dart';

Future<void> main() async {
  StartupTrace.start();
  WidgetsFlutterBinding.ensureInitialized();
  FrameStats.start();
  // Firebase is the real project unless built with
  // --dart-define=LINGORA_FIREBASE=off|emulator. The first frame does not
  // wait for it: the path is local, and Firebase users (sync, accounts,
  // analytics, billing) start when firebaseReadyProvider turns true.
  final mode = FirebaseMode.fromEnvironment;
  final firebase = initFirebase(mode).whenComplete(() => StartupTrace.mark('firebase'));
  final prefs = await SharedPreferences.getInstance();
  StartupTrace.mark('prefs');
  WidgetsBinding.instance.addPostFrameCallback((_) => StartupTrace.mark('first_frame'));
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        firebaseInitProvider.overrideWith((ref) => firebase),
        // Analytics + Remote Config: production Firebase only (no-op otherwise).
        ...growthOverrides(enabled: mode == FirebaseMode.prod),
        ...firebaseBillingOverrides,
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
    // Analytics consent sync + churn signals (no-op without analytics).
    ref.listen(growthSignalsProvider, (_, _) {});
    final settings = ref.watch(appSettingsProvider);
    final brightness = switch (settings.theme) {
      ThemePref.light => Brightness.light,
      ThemePref.dark => Brightness.dark,
      ThemePref.system => MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
    };
    final palette = Palette.of(settings.mode, brightness);
    // Set before building so the first frame already uses the right colours.
    Brand.apply(palette);
    SessionFx.sound = settings.sound;
    SpeechService.englishLocale = settings.accent.locale;
    ref.listen(examPackControllerProvider, (_, _) {});
    return MaterialApp(
      title: 'Dilbaz',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(mode: settings.mode, brightness: brightness),
      builder: (context, child) => PaletteScope(
        palette: palette,
        child: settings.reduceMotion
            ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
            : child!,
      ),
      home: ConsentGate(child: onboarded ? const HomeScreen() : const OnboardingScreen()),
    );
  }
}
