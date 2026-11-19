import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'emoji_compat.dart';

export 'emoji_compat.dart';

const _channel = MethodChannel('dilmac/device');

/// Asks the Android side for its API level and turns [LegacyEmoji.enabled]
/// on below API 29. Any failure leaves it off.
Future<void> detectLegacyEmoji() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final sdk = await _channel.invokeMethod<int>('sdkInt');
    LegacyEmoji.enabled = sdk != null && sdk < 29;
  } on Object catch (e) {
    debugPrint('sdkInt: $e');
  }
}

/// Reads assets like [rootBundle] but, on old Android, passes JSON and text
/// assets through [legacyEmoji].
class LegacyEmojiBundle extends CachingAssetBundle {
  LegacyEmojiBundle(this._inner);
  final AssetBundle _inner;

  static bool _isText(String key) => key.endsWith('.json') || key.endsWith('.md') || key.endsWith('.txt');

  @override
  Future<ByteData> load(String key) async {
    final data = await _inner.load(key);
    if (!LegacyEmoji.enabled || !_isText(key)) return data;
    final text = utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final swapped = legacyEmoji(text);
    if (identical(swapped, text) || swapped == text) return data;
    final bytes = Uint8List.fromList(utf8.encode(swapped));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<ImmutableBuffer> loadBuffer(String key) => _inner.loadBuffer(key);
}

/// The bundle the app reads its content from (use instead of [rootBundle]).
final AssetBundle appBundle = LegacyEmojiBundle(rootBundle);
