import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/speech_evidence.dart';
import '../core/tr_errors.dart';
import '../data/scenarios.dart';
import 'firebase/firebase_providers.dart';
import 'growth/referral.dart' show installIdProvider;

class ChatMessage {
  const ChatMessage({
    required this.fromUser,
    required this.text,
    this.correction,
    this.tipTr,
    this.spoken = false,
    this.evidence = const [],
  });
  final bool fromUser;
  final String text;

  /// More natural version of a user message, when it had a mistake.
  final String? correction;

  /// Short Turkish explanation of the mistake.
  final String? tipTr;

  /// The learner said it (speech recognition) rather than typed it.
  final bool spoken;

  /// What the recognizer struggled with in this message (lib/core/speech_evidence.dart).
  final List<WeakWordEvidence> evidence;

  ChatMessage withFeedback({String? correction, String? tipTr}) => ChatMessage(
    fromUser: fromUser,
    text: text,
    correction: correction,
    tipTr: tipTr,
    spoken: spoken,
    evidence: evidence,
  );

  Map<String, String> toApi() => {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

/// The partner's answer plus feedback on the learner's last message.
class ChatTurn {
  const ChatTurn({
    required this.reply,
    this.correction,
    this.tipTr,
    this.done = false,
    this.remaining,
    this.free = false,
  });
  final String reply;
  final String? correction;
  final String? tipTr;

  /// The scenario goal has been reached.
  final bool done;

  /// Learner messages left today, when the server says.
  final int? remaining;

  /// The turn came out of the free daily taste (no Premium).
  final bool free;
}

class ConversationException implements Exception {
  const ConversationException(this.message, {this.code});
  final String message;

  /// [freeQuotaCode] when the free daily taste is used up.
  final String? code;

  static const freeQuotaCode = 'free_quota';
  bool get freeQuotaUsed => code == freeQuotaCode;
  @override
  String toString() => message;
}

abstract class ConversationService {
  /// True when answers come from the real AI, false for the offline demo.
  bool get isLive;

  /// [history] starts with the partner's opening line and ends with the
  /// learner's newest message.
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history);
}

/// Calls a callable Cloud Function with JSON-like data and returns its result.
typedef CallableInvoker = Future<Object?> Function(String name, Map<String, Object?> data);

/// Messages for the AI cost guard reasons (functions/src/ai_guard.ts); null
/// for any other reason.
String? aiGuardMessage(String? reason) => switch (reason) {
  'app_check_required' =>
    "Bu özellik yalnızca Google Play'den yüklenen güncel uygulamada çalışır. Uygulamayı güncelle.",
  'ai_budget' => "Yapay zekâ bugün çok yoğun. Yarın tekrar dene.",
  _ => null,
};

/// Calls an AI Cloud Function with this installation's random id added
/// ([installIdProvider]); the server caps free AI use per install, so new
/// guest accounts on one phone share it (functions/src/ai_guard.ts).
CallableInvoker aiInvoker(FirebaseFunctions functions, {String? installId}) =>
    (name, data) async =>
        (await functions.httpsCallable(name).call<Object?>({...data, 'installId': ?installId})).data;

/// Talks to the `converse` Cloud Function (functions/src/converse.ts), which
/// checks Premium and the daily quota and calls Claude. The Anthropic API key
/// stays on the server.
class CallableConversationService implements ConversationService {
  CallableConversationService(this._invoke);

  CallableConversationService.firebase(FirebaseFunctions functions, {String? installId})
    : this(aiInvoker(functions, installId: installId));

  final CallableInvoker _invoke;

