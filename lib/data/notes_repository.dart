import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notes.dart';

/// Loads the notes imported from Notion (see tool/import_notes.js).
Future<NotesBundle> loadNotes(AssetBundle bundle) async {
  Future<dynamic> read(String name) async => jsonDecode(await bundle.loadString('assets/notes/$name'));
  final words = (await read('words.json') as List)
      .map((w) => NoteWord.fromJson(w as Map<String, dynamic>))
      .toList();
  final topics = (await read('grammar.json') as List)
      .map((t) => GrammarTopic.fromJson(t as Map<String, dynamic>))
      .toList();
  final meta = await read('meta.json') as Map<String, dynamic>;
  return NotesBundle(
    words: words,
    topics: topics,
    diaryPrompts: (meta['diaryPrompts'] as List).cast<String>(),
  );
}

final notesProvider = FutureProvider<NotesBundle>((ref) => loadNotes(rootBundle));
