// Uploads the downloadable course recordings listed in
// assets/voice_manifest.json to Firebase Storage (docs/ses.md).
//
//   dart run tool/upload_voice.dart --extra D:/DilmacSes/voice
//       stages the files under build/voice_upload/ (checking every hash)
//       and prints the gsutil commands; uploads nothing.
//   dart run tool/upload_voice.dart --extra D:/DilmacSes/voice --run
//       also runs them (real bucket; needs `gcloud auth login`).
//   dart run tool/upload_voice.dart --extra D:/DilmacSes/voice --emulator 127.0.0.1:9199
//       uploads to the local Storage emulator instead (tests).
//
// Recordings go up first, with a year-long immutable cache (their names hold
// their hash); the manifest last, with a short cache, so an app never sees a
// manifest whose files are not there yet.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lingora/core/voice_manifest.dart';

const bucket = 'dilbaz-3392e.firebasestorage.app';
const fileCache = 'public, max-age=31536000, immutable';
const manifestCache = 'public, max-age=300';
final stage = Directory('build/voice_upload');

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<void> main(List<String> args) async {
  final emulator = _arg(args, '--emulator');
  final run = args.contains('--run');
  final targetBucket = _arg(args, '--bucket') ?? bucket;
  if (emulator != null && !RegExp(r'^(localhost|127\.0\.0\.1|\[::1\]):\d+$').hasMatch(emulator)) {
    stderr.writeln('--emulator yalnızca localhost:PORT olabilir.');
    exit(64);
  }
  final sources = [
    Directory('voice'),
    for (var i = 0; i < args.length - 1; i++)
      if (args[i] == '--extra') Directory(args[i + 1]),
  ];
  final manifestFile = File(_arg(args, '--manifest') ?? 'assets/voice_manifest.json');
  final manifest = VoiceManifest.parse(manifestFile.readAsStringSync());

  // Stage: files/voice/<key>_<hash8>.mp3 + manifest.json, every hash checked.
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  final filesDir = Directory('${stage.path}/files')..createSync(recursive: true);
  var bad = 0;
  for (final f in manifest.files) {
    final src = sources.map((d) => File('${d.path}/${f.key}.mp3')).where((x) => x.existsSync()).firstOrNull;
    final bytes = src?.readAsBytesSync();
    if (bytes == null ||
        bytes.length != f.size ||
        sha256.convert(bytes).toString().substring(0, hashLength) != f.hash) {
      stderr.writeln('${f.key}: ${src == null ? 'dosya yok' : 'hash/boyut tutmuyor'}');
      bad++;
      continue;
    }
    final out = File('${filesDir.path}/${f.objectPath}')..parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  }
  if (bad > 0) {
    stderr.writeln('$bad kayıt hazır değil; önce: dart run tool/voice_manifest.dart --extra ...');
    exit(65);
  }
  final stagedManifest = File('${stage.path}/manifest.json')
    ..writeAsStringSync(manifestFile.readAsStringSync());
  stdout.writeln(
    '${manifest.fileCount} kayıt (${(manifest.bytes / 1048576).toStringAsFixed(1)} MB) '
    '${stage.path} altında hazır.',
  );

  if (emulator != null) {
    await _uploadToEmulator(emulator, targetBucket, filesDir, stagedManifest);
    return;
  }

  final commands = [
    [
      'gsutil', '-m', '-h', 'Cache-Control:$fileCache', '-h', 'Content-Type:audio/mpeg', //
      'rsync', '-r', '${filesDir.path}/$voiceObjectPrefix', 'gs://$targetBucket/$voiceObjectPrefix',
    ],
    [
      'gsutil', '-h', 'Cache-Control:$manifestCache', '-h', 'Content-Type:application/json', //
      'cp', stagedManifest.path, 'gs://$targetBucket/$voiceManifestObject',
    ],
  ];
  for (final c in commands) {
    stdout.writeln(c.map((a) => a.contains(' ') ? '"$a"' : a).join(' '));
  }
  if (!run) {
    stdout.writeln('Yüklemek için --run ekle (gerçek bucket).');
    return;
  }
  for (final c in commands) {
    final p = await Process.start(
      c.first,
      c.sublist(1),
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    final code = await p.exitCode;
    if (code != 0) exit(code);
  }
}

/// Uploads through the emulator's REST API as the admin ("Bearer owner"),
/// which the emulator accepts in place of IAM.
Future<void> _uploadToEmulator(String host, String bucket, Directory filesDir, File manifest) async {
  final client = HttpClient();
  Future<void> put(String object, List<int> bytes, String type, String cache) async {
    final url = Uri.parse('http://$host/v0/b/$bucket/o?name=${Uri.encodeQueryComponent(object)}');
    final req = await client.postUrl(url);
    req.headers
      ..set('Authorization', 'Bearer owner')
      ..set('Content-Type', type)
      ..set('X-Goog-Upload-Protocol', 'raw');
    req.add(bytes);
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (res.statusCode != 200) throw HttpException('$object: ${res.statusCode} $body');
  }

  var n = 0;
  for (final f in filesDir.listSync(recursive: true).whereType<File>()) {
    final object = f.path.substring(filesDir.path.length + 1).replaceAll(r'\', '/');
    await put(object, f.readAsBytesSync(), 'audio/mpeg', fileCache);
    n++;
  }
  await put(voiceManifestObject, manifest.readAsBytesSync(), 'application/json', manifestCache);
  client.close();
  stdout.writeln('Emülatöre $n kayıt + manifest yüklendi ($host).');
}
