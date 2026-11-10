// Content quality checks: catch the classes of errors found in the content review
// (docs/icerik-raporu.md) before they reach users.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';

/// Turkish words written without Turkish characters, as AI or keyboard input often does.
/// Matched as whole words in lowercase or capitalized form (ALL CAPS mnemonics are left alone).
const _asciiTurkish = [
  'tesekkur', 'tesekkurler', 'tesekkurederim', 'gunaydin', 'iyi aksamlar', 'nasilsin', 'nasilsiniz', //
  'ogrenci', 'ogretmen', 'degil', 'degilim', 'guzel', 'icin', 'simdi', 'bugun', 'yarin', 'gorusuruz',
  'lutfen', 'konusmak', 'calismak', 'ogrenmek', 'sehir', 'kucuk', 'buyuk', 'universite', 'musteri',
  'kahvalti', 'aksam', 'hosgeldiniz', 'hosgeldin', 'tanistigima', 'calisiyorum', 'ingilizce', 'turkce',
  'turkiye', 'ogle', 'cumle', 'yapiyorum', 'odeme', 'gorusme', 'sirket', 'is gorusmesi',
];

/// Keys holding identifiers, which are ASCII on purpose.
bool _isIdKey(String key) => key == 'id' || key.endsWith('Id') || key.endsWith('Ids');

List<String> _assetFiles() =>
    Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.json'))
        .toList()
      ..sort();

dynamic _read(String path) => jsonDecode(File(path).readAsStringSync());

/// Calls [visit] for every string value with a readable location.
void _strings(
  dynamic v,
  String where,
  void Function(String where, String key, String s) visit, [
  String key = '',
]) {
  if (v is String) {
    visit(where, key, v);
  } else if (v is List) {
    for (var i = 0; i < v.length; i++) {
      _strings(v[i], '$where[$i]', visit, key);
    }
  } else if (v is Map) {
    for (final e in v.entries) {
      _strings(e.value, '$where.${e.key}', visit, e.key as String);
    }
  }
}

List<String> _dupes(Iterable<String> items, String Function(String) norm) {
  final seen = <String>{};
  return [
    for (final i in items)
      if (!seen.add(norm(i))) i,
  ];
}

String _lower(String s) => s.trim().toLowerCase();

int _words(String s) => s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Longest sentence (in words) of an English text.
int _longestSentence(String text) =>
    text.split(RegExp(r'(?<=[.!?])\s+|\n+')).map(_words).fold(0, (a, b) => a > b ? a : b);

/// "an ___" / "a ----" right before a blank gives the answer away when the options do not all
/// start the same way (vowel vs consonant letter).
bool _articleGiveaway(String prompt, List<String> options) {
  final m = RegExp(r'\b([Aa]n?) (?:_{3,}|-{3,})').firstMatch(prompt);
  if (m == null) return false;
  final starts = options.map((o) => RegExp('^[aeiouAEIOU]').hasMatch(o.trim())).toSet();
  return starts.length > 1;
}

