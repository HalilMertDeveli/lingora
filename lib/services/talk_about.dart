import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Bunu konuşalım": hand-off from a text the learner just read (Günün
/// okuması, …) to the voice conversation.
///
/// Contract for the voice screen (feature/dogal-konusma): register a
/// launcher by overriding [talkAboutLauncherProvider], e.g. in main.dart
///
/// ```dart
/// talkAboutLauncherProvider.overrideWithValue((context, topic) =>
///     Navigator.of(context).push(MaterialPageRoute(builder: (_) => VoiceTalkScreen.free(topic: topic.topic, ...))));
/// ```
///
/// and send `{ mode: "free", topic: topic.topic }` to the server
/// (talk_context.ts `cleanTopic` keeps 60 characters, so [TalkTopic.topic]
/// is at most [TalkTopic.maxTopicChars]). [TalkTopic.context] carries the
/// whole text for a richer prompt if the server later accepts it.
/// While no launcher is registered the "Bunu konuşalım" button stays hidden.
class TalkTopic {
  const TalkTopic({
    required this.topic,
    this.context = '',
    this.opener = '',
    this.level,
    this.source = 'daily_reading',
  });

  static const maxTopicChars = 60;

  /// Short topic line, e.g. the reading's title (at most [maxTopicChars]).
  final String topic;

  /// The text the conversation is about (may be long).
  final String context;

  /// A first question the partner may open with.
  final String opener;

  /// CEFR band ("B1"), if known.
  final String? level;

  /// Where the hand-off came from (analytics), e.g. `daily_reading`.
  final String source;

  /// [raw] cut to [maxTopicChars] on a word boundary.
  static String clip(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.length <= maxTopicChars) return s;
    final cut = s.substring(0, maxTopicChars);
    final space = cut.lastIndexOf(' ');
    return (space > 20 ? cut.substring(0, space) : cut).trimRight();
  }
}

typedef TalkAboutLauncher = Future<void> Function(BuildContext context, TalkTopic topic);

/// The voice screen's entry point for a topic; null until the voice
/// conversation registers one.
final talkAboutLauncherProvider = Provider<TalkAboutLauncher?>((ref) => null);
