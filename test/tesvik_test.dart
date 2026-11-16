import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/ui/session.dart';

void main() {
  test('many short Turkish praise lines, none repeated', () {
    expect(teaPraises.length, greaterThanOrEqualTo(25));
    expect(teaPraises.toSet().length, teaPraises.length);
    expect(teaPraises, containsAll(['Helal olsun!', 'Helal koçuma!', 'Eline sağlık!']));
    for (final p in teaPraises) {
      expect(p.length, lessThanOrEqualTo(24), reason: '$p must fit on one line');
    }
  });

  test('consecutive answers never get the same praise', () {
    for (var n = 0; n < 60; n++) {
      expect(praiseFor(n), isNot(praiseFor(n + 1)));
    }
  });

  test('a run of right answers names its length, with varied wording', () {
    final lines = {for (var n = comboThreshold; n < comboThreshold + 5; n++) comboPraise(n)};
    expect(lines.length, 5);
    for (var n = comboThreshold; n < 20; n++) {
      expect(comboPraise(n), contains('$n'));
    }
  });

  test('soft lines after a wrong answer stay calm and unique', () {
    expect(softRetries.length, greaterThanOrEqualTo(8));
    expect(softRetries.toSet().length, softRetries.length);
  });
}
