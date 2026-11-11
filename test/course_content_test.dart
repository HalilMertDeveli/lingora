// Contract checks for the main course's section files,
// assets/courses/tr_en/NN_slug.json (see _cikti/ders_plan.md). Every shipped
// section file is validated; the fixture in test/fixtures/tr_en/ shows that a
// valid section passes and that the checks catch broken ones.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/models/course.dart';

const sectionDir = 'assets/courses/tr_en';
const fixtureDir = 'test/fixtures/tr_en';

/// Node types of every unit, in order.
const unitPattern = ['lesson', 'lesson', 'story', 'lesson', 'lesson', 'test', 'chest'];
const cefrLevels = {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'};
const exerciseTypes = {'select', 'translate', 'fillBlank', 'listen', 'match', 'speak'};

List<File> sectionFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Node and unit ids of tr_en.json (section 1).
Set<String> baseIds() {
  final j = jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final u in j['units'] as List) ...[
      (u as Map)['id'] as String,
      for (final n in u['nodes'] as List) (n as Map)['id'] as String,
    ],
  };
}

/// Whether [answer] can be built from the word bank [tokens] (each token used once).
bool buildable(String answer, List<String> tokens) {
  final bank = <String, int>{};
  for (final t in tokens) {
    for (final w in normalizeAnswer(t).split(' ').where((w) => w.isNotEmpty)) {
      bank[w] = (bank[w] ?? 0) + 1;
    }
  }
  for (final w in normalizeAnswer(answer).split(' ').where((w) => w.isNotEmpty)) {
    final left = bank[w] ?? 0;
    if (left == 0) return false;
    bank[w] = left - 1;
  }
  return true;
}

/// Problems with one section file; empty when it follows the contract. [seen]
/// holds ids used so far (tr_en.json and earlier files) and is extended.
List<String> validateSection(String fileName, Object? json, Set<String> seen) {
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add('$fileName: $message');
  }

  bool str(Object? v) => v is String && v.trim().isNotEmpty;
  List<String>? strList(Object? v) => v is List && v.isNotEmpty && v.every(str) ? v.cast<String>() : null;
  void unique(String id) => check(seen.add(id), 'id "$id" kullanılmış');

  if (json is! Map<String, dynamic>) return ['$fileName: kök bir JSON nesnesi değil'];
  final section = json['section'];
  if (section is! Map<String, dynamic>) return ['$fileName: "section" nesnesi yok'];

  final name = RegExp(r'^(\d\d)_[a-z0-9_]+\.json$').firstMatch(fileName);
  check(name != null, 'dosya adı NN_slug.json biçiminde değil');
  final index = section['index'];
  check(index is int && index >= 2, 'section.index 2 veya büyük bir sayı olmalı');
  if (name != null && index is int) {
    check(int.parse(name.group(1)!) == index, 'dosya numarası index ile aynı değil');
  }
  check(section['id'] == 's$index', 'section.id "s$index" olmalı');
  check(str(section['title']), 'section.title yok');
  check(cefrLevels.contains(section['cefr']), 'section.cefr A1–C2 olmalı');
  check(str(section['description']), 'section.description yok');
  check(strList(section['grammar']) != null, 'section.grammar boş olmayan bir metin listesi olmalı');
  if (section['id'] is String) unique(section['id'] as String);

  final units = json['units'];
  if (units is! List || units.isEmpty) return [...problems, '$fileName: "units" boş'];
  for (final (ui, u) in units.indexed) {
    if (u is! Map<String, dynamic>) {
      check(false, 'units[$ui] nesne değil');
      continue;
    }
    final unitId = u['id'];
    final where = 'ünite ${unitId ?? ui}';
    check(unitId is String && RegExp('^s${index}u\\d+\$').hasMatch(unitId), '$where: id s${index}uN olmalı');
    if (unitId is String) unique(unitId);
    check(str(u['title']), '$where: title yok');
    check(u['description'] is String, '$where: description yok');
    check(
      u['color'] is String && RegExp(r'^0x[0-9A-Fa-f]{8}$').hasMatch(u['color'] as String),
      '$where: color',
    );
    final nodes = u['nodes'];
    if (nodes is! List) {
      check(false, '$where: nodes yok');
      continue;
    }
    final types = [for (final n in nodes) n is Map ? n['type'] : null];
    check(types.join(',') == unitPattern.join(','), '$where: düğüm deseni ${types.join(',')}');
    for (final n in nodes.whereType<Map<String, dynamic>>()) {
      final id = n['id'];
      final at = '$where/${id ?? '?'}';
      check(id is String && unitId is String && id.startsWith(unitId), '$at: id ünite id ile başlamalı');
      if (id is String) unique(id);
      check(str(n['title']), '$at: title yok');
      switch (n['type']) {
        case 'lesson':
          final exercises = n['exercises'];
          if (exercises is! List) {
            check(false, '$at: exercises yok');
            break;
          }
          check(exercises.length >= 8 && exercises.length <= 10, '$at: ${exercises.length} alıştırma (8–10)');
          for (final (i, e) in exercises.indexed) {
            problems.addAll(validateExercise(e, '$fileName: $at#$i'));
          }
        case 'story':
          final steps = n['steps'];
          check(steps is List && steps.isNotEmpty, '$at: steps yok');
          for (final s in (steps is List ? steps : const []).whereType<Map>()) {
            if (s['kind'] == 'question') {
              final choices = strList(s['choices']);
              check(str(s['prompt']) && choices != null, '$at: soru alanları eksik');
              check(choices?.contains(s['answer']) ?? false, '$at: cevap "${s['answer']}" seçeneklerde yok');
            } else {
              check(s['kind'] == 'line' && str(s['speaker']) && str(s['text']), '$at: satır alanları eksik');
            }
          }
          check(n['rewardXp'] is int, '$at: rewardXp yok');
        case 'test' || 'chest':
          check(n['rewardXp'] is int && (n['rewardXp'] as int) > 0, '$at: rewardXp yok');
      }
    }
  }

  // The app must be able to read it.
  if (problems.isEmpty) {
    try {
      Section.fromFile(json);
    } catch (e) {
      problems.add('$fileName: uygulama okuyamıyor: $e');
    }
  }
  return problems;
}

