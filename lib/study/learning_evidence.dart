import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';

/// Evidence of learning kept on this device (like the study log): events
/// that show something was really learned, not just seen. "Gerçek ilerleme"
/// in Profil is built only from this and the answer log; XP plays no part.
///
/// * a word PASSED a spaced review: the learner knew it on a later day than
///   they last saw it (seeing a card or knowing it in the same sitting does
///   not count);
/// * a question left the error notebook: answered right
///   [mistakeClearRun] times in a row, each on the day it came back.

/// Most entries kept per list (oldest dropped).
const maxEvidence = 5000;

class LearningEvidence {
  const LearningEvidence({this.wordsPassed = const {}, this.mistakesCleared = const {}});

  /// Word id → the day it first passed a spaced review.
  final Map<String, String> wordsPassed;

  /// Item key → the day it left the error notebook.
  final Map<String, String> mistakesCleared;

  Map<String, dynamic> toJson() => {'w': wordsPassed, 'm': mistakesCleared};

  factory LearningEvidence.fromJson(Map<String, dynamic> j) => LearningEvidence(
    wordsPassed: Map<String, String>.from(j['w'] as Map? ?? const {}),
    mistakesCleared: Map<String, String>.from(j['m'] as Map? ?? const {}),
  );

  static Map<String, String> _add(Map<String, String> m, String key, String day) {
    if (m.containsKey(key)) return m;
    final next = {...m, key: day};
    if (next.length <= maxEvidence) return next;
    return Map.fromEntries(next.entries.skip(next.length - maxEvidence));
  }

  LearningEvidence passWord(String id, String day) =>
      LearningEvidence(wordsPassed: _add(wordsPassed, id, day), mistakesCleared: mistakesCleared);

  LearningEvidence clearMistake(String key, String day) =>
      LearningEvidence(wordsPassed: wordsPassed, mistakesCleared: _add(mistakesCleared, key, day));
}

/// Whether a review graded [known] on [today] is a spaced pass: the word was
/// last seen on an earlier day ([lastSeen], null for a new card).
bool isSpacedPass({required bool known, required String? lastSeen, required String today}) =>
    known && lastSeen != null && lastSeen.compareTo(today) < 0;

class LearningEvidenceNotifier extends Notifier<LearningEvidence> {
  static const _key = 'learning_evidence_v1';

  @override
  LearningEvidence build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const LearningEvidence();
    try {
      return LearningEvidence.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const LearningEvidence();
    }
  }

  void _save(LearningEvidence e) {
    if (identical(e.wordsPassed, state.wordsPassed) && identical(e.mistakesCleared, state.mistakesCleared)) {
      return;
    }
    state = e;
    ref.read(prefsProvider).setString(_key, jsonEncode(e.toJson()));
  }

  void passWord(String id, String day) => _save(state.passWord(id, day));
  void clearMistake(String key, String day) => _save(state.clearMistake(key, day));

  /// Progress was reset (another account on this phone): start over.
  void reset() {
    state = const LearningEvidence();
    ref.read(prefsProvider).remove(_key);
  }
}

final learningEvidenceProvider = NotifierProvider<LearningEvidenceNotifier, LearningEvidence>(
  LearningEvidenceNotifier.new,
);
