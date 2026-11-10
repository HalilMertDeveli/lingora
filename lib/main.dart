import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/progress.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const LingoraApp(),
  ));
}

class LingoraApp extends ConsumerWidget {
  const LingoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(progressProvider.select((p) => p.onboarded));
    return MaterialApp(
      title: 'Lingora',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
