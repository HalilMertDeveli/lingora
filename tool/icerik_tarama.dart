// İçerik tarama: ders/kurs içeriğindeki İngilizce cümleleri çıkarır ve olası
// yazım, dil bilgisi ve noktalama sorunlarını işaretler. YALNIZCA RAPOR ÜRETİR:
// hiçbir içerik dosyasını değiştirmez.
//
//   dart run tool/icerik_tarama.dart                 # yerel kurallar
//   dart run tool/icerik_tarama.dart --ai            # + YZ kontrolü (Anthropic API)
//   dart run tool/icerik_tarama.dart --ai --ai-limit 120 --limit 400
//
// Çıktı: docs/icerik-tarama-raporu.md (--out ile değiştirilebilir).
//
// Saf kural fonksiyonları (checkSentence, checkFragment, articleFor, ...) bu
// dosyadan test/icerik_tarama_test.dart tarafından içe aktarılır.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ---------------------------------------------------------------------------
// Veri modeli
// ---------------------------------------------------------------------------

/// Güven düzeyi. Sıralama: high < medium < low.
enum Confidence { high, medium, low }

const confidenceTr = {Confidence.high: 'yüksek', Confidence.medium: 'orta', Confidence.low: 'düşük'};

/// Tek bir kural bulgusu (konumdan bağımsız).
class Issue {
  Issue(this.rule, this.problem, this.suggestion, this.confidence, [this.offset = 0]);
  final String rule;
  final String problem;
  final String suggestion;
  final Confidence confidence;
  final int offset;
  @override
  String toString() => '$rule@$offset: $problem → $suggestion (${confidence.name})';
}

/// İçerikten çıkarılmış bir İngilizce metin parçası.
class Unit {
  Unit(this.file, this.ident, this.key, this.text, this.kind);
  final String file;
  final String ident;
  final String key; // alan adı (text, question, answers, ...)
  final String text;
  final UnitKind kind;
  int copies = 1;
}

/// sentence: tam cümle(ler), tüm kurallar. fragment: cevap/şık/kısa öbek;
/// büyük harf ve bitiş noktalaması kuralları uygulanmaz.
enum UnitKind { sentence, fragment }

class Finding {
  Finding(this.unit, this.issue, this.source);
  final Unit unit;
  final Issue issue;
  final String source; // 'kural' | 'YZ'
}

const ruleLabels = {
  'yazim': 'Olası yazım hatası (sözlük)',
  'bilinen_yazim': 'Bilinen yazım hatası',
  'tekrar_kelime': 'Kelime tekrarı',
  'cift_bosluk': 'Çift boşluk',
  'bosluk_once': 'Noktalamadan önce boşluk',
  'bosluk_sonra': 'Noktalamadan sonra boşluk yok',
  'cift_noktalama': 'Yinelenen noktalama',
  'kucuk_baslangic': 'Cümle küçük harfle başlıyor',
  'kucuk_i': 'Küçük "i" zamiri',
  'a_an': 'a/an uyumsuzluğu',
  'denge': 'Dengesiz tırnak/parantez',
  'bitis': 'Sonda noktalama yok',
  'karisiklik': 'Sık karıştırılan yapı',
  'yz': 'YZ bulgusu',
};

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

final _blankRe = RegExp(r'\(\d+\)\s*-{2,}|_{2,}|-{3,}|…{2,}');
const blankWord = 'BLANK';

/// Boşlukları (___ / ----) tek bir kelimeye çevirir; [fill] verilirse ve tek
/// boşluk varsa onunla doldurur.
String fillBlanks(String s, [String? fill]) {
  // "---- ." biçimindeki boşluk-noktalama arası boşluk biçim gereğidir
  s = s.replaceAllMapped(RegExp('(${_blankRe.pattern})\\s+(?=[.,;:!?])'), (m) => m.group(1)!);
  final n = _blankRe.allMatches(s).length;
  if (n == 1 && fill != null && fill.trim().isNotEmpty) {
    // Cümle başındaki boşluğa gelen cevabın ilk harfi büyütülür
    final m = _blankRe.firstMatch(s)!;
    var f = fill.trim();
    if (RegExp(r'(^|[.!?]\s+|\n)["“‘]?\s*$').hasMatch(s.substring(0, m.start))) {
      f = f[0].toUpperCase() + f.substring(1);
    }
    return s.replaceRange(m.start, m.end, f);
  }
  return s.replaceAll(_blankRe, blankWord);
}

final _turkishLetters = RegExp(r'[çğışöüÇĞŞÖÜİı]');
const _turkishWords = {
  've',
  'bir',
  'bu',
  'ile',
  'için',
  'icin',
  'da',
  'de',
  'mi',
  'mı',
  'mu',
  'mü',
  'ne',
  'çok',
  'ama',
  'gibi',
  'daha',
  'var',
  'yok',
  'olan',
  'değil',
  'ben',
  'sen',
  'biz',
  'siz',
  'onlar',
  'şu',
  'en',
  'hangi',
  'hangisi',
  'neden',
  'nasıl',
  'cümle',
  'doğru',
  'yanlış',
  'kelime',
  'olarak',
  'veya',
  'ya',
  'ki',
  'diye',
  'sonra',
  'önce',
  'kadar',
  'göre',
  'şık',
  'cevap',
  'metin',
  'metne',
  'bile',
  'kez',
  'hiç',
  'şey',
  'sadece',
  'bütün',
  'tüm',
  'çünkü',
  'eğer',
  'ise',
  'yani',
  'ancak',
  'artık',
  'hep',
  'dakika',
  'saat',
  'gün',
  'yıl',
  'hafta',
  'zaman',
  'iki',
  'üç',
  'dört',
  'beş',
  'altı',
  'yedi',
  'sekiz',
  'dokuz',
  'yirmi',
  'otuz',
  'kırk',
  'elli',
  'yüz',
  'fark',
  'burada',
  'orada',
  'yasak',
  'yemek',
  'evet',
  'hayır',
  'tamam',
  'lütfen',
  'merhaba',
};

const _englishFunctionWords = {
  'the',
  'a',
  'an',
  'is',
  'are',
  'was',
  'were',
  'to',
  'of',
  'and',
  'in',
  'on',
  'at',
  'i',
  'you',
  'he',
  'she',
  'it',
  'we',
  'they',
  'my',
  'your',
  'this',
  'that',
  'for',
  'with',
  'be',
  'have',
  'has',
  'do',
  'does',
  'did',
  'not',
  'can',
  'will',
  'what',
  'where',
  'when',
  'how',
  'who',
  'please',
  'from',
  'by',
  'or',
  'but',
  'me',
  'his',
  'her',
  'our',
  'their',
  'there',
  'here',
  'so',
};
final _turkishSuffixWord = RegExp(
  r"(['’](in|ın|un|ün|nin|nın|nun|nün|e|a|ye|ya|de|da|te|ta|den|dan|ten|tan|i|ı|u|ü|yi|yı|yu|yü|le|la|ler|lar|deki|daki|teki|taki|dir|dır)$)|"
  r'((sinde|sında|ında|inde|ndeki|ndaki|leri|ları|mek|mak|iyor|ıyor|uyor|üyor|miş|mış|dır|dir|tır|tir|meli|malı|ecek|acak|abilir|ebilir|ilir|ılır|amaz|emez|yaz|maz|mez|mıştı|mişti)$)',
);

/// Metin büyük olasılıkla Türkçe mi? Tırnak içindeki (alıntılanmış İngilizce)
/// bölümler çıkarıldıktan sonra Türkçe harfli/ekli/işlev kelimelerinin oranına
/// ve İngilizce işlev kelimelerinin yokluğuna bakar.
bool isTurkish(String s) {
  // Tırnak içi alıntıları çıkar ("…" “…” ‘…’ ve kelime sınırındaki '…')
  var rest = s.replaceAll(
    RegExp(
      r'"[^"]*"|“[^”]*”|‘[^’]*’|(?<![\p{L}])'
      "'"
      r"[^']*'(?![\p{L}])",
      unicode: true,
    ),
    ' ',
  );
  if (rest.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 2) rest = s;
  final words = rest.split(RegExp(r'\s+')).where((w) => RegExp(r'\p{L}', unicode: true).hasMatch(w)).toList();
  if (words.isEmpty) return false;
  var tr = 0, en = 0;
  for (final w in words) {
    final bare = w.replaceAll(RegExp(r"[^\p{L}'’]", unicode: true), '');
    final lower = bare.toLowerCase();
    if (_englishFunctionWords.contains(lower)) en++;
    if (_turkishSuffixWord.hasMatch(lower) && RegExp(r"['’]").hasMatch(lower)) {
      tr++; // Selin'in, İzmir'de
      continue;
    }
    // İngilizce cümlede Türkçe özel isim olabilir (Kadıköy)
    if (_turkishLetters.hasMatch(w) && RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(bare)) continue;
    if (_turkishLetters.hasMatch(w) ||
        _turkishWords.contains(lower) ||
        (lower.length >= 5 && _turkishSuffixWord.hasMatch(lower)))
      tr++;
  }
  if (tr / words.length >= 0.25) return true;
  // Hiç İngilizce işlev kelimesi yok ama Türkçe iz var
  return words.length >= 3 && tr >= 1 && en == 0;
}

/// Kod benzeri metin (yazılımcı dersleri): noktalama-boşluk kuralları atlanır.
bool isCodeLike(String s) =>
    s.contains('`') ||
    s.contains('=>') ||
    s.contains('()') ||
    s.contains('{') ||
    s.contains('http') ||
    s.contains('../') ||
    s.contains('/etc/') ||
    RegExp(r'\?\w+=|\s[?!]\s+[a-z]|\$\w|\w\(\)|<\w+>').hasMatch(s) ||
    RegExp(r'\b[a-z]+[A-Z][a-zA-Z]*\b').hasMatch(s) ||
    RegExp(r'\b\w+\.(dart|js|ts|json|yaml|md|com|org|io|txt|png|py|html|css)\b').hasMatch(s);

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

