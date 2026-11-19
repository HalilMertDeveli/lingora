// tool/icerik_tarama.dart içindeki saf kural fonksiyonlarının birim testleri.
import 'package:flutter_test/flutter_test.dart';

import '../tool/icerik_tarama.dart';

Set<String> rules(List<Issue> issues) => issues.map((i) => i.rule).toSet();

void main() {
  group('a/an', () {
    test('articleFor', () {
      expect(articleFor('apple'), 'an');
      expect(articleFor('banana'), 'a');
      expect(articleFor('hour'), 'an');
      expect(articleFor('honest'), 'an');
      expect(articleFor('university'), 'a');
      expect(articleFor('European'), 'a');
      expect(articleFor('one-way'), 'a');
      expect(articleFor('user'), 'a');
      expect(articleFor('unique'), 'a');
      expect(articleFor('umbrella'), 'an');
      expect(articleFor('unimportant'), 'an');
      expect(articleFor('FBI'), 'an');
      expect(articleFor('USB'), 'a');
      expect(articleFor('NASA'), isNull);
      expect(articleFor('8-hour'), 'an');
    });

    test('uyumsuzluk yakalanır, istisnalar geçer', () {
      expect(rules(checkFragment('I ate a apple.')), contains('a_an'));
      expect(rules(checkFragment('She is an teacher.')), contains('a_an'));
      expect(rules(checkFragment('It took an hour at a university.')), isNot(contains('a_an')));
      expect(rules(checkFragment('Choose a/an before the noun.')), isNot(contains('a_an')));
      expect(rules(checkFragment('He needs vitamin A every day.')), isNot(contains('a_an')));
      expect(rules(checkFragment('Dona Graça especially liked it.')), isNot(contains('a_an')));
    });
  });

  test('kelime tekrarı', () {
    expect(rules(checkFragment('I saw the the dog.')), contains('tekrar_kelime'));
    expect(rules(checkFragment('He said that that was fine.')), isNot(contains('tekrar_kelime')));
    expect(rules(checkFragment('It is five five five.')), isNot(contains('tekrar_kelime')));
    expect(rules(checkFragment('Santorio Santorio was a doctor.')), isNot(contains('tekrar_kelime')));
  });

  test('boşluk ve noktalama', () {
    expect(rules(checkFragment('Hello  world.')), contains('cift_bosluk'));
    expect(rules(checkFragment('Yes , I know.')), contains('bosluk_once'));
    expect(rules(checkFragment('Yes,I know.')), contains('bosluk_sonra'));
    expect(rules(checkFragment('Wait,, please.')), contains('cift_noktalama'));
    expect(rules(checkFragment('Wait.. please.')), contains('cift_noktalama'));
    expect(rules(checkFragment('Wait... please.')), isNot(contains('cift_noktalama')));
    expect(rules(checkFragment('It opens at 8 a.m., not later.')), isNot(contains('cift_noktalama')));
    expect(
      rules(checkFragment('He was born in Washington, D.C., in 1904.')),
      isNot(contains('cift_noktalama')),
    );
  });

  test('küçük i ve cümle başı', () {
    expect(rules(checkFragment('Yesterday i went home.')), contains('kucuk_i'));
    expect(rules(checkFragment("Then i'm going.")), contains('kucuk_i')); // i'm
    expect(rules(checkSentence('the cat sleeps.')), contains('kucuk_baslangic'));
    expect(rules(checkSentence('It rained. then we left.')), contains('kucuk_baslangic'));
    expect(rules(checkSentence('Ask Mr. Brown, e.g. tomorrow.')), isNot(contains('kucuk_baslangic')));
    // noktalamasız küçük harfli öbek cümle sayılmaz
    expect(rules(checkSentence('the man who spoke to you')), isNot(contains('kucuk_baslangic')));
  });

  test('denge', () {
    expect(rules(checkSentence('He said "hello and left.')), contains('denge'));
    expect(rules(checkSentence('This (is fine.')), contains('denge'));
    expect(rules(checkSentence('He said "hello" and left (quickly).')), isNot(contains('denge')));
  });

  test('karışıklıklar', () {
    expect(rules(checkFragment('You could of told me.')), contains('karisiklik'));
    expect(rules(checkFragment('She is taller then her brother.')), contains('karisiklik'));
    expect(rules(checkFragment('Your welcome!')), contains('karisiklik'));
    expect(rules(checkFragment('I have alot of work.')), contains('bilinen_yazim'));
    expect(rules(checkFragment('We had dinner and then we left.')), isNot(contains('karisiklik')));
    expect(
      rules(checkFragment('The report had an error in its very first table.')),
      isNot(contains('karisiklik')),
    );
    expect(rules(checkFragment('The day when I met you was rainy.')), isNot(contains('karisiklik')));
  });

  test('boşluk doldurma', () {
    expect(fillBlanks('I ___ a student.', 'am'), 'I am a student.');
    expect(fillBlanks('---- the rain, we went out.', 'despite'), 'Despite the rain, we went out.');
    expect(fillBlanks('Nobody knows when ---- .', 'it happened'), 'Nobody knows when it happened.');
    expect(fillBlanks('I ___ and you ___.', 'x'), 'I $blankWord and you $blankWord.');
  });

  test('Türkçe algılama', () {
    expect(isTurkish('Hastanede çalışan kardeşimin bizi ziyaret etmeye nadiren vakti olur.'), isTrue);
    expect(isTurkish('"Seeing it" cümlesinde "humbling" hangi anlamda?'), isTrue);
    expect(isTurkish('My name is Elif. I live in Beşiktaş, and I work in Kadıköy.'), isFalse);
    expect(isTurkish('The ferry to Kadıköy is slow but beautiful.'), isFalse);
  });

  test('cümle bölme', () {
    expect(splitSentences('Mr. Brown came. He sat down! Did he?'), [
      'Mr. Brown came.',
      'He sat down!',
      'Did he?',
    ]);
    expect(splitSentences('Line one\nLine two.'), ['Line one', 'Line two.']);
  });

  group('sözlük', () {
    SpellModel model() {
      final m = SpellModel();
      for (var i = 0; i < 30; i++) {
        m.addText('I will receive the letter and believe the friend until the government changes.');
      }
      m.addText('They walked to the park.');
      return m;
    }

    test('klasik yazım hatası önerilir', () {
      final m = model();
      m.addText('I will recieve it untill tomorrow.');
      expect(m.suggest('recieve')?.$1, 'receive');
      expect(m.suggest('untill')?.$1, 'until');
    });

    test('bilinen kelime, ek ve varyantlar işaretlenmez', () {
      final m = model();
      expect(m.suggest('receive'), isNull);
      expect(m.suggest('received'), isNull); // ekle türetilebilir
      expect(m.suggest('walking'), isNull);
      m.vocab.add('colour');
      expect(m.suggest('colour'), isNull);
      expect(SpellModel.variantPair('colour', 'color'), isTrue);
      expect(SpellModel.classicTypo('recieve', 'receive'), isTrue);
      expect(SpellModel.classicTypo('wafers', 'waters'), isFalse);
    });
  });

  test('bitiş noktalaması', () {
    expect(endsWithTerminal('Hello.'), isTrue);
    expect(endsWithTerminal('He said "yes."'), isTrue);
    expect(endsWithTerminal('Hello'), isFalse);
  });
}
