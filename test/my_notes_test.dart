import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/notes_practice.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/my_notes_screen.dart';
import 'package:lingora/screens/notes_screen.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _course = NotesBundle(
  words: [NoteWord(id: 'w_ferry', en: 'ferry', tr: 'vapur', topic: 'Genel')],
  topics: [
    GrammarTopic(id: 't1', title: 'Present Simple', category: 'Zamanlar', source: 'x', body: 'Her gün.'),
  ],
  diaryPrompts: ['What did you do today?'],
);

void main() {
  late ProviderContainer c;
  var now = DateTime(2026, 11, 16, 9);

  setUp(() async {
    now = DateTime(2026, 11, 16, 9);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
    );
  });
  tearDown(() => c.dispose());

  group('own notes', () {
    test('add, edit, delete; newest first; survive a restart', () {
      final n = c.read(progressProvider.notifier);
      n.saveUserNote(title: 'Since', body: 'since + başlangıç');
      now = now.add(const Duration(minutes: 1));
      n.saveUserNote(title: 'For', body: 'for + süre');
      var p = c.read(progressProvider);
      expect(p.visibleNotes.map((x) => x.title), ['For', 'Since']);

      final since = p.visibleNotes.last;
      now = now.add(const Duration(minutes: 1));
      n.saveUserNote(id: since.id, title: 'Since', body: 'since + başlangıç noktası');
      p = c.read(progressProvider);
      expect(p.visibleNotes.first.body, 'since + başlangıç noktası');
      expect(p.userNotes, hasLength(2));

      n.deleteUserNote(since.id);
      p = c.read(progressProvider);
      expect(p.visibleNotes.map((x) => x.title), ['For']);
      // The deletion stays as an empty tombstone for the other devices.
      final tomb = p.userNotes.firstWhere((x) => x.id == since.id);
      expect((tomb.deleted, tomb.body), (true, ''));

      final restored = Progress.fromJson(p.toJson());
      expect(restored.visibleNotes.single.body, 'for + süre');
      expect(restored.userNotes, hasLength(2));
    });
  });

  group('own words', () {
    test('edit keeps the id and the review history; duplicates are refused', () {
      final n = c.read(progressProvider.notifier);
      n.addCustomWord(customWord('deadline', 'son tarih'));
      n.addCustomWord(customWord('ferry boat', 'feribot'));
      final w = c.read(progressProvider).customWords.first;
      n.reviewWord(w.id, known: true);
      final box = c.read(progressProvider).wordBox[w.id];

      expect(n.updateCustomWord(w.id, en: 'Ferry boat', tr: 'x'), isFalse);
      expect(
        n.updateCustomWord(w.id, en: 'deadline', tr: 'son teslim tarihi', example: 'The deadline is Friday.'),
        isTrue,
      );
      final edited = c.read(progressProvider).customWords.first;
      expect((edited.id, edited.tr, edited.example), (w.id, 'son teslim tarihi', 'The deadline is Friday.'));
      expect(c.read(progressProvider).wordBox[w.id], box);
    });

    test('new own words come first in the review, before the course words', () {
      final n = c.read(progressProvider.notifier);
      n.addCustomWord(customWord('deadline', 'son tarih'));
      final p = c.read(progressProvider);
      final words = dictionaryWords(_course, p);
      expect(wordsToReview(words, p, now).first.en, 'deadline');
    });

    test('words saved under the old topic name still count as own words', () {
      const old = NoteWord(id: 'u_x', en: 'x', tr: 'y', topic: 'Eklediklerim');
      final words = dictionaryWords(_course, const Progress(customWords: [old]));
      expect(words.last.topic, customTopic);
      expect(isOwnWord(old), isTrue);
    });
  });

  group('merging two devices', () {
    UserNote note(String id, int at, {bool deleted = false}) => UserNote(
      id: id,
      title: id,
      body: deleted ? '' : 'b$at',
      createdAt: 0,
      updatedAt: at,
      deleted: deleted,
    );

    test('notes: the later edit or deletion wins, others are united', () {
      final local = Progress(userNotes: [note('a', 5), note('b', 9, deleted: true)]);
      final remote = Progress(userNotes: [note('a', 7), note('b', 3), note('c', 1)]);
      final m = mergeProgress(local, remote, localNewer: true);
      final byId = {for (final n in m.userNotes) n.id: n};
      expect(byId['a']!.body, 'b7');
      expect(byId['b']!.deleted, isTrue);
      expect(m.visibleNotes.map((n) => n.id).toSet(), {'a', 'c'});
    });

    test('words: a later deletion wins, a later re-add wins over it', () {
      final ferry = customWord('ferry', 'vapur');
      final removed = Progress(removedWords: const {'ferry': 10});
      final stale = Progress(customWords: [ferry.copyWith(at: 5)]);
      expect(mergeProgress(removed, stale, localNewer: true).customWords, isEmpty);
      expect(mergeProgress(stale, removed, localNewer: true).customWords, isEmpty);

      final readded = Progress(customWords: [ferry.copyWith(at: 20, tr: 'feribot')]);
      final m = mergeProgress(removed, readded, localNewer: true);
      expect(m.customWords.single.tr, 'feribot');
      expect(m.removedWords, {'ferry': 10});
    });

    test('words: the later edit wins', () {
      final a = Progress(customWords: [customWord('ferry', 'vapur').copyWith(at: 1)]);
      final b = Progress(customWords: [customWord('ferry', 'feribot').copyWith(at: 2)]);
      expect(mergeProgress(a, b, localNewer: true).customWords.single.tr, 'feribot');
    });
  });

  group('shared course notes read for everyone', () {
    test('no personal remarks left in the grammar notes', () {
      final text = File('assets/notes/grammar.json').readAsStringSync();
      expect(text, isNot(contains('benim yorumum')));
      expect(text, isNot(contains('Notlarımın')));
    });

    test('no app text points to one person\'s Notion notes', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final line in f.readAsLinesSync()) {
          if (line.trimLeft().startsWith('//')) continue;
          expect(line, isNot(contains('Notion')), reason: f.path);
        }
      }
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildTheme(), home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('home: own area next to the shared course notes', (tester) async {
      final overridden = ProviderContainer(
        parent: c,
        overrides: [notesProvider.overrideWith((ref) async => _course)],
      );
      addTearDown(overridden.dispose);
      c = overridden;
      await pump(tester, const Scaffold(body: NotesHomeScreen()));
      for (final s in ['BUGÜN', 'KENDİ NOTLARIM', 'DERS NOTLARI']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining('Notion'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('my-words')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Henüz kelime eklemedin'), findsOneWidget);
    });

    testWidgets('write, edit and delete a note', (tester) async {
      await pump(tester, const MyNotesScreen());
      expect(find.textContaining('Henüz notun yok'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-note')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-title')), 'Since / for');
      await tester.enterText(find.byKey(const ValueKey('note-body')), 'since + başlangıç, for + süre');
      await tester.tap(find.byKey(const ValueKey('note-save')));
      await tester.pumpAndSettle();
      expect(find.text('Since / for'), findsOneWidget);
      expect(find.text('Notlarım (1)'), findsOneWidget);

      await tester.tap(find.text('Since / for'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-title')), 'Since ve for');
      await tester.tap(find.byKey(const ValueKey('note-save')));
      await tester.pumpAndSettle();
      expect(find.text('Since ve for'), findsOneWidget);

      await tester.tap(find.text('Since ve for'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notu sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Since ve for'), findsNothing);
      expect(c.read(progressProvider).visibleNotes, isEmpty);
    });

    testWidgets('own word: edit from the dictionary, then review it', (tester) async {
      c.read(progressProvider.notifier).addCustomWord(customWord('deadline', 'son tarih'));
      await pump(tester, const WordListScreen(notes: _course, initialTopic: customTopic));
      expect(find.text('ferry'), findsNothing);
      await tester.tap(find.text('deadline'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-word')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('add-tr')), 'son teslim tarihi');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('son teslim tarihi'), findsOneWidget);

      await tester.tap(find.text('Bu konuyu çalış'));
      await tester.pumpAndSettle();
      expect(find.text('deadline'), findsOneWidget);
      await tester.tap(find.text('Biliyorum'));
      await tester.pump(const Duration(seconds: 5));
      final id = c.read(progressProvider).customWords.single.id;
      expect(c.read(progressProvider).wordBox[id], isNotNull);
    });
  });
}
