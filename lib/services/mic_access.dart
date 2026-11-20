import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Where the microphone permission stands.
enum MicStatus {
  granted,

  /// Not granted yet (never asked, or refused once): asking again shows the
  /// system dialog.
  denied,

  /// Refused for good ("Bir daha sorma", or refused twice on Android): only
  /// the phone's settings can turn it on.
  blocked,
}

/// The microphone permission (RECORD_AUDIO on Android). Speaking screens
/// ask for it themselves before the recognizer starts: a fresh install on a
/// Galaxy M22 (Android 13) never showed the dialog through the recognizer.
abstract interface class MicAccess {
  Future<MicStatus> status();

  /// Shows the system dialog when it still can.
  Future<MicStatus> request();

  /// Opens this app's page in the phone's settings.
  Future<void> openSettings();
}

/// The phone's permission; desktop and tests count as granted (the speech
/// service then says whether a recognizer exists).
class PhoneMicAccess implements MicAccess {
  const PhoneMicAccess();

  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static MicStatus _from(ph.PermissionStatus s) => switch (s) {
    ph.PermissionStatus.granted ||
    ph.PermissionStatus.limited ||
    ph.PermissionStatus.provisional => MicStatus.granted,
    ph.PermissionStatus.permanentlyDenied || ph.PermissionStatus.restricted => MicStatus.blocked,
    ph.PermissionStatus.denied => MicStatus.denied,
  };

  @override
  Future<MicStatus> status() async {
    if (!_mobile) return MicStatus.granted;
    try {
      return _from(await ph.Permission.microphone.status);
    } on Object catch (e) {
      debugPrint('Mic permission status failed: $e');
      return MicStatus.granted; // cannot tell: let the recognizer try
    }
  }

  @override
  Future<MicStatus> request() async {
    if (!_mobile) return MicStatus.granted;
    try {
      return _from(await ph.Permission.microphone.request());
    } on Object catch (e) {
      debugPrint('Mic permission request failed: $e');
      return MicStatus.granted;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } on Object {
      // No settings screen (tests, desktop).
    }
  }
}

final micAccessProvider = Provider<MicAccess>((ref) => const PhoneMicAccess());
