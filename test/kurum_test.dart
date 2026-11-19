import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/kurum/kurum.dart';
import 'package:lingora/kurum/kurum_widgets.dart';
import 'package:lingora/kurum/teacher_screen.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Wednesday 2026-11-18, 12:00.
final now = DateTime(2026, 11, 18, 12);

const studentCode = 'STUD2345ABCD';
const teacherCode = 'TEAC2345ABCD';
const usedCode = 'USED2345ABCD';
const oldCode = 'EXPR2345ABCD';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  Future<void> code(String c, String role, DateTime exp, {String? claimedBy}) =>
      db.doc('licenseCodes/$c').set({
        'org': 'Deneme Ortaokulu',
        'role': role,
        'expiresAt': Timestamp.fromDate(exp),
        'batch': 'deneme',
        'claimedBy': claimedBy,
        'claimedAt': null,
      });
  final future = DateTime.now().add(const Duration(days: 200));
  await code(studentCode, 'student', future);
  await code(teacherCode, 'teacher', future);
  await code(usedCode, 'student', future, claimedBy: 'someone');
  await code(oldCode, 'student', DateTime.now().subtract(const Duration(days: 1)));
  return db;
}

PathNode node(String id) => PathNode(id: id, type: NodeType.lesson, title: id, description: '');

final course = Course(
  id: 'c',
  title: 'Kurs',
  fromLang: 'tr',
  learningLang: 'en',
  units: [
    Unit(id: 'u1', title: 'Ünite 1', description: '', color: Colors.blue, nodes: [node('a'), node('b')]),
    Unit(id: 'u2', title: 'Ünite 2', description: '', color: Colors.blue, nodes: [node('c'), node('d')]),
  ],
);

const stats = ClassStats(streak: 2, lessonsDone: 5, unitsDone: 1, weekXp: 80, week: '2026-11-16');

