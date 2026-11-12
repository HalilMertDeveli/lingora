import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reading.dart';

List<ReadingStory> parseStories(String json) =>
    (jsonDecode(json) as List).map((s) => ReadingStory.fromJson(s as Map<String, dynamic>)).toList();

/// Extra reading files, same schema as stories.json: YDS extensive reading
/// (`yds_bol_okuma_*.json`, ids `yb_`) and the general course's library
/// (`genel_okuma_*.json`, ids `go_`).
const extraReadingPrefixes = ['assets/reading/yds_bol_okuma_', 'assets/reading/genel_okuma_'];

/// Which shelf a story comes from, shown on its library card; null for the
/// original stories.json texts.
String? readingSource(ReadingStory s) => s.id.startsWith('yb_')
    ? 'YDS'
    : s.id.startsWith('go_')
    ? 'Genel'
    : null;

/// stories.json plus every extra reading file, in file-name order. A broken
/// extra file is skipped and logged; a story id seen before is skipped.
Future<List<ReadingStory>> loadStories(AssetBundle bundle) async {
  final stories = parseStories(await bundle.loadString('assets/reading/stories.json'));
  List<String> extra;
  try {
    extra =
        (await AssetManifest.loadFromAssetBundle(bundle))
            .listAssets()
            .where((p) => extraReadingPrefixes.any(p.startsWith) && p.endsWith('.json'))
            .toList()
          ..sort();
  } catch (_) {
    extra = const [];
  }
  final ids = {for (final s in stories) s.id};
  for (final path in extra) {
    try {
      for (final s in parseStories(await bundle.loadString(path))) {
        if (ids.add(s.id)) stories.add(s);
      }
    } catch (e) {
      debugPrint('Okuma dosyası atlandı ($path): $e');
    }
  }
  return stories;
}

final storiesProvider = FutureProvider<List<ReadingStory>>((ref) => loadStories(rootBundle));
