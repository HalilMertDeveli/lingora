// Real Galaxy M22 (Android 13) dictation: each pause starts a new segment
// whose partial results begin empty. The transcript must keep all of them.
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/services/speech.dart';

void main() {
  test('segments after a pause are joined, not overwritten (device log)', () {
    final j = TranscriptJoiner();
    String? out;
    for (final p in [
      '',
      'last',
      'last year',
      'last year we built a payment app',
      'last year we built a payment app with',
      '',
      '',
      'I',
      'I wrote',
      'I wrote The backend services and the tests',
    ]) {
      out = j.add(p);
    }
    expect(out, 'last year we built a payment app with I wrote The backend services and the tests');
  });

  test('a recognizer that keeps the whole text in one result is unchanged', () {
    final j = TranscriptJoiner();
    j.add('I am');
    j.add('I am a backend');
    expect(j.add('I am a backend developer'), 'I am a backend developer');
  });

  test('an early revision of the first word is not a new segment', () {
    final j = TranscriptJoiner();
    j.add('Hi');
    expect(j.add('I am Mert'), 'I am Mert');
  });

  test('a new segment without an empty result in between is kept too', () {
    final j = TranscriptJoiner();
    j.add('my name is Mert');
    expect(j.add('I live in Ankara'), 'my name is Mert I live in Ankara');
  });
}
