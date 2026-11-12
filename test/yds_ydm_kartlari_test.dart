// YDS Faz 2c (docs/sinav/yds-faz2-icerik.md § F2c): full cards for the old YDS path's words.
// A bridge card (match pair of a `vocab` lesson, made by courseWordCards) and its full card must share the
// id wordCardId('ydm_', word), so learners' progress carries over.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/study/review_queue.dart' show wordCardId;

const _oldYds = [
  'assets/courses/exam_yds.json',
  'assets/courses/exam_yds/02_kelime_ve_kaliplar.json',
  'assets/courses/exam_yds/03_soru_tipleri.json',
  'assets/courses/exam_yds/04_deneme_ve_zaman.json',
];

Map<String, dynamic> _read(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final vocab = _read('assets/vocab/yds.json');
  final ydm = [
    for (final e in vocab['entries'] as List)
      if (((e as Map)['id'] as String).startsWith('ydm_')) e as Map<String, dynamic>,
  ];

  group('YDS ydm_ kartları', skip: ydm.isEmpty ? 'not shipped yet' : false, () {
    // Bridge words in path order, first occurrence wins — as courseWordCards makes them.
    final bridges = <String, (String, String)>{}; // id → (word, unit)
    for (final f in _oldYds) {
      for (final u in _read(f)['units'] as List) {
        for (final n in (u as Map)['nodes'] as List) {
          if ((n as Map)['type'] != 'lesson' || n['vocab'] != true) continue;
          for (final e in (n['exercises'] as List).cast<Map>()) {
            if (e['type'] != 'match') continue;
            for (final p in (e['pairs'] as List).cast<List>()) {
              bridges.putIfAbsent(
                wordCardId('ydm_', p[1] as String),
                () => (p[1] as String, u['id'] as String),
              );
            }
          }
        }
      }
    }
    final ydWords = {
      for (final e in vocab['entries'] as List)
        if (((e as Map)['id'] as String).startsWith('yd_')) (e['word'] as String).trim().toLowerCase(),
    };

    test('every id is wordCardId(ydm_, word); unique; topics are old-path units', () {
      final ids = <String>{};
      for (final e in ydm) {
        expect(e['id'], wordCardId('ydm_', e['word'] as String), reason: '${e['word']}');
        expect(ids.add(e['id'] as String), isTrue, reason: 'duplicate ${e['id']}');
        expect(e['topic'], matches(RegExp(r'^ys[1-4]u\d+$')), reason: '${e['id']}');
        expect(
          ydWords,
          isNot(contains((e['word'] as String).toLowerCase())),
          reason: '${e['id']} has a yd_ card',
        );
      }
    });

    test('every bridge word not covered by a yd_ card has its full card, same word and unit', () {
      final byId = {for (final e in ydm) e['id'] as String: e};
      final missing = <String>[];
      for (final MapEntry(key: id, value: (word, unit)) in bridges.entries) {
        if (ydWords.contains(word.trim().toLowerCase())) continue;
        final card = byId[id];
        if (card == null) {
          missing.add(id);
          continue;
        }
        expect(card['word'], word.trim(), reason: id);
        expect(card['topic'], unit, reason: id);
      }
      expect(missing, isEmpty, reason: missing.take(20).join(', '));
    });

    test('cards are complete: Turkish sense, example with translation, collocation', () {
      for (final e in ydm) {
        final id = e['id'];
        expect((e['senses'] as List), isNotEmpty, reason: '$id');
        final ex = (e['examples'] as List).cast<Map>();
        expect(ex, isNotEmpty, reason: '$id');
        expect(
          ex.every((x) => '${x['en']}'.contains('${x['target']}') && '${x['tr']}'.isNotEmpty),
          isTrue,
          reason: '$id',
        );
        expect((e['collocations'] as List), isNotEmpty, reason: '$id');
      }
    });
  });
}
