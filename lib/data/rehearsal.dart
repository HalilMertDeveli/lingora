import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase/firebase_providers.dart' show AppUser, authStateProvider;
import 'progress.dart';

/// Mülakat Provası: the learner answers interview questions in their own
/// words (voice or typing), the server (functions/src/rehearsal.ts) says
/// where they got stuck, the next day's study is built from that answer, a
/// new interview asks new questions, and the first and latest recordings
/// can be compared. Audio files stay on the phone; only transcripts and
/// analyses go to the server.
///
/// No made-up scores: everything shown is a count the learner can check in
/// their own answers (errors per tag, gaps, words, tasks done unaided).

// ------------------------------------------------------------- question bank

enum QuestionCategory {
  behavioural('Davranışsal'),
  technical('Teknik'),
  motivation('Motivasyon');

  const QuestionCategory(this.label);
  final String label;
}

class InterviewQuestion {
  const InterviewQuestion(this.id, this.category, this.text, this.hintTr);
  final String id;
  final QuestionCategory category;
  final String text;

  /// What a good answer covers, in Turkish (shown only when asked: using it
  /// makes the answer "with help").
  final String hintTr;
}

/// The first rehearsal: introduce yourself, then one of your projects.
const firstRehearsalQuestions = [
  InterviewQuestion(
    'intro',
    QuestionCategory.motivation,
    'Tell me a little about yourself.',
    'Adın, şu anki rolün, kaç yıldır bu işi yaptığın ve en çok neyle ilgilendiğin.',
  ),
  InterviewQuestion(
    'project',
    QuestionCategory.technical,
    'Tell me about one of your projects.',
    'Proje ne işe yarıyordu, sen tam olarak ne yaptın, hangi teknolojiler, sonuç ne oldu.',
  ),
];

