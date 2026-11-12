// YDS Faz 1 (docs/sinav/yds-faz1-icerik.md): the ys5 word bank and its cards in assets/vocab/yds.json.
// - every card word is new: not taught in the general course s1–s6 nor in the old YDS path (0 overlap)
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
const _bank = 'assets/courses/exam_yds/05_kelime_bankasi_1.json';
const _cards = 'assets/vocab/yds.json';

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
    if (RegExp(r"^[a-z][a-z' -]*$").hasMatch(s) && s.split(' ').length <= 3) out.add(s);
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

void main() {
  final shipped = File(_cards).existsSync() && File(_bank).existsSync();

  group('YDS kelime bankası 1', skip: shipped ? false : 'not shipped yet', () {
    late final Map<String, dynamic> vocab = _read(_cards);
    late final List<Map<String, dynamic>> bankCards = [
      for (final e in vocab['entries'] as List)
        if (((e as Map)['topic'] as String).startsWith('ys5u')) e as Map<String, dynamic>,
    ];

    test('800 cards, unique ids and words, ranks 1..N, topics are the 10 ys5 units', () {
      final entries = (vocab['entries'] as List).cast<Map<String, dynamic>>();
      expect(bankCards.length, 800);
      expect(entries.map((e) => e['id']).toSet().length, entries.length);
      expect(entries.map((e) => (e['word'] as String).toLowerCase()).toSet().length, entries.length);
      expect([for (final e in entries) e['rank']], [for (var i = 1; i <= entries.length; i++) i]);
      final topics = [for (final t in vocab['topics'] as List) (t as Map)['name']];
      expect(topics, [for (var i = 1; i <= 10; i++) 'ys5u$i']);
      for (final t in topics) {
        expect(bankCards.where((e) => e['topic'] == t), hasLength(80), reason: '$t');
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

    test('no card word was taught before (general course s1–s6, YDS path ys1–ys4)', () {
      final taught = _taught([..._general, ..._oldYds]);
      final clash = [
        for (final e in bankCards)
          if (taught.contains((e['word'] as String).toLowerCase())) e['word'],
      ];
      expect(clash, isEmpty, reason: '800 kelime, ${clash.length} çakışma: ${clash.take(20).join(', ')}');
    });

    test('every choice question names its YDS question type (qtype)', () {
      const qtypes = {
        'vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue', //
        'restatement', 'paragraphCompletion', 'irrelevantSentence',
      };
      final bad = [
        for (final e in _exercises(_bank))
          if (e['type'] == 'choice' && !qtypes.contains(e['qtype'])) e['question'],
      ];
      expect(bad, isEmpty, reason: bad.take(10).join('\n'));
    });

    // The app reads the cards through VocabBundle (YDS example contexts: genel/akademik/haber).
    test('cards load through VocabBundle', () {
      final bundle = VocabBundle.fromJson(vocab);
      expect(bundle.entries.length, (vocab['entries'] as List).length);
      // Every card's topic is a listed unit (compared as sets: 800 cards, 10 topics).
      expect(
        bundle.topics.map((t) => t.name).toSet(),
        containsAll(bundle.entries.map((e) => e.topic).toSet()),
      );
    });

    test('each unit introduces its card words in its vocab lessons', () {
      final bank = _read(_bank);
      for (final u in bank['units'] as List) {
        final id = (u as Map)['id'] as String;
        final text = jsonEncode(u).toLowerCase();
        final missing = [
          for (final e in bankCards)
            if (e['topic'] == id && !text.contains((e['word'] as String).toLowerCase())) e['word'],
        ];
        expect(missing, isEmpty, reason: '$id: $missing');
      }
    });
  });
}
