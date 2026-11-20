// Sesli Konuşma Koçu: voice mode with a text fallback, the free daily taste,
// on-device pronunciation evidence and the end-of-conversation karne.
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/speech_evidence.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/models/pronunciation.dart';
import 'package:lingora/screens/conversation_report_screen.dart';
import 'package:lingora/screens/conversation_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/screens/pronunciation_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/speech.dart';

import 'premium_test.dart' show FakeBilling, now, prefsWith;

/// A microphone that "hears" [heard] (the recognizer's guesses, favourite first).
///
/// Hands-free: the screens listen by themselves, so [heard] is said once
/// (later turns hear silence). With [manual] the learner only speaks when
/// the test calls [talk].
class VoiceSpeech implements SpeechService {
  VoiceSpeech({this.heard = const [], this.ready = true, this.manual = false});
  List<SpeechGuess> heard;
  final bool ready;
  final bool manual;
  final said = <String>[];
  int listens = 0;
  void Function(String)? _words;
  void Function()? _done;

  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async =>
      said.add(text);
  @override
  Future<bool> get canListen async => ready;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async {
    listens++;
    lastRecognition.value = const [];
    if (manual) {
      _words = onWords;
      _done = onDone;
      return;
    }
    _deliver(onWords, onDone);
  }

  void _deliver(void Function(String) onWords, void Function() onDone) {
    final h = heard;
    heard = const [];
    if (h.isNotEmpty) onWords(h.first.words);
    lastRecognition.value = h;
    onDone();
  }

  /// [manual]: the learner says [heard] now (in the open listening turn).
  void talk() {
    final w = _words, d = _done;
    _words = null;
    _done = null;
    if (w != null && d != null) _deliver(w, d);
  }

  @override
  Future<void> stopListening() async {
    final d = _done;
    _words = null;
    _done = null;
    d?.call();
  }
}

class FakeChat implements ConversationService {
  FakeChat({this.turn = const ChatTurn(reply: 'Lovely. Anything to eat?'), this.error});
  final ChatTurn turn;
  final ConversationException? error;
  final sent = <List<ChatMessage>>[];

  @override
  bool get isLive => true;
  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    sent.add(List.of(history));
    if (error case final e?) throw e;
    return turn;
  }
}

class FakeReport implements ConversationReportService {
  List<ChatMessage>? got;
  @override
  Future<ConversationReport> report(Scenario scenario, List<ChatMessage> history) async {
    got = history;
    return const ConversationReport(
      mistakes: [
        ReportMistake(
          original: 'I want three coffee.',
          corrected: "I'd like three coffees, please.",
          explanationTr: 'Birden fazla şey için çoğul -s gerekir.',
        ),
      ],
      summaryTr: 'Siparişini verdin. Çoğul ekine dikkat.',
      weakWords: [WeakWordEvidence(word: 'three', heard: 'tree', confidence: 0.41)],
    );
  }
}

