// End-to-end tests of friends ("birlikte çalış" codes, the shared streak,
// cheers) and of finding friends from the phone book, with two (and more)
// real accounts against the Firebase Emulator Suite and firestore.rules.
//
//   firebase emulators:start --only auth,firestore --project demo-lingora
//   flutter test integration_test/friends_flow_test.dart -d emulator-5554
//
// See docs/arkadaslar.md. Nothing here can reach the real project.
@Timeout(Duration(minutes: 4))
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingora/services/contacts/contact_matching.dart';
import 'package:lingora/services/contacts/contacts_source.dart' show PhoneContact;
import 'package:lingora/services/contacts/phone_numbers.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/demo_firebase_options.dart';
import 'package:lingora/services/firebase/firebase_config.dart';
import 'package:lingora/services/friends.dart';

import 'support/emulator.dart';

/// One signed-in phone: its own FirebaseApp, so its own user and cache.
class Person {
  Person._(this.auth, this.db, this.api);
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirestoreFriendsApi api;

  String get uid => api.uid;

  static int _n = 0;

  static Future<(FirebaseAuth, FirebaseFirestore)> _app(Emulators emu) async {
    final app = await Firebase.initializeApp(
      name: 'friend-${DateTime.now().microsecondsSinceEpoch}-${_n++}',
      options: demoFirebaseOptions(),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator(emu.host, authEmulatorPort);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.useFirestoreEmulator(emu.host, firestoreEmulatorPort);
    return (auth, db);
  }

  /// An e-mail account named [name].
  static Future<Person> email(Emulators emu, String email, String name) async {
    final (auth, db) = await _app(emu);
    final cred = await auth.createUserWithEmailAndPassword(email: email, password: 'secret123');
    return Person._(auth, db, FirestoreFriendsApi(db, uid: cred.user!.uid, name: name));
  }

  /// An account made by phone sign-in (the SMS code comes from the emulator).
  static Future<Person> phone(Emulators emu, String raw, String name) async {
    final (auth, db) = await _app(emu);
    final account = AccountService(auth);
    final e164 = normalizePhone(raw)!;
    final id = await account.startPhoneSignIn(raw);
    await account.confirmPhoneCode(id!, await emu.smsCode(e164));
    await until(() => auth.currentUser?.phoneNumber == e164, 'phone sign-in $e164');
    final user = auth.currentUser!;
    return Person._(
      auth,
      db,
      FirestoreFriendsApi(db, uid: user.uid, name: name, verifiedPhone: user.phoneNumber),
    );
  }

  /// A guest (anonymous) account.
  static Future<Person> guest(Emulators emu) async {
    final (auth, db) = await _app(emu);
    final cred = await auth.signInAnonymously();
    return Person._(auth, db, FirestoreFriendsApi(db, uid: cred.user!.uid, name: 'Misafir'));
  }

  Future<void> close() async {
    await db.terminate();
    await auth.signOut();
  }

  /// The friendship as stored on the server (not the local cache).
  Future<Friendship?> pair(Person other) async {
    final snap = await db
        .collection('friendships')
        .doc(pairIdOf(uid, other.uid))
        .get(const GetOptions(source: Source.server));
    final data = snap.data();
    return data == null ? null : Friendship.fromMap(snap.id, data, uid);
  }

  /// Today's cheers in [pairId], from the server.
  Future<List<Cheer>> cheersIn(String pairId, int day) async {
    final s = await db
        .collection('friendships/$pairId/cheers')
        .where('day', isEqualTo: day)
        .get(const GetOptions(source: Source.server));
    return [
      for (final d in s.docs)
        Cheer(
          from: d['from'] as String,
          to: d['to'] as String,
          kind: CheerKind.values.byName(d['kind'] as String),
          day: day,
        ),
    ];
  }
}

Future<void> denied(Future<Object?> f, String what) async {
  try {
    await f;
  } on FirebaseException catch (e) {
    expect(e.code, 'permission-denied', reason: what);
    return;
  }
  fail('Expected permission-denied: $what');
}

Future<void> friendError(Future<Object?> f, String reason) async {
  try {
    await f;
  } on FriendException catch (e) {
    expect(e.reason, reason);
    return;
  }
  fail('Expected FriendException($reason)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final emu = Emulators();
  final people = <Person>[];

  Future<Person> track(Future<Person> p) async => p.then((x) {
    people.add(x);
    return x;
  });

  setUpAll(() async {
    await emu.waitReady();
  });

  setUp(() async {
    await emu.reset();
  });

  tearDown(() async {
    for (final p in people) {
      await p.close();
    }
    people.clear();
  });

  // The server's Turkish day; the test assumes it does not roll over
  // (00:00 Türkiye) while it runs.
  int today() => friendDay(DateTime.now());

  group('A. friend codes and the shared streak', () {
    test('code: created once, well formed, stable', () async {
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      final code = await zeynep.api.myCode();
      expect(normalizeFriendCode(code), code);
      expect(await zeynep.api.myCode(), code, reason: 'the same code comes back');
    });

    test('adding by code; own, unknown, malformed and repeated codes are refused', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      final code = await zeynep.api.myCode();

      await friendError(zeynep.api.addFriend(code), 'self');
      await friendError(ali.api.addFriend('abc'), 'format');
      await friendError(ali.api.addFriend(code == 'ABCDEFGH' ? 'ABCDEFGJ' : 'ABCDEFGH'), 'notFound');

      final typed = '${code.substring(0, 4).toLowerCase()}-${code.substring(4)}';
      expect(await ali.api.addFriend(typed), 'Zeynep');
      final f = await zeynep.pair(ali);
      expect(f, isNotNull);
      expect(f!.name, 'Ali');
      expect((await ali.pair(zeynep))!.name, 'Zeynep');

      await friendError(ali.api.addFriend(code), 'already');
      // Zeynep adding Ali's code is the same friendship.
      await friendError(zeynep.api.addFriend(await ali.api.myCode()), 'already');
    });

    test('the streak grows when both reach the goal the same day, breaks after a missed day', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      await ali.api.addFriend(await zeynep.api.myCode());
      final t = today();
      final pairId = pairIdOf(ali.uid, zeynep.uid);

      // Only Ali today: no streak yet.
      await ali.api.markGoal(t);
      var f = (await ali.pair(zeynep))!;
      expect(f.meDone(t), isTrue);
      expect(f.friendDone(t), isFalse);
      expect(f.streakOn(t), 0);
      // Marking again changes nothing.
      await ali.api.markGoal(t);
      // Zeynep too: the streak starts.
      await zeynep.api.markGoal(t);
      f = (await ali.pair(zeynep))!;
      expect((f.streak, f.best, f.streakDay), (1, 1, t));

      // Yesterday both made it (streak 3): today it becomes 4.
      await emu.patchDoc('friendships/$pairId', {
        'done': {ali.uid: t - 1, zeynep.uid: t - 1},
        'streak': 3,
        'best': 3,
        'streakDay': t - 1,
      });
      expect((await ali.pair(zeynep))!.streakOn(t), 3, reason: 'still alive today');
      await zeynep.api.markGoal(t);
      expect((await ali.pair(zeynep))!.streak, 3, reason: 'Ali has not made it yet');
      await ali.api.markGoal(t);
      f = (await zeynep.pair(ali))!;
      expect((f.streak, f.best, f.streakDay), (4, 4, t));

      // Zeynep missed yesterday (streak 5 last grew two days ago): broken.
      await emu.patchDoc('friendships/$pairId', {
        'done': {ali.uid: t - 1, zeynep.uid: t - 2},
        'streak': 5,
        'best': 5,
        'streakDay': t - 2,
      });
      expect((await ali.pair(zeynep))!.streakOn(t), 0, reason: 'shown as 0 after a missed day');
      await ali.api.markGoal(t);
      await zeynep.api.markGoal(t);
      f = (await ali.pair(zeynep))!;
      expect((f.streak, f.best, f.streakDay), (1, 5, t), reason: 'restarts at 1, best kept');
    });

    test('cheers both ways, once per kind and day', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      await ali.api.addFriend(await zeynep.api.myCode());
      final t = today();
      final forAli = (await ali.pair(zeynep))!;
      final forZeynep = (await zeynep.pair(ali))!;

      await ali.api.sendCheer(forAli, CheerKind.destek, t);
      await ali.api.sendCheer(forAli, CheerKind.hadi, t);
      await zeynep.api.sendCheer(forZeynep, CheerKind.tebrik, t);
      await denied(ali.api.sendCheer(forAli, CheerKind.destek, t), 'same cheer twice a day');

      final seenByZeynep = await zeynep.cheersIn(forZeynep.pairId, t);
      expect(
        {
          for (final c in seenByZeynep)
            if (c.from == ali.uid) c.kind,
        },
        {CheerKind.destek, CheerKind.hadi},
      );
      expect(seenByZeynep.where((c) => c.from == ali.uid).every((c) => c.to == zeynep.uid), isTrue);
      final seenByAli = await ali.cheersIn(forAli.pairId, t);
      expect(
        [
          for (final c in seenByAli)
            if (c.from == zeynep.uid) c.kind,
        ],
        [CheerKind.tebrik],
      );
      // The app's stream sees them as well.
      final live = await ali.api.cheers(forAli.pairId, t).firstWhere((l) => l.length == 3);
      expect(live, hasLength(3));
    });

    test('unfriending removes the pair and its cheers; adding again starts clean', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      final code = await zeynep.api.myCode();
      await ali.api.addFriend(code);
      final t = today();
      final f = (await ali.pair(zeynep))!;
      await ali.api.sendCheer(f, CheerKind.hadi, t);

      await zeynep.api.remove(f.pairId);
      expect(await ali.pair(zeynep), isNull);
      expect(await ali.api.friendships().firstWhere((l) => l.isEmpty), isEmpty);
      await denied(ali.cheersIn(f.pairId, t), 'cheers of a removed pair');

      // Same day, same two people: the same cheer can be sent again.
      await ali.api.addFriend(code);
      final again = (await ali.pair(zeynep))!;
      expect(again.streak, 0);
      await ali.api.sendCheer(again, CheerKind.hadi, t);
    });

