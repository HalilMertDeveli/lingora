import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/progress.dart';

const reminderBaseId = 100;
const reminderDays = 7;

/// Id once used for "hearts refilled" alerts; still cancelled for old installs.
const _legacyHeartsId = 200;

class PlannedNotification {
  const PlannedNotification(this.id, this.when, this.title, this.body);
  final int id;
  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => '$id@${when.toIso8601String()}|$title|$body';
}

const _nudges = [
  ('Günün dersi seni bekliyor 📚', 'Birkaç dakikalık bir dersle güne bir adım ekle.'),
  ('5 dakikan var mı? ⏱️', 'Kısa bir ders, yeni kelimeler.'),
  ('İngilizce zamanı! 🇬🇧', 'Kaldığın yerden devam et.'),
  ('Küçük adımlar büyük fark yaratır ✨', 'Bugünkü dersini yapmayı unutma.'),
];

/// What should be scheduled right now, given the user's progress.
///
/// Daily reminders are one-off notifications for the next [reminderDays]
/// days (not a repeating alarm) so today's can be skipped once the user has
/// already practiced. Re-planned whenever progress changes.
List<PlannedNotification> planNotifications(Progress p, DateTime now) {
  if (p.remindersEnabled != true) return const [];
  final out = <PlannedNotification>[];
  final practicedToday = p.lastActiveDay == dayKey(now);
  final h = p.reminderMinutes ~/ 60, m = p.reminderMinutes % 60;

  for (var i = 0; i < reminderDays; i++) {
    final when = DateTime(now.year, now.month, now.day + i, h, m);
    if (i == 0 && (practicedToday || !when.isAfter(now))) continue;
    // Streak still alive on that day only if the user practiced the day before.
    final streak = p.streakAt(when);
    final (title, body) = streak > 0
        ? ('🔥 $streak günlük serini koru!', 'Bugün kısa bir ders serini devam ettirir.')
        : _nudges[i % _nudges.length];
    out.add(PlannedNotification(reminderBaseId + i, when, title, body));
  }

  return out;
}

/// Schedules local notifications on the device.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  String? _applied;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Hatırlatmalar',
      channelDescription: 'Günlük ders hatırlatmaları',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() => _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  /// Asks the OS for permission; returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    try {
      await (_ready ??= _init());
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true, badge: true) ?? false;
      return false;
    } catch (e) {
      debugPrint('notification permission failed: $e');
      return false;
    }
  }

  /// Replaces Lingora's scheduled notifications with [plan] (no-op if
  /// nothing changed since the last call).
  Future<void> apply(List<PlannedNotification> plan) async {
    final signature = plan.join(';');
    if (signature == _applied) return;
    _applied = signature;
    try {
      await (_ready ??= _init());
      for (var i = 0; i < reminderDays; i++) {
        await _plugin.cancel(id: reminderBaseId + i);
      }
      await _plugin.cancel(id: _legacyHeartsId);
      for (final n in plan) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          // An absolute instant; UTC avoids needing the device's zone name.
          scheduledDate: tz.TZDateTime.from(n.when, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      _applied = null; // retry on the next change
      debugPrint('notification scheduling failed: $e');
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());
