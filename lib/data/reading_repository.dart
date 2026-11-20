import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legacy_emoji.dart';
import '../models/reading.dart';

List<ReadingStory> parseStories(String json) =>
    (jsonDecode(json) as List).map((s) => ReadingStory.fromJson(s as Map<String, dynamic>)).toList();

/// Extra reading files, same schema as stories.json: YDS extensive reading
/// (`yds_bol_okuma_*.json`, ids `yb_`) and the general course's library
/// (`genel_okuma_*.json`, ids `go_`).
const extraReadingPrefixes = ['assets/reading/yds_bol_okuma_', 'assets/reading/genel_okuma_'];

/// The shelf tag on a story's library card: only the YDS shelf has one. The
/// general library (`go_` ids) sits among the stories.json texts at the same
/// levels, so a "Genel" tag on some of them only made the list uneven.
String? readingSource(ReadingStory s) => s.id.startsWith('yb_') ? 'YDS' : null;

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

final storiesProvider = FutureProvider<List<ReadingStory>>((ref) => loadStories(appBundle));
