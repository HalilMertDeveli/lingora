// Adds listening pieces to the general course, one per unit, right before the
// unit test:
//
//   dart run tool/add_listening.dart pieces.json [more.json ...]
//
// A pieces file maps a unit id to a piece without id and type:
//   {"u1": {"title": "...", "description": "...", "cefr": "A1",
//           "speakers": [...], "lines": [...], "questions": [...], "idioms": [...]}}
// The node gets the id "<unit id>d" and 15 XP. A unit that already has its
// listening node gets it replaced. The text is inserted as is, so the rest of
// each course file keeps its hand-made formatting.
import 'dart:convert';
import 'dart:io';

const _keys = ['title', 'description', 'cefr', 'speakers', 'lines', 'questions', 'idioms'];

List<File> courseFiles() => [
  File('assets/courses/tr_en.json'),
  ...(Directory('assets/courses/tr_en')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path))),
];

/// Index of the `{` that opens the object containing [at].
int _objectStart(String s, int at) {
  var depth = 0;
  for (var i = at; i >= 0; i--) {
    final c = s[i];
    if (c == '}') depth++;
    if (c == '{') {
      if (depth == 0) return i;
      depth--;
    }
  }
  throw StateError('no object start');
}

/// Index just after the `}` that closes the object opened at [start]
/// (strings in the course never contain braces inside quotes that matter
/// here, but quotes are skipped anyway).
int _objectEnd(String s, int start) {
  var depth = 0;
  var inString = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') inString = true;
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) return i + 1;
  }
  throw StateError('no object end');
}

String _nodeText(String unitId, Map<String, dynamic> piece, String indent) {
  final node = <String, dynamic>{
    'id': '${unitId}d',
    'type': 'listening',
    'rewardXp': 15,
    for (final k in _keys)
      if (piece[k] != null) k: piece[k],
  };
  // One key per line; the items of a list (a speaker, a line, a question)
  // one per line, like the hand-made course files.
  String value(Object? v) => v is List && v.isNotEmpty && v.first is Map
      ? '[\n${v.map((e) => '$indent    ${_compact(e)}').join(',\n')}\n$indent  ]'
      : _compact(v);
  final body = [for (final e in node.entries) '$indent  ${jsonEncode(e.key)}: ${value(e.value)}'];
  return '{\n${body.join(',\n')}\n$indent}';
}

/// JSON with a space after colons and commas.
String _compact(Object? v) => switch (v) {
  final Map<dynamic, dynamic> m =>
    '{${m.entries.map((e) => '${jsonEncode(e.key)}: ${_compact(e.value)}').join(', ')}}',
  final List<dynamic> l => '[${l.map(_compact).join(', ')}]',
  _ => jsonEncode(v),
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Kullanım: dart run tool/add_listening.dart parcalar.json');
    exit(64);
  }
  final pieces = <String, Map<String, dynamic>>{
    for (final a in args) ...(jsonDecode(File(a).readAsStringSync()) as Map<String, dynamic>).cast(),
  };
  final left = {...pieces.keys};
  for (final file in courseFiles()) {
    var s = file.readAsStringSync();
    final units = ((jsonDecode(s) as Map<String, dynamic>)['units'] as List).cast<Map<String, dynamic>>();
    var changed = false;
    for (final u in units) {
      final id = u['id'] as String;
      final piece = pieces[id];
      if (piece == null) continue;
      left.remove(id);
      // Drop an earlier version of the piece.
      final old = RegExp('"id":\\s*"${id}d"').firstMatch(s);
      if (old != null) {
        final start = _objectStart(s, old.start);
        var end = _objectEnd(s, start);
        final comma = RegExp(r'^\s*,\s*').matchAsPrefix(s, end);
        if (comma != null) end = comma.end;
        s = s.replaceRange(start, end, '');
      }
      final test = RegExp('"id":\\s*"${id}t"').firstMatch(s);
      if (test == null) throw StateError('$id: unit test not found in ${file.path}');
      final start = _objectStart(s, test.start);
      final lineStart = s.lastIndexOf('\n', start) + 1;
      final before = s.substring(lineStart, start);
      final indent = before.trim().isEmpty ? before : '';
      s = s.replaceRange(start, start, '${_nodeText(id, piece, indent)},\n$indent');
      changed = true;
    }
    if (changed) {
      jsonDecode(s); // still valid
      file.writeAsStringSync(s);
      stdout.writeln('${file.path}: güncellendi');
    }
  }
  if (left.isNotEmpty) {
    stderr.writeln('Kursta bulunamayan üniteler: ${left.join(', ')}');
    exit(1);
  }
}
