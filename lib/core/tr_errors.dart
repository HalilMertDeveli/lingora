/// Türk hata dedektörü: an offline rule engine that spots classic mistakes
/// Turkish speakers make in English and explains them in Turkish, naming the
/// Turkish habit behind each one.
///
/// Every rule carries an example and its fix; the tests check both, plus a
/// corpus of correct sentences that must stay silent.
library;

import 'text.dart';

/// Kinds of mistakes, used for explanations and the "Sık yaptığın hatalar"
/// statistics in the profile.
enum TrErrorCategory {
  article(
    'Artikel (a/an/the)',
    'Türkçede artikel yok; İngilizcede tekil, sayılabilen bir isim neredeyse hiç yalnız durmaz. '
        '"bir" diyorsan a/an, bilinen şeyden bahsediyorsan the kullan.',
  ),
  toBe(
    'to be (am/is/are)',
    'Türkçede "-im, -dir" ekleri fiilin içine gizlenir. İngilizcede sıfat, meslek ve yer '
        'söylerken am/is/are ayrı bir kelime olarak gelir; ama asıl fiil varken gelmez.',
  ),
  thirdPerson(
    '-s takısı (he/she/it)',
    'Türkçede "o gider, ben giderim" ekleri farklı; İngilizcede tek fark he/she/it ile '
        'geniş zamanda fiile eklenen -s. Cümlede he/she/it görünce fiile bak.',
  ),
  tense(
    'Zaman uyumu',
    'Türkçedeki "-yor" ve "-di" her zaman birebir karşılık bulmaz. Geçmiş zaman ifadesi '
        '(yesterday, ago) varsa geçmiş zaman, did varsa fiilin yalın hâli gelir.',
  ),
  sinceFor(
    'since / for',
    'Türkçede "5 yıldır burada yaşıyorum" şimdiki zamanla söylenir. İngilizcede bu '
        'present perfect ister: süre için for, başlangıç noktası için since.',
  ),
  modal(
    'Modal fiiller',
    'can, must, should, will gibi kelimelerden sonra fiil hep yalın gelir: '
        '"to" yok, "-s" yok, geçmiş hâl yok.',
  ),
  verbPattern(
    'Fiil kalıbı',
    'Türkçedeki "-mesini istiyorum" gibi yapılar İngilizcede kalıpla kurulur: '
        'want someone to do, let someone do.',
  ),
  preposition(
    'Edat (in/on/at/to…)',
    'Türkçede hâl ekleri (-e, -de, -den) edatların işini görür ve her zaman birebir '
        'eşleşmez. Edatları kalıp olarak ezberle: listen to, married to, good at.',
  ),
  plural(
    'Çoğul ve uyum',
    'Türkçede sayıdan sonra isim tekil kalır ("iki kitap"); İngilizcede çoğul olur '
        '(two books). people, children gibi kelimeler zaten çoğuldur.',
  ),
  uncountable(
    'Sayılamayan isim',
    'information, advice, homework, news İngilizcede sayılamaz: -s almaz, a/an almaz. '
        '"Bir tavsiye" için a piece of advice ya da some advice de.',
  ),
  wordOrder(
    'Kelime sırası',
    'Türkçede fiil sonda gelir, İngilizcede sıra özne + fiil + nesne. Sıfat ismin önünde, '
        '"very much" gibi zarflar cümlenin sonunda durur.',
  ),
  question(
    'Soru yapısı',
    'Türkçede soru "-mi" ekiyle ya da tonlamayla kurulur. İngilizcede soru kelimesinden '
        'sonra do/does/did gibi bir yardımcı fiil gerekir.',
  ),
  doubleNegative(
    'Çift olumsuz',
    'Türkçede "hiçbir şey bilmiyorum" iki olumsuzla kurulur. İngilizcede tek olumsuz yeter: '
        "I don't know anything ya da I know nothing.",
  ),
  comparative(
    'Karşılaştırma',
    'Türkçede "daha" her sıfatın önüne gelir. İngilizcede kısa sıfatlar -er alır '
        '(bigger), uzunlar more alır; ikisi birlikte kullanılmaz.',
  ),
  falseFriend(
    'Yanıltıcı kelime',
    'Türkçeye benzeyen kelimeler (sempatik, fabrika, kontrol) İngilizcede başka anlama '
        'gelebilir. Emin değilsen sözlükte örnek cümleye bak.',
  ),
  wordChoice(
    'Kelime seçimi',
    'Türkçede tek fiille söylenen şey (yapmak, açmak, çekmek, kazanmak) İngilizcede '
        'farklı fiillere bölünür: make/do, turn on, take a photo, earn money.',
  ),
  spelling(
    'Yazım',
    'Türkçeden farklı olarak İngilizcede dil, millet, gün ve ay adları ile "I" zamiri '
        'her zaman büyük harfle yazılır.',
  );

  const TrErrorCategory(this.label, this.tip);

  /// Short Turkish name shown on chips and in the profile.
  final String label;

  /// One-paragraph Turkish tip about the habit behind this category.
  final String tip;