Future<List<Override>> overrides(
  WidgetTester tester, {
  required SpeechService speech,
  ConversationService? chat,
  ConversationReportService? report,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  return [
    prefsProvider.overrideWithValue(await prefsWith({})),
    clockProvider.overrideWithValue(() => now),
    billingServiceProvider.overrideWithValue(FakeBilling()),
    premiumDevOverrideProvider.overrideWithValue(false),
    speechProvider.overrideWithValue(speech),
    conversationServiceProvider.overrideWithValue(chat ?? FakeChat()),
    conversationReportServiceProvider.overrideWithValue(report ?? FakeReport()),
  ];
}

Widget chatApp(List<Override> o, {String id = 'cafe'}) => ProviderScope(
  overrides: o,
  child: MaterialApp(home: ConversationScreen(scenario: scenarioById(id))),
);

void main() {
  tearDown(() => lastRecognition.value = const []);

  group('speech evidence', () {
    test('a word the learner fixed by hand is misheard', () {
      expect(speechEvidence([(words: 'I have tree brothers', confidence: 0.52)], 'I have three brothers.'), [
        const WeakWordEvidence(word: 'three', heard: 'tree', confidence: 0.52),
      ]);
    });

    test('a word the recognizer hesitated on is unsure', () {
      final e = speechEvidence([
        (words: "I'd like a coffee", confidence: 0.7),
        (words: "I'd like a copy", confidence: null),
      ], "I'd like a coffee");
      expect(e, [const WeakWordEvidence(word: 'coffee', confidence: 0.7)]);
    });

    test('no evidence without speech, for short words, or for a rewritten sentence', () {
      expect(speechEvidence(const [], 'Hello'), isEmpty);
      expect(speechEvidence([(words: 'I want a tea', confidence: 0.9)], 'I want the tea'), isEmpty);
      expect(
        speechEvidence([(words: 'hello there', confidence: 0.3)], 'Can I get a taxi to the airport'),
        isEmpty,
      );
      expect(speechEvidence([(words: 'I want tea', confidence: 0.95)], 'I want tea'), isEmpty);
    });

    test('collectEvidence keeps one entry per word, misheard and least sure first', () {
      final history = [
        const ChatMessage(
          fromUser: false,
          text: 'Hi',
          evidence: [WeakWordEvidence(word: 'hi')],
        ),
        const ChatMessage(
          fromUser: true,
          text: 'a',
          evidence: [
            WeakWordEvidence(word: 'coffee', confidence: 0.8),
            WeakWordEvidence(word: 'three', confidence: 0.6),
          ],
        ),
        const ChatMessage(
          fromUser: true,
          text: 'b',
          evidence: [
            WeakWordEvidence(word: 'coffee', confidence: 0.3),
            WeakWordEvidence(word: 'water', heard: 'waiter'),
          ],
        ),
      ];
      expect(collectEvidence(history).map((e) => e.word), ['water', 'coffee', 'three']);
      expect(collectEvidence(history).firstWhere((e) => e.word == 'coffee').confidence, 0.3);
      expect(collectEvidence(history, max: 1), hasLength(1));
    });
  });

  group('callables', () {
    test('free_quota from the server is a free-taste error, remaining/free are read', () async {
      final quota = CallableConversationService(
        (name, data) async =>
            throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'free_quota'),
      );
      await expectLater(
        quota.send(scenarios.first, const [ChatMessage(fromUser: true, text: 'hi')]),
        throwsA(isA<ConversationException>().having((e) => e.freeQuotaUsed, 'freeQuotaUsed', isTrue)),
      );
      final daily = CallableConversationService(
        (name, data) async =>
            throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'daily_quota'),
      );
      await expectLater(
        daily.send(scenarios.first, const [ChatMessage(fromUser: true, text: 'hi')]),
        throwsA(isA<ConversationException>().having((e) => e.freeQuotaUsed, 'freeQuotaUsed', isFalse)),
      );
      final ok = CallableConversationService(
        (name, data) async => {
          'reply': 'Hi',
          'correction': '',
          'tip_tr': '',
          'done': false,
          'remaining': 2,
          'free': true,
        },
      );
      final t = await ok.send(scenarios.first, const [ChatMessage(fromUser: true, text: 'hi')]);
      expect((t.remaining, t.free, t.correction), (2, true, null));
    });

    test('the report callable sends the pronunciation evidence and reads the karne', () async {
      Map<String, Object?>? sent;
      final service = CallableConversationReportService((name, data) async {
        expect(name, 'conversationReport');
        sent = data;
        return {
          'mistakes': [
            {
              'original': 'How much it is?',
              'corrected': 'How much is it?',
              'explanation_tr': 'Soruda is öne gelir.',
            },
          ],
          'summary_tr': 'İyi gitti.',
          'weak_words': [
            {'word': 'three', 'heard': 'tree', 'confidence': 0.4},
          ],
          'remaining': 9,
        };
      });
      final r = await service.report(scenarios.first, const [
        ChatMessage(fromUser: false, text: 'Hi'),
        ChatMessage(
          fromUser: true,
          text: 'three teas',
          spoken: true,
          evidence: [WeakWordEvidence(word: 'three', heard: 'tree', confidence: 0.4)],
        ),
      ]);
      expect(sent!['pronunciation'], [
        {'word': 'three', 'heard': 'tree', 'confidence': 0.4},
      ]);
      expect(r.mistakes.single.corrected, 'How much is it?');
      expect(r.weakWords.single, const WeakWordEvidence(word: 'three', heard: 'tree', confidence: 0.4));
    });

    test('the demo karne lists the chat corrections and the evidence', () async {
      final r = await DemoConversationReportService().report(scenarios.first, const [
        ChatMessage(fromUser: true, text: 'I am agree', correction: 'I agree', tipTr: 'agree fiildir'),
        ChatMessage(
          fromUser: true,
          text: 'ok',
          evidence: [WeakWordEvidence(word: 'coffee')],
        ),
      ]);
      expect(r.mistakes.single.corrected, 'I agree');
      expect(r.weakWords.single.word, 'coffee');
    });
  });

  group('voice chat', () {
    testWidgets('speak: the message goes by itself, the reply is shown and spoken', (tester) async {
      final speech = VoiceSpeech(
        heard: [(words: "I'd like a coffee", confidence: 0.7), (words: "I'd like a copy", confidence: 0.2)],
      );
      final chat = FakeChat();
      await tester.pumpWidget(chatApp(await overrides(tester, speech: speech, chat: chat)));
      await tester.pumpAndSettle();
      expect(speech.said.first, scenarioById('cafe').opening, reason: 'the opening is read aloud');
      // No microphone button: the microphone opened by itself after the opening.
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byKey(const Key('chat-input')), findsNothing);
      expect(chat.sent, hasLength(1));
      final mine = chat.sent.single.last;
      expect((mine.text, mine.fromUser, mine.spoken), ("I'd like a coffee", true, true));
      expect(mine.evidence.map((e) => e.word), ['coffee']);
      expect(find.text("I'd like a coffee"), findsOneWidget);
      expect(find.text('Lovely. Anything to eat?'), findsOneWidget);
      expect(speech.said.last, 'Lovely. Anything to eat?');
    });

    testWidgets('text fallback: type and send; back to voice listens by itself', (tester) async {
      final speech = VoiceSpeech(heard: [(words: 'I have tree brothers', confidence: 0.5)], manual: true);
      final chat = FakeChat();
      await tester.pumpWidget(chatApp(await overrides(tester, speech: speech, chat: chat)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('to-text')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('chat-input')), 'Hello, a table for two please');
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pumpAndSettle();
      expect(chat.sent.last.last.spoken, isFalse);
      expect(chat.sent.last.last.evidence, isEmpty);

      expect(find.byIcon(Icons.mic_rounded), findsNothing, reason: 'no dictation button');
      final before = speech.listens;
      await tester.tap(find.byKey(const Key('to-voice')));
      await tester.pump();
      await tester.pump();
      expect(speech.listens, before + 1, reason: 'listening opens by itself');
      speech.talk();
      await tester.pumpAndSettle();
      expect(chat.sent, hasLength(2));
      expect(chat.sent.last.last.spoken, isTrue);
    });

    testWidgets('no microphone: falls back to typing', (tester) async {
      await tester.pumpWidget(chatApp(await overrides(tester, speech: VoiceSpeech(ready: false))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
      expect(find.text('Mikrofon kullanılamıyor; yazarak devam edebilirsin.'), findsOneWidget);
    });

    testWidgets('free taste: shows what is left, then the paywall with the tutor line', (tester) async {
      final speech = VoiceSpeech(heard: [(words: 'Hello', confidence: 0.9)]);
      final o = await overrides(
        tester,
        speech: speech,
        chat: FakeChat(turn: const ChatTurn(reply: 'Hi!', remaining: 2, free: true)),
      );
      await tester.pumpWidget(chatApp(o));
      await tester.pumpAndSettle();
      expect(find.text('Ücretsiz: bugün 2 mesajın kaldı'), findsOneWidget);

      final o2 = await overrides(
        tester,
        speech: VoiceSpeech(heard: [(words: 'Hello', confidence: 0.9)]),
        chat: FakeChat(
          error: const ConversationException(
            CallableConversationService.freeQuotaMessage,
            code: ConversationException.freeQuotaCode,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox()); // a new chat, not the same screen
      await tester.pumpWidget(chatApp(o2, id: 'hotel_reception'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(freeTastePitch), findsOneWidget);
      expect(find.text('Sesli konuşma koçu + konuşma karnesi'), findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.textContaining('karneni alabilirsin'), findsOneWidget);
    });
  });

  group('karne', () {
    testWidgets('Bitir opens the karne; weak words open the telaffuz koçu', (tester) async {
      final speech = VoiceSpeech(heard: [(words: 'I want three coffee', confidence: 0.4)]);
      final report = FakeReport();
      await tester.pumpWidget(chatApp(await overrides(tester, speech: speech, report: report)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bitir'));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationReportScreen), findsOneWidget);
      expect(report.got!.where((m) => m.fromUser).single.spoken, isTrue);
      expect(find.text('1 mesaj · 1 sesli · 1 düzeltme'), findsOneWidget);
      expect(find.text("I'd like three coffees, please."), findsOneWidget);
      expect(find.text('Birden fazla şey için çoğul -s gerekir.'), findsOneWidget);
      expect(find.text('three'), findsOneWidget);
      expect(find.textContaining('“tree” olarak anlaşıldı'), findsOneWidget);
      expect(find.textContaining('güven %41'), findsOneWidget);

      // Saying it: the drill reads the word, then listens by itself.
      speech.heard = [(words: 'three', confidence: 0.9)];
      await tester.tap(find.byKey(const Key('practise-all')));
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationWordsScreen), findsOneWidget);
      expect(find.byKey(const Key('drill-word')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('drill-word'))).data, 'three');
      expect(speech.said.last, 'three');
      expect(find.byKey(const Key('drill-unit')), findsOneWidget, reason: 'three is in the th unit');
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.text('Harika! Çok net anlaşıldı.'), findsOneWidget);
    });

    testWidgets('typed-only chat: the karne says why no words are listed', (tester) async {
      final report = _EmptyReport();
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, speech: VoiceSpeech(), report: report),
          child: MaterialApp(
            home: ConversationReportScreen(
              scenario: scenarioById('interview'),
              history: const [ChatMessage(fromUser: true, text: 'I am a developer.')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-weak-words')), findsOneWidget);
      expect(find.textContaining('sesli konuşmadın'), findsOneWidget);
      expect(find.byKey(const Key('practise-all')), findsNothing);
    });
  });

  test('unitForWord picks the telaffuz koçu unit for a word', () {
    final units = parsePronUnits(File('assets/pronunciation/units.json').readAsStringSync());
    expect(unitForWord('think', units)?.id, 'th_voiceless');
    expect(unitForWord('three', units)?.id, 'th_voiceless');
    expect(unitForWord('they', units)?.id, 'th_voiced');
    expect(unitForWord('Wednesday', units)?.id, isNotNull);
    expect(unitForWord('xyz', units), isNull);

    // A word used in a unit's sentences (as a whole word) picks that unit.
    PronUnit unit(String id, String sentence) => PronUnit(
      id: id,
      emoji: '',
      title: id,
      sound: '',
      summary: '',
      how: const [],
      turkish: '',
      mistake: '',
      pairs: const [],
      sentences: [PronSentence(sentence, '')],
    );
    final synthetic = [unit('a', 'Unpleasant days.'), unit('b', 'Please sit down.')];
    expect(unitForWord('please', synthetic)?.id, 'b');
    expect(unitForWord('Pleas', synthetic), isNull);
  });

  test('voice coach roles exist on both sides', () {
    final server = File('functions/src/scenarios.ts').readAsStringSync();
    for (final id in ['cafe', 'interview', 'hotel_reception']) {
      expect(scenarioById(id).id, id);
      expect(server, contains('$id: {'));
    }
    expect(RegExp('persona:').allMatches(server).length, greaterThanOrEqualTo(3));
  });
}

class _EmptyReport implements ConversationReportService {
  @override
  Future<ConversationReport> report(Scenario scenario, List<ChatMessage> history) async =>
      const ConversationReport(mistakes: [], summaryTr: '', weakWords: []);
}
