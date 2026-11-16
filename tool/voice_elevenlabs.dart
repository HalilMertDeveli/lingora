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

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry');
  final all = args.contains('--all');
  final wanted = args.where((a) => !a.startsWith('--')).toSet();
  final units = _units().where((u) => all || wanted.contains(u['id'])).toList();
  if (units.isEmpty) {
    stderr.writeln('Hangi ünite? Örnek: dart run tool/voice_elevenlabs.dart u1');
    exit(64);
  }

  outDir.createSync(recursive: true);
  final index = indexFile.existsSync()
      ? (jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>).cast<String, String>()
      : <String, String>{};
  // --listening: only the lines of the listening pieces.
  final onlyListening = args.contains('--listening');
  final todo = <String, Voice>{};
  for (final u in units) {
    final spoken = onlyListening
        ? <String, Voice>{
            for (final (t, v) in listeningLines(u))
              if (_english(t)) normalizeSpoken(t): v,
          }
        : spokenIn(u);
    for (final MapEntry(:key, :value) in spoken.entries) {
      if (!index.containsKey(voiceKey(key))) todo[key] = value;
    }
  }
  if (onlyListening) {
    final m = todo.values.where((v) => v == Voice.matilda).length;
    stdout.writeln('Dinleme satırları: $m Matilda, ${todo.length - m} Eric.');
  }
  final chars = todo.keys.fold<int>(0, (n, t) => n + t.length);
  stdout.writeln('${units.length} ünite, ${todo.length} yeni metin, $chars karakter.');

  final key = _apiKey();
  if (key == null) {
    stderr.writeln('API anahtarı yok: ELEVENLABS_API_KEY ya da ~/.dilbaz/elevenlabs_key.txt');
    exit(66);
  }
  final http = HttpClient();
  final sub = await _getJson(http, key, 'https://api.elevenlabs.io/v1/user/subscription');
  final left = (sub['character_limit'] as int) - (sub['character_count'] as int);
  stdout.writeln('Kalan kredi: $left (${sub['tier']}).');
  if (dry) return;

  var used = 0;
  for (final MapEntry(key: text, value: voice) in todo.entries) {
    if (used + text.length > left) {
      stdout.writeln('Kredi bitti; kalanlar bir sonraki çalıştırmada.');
      break;
    }
    final file = File('${outDir.path}/${voiceKey(text)}.mp3');
    final req = await http.postUrl(
      Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/${voice.elevenLabsId}?output_format=$format'),
    );
    req.headers
      ..set('xi-api-key', key)
      ..contentType = ContentType.json;
    req.write(jsonEncode({'text': text, 'model_id': model}));
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('Hata ${res.statusCode}: ${await utf8.decodeStream(res)}');
      break;
    }
    await res.pipe(file.openWrite());
    used += text.length;
    index[voiceKey(text)] = voice.name;
    stdout.writeln('${voice.name.padRight(7)} $text');
    // Write the index as we go so an interrupted run keeps what it made.
    indexFile.writeAsStringSync(
      const JsonEncoder.withIndent(' ')
          .convert(Map.fromEntries(index.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))),
    );
  }
  http.close();
  stdout.writeln('Bitti: $used karakter kullanıldı, ${index.length} kayıt.');
}

Future<Map<String, dynamic>> _getJson(HttpClient http, String key, String url) async {
  final req = await http.getUrl(Uri.parse(url));
  req.headers.set('xi-api-key', key);
  final res = await req.close();
  return jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
}
