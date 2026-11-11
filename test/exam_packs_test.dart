import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/exam_pack_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/models/exam_pack.dart';
import 'package:lingora/screens/exam_pack_screen.dart';
import 'package:lingora/screens/exam_screen.dart';
import 'package:lingora/screens/family_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/billing_service.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/exam_packs.dart';
import 'package:lingora/services/billing/family.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/billing_backends_firebase.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real section layout of a full mock exam: section id → question count.
const ydsLayout = {
  'yds_vocab': 6,
  'yds_grammar': 10,
  'yds_cloze': 10,
  'yds_completion': 10,
  'yds_translation': 6,
  'yds_reading': 20,
  'yds_dialogue': 6,
  'yds_restatement': 3,
  'yds_paragraph': 4,
  'yds_irrelevant': 5,
};
const lgsLayout = {'lgs_vocab': 2, 'lgs_dialogue': 2, 'lgs_reading': 4, 'lgs_situation': 2};

ExamPackContent readPack(ExamPack p) =>
    ExamPackContent.fromJson(jsonDecode(File(p.asset).readAsStringSync()) as Map<String, dynamic>);

Exam readExam(String id) =>
    Exam.fromJson(jsonDecode(File('assets/exams/$id.json').readAsStringSync()) as Map<String, dynamic>);

class PackBilling implements BillingService {
  bool available = true;
  StorePurchaseStatus autoResult = StorePurchaseStatus.purchased;
  final owned = <String>{};
  final bought = <String>[];
  final completed = <String>[];
  final _ctrl = StreamController<List<StorePurchase>>.broadcast();

  void emit(String id, StorePurchaseStatus status) =>
      _ctrl.add([StorePurchase(productId: id, status: status, token: 'tok-$id', needsCompletion: true)]);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> loadProducts(Set<String> ids) async => [
    const StoreProduct(id: 'lingora_premium_monthly', title: 'Aylık', price: '₺100,00', rawPrice: 100),
    const StoreProduct(id: 'lingora_premium_yearly', title: 'Yıllık', price: '₺600,00', rawPrice: 600),
    const StoreProduct(id: 'lingora_premium_family_yearly', title: 'Aile', price: '₺900,00', rawPrice: 900),
    const StoreProduct(id: 'lingora_pack_yds_full', title: 'YDS', price: '₺149,99', rawPrice: 149.99),
    const StoreProduct(id: 'lingora_pack_lgs_full', title: 'LGS', price: '₺99,99', rawPrice: 99.99),
  ].where((p) => ids.contains(p.id)).toList();

  @override
  Future<void> buy(String productId) async {
    bought.add(productId);
    scheduleMicrotask(() => emit(productId, autoResult));
  }

  @override
  Future<void> restore() async {
    for (final id in owned) {
      scheduleMicrotask(() => emit(id, StorePurchaseStatus.restored));
    }
  }

  @override
  Stream<List<StorePurchase>> get purchases => _ctrl.stream;

  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase.productId);
}

class PackBackend implements EntitlementBackend {
  ServerEntitlement result = const ServerEntitlement(premium: false, status: 'expired', packs: {'yds'});
  Object? error;
  final server = StreamController<ServerEntitlement?>.broadcast();

  @override
  Future<ServerEntitlement> verify({required String productId, required String purchaseToken}) async {
    if (error case final e?) throw e;
    return result;
  }

  @override
  Stream<ServerEntitlement?> watch() => server.stream;
}

class FakeFamily implements FamilyBackend {
  FamilyInfo info = const FamilyInfo();
  final removed = <String>[];
  String? redeemed;

  @override
  Future<FamilyInfo> getFamily() async => info;

  @override
  Future<({String code, DateTime expiresAt})> createInvite() async {
    info = FamilyInfo(
      role: FamilyRole.owner,
      active: true,
      expiresAt: DateTime(2027, 11, 11),
      members: info.members,
      code: 'ABCDEFGH',
      codeExpiresAt: DateTime(2026, 11, 17),
    );
    return (code: 'ABCDEFGH', expiresAt: DateTime(2026, 11, 17));
  }

