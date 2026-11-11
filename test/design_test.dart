import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/profile_screen.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:lingora/ui/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show pumpApp;

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

/// Shared widgets on one screen, themed like the app does it.
Future<void> _pumpKit(WidgetTester tester, AppMode mode, Brightness b) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final palette = Palette.of(mode, b);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(mode: mode, brightness: b),
      builder: (_, child) => PaletteScope(palette: palette, child: child!),
      home: Scaffold(
        body: Confetti(
          child: ListView(
            children: [
              const Mascot(mood: Mood.happy),
              const Mascot(mood: Mood.think, decorative: true),
              TapCard(onTap: () {}, child: const Text('Kart')),
              const TapCard(selected: true, child: Text('Seçili')),
              PressableButton(label: 'KONTROL ET', onPressed: () {}),
              const PressableButton(label: 'DEVAM', onPressed: null),
              const GlossyProgress(value: 0.5, color: Colors.green),
              const Glyph(emoji: '🎓', icon: Icons.school_outlined),
              const IconBadge(icon: Icons.bolt, emoji: '⚡'),
              const SectionLabel('KURSLAR'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('appSettingsProvider', () {
    test('defaults to adult mode following the system theme', () async {
      final c = await _container({});
      expect(c.read(appSettingsProvider), const AppSettings());
      expect(c.read(appSettingsProvider).mode, AppMode.adult);
      expect(c.read(appSettingsProvider).theme, ThemePref.system);
    });

    test('persists mode and theme under settings_v1', () async {
      final c = await _container({});
      c.read(appSettingsProvider.notifier)
        ..setMode(AppMode.kid)
        ..setTheme(ThemePref.dark);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(AppSettingsNotifier.key)!) as Map<String, dynamic>;
      expect(saved, {'mode': 'kid', 'theme': 'dark', 'sound': true, 'reduceMotion': false});
      // Learning progress is stored separately and untouched.
      expect(prefs.getString('progress_v1'), isNull);

      final again = await _container({AppSettingsNotifier.key: jsonEncode(saved)});
      expect(again.read(appSettingsProvider), const AppSettings(mode: AppMode.kid, theme: ThemePref.dark));
    });

    test('bad or unknown stored values fall back to defaults', () async {
      final broken = await _container({AppSettingsNotifier.key: '{not json'});
      expect(broken.read(appSettingsProvider), const AppSettings());
      final unknown = await _container({AppSettingsNotifier.key: '{"mode":"robot","theme":"sepia"}'});
      expect(unknown.read(appSettingsProvider), const AppSettings());
    });

    test('resetting progress keeps the display settings', () async {
      final c = await _container({});
      c.read(appSettingsProvider.notifier).setMode(AppMode.kid);
      c.read(progressProvider.notifier).reset();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppSettingsNotifier.key), contains('kid'));
    });
  });

  group('sentenceCase', () {
    test('lowers Turkish all-caps labels correctly', () {
      expect(sentenceCase('KONTROL ET'), 'Kontrol et');
      expect(sentenceCase('ŞİMDİLİK ÇIK'), 'Şimdilik çık');
      expect(sentenceCase('İLERİ'), 'İleri');
      expect(sentenceCase('BİLMİYORUM'), 'Bilmiyorum');
      expect(sentenceCase('MİNİ DENEME BAŞLAT'), 'Mini deneme başlat');
      expect(sentenceCase('+20 XP AL'), '+20 XP al');
      expect(sentenceCase("PREMIUM'A GEÇ"), "Premium'a geç");
    });

    test('leaves mixed-case labels alone', () {
      expect(sentenceCase('Sözlüğüme ekle'), 'Sözlüğüme ekle');
      expect(sentenceCase(''), '');
    });
  });

  group('palettes', () {
    test('every mode and brightness has its own palette', () {
      final all = {
        for (final m in AppMode.values)
          for (final b in Brightness.values) Palette.of(m, b),
      };
      expect(all, hasLength(4));
      for (final p in all) {
        expect(p.kid, p == Palette.kidLight || p == Palette.kidDark);
        // Text stays readable on the page and card backgrounds.
        expect((p.ink.computeLuminance() - p.background.computeLuminance()).abs(), greaterThan(0.6));
        expect((p.ink.computeLuminance() - p.card.computeLuminance()).abs(), greaterThan(0.6));
      }
    });

    test('adult mode softens content colours, kid mode keeps them', () {
      const bright = Color(0xFF6C4CF1);
      expect(Palette.kidLight.tone(bright), bright);
      final soft = HSLColor.fromColor(Palette.adultLight.tone(bright));
      expect(soft.saturation, lessThan(HSLColor.fromColor(bright).saturation));
    });

    test('onColor picks a readable foreground', () {
      expect(onColor(const Color(0xFF1E1B2E)), Colors.white);
      expect(onColor(const Color(0xFFF0F0F0)), isNot(Colors.white));
    });
  });

  group('shared widgets', () {
    for (final b in Brightness.values) {
      testWidgets('adult mode (${b.name}) is calm: small still mascot, sentence-case buttons', (
        tester,
      ) async {
        await _pumpKit(tester, AppMode.adult, b);
        expect(tester.takeException(), isNull);
        expect(find.byType(Dayi), findsOneWidget, reason: 'decorative mascot is hidden');
        expect(tester.getSize(find.byType(Dayi)).height, Mascot.adultSize(120));
        expect(tester.widget<Dayi>(find.byType(Dayi)).animate, isFalse);
        expect(find.text('Kontrol et'), findsOneWidget);
        expect(find.text('KONTROL ET'), findsNothing);
        expect(find.text('🎓'), findsNothing);
        expect(find.byIcon(Icons.school_outlined), findsOneWidget);
        expect(Brand.palette, Palette.of(AppMode.adult, b));
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, isNull);
        final ctx = tester.element(find.text('Kart'));
        expect(Theme.of(ctx).brightness, b);
        expect(Theme.of(ctx).scaffoldBackgroundColor, Palette.of(AppMode.adult, b).background);
      });

      testWidgets('Çocuk modu (${b.name}) brings back a big animated mascot, emoji and caps', (tester) async {
        await _pumpKit(tester, AppMode.kid, b);
        expect(tester.takeException(), isNull);
        expect(find.byType(Dayi), findsNWidgets(2));
        expect(tester.getSize(find.byType(Dayi).first).height, 120);
        expect(find.text('KONTROL ET'), findsOneWidget);
        expect(find.text('🎓'), findsOneWidget);
        expect(find.text('⚡'), findsOneWidget);
        expect(Brand.palette, Palette.of(AppMode.kid, b));
      });
    }

    testWidgets('tapping a card and a button still works in adult mode', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Column(
              children: [
                TapCard(onTap: () => taps++, child: const Text('Kart')),
                PressableButton(label: 'DEVAM', onPressed: () => taps++),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Kart'));
      await tester.tap(find.text('Devam'));
      expect(taps, 2);
    });
  });

  group('app', () {
    testWidgets('stored settings apply on start (Çocuk modu + dark)', (tester) async {
      await pumpApp(tester, {AppSettingsNotifier.key: '{"mode":"kid","theme":"dark"}'});
      final ctx = tester.element(find.text('Dilbaz').first);
      expect(Theme.of(ctx).brightness, Brightness.dark);
      expect(ctx.isKid, isTrue);
      expect(Brand.palette, Palette.kidDark);
    });

    testWidgets('onboarding asks who it is for and switches the look at once', (tester) async {
      await pumpApp(tester, {});
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(find.text('Kimin için?'), findsOneWidget);
      expect(Brand.isKid, isFalse);
      await tester.tap(find.text('Çocuğum için (Çocuk modu)'));
      await tester.pumpAndSettle();
      expect(Brand.isKid, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppSettingsNotifier.key), contains('"mode":"kid"'));
    });

    testWidgets('Profil > Görünüm toggles Çocuk modu and dark theme without leaving the tab', (tester) async {
      await pumpApp(tester, {'progress_v1': jsonEncode(const Progress(onboarded: true).toJson())});
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('kid-mode-switch'));
      await tester.scrollUntilVisible(
        toggle,
        300,
        scrollable: find.descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(Brand.isKid, isTrue);
      expect(find.text('Görünüm'), findsOneWidget, reason: 'still on the Profil tab');

      await tester.tap(find.text('Koyu'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Görünüm'))).brightness, Brightness.dark);
      expect(Brand.palette, Palette.kidDark);
      expect(tester.takeException(), isNull);
    });
  });
}
