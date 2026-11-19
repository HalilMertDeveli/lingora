// "Bildir": the report flow on a question (sheet, attached data, limits).
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/app_version.dart';
import 'package:lingora/data/first_lesson.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/question_reports.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

class _FakeReporter implements QuestionReporter {
  final sent = <QuestionReport>[];
  ReportError? fail;

  @override
  Future<void> send(QuestionReport report) async {
    if (fail case final e?) throw ReportException(e);
    sent.add(report);
  }
}

Future<_FakeReporter> _pumpLesson(WidgetTester tester, {ReportError? fail}) async {
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final reporter = _FakeReporter()..fail = fail;
  // The translate question ("Sana katılıyorum.") of the first lesson.
  final item = firstLessonItems().firstWhere((i) => i.ex.tokens.contains('am'));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(p),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        questionReporterProvider.overrideWithValue(reporter),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: LessonScreen(
          nodeId: firstLessonId,
          title: firstLessonTitle,
          items: [item],
          color: Colors.indigo,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reporter;
}

Future<void> _answerIAmAgree(WidgetTester tester) async {
  for (final w in ['I', 'am', 'agree', 'with', 'you']) {
    await tester.tap(find.text(w).last);
    await tester.pump();
  }
  await tester.tap(find.text('Kontrol et'));
  await tester.pumpAndSettle();
}

void main() {
  group('report sheet', () {
    testWidgets('on the question and after its explanation, with the answer attached', (tester) async {
      final reporter = await _pumpLesson(tester);
      expect(find.byKey(const Key('report-question')), findsOneWidget);
      await _answerIAmAgree(tester);
      expect(find.byKey(const Key('report-question')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-question')));
      await tester.pumpAndSettle();
      expect(find.text('Cevap hatalı'), findsOneWidget);
      expect(find.text('Başka cevap da doğru'), findsOneWidget);
      expect(find.text('Açıklama anlaşılmıyor'), findsOneWidget);
      // A reason is required; the note is optional.
      expect(tester.widget<FilledButton>(find.byKey(const Key('report-send'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('report-reason-other_correct')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('report-note')), '  "I agree" tek başına da doğru  ');
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();

      expect(reporter.sent, hasLength(1));
      final r = reporter.sent.single;
      expect(r.reason, ReportReason.otherCorrect);
      expect(r.questionId, '$firstLessonId#4');
      expect(r.lessonId, firstLessonId);
      expect(r.answer, 'I am agree with you');
      expect(r.correct, isFalse);
      expect(r.appVersion, appVersion);
      expect(r.question, contains('Sana katılıyorum.'));
      expect(r.toFields()['note'], '"I agree" tek başına da doğru');
      expect(find.byKey(const Key('report-sheet')), findsNothing);
      expect(find.textContaining('Teşekkürler'), findsOneWidget);
    });

    testWidgets('a refused report says why and keeps the sheet open', (tester) async {
      await _pumpLesson(tester, fail: ReportError.tooFast);
      await tester.tap(find.byKey(const Key('report-question')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-reason-unclear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-error')), findsOneWidget);
      expect(find.textContaining('Birkaç saniye sonra'), findsOneWidget);
      expect(find.byKey(const Key('report-sheet')), findsOneWidget);
    });
  });

  group('Firestore reporter', () {
    const report = QuestionReport(
      reason: ReportReason.wrongAnswer,
      questionId: 'u1l2#4',
      lessonId: 'u1l2',
      appVersion: '0.1.0+1',
      answer: 'I am a student',
      correct: false,
    );

    test('writes reports/{uid}_{n} with the limit doc, status yeni', () async {
      final db = FakeFirebaseFirestore();
      var now = DateTime(2026, 11, 19, 10);
      final r = FirestoreQuestionReporter(db, 'alice', () => now);
      await r.send(report);
      final doc = await db.doc('reports/alice_1').get();
      expect(doc.data()!['reason'], 'wrong_answer');
      expect(doc.data()!['uid'], 'alice');
      expect(doc.data()!['status'], 'yeni');
      expect(doc.data()!['answer'], 'I am a student');
      expect(doc.data()!.containsKey('note'), isFalse);
      final limit = (await db.doc('reportLimits/alice').get()).data()!;
      expect(limit['n'], 1);
      expect(limit['count'], 1);
    });

    test('too fast, then fine; refused without an account', () async {
      final db = FakeFirebaseFirestore();
      var now = DateTime.now();
      final r = FirestoreQuestionReporter(db, 'alice', () => now);
      await r.send(report);
      await expectLater(
        r.send(report),
        throwsA(isA<ReportException>().having((e) => e.error, 'error', ReportError.tooFast)),
      );
      now = now.add(const Duration(seconds: 30));
      await r.send(report);
      expect((await db.doc('reports/alice_2').get()).exists, isTrue);
      await expectLater(
        FirestoreQuestionReporter(db, null, () => now).send(report),
        throwsA(isA<ReportException>().having((e) => e.error, 'error', ReportError.unavailable)),
      );
    });

    test('daily limit', () async {
      final db = FakeFirebaseFirestore();
      final now = DateTime.now();
      await db.doc('reportLimits/alice').set({
        'windowStart': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
        'last': Timestamp.fromDate(now.subtract(const Duration(minutes: 1))),
        'count': reportsPerDay,
        'n': 33,
      });
      await expectLater(
        FirestoreQuestionReporter(db, 'alice', () => now).send(report),
        throwsA(isA<ReportException>().having((e) => e.error, 'error', ReportError.dailyLimit)),
      );
    });

    test('long fields are cut to what the rules allow', () {
      final f = QuestionReport(
        reason: ReportReason.unclear,
        questionId: 'q',
        lessonId: 'l',
        appVersion: 'v',
        note: 'x' * 900,
        question: 'y' * 900,
      ).toFields();
      expect((f['note']! as String).length, maxReportNote);
      expect((f['question']! as String).length, 400);
      expect(f.containsKey('answer'), isFalse);
    });
  });
}
