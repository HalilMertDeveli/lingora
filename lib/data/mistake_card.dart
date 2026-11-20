/// A review card made from a wrong answer ("Tekrar kartları" come from the
/// learner's own mistakes, not from every word of the course): the item the
/// mistake was about, its Turkish, why it was wrong and a right example.
class MistakeCardInfo {
  const MistakeCardInfo({
    required this.id,
    required this.en,
    required this.tr,
    required this.why,
    required this.day,
    this.example,
    this.kind,
    this.source,
    this.ai = false,
  });

  /// Review box key (a word keeps its word-card id, so earlier reviews of it
  /// carry over).
  final String id;
  final String en;
  final String tr;

  /// Short Turkish reason: rule-based, or the AI analysis with Premium.
  final String why;

  /// Day of the (last) mistake, `yyyy-MM-dd`.
  final String day;

  /// A right sentence using [en].
  final String? example;

  /// "Kelime", "Gramer kuralı"... (MistakeKind.label).
  final String? kind;

  /// The question it came from (`nodeId#index`).
  final String? source;

  /// [why] is the AI analysis.
  final bool ai;

  MistakeCardInfo copyWith({String? why, String? day, bool? ai, String? example}) => MistakeCardInfo(
    id: id,
    en: en,
    tr: tr,
    why: why ?? this.why,
    day: day ?? this.day,
    example: example ?? this.example,
    kind: kind,
    source: source,
    ai: ai ?? this.ai,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'en': en,
    'tr': tr,
    'why': why,
    'day': day,
    'example': ?example,
    'kind': ?kind,
    'source': ?source,
    if (ai) 'ai': true,
  };

  /// Null for a broken entry (it is dropped, never an error).
  static MistakeCardInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    String? s(String k) => j[k] is String && (j[k] as String).trim().isNotEmpty ? j[k] as String : null;
    final id = s('id'), en = s('en'), tr = s('tr');
    if (id == null || en == null || tr == null) return null;
    return MistakeCardInfo(
      id: id,
      en: en,
      tr: tr,
      why: s('why') ?? '',
      day: s('day') ?? '',
      example: s('example'),
      kind: s('kind'),
      source: s('source'),
      ai: j['ai'] == true,
    );
  }
}

/// At most this many mistake cards are kept (oldest go first).
const maxMistakeCards = 400;
