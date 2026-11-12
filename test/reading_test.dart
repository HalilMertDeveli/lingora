import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/notes_practice.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/reading_repository.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/models/reading.dart';
import 'package:lingora/screens/notes_screen.dart';
import 'package:lingora/screens/reading_screen.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSpeech implements SpeechService {
  final said = <String>[];
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async =>
      said.add(text);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _stories = parseStories(File('assets/reading/stories.json').readAsStringSync());

/// The general course's reading library (docs/genel-mufredat.md §2 "Faz 6").
final _general = [
  for (final f in Directory(
    'assets/reading',
  ).listSync().whereType<File>().toList()..sort((x, y) => x.path.compareTo(y.path)))
    if (RegExp(r'genel_okuma_[a-z0-9_]+\.json$').hasMatch(f.path.replaceAll(r'\', '/')))
      ...parseStories(f.readAsStringSync()),
];

/// Word range of a general library text by level.
const _generalLengths = {
  'A1': (100, 180),
  'A2': (150, 250),
  'B1': (250, 400),
  'B2': (400, 650),
  'C1': (600, 900),
};

const _emptyNotes = NotesBundle(words: [], topics: [], diaryPrompts: []);

void main() {
  group('general reading library (genel_okuma_*)', () {
    test('80 texts: 15 A1, 20 A2, 10 B1, 20 B2, 15 C1; ids go_, unique across the library', () {
      final counts = {for (final l in _generalLengths.keys) l: _general.where((s) => s.level == l).length};
      expect(counts, {'A1': 15, 'A2': 20, 'B1': 10, 'B2': 20, 'C1': 15});
      expect(_general.every((s) => s.id.startsWith('go_')), isTrue);
      final all = [..._stories, ..._general].map((s) => s.id);
      expect(all.toSet(), hasLength(all.length));
    });

    test('lengths, 3 questions with 4 options, explanations, balanced answers', () {
      final positions = [0, 0, 0, 0];
      for (final s in _general) {
        final (lo, hi) = _generalLengths[s.level]!;
        // ReadingStory.wordCount and the checker count slightly differently: allow 5 words.
        expect(s.wordCount, inInclusiveRange(lo - 5, hi + 5), reason: s.id);
        expect(s.glosses, isNotEmpty, reason: s.id);
        expect(s.questions, hasLength(3), reason: s.id);
        for (final q in s.questions) {
          expect(q.options, hasLength(4), reason: '${s.id} ${q.q}');
          expect(q.options.map((o) => o.toLowerCase()).toSet(), hasLength(4), reason: '${s.id} ${q.q}');
          expect(q.answer, inInclusiveRange(0, 3), reason: '${s.id} ${q.q}');
          expect(q.explain.trim(), isNotEmpty, reason: '${s.id} ${q.q}');
          positions[q.answer]++;
        }
      }
      final total = positions.reduce((a, b) => a + b);
      expect(positions.every((n) => n < total * 0.4), isTrue, reason: '$positions');
    });

    test('every gloss can be tapped in the text', () {
      for (final s in _general) {
        final glossed = {
          for (final p in tokenizeStory(s))
            for (final t in p)
              if (t.gloss != null) t.word,
        };
        for (final key in s.glosses.keys) {
          expect(glossed, contains(key), reason: '${s.id}: "$key"');
        }
      }
    });
  });

  group('reading stories', () {
    test('15 stories, 5 per level, unique ids', () {
      expect(_stories, hasLength(15));
      expect(_stories.map((s) => s.id).toSet(), hasLength(15));
      for (final level in ['A1', 'A2', 'B1']) {
        expect(_stories.where((s) => s.level == level), hasLength(5), reason: level);
      }
      expect(_stories.every((s) => readingLevels.contains(s.level)), isTrue);
    });

    for (final s in _stories) {
      test('${s.id} is well formed', () {
        expect(s.wordCount, inInclusiveRange(80, 250));
        expect(s.title.trim(), isNotEmpty);
        expect(s.titleTr.trim(), isNotEmpty);
        expect(s.glosses, isNotEmpty);
        for (final e in s.glosses.entries) {
          expect(e.key.trim(), isNotEmpty);
          expect(e.value.trim(), isNotEmpty, reason: e.key);
        }
        expect(s.questions.length, inInclusiveRange(3, 4));
        for (final q in s.questions) {
          expect(q.options.length, greaterThanOrEqualTo(2), reason: q.q);
          expect(q.options.toSet(), hasLength(q.options.length), reason: q.q);
          expect(q.answer, inInclusiveRange(0, q.options.length - 1), reason: q.q);
          expect(q.explain.trim(), isNotEmpty, reason: q.q);
        }
      });

      test('${s.id}: every gloss can be tapped in the text', () {
        final glossed = {
          for (final p in tokenizeStory(s))
            for (final t in p)
              if (t.gloss != null) t.word,
        };
        for (final key in s.glosses.keys) {
          expect(glossed, contains(key), reason: '${s.id}: "$key"');
        }
      });
    }

    test('sentences split on full stops but not on titles', () {
      final story = _stories.firstWhere((s) => s.id == 'a1_neighbour');
      final sentences = storySentences(tokenizeStory(story));
      expect(sentences.first, 'We have a new neighbour.');
      expect(sentences[1], 'His name is Mr. Kaya.');
    });
  });

  group('user-added words', () {
    late ProviderContainer c;
    final now = DateTime(2026, 11, 10, 9);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
    });
    tearDown(() => c.dispose());

    test('persist, are not duplicated and appear in review', () {
      final n = c.read(progressProvider.notifier);
      expect(n.addCustomWord(customWord('Seagull', 'martı', example: 'A seagull catches it.')), isTrue);
      expect(n.addCustomWord(customWord('seagull', 'martı')), isFalse);

      final p = c.read(progressProvider);
      final restored = Progress.fromJson(p.toJson());
      expect(restored.customWords.single.en, 'Seagull');
      expect(restored.customWords.single.topic, customTopic);
      expect(restored.customWords.single.example, 'A seagull catches it.');

      const notes = NotesBundle(
        words: [NoteWord(id: 'w_ferry', en: 'ferry', tr: 'vapur', topic: 'Genel')],
        topics: [],
        diaryPrompts: [],
      );
      final words = dictionaryWords(notes, p);
      expect(words.map((w) => w.en), ['ferry', 'Seagull']);
      expect(findWord(words, 'SEAGULL')?.tr, 'martı');
      expect(wordsToReview(words, p, now).map((w) => w.en), contains('Seagull'));

      final id = customWordId('Seagull');
      n.reviewWord(id, known: false);
      expect(dueWordCount(words, c.read(progressProvider), now), 1);
      expect(wordsToReview(words, c.read(progressProvider), now).first.id, id);

      n.removeCustomWord(id);
      expect(c.read(progressProvider).customWords, isEmpty);
      expect(c.read(progressProvider).wordBox.containsKey(id), isFalse);
    });
  });

  group('reading screens', () {
    late _FakeSpeech speech;

    Future<ProviderContainer> pump(WidgetTester tester, Widget home) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      speech = _FakeSpeech();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          speechProvider.overrideWithValue(speech),
          notesProvider.overrideWith((ref) async => _emptyNotes),
          storiesProvider.overrideWith((ref) async => _stories),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildTheme(), home: home),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('"Önce dinle": text hidden, listen and answer, then the text opens', (tester) async {
      final story = _stories.first;
      final c = await pump(tester, StoryReaderScreen(story: story));
      await tester.tap(find.byKey(const Key('reading-listen-first')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-hidden-text')), findsOneWidget);
      expect(find.text('seagulls'), findsNothing);
      // The sentence player is on.
      await tester.tap(find.textContaining('Cümle 1/'));
      expect(speech.said, isNotEmpty);

      await tester.scrollUntilVisible(find.text('Sorulara geç'), 200);
      await tester.tap(find.text('Sorulara geç'));
      await tester.pumpAndSettle();
      for (final (i, q) in story.questions.indexed) {
        await tester.tap(find.text(q.options[q.answer]));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text(i + 1 == story.questions.length ? 'Bitir' : 'Devam'), 200);
        await tester.tap(find.text(i + 1 == story.questions.length ? 'Bitir' : 'Devam'));
        await tester.pumpAndSettle();
      }
      // The text opens; nothing is recorded until "Bitir".
      expect(find.byKey(const Key('reading-hidden-text')), findsNothing);
      expect(find.byKey(const Key('reading-listen-first')), findsNothing);
      await tester.scrollUntilVisible(find.text('seagulls'), 200);
      expect(c.read(progressProvider).isDone(readNodeId(story.id)), isFalse);
      await tester.scrollUntilVisible(find.text('Bitir'), 200);
      await tester.tap(find.text('Bitir'));
      await tester.pumpAndSettle();
      expect(c.read(progressProvider).isDone(readNodeId(story.id)), isTrue);
    });

    testWidgets('open a story, tap a glossed word, add it, listen and answer', (tester) async {
      final c = await pump(tester, const ReadingLibraryScreen());
      expect(find.text('0/5'), findsNWidgets(2));

      await tester.tap(find.text('The Ferry to Kadıköy'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('seagulls'), 200);
      await tester.tap(find.text('seagulls'));
      await tester.pumpAndSettle();
      expect(find.text('martılar'), findsOneWidget);
      await tester.tap(find.byTooltip('Telaffuz'));
      expect(speech.said.last, 'seagulls');

      await tester.tap(find.text('Sözlüğüme ekle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sözlüğüne eklendi'), findsOneWidget);
      final added = c.read(progressProvider).customWords.single;
      expect(added.en, 'seagulls');
      expect(added.tr, 'martılar');
      expect(added.example, 'There are many seagulls behind the ferry.');
      Navigator.of(tester.element(find.text('martılar'))).pop();
      await tester.pumpAndSettle();

      // Sentence-by-sentence listening.
      await tester.tap(find.byTooltip('Dinle'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Cümle 1/'));
      expect(speech.said.last, 'My name is Elif.');
      await tester.tap(find.byTooltip('Sonraki cümle'));
      await tester.pumpAndSettle();
      expect(speech.said.last, 'I live in Beşiktaş, and I work in Kadıköy.');

      await tester.tap(find.byTooltip('Dinlemeyi kapat'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sorulara geç'), 300);
      await tester.tap(find.text('Sorulara geç'));
      await tester.pumpAndSettle();

      final story = _stories.first;
      for (var i = 0; i < story.questions.length; i++) {
        final q = story.questions[i];
        // A wrong pick on the first question only asks to try again.
        if (i == 0) {
          await tester.tap(find.text(q.options[(q.answer + 1) % q.options.length]));
          await tester.pumpAndSettle();
          expect(find.textContaining('bir daha dene'), findsOneWidget);
        }
        await tester.tap(find.text(q.options[q.answer]));
        await tester.pumpAndSettle();
        expect(find.text(q.explain), findsOneWidget);
        await tester.tap(find.text(i == story.questions.length - 1 ? 'Bitir' : 'Devam'));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('Hikâye bitti!'), findsOneWidget);
      final p = c.read(progressProvider);
      expect(p.isDone(readNodeId(story.id)), isTrue);
      expect(p.totalXp, 10 + (story.questions.length - 1) * 2);
      // Let the result screen's delayed animations finish.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a word can be added to the dictionary by hand', (tester) async {
      final c = await pump(tester, const WordListScreen(notes: _emptyNotes));
      await tester.tap(find.text('Kelime ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('add-en')), 'deadline');
      await tester.enterText(find.byKey(const ValueKey('add-tr')), 'son teslim tarihi');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      expect(c.read(progressProvider).customWords.single.tr, 'son teslim tarihi');
      expect(find.text('deadline'), findsOneWidget);
      expect(find.text(customTopic), findsOneWidget);
      expect(find.text('Sözlüğüm (1)'), findsOneWidget);
    });
  });
}
