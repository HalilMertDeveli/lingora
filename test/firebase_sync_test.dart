import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/account_section.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/firebase_config.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/firebase/progress_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

NoteWord word(String id, String en) => NoteWord(id: id, en: en, tr: en, topic: 't');

class _Toggle extends Notifier<bool> {
  _Toggle([this.initial = false]);
  final bool initial;
  @override
  bool build() => initial;
  void set(bool v) => state = v;
}

final _premium = NotifierProvider<_Toggle, bool>(_Toggle.new);

class _FixedSync extends ProgressSync {
  _FixedSync(this.fixed);
  final SyncStatus fixed;
  @override
  SyncStatus build() => fixed;
}

void main() {
  group('mergeProgress', () {
    test('never loses XP, completed nodes or counters', () {
      const local = Progress(
        totalXp: 120,
        xpByDay: {'2026-11-09': 50, '2026-11-10': 70},
        completed: {'a': 1, 'b': 3},
        lessonsDone: 4,
        examBest: {'yds': 60},
        errorStats: {'article': 2},
        claimed: ['2026-11-10:q1'],
      );
      const remote = Progress(
        totalXp: 300,
        xpByDay: {'2026-11-08': 200, '2026-11-10': 40},
        completed: {'b': 1, 'c': 2},
        lessonsDone: 9,
        examBest: {'yds': 80, 'toefl': 50},
        errorStats: {'article': 1, 'tense': 4},
        claimed: ['2026-11-09:q2'],
      );
      final m = mergeProgress(local, remote, localNewer: true);
      expect(m.totalXp, 300);
      expect(m.xpByDay, {'2026-11-08': 200, '2026-11-09': 50, '2026-11-10': 70});
      expect(m.completed, {'a': 1, 'b': 3, 'c': 2});
      expect(m.lessonsDone, 9);
      expect(m.examBest, {'yds': 80, 'toefl': 50});
      expect(m.errorStats, {'article': 2, 'tense': 4});
      expect(m.claimed.toSet(), {'2026-11-10:q1', '2026-11-09:q2'});
    });

    test('streak comes from the most recently active copy', () {
      const a = Progress(streak: 3, lastActiveDay: '2026-11-10');
      const b = Progress(streak: 40, lastActiveDay: '2026-11-01');
      expect(mergeProgress(a, b, localNewer: false).streak, 3);
      expect(mergeProgress(b, a, localNewer: true).streak, 3);
      const c = Progress(streak: 5, lastActiveDay: '2026-11-10');
      expect(mergeProgress(a, c, localNewer: true).streak, 5);
    });

    test('settings come from the newer copy, onboarded is kept', () {
      const local = Progress(onboarded: true, dailyGoal: 10, trackId: 'yds', reminderMinutes: 600);
      const remote = Progress(
        dailyGoal: 50,
        trackId: 'general',
        reminderMinutes: 1200,
        remindersEnabled: true,
      );
      final localWins = mergeProgress(local, remote, localNewer: true);
      expect(localWins.dailyGoal, 10);
      expect(localWins.trackId, 'yds');
      expect(localWins.remindersEnabled, true); // never answered on this device
      final remoteWins = mergeProgress(local, remote, localNewer: false);
      expect(remoteWins.dailyGoal, 50);
      expect(remoteWins.reminderMinutes, 1200);
      expect(remoteWins.onboarded, true);
    });

    test('diary, own words and word reviews are united', () {
      final local = Progress(
        diary: const {'2026-11-09': 'local'},
        customWords: [word('w1', 'apple')],
        wordBox: const {'w1': 2, 'x': 1},
        wordDue: const {'w1': '2026-11-20', 'x': '2026-11-11'},
      );
      final remote = Progress(
        diary: const {'2026-11-09': 'remote', '2026-11-10': 'today'},
        customWords: [word('w9', 'Apple'), word('w2', 'pear')],
        wordBox: const {'x': 3},
        wordDue: const {'x': '2026-11-15'},
      );
      final m = mergeProgress(local, remote, localNewer: true);
      expect(m.diary, {'2026-11-09': 'local', '2026-11-10': 'today'});
      expect(m.customWords.map((w) => w.id).toList(), ['w1', 'w2']);
      expect(m.wordBox, {'w1': 2, 'x': 3});
      expect(m.wordDue, {'w1': '2026-11-20', 'x': '2026-11-15'});
    });

    test('league state follows the later week', () {
      const a = Progress(leagueTier: 3, leagueWeek: '2026-11-09');
      const b = Progress(leagueTier: 1, leagueWeek: '2026-11-02');
      expect(mergeProgress(b, a, localNewer: true).leagueTier, 3);
    });

    test('canonical form ignores map order', () {
      const a = Progress(completed: {'a': 1, 'b': 2});
      const b = Progress(completed: {'b': 2, 'a': 1});
      expect(canonicalProgress(a), canonicalProgress(b));
    });
  });

  test('display name fits the 40-character rule', () {
    expect(shortDisplayName(null), isNull);
    expect(shortDisplayName('  '), isNull);
    expect(shortDisplayName(' Ayşe '), 'Ayşe');
    expect(shortDisplayName('x' * 50)!.length, 40);
  });

  test('FirebaseMode parsing defaults to off', () {
    expect(FirebaseMode.parse(null), FirebaseMode.off);
    expect(FirebaseMode.parse(''), FirebaseMode.off);
    expect(FirebaseMode.parse('emulator'), FirebaseMode.emulator);
    expect(FirebaseMode.parse('PROD'), FirebaseMode.prod);
    expect(FirebaseMode.fromEnvironment, FirebaseMode.prod);
    expect(emulatorHost(platform: TargetPlatform.android), '10.0.2.2');
    expect(emulatorHost(platform: TargetPlatform.iOS), 'localhost');
  });

  test('with Firebase off nothing is touched and sync is off', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(await SharedPreferences.getInstance())],
    );
    addTearDown(c.dispose);
    c.listen(progressSyncProvider, (_, _) {});
    await settle();
    expect(c.read(firebaseReadyProvider), false);
    expect(c.read(firebaseAuthProvider), isNull);
    expect(c.read(firestoreProvider), isNull);
    expect(c.read(functionsProvider), isNull);
    expect(c.read(currentUidProvider), isNull);
    expect(c.read(accountServiceProvider), isNull);
    expect(c.read(progressSyncProvider).state, SyncState.off);
    c.read(progressProvider.notifier).completeNode('n1', xp: 10, answered: 1, correct: 1);
    expect(c.read(progressProvider).totalXp, 10);
  });

  group('ProgressSync', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    Future<ProviderContainer> start(Progress local, {bool premium = true}) async {
      SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(local.toJson())});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 10, 12)),
          firebaseReadyProvider.overrideWithValue(true),
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(auth),
          syncDebounceProvider.overrideWithValue(Duration.zero),
          _premium.overrideWith(() => _Toggle(premium)),
          premiumProvider.overrideWith((ref) => ref.watch(_premium)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(progressSyncProvider, (_, _) {});
      await settle();
      return c;
    }

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', isAnonymous: true));
    });

    test('first sign-in uploads the local progress', () async {
      final c = await start(const Progress(onboarded: true, totalXp: 42, completed: {'a': 1}));
      expect(c.read(currentUidProvider), 'u1');
      final doc = (await db.doc('users/u1').get()).data()!;
      expect(doc['schemaVersion'], userDocSchema);
      expect(doc['totalXp'], 42);
      expect((doc['progress'] as Map)['completed'], {'a': 1});
      expect(c.read(progressSyncProvider).state, SyncState.synced);
    });

    test('pull on sign-in merges the cloud copy without losing anything', () async {
      await db.doc('users/u1').set({
        'schemaVersion': 1,
        'clientUpdatedAt': DateTime(2026, 11, 9).millisecondsSinceEpoch,
        'totalXp': 500,
        'progress': const Progress(
          onboarded: true,
          totalXp: 500,
          completed: {'b': 2},
          dailyGoal: 50,
          streak: 12,
          lastActiveDay: '2026-11-09',
        ).toJson(),
      });
      final c = await start(const Progress(totalXp: 100, completed: {'a': 1}));
      final p = c.read(progressProvider);
      expect(p.onboarded, true);
      expect(p.totalXp, 500);
      expect(p.completed, {'a': 1, 'b': 2});
      expect(p.streak, 12);
      expect(p.dailyGoal, 50); // this device never changed it → cloud setting
      final doc = (await db.doc('users/u1').get()).data()!;
      expect((doc['progress'] as Map)['completed'], {'a': 1, 'b': 2});
      expect(c.read(progressSyncProvider).state, SyncState.synced);
    });

    test('local saves are written to the cloud', () async {
      final c = await start(const Progress(onboarded: true));
      c.read(progressProvider.notifier).completeNode('n1', xp: 15, answered: 2, correct: 2);
      expect(c.read(progressSyncProvider).state, SyncState.pending);
      await settle();
      final doc = (await db.doc('users/u1').get()).data()!;
      expect(doc['totalXp'], 15);
      expect((doc['progress'] as Map)['completed'], {'n1': 1});
      expect(doc['clientUpdatedAt'], DateTime(2026, 11, 10, 12).millisecondsSinceEpoch);
      expect(c.read(progressSyncProvider).state, SyncState.synced);
    });

    test('changes from another device are merged in', () async {
      final c = await start(const Progress(onboarded: true, totalXp: 10, completed: {'a': 1}));
      await db.doc('users/u1').set({
        'clientUpdatedAt': DateTime(2026, 11, 10, 13).millisecondsSinceEpoch,
        'progress': const Progress(onboarded: true, totalXp: 80, completed: {'z': 1}).toJson(),
      });
      await settle();
      expect(c.read(progressProvider).totalXp, 80);
      expect(c.read(progressProvider).completed, {'a': 1, 'z': 1});
      final doc = (await db.doc('users/u1').get()).data()!;
      expect((doc['progress'] as Map)['completed'], {'a': 1, 'z': 1});
    });
  });

  group('Premium gating', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    final remoteProgress = const Progress(
      onboarded: true,
      totalXp: 300,
      completed: {'cloud': 1},
      dailyGoal: 50,
    ).toJson();

    Future<ProviderContainer> start(Progress local, {required bool premium}) async {
      SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(local.toJson())});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 10, 12)),
          firebaseReadyProvider.overrideWithValue(true),
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(auth),
          syncDebounceProvider.overrideWithValue(Duration.zero),
          _premium.overrideWith(() => _Toggle(premium)),
          premiumProvider.overrideWith((ref) => ref.watch(_premium)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(progressSyncProvider, (_, _) {});
      await settle();
      return c;
    }

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1', isAnonymous: true));
    });

    test('free user: signed in, but nothing is read or written', () async {
      await db.doc('users/u1').set({'clientUpdatedAt': 1, 'progress': remoteProgress});
      final c = await start(const Progress(onboarded: true, totalXp: 5), premium: false);
      expect(c.read(currentUidProvider), 'u1'); // sign-in stays free (leagues)
      expect(c.read(progressSyncProvider).state, SyncState.premiumOnly);
      expect(c.read(progressProvider).totalXp, 5); // cloud copy not pulled
      c.read(progressProvider.notifier).completeNode('n1', xp: 10, answered: 1, correct: 1);
      await settle();
      expect(c.read(progressSyncProvider).state, SyncState.premiumOnly);
      final doc = (await db.doc('users/u1').get()).data()!;
      expect(doc['progress'], remoteProgress); // untouched
      expect(c.read(progressProvider).completed, {'n1': 1}); // kept on device
    });

    test('becoming Premium syncs at once: pull + merge, then push', () async {
      await db.doc('users/u1').set({'clientUpdatedAt': 1, 'progress': remoteProgress});
      final c = await start(
        const Progress(onboarded: true, totalXp: 20, completed: {'local': 2}),
        premium: false,
      );
      // A setting changed while free still counts as the newest edit.
      c.read(progressProvider.notifier).setDailyGoal(10);
      await settle();
      c.read(_premium.notifier).set(true);
      await settle();
      final p = c.read(progressProvider);
      expect(p.totalXp, 300);
      expect(p.completed, {'local': 2, 'cloud': 1});
      expect(p.dailyGoal, 10);
      final doc = (await db.doc('users/u1').get()).data()!;
      expect((doc['progress'] as Map)['completed'], {'local': 2, 'cloud': 1});
      expect(doc['totalXp'], 300);
      expect(c.read(progressSyncProvider).state, SyncState.synced);
    });

    test('Premium lapsing stops syncing and keeps local data', () async {
      final c = await start(const Progress(onboarded: true, totalXp: 7), premium: true);
      expect(c.read(progressSyncProvider).state, SyncState.synced);
      c.read(_premium.notifier).set(false);
      await settle();
      expect(c.read(progressSyncProvider).state, SyncState.premiumOnly);
      c.read(progressProvider.notifier).completeNode('after', xp: 30, answered: 1, correct: 1);
      await settle();
      expect(c.read(progressProvider).totalXp, 37);
      final doc = (await db.doc('users/u1').get()).data()!;
      expect(doc['totalXp'], 7);
      expect((doc['progress'] as Map)['completed'], isEmpty);
      // Changes made by another device while lapsed are not pulled either.
      await db.doc('users/u1').set({'clientUpdatedAt': 1, 'progress': remoteProgress});
      await settle();
      expect(c.read(progressProvider).completed, {'after': 1});
      // Renewing brings both together.
      c.read(_premium.notifier).set(true);
      await settle();
      expect(c.read(progressProvider).completed, {'after': 1, 'cloud': 1});
      expect(((await db.doc('users/u1').get()).data()!['progress'] as Map)['completed'], {
        'after': 1,
        'cloud': 1,
      });
    });
  });

  group('AccountService', () {
    test('e-mail upgrade links the anonymous user (same uid)', () async {
      final auth = _FakeAuth(_FakeUser());
      await AccountService(auth).registerWithEmail(' a@b.co ', 'secret1');
      expect(auth.calls, ['link:password']);
    });

    test('a signed-in user with a real account creates a new one', () async {
      final auth = _FakeAuth(_FakeUser(anonymous: false));
      await AccountService(auth).registerWithEmail('a@b.co', 'secret1');
      expect(auth.calls, ['create:a@b.co']);
    });

    test('Google credential of an existing account signs into it', () async {
      final auth = _FakeAuth(_FakeUser(linkError: 'credential-already-in-use'));
      final service = AccountService(
        auth,
        googleCredential: () async => GoogleAuthProvider.credential(idToken: 'x'),
      );
      await service.signInWithGoogle();
      expect(auth.calls, ['link:google.com', 'signIn:google.com']);
    });

    test('cancelled Google sign-in does nothing', () async {
      final auth = _FakeAuth(_FakeUser());
      await AccountService(auth, googleCredential: () async => null).signInWithGoogle();
      expect(auth.calls, isEmpty);
    });

    test('errors are shown in Turkish', () async {
      final auth = _FakeAuth(_FakeUser(linkError: 'weak-password'));
      await expectLater(
        AccountService(auth).registerWithEmail('a@b.co', '1'),
        throwsA(isA<AccountException>().having((e) => e.message, 'message', contains('6 karakter'))),
      );
    });
  });

  group('AccountSection', () {
    Future<void> pump(WidgetTester tester, List<Override> overrides) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsProvider.overrideWithValue(prefs), ...overrides],
          child: const MaterialApp(home: Scaffold(body: AccountSection())),
        ),
      );
      await tester.pump();
    }

    testWidgets('Firebase off: says progress is on this device', (tester) async {
      await pump(tester, []);
      expect(find.text('Bu cihazda saklanıyor'), findsOneWidget);
      expect(find.text('Çıkış yap'), findsNothing);
    });

    testWidgets('synced: shows the backup indicator and upgrade buttons', (tester) async {
      await pump(tester, [
        progressSyncProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncState.synced))),
        authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'u1'))),
        accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
      ]);
      expect(find.text('İlerlemem buluta yedeklendi'), findsOneWidget);
      expect(find.text('Misafir hesabı'), findsOneWidget);
      expect(find.text('Google ile bağla'), findsOneWidget);
    });

    testWidgets('free user: backup is Premium-only with a paywall button', (tester) async {
      await pump(tester, [
        progressSyncProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncState.premiumOnly))),
        authStateProvider.overrideWithValue(
          const AsyncData(AppUser(uid: 'u1', isAnonymous: false, email: 'a@b.co')),
        ),
        accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
      ]);
      expect(find.text("Buluta yedekleme Premium'a özel"), findsOneWidget);
      expect(find.text('İlerlemem buluta yedeklendi'), findsNothing);
      expect(find.byKey(const ValueKey('account-premium-backup')), findsOneWidget);
      expect(find.text('Çıkış yap'), findsOneWidget); // sign-in stays free
    });

    testWidgets('signed in: shows e-mail and sign-out', (tester) async {
      await pump(tester, [
        progressSyncProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncState.pending))),
        authStateProvider.overrideWithValue(
          const AsyncData(AppUser(uid: 'u1', isAnonymous: false, email: 'a@b.co')),
        ),
        accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
      ]);
      expect(find.text('a@b.co'), findsOneWidget);
      expect(find.text('İnternet gelince buluta yedeklenecek'), findsOneWidget);
      expect(find.text('Çıkış yap'), findsOneWidget);
    });
  });
}

class _FakeUser implements User {
  _FakeUser({this.anonymous = true, this.linkError});
  final bool anonymous;
  final String? linkError;
  late _FakeAuth auth;

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    auth.calls.add('link:${credential.providerId}');
    if (linkError != null) throw FirebaseAuthException(code: linkError!);
    return _FakeCredential();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  _FakeAuth(this.user) {
    user.auth = this;
  }
  final _FakeUser user;
  final calls = <String>[];

  @override
  User? get currentUser => user;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    calls.add('signIn:${credential.providerId}');
    return _FakeCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    calls.add('create:$email');
    return _FakeCredential();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
