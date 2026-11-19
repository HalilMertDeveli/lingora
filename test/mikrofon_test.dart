import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/spoken_match.dart';
import 'package:lingora/exercises/common.dart' show Grader;
import 'package:lingora/exercises/hands_free.dart';
import 'package:lingora/exercises/speak_exercise.dart';
import 'package:lingora/exercises/speak_mic.dart';
import 'package:lingora/data/progress.dart' show prefsProvider;
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/pronunciation_screen.dart' show coachMatch;
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HandsFree extends HandsFreeSetting {
  _HandsFree(this.on);
  final bool on;
  @override
  bool build() => on;
}

/// Speech recognition driven by the test: words arrive when the test says.
class _LiveSpeech implements SpeechService {
  _LiveSpeech({this.mic = true});
  final bool mic;
  final said = <String>[];
  int listens = 0;
  int stops = 0;
  void Function(String)? _onWords;
  void Function()? _onDone;

  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async =>
      said.add(text);
  @override
  Future<bool> get canListen async => mic;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async {
    listens++;
    _onWords = onWords;
    _onDone = onDone;
  }

  void words(String w) => _onWords?.call(w);
  void done() {
    final d = _onDone;
    _onDone = null;
    d?.call();
  }

  @override
  Future<void> stopListening() async {
    stops++;
    done();
  }
}

