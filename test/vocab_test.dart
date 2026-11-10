import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/dev_scenarios.dart';
import 'package:lingora/data/notes_practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/vocab_practice.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/screens/vocab/dev_scenario_screen.dart';
import 'package:lingora/screens/vocab/discover_screen.dart';
import 'package:lingora/screens/vocab/vocab_home_screen.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeSpeech;

final _json = jsonDecode(File(vocabAsset).readAsStringSync()) as Map<String, dynamic>;
final _bundle = VocabBundle.fromJson(_json);
final _entries = _bundle.entries;

Future<ProviderContainer> _container(DateTime now, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(sp), clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('software vocabulary content', () {
    test('has about 600 entries with unique ids, words and ranks 1..N', () {
      expect(_entries.length, greaterThanOrEqualTo(550));
      expect(_entries.map((e) => e.id).toSet().length, _entries.length);
      expect(_entries.map((e) => e.word.toLowerCase()).toSet().length, _entries.length);
      expect([for (final e in _entries) e.rank], [for (var i = 1; i <= _entries.length; i++) i]);
      for (final e in _entries) {
        expect(e.id, startsWith(vocabIdPrefix));
      }
    });

    test('topics are the 13 planned ones and each has words', () {
      expect(_bundle.topics.map((t) => t.name), [
        'Temeller',
        'Git ve sürüm kontrolü',
        'Hata ayıklama',
        'Test',
        'Mimari ve tasarım',
        'Web',
        'Mobil (Flutter/Android/Kotlin)',
        'Veri ve yapay zekâ',
        'DevOps ve bulut',
        'Güvenlik',
        'Proje yönetimi ve Agile',
        'Toplantı ve iletişim',
        'Mülakat',
      ]);
      final names = _bundle.topics.map((t) => t.name).toSet();
      for (final e in _entries) {
        expect(names, contains(e.topic), reason: e.word);
      }
      for (final t in names) {
        expect(_bundle.inTopic(t).length, greaterThanOrEqualTo(25), reason: t);
      }
    });

    test('every entry has a Turkish meaning, definition, example and collocation', () {
      for (final e in _entries) {
        expect(e.senses, isNotEmpty, reason: e.word);
        for (final s in e.senses) {
          expect(s.tr.trim(), isNotEmpty, reason: e.word);
          expect(s.def.length, greaterThan(7), reason: e.word);
          expect(s.def.toLowerCase(), isNot(contains(e.word.toLowerCase())), reason: e.word);
        }
        expect(e.examples, isNotEmpty, reason: e.word);
        for (final x in e.examples) {
          expect(x.en, contains(x.target), reason: e.word);
          expect(x.tr.trim(), isNotEmpty, reason: e.word);
          expect(x.blanked, contains('_____'), reason: e.word);
        }
        expect(e.collocations, isNotEmpty, reason: e.word);
        for (final c in e.collocations) {
          expect(c.phrase.split(' '), contains(c.answer), reason: '${e.word}: ${c.phrase}');
          expect(c.blanked, contains('_____'), reason: e.word);
          expect(c.tr.trim(), isNotEmpty, reason: e.word);
        }
        if (e.synonym != null) expect(e.synonym!.toLowerCase(), isNot(e.word.toLowerCase()));
      }
    });

    test('examples cover every working context, and commit/PR/ticket sentences are common', () {
      final contexts = {
        for (final e in _entries)
          for (final x in e.examples) x.context,
      };
      expect(contexts, VocabContext.values.toSet());
      expect(_entries.where((e) => e.examples.any((x) => x.context.isWritten)).length, greaterThan(150));
      expect(_entries.where((e) => e.tip != null).length, greaterThan(150));
    });

    test('seeded entries link to words in the Notion dictionary', () {
      final notes = (jsonDecode(File('assets/notes/words.json').readAsStringSync()) as List)
          .map((w) => (w as Map)['en'] as String)
          .toSet();
      final seeded = _entries.where((e) => e.fromNotes).toList();
      expect(seeded.length, greaterThanOrEqualTo(30));
      for (final e in seeded) {
        expect(notes, contains(e.notesWord), reason: e.word);
      }
    });
  });

  group('knowledge map and scheduling', () {
    test('rank bands count unknown / learning / known and estimate the known share', () {
      final p = Progress(wordBox: {for (final e in _entries.take(10)) e.id: 3, _entries[10].id: 1});
      final bands = rankBands(_entries, p);
      expect(bands.first.from, 1);
      expect(bands.first.to, rankBandSize);
      expect(bands.fold<int>(0, (s, b) => s + b.size), _entries.length);
      expect(bands.first.known, 10);
      expect(bands.first.learning, 1);
      // 10 of the 11 sorted words are known, so most of band 1 counts as known.
      expect(bands.first.estimatedKnown, closeTo(100 * 10 / 11, 0.01));
      expect(knownPercent(bands), greaterThan(10));
      expect(knownPercent(rankBands(_entries, const Progress())), 0);
    });

    test('triage puts known words in the known box and words to learn in today\'s queue', () async {
      final now = DateTime(2026, 11, 10, 9);
      final c = await _container(now);
      final a = _entries[0], b = _entries[1];
      c.read(progressProvider.notifier)
        ..triageWord(a.id, known: true)
        ..triageWord(b.id, known: false);
      final p = c.read(progressProvider);
      expect(vocabStatus(a, p), VocabStatus.known);
      expect(vocabStatus(b, p), VocabStatus.learning);
      expect(vocabStatus(_entries[2], p), VocabStatus.unknown);
      expect(triageQueue(_entries, p).first, _entries[2]);
      expect(reviewQueue(_entries, p, now), [b]);
      expect(reviewQueue(_entries, p, now.add(const Duration(days: 7))), [b, a]);
      expect(dueVocabCount(_entries, p, now), 1);
      // Track words do not inflate the Notlarım "learned" counter.
      expect(learnedWordCount(p), 0);

      c.read(progressProvider.notifier).reviewWord(b.id, known: true);
      final p2 = c.read(progressProvider);
      expect(p2.wordBox[b.id], 1);
      expect(reviewQueue(_entries, p2, now), isEmpty);
      expect(reviewQueue(_entries, p2, now.add(const Duration(days: 1))), [b]);
    });

    test('topic filters scope the queues', () {
      final topic = _entries.first.topic;
      expect(triageQueue(_entries, const Progress(), topic: topic).every((e) => e.topic == topic), isTrue);
    });
  });

  group('review cards', () {
    test('every card type can be built and has its answer among the options', () {
      final r = Random(7);
      final seen = <VocabCardType>{};
      for (final e in _entries) {
        for (final type in availableCardTypes(e)) {
          final card = buildCard(e, _entries, type, r)!;
          seen.add(type);
          if (card.isTyping) {
            expect(card.hint, isNotNull);
            expect(card.check(card.answer.toUpperCase()), isTrue, reason: '${e.word} $type');
          } else {
            expect(card.options, contains(card.answer), reason: '${e.word} $type');
            expect(card.options.toSet().length, card.options.length, reason: '${e.word} $type');
            expect(card.options.length, 4, reason: '${e.word} $type');
            expect(card.check(card.answer), isTrue);
          }
        }
      }
      expect(seen, VocabCardType.values.toSet());
    });

    test('blanked prompts hide the answer', () {
      final r = Random(1);
      for (final e in _entries.take(150)) {
        for (final type in [
          VocabCardType.exampleBlank,
          VocabCardType.collocation,
          VocabCardType.devSentence,
        ]) {
          final card = buildCard(e, _entries, type, r);
          if (card == null) continue;
          expect(card.prompt, contains('_____'));
        }
      }
    });

    test('a session has one card per word and mixes types by box', () {
      final queue = _entries.take(12).toList();
      final p = Progress(wordBox: {for (final (i, e) in queue.indexed) e.id: i % 4});
      final cards = buildSession(queue, _entries, p, Random(3));
      expect(cards.map((c) => c.entry), queue);
      expect(cards.map((c) => c.type).toSet().length, greaterThan(2));
      for (var i = 1; i < cards.length; i++) {
        final options = availableCardTypes(cards[i].entry);
        if (options.length > 1) expect(cards[i].type, isNot(cards[i - 1].type));
      }
      // New words start with recognition cards.
      final fresh = buildSession(queue, _entries, const Progress(), Random(3));
      for (final c in fresh) {
        expect([VocabCardType.meaning, VocabCardType.definition], contains(c.type));
      }
    });

    test('typed answers ignore case, spacing and end punctuation', () {
      expect(normalizeAnswer('  Pull   Request. '), 'pull request');
      expect(normalizeAnswer('don’t'), "don't");
      expect(
        VocabCard(
          type: VocabCardType.listenSpell,
          entry: _entries.first,
          prompt: '',
          answer: 'CI',
        ).check('ci'),
        isTrue,
      );
    });
  });

  group('scenarios and catalog', () {
    test('eight developer scenarios with model answers that pass their own checklist', () {
      expect(devScenarios.length, 8);
      expect(devScenarios.map((s) => s.id).toSet().length, 8);
      for (final s in devScenarios) {
        expect(s.id, startsWith('dev_'));
        expect(s.review(s.modelAnswer).every((c) => c.$2), isTrue, reason: s.id);
        expect(s.review('hello').every((c) => c.$2), isFalse, reason: s.id);
        expect(detectTrErrors(s.modelAnswer), isEmpty, reason: s.id);
      }
    });

    test('the track is listed under MESLEK', () {
      final t = trackById('pro_software');
      expect(t.kind, TrackKind.vocab);
      expect(t.badge, 'MESLEK');
      expect(t.title, 'Yazılımcı İngilizcesi');
    });
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    Widget home, {
    AppMode mode = AppMode.adult,
    Brightness brightness = Brightness.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(sp),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 10, 9)),
        speechProvider.overrideWithValue(FakeSpeech()),
        vocabProvider.overrideWith((ref) async => _bundle),
      ],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(mode: mode, brightness: brightness),
          builder: (_, child) => PaletteScope(palette: Palette.of(mode, brightness), child: child!),
          home: Scaffold(body: home),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('track home shows the knowledge map, actions and topics', (tester) async {
    await pumpScreen(tester, const VocabHomeScreen());
    expect(find.text('Bilgi haritası'), findsOneWidget);
    expect(find.text('~%0 biliyorsun'), findsOneWidget);
    expect(find.text('1–100'), findsOneWidget);
    expect(find.text('Kelime keşfet'), findsOneWidget);
    expect(find.text('İş senaryoları'), findsOneWidget);
  });

  testWidgets('track home follows the design modes (Çocuk modu, koyu tema)', (tester) async {
    await pumpScreen(tester, const VocabHomeScreen(), mode: AppMode.kid, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Bilgi haritası'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Temeller'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('🧱'), findsOneWidget); // kid mode shows topic emoji
  });

  testWidgets('track home in adult dark mode uses icons, not emoji', (tester) async {
    await pumpScreen(tester, const VocabHomeScreen(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(find.text('Temeller'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('🧱'), findsNothing); // adult mode shows icons instead
    expect(find.byIcon(Icons.code_rounded), findsWidgets);
  });

  testWidgets('scenario practice checks the text and shows the model answer', (tester) async {
    final c = await pumpScreen(tester, DevScenarioScreen(scenario: devScenarios.first));
    await tester.enterText(
      find.byKey(const Key('scenarioInput')),
      'Yesterday I finish the login screen. I am agree.',
    );
    await tester.tap(find.text('Kontrol et'));
    await tester.pump();
    expect(find.text('Neden yanlış?'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('modelAnswer')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.byKey(const Key('modelAnswer')), findsOneWidget);
    final p = c.read(progressProvider);
    expect(p.errorStats, isNotEmpty);
    expect(p.isDone(devScenarioNodeId('dev_standup')), isTrue);
  });

  testWidgets('triage then review moves words through the boxes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final now = DateTime(2026, 11, 10, 9);
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(sp),
        clockProvider.overrideWithValue(() => now),
        speechProvider.overrideWithValue(FakeSpeech()),
      ],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DiscoverScreen(all: _entries)),
      ),
    );
    await tester.pump();
    final first = _entries[0], second = _entries[1], third = _entries[2];

    expect(find.text(first.word), findsOneWidget);
    await tester.tap(find.text('Öğreneceğim'));
    await tester.pump();
    await tester.tap(find.text('Öğreneceğim'));
    await tester.pump();
    await tester.tap(find.text('Biliyorum'));
    await tester.pump();
    for (var i = 3; i < discoverRound; i++) {
      await tester.tap(find.text('Sonra'));
      await tester.pump();
    }
    expect(find.text('Tur bitti!'), findsOneWidget);
    var p = container.read(progressProvider);
    expect(vocabStatus(first, p), VocabStatus.learning);
    expect(vocabStatus(second, p), VocabStatus.learning);
    expect(vocabStatus(third, p), VocabStatus.known);
    expect(vocabStatus(_entries[3], p), VocabStatus.unknown);

    await tester.tap(find.text('Şimdi öğren (2)'));
    await tester.pumpAndSettle();

    for (final e in [first, second]) {
      // New words get "anlamı seç" or "tanımdan kelimeyi seç" cards.
      final meaning = find.text(e.tr);
      await tester.tap(meaning.evaluate().isNotEmpty ? meaning : find.text(e.word).last);
      await tester.pump();
      expect(find.textContaining('Doğru!'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vocabNext')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    p = container.read(progressProvider);
    expect(p.wordBox[first.id], 1);
    expect(p.wordBox[second.id], 1);
    expect(p.wordDue[first.id], dayKey(now.add(const Duration(days: 1))));
    expect(p.completed['sw_review'], 1);
    expect(p.totalXp, greaterThan(0));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