/// Uzun metinlerde sorunun çevresini kırpar.
String snippetAround(String s, int offset, {int width = 140}) {
  final flat = s.replaceAll(RegExp(r'\s*\n\s*'), ' / ');
  if (flat.length <= width) return flat;
  // offset düz metinde biraz kayabilir; yaklaşık yeterli.
  final o = min(max(0, offset), flat.length);
  var start = max(0, o - width ~/ 2);
  var end = min(flat.length, start + width);
  start = max(0, end - width);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}${end < flat.length ? '…' : ''}';
}

// ---------------------------------------------------------------------------
// a / an
// ---------------------------------------------------------------------------

const _anConsonantSound = {
  'hour',
  'hours',
  'hourly',
  'honest',
  'honestly',
  'honesty',
  'honour',
  'honor',
  'honours',
  'honors',
  'honourable',
  'honorable',
  'honorary',
  'heir',
  'heiress',
  'heirloom',
  'herb',
  'herbs',
};
const _letterNameVowel = 'AEFHILMNORSX'; // harf adı ünlüyle başlayanlar (an FBI, an MP3)
const _acronymWords = {
  'NASA',
  'NATO',
  'UNESCO',
  'UNICEF',
  'OPEC',
  'AIDS',
  'LASER',
  'RADAR',
  'SCUBA',
  'ASAP',
  'OK',
};

/// Kelimenin önüne gelmesi gereken belirsiz tanımlık: 'a', 'an' ya da
/// belirsizse null.
String? articleFor(String word) {
  final w0 = word.replaceAll(RegExp(r"^[^A-Za-z0-9]+"), '');
  if (w0.isEmpty) return null;
  if (RegExp(r'^\d').hasMatch(w0)) {
    // an 8, an 11, an 18, an 80...
    if (RegExp(r'^(8|11|18)(\D|$)').hasMatch(w0) || RegExp(r'^8\d').hasMatch(w0)) return 'an';
    return 'a';
  }
  final letters = w0.replaceAll(RegExp(r'[^A-Za-z].*$'), '');
  if (letters.isEmpty) return null;
  // Kısaltmalar: harf harf okunur (an MP3, a UFO) — NASA gibi okunanlar hariç
  if (letters.length >= 2 && letters == letters.toUpperCase()) {
    // Harf harf okunanlar: kısa (FBI, MP3, USB) ya da ünlüsüz (HTML). Kelime
    // gibi okunanlar (NASA, REST, JSON) belirsiz sayılır.
    if (_acronymWords.contains(letters)) return null;
    if (letters.length <= 3 || !RegExp(r'[AEIOU]').hasMatch(letters)) {
      return _letterNameVowel.contains(letters[0]) ? 'an' : 'a';
    }
    return null;
  }
  final w = w0.toLowerCase();
  if (w.length == 1) return null; // tek harf: belirsiz
  if (_anConsonantSound.contains(letters.toLowerCase()) ||
      RegExp(r'^(hour|honest|honou?r|heir)').hasMatch(w)) {
    return 'an';
  }
  if (RegExp(
    r'^(one\b|one-|once|eu|ewe|uni(?![mnd])|unan|use|usu|usa|uti|ura|ure|uri|uro|ubiq|ukul|ufo|ukr|uga|ucat|ewe|uvu)',
  ).hasMatch(w)) {
    return 'a';
  }
  if (w == 'one' || w.startsWith('one-') || w == 'u-turn' || w.startsWith('u-')) return 'a';
  if (RegExp(r'^[aeiou]').hasMatch(w)) return 'an';
  if (w.startsWith('x-')) return 'an'; // an X-ray
  return 'a';
}

// ---------------------------------------------------------------------------
// Kurallar
// ---------------------------------------------------------------------------

const _repeatOk = {
  'that',
  'had',
  'very',
  'bye',
  'no',
  'ha',
  'knock',
  'hip',
  'so',
  'well',
  'blah',
  'go',
  'yes',
  'tick',
  'chop',
  'hurry',
  'more',
  'again',
  'round',
  'over',
  'on',
  'far',
  'is',
  'blank',
};

const _numberWords = {
  'zero',
  'oh',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'double',
};

const _abbrevBeforeDot = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'st',
  'prof',
  'jr',
  'sr',
  'vs',
  'etc',
  'e.g',
  'i.e',
  'a.m',
  'p.m',
  'no',
  'inc',
  'ltd',
  'co',
  'u.s',
  'u.k',
  'mt',
  'approx',
  'fig',
  'cf',
  'al',
  'ca',
  'ave',
  'dept',
  'min',
  'max',
  'p',
  'pp',
  'vol',
  'ch',
  'sq',
  'km',
  'kg',
  'cm',
};

const _knownMisspellings = {
  'untill': 'until',
  'recieve': 'receive',
  'recieved': 'received',
  'beleive': 'believe',
  'seperate': 'separate',
  'definately': 'definitely',
  'occured': 'occurred',
  'wich': 'which',
  'thier': 'their',
  'becuase': 'because',
  'accomodate': 'accommodate',
  'accomodation': 'accommodation',
  'adress': 'address',
  'tommorow': 'tomorrow',
  'tomorow': 'tomorrow',
  'goverment': 'government',
  'enviroment': 'environment',
  'wierd': 'weird',
  'freind': 'friend',
  'begining': 'beginning',
  'finaly': 'finally',
  'realy': 'really',
  'sucess': 'success',
  'neccessary': 'necessary',
  'necesary': 'necessary',
  'occurence': 'occurrence',
  'existance': 'existence',
  'independant': 'independent',
  'calender': 'calendar',
  'arguement': 'argument',
  'publically': 'publicly',
  'truely': 'truly',
  'whith': 'with',
  'teh': 'the',
  'hte': 'the',
  'adn': 'and',
  'waht': 'what',
  'taht': 'that',
  'alot': 'a lot',
  'acheive': 'achieve',
  'acheived': 'achieved',
  'beatiful': 'beautiful',
  'buisness': 'business',
  'comming': 'coming',
  'commited': 'committed',
  'concious': 'conscious',
  'embarass': 'embarrass',
  'enviromental': 'environmental',
  'excercise': 'exercise',
  'familar': 'familiar',
  'foriegn': 'foreign',
  'gaurd': 'guard',
  'grammer': 'grammar',
  'happend': 'happened',
  'immediatly': 'immediately',
  'knowlege': 'knowledge',
  'libary': 'library',
  'noticable': 'noticeable',
  'occassion': 'occasion',
  'persistant': 'persistent',
  'posession': 'possession',
  'prefered': 'preferred',
  'pronounciation': 'pronunciation',
  'reccomend': 'recommend',
  'recomend': 'recommend',
  'refered': 'referred',
  'relevent': 'relevant',
  'remeber': 'remember',
  'resturant': 'restaurant',
  'rythm': 'rhythm',
  'shedule': 'schedule',
  'sieze': 'seize',
  'similiar': 'similar',
  'speach': 'speech',
  'stoped': 'stopped',
  'suprise': 'surprise',
  'suprised': 'surprised',
  'temperture': 'temperature',
  'tounge': 'tongue',
  'truley': 'truly',
  'unfortunatly': 'unfortunately',
  'usefull': 'useful',
  'writting': 'writing',
  'wether': 'whether',
  'wheather': 'weather',
  'thru': 'through',
  'responsability': 'responsibility',
  'developement': 'development',
  'enviorment': 'environment',
  'beggining': 'beginning',
  'diffrent': 'different',
  'intresting': 'interesting',
  'interupt': 'interrupt',
  'medecine': 'medicine',
  'mispell': 'misspell',
  'neighbour hood': 'neighbourhood',
  'peice': 'piece',
  'plesure': 'pleasure',
  'procede': 'proceed',
  'questionaire': 'questionnaire',
  'recieve d': 'received',
  'sentance': 'sentence',
  'shoud': 'should',
  'woud': 'would',
  'coud': 'could',
  'becasue': 'because',
};

const _comparatives =
    'more|less|fewer|better|worse|rather|bigger|smaller|faster|slower|older|younger|taller|cheaper|easier|harder|larger|higher|lower|longer|stronger|warmer|colder|happier|safer|healthier|busier|quieter|louder|richer|poorer|wider|heavier|lighter|cleaner|nicer';

