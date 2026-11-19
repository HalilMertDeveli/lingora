import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/voice_manifest.dart';
import 'voice_store.dart';

/// Storage bucket of the course audio (Firebase project dilbaz-3392e).
const voiceBucket = 'dilbaz-3392e.firebasestorage.app';

/// `--dart-define=LINGORA_STORAGE_EMULATOR=10.0.2.2:9199` downloads from the
/// Storage emulator instead of the real bucket.
const _emulator = String.fromEnvironment('LINGORA_STORAGE_EMULATOR');

/// What the settings row shows.
@immutable
class VoiceDownloadState {
  const VoiceDownloadState({
    this.enabled = true,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.running = false,
    this.waitingForWifi = false,
  });

  final bool enabled;
  final int totalBytes;
  final int downloadedBytes;
  final bool running;
  final bool waitingForWifi;

  bool get complete => totalBytes > 0 && downloadedBytes >= totalBytes;

  VoiceDownloadState copyWith({
    bool? enabled,
    int? totalBytes,
    int? downloadedBytes,
    bool? running,
    bool? waitingForWifi,
  }) => VoiceDownloadState(
    enabled: enabled ?? this.enabled,
    totalBytes: totalBytes ?? this.totalBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    running: running ?? this.running,
    waitingForWifi: waitingForWifi ?? this.waitingForWifi,
  );
}

/// The course recordings that are not bundled (docs/ses.md): downloaded in
/// the background on Wi-Fi, section by section in course order, into app
/// storage. Until a recording is on the phone, the phone's voice reads it.
class VoiceLibrary {
  VoiceLibrary._();

  static final instance = VoiceLibrary._();

  static const _prefKey = 'voicePacks.wifi';

  final state = ValueNotifier(const VoiceDownloadState());
  var _manifest = VoiceManifest.empty;
  VoiceCache? _cache;
  Future<void>? _init;
  VoiceDownloader? _downloader;
  StreamSubscription<List<ConnectivityResult>>? _wifiWatch;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Path of the downloaded recording of [key], or null (not downloaded,
  /// not part of the course audio, or [init] not done yet).
  String? pathFor(String key) {
    final f = _manifest[key];
    return f == null ? null : _cache?.pathFor(f);
  }

  /// Loads the manifest and the cache, then starts downloading when allowed.
  /// Safe to call many times.
  Future<void> init() => _init ??= _load();

  Future<void> _load() async {
    if (!_supported) return;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/voice');
      final cache = VoiceCache(Directory('${dir.path}/files'));
      await cache.load();
      _manifest = _newer(await _bundledManifest(), await _savedManifest(dir));
      await cache.prune(_manifest);
      _cache = cache;
      final prefs = await SharedPreferences.getInstance();
      _publish(enabled: prefs.getBool(_prefKey) ?? true);
      unawaited(_maybeStart());
    } catch (e) {
      debugPrint('Voice library: $e');
    }
  }

  static Future<VoiceManifest> _bundledManifest() async {
    try {
      return VoiceManifest.parse(await rootBundle.loadString('assets/voice_manifest.json'));
    } catch (_) {
      return VoiceManifest.empty;
    }
  }

  static File _savedFile(Directory dir) => File('${dir.path}/manifest.json');

  static Future<VoiceManifest> _savedManifest(Directory dir) async {
    try {
      return VoiceManifest.parse(await _savedFile(dir).readAsString());
    } catch (_) {
      return VoiceManifest.empty;
    }
  }

  static VoiceManifest _newer(VoiceManifest a, VoiceManifest b) => b.version > a.version ? b : a;

  void _publish({bool? enabled, bool? running, bool? waitingForWifi}) {
    state.value = state.value.copyWith(
      enabled: enabled,
      running: running,
      waitingForWifi: waitingForWifi,
      totalBytes: _manifest.bytes,
      downloadedBytes: _cache?.bytesOf(_manifest) ?? 0,
    );
  }

  static Future<bool> _onWifi() async {
    final r = await Connectivity().checkConnectivity();
    return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
  }

  Future<void> setEnabled(bool on) async {
    await init();
    await (await SharedPreferences.getInstance()).setBool(_prefKey, on);
    _publish(enabled: on);
    if (on) {
      unawaited(_maybeStart());
    } else {
      _downloader?.cancel();
      await _wifiWatch?.cancel();
      _wifiWatch = null;
      _publish(waitingForWifi: false);
    }
  }

  /// Deletes every downloaded recording and stops downloading (the switch
  /// is turned off too, or they would come straight back).
  Future<void> deleteAll() async {
    await init();
    await setEnabled(false);
    while (state.value.running) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _cache?.clear();
    _publish();
  }

  Future<void> _maybeStart() async {
    final cache = _cache;
    if (cache == null || state.value.running || !state.value.enabled) return;
    if (!await _onWifi()) {
      _publish(waitingForWifi: true);
      _wifiWatch ??= Connectivity().onConnectivityChanged.listen((r) {
        if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) {
          unawaited(_maybeStart());
        }
      });
      return;
    }
    _publish(running: true, waitingForWifi: false);
    try {
      await _refreshManifest(cache);
      final d = _downloader = VoiceDownloader(
        cache: cache,
        fetch: httpFetch,
        urlFor: (f) => storageUrl(voiceBucket, f.objectPath, emulator: _emulator.isEmpty ? null : _emulator),
        allowed: () async => state.value.enabled && await _onWifi(),
      );
      var last = DateTime.now();
      final r = await d.download(
        [for (final p in _manifest.packs) ...p.files],
        onFile: (_) {
          if (DateTime.now().difference(last).inMilliseconds > 500) {
            last = DateTime.now();
            _publish();
          }
        },
      );
      debugPrint('Voice library: ${r.downloaded} downloaded, ${r.failed} failed, stopped ${r.stopped}');
      if (r.stopped && state.value.enabled) _publish(waitingForWifi: true);
    } catch (e) {
      debugPrint('Voice library: $e');
    } finally {
      _downloader = null;
      _publish(running: false);
    }
  }

  /// Picks up recordings added since this app was built: the bucket's
  /// manifest wins when it is newer than the one in use.
  Future<void> _refreshManifest(VoiceCache cache) async {
    try {
      final url = storageUrl(
        voiceBucket,
        voiceManifestObject,
        emulator: _emulator.isEmpty ? null : _emulator,
      );
      final text = utf8.decode(await httpFetch(url));
      final remote = VoiceManifest.parse(text);
      if (remote.version <= _manifest.version) return;
      await _savedFile(cache.dir.parent).writeAsString(text);
      _manifest = remote;
      await cache.prune(remote);
      _publish();
    } catch (e) {
      debugPrint('Voice manifest not refreshed: $e');
    }
  }
}
