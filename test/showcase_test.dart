import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/shop_catalog.dart';

/// The ids others may see. Consumables (the streak freeze) are never worn.
Set<String> catalogIds() => {
  for (final item in shopItems)
    if (!item.consumable) item.id,
};

Set<String> idsIn(String text) => {
  for (final m in RegExp(r'''['"]([a-z]{2}_[a-z0-9_]+)['"]''').allMatches(text)) m[1]!,
};

void main() {
  test('firestore.rules accepts exactly the Mağaza catalog ids', () {
    final rules = File('firestore.rules').readAsStringSync();
    final start = rules.indexOf('function knownItemId');
    expect(start, isNot(-1));
    final list = rules.substring(rules.indexOf('[', start), rules.indexOf(']', start) + 1);
    expect(idsIn(list), catalogIds());
  });

  test('the league function accepts exactly the Mağaza catalog ids', () {
    final ts = File('functions/src/shop_ids.ts').readAsStringSync();
    expect(idsIn(ts), catalogIds());
  });
}
