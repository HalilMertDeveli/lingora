import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/scenarios.dart';
import '../services/conversation.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/growth/referral.dart' show installIdProvider;

/// One event of a streamed reply.
sealed class TalkEvent {
  const TalkEvent();
}

/// A finished sentence of the partner's reply, with its neural audio (MP3)
/// when the server made one.
class TalkSentenceEvent extends TalkEvent {
  const TalkSentenceEvent(this.index, this.text, this.audio);
  final int index;
  final String text;
  final Uint8List? audio;
}

/// The whole reply plus the silent feedback on the learner's turn.
class TalkDoneEvent extends TalkEvent {
  const TalkDoneEvent(this.turn, {this.neural = false, this.talkSecondsLeft, this.serverFirstAudioMs});
  final ChatTurn turn;

  /// The sentences came with the neural voice.
  final bool neural;

  /// Premium fair-use seconds left today.
  final int? talkSecondsLeft;

  /// Server time to the first audio (for the latency log).
  final int? serverFirstAudioMs;
}

/// What a voice turn is about and how the partner should talk.
class TalkRequest {
  const TalkRequest({
    required this.scenario,
    required this.history,
    this.level,
    this.goal = 'general',
    this.voice,
  });
  final Scenario scenario;
  final List<ChatMessage> history;

  /// The learner's CEFR level ("A2"), when known.
  final String? level;
  final String goal;

  /// A neural voice id (voice_catalog.dart); null = the partner's own.
  final String? voice;

  Map<String, Object?> toApi() {
    return {
      ...scenario.api,
      'level': ?level,
      'goal': goal,
      'voice': ?voice,
      'messages': apiMessages(history),
    };
  }
}

/// Codes of the Premium fair-use stop (functions/src/talk.ts).
const fairUseCode = 'fair_use';

/// Shown when today's fair-use talking time is used up. Typing in a voice
/// chat hits the same limit (functions/src/talk.ts), so it points elsewhere.
const fairUseMessage =
    'Bugün 30 dakika konuştun, harika iş! Sesin biraz dinlensin; yarın kaldığımız yerden devam edelim. '
    'Bu arada derslere, okumaya ve telaffuz koçuna devam edebilirsin.';

abstract class TalkService {
  /// True when replies come from the real AI.
  bool get isLive;

  /// Streams the partner's reply to the last learner message of [req].
  /// Errors are [ConversationException]s with Turkish messages.
  Stream<TalkEvent> talk(TalkRequest req);

  /// The neural voice for [text] (opening lines, replays); null = use the
  /// phone's voice (free users, offline, caps).
  Future<Uint8List?> speak(String text, {String? voice, double rate = 1});

  /// The call is starting: wake the server and open its connections early.
  Future<void> warm();
}

/// One message of a streaming callable: a chunk, or (last) its result.
typedef CallablePart = ({bool done, Object? data});

/// Calls a streaming callable: yields its chunks, then its result.
typedef CallableStreamer = Stream<CallablePart> Function(String name, Map<String, Object?> data);

/// The `talk` and `speak` Cloud Functions (functions/src/talk.ts, tts.ts).
class CallableTalkService implements TalkService {
  CallableTalkService(this._stream, this._invoke);

  /// [installId] goes with every turn: the server caps free AI use per
  /// install (functions/src/ai_guard.ts).
  CallableTalkService.firebase(FirebaseFunctions functions, {String? installId})
    : this(
        (name, data) => functions
            .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
            .stream<Object?, Object?>({...data, 'installId': ?installId})
            .map(
              (r) => switch (r) {
                Chunk(:final partialData) => (done: false, data: partialData),
                Result(:final result) => (done: true, data: result.data),
              },
            ),
        (name, data) async =>
            (await functions.httpsCallable(name).call<Object?>({...data, 'installId': ?installId})).data,
      );

  final CallableStreamer _stream;
  final CallableInvoker _invoke;

  @override
  bool get isLive => true;