/// Her metin türü için ortak kurallar (yazım/sözlük kuralı hariç).
List<Issue> checkCommon(String s, {bool code = false}) {
  final out = <Issue>[];
  // Kelime tekrarı
  for (final m in RegExp(
    r"(?<![\p{L}'’])(\p{L}[\p{L}'’]*)\s+\1(?![\p{L}])",
    caseSensitive: false,
    unicode: true,
  ).allMatches(s)) {
    final w = m.group(1)!.toLowerCase();
    if (_repeatOk.contains(w) || _numberWords.contains(w)) continue;
    // Özel isim tekrarı (Santorio Santorio, River River) bilerek olabilir
    final parts = m.group(0)!.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts[0] == parts[1] && RegExp(r'^\p{Lu}', unicode: true).hasMatch(parts[0]))
      continue;
    // "do you know who she is? She is" gibi büyük harfle yeni cümle değil, aynı satır
    if (s.substring(m.start, m.end).contains('\n')) continue;
    out.add(
      Issue('tekrar_kelime', 'Kelime tekrarı: “${m.group(0)}”', '“${m.group(1)}”', Confidence.high, m.start),
    );
  }
  // Çift boşluk (satır içi)
  for (final m in RegExp(r'\S( {2,})\S').allMatches(s)) {
    out.add(Issue('cift_bosluk', 'Çift boşluk', 'Tek boşluk bırak', Confidence.high, m.start));
    break;
  }
  // Yinelenen noktalama
  for (final m in RegExp(
    r'(?<![./])\.\.(?![./])|,,|;;|::|,\.|(?<=[a-z]{3})\.,(?!\d)|\?\.|!\.|,;|;,|\s,\s*,',
  ).allMatches(s)) {
    if (code) break;
    if (m.group(0) == '.,') {
      // Kısaltma sonrası virgül (Bros., D.C., Jr.) normaldir
      final w = RegExp(r'([A-Za-z.]+)$').firstMatch(s.substring(0, m.start))?.group(1) ?? '';
      if (_abbrevBeforeDot.contains(w.toLowerCase()) || RegExp(r'^[A-Z]').hasMatch(w) && w.length <= 5)
        continue;
    }
    out.add(
      Issue(
        'cift_noktalama',
        'Yinelenen noktalama: “${m.group(0)!.trim()}”',
        'Tek işaret kullan',
        Confidence.high,
        m.start,
      ),
    );
  }
  // Bilinen karışıklıklar
  final confusions = <RegExp, List<String>>{
    RegExp(r'\b(could|should|would|must|might)\s+of\b', caseSensitive: false): ['“%” → “have”', 'high'],
    RegExp(r"\bits'(?!s)", caseSensitive: false): ["“its'” diye bir biçim yok", 'high'],
    RegExp(r'\byour\s+welcome\b', caseSensitive: false): ["“your welcome” → “you're welcome”", 'high'],
    RegExp(r'\b(' + _comparatives + r')\s+then\b(?!\s*,)', caseSensitive: false): [
      'Karşılaştırmada “then” değil “than”',
      'high',
    ],
    RegExp(r'\bmore\s+[a-z]+\s+then\b(?!\s*,)'): ['Karşılaştırmada “then” değil “than”', 'medium'],
    RegExp(r"\b[Ii]ts\s+(a|an|the|not|been|going|ok|okay|raining|my|your)\b"): [
      "“its” (iyelik) değil “it's” olmalı",
      'medium',
    ],
    RegExp(r"\bit's\s+(own|own\b|colou?r|name|tail|size|shape|way through)\b", caseSensitive: false): [
      "İyelikte “it's” değil “its”",
      'medium',
    ],
    RegExp(
      r'(?:^|[.!?]\s+|,\s+|\b(?:and|but|so|because|if|when|then)\s+)(?:you|we|they|You|We|They)\s+was\b',
    ): [
      'Özne-fiil uyumu: “was” değil “were”',
      'medium',
    ],
    RegExp(
      r'\b(a|an)\s+(few\s+)?(informations|advices|furnitures|equipments|homeworks|luggages|knowledges)\b',
      caseSensitive: false,
    ): [
      'Sayılamayan isim çoğul/tanımlıkla',
      'high',
    ],
    RegExp(
      r'\b(informations|advices|furnitures|equipments|homeworks|luggages|knowledges|researches\s+(?:shows|is))\b',
    ): [
      'Sayılamayan isim çoğul yapılmış',
      'medium',
    ],
    RegExp(r'\b(?:he|she|it)\s+don\x27t\b', caseSensitive: false): ["“don't” değil “doesn't”", 'high'],
    RegExp(
      r'\bdid(?:n\x27t| not)?\s+(went|saw|came|ate|took|gave|bought|made|wrote|said|told|got|had)\b',
      caseSensitive: false,
    ): [
      '“did”den sonra fiil yalın olmalı',
      'high',
    ],
    RegExp(
      r'\b(?:can|could|will|would|should|must|may|might)\s+(?:not\s+)?(?:to\s+)?(went|goes|saw|came|ate|took|wrote|did|does|has|was|were|is)\b',
    ): [
      'Kipten sonra fiil yalın olmalı',
      'medium',
    ],
    RegExp(
      r'\b(?:more|most)\s+(better|worse|bigger|easier|cheaper|faster|best|worst|biggest|easiest)\b',
      caseSensitive: false,
    ): [
      'Çift karşılaştırma',
      'high',
    ],
  };
  confusions.forEach((re, info) {
    for (final m in re.allMatches(s)) {
      final c = info[1] == 'high'
          ? Confidence.high
          : info[1] == 'medium'
          ? Confidence.medium
          : Confidence.low;
      out.add(
        Issue(
          'karisiklik',
          'Sık karıştırılan yapı: “${m.group(0)}”',
          info[0].replaceAll('%', m.group(0)!),
          c,
          m.start,
        ),
      );
    }
  });
  // Bilinen yazım hataları
  for (final m in RegExp(r"[A-Za-z]+").allMatches(s)) {
    final w = m.group(0)!.toLowerCase();
    final fix = _knownMisspellings[w];
    if (fix != null) {
      out.add(Issue('bilinen_yazim', 'Yazım hatası: “${m.group(0)}”', '“$fix”', Confidence.high, m.start));
    }
  }
  // a / an
  for (final m in RegExp(
    r"(?<![\p{L}\p{N}_/'’\x22“-])(a|an|A|An)\s+([A-Za-z0-9][\w'’-]*)(?![\p{L}])",
    unicode: true,
  ).allMatches(s)) {
    final art = m.group(1)!;
    final next = m.group(2)!;
    final before = s.substring(0, m.start);
    // Büyük harfli A cümle ortasında (Plan A, Vitamin A) → atla
    if (art.startsWith('A') && before.trim().isNotEmpty && !RegExp(r'[.!?:\n"“]\s*$').hasMatch(before))
      continue;
    if (next == blankWord || next.toLowerCase() == 'blank') continue;
    // "a/an", "a or an", tırnak içinde tanımlık anlatımı
    if (RegExp(r'^(or|and|vs|/)$', caseSensitive: false).hasMatch(next)) continue;
    final after = s.substring(m.end);
    if (after.startsWith('/') || before.endsWith('/') || before.endsWith('‘') || before.endsWith("'"))
      continue;
    if (RegExp(
      r'(letter|option|vitamin|grade|type|plan|part|section|exercise|row|column|point|class|level|band)\s*$',
      caseSensitive: false,
    ).hasMatch(before))
      continue;
    // Tek harf / sayı-harf (a B, an A+)
    if (next.length == 1) continue;
    final want = articleFor(next);
    if (want == null || want == art.toLowerCase()) continue;
    final lowerNext = next.toLowerCase();
    var conf = Confidence.high;
    if (next != lowerNext ||
        RegExp(r'^\d').hasMatch(next) ||
        RegExp(r'^(u|eu|one|h)', caseSensitive: false).hasMatch(next)) {
      conf = Confidence.medium;
    }
    final fixed = art[0] == 'A' ? (want == 'an' ? 'An' : 'A') : want;
    out.add(Issue('a_an', '“${m.group(0)}”: tanımlık sesle uyuşmuyor', '“$fixed $next”', conf, m.start));
  }
  if (!code) {
    // Noktalamadan önce boşluk ("word ," / "word .")
    for (final m in RegExp(
      r'[A-Za-z0-9\)”"]( +)([,;:]|[.!?](?!\.)(?=\s*$|\s+["“A-Z]))(?=\s|$)',
    ).allMatches(s)) {
      if (s.substring(0, m.start + 1).endsWith(blankWord)) continue; // "___ ." boşluk biçimi
      out.add(
        Issue(
          'bosluk_once',
          'Noktalamadan önce boşluk: “${m.group(0)}”',
          '“${s.substring(m.start, m.start + 1)}${m.group(2)}”',
          Confidence.high,
          m.start,
        ),
      );
    }
    // Noktalamadan sonra boşluk yok ("word,word" / "end.Next")
    for (final m in RegExp(r'([a-z]{2,})([,;!?])([A-Za-z]{2,}|I\b)').allMatches(s)) {
      out.add(
        Issue(
          'bosluk_sonra',
          'Noktalamadan sonra boşluk yok: “${m.group(0)}”',
          '“${m.group(1)}${m.group(2)} ${m.group(3)}”',
          Confidence.high,
          m.start,
        ),
      );
    }
    for (final m in RegExp(r'([a-z]{2,})\.([A-Z][a-z]+)').allMatches(s)) {
      if (_abbrevBeforeDot.contains(m.group(1)!.toLowerCase())) continue;
      out.add(
        Issue(
          'bosluk_sonra',
          'Noktadan sonra boşluk yok: “${m.group(0)}”',
          '“${m.group(1)}. ${m.group(2)}”',
          Confidence.medium,
          m.start,
        ),
      );
    }
    // Küçük "i" zamiri
    for (final m in RegExp(r"(?<=^|[\s“\x22(])i(?=\s+[a-z]|['’](m|ve|ll|d)\b)").allMatches(s)) {
      final pre = s.substring(0, m.start);
      if (RegExp(r'\b(for|if|let|var|int|while)\s*\(?\s*$').hasMatch(pre)) continue;
      out.add(Issue('kucuk_i', 'Zamir “i” küçük yazılmış', '“I”', Confidence.high, m.start));
    }
  }
  return out;
}

