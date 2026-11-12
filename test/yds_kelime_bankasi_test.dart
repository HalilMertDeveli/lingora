// YDS word banks and their cards in assets/vocab/yds.json: ys5 (Faz 1, docs/sinav/yds-faz1-icerik.md)
// and ys7 (Faz 2a, docs/sinav/yds-faz2-icerik.md).
// - every card word is new: not taught before its bank (0 overlap)
// - cards are complete (example with Turkish, collocation, family for verbs and nouns)
// - the cards and the ys5 vocab lessons describe the same words.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/models/vocab.dart';

const _general = [
  'assets/courses/tr_en.json',
  'assets/courses/tr_en/02_gunluk_hayat.json',
  'assets/courses/tr_en/03_kendini_anlatmak.json',
  'assets/courses/tr_en/04_sehirde_ve_iste.json',
  'assets/courses/tr_en/05_deneyimler.json',
  'assets/courses/tr_en/06_fikirler_ve_hikayeler.json',
];
const _oldYds = [
  'assets/courses/exam_yds.json',
  'assets/courses/exam_yds/02_kelime_ve_kaliplar.json',
  'assets/courses/exam_yds/03_soru_tipleri.json',
  'assets/courses/exam_yds/04_deneme_ve_zaman.json',
];
const _cards = 'assets/vocab/yds.json';

/// The general course, all sections and skill files (Faz 2 exclusion set).
List<String> _generalAll() => [
  'assets/courses/tr_en.json',
  ...(Directory('assets/courses/tr_en')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => p.endsWith('.json'))
      .toList()
    ..sort()),
];

/// (section, file, units, taught-before files, earlier banks whose cards also count as taught)
final _banks = <(String, String, int, List<String> Function(), List<String>)>[
  ('ys5', 'assets/courses/exam_yds/05_kelime_bankasi_1.json', 10, () => [..._general, ..._oldYds], []),
  (
    'ys7',
    'assets/courses/exam_yds/07_kelime_bankasi_2.json',
    15,
    () => [..._generalAll(), ..._oldYds, 'assets/courses/exam_yds/05_kelime_bankasi_1.json'],
    ['ys5'],
  ),
  // Faz 3a: everything shipped before ys9 (sections 05–08, every yd_ and ydm_ card). No exceptions.
  (
    'ys9',
    'assets/courses/exam_yds/09_kelime_bankasi_3.json',
    12,
    () => [
      ..._generalAll(),
      ..._oldYds,
      for (final n in ['05_kelime_bankasi_1', '06_okuma_evi_1', '07_kelime_bankasi_2', '08_okuma_evi_2'])
        'assets/courses/exam_yds/$n.json',
    ],
    ['ys5', 'ys7', 'ys1', 'ys2', 'ys3', 'ys4'],
  ),
];

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync().replaceFirst('﻿', '')) as Map<String, dynamic>;

Iterable<Map<String, dynamic>> _exercises(String path) sync* {
  for (final u in _read(path)['units'] as List) {
    for (final n in (u as Map)['nodes'] as List) {
      for (final e in ((n as Map)['exercises'] as List?) ?? const []) {
        yield e as Map<String, dynamic>;
      }
    }
  }
}

/// Words a learner was taught: English side of match pairs, fillBlank answers, short correct choices.
Set<String> _taught(List<String> files) {
  final out = <String>{};
  void add(Object? w) {
    final s = '$w'.trim().toLowerCase();
    if (RegExp(r"^[a-z][a-z' -]*$").hasMatch(s) && s.split(' ').length <= 6) out.add(s);
  }

  for (final f in files) {
    for (final e in _exercises(f)) {
      switch (e['type']) {
        case 'match':
          for (final p in e['pairs'] as List) {
            add((p as List)[1]);
          }
        case 'fillBlank':
          add(e['answer']);
        case 'choice':
          add((e['options'] as List)[e['answer'] as int]);
      }
    }
  }
  return out;
}

/// Phrases of 4+ words that the old YDS path already teaches as match pairs. The overlap check counted
/// only 1–3-word items until after #51, so these shipped as bank cards. They stay on purpose
/// (yds-arastirma): removing them would orphan learners' card progress, and meeting them again is
/// recycling. New banks (F3+) must have no exceptions.
const _shippedOverlaps = {
  'on the other hand', 'in the long run', // ys5u10
  'to a large extent', 'for the most part', // ys7u14
  'in the absence of', 'with the exception of', 'in the wake of', // ys7u15
  'at the expense of', 'on the basis of', 'on the grounds that', // ys7u15
};

