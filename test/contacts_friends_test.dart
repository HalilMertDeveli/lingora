import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/screens/contacts_friends_screen.dart';
import 'package:lingora/screens/friends_screen.dart';
import 'package:lingora/services/contacts/contact_matching.dart';
import 'package:lingora/services/contacts/contacts_source.dart';
import 'package:lingora/services/contacts/phone_numbers.dart';
import 'package:lingora/services/friends.dart';
import 'package:lingora/theme.dart';

import 'friends_test.dart' show FakeFriendsApi, overrides;

class FakeContacts implements ContactsSource {
  FakeContacts(this.access, [this.contacts = const []]);
  ContactsAccess access;
  final List<PhoneContact> contacts;
  int asked = 0;
  int loaded = 0;

  @override
  Future<ContactsAccess> requestAccess() async {
    asked++;
    return access;
  }

  @override
  Future<List<PhoneContact>> load() async {
    loaded++;
    return contacts;
  }

  @override
  Future<void> openSettings() async {}
}

const zeynepPhone = '+905321234567';
const book = [
  PhoneContact(name: 'Zeynep Okul', numbers: ['0532 123 45 67']),
  PhoneContact(name: 'Annem', numbers: ['+90 (533) 000 11 22']),
  PhoneContact(name: 'Kendim', numbers: ['0555 555 55 55']),
];

