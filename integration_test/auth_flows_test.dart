// End-to-end sign-in and progress tests against the Firebase Emulator Suite.
//
//   firebase emulators:start --only auth,firestore --project demo-lingora
//   flutter test integration_test/auth_flows_test.dart -d emulator-5554
//
// See docs/giris-testleri.md. Nothing here can reach the real project.
@Timeout(Duration(minutes: 3))
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingora/screens/auth_screen.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/firebase_bootstrap.dart';
import 'package:lingora/services/firebase/firebase_config.dart';
import 'package:lingora/services/firebase/progress_sync.dart';
import 'package:lingora/theme.dart';

import 'support/emulator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final emu = Emulators();
  TestDevice? device;

  Future<TestDevice> start({Future<AuthCredential?> Function()? google, int? authPort, int? fsPort}) async {
    await device?.close();
    return device = await TestDevice.start(
      emu: emu,
      google: google,
      authPort: authPort ?? authEmulatorPort,
      firestorePort: fsPort ?? firestoreEmulatorPort,
    );
  }

  setUpAll(() async {
    if (!await emu.reachable()) {
      fail(
        'Firebase emülatörleri ${emu.host} adresinde yok. Önce: '
        'firebase emulators:start --only auth,firestore --project demo-lingora',
      );
    }
    await emu.reset();
  });

  tearDown(() async {
    await device?.close();
    device = null;
  });

  test('emulator build uses the demo project, never the real one', () async {
    expect(await initFirebase(FirebaseMode.emulator), isTrue);
    expect(lingoraFirebaseApp.name, emulatorAppName);
    expect(lingoraFirebaseApp.options.projectId, demoProjectId);
    // What the app's providers hand out.
    final auth = FirebaseAuth.instanceFor(app: lingoraFirebaseApp);
    await auth.signInAnonymously();
    expect(auth.currentUser, isNotNull, reason: 'reached the Auth emulator');
    await auth.signOut();
  });

  group('1. guest → e-mail account', () {
    test('free: uid kept, progress kept on the device', () async {
      final d = await start();
      final guestUid = await d.guest();
      d.finishLesson('u1_n1');
      d.finishLesson('u1_n2');
      await until(() => d.sync == SyncState.premiumOnly, 'premium-only state');

      await d.account.registerWithEmail('free1@example.com', 'secret123');
      await until(() => d.user?.isAnonymous == false, 'linked user');

      expect(d.user!.uid, guestUid);
      expect(d.user!.email, 'free1@example.com');
      expect(d.user!.providers, contains('password'));
      expect(d.progress.completed.keys, containsAll(['u1_n1', 'u1_n2']));
      expect(d.progress.lessonsDone, 2);
      expect(d.sync, SyncState.premiumOnly);
      expect(await emu.userDoc(guestUid), isNull, reason: 'free users have no cloud copy');
    });

    test('premium: the cloud copy stays on the same uid', () async {
      final d = await start();
      final guestUid = await d.guest();
      await emu.grantPremium(guestUid);
      await until(() => d.premium, 'premium from entitlements/{uid}');
      d.finishLesson('u1_n1');
      d.finishLesson('u1_n2');
      await untilAsync(
        () async => (await emu.cloudCompleted(guestUid)).containsAll(['u1_n1', 'u1_n2']),
        'guest progress in the cloud',
      );

      await d.account.registerWithEmail('prem1@example.com', 'secret123');
      await until(() => d.user?.isAnonymous == false, 'linked user');
      expect(d.user!.uid, guestUid);

      d.finishLesson('u1_n3');
      await untilAsync(
        () async => (await emu.cloudCompleted(guestUid)).length == 3,
        'third lesson in the cloud',
      );
      await until(() => d.sync == SyncState.synced, 'synced');
      expect(d.progress.completed.length, 3);
    });
  });

  group('2. sign in on another device (clean storage)', () {
    test('premium account: device and cloud progress merge', () async {
      // Device A: prem1@example.com has u1_n1..3 in the cloud (group 1).
      final a = await start();
      await a.guest(); // the sign-in button waits for the guest account
      await a.account.signInWithEmail('prem1@example.com', 'secret123');
      await until(() => a.user?.email == 'prem1@example.com', 'device A signed in');
      final uid = a.user!.uid;
      await until(() => a.sync == SyncState.synced, 'device A synced');
      expect(a.progress.completed.length, 3);

      // Device B: fresh install, one lesson as a guest, then signs in.
      final b = await start();
      final guestUid = await b.guest();
      b.finishLesson('u2_n1');
      await b.account.signInWithEmail('prem1@example.com', 'secret123');
      await until(() => b.user?.uid == uid, 'device B switched to the account');
      expect(uid, isNot(guestUid));
      await until(() => b.premium, 'premium of the account');
      await until(
        () => b.sync == SyncState.synced && b.progress.completed.length == 4,
        'merged progress on device B',
      );
      expect(b.progress.completed.keys, containsAll(['u1_n1', 'u1_n2', 'u1_n3', 'u2_n1']));
      await untilAsync(
        () async => (await emu.cloudCompleted(uid)).length == 4,
        'merged progress in the cloud',
      );
    });

    test('free account: no cloud copy, device progress is kept', () async {
      // free1@example.com from group 1: no entitlement.
      final b = await start();
      await b.guest();
      b.finishLesson('u3_n1');
      await b.account.signInWithEmail('free1@example.com', 'secret123');
      await until(() => b.user?.email == 'free1@example.com', 'signed in');
      await until(() => b.sync == SyncState.premiumOnly, 'premium-only');
      expect(b.premium, isFalse);
      expect(b.progress.completed.keys, contains('u3_n1'));
    });
  });

  group('3. phone', () {
    const raw = '0532 111 22 33';
    const e164 = '+905321112233';

    test('links the guest account (same uid)', () async {
      final d = await start();
      final guestUid = await d.guest();
      d.finishLesson('u1_n1');
      final id = await d.account.startPhoneSignIn(raw);
      expect(id, isNotNull);
      await d.account.confirmPhoneCode(id!, await emu.smsCode(e164));
      await until(() => d.user?.phoneNumber == e164, 'phone linked');
      expect(d.user!.uid, guestUid);
      expect(d.user!.isAnonymous, isFalse);
      expect(d.user!.providers, contains('phone'));

      // Premium for the phone account, so the next test can merge.
      await emu.grantPremium(guestUid);
      await untilAsync(() async => (await emu.cloudCompleted(guestUid)).contains('u1_n1'), 'cloud copy');
    });

    test('number already used: switches to that account and merges', () async {
      final first = await start();
      await first.account.startPhoneSignIn(raw).then((id) async {
        await first.account.confirmPhoneCode(id!, await emu.smsCode(e164));
      });
      await until(() => first.user?.phoneNumber == e164, 'phone account');
      final phoneUid = first.user!.uid;

      final d = await start();
      final guestUid = await d.guest();
      d.finishLesson('u4_n1');
      final id = await d.account.startPhoneSignIn(raw);
      await d.account.confirmPhoneCode(id!, await emu.smsCode(e164));
      await until(() => d.user?.uid == phoneUid, 'switched to the phone account');
      expect(phoneUid, isNot(guestUid));
      await until(
        () => d.sync == SyncState.synced && d.progress.completed.keys.toSet().containsAll(['u1_n1', 'u4_n1']),
        'merged',
      );
      await untilAsync(
        () async => (await emu.cloudCompleted(phoneUid)).containsAll(['u1_n1', 'u4_n1']),
        'merged in the cloud',
      );
    });
  });

  group('4. Google (fake id_token)', () {
    Future<AuthCredential?> google() async => fakeGoogleCredential('g-1001', 'ayse@example.com');

    test('links the guest account', () async {
      final d = await start(google: google);
      final guestUid = await d.guest();
      d.finishLesson('u1_n1');
      await d.account.signInWithGoogle();
      await until(() => d.user?.isAnonymous == false, 'linked');
      expect(d.user!.uid, guestUid);
      expect(d.user!.providers, contains('google.com'));
      expect(d.user!.email, 'ayse@example.com');
      await emu.grantPremium(guestUid);
      await untilAsync(() async => (await emu.cloudCompleted(guestUid)).contains('u1_n1'), 'cloud copy');
    });

    test('credential-already-in-use: switches to the Google account and merges', () async {
      final d = await start(google: google);
      final guestUid = await d.guest();
      d.finishLesson('u5_n1');
      await d.account.signInWithGoogle();
      await until(() => d.user?.email == 'ayse@example.com', 'switched');
      expect(d.user!.uid, isNot(guestUid));
      final uid = d.user!.uid;
      await until(
        () => d.sync == SyncState.synced && d.progress.completed.keys.toSet().containsAll(['u1_n1', 'u5_n1']),
        'merged',
      );
      await untilAsync(
        () async => (await emu.cloudCompleted(uid)).containsAll(['u1_n1', 'u5_n1']),
        'merged in the cloud',
      );
    });

    test('cancelled Google sheet changes nothing', () async {
      final d = await start(google: () async => null);
      final guestUid = await d.guest();
      await d.account.signInWithGoogle();
      expect(d.user!.uid, guestUid);
      expect(d.user!.isAnonymous, isTrue);
    });
  });

  group('5. sign out', () {
    test('new guest account; progress stays on the device; no Premium carried over', () async {
      final d = await start();
      await d.guest();
      await d.account.signInWithEmail('prem1@example.com', 'secret123');
      await until(() => d.user?.email == 'prem1@example.com', 'signed in');
      final uid = d.user!.uid;
      await until(() => d.premium && d.sync == SyncState.synced, 'premium account synced');
      final before = d.progress.completed.length;
      expect(before, greaterThan(0));

      await d.account.signOut();
      await until(() => d.user != null && d.user!.uid != uid, 'new guest account');
      expect(d.user!.isAnonymous, isTrue);
      expect(d.progress.completed.length, before);
      // The entitlement belongs to prem1, not to the new guest.
      await until(() => !d.premium, 'premium not carried to the guest');
      await until(() => d.sync == SyncState.premiumOnly, 'premium-only');
      // The account's cloud copy is untouched.
      expect((await emu.cloudCompleted(uid)).length, before);
    });
  });

  group('6. no connection', () {
    test('auth emulator down: nothing crashes, progress stays local', () async {
      // Port 1 is closed: every Auth/Firestore call fails like "no network".
      final d = await start(authPort: 1, fsPort: 1);
      d.finishLesson('u1_n1');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(d.user, isNull);
      expect(d.sync, SyncState.signedOut);
      expect(d.progress.completed.keys, contains('u1_n1'));
      await expectLater(
        d.account.registerWithEmail('x@example.com', 'secret123'),
        throwsA(isA<AccountException>().having((e) => e.message, 'message', contains('İnternet'))),
      );
      await expectLater(
        d.account.signInWithEmail('x@example.com', 'secret123'),
        throwsA(isA<AccountException>().having((e) => e.message, 'message', contains('İnternet'))),
      );
      await expectLater(
        d.account.sendPasswordResetEmail('x@example.com'),
        throwsA(isA<AccountException>().having((e) => e.message, 'message', contains('İnternet'))),
      );
    });

    test('Firestore offline: changes wait as pending, then upload', () async {
      final d = await start();
      final uid = await d.guest();
      await emu.grantPremium(uid);
      await until(() => d.premium, 'premium');
      d.finishLesson('u1_n1');
      await until(() => d.sync == SyncState.synced, 'synced');

      await d.db.disableNetwork();
      d.finishLesson('u1_n2');
      await until(() => d.sync == SyncState.pending, 'pending');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(d.sync, SyncState.pending, reason: 'stays pending while offline, no error');
      expect(await emu.cloudCompleted(uid), isNot(contains('u1_n2')));

      await d.db.enableNetwork();
      await untilAsync(() async => (await emu.cloudCompleted(uid)).contains('u1_n2'), 'uploaded');
      await until(() => d.sync == SyncState.synced, 'synced again');
    });
  });

  group('7. Turkish messages', () {
    Future<void> pumpAuth(WidgetTester tester, AccountService service) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness: Brightness.light),
          builder: (_, child) =>
              PaletteScope(palette: Palette.of(AppMode.adult, Brightness.light), child: child!),
          home: AuthScreen(service: service),
        ),
      );
      await tester.pump();
    }

    Future<void> waitFor(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(f, findsOneWidget);
    }

    String error(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('auth-error'))).data!;

    Future<void> fill(WidgetTester tester, String key, String text) => tester.enterText(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)),
      text,
    );

    testWidgets('wrong password', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await fill(tester, 'auth-email', 'prem1@example.com');
      await fill(tester, 'auth-password', 'yanlis-sifre');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'E-posta ya da şifre hatalı.');
    });

    testWidgets('unknown e-mail on sign-in', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await fill(tester, 'auth-email', 'kimse@example.com');
      await fill(tester, 'auth-password', 'secret123');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'E-posta ya da şifre hatalı.');
    });

    testWidgets('empty password', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await fill(tester, 'auth-email', 'prem1@example.com');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'Şifreni yaz.');
    });

    testWidgets('weak password on register', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
      await tester.pump();
      await fill(tester, 'auth-email', 'zayif@example.com');
      await fill(tester, 'auth-password', '123');
      await fill(tester, 'auth-password2', '123');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'Şifre en az 6 karakter olmalı.');
      expect(d.user!.isAnonymous, isTrue);
    });

    testWidgets('e-mail already registered', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
      await tester.pump();
      await fill(tester, 'auth-email', 'prem1@example.com');
      await fill(tester, 'auth-password', 'secret123');
      await fill(tester, 'auth-password2', 'secret123');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'Bu e-posta ile zaten bir hesap var. "Giriş yap"ı dene.');
    });

    for (final email in ['prem1@example.com', 'kimse@example.com']) {
      testWidgets('forgot password: $email gets the same answer', (tester) async {
        final d = await start();
        await d.guest();
        await pumpAuth(tester, d.account);
        await fill(tester, 'auth-email', email);
        await tester.tap(find.byKey(const ValueKey('auth-forgot')));
        await waitFor(tester, find.text('Şifre sıfırlama bağlantısı $email adresine gönderildi.'));
        expect(find.byKey(const ValueKey('auth-error')), findsNothing);
      });
    }

    testWidgets('forgot password without an address', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await tester.tap(find.byKey(const ValueKey('auth-forgot')));
      await waitFor(tester, find.byKey(const ValueKey('auth-error')));
      expect(error(tester), 'Önce e-posta adresini yaz.');
    });

    testWidgets('invalid phone numbers', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      for (final bad in ['123', '0532 12', 'abc']) {
        await tester.tap(find.byKey(const ValueKey('auth-phone')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('phone-number')), bad);
        await tester.tap(find.text('Kod gönder'));
        await waitFor(tester, find.text('Telefon numarası geçerli değil. Örnek: 0532 123 45 67'));
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('wrong SMS code', (tester) async {
      final d = await start();
      await d.guest();
      await pumpAuth(tester, d.account);
      await tester.tap(find.byKey(const ValueKey('auth-phone')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('phone-number')), '0533 444 55 66');
      await tester.tap(find.text('Kod gönder'));
      await waitFor(tester, find.byKey(const ValueKey('phone-code')));
      await tester.enterText(find.byKey(const ValueKey('phone-code')), '000000');
      await tester.tap(find.text('Onayla'));
      await waitFor(tester, find.text('Kod hatalı. SMS ile gelen 6 haneli kodu gir.'));
      expect(d.user!.isAnonymous, isTrue);
    });
  });
}
