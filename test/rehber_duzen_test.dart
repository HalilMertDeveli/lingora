import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/guide_view.dart';
import 'package:lingora/ui/markdown_text.dart';

/// Every `guide` string shipped in assets/, with where it came from.
List<(String, String)> _shippedGuides() {
  final out = <(String, String)>[];
  void walk(Object? o, String file) {
    if (o is List) {
      for (final x in o) {
        walk(x, file);
      }
    } else if (o is Map) {
      final g = o['guide'];
      if (g is String && g.contains('\n')) out.add(('$file ${o['id'] ?? o['title']}', g));
      for (final v in o.values) {
        walk(v, file);
      }
    }
  }

  for (final f in Directory('assets/courses').listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.json')) walk(jsonDecode(f.readAsStringSync()), f.path);
  }
  return out;
}

const _sample = '''
Giriş paragrafı.

## Kural
**1. Present simple:** alışkanlık bildirir.

**2. Present continuous:** şu an süren iş.

Özne + am/is/are + fiil-ing

**Dikkat:** *do/does* sonrası fiil yalın kalır.

## Örnekler
- *She works in a bank.* — Bankada çalışır.
- **love / like / enjoy + -ing**: sevmek. Örnek: I love playing the guitar.
- *sustain → sustainable → sustainability*

## Nasıl çözülür
1. Zaman zarfını bul.
2. Özneye bak.
3. Şıkları ele.

## Türklerin sık hatası
- Meslekten önce **a** düşer: ❌ I'm student. ✅ I'm a student.
- "I prefer hiking than climbing." → **I prefer hiking to climbing.**: prefer ile to kullanılır.

## Model metin
> Hi Sam,
>
> See you on Sunday!

## Sınav ipuçları
> **Sınav ipucu 1:** Boşluktan sonra than varsa karşılaştırma gelir.

> **Sınav ipucu 2:** Tabloya bak.

İpucu: Önce soruyu oku.

| Yanlış | Doğru |
|---|---|
| I am agree. | **I agree.** |
''';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppMode mode = AppMode.adult,
  Brightness b = Brightness.light,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(mode: mode, brightness: b),
      builder: (_, c) => PaletteScope(palette: Palette.of(mode, b), child: c!),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    ),
  );
}

