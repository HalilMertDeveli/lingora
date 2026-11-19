import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation.dart' show CallableConversationService, CallableInvoker;
import 'firebase/firebase_providers.dart';

/// What the learner asks after "Neden yanlış?".
enum ExplainMode {
  confused('Anlamadım'),
  simpler('Daha basit anlat'),
  question('Soru sor');

  const ExplainMode(this.label);
  final String label;
}

/// The wrongly answered question, as the server needs it.
class ExplainQuestion {
  const ExplainQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.picked,
    this.explanation = '',
  });

  /// Question text (with its passage, shortened, when it has one).
  final String question;
  final List<String> options;
  final int answer;
  final int? picked;
  final String explanation;
}

/// One follow-up: what the learner asked (a mode label or their own words)
/// and the answer.
class ExplainTurn {
  const ExplainTurn(this.q, this.a);
  final String q;
  final String a;
}

class ExplainAnswer {
  const ExplainAnswer(this.text, {this.remaining});
  final String text;

  /// Follow-ups left today.
  final int? remaining;
}

class ExplainMoreException implements Exception {
  const ExplainMoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Follow-ups a learner can ask on one question (the server also caps the day).
const maxFollowUpsPerQuestion = 3;

/// Characters of the learner's own question.
const maxFollowUpChars = 200;

abstract class ExplainMoreService {
  Future<ExplainAnswer> ask(
    ExplainQuestion q,
    ExplainMode mode, {
    String text = '',
    List<ExplainTurn> history,
  });
}

/// Calls the `explainMore` Cloud Function (functions/src/explain_more.ts),
/// which checks Premium and the daily cap.
class CallableExplainMoreService implements ExplainMoreService {
  CallableExplainMoreService(this._invoke);

  CallableExplainMoreService.firebase(FirebaseFunctions functions)
    : this((name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);

  final CallableInvoker _invoke;

  @override
  Future<ExplainAnswer> ask(
    ExplainQuestion q,
    ExplainMode mode, {
    String text = '',
    List<ExplainTurn> history = const [],
  }) async {
    final Object? raw;
    try {
      raw = await _invoke('explainMore', {
        'question': q.question,
        'options': q.options,
        'answer': q.answer,
        'picked': q.picked,
        'explanation': q.explanation,
        'mode': mode.name,
        if (mode == ExplainMode.question) 'text': text.trim(),
        'history': [
          for (final h in history.reversed.take(maxFollowUpsPerQuestion).toList().reversed)
            {'q': h.q, 'a': h.a},
        ],
      }).timeout(const Duration(seconds: 60));
    } on FirebaseFunctionsException catch (e) {
      throw ExplainMoreException(messageForCode(e.code, reason: e.message));
    } on Exception {
      throw const ExplainMoreException('Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.');
    }
    final m = Map<String, Object?>.from(raw as Map);
    final text0 = (m['answer_tr'] as String? ?? '').trim();
    if (text0.isEmpty) throw const ExplainMoreException('Cevap gelmedi. Biraz sonra tekrar dene.');
    return ExplainAnswer(text0, remaining: (m['remaining'] as num?)?.toInt());
  }

  static String messageForCode(String code, {String? reason}) => switch (code) {
    'resource-exhausted' => 'Bugünkü ek açıklama hakkın doldu. Yarın yine sorabilirsin.',
    'permission-denied' => 'Ek açıklama Premium üyelere açık.',
    'unauthenticated' => 'Sormak için önce giriş yapmalısın.',
    'invalid-argument' => 'Bu soru için ek açıklama istenemedi.',
    _ => CallableConversationService.messageForCode(code, reason: reason),
  };
}

/// Null when Firebase is off or nobody is signed in.
final explainMoreServiceProvider = Provider<ExplainMoreService?>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return null;
  return CallableExplainMoreService.firebase(functions);
});

/// The question sent for [text] with an optional reading [passage]: the
/// passage is shortened so the request stays small.
String explainQuestionText(String text, {String? passage}) {
  final p = passage?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (p.isEmpty) return text;
  return '${p.length > 600 ? '${p.substring(0, 600)}…' : p}\n\n$text';
}
