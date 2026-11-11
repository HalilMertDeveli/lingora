import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/account_section.dart';
import 'package:lingora/screens/auth_screen.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/firebase/progress_sync.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records password-reset requests.
class _ResetAuth extends MockFirebaseAuth {
  final resets = <String>[];

  @override
  Future<void> sendPasswordResetEmail({required String email, ActionCodeSettings? actionCodeSettings}) {
    resets.add(email);
    return Future.value();
  }
}

class _FixedSync extends ProgressSync {
  _FixedSync(this.status);
  final SyncStatus status;
  @override
  SyncStatus build() => status;
}

Future<void> _pumpAuth(WidgetTester tester, AccountService service, {Brightness b = Brightness.light}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: b),
      builder: (_, child) => PaletteScope(palette: Palette.of(AppMode.adult, b), child: child!),
      home: AuthScreen(service: service),
    ),
  );
  await tester.pump();
}

void main() {
  group('AuthScreen', () {
    testWidgets('sign-in form: Turkish texts, e-mail, password, Google and phone only', (tester) async {
      await _pumpAuth(tester, AccountService(MockFirebaseAuth()));
      expect(find.text('Tekrar hoş geldin!'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-password2')), findsNothing);
      expect(find.text('Şifremi unuttum'), findsOneWidget);
      expect(find.text('ya da şununla devam et'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-google')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-phone')), findsOneWidget);
      for (final unsupported in ['X', 'GitHub', 'Apple', 'Twitter']) {
        expect(find.text(unsupported), findsNothing, reason: unsupported);
      }
      expect(find.widgetWithText(FilledButton, 'Giriş yap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('password can be shown and hidden', (tester) async {
      await _pumpAuth(tester, AccountService(MockFirebaseAuth()));
      TextField field() => tester.widget<TextField>(
        find.descendant(of: find.byKey(const ValueKey('auth-password')), matching: find.byType(TextField)),
      );
      expect(field().obscureText, isTrue);
      await tester.tap(find.byKey(const ValueKey('auth-toggle-password')));
      await tester.pump();
      expect(field().obscureText, isFalse);
      expect(find.byTooltip('Şifreyi gizle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-toggle-password')));
      await tester.pump();
      expect(field().obscureText, isTrue);
    });

    testWidgets('"Şifremi unuttum" sends a reset e-mail', (tester) async {
      final auth = _ResetAuth();
      await _pumpAuth(tester, AccountService(auth));
      await tester.tap(find.byKey(const ValueKey('auth-forgot')));
      await tester.pump();
      expect(find.text('Önce e-posta adresini yaz.'), findsOneWidget);
      expect(auth.resets, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('auth-email')), ' ali@ornek.com ');
      await tester.tap(find.byKey(const ValueKey('auth-forgot')));
      await tester.pump();
      expect(auth.resets, ['ali@ornek.com']);
      expect(find.textContaining('Şifre sıfırlama bağlantısı'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-screen')), findsOneWidget, reason: 'stays open');
    });

    testWidgets('"Hesap oluştur" asks for the password twice and checks it', (tester) async {
      await _pumpAuth(tester, AccountService(MockFirebaseAuth()));
      await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
      await tester.pump();
      expect(find.text('Hesabını oluştur'), findsOneWidget);
      expect(find.text('Şifremi unuttum'), findsNothing);
      expect(find.byKey(const ValueKey('auth-password2')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('auth-email')), 'ali@ornek.com');
      await tester.enterText(find.byKey(const ValueKey('auth-password')), 'gizli123');
      await tester.enterText(find.byKey(const ValueKey('auth-password2')), 'gizli124');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pump();
      expect(find.text('Şifreler aynı değil.'), findsOneWidget);
    });

    testWidgets('signing in closes the screen', (tester) async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', email: 'ali@ornek.com'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: AccountService(auth)))),
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('auth-email')), 'ali@ornek.com');
      await tester.enterText(find.byKey(const ValueKey('auth-password')), 'gizli123');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-screen')), findsNothing);
      expect(auth.currentUser?.email, 'ali@ornek.com');
    });

    testWidgets('dark theme renders without errors', (tester) async {
      await _pumpAuth(tester, AccountService(MockFirebaseAuth()), b: Brightness.dark);
      expect(tester.takeException(), isNull);
      final submit = tester.widget<FilledButton>(find.byKey(const ValueKey('auth-submit')));
      expect(submit.style?.backgroundColor?.resolve({}), Palette.adultDark.mascot);
    });
  });

  testWidgets('Profil "Hesap" card opens the sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          progressSyncProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncState.synced))),
          authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'u1'))),
          accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountSection())),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('account-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
