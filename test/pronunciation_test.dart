import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/pronunciation.dart';
import 'package:lingora/screens/pronunciation_screen.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSpeech implements SpeechService {
  final said = <String>[];
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false}) async => said.add(text);
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async =>
      onDone();
  @override
  Future<void> stopListening() async {}
}

List<PronUnit> readUnits() => parsePronUnits(File('assets/pronunciation/units.json').readAsStringSync());

void main() {
  group('pronunciation content', () {
    final units = readUnits();

    test('has about ten units with unique ids', () {
      expect(units.length, greaterThanOrEqualTo(10));
      expect(units.map((u) => u.id).toSet(), hasLength(units.length));
    });

    test('every unit is complete', () {
      for (final u in units) {
        expect(u.title.trim(), isNotEmpty, reason: u.id);
        expect(u.sound.trim(), isNotEmpty, reason: u.id);
        expect(u.summary.trim(), isNotEmpty, reason: u.id);
        expect(u.how, isNotEmpty, reason: u.id);
        expect(u.turkish.trim(), isNotEmpty, reason: u.id);
        expect(u.mistake.trim(), isNotEmpty, reason: u.id);
        expect(u.pairs.length, greaterThanOrEqualTo(4), reason: u.id);
        expect(u.sentences.length, greaterThanOrEqualTo(2), reason: u.id);
        for (final s in u.sentences) {
          expect(s.en.trim(), isNotEmpty, reason: u.id);
          expect(s.tr.trim(), isNotEmpty, reason: u.id);
        }
      }
    });

    test('every pair has two different words with meanings', () {
      for (final u in units) {
        for (final p in u.pairs) {
          expect(p.a.trim(), isNotEmpty, reason: u.id);
          expect(p.b.trim(), isNotEmpty, reason: u.id);
          expect(normalizeAnswer(p.a), isNot(normalizeAnswer(p.b)), reason: '${u.id}: ${p.a}/${p.b}');
          expect(p.aTr.trim(), isNotEmpty, reason: '${u.id}: ${p.a}');
          expect(p.bTr.trim(), isNotEmpty, reason: '${u.id}: ${p.b}');
        }
      }
    });
  });

  group('speak feedback', () {
    const pair = MinimalPair(a: 'think', aTr: '', b: 'sink', bTr: '');
    test('praises an exact match', () {
      expect(speakFeedback(target: 'think', heard: 'Think', pair: pair), startsWith('Harika'));
    });
    test('names the partner word when that is what was heard', () {
      expect(speakFeedback(target: 'think', heard: 'sink', pair: pair), contains('“sink” gibi'));
    });
    test('handles silence and near misses kindly', () {
      expect(speakFeedback(target: 'think', heard: ''), contains('duyamadım'));
      expect(
        speakFeedback(target: 'I think three is enough', heard: 'I think tree is enough'),
        contains('neredeyse'),
      );
      expect(speakFeedback(target: 'think', heard: 'pink'), contains('“pink”'));
    });
  });

  testWidgets('opens a unit, answers listening drills and finishes without a mic', (tester) async {
    SharedPreferences.setMockInitialValues({'progress_v1': '{"onboarded": true}'});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final speech = FakeSpeech();
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        speechProvider.overrideWithValue(speech),
        pronUnitsProvider.overrideWith((ref) async => readUnits()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(), home: const PronunciationScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sert th: think'));
    await tester.pumpAndSettle();
    expect(find.text('Nasıl söylenir?'), findsOneWidget);

    await tester.tap(find.text('ALIŞTIRMAYA BAŞLA'));
    await tester.pumpAndSettle();
    expect(find.text('Hangisini duydun?'), findsOneWidget);

    // First drill: pick the word the coach said.
    final heard = speech.said.last;
    expect(['think', 'sink'], contains(heard));
    await tester.tap(find.text(heard));
    await tester.pumpAndSettle();
    expect(find.textContaining('Doğru!'), findsOneWidget);
    await tester.tap(find.text('DEVAM'));
    await tester.pumpAndSettle();

    // Second drill: pick the wrong word; no punishment, just a gentle replay.
    final target = speech.said.last;
    await tester.tap(find.text(target == 'thank' ? 'tank' : 'thank'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bu sefer “$target” dedim'), findsOneWidget);
    await tester.tap(find.text('DEVAM'));
    await tester.pumpAndSettle();

    // Remaining listening drills.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(speech.said.last));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEVAM'));
      await tester.pumpAndSettle();
    }

    // Speaking drills: the fake has no microphone, so the step can be skipped.
    expect(find.text('Söyle'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Mikrofon kullanılamıyor'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('DEVAM'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('BİTİR'));
    await tester.pumpAndSettle();

    expect(container.read(progressProvider).isDone('pron_th_voiceless'), isTrue);
    expect(container.read(progressProvider).totalXp, 10 + 5);
    // Let the result screen's delayed animations finish.
    await tester.pump(const Duration(seconds: 10));
  });
}
