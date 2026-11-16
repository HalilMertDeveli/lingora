// Listening pieces (NodeType.listening): the content of every general-course
// unit, the level rules, the voice script and the listen → questions → text
// flow of the screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/voice_key.dart';
import 'package:lingora/data/listening.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/listening_screen.dart';
import 'package:lingora/screens/path_map.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/build_course_index.dart' as index_tool;
import '../tool/voice_elevenlabs.dart' as voice_tool;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

/// Every section of the general course with its units (extension files
/// joined to their section), read straight from the assets.
List<(String cefr, Map<String, dynamic> unit)> _generalUnits() {
  final files = [
    File('assets/courses/tr_en.json'),
    ...(Directory('assets/courses/tr_en')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path))),
  ];
  final cefrOf = <String, String>{};
  final out = <(String, Map<String, dynamic>)>[];
  for (final f in files) {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final section = j['section'] as Map<String, dynamic>?;
    if (section != null) cefrOf[section['id'] as String] = section['cefr'] as String;
    final cefr = section?['cefr'] as String? ?? cefrOf[j['extends']]!;
    for (final u in (j['units'] as List).cast<Map<String, dynamic>>()) {
      out.add((cefr, u));
    }
  }
  return out;
}

class _Lines implements LinePlayer {
  final played = <(String, double, double)>[];
  int stops = 0;
  @override
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1}) async =>
      played.add((text, rate, pitch));
  @override
  Future<void> stopLine() async => stops++;
}