/// Follow-up interview questions (original wording, written for this app).
/// Never repeated for a learner: see [pickNewQuestions].
const interviewQuestionBank = <InterviewQuestion>[
  // Behavioural
  InterviewQuestion(
    'b_conflict',
    QuestionCategory.behavioural,
    'Describe a time you disagreed with a teammate. What did you do?',
    'Durum, senin bakış açın, nasıl konuştunuz, nasıl bitti.',
  ),
  InterviewQuestion(
    'b_deadline',
    QuestionCategory.behavioural,
    'Tell me about a deadline you almost missed.',
    'Neden sıkıştı, ne yaptın, sonuç, bir dahakine ne değiştirirsin.',
  ),
  InterviewQuestion(
    'b_mistake',
    QuestionCategory.behavioural,
    'What is a mistake you made at work, and what did you learn from it?',
    'Hatayı açıkça söyle, nasıl düzelttin, ne öğrendin.',
  ),
  InterviewQuestion(
    'b_feedback',
    QuestionCategory.behavioural,
    'Tell me about a time you received difficult feedback.',
    'Geri bildirim neydi, ilk tepkin, sonra neyi değiştirdin.',
  ),
  InterviewQuestion(
    'b_lead',
    QuestionCategory.behavioural,
    'Describe a situation where you took the lead without being asked.',
    'Neden sen üstlendin, ne yaptın, ekibe etkisi.',
  ),
  InterviewQuestion(
    'b_unclear',
    QuestionCategory.behavioural,
    'How did you handle a task with unclear requirements?',
    'Belirsizlik neydi, kime ne sordun, nasıl karar verdin.',
  ),
  InterviewQuestion(
    'b_help',
    QuestionCategory.behavioural,
    'Tell me about a time you helped a colleague solve a problem.',
    'Sorun, senin katkın, sonuç.',
  ),
  InterviewQuestion(
    'b_priorities',
    QuestionCategory.behavioural,
    'How do you decide what to work on when everything is urgent?',
    'Öncelik ölçütün, kiminle konuşursun, bir örnek.',
  ),
  InterviewQuestion(
    'b_change',
    QuestionCategory.behavioural,
    'Describe a big change at work and how you adapted to it.',
    'Değişiklik neydi, zorluk, nasıl uyum sağladın.',
  ),
  InterviewQuestion(
    'b_proud',
    QuestionCategory.behavioural,
    'What achievement from your last role are you most proud of?',
    'Başarı, senin payın, ölçülebilir sonuç.',
  ),
  InterviewQuestion(
    'b_fail',
    QuestionCategory.behavioural,
    'Tell me about a project that did not go as planned.',
    'Ne ters gitti, senin rolün, ne öğrendiniz.',
  ),
  InterviewQuestion(
    'b_customer',
    QuestionCategory.behavioural,
    'Describe a time you had to explain something technical to a non-technical person.',
    'Kime, neyi, nasıl basitleştirdin, anlaşıldı mı.',
  ),
  // Technical
  InterviewQuestion(
    't_bug',
    QuestionCategory.technical,
    'Walk me through the hardest bug you have fixed.',
    'Belirti, nasıl aradın, asıl neden, çözüm.',
  ),
  InterviewQuestion(
    't_design',
    QuestionCategory.technical,
    'How would you design a simple system to send notifications to users?',
    'Bileşenler, veri akışı, hata ve yük durumları.',
  ),
  InterviewQuestion(
    't_review',
    QuestionCategory.technical,
    'What do you look for when you review someone else\'s code?',
    'Doğruluk, okunabilirlik, test, nasıl yorum yazarsın.',
  ),
  InterviewQuestion(
    't_testing',
    QuestionCategory.technical,
    'How do you test your work before you release it?',
    'Test türleri, otomasyon, bir örnek.',
  ),
  InterviewQuestion(
    't_performance',
    QuestionCategory.technical,
    'Tell me about a time you made something faster.',
    'Ne yavaştı, nasıl ölçtün, ne değiştirdin, ne kadar hızlandı.',
  ),
  InterviewQuestion(
    't_tradeoff',
    QuestionCategory.technical,
    'Describe a technical decision where you had to choose between two options.',
    'Seçenekler, artıları/eksileri, neden birini seçtin.',
  ),
  InterviewQuestion(
    't_tool',
    QuestionCategory.technical,
    'Which tool or technology do you know best, and why do you like it?',
    'Araç, ne için kullandın, güçlü ve zayıf yanı.',
  ),
  InterviewQuestion(
    't_learn',
    QuestionCategory.technical,
    'How do you learn a new technology quickly?',
    'Yöntemin, kaynaklar, son öğrendiğin şey.',
  ),
  InterviewQuestion(
    't_legacy',
    QuestionCategory.technical,
    'Have you worked with old code that nobody understood? What did you do?',
    'Durum, nasıl anladın, neyi iyileştirdin.',
  ),
  InterviewQuestion(
    't_incident',
    QuestionCategory.technical,
    'Tell me about a production problem and how your team handled it.',
    'Ne oldu, senin görevin, nasıl çözüldü, sonra ne değişti.',
  ),
  InterviewQuestion(
    't_data',
    QuestionCategory.technical,
    'How do you keep user data safe in the products you build?',
    'Somut önlemler, bir örnek.',
  ),
  InterviewQuestion(
    't_explain',
    QuestionCategory.technical,
    'Explain the architecture of a project you worked on.',
    'Ana parçalar, nasıl konuşuyorlar, senin sorumlu olduğun kısım.',
  ),
  // Motivation
  InterviewQuestion(
    'm_why_role',
    QuestionCategory.motivation,
    'Why are you interested in this role?',
    'Rolde seni çeken iki şey ve geçmişinle bağlantısı.',
  ),
  InterviewQuestion(
    'm_why_leave',
    QuestionCategory.motivation,
    'Why do you want to leave your current job?',
    'Olumlu ifade et: ne arıyorsun, neden şimdi.',
  ),
  InterviewQuestion(
    'm_five_years',
    QuestionCategory.motivation,
    'Where do you see yourself in a few years?',
    'Gerçekçi bir hedef ve bu rolün ona katkısı.',
  ),
  InterviewQuestion(
    'm_strength',
    QuestionCategory.motivation,
    'What is your greatest strength? Give an example.',
    'Bir güçlü yan ve onu gösteren kısa bir örnek.',
  ),
  InterviewQuestion(
    'm_weakness',
    QuestionCategory.motivation,
    'What is something you are working to improve?',
    'Gerçek bir gelişim alanı ve onun için ne yaptığın.',
  ),
  InterviewQuestion(
    'm_team',
    QuestionCategory.motivation,
    'What kind of team do you work best in?',
    'Ekip tarzı, neden, bir örnek.',
  ),
  InterviewQuestion(
    'm_remote',
    QuestionCategory.motivation,
    'How do you stay productive when you work remotely?',
    'Alışkanlıkların, iletişim, bir örnek.',
  ),
  InterviewQuestion(
    'm_company',
    QuestionCategory.motivation,
    'What do you know about the kind of company you want to join?',
    'Şirket türü, ürün, neden ilgini çekiyor.',
  ),
  InterviewQuestion(
    'm_questions',
    QuestionCategory.motivation,
    'Do you have any questions for us?',
    'Rol, ekip ya da ürün hakkında iki düşünülmüş soru.',
  ),
  InterviewQuestion(
    'm_salary',
    QuestionCategory.motivation,
    'What matters most to you in your next job, apart from salary?',
    'İki öncelik ve nedenleri.',
  ),
];

