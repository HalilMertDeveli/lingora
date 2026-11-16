import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/friends_screen.dart';
import 'package:lingora/screens/league_screen.dart';
import 'package:lingora/screens/profile_header.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/friends.dart';
import 'package:lingora/services/profile.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_test.dart' show FakeFriendsApi, friend;

final now = DateTime.utc(2026, 11, 16, 9);

/// A [w]×[h] PNG with a colour gradient (or noise, which compresses badly).
Uint8List png(int w, int h, {bool noise = false}) {
  final r = Random(7);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = noise ? r.nextInt(256) : p.x * 255 ~/ w
      ..g = noise ? r.nextInt(256) : p.y * 255 ~/ h
      ..b = noise ? r.nextInt(256) : 120;
  }
  return img.encodePng(im);
}

final photoA = processAvatar(png(300, 200));

class FakeProfileApi implements ProfileApi {
  FakeProfileApi({Map<String, ProfileData>? docs}) : docs = docs ?? {};
  final Map<String, ProfileData> docs;
  final saved = <(String, ProfileData)>[];

  @override
  Future<ProfileData?> fetch(String uid) async => docs[uid];

  @override
  Future<void> save(String uid, ProfileData profile) async {
    saved.add((uid, profile));
    docs[uid] = profile;
  }

  @override
  Stream<ProfileData?> watch(String uid) => Stream.value(docs[uid]);
}