  static TrErrorCategory? byName(String name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// One detected mistake.
class TrError {
  const TrError({
    required this.ruleId,
    required this.category,
    required this.wrong,
    required this.corrected,
    required this.explanation,
  });

  final String ruleId;
  final TrErrorCategory category;

  /// The wrong fragment as the user wrote it.
  final String wrong;

  /// The whole sentence, corrected.
  final String corrected;

  /// Short Turkish explanation naming the Turkish habit behind it.
  final String explanation;

  @override
  String toString() => 'TrError($ruleId: "$wrong" → "$corrected")';
}

/// A pattern for one classic mistake and how to fix and explain it.
class TrRule {
  TrRule(
    this.id,
    this.category,
    String pattern,
    this._fix,
    this._why, {
    required this.example,
    required this.fixed,
    bool caseSensitive = false,
  }) : pattern = RegExp(pattern, caseSensitive: caseSensitive, multiLine: true);

  final String id;
  final TrErrorCategory category;
  final RegExp pattern;
  final String Function(Match m) _fix;

  /// A String, or a `String Function(Match)` for explanations that quote the
  /// user's words.
  final Object _why;

  /// A wrong sentence this rule catches, and the same sentence after the fix.
  final String example;
  final String fixed;

  String explain(Match m) => _why is String ? _why : (_why as String Function(Match))(m);

  /// Replacement for the matched text, keeping a leading capital letter.
  String replacement(Match m) => _keepCase(m[0]!, _fix(m));

  /// [text] with this rule's first match fixed, or null when it does not match.
  String? apply(String text) {
    final m = pattern.firstMatch(text);
    if (m == null) return null;
    return text.replaceRange(m.start, m.end, replacement(m));
  }
}

String _keepCase(String original, String replacement) {
  if (original.isEmpty || replacement.isEmpty) return replacement;
  final first = original[0];
  final isUpper = first.toUpperCase() == first && first.toLowerCase() != first;
  return isUpper ? replacement[0].toUpperCase() + replacement.substring(1) : replacement;
}

// ---------------------------------------------------------------------------
// Small English helpers.

const _irregularThird = {'have': 'has', 'do': 'does', 'go': 'goes', 'be': 'is'};

/// "go" → "goes", "study" → "studies", "like" → "likes".
String thirdPerson(String verb) {
  final v = verb.toLowerCase();
  if (_irregularThird.containsKey(v)) return _irregularThird[v]!;
  if (RegExp(r'(s|sh|ch|x|z|o)$').hasMatch(v)) return '${v}es';
  if (RegExp(r'[^aeiou]y$').hasMatch(v)) return '${v.substring(0, v.length - 1)}ies';
  return '${v}s';
}

const _irregularPast = {
  'be': 'was',
  'go': 'went',
  'come': 'came',
  'see': 'saw',
  'eat': 'ate',
  'drink': 'drank',
  'take': 'took',
  'make': 'made',
  'do': 'did',
  'buy': 'bought',
  'write': 'wrote',
  'speak': 'spoke',
  'know': 'knew',
  'give': 'gave',
  'get': 'got',
  'have': 'had',
  'say': 'said',
  'tell': 'told',
  'find': 'found',
  'think': 'thought',
  'leave': 'left',
  'meet': 'met',
  'run': 'ran',
  'sit': 'sat',
  'sleep': 'slept',
  'swim': 'swam',
  'begin': 'began',
  'break': 'broke',
  'choose': 'chose',
  'forget': 'forgot',
  'read': 'read',
  'send': 'sent',
  'lose': 'lost',
  'hear': 'heard',
  'teach': 'taught',
  'feel': 'felt',
  'drive': 'drove',
  'sing': 'sang',
  'win': 'won',
  'lend': 'lent',
  'learn': 'learned',
};

const _irregularParticiple = {
  'be': 'been',
  'go': 'gone',
  'see': 'seen',
  'eat': 'eaten',
  'take': 'taken',
  'do': 'done',
  'write': 'written',
  'speak': 'spoken',
  'know': 'known',
  'give': 'given',
  'come': 'come',
  'drink': 'drunk',
  'swim': 'swum',
  'begin': 'begun',
  'break': 'broken',
  'choose': 'chosen',
  'forget': 'forgotten',
  'drive': 'driven',
  'sing': 'sung',
};

String _regularEd(String v) {
  if (v.endsWith('e')) return '${v}d';
  if (RegExp(r'[^aeiou]y$').hasMatch(v)) return '${v.substring(0, v.length - 1)}ied';
  if (RegExp(r'^(stop|plan|shop|drop|chat)$').hasMatch(v)) return '$v${v[v.length - 1]}ed';
  return '${v}ed';
}

String pastOf(String verb) => _irregularPast[verb.toLowerCase()] ?? _regularEd(verb.toLowerCase());

String participleOf(String verb) {
  final v = verb.toLowerCase();
  return _irregularParticiple[v] ?? _irregularPast[v] ?? _regularEd(v);
}

/// Base form of a past tense, participle or third-person verb.
String baseOf(String verb) {
  final v = verb.toLowerCase();
  for (final e in _irregularPast.entries) {
    if (e.value == v) return e.key;
  }
  for (final e in _irregularParticiple.entries) {
    if (e.value == v) return e.key;
  }
  for (final e in _irregularThird.entries) {
    if (e.value == v) return e.key;
  }
  const special = {
    'liked': 'like',
    'lived': 'live',
    'loved': 'love',
    'used': 'use',
    'arrived': 'arrive',
    'decided': 'decide',
    'moved': 'move',
    'closed': 'close',
    'hoped': 'hope',
    'stopped': 'stop',
    'planned': 'plan',
    'shopped': 'shop',
    'chatted': 'chat',
    'watches': 'watch',
    'washes': 'wash',
    'finishes': 'finish',
    'misses': 'miss',
    'teaches': 'teach',
    'catches': 'catch',
    'fixes': 'fix',
    'discusses': 'discuss',
    'learnt': 'learn',
  };
  if (special.containsKey(v)) return special[v]!;
  if (v.endsWith('ied')) return '${v.substring(0, v.length - 3)}y';
  if (v.endsWith('ies')) return '${v.substring(0, v.length - 3)}y';
  if (v.endsWith('ed')) return v.substring(0, v.length - 2);
  if (v.endsWith('s') && !v.endsWith('ss')) return v.substring(0, v.length - 1);
  return v;
}

String _articleFor(String word) {
  final w = word.toLowerCase();
  if (RegExp(r'^(hour|honest|hono(u)?r|heir)').hasMatch(w)) return 'an';
  if (RegExp(r'^(uni|use|usu|eu|one\b|once)').hasMatch(w)) return 'a';
  return RegExp('^[aeiou]').hasMatch(w) ? 'an' : 'a';
}

const _irregularPlural = {
  'child': 'children',
  'person': 'people',
  'man': 'men',
  'woman': 'women',
  'foot': 'feet',
  'tooth': 'teeth',
};

String pluralOf(String noun) {
  final n = noun.toLowerCase();
  if (_irregularPlural.containsKey(n)) return _irregularPlural[n]!;
  if (RegExp(r'(s|sh|ch|x|z)$').hasMatch(n)) return '${n}es';
  if (RegExp(r'[^aeiou]y$').hasMatch(n)) return '${n.substring(0, n.length - 1)}ies';
  return '${n}s';
}

String singularOf(String noun) {
  final n = noun.toLowerCase();
  for (final e in _irregularPlural.entries) {
    if (e.value == n) return e.key;
  }
  if (n == 'persons') return 'person';
  if (n.endsWith('ies')) return '${n.substring(0, n.length - 3)}y';
  if (RegExp(r'(ses|shes|ches|xes)$').hasMatch(n)) return n.substring(0, n.length - 2);
  return n.endsWith('s') ? n.substring(0, n.length - 1) : n;
}

const _comparatives = {
  'good': 'better',
  'bad': 'worse',
  'easy': 'easier',
  'big': 'bigger',
  'hot': 'hotter',
  'happy': 'happier',
  'busy': 'busier',
  'heavy': 'heavier',
  'pretty': 'prettier',
  'early': 'earlier',
  'nice': 'nicer',
  'large': 'larger',
  'late': 'later',
  'close': 'closer',
};

String comparativeOf(String adj) {
  final a = adj.toLowerCase();
  if (_comparatives.containsKey(a)) return _comparatives[a]!;
  if (a.length > 7) return 'more $a';
  return '${a}er';
}

String _be(String subject, {bool past = false}) {
  final s = subject.toLowerCase();
  if (s == 'i') return past ? 'was' : 'am';
  if (s == 'he' || s == 'she' || s == 'it') return past ? 'was' : 'is';
  return past ? 'were' : 'are';
}

String _haveFor(String subject) =>
    RegExp(r'^(he|she|it|my )', caseSensitive: false).hasMatch(subject) ? 'has' : 'have';

bool _isThirdSingular(String subject) => RegExp(
  r'^(he|she|it|my \w+|everybody|everyone|somebody|someone|nobody)$',
  caseSensitive: false,
).hasMatch(subject);

/// Replaces a verb with another verb in the same form (base, -s, past, -ing).
String _sameForm(String original, String base, {String? past}) {
  final o = original.toLowerCase();
  if (o.endsWith('ing')) {
    final stem = base.endsWith('e') && base != 'see' ? base.substring(0, base.length - 1) : base;
    return '${stem}ing';
  }
  if (o.endsWith('ed') || const {'said', 'did', 'won', 'made', 'took', 'told', 'lent'}.contains(o)) {
    return past ?? pastOf(base);
  }
  if (o.endsWith('s')) return thirdPerson(base);
  return base;
}

String _join(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).join(' ');

String _alts(Iterable<String> words) => words.join('|');

// Shared word lists.
const _verbs3 = [
  'go', 'do', 'have', 'want', 'like', 'need', 'live', 'work', 'play', 'watch', 'speak', 'know', 'love', //
  'eat', 'drink', 'write', 'study', 'come', 'make', 'take', 'get', 'say', 'think', 'try', 'wash', 'teach',
  'finish', 'miss', 'cook', 'drive', 'leave', 'sleep', 'walk', 'run', 'understand', 'believe', 'remember',
  'hate', 'prefer', 'visit', 'help', 'listen', 'look', 'feel', 'seem', 'mean', 'cry', 'fly', 'swim',
];
const _adjs = [
  'happy', 'tired', 'hungry', 'thirsty', 'ready', 'busy', 'sad', 'sick', 'ill', 'late', 'angry', 'afraid', //
  'sorry', 'fine', 'bored', 'married', 'single', 'sleepy', 'nervous', 'excited', 'worried', 'cold', 'hot',
];
const _numbers = r'two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|[2-9]|\d{2,}';
const _durations =
    '(?:\\d+|two|three|four|five|six|seven|eight|nine|ten|many|several|a few|a couple of)'
    '\\s+(?:years?|months?|weeks?|days?|hours?|minutes?)';
const _sentenceStart = r'(?:^|(?<=[.!?]\s{1,3}))';
const _objects = {'I': 'me', 'he': 'him', 'she': 'her', 'we': 'us', 'they': 'them', 'you': 'you'};
const _yesterdayVerbs = [
  'go', 'come', 'see', 'eat', 'buy', 'meet', 'watch', 'play', 'visit', 'have', 'do', 'make', 'take', //
  'get', 'drink', 'work', 'study', 'cook', 'call', 'sleep', 'swim', 'write', 'walk', 'finish', 'start',
];
final _yVerbAlts = _alts([
  for (final v in _yesterdayVerbs) ...[v, thirdPerson(v)],
]);
const _pastTime =
    r'yesterday|last\s+(?:night|week|year|month|weekend|summer|winter|monday|tuesday|wednesday|thursday|friday|saturday|sunday)';
const _noBreak = r"(?:(?!\b(?:but|and|so|because|while|although|now|today|tomorrow)\b)[^.!?,;])";

// ---------------------------------------------------------------------------
// The rules. Order matters: when two rules match the same words, the first
// one wins.

final List<TrRule> trRules = [
  // --- to be -----------------------------------------------------------------
  TrRule(
    'be_agree',
    TrErrorCategory.toBe,
    r"\b(I|you|we|they|he|she|people|everyone|everybody)(\s+am|\s+are|\s+is|'m|'re|'s|\s+was|\s+were)\s+agree\b",
    (m) {
      final s = m[1]!;
      final past = RegExp('was|were').hasMatch(m[2]!);
      return '$s ${past
          ? 'agreed'
          : _isThirdSingular(s)
          ? 'agrees'
          : 'agree'}';
    },
    '"agree" zaten bir fiil: "katılıyorum" demek. Türkçedeki "-im" ekini "am" ile karşılamaya '
        'gerek yok; "I agree" yeterli.',
    example: 'I am agree with you.',
    fixed: 'I agree with you.',
  ),
  TrRule(
    'be_plus_verb',
    TrErrorCategory.toBe,
    r"\b(I am|I'm|you are|you're|we are|we're|they are|they're)\s+(want|need|know|love|work|understand|go|come|have|see|play|eat|drink|speak|think|remember|believe|study|watch|read|write)\b",
    (m) => '${m[1]!.split(RegExp(r"[\s']")).first} ${m[2]}',
    (Match m) =>
        'Geniş zamanda asıl fiil varken am/is/are kullanılmaz. Türkçedeki "-im" ekini ayrı '
        'kelimeyle karşılama: "${m[1]!.split(RegExp(r"[\s']")).first} ${m[2]}" yeterli.',
    example: 'I am want a new phone.',
    fixed: 'I want a new phone.',
  ),
  TrRule(
    'he_is_plus_verb',
    TrErrorCategory.toBe,
    r"\b(he|she)(\s+is|'s)\s+(want|need|know|love|work|understand|go|have|play|eat|drink|speak|live)\b",
    (m) => '${m[1]} ${thirdPerson(m[3]!)}',
    'Asıl fiil varken "is" gelmez. He/she/it ile geniş zamanda fiile -s eklenir: "She works".',
    example: 'She is work in a bank.',
    fixed: 'She works in a bank.',
  ),
  TrRule(
    'missing_be_adj',
    TrErrorCategory.toBe,
    '(?<!\\b(?:am|is|are|was|were|be|been|do|does|did|make|makes|made|let|keep|keeps|feel|want|see|saw|found|and|or|when|if)\\s)'
        '\\b(I|you|we|they|he|she)\\s+(${_alts(_adjs)})\\b',
    (m) => '${m[1]} ${_be(m[1]!)} ${m[2]}',
    (Match m) =>
        'Türkçede "${m[2]}" durumu "-im/-dir" ekiyle söylenir ve ayrı fiil gerekmez. İngilizcede '
        'sıfattan önce am/is/are şart: "${m[1]} ${_be(m[1]!)} ${m[2]}".',
    example: 'I hungry now.',
    fixed: 'I am hungry now.',
  ),
  TrRule(
    'missing_be_ing',
    TrErrorCategory.toBe,
    '$_sentenceStart(I|You|We|They|He|She)\\s+'
        '(?!(?:bring|sing|ring|sting|swing|cling|fling|wring|spring|string|thing|king|wing)\\b)(\\w{2,}ing)\\b',
    (m) => '${m[1]} ${_be(m[1]!)} ${m[2]}',
    (Match m) =>
        'Türkçede "-yor" eki fiilin içinde. İngilizcede şimdiki zaman iki parçalı: '
        'am/is/are + fiil-ing ("${m[1]} ${_be(m[1]!)} ${m[2]}").',
    example: 'I going to work now.',
    fixed: 'I am going to work now.',
  ),
  TrRule(
    'it_depends',
    TrErrorCategory.toBe,
    r"\b(it's|it is|that's|that is)\s+depends?\b",
    (m) => '${m[1]!.toLowerCase().startsWith('it') ? 'it' : 'that'} depends',
    '"depend" bir fiil, önüne "is" gelmez. Türkçedeki "duruma bağlı" sıfat gibi düşünülse de '
        'İngilizcede "It depends" denir.',
    example: "It's depend on the weather.",
    fixed: 'It depends on the weather.',
  ),
  TrRule(
    'have_years',
    TrErrorCategory.toBe,
    '\\b(I|you|we|they|he|she)\\s+(have|has|had)\\s+(\\d+|$_numbers)\\s+years\\b'
        '(?!\\s+(?:of|left|to|ago|experience|in|at|old))',
    (m) => '${m[1]} ${_be(m[1]!, past: m[2]!.toLowerCase() == 'had')} ${m[3]} years old',
    'Türkçede "25 yaşım var" denir ama İngilizcede yaş "be" ile söylenir: "I am 25 years old".',
    example: 'I have 25 years.',
    fixed: 'I am 25 years old.',
  ),
  TrRule(
    'noun_adj_missing_be',
    TrErrorCategory.toBe,
    '$_sentenceStart(the|my|your|his|her|our|their|this|that)\\s+'
        '(car|house|book|dress|city|room|phone|film|movie|bag|food|weather|apartment|flat|garden|job|teacher|coffee|hotel)\\s+'
        '(red|blue|big|small|new|old|beautiful|nice|good|bad|expensive|cheap|long|short|black|white|clean|dirty|modern|lovely|interesting|boring|delicious|cold|hot)\\b'
        '(?=\\s*[.!?,]|\\s*\$|\\s+and\\b|\\s+but\\b)',
    (m) => '${m[1]} ${m[2]} is ${m[3]}',
    (Match m) =>
        'Türkçede "${m[2]} ${m[3]}" diye "-dir" eki düşürülebilir. İngilizcede durum anlatırken '
        '"is" gerekir: "${m[1]} ${m[2]} is ${m[3]}".',
    example: 'My house big.',
    fixed: 'My house is big.',
  ),

  // --- third person -s -------------------------------------------------------
  TrRule(
    'third_person_s',
    TrErrorCategory.thirdPerson,
    "(?<!\\b(?:do|does|did|can|could|will|would|should|must|may|might|shall|let|lets|make|makes|made|help|helps|"
        "helped|see|saw|watch|hear|heard|to|and|or|\\w+n't)\\s(?:not\\s)?)"
        '\\b(he|she|it|my (?:mother|father|mom|dad|brother|sister|friend|teacher|boss|wife|husband|son|daughter)|'
        'everybody|everyone|somebody|someone|nobody)\\s+(${_alts(_verbs3)})\\b',
    (m) => '${m[1]} ${thirdPerson(m[2]!)}',
    (Match m) =>
        'Türkçede "o gider, ben giderim" farkını ekler taşır. İngilizcede he/she/it ile geniş '
        'zamanda fiile -s eklenir: "${m[1]} ${thirdPerson(m[2]!)}".',
    example: 'He go to school every day.',
    fixed: 'He goes to school every day.',
  ),
  TrRule(
    'he_dont',
    TrErrorCategory.thirdPerson,
    r"\b(he|she|it)\s+do(n't|\s+not)\b",
    (m) => "${m[1]} does${m[2]!.startsWith("n") ? "n't" : ' not'}",
    "He/she/it ile olumsuzda don't değil doesn't kullanılır; -s işareti does'a geçer.",
    example: "She don't like coffee.",
    fixed: "She doesn't like coffee.",
  ),
  TrRule(
    'do_he',
    TrErrorCategory.thirdPerson,
    '${_sentenceStart}Do\\s+(he|she|it|your (?:mother|father|brother|sister|friend))\\b',
    (m) => 'Does ${m[1]}',
    'He/she/it ile kurulan sorular "Does" ile başlar. Türkçedeki "-mi" eki herkese aynıdır, '
        'İngilizcede yardımcı fiil özneye uyar.',
    example: 'Do he speak English?',
    fixed: 'Does he speak English?',
  ),
  TrRule(
    'does_plus_s',
    TrErrorCategory.thirdPerson,
    r"\b(does|doesn't|does not)\s+(?:(he|she|it)\s+)?(likes|wants|goes|has|knows|needs|works|lives|plays|speaks|loves|watches|comes|eats|drinks|studies|makes|takes)\b",
    (m) => _join([m[1], m[2], baseOf(m[3]!)]),
    (Match m) =>
        '-s işareti zaten "does" üzerinde. Fiil yalın kalır: "${baseOf(m[3]!)}". '
        'Türkçedeki gibi eki iki kez taşımaya gerek yok.',
    example: "He doesn't likes fish.",
    fixed: "He doesn't like fish.",
  ),

  // --- tense -----------------------------------------------------------------
  TrRule(
    'did_past',
    TrErrorCategory.tense,
    r"\b(didn't|did not|did)\s+(?:(I|you|he|she|it|we|they)\s+)?(went|came|saw|ate|drank|took|made|bought|wrote|spoke|knew|gave|got|had|said|told|found|thought|left|met|ran|slept|swam|forgot|watched|played|worked|liked|wanted|finished|visited|called|studied|lived|loved|stopped|tried|cooked|cleaned|opened|started|listened|enjoyed|waited|walked|talked|arrived|decided|needed|helped)\b",
    (m) => _join([m[1], m[2], baseOf(m[3]!)]),
    (Match m) =>
        'Geçmiş zaman işareti zaten "did" üzerinde; fiil yalın kalır: "${baseOf(m[3]!)}". '
        'Türkçedeki "-medi" gibi eki fiile de eklemek gerekmiyor.',
    example: "I didn't went to school yesterday.",
    fixed: "I didn't go to school yesterday.",
  ),
  TrRule(
    'perfect_ago',
    TrErrorCategory.tense,
    r"\b(I|you|we|they|he|she|it)(\s+have|\s+has|'ve|'s)\s+(seen|been|done|gone|eaten|written|taken|given|come|bought|met|made|had|visited|finished|started|called|watched|played|worked|lived|moved|arrived|lost|found|left|got|sent|told|heard)\b([^.!?]{0,30}?)\s+ago\b",
    (m) {
      final verb = m[3]!.toLowerCase() == 'been' ? _be(m[1]!, past: true) : pastOf(baseOf(m[3]!));
      return '${m[1]} $verb${m[4]} ago';
    },
    '"ago" geçmişte bitmiş bir anı gösterir, bu yüzden present perfect (have + V3) değil '
        'düz geçmiş zaman gelir. Türkçedeki "-dı" ile aynı.',
    example: 'I have seen him two days ago.',
    fixed: 'I saw him two days ago.',
  ),
  TrRule(
    'present_with_past_time',
    TrErrorCategory.tense,
    '(?<!\\b(?:did|didn\'t|to|will|can|could|should|would|must|might|do|does)\\s)'
        '\\b(I|we|they|you|he|she)\\s+($_yVerbAlts)\\b($_noBreak{0,30}?)\\s+($_pastTime|\\w+\\s+(?:days?|weeks?|years?)\\s+ago)\\b',
    (m) => '${m[1]} ${pastOf(baseOf(m[2]!))}${m[3]} ${m[4]}',
    (Match m) =>
        '"${m[4]}" geçmişi gösteriyor; fiil de geçmiş zamanda olmalı: "${pastOf(baseOf(m[2]!))}". '
        'Türkçedeki "-dı" ekini İngilizcede fiilin geçmiş hâli taşır.',
    example: 'I go to the cinema yesterday.',
    fixed: 'I went to the cinema yesterday.',
  ),
  TrRule(
    'past_time_then_present',
    TrErrorCategory.tense,
    '(?<!\\bsince\\s)\\b($_pastTime)\\s*(,?)\\s+(I|we|they|you|he|she)\\s+($_yVerbAlts)\\b',
    (m) => '${m[1]}${m[2]} ${m[3]} ${pastOf(baseOf(m[4]!))}',
    (Match m) => '"${m[1]}" geçmişi gösteriyor; fiil de geçmiş zamanda olmalı: "${pastOf(baseOf(m[4]!))}".',
    example: 'Last night we eat pizza.',
    fixed: 'Last night we ate pizza.',
  ),
  TrRule(
    'when_will',
    TrErrorCategory.tense,
    '$_sentenceStart(When|If|As soon as|After|Before)\\s+(I|you|he|she|it|we|they)\\s+will\\s+(\\w+)',
    (m) => '${m[1]} ${m[2]} ${_isThirdSingular(m[2]!) ? thirdPerson(m[3]!) : m[3]}',
    'Türkçede "geldiğimde" gelecek anlamı taşır, ama İngilizcede when/if yan cümlesinde '
        '"will" kullanılmaz: "When I come, I will call you."',
    example: 'When I will come home, I will call you.',
    fixed: 'When I come home, I will call you.',
  ),
  TrRule(
    'stative_ing',
    TrErrorCategory.tense,
    r"\b(I|you|we|they|he|she|it)(\s+am|\s+is|\s+are|'m|'re|'s)\s+(knowing|wanting|liking|understanding|believing|needing|owning|belonging|hating|preferring|meaning|seeming|agreeing|recognizing)\b",
    (m) {
      const base = {
        'knowing': 'know',
        'wanting': 'want',
        'liking': 'like',
        'understanding': 'understand',
        'believing': 'believe',
        'needing': 'need',
        'owning': 'own',
        'belonging': 'belong',
        'hating': 'hate',
        'preferring': 'prefer',
        'meaning': 'mean',
        'seeming': 'seem',
        'agreeing': 'agree',
        'recognizing': 'recognize',
      };
      final v = base[m[3]!.toLowerCase()]!;
      return '${m[1]} ${_isThirdSingular(m[1]!) ? thirdPerson(v) : v}';
    },
    (Match m) =>
        'Türkçede "biliyorum, anlıyorum" -yor ile söylenir. İngilizcede know, want, like, '
        'understand gibi durum fiilleri -ing almaz; geniş zaman kullanılır.',
    example: 'I am knowing the answer.',
    fixed: 'I know the answer.',
  ),

  // --- since / for -----------------------------------------------------------
  TrRule(
    'since_duration',
    TrErrorCategory.sinceFor,
    '\\bsince\\s+($_durations)\\b(?!\\s+ago)',
    (m) => 'for ${m[1]}',
    (Match m) =>
        'Türkçedeki "-dır/-dir" iki anlama da gelir. Süre (${m[1]}) için "for", başlangıç '
        'noktası (2019, Monday) için "since" kullanılır.',
    example: 'I have lived here since 5 years.',
    fixed: 'I have lived here for 5 years.',
  ),
  TrRule(
    'for_point_in_time',
    TrErrorCategory.sinceFor,
    r"\b(been|lived|worked|known|studied|waited|had)\b([^.!?]{0,25}?)\s+for\s+((?:19|20)\d\d|last\s+(?:year|month|week|summer|winter)|yesterday|(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|june|july|august|september|october|november|december))\b",
    (m) => '${m[1]}${m[2]} since ${m[3]}',
    (Match m) => '"${m[3]}" bir başlangıç noktası; süre değil. Başlangıç noktası için "since" kullanılır.',
    example: 'I have lived in Izmir for 2019.',
    fixed: 'I have lived in Izmir since 2019.',
  ),
  TrRule(
    'present_since',
    TrErrorCategory.sinceFor,
    '\\b(I|you|we|they|he|she)\\s+(live|lives|work|works|know|knows|study|studies|wait|waits|teach|teaches|play|plays|learn|learns)\\b'
        '((?:\\s+[\\w\']+){0,4}?)\\s+(since\\b(?!\\s+(?:I|you|he|she|we|they|it)\\b)|for\\s+(?:\\d+|$_numbers|many|several|a few|a long)\\s+(?:years?|months?|weeks?|days?|time)\\b(?!\\s+(?:a|per|every)\\b))',
    (m) => '${m[1]} ${_haveFor(m[1]!)} ${participleOf(baseOf(m[2]!))}${m[3]} ${m[4]}',
    'Türkçede "5 yıldır burada yaşıyorum" şimdiki zamanla söylenir. İngilizcede geçmişte '
        'başlayıp hâlâ süren durumlar present perfect ister: "I have lived here for 5 years".',
    example: 'I live here since 2015.',
    fixed: 'I have lived here since 2015.',
  ),
  TrRule(
    'be_since',
    TrErrorCategory.sinceFor,
    r"\b(I am|I'm|you are|you're|we are|we're|they are|they're|he is|he's|she is|she's)\s+(here|there|married|single|sick|ill|busy|at home|in\s+[A-Za-zÇĞİÖŞÜçğıöşü]+|a\s+\w+|\w+ing)\b((?:\s+[\w']+){0,3}?)\s+since\b(?!\s+(?:I|you|he|she|we|they|it)\b)",
    (m) {
      final s = m[1]!.split(RegExp(r"[\s']")).first;
      return '$s ${_haveFor(s)} been ${m[2]}${m[3]} since';
    },
    'Türkçede "2020\'den beri evliyim" şimdiki zamanla söylenir; İngilizcede "since" ile '
        'present perfect gelir: "I have been married since 2020".',
    example: 'I am married since 2020.',
    fixed: 'I have been married since 2020.',
  ),

  // --- modals ----------------------------------------------------------------
  TrRule(
    'modal_s',
    TrErrorCategory.modal,
    r"\b(can|can't|cannot|could|will|won't|would|should|must|might)\s+(?:(not|he|she|it)\s+)?(goes|likes|wants|has|plays|works|speaks|comes|does|knows|needs|makes|lives|drives|swims|cooks|sings)\b",
    (m) => _join([m[1], m[2], baseOf(m[3]!)]),
    (Match m) => '"${m[1]}" gibi modal fiillerden sonra fiil hep yalın gelir, -s almaz: "${baseOf(m[3]!)}".',
    example: 'She can speaks three languages.',
    fixed: 'She can speak three languages.',
  ),
  TrRule(
    'modal_past',
    TrErrorCategory.modal,
    r"\b(can|can't|could|couldn't|should|must|will|won't|would)\s+(not\s+)?(went|came|saw|ate|took|bought|wrote|spoke|gave|drank)\b",
    (m) => _join([m[1], m[2], baseOf(m[3]!)]),
    (Match m) => 'Modal fiilden sonra fiilin geçmiş hâli gelmez; yalın hâli gelir: "${baseOf(m[3]!)}".',
    example: "I couldn't came to the party.",
    fixed: "I couldn't come to the party.",
  ),
  TrRule(
    'modal_to',
    TrErrorCategory.modal,
    r"\b(can|can't|cannot|must|should|will|won't|might|could)\s+to\s+(\w+)",
    (m) => '${m[1]} ${m[2]}',
    'Türkçedeki "-meli, -ebilir" gibi düşününce araya "to" eklenebiliyor. Modal fiillerden '
        'sonra "to" gelmez: "I can swim".',
    example: 'I can to swim.',
    fixed: 'I can swim.',
  ),

  // --- verb patterns ---------------------------------------------------------
  TrRule(
    'let_to',
    TrErrorCategory.verbPattern,
    r"\b(let's|let\s+(?:me|him|her|us|them)|make\s+(?:me|him|her|us|them))\s+to\s+(\w+)",
    (m) => '${m[1]} ${m[2]}',
    '"let" ve "make" kalıbında fiil "to" almadan gelir: "Let\'s go", "Let me help".',
    example: "Let's to go to the park.",
    fixed: "Let's go to the park.",
  ),
  TrRule(
    'want_that',
    TrErrorCategory.verbPattern,
    r"\b(want|wants|wanted|would like)\s+that\s+(you|he|she|they|we|him|her|them|us)\s+(\w+)",
    (m) {
      final p = m[2]!.toLowerCase();
      return '${m[1]} ${_objects[p] ?? p} to ${baseOf(m[3]!)}';
    },
    'Türkçede "gelmeni istiyorum" yapısı İngilizcede "that" ile değil, '
        '"want + kişi + to + fiil" kalıbıyla kurulur: "I want you to come".',
    example: 'I want that you come with me.',
    fixed: 'I want you to come with me.',
  ),

  // --- prepositions ----------------------------------------------------------
  TrRule(
    'go_to_home',
    TrErrorCategory.preposition,
    r"\b(go|goes|going|went|gone|come|comes|coming|came|get|gets|getting|got|arrive|arrives|arrived|return|returns|returned|walk|walked|drive|drove)\s+to\s+(home|here|there|abroad|downtown|upstairs|downstairs)\b",
    (m) => '${m[1]} ${m[2]}',
    (Match m) =>
        'Türkçedeki "-e" (eve, oraya) eki yüzünden "to" eklenir; ama "${m[2]}" zaten yön bildirir, '
        'önüne "to" gelmez: "go ${m[2]}".',
    example: 'I am going to home now.',
    fixed: 'I am going home now.',
  ),
  TrRule(
    'go_to_activity',
    TrErrorCategory.preposition,
    r"\b(go|goes|going|went|gone)\s+to\s+(shopping|swimming|fishing|skiing|jogging|running|hiking|dancing|camping|sightseeing)\b",
    (m) => '${m[1]} ${m[2]}',
    'Türkçede "alışverişe gitmek" -e ekiyle söylenir; İngilizcede "go + -ing" kalıbında '
        '"to" kullanılmaz: "go shopping".',
    example: 'We went to shopping on Saturday.',
    fixed: 'We went shopping on Saturday.',
  ),
  TrRule(
    'listen_to',
    TrErrorCategory.preposition,
    r"\b(listen|listens|listened|listening)\s+(music|the radio|radio|songs?|the song|podcasts?|me|him|her|them|us|you|it|my \w+|this|that|the teacher|the news)\b",
    (m) => '${m[1]} to ${m[2]}',
    'Türkçede "müzik dinlemek" doğrudan nesne alır. İngilizcede "listen" her zaman "to" ister: '
        '"listen to music".',
    example: 'I listen music every evening.',
    fixed: 'I listen to music every evening.',
  ),
  TrRule(
    'married_with',
    TrErrorCategory.preposition,
    r"\b(married|engaged)\s+with\b(?!\s+(?:two|three|four|\d|a\s+(?:child|kid|son|daughter|baby)|children|kids|no)\b)",
    (m) => '${m[1]} to',
    'Türkçedeki "biriyle evli" ifadesindeki "ile" yüzünden "with" kullanılır; İngilizcede '
        '"married to" denir.',
    example: 'She is married with a doctor.',
    fixed: 'She is married to a doctor.',
  ),
  TrRule(
    'arrive_to',
    TrErrorCategory.preposition,
    r"\b(arrive|arrives|arrived|arriving)\s+to\s+(\w+)",
    (m) {
      final word = m[2]!;
      final city = word[0] == word[0].toUpperCase() && word != 'the';
      return '${m[1]} ${city ? 'in' : 'at'} $word';
    },
    'Türkçedeki "-e varmak" yüzünden "to" eklenir. "arrive" to almaz: şehir/ülke için '
        '"arrive in", bina/yer için "arrive at".',
    example: 'We arrived to Ankara at night.',
    fixed: 'We arrived in Ankara at night.',
  ),
  TrRule(
    'enter_to',
    TrErrorCategory.preposition,
    r"\b(enter|enters|entered|entering)\s+(?:to|in)\s+(the|a|an|my|our|his|her|this|their)\b",
    (m) => '${m[1]} ${m[2]}',
    'Türkçedeki "odaya girmek" -e ekiyle söylenir; İngilizcede "enter" doğrudan nesne alır: '
        '"enter the room".',
    example: 'He entered to the room quietly.',
    fixed: 'He entered the room quietly.',
  ),
  TrRule(
    'depend_on',
    TrErrorCategory.preposition,
    r"\b(depend|depends|depended|depending)\s+(of|from|to)\b",
    (m) => '${m[1]} on',
    'Türkçedeki "-e bağlı" ya da "-den" kalıbı İngilizceye taşınmaz; "depend on" sabit bir kalıp.',
    example: 'It depends of the price.',
    fixed: 'It depends on the price.',
  ),
  TrRule(
    'day_on',
    TrErrorCategory.preposition,
    r"\b(in|at)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(s?)\b",
    (m) => 'on ${m[2]![0].toUpperCase()}${m[2]!.substring(1).toLowerCase()}${m[3]}',
    'Türkçede "pazartesi günü" ya da "-de" deriz; İngilizcede günlerden önce "on" gelir: '
        '"on Monday".',
    example: 'I will see you in Monday.',
    fixed: 'I will see you on Monday.',
  ),
  TrRule(
    'in_the_weekend',
    TrErrorCategory.preposition,
    r"\bin\s+the\s+weekend\b",
    (m) => 'at the weekend',
    'Türkçedeki "hafta sonunda" -de eki "in" gibi düşünülür; İngilizcede "at the weekend" '
        '(Amerikan İngilizcesinde "on the weekend") denir.',
    example: 'We relax in the weekend.',
    fixed: 'We relax at the weekend.',
  ),
  TrRule(
    'part_of_day',
    TrErrorCategory.preposition,
    r"\bat\s+(?:the\s+)?(morning|afternoon|evening)\b",
    (m) => 'in the ${m[1]}',
    'Türkçede "sabahleyin, akşamleyin" tek kelime. İngilizcede "in the morning / in the '
        'evening" ama "at night" denir.',
    example: 'I drink tea at the morning.',
    fixed: 'I drink tea in the morning.',
  ),
  TrRule(
    'in_night',
    TrErrorCategory.preposition,
    r"\bin\s+night\b",
    (m) => 'at night',
    'Gece için kalıp "at night". (Sabah, öğle, akşam ise "in the morning/afternoon/evening".)',
    example: 'I study in night.',
    fixed: 'I study at night.',
  ),
  TrRule(
    'month_year_in',
    TrErrorCategory.preposition,
    r"\b(on|at)\s+((?:19|20)\d\d|january|february|march|april|june|july|august|september|october|november|december|summer|winter|spring|autumn)\b(?!\s*\d)",
    (m) => 'in ${m[2]}',
    'Türkçede tarihlerin hepsi "-de" alır. İngilizcede yıl, ay ve mevsim için "in", gün için '
        '"on", saat için "at" kullanılır.',
    example: 'I was born on 1998.',
    fixed: 'I was born in 1998.',
  ),
  TrRule(
    'good_at',
    TrErrorCategory.preposition,
    r"\b(good|bad|better|best|great|terrible)\s+(?:in|on)\s+(english|math|maths|mathematics|science|sports?|football|basketball|languages|music|cooking|drawing|swimming|tennis|chess|physics|chemistry|history|singing|dancing)\b",
    (m) => '${m[1]} at ${m[2]!.toLowerCase() == 'english' ? 'English' : m[2]}',
    'Türkçedeki "matematikte iyi" ifadesindeki "-de" yüzünden "in" seçilir; İngilizcede '
        '"good at" sabit kalıp.',
    example: 'She is very good in math.',
    fixed: 'She is very good at math.',
  ),
  TrRule(
    'interested_in',
    TrErrorCategory.preposition,
    r"\binterested\s+(?:about|on|with|for)\b",
    (m) => 'interested in',
    'Türkçedeki "bir şeyle ilgilenmek" ifadesindeki "ile" yüzünden "with" kullanılır; '
        'İngilizcede "interested in" denir.',
    example: 'I am interested with art.',
    fixed: 'I am interested in art.',
  ),
  TrRule(
    'afraid_of',
    TrErrorCategory.preposition,
    r"\b(afraid|scared|frightened|terrified)\s+(?:from|with)\b",
    (m) => '${m[1]} of',
    'Türkçedeki "-den korkmak" yüzünden "from" seçilir; İngilizcede "afraid of / scared of".',
    example: 'My son is afraid from dogs.',
    fixed: 'My son is afraid of dogs.',
  ),
  TrRule(
    'explain_me',
    TrErrorCategory.preposition,
    r"\bexplain(s|ed|ing)?\s+(me|us)\b(?:\s+([\w' ]+?)(?=\s*[.!?,]|\s*$))?",
    (m) => m[3] == null ? 'explain${m[1] ?? ''} to ${m[2]}' : 'explain${m[1] ?? ''} ${m[3]} to ${m[2]}',
    'Türkçede "bana açıkla" -e ekiyle söylenir ve İngilizcede de karşılığı "to me" olur: '
        '"explain it to me".',
    example: 'Can you explain me this rule?',
    fixed: 'Can you explain this rule to me?',
  ),
  TrRule(
    'discuss_about',
    TrErrorCategory.preposition,
    r"\b(discuss|discusses|discussed|discussing)\s+about\b",
    (m) => '${m[1]}',
    'Türkçedeki "hakkında tartışmak" yüzünden "about" eklenir; "discuss" doğrudan nesne alır.',
    example: 'We discussed about the project.',
    fixed: 'We discussed the project.',
  ),
  TrRule(
    'wait_for',
    TrErrorCategory.preposition,
    r"\b(wait|waits|waited|waiting)\s+(me|him|her|us|them|you)\b(?!\s+(?:for|to)\b)",
    (m) => '${m[1]} for ${m[2]}',
    'Türkçede "seni bekliyorum" doğrudan nesne alır; İngilizcede "wait for" gerekir.',
    example: 'I will wait you at the station.',
    fixed: 'I will wait for you at the station.',
  ),
  TrRule(
    'call_to',
    TrErrorCategory.preposition,
    r"\b(call|calls|called|calling)\s+to\s+(me|him|her|you|us|them|(?:my|your|his|her)\s+\w+)\b",
    (m) => '${m[1]} ${m[2]}',
    'Türkçedeki "birine telefon etmek" -e eki yüzünden "to" eklenir; "call" doğrudan nesne '
        'alır: "call my mom".',
    example: 'I called to my mom.',
    fixed: 'I called my mom.',
  ),
  TrRule(
    'on_tv',
    TrErrorCategory.preposition,
    r"\bin\s+(?:the\s+)?(tv|television|radio)\b(?!\s+(?:room|studio|station|show|series|channel|program|programme)\b)",
    (m) =>
        m[1]!.toLowerCase() == 'radio' ? 'on the radio' : 'on ${m[1]!.toLowerCase() == 'tv' ? 'TV' : m[1]}',
    'Türkçedeki "televizyonda" -de eki "in" gibi görünür; İngilizcede "on TV, on the radio".',
    example: 'I saw it in the TV.',
    fixed: 'I saw it on TV.',
  ),
  TrRule(
    'at_same_time',
    TrErrorCategory.preposition,
    r"\bin\s+the\s+same\s+time\b",
    (m) => 'at the same time',
    'Türkçedeki "aynı zamanda" ifadesi "in" ile çevrilir ama kalıp "at the same time".',
    example: 'We arrived in the same time.',
    fixed: 'We arrived at the same time.',
  ),
  TrRule(
    'before_ago',
    TrErrorCategory.preposition,
    '\\bbefore\\s+((?:\\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|a few|few|many|several)\\s+(?:years?|months?|weeks?|days?|hours?|minutes?))\\b',
    (m) => '${m[1]} ago',
    'Türkçedeki "iki yıl önce" kelimesi kelimesine "before two years" olur. İngilizcede '
        'şimdiden geriye sayarken "two years ago" denir.',
    example: 'I moved here before two years.',
    fixed: 'I moved here two years ago.',
  ),
  TrRule(
    'until_by',
    TrErrorCategory.preposition,
    r"\b(finish|finished|send|sent|submit|submitted|complete|completed|return|returned|deliver|delivered|pay|paid|be back|be ready)\b([^.!?]{0,30}?)\s+until\b",
    (m) => '${m[1]}${m[2]} by',
    'Türkçedeki "-e kadar" iki anlama gelir. Bir işin bitiş sınırı için "by" (Friday\'ye '
        'kadar bitir), süren bir durum için "until" (5\'e kadar bekle) kullanılır.',
    example: 'Please finish the report until Friday.',
    fixed: 'Please finish the report by Friday.',
  ),
  TrRule(
    'in_home',
    TrErrorCategory.preposition,
    r"\bin\s+home\b(?!\s+(?:office|country|town|page|team|game|screen)\b)",
    (m) => 'at home',
    'Türkçedeki "evde" -de eki "in" gibi düşünülür; İngilizcede kalıp "at home".',
    example: 'I stayed in home all day.',
    fixed: 'I stayed at home all day.',
  ),

  // --- articles --------------------------------------------------------------
  TrRule(
    'a_before_vowel',
    TrErrorCategory.article,
    r"(?<![\w'])(a|A)\s+(?!(?:one|once|uni\w*|use\w*|usu\w*|[Ee]u\w*|is|in|it|if|of|on|or|and|are|at|as|also|again|am|an|a|I)\b)((?:[aeioAEIO]\w*)|[uU](?!ni|se|su|ro|te|kr|ri)\w*|hours?\b|honest\w*)",
    (m) => '${m[1] == 'A' ? 'An' : 'an'} ${m[2]}',
    (Match m) => 'Sesli harfle başlayan kelimeden önce "a" değil "an" gelir: "an ${m[2]}".',
    caseSensitive: true,
    example: 'I ate a apple.',
    fixed: 'I ate an apple.',
  ),
  TrRule(
    'an_before_consonant',
    TrErrorCategory.article,
    r"(?<![\w'])(an|An)\s+((?:[bcdfgjklmnpqrstvwxyz]\w*)|h(?!our|onest|onou?r|eir|erb)\w*|uni\w*|use\w*|usu\w*|euro\w*|one\b)",
    (m) => '${m[1] == 'An' ? 'A' : 'a'} ${m[2]}',
    (Match m) => 'Ünsüz sesle başlayan kelimeden önce "an" değil "a" gelir: "a ${m[2]}".',
    caseSensitive: true,
    example: 'She is an university student.',
    fixed: 'She is a university student.',
  ),
  TrRule(
    'profession_article',
    TrErrorCategory.article,
    r"\b(I am|I'm|you are|you're|he is|he's|she is|she's|my (?:mother|father|mom|dad|brother|sister|friend|wife|husband) is)\s+(teacher|doctor|student|engineer|nurse|lawyer|dentist|architect|accountant|waiter|waitress|chef|cook|pilot|driver|officer|manager|developer|programmer|designer|artist|actor|actress|singer|farmer|soldier|journalist|pharmacist|secretary|worker)\b",
    (m) => '${m[1]} ${_articleFor(m[2]!)} ${m[2]}',
    (Match m) =>
        'Türkçede "Ben öğretmenim" derken "bir" gerekmez; İngilizcede meslekten önce a/an '
        'şart: "${_articleFor(m[2]!)} ${m[2]}".',
    example: 'I am teacher.',
    fixed: 'I am a teacher.',
  ),
  TrRule(
    'have_a',
    TrErrorCategory.article,
    r"\b(have|has|had|need|want|buy|bought|got)\s+(car|dog|cat|house|computer|job|bike|bicycle|idea|question|problem|apartment|flat|umbrella|phone|laptop|boyfriend|girlfriend|garden|meeting|headache)\b(?!\s+(?:insurance|food|keys?|trouble|accident|park|lot|number|bill|charger|call|room|owner|loan|parts?)\b)",
    (m) => '${m[1]} ${_articleFor(m[2]!)} ${m[2]}',
    (Match m) =>
        'Türkçede "arabam var / araba aldım" derken "bir" düşer. İngilizcede tekil sayılabilen '
        'isim yalnız durmaz: "${_articleFor(m[2]!)} ${m[2]}".',
    example: 'I have car.',
    fixed: 'I have a car.',
  ),
  TrRule(
    'play_the_instrument',
    TrErrorCategory.article,
    r"\b(play|plays|played|playing)\s+(guitar|piano|violin|drums|flute|cello|saxophone)\b",
    (m) => '${m[1]} the ${m[2]}',
    'Türkçede "gitar çalmak" artikelsiz söylenir; İngilizcede çalgılardan önce "the" gelir: '
        '"play the guitar".',
    example: 'He plays guitar every night.',
    fixed: 'He plays the guitar every night.',
  ),
  TrRule(
    'superlative_the',
    TrErrorCategory.article,
    r"\b(is|are|was|were|am|'s|'re)\s+(best|worst|biggest|smallest|tallest|oldest|youngest|highest|cheapest|most beautiful|most important|most expensive|most popular)\s+(?!(?:to|not|for|when|if|of|in|at)\b)(\w+)",
    (m) => '${m[1]} the ${m[2]} ${m[3]}',
    'Türkçedeki "en" tek başına yeter; İngilizcede en üstünlük sıfatından önce "the" gelir: '
        '"the best".',
    example: 'He is best student in the class.',
    fixed: 'He is the best student in the class.',
  ),

  // --- plural and agreement --------------------------------------------------
  TrRule(
    'people_is',
    TrErrorCategory.plural,
    r"\b(people|police|children|men|women)\s+(is|was|has|doesn't|does)\b",
    (m) {
      const fix = {'is': 'are', 'was': 'were', 'has': 'have', "doesn't": "don't", 'does': 'do'};
      return '${m[1]} ${fix[m[2]!.toLowerCase()]}';
    },
    (Match m) =>
        'Türkçede çoğul özneyle tekil fiil kullanılabilir ("insanlar geldi"). İngilizcede '
        '"${m[1]}" zaten çoğuldur ve fiil de çoğul olmalı.',
    example: 'People is very friendly here.',
    fixed: 'People are very friendly here.',
  ),
  TrRule(
    'everyone_are',
    TrErrorCategory.plural,
    r"\b(everyone|everybody|nobody|somebody|someone|no one)\s+(are|were|have|don't)\b",
    (m) {
      const fix = {'are': 'is', 'were': 'was', 'have': 'has', "don't": "doesn't"};
      return '${m[1]} ${fix[m[2]!.toLowerCase()]}';
    },
    (Match m) =>
        'Türkçede "herkes" anlamca kalabalık olsa da İngilizcede "${m[1]}" tekildir; fiil '
        'de tekil gelir.',
    example: 'Everyone are happy today.',
    fixed: 'Everyone is happy today.',
  ),
  TrRule(
    'number_singular',
    TrErrorCategory.plural,
    '\\b($_numbers|many|several|a few)\\s+(book|car|friend|year|day|week|month|hour|minute|student|child|person|man|woman|apple|brother|sister|thing|country|city|language|cat|dog|time|kilometer|kilo|ticket|room|page|egg)\\b'
        '(?!-|\\s+(?:old|walk|drive|ride|break|trip|course|program|journey|flight|wait)\\b)',
    (m) => '${m[1]} ${pluralOf(m[2]!)}',
    (Match m) =>
        'Türkçede sayıdan sonra isim tekil kalır ("iki kitap"). İngilizcede birden fazlaysa '
        'isim çoğul olur: "${m[1]} ${pluralOf(m[2]!)}".',
    example: 'I have two brother.',
    fixed: 'I have two brothers.',
  ),
  TrRule(
    'one_of_plural',
    TrErrorCategory.plural,
    r"\bone of (my|the|his|her|our|their|your)\s+((?:best|favorite|favourite|closest|oldest|biggest|most \w+)\s+)?(friend|brother|sister|teacher|colleague|student|book|problem|reason|city|country|film|movie|song|place|day|thing|man|woman|child|person)\b",
    (m) => 'one of ${m[1]} ${m[2] ?? ''}${pluralOf(m[3]!)}',
    '"One of" birçoğun içinden birini seçer; bu yüzden ardından gelen isim çoğul olur: '
        '"one of my friends". Türkçedeki "arkadaşlarımdan biri" de aslında çoğul.',
    example: 'He is one of my friend.',
    fixed: 'He is one of my friends.',
  ),
  TrRule(
    'every_plural',
    TrErrorCategory.plural,
    r"\bevery\s+(students|days|weeks|children|persons|things|years|mornings|nights|people|teachers|questions)\b",
    (m) => 'every ${singularOf(m[1]!)}',
    'Türkçedeki "her gün" gibi, "every" de tekil isimle gelir: "every day, every student".',
    example: 'I walk every days.',
    fixed: 'I walk every day.',
  ),
  TrRule(
    'there_is_many',
    TrErrorCategory.plural,
    '\\bthere(\\s+is|\\s+was|\'s)\\s+($_numbers|many|several|a lot of|lots of)\\b'
        '(?!\\s+(?:water|money|time|traffic|noise|food|work|information|milk|rain|snow|sugar|furniture|fun|love)\\b)',
    (m) => 'there ${m[1]!.contains('was') ? 'were' : 'are'} ${m[2]}',
    'Türkçedeki "var" tekil-çoğul ayırmaz. İngilizcede çoğul için "there are", tekil için '
        '"there is" kullanılır.',
    example: 'There is many people in the street.',
    fixed: 'There are many people in the street.',
  ),

  // --- uncountable -----------------------------------------------------------
  TrRule(
    'uncountable_s',
    TrErrorCategory.uncountable,
    r"\b(informations|advices|furnitures|equipments|homeworks|luggages|baggages|knowledges|evidences|feedbacks|softwares|traffics)\b",
    (m) => m[1]!.substring(0, m[1]!.length - 1),
    (Match m) =>
        'Türkçede "bilgiler, tavsiyeler" çoğul olabilir ama İngilizcede '
        '"${m[1]!.substring(0, m[1]!.length - 1)}" sayılamaz, -s almaz.',
    example: 'He gave me some useful advices.',
    fixed: 'He gave me some useful advice.',
  ),
  TrRule(
    'a_uncountable',
    TrErrorCategory.uncountable,
    r"\b(?:a|an)\s+((?:good|bad|great|useful|nice|important)\s+)?(information|advice|furniture|homework|luggage|news|equipment|feedback|bread)\b(?![\s-]+(?:assignment|forecast|report|bag|item|piece|story|agency|program|channel|station|desk|company|shop|store|lover|teacher|video|festival|maker)\b)",
    (m) => 'some ${m[1] ?? ''}${m[2]}',
    (Match m) =>
        'Türkçedeki "bir haber, bir tavsiye" yüzünden "a" eklenir; "${m[2]}" sayılamaz. '
        '"some ${m[2]}" ya da "a piece of ${m[2]}" de.',
    example: 'I have a good news for you.',
    fixed: 'I have some good news for you.',
  ),
  TrRule(
    'many_uncountable',
    TrErrorCategory.uncountable,
    r"\bmany\s+(money|information|advice|water|homework|work|furniture|luggage|traffic|bread|food|milk|sugar|news|music|knowledge|rain|snow)\b",
    (m) => 'much ${m[1]}',
    (Match m) =>
        'Türkçedeki "çok" her isimle gelir. İngilizcede sayılamayan isimlerle "much" ya da '
        '"a lot of" kullanılır: "much ${m[1]}".',
    example: 'I don\'t have many money.',
    fixed: 'I don\'t have much money.',
  ),
  TrRule(
    'much_countable',
    TrErrorCategory.uncountable,
    r"\bmuch\s+(people|friends|books|cars|students|things|problems|questions|children|countries|cities|times|days|years|mistakes)\b",
    (m) => 'many ${m[1]}',
    (Match m) => 'Sayılabilen çoğul isimlerle "much" değil "many" kullanılır: "many ${m[1]}".',
    example: 'There were much people at the concert.',
    fixed: 'There were many people at the concert.',
  ),
  TrRule(
    'news_is',
    TrErrorCategory.uncountable,
    r"\bnews\s+(are|were|have)\b",
    (m) => 'news ${const {'are': 'is', 'were': 'was', 'have': 'has'}[m[1]!.toLowerCase()]}',
    '"news" -s ile bitse de tekildir ve sayılamaz: "The news is good".',
    example: 'The news are good.',
    fixed: 'The news is good.',
  ),
  TrRule(
    'hairs',
    TrErrorCategory.uncountable,
    r"\b(my|her|his|your|their|our)\s+hairs(?:\s+(are|were))?\b",
    (m) =>
        '${m[1]} hair${m[2] == null
            ? ''
            : m[2]!.toLowerCase() == 'are'
            ? ' is'
            : ' was'}',
    'Türkçedeki "saçlarım" çoğul ama İngilizcede baştaki saç topluca "hair" (sayılamaz).',
    example: 'Her hairs are long.',
    fixed: 'Her hair is long.',
  ),

  // --- word order ------------------------------------------------------------
  TrRule(
    'adjective_after_noun',
    TrErrorCategory.wordOrder,
    r"\b(a|an)\s+(car|house|book|dress|day|city|man|woman|girl|boy|dog|cat|room|phone|film|movie|bag|shirt|apartment|computer|garden|friend|job|restaurant|hotel)\s+(red|blue|big|small|new|old|beautiful|nice|good|bad|expensive|cheap|long|short|black|white|green|yellow|large|little|young|tall|clean|dirty|modern|lovely|interesting|boring|delicious)\b(?!\s+(?:enough|for|to)\b)",
    (m) => '${_articleFor(m[3]!)} ${m[3]} ${m[2]}',
    (Match m) => 'Sıfat ismin önüne gelir: "${_articleFor(m[3]!)} ${m[3]} ${m[2]}".',
    example: 'I want a car red.',
    fixed: 'I want a red car.',
  ),
  TrRule(
    'very_much_position',
    TrErrorCategory.wordOrder,
    r"\b(like|likes|love|loves|liked|loved|enjoy|enjoys|enjoyed)\s+very\s+much\s+([\w' ]+?)(?=\s*[.!?,]|\s*$)",
    (m) => '${m[1]} ${m[2]} very much',
    'Türkçede "çok seviyorum" der, zarfı fiilin önüne koyarız. İngilizcede "very much" nesneden '
        'sonra, cümlenin sonuna gelir: "I like football very much".',
    example: 'I like very much football.',
    fixed: 'I like football very much.',
  ),

  // --- questions -------------------------------------------------------------
  TrRule(
    'question_no_aux',
    TrErrorCategory.question,
    '$_sentenceStart(What time|How often|How much|How many|Where|What|When|Why|How)\\s+(you|they|we|I|he|she)\\s+'
        '(live|work|go|like|want|study|come|eat|play|mean|think|need|do|have|know|say|get|start|finish|watch|read|learn)\\b'
        '(?=[^.!?]*\\?)',
    (m) => '${m[1]} ${_isThirdSingular(m[2]!) ? 'does' : 'do'} ${m[2]} ${m[3]}',
    (Match m) =>
        'Türkçede soru "Nerede yaşıyorsun?" gibi ek ve tonlamayla kurulur. İngilizcede soru '
        'kelimesinden sonra yardımcı fiil gelir: "${m[1]} ${_isThirdSingular(m[2]!) ? 'does' : 'do'} ${m[2]} ${m[3]}?"',
    example: 'Where you live?',
    fixed: 'Where do you live?',
  ),
  TrRule(
    'what_means',
    TrErrorCategory.question,
    "${_sentenceStart}What\\s+means\\s+([\\w' \"“”-]+?)\\s*(\\?|\$)",
    (m) => 'What does ${m[1]} mean?',
    'Türkçedeki "... ne demek?" sırası İngilizceye taşınınca "What means" çıkar. Doğrusu '
        '"What does ... mean?"',
    example: 'What means "sympathetic"?',
    fixed: 'What does "sympathetic" mean?',
  ),
  TrRule(
    'indirect_question',
    TrErrorCategory.question,
    r"\b(know|tell me|wonder|ask|remember|understand)\s+(where|what|when|why|how|what time|how much|how many)\s+(is|are|was|were)\s+((?:the|a|an|my|your|his|her|our|their|it|this|that|he|she|they|we|you)\b[\w' ]*?)(?=\s*[?.!,]|\s*$)",
    (m) => '${m[1]} ${m[2]} ${m[4]} ${m[3]}',
    'Dolaylı soruda ("Biliyor musun ... nerede?") soru sırası bozulmaz: özne önce, fiil sonra '
        'gelir: "Do you know where the station is?"',
    example: 'Do you know where is the station?',
    fixed: 'Do you know where the station is?',
  ),

  // --- double negative -------------------------------------------------------
  TrRule(
    'double_negative',
    TrErrorCategory.doubleNegative,
    r"\b(don't|doesn't|didn't|can't|cannot|won't|wouldn't|couldn't|haven't|hasn't|isn't|aren't|wasn't|weren't|never)\b((?:\s+(?!(?:if|that|because|when|but)\b)[\w']+){0,3}?)\s+(?<!\b(?:say|said|says|saying|answer|answered|take|took)\s)(nothing|nobody|nowhere|no one|none|never|no)\b",
    (m) {
      const any = {
        'nothing': 'anything',
        'nobody': 'anybody',
        'nowhere': 'anywhere',
        'no one': 'anyone',
        'none': 'any',
        'never': 'ever',
        'no': 'any',
      };
      return '${m[1]}${m[2]} ${any[m[3]!.toLowerCase()]}';
    },
    (Match m) =>
        'Türkçede "hiçbir şey bilmiyorum" iki olumsuzla kurulur. İngilizcede "${m[1]}" zaten '
        'olumsuz; "${m[3]}" yerine any- biçimi gelir.',
    example: "I don't know nothing about it.",
    fixed: "I don't know anything about it.",
  ),

  // --- comparatives ----------------------------------------------------------
  TrRule(
    'more_er',
    TrErrorCategory.comparative,
    r"\b(much\s+)?more\s+(better|worse|bigger|smaller|easier|harder|older|younger|cheaper|faster|taller|happier|longer|shorter|nicer|colder|hotter|richer|stronger|higher|lower|larger|greater|prettier|busier|heavier|lighter|earlier|later|closer)\b",
    (m) => '${m[1] ?? ''}${m[2]}',
    (Match m) =>
        'Türkçede "daha" her sıfatın önüne gelir. "${m[2]}" zaten karşılaştırma bildirir; önüne '
        '"more" eklenmez.',
    example: 'This book is more better.',
    fixed: 'This book is better.',
  ),
  TrRule(
    'more_short_adjective',
    TrErrorCategory.comparative,
    r"\bmore\s+(easy|big|small|cheap|fast|tall|old|young|happy|hard|long|short|nice|cold|hot|good|bad|busy|heavy|pretty|rich|strong|high|low|large|great|close|early)\b(?=\s+than\b|\s*[.!?,]|\s*$)",
    (m) => comparativeOf(m[1]!),
    (Match m) => 'Kısa sıfatlar "more" yerine -er alır: "${comparativeOf(m[1]!)}".',
    example: 'Istanbul is more big than Izmir.',
    fixed: 'Istanbul is bigger than Izmir.',
  ),
  TrRule(
    'than_without_er',
    TrErrorCategory.comparative,
    r"\b(is|are|was|were|am|'s|'re)\s+(big|small|tall|old|young|fast|cheap|cold|hot|long|short|good|bad|easy|hard|nice|happy|rich|strong|busy|expensive|beautiful|interesting|difficult|important|comfortable)\s+than\b",
    (m) => '${m[1]} ${comparativeOf(m[2]!)} than',
    (Match m) =>
        'Türkçede "benden uzun" derken sıfat değişmez; İngilizcede "than" ile karşılaştırırken '
        'sıfat -er ya da more alır: "${comparativeOf(m[2]!)} than".',
    example: 'My brother is tall than me.',
    fixed: 'My brother is taller than me.',
  ),
  TrRule(
    'most_est',
    TrErrorCategory.comparative,
    r"\b(?:the\s+)?most\s+(best|worst|(?!honest|modest|earnest|interest)\w{2,}est)\b",
    (m) => 'the ${m[1]}',
    (Match m) => '"${m[1]}" zaten en üstünlük bildirir; önüne "most" gelmez.',
    example: 'It was the most best day of my life.',
    fixed: 'It was the best day of my life.',
  ),
  TrRule(
    'as_than',
    TrErrorCategory.comparative,
    r"\bas\s+(\w+)\s+than\b",
    (m) => 'as ${m[1]} as',
    'Eşitlik "as ... as" ile kurulur ("kadar"); "than" sadece -er/more ile kullanılır.',
    example: 'He is as tall than his father.',
    fixed: 'He is as tall as his father.',
  ),

  // --- false friends ---------------------------------------------------------
  TrRule(
    'sympathetic',
    TrErrorCategory.falseFriend,
    r"\b(is|are|was|were|'s|'re|looks|seems|very|so|really)\s+((?:very|so|really)\s+)?sympathetic\b(?!\s+(?:to|towards|about|ear)\b)",
    (m) => '${m[1]} ${m[2] ?? ''}nice',
    'Türkçedeki "sempatik" İngilizcede "nice, likeable, friendly" demek. "Sympathetic" ise '
        '"anlayışlı, halden anlayan" anlamına gelir.',
    example: 'My teacher is very sympathetic.',
    fixed: 'My teacher is very nice.',
  ),
  TrRule(
    'fabric_factory',
    TrErrorCategory.falseFriend,
    r"\b(in|at|to)\s+(a|the|this|that|our|my|his|her|their)\s+fabric\b",
    (m) => '${m[1]} ${m[2]} factory',
    'Türkçedeki "fabrika" İngilizcede "factory". "Fabric" kumaş demek.',
    example: 'My father works in a fabric.',
    fixed: 'My father works in a factory.',
  ),
  TrRule(
    'control_check',
    TrErrorCategory.falseFriend,
    r"\b(control|controls|controlled|controlling)\s+(my|your|his|her|our|the)\s+(e-?mails?|mail|messages|homework|answers?|phone|bag|tickets?|passport)\b",
    (m) => '${_sameForm(m[1]!, 'check', past: 'checked')} ${m[2]} ${m[3]}',
    'Türkçedeki "kontrol etmek" çoğu zaman "check" demek. İngilizcede "control" yönetmek, '
        'hâkim olmak anlamındadır.',
    example: 'I control my email every morning.',
    fixed: 'I check my email every morning.',
  ),
  TrRule(
    'pasta_cake',
    TrErrorCategory.falseFriend,
    r"\b(birthday|chocolate|strawberry|wedding)\s+pasta\b",
    (m) => '${m[1]} cake',
    'Türkçedeki "pasta" İngilizcede "cake". "Pasta" makarna demek.',
    example: 'We bought a birthday pasta.',
    fixed: 'We bought a birthday cake.',
  ),
  TrRule(
    'pension_guesthouse',
    TrErrorCategory.falseFriend,
    r"\b(stay|stays|stayed|staying)\s+(at|in)\s+(a|the)\s+pension\b",
    (m) => '${m[1]} ${m[2]} ${m[3]} guesthouse',
    'Türkçedeki "pansiyon" İngilizcede "guesthouse". "Pension" emekli maaşı demek.',
    example: 'We stayed at a pension in Bodrum.',
    fixed: 'We stayed at a guesthouse in Bodrum.',
  ),
  TrRule(
    'condition_shape',
    TrErrorCategory.falseFriend,
    r"\b(?:I have|I've got)\s+(?:a\s+)?(good|bad|great|poor)\s+condition\b",
    (m) => 'I am in ${m[1]} shape',
    'Türkçedeki "kondisyonum iyi" İngilizcede "I am in good shape". "Condition" durum, şart '
        'demek.',
    example: 'I have good condition because I run.',
    fixed: 'I am in good shape because I run.',
  ),
  TrRule(
    'parking_car_park',
    TrErrorCategory.falseFriend,
    r"\b(a|the)\s+parking\b(?!\s+(?:lot|space|spot|garage|area|ticket|meter|fine|place)\b)",
    (m) => '${m[1]} car park',
    'Türkçedeki "otopark" İngilizcede "car park" (Amerikan: "parking lot"). "Parking" tek '
        'başına park etme eylemi.',
    example: 'Is there a parking near here?',
    fixed: 'Is there a car park near here?',
  ),
  TrRule(
    'magazine_gossip',
    TrErrorCategory.falseFriend,
    r"\bmagazine\s+(news|programs?|programmes?|shows?)\b",
    (m) => 'celebrity ${m[1]}',
    'Türkçedeki "magazin haberleri" İngilizcede "celebrity news / gossip". "Magazine" dergi '
        'demek.',
    example: 'I never watch magazine programs.',
    fixed: 'I never watch celebrity programs.',
  ),

  // --- word choice -----------------------------------------------------------
  TrRule(
    'make_homework',
    TrErrorCategory.wordChoice,
    r"\b(make|makes|making|made)\s+((?:my|your|his|her|our|their|the|some|a lot of|much)\s+)?(homework|exercise|sports?|shopping|housework|research|dishes|cleaning|laundry|yoga|a favou?r)\b",
    (m) {
      final before = m.input.substring(0, m.start);
      final perfect = RegExp(r"(have|has|had|'ve|'s)\s+$", caseSensitive: false).hasMatch(before);
      final verb = m[1]!.toLowerCase() == 'made' ? (perfect ? 'done' : 'did') : _sameForm(m[1]!, 'do');
      return '$verb ${m[2] ?? ''}${m[3]}';
    },
    (Match m) =>
        'Türkçede hepsi "yapmak". İngilizcede iş, görev ve aktiviteler "do" ile söylenir: '
        '"do ${m[3]}". Bir şey üretirken "make" (make a cake).',
    example: 'I make my homework after dinner.',
    fixed: 'I do my homework after dinner.',
  ),
  TrRule(
    'do_mistake',
    TrErrorCategory.wordChoice,
    r"(?<!^|[.!?]\s)(?<!\b(?:why|how|what|where|when|who)\s)\b(do|does|doing|did|done)\s+((?:a|an|many|some|lots of|a lot of|the same|no|any|a big|a terrible)\s+)?(mistakes?|noise|decisions?|plans?|phone calls?|effort|progress|wishes|a wish|promises?|choices?|appointments?|a speech|reservations?)\b",
    (m) {
      final v = m[1]!.toLowerCase();
      final verb = v == 'done' ? 'made' : _sameForm(m[1]!, 'make', past: 'made');
      return '$verb ${m[2] ?? ''}${m[3]}';
    },
    (Match m) =>
        'Türkçede "hata yapmak, karar vermek" diyoruz; İngilizcede bunlar "make" ile kalıplaşmış: '
        '"make ${m[3]}".',
    example: 'I did a mistake in the test.',
    fixed: 'I made a mistake in the test.',
  ),
  TrRule(
    'pull_photo',
    TrErrorCategory.wordChoice,
    r"\b(pull|pulls|pulled|pulling)\s+((?:a|the|some|many|lots of|a lot of|my|your|our)\s+)?(photos?|pictures?|selfies?|videos?)\b",
    (m) => '${_sameForm(m[1]!, 'take', past: 'took')} ${m[2] ?? ''}${m[3]}',
    'Türkçedeki "fotoğraf çekmek" kelimesi kelimesine "pull" olur. İngilizcede '
        '"take a photo" denir.',
    example: 'Can I pull a photo here?',
    fixed: 'Can I take a photo here?',
  ),
  TrRule(
    'open_the_light',
    TrErrorCategory.wordChoice,
    r"\b(open|opens|opened|opening|close|closes|closed|closing)\s+(the\s+)?(lights?|tv|television|radio|computer|music|air conditioner|heater|lamp)\b",
    (m) {
      final on = m[1]!.toLowerCase().startsWith('open');
      final turn = _sameForm(m[1]!, 'turn', past: 'turned');
      final thing = m[3]!.toLowerCase() == 'tv' ? 'TV' : m[3];
      return '$turn ${on ? 'on' : 'off'} ${m[2] ?? ''}$thing';
    },
    'Türkçede ışık ve cihazlar "açılır, kapanır". İngilizcede elektrikli şeyler için '
        '"turn on / turn off" kullanılır; "open" kapı, pencere içindir.',
    example: 'Can you open the light?',
    fixed: 'Can you turn on the light?',
  ),
  TrRule(
    'say_tell',
    TrErrorCategory.wordChoice,
    r"\b(say|says|said|saying)\s+(me|him|her|us)\b",
    (m) => '${_sameForm(m[1]!, 'tell', past: 'told')} ${m[2]}',
    'Türkçede ikisi de "söylemek". Birine söylerken "tell + kişi" (tell me), kişisiz '
        '"say" (say hello) kullanılır.',
    example: 'He said me the truth.',
    fixed: 'He told me the truth.',
  ),
  TrRule(
    'look_tv',
    TrErrorCategory.wordChoice,
    r"\b(look|looks|looked|looking)\s+(tv|television)\b",
    (m) => '${_sameForm(m[1]!, 'watch', past: 'watched')} TV',
    'Türkçedeki "televizyona bakmak" İngilizcede "watch TV". "Look" kısa süre göz atmaktır.',
    example: 'We look TV every evening.',
    fixed: 'We watch TV every evening.',
  ),
  TrRule(
    'borrow_lend',
    TrErrorCategory.wordChoice,
    r"\b(borrow|borrows|borrowed)\s+(me|him|her|us|them)\b",
    (m) => '${_sameForm(m[1]!, 'lend', past: 'lent')} ${m[2]}',
    'Türkçede "ödünç vermek / almak" aynı kelimeyle kurulur. Birine verirken "lend", '
        'birinden alırken "borrow" kullanılır.',
    example: 'Can you borrow me your pen?',
    fixed: 'Can you lend me your pen?',
  ),
  TrRule(
    'win_earn',
    TrErrorCategory.wordChoice,
    r"\b(win|wins|won|winning)\s+([^.!?]{0,25}?)\s+(a|per|every)\s+(month|year|week|day|hour)\b",
    (m) => '${_sameForm(m[1]!, 'earn', past: 'earned')} ${m[2]} ${m[3]} ${m[4]}',
    'Türkçede "para kazanmak" ile "yarışma kazanmak" aynı fiil. İngilizcede çalışarak para '
        'için "earn", yarışma için "win" kullanılır.',
    example: 'She wins 3000 dollars a month.',
    fixed: 'She earns 3000 dollars a month.',
  ),
  TrRule(
    'boring_bored',
    TrErrorCategory.wordChoice,
    r"\b(I am|I'm|I was|I feel|I felt|we are|we were|we're)\s+(boring|exciting|tiring|confusing|surprising|disappointing|embarrassing|annoying)\b",
    (m) {
      const fix = {
        'boring': 'bored',
        'exciting': 'excited',
        'tiring': 'tired',
        'confusing': 'confused',
        'surprising': 'surprised',
        'disappointing': 'disappointed',
        'embarrassing': 'embarrassed',
        'annoying': 'annoyed',
      };
      return '${m[1]} ${fix[m[2]!.toLowerCase()]}';
    },
    'Türkçede "sıkıldım" ve "sıkıcı" farklı kelimeler. İngilizcede hissettiğin şey -ed '
        '(bored), başkasına verdiğin his -ing (boring) olur.',
    example: 'I am boring in this lesson.',
    fixed: 'I am bored in this lesson.',
  ),
  TrRule(
    'how_called',
    TrErrorCategory.wordChoice,
    r"\bhow\s+(is|are)\s+(it|this|that|they|these|those)\s+called\b",
    (m) => 'what ${m[1]} ${m[2]} called',
    'Türkçedeki "buna nasıl denir?" yüzünden "how" seçilir; İngilizcede "What is it called?"',
    example: 'How is this called in English?',
    fixed: 'What is this called in English?',
  ),
  TrRule(
    'good_well',
    TrErrorCategory.wordChoice,
    r"\b(speak|speaks|spoke|play|plays|played|sing|sings|sang|cook|cooks|cooked|swim|swims|swam|dance|dances|danced|drive|drives|drove|write|writes|wrote)\b((?:(?!\b(?:is|was|are|were|looks?|tastes?|smells?|sounds?|seems?)\b)[^.!?,]){0,25}?)\s+((?:very|so|really)\s+)?good\b(?=\s*[.!?,]|\s*$)",
    (m) => '${m[1]}${m[2]} ${m[3] ?? ''}well',
    'Türkçede "iyi konuşuyor" derken "iyi" hem sıfat hem zarf. İngilizcede fiili nitelerken '
        'zarf "well" kullanılır: "She speaks English well".',
    example: 'She speaks English very good.',
    fixed: 'She speaks English very well.',
  ),
  TrRule(
    'very_thanks',
    TrErrorCategory.wordChoice,
    r"\b(very\s+thanks|thanks\s+you|many\s+thank\s+you)\b",
    (m) => m[1]!.toLowerCase().startsWith('very') ? 'thanks a lot' : 'thank you',
    'Türkçedeki "çok teşekkürler" kelimesi kelimesine "very thanks" olur. İngilizcede '
        '"thanks a lot" ya da "thank you very much" denir.',
    example: 'Very thanks for your help.',
    fixed: 'Thanks a lot for your help.',
  ),
  TrRule(
    'according_to_me',
    TrErrorCategory.wordChoice,
    r"\baccording\s+to\s+(me|you|him|her|us|them)\b",
    (m) =>
        'in ${const {'me': 'my', 'you': 'your', 'him': 'his', 'her': 'her', 'us': 'our', 'them': 'their'}[m[1]!.toLowerCase()]} opinion',
    'Türkçedeki "bana göre" İngilizcede "in my opinion" olur. "According to" başkasının '
        'sözünü aktarırken kullanılır (according to the news).',
    example: 'According to me, this film is great.',
    fixed: 'In my opinion, this film is great.',
  ),
  TrRule(
    'very_like',
    TrErrorCategory.wordChoice,
    r"\b(I|you|we|they|he|she)\s+very\s+(like|love|liked|loved|likes|loves|enjoy|enjoyed|want|wanted|miss|missed)\b",
    (m) => '${m[1]} really ${m[2]}',
    'Türkçedeki "çok seviyorum" kelimesi kelimesine "very like" olur. "Very" fiili nitelemez; '
        '"I really like it" ya da "I like it very much" de.',
    example: 'I very like this song.',
    fixed: 'I really like this song.',
  ),
  TrRule(
    'too_very',
    TrErrorCategory.wordChoice,
    r"\b(is|are|was|were|'s|'re|looks|look|tastes|taste)\s+too\s+(beautiful|nice|good|delicious|lovely|interesting|happy|great|tasty|kind|cute|fun|amazing|perfect)\b(?=\s*[.!?,]|\s*$)",
    (m) => '${m[1]} very ${m[2]}',
    'Türkçedeki "çok" her zaman "too" değildir. "Too" gereğinden fazla (olumsuz) demek; '
        'beğeni için "very" kullan.',
    example: 'This cake is too delicious!',
    fixed: 'This cake is very delicious!',
  ),

  // --- spelling --------------------------------------------------------------
  TrRule(
    'capital_names',
    TrErrorCategory.spelling,
    r"\b(english|turkish|german|french|spanish|italian|arabic|russian|japanese|chinese|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|april|june|july|august|september|october|november|december|istanbul|ankara|izmir|london)\b",
    (m) => '${m[1]![0].toUpperCase()}${m[1]!.substring(1)}',
    (Match m) =>
        'Türkçede "ingilizce, pazartesi" küçük yazılabilir; İngilizcede dil, gün, ay ve şehir '
        'adları büyük harfle başlar: "${m[1]![0].toUpperCase()}${m[1]!.substring(1)}".',
    caseSensitive: true,
    example: 'I study english every day.',
    fixed: 'I study English every day.',
  ),
  TrRule(
    'lowercase_i',
    TrErrorCategory.spelling,
    r"(?<![\w'’.-])i(?=\s|'m|'ve|'ll|'d|$|[,!?])",
    (m) => 'I',
    'Türkçedeki "ben" cümle içinde küçük yazılır; İngilizcede "I" her yerde büyük harftir.',
    caseSensitive: true,
    example: 'Yesterday i was tired.',
    fixed: 'Yesterday I was tired.',
  ),
];