void main() {
  group('codes', () {
    test('normalising and formatting', () {
      expect(normalizeLicenseCode('stud-2345 abcd'), studentCode);
      expect(normalizeLicenseCode('STUD2345ABC'), isNull); // too short
      expect(normalizeLicenseCode('STUD2345ABC0'), isNull); // 0 is not used
      expect(formatLicenseCode(studentCode), 'STUD-2345-ABCD');
      expect(normalizeClassCode('snfx 8abc'), 'SNFX8ABC');
      expect(normalizeClassCode('SINIF8AB'), isNull); // I is not used
      final c = newClassCode(Random(1));
      expect(normalizeClassCode(c), c);
    });
  });

  group('summary for teachers', () {
    test('streak, lessons, finished units, this week\'s XP and top mistakes', () {
      final p = const Progress().copyWith(
        streak: 4,
        lastActiveDay: dayKey(now),
        lessonsDone: 7,
        completed: {'a': 1, 'b': 2, 'c': 1},
        xpByDay: {'2026-11-16': 30, '2026-11-18': 20, '2026-11-15': 500},
        errorStats: {'article': 5, 'tense': 9, 'plural': 1, 'modal': 3, 'nonsense': 50},
      );
      final s = classStatsOf(p, course, now);
      expect(s.streak, 4);
      expect(s.lessonsDone, 7);
      expect(s.unitsDone, 1);
      expect(s.weekXp, 50); // Sunday the 15th is last week
      expect(s.week, '2026-11-16');
      expect(s.topErrors, ['tense', 'article', 'modal']);
      expect(s.weekXpAt(now), 50);
      expect(s.weekXpAt(now.add(const Duration(days: 7))), 0);
      // Only the fields firestore.rules allow.
      expect(
        s.toJson().keys,
        unorderedEquals(['streak', 'lessonsDone', 'unitsDone', 'weekXp', 'week', 'topErrors']),
      );
      expect(ClassStats.fromJson(s.toJson()), s);
    });

    test('class-wide top mistakes count students', () {
      ClassMember m(String uid, List<String> e) => ClassMember(
        uid: uid,
        name: uid,
        stats: ClassStats(streak: 0, lessonsDone: 0, unitsDone: 0, weekXp: 0, week: '', topErrors: e),
      );
      expect(
        classTopErrors([
          m('a', ['tense', 'article']),
          m('b', ['tense']),
          m('c', ['plural', 'article']),
        ]),
        [('article', 2), ('tense', 2), ('plural', 1)],
      );
    });
  });

  group('licenses', () {
    test('redeeming a seat claims the code and writes the license', () async {
      final db = await seeded();
      final api = FirestoreKurumApi(db, 'elif');
      final l = await api.redeem('stud-2345-abcd');
      expect(l.org, 'Deneme Ortaokulu');
      expect(l.role, LicenseRole.student);
      expect((await db.doc('licenseCodes/$studentCode').get()).data()!['claimedBy'], 'elif');
      expect((await db.doc('licenses/elif').get()).data()!['code'], studentCode);
      final watched = await api.license().first;
      expect(watched!.activeAt(DateTime.now()), isTrue);
      // A second phone re-links the same seat; a second seat is refused.
      expect((await api.redeem(studentCode)).code, studentCode);
      await expectLater(
        api.redeem(teacherCode),
        throwsA(isA<KurumException>().having((e) => e.reason, 'reason', 'hasLicense')),
      );
    });

    test('wrong, used, expired codes and guests get a Turkish reason', () async {
      final db = await seeded();
      Future<String> reason(Future<Object?> f) async {
        try {
          await f;
          return 'ok';
        } on KurumException catch (e) {
          expect(e.message, isNotEmpty);
          return e.reason;
        }
      }

      final api = FirestoreKurumApi(db, 'elif');
      expect(await reason(api.redeem('12')), 'format');
      expect(await reason(api.redeem('ZZZZ2345ABCD')), 'notFound');
      expect(await reason(api.redeem(usedCode)), 'used');
      expect(await reason(api.redeem(oldCode)), 'expired');
      expect(await reason(FirestoreKurumApi(db, 'g', isGuest: true).redeem(studentCode)), 'needsAccount');
    });

    test('a seat the operator released no longer counts', () async {
      final db = await seeded();
      final api = FirestoreKurumApi(db, 'elif');
      await api.redeem(studentCode);
      await db.doc('licenseCodes/$studentCode').update({'claimedBy': null});
      expect(await api.license().first, isNull);
    });

    test('an active seat turns Premium on', () async {
      final db = await seeded();
      final api = FirestoreKurumApi(db, 'elif');
      await api.redeem(studentCode);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [kurumApiProvider.overrideWithValue(api), prefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      c.listen(orgLicenseProvider, (_, _) {});
      await c.read(orgLicenseProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(licensePremiumProvider), isTrue);
      expect(c.read(premiumProvider), isTrue);
    });
  });

  group('classes', () {
    test('teacher opens a class, student joins, reports and leaves', () async {
      final db = await seeded();
      final teacher = FirestoreKurumApi(db, 'ayse', random: Random(3));
      final room = await teacher.createClass(
        name: '8-A',
        teacherName: 'Ayşe Öğretmen',
        org: 'Deneme Ortaokulu',
      );
      expect(normalizeClassCode(room.code), room.code);
      expect((await teacher.teacherClasses().first).single.name, '8-A');

      final student = FirestoreKurumApi(db, 'elif');
      expect((await student.joinClass(room.code.toLowerCase(), name: 'Elif', stats: stats)).name, '8-A');
      expect(await student.myClassCodes().first, [room.code]);
      final members = await teacher.members(room.code).first;
      expect(members.single.name, 'Elif');
      expect(members.single.stats.weekXp, 80);
      final data = (await db.doc('classes/${room.code}/members/elif').get()).data()!;
      expect(data.keys, isNot(contains('email')));

      expect(
        await student.publish(
          room.code,
          const ClassStats(streak: 3, lessonsDone: 6, unitsDone: 1, weekXp: 95, week: '2026-11-16'),
        ),
        isTrue,
      );
      expect((await teacher.members(room.code).first).single.stats.streak, 3);

      // The server's speaking copy (speaking_stats.ts) reaches the teacher...
      await db.doc('classes/${room.code}/speaking/elif').set({
        'conversations': 2,
        'minutes': 9,
        'lastAt': Timestamp.fromDate(now),
        'lastSummary': 'İyi gitti.',
        'recentMistakes': [
          {'original': 'I go', 'corrected': 'I went'},
        ],
        'weakWords': ['thought'],
      });
      final talk = (await teacher.speaking(room.code).first)['elif']!;
      expect(talk.conversations, 2);
      expect(talk.minutes, 9);
      expect(talk.recentMistakes.single.corrected, 'I went');

      // ...and leaves with the student.
      await student.leaveClass(room.code);
      expect(await student.myClassCodes().first, isEmpty);
      expect(await teacher.members(room.code).first, isEmpty);
      expect(await teacher.speaking(room.code).first, isEmpty);
    });

    test('a removed student stops reporting; closed classes take nobody new', () async {
      final db = await seeded();
      final teacher = FirestoreKurumApi(db, 'ayse');
      final room = await teacher.createClass(name: '8-B', teacherName: 'Ayşe', org: 'Deneme Ortaokulu');
      final student = FirestoreKurumApi(db, 'mert');
      await student.joinClass(room.code, name: 'Mert', stats: stats);
      await db.doc('classes/${room.code}/speaking/mert').set({'conversations': 1, 'minutes': 2});
      await teacher.removeMember(room.code, 'mert');
      expect(await teacher.speaking(room.code).first, isEmpty);
      expect(await student.publish(room.code, stats), isFalse);
      expect(await student.myClassCodes().first, isEmpty);

      await teacher.setOpen(room.code, false);
      await expectLater(
        student.joinClass(room.code, name: 'Mert', stats: stats),
        throwsA(isA<KurumException>().having((e) => e.reason, 'reason', 'closed')),
      );
      await expectLater(
        student.joinClass('ZZZZ2345', name: 'Mert', stats: stats),
        throwsA(isA<KurumException>().having((e) => e.reason, 'reason', 'notFound')),
      );
    });
  });

  group('screens', () {
    Future<FirestoreKurumApi> pump(
      WidgetTester tester,
      Widget child, {
      String uid = 'elif',
      FakeFirebaseFirestore? db,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FirestoreKurumApi(db ?? await seeded(), uid);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            kurumApiProvider.overrideWithValue(api),
            clockProvider.overrideWithValue(() => now),
            kurumNameHintProvider.overrideWithValue('Elif Yılmaz'),
            classStatsProvider.overrideWithValue(stats),
          ],
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a student enters a license code and joins a class', (tester) async {
      final db = await tester.runAsync(seeded);
      await tester.runAsync(
        () => FirestoreKurumApi(
          db!,
          'ayse',
        ).createClass(name: '8-A', teacherName: 'Ayşe', org: 'Deneme Ortaokulu'),
      );
      final code = (await tester.runAsync(() => db!.collection('classes').get()))!.docs.single.id;
      await pump(tester, const KurumSection(), db: db);
      expect(find.byKey(const Key('kurum-redeem')), findsOneWidget);
      expect(find.byKey(const Key('kurum-teacher')), findsNothing);

      await tester.tap(find.byKey(const Key('kurum-redeem')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('kurum-code-field')), 'USED-2345-ABCD');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('kurum-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kurum-dialog-error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('kurum-code-field')), 'stud 2345 abcd');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('kurum-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kurum-dialog-done')), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kurum-license')), findsOneWidget);

      await tester.tap(find.byKey(const Key('kurum-join')));
      await tester.pumpAndSettle();
      // The name field is pre-filled with the first name only.
      expect(find.text('Elif'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('kurum-code-field')), code);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('kurum-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kurum-dialog-done')), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('kurum-class-$code')), findsOneWidget);
    });

    testWidgets('the teacher sees each student\'s summary and the class\'s mistakes', (tester) async {
      final db = await tester.runAsync(seeded);
      final code = (await tester.runAsync(() async {
        final t = FirestoreKurumApi(db!, 'ayse');
        await t.redeem(teacherCode);
        final room = await t.createClass(name: '8-A', teacherName: 'Ayşe', org: 'Deneme Ortaokulu');
        await FirestoreKurumApi(db, 'elif').joinClass(
          room.code,
          name: 'Elif',
          stats: const ClassStats(
            streak: 5,
            lessonsDone: 9,
            unitsDone: 2,
            weekXp: 120,
            week: '2026-11-16',
            topErrors: ['tense', 'article'],
          ),
        );
        await FirestoreKurumApi(db, 'can').joinClass(
          room.code,
          name: 'Can',
          stats: const ClassStats(
            streak: 0,
            lessonsDone: 1,
            unitsDone: 0,
            weekXp: 40,
            week: '2026-11-09',
            topErrors: ['tense'],
          ),
        );
        await db.doc('classes/${room.code}/speaking/elif').set({
          'conversations': 3,
          'minutes': 14,
          'lastAt': Timestamp.fromDate(DateTime(2026, 11, 17, 20)),
          'lastSummary': 'Akıcı konuştun. Geçmiş zamanı çalış.',
          'recentMistakes': [
            {'original': 'I go yesterday', 'corrected': 'I went yesterday'},
          ],
          'weakWords': ['thought', 'three'],
        });
        return room.code;
      }))!;
      await pump(
        tester,
        const SizedBox(height: 800, child: TeacherScreen()),
        uid: 'ayse',
        db: db,
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('teacher-class-$code')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text(code), findsOneWidget);
      expect(
        find.textContaining('2 öğrenci · bu hafta toplam 120 XP'),
        findsOneWidget,
      ); // Can's XP is last week's
      expect(find.textContaining('🔥 5 gün seri · 2 ünite · 9 ders · bu hafta 120 XP'), findsOneWidget);
      expect(find.byKey(const Key('class-error-tense')), findsOneWidget);
      expect(find.textContaining('Zaman uyumu · 2 öğrenci'), findsOneWidget);
      // Voice-coach stats only for Elif, who practised.
      expect(find.textContaining('1 öğrenci konuşma pratiği yaptı · toplam yaklaşık 14 dk'), findsOneWidget);
      expect(find.byType(SpeakingLines), findsOneWidget);
      expect(find.textContaining('3 konuşma · yaklaşık 14 dk · son 17.11'), findsOneWidget);
      expect(find.textContaining('Son karne: Akıcı konuştun.'), findsOneWidget);
      expect(find.textContaining('"I go yesterday" → "I went yesterday"'), findsOneWidget);
      expect(find.textContaining('Telaffuzda zorlandığı: thought, three'), findsOneWidget);
    });
  });
}