/// Questions in a follow-up interview.
const followUpQuestionCount = 3;

/// [count] questions the learner has never been asked ([asked] holds
/// question ids), one per category in turn so an interview mixes
/// behavioural, technical and motivation questions. Never repeats a
/// question: when the bank runs out, fewer (or none) come back.
List<InterviewQuestion> pickNewQuestions(
  Set<String> asked, {
  int count = followUpQuestionCount,
  int seed = 0,
}) {
  final rng = Random(seed);
  final pools = {
    for (final c in QuestionCategory.values)
      c: [
        for (final q in interviewQuestionBank)
          if (q.category == c && !asked.contains(q.id)) q,
      ]..shuffle(rng),
  };
  final out = <InterviewQuestion>[];
  var c = seed % QuestionCategory.values.length;
  var empty = 0;
  while (out.length < count && empty < QuestionCategory.values.length) {
    final pool = pools[QuestionCategory.values[c]]!;
    if (pool.isEmpty) {
      empty++;
    } else {
      out.add(pool.removeLast());
      empty = 0;
    }
    c = (c + 1) % QuestionCategory.values.length;
  }
  return out;
}

InterviewQuestion? questionById(String id) {
  for (final q in [...firstRehearsalQuestions, ...interviewQuestionBank]) {
    if (q.id == id) return q;
  }
  return null;
}

// ------------------------------------------------- grammar tags and lessons

/// Turkish names of the server's grammar tags (functions/src/rehearsal.ts
/// GRAMMAR_TAGS).
const grammarTagNames = {
  'past_simple': 'Geçmiş zaman (Simple Past)',
  'present_perfect': 'Present Perfect',
  'present_simple': 'Geniş zaman',
  'present_continuous': 'Şimdiki zaman',
  'subject_verb_agreement': 'Özne-fiil uyumu (-s)',
  'to_be': 'To be (am/is/are)',
  'articles': 'A / an / the',
  'prepositions': 'Edatlar (in/on/at…)',
  'plurals': 'Tekil-çoğul',
  'pronouns': 'Zamirler',
  'word_order': 'Kelime sırası',
  'questions': 'Soru kurma',
  'modals': 'Modallar (can/should…)',
  'future': 'Gelecek zaman',
  'gerund_infinitive': '-ing mi to mu',
  'passive': 'Edilgen yapı',
  'comparatives': 'Karşılaştırma',
  'conditionals': 'Koşul cümleleri',
  'relative_clauses': 'Relative clauses',
  'connectors': 'Bağlaçlar',
  'word_choice': 'Kelime seçimi',
};