Future<void> _pump(
  WidgetTester tester,
  SpeechService speech, {
  String text = 'I am twenty one years old.',
  void Function(Grader?)? onReady,
  VoidCallback? onSkip,
  bool handsFree = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speechProvider.overrideWithValue(speech),
        handsFreeProvider.overrideWith(() => _HandsFree(handsFree)),
        premiumProvider.overrideWithValue(false),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpeakExercise(
              ex: Exercise(type: ExerciseType.speak, text: text),
              locked: false,
              onReady: (check) => onReady?.call(check),
              onSkip: onSkip ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _say(WidgetTester tester, _LiveSpeech speech, String words) async {
  await tester.tap(find.byIcon(Icons.mic_rounded));
  await tester.pump();
  speech.words(words);
  await tester.pump();
  speech.done();
  await tester.pump();
}

void main() {
  setUp(() {
    speechIssue.value = null;
    speechLevel.value = 0;
  });

  group('spoken matcher', () {
    test('case, punctuation and contractions are not mistakes', () {
      final m = matchSpoken("I'm fine, thank you!", ['i am fine thank you']);
      expect(m.perfect, isTrue);
      expect(matchSpoken("I don't know.", ['I do not know']).perfect, isTrue);
      expect(matchSpoken('It is late', ["it's late"]).perfect, isTrue);
    });

    test('digits are the same as number words', () {
      expect(matchSpoken('I have two cats', ['I have 2 cats']).perfect, isTrue);
      expect(matchSpoken('She is twenty-one', ['she is 21']).perfect, isTrue);
      expect(matchSpoken('The train leaves at 7:30', ['the train leaves at seven thirty']).perfect, isTrue);
      expect(matchSpoken('It is my 3rd day', ['it is my third day']).perfect, isTrue);
      expect(matchSpoken('I was born in 1990', ['I was born in nineteen ninety']).perfect, isTrue);
      expect(numberWords(2005), ['two', 'thousand', 'five']);
      expect(numberWords(115), ['one', 'hundred', 'fifteen']);
    });

    test('homophones and spelling variants count', () {
      expect(matchSpoken('I want to go too', ['I want two go to']).perfect, isTrue);
      expect(matchSpoken('Write your name', ['right your name']).perfect, isTrue);
      expect(matchSpoken('What colour is it', ['what color is it']).perfect, isTrue);
    });

    test('a Turkish accent is forgiven in sentences', () {
      expect(matchSpoken('I think it is very good', ['I tink it is wery good']).perfect, isTrue);
      expect(matchSpoken('This is the weather', ['dis is de wether']).matched, greaterThanOrEqualTo(3));
    });

    test('about 80%: one missing word in a short sentence still passes', () {
      final m = matchSpoken('I would like a cup of tea', ['I would like cup of tea']);
      expect(m.missed, 1);
      expect(m.passed, isTrue);
      expect(m.words.where((w) => !w.heard).map((w) => w.text), ['a']);

      final two = matchSpoken('I would like a cup of tea', ['I like cup of tea']);
      expect(two.passed, isFalse);
      expect(two.words.where((w) => !w.heard).map((w) => w.text), ['would', 'a']);
    });

    test('one or two words must all be heard', () {
      expect(matchSpoken('Good morning', ['good']).passed, isFalse);
      expect(matchSpoken('Good morning', ['good morning']).passed, isTrue);
      expect(allowedMisses(10), 2);
      expect(allowedMisses(5), 1);
      expect(allowedMisses(2), 0);
    });

    test('word order and extra words', () {
      // Fillers and a restarted sentence do not hurt.
      expect(matchSpoken('Where is the station', ['um where where is the uh station']).perfect, isTrue);
      // Words out of order are not all heard in order.
      expect(matchSpoken('Where is the station', ['the station is where']).perfect, isFalse);
    });

    test('a different word is still a miss', () {
      final m = matchSpoken('I like apples', ['I like bananas']);
      expect(m.words.last, (text: 'apples', heard: false));
      expect(m.passed, isTrue, reason: 'one slip in three words');
      expect(matchSpoken('I like apples', ['you hate bananas']).passed, isFalse);
    });

    test('the best of the alternatives wins', () {
      final m = matchSpoken('I need a taxi', ['I need attacks he', 'I need a taxi', 'eye knee a taxi']);
      expect(m.heard, 'I need a taxi');
      expect(m.perfect, isTrue);
      expect(bestTranscription('I need a taxi', ['I need attacks he', 'I need a taxi']), 'I need a taxi');
      expect(bestTranscription(null, ['first', 'second']), 'first');
      expect(bestTranscription('anything', []), '');
    });

    test('nothing heard', () {
      final m = matchSpoken('Hello there', ['', '  ']);
      expect(m.heard, '');
      expect(m.passed, isFalse);
      expect(m.words.map((w) => w.heard), [false, false]);
    });

    test('the pronunciation coach stays strict about the sound it teaches', () {
      expect(coachMatch('three', 'tree').perfect, isFalse);
      expect(coachMatch('sheep', 'ship').perfect, isFalse);
      expect(coachMatch("I'm three", 'I am 3').perfect, isTrue);
    });

    test('sound key', () {
      expect(soundKey('think'), soundKey('tink'));
      expect(soundKey('very'), soundKey('wery'));
      expect(soundKey('phone'), soundKey('fone'));
      expect(soundKey('cat'), isNot(soundKey('dog')));
    });
  });

  group('listening setup', () {
    test('longer sentences wait longer', () {
      final short = listenTimes(2), long = listenTimes(14);
      expect(short.pause, const Duration(seconds: 4));
      expect(long.pause, greaterThan(short.pause));
      expect(long.pause, lessThanOrEqualTo(const Duration(seconds: 7)));
      expect(long.total, greaterThan(short.total));
    });

    test('English locale: wanted, then US/GB, then any English', () {
      expect(pickEnglishLocale('en-US', ['tr_TR', 'en_US', 'en_GB']), 'en_US');
      expect(pickEnglishLocale('en-US', ['tr-TR', 'en-GB']), 'en-GB');
      expect(pickEnglishLocale('en-GB', ['en_AU', 'en_IN']), 'en_AU');
      expect(pickEnglishLocale('en-US', ['tr_TR', 'de_DE']), isNull, reason: 'no English pack');
      expect(pickEnglishLocale('en-US', []), 'en_US', reason: 'unknown list: try anyway');
    });

    test('sound level is 0..1', () {
      expect(normalizeSoundLevel(-10), 0);
      expect(normalizeSoundLevel(4), closeTo(0.5, 0.01));
      expect(normalizeSoundLevel(20), 1);
    });

    test('a missing English pack points to the Google app voice settings', () {
      expect(SpeechIssues.noEnglishRecognizer, contains('Google'));
      expect(SpeechIssues.noEnglishRecognizer, contains('English'));
      expect(SpeechIssues.notHeard, contains('yakın'));
    });
  });

  group('speak exercise', () {
    testWidgets('shows words live while listening and the level ring', (tester) async {
      final speech = _LiveSpeech();
      await _pump(tester, speech);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(find.text('Dinliyorum… Şimdi söyle.'), findsOneWidget);
      expect(find.byKey(const Key('mic-level')), findsOneWidget);

      speechLevel.value = 0.8;
      speech.words('I am');
      await tester.pump();
      expect(find.text('“I am”'), findsOneWidget);
      speech.words("I'm 21 years");
      await tester.pump();
      expect(find.text('“I\'m 21 years”'), findsOneWidget);
      speech.done();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mic-level')), findsNothing);
    });

    testWidgets('accepts a contraction, digits and a missing word; shows the missed word in red', (
      tester,
    ) async {
      final speech = _LiveSpeech();
      Grader? grader;
      await _pump(tester, speech, onReady: (g) => grader = g);
      await _say(tester, speech, "I'm 21 old");
      expect(grader, isNotNull);
      expect(grader!(), isTrue);
      final missed = tester.widget<Text>(find.byKey(const ValueKey('missed-years')));
      expect(missed.style?.color, Brand.error);
      expect(find.textContaining('Güzel'), findsOneWidget);
    });

    testWidgets('after two failed tries the skip is offered up front', (tester) async {
      final speech = _LiveSpeech();
      var skipped = false;
      await _pump(tester, speech, onSkip: () => skipped = true);
      expect(find.byKey(const Key('speak-skip-offer')), findsNothing);
      expect(find.text('Şu an konuşamıyorum'), findsOneWidget);

      await _say(tester, speech, 'hello');
      expect(find.byKey(const Key('speak-skip-offer')), findsNothing);
      await _say(tester, speech, '');
      expect(find.text(SpeechIssues.notHeard), findsOneWidget, reason: 'nothing heard: get closer');
      expect(find.byKey(const Key('speak-skip-offer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('speak-skip-offer')));
      expect(skipped, isTrue);
    });

    testWidgets('a good try does not count as a failure', (tester) async {
      final speech = _LiveSpeech();
      await _pump(tester, speech, text: 'Good morning');
      await _say(tester, speech, 'good morning');
      await _say(tester, speech, 'good morning');
      await _say(tester, speech, 'good morning');
      expect(find.byKey(const Key('speak-skip-offer')), findsNothing);
      expect(find.text('Harika, hepsini duydum!'), findsOneWidget);
    });

    group('hands-free', () {
      setUp(() => handsFreeMicRefused = false);

      testWidgets('reads the sentence, listens by itself and ends after the silence', (tester) async {
        final speech = _LiveSpeech();
        Grader? grader;
        await _pump(tester, speech, text: 'Good morning', handsFree: true, onReady: (g) => grader = g);
        await tester.pump();
        expect(speech.said, ['Good morning'], reason: 'the prompt plays before listening');
        expect(speech.listens, 1);
        expect(find.byKey(const Key('hands-free-listening')), findsOneWidget);
        speech.words('good');
        await tester.pump(const Duration(milliseconds: 600));
        speech.words('good morning');
        await tester.pump(const Duration(milliseconds: 600));
        expect(speech.stops, 0, reason: 'still talking: the silence timer restarted');
        await tester.pump(endOfSpeechSilence);
        expect(speech.stops, 1);
        await tester.pump();
        expect(grader, isNotNull);
        expect(grader!(), isTrue);
        expect(find.byKey(const Key('hands-free-listening')), findsNothing);
      });

      testWidgets('no speech: a gentle hint and one retry, the skip stays', (tester) async {
        final speech = _LiveSpeech();
        await _pump(tester, speech, handsFree: true);
        await tester.pump();
        await tester.pump(noSpeechTimeout);
        await tester.pump();
        expect(find.byKey(const Key('hands-free-no-speech')), findsOneWidget);
        expect(find.text('Şu an konuşamıyorum'), findsOneWidget);
        await tester.tap(find.byKey(const Key('hands-free-retry')));
        await tester.pump();
        expect(speech.listens, 2);
        expect(find.byKey(const Key('hands-free-no-speech')), findsNothing);
        expect(find.byKey(const Key('hands-free-listening')), findsOneWidget);
        speech.done();
        await tester.pumpAndSettle();
      });

      testWidgets('no microphone: the button flow stays and nothing listens', (tester) async {
        final speech = _LiveSpeech(mic: false);
        await _pump(tester, speech, handsFree: true);
        await tester.pump();
        expect(speech.listens, 0);
        expect(find.byKey(const Key('hands-free-listening')), findsNothing);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      });

      testWidgets('a manual tap still works and also ends by itself', (tester) async {
        final speech = _LiveSpeech(mic: false);
        await _pump(tester, speech, text: 'Good morning', handsFree: true);
        await tester.pump();
        expect(handsFreeMicRefused, isTrue);
        await tester.pumpWidget(const SizedBox());
        final live = _LiveSpeech();
        await _pump(tester, live, text: 'Good morning', handsFree: true);
        await tester.pump();
        expect(live.listens, 0, reason: 'refused once this run: no new automatic tries');
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();
        expect(live.listens, 1);
        live.words('good morning');
        await tester.pump(endOfSpeechSilence);
        await tester.pump();
        expect(find.text('Harika, hepsini duydum!'), findsOneWidget);
      });
    });

    testWidgets('SpokenWordsView marks heard words green', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SpokenWordsView(match: matchSpoken('See you soon', ['see you']))),
        ),
      );
      expect(tester.widget<Text>(find.text('See')).style?.color, Brand.success);
      expect(find.byKey(const ValueKey('missed-soon')), findsOneWidget);
    });
  });
}