  @override
  Future<ServerEntitlement> redeem(String code) async {
    if (code.trim().isEmpty) throw const FamilyException('invalid-argument', 'invalid_code');
    if (code == 'FULLFULL') throw const FamilyException('resource-exhausted', 'family_full');
    redeemed = code;
    info = FamilyInfo(role: FamilyRole.member, ownerName: 'Ayşe', expiresAt: DateTime(2027, 11, 11));
    return ServerEntitlement(
      premium: true,
      status: 'active',
      productId: PremiumPlan.familyYearly.id,
      expiresAt: DateTime(2027, 11, 11),
      source: 'family',
    );
  }

  @override
  Future<void> removeMember(String uid) async {
    removed.add(uid);
    info = FamilyInfo(
      role: FamilyRole.owner,
      active: true,
      expiresAt: info.expiresAt,
      members: [
        for (final m in info.members)
          if (m.uid != uid) m,
      ],
      code: info.code,
    );
  }

  @override
  Future<void> leave() async => info = const FamilyInfo();
}

final now = DateTime(2026, 11, 10, 12);

Future<ProviderContainer> container(
  PackBilling billing, {
  EntitlementBackend? backend,
  bool dev = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => now),
      billingServiceProvider.overrideWithValue(billing),
      entitlementBackendProvider.overrideWithValue(backend),
      premiumDevOverrideProvider.overrideWithValue(dev),
    ],
  );
  addTearDown(c.dispose);
  c.listen(premiumControllerProvider, (_, _) {});
  c.listen(examPackControllerProvider, (_, _) {});
  return c;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

Future<List<Override>> widgetOverrides(
  WidgetTester tester,
  PackBilling billing, {
  bool dev = false,
  List<Override> extra = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    prefsProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => now),
    billingServiceProvider.overrideWithValue(billing),
    premiumDevOverrideProvider.overrideWithValue(dev),
    for (final p in ExamPack.values) examPackContentProvider(p).overrideWith((ref) async => readPack(p)),
    ...extra,
  ];
}

Widget app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(home: Scaffold(body: home)),
);

