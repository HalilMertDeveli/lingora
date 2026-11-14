import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/topic_themes.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/path_map.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:lingora/ui/theme_art.dart';

/// Every course file with a learning path: the general course (Bölüm 1 and
/// the section files) and the professional courses.
List<File> _courseFiles() => [
  File('assets/courses/tr_en.json'),
  ...Directory('assets/courses/tr_en').listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
  ...Directory('assets/courses').listSync().whereType<File>().where((f) => f.path.contains('pro_')),
];

List<Map<String, dynamic>> _units() => [
  for (final f in _courseFiles())
    for (final u in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['units'] as List)
      u as Map<String, dynamic>,
];

void main() {
  group('topic themes', () {
    test('every unit names a theme that exists', () {
      final units = _units();
      expect(
        units.length,
        94 + 24 + 12 + 12 + 9,
        reason: '94 general units, 24 skill units, 24 C1 units (S9, S10) and 9 professional ones',
      );
      for (final u in units) {
        expect(topicThemes.keys, contains(u['theme']), reason: '${u['id']} ${u['title']}');
      }
    });

    test('tea is kept for greetings, guests, the neighbourhood and small talk', () {
      final tea = [
        for (final u in _units())
          if (u['theme'] == 'cay') u['id'],
      ];
      expect(tea, contains('u1'));
      expect(tea.length, lessThanOrEqualTo(8));
      final used = {for (final u in _units()) u['theme']};
      expect(used.length, greaterThanOrEqualTo(20), reason: 'units are spread over 20–30 themes');
    });

    test('20–30 themes, each complete and with its own lines', () {
      expect(topicThemes.length, inInclusiveRange(20, 30));
      final invites = <String>{};
      for (final t in topicThemes.values) {
        expect(t.steps.length, greaterThanOrEqualTo(3), reason: t.id);
        expect(t.decor, hasLength(2), reason: t.id);
        for (final line in [t.lessonInvite, t.storyInvite, t.testInvite, t.chestInvite]) {
          expect(line.length, lessThanOrEqualTo(34), reason: '${t.id}: "$line" fits the bubble');
        }
        expect(invites.add(t.lessonInvite), isTrue, reason: '${t.id} repeats another theme\'s line');
      }
      // Tea lines only in the tea theme.
      for (final t in topicThemes.values.where((t) => !t.tea)) {
        expect(t.lessonInvite.toLowerCase(), isNot(contains('çay')), reason: t.id);
      }
    });

    test('no theme picture is missing, every folder is bundled, the set stays small', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      var bytes = 0;
      for (final t in topicThemes.values) {
        expect(pubspec, contains('- assets/themes/${t.id}/'), reason: t.id);
        for (final o in t.objects) {
          final f = File(t.asset(o));
          expect(f.existsSync(), isTrue, reason: f.path);
          final svg = f.readAsStringSync();
          expect(svg, startsWith('<svg'), reason: f.path);
          bytes += svg.length;
        }
      }
      for (var i = 0; i < 8; i++) {
        expect(File(themeAsset(softwareThemeId, softwareTopicObject(i))).existsSync(), isTrue);
      }
      expect(bytes, lessThan(3 * 1024 * 1024));
    });

    test('a missing or unknown theme falls back to tea', () {
      expect(themeById(null).id, defaultThemeId);
      expect(themeById('yok-boyle-tema').id, defaultThemeId);
      final unit = Unit.fromJson({
        'id': 'x1',
        'title': 'Deneme',
        'color': '0xFF000000',
        'nodes': [
          {'id': 'x1l1', 'type': 'lesson', 'title': 'Ders'},
        ],
      });
      expect(unit.theme, isNull);
      expect(themeOf(unit).tea, isTrue);
      expect(nodeInvite(NodeType.lesson), 'Hadi, bir çay daha!');
    });

    test('a unit tells its topic as a story: each step has the next object', () {
      Unit unit(String theme) => Unit.fromJson({
        'id': 'x1',
        'title': 'Deneme',
        'color': '0xFF000000',
        'theme': theme,
        'nodes': [
          for (final (i, t) in ['lesson', 'lesson', 'story', 'lesson', 'test', 'chest'].indexed)
            {'id': 'x1n$i', 'type': t, 'title': 'Adım $i'},
        ],
      });
      final u = unit('seyahat');
      expect(u.nodes.map((n) => nodeObject(u, n)), [
        'bavul',
        'bilet',
        'ucak',
        'oda_anahtari',
        'pusula',
        'hediye_bavul',
      ]);
      expect(nodeInvite(NodeType.lesson, themeOf(u)), 'Biniş kartın hazır!');
      expect(nodeInvite(NodeType.lesson, themeOf(unit('yemek'))), 'Bir lokma daha!');
    });
  });

  group('themed nodes', () {
    Widget host(Widget child, {bool reduce = false, Brightness brightness = Brightness.light}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

    final seyahat = themeById('seyahat');

    testWidgets('done, current and locked steps draw the same object differently', (tester) async {
      await tester.pumpWidget(
        host(
          Row(
            children: [
              for (final s in NodeState.values)
                TeaNode(
                  key: Key('n-${s.name}'),
                  type: NodeType.lesson,
                  state: s,
                  color: Colors.blue,
                  theme: seyahat,
                  object: 'ucak',
                  onTap: () {},
                ),
            ],
          ),
          reduce: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-object-seyahat-ucak')), findsNWidgets(3));
      // Only the locked one is a grey silhouette; no steam on themed nodes.
      // The grey is a colour filter on the picture itself (no offscreen layer).
      bool filtered(Finder f) {
        final obj = tester.widget<ThemeObject>(find.descendant(of: f, matching: find.byType(ThemeObject)));
        return obj.grey || obj.tint != null;
      }

      expect(filtered(find.byKey(const Key('n-locked'))), isTrue);
      expect(filtered(find.byKey(const Key('n-done'))), isFalse);
      expect(filtered(find.byKey(const Key('n-active'))), isFalse);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byKey(const Key('steam')), findsNothing);
      expect(find.byKey(const Key('active-glow')), findsOneWidget);
    });

    testWidgets('the current object moves only while animations are allowed', (tester) async {
      Widget node() => TeaNode(
        type: NodeType.lesson,
        state: NodeState.active,
        color: Colors.blue,
        theme: seyahat,
        object: 'ucak',
        onTap: () {},
      );
      await tester.pumpWidget(host(node(), reduce: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(host(node()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('test badge and reward use the theme, also in dark mode', (tester) async {
      await tester.pumpWidget(
        host(
          Row(
            children: [
              TeaNode(
                type: NodeType.test,
                state: NodeState.locked,
                color: Colors.blue,
                theme: seyahat,
                object: seyahat.badge,
                onTap: () {},
              ),
              TeaNode(
                type: NodeType.chest,
                state: NodeState.done,
                color: Colors.blue,
                theme: seyahat,
                object: seyahat.reward,
                onTap: () {},
              ),
            ],
          ),
          reduce: true,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .toList();
      expect(painters.whereType<BadgePainter>().single.dim, isTrue);
      expect(find.byKey(const ValueKey('theme-object-seyahat-pusula')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-object-seyahat-hediye_bavul')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the host wears the theme costume', (tester) async {
      await tester.pumpWidget(host(PathMascot(mood: Mood.calm, theme: themeById('yemek'))));
      await tester.pump();
      expect(find.byKey(const Key('costume-yemek')), findsOneWidget);
      await tester.pumpWidget(host(PathMascot(mood: Mood.calm, theme: themeById('cay'))));
      await tester.pump();
      expect(find.byKey(const Key('costume-cay')), findsNothing);
    });
  });
}