/// Existing grammar-path lessons (assets/notes/lessons.json ids, read-only)
/// for each grammar tag, most relevant first. `word_choice` has none.
const grammarTagLessons = <String, List<String>>{
  'past_simple': ['simple_past', 'to_be_past'],
  'present_perfect': ['present_perfect', 'perfect_vs_past'],
  'present_simple': ['simple_present', 'present_compare'],
  'present_continuous': ['present_continuous', 'present_compare'],
  'subject_verb_agreement': ['simple_present', 'have_do'],
  'to_be': ['to_be_present', 'to_be_past'],
  'articles': ['articles'],
  'prepositions': ['prepositions_place_time', 'dependent_prepositions'],
  'plurals': ['plurals_countables'],
  'pronouns': ['pronouns_possessives'],
  'word_order': ['sentence_parts'],
  'questions': ['questions', 'question_tags'],
  'modals': ['modals_overview', 'can_could', 'should'],
  'future': ['will', 'going_to'],
  'gerund_infinitive': ['gerund_infinitive', 'ing_or_to'],
  'passive': ['passive'],
  'comparatives': ['comparatives', 'superlatives'],
  'conditionals': ['conditionals'],
  'relative_clauses': ['relative_basic'],
  'connectors': ['conjunctions_contrast', 'connectives'],
  'word_choice': [],
};

/// The grammar-path lessons for [tags] (in order, no duplicates).
List<String> lessonsForTags(Iterable<String> tags) {
  final out = <String>[];
  for (final t in tags) {
    for (final id in grammarTagLessons[t] ?? const <String>[]) {
      if (!out.contains(id)) out.add(id);
    }
  }
  return out;
}

/// Turkish names of the content gap types.
const gapTypeNames = {
  'contribution': 'Senin katkın',
  'impact': 'Sonuç ve etki',
  'tech': 'Teknolojiler',
  'role': 'Rolün ve ekibin',
  'structure': 'Anlatım düzeni',
  'detail': 'Somut ayrıntı',
};

// ----------------------------------------------------------------- analysis

class ContentGap {
  const ContentGap({required this.type, required this.quote, required this.messageTr});
  final String type;
  final String quote;
  final String messageTr;

  Map<String, Object?> toJson() => {'type': type, 'quote': quote, 'message_tr': messageTr};
  factory ContentGap.fromJson(Map j) => ContentGap(
    type: '${j['type'] ?? ''}',
    quote: '${j['quote'] ?? ''}',
    messageTr: '${j['message_tr'] ?? ''}',
  );
}

class GrammarExample {
  const GrammarExample(this.quote, this.fix);
  final String quote;
  final String fix;
}

class GrammarError {
  const GrammarError({required this.tag, required this.explanationTr, required this.examples});
  final String tag;
  final String explanationTr;
  final List<GrammarExample> examples;

  Map<String, Object?> toJson() => {
    'tag': tag,
    'explanation_tr': explanationTr,
    'examples': [
      for (final e in examples) {'quote': e.quote, 'fix': e.fix},
    ],
  };
  factory GrammarError.fromJson(Map j) => GrammarError(
    tag: '${j['tag'] ?? ''}',
    explanationTr: '${j['explanation_tr'] ?? ''}',
    examples: [
      for (final e in (j['examples'] as List?) ?? const [])
        if (e is Map) GrammarExample('${e['quote'] ?? ''}', '${e['fix'] ?? ''}'),
    ],
  );
}

enum ExerciseKind { fixSentence, fillBlank, reorder }

class RehearsalExercise {
  const RehearsalExercise({
    required this.kind,
    required this.instructionTr,
    required this.prompt,
    required this.answer,
    required this.tag,
    this.words = const [],
  });
  final ExerciseKind kind;
  final String instructionTr;
  final String prompt;
  final String answer;
  final String tag;

  /// reorder: the answer's words, shuffled.
  final List<String> words;

  static const _kinds = {
    'fix_sentence': ExerciseKind.fixSentence,
    'fill_blank': ExerciseKind.fillBlank,
    'reorder': ExerciseKind.reorder,
  };

  Map<String, Object?> toJson() => {
    'kind': _kinds.entries.firstWhere((e) => e.value == kind).key,
    'instruction_tr': instructionTr,
    'prompt': prompt,
    'answer': answer,
    'tag': tag,
    if (words.isNotEmpty) 'words': words,
  };