/// Problems with one exercise.
List<String> validateExercise(Object? e, String at) {
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add('$at: $message');
  }

  bool str(Object? v) => v is String && v.trim().isNotEmpty;
  List<String>? strList(Object? v) => v is List && v.isNotEmpty && v.every(str) ? v.cast<String>() : null;

  if (e is! Map<String, dynamic>) return ['$at: nesne değil'];
  final type = e['type'];
  if (!exerciseTypes.contains(type)) return ['$at: bilinmeyen tür "$type"'];
  switch (type) {
    case 'select':
      final choices = e['choices'];
      final texts = [
        if (choices is List)
          for (final c in choices)
            if (c is Map && str(c['text'])) c['text'] as String,
      ];
      check(str(e['prompt']), 'prompt yok');
      check(
        choices is List && texts.length == choices.length && texts.length >= 2,
        'choices {text, emoji} olmalı',
      );
      check(texts.contains(e['answer']), 'cevap "${e['answer']}" seçeneklerde yok');
    case 'fillBlank':
      final choices = strList(e['choices']);
      check(str(e['text']) && (e['text'] as String).contains('___'), 'text "___" içermeli');
      check(str(e['translation']), 'translation yok');
      check(choices != null && choices.length >= 2, 'choices yok');
      check(choices?.contains(e['answer']) ?? false, 'cevap "${e['answer']}" seçeneklerde yok');
    case 'translate':
      final answers = strList(e['answers']);
      final tokens = strList(e['tokens']);
      check(str(e['text']), 'text yok');
      check(e['lang'] == 'tr' || e['lang'] == 'en', 'lang tr ya da en olmalı');
      check(answers != null, 'answers yok');
      check(tokens != null, 'tokens yok');
      if (answers != null && tokens != null) {
        check(
          answers.any((a) => buildable(a, tokens)),
          'hiçbir cevap token\'larla kurulamıyor: ${answers.first}',
        );
      }
    case 'listen':
      check(str(e['text']), 'text yok');
      check(strList(e['answers']) != null, 'answers yok');
    case 'match':
      final pairs = e['pairs'];
      final ok =
          pairs is List &&
          pairs.length >= 3 &&
          pairs.every((p) => p is List && p.length == 2 && p.every(str));
      check(ok, 'pairs en az 3 [tr, en] çifti olmalı');
      if (ok) {
        final left = {for (final p in pairs) normalizeAnswer((p as List)[0] as String)};
        final right = {for (final p in pairs) normalizeAnswer((p as List)[1] as String)};
        check(left.length == pairs.length && right.length == pairs.length, 'çiftler benzersiz değil');
      }
    case 'speak':
      check(str(e['text']), 'text yok');
  }
  return problems;
}

