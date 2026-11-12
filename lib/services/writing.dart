import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../models/course.dart';
import 'conversation.dart';
import 'firebase/firebase_providers.dart';

/// One correction in AI writing feedback: [from] → [to], why in Turkish, and
/// its error type (one of [writingFocusTypes] or "other").
class WritingCorrection {
  const WritingCorrection({required this.from, required this.to, required this.whyTr, required this.type});
  final String from;
  final String to;
  final String whyTr;
  final String type;
}

/// AI feedback on a writing task (functions/src/assessWriting.ts): rubric
/// scores 0–3 (task, accuracy, range, coherence), a few focused corrections
/// and the next step in Turkish.
class WritingFeedback {
  const WritingFeedback({
    required this.scores,
    required this.corrections,
    required this.nextTr,
    this.remaining,
  });
  final Map<String, int> scores;
  final List<WritingCorrection> corrections;
  final String nextTr;

  /// Feedback requests left today.
  final int? remaining;

  /// Rubric criteria in display order with their Turkish names.
  static const criteria = {
    'task': 'Görev',
    'accuracy': 'Doğruluk',
    'range': 'Kelime çeşitliliği',
    'coherence': 'Tutarlılık ve bağlantı',
  };

  factory WritingFeedback.fromJson(Map<String, Object?> j) {
    final scores = Map<String, Object?>.from((j['scores'] as Map?) ?? const {});
    return WritingFeedback(
      scores: {
        for (final c in criteria.keys)
          if (scores[c] is num) c: (scores[c]! as num).round().clamp(0, 3),
      },
      corrections: [
        for (final c in (j['corrections'] as List?) ?? const [])
          if (c is Map)
            WritingCorrection(
              from: '${c['from'] ?? ''}',
              to: '${c['to'] ?? ''}',
              whyTr: '${c['why_tr'] ?? ''}',
              type: '${c['type'] ?? 'other'}',
            ),
      ],
      nextTr: j['next_tr'] as String? ?? '',
      remaining: (j['remaining'] as num?)?.toInt(),
    );
  }
}

/// The app's error category of a writing error type, for the error analysis
/// screen (progress.errorStats); null for "other".
TrErrorCategory? errorCategoryOf(String type) => switch (type) {
  'article' => TrErrorCategory.article,
  'tense' => TrErrorCategory.tense,
  'preposition' => TrErrorCategory.preposition,
  'word_order' => TrErrorCategory.wordOrder,
  'be' => TrErrorCategory.toBe,
  _ => null,
};

/// Words in a learner's text, as the server counts them.
int wordCount(String text) => RegExp(r"[A-Za-z0-9'’-]+").allMatches(text).length;

/// The free check of a writing task, without a server: whether the text is
/// long enough and every checklist item is ticked, plus short Turkish notes.
({bool done, List<String> notes}) localWritingCheck(Exercise ex, String text, Set<int> ticked) {
  final words = wordCount(text);
  final notes = <String>[
    if (words < ex.minWords) 'En az ${ex.minWords} kelime yaz (şu an $words).',
    if (ex.maxWords > 0 && words > ex.maxWords)
      'Biraz kısalt: hedef en çok ${ex.maxWords} kelime (şu an $words).',
    if (ticked.length < ex.checklist.length) 'Kontrol listesindeki her maddeyi metninde ara ve işaretle.',
  ];
  return (done: words >= ex.minWords && ticked.length >= ex.checklist.length, notes: notes);
}

class WritingException implements Exception {
  const WritingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks the server for AI feedback on a writing task.
abstract class WritingService {
  Future<WritingFeedback> assess(String taskId, String text);
}

/// Calls the `assessWriting` Cloud Function, which checks Premium and the
/// daily quota and keeps the rubric and the API key on the server.
class CallableWritingService implements WritingService {
  CallableWritingService(this._invoke);

  CallableWritingService.firebase(FirebaseFunctions functions)
    : this((name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);

  final CallableInvoker _invoke;

  @override
  Future<WritingFeedback> assess(String taskId, String text) async {
    final Object? raw;
    try {
      raw = await _invoke('assessWriting', {
        'taskId': taskId,
        'text': text,
      }).timeout(const Duration(seconds: 90));
    } on FirebaseFunctionsException catch (e) {
      throw WritingException(messageForCode(e.code));
    } on Exception {
      throw const WritingException('Bağlantı kurulamadı. Yerel kontrol yine de çalışıyor.');
    }
    return WritingFeedback.fromJson(Map<String, Object?>.from(raw as Map));
  }

  /// Turkish message for a callable error code.
  static String messageForCode(String code) => switch (code) {
    'resource-exhausted' => 'Bugünlük yazma geri bildirimi hakkın doldu. Yarın tekrar dene.',
    'permission-denied' => 'Yapay zekâ geri bildirimi Premium üyelere açık.',
    'not-found' => 'Bu görev için geri bildirim henüz hazır değil.',
    _ => CallableConversationService.messageForCode(code),
  };
}

/// The writing feedback service, or null when Firebase is off or nobody is
/// signed in (the exercise then uses [localWritingCheck] only).
final writingServiceProvider = Provider<WritingService?>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return null;
  return CallableWritingService.firebase(functions);
});
