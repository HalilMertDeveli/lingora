// Records course sentences with ElevenLabs into assets/voice/.
//
//   dart run tool/voice_elevenlabs.dart u1            # one unit
//   dart run tool/voice_elevenlabs.dart u1 u2 --dry   # count only
//   dart run tool/voice_elevenlabs.dart --all
//   dart run tool/voice_elevenlabs.dart --all --listening --dry  # listening pieces only
//
// Listening lines are read by their speaker: women Matilda, men Eric.
//
// The API key is read from ELEVENLABS_API_KEY or from
// %USERPROFILE%/.dilbaz/elevenlabs_key.txt; it is never printed or stored in
// the repository. Already recorded sentences are skipped, so the script can
// be run again month by month as credits renew.
import 'dart:convert';
import 'dart:io';

import 'package:lingora/core/voice_key.dart';

const model = 'eleven_multilingual_v2';
const format = 'mp3_44100_64';
final outDir = Directory('assets/voice');
final indexFile = File('assets/voice/index.json');

final _turkish = RegExp('[çğıöşüÇĞİÖŞÜ]');
bool _english(String? s) => s != null && s.trim().isNotEmpty && !_turkish.hasMatch(s);

String? _apiKey() {
  final env = Platform.environment['ELEVENLABS_API_KEY'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final f = File('$home/.dilbaz/elevenlabs_key.txt');
  return f.existsSync() ? f.readAsStringSync().trim() : null;
}

/// Every unit of the general course, in file order.
List<Map<String, dynamic>> allUnits() => _units();

List<Map<String, dynamic>> _units() {
  final files = [
    File('assets/courses/tr_en.json'),
    ...(Directory('assets/courses/tr_en')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path))),
  ];
  return [
    for (final f in files)
      for (final u in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['units'] as List)
        u as Map<String, dynamic>,
  ];
}