/// Tam cümle(ler) için kurallar: ortak kurallar + cümle başı büyük harf +
/// cümle sonu sonrası küçük harf + tırnak/parantez dengesi.
List<Issue> checkSentence(String s, {bool code = false, bool expectCapital = true}) {
  final out = checkCommon(s, code: code);
  final t = s.trimLeft();
  // Küçük harfle başlayıp noktalamasız biten tek satır bir öbektir (the man
  // who spoke to you), cümle değil.
  final phrase = !endsWithTerminal(t) && !t.contains('\n') && RegExp(r'^[^A-Za-z]*[a-z]').hasMatch(t);
  if (expectCapital && !code && !phrase && t.isNotEmpty) {
    final first = RegExp(r'[\p{L}]', unicode: true).firstMatch(t);
    final lead = first == null ? '' : t.substring(0, first.start);
    if (first != null &&
        RegExp(r'[a-z]').hasMatch(t[first.start]) &&
        !RegExp(r'[\d…]|\.\.\.').hasMatch(lead) &&
        !RegExp(r'^(iPhone|iPad|iOS|eBay|e\.g\.|i\.e\.|etc\b|vs\b|mRNA|pH\b|km\b|kg\b|[a-z]+:)')
            .hasMatch(t.substring(first.start))) {
      out.add(
        Issue('kucuk_baslangic', 'Cümle küçük harfle başlıyor', 'İlk harfi büyüt', Confidence.medium, 0),
      );
    }
  }
  if (!code) {
    // Cümle sonundan sonra küçük harf: "home. then we"
    for (final m in RegExp(r"([A-Za-z.]+)([.!?])\s+([a-z][a-z]+)").allMatches(s)) {
      final w = m.group(1)!.toLowerCase();
      if (m.group(2) == '.' &&
          (_abbrevBeforeDot.contains(w) ||
              _abbrevBeforeDot.contains(w.replaceAll(RegExp(r'\.$'), '')) ||
              w.contains('.')))
        continue;
      if (w.length == 1) continue; // baş harfler
      out.add(
        Issue(
          'kucuk_baslangic',
          'Cümle sonundan sonra küçük harf: “${m.group(0)}”',
          'Yeni cümleyi büyük harfle başlat',
          m.group(2) == '.' ? Confidence.medium : Confidence.low,
          m.start,
        ),
      );
    }
    // Parantez dengesi
    final open = '('.allMatches(s).length, close = ')'.allMatches(s).length;
    final listMarkers = RegExp(r'(^|\s)([a-eA-E1-9]|[ivx]+)\)').allMatches(s).length;
    if (open != close && open != close - listMarkers) {
      out.add(
        Issue(
          'denge',
          'Açılan/kapanan parantez sayısı uyuşmuyor ($open/$close)',
          'Parantezleri kontrol et',
          Confidence.medium,
          s.indexOf(open > close ? '(' : ')'),
        ),
      );
    }
    final dq = '"'.allMatches(s).length;
    final lq = '“'.allMatches(s).length, rq = '”'.allMatches(s).length;
    if (dq.isOdd) {
      out.add(
        Issue(
          'denge',
          'Çift tırnak sayısı tek ($dq)',
          'Eksik tırnağı ekle',
          s.contains('\n') ? Confidence.low : Confidence.medium,
          s.indexOf('"'),
        ),
      );
    } else if (lq != rq) {
      out.add(
        Issue(
          'denge',
          'Açılan/kapanan tırnak sayısı uyuşmuyor ($lq/$rq)',
          'Eksik tırnağı ekle',
          s.contains('\n') ? Confidence.low : Confidence.medium,
          max(0, s.indexOf(lq > rq ? '“' : '”')),
        ),
      );
    }
  }
  return out;
}

/// Cevap/şık/kısa öbek: yalnızca ortak kurallar.
List<Issue> checkFragment(String s, {bool code = false}) => checkCommon(s, code: code);

/// Metni cümlelere böler (kısaltmaları korur). Yeni satırlar her zaman böler.
List<String> splitSentences(String s) {
  final out = <String>[];
  for (final line in s.split(RegExp(r'\n+'))) {
    var start = 0;
    final re = RegExp(r'[.!?…]["”’)]*\s+(?=["“‘(]?[A-Z0-9])');
    for (final m in re.allMatches(line)) {
      final before = line.substring(start, m.start);
      final lastWord = RegExp(r"([A-Za-z.]+)$").firstMatch(before)?.group(1)?.toLowerCase() ?? '';
      if (line[m.start] == '.' && (_abbrevBeforeDot.contains(lastWord) || (lastWord.length == 1))) continue;
      out.add(line.substring(start, m.end).trim());
      start = m.end;
    }
    final rest = line.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest);
  }
  return out.where((x) => x.isNotEmpty).toList();
}

/// Cümle sonu noktalaması var mı?
bool endsWithTerminal(String s) => RegExp(r'''[.!?…:;]["”’')\]*]*$|\.\.\.$''').hasMatch(s.trimRight());

// ---------------------------------------------------------------------------
// Sözlük ve yazım denetimi
// ---------------------------------------------------------------------------

final _wordRe = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");

/// Kelime sıklığı + kelime listeleri üzerinden olası yazım hatası arar.
class SpellModel {
  final Map<String, int> freq = {};
  final Set<String> vocab = {};
  final Set<String> allow = {..._builtinAllow};

  void addText(String s) {
    for (final m in _wordRe.allMatches(s)) {
      for (final part in m.group(0)!.toLowerCase().replaceAll('’', "'").split("'")) {
        if (part.isEmpty) continue;
        freq[part] = (freq[part] ?? 0) + 1;
      }
    }
  }

  void addVocab(String s) {
    for (final m in _wordRe.allMatches(s)) {
      vocab.add(m.group(0)!.toLowerCase().replaceAll('’', "'").split("'").first);
    }
  }

  int f(String w) => freq[w] ?? 0;

  bool _base(String w) => w.length >= 2 && (f(w) >= 3 || vocab.contains(w) || allow.contains(w));

  /// Yaygın eklerle bilinen bir köke indirgenebiliyor mu?
  bool derivable(String w) {
    const suffixes = [
      's',
      'es',
      'ed',
      'd',
      'ing',
      'ly',
      'er',
      'ers',
      'est',
      'ness',
      'ment',
      'ments',
      'ful',
      'less',
      'able',
      'ible',
      'ion',
      'ions',
      'ation',
      'ations',
      'al',
      'ally',
      'ity',
      'ize',
      'ise',
      'ized',
      'ised',
      'ous',
      'ive',
      'ist',
      'ists',
      'ism',
      'y',
      'ish',
      'en',
      'ship',
      'hood',
      'ward',
      'wards',
      'like',
      'ence',
      'ance',
      'ent',
      'ant',
      'ic',
      'ical',
      'or',
      'ors',
      'ee',
      'ery',
      'age',
      'ies',
      'ied',
      'ier',
      'iest',
      'ily',
      'iness',
    ];
    for (final suf in suffixes) {
      if (!w.endsWith(suf) || w.length - suf.length < 3) continue;
      final stem = w.substring(0, w.length - suf.length);
      if (_base(stem) || _base('${stem}e') || _base('${stem}y')) return true;
      if (stem.length >= 3 &&
          stem[stem.length - 1] == stem[stem.length - 2] &&
          _base(stem.substring(0, stem.length - 1)))
        return true;
      if (suf.startsWith('i') && _base('${stem}y')) return true;
    }
    const prefixes = [
      'un',
      're',
      'dis',
      'in',
      'im',
      'il',
      'ir',
      'non',
      'over',
      'under',
      'out',
      'pre',
      'mis',
      'co',
      'anti',
      'sub',
      'inter',
      'super',
      'self',
      'post',
      'semi',
      'multi',
      'micro',
      'trans',
      'up',
      'down',
      'counter',
      'ex',
      'de',
      'bio',
      'eco',
      'tele',
      'auto',
    ];
    for (final p in prefixes) {
      if (w.startsWith(p) && w.length - p.length >= 3) {
        final rest = w.substring(p.length);
        if (_base(rest) || derivableSimple(rest)) return true;
      }
    }
    // Bileşik kelime: iki bilinen parçadan oluşuyor (bookshelf, sunlight)
    for (var i = 3; i <= w.length - 3; i++) {
      if (_base(w.substring(0, i)) &&
          f(w.substring(0, i)) >= 3 &&
          _base(w.substring(i)) &&
          f(w.substring(i)) >= 3)
        return true;
    }
    return false;
  }

  bool derivableSimple(String w) {
    for (final suf in const ['s', 'es', 'ed', 'd', 'ing', 'ly', 'er', 'able', 'ful']) {
      if (w.endsWith(suf) && w.length - suf.length >= 3) {
        final stem = w.substring(0, w.length - suf.length);
        if (_base(stem) || _base('${stem}e')) return true;
      }
    }
    return false;
  }

  bool known(String w) => _base(w) || derivable(w);

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz';

  /// Tek düzenleme (silme, ekleme, değiştirme, yer değiştirme) uzaklığındaki
  /// kelimeler.
  static Set<String> edits1(String w) {
    final out = <String>{};
    for (var i = 0; i <= w.length; i++) {
      final a = w.substring(0, i), b = w.substring(i);
      if (b.isNotEmpty) out.add(a + b.substring(1));
      if (b.length > 1) out.add(a + b[1] + b[0] + b.substring(2));
      for (final c in _alphabet.split('')) {
        if (b.isNotEmpty) out.add(a + c + b.substring(1));
        out.add(a + c + b);
      }
    }
    out.remove(w);
    return out;
  }

