import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/screens/friends_screen.dart';
import 'package:lingora/services/friends.dart';
import 'package:lingora/services/profile.dart';
import 'package:lingora/theme.dart';

import 'friends_test.dart' show FakeFriendsApi, friend, overrides;

Future<ProviderContainer> pump(WidgetTester tester, FakeFriendsApi api, {String? liveName}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await overrides(api: api),
        friendProfileProvider.overrideWith((ref, uid) => Stream.value(ProfileData(name: liveName))),
      ],
      child: MaterialApp(theme: buildTheme(), home: const FriendsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FriendsScreen)));
}

void main() {
  group('name sync (fake Firestore)', () {
    test('a nameless friend renames: code and friendships follow, only their own entry', () async {
      final db = FakeFirebaseFirestore();
      final zeynep = FirestoreFriendsApi(db, uid: 'zeynep', name: defaultFriendName);
      final ali = FirestoreFriendsApi(db, uid: 'ali', name: 'Ali');
      final code = await zeynep.myCode();
      await ali.addFriend(code);
      // The bug: the friendship keeps the generic name it was made with.
      var f = (await ali.friendships().first).single;
      expect(f.name, defaultFriendName);
      expect(f.myName, 'Ali');

      final renamed = FirestoreFriendsApi(db, uid: 'zeynep', name: 'Zeynep');
      await renamed.syncMyName();
      f = (await ali.friendships().first).single;
      expect(f.name, 'Zeynep');
      expect(f.myName, 'Ali', reason: "Ali's own entry untouched");
      expect((await db.collection('friendCodes').doc(code).get()).data()!['name'], 'Zeynep');
      // Nothing to do the second time.
      await renamed.syncMyName();
    });

    test('isDefaultFriendName', () {
      expect(isDefaultFriendName(defaultFriendName), isTrue);
      expect(isDefaultFriendName('Arkadaş'), isTrue);
      expect(isDefaultFriendName('Zeynep'), isFalse);
    });
  });

  group('friends screen', () {
    testWidgets('the card shows the friend\'s current name, not the saved one', (tester) async {
      final api = FakeFriendsApi(friends: [friend(friendDay: 0)]);
      await pump(tester, api, liveName: 'Zeynep Yeni');
      expect(find.text('Zeynep Yeni'), findsOneWidget);
      expect(find.textContaining('Zeynep Yeni: bugün henüz değil'), findsOneWidget);
      expect(find.text('Zeynep'), findsNothing);
    });

    testWidgets('without a profile the saved name is the fallback', (tester) async {
      await pump(tester, FakeFriendsApi(friends: [friend()]));
      expect(find.text('Zeynep'), findsOneWidget);
    });

    testWidgets('no code with the generic name: asks for a name first', (tester) async {
      final api = FakeFriendsApi()..myName = defaultFriendName;
      final c = await pump(tester, api);
      expect(find.byKey(const ValueKey('friend-my-code')), findsNothing);
      expect(find.byKey(const ValueKey('friend-code-needs-name')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friend-set-name')));
      await tester.pumpAndSettle();
      expect(find.text('Arkadaşların seni hangi adla görsün?'), findsOneWidget);
      // An empty or generic name is refused.
      await tester.enterText(find.byKey(const ValueKey('friend-name-field')), defaultFriendName);
      await tester.tap(find.byKey(const ValueKey('friend-name-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friend-name-dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('friend-name-field')), '  Zeynep  ');
      await tester.tap(find.byKey(const ValueKey('friend-name-save')));
      await tester.pumpAndSettle();
      expect(c.read(profileProvider).name, 'Zeynep', reason: 'saved as the Profil name');
    });

    testWidgets('adding by code with the generic name asks first; "Vazgeç" sends nothing', (tester) async {
      final api = FakeFriendsApi()..myName = defaultFriendName;
      await pump(tester, api);
      await tester.enterText(find.byKey(const ValueKey('friend-code-field')), 'ABCD2345');
      await tester.tap(find.byKey(const ValueKey('friend-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friend-name-dialog')), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(api.added, isEmpty);
    });

    testWidgets('accepting a request with the generic name asks first', (tester) async {
      final api = FakeFriendsApi()
        ..myName = defaultFriendName
        ..incoming = [const FriendRequest(from: 'zeynep', to: 'me', name: 'Zeynep', avatar: '🦊')];
      await pump(tester, api);
      await tester.tap(find.byKey(const ValueKey('request-accept-zeynep')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friend-name-dialog')), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(api.accepted, isEmpty);
    });

    testWidgets('with a name, adding goes straight through', (tester) async {
      final api = FakeFriendsApi();
      await pump(tester, api);
      await tester.enterText(find.byKey(const ValueKey('friend-code-field')), 'ABCD2345');
      await tester.tap(find.byKey(const ValueKey('friend-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friend-name-dialog')), findsNothing);
      expect(api.added, ['ABCD2345']);
    });
  });
}