void main() {
  group('content', () {
    final units = _generalUnits();

    test('the general course has 142 units, each with one listening piece before its test', () {
      expect(units, hasLength(142));
      for (final (_, u) in units) {
        final nodes = (u['nodes'] as List).cast<Map<String, dynamic>>();
        final types = [for (final n in nodes) n['type']];
        expect(types.where((t) => t == 'listening'), hasLength(1), reason: u['id'] as String);
        expect(types.indexOf('listening'), types.indexOf('test') - 1, reason: u['id'] as String);
        final node = nodes.firstWhere((n) => n['type'] == 'listening');
        expect(node['id'], '${u['id']}d');
      }
    });

    test('pieces follow the rules of their section\'s level', () {
      for (final (cefr, u) in units) {
        final id = u['id'] as String;
        final json = (u['nodes'] as List).cast<Map<String, dynamic>>().firstWhere(
          (n) => n['type'] == 'listening',
        );
        final node = PathNode.fromJson(json);
        final p = node.listening!;
        final r = ListeningRules.of(cefr);
        expect(p.cefr, cefr, reason: id);
        expect(p.lines.length, inInclusiveRange(r.minLines, r.maxLines), reason: '$id lines');
        expect(dialogueWords(p), inInclusiveRange(r.minWords, r.maxWords), reason: '$id words');
        expect(
          estimatedSeconds(p),
          inInclusiveRange((r.seconds * 0.7).round(), (r.seconds * 1.3).round()),
          reason: '$id length',
        );
        expect(p.questions.length, inInclusiveRange(r.minQuestions, r.maxQuestions), reason: '$id questions');
        expect(p.questions.map((q) => q.kind).toSet().length, greaterThanOrEqualTo(2), reason: id);
        // Two speakers, a woman and a man, taking turns.
        expect(p.speakers.map((s) => s.female).toSet(), {true, false}, reason: id);
        for (final s in p.speakers) {
          final v = voiceForAvatar(s.avatar);
          if (v != null) expect(v == Voice.matilda, s.female, reason: '$id ${s.name} avatar');
        }
        for (var i = 0; i < p.lines.length; i++) {
          final l = p.lines[i];
          expect(p.speaker(l.speaker), isNotNull, reason: '$id line $i');
          expect(l.translation, isNotEmpty, reason: '$id line $i');
          expect(l.text, isNot(contains(RegExp('[çğıöşüÇĞİÖŞÜ]'))), reason: '$id line $i: not recordable');
          if (i > 0) expect(l.speaker, isNot(p.lines[i - 1].speaker), reason: '$id line $i');
        }
        if (r.needsInference) {
          expect(p.questions.any((q) => q.skill == 'inference' || q.skill == 'attitude'), isTrue, reason: id);
          expect(p.idioms, isNotEmpty, reason: id);
          for (final idiom in p.idioms) {
            expect(
              p.lines.any((l) => l.text.toLowerCase().contains(idiom.toLowerCase())),
              isTrue,
              reason: '$id idiom $idiom',
            );
          }
        }
      }
    });

    test('every answer can be found in the dialogue', () {
      for (final (_, u) in units) {
        final json = (u['nodes'] as List).cast<Map<String, dynamic>>().firstWhere(
          (n) => n['type'] == 'listening',
        );
        final p = PathNode.fromJson(json).listening!;
        for (final q in p.questions) {
          final at = '${u['id']}: ${q.prompt} ${q.quote ?? ''}';
          expect(q.choices, contains(q.answer), reason: at);
          expect(q.choices.toSet(), hasLength(q.choices.length), reason: at);
          if (q.kind == ListeningQuestionKind.who) {
            final said = p.lines.where((l) => l.text.contains(q.quote!)).toList();
            expect(said, hasLength(1), reason: at);
            expect(said.single.speaker, q.answer, reason: at);
          } else {
            expect(q.line, inInclusiveRange(0, p.lines.length - 1), reason: at);
            expect(p.lines[q.line!].text.toLowerCase(), contains(q.key!.toLowerCase()), reason: at);
          }
        }
      }
    });

    test('the voice script reads women with Matilda and men with Eric', () {
      for (final (_, u) in units.take(30)) {
        final node = (u['nodes'] as List).cast<Map<String, dynamic>>().firstWhere(
          (n) => n['type'] == 'listening',
        );
        final gender = {
          for (final s in (node['speakers'] as List).cast<Map<String, dynamic>>()) s['name']: s['gender'],
        };
        final lines = voice_tool.listeningLines(u);
        expect(lines, hasLength((node['lines'] as List).length));
        for (final (i, l) in (node['lines'] as List).cast<Map<String, dynamic>>().indexed) {
          expect(lines[i].$2, gender[l['speaker']] == 'male' ? Voice.eric : Voice.matilda);
          // Recorded for the whole unit too.
          expect(voice_tool.spokenIn(u), contains(normalizeSpoken(l['text'] as String)));
        }
      }
    });
  });

  test('the course outline keeps a listening node but not its dialogue', () {
    final node = index_tool.outlineNode({
      'id': 'u1d',
      'type': 'listening',
      'title': 'T',
      'cefr': 'B1',
      'speakers': [],
      'lines': [],
      'questions': [],
    }) as Map<String, dynamic>;
    expect(node.keys, unorderedEquals(['id', 'type', 'title', 'cefr']));
    final outline = PathNode.fromJson(node);
    expect(outline.type, NodeType.listening);
    expect(outline.listening, isNull);
    expect(listeningLength(outline), '≈45 sn');
  });

  test('levels get longer dialogues', () {
    expect(
      [
        for (final c in ['A1', 'A2', 'B1', 'B2', 'C1']) ListeningRules.of(c).seconds,
      ],
      [30, 30, 45, 60, 60],
    );
    expect(pitchFor(female: true), greaterThan(1));
    expect(pitchFor(female: false), lessThan(1));
  });

  group('screen', () {
    final node = PathNode.fromJson({
      'id': 'u1d',
      'type': 'listening',
      'title': 'Yeni komşu',
      'description': '',
      'rewardXp': 15,
      'cefr': 'A1',
      'speakers': [
        {'name': 'Elif', 'gender': 'female', 'avatar': '👩'},
        {'name': 'Tom', 'gender': 'male', 'avatar': '👨'},
      ],
      'lines': [
        {'speaker': 'Elif', 'text': 'Are you the new neighbour?', 'translation': 'Yeni komşu sen misin?'},
        {
          'speaker': 'Tom',
          'text': 'Yes, I live in flat five.',
          'translation': 'Evet, beş numarada oturuyorum.',
        },
      ],
      'questions': [
        {
          'kind': 'choice',
          'prompt': 'Tom hangi dairede?',
          'choices': ['İki', 'Beş', 'Dokuz'],
          'answer': 'Beş',
          'line': 1,
          'key': 'flat five',
        },
        {'kind': 'trueFalse', 'statement': 'Elif yeni komşu.', 'answer': false, 'line': 0, 'key': 'new'},
        {'kind': 'who', 'quote': 'Are you the new neighbour?', 'answer': 'Elif'},
      ],
    });

    Future<(ProviderContainer, _Lines)> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final lines = _Lines();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            speechProvider.overrideWithValue(FakeSpeech()),
            linePlayerProvider.overrideWithValue(lines),
            notificationServiceProvider.overrideWithValue(FakeNotifications()),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: ListeningScreen(node: node, color: Brand.primary, gap: Duration.zero),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (ProviderScope.containerOf(tester.element(find.byType(ListeningScreen))), lines);
    }

    testWidgets('listen with the text hidden, answer, then read and replay the text', (tester) async {
      final (container, lines) = await pump(tester);
      // Text hidden; questions only after hearing it once.
      expect(find.text('Are you the new neighbour?'), findsNothing);
      expect(find.byKey(const Key('listening-hint')), findsOneWidget);
      await tester.tap(find.text('Sorulara geç'));
      await tester.pumpAndSettle();
      expect(find.text('Tom hangi dairede?'), findsNothing);

      // Slower, two voices.
      await tester.tap(find.byKey(const Key('listening-speed')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('listening-play')));
      await tester.pumpAndSettle();
      expect(lines.played.map((p) => p.$1), ['Are you the new neighbour?', 'Yes, I live in flat five.']);
      expect(lines.played.every((p) => p.$2 == 0.75), isTrue);
      expect(lines.played[0].$3, greaterThan(lines.played[1].$3)); // woman higher than man
      expect(find.text('Are you the new neighbour?'), findsNothing);

      await tester.tap(find.text('Sorulara geç'));
      await tester.pumpAndSettle();
      // A wrong answer can be tried again; nothing is taken away.
      await tester.tap(find.text('Dokuz'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Olmadı'), findsOneWidget);
      await tester.tap(find.text('Beş'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      // True / false.
      expect(find.text('Elif yeni komşu.'), findsOneWidget);
      await tester.tap(find.text('Yanlış'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      // Who said it?
      expect(find.text('Bunu kim söyledi?'), findsOneWidget);
      await tester.tap(find.text('Elif'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metni gör'));
      await tester.pumpAndSettle();

      // The text, line by line; a tap replays a line and shows its translation.
      expect(find.text('Are you the new neighbour?'), findsOneWidget);
      expect(find.text('Yes, I live in flat five.'), findsOneWidget);
      lines.played.clear();
      await tester.tap(find.byKey(const Key('listening-line-1')));
      await tester.pumpAndSettle();
      expect(lines.played.single.$1, 'Yes, I live in flat five.');
      expect(find.text('Evet, beş numarada oturuyorum.'), findsOneWidget);
      lines.played.clear();
      await tester.tap(find.byKey(const Key('listening-replay-all')));
      await tester.pumpAndSettle();
      expect(lines.played, hasLength(2));

      await tester.tap(find.text('Bitir'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(progressProvider).isDone('u1d'), isTrue);
      expect(find.text('Dinleme tamamlandı!'), findsOneWidget);
    });
  });

  testWidgets('the path card invites to listen', (tester) async {
    expect(nodeIcon(NodeType.listening), Icons.headphones_rounded);
    expect(nodeCta(NodeType.listening), anyOf('DİNLE', 'Dinle'));
  });
}
