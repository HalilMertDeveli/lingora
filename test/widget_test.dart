import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSpeech implements SpeechService {
  final said = <String>[];
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false}) async => said.add(text);
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async =>
      onDone();
  @override
  Future<void> stopListening() async {}
}

class FakeNotifications implements NotificationService {
  bool grant = true;
  List<PlannedNotification> last = const [];
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> apply(List<PlannedNotification> plan) async => last = plan;
}

late FakeNotifications notifications;

Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  final course = Course.fromJson(
    jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      courseProvider.overrideWith((ref) async => course),
      prefsProvider.overrideWithValue(p),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(notifications = FakeNotifications()),
    ],
    child: const LingoraApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding leads to the learning path', (tester) async {
    await pumpApp(tester, {});
    expect(find.text('Lingora'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.text('Ne öğrenmek istiyorsun?'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ciddi'));
    await tester.tap(find.text('Öğrenmeye başla'));
    await tester.pumpAndSettle();

    expect(find.text('Merhaba!'), findsOneWidget);
    expect(find.text('Selamlaşma'), findsOneWidget);
    expect(find.text('0 / 30 XP'), findsOneWidget);
  });

  testWidgets('reminder prompt enables reminders and schedules them', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
    expect(find.text('Her gün hatırlatayım mı?'), findsOneWidget);
    expect(notifications.last, isEmpty);
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(find.text('Her gün hatırlatayım mı?'), findsNothing);
    expect(notifications.last.where((n) => n.id >= reminderBaseId && n.id < heartsFullId),
        hasLength(greaterThanOrEqualTo(reminderDays - 1)));
  });

  testWidgets('denied permission keeps reminders off', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
    notifications.grant = false;
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(find.textContaining('izni verilmedi'), findsOneWidget);
    expect(notifications.last, isEmpty);
  });

  testWidgets('wrong answer costs a heart and shows the correct one', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
    await tester.tap(find.text('BAŞLA'));
    await tester.pumpAndSettle();

    expect(find.text('“merhaba” hangisi?'), findsOneWidget);
    await tester.tap(find.text('coffee'));
    await tester.pump();
    await tester.tap(find.text('KONTROL ET'));
    await tester.pumpAndSettle();
    expect(find.text('Doğru cevap:'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // hearts in the lesson header

    await tester.tap(find.text('DEVAM'));
    await tester.pumpAndSettle();
    expect(find.text('Bu cümleyi çevir'), findsOneWidget);
  });

  testWidgets('correct word-bank answer is accepted', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboarded": true}'});
    await tester.tap(find.text('BAŞLA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hello'));
    await tester.pump();
    await tester.tap(find.text('KONTROL ET'));
    await tester.pumpAndSettle();
    expect(find.text('Doğru cevap:'), findsNothing);
    await tester.tap(find.text('DEVAM'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hello').last);
    await tester.pump();
    await tester.tap(find.text('KONTROL ET'));
    await tester.pumpAndSettle();
    expect(find.text('Doğru cevap:'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
}
