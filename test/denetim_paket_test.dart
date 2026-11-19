// Audit item 3 (client): a refunded exam pack closes, even the last one.
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/exam_packs.dart';
import 'package:lingora/services/billing/products.dart';

import 'exam_packs_test.dart' show PackBackend, PackBilling, container, settle;

void main() {
  ServerEntitlement doc(Map<String, Object?> packs) =>
      ServerEntitlement.fromDoc({'premium': false, 'status': 'expired', 'packs': packs});

  test('refunding the only pack (server: {yds: false}) locks it', () async {
    final backend = PackBackend();
    final c = await container(PackBilling(), backend: backend);
    await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
    await settle();
    expect(c.read(examPackUnlockedProvider('yds')), isTrue);

    backend.server.add(doc({'yds': false}));
    await settle();
    expect(c.read(examPackUnlockedProvider('yds')), isFalse);
    expect(c.read(examPackControllerProvider).owned, isEmpty);
  });

  test('an explicit empty pack map is authoritative too', () async {
    final backend = PackBackend();
    final c = await container(PackBilling(), backend: backend);
    await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
    await settle();
    backend.server.add(doc({}));
    await settle();
    expect(c.read(examPackUnlockedProvider('yds')), isFalse);
  });

  test('a document without a pack list (Premium only) changes nothing', () async {
    final backend = PackBackend();
    final c = await container(PackBilling(), backend: backend);
    await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
    await settle();
    backend.server.add(ServerEntitlement.fromDoc({'premium': true, 'status': 'active'}));
    await settle();
    expect(c.read(examPackUnlockedProvider('yds')), isTrue);
  });

  test("a store-only grant (server offline) waits for the server's word", () async {
    final backend = PackBackend()..error = StateError('offline');
    final c = await container(PackBilling(), backend: backend);
    await c.read(examPackControllerProvider.notifier).buy(ExamPack.lgs);
    await settle();
    expect(c.read(examPackUnlockedProvider('lgs')), isTrue);
    // The server has not seen it yet: another pack's list keeps it open.
    backend.server.add(doc({'yds': true}));
    await settle();
    expect(c.read(examPackUnlockedProvider('lgs')), isTrue);
    expect(c.read(examPackUnlockedProvider('yds')), isTrue);
    // The server revokes it: closed.
    backend.server.add(doc({'yds': true, 'lgs': false}));
    await settle();
    expect(c.read(examPackUnlockedProvider('lgs')), isFalse);
  });

  test('parsing tells a missing pack list from an empty one', () {
    expect(ServerEntitlement.fromJson({'active': true}).packsKnown, isFalse);
    expect(ServerEntitlement.fromJson({'active': true, 'packs': {}}).packsKnown, isTrue);
    final e = ServerEntitlement.fromJson({
      'packs': {'yds': false, 'lgs': true},
    });
    expect(e.packs, {'lgs'});
    expect(e.packsRevoked, {'yds'});
  });
}
