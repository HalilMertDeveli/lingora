import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/tr_errors.dart';

List<String> ids(String text, {String? expected}) =>
    detectTrErrors(text, expected: expected).map((e) => e.ruleId).toList();

void main() {
  group('rule set', () {
    test('has at least 50 rules with unique ids', () {
      expect(trRules.length, greaterThanOrEqualTo(50));
      expect(trRules.map((r) => r.id).toSet().length, trRules.length);
    });

    test('covers every category', () {
      final used = trRules.map((r) => r.category).toSet();
      expect(used, containsAll(TrErrorCategory.values));
    });

    for (final rule in trRules) {
      test('${rule.id}: catches and fixes its example', () {
        expect(rule.apply(rule.example), rule.fixed, reason: rule.example);
        final errors = detectTrErrors(rule.example);
        final mine = errors.where((e) => e.ruleId == rule.id);
        expect(mine, isNotEmpty, reason: 'detected: $errors');
        expect(mine.first.category, rule.category);
        expect(mine.first.explanation, isNotEmpty);
        // The fixed sentence must not trigger the same rule again.
        expect(rule.pattern.hasMatch(rule.fixed), isFalse, reason: rule.fixed);
      });
    }
  });

  group('classic Turkish-speaker mistakes', () {
    void fixes(String wrong, String right) =>
        expect(correctTrText(wrong), right, reason: 'found: ${detectTrErrors(wrong)}');

    test('to be and -s', () {
      fixes('I am agree with you', 'I agree with you');
      fixes("I'm agree.", 'I agree.');
      fixes('She is agree with me.', 'She agrees with me.');
      fixes('I have 25 years.', 'I am 25 years old.');
      fixes('She has 30 years.', 'She is 30 years old.');
      fixes('He go to work by bus.', 'He goes to work by bus.');
      fixes('My mother cook every day.', 'My mother cooks every day.');
      fixes('She like coffee', 'She likes coffee');
      fixes("He don't know.", "He doesn't know.");
      fixes("Does she likes it?", 'Does she like it?');
      fixes('I am student.', 'I am a student.');
      fixes('She is engineer.', 'She is an engineer.');
      fixes('They tired.', 'They are tired.');
    });

    test('tense', () {
      fixes("I didn't went there.", "I didn't go there.");
      fixes('Did you saw the film?', 'Did you see the film?');
      fixes('She can speaks English.', 'She can speak English.');
      fixes('I must to go.', 'I must go.');
      fixes('We go to Antalya last summer.', 'We went to Antalya last summer.');
      fixes('Yesterday I buy a new phone.', 'Yesterday I bought a new phone.');
      fixes('If it will rain, we will stay home.', 'If it rains, we will stay home.');
      fixes('He is wanting a dog.', 'He wants a dog.');
    });

    test('since and for', () {
      fixes('I live here since 2 years.', 'I have lived here for 2 years.');
      fixes('I am working here since 2019.', 'I have been working here since 2019.');
      fixes('She works here for 5 years.', 'She has worked here for 5 years.');
      fixes('I am here since Monday.', 'I have been here since Monday.');
    });

    test('prepositions', () {
      fixes('I am going to home.', 'I am going home.');
      fixes('I listen music.', 'I listen to music.');
      fixes('He is married with my cousin.', 'He is married to my cousin.');
      fixes('Send it until Monday.', 'Send it by Monday.');
      fixes('See you in Friday.', 'See you on Friday.');
      fixes('She arrived to the airport.', 'She arrived at the airport.');
      fixes('It happened before 3 years.', 'It happened 3 years ago.');
    });

    test('nouns, plurals and articles', () {
      fixes('People is nice.', 'People are nice.');
      fixes('Thanks for the informations.', 'Thanks for the information.');
      fixes('She gave me an advice.', 'She gave me some advice.');
      fixes('I bought three book.', 'I bought three books.');
      fixes('I have an idea and a umbrella.', 'I have an idea and an umbrella.');
      fixes('There is many cars.', 'There are many cars.');
    });

    test('word choice, order and false friends', () {
      fixes('I make my homework.', 'I do my homework.');
      fixes('I have made my homework.', 'I have done my homework.');
      fixes('Everybody does mistakes.', 'Everybody makes mistakes.');
      fixes('He is very sympathetic.', 'He is very nice.');
      fixes('She has a dress red.', 'She has a red dress.');
      fixes('This is more better.', 'This is better.');
      fixes('I don\'t want nothing.', 'I don\'t want anything.');
      fixes('Can I pull a selfie?', 'Can I take a selfie?');
      fixes('Please close the lights.', 'Please turn off the lights.');
      fixes('What you want?', 'What do you want?');
    });
  });

  group('no false positives', () {
    const correct = [
      'I agree with you.',
      'I am 25 years old.',
      'I have 5 years of experience.',
      'He goes to school every day.',
      'Does he go to school?',
      "She doesn't like coffee.",
      'Why does she work so late?',
      'Let it go.',
      'I made her cry.',
      'Can he swim?',
      'I am a teacher.',
      'She is an engineer.',
      'An hour ago I was at home.',
      'It was a useful idea.',
      'A European city.',
      'He is a university student.',
      'Are you happy?',
      'It makes me happy.',
      'Are you coming tonight?',
      'I bring my lunch to work.',
      'I am going home now.',
      'I listen to music every day.',
      'She is married to a doctor.',
      'She is married with two children.',
      'I have lived here for five years.',
      'I have lived here since 2015.',
      'I have been working here since 2019.',
      'I work for two hours a day.',
      'I stay home since it is raining.',
      'I went to the cinema yesterday.',
      "I didn't go to school yesterday.",
      'Did you go to the cinema yesterday?',
      'I go to school every day, but yesterday I stayed home.',
      'When I come home, I will call you.',
      "I don't know when he will come.",
      'When I go to school, I take the bus.',
      'What I mean is simple.',
      'Where do you live?',
      'Do you know where the station is?',
      'I know what is good for me.',
      'People are very friendly.',
      'Everyone is here.',
      'I have two brothers.',
      'She is a five year old girl.',
      'It is a ten minute walk.',
      'I have one brother.',
      'Many times I tried.',
      'There is a lot of water.',
      'There are many people.',
      'I need some information.',
      'I like football very much.',
      'I like it very much.',
      'This book is better than that one.',
      'It is more expensive than the other one.',
      'He is the most honest man I know.',
      'He is as tall as his father.',
      'I do my homework every evening.',
      'I made a mistake.',
      'Do mistakes matter?',
      'Take a photo, please.',
      'Turn on the light.',
      'Open the door.',
      'Tell me the truth.',
      'Can you say them again?',
      'I watch TV every evening.',
      'Look at the TV.',
      'I play the guitar.',
      'She speaks English very well.',
      'He cooks food that is good.',
      'Thank you very much.',
      'In my opinion, it is great.',
      'According to the news, it will rain.',
      'This cake is too sweet.',
      'This is too good to be true.',
      'I study English on Monday.',
      'I was born on January 5.',
      'I was born in May.',
      'She is good at math.',
      'I am interested in art.',
      'I am interested to hear your idea.',
      'He is afraid of dogs.',
      'Please explain it to me.',
      'We discussed the project.',
      'I will wait for you.',
      'I called my mom.',
      'I saw it on TV.',
      'We met at the same time.',
      'I moved here two years ago.',
      'Finish it by Friday.',
      'Wait until Friday.',
      'I stayed at home.',
      'I said no.',
      "I can't say no.",
      "I don't know if no one came.",
      'I never said that.',
      'She was sympathetic to my problem.',
      'This fabric is soft.',
      'Is there a parking lot near here?',
      'I check my email every morning.',
      'Let me help you.',
      'I want you to come.',
      'I have a car.',
      'We have car insurance.',
      'Her hair is long.',
      'The news is good.',
      'Plan A is better.',
      'I.e. this is fine.',
      'I really like this song.',
      'I am bored.',
      'What is it called?',
      'I earn 3000 dollars a month.',
      'The film is boring.',
      'My house is big.',
    ];
    for (final s in correct) {
      test(s, () => expect(detectTrErrors(s), isEmpty));
    }
  });

  group('with an accepted answer', () {
    test('rules that also match the accepted answer are ignored', () {
      // "I am going home" is correct; nothing about "going" should be flagged.
      expect(ids('I am going to home', expected: 'I am going home'), ['go_to_home']);
      final e = detectTrErrors('I am going to home', expected: 'I am going home').single;
      expect(e.corrected, 'I am going home');
      expect(e.wrong, 'going to home');
    });

    test('capital letters are not blamed in exercises', () {
      expect(ids('i study english', expected: 'I study English'), isEmpty);
    });

    test('word order is explained', () {
      final e = detectTrErrors('student a am I', expected: 'I am a student').single;
      expect(e.category, TrErrorCategory.wordOrder);
    });

    test('missing article, be and preposition are explained', () {
      expect(detectTrErrors('He teacher', expected: 'He is a teacher').map((e) => e.category), [
        TrErrorCategory.article,
        TrErrorCategory.toBe,
      ]);
      expect(detectTrErrors('I am a students', expected: 'I am a student').map((e) => e.category), [
        TrErrorCategory.plural,
      ]);
      expect(
        detectTrErrors('He like it', expected: 'He likes it').first.category,
        TrErrorCategory.thirdPerson,
      );
      expect(detectTrErrors('I listen him', expected: 'I listen to him').first.ruleId, 'listen_to');
    });

    test('unrelated words give no explanation', () {
      expect(detectTrErrors('Good night', expected: 'Good morning'), isEmpty);
      final diff = answerWordDiff('Good night', 'Good morning');
      expect(diff.missing, ['morning']);
      expect(diff.extra, ['night']);
    });

    test('closest accepted answer is chosen', () {
      expect(
        closestAnswer('Good morning thanks', ['Good morning, thank you', 'Good morning, thanks']),
        'Good morning, thanks',
      );
    });
  });

  test('empty text has no errors', () {
    expect(detectTrErrors('   '), isEmpty);
  });
}