  /// İngiliz/Amerikan yazım farkı ya da çekim farkı mı? (bunlar hata değil)
  static bool variantPair(String w, String c) {
    String norm(String x) => x
        .replaceAll('our', 'or')
        .replaceAll(RegExp(r'([^aeiou])re$'), r'$1er')
        .replaceAll(RegExp(r'([^aeiou])res$'), r'$1ers')
        .replaceAll('ise', 'ize')
        .replaceAll('isa', 'iza')
        .replaceAll('yse', 'yze')
        .replaceAll('ence', 'ense')
        .replaceAllMapped(RegExp(r'll(ed|ing|er|ers|ation)$'), (m) => 'l${m[1]}')
        .replaceAll('ae', 'e')
        .replaceAll('oe', 'e')
        .replaceAll('grey', 'gray')
        .replaceAll('ogue', 'og');
    if (norm(w) == norm(c)) return true;
    // Çekim: c + s / c + d / c + r / c + n (move→moves, close→closer)
    for (final suf in const ['s', 'd', 'r', 'n', 'y', 'e']) {
      if (w == c + suf || c == w + suf) return true;
    }
    return false;
  }

  /// [word] olası bir yazım hatasıysa önerilen kelimeyi ve güveni döndürür.
  (String, Confidence)? suggest(String word) {
    final w = word.toLowerCase();
    if (w.length < 4 || !RegExp(r'^[a-z]+$').hasMatch(w)) return null;
    if (f(w) > 2 || known(w)) return null;
    String? best;
    var bestF = 0;
    for (final c in edits1(w)) {
      final cf = f(c);
      if (cf > bestF && (cf >= 10 || (vocab.contains(c) && cf >= 3))) {
        best = c;
        bestF = cf;
      }
    }
    if (best == null || variantPair(w, best)) return null;
    // İlk harfte düzenleme (awaited/waited, preach/reach): gerçek yazım
    // hatalarında nadirdir, genelde başka bir gerçek kelimedir.
    if (w[0] != best[0]) return null;
    // Yalnızca klasik yazım kalıpları. Harf değiştirme/ekleme (wafers/waters,
    // tusk/task, fallow/follow) içerikte neredeyse her zaman nadir ama gerçek
    // bir kelimeydi; onları YZ kontrolüne bırakıyoruz.
    if (!classicTypo(w, best)) return null;
    final conf = (bestF >= 20 && w.length >= 7 && f(w) == 1)
        ? Confidence.high
        : (w.length <= 5 ? Confidence.low : Confidence.medium);
    return (best, conf);
  }

  /// Klasik yazım hatası kalıbı mı: komşu harf yer değiştirmesi (recieve),
  /// çift harfin teklenmesi (ocured) ya da tek harfin çiftlenmesi (untill).
  static bool classicTypo(String w, String c) {
    if (w.length == c.length) {
      // yer değiştirme
      final diff = [
        for (var i = 0; i < w.length; i++)
          if (w[i] != c[i]) i,
      ];
      return diff.length == 2 &&
          diff[1] == diff[0] + 1 &&
          w[diff[0]] == c[diff[1]] &&
          w[diff[1]] == c[diff[0]];
    }
    final longer = w.length > c.length ? w : c, shorter = w.length > c.length ? c : w;
    for (var i = 0; i < longer.length; i++) {
      if (longer.substring(0, i) + longer.substring(i + 1) == shorter) {
        // silinen/eklenen harf komşusuyla aynı mı?
        if ((i > 0 && longer[i - 1] == longer[i]) || (i + 1 < longer.length && longer[i + 1] == longer[i]))
          return true;
      }
    }
    return false;
  }
}

/// Yaygın kısaltmalar, adlar ve sözlükte bulunmayabilecek kelimeler.
const _builtinAllow = {
  'don',
  'doesn',
  'didn',
  'isn',
  'aren',
  'wasn',
  'weren',
  'won',
  'wouldn',
  'couldn',
  'shouldn',
  'haven',
  'hasn',
  'hadn',
  'mustn',
  'needn',
  'shan',
  'mightn',
  'll',
  've',
  're',
  'okay',
  'ok',
  'hi',
  'hey',
  'yeah',
  'oops',
  'wow',
  'hmm',
  'gonna',
  'wanna',
  'gotta',
  'ma',
  'am',
  'pm',
  'mr',
  'mrs',
  'ms',
  'dr',
  'tv',
  'app',
  'apps',
  'email',
  'emails',
  'online',
  'offline',
  'website',
  'websites',
  'smartphone',
  'smartphones',
  'laptop',
  'laptops',
  'wifi',
  'login',
  'logout',
  'signup',
  'checkout',
  'username',
  'password',
  'simit',
  'kebab',
  'baklava',
  'ayran',
  'meze',
  'raki',
  'lira',
  'liras',
  'bazaar',
  'hammam',
  'dolmus',
  'pide',
  'lahmacun',
  'manti',
  'borek',
  'kofte',
  'doner',
  'tea',
  'pasha',
  'sultan',
  'sultans',
  'ottoman',
  'ottomans',
  'mosque',
  'mosques',
  'kilim',
  'kilims',
  'bayram',
  'iftar',
  'ramadan',
  'vapur',
  'mahalle',
  'teyze',
  'abla',
  'abi',
  'hoca',
  'cay',
  'cafe',
  'cafes',
  'barista',
  'emoji',
  'emojis',
  'selfie',
  'selfies',
  'blog',
  'blogs',
  'blogger',
  'vlog',
  'podcast',
  'podcasts',
  'stoic',
  'stoics',
  'seneca',
  'epictetus',
  'marcus',
  'thee',
  'thou',
  'thy',
  'thine',
  'hath',
  'doth',
  'shalt',
  'unto',
  'whilst',
  'amongst',
};

// ---------------------------------------------------------------------------
// Çıkarma (JSON → birimler)
// ---------------------------------------------------------------------------

/// Tam cümle denetimi yapılan alanlar.
const sentenceKeys = {
  'text',
  'question',
  'q',
  'en',
  'example',
  'passage',
  'model',
  'right',
  'prompt',
  'statement',
};

/// Cevap/öbek denetimi yapılan alanlar (quote/key: diyalogdan kesit).
const fragmentKeys = {'answer', 'answers', 'key', 'def', 'phrase', 'title', 'quote'};

/// Yalnızca sözlüğe katkı veren alanlar (çeldiriciler, kelime bankaları).
const dictOnlyKeys = {
  'options',
  'choices',
  'tokens',
  'pairs',
  'word',
  'family',
  'synonym',
  'target',
  'ys5',
  'idioms',
  'glossKeys',
};

/// Hiç okunmayan alanlar (Türkçe ya da teknik).
const skipKeys = {
  'id',
  'tr',
  'translation',
  'explanation',
  'explain',
  'why',
  'guide',
  'description',
  'titleTr',
  'tip',
  'story',
  'summary',
  'compare',
  'rules',
  'how',
  'turkish',
  'mistake',
  'wrong',
  'type',
  'kind',
  'speaker',
  'avatar',
  'emoji',
  'color',
  'theme',
  'lang',
  'fromLang',
  'learningLang',
  'cefr',
  'level',
  'genre',
  'skill',
  'qtype',
  'section',
  'examId',
  'taskId',
  'focus',
  'checklist',
  'note',
  'source',
  'category',
  'unit',
  'noteIds',
  'label',
  'timeline',
  'timelineNote',
  'gender',
  'name',
  'topic',
  'pos',
  'context',
  'aTr',
  'bTr',
  'sound',
  'author',
  'work',
  'ref',
  'scoring',
  'field',
  'extends',
  'version',
  'grammar',
  'body',
};

class Extraction {
  final List<Unit> units = [];
  final Map<String, int> unitsPerFile = {};
  final SpellModel spell = SpellModel();
}

void extractFile(String relPath, dynamic json, Extraction ex) {
  void addUnit(String ident, String key, String text, UnitKind kind) {
    if (key.endsWith('prompt') && !text.trim().contains(' ')) return; // tek kelimelik Türkçe istem
    if (text.trim().isEmpty) return;
    if (isTurkish(text)) return;
    // Bilerek yanlış verilmiş örnekler
    if (RegExp(r'[✗❌✘]|\(yanlış\)|^\s*\*', caseSensitive: false).hasMatch(text)) return;
    ex.spell.addText(text);
    ex.units.add(Unit(relPath, ident, key, text, kind));
    ex.unitsPerFile[relPath] = (ex.unitsPerFile[relPath] ?? 0) + 1;
  }

  void dictText(String s) {
    if (!isTurkish(s)) ex.spell.addText(s);
  }

  void walk(dynamic v, String path, String ident, String key) {
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      final id = m['id'] is String ? m['id'] as String : ident;
      // Doğru şık: options[answer] / choices[answer]
      String? correct;
      for (final listKey in const ['options', 'choices']) {
        final list = m[listKey];
        final ans = m['answer'];
        if (list is List && _turkishList(list)) continue;
        if (list is List && ans is int && ans >= 0 && ans < list.length && list[ans] is String) {
          correct = list[ans] as String;
          addUnit(id, '$listKey[doğru]', correct, UnitKind.fragment);
        } else if (list is List && ans is String) {
          correct = ans;
        }
      }
      for (final e in m.entries) {
        final k = e.key, val = e.value;
        final p = '$path.$k';
        if (skipKeys.contains(k)) continue;
        if (k == 'text' && m['lang'] == 'tr') continue; // çeviri alıştırmasının Türkçe kaynağı
        if (k == 'glosses' && val is Map) {
          for (final gk in val.keys) {
            ex.spell.addVocab(gk.toString());
            dictText(gk.toString());
          }
          continue;
        }
        if (dictOnlyKeys.contains(k)) {
          if (k == 'pairs' && val is List) {
            // Eşleştirme çiftleri [Türkçe, İngilizce]: yalnızca ikinci öğe
            for (final pair in val) {
              if (pair is List && pair.length == 2 && pair[1] is String && !isTurkish(pair[1] as String)) {
                ex.spell.addVocab(pair[1] as String);
                dictText(pair[1] as String);
              }
            }
            continue;
          }
          // Bir şık Türkçeyse bütün liste Türkçe kabul edilir
          if (val is List && _turkishList(val)) continue;
          _forStrings(val, dictText);
          if (k == 'word' || k == 'family' || k == 'synonym' || k == 'ys5' || k == 'target') {
            _forStrings(val, ex.spell.addVocab);
          }
          continue;
        }
        if (val is String) {
          final isSentenceKey = sentenceKeys.contains(k);
          if (!isSentenceKey && !fragmentKeys.contains(k)) continue;
          // 'en' notes/words.json'da tek kelime (dict); diğer yerlerde cümle
          if (k == 'en' && relPath.endsWith('notes/words.json')) {
            ex.spell.addVocab(val);
            dictText(val);
            continue;
          }
          if (k == 'title' && !relPath.contains('reading/')) continue;
          var text = val;
          if (_blankRe.hasMatch(text)) {
            text = fillBlanks(text, (k == 'text' || k == 'question' || k == 'prompt') ? correct : null);
          }
          addUnit(id, p.substring(1), text, isSentenceKey ? UnitKind.sentence : UnitKind.fragment);
        } else if (val is List && (k == 'answers')) {
          for (var i = 0; i < val.length; i++) {
            if (val[i] is String) addUnit(id, '${p.substring(1)}[$i]', val[i] as String, UnitKind.fragment);
          }
        } else {
          walk(val, p, id, k);
        }
      }
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        final item = v[i];
        if (item is String) {
          if (sentenceKeys.contains(key) || fragmentKeys.contains(key)) {
            addUnit(
              ident,
              '${path.substring(1)}[$i]',
              item,
              sentenceKeys.contains(key) ? UnitKind.sentence : UnitKind.fragment,
            );
          }
        } else {
          walk(item, '$path[$i]', ident, key);
        }
      }
    }
  }

  walk(json, '', '', '');
}

