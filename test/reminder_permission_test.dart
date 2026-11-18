import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/reminder_settings.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications;

/// QA: reminders switched on on one phone arrive here with the synced
/// progress, but this phone never granted notifications: say so.
Future<FakeNotifications> _pump(WidgetTester tester, {required bool? enabled, required bool? allowed}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(Progress(onboarded: true, remindersEnabled: enabled).toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final fake = FakeNotifications();
  var allowedNow = allowed;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(fake),
        notificationsAllowedProvider.overrideWith((ref) async => allowedNow),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        builder: (_, child) =>
            PaletteScope(palette: Palette.of(AppMode.adult, Brightness.light), child: child!),
        home: const Scaffold(body: ReminderSettings()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // After "İzin ver" the provider is re-read: the phone now allows them.
  allowedNow = true;
  return fake;
}

final _warning = find.byKey(const ValueKey('reminder-permission-missing'));

void main() {
  testWidgets('on, but not allowed on this phone: warning with "İzin ver"', (tester) async {
    await _pump(tester, enabled: true, allowed: false);
    expect(_warning, findsOneWidget);
    await tester.tap(find.text('İzin ver'));
    await tester.pumpAndSettle();
    expect(_warning, findsNothing);
  });

  testWidgets('allowed, unknown or switched off: no warning', (tester) async {
    await _pump(tester, enabled: true, allowed: true);
    expect(_warning, findsNothing);
    await _pump(tester, enabled: true, allowed: null);
    expect(_warning, findsNothing);
    await _pump(tester, enabled: false, allowed: false);
    expect(_warning, findsNothing);
  });
}
