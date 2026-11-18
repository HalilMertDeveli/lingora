// QA Premium regressions in the live chat / voice coach.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/screens/conversation_screen.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/speech.dart';

import 'ses_kocu_test.dart' show FakeChat, VoiceSpeech, chatApp, overrides;

/// A server answer the app cannot parse (e.g. a field of the wrong type).
class BrokenChat extends FakeChat {
  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    sent.add(List.of(history));
    throw TypeError();
  }
}

void main() {
  tearDown(() {
    lastRecognition.value = const [];
    speechIssue.value = null;
  });

  testWidgets('a malformed answer does not leave the chat stuck', (tester) async {
    final chat = BrokenChat();
    await tester.pumpWidget(chatApp(await overrides(tester, speech: VoiceSpeech(), chat: chat)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('to-text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-input')), 'A coffee please');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('Sunucu hatası. Biraz sonra tekrar dene.'), findsOneWidget);
    expect(find.text('A coffee please'), findsOneWidget, reason: 'the text is kept for a retry');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(chat.sent, hasLength(2), reason: 'send works again');
  });

  testWidgets('Bitir (tapped twice) counts the XP once', (tester) async {
    await tester.pumpWidget(
      chatApp(await overrides(tester, speech: VoiceSpeech(heard: [(words: 'Hello', confidence: 0.9)]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ConversationScreen)));
    final before = container.read(progressProvider).totalXp;

    await tester.tap(find.text('Bitir'));
    await tester.tap(find.text('Bitir'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(container.read(progressProvider).totalXp - before, conversationXp);
  });

  testWidgets('a denied microphone offers the settings and the text fallback', (tester) async {
    speechIssue.value = SpeechIssues.noMicPermission;
    await tester.pumpWidget(chatApp(await overrides(tester, speech: VoiceSpeech(ready: false))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-input')), findsOneWidget);
    expect(find.byKey(const Key('mic-settings')), findsOneWidget);
    expect(find.textContaining('Mikrofon izni kapalı'), findsOneWidget);
  });
}
