import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/account_section.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, AccountService service) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(await SharedPreferences.getInstance())],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        builder: (_, child) =>
            PaletteScope(palette: Palette.of(AppMode.adult, Brightness.light), child: child!),
        home: Scaffold(
          body: Center(child: DeleteAccountButton(service: service)),
        ),
      ),
    ),
  );
}

MockFirebaseAuth _signedIn() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'u1', email: 'a@b.co'),
);

void main() {
  test('deleteAccount calls the server once, then signs out', () async {
    final auth = _signedIn();
    var calls = 0;
    final service = AccountService(auth, deleteServerData: () async => calls++);
    await service.deleteAccount();
    expect(calls, 1);
    expect(auth.currentUser, isNull);
  });

  test('offline: Turkish message and the user stays signed in', () async {
    final auth = _signedIn();
    final service = AccountService(
      auth,
      deleteServerData: () => throw FirebaseFunctionsException(code: 'unavailable', message: 'x'),
    );
    await expectLater(
      service.deleteAccount(),
      throwsA(
        isA<AccountException>().having((e) => e.message, 'message', contains('İnternet bağlantısı yok')),
      ),
    );
    expect(auth.currentUser, isNotNull);
  });

  test('without Functions the button explains it is unavailable', () async {
    await expectLater(AccountService(_signedIn()).deleteAccount(), throwsA(isA<AccountException>()));
  });

  testWidgets('asks first; cancel deletes nothing; double tap sends one request', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    final service = AccountService(
      _signedIn(),
      deleteServerData: () {
        calls++;
        return gate.future;
      },
    );
    await _pump(tester, service);

    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Hesabın silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog closes
    expect(find.text('Siliniyor…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-delete')), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hesabın silinsin mi?'), findsNothing);
    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hesabın ve bulut verilerin silindi.'), findsOneWidget);
  });
}
