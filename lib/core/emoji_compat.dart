// Pure Dart (no Flutter): also used by models and tools.

/// Android 7–9 (API 24–28) lack the newer emoji (Emoji 4.0+ on 7.0, 5.0+ on
/// 7.1/8.x, 12.0+ on 9) and draw them as empty boxes. On those phones every
/// such emoji the app uses is swapped for one Android 7.0 already has
/// (Emoji 3.0 or older, or an Emoji 4.0 ZWJ sequence that 7.0 still draws
/// as two glyphs). Newer phones see the original emoji.
///
/// Content files stay untouched: [LegacyEmojiBundle] rewrites the JSON
/// assets as they are read, and the few Dart literals go through
/// [legacyEmoji]. `test/legacy_emoji_test.dart` fails when a new
/// unsupported emoji appears without a mapping (docs/play-store-hazirlik.md).
class LegacyEmoji {
  LegacyEmoji._();

  /// True on Android below API 29 (set once in `main()`, see legacy_emoji.dart).
  static bool enabled = false;
}

/// Unsupported emoji → an Android 7.0-safe stand-in. Keys are written
/// without U+FE0F; the matcher ignores it.
const legacyEmojiMap = <String, String>{
  // Emoji 4.0 (only the standalone medical symbol; 4.0 ZWJ sequences degrade
  // to two glyphs on 7.0 and are fine from 7.1).
  '\u2695': '💊',
  // Emoji 5.0
  '🧔🏻': '👨🏻', '🧔': '👨', '🧕': '👩', '🦔': '🐭', '🧣': '🎀', '🧢': '👒', '🧠': '💡',
  '🧑‍🤝‍🧑': '👫', '🧑‍🏫': '👩‍🏫', '🧑‍🍳': '👨‍🍳', '🧑‍🌾': '👨‍🌾', '🧑‍💼': '👨‍💼',
  '🧑‍✈': '👨‍✈️', '🧑‍⚕': '👩‍⚕️', '🧑‍🦱': '👦', '🧑‍💻': '👩‍💻', '🧑‍🎓': '👨‍🎓', '🧑': '👦',
  '🤩': '😍', '🥧': '🍰', '🤫': '🤐', '🧗': '⛰️', '🥪': '🍔', '🥩': '🍖', '🧒': '👦',
  '🧥': '👔', '🤲': '👐', '🥣': '🍲', '🥤': '🥛', '🤯': '😵', '🤟': '👌', '🥦': '🥕',
  '🦒': '📏', '🧓': '👴', '🧘': '😌', '🤨': '🤔', '🧦': '👟', '🧤': '✋', '🧐': '🔍',
  // Emoji 11.0
  '🦜': '🐦', '🧩': '📐', '🧿': '🔵', '🦚': '🦃', '🧭': '🗺️', '🧱': '🏗️', '🥾': '👢',
  '🧳': '💼', '🧺': '👕', '🧹': '✨', '🧪': '⚗️', '🧬': '🔬', '🦠': '🔬', '🧾': '📄',
  '🧮': '🔢', '👩🏻‍🦰': '👩🏻', '👨🏻‍🦰': '👨🏻', '👩‍🦰': '👩', '👩‍🦱': '👩', '👩‍🦳': '👵',
  '👨‍🦳': '👴', '🧼': '🛁', '🦷': '😬', '🦴': '🤕', '🧸': '🎁', '♟': '🎲', '🧽': '🚿',
  '🧂': '🍴', '🧴': '🍶', '🧶': '🏠', '🦹': '💰', '🥺': '😢', '♾': '🔁', '🧷': '📎',
  '🦶': '👣', '🧰': '🔧', '🧵': '🔗', '🛹': '🛴', '🧫': '🔬', '🥯': '🍩', '🥮': '🍰',
  '🦙': '🐑', '🥬': '🥗',
  // Emoji 12.0 / 12.1
  '🧍': '🚶', '🦪': '⚪', '🩺': '💉', '🧊': '❄️', '🦩': '🐦', '🤿': '🏊', '🦺': '🚣',
  '🥱': '😴', '🪐': '🌍', '🩹': '🚑', '🪑': '💺', '🤏': '👌', '🧈': '🧀', '🧃': '🍹',
  '🧅': '🌰', '🟫': '⬜', '🟢': '💚', '🟡': '💛', '🪁': '🎐', '🩰': '💃', '🩸': '💉',
  // Emoji 13.0+
  '🪙': '💰', '🪢': '➰', '🪴': '🌱', '🪣': '🗑️', '🪶': '🍃', '🪜': '📈', '🛗': '⬆️',
  '🪟': '🖼️', '🪞': '💄', '🫑': '🌶️', '🪧': '🚫', '🪥': '😁', '🫒': '🍇', '🥲': '😊',
  '🪲': '🐞', '🪆': '🎎', '🪨': '🗿', '🐻‍❄': '🐻', '🫖': '🍵', '🫓': '🍞', '🫁': '💨',
  '🫀': '❤️', '🫧': '🛁', '🫗': '🍶', '🫘': '🍲', '🪪': '📛', '🛝': '🎠', '🪫': '🔋',
  '🥹': '😊', '🫵': '👉', '🫙': '🏺', '🐦‍⬛': '🐦', '🛟': '🆘',
};

RegExp? _pattern;

RegExp get _matcher => _pattern ??= () {
  // Longest first, so "🧑‍🏫" wins over "🧑"; an optional U+FE0F after each
  // code point of the key.
  final keys = legacyEmojiMap.keys.toList()..sort((a, b) => b.length - a.length);
  String esc(String k) => k.runes.map((r) => '${RegExp.escape(String.fromCharCode(r))}\uFE0F?').join();
  // Never inside a ZWJ sequence that is kept (e.g. the ⚕ of 👩‍⚕️).
  return RegExp('(?<!\u200D)(?:${keys.map(esc).join('|')})', unicode: true);
}();

String _key(String match) => match.replaceAll('\uFE0F', '');

/// [text] with the unsupported emoji swapped, or [text] itself when
/// [LegacyEmoji.enabled] is off (pass [force] in tests and tools).
String legacyEmoji(String text, {bool? force}) {
  if (!(force ?? LegacyEmoji.enabled) || text.isEmpty) return text;
  return text.replaceAllMapped(_matcher, (m) => legacyEmojiMap[_key(m[0]!)] ?? m[0]!);
}