  @override
  bool get isLive => true;

  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    // Only the most recent turns are sent; the server enforces limits too.
    final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
    final Object? raw;
    try {
      raw = await _invoke('converse', {
        'scenarioId': scenario.id,
        'messages': [for (final m in recent) m.toApi()],
      }).timeout(const Duration(seconds: 90));
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted' && e.message == ConversationException.freeQuotaCode) {
        throw const ConversationException(freeQuotaMessage, code: ConversationException.freeQuotaCode);
      }
      throw ConversationException(messageForCode(e.code, reason: e.message));
    } on Exception {
      throw const ConversationException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
    final j = Map<String, Object?>.from(raw as Map);
    return ChatTurn(
      reply: j['reply'] as String? ?? '',
      correction: _nonEmpty(j['correction']),
      tipTr: _nonEmpty(j['tip_tr']),
      done: j['done'] as bool? ?? false,
      remaining: (j['remaining'] as num?)?.toInt(),
      free: j['free'] as bool? ?? false,
    );
  }

  static const freeQuotaMessage = 'Bugünkü 3 ücretsiz mesajını kullandın.';

  /// Reasons the functions send with "unavailable" (functions/src/*.ts). Any
  /// other "unavailable" comes from the phone: no connection.
  static const serverBusyReasons = {'upstream_busy', 'upstream_error', 'empty_response', 'refused'};

  static const offlineMessage = 'Bağlantı kurulamadı. İnternetini kontrol et.';

  /// Turkish message for a callable error [code] and the server's [reason].
  static String messageForCode(String code, {String? reason}) => switch (code) {
    _ when aiGuardMessage(reason) != null => aiGuardMessage(reason)!,
    'resource-exhausted' => 'Bugünlük konuşma hakkın doldu. Yarın tekrar dene.',
    'permission-denied' => 'Yapay zekâ ile konuşma Premium üyelere açık.',
    'unauthenticated' => 'Konuşmak için önce giriş yapmalısın.',
    'unavailable' when reason != null && !serverBusyReasons.contains(reason) => offlineMessage,
    'unavailable' || 'deadline-exceeded' => 'Sunucu şu an yoğun. Biraz sonra tekrar dene.',
    _ => 'Sunucu hatası. Biraz sonra tekrar dene.',
  };

  static String? _nonEmpty(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;
}

/// Offline stand-in used when Firebase is off or nobody is signed in: a short scripted
/// conversation per scenario with rule-based corrections of common Turkish
/// learner mistakes. Labelled "Demo" in the UI.
class DemoConversationService implements ConversationService {
  @override
  bool get isLive => false;

  static const _scripts = {
    'cafe': [
      'Great choice! Would you like anything to eat with that?',
      'Sure. For here or to go?',
      'That\'s 7 euros, please. Enjoy your order!',
    ],
    'hotel_checkin': [
      'Here you are. Is breakfast included in my booking?',
      'Lovely. And what time is check-out?',
      'Thank you so much, you\'ve been very helpful!',
    ],
    'hotel_reception': [
      'Lovely. And how many nights will you be staying with us?',
      'Perfect. Your room is 214. Do you have any questions?',
      'Breakfast is from 7 to 10, and the Wi-Fi password is on your key card. Enjoy your stay!',
    ],
    'restaurant_guest': [
      'That sounds good. Does it contain nuts? My son is allergic.',
      'Perfect, we\'ll take two of those, please.',
      'Thank you! Could we have some water too?',
    ],
    'directions': [
      'Sorry, is it far? Can I walk there?',
      'Turn left at the bank, then straight on. Got it!',
      'Thank you very much, have a nice day!',
    ],
    'interview': [
      'Interesting. What was your biggest achievement in your last job?',
      'Why do you want to work for our company?',
      'Great. Do you have any questions for us?',
    ],
    'doctor': [
      'I see. How long have you had this problem?',
      'Do you have a fever as well?',
      'Take this medicine twice a day after meals. You should rest.',
    ],
    // Yazılımcı İngilizcesi (lib/data/dev_scenarios.dart)
    'dev_standup': [
      'Thanks. And what are you planning to work on today?',
      'Got it. Is anything blocking you?',
      "Okay, let's sync after the meeting. Thanks, everyone!",
    ],
    'dev_code_review': [
      'Good catch. Why do you think it matters here?',
      'Makes sense. What would you suggest instead?',
      "Great idea, I'll update the PR this afternoon. Thanks for the review!",
    ],
    'dev_bug_ticket': [
      'Thanks. What did you expect to happen?',
      'And what actually happened? Does it happen every time?',
      "Perfect, I can reproduce it now. I'll add it to this sprint.",
    ],
    'dev_commit': [
      'Okay. How would you write that as a short commit title?',
      'Nice and clear. Why was the change needed?',
      'Great, that will help whoever reads the log later. Thanks!',
    ],
    'dev_pr_description': [
      'Sounds good. Why did we need this change?',
      'Got it. How should I test it?',
      "Thanks, that's a clear description. I'll start the review now.",
    ],
    'dev_team_chat': [
      'Hmm, what have you already tried?',
      'Okay. Which user and environment are you using?',
      'Ah, you need the new orders:read permission. I just added it, try again!',
    ],
    'dev_interview_intro': [
      'Interesting. Which technologies do you mostly work with?',
      "Tell me about a project you're proud of.",
      'Great. Why are you interested in this role?',
    ],
    'dev_estimate': [
      'Okay. What are you assuming in that estimate?',
      'And what is the biggest risk?',
      "Thanks, that's very helpful for planning the release.",
    ],
  };