void main() {
  group('pack content', () {
    final banks = {
      for (final id in ['yds', 'lgs']) id: readExam(id),
    };
    final allIds = <String>{for (final e in banks.values) ...e.allQuestions.map((q) => q.id)};

    for (final pack in ExamPack.values) {
      test('${pack.id} is complete, well formed and original', () {
        final c = readPack(pack);
        final bank = banks[pack.examId]!;
        final layout = pack == ExamPack.yds ? ydsLayout : lgsLayout;
        expect(c.examId, pack.examId);
        expect(c.optionCount, bank.optionCount);
        expect(c.mocks, hasLength(pack == ExamPack.yds ? 3 : 4));
        expect(c.sections.map((s) => s.id).toSet(), layout.keys.toSet());
        final bankTexts = {for (final q in bank.allQuestions) q.text};
        final letters = List.filled(c.optionCount, 0);
        for (final m in c.mocks) {
          expect(m.minutes, pack == ExamPack.yds ? 180 : 15);
          expect(m.questions, hasLength(layout.values.reduce((a, b) => a + b)), reason: m.id);
          final perSection = <String, int>{};
          for (final q in m.questions) {
            perSection[q.section!] = (perSection[q.section!] ?? 0) + 1;
            expect(allIds.add(q.id), isTrue, reason: 'duplicate id ${q.id}');
            expect(q.id, startsWith('${m.id}_q'));
            expect(q.options, hasLength(c.optionCount), reason: q.id);
            expect(
              q.options.map((o) => o.trim().toLowerCase()).toSet(),
              hasLength(c.optionCount),
              reason: q.id,
            );
            expect(q.answer, inInclusiveRange(0, c.optionCount - 1), reason: q.id);
            expect(q.explanation.trim().length, greaterThan(40), reason: q.id);
            expect(
              q.explanation,
              matches(RegExp('[çğıöşüÇĞİÖŞÜ]')),
              reason: '${q.id} explanation in Turkish',
            );
            if (q.passage == null && !q.text.contains('hangisi')) {
              expect(bankTexts, isNot(contains(q.text)), reason: '${q.id} copies the free bank');
            }
            letters[q.answer]++;
          }
          expect(perSection, layout, reason: '${m.id} section proportions');
        }
        final total = letters.reduce((a, b) => a + b);
        expect(letters.reduce(max), lessThan(total * 0.35), reason: 'answer letters $letters');
        expect(letters.reduce(min), greaterThan(total * 0.12), reason: 'answer letters $letters');
      });
    }
  });

  group('scoring', () {
    ExamQuestion q(String section, int answer) => ExamQuestion(
      id: '$section$answer',
      section: section,
      text: 't',
      options: const ['a', 'b'],
      answer: answer,
      explanation: 'e',
    );

    test('YDS: 1.25 points per correct answer, wrong answers cost nothing', () {
      final qs = [for (var i = 0; i < 80; i++) q(i < 40 ? 'yds_vocab' : 'yds_reading', 0)];
      final answers = {for (var i = 0; i < 60; i++) i: i < 50 ? 0 : 1};
      final s = MockScore.of(qs, answers, ExamScoring.yds);
      expect((s.correct, s.wrong, s.blank), (50, 10, 20));
      expect(s.score, 62.5);
      expect(s.net, 50);
      expect(s.topics['yds_vocab'], (correct: 40, wrong: 0, total: 40));
      expect(s.topics['yds_reading'], (correct: 10, wrong: 10, total: 40));
    });

    test('LGS: three wrong answers cancel one correct', () {
      final qs = [for (var i = 0; i < 10; i++) q('lgs_vocab', 0)];
      final s = MockScore.of(qs, {for (var i = 0; i < 9; i++) i: i < 6 ? 0 : 1}, ExamScoring.lgs);
      expect((s.correct, s.wrong, s.blank), (6, 3, 1));
      expect(s.net, 5);
      expect(s.score, isNull);
    });
  });

  group('pack purchases', () {
    test('buying a pack unlocks it, caches it and leaves Premium alone', () async {
      final billing = PackBilling();
      final c = await container(billing);
      expect(c.read(examPackUnlockedProvider('yds')), isFalse);
      await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
      await settle();
      expect(c.read(examPackUnlockedProvider('yds')), isTrue);
      expect(c.read(examPackUnlockedProvider('lgs')), isFalse);
      expect(c.read(examPackControllerProvider).justPurchased, ExamPack.yds);
      expect(c.read(premiumProvider), isFalse);
      expect(billing.completed, ['lingora_pack_yds_full'], reason: 'completed exactly once');
      expect(c.read(prefsProvider).getStringList('packs.owned'), ['yds']);
    });

    test('Premium unlocks every pack', () async {
      final c = await container(PackBilling(), dev: true);
      expect(c.read(examPackUnlockedProvider('yds')), isTrue);
      expect(c.read(examPackUnlockedProvider('lgs')), isTrue);
    });

    test('a pack purchase does not open Premium even with a premium-looking token', () async {
      final billing = PackBilling();
      final c = await container(billing);
      billing.emit('lingora_pack_lgs_full', StorePurchaseStatus.purchased);
      await settle();
      expect(c.read(premiumControllerProvider).active, isFalse);
      expect(c.read(premiumControllerProvider).error, isNull);
      expect(c.read(examPackUnlockedProvider('lgs')), isTrue);
    });

    test('server verification: rejected and unreachable', () async {
      final billing = PackBilling();
      final backend = PackBackend()..error = const EntitlementRejected('already-exists');
      final c = await container(billing, backend: backend);
      await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
      await settle();
      expect(c.read(examPackUnlockedProvider('yds')), isFalse);
      expect(c.read(examPackControllerProvider).error, contains('başka bir Dilbaz hesabına'));

      backend.error = StateError('offline');
      await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
      await settle();
      expect(c.read(examPackUnlockedProvider('yds')), isTrue, reason: 'store trusted when offline');
    });

    test('server answer without the pack does not unlock; the server stream can grant', () async {
      final backend = PackBackend()..result = const ServerEntitlement(premium: false, status: 'expired');
      final c = await container(PackBilling(), backend: backend);
      await c.read(examPackControllerProvider.notifier).buy(ExamPack.lgs);
      await settle();
      expect(c.read(examPackUnlockedProvider('lgs')), isFalse);
      backend.server.add(const ServerEntitlement(premium: false, status: 'expired', packs: {'lgs'}));
      await settle();
      expect(c.read(examPackUnlockedProvider('lgs')), isTrue);
    });

    test('pending payment, then restore', () async {
      final billing = PackBilling()..autoResult = StorePurchaseStatus.pending;
      final c = await container(billing);
      await c.read(examPackControllerProvider.notifier).buy(ExamPack.yds);
      await settle();
      expect(c.read(examPackControllerProvider).pending, {'yds'});
      expect(c.read(examPackUnlockedProvider('yds')), isFalse);

      billing.owned.add('lingora_pack_yds_full');
      await c.read(examPackControllerProvider.notifier).restore(ExamPack.yds);
      expect(c.read(examPackUnlockedProvider('yds')), isTrue);
      expect(
        c.read(examPackControllerProvider).justPurchased,
        isNull,
        reason: 'restore is not a new purchase',
      );
    });

    test('restore with nothing to restore says so', () async {
      final c = await container(PackBilling());
      await c.read(examPackControllerProvider.notifier).restore(ExamPack.lgs);
      expect(c.read(examPackControllerProvider).message, contains('bulunamadı'));
    });

    test('server entitlement parsing', () {
      final e = ServerEntitlement.fromJson({
        'active': true,
        'expiresAt': 1000,
        'packs': {'yds': true, 'lgs': false},
        'source': 'family',
        'family': {'ownerUid': 'o', 'role': 'member'},
      });
      expect(e.packs, {'yds'});
      expect(e.source, 'family');
      expect(e.familyOwnerUid, 'o');
      expect(e.familyRole, 'member');
    });
  });

  group('exam home', () {
    testWidgets('locked pack shows the store price; buying unlocks the full mock list', (tester) async {
      final billing = PackBilling();
      final exam = readExam('lgs');
      final overrides = await widgetOverrides(
        tester,
        billing,
        extra: [examProvider('lgs').overrideWith((ref) async => exam)],
      );
      await tester.pumpWidget(app(overrides, const ExamHomeScreen(examId: 'lgs')));
      await tester.pumpAndSettle();
      expect(find.text('LGS İngilizce Tam Deneme Paketi'), findsOneWidget);
      expect(find.text('Satın al · ₺99,99'), findsOneWidget);
      expect(find.byKey(const ValueKey('full-mock-lgs_m1')), findsNothing);

      await tester.tap(find.text('Satın al · ₺99,99'));
      await tester.pumpAndSettle();
      expect(billing.bought, ['lingora_pack_lgs_full']);
      expect(find.byKey(const ValueKey('full-mock-lgs_m4')), findsOneWidget);
      expect(find.textContaining('açıldı'), findsOneWidget);
    });

    testWidgets('full mock: real timer, blanks allowed, net and topic breakdown, wrong-answer review', (
      tester,
    ) async {
      final exam = readExam('lgs');
      final pack = readPack(ExamPack.lgs);
      final overrides = await widgetOverrides(
        tester,
        PackBilling(),
        dev: true,
        extra: [examProvider('lgs').overrideWith((ref) async => exam)],
      );
      await tester.pumpWidget(app(overrides, const ExamHomeScreen(examId: 'lgs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('full-mock-lgs_m2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Başla'));
      await tester.pumpAndSettle();
      expect(find.byType(ExamSessionScreen), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('14:59'), findsOneWidget);

      final qs = pack.mocks[1].questions;
      // Answer the first question right, the second wrong, leave the rest blank.
      await tester.tap(find.text(qs[0].options[qs[0].answer]));
      await tester.pump();
      await tester.tap(find.text('Sonraki'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(qs[1].options[(qs[1].answer + 1) % 4]));
      await tester.pump();
      await tester.tap(find.text('Önceki'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SORU 1/10'), findsOneWidget);
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.text(i == 0 ? 'Sonraki' : (i == 1 ? 'Sonraki' : 'Boş bırak')).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Denemeyi bitir'));
      await tester.pumpAndSettle();
      expect(find.text('8 soru boş. Bitirirsen boş sorular puanlanmaz.'), findsOneWidget);
      await tester.tap(find.text('Bitir'));
      await tester.pumpAndSettle();

      expect(find.byType(FullMockResultScreen), findsOneWidget);
      // 1 correct, 1 wrong: net = 1 - 1/3.
      expect(find.text('İngilizce neti: 0,67 / 10'), findsOneWidget);
      expect(find.text('Konu dökümü'), findsOneWidget);
      expect(find.text('Okuduğunu anlama'), findsOneWidget);
      // Review lists the wrong and blank ones (9 of 10) by default.
      expect(find.textContaining('Boş · doğru'), findsNWidgets(8));
      expect(find.textContaining('Senin: '), findsOneWidget);
      await tester.tap(find.text('Yalnız yanlış/boş'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Senin: '), findsNWidgets(2));
    });

    testWidgets('YDS result shows a score estimate', (tester) async {
      final pack = readPack(ExamPack.yds);
      final mock = pack.mocks.first;
      final overrides = await widgetOverrides(tester, PackBilling());
      await tester.pumpWidget(
        app(
          overrides,
          FullMockResultScreen(
            pack: pack,
            mock: mock,
            answers: {for (var i = 0; i < 40; i++) i: mock.questions[i].answer},
            xp: 40,
            duration: const Duration(minutes: 150),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tahmini puan: 50'), findsOneWidget);
      expect(find.text('Anlam bütünlüğünü bozan cümle'), findsOneWidget);
    });
  });

  group('family plan', () {
    testWidgets('without a server the family screen explains why', (tester) async {
      final overrides = await widgetOverrides(tester, PackBilling());
      await tester.pumpWidget(app(overrides, const FamilyScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('sunucu bağlantısı'), findsOneWidget);
      expect(find.byKey(const ValueKey('family-join')), findsNothing);
    });

    testWidgets('redeeming a code opens Premium; errors are shown in Turkish', (tester) async {
      final family = FakeFamily();
      final overrides = await widgetOverrides(
        tester,
        PackBilling(),
        extra: [familyBackendProvider.overrideWithValue(family), currentUidProvider.overrideWithValue('kid')],
      );
      await tester.pumpWidget(app(overrides, const FamilyScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('family-code-field')), 'FULLFULL');
      await tester.tap(find.byKey(const ValueKey('family-join')));
      await tester.pumpAndSettle();
      expect(find.text('Bu aile planı dolu (en fazla 5 kişi).'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('family-code-field')), 'abcd-efgh');
      await tester.tap(find.byKey(const ValueKey('family-join')));
      await tester.pumpAndSettle();
      expect(family.redeemed, 'abcd-efgh');
      expect(find.textContaining('Premium açıldı'), findsOneWidget);
      expect(find.textContaining('Ayşe aile planındasın'), findsOneWidget);
      final c = ProviderScope.containerOf(tester.element(find.byType(FamilyScreen)));
      expect(c.read(premiumProvider), isTrue);
      expect(c.read(premiumControllerProvider).productId, PremiumPlan.familyYearly.id);
    });

    testWidgets('owner creates a code and removes a member', (tester) async {
      final family = FakeFamily()
        ..info = FamilyInfo(
          role: FamilyRole.owner,
          active: true,
          expiresAt: DateTime(2027, 11, 11),
          members: const [FamilyMember(uid: 'kid', displayName: 'Ali')],
        );
      final overrides = await widgetOverrides(
        tester,
        PackBilling(),
        extra: [
          familyBackendProvider.overrideWithValue(family),
          currentUidProvider.overrideWithValue('owner'),
        ],
      );
      await tester.pumpWidget(app(overrides, const FamilyScreen()));
      await tester.pumpAndSettle();
      expect(find.text('2/5 kişi · plan 11.11.2027 tarihine kadar geçerli'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('family-new-code')));
      await tester.pumpAndSettle();
      expect(find.text('ABCD-EFGH'), findsOneWidget);

      await tester.tap(find.byTooltip('Aileden çıkar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çıkar'));
      await tester.pumpAndSettle();
      expect(family.removed, ['kid']);
      expect(find.text('Ali'), findsNothing);
    });

    testWidgets('paywall offers the family plan only with a server', (tester) async {
      final billing = PackBilling();
      final overrides = await widgetOverrides(tester, billing);
      await tester.pumpWidget(app(overrides, const PaywallScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-familyYearly')), findsNothing);
      expect(find.textContaining('bu sürümde satın alınamaz'), findsOneWidget);
    });

    testWidgets('paywall sells the family plan with a server', (tester) async {
      final billing = PackBilling();
      final overrides = await widgetOverrides(
        tester,
        billing,
        extra: [familyBackendProvider.overrideWithValue(FakeFamily())],
      );
      await tester.pumpWidget(app(overrides, const PaywallScreen(showFamily: true)));
      await tester.pumpAndSettle();
      expect(find.text('₺900,00 / yıl · 5 kişiye kadar'), findsOneWidget);
      await tester.tap(find.text('Aile · ₺900,00'));
      await tester.pumpAndSettle();
      expect(billing.bought, ['lingora_premium_family_yearly']);
    });

    test('Firebase backends map callable errors', () async {
      FirebaseFunctionsException err(String code, String message) =>
          FirebaseFunctionsException(code: code, message: message);
      final ent = FirebaseEntitlementBackend(
        call: (name, data) async => throw err('already-exists', 'token_in_use'),
      );
      await expectLater(
        ent.verify(productId: 'lingora_pack_yds_full', purchaseToken: 't'),
        throwsA(isA<EntitlementRejected>()),
      );
      final ok = FirebaseEntitlementBackend(
        call: (name, data) async {
          expect(name, 'verifyPurchase');
          return {
            'active': false,
            'productId': data['productId'],
            'packs': {'yds': true},
          };
        },
      );
      expect((await ok.verify(productId: 'lingora_pack_yds_full', purchaseToken: 't')).packs, {'yds'});

      final fam = FirebaseFamilyBackend((name, data) async => throw err('resource-exhausted', 'family_full'));
      await expectLater(
        fam.redeem('ABCDEFGH'),
        throwsA(isA<FamilyException>().having((e) => e.message, 'message', contains('dolu'))),
      );
      final offline = FirebaseFamilyBackend((name, data) async => throw const SocketException('x'));
      await expectLater(
        offline.getFamily(),
        throwsA(isA<FamilyException>().having((e) => e.code, 'code', 'unavailable')),
      );
      final info = await FirebaseFamilyBackend(
        (name, data) async => {
          'role': 'owner',
          'seats': 5,
          'expiresAt': 1000,
          'active': true,
          'members': [
            {'uid': 'a', 'displayName': 'A', 'joinedAt': 5},
          ],
          'code': 'ABCDEFGH',
          'codeExpiresAt': 2000,
        },
      ).getFamily();
      expect(info.role, FamilyRole.owner);
      expect(info.members.single.displayName, 'A');
      expect(info.freeSeats, 3);
    });
  });
}