  static RehearsalExercise? fromJson(Map j) {
    final kind = _kinds['${j['kind']}'];
    if (kind == null) return null;
    return RehearsalExercise(
      kind: kind,
      instructionTr: '${j['instruction_tr'] ?? ''}',
      prompt: '${j['prompt'] ?? ''}',
      answer: '${j['answer'] ?? ''}',
      tag: '${j['tag'] ?? ''}',
      words: [for (final w in (j['words'] as List?) ?? const []) '$w'],
    );
  }

  /// Whether [given] is right: case, punctuation and extra spaces ignored.
  bool accepts(String given) => normalizeAnswer(given) == normalizeAnswer(answer);
}

String normalizeAnswer(String s) => s
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class RehearsalAnalysis {
  const RehearsalAnalysis({
    required this.summaryTr,
    required this.gaps,
    required this.errors,
    required this.exercises,
    required this.retellPromptTr,
    required this.retellChecklistTr,
    this.repeatedTags = const [],
    this.repeatedGaps = const [],
    this.recurrenceNoteTr = '',
    this.wordCount = 0,
    this.freeLeft,
  });

  final String summaryTr;
  final List<ContentGap> gaps;
  final List<GrammarError> errors;
  final List<RehearsalExercise> exercises;
  final String retellPromptTr;
  final List<String> retellChecklistTr;

  /// Follow-ups: earlier tags and gaps that came back in this answer.
  final List<String> repeatedTags;
  final List<String> repeatedGaps;
  final String recurrenceNoteTr;
  final int wordCount;

  /// Free analyses left (null with Premium).
  final int? freeLeft;

  List<String> get tags => [for (final e in errors) e.tag];

  /// Error examples for [tag] (0 when the tag did not come up).
  int errorCount(String tag) {
    for (final e in errors) {
      if (e.tag == tag) return e.examples.length;
    }
    return 0;
  }

  Map<String, Object?> toJson() => {
    'summary_tr': summaryTr,
    'content_gaps': [for (final g in gaps) g.toJson()],
    'grammar_errors': [for (final e in errors) e.toJson()],
    'exercises': [for (final x in exercises) x.toJson()],
    'retell': {'prompt_tr': retellPromptTr, 'checklist_tr': retellChecklistTr},
    'recurrence': {'repeated_tags': repeatedTags, 'repeated_gaps': repeatedGaps, 'note_tr': recurrenceNoteTr},
    'word_count': wordCount,
  };

  factory RehearsalAnalysis.fromJson(Map j) {
    final retell = (j['retell'] as Map?) ?? const {};
    final rec = (j['recurrence'] as Map?) ?? const {};
    List<String> strings(Object? v) => [for (final s in (v as List?) ?? const []) '$s'];
    return RehearsalAnalysis(
      summaryTr: '${j['summary_tr'] ?? ''}',
      gaps: [
        for (final g in (j['content_gaps'] as List?) ?? const [])
          if (g is Map) ContentGap.fromJson(g),
      ],
      errors: [
        for (final e in (j['grammar_errors'] as List?) ?? const [])
          if (e is Map) GrammarError.fromJson(e),
      ],
      exercises: [
        for (final x in (j['exercises'] as List?) ?? const [])
          if (x is Map) ?RehearsalExercise.fromJson(x),
      ],
      retellPromptTr: '${retell['prompt_tr'] ?? ''}',
      retellChecklistTr: strings(retell['checklist_tr']),
      repeatedTags: strings(rec['repeated_tags']),
      repeatedGaps: strings(rec['repeated_gaps']),
      recurrenceNoteTr: '${rec['note_tr'] ?? ''}',
      wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
      freeLeft: (j['free_left'] as num?)?.toInt(),
    );
  }
}

// ------------------------------------------------------------------ history

enum RehearsalKind { first, interview, retell }

/// One spoken (or typed) answer.
class RehearsalAnswer {
  const RehearsalAnswer({
    required this.questionId,
    required this.question,
    required this.answer,
    this.audioPath,
    this.typed = false,
    this.retakes = 0,
    this.hintShown = false,
  });
  final String questionId;
  final String question;
  final String answer;