// ---------------------------------------------------------------------------
// Public API.

/// Finds classic Turkish-speaker mistakes in [userText].
///
/// With [expected] (the accepted answer of an exercise), rules that also
/// match the accepted answer are ignored, every error's corrected sentence
/// is [expected], and when no rule matches a word-level comparison explains
/// the difference (missing article, missing "am/is/are", word order…).
List<TrError> detectTrErrors(String userText, {String? expected}) {
  final text = userText.trim();
  if (text.isEmpty) return const [];
  final found = <(Match, TrRule)>[];
  for (final rule in trRules) {
    final m = rule.pattern.firstMatch(text);
    if (m == null || m[0]!.trim().isEmpty) continue;
    // Exercises are graded case-insensitively, so capitals are not the
    // reason an answer was wrong.
    if (expected != null && (rule.category == TrErrorCategory.spelling || rule.pattern.hasMatch(expected))) {
      continue;
    }
    // Skip a match inside one already reported (e.g. "monday" in "in monday").
    if (found.any((f) => f.$1.start <= m.start && m.end <= f.$1.end)) continue;
    found.add((m, rule));
  }
  if (found.isEmpty) return expected == null ? const [] : _diffHints(text, expected);
  final corrected = expected ?? correctTrText(text);
  return [
    for (final (m, rule) in found)
      TrError(
        ruleId: rule.id,
        category: rule.category,
        wrong: m[0]!.trim(),
        corrected: corrected,
        explanation: rule.explain(m),
      ),
  ];
}

