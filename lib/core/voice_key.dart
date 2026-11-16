// Shared by the app and `tool/voice_elevenlabs.dart`: which recorded file
// belongs to a sentence, and which voice reads it. Pure Dart (no Flutter).

/// Recorded voices (ElevenLabs premade voices, American English).
enum Voice {
  /// Female, clear and educational: the default voice.
  matilda('XrExE9yKIg1WjnnlVkGX'),

  /// Male, smooth: male story characters and now and then a sentence.
  eric('cjVigY5qzO86Huf0OWal');

  const Voice(this.elevenLabsId);
  final String elevenLabsId;
}

/// The text as it is matched: trimmed, single spaces.
String normalizeSpoken(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// File name (without extension) of the recording of [text]: two 32-bit
/// FNV-1a hashes (different seeds) of the normalized text, 16 hex digits.
/// 32-bit halves keep every step positive and exact.
String voiceKey(String text) {
  final units = normalizeSpoken(text).codeUnits;
  String fnv(int seed) {
    var h = seed;
    for (final u in units) {
      h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return fnv(0x811c9dc5) + fnv(0x050c5d1f);
}

/// Voice of a lesson sentence: Matilda, and Eric for about one in four
/// sentences of three words or more (single words stay in one voice).
Voice voiceForSentence(String text) {
  final t = normalizeSpoken(text);
  if (t.split(' ').length < 3) return Voice.matilda;
  return int.parse(voiceKey(t).substring(14), radix: 16) % 4 == 3 ? Voice.eric : Voice.matilda;
}

/// Voice of a story speaker from their avatar emoji: men are Eric, women
/// Matilda; anyone else takes the voice not used by the other speaker.
Voice? voiceForAvatar(String? avatar) {
  const male = ['👨', '👦', '👴', '🧔', '👲', '🤵', '👮‍♂️', '👨‍'];
  const female = ['👩', '👧', '👵', '🧕', '👱‍♀️', '👸', '🤰', '👩‍'];
  if (avatar == null) return null;
  if (female.any(avatar.startsWith)) return Voice.matilda;
  if (male.any(avatar.startsWith)) return Voice.eric;
  return null;
}
