import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/friends_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lingora/services/friends.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Monday 2026-11-16, 12:00 in Turkey (09:00 UTC).
final now = DateTime.utc(2026, 11, 16, 9);
final today = friendDay(now);

class FakeFriendsApi implements FriendsApi {
  FakeFriendsApi({List<Friendship> friends = const [], this.cheerList = const []})
    : _friends = StreamController<List<Friendship>>.broadcast(),
      current = friends;

  final StreamController<List<Friendship>> _friends;
  List<Friendship> current;
  final List<Cheer> cheerList;
  final added = <String>[];
  final sent = <CheerKind>[];
  final removed = <String>[];
  final marked = <int>[];

  @override
  String get uid => 'me';

  @override
  Future<String> myCode() async => 'ABCD2345';

  @override
  Future<String> addFriend(String code) async {
    final c = normalizeFriendCode(code);
    if (c == null) throw const FriendException('format');
    added.add(c);
    if (c == 'ZZZZ2222') throw const FriendException('notFound');
    return 'Zeynep';
  }

  @override
  Stream<List<Friendship>> friendships() async* {
    yield current;
    yield* _friends.stream;
  }

  @override
  Stream<List<Cheer>> cheers(String pairId, int day) => Stream.value(cheerList);

  @override
  Future<void> sendCheer(Friendship f, CheerKind kind, int day) async {
    sent.add(kind);
    cheered.add((f.friendUid, kind));
  }

  @override
  Future<void> remove(String pairId) async => removed.add(pairId);

  @override
  Future<void> markGoal(int day) async => marked.add(day);

  @override
  String myName = 'Ben';
  final nameSyncs = <bool>[];

  @override
  Future<void> syncMyName({bool friendships = true}) async => nameSyncs.add(friendships);

  // ---- Requests and phone discovery ----
  List<FriendRequest> incoming = [];
  List<FriendRequest> outgoing = [];
  final requested = <String>[];
  final accepted = <String>[];
  final deleted = <String>[];
  final cheered = <(String, CheerKind)>[];
  Map<String, String> phoneOwners = {};
  final looked = <String>[];
  @override
  String? verifiedPhone;
  bool discoverableNow = false;

  @override
  Future<RequestResult> sendRequest(String toUid) async {
    requested.add(toUid);
    outgoing = [...outgoing, FriendRequest(from: uid, to: toUid, name: 'Ben', avatar: '⭐')];
    return RequestResult.sent;
  }

  @override
  Stream<List<FriendRequest>> incomingRequests() => Stream.value(incoming);

  @override
  Stream<List<FriendRequest>> outgoingRequests() => Stream.value(outgoing);

  @override
  Future<String> acceptRequest(FriendRequest r) async {
    accepted.add(r.from);
    return pairIdOf(r.from, r.to);
  }

  @override
  Future<void> deleteRequest(FriendRequest r) async => deleted.add(r.id);

  @override
  Future<bool?> discoverable() async => verifiedPhone == null ? null : discoverableNow;

  @override
  Future<void> setDiscoverable(bool on) async => discoverableNow = on;

  @override
  Future<Map<String, String>> lookupPhones(Iterable<String> hashes) async {
    looked.addAll(hashes);
    return {for (final h in hashes) h: ?phoneOwners[h]};
  }
}

Friendship friend({int myDay = 0, int friendDay = 0, int streak = 0, int best = 0, int streakDay = 0}) =>
    Friendship(
      pairId: 'me_zeynep',
      friendUid: 'zeynep',
      name: 'Zeynep',
      avatar: '🦊',
      myDay: myDay,
      friendDay: friendDay,
      streak: streak,
      best: best,
      streakDay: streakDay,
    );

Future<List<Override>> overrides({FriendsApi? api, Progress progress = const Progress()}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  return [
    prefsProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => now),
    friendsApiProvider.overrideWithValue(api),
  ];
}

