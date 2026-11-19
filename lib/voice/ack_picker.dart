import 'dart:math';

import 'package:flutter/foundation.dart';

import 'turn_taking.dart';

/// Picks the backchannel to play while a reply is late: random, never the
/// same one twice in a row, with its pre-synthesized neural audio when there
/// is one (otherwise the phone voice says it).
class AckPicker {
  AckPicker(this.phrases, {Random? random}) : _random = random ?? Random();
  final List<String> phrases;
  final Random _random;
  final _audio = <String, Uint8List>{};
  String? _last;

  /// Stores the neural audio for [phrase] (from `speak`, cached on the server).
  void setAudio(String phrase, Uint8List? audio) {
    if (audio != null && audio.isNotEmpty) _audio[phrase] = audio;
  }

  bool hasAudio(String phrase) => _audio.containsKey(phrase);

  SpokenSentence? pick({double rate = 1}) {
    final choices = [
      for (final p in phrases)
        if (p != _last) p,
    ];
    if (choices.isEmpty) return null;
    final p = choices[_random.nextInt(choices.length)];
    _last = p;
    return SpokenSentence(p, audio: _audio[p], rate: rate, ack: true);
  }
}

/// Median and 90th percentile of [ms] (null when empty).
({int median, int p90})? latencyStats(List<int> ms) {
  if (ms.isEmpty) return null;
  final s = [...ms]..sort();
  int at(double q) => s[((s.length - 1) * q).round()];
  return (median: at(0.5), p90: at(0.9));
}