/// [text] with every detected mistake fixed, one rule at a time.
String correctTrText(String text) {
  var out = text.trim();
  for (var round = 0; round < 12; round++) {
    String? next;
    for (final rule in trRules) {
      next = rule.apply(out);
      if (next != null && next != out) break;
      next = null;
    }
    if (next == null) break;
    out = next;
  }
  return out;
}

/// The accepted answer closest to [user], by shared words.
String closestAnswer(String user, List<String> answers) {
  final words = normalizeAnswer(user).split(' ').toSet();
  var best = answers.first;
  var bestScore = -1;
  for (final a in answers) {
    final score = normalizeAnswer(a).split(' ').where(words.contains).length;
    if (score > bestScore) {
      best = a;
      bestScore = score;
    }
  }
  return best;
}

/// Words of [expected] missing from [user], and words of [user] not in
/// [expected] (normalized, each word counted once per occurrence).
({List<String> missing, List<String> extra}) answerWordDiff(String user, String expected) {
  final u = _words(user);
  final e = _words(expected);
  final missing = [...e];
  final extra = <String>[];
  for (final w in u) {
    if (!missing.remove(w)) extra.add(w);
  }
  return (missing: missing, extra: extra);
}

List<String> _words(String s) => normalizeAnswer(s).split(' ').where((w) => w.isNotEmpty).toList();

