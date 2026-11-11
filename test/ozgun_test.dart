import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/screens/section_header.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/tea_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show pumpApp;

/// Dilbaz's own identity (docs/tasarim.md, "Çay kimliği"): districts,
/// palettes, the two hosts per mode, accent and guest flags.
void main() {
  test('sections walk through districts: Mahalle, Çarşı, Vapur… and wrap after eight', () {
    expect(District.of(1), District.mahalle);
    expect(District.of(2), District.carsi);
    expect(District.of(3).label, 'Vapur');
    expect(District.of(8), District.sahne);
    expect(District.of(9), District.mahalle);
  });

  test('palettes: cream paper, tea for right answers, İznik navy for wrong ones', () {
    for (final p in [Palette.adultLight, Palette.adultDark, Palette.kidLight, Palette.kidDark]) {
      final tea = HSLColor.fromColor(p.success).hue;
      final navy = HSLColor.fromColor(p.error).hue;
      expect(tea, inInclusiveRange(10, 40), reason: 'tea / amber ${p.brightness} kid=${p.kid}');
      expect(navy, inInclusiveRange(200, 240), reason: 'navy ${p.brightness} kid=${p.kid}');
    }
    expect(HSLColor.fromColor(Palette.adultLight.background).hue, inInclusiveRange(25, 50), reason: 'cream');
    // Çocuk modu is livelier than the adult palette.
    expect(
      HSLColor.fromColor(Palette.kidLight.primary).saturation,
      greaterThan(HSLColor.fromColor(Palette.adultLight.primary).saturation),
    );
  });

  test('accent and guest countries persist; unknown countries are dropped', () {
    const s = AppSettings(accent: Accent.gb, guests: ['es', 'in']);
    expect(AppSettings.fromJson(s.toJson()), s);
    expect(
      AppSettings.fromJson(const {
        'guests': ['xx', 'fr'],
      }).guests,
      ['fr'],
    );
    expect(AppSettings.fromJson(const {}).accent, Accent.us);
  });

  group('app', () {
    String settings(String mode) => jsonEncode({'mode': mode, 'theme': 'light'});

    for (final mode in ['adult', 'kid']) {
      testWidgets('$mode: the right host stands by the lane, the invite carries their face', (tester) async {
        await pumpApp(tester, {
          'progress_v1': '{"onboarded": true}',
          AppSettingsNotifier.key: settings(mode),
        });
        final host = find.byKey(const Key('path-mascot'));
        expect(host, findsWidgets);
        final images = tester
            .widgetList<Image>(find.descendant(of: host.first, matching: find.byType(Image)))
            .map((i) => (i.image as AssetImage).assetName);
        expect(images.single, mode == 'kid' ? contains('pofuduk') : contains('cayci_dayi'));
        final invite = tester
            .widgetList<Image>(
              find.descendant(of: find.byKey(const Key('tea-invite-u1l1')), matching: find.byType(Image)),
            )
            .map((i) => (i.image as AssetImage).assetName);
        expect(invite.single, mode == 'kid' ? contains('pofuduk_avatar') : contains('cayci_dayi'));
      });
    }

    testWidgets('section cards carry their district scene', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<DistrictPainter>();
      expect(painters.map((p) => p.district), contains(District.mahalle));
      expect(find.byType(SectionHeader), findsWidgets);
    });

    testWidgets('kid mode profile shows Pofuduk\'s face as the avatar', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true}', AppSettingsNotifier.key: settings('kid')});
      await tester.tap(find.byKey(const Key('tab-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kid-avatar')), findsOneWidget);
    });

    testWidgets('the course drawer switches the voice between US and UK English', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
      await tester.tap(find.byKey(const Key('topbar-track')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accent-us')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('accent-gb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accent-gb')));
      await tester.pumpAndSettle();
      expect(SpeechService.englishLocale, 'en-GB');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppSettingsNotifier.key), contains('"accent":"gb"'));
      SpeechService.englishLocale = 'en-US';
    });

    testWidgets('the tourism path asks where the guests come from, with flags', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true, "trackId": "pro_tourism"}'});
      expect(find.byKey(const Key('guest-flags')), findsOneWidget);
      expect(find.text('Misafirlerin nereden geliyor?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guest-in')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 ülkeden misafir'), findsOneWidget);
    });

    testWidgets('other courses do not show the guest card', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
      expect(find.byKey(const Key('guest-flags')), findsNothing);
    });
  });
}
