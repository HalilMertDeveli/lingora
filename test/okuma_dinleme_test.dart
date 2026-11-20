import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/reading_repository.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/models/reading.dart';
import 'package:lingora/screens/daily_reading_screen.dart';
import 'package:lingora/screens/reading_screen.dart';
import 'package:lingora/services/read_aloud.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'buyume_kampanya_test.dart' show FakeDailySource, overrides, reading;
import 'premium_test.dart' show FakeSpeech;

/// Records the lines; with [hold] each line waits until [release]d, like a
/// real voice that takes a while to speak.
class _Lines implements LinePlayer {
  @override
  Future<void> sayBeforeListening(String text, {double rate = 1}) => sayLine(text, rate: rate);

  _Lines({this.hold = false});
  final bool hold;
  final played = <(String, double)>[];
  int stops = 0;
  Completer<void>? _line;

  @override
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1}) {
    played.add((text, rate));
    if (!hold) return Future.value();
    return (_line = Completer<void>()).future;
  }

  void release() {
    final line = _line;
    if (line != null && !line.isCompleted) line.complete();
  }

  @override
  Future<void> stopLine() async {
    stops++;
    release();
  }
}

final _stories = parseStories(File('assets/reading/stories.json').readAsStringSync());

void main() {
  test('splitSentences splits after . ! ? and closing quotes', () {
    expect(
      splitSentences(
        'One rainy morning a neighbour found it.\n\nShe gave it back! Why? "Hello," he said. "Thanks."',
      ),
      [
        'One rainy morning a neighbour found it.',
        'She gave it back!',
        'Why?',
        '"Hello," he said.',
        '"Thanks."',
      ],
    );
    expect(splitSentences('  '), isEmpty);
  });

  group('ReadAloud', () {
    test('reads every sentence in order, waiting for each, then reports the end', () async {
      final lines = _Lines(hold: true);
      final seen = <int?>[];
      final aloud = ReadAloud(lines, onSentence: seen.add);
      final done = aloud.play(['A.', 'B.', 'C.']);
      await Future<void>.delayed(Duration.zero);
      expect(lines.played.map((l) => l.$1), ['A.']);
      expect(aloud.playing, isTrue);
      lines.release();
      await Future<void>.delayed(Duration.zero);
      expect(lines.played.map((l) => l.$1), ['A.', 'B.']);
      lines.release();
      await Future<void>.delayed(Duration.zero);
      lines.release();
      await done;
      expect(seen, [0, 1, 2, null]);
      expect(aloud.playing, isFalse);
    });

    test('stop silences the voice and ends the reading', () async {
      final lines = _Lines(hold: true);
      final aloud = ReadAloud(lines, onSentence: (_) {});
      final done = aloud.play(['A.', 'B.']);
      await Future<void>.delayed(Duration.zero);
      await aloud.stop();
      await done;
      expect(lines.played.map((l) => l.$1), ['A.']);
      expect(lines.stops, 1);
      expect(aloud.playing, isFalse);
    });

    test('slow reading plays at half speed', () async {
      final lines = _Lines();
      await ReadAloud(lines, onSentence: (_) {}).play(['A.'], slow: true);
      expect(lines.played.single.$2, slowReadRate);
    });
  });

  testWidgets('"Önce dinle" starts reading the hidden story aloud at once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lines = _Lines(hold: true);
    final story = _stories.first;
    final sentences = storySentences(tokenizeStory(story));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          speechProvider.overrideWithValue(FakeSpeech()),
          linePlayerProvider.overrideWithValue(lines),
          notesProvider.overrideWith(
            (ref) async => const NotesBundle(words: [], topics: [], diaryPrompts: []),
          ),
          storiesProvider.overrideWith((ref) async => _stories),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: StoryReaderScreen(story: story),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(lines.played, isEmpty);

    await tester.tap(find.byKey(const Key('reading-listen-first')));
    await tester.pump();
    expect(lines.played.map((l) => l.$1), [sentences.first]);
    expect(find.text('Cümle 1/${sentences.length}'), findsOneWidget);
    lines.release();
    await tester.pump();
    expect(lines.played.map((l) => l.$1), sentences.take(2));
    expect(find.text('Cümle 2/${sentences.length}'), findsOneWidget);

    // The pause button stops it; the play button goes on from that sentence.
    await tester.tap(find.byKey(const Key('reading-play-all')));
    await tester.pump();
    expect(lines.stops, 1);
    expect(find.byTooltip('Buradan sona kadar dinle'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reading-play-all')));
    await tester.pump();
    expect(lines.played.last.$1, sentences[1]);

    // Turning "Önce dinle" off stops the voice.
    await tester.tap(find.byKey(const Key('reading-listen-first')));
    await tester.pump();
    expect(lines.stops, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Günün okuması: "Dinle" reads the text aloud, "Durdur" stops it', (tester) async {
    final lines = _Lines(hold: true);
    final src = FakeDailySource({'2026-11-19_A2': reading('2026-11-19', 'A2')});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await overrides(tester, daily: src),
          linePlayerProvider.overrideWithValue(lines),
        ],
        child: const MaterialApp(home: DailyReadingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-reading-listen')));
    await tester.pump();
    expect(lines.played.map((l) => l.$1), ['One rainy morning a quiet neighbour found an umbrella.']);
    expect(find.text('Durdur · cümle 1/2'), findsOneWidget);
    lines.release();
    await tester.pump();
    expect(lines.played.last.$1, 'She gave it back with a smile.');
    expect(find.text('Durdur · cümle 2/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-reading-listen')));
    await tester.pump();
    expect(lines.stops, 1);
    expect(find.text('Dinle'), findsOneWidget);
  });
}
