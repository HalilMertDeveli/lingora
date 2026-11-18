import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/services/notifications.dart';

void main() {
  test('notification small icon is a white-only drawable that survives shrinking', () {
    // QA: '@mipmap/ic_launcher' (full-bleed Çaycı Dayı) showed as a white
    // square in the status bar and put Çaycı Dayı in kid-mode notifications.
    final icon = File('android/app/src/main/res/drawable/${NotificationService.smallIcon}.xml');
    expect(icon.existsSync(), isTrue);
    final fills = RegExp(r'fillColor="([^"]+)"').allMatches(icon.readAsStringSync()).map((m) => m[1]).toSet();
    expect(fills, {'#FFFFFFFF'});
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    expect(keep, contains('@drawable/${NotificationService.smallIcon}'));
  });
}