  /// Local recording (never uploaded); null when typed.
  final String? audioPath;
  final bool typed;

  /// Times the learner threw a recording away and started again.
  final int retakes;
  final bool hintShown;

  bool get unaided => retakes == 0 && !hintShown;

  Map<String, Object?> toJson() => {
    'q': questionId,
    'qt': question,
    'a': answer,
    'p': ?audioPath,
    if (typed) 't': true,
    if (retakes > 0) 'r': retakes,
    if (hintShown) 'h': true,
  };
  factory RehearsalAnswer.fromJson(Map j) => RehearsalAnswer(
    questionId: '${j['q'] ?? ''}',
    question: '${j['qt'] ?? ''}',
    answer: '${j['a'] ?? ''}',
    audioPath: j['p'] as String?,
    typed: j['t'] == true,
    retakes: (j['r'] as num?)?.toInt() ?? 0,
    hintShown: j['h'] == true,
  );
}

class RehearsalSession {
  const RehearsalSession({
    required this.id,
    required this.kind,
    required this.at,
    required this.answers,
    this.analysis,
  });
  final String id;
  final RehearsalKind kind;
  final DateTime at;
  final List<RehearsalAnswer> answers;
  final RehearsalAnalysis? analysis;

  int get wordCount => answers.fold(0, (n, a) => n + countWords(a.answer));
  String? get audioPath => answers.map((a) => a.audioPath).whereType<String>().firstOrNull;

  RehearsalSession withAnalysis(RehearsalAnalysis a) =>
      RehearsalSession(id: id, kind: kind, at: at, answers: answers, analysis: a);

  Map<String, Object?> toJson() => {
    'id': id,
    'k': kind.name,
    'at': at.toIso8601String(),
    'ans': [for (final a in answers) a.toJson()],
    'an': ?analysis?.toJson(),
  };
  static RehearsalSession? fromJson(Map j) {
    final kind = RehearsalKind.values.where((k) => k.name == j['k']).firstOrNull;
    final at = DateTime.tryParse('${j['at']}');
    if (kind == null || at == null) return null;
    return RehearsalSession(
      id: '${j['id']}',
      kind: kind,
      at: at,
      answers: [
        for (final a in (j['ans'] as List?) ?? const [])
          if (a is Map) RehearsalAnswer.fromJson(a),
      ],
      analysis: j['an'] is Map ? RehearsalAnalysis.fromJson(j['an'] as Map) : null,
    );
  }
}

int countWords(String text) => RegExp(r"[A-Za-z0-9'’-]+").allMatches(text).length;

/// One completed study task of a rehearsal day. [unaided]: done on the
/// first try, with no hint, no shown answer and no re-recording.
class RehearsalTask {
  const RehearsalTask({
    required this.id,
    required this.title,
    required this.day,
    this.hints = 0,
    this.retries = 0,
  });
  final String id;
  final String title;
  final String day;
  final int hints;
  final int retries;

  bool get unaided => hints == 0 && retries == 0;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'day': day, 'h': hints, 'r': retries};
  factory RehearsalTask.fromJson(Map j) => RehearsalTask(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    day: '${j['day'] ?? ''}',
    hints: (j['h'] as num?)?.toInt() ?? 0,
    retries: (j['r'] as num?)?.toInt() ?? 0,
  );
}

/// Counts help on one task while the learner works on it.
class TaskAttempt {
  int hints = 0;
  int retries = 0;
  void hint() => hints++;
  void wrong() => retries++;
}

/// Task id of exercise [index] of session [sessionId].
String exerciseTaskId(String sessionId, int index) => '$sessionId:ex$index';
String retellTaskId(String sessionId) => '$sessionId:retell';

class RehearsalState {
  const RehearsalState({this.sessions = const [], this.tasks = const []});
  final List<RehearsalSession> sessions;
  final List<RehearsalTask> tasks;

  RehearsalSession? get first => sessions.firstOrNull;
  RehearsalSession? get latest => sessions.lastOrNull;

