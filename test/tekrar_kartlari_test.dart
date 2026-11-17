// "Tekrar kartları": the turning review card, its grades and swipes, the
// spaced-repetition update behind them and the session summary.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/review_grade.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/screens/study/srs_review_screen.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/review_card_data.dart';
import 'package:lingora/study/review_queue.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:lingora/ui/review_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'study_test.dart' show container, inDays, pumpApp, today, vocabDone;
import 'widget_test.dart' show FakeSpeech;

const _card = ReviewCardData(
  id: 'w_borrow',
  en: 'borrow',
  tr: 'ödünç almak',
  tag: 'Günlük hayat',
  sub: 'verb',
  exampleEn: 'Can I borrow your pen?',
  exampleTr: 'Kalemini ödünç alabilir miyim?',
  note: 'lend ile karıştırma: lend = ödünç vermek.',
  noteLabel: 'Sık hata',
);

class _Host {
  final grades = <ReviewGrade>[];
  final speech = FakeSpeech();
}

Future<_Host> _pumpDeck(
  WidgetTester tester, {
  bool reduced = false,
  AppMode mode = AppMode.adult,
  Brightness brightness = Brightness.light,
  bool sound = true,
}) async {
  SharedPreferences.setMockInitialValues({
    AppSettingsNotifier.key: jsonEncode(AppSettings(mode: mode, sound: sound).toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
    disableAnimations: reduced,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final host = _Host();
  final palette = Palette.of(mode, brightness);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [prefsProvider.overrideWithValue(prefs), speechProvider.overrideWithValue(host.speech)],
      child: MaterialApp(
        theme: buildTheme(mode: mode, brightness: brightness),
        builder: (_, c) => PaletteScope(palette: palette, child: c!),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ReviewDeck(
              key: UniqueKey(),
              card: _card,
              behind: 3,
              color: Brand.primary,
              badge: (label: 'YENİ', color: Brand.accent),
              intervalOf: (g) => intervalLabel(scheduleReview(2, g).days),
              onGrade: host.grades.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return host;
}

/// Whether the card is drawn turned around the vertical axis right now.
bool _turning(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(of: find.byKey(const Key('review-card')), matching: find.byType(Transform)),
    )
    .any((t) => t.transform.entry(0, 2).abs() > 0.01);

Finder get _cardFinder => find.byKey(const Key('review-card'));

void main() {
  group('scheduleReview', () {
    test('again drops two boxes, hard stays sooner, good moves one, easy two', () {
      expect(scheduleReview(4, ReviewGrade.again), (box: 2, days: 3));
      expect(scheduleReview(4, ReviewGrade.hard), (box: 4, days: 7));
      expect(scheduleReview(4, ReviewGrade.good), (box: 5, days: 30));
      expect(scheduleReview(4, ReviewGrade.easy), (box: 6, days: 60));
      // A new word: hard still waits a day, easy jumps to three days.
      expect(scheduleReview(null, ReviewGrade.hard), (box: 0, days: 1));
      expect(scheduleReview(null, ReviewGrade.easy), (box: 2, days: 3));
      expect(scheduleReview(reviewIntervals.length - 1, ReviewGrade.easy).box, reviewIntervals.length - 1);
      expect(intervalLabel(0), 'bugün');
      expect(intervalLabel(3), '3 gün');
      expect(intervalLabel(60), '2 ay');
    });

    test('gradeWord updates the box and the due day', () async {
      final c = await container(Progress(wordBox: const {'w': 3}, wordDue: {'w': today}));
      final n = c.read(progressProvider.notifier);
      n.gradeWord('w', ReviewGrade.easy);
      expect((c.read(progressProvider).wordBox['w'], c.read(progressProvider).wordDue['w']), (5, inDays(30)));
      n.gradeWord('w', ReviewGrade.hard);
      expect((c.read(progressProvider).wordBox['w'], c.read(progressProvider).wordDue['w']), (5, inDays(15)));
      n.gradeWord('w', ReviewGrade.again);
      expect((c.read(progressProvider).wordBox['w'], c.read(progressProvider).wordDue['w']), (3, inDays(7)));
      // learnWord keeps its meaning: good / again, and counts a new word.
      n.learnWord('new', known: true);
      expect(c.read(progressProvider).wordBox['new'], 1);
      expect(c.read(progressProvider).counters['$today:$newWordsMetric'], 1);
    });
  });

  group('card content', () {
    test('a YDS word brings its example, translation and common mistake', () {
      final entry = VocabEntry.fromJson({
        'id': 'yd_assess',
        'word': 'assess',
        'pos': 'verb',
        'rank': 1,
        'topic': 'u1',
        'senses': [
          {'tr': 'değerlendirmek', 'def': 'to judge'},
        ],
        'examples': [
          {
            'en': 'They assessed the damage.',
            'tr': 'Hasarı değerlendirdiler.',
            'context': 'genel',
            'target': 'assessed',
          },
        ],
        'tip': 'asses (eşek) ile karıştırma.',
      });
      final card = reviewCardFor((
        id: 'ydm_assess',
        en: 'assess',
        tr: 'değerlendirmek',
        example: null,
        unit: 'Ünite 1',
      ), entries: entryIndex([entry]));
      expect(card.sub, 'verb');
      expect(card.tag, 'Ünite 1');
      expect(
        (card.exampleEn, card.exampleTr, card.highlight),
        ('They assessed the damage.', 'Hasarı değerlendirdiler.', 'assessed'),
      );
      expect((card.noteLabel, card.note), ('Sık hata', 'asses (eşek) ile karıştırma.'));
    });

    test('a word without a tip finds a Notlarım pattern that uses it', () {
      final notes = NotesBundle(
        words: const [],
        topics: [
          GrammarTopic.fromJson({
            'id': 'g1',
            'title': 'used to',
            'category': 'Zamanlar',
            'source': 'x',
            'body': '',
            'rules': <String>[],
            'examples': [
              {'en': 'I used to travel a lot.', 'tr': 'Eskiden çok seyahat ederdim.'},
            ],
          }),
        ],
        diaryPrompts: const [],
      );
      final card = reviewCardFor((
        id: 'gm_travel',
        en: 'travel',
        tr: 'seyahat etmek',
        example: null,
        unit: null,
      ), notes: notes);
      expect((card.noteLabel, card.note), ('Notlarım', 'used to'));
      expect((card.exampleEn, card.exampleTr), ('I used to travel a lot.', 'Eskiden çok seyahat ederdim.'));
      expect(containsWord('Traveling is fun', 'travel'), isFalse);
    });
  });

  group('ReviewDeck', () {
    testWidgets('tap turns the card in 3D; grades show only on the back', (tester) async {
      final host = await _pumpDeck(tester);
      expect(find.byKey(const Key('srs-front')), findsOneWidget);
      expect(find.text('verb'), findsOneWidget);
      expect(find.text('YENİ'), findsOneWidget);
      for (final g in ReviewGrade.values) {
        expect(find.byKey(Key('grade-${g.name}')), findsNothing);
      }

      await tester.tap(_cardFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(_turning(tester), isTrue, reason: 'mid-turn the card is rotated around Y');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-back')), findsOneWidget);
      expect(find.byKey(const Key('srs-front')), findsNothing);
      expect(find.text('ödünç almak'), findsOneWidget);
      expect(find.byKey(const Key('card-example')), findsOneWidget);
      expect(find.text('Kalemini ödünç alabilir miyim?'), findsOneWidget);
      expect(find.byKey(const Key('card-note')), findsOneWidget);
      for (final g in ReviewGrade.values) {
        expect(find.byKey(Key('grade-${g.name}')), findsOneWidget);
      }
      // "sonraki" interval from box 2.
      expect(find.text('7 gün'), findsOneWidget);

      await tester.tap(find.byKey(const Key('grade-hard')));
      await tester.pump();
      expect(host.grades, [ReviewGrade.hard]);
    });

    testWidgets('the flip takes about 400 ms', (tester) async {
      await _pumpDeck(tester);
      await tester.tap(_cardFinder);
      await tester.pump();
      await tester.pump(flipDuration - const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('card-back')), findsOneWidget);
    });

    testWidgets('swiping right is "Bildim", left is "Bilmiyordum"; the card tilts and tints', (tester) async {
      var host = await _pumpDeck(tester);
      final g = await tester.startGesture(tester.getCenter(_cardFinder));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(const Key('swipe-known')), findsOneWidget);
      expect(find.text('BİLDİM'), findsOneWidget);
      final tilt = tester.widget<Transform>(
        find.ancestor(of: find.byKey(const Key('review-card')), matching: find.byType(Transform)).first,
      );
      expect(tilt.transform.entry(0, 1), isNot(0), reason: 'rotated while dragged');
      await g.moveBy(const Offset(80, 0));
      await g.up();
      await tester.pumpAndSettle();
      expect(host.grades, [ReviewGrade.good]);

      host = await _pumpDeck(tester);
      await tester.drag(_cardFinder, const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(host.grades, [ReviewGrade.again]);
    });

    testWidgets('a short drag springs back without grading', (tester) async {
      final host = await _pumpDeck(tester);
      final g = await tester.startGesture(tester.getCenter(_cardFinder));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(find.byKey(const Key('swipe-unknown')), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(host.grades, isEmpty);
      expect(find.byKey(const Key('swipe-unknown')), findsNothing);
    });

    testWidgets('reduced motion: faces cross-fade, no 3D turn; swipe still grades', (tester) async {
      final host = await _pumpDeck(tester, reduced: true);
      await tester.tap(_cardFinder);
      await tester.pump(const Duration(milliseconds: 90));
      expect(_turning(tester), isFalse);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-back')), findsOneWidget);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
      await tester.drag(_cardFinder, const Offset(260, 0));
      await tester.pump();
      expect(host.grades, [ReviewGrade.good]);
    });

    testWidgets('the word is read out on open when sounds are on', (tester) async {
      var host = await _pumpDeck(tester);
      expect(host.speech.said, ['borrow']);
      host = await _pumpDeck(tester, sound: false);
      expect(host.speech.said, isEmpty);
    });

    testWidgets('screen readers hear the face shown: word first, then meaning and example', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester, reduced: true);
      expect(find.bySemanticsLabel(RegExp('^borrow. verb. Günlük hayat')), findsOneWidget);
      await tester.tap(_cardFinder);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          RegExp(
            'borrow: ödünç almak. Örnek: Can I borrow your pen\\?. Kalemini ödünç alabilir miyim\\?. Sık hata',
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Bildim, sonraki tekrar')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Çocuk modu shows Pofuduk, never Çaycı Dayı; adults see neither on the card', (tester) async {
      await _pumpDeck(tester, mode: AppMode.kid, reduced: true);
      expect(find.byType(Pofuduk), findsOneWidget);
      expect(find.byType(Dayi), findsNothing);
      await _pumpDeck(tester, reduced: true);
      expect(find.byType(Pofuduk), findsNothing);
      expect(find.byType(Dayi), findsNothing);
    });

    testWidgets('dark theme renders both faces', (tester) async {
      await _pumpDeck(tester, brightness: Brightness.dark, reduced: true);
      await tester.tap(_cardFinder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('card-back')), findsOneWidget);
    });
  });

  group('SrsReviewScreen', () {
    testWidgets('a session ends in a summary with gold, paid once a day', (tester) async {
      final c = await pumpApp(tester, const SrsReviewScreen(newPerDay: 3), progress: vocabDone(1));
      expect(find.byKey(const Key('srs-progress')), findsOneWidget);
      final words = <String>[];
      // Right, left, right: the forgotten card comes back at the end.
      for (final dx in [300.0, -300.0, 300.0, 300.0]) {
        words.add(tester.widget<Text>(find.byKey(const Key('srs-front'))).data!);
        await tester.drag(find.byKey(const Key('review-card')), Offset(dx, 0));
        await tester.pumpAndSettle();
      }
      expect(words.last, words[1]);
      expect(find.byKey(const Key('review-summary')), findsOneWidget);
      final p = c.read(progressProvider);
      expect(p.wordBox[wordCardId(ydsWordPrefix, words[0])], 1);
      expect(p.wordBox[wordCardId(ydsWordPrefix, words[1])], 1, reason: 'again, then good');
      final gold = reviewGold(2);
      expect(find.text('+$gold'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'two of three known');
      expect(find.text('3'), findsOneWidget);
      final balance = p.wallet.balance;
      expect(balance, gold);

      // Same day, another session: no second payout.
      await tester.pumpWidget(const SizedBox());
      final c2 = await pumpApp(
        tester,
        const SrsReviewScreen(newPerDay: 6),
        progress: vocabDone(1).copyWith(wallet: p.wallet, wordBox: p.wordBox, wordDue: p.wordDue),
      );
      while (find.byKey(const Key('review-card')).evaluate().isNotEmpty) {
        await tester.drag(find.byKey(const Key('review-card')), const Offset(300, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('+0'), findsOneWidget);
      expect(c2.read(progressProvider).wallet.balance, balance);
    });
  });
}