    test('security: outsiders cannot write, read or scan', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      final mallory = await track(Person.email(emu, 'mallory@test.dev', 'Mallory'));
      final guest = await track(Person.guest(emu));
      final code = await zeynep.api.myCode();
      await ali.api.addFriend(code);
      final pairId = pairIdOf(ali.uid, zeynep.uid);
      final pair = mallory.db.collection('friendships').doc(pairId);
      final t = today();

      // Someone else's friendship: no reading, marking, renaming, deleting, cheering.
      await denied(pair.get(const GetOptions(source: Source.server)), 'read');
      await denied(pair.update({'done.${mallory.uid}': t}), 'mark');
      await denied(pair.update({'names.${ali.uid}': 'Kötü'}), 'rename');
      await denied(pair.update({'streak': 99}), 'streak');
      await denied(pair.delete(), 'delete');
      await denied(
        pair.collection('cheers').doc('${mallory.uid}_${t}_hadi').set({
          'from': mallory.uid,
          'to': ali.uid,
          'kind': 'hadi',
          'day': t,
          'createdAt': FieldValue.serverTimestamp(),
        }),
        'cheer',
      );
      // A member cannot forge the other member's day or the streak either.
      await denied(
        ali.db.collection('friendships').doc(pairId).update({'done.${zeynep.uid}': t}),
        "the friend's day",
      );
      await denied(
        ali.db.collection('friendships').doc(pairId).update({'streak': 30, 'best': 30, 'streakDay': t}),
        'a made-up streak',
      );
      // No pairing two other people, nor oneself with a stolen code.
      await denied(
        mallory.db.collection('friendships').doc(pairId).set({
          'members': [ali.uid, zeynep.uid]..sort(),
        }),
        'pair two others',
      );

      // Codes: one at a time only; no listing, no taking over, guests none.
      await denied(mallory.db.collection('friendCodes').get(const GetOptions(source: Source.server)), 'list');
      await denied(
        mallory.db
            .collection('friendCodes')
            .where('uid', isEqualTo: zeynep.uid)
            .get(const GetOptions(source: Source.server)),
        'list by uid',
      );
      await denied(
        mallory.db.collection('friendCodes').doc(code).set({
          'uid': mallory.uid,
          'name': 'Mallory',
          'avatar': '🦊',
          'createdAt': FieldValue.serverTimestamp(),
        }),
        'take over a code',
      );
      await denied(
        guest.db.collection('friendCodes').doc(code).get(const GetOptions(source: Source.server)),
        'guest',
      );
      await friendError(guest.api.addFriend(code), 'offline');
      // A guessed code is just "not found" (32^8 codes; nothing to list).
      await friendError(mallory.api.addFriend('ZZZZ2222'), 'notFound');
    });
  });

  group('B. phone book: opt-in discovery and friend requests', () {
    test('only a verified number can be published, as a hash; off by default', () async {
      final ali = await track(Person.phone(emu, '0532 111 22 33', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));
      final aliHash = phoneHash('+905321112233');

      expect(await ali.api.discoverable(), isFalse, reason: 'off by default');
      expect(await zeynep.api.lookupPhones([aliHash]), isEmpty);
      // An e-mail account has no verified number.
      expect(await zeynep.api.discoverable(), isNull);
      await friendError(zeynep.api.setDiscoverable(true), 'noPhone');
      // Publishing a number that is not one's own.
      await denied(
        zeynep.db.collection('phoneIndex').doc(aliHash).set({
          'uid': zeynep.uid,
          'createdAt': FieldValue.serverTimestamp(),
        }),
        "someone else's number",
      );

      await ali.api.setDiscoverable(true);
      expect(await ali.api.discoverable(), isTrue);
      expect(await zeynep.api.lookupPhones([aliHash, phoneHash('+905320000000')]), {aliHash: ali.uid});
      // The index cannot be listed or searched by uid.
      await denied(zeynep.db.collection('phoneIndex').get(const GetOptions(source: Source.server)), 'list');
      await denied(
        zeynep.db
            .collection('phoneIndex')
            .where('uid', isEqualTo: ali.uid)
            .get(const GetOptions(source: Source.server)),
        'by uid',
      );
      // What is stored: the uid and a time, no number.
      final stored = await ali.db
          .collection('phoneIndex')
          .doc(aliHash)
          .get(const GetOptions(source: Source.server));
      expect(stored.data()!.keys.toSet(), {'uid', 'createdAt'});
      expect(aliHash, isNot(contains('5321112233')));

      await ali.api.setDiscoverable(false);
      expect(await zeynep.api.lookupPhones([aliHash]), isEmpty);
    });

    test('request from the phone book → accept → friends with a shared streak', () async {
      final ali = await track(Person.phone(emu, '0532 111 22 33', 'Ali'));
      final zeynep = await track(Person.phone(emu, '0533 444 55 66', 'Zeynep'));
      final mallory = await track(Person.email(emu, 'mallory@test.dev', 'Mallory'));
      await ali.api.setDiscoverable(true);

      // Zeynep's phone book: Ali (saved her own way), her mother (not on Dilmaç).
      final book = await findContactsOnApp(zeynep.api, [
        const PhoneContact(name: 'Ali Okul', numbers: ['0532 111 22 33']),
        const PhoneContact(name: 'Annem', numbers: ['0535 000 00 00']),
        const PhoneContact(name: 'Ben', numbers: ['+90 533 444 55 66']),
      ]);
      expect(book.onApp.map((c) => (c.name, c.uid)), [('Ali Okul', ali.uid)]);
      expect(book.others.map((c) => c.name), ['Annem', 'Ben']);

      expect(await zeynep.api.sendRequest(ali.uid), RequestResult.sent);
      final inbox = await ali.api.incomingRequests().firstWhere((l) => l.isNotEmpty);
      expect(inbox.single.from, zeynep.uid);
      expect(inbox.single.name, 'Zeynep');
      expect((await zeynep.api.outgoingRequests().firstWhere((l) => l.isNotEmpty)).single.to, ali.uid);

      // Outsiders cannot read, answer or forge requests.
      final reqId = '${zeynep.uid}_${ali.uid}';
      await denied(
        mallory.db.collection('friendRequests').doc(reqId).get(const GetOptions(source: Source.server)),
        'read a request',
      );
      await denied(mallory.db.collection('friendRequests').doc(reqId).delete(), 'delete a request');
      await denied(
        mallory.db.collection('friendRequests').doc('${zeynep.uid}_${mallory.uid}').set({
          'from': zeynep.uid,
          'to': mallory.uid,
          'name': 'Zeynep',
          'avatar': '🦊',
          'createdAt': FieldValue.serverTimestamp(),
        }),
        'request in her name',
      );
      // The sender cannot accept her own request.
      await denied(
        zeynep.db.collection('friendships').doc(pairIdOf(ali.uid, zeynep.uid)).set({
          'members': [ali.uid, zeynep.uid]..sort(),
          'code': '',
          'names': {ali.uid: 'Ali', zeynep.uid: 'Zeynep'},
          'avatars': {ali.uid: ali.api.avatar, zeynep.uid: zeynep.api.avatar},
          'done': <String, Object>{},
          'streak': 0,
          'best': 0,
          'streakDay': 0,
          'createdAt': FieldValue.serverTimestamp(),
        }),
        'accept own request',
      );

      final pairId = await ali.api.acceptRequest(inbox.single);
      expect((await zeynep.pair(ali))!.name, 'Ali');
      expect(await ali.api.incomingRequests().firstWhere((l) => l.isEmpty), isEmpty);
      await friendError(zeynep.api.sendRequest(ali.uid), 'already');

      // "Ortak seri başlat": a cheer, then the streak as with codes.
      final t = today();
      await ali.api.sendCheer((await ali.pair(zeynep))!, CheerKind.hadi, t);
      expect((await zeynep.cheersIn(pairId, t)).single.kind, CheerKind.hadi);
      await ali.api.markGoal(t);
      await zeynep.api.markGoal(t);
      expect((await ali.pair(zeynep))!.streak, 1);
    });

    test('declining and withdrawing; asking back makes friends at once', () async {
      final ali = await track(Person.email(emu, 'ali@test.dev', 'Ali'));
      final zeynep = await track(Person.email(emu, 'zeynep@test.dev', 'Zeynep'));

      await zeynep.api.sendRequest(ali.uid);
      final r = (await ali.api.incomingRequests().firstWhere((l) => l.isNotEmpty)).single;
      await ali.api.deleteRequest(r); // decline
      expect(await zeynep.api.outgoingRequests().firstWhere((l) => l.isEmpty), isEmpty);
      expect(await ali.pair(zeynep), isNull);

      await zeynep.api.sendRequest(ali.uid);
      await zeynep.api.deleteRequest(
        FriendRequest(from: zeynep.uid, to: ali.uid, name: '', avatar: ''),
      ); // withdraw
      expect(await ali.api.incomingRequests().firstWhere((l) => l.isEmpty), isEmpty);

      await zeynep.api.sendRequest(ali.uid);
      expect(await ali.api.sendRequest(zeynep.uid), RequestResult.friends);
      expect(await zeynep.pair(ali), isNotNull);
    });
  });
}
