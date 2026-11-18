import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rehearsal.dart';
import 'conversation.dart' show CallableConversationService, CallableInvoker;
import 'firebase/firebase_providers.dart';

class RehearsalException implements Exception {
  const RehearsalException(this.message, {this.premiumRequired = false});
  final String message;

  /// The server said this analysis needs Premium (the free one is used).
  final bool premiumRequired;
  @override
  String toString() => message;
}

/// What the app sends for one analysis (see functions/src/rehearsal.ts).
class RehearsalRequest {
  const RehearsalRequest({
    required this.id,
    required this.kind,
    required this.answers,
    this.previousTags = const [],
    this.previousGaps = const [],
  });
  final String id;
  final RehearsalKind kind;
  final List<RehearsalAnswer> answers;
  final List<String> previousTags;
  final List<String> previousGaps;

  Map<String, Object?> toApi() => {
    'rehearsalId': id,
    'kind': kind.name,
    'items': [
      for (final a in answers) {'question': a.question, 'answer': a.answer},
    ],
    'previousTags': previousTags,
    'previousGaps': previousGaps,
  };
}

abstract class RehearsalService {
  /// True when the analysis comes from the real AI, false for the offline demo.
  bool get isLive;
  Future<RehearsalAnalysis> analyze(RehearsalRequest request);
}

/// Calls the `analyzeRehearsal` Cloud Function, which enforces the one free
/// analysis and keeps the API key on the server.
class CallableRehearsalService implements RehearsalService {
  CallableRehearsalService(this._invoke);

  CallableRehearsalService.firebase(FirebaseFunctions functions)
    : this((name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);

  final CallableInvoker _invoke;

  @override
  bool get isLive => true;

  @override
  Future<RehearsalAnalysis> analyze(RehearsalRequest request) async {
    final Object? raw;
    try {
      raw = await _invoke('analyzeRehearsal', request.toApi()).timeout(const Duration(seconds: 120));
    } on FirebaseFunctionsException catch (e) {
      throw RehearsalException(messageForCode(e.code), premiumRequired: e.code == 'permission-denied');
    } on Exception {
      throw const RehearsalException('Bağlantı kurulamadı. Cevabın kaydedildi, sonra tekrar dene.');
    }
    return RehearsalAnalysis.fromJson(Map<String, Object?>.from(raw as Map));
  }

  static String messageForCode(String code) => switch (code) {
    'permission-denied' => 'Ücretsiz ilk provanı kullandın. Yeni provalar Premium\'a açık.',
    'failed-precondition' => 'Cevabın çok kısa. Biraz daha anlat: en az birkaç cümle.',
    'resource-exhausted' => 'Bugünlük prova analizi hakkın doldu. Yarın tekrar dene.',
    _ => CallableConversationService.messageForCode(code),
  };
}

/// Offline stand-in (Firebase off or nobody signed in), labelled "Demo": a
/// few rules for common Turkish speakers' interview mistakes, so the whole
/// loop works without a server.
class DemoRehearsalService implements RehearsalService {
  DemoRehearsalService({this.delay = const Duration(milliseconds: 600)});
  final Duration delay;

  @override
  bool get isLive => false;

  static const _past = {
    'make': 'made',
    'use': 'used',
    'send': 'sent',
    'build': 'built',
    'develop': 'developed',
    'create': 'created',
    'work': 'worked',
    'write': 'wrote',
    'find': 'found',
    'fix': 'fixed',
    'design': 'designed',
    'lead': 'led',
    'start': 'started',
    'finish': 'finished',
    'have': 'had',
    'do': 'did',
    'go': 'went',
    'add': 'added',
    'test': 'tested',
    'decide': 'decided',
  };
  static final _pastCue = RegExp(r'\b(last|ago|was|were|yesterday|in 20\d\d)\b', caseSensitive: false);
  static final _subjectVerb = RegExp(r'\b(I|we|We|they|They)\s+([a-z]+)\b');
  static final _noArticle = RegExp(
    r'\b(am|is|was|a)\s+(very\s+)?(big|small|new|good|simple|mobile|web|backend|frontend|junior|senior)\s+(project|app|team|company|developer|engineer|system)\b',
    caseSensitive: false,
  );
  static final _since = RegExp(r'\bsince (\w+) (years|months)\b', caseSensitive: false);
  static final _tech = RegExp(
    r'\b(kotlin|java|flutter|dart|react|python|sql|swift|go|node|aws|firebase|docker|api|android|ios|typescript)\b',
    caseSensitive: false,
  );