Future<void> pumpScreen(WidgetTester tester, {FriendsApi? api}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: await overrides(api: api),
      child: const MaterialApp(home: FriendsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('helpers', () {
    test('friendDay is the Turkish calendar day (UTC+3)', () {
      // 20:59 UTC is 23:59 in Turkey; 21:00 UTC is already the next day.
      expect(friendDay(DateTime.utc(2026, 11, 16, 20, 59)), today);
      expect(friendDay(DateTime.utc(2026, 11, 16, 21)), today + 1);
      expect(friendDay(DateTime.utc(2026, 11, 15, 21)), today);
      expect(today, (DateTime.utc(2026, 11, 16).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay));
    });

    test('codes use only unambiguous characters', () {
      final r = Random(1);
      for (var i = 0; i < 200; i++) {
        final c = newFriendCode(r);
        expect(c, hasLength(8));
        expect(c, isNot(matches(RegExp('[01IO]'))));
        expect(normalizeFriendCode(c), c);
      }
      expect(normalizeFriendCode(' abcd-2345 '), 'ABCD2345');
      expect(normalizeFriendCode('ABCD0345'), isNull);
      expect(normalizeFriendCode('ABC'), isNull);
    });

    test('pair ids are sorted and avatars stable', () {
      expect(pairIdOf('b', 'a'), 'a_b');
      expect(pairIdOf('a', 'b'), 'a_b');
      expect(friendAvatar('xyz'), friendAvatar('xyz'));
    });

    test('goalUpdate grows the streak only when both made it today', () {
      Map<String, dynamic> doc({
        Map<String, int> done = const {},
        int streak = 0,
        int best = 0,
        int day = 0,
      }) => {
        'members': ['a', 'b'],
        'done': done,
        'streak': streak,
        'best': best,
        'streakDay': day,
      };
      final t = today;
      // Alone: only the mark.
      expect(goalUpdate(doc(), 'a', t), {'done.a': t});
      // Friend already done, streak new.
      expect(goalUpdate(doc(done: {'b': t}), 'a', t), {'done.a': t, 'streak': 1, 'streakDay': t, 'best': 1});
      // Consecutive day.
      expect(goalUpdate(doc(done: {'b': t}, streak: 4, best: 6, day: t - 1), 'a', t), {
        'done.a': t,
        'streak': 5,
        'streakDay': t,
        'best': 6,
      });
      // A gap restarts at 1 but keeps the best.
      expect(goalUpdate(doc(done: {'b': t}, streak: 4, best: 6, day: t - 2), 'a', t), {
        'done.a': t,
        'streak': 1,
        'streakDay': t,
        'best': 6,
      });
      // Already marked today: nothing.
      expect(goalUpdate(doc(done: {'a': t}), 'a', t), isNull);
    });

    test('the shown streak lapses after a missed day', () {
      expect(friend(streak: 3, streakDay: today).streakOn(today), 3);
      expect(friend(streak: 3, streakDay: today - 1).streakOn(today), 3);
      expect(friend(streak: 3, streakDay: today - 2).streakOn(today), 0);
    });

    test('Friendship.fromMap sees the other member', () {
      final f = Friendship.fromMap('a_b', {
        'members': ['a', 'b'],
        'names': {'a': 'Ali', 'b': 'Banu'},
        'avatars': {'a': '⭐', 'b': '🐢'},
        'done': {'b': today},
        'streak': 2,
        'best': 5,
        'streakDay': today - 1,
      }, 'a')!;
      expect(f.friendUid, 'b');
      expect(f.name, 'Banu');
      expect(f.avatar, '🐢');
      expect(f.friendDone(today), isTrue);
      expect(f.meDone(today), isFalse);
      expect(
        Friendship.fromMap('x_y', {
          'members': ['x', 'y'],
        }, 'a'),
        isNull,
      );
    });
  });

  group('FirestoreFriendsApi (fake Firestore)', () {
    test('code, adding a friend, shared streak, cheers and removal', () async {
      final db = FakeFirebaseFirestore();
      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali');
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep');

      final code = await zeynep.myCode();
      expect(normalizeFriendCode(code), code);
      expect(await zeynep.myCode(), code, reason: 'the same code is reused');

      await expectLater(
        ali.addFriend('ABCD0'),
        throwsA(isA<FriendException>().having((e) => e.reason, 'r', 'format')),
      );
      await expectLater(
        ali.addFriend('ZZZZ2222'),
        throwsA(isA<FriendException>().having((e) => e.reason, 'r', 'notFound')),
      );
      await expectLater(
        zeynep.addFriend(code),
        throwsA(isA<FriendException>().having((e) => e.reason, 'r', 'self')),
      );

      expect(await ali.addFriend(code.toLowerCase()), 'Zeynep');
      await expectLater(
        ali.addFriend(code),
        throwsA(isA<FriendException>().having((e) => e.reason, 'r', 'already')),
      );

      final pair = (await db.doc('friendships/ali_zeynep').get()).data()!;
      expect(pair['members'], ['ali', 'zeynep']);
      expect(pair['names'], {'ali': 'Ali', 'zeynep': 'Zeynep'});
      expect(pair['code'], code);

      // Zeynep sees Ali in her list.
      final list = await zeynep.friendships().first;
      expect(list.single.name, 'Ali');

      // Ali first, then Zeynep: the streak starts once.
      final t = today;
      await ali.markGoal(t);
      var d = (await db.doc('friendships/ali_zeynep').get()).data()!;
      expect(d['streak'], 0);
      await zeynep.markGoal(t);
      await zeynep.markGoal(t);
      d = (await db.doc('friendships/ali_zeynep').get()).data()!;
      expect((d['streak'], d['best'], d['streakDay']), (1, 1, t));

      // Next day, both again.
      await zeynep.markGoal(t + 1);
      await ali.markGoal(t + 1);
      d = (await db.doc('friendships/ali_zeynep').get()).data()!;
      expect((d['streak'], d['best']), (2, 2));

      // Cheers.
      final f = (await ali.friendships().first).single;
      await ali.sendCheer(f, CheerKind.tebrik, t + 1);
      final cheers = await zeynep.cheers('ali_zeynep', t + 1).first;
      expect(cheers.single.kind, CheerKind.tebrik);
      expect(cheers.single.to, 'zeynep');
      expect(await zeynep.cheers('ali_zeynep', t).first, isEmpty);

      await zeynep.remove('ali_zeynep');
      expect(await ali.friendships().first, isEmpty);
    });
  });

  group('friendGoalSyncProvider', () {
    test('marks the goal once today reaches it', () async {
      final api = FakeFriendsApi(friends: [friend()]);
      final dayKeyNow = dayKey(now);
      final c = ProviderContainer(
        overrides: await overrides(
          api: api,
          progress: Progress(dailyGoal: 20, xpByDay: {dayKeyNow: 25}),
        ),
      );
      addTearDown(c.dispose);
      c.listen(friendGoalSyncProvider, (_, _) {});
      c.listen(friendshipsProvider, (_, _) {});
      await c.read(friendshipsProvider.future);
      await Future<void>.delayed(Duration.zero);
      c.read(friendGoalSyncProvider);
      expect(api.marked, [today]);
    });

    test('does nothing below the goal or when already marked', () async {
      for (final (xp, f) in [(5, friend()), (25, friend(myDay: today))]) {
        final api = FakeFriendsApi(friends: [f]);
        final c = ProviderContainer(
          overrides: await overrides(
            api: api,
            progress: Progress(dailyGoal: 20, xpByDay: {dayKey(now): xp}),
          ),
        );
        c.listen(friendGoalSyncProvider, (_, _) {});
        c.listen(friendshipsProvider, (_, _) {});
        await c.read(friendshipsProvider.future);
        await Future<void>.delayed(Duration.zero);
        c.read(friendGoalSyncProvider);
        expect(api.marked, isEmpty);
        c.dispose();
      }
    });
  });

  group('FriendsScreen', () {
    testWidgets('guests are asked to link an account', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('ücretsiz bir Dilmaç hesabı'), findsOneWidget);
      expect(find.byKey(const ValueKey('friend-code-field')), findsNothing);
    });

    testWidgets('shows the code and an empty list', (tester) async {
      await pumpScreen(tester, api: FakeFriendsApi());
      expect(find.byKey(const ValueKey('friend-my-code')), findsOneWidget);
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.byKey(const ValueKey('friends-empty')), findsOneWidget);
    });

    testWidgets('adds a friend and shows errors in Turkish', (tester) async {
      final api = FakeFriendsApi();
      await pumpScreen(tester, api: api);
      await tester.enterText(find.byKey(const ValueKey('friend-code-field')), 'zzzz2222');
      await tester.tap(find.byKey(const ValueKey('friend-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bulunamadı'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('friend-code-field')), 'qrst6789');
      await tester.tap(find.byKey(const ValueKey('friend-add')));
      await tester.pumpAndSettle();
      expect(api.added.last, 'QRST6789');
      expect(find.text('Zeynep ile artık arkadaşsınız!'), findsOneWidget);
    });

    testWidgets('friend card: streak, today, cheers and removal', (tester) async {
      final api = FakeFriendsApi(
        friends: [friend(friendDay: today, streak: 4, best: 7, streakDay: today - 1)],
        cheerList: [
          Cheer(from: 'zeynep', to: 'me', kind: CheerKind.hadi, day: today),
          Cheer(from: 'me', to: 'zeynep', kind: CheerKind.tebrik, day: today),
        ],
      );
      await pumpScreen(tester, api: api);
      final streak = find.byKey(const ValueKey('friend-streak-zeynep'));
      await tester.scrollUntilVisible(streak, 200, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<Text>(streak).data, '4');
      expect(find.text('En iyi ortak seri: 7 gün'), findsOneWidget);
      expect(find.textContaining('Sıra sende'), findsOneWidget);
      expect(find.byKey(const ValueKey('cheer-in-hadi')), findsOneWidget);

      // Tebrik was already sent today; Destek goes out.
      final tebrik = find.byKey(const ValueKey('cheer-zeynep-tebrik'));
      expect(tester.widget<ActionChip>(tebrik).onPressed, isNull);
      final destek = find.byKey(const ValueKey('cheer-zeynep-destek'));
      await tester.scrollUntilVisible(destek, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(destek);
      await tester.pump();
      expect(api.sent, [CheerKind.destek]);

      await tester.tap(find.byTooltip('Seçenekler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arkadaşlıktan çıkar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Çıkar'));
      await tester.pumpAndSettle();
      expect(api.removed, ['me_zeynep']);
    });

    testWidgets('a lapsed streak shows 0', (tester) async {
      await pumpScreen(
        tester,
        api: FakeFriendsApi(friends: [friend(streak: 9, best: 9, streakDay: today - 3)]),
      );
      final streak = find.byKey(const ValueKey('friend-streak-zeynep'));
      await tester.scrollUntilVisible(streak, 200, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<Text>(streak).data, '0');
    });
  });

  test('share text carries the code', () {
    expect(friendShareText('ABCD2345'), contains('ABCD2345'));
  });
}