const _articles = {'a', 'an', 'the'};
const _beForms = {
  'am',
  'is',
  'are',
  'was',
  'were',
  "i'm",
  "you're",
  "he's",
  "she's",
  "it's",
  "we're",
  "they're",
};
const _prepositions = {'to', 'in', 'on', 'at', 'for', 'of', 'with', 'from', 'by', 'about'};

List<TrError> _diffHints(String user, String expected) {
  final u = _words(user);
  final e = _words(expected);
  if (u.join(' ') == e.join(' ')) return const [];
  TrError hint(String id, TrErrorCategory c, String wrong, String why) =>
      TrError(ruleId: id, category: c, wrong: wrong, corrected: expected, explanation: why);

  final sortedU = [...u]..sort();
  final sortedE = [...e]..sort();
  if (sortedU.join(' ') == sortedE.join(' ')) {
    return [
      hint(
        'diff_word_order',
        TrErrorCategory.wordOrder,
        user.trim(),
        'Kelimeler doğru ama sırası farklı. Türkçede fiil sonda gelir; İngilizcede sıra '
            'özne + fiil + nesne: "$expected".',
      ),
    ];
  }

  final (:missing, :extra) = answerWordDiff(user, expected);
  final out = <TrError>[];
  final missingArticle = missing.where(_articles.contains);
  if (missingArticle.isNotEmpty) {
    out.add(
      hint(
        'diff_missing_article',
        TrErrorCategory.article,
        missingArticle.first,
        'Burada "${missingArticle.first}" eksik. Türkçede artikel olmadığı için kolayca unutulur; '
            'İngilizcede tekil sayılabilen isim yalnız durmaz.',
      ),
    );
  } else if (extra.any(_articles.contains)) {
    final w = extra.firstWhere(_articles.contains);
    out.add(
      hint(
        'diff_extra_article',
        TrErrorCategory.article,
        w,
        'Burada "$w" gerekmiyor. Genel anlamda konuşurken, isimlerin ve çoğulların önünde '
            'çoğu zaman artikel kullanılmaz.',
      ),
    );
  }
  final missingBe = missing.where(_beForms.contains);
  if (missingBe.isNotEmpty) {
    out.add(
      hint(
        'diff_missing_be',
        TrErrorCategory.toBe,
        missingBe.first,
        '"${missingBe.first}" eksik. Türkçede "-im, -dir" eki kelimeye yapışır; İngilizcede '
            'am/is/are ayrı bir kelime olarak yazılır.',
      ),
    );
  } else if (extra.any(_beForms.contains)) {
    final w = extra.firstWhere(_beForms.contains);
    out.add(
      hint(
        'diff_extra_be',
        TrErrorCategory.toBe,
        w,
        '"$w" fazla. Cümlede asıl fiil varsa (want, like, go…) geniş zamanda am/is/are gelmez.',
      ),
    );
  }
  bool withS(String long, String short) =>
      long != short &&
      (long == '${short}s' || long == '${short}es' || long == '${short.replaceAll(RegExp(r'y$'), '')}ies');
  final third = e.any((x) => x == 'he' || x == 'she' || x == 'it');
  for (final w in missing) {
    // The answer needs an -s the user left out.
    final short = extra.where((x) => withS(w, x));
    if (short.isNotEmpty) {
      out.add(
        hint(
          third ? 'diff_third_person' : 'diff_plural',
          third ? TrErrorCategory.thirdPerson : TrErrorCategory.plural,
          short.first,
          third
              ? 'He/she/it ile geniş zamanda fiil -s alır: "${short.first}" değil "$w".'
              : 'Burada isim çoğul olmalı: "${short.first}" değil "$w". Türkçede sayıdan sonra '
                    'isim tekil kalır, İngilizcede kalmaz.',
        ),
      );
      break;
    }
    // The user added an -s the answer does not have.
    final long = extra.where((x) => withS(x, w));
    if (long.isNotEmpty) {
      out.add(
        hint(
          third ? 'diff_third_person' : 'diff_plural',
          third ? TrErrorCategory.thirdPerson : TrErrorCategory.plural,
          long.first,
          third
              ? 'Burada fiil -s almaz: "${long.first}" değil "$w". -s yalnızca he/she/it ile geniş '
                    'zamanda, yardımcı fiil yokken gelir.'
              : 'Burada tekil kullanılmalı: "${long.first}" değil "$w". a/an ve "one" tek bir şeyi '
                    'gösterir.',
        ),
      );
      break;
    }
  }
  final missingPrep = missing.where(_prepositions.contains);
  if (missingPrep.isNotEmpty) {
    out.add(
      hint(
        'diff_missing_preposition',
        TrErrorCategory.preposition,
        missingPrep.first,
        '"${missingPrep.first}" eksik. Türkçede bu iş -e, -de, -den ekleriyle görülür; '
            'İngilizcede ayrı bir edat gerekir.',
      ),
    );
  } else if (extra.any(_prepositions.contains)) {
    final w = extra.firstWhere(_prepositions.contains);
    out.add(
      hint(
        'diff_extra_preposition',
        TrErrorCategory.preposition,
        w,
        '"$w" fazla. Türkçedeki hâl eki yüzünden edat eklemek kolay, ama bu fiil doğrudan '
            'nesne alıyor.',
      ),
    );
  }
  return out;
}