bool _turkishList(List list) {
  final strs = list.whereType<String>().toList();
  if (strs.any(isTurkish) ||
      strs.any((s) => _turkishLetters.hasMatch(s) && !RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(s)))
    return true;
  // choices: [{text: ...}]
  final texts = list.whereType<Map>().map((m) => m['text']).whereType<String>().toList();
  return texts.any(isTurkish);
}

void _forStrings(dynamic v, void Function(String) f) {
  if (v is String) {
    f(v);
  } else if (v is List) {
    for (final x in v) {
      _forStrings(x, f);
    }
  } else if (v is Map) {
    for (final x in v.values) {
      _forStrings(x, f);
    }
  }
}

/// Kelime listesi dosyaları (assets/vocab): sözlüğe girer; örnek cümleler ve
/// tanımlar ayrıca denetlenir.
void extractVocab(String relPath, dynamic json, Extraction ex) {
  final entries = (json is Map ? json['entries'] : null) as List? ?? const [];
  for (final e in entries) {
    if (e is! Map) continue;
    _forStrings(e['word'], ex.spell.addVocab);
    _forStrings(e['family'], (s) => ex.spell.addVocab(s.replaceAll(RegExp(r'\(.*?\)'), '')));
    _forStrings(e['synonym'], ex.spell.addVocab);
    final colls = e['collocations'];
    if (colls is List) {
      for (final c in colls) {
        if (c is Map && c['phrase'] is String) ex.spell.addText(c['phrase'] as String);
      }
    }
  }
  // Örnek cümleler ve tanımlar normal yürüyüşle
  extractFile(relPath, {
    'entries': entries
        .map((e) => e is Map ? {'id': e['id'], 'senses': e['senses'], 'examples': e['examples']} : e)
        .toList(),
  }, ex);
}

// ---------------------------------------------------------------------------
// Tarama
// ---------------------------------------------------------------------------

/// Birimleri yinelenenlerden arındırır (aynı metin birçok alıştırmada geçer).
List<Unit> dedupe(List<Unit> units) {
  final byText = <String, Unit>{};
  for (final u in units) {
    final k = u.text.trim();
    final prev = byText[k];
    if (prev == null) {
      byText[k] = u;
    } else {
      prev.copies++;
      // Cümle türü baskın
      if (prev.kind == UnitKind.fragment && u.kind == UnitKind.sentence) {
        byText[k] = Unit(u.file, u.ident, u.key, u.text, u.kind)..copies = prev.copies;
      }
    }
  }
  return byText.values.toList();
}

String normKey(String key) =>
    key.replaceAll(RegExp(r'\[\d+\]'), '').split('.').last.replaceAll(RegExp(r'\[.*\]'), '');

List<Finding> scan(Extraction ex) {
  final units = dedupe(ex.units);
  // Kardeş alan istatistikleri: (dosya, alan) bazında noktalama ile biten ve
  // büyük harfle başlayan oranı.
  final endStats = <String, List<int>>{};
  final capStats = <String, List<int>>{};
  for (final u in units) {
    if (u.kind != UnitKind.sentence) continue;
    final k = '${u.file}|${normKey(u.key)}';
    final words = u.text.trim().split(RegExp(r'\s+')).length;
    if (words >= 4) {
      final e = endStats.putIfAbsent(k, () => [0, 0]);
      e[1]++;
      if (endsWithTerminal(u.text)) e[0]++;
    }
    final c = capStats.putIfAbsent(k, () => [0, 0]);
    final first = RegExp(r'\p{L}', unicode: true).firstMatch(u.text);
    if (first != null) {
      c[1]++;
      if (RegExp(r'\p{Lu}', unicode: true).hasMatch(u.text[first.start])) c[0]++;
    }
  }
  double ratio(Map<String, List<int>> m, String k) {
    final e = m[k];
    return (e == null || e[1] == 0) ? 0 : e[0] / e[1];
  }

  final findings = <Finding>[];
  for (final u in units) {
    // Harf işareti olmayan Türkçe metinler ("Burada yemek yemek yasak."):
    // küçük harfli kelimelerin yarısından azı İngilizce sözlükteyse atla.
    final lw = RegExp(
      r'(?<![\p{L}])[a-z]{2,}(?![\p{L}])',
      unicode: true,
    ).allMatches(u.text).map((m) => m.group(0)!).toList();
    if (lw.length >= 2 && lw.where(ex.spell.known).length / lw.length < 0.5) continue;
    final code = isCodeLike(u.text);
    final k = '${u.file}|${normKey(u.key)}';
    final issues = <Issue>[];
    if (u.kind == UnitKind.sentence) {
      final expectCap = ratio(capStats, k) >= 0.9;
      for (final i in checkSentence(u.text, code: code, expectCapital: expectCap)) {
        // Baştaki kelime sözlükte yoksa (npm, p99, iOS) büyük harf beklentisi zayıf
        final firstWord = RegExp(r'[A-Za-z]+').firstMatch(u.text)?.group(0) ?? '';
        if (i.rule == 'kucuk_baslangic' && i.offset == 0 && !ex.spell.known(firstWord.toLowerCase())) {
          issues.add(Issue(i.rule, i.problem, i.suggestion, Confidence.low, i.offset));
        } else {
          issues.add(i);
        }
      }
      final r = ratio(endStats, k);
      final words = u.text.trim().split(RegExp(r'\s+')).length;
      final lowerStart = RegExp(r'^[^A-Za-z]*[a-z]').hasMatch(u.text.trimLeft());
      if (words >= 4 &&
          r >= 0.9 &&
          !lowerStart &&
          splitSentences(u.text).length == 1 &&
          !u.text.trimRight().endsWith(')') &&
          !endsWithTerminal(u.text) &&
          !u.text.contains('\n') &&
          !u.text.trimRight().endsWith(blankWord)) {
        issues.add(
          Issue(
            'bitis',
            'Cümle sonunda noktalama yok (bu alanın %${(r * 100).round()}’i noktalamayla bitiyor)',
            'Sona nokta/soru işareti ekle',
            r >= 0.97 ? Confidence.medium : Confidence.low,
            u.text.length,
          ),
        );
      }
    } else {
      issues.addAll(checkFragment(u.text, code: code));
    }
    // Yazım (sözlük)
    if (!code) {
      final sentenceStarts = <int>{0};
      for (final m in RegExp(r'[.!?…]["”’)]*\s+|\n').allMatches(u.text)) {
        sentenceStarts.add(m.end);
      }
      for (final m in _wordRe.allMatches(u.text)) {
        final w = m.group(0)!;
        if (w.contains("'") || w.contains('’')) continue;
        final cap = RegExp(r'^[A-Z]').hasMatch(w);
        final atStart =
            sentenceStarts.contains(m.start) ||
            (m.start > 0 &&
                RegExp(r'["“(‘]$').hasMatch(u.text.substring(0, m.start)) &&
                sentenceStarts.contains(m.start - 1));
        if (cap && !atStart) continue; // özel isim
        if (w == w.toUpperCase() && w.length > 1) continue; // kısaltma
        // Türkçe özel isimle bitişik (Kadıköy'de) ya da harf dışı karakterle bitişikse atla
        if (m.end < u.text.length && RegExp(r'[\p{L}\d_]', unicode: true).hasMatch(u.text[m.end])) continue;
        if (m.start > 0 && RegExp(r'[\p{L}\d_]', unicode: true).hasMatch(u.text[m.start - 1])) continue;
        // Kelimenin başka bir yerde büyük harfle (özel isim olarak) geçmesi
        final s = ex.spell.suggest(w);
        if (s == null) continue;
        var conf = s.$2;
        if (cap) conf = Confidence.low;
        issues.add(
          Issue(
            'yazim',
            'Olası yazım hatası: “$w” (içerikte ${ex.spell.f(w.toLowerCase())} kez)',
            '“${cap ? s.$1[0].toUpperCase() + s.$1.substring(1) : s.$1}”?',
            conf,
            m.start,
          ),
        );
      }
    }
    // Aynı kural + aynı konum tekrarını at
    final seen = <String>{};
    for (final i in issues) {
      if (seen.add('${i.rule}|${i.offset}')) findings.add(Finding(u, i, 'kural'));
    }
  }
  findings.sort((a, b) {
    final c = a.issue.confidence.index.compareTo(b.issue.confidence.index);
    if (c != 0) return c;
    final f = a.unit.file.compareTo(b.unit.file);
    return f != 0 ? f : a.unit.ident.compareTo(b.unit.ident);
  });
  return findings;
}

