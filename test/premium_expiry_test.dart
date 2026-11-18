// QA Premium regressions: Premium that runs out while the app is open, a
// renewed subscription after the cached period, and the monthly Premium
// streak freezes counted once across phones.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/app_resume.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/wallet.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/billing/premium_perks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBackend, FakeBilling;

var _now = DateTime(2026, 11, 30, 23, 59);

Future<ProviderContainer> _container({
  FakeBilling? billing,
  EntitlementBackend? backend,
  Map<String, Object> prefs = const {},
  bool dev = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      clockProvider.overrideWithValue(() => _now),
      billingServiceProvider.overrideWithValue(billing ?? FakeBilling()),
      entitlementBackendProvider.overrideWithValue(backend),
      premiumDevOverrideProvider.overrideWithValue(dev),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => _now = DateTime(2026, 11, 30, 23, 59));

  test('Premium turns off when the period ends while the app is open (resume)', () async {
    final backend = FakeBackend(const ServerEntitlement(premium: true, status: 'active'));
    final c = await _container(backend: backend);
    final seen = <bool>[];
    c.listen(premiumProvider, (_, v) => seen.add(v), fireImmediately: true);
    backend.server.add(
      ServerEntitlement(premium: true, status: 'active', expiresAt: _now.add(const Duration(hours: 1))),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(premiumProvider), isTrue);

    // Time passes with no new server event (no renewal is ever written).
    _now = _now.add(const Duration(hours: 2));
    c.read(appResumeProvider.notifier).bump();
    expect(c.read(premiumProvider), isFalse);
    expect(seen, [false, true, false]);
  });

  test('Premium turns off by itself at expiresAt, without a resume', () async {
    final backend = FakeBackend(const ServerEntitlement(premium: true, status: 'active'));
    final c = await _container(backend: backend);
    c.listen(premiumProvider, (_, _) {});
    backend.server.add(
      ServerEntitlement(
        premium: true,
        status: 'active',
        expiresAt: _now.add(const Duration(milliseconds: 100)),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(premiumProvider), isTrue);
    _now = _now.add(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(c.read(premiumProvider), isFalse);
  });

  test('a renewed plan is restored quietly after the cached period ran out', () async {
    final billing = FakeBilling()..owned.add('lingora_premium_monthly');
    final c = await _container(
      billing: billing,
      prefs: {
        'premium.cache': jsonEncode({
          'productId': 'lingora_premium_monthly',
          'until': _now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          'source': 'store',
        }),
      },
    );
    c.listen(premiumProvider, (_, _) {});
    expect(c.read(premiumProvider), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(premiumProvider), isTrue, reason: 'the store re-delivered the renewed subscription');
  });

  test('monthly Premium freezes are counted once across two phones', () {
    // Phone A and phone B each granted November before syncing.
    var a = const Wallet();
    var b = const Wallet();
    Wallet grant(Wallet w) => w.copyWith(
      once: {...w.once, premiumFreezeKey(_now): '2026-11-30'},
      freezeBought: {
        ...w.freezeBought,
        premiumFreezeSource: (w.freezeBought[premiumFreezeSource] ?? 0) + premiumFreezesPerMonth,
      },
    );
    a = grant(a);
    b = grant(b);
    expect(mergeWallets(a, b).freezes, premiumFreezesPerMonth);
  });

  test('a new month while the app sleeps adds its freezes on resume', () async {
    final dev = await _container(dev: true);
    dev.listen(premiumPerksSyncProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final nov = dev.read(progressProvider).wallet.freezes;
    expect(nov, premiumFreezesPerMonth);

    dev
        .read(progressProvider.notifier)
        .updateWallet((w, device) => w.copyWith(freezeUsed: {...w.freezeUsed, device: nov}));
    _now = DateTime(2026, 12, 1, 9);
    dev.read(appResumeProvider.notifier).bump();
    await Future<void>.delayed(Duration.zero);
    expect(dev.read(progressProvider).wallet.once.containsKey('pfz:2026-12'), isTrue);
    expect(dev.read(progressProvider).wallet.freezes, premiumFreezesPerMonth);
  });
}
