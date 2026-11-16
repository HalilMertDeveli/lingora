// Generates the short answer sounds in assets/sfx/ from plain sine tones.
//
//   dart run tool/make_sfx.dart
//
// The sounds are made here, not taken from anywhere: soft two- and
// four-note chimes with a quick fade so they never click.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const rate = 22050;

/// One note: [freq] Hz for [ms] milliseconds, a light second harmonic and an
/// exponential fade.
List<double> note(double freq, int ms, {double gain = 0.5}) {
  final n = rate * ms ~/ 1000;
  return [
    for (var i = 0; i < n; i++)
      () {
        final t = i / rate;
        final attack = min(1.0, i / (rate * 0.006));
        final decay = exp(-4.0 * i / n);
        final wave = sin(2 * pi * freq * t) + 0.25 * sin(4 * pi * freq * t);
        return gain * attack * decay * wave / 1.25;
      }(),
  ];
}

List<double> silence(int ms) => List.filled(rate * ms ~/ 1000, 0);

Uint8List wav(List<double> samples) {
  final data = ByteData(44 + samples.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  final dir = Directory('assets/sfx')..createSync(recursive: true);
  final sounds = {
    // Bright rising pair.
    'dogru.wav': [...note(659.3, 110), ...note(880.0, 220)],
    // Soft, low falling pair: a nudge, not a buzzer.
    'yanlis.wav': [...note(392.0, 120, gain: 0.35), ...note(311.1, 220, gain: 0.35)],
    // Four-note arpeggio for a finished lesson.
    'kutlama.wav': [
      ...note(523.3, 110),
      ...note(659.3, 110),
      ...note(784.0, 110),
      ...note(1046.5, 380),
      ...silence(40),
    ],
  };
  for (final MapEntry(:key, :value) in sounds.entries) {
    File('${dir.path}/$key').writeAsBytesSync(wav(value));
    stdout.writeln('assets/sfx/$key ${value.length * 2 ~/ 1024} KB');
  }

  // Reminder notification: three light, overlapping bell notes, like a
  // spoon on a tea glass. Android plays it from res/raw.
  final raw = Directory('android/app/src/main/res/raw')..createSync(recursive: true);
  final bell = mix([
    (0, note(1318.5, 700, gain: 0.45)),
    (140, note(1568.0, 700, gain: 0.4)),
    (280, note(2093.0, 900, gain: 0.35)),
  ]);
  File('${raw.path}/dilbaz_bildirim.wav').writeAsBytesSync(wav(bell));
  stdout.writeln('${raw.path}/dilbaz_bildirim.wav ${bell.length * 2 ~/ 1024} KB');
}

/// Overlays [parts], each starting [ms] after the beginning.
List<double> mix(List<(int ms, List<double> samples)> parts) {
  final length = parts.map((p) => rate * p.$1 ~/ 1000 + p.$2.length).reduce(max);
  final out = List<double>.filled(length, 0);
  for (final (ms, s) in parts) {
    final start = rate * ms ~/ 1000;
    for (var i = 0; i < s.length; i++) {
      out[start + i] += s[i];
    }
  }
  final peak = out.map((v) => v.abs()).reduce(max);
  return peak > 0.9 ? [for (final v in out) v * 0.9 / peak] : out;
}
