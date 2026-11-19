import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legacy_emoji.dart';

/// Turkish glosses of exam options, kept beside the content so the questions
/// themselves never change: `assets/option_glosses/<exam>.json` maps a
/// question key (a path exercise's "nodeId#index", or an exam bank
/// question's id) to
///
/// ```json
/// {"tr": ["sulama", ...], "why": ["Doğru: ...", "Olmaz: ...", ...]}
/// ```
///
/// both in the question's option order. [tr] is what the option means (a
/// word's meaning, a linker's function, a sentence's translation); [why] is
/// one line on why it is right or does not fit. Either may be missing or
/// hold empty strings; nothing is shown then.
class OptionGloss {
  const OptionGloss({this.tr = const [], this.why = const []});

  final List<String> tr;
  final List<String> why;

  /// Turkish of option [i], or null.
  String? trOf(int i) => _at(tr, i);

  /// Why option [i] is right or wrong, or null.
  String? whyOf(int i) => _at(why, i);

  bool get isEmpty => tr.every((s) => s.trim().isEmpty) && why.every((s) => s.trim().isEmpty);

  static String? _at(List<String> list, int i) {
    if (i < 0 || i >= list.length) return null;
    final s = list[i].trim();
    return s.isEmpty ? null : s;
  }

  /// The gloss for a question with [optionCount] options, or null when it
  /// does not fit (a list of another length means the options changed, so
  /// showing it could pair a meaning with the wrong option).
  static OptionGloss? parse(Object? json, int optionCount) {
    if (json is! Map) return null;
    List<String>? strings(Object? v) {
      if (v == null) return const [];
      if (v is! List || v.length != optionCount) return null;
      return [for (final s in v) s is String ? s : ''];
    }

    final tr = strings(json['tr']);
    final why = strings(json['why']);
    if (tr == null || why == null) return null;
    final gloss = OptionGloss(tr: tr, why: why);
    return gloss.isEmpty ? null : gloss;
  }
}

/// The free one-line reason after the day's "Neden yanlış?" uses: the
/// gloss's line for the right option ("Doğru: …", the rule and the right
/// form), else the first sentence of [explanation]; null when neither
/// exists (the right answer is shown anyway).
String? basicWhyLine(OptionGloss? gloss, int? answer, {String explanation = ''}) {
  final line = answer == null ? null : gloss?.whyOf(answer);
  if (line != null) return line.startsWith('Doğru') ? line : 'Doğru: $line';
  final e = explanation.trim();
  if (e.isEmpty) return null;
  final end = e.indexOf(RegExp(r'[.!?](\s|$)'));
  return end < 0 ? e : e.substring(0, end + 1);
}

/// Every gloss file's entries, by question key.
class OptionGlosses {
  const OptionGlosses(this._raw);
  static const empty = OptionGlosses({});

  final Map<String, Object?> _raw;

  /// The gloss of question [key] with [optionCount] options, or null.
  OptionGloss? of(String? key, int optionCount) =>
      key == null ? null : OptionGloss.parse(_raw[key], optionCount);

  int get length => _raw.length;

  /// Reads one gloss file's JSON (a key → entry map; anything else is
  /// ignored so a broken file never breaks a question).
  static Map<String, Object?> decode(String source) {
    try {
      final j = jsonDecode(source);
      if (j is Map<String, dynamic>) {
        final items = j['items'];
        return items is Map<String, dynamic> ? items : j;
      }
    } on FormatException {
      // fall through
    }
    return const {};
  }
}

const optionGlossesPrefix = 'assets/option_glosses/';

/// All gloss files merged. Missing or unreadable files give no glosses.
Future<OptionGlosses> loadOptionGlosses(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths =
        manifest.listAssets().where((p) => p.startsWith(optionGlossesPrefix) && p.endsWith('.json')).toList()
          ..sort();
    final merged = <String, Object?>{};
    for (final p in paths) {
      merged.addAll(OptionGlosses.decode(await bundle.loadString(p)));
    }
    return OptionGlosses(merged);
  } catch (_) {
    return OptionGlosses.empty;
  }
}

final optionGlossesProvider = FutureProvider<OptionGlosses>((ref) => loadOptionGlosses(appBundle));