// ---------------------------------------------------------------------------
// YZ kontrolü (isteğe bağlı, --ai)
// ---------------------------------------------------------------------------

const _aiModel = 'claude-haiku-5-5';
const _keyPath = r'C:\Users\clt\.dilbaz\anthropic_key.txt';

class AiResult {
  final List<Finding> findings = [];
  int sent = 0;
  int batches = 0;
  final List<String> notes = [];
}

Future<AiResult> runAi(List<Unit> units, List<Finding> local, int limit) async {
  final res = AiResult();
  final keyFile = File(_keyPath);
  if (!keyFile.existsSync()) {
    res.notes.add('Anahtar dosyası bulunamadı; YZ kontrolü atlandı.');
    return res;
  }
  final key = keyFile.readAsStringSync().trim();
  if (key.isEmpty) {
    res.notes.add('Anahtar dosyası boş; YZ kontrolü atlandı.');
    return res;
  }
  // Aday cümleler: önce yerel kuralların orta/düşük işaretledikleri, sonra
  // uzun cümleler. Pasajlar cümlelere bölünür.
  final flaggedTexts = <String>{
    for (final f in local)
      if (f.issue.confidence != Confidence.high) f.unit.text.trim(),
  };
  final cands = <(Unit, String)>[];
  final seen = <String>{};
  void add(Unit u, String s) {
    final t = s.trim();
    if (t.split(RegExp(r'\s+')).length < 4 || !seen.add(t)) return;
    cands.add((u, t));
  }

  final uniq = dedupe(units);
  for (final u in uniq) {
    if (!flaggedTexts.contains(u.text.trim())) continue;
    for (final s in splitSentences(u.text)) {
      add(u, s);
    }
  }
  final rest = <(Unit, String)>[];
  for (final u in uniq) {
    if (u.kind != UnitKind.sentence || isCodeLike(u.text)) continue;
    for (final s in splitSentences(u.text)) {
      rest.add((u, s));
    }
  }
  rest.sort((a, b) => b.$2.length.compareTo(a.$2.length));
  // Uzun cümlelerden dosyalara dengeli bir seçim (her dosyadan sırayla)
  final byFile = <String, List<(Unit, String)>>{};
  for (final r in rest) {
    byFile.putIfAbsent(r.$1.file, () => []).add(r);
  }
  var idx = 0;
  while (cands.length < limit && byFile.values.any((l) => l.length > idx)) {
    for (final l in byFile.values) {
      if (idx < l.length && cands.length < limit) add(l[idx].$1, l[idx].$2);
    }
    idx++;
  }
  final chosen = cands.take(limit).toList();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    for (var b = 0; b < chosen.length; b += 60) {
      final batch = chosen.sublist(b, min(b + 60, chosen.length));
      final numbered = StringBuffer();
      for (var i = 0; i < batch.length; i++) {
        numbered.writeln('${i + 1}. ${batch[i].$2.replaceAll('\n', ' ')}');
      }
      final prompt =
          '''Below are numbered English sentences from an English-learning app for Turkish speakers.
Find ONLY clear errors in spelling, grammar or punctuation. Ignore: style preferences, British vs American spelling,
the placeholder word BLANK (a gap in an exercise), Turkish proper names, informal but correct dialogue, sentence fragments
that are clearly intentional (titles, short answers), and fictional place names.
Return STRICT JSON only, no prose, in this shape:
{"errors":[{"i":<number>,"problem":"<short description in Turkish>","fix":"<corrected sentence or the corrected part>","confidence":"high|medium|low"}]}
If there are no errors return {"errors":[]}.

$numbered''';
      final body = jsonEncode({
        'model': _aiModel,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      });
      res.batches++;
      try {
        final req = await client.postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
        req.headers
          ..set('x-api-key', key)
          ..set('anthropic-version', '2023-06-01')
          ..set('content-type', 'application/json');
        req.add(utf8.encode(body));
        final resp = await req.close().timeout(const Duration(seconds: 120));
        final text = await resp.transform(utf8.decoder).join();
        if (resp.statusCode != 200) {
          var msg = 'HTTP ${resp.statusCode}';
          try {
            final err = jsonDecode(text);
            msg += ' (${err['error']?['type'] ?? ''}: ${_clip('${err['error']?['message'] ?? ''}', 120)})';
          } catch (_) {}
          res.notes.add('Grup ${res.batches}: $msg');
          if (resp.statusCode == 401 || resp.statusCode == 403 || resp.statusCode == 404) break;
          continue;
        }
        res.sent += batch.length;
        final data = jsonDecode(text) as Map<String, dynamic>;
        final content = (data['content'] as List)
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String)
            .join();
        final a = content.indexOf('{'), z = content.lastIndexOf('}');
        if (a < 0 || z <= a) {
          res.notes.add('Grup ${res.batches}: yanıt JSON değil');
          continue;
        }
        final parsed = jsonDecode(content.substring(a, z + 1)) as Map<String, dynamic>;
        for (final e in (parsed['errors'] as List? ?? const [])) {
          if (e is! Map) continue;
          final i = (e['i'] is int ? e['i'] as int : int.tryParse('${e['i']}') ?? 0) - 1;
          if (i < 0 || i >= batch.length) continue;
          final conf = switch ('${e['confidence']}') {
            'high' => Confidence.high,
            'low' => Confidence.low,
            _ => Confidence.medium,
          };
          final u = batch[i].$1;
          final sentUnit = Unit(u.file, u.ident, u.key, batch[i].$2, u.kind);
          res.findings.add(
            Finding(sentUnit, Issue('yz', '${e['problem'] ?? ''}', '${e['fix'] ?? ''}', conf), 'YZ'),
          );
        }
      } catch (e) {
        res.notes.add('Grup ${res.batches}: ağ/ayrıştırma hatası (${e.runtimeType})');
      }
    }
  } finally {
    client.close(force: true);
  }
  return res;
}

// ---------------------------------------------------------------------------
// Rapor
// ---------------------------------------------------------------------------

String _cell(String s) => s.replaceAll('|', r'\|').replaceAll(RegExp(r'\s*\n\s*'), ' / ').trim();

