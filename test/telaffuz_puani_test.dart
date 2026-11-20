import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/pronunciation_feedback.dart';

void main() {
  WordFeedback word(PronunciationFeedback f, String w) => f.words.firstWhere((x) => x.word == w);

  group('pronunciationFeedback', () {
    test('an exact transcription is all doğru', () {
      final f = pronunciationFeedback('I think three is enough.', [
        (words: 'I think three is enough', confidence: 0.92),
      ]);
      expect(f.allClear, isTrue);
      expect(f.problems, isEmpty);
      expect(f.lowConfidence, isFalse);
    });

    test('a sound-alike is "şu ses zor" with the Turkish-speaker issue', () {
      final f = pronunciationFeedback('I think three is enough', [
        (words: 'I tink tree is enough', confidence: 0.7),
      ]);
      expect(word(f, 'think').verdict, WordVerdict.hardSound);
      expect(word(f, 'think').heardAs, 'tink');
      expect(word(f, 'think').issue, SoundIssue.thVoiceless);
      expect(word(f, 'three').heardAs, 'tree');
      expect(word(f, 'I').verdict, WordVerdict.ok);
      expect(f.issues, [SoundIssue.thVoiceless]);
    });

    test('w/v, vowels and final consonants are named', () {
      expect(soundIssueFor('west', 'vest'), SoundIssue.wV);
      expect(soundIssueFor('very', 'wery'), SoundIssue.wV);
      expect(soundIssueFor('sheep', 'ship'), SoundIssue.vowelLength);
      expect(soundIssueFor('bad', 'bed'), SoundIssue.openA);
      expect(soundIssueFor('dog', 'dock'), SoundIssue.finalConsonant);
      expect(soundIssueFor('need', 'neat'), SoundIssue.finalConsonant);
      expect(soundIssueFor('they', 'day'), SoundIssue.thVoiced);
      expect(soundIssueFor('school', 'iskul'), SoundIssue.initialCluster);
      expect(soundIssueFor('sing', 'sin'), SoundIssue.ng);
      expect(soundIssueFor('worked', 'workid'), SoundIssue.edEnding);
    });

    test('a missing word is "anlaşılmadı" with a guessed issue', () {
      final f = pronunciationFeedback('The weather is nice', [(words: 'is nice', confidence: null)]);
      expect(word(f, 'weather').verdict, WordVerdict.unclear);
      expect(word(f, 'weather').issueIsGuess, isTrue);
      expect(word(f, 'weather').issue, SoundIssue.thVoiced);
      expect(word(f, 'nice').verdict, WordVerdict.ok);
    });

    test('a different word in the gap is a slip when it is close', () {
      final f = pronunciationFeedback('I want a big dog', [(words: 'I want a big dock', confidence: 0.8)]);
      expect(word(f, 'dog').verdict, WordVerdict.hardSound);
      expect(word(f, 'dog').issue, SoundIssue.finalConsonant);
    });

    test('the recognizer hesitating between sound-alikes flags the word', () {
      final f = pronunciationFeedback('Look at the sheep', [
        (words: 'look at the sheep', confidence: 0.6),
        (words: 'look at the ship', confidence: null),
      ]);
      expect(word(f, 'sheep').verdict, WordVerdict.hardSound);
      expect(word(f, 'sheep').heardAs, 'ship');
      expect(word(f, 'Look').verdict, WordVerdict.ok);
    });

    test('homophones and numbers stay doğru; nothing heard is all unclear', () {
      expect(
        pronunciationFeedback('I have two cats', [(words: 'I have 2 cats', confidence: 0.9)]).allClear,
        isTrue,
      );
      expect(
        pronunciationFeedback('I want to go', [(words: 'I want too go', confidence: 0.9)]).allClear,
        isTrue,
      );
      final none = pronunciationFeedback('Hello there', const []);
      expect(none.nothingHeard, isTrue);
      expect(none.words.every((w) => w.verdict == WordVerdict.unclear), isTrue);
    });

    test('a long sentence from the room is not an attempt at the word', () {
      // Galaxy QA: auto-listen heard someone nearby and blamed the learner's th.
      final f = pronunciationFeedback('think', [
        (words: 'Infinity customer service taking today because of my cell phone number', confidence: 0.8),
      ]);
      expect(f.nothingHeard, isTrue);
      expect(f.words.single.verdict, WordVerdict.unclear);
      // A short slip is still feedback, and a sentence with the word in it is fine.
      expect(
        word(pronunciationFeedback('think', [(words: 'sink', confidence: 0.8)]), 'think').heardAs,
        'sink',
      );
      expect(pronunciationFeedback('think', [(words: 'I think so', confidence: 0.9)]).allClear, isTrue);
    });

    test('low recognizer confidence is a note, not a score', () {
      final f = pronunciationFeedback('Good morning', [(words: 'good morning', confidence: 0.31)]);
      expect(f.lowConfidence, isTrue);
      expect(f.allClear, isTrue);
    });
  });
}
