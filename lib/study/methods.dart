// "Nasıl öğretiyoruz?": the learning methods behind Dilbaz's YDS plan, in
// plain Turkish (docs/sinav/yds-faz1-yontem.md §6). Each card says what the
// method is, why (one finding and its source) and where it works in the app.
// The wording never claims more than the research write-up does.

/// Research write-up the cards come from.
const methodsSourceDoc = 'docs/sinav/yds-arastirma.md (§2 yöntemler, §3 yöntem → özellik)';

class StudyMethod {
  const StudyMethod({
    required this.id,
    required this.emoji,
    required this.title,
    required this.what,
    required this.why,
    required this.where,
  });

  final String id;
  final String emoji;
  final String title;

  /// Ne?
  final String what;

  /// Neden? One finding and its source.
  final String why;

  /// Dilbaz'da nerede?
  final String where;
}

const studyMethods = [
  StudyMethod(
    id: 'spacing',
    emoji: '🔁',
    title: 'Aralıklı tekrar',
    what:
        'Bir bilgiyi unutmak üzereyken yeniden görmek. Bildiğin kart daha geç, bilmediğin daha erken gelir.',
    why:
        'Unutmadan hemen önce tekrar etmek, aynı süreyi tek seferde harcamaktan daha kalıcıdır '
        '(Cepeda vd. 2008; Dunlosky vd. 2013).',
    where: 'Tekrar kartları ve hata defteri: kelimeler 1 günden 8 aya, sorular 1-3-7-21 gün arayla döner.',
  ),
  StudyMethod(
    id: 'retrieval',
    emoji: '🧠',
    title: 'Kendini sınama',
    what: 'Bilgiyi yeniden okumak yerine hafızandan çağırmaya çalışmak.',
    why: 'Hatırlamaya çalışmak, yeniden okumaktan daha iyi öğretir (Roediger ve Karpicke 2006; Adesope vd. 2017).',
    where: 'Dersler soruyla ilerler; kartta önce anlamı aklından söyler, sonra çevirirsin.',
  ),
  StudyMethod(
    id: 'interleaving',
    emoji: '🧩',
    title: 'Karışık çalışma',
    what: 'Benzer konuları ayrı ayrı değil, karıştırarak çalışmak.',
    why: 'Konuları karıştırmak onları ayırt etmeyi öğretir; sınavda da sorunun konusu yazmaz (Brunmair ve Richter 2019).',
    where: 'Bugün › Soru bloğu: son haftaların ünitelerinden karışık set.',
  ),
  StudyMethod(
    id: 'deep',
    emoji: '🔍',
    title: 'Derin işleme',
    what: 'Kelimeyi tek anlamla ezberlemek yerine örnek cümle, kelime ailesi ve eşdizimiyle öğrenmek.',
    why: 'Kelimeyle ne kadar çok uğraşırsan o kadar iyi kalır (Laufer ve Hulstijn 2001).',
    where: 'Kelime dersleri, kartlardaki örnek cümleler, hata defterindeki "neden yanıldım" notu.',
  ),
  StudyMethod(
    id: 'reading',
    emoji: '📚',
    title: 'Bol okuma',
    what: 'Seviyene uygun, kolay metinleri çok okumak.',
    why: 'Kolay ve çok okumak hem kelime bilgisini hem okuma hızını geliştirir (Jeon ve Day 2016; Nation).',
    where: 'Bugün › Okuma bloğu, Okuma evi, okuma sayacı.',
  ),
  StudyMethod(
    id: 'coverage',
    emoji: '🎯',
    title: 'Kelime kapsamı',
    what: 'Metinleri rahat anlamak için yeterli sayıda kelimeyi tanımak.',
    why:
        'YDS metinlerini rahat anlamak için yaklaşık 6.500 kelime ailesini hedefliyoruz '
        '(Nation 2006; Laufer ve Ravenhorst-Kalovski 2010).',
    where: 'Kelime bankası ve her haftanın yeni kelime hedefi.',
  ),
  StudyMethod(
    id: 'encounters',
    emoji: '🔂',
    title: 'Tekrar sayısı',
    what: 'Bir kelimeyle farklı yerlerde birçok kez karşılaşmak.',
    why:
        'Bir kelime genellikle 10 civarı karşılaşmadan sonra kalıcılaşır; sayı kelimeye ve kişiye göre '
        'değişir (Webb 2007; Uchihara vd. 2019).',
    where: 'Kartlar ve okuma metinlerinde aynı kelimelerin yeniden kullanılması.',
  ),
  StudyMethod(
    id: 'mockloop',
    emoji: '🔬',
    title: 'Deneme, analiz, hedefli tekrar',
    what: 'Deneme çöz, yanlışlarının nedenini bul, zayıf konuna dön.',
    why:
        'Zayıf noktaya odaklanan pratik ve geri bildirimli sınama ilerlemeyi hızlandırır '
        '(Ericsson vd. 1993; Adesope vd. 2017).',
    where: 'Deneme günü, ertesi günkü deneme analizi ve hata defteri.',
  ),
  StudyMethod(
    id: 'time',
    emoji: '⏱️',
    title: 'Zaman yönetimi',
    what: '180 dakikayı bölümlere ayırmak; bir soruda 2 dakikayı aşınca işaretleyip geçmek.',
    why: 'Okumaya en az 60 dakika kalması, puanın yarısından fazlasını getiren metin sorularını korur.',
    where: 'Deneme sonucu ve her soru tipi için hedef süreler.',
  ),
  StudyMethod(
    id: 'habit',
    emoji: '📅',
    title: 'Alışkanlık',
    what: 'Her gün aynı saatte ve yerde çalışmak.',
    why: 'Bir alışkanlığın oturması ortalama 66 gün sürer ve tek bir gün kaçırmak onu bozmaz (Lally vd. 2010).',
    where: 'Bugün planı, hatırlatıcı ve haftada bir otomatik seri dondurma.',
  ),
];
