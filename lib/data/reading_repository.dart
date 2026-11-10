import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reading.dart';

List<ReadingStory> parseStories(String json) =>
    (jsonDecode(json) as List).map((s) => ReadingStory.fromJson(s as Map<String, dynamic>)).toList();

Future<List<ReadingStory>> loadStories(AssetBundle bundle) async =>
    parseStories(await bundle.loadString('assets/reading/stories.json'));

final storiesProvider = FutureProvider<List<ReadingStory>>((ref) => loadStories(rootBundle));