void main() {
  final files = _assetFiles();

  group('all content files', () {
    test('no stray whitespace, import artifacts or ASCII-only Turkish words', () {
      final problems = <String>[];
      final ascii = [
        for (final w in _asciiTurkish) ...[
          RegExp('(^|[^\\p{L}])$w(\$|[^\\p{L}])', unicode: true),
          RegExp('(^|[^\\p{L}])${w[0].toUpperCase()}${w.substring(1)}(\$|[^\\p{L}])', unicode: true),
        ],
      ];
      for (final f in files) {
        _strings(_read(f), f, (where, key, s) {
          if (_isIdKey(key)) return;
          if (s != s.trim()) problems.add('$where: leading/trailing space');
          if (RegExp(r'[^\s] {2,}[^\s]').hasMatch(s)) problems.add('$where: double space');
          if (RegExp(r'�|\*\*|&nbsp;|</?[a-z]+>').hasMatch(s)) problems.add('$where: import artifact');
          for (final r in ascii) {
            final m = r.firstMatch(s);
            if (m != null) problems.add('$where: "${m.group(0)!.trim()}" lacks Turkish characters');
          }
        });
      }
      expect(problems, isEmpty, reason: problems.take(20).join('\n'));
    });
  });

  for (final path in files.where((f) => f.startsWith('assets/courses/'))) {
    final course = _read(path) as Map<String, dynamic>;
    group('course ${course['id']}', () {
      final nodes = [
        for (final u in course['units'] as List)
          for (final n in (u as Map)['nodes'] as List) n as Map<String, dynamic>,
      ];
      final exercises = [
        for (final n in nodes)
          for (final e in (n['exercises'] as List?) ?? const [])
            (n['id'] as String, e as Map<String, dynamic>),
      ];

      test('accepted answers have no duplicates', () {
        for (final (id, e) in exercises) {
          final answers = ((e['answers'] as List?) ?? const []).cast<String>();
          expect(_dupes(answers, normalizeAnswer), isEmpty, reason: '$id ${e['text']}');
        }
      });

      test('options are distinct, also ignoring case', () {
        for (final (id, e) in exercises) {
          final reason = '$id ${e['type']} ${e['text'] ?? e['prompt']}';
          switch (e['type']) {
            case 'select':
              final texts = [for (final c in e['choices'] as List) (c as Map)['text'] as String];
              expect(_dupes(texts, _lower), isEmpty, reason: reason);
            case 'fillBlank':
              expect(_dupes((e['choices'] as List).cast<String>(), _lower), isEmpty, reason: reason);
            case 'match':
              final pairs = [for (final p in e['pairs'] as List) (p as List).cast<String>()];
              expect(_dupes(pairs.map((p) => p[0]), _lower), isEmpty, reason: reason);
              expect(_dupes(pairs.map((p) => p[1]), _lower), isEmpty, reason: reason);
          }
        }
        for (final n in nodes) {
          for (final s in (n['steps'] as List?) ?? const []) {
            final choices = ((s as Map)['choices'] as List?)?.cast<String>() ?? const [];
            expect(_dupes(choices, _lower), isEmpty, reason: '${n['id']} ${s['prompt']}');
          }
        }
      });

      test('fill-in-the-blank has exactly one blank and no a/an giveaway', () {
        for (final (id, e) in exercises.where((x) => x.$2['type'] == 'fillBlank')) {
          final text = e['text'] as String;
          expect('___'.allMatches(text), hasLength(1), reason: '$id $text');
          final choices = (e['choices'] as List).cast<String>();
          expect(_articleGiveaway(text, choices), isFalse, reason: '$id $text $choices');
        }
      });

      // The professional courses are B1 throughout; only the general course starts at A1.
      test('sentences stay short enough for the level', skip: course['id'] != 'tr_en', () {
        final units = course['units'] as List;
        for (var i = 0; i < units.length; i++) {
          // The first third of a course is beginner material.
          final limit = i < units.length / 3 ? 10 : 16;
          for (final n in (units[i] as Map)['nodes'] as List) {
            final texts = <String>[
              for (final e in ((n as Map)['exercises'] as List?) ?? const [])
                if ((e as Map)['lang'] != 'tr' && e['text'] is String) e['text'] as String,
              for (final s in (n['steps'] as List?) ?? const [])
                if ((s as Map)['text'] is String) s['text'] as String,
            ];
            for (final t in texts) {
              expect(_longestSentence(t), lessThanOrEqualTo(limit), reason: '${n['id']}: $t');
            }
          }
        }
      });
    });
  }

  group('multiple-choice banks', () {
    // (file, question list, options key, prompt key)
    final banks = <(String, List<Map<String, dynamic>>, String, String)>[
      for (final f in files.where((f) => f.startsWith('assets/exams/')))
        (
          f,
          [
            for (final s in ((_read(f) as Map)['sections'] as List?) ?? const [])
              for (final q in ((s as Map)['questions'] as List?) ?? const []) q as Map<String, dynamic>,
          ],
          'options',
          'text',
        ),
      // Paid exam packs: full mock exams.
      for (final f in files.where((f) => f.startsWith('assets/exam_packs/')))
        (
          f,
          [
            for (final m in ((_read(f) as Map)['mocks'] as List?) ?? const [])
              for (final q in ((m as Map)['questions'] as List?) ?? const []) q as Map<String, dynamic>,
          ],
          'options',
          'text',
        ),
      (
        'assets/placement/questions.json',
        (_read('assets/placement/questions.json') as List).cast(),
        'choices',
        'prompt',
      ),
      (
        'assets/notes/lessons.json',
        [
          for (final l in _read('assets/notes/lessons.json') as List)
            for (final q in (l as Map)['quiz'] as List) q as Map<String, dynamic>,
        ],
        'options',
        'q',
      ),
    ];

    for (final (file, questions, optionsKey, promptKey) in banks) {
      test(
        '$file: options distinct ignoring case, no a/an giveaway, explanations name no option by position',
        () {
          for (final q in questions) {
            final reason = '${q['id'] ?? ''} ${q[promptKey]}';
            final options = (q[optionsKey] as List).cast<String>();
            expect(_dupes(options, _lower), isEmpty, reason: reason);
            final prompt = (q[promptKey] as String?) ?? '';
            expect(_articleGiveaway(prompt, options), isFalse, reason: reason);
            final explanation = (q['explanation'] as String?) ?? '';
            expect(
              RegExp(
                r'(ilk|ikinci|üçüncü|dördüncü|beşinci|son) (seçenek|şık)',
                caseSensitive: false,
              ).hasMatch(explanation),
              isFalse,
              reason: 'refer to options by their text, positions change: $reason',
            );
          }
        },
      );
    }
  });

  group('reading stories', () {
    final stories = (_read('assets/reading/stories.json') as List).cast<Map<String, dynamic>>();
    const maxSentence = {'A1': 20, 'A2': 28, 'B1': 35, 'B2': 45};
    test('sentence length matches the level', () {
      for (final s in stories) {
        final limit = maxSentence[s['level']] ?? 45;
        expect(_longestSentence(s['text'] as String), lessThanOrEqualTo(limit), reason: s['id'] as String);
      }
    });
  });
}
