import '../models/course.dart';

/// How long a listening piece of a level is: replies, English words,
/// questions and the length it aims at. A1–A2 is spoken slowly and clearly
/// (about 2 words a second), B1 at a calm everyday pace, B2–C1 at a natural
/// one.
class ListeningRules {
  const ListeningRules({
    required this.minLines,
    required this.maxLines,
    required this.minWords,
    required this.maxWords,
    required this.minQuestions,
    required this.maxQuestions,
    required this.seconds,
    required this.wordsPerSecond,
    this.needsInference = false,
  });

  final int minLines;
  final int maxLines;
  final int minWords;
  final int maxWords;
  final int minQuestions;
  final int maxQuestions;

  /// Target length in seconds (30, 45 or 60).
  final int seconds;
  final double wordsPerSecond;

  /// B2–C1: at least one inference or attitude question and some idioms.
  final bool needsInference;

  static const _basic = ListeningRules(
    minLines: 4,
    maxLines: 6,
    minWords: 45,
    maxWords: 75,
    minQuestions: 2,
    maxQuestions: 3,
    seconds: 30,
    wordsPerSecond: 2,
  );
  static const _everyday = ListeningRules(
    minLines: 6,
    maxLines: 8,
    minWords: 90,
    maxWords: 130,
    minQuestions: 3,
    maxQuestions: 4,
    seconds: 45,
    wordsPerSecond: 2.4,
  );
  static const _advanced = ListeningRules(
    minLines: 8,
    maxLines: 12,
    minWords: 135,
    maxWords: 190,
    minQuestions: 3,
    maxQuestions: 4,
    seconds: 60,
    wordsPerSecond: 2.7,
    needsInference: true,
  );

  /// Rules of a CEFR level; unknown levels use the A1–A2 ones.
  static ListeningRules of(String? cefr) => switch (cefr) {
    'B1' => _everyday,
    'B2' || 'C1' || 'C2' => _advanced,
    _ => _basic,
  };
}

/// English words of a text (tokens with a letter or digit).
int englishWords(String text) =>
    text.trim().split(RegExp(r'\s+')).where((w) => w.contains(RegExp('[A-Za-z0-9]'))).length;

/// Words of the whole dialogue.
int dialogueWords(ListeningPiece piece) => piece.lines.fold(0, (n, l) => n + englishWords(l.text));

/// Rough playing time at the level's pace, in seconds.
int estimatedSeconds(ListeningPiece piece) {
  final r = ListeningRules.of(piece.cefr);
  return (dialogueWords(piece) / r.wordsPerSecond).round();
}

/// "≈30 sn" for a node of the path (from its level, also in an outline).
String listeningLength(PathNode node) =>
    '≈${ListeningRules.of(node.cefr ?? node.listening?.cefr).seconds} sn';
