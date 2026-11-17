import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One person in the phone book: the name shown on this phone and their
/// numbers as written there (normalised later, on the phone).
class PhoneContact {
  const PhoneContact({required this.name, required this.numbers});
  final String name;
  final List<String> numbers;
}

enum ContactsAccess { granted, denied, permanentlyDenied }

/// Read-only access to the phone book (mockable in tests). The permission
/// is asked only when the user taps "Rehberden bul".
abstract class ContactsSource {
  /// Asks for the read permission (the system dialog) when not yet granted.
  Future<ContactsAccess> requestAccess();

  /// Every contact with at least one number. Call after [requestAccess].
  Future<List<PhoneContact>> load();

  /// The system settings page, after a permanent "no".
  Future<void> openSettings();
}

class FlutterContactsSource implements ContactsSource {
  const FlutterContactsSource();

  @override
  Future<ContactsAccess> requestAccess() async {
    final status = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
    return switch (status) {
      fc.PermissionStatus.granted || fc.PermissionStatus.limited => ContactsAccess.granted,
      fc.PermissionStatus.permanentlyDenied ||
      fc.PermissionStatus.restricted => ContactsAccess.permanentlyDenied,
      _ => ContactsAccess.denied,
    };
  }

  @override
  Future<List<PhoneContact>> load() async {
    final all = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.name, fc.ContactProperty.phone},
    );
    return [
      for (final c in all)
        if (c.phones.isNotEmpty)
          PhoneContact(
            name: (c.displayName ?? '').trim().isEmpty ? c.phones.first.number : c.displayName!.trim(),
            numbers: [for (final p in c.phones) p.number],
          ),
    ];
  }

  @override
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();
}

final contactsSourceProvider = Provider<ContactsSource>((ref) => const FlutterContactsSource());