void main() {
  final vocabShipped = File(_cards).existsSync();

  test('yds.json: unique ids and words, ranks 1..N, topics are the shipped bank units, loads through VocabBundle', () {
    if (!vocabShipped) return;
    final vocab = _read(_cards);
    final entries = (vocab['entries'] as List).cast<Map<String, dynamic>>();
    expect(entries.map((e) => e['id']).toSet().length, entries.length);
    expect(entries.map((e) => (e['word'] as String).toLowerCase()).toSet().length, entries.length);
    expect([for (final e in entries) e['rank']], [for (var i = 1; i <= entries.length; i++) i]);
    final topics = [for (final t in vocab['topics'] as List) (t as Map)['name']];
    // Bank units first, then (Faz 2c) the old path's units for the ydm_ cards.
    final bankTopics = [
      for (final (sec, file, units, _, _) in _banks)
        if (File(file).existsSync())
          for (var i = 1; i <= units; i++) '${sec}u$i',
    ];
    expect(topics.take(bankTopics.length), bankTopics);
    expect(topics.skip(bankTopics.length).every((t) => RegExp(r'^ys[1-4]u\d+$').hasMatch('$t')), isTrue);
    // The app reads the cards through VocabBundle (YDS example contexts: genel/akademik/haber).
    final bundle = VocabBundle.fromJson(vocab);
    expect(bundle.entries.length, entries.length);
    expect(bundle.topics.map((t) => t.name).toSet(), containsAll(bundle.entries.map((e) => e.topic).toSet()));
  });

  for (final (sec, file, units, before, earlierBanks) in _banks) {
    final shipped = vocabShipped && File(file).existsSync();
    group('YDS kelime bankası $sec', skip: shipped ? false : 'not shipped yet', () {
      late final Map<String, dynamic> vocab = _read(_cards);
      late final List<Map<String, dynamic>> bankCards = [
        for (final e in vocab['entries'] as List)
          if (((e as Map)['topic'] as String).startsWith('${sec}u')) e as Map<String, dynamic>,
      ];

      // ys5 and ys7: 80 words a unit; ys9 (Faz 3a): 1,300 words over 12 units (108–109 each).
      final total = const {'ys5': 800, 'ys7': 1200, 'ys9': 1300}[sec]!;
      test('$total cards, about ${total ~/ units} per unit', () {
        expect(bankCards.length, total);
        for (var i = 1; i <= units; i++) {
          final n = bankCards.where((e) => e['topic'] == '${sec}u$i').length;
          expect(n, inInclusiveRange(total ~/ units, total ~/ units + 1), reason: '${sec}u$i');
        }
      });

      test('every card has a Turkish sense, an example with translation, a collocation and a family', () {
        final problems = <String>[];
        for (final e in bankCards) {
          final w = e['word'] as String;
          if (e['id'] != 'yd_${w.replaceAll(' ', '_')}') problems.add('$w: id');
          final senses = (e['senses'] as List).cast<Map>();
          if (senses.isEmpty || senses.any((s) => '${s['tr']}'.isEmpty || '${s['def']}'.isEmpty)) {
            problems.add('$w: senses');
          }
          final ex = (e['examples'] as List).cast<Map>();
          if (ex.isEmpty || ex.any((x) => '${x['tr']}'.isEmpty || !'${x['en']}'.contains('${x['target']}'))) {
            problems.add('$w: example');
          }
          final col = (e['collocations'] as List).cast<Map>();
          if (col.isEmpty ||
              col.any((c) => !'${c['phrase']}'.contains('${c['answer']}') || '${c['tr']}'.isEmpty)) {
            problems.add('$w: collocation');
          }
          if (RegExp('verb|noun').hasMatch(e['pos'] as String) && e['family'] is! List) {
            problems.add('$w: family');
          }
        }
        expect(problems, isEmpty, reason: problems.take(20).join('\n'));
      });

      test('no card word was taught before this bank', () {
        final taught = {
          ..._taught(before()),
          for (final e in vocab['entries'] as List)
            if (earlierBanks.any((b) => ((e as Map)['topic'] as String).startsWith('${b}u')))
              ((e as Map)['word'] as String).toLowerCase(),
        };
        final clash = [
          for (final e in bankCards)
            if (taught.contains((e['word'] as String).toLowerCase()) &&
                !_shippedOverlaps.contains((e['word'] as String).toLowerCase()))
              e['word'],
        ];
        expect(
          clash,
          isEmpty,
          reason: '${bankCards.length} kelime, ${clash.length} çakışma: ${clash.take(20).join(', ')}',
        );
      });

      test('every choice question names its YDS question type (qtype)', () {
        const qtypes = {
          'vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue', //
          'restatement', 'paragraphCompletion', 'irrelevantSentence',
        };
        final bad = [
          for (final e in _exercises(file))
            if (e['type'] == 'choice' && !qtypes.contains(e['qtype'])) e['question'],
        ];
        expect(bad, isEmpty, reason: bad.take(10).join('\n'));
      });

      test('each unit introduces its card words in its vocab lessons', () {
        for (final u in _read(file)['units'] as List) {
          final id = (u as Map)['id'] as String;
          final text = jsonEncode(u).toLowerCase();
          // Phrasal verbs may be inflected ("drew on" for "draw on"): their particles must appear.
          bool used(String w) {
            final parts = w.toLowerCase().split(' ');
            return text.contains(w.toLowerCase()) ||
                (parts.length > 1 && text.contains(' ${parts.skip(1).join(' ')}'));
          }

          final missing = [
            for (final e in bankCards)
              if (e['topic'] == id && !used(e['word'] as String)) e['word'],
          ];
          expect(missing, isEmpty, reason: '$id: $missing');
        }
      });
    });
  }
}
