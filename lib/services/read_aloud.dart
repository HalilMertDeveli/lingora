import 'speech.dart';

/// Playback rate of the slow (turtle) reading of a whole text: recordings
/// play at half speed, the phone's engine a little slower than that.
const slowReadRate = 0.5;

/// The sentences of a plain text: split after `.`, `!` or `?` (and a
/// closing quote) followed by white space. Empty pieces are dropped.
List<String> splitSentences(String text) => [
  for (final s in text.trim().split(RegExp(r'(?<=[.!?]["”’]?)\s+')))
    if (s.trim().isNotEmpty) s.trim(),
];

/// Reads a text aloud sentence after sentence with a [LinePlayer], each
/// line waiting for the previous one to be heard. A newer [play], [cancel]
/// or [stop] ends the running one.
class ReadAloud {
  ReadAloud(this._player, {required this.onSentence});

  final LinePlayer _player;

  /// The sentence being read, or null when reading finished or stopped.
  final void Function(int? sentence) onSentence;

  int _run = 0;
  bool _playing = false;

  bool get playing => _playing;

  /// Reads [sentences] from [from] to the end.
  Future<void> play(List<String> sentences, {int from = 0, bool slow = false}) async {
    final run = ++_run;
    _playing = true;
    for (var i = from; i < sentences.length; i++) {
      if (run != _run) return;
      onSentence(i);
      await _player.sayLine(sentences[i], rate: slow ? slowReadRate : 1);
    }
    if (run != _run) return;
    _playing = false;
    onSentence(null);
  }

  /// Ends the reading without silencing the voice (a single sentence the
  /// learner asked for takes over).
  void cancel() {
    _run++;
    _playing = false;
  }

  /// Ends the reading and silences the voice.
  Future<void> stop() {
    cancel();
    return _player.stopLine();
  }
}