  /// The newest analysed session: the day's study is built from it.
  RehearsalSession? get source {
    for (final s in sessions.reversed) {
      if (s.analysis != null) return s;
    }
    return null;
  }

  Set<String> get askedQuestions => {
    for (final s in sessions)
      for (final a in s.answers) a.questionId,
  };
  bool isDone(String taskId) => tasks.any((t) => t.id == taskId);
  List<RehearsalTask> get unaidedTasks => [
    for (final t in tasks)
      if (t.unaided) t,
  ];

  /// Every grammar tag and gap type the learner had so far (for the
  /// follow-up's recurrence check).
  List<String> get earlierTags => {for (final s in sessions) ...?s.analysis?.tags}.toList();
  List<String> get earlierGaps => {
    for (final s in sessions)
      for (final g in s.analysis?.gaps ?? const <ContentGap>[]) g.type,
  }.toList();
}

/// Facts for "ilk prova ↔ son prova": no scores, only counts.
class RehearsalComparison {
  RehearsalComparison(this.first, this.latest, this.tasks);
  final RehearsalSession first;
  final RehearsalSession latest;
  final List<RehearsalTask> tasks;

  /// Grammar tags of the first analysis with the error count then and now.
  List<({String tag, int before, int after})> get errorCounts => [
    for (final e in first.analysis?.errors ?? const <GrammarError>[])
      (tag: e.tag, before: e.examples.length, after: latest.analysis?.errorCount(e.tag) ?? 0),
  ];

  /// New tags in the latest analysis that the first did not have.
  List<String> get newTags => [
    for (final t in latest.analysis?.tags ?? const <String>[])
      if (!(first.analysis?.tags.contains(t) ?? false)) t,
  ];

  int get gapsBefore => first.analysis?.gaps.length ?? 0;
  int get gapsAfter => latest.analysis?.gaps.length ?? 0;
  List<RehearsalTask> get unaided => [
    for (final t in tasks)
      if (t.unaided) t,
  ];
}

/// Deletes the recordings at [paths] (missing files are fine).
typedef RecordingWiper = Future<void> Function(Iterable<String> paths);

Future<void> _deleteRecordings(Iterable<String> paths) async {
  if (kIsWeb) return;
  for (final p in paths) {
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('Recording not deleted: $e');
    }
  }
}

/// How rehearsal recordings are deleted (tests replace it).
final recordingWiperProvider = Provider<RecordingWiper>((ref) => _deleteRecordings);

/// The learner's rehearsals on this phone: answers, analyses and the paths
/// of their recordings. They belong to one account at a time
/// ([_ownerKey]): another account signing in on this phone (or signing out,
/// which makes a new guest) neither sees nor keeps them; they are deleted
/// together with the recordings. A guest's rehearsals move to the account
/// the guest signs in to, like the progress does. Rehearsals saved before
/// they had an owner belong to the first account seen.
class RehearsalStore extends Notifier<RehearsalState> {
  static const _key = 'rehearsal_v1';

  /// `{uid, guest}` of the account the stored rehearsals belong to.
  static const _ownerKey = 'rehearsal_owner_v1';

  @override
  RehearsalState build() {
    final user = ref.watch(authStateProvider.select((s) => s.value));
    final prefs = ref.read(prefsProvider);
    final stored = _read(prefs.getString(_key));
    final owner = _owner();
    if (user == null) {
      // Firebase off (no accounts on this phone) or between accounts: only
      // rehearsals no account owns are shown.
      return owner == null ? stored : const RehearsalState();
    }
    if (owner == null || owner.uid == user.uid || (owner.guest && !user.isAnonymous)) {
      _setOwner(user);
      return stored;
    }
    // Another account's (or an earlier guest's) rehearsals: gone from here.
    _wipe(stored);
    _setOwner(user);
    return const RehearsalState();
  }

  ({String uid, bool guest})? _owner() {
    final raw = ref.read(prefsProvider).getString(_ownerKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (uid: j['uid'] as String, guest: j['guest'] == true);
    } catch (_) {
      return null;
    }
  }