  /// Ordering a drink or snack: "I want coffee" is not wrong, just blunt.
  static final _politeOrder = RegExp(
    r'\bI want (?:a |an )?(coffee|tea|water|cake|sandwich)\b',
    caseSensitive: false,
  );
  static const _orderingScenarios = {'cafe', 'restaurant_guest'};

  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final userTurns = history.where((m) => m.fromUser).length;
    final script = _scripts[scenario.id] ?? const ['I see. Tell me more.'];
    final reply = script[(userTurns - 1).clamp(0, script.length - 1)];
    var fix = suggestCorrection(history.last.text);
    if (fix == null && _orderingScenarios.contains(scenario.id)) {
      final m = _politeOrder.firstMatch(history.last.text);
      if (m != null) {
        fix = (
          history.last.text.replaceRange(m.start, m.end, 'I would like a ${m[1]!.toLowerCase()}, please'),
          'Sipariş verirken "I would like ..., please" daha kibar duyulur.',
        );
      }
    }
    return ChatTurn(reply: reply, correction: fix?.$1, tipTr: fix?.$2, done: userTurns >= script.length);
  }

  /// Offline check for classic Turkish-speaker mistakes with the Türk hata
  /// dedektörü: the corrected text and the Turkish tips (one per line), or
  /// null when no rule matches.
  static (String, String)? suggestCorrection(String text) {
    final errors = detectTrErrors(text);
    if (errors.isEmpty) return null;
    return (errors.first.corrected, errors.map((e) => e.explanation).toSet().join('\n'));
  }
}

/// The live AI when Firebase is ready and someone is signed in, otherwise
/// the offline demo. (Premium itself is checked by the server; the
/// conversation screen gates it in the UI.)
final conversationServiceProvider = Provider<ConversationService>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return DemoConversationService();
  return CallableConversationService.firebase(functions, installId: ref.read(installIdProvider));
});

// ------------------------------------------------------------------ karne

/// One of the learner's sentences with a real mistake.
class ReportMistake {
  const ReportMistake({required this.original, required this.corrected, required this.explanationTr});
  final String original;
  final String corrected;
  final String explanationTr;
}

/// The end-of-conversation karne of the voice coach.
class ConversationReport {
  const ConversationReport({required this.mistakes, required this.summaryTr, required this.weakWords});
  final List<ReportMistake> mistakes;
  final String summaryTr;

  /// Words the phone's recognizer struggled with, weakest first. Comes only
  /// from on-device evidence ([speechEvidence]), never from the AI.
  final List<WeakWordEvidence> weakWords;