/// What the app reads aloud in [unit], with the voice for each text.
Map<String, Voice> spokenIn(Map<String, dynamic> unit) {
  final out = <String, Voice>{};
  void add(String? text, [Voice? voice]) {
    if (!_english(text)) return;
    final t = normalizeSpoken(text!);
    out.putIfAbsent(t, () => voice ?? voiceForSentence(t));
  }

  for (final node in (unit['nodes'] as List).cast<Map<String, dynamic>>()) {
    for (final ex in ((node['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      switch (ex['type']) {
        case 'select':
          for (final c in (ex['choices'] as List? ?? const [])) {
            add(c is Map ? c['text'] as String? : c as String?);
          }
        case 'match':
          for (final p in (ex['pairs'] as List? ?? const [])) {
            add((p as List)[1] as String?);
          }
        case 'translate':
          if (ex['lang'] != 'tr') add(ex['text'] as String?);
        case 'listen' || 'speak' || 'shadow':
          add(ex['text'] as String?);
      }
    }
    final steps = ((node['steps'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final speakerVoice = <String, Voice>{};
    for (final s in steps.where((s) => s['kind'] == 'line')) {
      final who = s['speaker'] as String? ?? '';
      speakerVoice[who] ??=
          voiceForAvatar(s['avatar'] as String?) ??
          (speakerVoice.values.contains(Voice.matilda) ? Voice.eric : Voice.matilda);
      add(s['text'] as String?, speakerVoice[who]);
    }
  }
  for (final (text, voice) in listeningLines(unit)) {
    add(text, voice);
  }
  return out;
}

/// Lines of the unit's listening pieces with their speaker's voice: women
/// Matilda, men Eric (the `gender` of the speaker).
List<(String, Voice)> listeningLines(Map<String, dynamic> unit) => [
  for (final node in (unit['nodes'] as List).cast<Map<String, dynamic>>())
    if (node['type'] == 'listening')
      for (final l in ((node['lines'] as List?) ?? const []).cast<Map<String, dynamic>>())
        (
          l['text'] as String,
          ((node['speakers'] as List).cast<Map<String, dynamic>>().firstWhere(
                    (s) => s['name'] == l['speaker'],
                  )['gender'] ==
                  'male')
              ? Voice.eric
              : Voice.matilda,
        ),
];

/// Expressive but clear: lively intonation, close to the original voice.
const voiceSettings = {'stability': 0.3, 'similarity_boost': 0.8, 'style': 0.5, 'use_speaker_boost': true};

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Map<String, String> _readIndex(File f) => f.existsSync()
    ? (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).cast<String, String>()
    : <String, String>{};

void _writeIndex(File f, Map<String, String> index) => f.writeAsStringSync(
  const JsonEncoder.withIndent(' ')
      .convert(Map.fromEntries(index.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))),
);

int _mp3Bytes(Directory d) => d.existsSync()
    ? d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .fold(0, (n, f) => n + f.lengthSync())
    : 0;

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry');
  final all = args.contains('--all');
  // --regen: record again everything already in assets/voice (e.g. after
  // moving to a paid plan). Progress is kept in .dart_tool so a stopped run
  // resumes without paying twice.
  final regen = args.contains('--regen');
  // --budget N: spend at most N characters in this run.
  // --keep N: never let the account's remaining characters drop below N.
  final budget = int.tryParse(_arg(args, '--budget') ?? '');
  final keep = int.tryParse(_arg(args, '--keep') ?? '') ?? 0;
  // --max-mb M --overflow DIR: once assets/voice holds M MB of recordings,
  // new ones go to DIR (outside the APK, with its own index.json).
  final maxBytes = (double.tryParse(_arg(args, '--max-mb') ?? '') ?? double.infinity) * 1024 * 1024;
  final overflowPath = _arg(args, '--overflow');
  final valueArgs = {_arg(args, '--budget'), _arg(args, '--keep'), _arg(args, '--max-mb'), overflowPath};
  final wanted = args.where((a) => !a.startsWith('--') && !valueArgs.contains(a)).toSet();
  final units = _units().where((u) => all || regen || wanted.contains(u['id'])).toList();
  if (units.isEmpty) {
    stderr.writeln('Hangi ünite? Örnek: dart run tool/voice_elevenlabs.dart u1');
    exit(64);
  }

  outDir.createSync(recursive: true);
  final index = _readIndex(indexFile);
  final overflowDir = overflowPath == null ? null : Directory(overflowPath);
  final overflowIndexFile = overflowDir == null ? null : File('${overflowDir.path}/index.json');
  final overflowIndex = overflowIndexFile == null ? <String, String>{} : _readIndex(overflowIndexFile);
  final regenDone = File('.dart_tool/voice_regen_done.txt');
  final done = regen && regenDone.existsSync() ? regenDone.readAsLinesSync().toSet() : <String>{};

  // --listening: only the lines of the listening pieces.
  final onlyListening = args.contains('--listening');
  final again = <String, Voice>{}; // already in assets/voice, recorded again
  final todo = <String, Voice>{}; // not recorded yet, in course order
  final unitOf = <String, String>{}; // first unit of each new text
  for (final u in units) {
    final spoken = onlyListening
        ? <String, Voice>{
            for (final (t, v) in listeningLines(u))
              if (_english(t)) normalizeSpoken(t): v,
          }
        : spokenIn(u);
    for (final MapEntry(:key, :value) in spoken.entries) {
      final k = voiceKey(key);
      if (index.containsKey(k)) {
        if (regen && !done.contains(k)) again.putIfAbsent(key, () => value);
      } else if (!overflowIndex.containsKey(k) && (all || wanted.contains(u['id']))) {
        todo.putIfAbsent(key, () => value);
        unitOf.putIfAbsent(key, () => u['id'] as String);
      }
    }
  }
  if (regen) {
    final found = {for (final t in again.keys) voiceKey(t), ...done};
    final orphans = index.keys.where((k) => !found.contains(k)).length;
    stdout.writeln(
      'Yeniden kayıt: ${again.length} metin, ${again.keys.fold<int>(0, (n, t) => n + t.length)} karakter'
      '${done.isEmpty ? '' : ' (${done.length} zaten yapıldı)'}'
      '${orphans == 0 ? '' : ' ($orphans kayıt kursta bulunamadı)'}.',
    );
  }
  if (onlyListening) {
    final m = todo.values.where((v) => v == Voice.matilda).length;
    stdout.writeln('Dinleme satırları: $m Matilda, ${todo.length - m} Eric.');
  }
  final chars = todo.keys.fold<int>(0, (n, t) => n + t.length);
  stdout.writeln('${units.length} ünite, ${todo.length} yeni metin, $chars karakter.');
  if (dry && budget != null) {
    // How far the budget reaches, in course order.
    final order = [...again.keys, ...todo.keys];
    var n = 0, c = 0;
    for (final t in order) {
      if (c + t.length > budget) break;
      c += t.length;
      n++;
    }
    final stop = n < order.length ? unitOf[order[n]] : null;
    stdout.writeln(
      '$budget karakterle: $n metin ($c karakter)'
      '${stop == null ? ', hepsi.' : ', $stop ünitesinin ortasına kadar.'}',
    );
  }

  final key = _apiKey();
  if (key == null) {
    stderr.writeln('API anahtarı yok: ELEVENLABS_API_KEY ya da ~/.dilbaz/elevenlabs_key.txt');
    exit(66);
  }
  final http = HttpClient();
  final sub = await _getJson(http, key, 'https://api.elevenlabs.io/v1/user/subscription');
  final left = (sub['character_limit'] as int) - (sub['character_count'] as int);
  stdout.writeln(
    'Hesap: ${sub['tier']} (${sub['status']}), kullanılan ${sub['character_count']}, '
    'limit ${sub['character_limit']}, kalan $left.',
  );
  if (dry) {
    http.close();
    return;
  }

  // Hard cap: the smaller of --budget and what keeps --keep on the account.
  var cap = left - keep;
  if (budget != null && budget < cap) cap = budget;
  stdout.writeln('Bu çalıştırmada en çok $cap karakter.');
  var used = 0;
  var assetBytes = _mp3Bytes(outDir);
  var made = 0, overflowMade = 0;
  final jobs = [
    for (final e in again.entries) (e.key, e.value, true),
    for (final e in todo.entries) (e.key, e.value, false),
  ];
  for (final (text, voice, isAgain) in jobs) {
    if (used + text.length > cap) {
      stdout.writeln('Bütçe doldu; kalanlar bir sonraki çalıştırmada.');
      break;
    }
    final k = voiceKey(text);
    final toOverflow = !isAgain && assetBytes >= maxBytes;
    if (toOverflow && overflowDir == null) {
      stdout.writeln('assets/voice dolu (--max-mb); --overflow verilmedi.');
      break;
    }
    final dir = toOverflow ? overflowDir! : outDir;
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$k.mp3');
    final req = await http.postUrl(
      Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/${voice.elevenLabsId}?output_format=$format'),
    );
    req.headers
      ..set('xi-api-key', key)
      ..contentType = ContentType.json;
    req.write(jsonEncode({'text': text, 'model_id': model, 'voice_settings': voiceSettings}));
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('Hata ${res.statusCode}: ${await utf8.decodeStream(res)}');
      break;
    }
    final bytes = await res.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
    used += text.length;
    if (bytes.isEmpty) {
      stderr.writeln('Boş ses: $text');
      break;
    }
    final before = file.existsSync() ? file.lengthSync() : 0;
    file.writeAsBytesSync(bytes);
    // Write the index (and regen progress) as we go so an interrupted run
    // keeps what it made.
    if (toOverflow) {
      overflowIndex[k] = voice.name;
      _writeIndex(overflowIndexFile!, overflowIndex);
      overflowMade++;
    } else {
      assetBytes += bytes.length - before;
      index[k] = voice.name;
      _writeIndex(indexFile, index);
      made++;
      if (isAgain) regenDone.writeAsStringSync('$k\n', mode: FileMode.append);
    }
    stdout.writeln('${toOverflow ? '+' : ' '}${voice.name.padRight(7)} $text');
  }
  http.close();
  stdout.writeln(
    'Bitti: $used karakter kullanıldı; assets/voice: $made dosya yazıldı '
    '(${index.length} kayıt, ${(assetBytes / 1048576).toStringAsFixed(1)} MB)'
    '${overflowDir == null ? '' : '; ${overflowDir.path}: $overflowMade dosya yazıldı (${overflowIndex.length} kayıt)'}.',
  );
}

Future<Map<String, dynamic>> _getJson(HttpClient http, String key, String url) async {
  final req = await http.getUrl(Uri.parse(url));
  req.headers.set('xi-api-key', key);
  final res = await req.close();
  return jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
}