  void _setOwner(AppUser user) => ref
      .read(prefsProvider)
      .setString(_ownerKey, jsonEncode({'uid': user.uid, 'guest': user.isAnonymous}));

  void _wipe(RehearsalState s) {
    ref.read(prefsProvider).remove(_key);
    final paths = [
      for (final x in s.sessions)
        for (final a in x.answers) ?a.audioPath,
    ];
    if (paths.isNotEmpty) unawaited(ref.read(recordingWiperProvider)(paths));
  }

  /// Deletes every rehearsal and recording on this phone (account deletion).
  void clearLocal() {
    _wipe(state);
    state = const RehearsalState();
  }

  static RehearsalState _read(String? raw) {
    if (raw == null) return const RehearsalState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return RehearsalState(
        sessions: [
          for (final s in (j['s'] as List?) ?? const [])
            if (s is Map) ?RehearsalSession.fromJson(s),
        ],
        tasks: [
          for (final t in (j['t'] as List?) ?? const [])
            if (t is Map) RehearsalTask.fromJson(t),
        ],
      );
    } catch (_) {
      return const RehearsalState();
    }
  }

  void _save(RehearsalState s) {
    state = s;
    ref
        .read(prefsProvider)
        .setString(
          _key,
          jsonEncode({
            's': [for (final x in s.sessions) x.toJson()],
            't': [for (final t in s.tasks) t.toJson()],
          }),
        );
  }

  /// Adds or replaces [session] (same id).
  void putSession(RehearsalSession session) {
    final list = [
      for (final s in state.sessions)
        if (s.id != session.id) s,
      session,
    ]..sort((a, b) => a.at.compareTo(b.at));
    _save(RehearsalState(sessions: list, tasks: state.tasks));
  }

  /// Adds analysed rehearsals kept in the account (another phone, a
  /// reinstall) that this phone does not have. Local copies win: they hold
  /// the recordings. Returns how many were added.
  int mergeFromCloud(List<RehearsalSession> cloud) {
    final have = {for (final s in state.sessions) s.id};
    final add = [
      for (final s in cloud)
        if (!have.contains(s.id)) s,
    ];
    if (add.isEmpty) return 0;
    _save(
      RehearsalState(
        sessions: [...state.sessions, ...add]..sort((a, b) => a.at.compareTo(b.at)),
        tasks: state.tasks,
      ),
    );
    return add.length;
  }

  /// A rehearsal as the server keeps it in rehearsals/{uid}/items/{id}
  /// ({kind, items: [{question, answer}], analysis, createdAt}); null when
  /// it cannot be read. Recordings never leave the phone that made them.
  static RehearsalSession? fromCloud(String id, Map<String, Object?> d, {DateTime? createdAt}) {
    final kind = RehearsalKind.values.where((k) => k.name == d['kind']).firstOrNull;
    final analysis = d['analysis'];
    if (kind == null || analysis is! Map || createdAt == null) return null;
    final byText = {
      for (final q in [...firstRehearsalQuestions, ...interviewQuestionBank]) q.text: q.id,
    };
    return RehearsalSession(
      id: id,
      kind: kind,
      at: createdAt,
      answers: [
        for (final i in (d['items'] as List?) ?? const [])
          if (i is Map)
            RehearsalAnswer(
              questionId: byText['${i['question']}'] ?? '',
              question: '${i['question'] ?? ''}',
              answer: '${i['answer'] ?? ''}',
              typed: true,
            ),
      ],
      analysis: RehearsalAnalysis.fromJson(analysis),
    );
  }

  /// Records a finished task once; a later attempt does not overwrite it.
  void completeTask(String id, String title, TaskAttempt attempt) {
    if (state.isDone(id)) return;
    final day = dayKey(ref.read(clockProvider)());
    _save(
      RehearsalState(
        sessions: state.sessions,
        tasks: [
          ...state.tasks,
          RehearsalTask(id: id, title: title, day: day, hints: attempt.hints, retries: attempt.retries),
        ],
      ),
    );
  }
}

final rehearsalProvider = NotifierProvider<RehearsalStore, RehearsalState>(RehearsalStore.new);
