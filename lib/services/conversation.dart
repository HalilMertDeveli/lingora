import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/scenarios.dart';

/// Endpoint of the conversation proxy (see server/README.md). Pass at build
/// time: --dart-define=LINGORA_AI_URL=... --dart-define=LINGORA_AI_KEY=...
/// LINGORA_AI_KEY is the public (anon) key of the backend, never an
/// Anthropic API key: that one stays on the server.
const aiEndpoint = String.fromEnvironment('LINGORA_AI_URL');
const aiPublicKey = String.fromEnvironment('LINGORA_AI_KEY');

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text, this.correction, this.tipTr});
  final bool fromUser;
  final String text;

  /// More natural version of a user message, when it had a mistake.
  final String? correction;

  /// Short Turkish explanation of the mistake.
  final String? tipTr;

  Map<String, String> toApi() => {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

/// The partner's answer plus feedback on the learner's last message.
class ChatTurn {
  const ChatTurn({required this.reply, this.correction, this.tipTr, this.done = false});
  final String reply;
  final String? correction;
  final String? tipTr;

  /// The scenario goal has been reached.
  final bool done;
}

class ConversationException implements Exception {
  const ConversationException(this.message);
  final String message;
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

/// Talks to the server proxy, which calls Claude.
class RemoteConversationService implements ConversationService {
  RemoteConversationService(this.endpoint, this.publicKey);
  final String endpoint;
  final String publicKey;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  @override
  bool get isLive => true;

  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    try {
      final req = await _http.postUrl(Uri.parse(endpoint));
      req.headers
        ..contentType = ContentType.json
        ..set('Authorization', 'Bearer $publicKey')
        ..set('apikey', publicKey);
      // Only the most recent turns are sent; the server enforces limits too.
      final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
      req.add(
        utf8.encode(
          jsonEncode({
            'scenarioId': scenario.id,
            'messages': [for (final m in recent) m.toApi()],
          }),
        ),
      );
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429) {
        throw const ConversationException('Bugünlük konuşma hakkın doldu. Yarın tekrar dene.');
      }
      if (res.statusCode != 200) {
        throw ConversationException('Sunucu hatası (${res.statusCode}). Biraz sonra tekrar dene.');
      }
      final j = jsonDecode(body) as Map<String, dynamic>;
      return ChatTurn(
        reply: j['reply'] as String,
        correction: _nonEmpty(j['correction']),
        tipTr: _nonEmpty(j['tip_tr']),
        done: j['done'] as bool? ?? false,
      );
    } on ConversationException {
      rethrow;
    } on Exception {
      throw const ConversationException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
  }

  static String? _nonEmpty(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;
}

/// Offline stand-in used until the proxy is deployed: a short scripted
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
  };

  /// (pattern, natural version, Turkish tip) for classic Turkish-speaker errors.
  static final _rules = <(RegExp, String Function(Match), String)>[
    (
      RegExp(r'\bI am agree\b', caseSensitive: false),
      (_) => 'I agree',
      '"agree" zaten fiil; Türkçedeki "katılıyorum" gibi başına "am" gelmez.',
    ),
    (
      RegExp(r'\bI am (want|like|need|know|have)\b', caseSensitive: false),
      (m) => 'I ${m[1]}',
      'Geniş zamanda fiilden önce "am" kullanılmaz: "I ${'{verb}'}" yeterli.',
    ),
    (
      RegExp(r'\b(he|she|it) (want|like|need|go|have|work|live)\b', caseSensitive: false),
      (m) =>
          '${m[1]} ${m[2] == 'have'
              ? 'has'
              : m[2] == 'go'
              ? 'goes'
              : '${m[2]}s'}',
      'He/she/it ile geniş zamanda fiile -s eklenir.',
    ),
    (
      RegExp(r'\bI want (coffee|tea|water|cake|sandwich)\b', caseSensitive: false),
      (m) => 'I would like a ${m[1]}, please',
      'Sipariş verirken "I would like ..., please" daha kibar duyulur.',
    ),
    (
      RegExp(r'\bI have (\d+) years\b', caseSensitive: false),
      (m) => 'I am ${m[1]} years old',
      'Yaş söylerken İngilizcede "have" değil "be" kullanılır: "I am 25 years old".',
    ),
    (
      RegExp(r'\bI am working here since\b', caseSensitive: false),
      (_) => 'I have been working here since',
      '"since" ile geçmişten bugüne süren durumlar için present perfect kullanılır.',
    ),
  ];

  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final userTurns = history.where((m) => m.fromUser).length;
    final script = _scripts[scenario.id] ?? const ['I see. Tell me more.'];
    final reply = script[(userTurns - 1).clamp(0, script.length - 1)];
    final fix = suggestCorrection(history.last.text);
    return ChatTurn(reply: reply, correction: fix?.$1, tipTr: fix?.$2, done: userTurns >= script.length);
  }

  /// Offline check for classic Turkish-speaker mistakes: the corrected text
  /// and a Turkish tip, or null when no rule matches. Applies every rule.
  static (String, String)? suggestCorrection(String text) {
    var fixed = text;
    final tips = <String>[];
    for (final (pattern, fix, why) in _rules) {
      final m = pattern.firstMatch(fixed);
      if (m != null) {
        fixed = fixed.replaceRange(m.start, m.end, fix(m));
        tips.add(why.replaceAll('{verb}', m.groupCount >= 1 ? (m[1] ?? '') : ''));
      }
    }
    return tips.isEmpty ? null : (fixed, tips.join('\n'));
  }
}

final conversationServiceProvider = Provider<ConversationService>(
  (ref) =>
      aiEndpoint.isEmpty ? DemoConversationService() : RemoteConversationService(aiEndpoint, aiPublicKey),
);