Future<void> pump(
  WidgetTester tester,
  Widget home, {
  required FakeFriendsApi api,
  FakeContacts? contacts,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625; // a phone: 411 dp wide
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await overrides(api: api),
        contactsSourceProvider.overrideWithValue(contacts ?? FakeContacts(ContactsAccess.granted, book)),
      ],
      // The app's theme: its full-width buttons break rows that were fine without it.
      child: MaterialApp(theme: buildTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('phone numbers', () {
    test('Turkish formats normalise to E.164', () {
      for (final raw in [
        '0532 123 45 67',
        '532 123 45 67',
        '+90 532 123 45 67',
        '90 (532) 123-45-67',
        '0090 532 123 45 67',
        '+905321234567',
        '0532.123.45.67 ext. 12',
      ]) {
        expect(normalizePhone(raw), zeynepPhone, reason: raw);
      }
      expect(normalizePhone('+44 20 7946 0958'), '+442079460958');
      expect(normalizePhone('0049 30 123456'), '+4930123456');
    });

    test('short codes, garbage and wrong lengths are dropped', () {
      for (final raw in ['112', '', 'abc', '0532 123 45', '+90 532 123 45 678', '444 0 444', '+0123']) {
        expect(normalizePhone(raw), isNull, reason: raw);
      }
    });

    test('the hash is salted SHA-256 hex, the same as in firestore.rules', () {
      // Computed with node: sha256('dilmac-rehber-v1:+905321234567').
      expect(phoneHash(zeynepPhone), '73fbd6587a1146001b7434d2d6717918eb138e0bce9a69ab90efb7e2c8d3d843');
      expect(phoneHash(zeynepPhone), isNot(contains('5321234567')));
    });

    test('hashContacts dedupes numbers and leaves out the own number', () {
      final h = hashContacts([
        ...book,
        const PhoneContact(name: 'Zeynep 2', numbers: ['+905321234567']),
      ], myPhone: '+905555555555');
      expect(h, hasLength(2));
      expect(h[phoneHash(zeynepPhone)]!.name, 'Zeynep Okul');
      expect(h.containsKey(phoneHash('+905555555555')), isFalse);
    });

    test('findContactsOnApp sends only hashes and splits the book', () async {
      final api = FakeFriendsApi()
        ..verifiedPhone = '+905555555555'
        ..phoneOwners = {phoneHash(zeynepPhone): 'zeynep'};
      final result = await findContactsOnApp(api, book);
      expect(result.onApp.single.uid, 'zeynep');
      expect(result.onApp.single.name, 'Zeynep Okul');
      expect(result.others.map((c) => c.name), ['Annem', 'Kendim']);
      expect(api.looked, hasLength(2));
      for (final h in api.looked) {
        expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });
  });

  group('FirestoreFriendsApi requests (fake Firestore)', () {
    test('request, inbox, accept: friends with the sender\'s name; request gone', () async {
      final db = FakeFirebaseFirestore();
      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali', avatar: '⭐');
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep', avatar: '🦊');
      expect(await ali.sendRequest('zeynep'), RequestResult.sent);
      expect((await ali.outgoingRequests().first).single.to, 'zeynep');
      final inbox = await zeynep.incomingRequests().first;
      expect(inbox.single.name, 'Ali');
      final pair = await zeynep.acceptRequest(inbox.single);
      expect(pair, 'ali_zeynep');
      final f = (await ali.friendships().first).single;
      expect(f.name, 'Zeynep');
      final z = (await zeynep.friendships().first).single;
      expect(z.name, 'Ali');
      expect((await db.collection('friendships').doc(pair).get()).data()!['code'], '');
      expect((await db.collection('friendRequests').get()).docs, isEmpty);
      await expectLater(ali.sendRequest('zeynep'), throwsA(isA<FriendException>()));
      await expectLater(ali.sendRequest('ali'), throwsA(isA<FriendException>()));
    });

    test('asking someone who already asked you makes you friends at once', () async {
      final db = FakeFirebaseFirestore();
      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali');
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep');
      await ali.sendRequest('zeynep');
      expect(await zeynep.sendRequest('ali'), RequestResult.friends);
      expect(await ali.friendships().first, hasLength(1));
      expect((await db.collection('friendRequests').get()).docs, isEmpty);
    });

    test('adding by code clears pending requests; remove clears cheers', () async {
      final db = FakeFirebaseFirestore();
      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali');
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep');
      await zeynep.sendRequest('ali');
      await ali.addFriend(await zeynep.myCode());
      expect((await db.collection('friendRequests').get()).docs, isEmpty);
      final f = (await ali.friendships().first).single;
      await ali.sendCheer(f, CheerKind.hadi, 20000);
      await zeynep.remove(f.pairId);
      expect((await db.collection('friendships').doc(f.pairId).collection('cheers').get()).docs, isEmpty);
    });

    test('discoverable needs a verified number and writes only its hash', () async {
      final db = FakeFirebaseFirestore();
      final plain = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali');
      expect(await plain.discoverable(), isNull);
      await expectLater(plain.setDiscoverable(true), throwsA(isA<FriendException>()));

      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali', verifiedPhone: '+905555555555');
      expect(await ali.discoverable(), isFalse);
      await ali.setDiscoverable(true);
      expect(await ali.discoverable(), isTrue);
      final docs = (await db.collection('phoneIndex').get()).docs;
      expect(docs.single.id, phoneHash('+905555555555'));
      expect(docs.single.data().keys, unorderedEquals(['uid', 'createdAt']));
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep');
      expect(await zeynep.lookupPhones([phoneHash('+905555555555'), phoneHash(zeynepPhone)]), {
        phoneHash('+905555555555'): 'ali',
      });
      // Your own entry is never a match for yourself.
      expect(await ali.lookupPhones([phoneHash('+905555555555')]), isEmpty);
      await ali.setDiscoverable(false);
      expect((await db.collection('phoneIndex').get()).docs, isEmpty);
    });
  });

  group('Rehberden bul screen', () {
    testWidgets('the permission is asked only after the tap', (tester) async {
      final contacts = FakeContacts(ContactsAccess.granted, book);
      final api = FakeFriendsApi()..phoneOwners = {phoneHash(zeynepPhone): 'zeynep'};
      await pump(tester, const ContactsFriendsScreen(), api: api, contacts: contacts);
      expect(contacts.asked, 0);
      expect(contacts.loaded, 0);
      await tester.tap(find.byKey(const ValueKey('contacts-search')));
      await tester.pumpAndSettle();
      expect(contacts.asked, 1);
      expect(find.text('Zeynep Okul'), findsOneWidget);
      expect(find.text('Annem'), findsOneWidget);
      expect(find.text('Davet et'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('contact-request-zeynep')));
      await tester.pumpAndSettle();
      expect(api.requested, ['zeynep']);
      expect(find.textContaining('arkadaşlık isteği gönderildi'), findsOneWidget);
    });

    testWidgets('a "no" keeps the code method and reads nothing', (tester) async {
      final contacts = FakeContacts(ContactsAccess.denied, book);
      final api = FakeFriendsApi();
      await pump(tester, const ContactsFriendsScreen(), api: api, contacts: contacts);
      await tester.tap(find.byKey(const ValueKey('contacts-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contacts-denied')), findsOneWidget);
      expect(find.textContaining('kodla eklemeye devam'), findsOneWidget);
      expect(contacts.loaded, 0);
      expect(api.looked, isEmpty);
    });

    testWidgets('friends and pending requests are shown as such', (tester) async {
      final api = FakeFriendsApi()
        ..phoneOwners = {phoneHash(zeynepPhone): 'zeynep', phoneHash('+905330001122'): 'anne'}
        ..outgoing = [const FriendRequest(from: 'me', to: 'anne', name: 'Ben', avatar: '⭐')];
      await pump(tester, const ContactsFriendsScreen(), api: api);
      await tester.tap(find.byKey(const ValueKey('contacts-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contact-pending-anne')), findsOneWidget);
      expect(find.byKey(const ValueKey('contact-request-zeynep')), findsOneWidget);
    });

    testWidgets('discoverable switch: off by default, locked without a verified number', (tester) async {
      final api = FakeFriendsApi();
      await pump(tester, const ContactsFriendsScreen(), api: api);
      final locked = tester.widget<SwitchListTile>(find.byKey(const ValueKey('discoverable-switch')));
      expect(locked.value, isFalse);
      expect(locked.onChanged, isNull);
    });

    testWidgets('discoverable switch turns on with a verified number', (tester) async {
      final api = FakeFriendsApi()..verifiedPhone = '+905555555555';
      await pump(tester, const ContactsFriendsScreen(), api: api);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('discoverable-switch'))).value, isFalse);
      await tester.tap(find.byKey(const ValueKey('discoverable-switch')));
      await tester.pumpAndSettle();
      expect(api.discoverableNow, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('discoverable-switch'))).value, isTrue);
    });
  });

  group('requests on the friends screen', () {
    testWidgets('accept, then "Ortak seri başlat" sends a cheer', (tester) async {
      final api = FakeFriendsApi()
        ..incoming = [const FriendRequest(from: 'zeynep', to: 'me', name: 'Zeynep', avatar: '🦊')];
      await pump(tester, const FriendsScreen(), api: api);
      expect(find.text('Zeynep seninle arkadaş olmak istiyor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request-accept-zeynep')));
      await tester.pumpAndSettle();
      expect(api.accepted, ['zeynep']);
      expect(find.byKey(const ValueKey('shared-streak-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shared-streak-start')));
      await tester.pumpAndSettle();
      expect(api.cheered, [('zeynep', CheerKind.hadi)]);
    });

    testWidgets('decline deletes the request', (tester) async {
      final api = FakeFriendsApi()
        ..incoming = [const FriendRequest(from: 'zeynep', to: 'me', name: 'Zeynep', avatar: '🦊')];
      await pump(tester, const FriendsScreen(), api: api);
      await tester.tap(find.byKey(const ValueKey('request-decline-zeynep')));
      await tester.pumpAndSettle();
      expect(api.deleted, ['zeynep_me']);
    });

    testWidgets('"Rehberden bul" opens the contacts screen', (tester) async {
      await pump(tester, const FriendsScreen(), api: FakeFriendsApi());
      await tester.tap(find.byKey(const ValueKey('friends-contacts')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactsFriendsScreen), findsOneWidget);
    });
  });

  test('the invite text carries the Play link and the code', () {
    expect(contactInviteText('ABCD2345'), allOf(contains(dilmacPlayLink), contains('ABCD2345')));
    expect(contactInviteText(null), contains(dilmacPlayLink));
  });
}