void main() {
  group('guide parser', () {
    final sections = guideSections(_sample);
    List<MdBlock> of(String title) => sections.firstWhere((s) => s.title == title).blocks;

    test('splits by heading and guesses each section topic', () {
      expect(sections.map((s) => s.title), [
        '',
        'Kural',
        'Örnekler',
        'Nasıl çözülür',
        'Türklerin sık hatası',
        'Model metin',
        'Sınav ipuçları',
      ]);
      expect(sections.map((s) => s.topic), [
        GuideTopic.other,
        GuideTopic.rule,
        GuideTopic.example,
        GuideTopic.steps,
        GuideTopic.mistakes,
        GuideTopic.example,
        GuideTopic.tips,
      ]);
      expect(guideTopic('Biz nasıl söylüyoruz?'), GuideTopic.compare);
      expect(guideTopic('Hedef kalıplar'), GuideTopic.rule);
      expect(guideTopic('Bu ünitede yapabileceklerin'), GuideTopic.goal);
      expect(guideTopic('Anahtar kelimeler'), GuideTopic.words);
    });

    test('bold numbered paragraphs become steps; formulas become chips; labels become callouts', () {
      final rule = of('Kural');
      expect(rule.map((b) => b.kind), [MdKind.numbered, MdKind.numbered, MdKind.pattern, MdKind.tip]);
      expect(rule[0].number, 1);
      expect(rule[0].text, '**Present simple:** alışkanlık bildirir.');
      expect(rule[2].parts, ['Özne', 'am/is/are', 'fiil-ing']);
      expect(rule[3].tone, CalloutTone.warning);
      expect(rule[3].label, 'Dikkat');
      expect(rule[3].text, '*do/does* sonrası fiil yalın kalır.');
    });

    test('examples, formula bullets with "Örnek:" and word families', () {
      final ex = of('Örnekler');
      expect(ex.map((b) => b.kind), [MdKind.example, MdKind.bullet, MdKind.pattern]);
      expect((ex[0].text, ex[0].translation), ('She works in a bank.', 'Bankada çalışır.'));
      expect(ex[1].parts, ['love / like / enjoy', '-ing']);
      expect((ex[1].text, ex[1].example), ('sevmek.', 'I love playing the guitar.'));
      expect(ex[2].parts, ['sustain', 'sustainable', 'sustainability']);
      expect(ex[2].joiner, '→');
    });

    test('mistakes: ❌/✅ and "…" → **…** forms', () {
      final m = of('Türklerin sık hatası');
      expect(m.map((b) => b.kind), [MdKind.mistake, MdKind.mistake]);
      expect(
        (m[0].label, m[0].text, m[0].translation),
        ('Meslekten önce **a** düşer:', "I'm student.", "I'm a student."),
      );
      expect(m[1].text, '"I prefer hiking than climbing."');
      expect(m[1].translation, '**I prefer hiking to climbing.**');
      expect(m[1].example, 'prefer ile to kullanılır.');
    });

    test('a model text is a quote that keeps its line breaks; exam tips stay separate tips', () {
      final q = of('Model metin').single;
      expect(q.kind, MdKind.quote);
      expect(q.text, 'Hi Sam,\n\nSee you on Sunday!');
      final tips = of('Sınav ipuçları');
      expect(tips.map((b) => (b.kind, b.label)), [
        (MdKind.tip, 'Sınav ipucu 1'),
        (MdKind.tip, 'Sınav ipucu 2'),
        (MdKind.tip, 'İpucu'),
        (MdKind.table, ''),
      ]);
      expect(tips.first.text, 'Boşluktan sonra than varsa karşılaştırma gelir.');
    });

    test('reading passages (guide: false) keep the old plain reading', () {
      final b = parseMarkdown('- *She works.* — Çalışır.\n> Hi Sam,\n> bye\n**1. Bir:** iki');
      expect(b.map((x) => x.kind), [MdKind.bullet, MdKind.tip, MdKind.paragraph]);
      expect(b[1].text, 'Hi Sam, bye');
    });

    test('no shipped guide loses a word in the guide reading', () {
      final guides = _shippedGuides();
      expect(guides.length, greaterThan(150));
      final word = RegExp(r"[A-Za-zÇĞİÖŞÜçğıöşüâîû0-9']+");
      for (final (where, g) in guides) {
        final blocks = parseMarkdown(g, guide: true);
        final shown = StringBuffer();
        for (final b in blocks) {
          shown
            ..writeln(b.number)
            ..writeln(b.text)
            ..writeln(b.translation)
            ..writeln(b.example)
            ..writeln(b.label)
            ..writeln(b.parts.join(' '));
          for (final r in b.rows) {
            shown.writeln(r.join(' '));
          }
        }
        final have = word.allMatches(shown.toString()).map((m) => m[0]).toSet();
        // The "Örnek" label of a bullet is drawn as the example box's icon.
        final missing = word
            .allMatches(g)
            .map((m) => m[0]!)
            .where((w) => !have.contains(w) && w != 'Örnek')
            .toSet();
        expect(missing, isEmpty, reason: where);
      }
    });
  });

  group('guide view', () {
    for (final mode in AppMode.values) {
      for (final b in Brightness.values) {
        testWidgets('draws section cards, steps, callouts, examples and chips (${mode.name}, ${b.name})', (
          tester,
        ) async {
          await _pump(tester, const GuideView(_sample), mode: mode, b: b);
          expect(tester.takeException(), isNull);
          // One coloured card per section, a heading in each titled one.
          expect(find.byKey(const Key('guide-section-0')), findsOneWidget);
          expect(find.byKey(const Key('md-h2')), findsNWidgets(6));
          // Numbered "Nasıl çözülür" items are "Adım" steps.
          expect(find.text('ADIM 1'), findsOneWidget);
          expect(find.text('ADIM 3'), findsOneWidget);
          expect(find.byKey(const Key('md-steps')), findsNWidgets(2));
          expect(find.byKey(const Key('md-callout-warning')), findsOneWidget);
          expect(find.byKey(const Key('md-callout-tip')), findsNWidgets(3));
          expect(find.text('Sınav ipucu 1'), findsOneWidget);
          expect(find.byKey(const Key('md-example')), findsNWidgets(2));
          expect(find.byKey(const Key('md-pattern')), findsNWidgets(3));
          expect(find.byKey(const Key('md-mistake')), findsNWidgets(2));
          expect(find.byKey(const Key('md-quote')), findsOneWidget);
          expect(find.byKey(const Key('md-table')), findsOneWidget);
        });
      }
    }

    testWidgets('bullets have coloured dots in the section colour', (tester) async {
      await _pump(tester, const GuideView('## Strateji\n- bir\n- iki'));
      expect(find.byKey(const Key('md-bullet')), findsNWidgets(2));
      final dot = tester
          .widgetList<Container>(
            find.descendant(of: find.byKey(const Key('md-bullet')).first, matching: find.byType(Container)),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.shape == BoxShape.circle);
      expect(dot.color, guideLook(GuideTopic.steps, Palette.adultLight).color);
    });

    testWidgets('every shipped guide draws on a small phone without overflow (kid, dark)', (tester) async {
      final guides = _shippedGuides();
      for (var i = 0; i < guides.length; i += 2) {
        await _pump(tester, GuideView(guides[i].$2), mode: AppMode.kid, b: Brightness.dark, width: 320);
        expect(tester.takeException(), isNull, reason: guides[i].$1);
      }
    });
  });
}
