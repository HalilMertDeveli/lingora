// Audit item 2: Mülakat Provası answers and recordings belong to one account.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/rehearsal.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

RehearsalSession session(String id) => RehearsalSession(
  id: id,
  kind: RehearsalKind.interview,
  at: DateTime(2026, 11, 19),
  answers: [RehearsalAnswer(questionId: 'q', question: 'Q?', answer: 'A', audioPath: '/prova/$id.m4a')],
);

const ayse = AppUser(uid: 'ayse', isAnonymous: false, providers: ['google.com']);
const mehmet = AppUser(uid: 'mehmet', isAnonymous: false, providers: ['password']);
const guest = AppUser(uid: 'g1');
const guest2 = AppUser(uid: 'g2');

void main() {
  late StreamController<AppUser?> users;
  late List<String> wiped;

  Future<ProviderContainer> start(Map<String, Object> prefsValues, AppUser? first) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    users = StreamController<AppUser?>.broadcast();
    wiped = [];
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        authStateProvider.overrideWith((ref) async* {
          yield first;
          yield* users.stream;
        }),
        recordingWiperProvider.overrideWithValue((paths) async => wiped.addAll(paths)),
      ],
    );
    addTearDown(() {
      c.dispose();
      users.close();
    });
    c.listen(rehearsalProvider, (_, _) {});
    await pumpEventQueue();
    return c;
  }

  Future<void> signIn(AppUser? u) async {
    users.add(u);
    await pumpEventQueue();
  }

  test("another account on the same phone does not see the first one's rehearsals; they are deleted", () async {
    final c = await start({}, ayse);
    c.read(rehearsalProvider.notifier).putSession(session('s1'));
    expect(c.read(rehearsalProvider).sessions, hasLength(1));
    await signIn(mehmet);
    expect(c.read(rehearsalProvider).sessions, isEmpty);
    expect(wiped, ['/prova/s1.m4a']);
    // Ayşe signing in again does not get them back from this phone.
    await signIn(ayse);
    expect(c.read(rehearsalProvider).sessions, isEmpty);
  });

  test('signing out (a new guest) clears them too', () async {
    final c = await start({}, ayse);
    c.read(rehearsalProvider.notifier).putSession(session('s1'));
    await signIn(null); // between accounts: hidden, not deleted
    expect(c.read(rehearsalProvider).sessions, isEmpty);
    expect(wiped, isEmpty);
    await signIn(guest2);
    expect(c.read(rehearsalProvider).sessions, isEmpty);
    expect(wiped, ['/prova/s1.m4a']);
  });

  test("a guest's rehearsals move to the account the guest signs in to", () async {
    final c = await start({}, guest);
    c.read(rehearsalProvider.notifier).putSession(session('g'));
    await signIn(ayse);
    expect(c.read(rehearsalProvider).sessions.single.id, 'g');
    expect(wiped, isEmpty);
  });

  test('rehearsals saved before owners existed go to the first account seen', () async {
    final c = await start({
      'rehearsal_v1': '{"s":[${_json(session('old'))}],"t":[]}',
    }, ayse);
    expect(c.read(rehearsalProvider).sessions.single.id, 'old');
    await signIn(mehmet);
    expect(c.read(rehearsalProvider).sessions, isEmpty);
    expect(wiped, ['/prova/old.m4a']);
  });

  test('account deletion deletes answers and recordings', () async {
    final c = await start({}, ayse);
    c.read(rehearsalProvider.notifier).putSession(session('s1'));
    c.read(rehearsalProvider.notifier).clearLocal();
    await pumpEventQueue();
    expect(c.read(rehearsalProvider).sessions, isEmpty);
    expect(wiped, ['/prova/s1.m4a']);
    expect(c.read(prefsProvider).getString('rehearsal_v1'), isNull);
  });

  test('without Firebase (no accounts) rehearsals stay as before', () async {
    final c = await start({}, null);
    c.read(rehearsalProvider.notifier).putSession(session('s1'));
    expect(c.read(rehearsalProvider).sessions, hasLength(1));
  });
}

String _json(RehearsalSession s) => jsonEncode(s.toJson());