/// Validates [files] in order against tr_en.json's ids.
List<String> validateAll(List<File> files) {
  final seen = baseIds();
  return [
    for (final f in files)
      ...validateSection(f.uri.pathSegments.last, jsonDecode(f.readAsStringSync()), seen),
  ];
}

void main() {
  test('shipped section files follow the contract', () {
    // Passes with an empty folder too: the content teams add the files.
    final problems = validateAll(sectionFiles(sectionDir));
    expect(problems, isEmpty, reason: problems.take(30).join('\n'));
  });

  test('section folder is declared in pubspec.yaml and keeps no fixture', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/courses/tr_en/'));
    for (final f in sectionFiles(sectionDir)) {
      expect(f.readAsStringSync(), isNot(contains('test fixture')), reason: f.path);
    }
  });

  group('fixture section', () {
    final files = sectionFiles(fixtureDir);

    test('exists and passes', () {
      expect(files, isNotEmpty);
      final problems = validateAll(files);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    Map<String, dynamic> fixture() => jsonDecode(files.first.readAsStringSync()) as Map<String, dynamic>;
    List<String> broken(void Function(Map<String, dynamic> j) breakIt, [String name = '02_ornek.json']) {
      final j = fixture();
      breakIt(j);
      return validateSection(name, j, baseIds());
    }

    Map<String, dynamic> unit(Map<String, dynamic> j) => (j['units'] as List).first as Map<String, dynamic>;
    Map<String, dynamic> lesson(Map<String, dynamic> j) =>
        (unit(j)['nodes'] as List).first as Map<String, dynamic>;
    List<dynamic> exercises(Map<String, dynamic> j) => lesson(j)['exercises'] as List;
    Map<String, dynamic> firstOf(Map<String, dynamic> j, String type) =>
        exercises(j).cast<Map<String, dynamic>>().firstWhere((e) => e['type'] == type);

    test('catches a duplicate id, also against tr_en.json', () {
      expect(broken((j) => lesson(j)['id'] = 'u1l1'), anyElement(contains('"u1l1" kullanılmış')));
      expect(
        broken((j) => (unit(j)['nodes'] as List)[1]['id'] = lesson(j)['id']),
        anyElement(contains('kullanılmış')),
      );
    });

    test('catches a wrong node pattern and lesson size', () {
      expect(broken((j) => (unit(j)['nodes'] as List).removeLast()), anyElement(contains('düğüm deseni')));
      expect(broken((j) => exercises(j).removeRange(0, 3)), anyElement(contains('alıştırma (8–10)')));
    });

    test('catches answers missing from the choices or the word bank', () {
      expect(
        broken((j) => firstOf(j, 'select')['answer'] = 'pizza'),
        anyElement(contains('seçeneklerde yok')),
      );
      expect(
        broken((j) => firstOf(j, 'fillBlank')['answer'] = 'pizza'),
        anyElement(contains('seçeneklerde yok')),
      );
      expect(
        broken((j) => firstOf(j, 'translate')['tokens'] = ['I', 'am']),
        anyElement(contains('token\'larla kurulamıyor')),
      );
    });

    test('catches missing fields, bad types and file naming', () {
      expect(broken((j) => firstOf(j, 'listen').remove('answers')), anyElement(contains('answers yok')));
      expect(broken((j) => exercises(j).add({'type': 'draw'})), anyElement(contains('bilinmeyen tür')));
      expect(broken((j) => (j['section'] as Map).remove('cefr')), anyElement(contains('cefr')));
      expect(broken((_) {}, '3_ornek.json'), anyElement(contains('dosya adı')));
      expect(broken((_) {}, '03_ornek.json'), anyElement(contains('index ile aynı değil')));
    });

    test('token check accepts any order and contractions', () {
      expect(buildable("I don't drink coffee", ['coffee', "don't", 'I', 'drink', 'tea']), isTrue);
      expect(buildable('I am a student', ['I', 'a', 'student']), isFalse);
      expect(buildable('the the', ['the']), isFalse);
    });
  });
}