String buildReport({
  required Extraction ex,
  required List<Finding> findings,
  required int tableLimit,
  AiResult? ai,
  required bool aiRequested,
  required List<String> files,
}) {
  final b = StringBuffer();
  final all = [...findings, ...?ai?.findings]
    ..sort((a, c) {
      final x = a.issue.confidence.index.compareTo(c.issue.confidence.index);
      if (x != 0) return x;
      final s = a.source.compareTo(c.source);
      if (s != 0) return s;
      final f = a.unit.file.compareTo(c.unit.file);
      return f != 0 ? f : a.unit.ident.compareTo(c.unit.ident);
    });
  final uniqUnits = dedupe(ex.units);
  final sentenceCount = uniqUnits.fold<int>(
    0,
    (n, u) => n + (u.kind == UnitKind.sentence ? splitSentences(u.text).length : 1),
  );
  b.writeln('# İçerik tarama raporu (İngilizce yazım, dil bilgisi, noktalama)');
  b.writeln();
  b.writeln(
    'Bu rapor `tool/icerik_tarama.dart` tarafından üretildi. **Yalnızca rapordur: hiçbir içerik dosyası '
    'değiştirilmedi.** Bulgular otomatik olduğu için her satır bir *şüphedir*; düzeltmeden önce cümleyi bağlamında okuyun.',
  );
  b.writeln();
  b.writeln('## Nasıl çalıştırılır');
  b.writeln();
  b.writeln('```');
  b.writeln('dart run tool/icerik_tarama.dart                  # yalnızca yerel kurallar');
  b.writeln(
    'dart run tool/icerik_tarama.dart --ai             # + YZ kontrolü (Anthropic API, varsayılan 300 cümle)',
  );
  b.writeln(
    'dart run tool/icerik_tarama.dart --ai --ai-limit 120 --limit 500 --out docs/icerik-tarama-raporu.md',
  );
  b.writeln('```');
  b.writeln();
  b.writeln(
    '- **Taranan:** ${files.length} dosya, ${ex.units.length} İngilizce metin alanı '
    '(${uniqUnits.length} benzersiz, yaklaşık $sentenceCount cümle/öbek).',
  );
  b.writeln(
    '- **Sözlük:** sistem sözlüğü yok; içeriğin kendisinden (${ex.spell.freq.length} farklı kelime) ve kelime '
    'listelerinden (`assets/vocab`, sözlük alanları, glossary anahtarları; ${ex.spell.vocab.length} kelime) kuruldu. '
    'Az geçen (≤2), listelerde olmayan, özel isim olmayan ve sık bir kelimeye tek harf uzaklıkta olan kelimeler işaretlenir.',
  );
  b.writeln(
    '- **Atlananlar:** Türkçe alanlar (`tr`, `translation`, `explanation`, `why`, `guide`, …) ve Türkçe karakter/kelime '
    'oranı yüksek metinler; çoktan seçmeli **çeldiriciler** (yalnızca doğru şık `options[answer]` denetlenir), kelime '
    'bankaları (`tokens`), eşleştirme çiftleri, `mistakes.wrong` gibi bilerek yanlış örnekler. Boşluklar (`___`, `----`) '
    'tek boşluklu ve cevabı bilinen alıştırmalarda doğru cevapla doldurulur, aksi halde `BLANK` kelimesi olarak sayılır.',
  );
  b.writeln(
    '- Aynı metin birden çok yerde geçiyorsa (ör. her soruda tekrarlanan okuma parçası) bir kez denetlenir; '
    'tabloda ilk geçtiği yer gösterilir.',
  );
  if (aiRequested) {
    if (ai == null) {
      b.writeln('- **YZ kontrolü:** çalıştırılamadı.');
    } else {
      b.writeln(
        '- **YZ kontrolü (`--ai`, model `$_aiModel`):** ${ai.sent} cümle ${ai.batches} istekte gönderildi; '
        '${ai.findings.length} bulgu (kaynak **YZ**). Öncelik: yerel kuralların orta/düşük işaretledikleri, sonra her dosyadan en uzun cümleler.'
        '${ai.notes.isEmpty ? '' : ' Notlar: ${ai.notes.join('; ')}'}',
      );
    }
  } else {
    b.writeln('- **YZ kontrolü:** bu çalıştırmada kapalı (`--ai` ile açılır).');
  }
  b.writeln();
  b.writeln('## Ayarlama notları (yanlış alarm azaltma)');
  b.writeln();
  b.writeln(
    'İlk çalıştırmalarda elle incelenen ~150 şüphenin neredeyse tamamı yanlış alarmdı; kurallar buna göre daraltıldı:',
  );
  b.writeln();
  b.writeln(
    '- **Yazım (sözlük):** yalnızca klasik yazım kalıpları (komşu harf yer değiştirmesi, çift harfin teklenmesi/tek harfin '
    'çiftlenmesi) ve ilk harf dışındaki düzenlemeler işaretlenir. Harf değiştirme/ekleme (wafers→waters, tusk→task, fallow→follow, '
    'preach→reach) içerikte hep nadir ama gerçek kelimelerdi; bunlar YZ kontrolüne bırakıldı. İngiliz/Amerikan yazımı (colour, centre, '
    'organise, travelled) ve ekle türetilebilen kelimeler hata sayılmaz.',
  );
  b.writeln(
    '- **Türkçe sızıntı:** Türkçe şık listeleri (bir şık Türkçeyse tüm liste), `lang: tr` kaynak metinleri, eşleştirme '
    'çiftlerinin Türkçe tarafı, tek kelimelik Türkçe istemler ve küçük harfli kelimelerinin yarısından azı İngilizce sözlükte olan metinler atlanır.',
  );
  b.writeln(
    '- **Noktalama:** boşluk biçimi `---- .` hata sayılmaz; kısaltma sonrası virgül (Bros., D.C., a.m.,) normaldir; kod/yol içeren '
    'metinler (`../`, `?page=2`, camelCase) noktalama kurallarından muaftır; sonda noktalama kuralı yalnızca aynı alanın ≥%90’ı '
    'noktalamayla bitiyorsa ve metin tek cümleyse çalışır (commit mesajları, imzalı notlar, parantezli ipuçları hariç).',
  );
  b.writeln(
    '- **Diğer:** özel isim ve sayı tekrarları (Santorio Santorio, five five five), *its very first*, *the day when I met you was*, '
    '*as if it were*, *Does she have* gibi doğru yapılar kurallardan çıkarıldı; küçük harfle başlayıp noktasız biten öbekler '
    '(*the man who spoke to you*) cümle sayılmaz; tanımlıkta harf harf okunmayan kısaltmalar (NASA, REST, UNESCO) belirsiz kabul edilir.',
  );
  b.writeln();

  // Dosya bazında sayılar
  b.writeln('## Dosya bazında');
  b.writeln();
  b.writeln('| Dosya | İngilizce alan | Yüksek | Orta | Düşük |');
  b.writeln('|---|---:|---:|---:|---:|');
  for (final f in files) {
    final fs = all.where((x) => x.unit.file == f);
    int c(Confidence k) => fs.where((x) => x.issue.confidence == k).length;
    b.writeln(
      '| `$f` | ${ex.unitsPerFile[f] ?? 0} | ${c(Confidence.high)} | ${c(Confidence.medium)} | ${c(Confidence.low)} |',
    );
  }
  b.writeln();

  // Kural bazında toplamlar
  b.writeln('## Kural bazında toplamlar');
  b.writeln();
  b.writeln('| Kural | Yüksek | Orta | Düşük | Toplam |');
  b.writeln('|---|---:|---:|---:|---:|');
  final rules = <String>{for (final f in all) f.issue.rule}.toList()
    ..sort(
      (a, c) =>
          all.where((x) => x.issue.rule == c).length.compareTo(all.where((x) => x.issue.rule == a).length),
    );
  for (final r in rules) {
    final rs = all.where((x) => x.issue.rule == r);
    int c(Confidence k) => rs.where((x) => x.issue.confidence == k).length;
    b.writeln(
      '| ${ruleLabels[r] ?? r} | ${c(Confidence.high)} | ${c(Confidence.medium)} | ${c(Confidence.low)} | ${rs.length} |',
    );
  }
  int tc(Confidence k) => all.where((x) => x.issue.confidence == k).length;
  b.writeln(
    '| **Toplam** | **${tc(Confidence.high)}** | **${tc(Confidence.medium)}** | **${tc(Confidence.low)}** | **${all.length}** |',
  );
  b.writeln();

  b.writeln('## Bulgular');
  b.writeln();
  b.writeln(
    all.length > tableLimit
        ? 'Güvene göre sıralı ilk $tableLimit bulgu (toplam ${all.length}; tamamı için `--limit ${all.length}`).'
        : 'Güvene göre sıralı tüm bulgular (${all.length}).',
  );
  b.writeln();
  b.writeln('| # | Dosya | Kimlik | Cümle | Sorun | Öneri | Güven | Kaynak |');
  b.writeln('|---:|---|---|---|---|---|---|---|');
  var n = 0;
  for (final f in all.take(tableLimit)) {
    n++;
    final u = f.unit;
    final ident = u.ident.isEmpty ? u.key : '${u.ident} · ${u.key}';
    final copies = u.copies > 1 ? ' (+${u.copies - 1} yer)' : '';
    b.writeln(
      '| $n | `${u.file}` | `${_cell(_clip(ident, 80))}`$copies | ${_cell(snippetAround(u.text, f.issue.offset))} | '
      '${_cell(f.issue.problem)} | ${_cell(_clip(f.issue.suggestion, 160))} | ${confidenceTr[f.issue.confidence]} | ${f.source} |',
    );
  }
  b.writeln();
  return b.toString();
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

/// Taranacak içerik dosyaları (kök dizine göre, / ayraçlı).
List<String> contentFiles(Directory root) {
  final out = <String>[];
  for (final dir in const [
    'courses',
    'reading',
    'notes',
    'exams',
    'exam_packs',
    'placement',
    'vocab',
    'pronunciation',
    'quotes',
  ]) {
    final d = Directory('${root.path}/assets/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final rel = f.path.substring(root.path.length + 1).replaceAll(r'\', '/');
      if (rel.endsWith('notes/meta.json')) continue;
      out.add(rel);
    }
  }
  out.sort();
  return out;
}

Future<void> main(List<String> args) async {
  int argInt(String name, int def) {
    final i = args.indexOf(name);
    return (i >= 0 && i + 1 < args.length) ? int.tryParse(args[i + 1]) ?? def : def;
  }

  String argStr(String name, String def) {
    final i = args.indexOf(name);
    return (i >= 0 && i + 1 < args.length) ? args[i + 1] : def;
  }

  final useAi = args.contains('--ai');
  final aiLimit = argInt('--ai-limit', 300);
  final tableLimit = argInt('--limit', 300);
  final outPath = argStr('--out', 'docs/icerik-tarama-raporu.md');

  final root = Directory.current;
  final files = contentFiles(root);
  if (files.isEmpty) {
    stderr.writeln('assets/ bulunamadı: komutu depo kökünden çalıştırın.');
    exitCode = 2;
    return;
  }
  final ex = Extraction();
  for (final rel in files) {
    final json = jsonDecode(File('${root.path}/$rel').readAsStringSync());
    if (rel.startsWith('assets/vocab/')) {
      extractVocab(rel, json, ex);
    } else {
      extractFile(rel, json, ex);
    }
  }
  final findings = scan(ex);
  AiResult? ai;
  if (useAi) {
    stdout.writeln('YZ kontrolü: en fazla $aiLimit cümle…');
    ai = await runAi(ex.units, findings, aiLimit);
    for (final n in ai.notes) {
      stdout.writeln('  YZ notu: $n');
    }
  }
  final report = buildReport(
    ex: ex,
    findings: findings,
    tableLimit: tableLimit,
    ai: ai,
    aiRequested: useAi,
    files: files,
  );
  File(outPath).writeAsStringSync(report);
  int c(Confidence k) => findings.where((f) => f.issue.confidence == k).length;
  stdout.writeln(
    '${files.length} dosya, ${ex.units.length} İngilizce alan. Yerel bulgu: '
    'yüksek ${c(Confidence.high)}, orta ${c(Confidence.medium)}, düşük ${c(Confidence.low)}'
    '${ai == null ? '' : '; YZ: ${ai.findings.length}'}. Rapor: $outPath',
  );
}
