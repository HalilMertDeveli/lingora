import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_resume.dart';
import 'core/app_update.dart';
import 'core/frame_stats.dart';
import 'core/legacy_emoji.dart';
import 'core/startup_trace.dart';
import 'data/app_settings.dart';
import 'data/gold_wallet.dart';
import 'data/progress.dart';
import 'data/shop_catalog.dart';
import 'kurum/kurum.dart';
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
import 'services/billing/premium_perks.dart';
import 'services/friends.dart';
import 'services/growth/analytics.dart';
import 'services/growth/crash_reporting.dart';
import 'services/growth/funnel_stats.dart';
import 'services/growth/growth.dart';
import 'services/growth/review_prompt.dart';
import 'services/league_remote.dart';
import 'services/rehearsal_cloud.dart';
import 'services/showcase.dart';
import 'services/speech.dart';
import 'services/voice_library.dart';
import 'theme.dart';
import 'ui/motion.dart';
import 'ui/shop_visuals.dart';

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
  // Android 7–9: emoji they cannot draw are swapped (lib/core/legacy_emoji.dart).
  final (prefs, _) = await (SharedPreferences.getInstance(), detectLegacyEmoji()).wait;
  StartupTrace.mark('prefs');
  // Crash reports: hooks now, Firebase Crashlytics once Firebase is ready.
  // Production builds only, and only with the analytics consent.
  CrashReporter.install(consent: prefs.getBool(AnalyticsConsent.key));
  // The review prompt waits a few days after the first launch.
  ReviewPolicy(prefs).markFirstSeen(DateTime.now());
  if (mode == FirebaseMode.prod) {
    firebase.then((ok) {
      if (ok) CrashReporter.attach(FirebaseCrashSink());
    });
  }
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
  // Course audio not in the bundle: downloaded on Wi-Fi, after startup.
  unawaited(Future<void>.delayed(const Duration(seconds: 8), VoiceLibrary.instance.init));
}

class LingoraApp extends ConsumerWidget {
  const LingoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the cloud sync alive (does nothing when Firebase is off).
    ref.listen(progressSyncProvider, (_, _) {});
    // Marks the daily goal in friendships for the shared streak.
    ref.listen(friendGoalSyncProvider, (_, _) {});
    ref.listen(friendNameSyncProvider, (_, _) {});
    // Reports the week's XP to the Dünya Ligi (does nothing for guests).
    ref.listen(leagueXpSyncProvider, (_, _) {});
    // Shares the progress summary with the student's classes (Firebase only).
    ref.listen(classReportSyncProvider, (_, _) {});
    final onboarded = ref.watch(progressProvider.select((p) => p.onboarded));
    // Start listening to the store at launch: Google Play re-delivers
    // unacknowledged or pending purchases right after start-up.
    ref.listen(premiumControllerProvider, (_, _) {});
    // Premium's monthly streak freezes go into the wallet by themselves.
    ref.listen(premiumPerksSyncProvider, (_, _) {});
    // Mülakat Provası history comes back from the account on a new phone.
    ref.listen(rehearsalCloudSyncProvider, (_, _) {});
    // Analytics consent sync + churn signals (no-op without analytics).
    ref.listen(growthSignalsProvider, (_, _) {});
    // Crash reports follow the same consent; the uid is the only identifier.
    ref.listen(crashReportingSyncProvider, (_, _) {});
    // Owner dashboard funnel counters (consent only, no identifiers).
    ref.listen(funnelStatsProvider, (_, _) {});
    final settings = ref.watch(appSettingsProvider);
    final brightness = switch (settings.theme) {
      ThemePref.light => Brightness.light,
      ThemePref.dark => Brightness.dark,
      ThemePref.system => MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
    };
    // The Mağaza look: brand colour and Çaycı Dayı's accessory.
    final themeItem = ref.watch(walletProvider.select((w) => equippedIn(w, WalletSlot.theme)));
    final outfit = ref.watch(walletProvider.select((w) => equippedIn(w, WalletSlot.mascot)?.accessory));
    final kidOutfit = ref.watch(walletProvider.select((w) => equippedIn(w, WalletSlot.pofuduk)?.accessory));
    final palette = appPalette(settings.mode, brightness, themeItem);
    // Puts the worn Mağaza look into profiles/{uid} for friends.
    ref.listen(showcaseSyncProvider, (_, _) {});
    // Set before building so the first frame already uses the right colours.
    Brand.apply(palette);
    SessionFx.sound = settings.sound;
    SpeechService.englishLocale = settings.accent.locale;
    ref.listen(examPackControllerProvider, (_, _) {});
    return MaterialApp(
      title: 'Dilmaç',
      debugShowCheckedModeBanner: false,
      // Turkish date and time pickers, and Turkish names for the built-in
      // buttons TalkBack reads ("Geri", not "Back").
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(mode: settings.mode, brightness: brightness, palette: palette),
      builder: (context, child) => AppResumeWatcher(
        child: PaletteScope(
          palette: palette,
          child: MascotOutfitScope(
            accessory: outfit,
            pofuduk: kidOutfit,
            // "Lütfen güncelle" screen / new-version banner (config/app).
            child: UpdateGate(
              child: settings.reduceMotion
                  ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
                  : child!,
            ),
          ),
        ),
      ),
      home: ConsentGate(child: onboarded ? const HomeScreen() : const OnboardingScreen()),
    );
  }
}

final _palettes = <(AppMode, Brightness, String?), Palette>{};

/// The palette for [mode] and [brightness] with the Mağaza [theme]'s brand
/// colour. The same object comes back for the same inputs, so PaletteScope
/// only rebuilds everything when the look really changes.
Palette appPalette(AppMode mode, Brightness brightness, ShopItem? theme) {
  final accent = theme?.accent;
  final id = accent == null || theme!.free ? null : theme.id;
  return _palettes.putIfAbsent((mode, brightness, id), () {
    final base = Palette.of(mode, brightness);
    if (accent == null || id == null) return base;
    return base.withPrimary(brightness == Brightness.dark ? accent.dark : accent.light);
  });
}
