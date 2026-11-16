import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/ui/session.dart';

void main() {
  test('many short Turkish praise lines, none repeated', () {
    expect(teaPraises.length, greaterThanOrEqualTo(25));
    expect(teaPraises.toSet().length, teaPraises.length);
    expect(teaPraises, containsAll(['Helal olsun!', 'Helal koçuma!', 'Eline sağlık!']));
    for (final p in [...teaPraises, ...kidPraises]) {
      expect(p.length, lessThanOrEqualTo(24), reason: '$p must fit on one line');
    }
  });

  test('Çocuk modu has its own praise, without grown-up slang', () {
    expect(kidPraises.length, greaterThanOrEqualTo(12));
    expect(kidPraises.toSet().length, kidPraises.length);
    expect(kidPraises.toSet().intersection(teaPraises.toSet()), isEmpty);
    for (var n = 0; n < 40; n++) {
      final p = praiseFor(n, kid: true);
      expect([...kidPraises, ...kidProverbPraises], contains(p));
      expect(p, isNot(contains('koç')));
      expect(comboPraise(n + comboThreshold, kid: true), contains('${n + comboThreshold}'));
    }
  });

  test('a short proverb comes every few right answers', () {
    expect(proverbPraises, contains('Damlaya damlaya göl olur!'));
    for (final p in [...proverbPraises, ...kidProverbPraises]) {
      expect(p.length, lessThanOrEqualTo(34), reason: '$p is too long for the panel');
    }
    final adult = [for (var n = 0; n < 40; n++) praiseFor(n, kid: false)];
    final proverbs = adult.where(proverbPraises.contains).length;
    expect(proverbs, 40 ~/ proverbEvery);
    expect(adult.where(teaPraises.contains).length, 40 - proverbs);
  });

  test('consecutive answers never get the same praise', () {
    for (final kid in [false, true]) {
      for (var n = 0; n < 60; n++) {
        expect(praiseFor(n, kid: kid), isNot(praiseFor(n + 1, kid: kid)));
      }
    }
  });

  test('a run of right answers names its length, with varied wording', () {
    final lines = {for (var n = comboThreshold; n < comboThreshold + 5; n++) comboPraise(n, kid: false)};
    expect(lines.length, 5);
    for (var n = comboThreshold; n < 20; n++) {
      expect(comboPraise(n, kid: false), contains('$n'));
    }
  });

  test('soft lines after a wrong answer stay calm and unique', () {
    expect(softRetries.length, greaterThanOrEqualTo(8));
    expect(softRetries.toSet().length, softRetries.length);
  });
}