  static ConversationReport fromJson(Map<String, Object?> j) => ConversationReport(
    mistakes: [
      for (final m in (j['mistakes'] as List? ?? const []).cast<Map<Object?, Object?>>())
        ReportMistake(
          original: m['original'] as String? ?? '',
          corrected: m['corrected'] as String? ?? '',
          explanationTr: m['explanation_tr'] as String? ?? '',
        ),
    ],
    summaryTr: j['summary_tr'] as String? ?? '',
    weakWords: [
      for (final w in (j['weak_words'] as List? ?? const []).cast<Map<Object?, Object?>>())
        WeakWordEvidence.fromJson(Map<String, Object?>.from(w)),
    ],
  );
}

/// All the pronunciation evidence of a conversation: one entry per word (the
/// least confident; misheard before merely unsure), at most [max].
List<WeakWordEvidence> collectEvidence(List<ChatMessage> history, {int max = 8}) {
  double rank(WeakWordEvidence w) => (w.heard.isEmpty ? 1 : 0) + (w.confidence ?? 0.5);
  final byWord = <String, WeakWordEvidence>{};
  for (final m in history) {
    if (!m.fromUser) continue;
    for (final e in m.evidence) {
      final old = byWord[e.word];
      if (old == null || rank(e) < rank(old)) byWord[e.word] = e;
    }
  }
  return (byWord.values.toList()..sort((a, b) => rank(a).compareTo(rank(b)))).take(max).toList();
}

abstract class ConversationReportService {
  Future<ConversationReport> report(Scenario scenario, List<ChatMessage> history);
}

/// The `conversationReport` Cloud Function (functions/src/conversation_report.ts).
class CallableConversationReportService implements ConversationReportService {
  CallableConversationReportService(this._invoke);
  final CallableInvoker _invoke;

  @override
  Future<ConversationReport> report(Scenario scenario, List<ChatMessage> history) async {
    final recent = history.length > 40 ? history.sublist(history.length - 40) : history;
    final Object? raw;
    try {
      raw = await _invoke('conversationReport', {
        ...scenario.api,
        'messages': [for (final m in recent) m.toApi()],
        'pronunciation': [for (final e in collectEvidence(history, max: 30)) e.toJson()],
        // Recasts the voice partner made silently during the chat (talk).
        'corrections': [
          for (final m in recent)
            if (m.fromUser && m.correction != null)
              {'original': m.text, 'corrected': m.correction, 'tip_tr': m.tipTr ?? ''},
        ],
      }).timeout(const Duration(seconds: 90));
    } on FirebaseFunctionsException catch (e) {
      throw ConversationException(
        e.code == 'resource-exhausted' && aiGuardMessage(e.message) == null
            ? 'Bugünkü karne hakkın doldu. Yarın yeni bir sohbetle tekrar dene.'
            : CallableConversationService.messageForCode(e.code, reason: e.message),
      );
    } on Exception {
      throw const ConversationException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
    return ConversationReport.fromJson(Map<String, Object?>.from(raw as Map));
  }
}

/// Offline karne for the demo: the rule-based corrections already shown in
/// the chat plus the on-device pronunciation evidence.
class DemoConversationReportService implements ConversationReportService {
  @override
  Future<ConversationReport> report(Scenario scenario, List<ChatMessage> history) async {
    final mistakes = [
      for (final m in history)
        if (m.fromUser && m.correction != null)
          ReportMistake(original: m.text, corrected: m.correction!, explanationTr: m.tipTr ?? ''),
    ];
    return ConversationReport(
      mistakes: mistakes,
      summaryTr: mistakes.isEmpty
          ? 'Cümlelerinde belirgin bir hata görmedim. Bir sonraki sahnede daha uzun cevaplar dene.'
          : 'Sahneyi tamamladın. Aşağıdaki cümleleri bir kez de doğru hâliyle yüksek sesle söyle.',
      weakWords: collectEvidence(history),
    );
  }
}

/// Live karne when the chat is live, the offline one for the demo.
final conversationReportServiceProvider = Provider<ConversationReportService>((ref) {
  final functions = ref.watch(functionsProvider);
  if (!ref.watch(conversationServiceProvider).isLive || functions == null) {
    return DemoConversationReportService();
  }
  return CallableConversationReportService(aiInvoker(functions, installId: ref.read(installIdProvider)));
});
