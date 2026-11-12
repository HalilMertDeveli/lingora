// Contract checks for the main course's section files,
// assets/courses/tr_en/NN_slug.json (see _cikti/ders_plan.md). Every shipped
// section file is validated; the fixture in test/fixtures/tr_en/ shows that a
// valid section passes and that the checks catch broken ones.
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/models/course.dart';

const sectionDir = 'assets/courses/tr_en';
const fixtureDir = 'test/fixtures/tr_en';

/// Node types of every unit, in order.
const unitPattern = ['lesson', 'lesson', 'story', 'lesson', 'lesson', 'test', 'chest'];
const cefrLevels = {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'};
const exerciseTypes = {'select', 'translate', 'fillBlank', 'listen', 'match', 'speak', 'choice'};

List<File> sectionFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Section, unit and node ids of tr_en.json (section 1).
Set<String> baseIds() {
  final j = jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    's1',
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
  final extension = json.containsKey('extends');
  final int index;
  if (extension) {
    // NNx_slug.json: {"extends": "sNN", "units": [...]} adds units to the end
    // of an earlier section (see loadSections). New units bring a guide.
    final name = RegExp(r'^(\d\d)x_[a-z0-9_]+\.json$').firstMatch(fileName);
    if (name == null) return ['$fileName: genişletme dosyasının adı NNx_slug.json olmalı'];
    index = int.parse(name.group(1)!);
    check(json['extends'] == 's$index', 'extends "s$index" olmalı');
    check(json.keys.toSet().difference({'extends', 'units'}).isEmpty, 'yalnızca extends ve units olmalı');
    check(seen.contains('s$index'), 'genişletilen bölüm s$index daha önce gelmeli');
  } else {
    final section = json['section'];
    if (section is! Map<String, dynamic>) return ['$fileName: "section" nesnesi yok'];

    final name = RegExp(r'^(\d\d)_[a-z0-9_]+\.json$').firstMatch(fileName);
    check(name != null, 'dosya adı NN_slug.json biçiminde değil');
    final i = section['index'];
    check(i is int && i >= 2, 'section.index 2 veya büyük bir sayı olmalı');
    if (name != null && i is int) {
      check(int.parse(name.group(1)!) == i, 'dosya numarası index ile aynı değil');
    }
    index = i is int ? i : -1;
    check(section['id'] == 's$index', 'section.id "s$index" olmalı');
    check(str(section['title']), 'section.title yok');
    check(cefrLevels.contains(section['cefr']), 'section.cefr A1–C2 olmalı');
    check(str(section['description']), 'section.description yok');
    check(strList(section['grammar']) != null, 'section.grammar boş olmayan bir metin listesi olmalı');
    if (section['id'] is String) unique(section['id'] as String);
  }
  // Section 1 (tr_en.json) numbers its units u1, u2, …
  final unitPrefix = index == 1 ? 'u' : 's${index}u';

  final units = json['units'];
  if (units is! List || units.isEmpty) return [...problems, '$fileName: "units" boş'];
  for (final (ui, u) in units.indexed) {
    if (u is! Map<String, dynamic>) {
      check(false, 'units[$ui] nesne değil');
      continue;
    }
    final unitId = u['id'];
    final where = 'ünite ${unitId ?? ui}';
    check(
      unitId is String && RegExp('^$unitPrefix\\d+\$').hasMatch(unitId),
      '$where: id ${unitPrefix}N olmalı',
    );
    if (extension) {
      check(u['theme'] is String, '$where: theme yok');
      check(u['guide'] is String && (u['guide'] as String).trim().length > 200, '$where: Türkçe guide yok');
    }
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
      if (extension) {
        for (final u in units) {
          Unit.fromJson(u as Map<String, dynamic>);
        }
      } else {
        Section.fromFile(json);
      }
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
    case 'choice':
      final options = strList(e['options']);
      final answer = e['answer'];
      check(str(e['question']), 'question yok');
      check(
        options != null && options.length >= 4 && options.length <= 5,
        'options 4 (LGS) ya da 5 (YDS) olmalı',
      );
      if (options != null) {
        check(options.map((o) => o.trim().toLowerCase()).toSet().length == options.length, 'seçenekler aynı');
      }
      check(answer is int && answer >= 0 && answer < (options?.length ?? 0), 'answer seçenek sırası olmalı');
      check(str(e['explanation']), 'Türkçe explanation yok');
      check(!e.containsKey('passage') || str(e['passage']), 'passage boş');
  }
  return problems;
}

/// Exam study paths: `assets/courses/<id>.json` plus `<id>/NN_slug.json`
/// (_cikti/sinav_yolu_plan.md). [prefix] is the id letter ("l" LGS, "y"
/// YDS), [options] the option count of its choice questions and [testSize]
/// the allowed size of a unit test's own questions (a test node without
/// questions samples the lessons). No file, no problems: the YDS path ships
/// in its own PR.
List<String> validateExamPath(String id, String prefix, int options, {(int, int) testSize = (10, 20)}) {
  final top = File('assets/courses/$id.json');
  if (!top.existsSync()) return const [];
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add(message);
  }

  final seen = <String>{};
  final j = jsonDecode(top.readAsStringSync()) as Map<String, dynamic>;
  check(
    j['id'] == id && j['fromLang'] == 'tr' && j['learningLang'] == 'en',
    '$id.json: id/fromLang/learningLang',
  );
  final files = <(String, Map<String, dynamic>)>[
    ('$id.json', {'section': j['section'], 'units': j['units']}),
    for (final f in sectionFiles('assets/courses/$id'))
      (f.uri.pathSegments.last, jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
  ];
  var choices = 0;
  final letters = <int, int>{};
  for (final (i, (name, file)) in files.indexed) {
    final section = file['section'];
    if (section is! Map<String, dynamic>) {
      check(false, '$name: "section" yok');
      continue;
    }
    final index = section['index'];
    check(index == i + 1, '$name: section.index ${i + 1} olmalı');
    if (i > 0) {
      final m = RegExp(r'^(\d\d)_[a-z0-9_]+\.json$').firstMatch(name);
      check(m != null && int.parse(m.group(1)!) == index, '$name: dosya adı NN_slug.json, NN == index');
    }
    check(section['id'] == '${prefix}s$index', '$name: section.id "${prefix}s$index" olmalı');
    check(section['title'] is String && section['grammar'] is List, '$name: section title/grammar');
    final units = ((file['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
    check(units.isNotEmpty, '$name: ünite yok');
    for (final (ui, u) in units.indexed) {
      final unitId = u['id'] as String?;
      final where = '$name/$unitId';
      check(unitId != null && RegExp('^${prefix}s${index}u\\d+\$').hasMatch(unitId), '$where: id biçimi');
      if (unitId != null) check(seen.add(unitId), '$where: id kullanılmış');
      check(u['theme'] is String, '$where: theme yok');
      check(u['guide'] is String && (u['guide'] as String).trim().length > 200, '$where: guide yok');
      final nodes = (u['nodes'] as List).cast<Map<String, dynamic>>();
      final types = nodes.map((n) => n['type'] as String?).toList();
      // Lessons (and optional stories), then test and chest, then an
      // optional mock; the section's last unit always ends with a mock.
      final mock = types.isNotEmpty && types.last == 'mock';
      final tail = mock ? ['test', 'chest', 'mock'] : ['test', 'chest'];
      final head = types.take(max(0, types.length - tail.length)).toList();
      check(
        types.length > tail.length &&
            types.skip(types.length - tail.length).join(',') == tail.join(',') &&
            head.every((t) => t == 'lesson' || t == 'story') &&
            head.where((t) => t == 'lesson').length >= 4 &&
            (mock || ui < units.length - 1),
        '$where: düğüm deseni ${types.join(',')} (ders×4+, test, chest, [mock]; bölüm sonunda mock)',
      );
      for (final n in nodes) {
        final nid = n['id'] as String?;
        final at = '$where/$nid';
        check(nid != null && nid.startsWith('${prefix}s$index'), '$at: id bölüm önekiyle başlamalı');
        if (nid != null) check(seen.add(nid), '$at: id kullanılmış');
        final ex = (n['exercises'] as List?) ?? const [];
        void exercises() {
          for (final (k, e) in ex.indexed) {
            problems.addAll(validateExercise(e, '$at#$k'));
            if (e is Map && e['type'] == 'choice' && e['answer'] is int) {
              choices++;
              check((e['options'] as List?)?.length == options, '$at#$k: $options seçenek olmalı');
              letters[e['answer'] as int] = (letters[e['answer'] as int] ?? 0) + 1;
            }
          }
        }

        switch (n['type']) {
          case 'lesson':
            check(ex.length >= 8 && ex.length <= 12, '$at: ${ex.length} alıştırma (8–12)');
            exercises();
          case 'test':
            check(n['rewardXp'] is int && (n['rewardXp'] as int) > 0, '$at: rewardXp yok');
            // A unit test with its own questions: a fixed exam in the real format.
            if (ex.isNotEmpty) {
              check(
                ex.length >= testSize.$1 && ex.length <= testSize.$2,
                '$at: ${ex.length} test sorusu (${testSize.$1}–${testSize.$2})',
              );
              check(ex.every((e) => e is Map && e['type'] == 'choice'), '$at: test soruları choice olmalı');
              exercises();
            }
          case 'chest':
            check(n['rewardXp'] is int && (n['rewardXp'] as int) > 0, '$at: rewardXp yok');
          case 'mock':
            check(n['examId'] is String, '$at: examId yok');
            // A pack's full mock (packId + mockId) brings its own size and time.
            if (n['packId'] != null) {
              check(n['mockId'] is String, '$at: packId ile mockId gerekli');
            } else {
              check(n['size'] is int && (n['size'] as int) >= 10, '$at: size en az 10');
              check(n['minutes'] is int && (n['minutes'] as int) > 0, '$at: minutes yok');
            }
        }
      }
    }
    try {
      Section.fromFile(file);
    } catch (e) {
      problems.add('$name: uygulama okuyamıyor: $e');
    }
  }
  check(choices > 0, '$id: hiç choice sorusu yok');
  final most = letters.values.fold(0, max);
  check(most < choices * 0.4, '$id: doğru harf dağılımı dengesiz $letters');
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

  group('exam study paths', () {
    List<Map<String, dynamic>> lgsUnits() {
      final top = jsonDecode(File('assets/courses/exam_lgs.json').readAsStringSync()) as Map<String, dynamic>;
      return [
        ...(top['units'] as List).cast<Map<String, dynamic>>(),
        for (final f in sectionFiles('assets/courses/exam_lgs'))
          ...((jsonDecode(f.readAsStringSync()) as Map)['units'] as List).cast<Map<String, dynamic>>(),
      ];
    }

    test('LGS path follows the contract: guides, 4-option choice questions, mocks', () {
      final problems = validateExamPath('exam_lgs', 'l', 4, testSize: (10, 10));
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('LGS path has the 10 units of the 8th grade programme, in order, mostly exam-style', () {
      final units = lgsUnits();
      expect(units.map((u) => u['title']), [
        'Friendship',
        'Teen Life',
        'In the Kitchen',
        'On the Phone',
        'The Internet',
        'Adventures',
        'Tourism',
        'Chores',
        'Science',
        'Natural Forces',
      ]);
      final exercises = [
        for (final u in units)
          for (final n in u['nodes'] as List) ...((n as Map)['exercises'] as List?) ?? const [],
      ];
      final choice = exercises.where((e) => (e as Map)['type'] == 'choice').length;
      expect(choice / exercises.length, greaterThan(0.5));
      // Section 1 = units 1–5, section 2 = units 6–10, each ending in a mock.
      expect(
        units.where((u) => (u['nodes'] as List).any((n) => (n as Map)['type'] == 'mock')).map((u) => u['id']),
        ['ls1u5', 'ls2u5'],
      );
    });

    // docs/sinav/lgs-plan.md: what every unit has, and mocks in the real format.
    test('LGS units follow the plan: guide table and 3 exam tips, lesson sizes, a 10-question mini test', () {
      for (final u in lgsUnits()) {
        final id = u['id'];
        final guide = u['guide'] as String;
        expect(guide, contains('## Özet tablo'), reason: '$id');
        final tableLines = RegExp(r'^\|.*\|$', multiLine: true).allMatches(guide);
        expect(tableLines.length, greaterThanOrEqualTo(7), reason: '$id summary table');
        final tips = RegExp(r'^> \*\*Sınav ipucu [1-3]:\*\*', multiLine: true).allMatches(guide);
        expect(tips, hasLength(3), reason: '$id exam tips');
        final nodes = (u['nodes'] as List).cast<Map<String, dynamic>>();
        List<Map> ex(int i) => ((nodes[i]['exercises'] as List?) ?? const []).cast<Map>();
        expect([for (var i = 0; i < 5; i++) ex(i).length], [11, 11, 10, 9, 10], reason: '$id lesson sizes');
        expect(ex(0).where((e) => e['type'] == 'match'), hasLength(2), reason: '$id vocabulary: match');
        expect(ex(0).where((e) => e['type'] == 'select'), hasLength(3), reason: '$id vocabulary: select');
        // Reading: a text with 5 questions and a short one with 4.
        expect(ex(3).map((e) => e['passage']).toSet(), hasLength(2), reason: '$id reading texts');
        expect(nodes[4]['type'], 'test');
        expect(ex(4).every((e) => e['type'] == 'choice'), isTrue, reason: '$id mini test');
      }
    });

    test('LGS section mocks match the real exam: 10 questions in 15 minutes', () {
      final mocks = [
        for (final u in lgsUnits())
          for (final n in (u['nodes'] as List).cast<Map>())
            if (n['type'] == 'mock') n,
      ];
      expect(mocks.map((m) => (m['id'], m['examId'], m['size'], m['minutes'])), [
        ('ls1m', 'lgs', 10, 15),
        ('ls2m', 'lgs', 10, 15),
      ]);
    });

    test('YDS path, once shipped, follows the contract with 5 options', () {
      final problems = validateExamPath('exam_yds', 'y', 5, testSize: (15, 20));
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('exam path folders are declared in pubspec.yaml and kept in git', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/courses/exam_lgs/'));
      expect(pubspec, contains('- assets/courses/exam_yds/'));
      expect(File('assets/courses/exam_yds/.gitkeep').existsSync(), isTrue);
    });

    test('choice checks catch a bad answer, few options and a missing explanation', () {
      const ok = <String, Object>{
        'type': 'choice',
        'question': 'Q?',
        'options': ['a', 'b', 'c', 'd'],
        'answer': 1,
        'explanation': 'Çünkü b.',
      };
      expect(validateExercise({...ok}, 'x'), isEmpty);
      expect(validateExercise({...ok, 'answer': 4}, 'x'), anyElement(contains('answer')));
      expect(validateExercise({...ok, 'answer': 'b'}, 'x'), anyElement(contains('answer')));
      expect(
        validateExercise({
          ...ok,
          'options': ['a', 'b'],
        }, 'x'),
        anyElement(contains('options')),
      );
      expect(
        validateExercise({
          ...ok,
          'options': ['a', 'A', 'c', 'd'],
        }, 'x'),
        anyElement(contains('aynı')),
      );
      expect(validateExercise({...ok}..remove('explanation'), 'x'), anyElement(contains('explanation')));
    });
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

    /// The fixture's unit as an extension of [section] with unit id [unitId].
    Map<String, dynamic> extension(String section, String unitId) {
      final text = files.first.readAsStringSync().replaceAll('"s2u1', '"$unitId');
      final u = (jsonDecode(text)['units'] as List).first as Map<String, dynamic>;
      return {
        'extends': section,
        'units': [
          {
            ...u,
            'theme': 'cay',
            'guide': '## Rehber\n\n${'Bu ünitede dinleme ve konuşma çalışıyoruz. ' * 6}'.trim(),
          },
        ],
      };
    }

    test('an extension file passes after its section, also for section 1', () {
      final seen = baseIds();
      expect(validateSection('01x_beceri.json', extension('s1', 'u13'), seen), isEmpty);
      expect(validateSection('02_ornek.json', fixture(), seen), isEmpty);
      expect(validateSection('02x_beceri.json', extension('s2', 's2u13'), seen), isEmpty);
    });

    test('catches a misnamed, misplaced or guideless extension', () {
      List<String> ext(String name, Map<String, dynamic> j) =>
          validateSection(name, j, baseIds()..addAll(['s2']));
      expect(ext('02_beceri.json', extension('s2', 's2u13')), anyElement(contains('NNx_slug')));
      expect(ext('03x_beceri.json', extension('s2', 's2u13')), anyElement(contains('extends "s3"')));
      expect(ext('03x_beceri.json', extension('s3', 's3u13')), anyElement(contains('daha önce gelmeli')));
      expect(ext('02x_beceri.json', extension('s2', 'u13')), anyElement(contains('id s2uN')));
      expect(ext('02x_beceri.json', extension('s2', 'u12')), anyElement(contains('kullanılmış')));
      final noGuide = extension('s2', 's2u13');
      ((noGuide['units'] as List).first as Map).remove('guide');
      expect(ext('02x_beceri.json', noGuide), anyElement(contains('guide yok')));
      expect(
        ext('02x_beceri.json', {...extension('s2', 's2u13'), 'section': {}}),
        anyElement(contains('yalnızca extends')),
      );
    });

    test('token check accepts any order and contractions', () {
      expect(buildable("I don't drink coffee", ['coffee', "don't", 'I', 'drink', 'tea']), isTrue);
      expect(buildable('I am a student', ['I', 'a', 'student']), isFalse);
      expect(buildable('the the', ['the']), isFalse);
    });
  });
}