  static List<String> _sentences(String text) => [
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+|\n')))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  @override
  Future<RehearsalAnalysis> analyze(RehearsalRequest request) async {
    await Future<void>.delayed(delay);
    final all = request.answers.map((a) => a.answer).join(' ');
    if (countWords(all) < 5) {
      throw const RehearsalException('Cevabın çok kısa. Biraz daha anlat: en az birkaç cümle.');
    }
    final sentences = [for (final a in request.answers) ..._sentences(a.answer)];

    final past = <GrammarExample>[];
    final articles = <GrammarExample>[];
    final preps = <GrammarExample>[];
    final fixed = <String, String>{}; // sentence -> corrected
    for (final s in sentences) {
      var out = s;
      final cue = _pastCue.hasMatch(all);
      for (final m in _subjectVerb.allMatches(s)) {
        final p = _past[m.group(2)];
        if (cue && p != null) {
          past.add(GrammarExample(m.group(0)!, '${m.group(1)} $p'));
          out = out.replaceFirst(m.group(0)!, '${m.group(1)} $p');
        }
      }
      for (final m in _noArticle.allMatches(s)) {
        if (m.group(1)!.toLowerCase() == 'a') continue;
        final fix = '${m.group(1)} a ${m.group(0)!.substring(m.group(1)!.length + 1)}';
        articles.add(GrammarExample(m.group(0)!, fix));
        out = out.replaceFirst(m.group(0)!, fix);
      }
      for (final m in _since.allMatches(s)) {
        final fix = 'for ${m.group(1)} ${m.group(2)}';
        preps.add(GrammarExample(m.group(0)!, fix));
        out = out.replaceFirst(m.group(0)!, fix);
      }
      if (out != s) fixed[s] = out;
    }

    final errors = [
      if (past.isNotEmpty)
        GrammarError(
          tag: 'past_simple',
          explanationTr: past.length > 1
              ? 'Geçmişte olanı geniş zamanla anlatıyorsun; aynı hatayı ${past.length} kez tekrarladın.'
              : 'Geçmişte olanı geniş zamanla anlattın.',
          examples: past.take(3).toList(),
        ),
      if (articles.isNotEmpty)
        GrammarError(
          tag: 'articles',
          explanationTr: 'Tekil sayılabilen isimden önce a/an gerekiyor.',
          examples: articles.take(3).toList(),
        ),
      if (preps.isNotEmpty)
        GrammarError(
          tag: 'prepositions',
          explanationTr: 'Süre için "since" değil "for" kullanılır.',
          examples: preps.take(3).toList(),
        ),
    ];

    final hasI = RegExp(r'\bI\s+(\w+ed|made|built|wrote|led|did|was responsible|designed)\b').hasMatch(all);
    final weSentence = sentences.firstWhere((s) => RegExp(r'^\s*We\b').hasMatch(s), orElse: () => '');
    final gaps = [
      if (!hasI)
        ContentGap(
          type: 'contribution',
          quote: weSentence,
          messageTr: 'Projenin ne yaptığını anlattın ama senin katkın anlaşılmadı. "I built…", "I was responsible for…" gibi kendi işini söyle.',
        ),
      if (!RegExp(r'\d|percent|%|users|customers|faster').hasMatch(all))
        const ContentGap(
          type: 'impact',
          quote: '',
          messageTr: 'Sonucu söylemedin: kaç kullanıcı, ne kadar hızlandı, ne değişti?',
        ),
      if (!_tech.hasMatch(all))
        const ContentGap(type: 'tech', quote: '', messageTr: 'Hangi teknolojileri kullandığını söylemedin.'),
    ];

    final exercises = <RehearsalExercise>[];
    for (final e in fixed.entries.take(2)) {
      exercises.add(
        RehearsalExercise(
          kind: ExerciseKind.fixSentence,
          instructionTr: 'Kendi cümlen: hatayı düzelt.',
          prompt: e.key,
          answer: e.value,
          tag: errors.isEmpty ? 'word_choice' : errors.first.tag,
        ),
      );
    }
    if (past.isNotEmpty) {
      final ex = past.first;
      final verb = ex.fix.split(' ').last;
      final src = fixed.values.firstWhere((s) => s.contains(ex.fix), orElse: () => ex.fix);
      exercises.add(
        RehearsalExercise(
          kind: ExerciseKind.fillBlank,
          instructionTr: 'Boşluğa fiilin geçmiş hâlini yaz.',
          prompt: src.replaceFirst(ex.fix, '${ex.fix.split(' ').first} ___'),
          answer: verb,
          tag: 'past_simple',
        ),
      );
    }
    final reorderSrc = [...fixed.values, ...sentences].firstWhere(
      (s) => countWords(s) >= 4 && countWords(s) <= 10,
      orElse: () => 'I built the payment screen myself.',
    );
    final words = reorderSrc.split(RegExp(r'\s+'));
    exercises.add(
      RehearsalExercise(
        kind: ExerciseKind.reorder,
        instructionTr: 'Kelimeleri sıraya koy.',
        prompt: '',
        answer: reorderSrc,
        tag: errors.isEmpty ? 'word_order' : errors.first.tag,
        words: [...words.reversed],
      ),
    );
    if (exercises.length < 3) {
      exercises.add(
        const RehearsalExercise(
          kind: ExerciseKind.fillBlank,
          instructionTr: 'Kendi katkını anlatan cümleyi tamamla.',
          prompt: 'I was ___ for the backend of the app.',
          answer: 'responsible',
          tag: 'word_choice',
        ),
      );
    }

    final tags = [for (final e in errors) e.tag];
    final gapTypes = [for (final g in gaps) g.type];
    final followUp = request.kind != RehearsalKind.first;
    final repeatedTags = followUp
        ? [
            for (final t in request.previousTags)
              if (tags.contains(t)) t,
          ]
        : <String>[];
    final repeatedGaps = followUp
        ? [
            for (final g in request.previousGaps)
              if (gapTypes.contains(g)) g,
          ]
        : <String>[];
    final gone = followUp
        ? [
            for (final t in request.previousTags)
              if (!tags.contains(t)) t,
          ]
        : <String>[];
    return RehearsalAnalysis(
      summaryTr: errors.isEmpty && gaps.isEmpty
          ? 'Açık ve anlaşılır bir cevap. Aynı düzeyi yeni sorularda da dene.'
          : 'Neler yaptığını anlattın; aşağıda takıldığın ${gaps.length + errors.length} noktayı kendi cümlelerinle gösteriyoruz.',
      gaps: gaps,
      errors: errors,
      exercises: exercises.take(5).toList(),
      retellPromptTr:
          'Aynı projeyi bir kez daha anlat; bu sefer kendi katkını ve sonucunu söyle, geçmiş zamanı kullan.',
      retellChecklistTr: const [
        'Projenin amacı (1 cümle)',
        'Senin yaptığın iş: "I…"',
        'Kullandığın teknolojiler',
        'Sonuç: bir sayı ya da değişiklik',
      ],
      repeatedTags: repeatedTags,
      repeatedGaps: repeatedGaps,
      recurrenceNoteTr: !followUp
          ? ''
          : repeatedTags.isEmpty && repeatedGaps.isEmpty
          ? 'Önceki hataların bu cevapta tekrar etmedi.'
          : 'Tekrar eden: ${[...repeatedTags.map((t) => grammarTagNames[t] ?? t), ...repeatedGaps.map((g) => gapTypeNames[g] ?? g)].join(', ')}.'
                '${gone.isEmpty ? '' : ' Artık görünmeyen: ${gone.map((t) => grammarTagNames[t] ?? t).join(', ')}.'}',
      wordCount: countWords(all),
    );
  }
}

/// The analysis service: the Cloud Function when signed in, else the demo.
final rehearsalServiceProvider = Provider<RehearsalService>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return DemoRehearsalService();
  return CallableRehearsalService.firebase(functions);
});
