import 'package:flutter_contacts/flutter_contacts.dart' as fc;

/// Opens this app's page in the phone's settings (Uygulama bilgisi), e.g. to
/// turn the microphone back on after "Bir daha sorma". Uses the contacts
/// plugin's generic ACTION_APPLICATION_DETAILS_SETTINGS intent.
Future<void> openAppSettings() async {
  try {
    await fc.FlutterContacts.permissions.openSettings();
  } on Object {
    // No settings screen (tests, desktop): nothing to open.
  }
}