  @override
  Stream<TalkEvent> talk(TalkRequest req) async* {
    var sent = 0;
    var finished = false;
    try {
      await for (final r in _stream('talk', req.toApi()).timeout(const Duration(seconds: 60))) {
        if (!r.done) {
          final s = _sentence(r.data);
          if (s != null) {
            sent++;
            yield s;
          }
        } else {
          finished = true;
          yield* _result(r.data, sentencesSent: sent);
        }
      }
      if (!finished) {
        // The Android plugin (cloud_functions 7.0.1, StreamResponseSubscriber)
        // ends the stream quietly on a server error instead of failing it:
        // the free-quota paywall and every error message were lost and the
        // chat waited forever (QA, emulator). Nothing was said yet, so ask
        // once more without streaming: its error (or reply) arrives intact.
        if (sent > 0) throw FirebaseFunctionsException(code: 'unavailable', message: 'stream_cut');
        yield* _result(
          await _invoke('talk', req.toApi()).timeout(const Duration(seconds: 60)),
          sentencesSent: 0,
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted' && e.message == ConversationException.freeQuotaCode) {
        throw const ConversationException(
          CallableConversationService.freeQuotaMessage,
          code: ConversationException.freeQuotaCode,
        );
      }
      if (e.code == 'resource-exhausted' && e.message == fairUseCode) {
        throw const ConversationException(fairUseMessage, code: fairUseCode);
      }
      throw ConversationException(CallableConversationService.messageForCode(e.code, reason: e.message));
    } on TimeoutException {
      throw ConversationException(CallableConversationService.messageForCode('deadline-exceeded'));
    } on ConversationException {
      rethrow;
    } on Exception {
      throw const ConversationException(CallableConversationService.offlineMessage);
    }
  }

  Stream<TalkEvent> _result(Object? data, {required int sentencesSent}) async* {
    final j = Map<String, Object?>.from(data as Map);
    // Clients that cannot stream get every sentence here.
    if (sentencesSent == 0) {
      for (final raw in (j['sentences'] as List? ?? const [])) {
        final s = _sentence(raw);
        if (s != null) yield s;
      }
    }
    final timing = j['timing'] is Map ? Map<String, Object?>.from(j['timing'] as Map) : const {};
    yield TalkDoneEvent(
      ChatTurn(
        reply: j['reply'] as String? ?? '',
        correction: _nonEmpty(j['correction']),
        tipTr: _nonEmpty(j['tip_tr']),
        done: j['done'] as bool? ?? false,
        remaining: (j['remaining'] as num?)?.toInt(),
        free: j['free'] as bool? ?? false,
      ),
      neural: j['voice'] == 'neural',
      talkSecondsLeft: (j['talkSecondsLeft'] as num?)?.toInt(),
      serverFirstAudioMs: (timing['firstAudioMs'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> warm() async {
    try {
      await _invoke('talk', {'warm': true}).timeout(const Duration(seconds: 10));
    } on Object {
      // Only an optimisation.
    }
  }

  static TalkSentenceEvent? _sentence(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final audio = raw['audio'];
    Uint8List? bytes;
    if (audio is String && audio.isNotEmpty) {
      try {
        bytes = base64Decode(audio);
      } on FormatException {
        bytes = null;
      }
    }
    return TalkSentenceEvent((raw['i'] as num?)?.toInt() ?? 0, text, bytes);
  }

  @override
  Future<Uint8List?> speak(String text, {String? voice, double rate = 1}) async {
    try {
      final raw = await _invoke('speak', {
        'text': text,
        'voice': ?voice,
        'rate': rate,
      }).timeout(const Duration(seconds: 8));
      final audio = (raw as Map?)?['audio'];
      return audio is String && audio.isNotEmpty ? base64Decode(audio) : null;
    } on Object {
      return null; // free user, offline or a cap: the phone's voice reads it
    }
  }

  static String? _nonEmpty(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;
}

/// Splits a reply into sentences the way the server does (roughly).
List<String> splitSentences(String text) => [
  for (final m in RegExp(r'[^.!?]+[.!?]*["\x27)]*').allMatches(text))
    if (m[0]!.trim().isNotEmpty) m[0]!.trim(),
];

/// Offline stand-in (demo, kid mode, tests): the scripted replies of
/// [DemoConversationService] in the phone's own voice.
class DemoTalkService implements TalkService {
  DemoTalkService([ConversationService? replies]) : _replies = replies ?? DemoConversationService();
  final ConversationService _replies;

  @override
  bool get isLive => false;

  @override
  Stream<TalkEvent> talk(TalkRequest req) async* {
    final turn = await _replies.send(req.scenario, req.history);
    var i = 0;
    for (final s in splitSentences(turn.reply)) {
      yield TalkSentenceEvent(i++, s, null);
    }
    yield TalkDoneEvent(turn);
  }

  @override
  Future<Uint8List?> speak(String text, {String? voice, double rate = 1}) async => null;

  @override
  Future<void> warm() async {}
}

/// The live `talk` function when Firebase is ready and someone is signed in,
/// otherwise the offline demo.
final talkServiceProvider = Provider<TalkService>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return DemoTalkService();
  return CallableTalkService.firebase(functions, installId: ref.read(installIdProvider));
});
