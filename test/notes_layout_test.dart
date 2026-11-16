import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/notes_index.dart';
import 'package:lingora/data/notes_practice.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/notes_screen.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

GrammarTopic _topic(String id, String title, String category, {String body = ''}) => GrammarTopic(
  id: id,
  title: title,
  category: category,
  source: 'English Book',
  body: body,
  examples: const [NoteExample('I am here.', 'Buradayım.')],
);

NoteWord _word(String en, String tr, String topic) => NoteWord(id: 'w_$en', en: en, tr: tr, topic: topic);

final _notes = NotesBundle(
  topics: [
    _topic('t1', 'Gramer Terimleri', 'Temeller'),
    _topic('t2', 'Present Simple', 'Zamanlar', body: 'Her gün yapılan işler.'),
    _topic('t3', 'Sözcük Türleri', 'Temeller'),
    _topic('t4', 'If Clauses', 'Koşul ve Dilek', body: 'unless = if not'),
  ],
  words: [
    _word('zebra', 'zebra (hayvan)', 'Karışık'),
    _word('widget', 'bileşen', 'Flutter'),
    _word('apple', 'elma', 'Karışık'),
    _word('çay', 'tea', 'Çeviri'),
  ],
  diaryPrompts: const ['What did you do today?'],
);

void main() {
  group('notes index', () {
    test('grammar chapters keep notebook order; topics stay in their chapter', () {
      final s = grammarSections(_notes.topics);
      expect(s.map((c) => c.title), ['Temeller', 'Zamanlar', 'Koşul ve Dilek']);
      expect(s.first.items.map((t) => t.id), ['t1', 't3']);
    });

    test('search looks at title, body, rules and examples; i/İ/ı fold together', () {
      expect(grammarSections(_notes.topics, query: 'UNLESS').single.items.single.id, 't4');
      expect(grammarSections(_notes.topics, query: 'if').single.title, 'Koşul ve Dilek');
      expect(grammarSections(_notes.topics, query: 'buradayim').expand((s) => s.items), hasLength(4));
      expect(grammarSections(_notes.topics, query: 'yok böyle bir şey'), isEmpty);
    });

    test('word topics: own words first, then Turkish A-Z; words A-Z inside', () {
      final words = [..._notes.words, customWord('deadline', 'son tarih')];
      expect(wordTopics(words), [customTopic, 'Çeviri', 'Flutter', 'Karışık']);
      final karisik = wordSections(words).firstWhere((s) => s.title == 'Karışık');
      expect(karisik.items.map((w) => w.en), ['apple', 'zebra']);
      expect(wordSections(words, topic: 'Flutter').single.items.single.en, 'widget');
      expect(wordSections(words, query: 'ELMA').single.items.single.en, 'apple');
    });

    test('trCompare puts Turkish letters in place', () {
      final l = ['şeker', 'su', 'çay', 'ceviz', 'dut']..sort(trCompare);
      expect(l, ['ceviz', 'çay', 'dut', 'su', 'şeker']);
    });

    test('diary days newest first and searchable', () {
      final diary = {'2026-11-01': 'I went home.', '2026-11-03': 'I drank tea.'};
      expect(diaryDays(diary), ['2026-11-03', '2026-11-01']);
      expect(diaryDays(diary, query: 'tea'), ['2026-11-03']);
    });

    test('real notebook: every topic and word lands in exactly one section', () {
      final topics = (jsonDecode(File('assets/notes/grammar.json').readAsStringSync()) as List)
          .map((t) => GrammarTopic.fromJson(t as Map<String, dynamic>))
          .toList();
      final words = (jsonDecode(File('assets/notes/words.json').readAsStringSync()) as List)
          .map((w) => NoteWord.fromJson(w as Map<String, dynamic>))
          .toList();
      expect(grammarSections(topics).expand((s) => s.items), hasLength(topics.length));
      expect(grammarSections(topics).first.title, 'Temeller');
      expect(wordSections(words).expand((s) => s.items), hasLength(words.length));
    });
  });

  group('notes screens', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget home, {AppMode mode = AppMode.adult}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          notesProvider.overrideWith((ref) async => _notes),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(mode: mode),
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('home is split into sections and opens the overview', (tester) async {
      await pump(tester, const Scaffold(body: NotesHomeScreen()));
      for (final s in ['BUGÜN', 'KENDİ NOTLARIM', 'DERS NOTLARI', 'OKUMA']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('Sözlük'), findsOneWidget);
      expect(find.textContaining('4 kelime, 3 konuda'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notes-overview')));
      await tester.pumpAndSettle();
      expect(find.text('Tüm notlarım'), findsOneWidget);
    });

    testWidgets('overview: table of contents, then search across all notes', (tester) async {
      await pump(tester, AllNotesScreen(notes: _notes));
      expect(find.text('1. Temeller'), findsOneWidget);
      expect(find.text('3. Koşul ve Dilek'), findsOneWidget);
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.textContaining('Henüz günlük yazmadın'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('all-notes-search')), 'elma');
      await tester.pumpAndSettle();
      expect(find.text('Kelimeler'), findsOneWidget);
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('Gramer'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('all-notes-search')), 'unless');
      await tester.pumpAndSettle();
      expect(find.text('If Clauses'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('all-notes-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Temeller'));
      await tester.pumpAndSettle();
      expect(find.text('Gramer konuları (4)'), findsOneWidget);
    });

    testWidgets('grammar notes are numbered chapters', (tester) async {
      await pump(tester, GrammarListScreen(notes: _notes));
      expect(find.text('1.1'), findsOneWidget);
      expect(find.text('1.2'), findsOneWidget);
      expect(find.text('2.1'), findsOneWidget);
      expect(find.text('3.1'), findsOneWidget);
      // Numbers stay the same while searching.
      await tester.enterText(find.byType(TextField), 'if');
      await tester.pumpAndSettle();
      expect(find.text('3.1'), findsOneWidget);
      expect(find.text('1.1'), findsNothing);
    });

    testWidgets('dictionary is grouped by topic and A-Z', (tester) async {
      await pump(tester, WordListScreen(notes: _notes));
      expect(find.text('Karışık (2)'), findsOneWidget);
      final apple = tester.getTopLeft(find.text('apple')).dy;
      final zebra = tester.getTopLeft(find.text('zebra')).dy;
      final flutter = tester.getTopLeft(find.text('widget')).dy;
      expect(flutter < apple && apple < zebra, isTrue);

      await tester.ensureVisible(find.text('Flutter (1)'));
      await tester.tap(find.text('Flutter (1)'));
      await tester.pumpAndSettle();
      expect(find.text('apple'), findsNothing);
      expect(find.text('Bu konuyu çalış'), findsOneWidget);
    });

    testWidgets('kid mode still renders the notes home', (tester) async {
      Brand.apply(Palette.kidLight);
      addTearDown(() => Brand.apply(Palette.adultLight));
      await pump(tester, const Scaffold(body: NotesHomeScreen()), mode: AppMode.kid);
      expect(find.text('BUGÜN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