Future<List<Override>> overrides({
  Map<String, Object> prefs = const {},
  AppUser? user,
  ProfileApi? api,
  FriendsApi? friends,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  return [
    prefsProvider.overrideWithValue(p),
    clockProvider.overrideWithValue(() => now),
    authStateProvider.overrideWithValue(AsyncData(user)),
    profileApiProvider.overrideWithValue(api),
    if (friends != null) friendsApiProvider.overrideWithValue(friends),
    avatarProcessorProvider.overrideWithValue((b) async => processAvatar(b)),
  ];
}

const ali = AppUser(uid: 'ali', isAnonymous: false, displayName: 'Ali Veli');
const guest = AppUser(uid: 'g1');

Future<ProviderContainer> container(List<Override> o) async {
  final c = ProviderContainer(overrides: o);
  addTearDown(c.dispose);
  c.read(profileProvider);
  // Let the sign-in sync finish.
  await pumpEventQueue();
  return c;
}

void main() {
  group('processAvatar', () {
    test('crops to a 256 px square JPEG', () {
      final out = processAvatar(png(600, 400));
      expect(looksLikeJpeg(out), isTrue);
      final back = img.decodeJpg(out)!;
      expect((back.width, back.height), (avatarSize, avatarSize));
      expect(out.length, lessThanOrEqualTo(maxAvatarBytes));
    });

    test('a photo that compresses badly still fits the rules', () {
      final out = processAvatar(png(1024, 1024, noise: true));
      expect(out.length, lessThanOrEqualTo(maxAvatarBytes));
      expect(looksLikeJpeg(out), isTrue);
    });

    test('small images are scaled up to the avatar size', () {
      final back = img.decodeJpg(processAvatar(png(40, 90)))!;
      expect(back.width, avatarSize);
    });

    test('refuses bytes that are not an image', () {
      expect(
        () => processAvatar(Uint8List.fromList(utf8.encode('merhaba'))),
        throwsA(isA<AvatarException>()),
      );
    });
  });

  group('cleanDisplayName', () {
    test('trims, collapses spaces and keeps 24 units', () {
      expect(cleanDisplayName('  Ayşe   Nur  '), 'Ayşe Nur');
      expect(cleanDisplayName('   '), isNull);
      expect(cleanDisplayName(null), isNull);
      expect(cleanDisplayName('a' * 30), 'a' * 24);
      // An emoji is two UTF-16 units and is never cut in half.
      final s = cleanDisplayName('${'b' * 23}😀')!;
      expect(s, 'b' * 23);
    });
  });

  group('ProfileNotifier', () {
    test('a guest keeps the photo on the device only', () async {
      final api = FakeProfileApi();
      final c = await container(await overrides(user: guest, api: api));
      await c.read(profileProvider.notifier).setPhoto(photoA);
      await c.read(profileProvider.notifier).setName('  Deniz ');
      expect(api.saved, isEmpty);
      expect(c.read(profileProvider).name, 'Deniz');
      // Survives a restart.
      final stored = c.read(prefsProvider).getString(ProfileNotifier.key)!;
      final again = ProfileData.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      expect(again.photo, photoA);
      expect(again.name, 'Deniz');
      expect(again.owner, isNull);
    });

    test('an account uploads every change', () async {
      final api = FakeProfileApi();
      final c = await container(await overrides(user: ali, api: api));
      await c.read(profileProvider.notifier).setPhoto(photoA);
      expect(api.docs['ali']!.photo, photoA);
      expect(api.docs['ali']!.updatedAt, now.millisecondsSinceEpoch);
      await c.read(profileProvider.notifier).removePhoto();
      expect(api.docs['ali']!.photo, isNull);
      await c.read(profileProvider.notifier).setName('');
      expect(api.docs['ali']!.name, isNull);
      expect(c.read(myDisplayNameProvider), 'Ali');
    });

    test('signing in on a new phone brings the profile back', () async {
      final api = FakeProfileApi(
        docs: {'ali': ProfileData(name: 'Alişko', photo: photoA, updatedAt: 5)},
      );
      final c = await container(await overrides(user: ali, api: api));
      expect(c.read(profileProvider).name, 'Alişko');
      expect(c.read(profileProvider).photo, photoA);
      expect(c.read(myDisplayNameProvider), 'Alişko');
      expect(api.saved, isEmpty);
    });

    test('a guest photo goes up when the guest signs in', () async {
      final local = ProfileData(photo: photoA, updatedAt: 10);
      final api = FakeProfileApi(docs: {'ali': const ProfileData(name: 'Eski', updatedAt: 3)});
      final c = await container(
        await overrides(prefs: {ProfileNotifier.key: jsonEncode(local.toJson())}, user: ali, api: api),
      );
      expect(api.saved.single.$1, 'ali');
      expect(api.docs['ali']!.photo, photoA);
      expect(c.read(profileProvider).owner, 'ali');
    });

    test('another account\'s copy on this phone is not uploaded', () async {
      final local = ProfileData(name: 'Zeynep', photo: photoA, updatedAt: 99, owner: 'zeynep');
      final api = FakeProfileApi();
      final c = await container(
        await overrides(prefs: {ProfileNotifier.key: jsonEncode(local.toJson())}, user: ali, api: api),
      );
      expect(api.saved, isEmpty);
      expect(c.read(profileProvider).isEmpty, isTrue);
      expect(c.read(profileProvider).owner, 'ali');
    });
  });

  group('ProfileHeader', () {
    Future<void> pump(WidgetTester tester, List<Override> o, {Uint8List? picked}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...o, avatarPickerProvider.overrideWithValue((ImageSource s) async => picked)],
          child: const MaterialApp(home: Scaffold(body: ProfileHeader())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('picks, shows and removes a photo', (tester) async {
      final raw = png(500, 300);
      await pump(tester, await overrides(user: guest), picked: raw);
      expect(find.text('Öğrenci'), findsOneWidget);
      expect(find.byKey(const ValueKey('avatar-photo')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('profile-avatar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('yalnızca bu cihazda'), findsOneWidget);
      expect(find.byKey(const ValueKey('avatar-remove')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('avatar-gallery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('avatar-photo')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('avatar-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('avatar-photo')), findsNothing);
    });

    testWidgets('an unreadable file shows a message', (tester) async {
      await pump(tester, await overrides(user: guest), picked: Uint8List.fromList([1, 2, 3]));
      await tester.tap(find.byKey(const ValueKey('profile-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('avatar-camera')));
      await tester.pumpAndSettle();
      expect(find.textContaining('açılamadı'), findsOneWidget);
    });

    testWidgets('edits the display name', (tester) async {
      await pump(tester, await overrides(user: ali));
      // The account's first name until one is chosen.
      expect(find.text('Ali'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-edit-name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('profile-name-field')), '  Kaptan   Ali ');
      await tester.tap(find.byKey(const ValueKey('profile-name-save')));
      await tester.pumpAndSettle();
      expect(find.text('Kaptan Ali'), findsOneWidget);
    });

    testWidgets('kid mode keeps Pofuduk and has no photo upload', (tester) async {
      Brand.apply(Palette.of(AppMode.kid, Brightness.light));
      addTearDown(() => Brand.apply(Palette.adultLight));
      await pump(
        tester,
        await overrides(
          user: guest,
          prefs: {ProfileNotifier.key: jsonEncode(ProfileData(photo: photoA).toJson())},
        ),
      );
      expect(find.byKey(const Key('kid-avatar')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-avatar')), findsNothing);
      expect(find.byKey(const ValueKey('avatar-photo')), findsNothing);
    });
  });

  testWidgets('friends see each other\'s photo and chosen name', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeProfileApi(
      docs: {'zeynep': ProfileData(name: 'Zeyno', photo: photoA, owner: 'zeynep')},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(
          user: const AppUser(uid: 'me', isAnonymous: false),
          api: api,
          friends: FakeFriendsApi(friends: [friend()]),
        ),
        child: const MaterialApp(home: FriendsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('friend-zeynep'));
    expect(find.descendant(of: card, matching: find.text('Zeyno')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('avatar-photo'))), findsOneWidget);
  });

  testWidgets('a friend without a profile keeps the animal avatar', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(
          user: const AppUser(uid: 'me', isAnonymous: false),
          api: FakeProfileApi(),
          friends: FakeFriendsApi(friends: [friend()]),
        ),
        child: const MaterialApp(home: FriendsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('friend-zeynep'));
    expect(find.descendant(of: card, matching: find.text('Zeynep')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('🦊')), findsOneWidget);
  });

  testWidgets('the league shows the user\'s photo and name', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(
          user: guest,
          prefs: {ProfileNotifier.key: jsonEncode(ProfileData(name: 'Deniz', photo: photoA).toJson())},
        ),
        child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('league-my-avatar')),
      200,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('league-my-avatar')),
        matching: find.byKey(const ValueKey('avatar-photo')),
      ),
      findsOneWidget,
    );
    expect(find.text('Deniz (Sen)'), findsOneWidget);
  });

  test('friend profiles are not read without an account', () async {
    final c = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(const AsyncData(guest)),
        profileApiProvider.overrideWithValue(FakeProfileApi(docs: {'z': const ProfileData(name: 'Z')})),
      ],
    );
    addTearDown(c.dispose);
    final done = Completer<ProfileData?>();
    c.listen(friendProfileProvider('z'), (_, v) {
      if (v.hasValue && !done.isCompleted) done.complete(v.value);
    }, fireImmediately: true);
    expect(await done.future, isNull);
  });
}
