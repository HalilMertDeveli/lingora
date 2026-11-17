import '../friends.dart';
import 'contacts_source.dart';
import 'phone_numbers.dart';

/// At most this many distinct numbers are looked up per search (each is one
/// Firestore read; docs/arkadaslar.md).
const maxContactLookups = 500;

/// A phone-book entry whose number belongs to a discoverable Dilmaç user.
class ContactOnApp {
  const ContactOnApp({required this.name, required this.uid});

  /// The name as saved in this phone's book (never uploaded).
  final String name;
  final String uid;
}

/// The phone book split into people on Dilmaç and everyone else.
class ContactBook {
  const ContactBook({required this.onApp, required this.others, this.truncated = false});
  final List<ContactOnApp> onApp;
  final List<PhoneContact> others;

  /// More numbers than [maxContactLookups]; the rest were not checked.
  final bool truncated;
}

/// Phone hashes of [contacts] (normalised to E.164 on the phone), each with
/// the first contact that has that number. The user's own number is left out.
Map<String, PhoneContact> hashContacts(List<PhoneContact> contacts, {String? myPhone}) {
  final mine = myPhone == null ? null : normalizePhone(myPhone);
  final out = <String, PhoneContact>{};
  for (final c in contacts) {
    for (final n in c.numbers) {
      final e164 = normalizePhone(n);
      if (e164 == null || e164 == mine) continue;
      out.putIfAbsent(phoneHash(e164), () => c);
    }
  }
  return out;
}

/// Looks the phone book up in phoneIndex. Only hashes leave the phone.
Future<ContactBook> findContactsOnApp(FriendsApi api, List<PhoneContact> contacts) async {
  final hashed = hashContacts(contacts, myPhone: api.verifiedPhone);
  final keys = hashed.keys.take(maxContactLookups).toList();
  final found = await api.lookupPhones(keys);
  final onApp = <String, ContactOnApp>{};
  final matched = <PhoneContact>{};
  for (final h in keys) {
    final uid = found[h];
    if (uid == null) continue;
    matched.add(hashed[h]!);
    onApp.putIfAbsent(uid, () => ContactOnApp(name: hashed[h]!.name, uid: uid));
  }
  final others = [
    for (final c in contacts)
      if (!matched.contains(c)) c,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final list = onApp.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return ContactBook(onApp: list, others: others, truncated: hashed.length > keys.length);
}
