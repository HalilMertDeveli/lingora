// Shared answer matcher for typed answers (lib/core/spelling.dart): silent
// normalisation, forgiven spelling slips with a note, and slips that make
// another word or touch a grammar ending staying wrong.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/spelling.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/spelling_lexicon.dart';
import 'package:lingora/data/vocab_practice.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnswerMatchKind kind(String input, String answer, {bool turkish = false, Set<String> lexicon = const {}}) =>
    matchAnswer(input, [answer], turkish: turkish, lexicon: lexicon).kind;

const exact = AnswerMatchKind.exact;
const typo = AnswerMatchKind.typo;
const wrong = AnswerMatchKind.wrong;

class _Speech implements SpeechService {
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async {}
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async {}
  @override
  Future<void> stopListening() async {}
}

class _NoNotifications implements NotificationService {
  @override
  void Function(String? payload)? get onTap => null;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> apply(List<PlannedNotification> plan) async {}
}

void main() {
  group('silent normalisation (no note)', () {
    test('case, spaces and end punctuation', () {
      expect(kind('  i AM a   teacher ', 'I am a teacher.'), exact);
      expect(kind('Good morning thanks', 'Good morning, thanks!'), exact);
      expect(kind('“Hello”…', 'Hello'), exact);
    });

    test('smart quotes and apostrophes', () {
      expect(kind('I’m here', "I'm here"), exact);
      expect(kind('It‘s ok', "It's ok"), exact);
      expect(kind("don`t go", "Don't go"), exact);
    });

    test('contractions equal their long forms', () {
      expect(kind('I am a student', "I'm a student"), exact);
      expect(kind("I'm a student", 'I am a student'), exact);
      expect(kind('do not go', "Don't go"), exact);
      expect(kind("They're late", 'They are late'), exact);
      expect(kind('We have finished', "We've finished"), exact);
      expect(kind('I can not swim', "I can't swim"), exact);
      expect(kind('I cannot swim', "I can't swim"), exact);
      expect(kind('She will not come', "She won't come"), exact);
      expect(kind("It's cold", 'It is cold'), exact);
    });

    test('a wrong answer stays wrong', () {
      expect(kind('Good night', 'Good morning'), wrong);
      expect(kind('', 'Hello'), wrong);
      expect(kind('I am teacher', 'I am a teacher'), wrong);
      expect(kind('I am a good teacher', 'I am a teacher'), wrong);
    });

    test('matchesAny (word banks) normalises but forgives no typo', () {
      expect(matchesAny("I’m a student", ['I am a student']), isTrue);
      expect(matchesAny('I am a teachet', ['I am a teacher']), isFalse);
    });
  });

  group('forgiven spelling slips', () {
    test('teacher / teachet', () {
      final m = matchAnswer('I am a teachet', ['I am a teacher.']);
      expect(m.kind, typo);
      expect(m.correct, isTrue);
      expect(m.fixes, [const SpellingFix('teachet', 'teacher')]);
      expect(m.expected, 'I am a teacher.');
    });

    test('receive / recieve: a swap is one edit', () {
      expect(damerauLevenshtein('recieve', 'receive'), 1);
      expect(kind('recieve', 'receive'), typo);
      expect(kind('I recieved a letter', 'I received a letter'), typo);
    });

    test('beautiful / beautifull', () {
      expect(kind('a beautifull day', 'a beautiful day'), typo);
    });

    test('long words take two slips, mid-length one', () {
      expect(kind('beautifl', 'beautiful'), typo); // 9 letters, 1 edit
      expect(kind('beutifull', 'beautiful'), typo); // 2 edits
      expect(kind('becuase', 'because'), typo); // 7 letters, a swap
      expect(kind('becuse', 'because'), typo);
      expect(kind('bcuse', 'because'), wrong); // 7 letters, 2 edits
      expect(kind('butifl', 'beautiful'), wrong); // 3 edits
    });

    test('allowance by word length', () {
      expect(typoAllowance(3), 0);
      expect(typoAllowance(4), 1);
      expect(typoAllowance(7), 1);
      expect(typoAllowance(8), 2);
    });

    test('the highlighted part is what differs', () {
      String marked(SpellingFix f) => f.parts.where((p) => p.mark).map((p) => p.text).join();
      expect(marked(const SpellingFix('teachet', 'teacher')), 'r');
      expect(const SpellingFix('teachet', 'teacher').parts.first.text, 'teache');
      expect(marked(const SpellingFix('recieve', 'receive')), 'ei');
      expect(marked(const SpellingFix('beautifull', 'beautiful')), 'beautiful');
    });
  });

  group('short words: no tolerance', () {
    test('1–3 letter words must be exact', () {
      expect(kind('I see the cta', 'I see the cat'), wrong);
      expect(kind('teh book', 'the book'), wrong);
      expect(kind('I am hppy', 'I am happy'), typo); // 5 letters
    });
  });

  group('a slip that makes another word is a mistake', () {
    final pairs = [
      ('their', 'there'),
      ('then', 'than'),
      ('live', 'life'),
      ('quite', 'quiet'),
      ('form', 'from'),
      ('were', 'where'),
      ('of', 'off'),
      ('a', 'an'),
      ('is', 'are'),
      ('is', 'was'),
      ('has', 'have'),
      ('its', "it's"),
    ];
    for (final (a, b) in pairs) {
      test('$a / $b', () {
        expect(kind('I like $a', 'I like $b'), wrong);
        expect(kind('I like $b', 'I like $a'), wrong);
      });
    }

    test('words from the course count too', () {
      expect(kind('a small cart', 'a small card'), typo);
      expect(kind('a small cart', 'a small card', lexicon: {'cart'}), wrong);
    });

    test('the lexicon is built from the course and the dictionary', () {
      final words = buildSpellingLexicon(
        course: Course(
          id: 't',
          title: 't',
          fromLang: 'tr',
          learningLang: 'en',
          units: [
            Unit(
              id: 'u',
              title: 'u',
              description: '',
              color: Brand.primary,
              nodes: [
                PathNode(
                  id: 'n',
                  type: NodeType.lesson,
                  title: 'n',
                  description: '',
                  rewardXp: 10,
                  exercises: const [
                    Exercise(
                      type: ExerciseType.listen,
                      text: 'The cart is red',
                      answers: ['The cart is red'],
                    ),
                    Exercise(type: ExerciseType.translate, text: 'Kart', lang: 'en', answers: ['Kartvizit']),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      expect(words, containsAll(['cart', 'red']));
      expect(words, isNot(contains('kartvizit')));
    });
  });

  group('grammar endings are not typos', () {
    test('-s, -es, -ed, -ing and plurals', () {
      expect(kind('She go to school', 'She goes to school'), wrong);
      expect(kind('She goe to school', 'She goes to school'), wrong);
      expect(kind('He work here', 'He works here'), wrong);
      expect(kind('I walk home', 'I walked home'), wrong);
      expect(kind('I walkd home', 'I walked home'), wrong);
      expect(kind('two book', 'two books'), wrong);
      expect(kind('two bookz', 'two books'), wrong);
      expect(kind('she studys', 'she studies'), wrong);
      expect(kind('I am play', 'I am playing'), wrong);
    });

    test('a slip before the ending is still forgiven', () {
      expect(kind('She recieves letters', 'She receives letters'), typo);
    });
  });

  group('the whole answer has a budget', () {
    test('a few slips are fine, many are not', () {
      expect(kind('My teachet is beautifull', 'My teacher is beautiful'), typo);
      expect(matchAnswer('My teachet is beautifull', ['My teacher is beautiful']).fixes, [
        const SpellingFix('teachet', 'teacher'),
        const SpellingFix('beautifull', 'beautiful'),
      ]);
      // Three slips in four words: over the budget of two.
      expect(kind('My teachet recieved beautifull', 'My teacher received beautiful'), wrong);
      expect(sentenceTypoBudget(4), 2);
      expect(sentenceTypoBudget(8), 3);
    });

    test('the closest accepted answer wins', () {
      final m = matchAnswer('I am a teachet', ['I am a doctor', 'I am a teacher']);
      expect(m.expected, 'I am a teacher');
      expect(matchAnswer('I am a teacher', ['I am a teachet', 'I am a teacher']).kind, exact);
    });
  });

  group('Turkish answers', () {
    test('missing Turkish letters count as correct, with a note', () {
      final m = matchAnswer('Bugun cok guzel bir gun', ['Bugün çok güzel bir gün.'], turkish: true);
      expect(m.kind, typo);
      expect(m.turkishLetters, isTrue);
      expect(m.fixes.map((f) => f.correct), ['bugün', 'çok', 'güzel', 'gün']);
      expect(kind('Isik', 'Işık', turkish: true), typo);
      expect(kind('Ogretmen', 'Öğretmen', turkish: true), typo);
      expect(kind('kus', 'kuş', turkish: true), typo); // short words too
      expect(kind('İstanbul', 'istanbul', turkish: true), exact);
    });

    test('other Turkish slips are not forgiven: a letter can be a suffix', () {
      expect(kind('Okula gitti', 'Okula gittim', turkish: true), wrong);
      expect(kind('Ogretmenn', 'Öğretmen', turkish: true), wrong);
    });
  });

  group('kelime tekrarı', () {
    final entry = VocabEntry.fromJson({
      'id': 'w1',
      'word': 'receive',
      'pos': 'verb',
      'rank': 1,
      'topic': 't',
      'senses': [
        {'tr': 'almak', 'def': 'to get'},
      ],
      'examples': <Object>[],
      'collocations': <Object>[],
    });
    VocabCard card({List<String> options = const []}) => VocabCard(
      type: VocabCardType.listenSpell,
      entry: entry,
      prompt: '',
      answer: 'receive',
      options: options,
    );

    test('typed cards forgive slips, choices do not', () {
      expect(card().match('recieve').kind, typo);
      expect(card().check('recieve'), isTrue);
      expect(card().check('receiver', lexicon: {'receiver'}), isFalse);
      expect(card(options: ['receive', 'recipe']).check('recieve'), isFalse);
      expect(card(options: ['receive', 'recipe']).check('receive'), isTrue);
    });

    test('a slip keeps the word in its box and brings it back tomorrow', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await SharedPreferences.getInstance())],
      );
      addTearDown(c.dispose);
      final n = c.read(progressProvider.notifier);
      n.reviewWord('w1', known: true);
      n.reviewWord('w1', known: true);
      expect(c.read(progressProvider).wordBox['w1'], 2);
      n.reviewWord('w1', known: true, weakSpelling: true);
      expect(c.read(progressProvider).wordBox['w1'], 2);
      n.reviewWord('w1', known: true);
      expect(c.read(progressProvider).wordBox['w1'], 3);
    });
  });

  group('dinle-yaz in a lesson', () {
    Future<(ProviderContainer, List<bool>)> pump(WidgetTester tester, String typed) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final answers = <bool>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            speechProvider.overrideWithValue(_Speech()),
            notificationServiceProvider.overrideWithValue(_NoNotifications()),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: LessonScreen(
              nodeId: 'yazim',
              title: 'Dinle',
              color: Brand.primary,
              items: const [
                (
                  key: 'yazim#0',
                  ex: Exercise(
                    type: ExerciseType.listen,
                    text: 'I am a teacher.',
                    answers: ['I am a teacher.'],
                  ),
                ),
              ],
              onAnswered: (_, correct) => answers.add(correct),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      return (ProviderScope.containerOf(tester.element(find.byType(MaterialApp))), answers);
    }

    testWidgets('a small slip is correct and shows the exact spelling', (tester) async {
      final (c, answers) = await pump(tester, 'I am a teachet');
      expect(answers, [true]);
      expect(find.byKey(const Key('spelling-note')), findsOneWidget);
      expect(find.textContaining('Küçük bir yazım hatası: teacher', findRichText: true), findsOneWidget);
      // No penalty, but the hata dedektörü notes the spelling.
      expect(c.read(progressProvider).errorStats[TrErrorCategory.spelling.name], 1);
      expect(c.read(progressProvider).mistakes, isEmpty);
    });

    testWidgets('an exact answer shows no note', (tester) async {
      final (c, answers) = await pump(tester, "I'm a teacher");
      expect(answers, [true]);
      expect(find.byKey(const Key('spelling-note')), findsNothing);
      expect(c.read(progressProvider).errorStats, isEmpty);
    });

    testWidgets('a slip that makes another word is wrong', (tester) async {
      final (_, answers) = await pump(tester, 'I am a teachers');
      expect(answers, [false]);
      expect(find.byKey(const Key('spelling-note')), findsNothing);
    });
  });
}
