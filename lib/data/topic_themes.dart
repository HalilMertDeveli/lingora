import 'package:flutter/material.dart';

/// Topic themes of the learning path (docs/tasarim/temalar.md). Every unit
/// names one in its JSON (`"theme": "seyahat"`); the path then draws that
/// unit's steps as a small story of the topic (bavul → bilet → uçak → oda
/// anahtarı), with a themed reward, test badge, band pattern, roadside
/// decorations, host lines and, for some topics, a costume for the host.
///
/// Tea (çay) is only one theme among many: greetings, guests, the
/// neighbourhood and small talk. Unknown or missing ids fall back to
/// [defaultThemeId].

/// How the current node moves (only while animations are allowed).
enum ThemeMotion {
  /// Rocks left and right, like a leaf or a hanging sign.
  sway,

  /// Floats up and down.
  bob,

  /// Beats like a heart.
  pulse,

  /// A soft light blinks behind it (a screen, a lamp, an "on air" sign).
  blink,

  /// Turns a little back and forth quickly, like a ringing clock.
  wiggle,
}

class TopicTheme {
  const TopicTheme({
    required this.id,
    required this.name,
    required this.accent,
    required this.motion,
    required this.steps,
    required this.reward,
    required this.rewardName,
    required this.rewardLine,
    required this.badge,
    required this.badgeName,
    required this.decor,
    required this.lessonInvite,
    required this.storyInvite,
    required this.testInvite,
    required this.chestInvite,
    this.hat,
    this.tea = false,
  });

  final String id;

  /// Short Turkish name ("Seyahat").
  final String name;

  /// Accent of the theme: glows, badge ring, band art.
  final Color accent;
  final ThemeMotion motion;

  /// Objects of the lessons and stories, in story order. The n-th step of a
  /// unit (tests and rewards aside) gets `steps[n % steps.length]`.
  final List<String> steps;

  /// The reward node (in place of the teapot) and its name.
  final String reward;
  final String rewardName;

  /// Headline when the reward opens ("Piknik sepeti açıldı!").
  final String rewardLine;

  /// Emblem inside the unit test's rosette, and the rosette's name.
  final String badge;
  final String badgeName;

  /// Two roadside decorations, also used as the band pattern (the first).
  final List<String> decor;

  /// Host lines over the current node.
  final String lessonInvite;
  final String storyInvite;
  final String testInvite;
  final String chestInvite;

  /// Costume the host wears for this topic, if any (an object name).
  final String? hat;

  /// The tea house theme: nodes keep the drawn tea glass, teapot and tulip.
  final bool tea;

  /// Asset path of [object] in this theme's folder.
  String asset(String object) => themeAsset(id, object);

  /// Every object file this theme needs.
  Set<String> get objects => {...steps, reward, badge, ...decor, ?hat};

  /// Object of the [n]th lesson/story step of a unit.
  String stepObject(int n) => steps[n % steps.length];
}

String themeAsset(String themeId, String object) => 'assets/themes/$themeId/$object.svg';

const defaultThemeId = 'cay';

/// Theme by id; unknown or empty ids get the tea house.
TopicTheme themeById(String? id) => topicThemes[id] ?? topicThemes[defaultThemeId]!;

const _themes = <TopicTheme>[
  TopicTheme(
    id: 'cay',
    name: 'Çay ve sohbet',
    accent: Color(0xFFD0532A),
    motion: ThemeMotion.bob,
    steps: ['cay_bardagi', 'simit', 'cay_bardagi', 'demlik'],
    reward: 'demlik',
    rewardName: 'Çaydanlık',
    rewardLine: 'Bir avuç şeker!',
    badge: 'lale',
    badgeName: 'Lale',
    decor: ['lale', 'simit'],
    lessonInvite: 'Hadi, bir çay daha!',
    storyInvite: 'Çayını al, hikâye başlıyor!',
    testInvite: 'Lale seni bekliyor!',
    chestInvite: 'Demlik hazır, aç bakalım!',
    tea: true,
  ),
  TopicTheme(
    id: 'yemek',
    name: 'Yemek ve içecek',
    accent: Color(0xFFE4572E),
    motion: ThemeMotion.wiggle,
    steps: ['simit', 'corba', 'tabak', 'elma'],
    reward: 'piknik_sepeti',
    rewardName: 'Piknik sepeti',
    rewardLine: 'Piknik sepeti dolu!',
    badge: 'kasik_catal',
    badgeName: 'Altın kaşık',
    decor: ['elma', 'simit'],
    lessonInvite: 'Bir lokma daha!',
    storyInvite: 'Masaya buyur, hikâye var!',
    testInvite: 'Şefin sınavı geldi!',
    chestInvite: 'Sepeti aç, afiyet olsun!',
    hat: 'sapka_asci',
  ),
  TopicTheme(
    id: 'aile',
    name: 'Aile ve ev',
    accent: Color(0xFFA0673A),
    motion: ThemeMotion.blink,
    steps: ['kapi', 'ev', 'pencere', 'anahtar'],
    reward: 'kurabiye_kavanozu',
    rewardName: 'Kurabiye kavanozu',
    rewardLine: 'Annemin kurabiyeleri!',
    badge: 'ev',
    badgeName: 'Ev',
    decor: ['cicek_saksi', 'agac'],
    lessonInvite: 'Kapı açık, gir içeri!',
    storyInvite: 'Ailece dinleyelim!',
    testInvite: 'Evin anahtarı sende mi?',
    chestInvite: 'Kavanozda ne var?',
  ),
  TopicTheme(
    id: 'zaman',
    name: 'Sayılar ve zaman',
    accent: Color(0xFF2EA4A6),
    motion: ThemeMotion.wiggle,
    steps: ['calar_saat', 'duvar_saati', 'takvim', 'kum_saati'],
    reward: 'zaman_kapsulu',
    rewardName: 'Zaman kapsülü',
    rewardLine: 'Zaman kapsülü açıldı!',
    badge: 'duvar_saati',
    badgeName: 'Saat',
    decor: ['kum_saati', 'takvim'],
    lessonInvite: 'Tik tak, ders vakti!',
    storyInvite: 'Tam vaktinde bir hikâye!',
    testInvite: 'Süre başlasın mı?',
    chestInvite: 'Kapsülü açma vakti!',
  ),
  TopicTheme(
    id: 'alisveris',
    name: 'Alışveriş ve renkler',
    accent: Color(0xFFEE7FA6),
    motion: ThemeMotion.sway,
    steps: ['boya_kalemi', 'etiket', 'poset', 'cuzdan'],
    reward: 'hediye_kutusu',
    rewardName: 'Hediye kutusu',
    rewardLine: 'Kasadan hediye çıktı!',
    badge: 'etiket',
    badgeName: 'Etiket',
    decor: ['poset', 'boya_kalemi'],
    lessonInvite: 'Sepete bir ders ekle!',
    storyInvite: 'Çarşıda bir hikâye!',
    testInvite: 'Pazarlık zamanı!',
    chestInvite: 'Paketi aç bakalım!',
  ),
  TopicTheme(
    id: 'gunluk',
    name: 'Günlük hayat',
    accent: Color(0xFFF39A3D),
    motion: ThemeMotion.bob,
    steps: ['calar_saat', 'dis_fircasi', 'kupa', 'sirt_cantasi'],
    reward: 'kahvalti_tepsisi',
    rewardName: 'Kahvaltı tepsisi',
    rewardLine: 'Kahvaltı hazır!',
    badge: 'kupa',
    badgeName: 'Kupa',
    decor: ['sokak_lambasi', 'cicek_saksi'],
    lessonInvite: 'Günaydın, hadi başla!',
    storyInvite: 'Gün içinden bir hikâye!',
    testInvite: 'Günün sınavı seni bekler!',
    chestInvite: 'Tepside ne var?',
  ),
  TopicTheme(
    id: 'seyahat',
    name: 'Seyahat',
    accent: Color(0xFF3C7DD9),
    motion: ThemeMotion.sway,
    steps: ['bavul', 'bilet', 'ucak', 'oda_anahtari'],
    reward: 'hediye_bavul',
    rewardName: 'Hediye bavulu',
    rewardLine: 'Bavul hediye dolu!',
    badge: 'pusula',
    badgeName: 'Pusula',
    decor: ['palmiye', 'pusula'],
    lessonInvite: 'Biniş kartın hazır!',
    storyInvite: 'Yol hikâyesi başlıyor!',
    testInvite: 'Pasaport kontrolü!',
    chestInvite: 'Bavulu aç bakalım!',
    hat: 'sapka_kaptan',
  ),
  TopicTheme(
    id: 'sehir',
    name: 'Şehir',
    accent: Color(0xFFE4572E),
    motion: ThemeMotion.blink,
    steps: ['tabela', 'tramvay', 'trafik_lambasi', 'vapur'],
    reward: 'balonlar',
    rewardName: 'Balonlar',
    rewardLine: 'Şehir bayramda!',
    badge: 'tabela',
    badgeName: 'Tabela',
    decor: ['sokak_lambasi', 'agac'],
    lessonInvite: 'Tramvay kalkıyor, atla!',
    storyInvite: 'Vapurda bir hikâye!',
    testInvite: 'Yeşil yandı, sınava geç!',
    chestInvite: 'Balonları yakala!',
  ),
  TopicTheme(
    id: 'gecmis',
    name: 'Geçmiş zaman',
    accent: Color(0xFF8E5BC9),
    motion: ThemeMotion.blink,
    steps: ['foto_albumu', 'polaroid', 'radyo', 'gunluk_defter'],
    reward: 'ani_sandigi',
    rewardName: 'Anı sandığı',
    rewardLine: 'Sandıktan anılar çıktı!',
    badge: 'polaroid',
    badgeName: 'Fotoğraf',
    decor: ['kum_saati', 'polaroid'],
    lessonInvite: 'Albümü açalım mı?',
    storyInvite: 'Bir varmış, bir yokmuş!',
    testInvite: 'Geçmişi hatırla!',
    chestInvite: 'Sandığın kilidi açık!',
  ),
  TopicTheme(
    id: 'saglik',
    name: 'Sağlık',
    accent: Color(0xFFE4572E),
    motion: ThemeMotion.pulse,
    steps: ['kalp', 'termometre', 'stetoskop', 'ilac'],
    reward: 'ilk_yardim',
    rewardName: 'İlk yardım çantası',
    rewardLine: 'Şifa çantası açıldı!',
    badge: 'kalp',
    badgeName: 'Kalp',
    decor: ['elma', 'cicek_saksi'],
    lessonInvite: 'Geçmiş olsun, başlayalım!',
    storyInvite: 'Bekleme salonunda hikâye!',
    testInvite: 'Check-up zamanı!',
    chestInvite: 'Çantayı aç, iyileş!',
  ),
  TopicTheme(
    id: 'hava',
    name: 'Hava ve mevsimler',
    accent: Color(0xFF3C7DD9),
    motion: ThemeMotion.sway,
    steps: ['gunes', 'bulut', 'semsiye', 'kar_tanesi'],
    reward: 'gokkusagi',
    rewardName: 'Gökkuşağı',
    rewardLine: 'Yağmurdan sonra gökkuşağı!',
    badge: 'gunes',
    badgeName: 'Güneş',
    decor: ['bulut', 'agac'],
    lessonInvite: 'Hava ders için şahane!',
    storyInvite: 'Şemsiyeni al, hikâye var!',
    testInvite: 'Fırtınaya hazır mısın?',
    chestInvite: 'Gökkuşağının ucunda ne var?',
    hat: 'sapka_hasir',
  ),
  TopicTheme(
    id: 'hayaller',
    name: 'Planlar ve hayaller',
    accent: Color(0xFF8E5BC9),
    motion: ThemeMotion.pulse,
    steps: ['harita', 'yildiz', 'roket', 'dilek_feneri'],
    reward: 'hazine_sandigi',
    rewardName: 'Hazine sandığı',
    rewardLine: 'Hayallerin hazinesi!',
    badge: 'yildiz',
    badgeName: 'Yıldız',
    decor: ['yildiz', 'dilek_feneri'],
    lessonInvite: 'Bir dilek tut, başla!',
    storyInvite: 'Gelecekten bir hikâye!',
    testInvite: 'Yıldızına uzan!',
    chestInvite: 'Hazine haritası burayı gösteriyor!',
  ),
  TopicTheme(
    id: 'is',
    name: 'İş ve ofis',
    accent: Color(0xFF2B3A67),
    motion: ThemeMotion.bob,
    steps: ['evrak_cantasi', 'dosya', 'kupa', 'atas'],
    reward: 'kupa_odul',
    rewardName: 'Ayın çalışanı kupası',
    rewardLine: 'Ayın çalışanı sensin!',
    badge: 'evrak_cantasi',
    badgeName: 'Çanta',
    decor: ['cicek_saksi', 'dosya'],
    lessonInvite: 'Mesai başladı!',
    storyInvite: 'Ofis koridorunda hikâye!',
    testInvite: 'Performans değerlendirmesi!',
    chestInvite: 'Prim günü geldi!',
  ),
  TopicTheme(
    id: 'teknoloji',
    name: 'Teknoloji',
    accent: Color(0xFF2EA4A6),
    motion: ThemeMotion.blink,
    steps: ['telefon', 'kulaklik', 'dizustu', 'wifi'],
    reward: 'robot',
    rewardName: 'Robot',
    rewardLine: 'Bip bop, hediye!',
    badge: 'wifi',
    badgeName: 'Sinyal',
    decor: ['wifi', 'telefon'],
    lessonInvite: 'Telefon çalıyor, aç!',
    storyInvite: 'Hatta bir hikâye var!',
    testInvite: 'Sinyal tam, sınava!',
    chestInvite: 'Robotu çalıştır!',
    hat: 'kulaklik',
  ),
  TopicTheme(
    id: 'yazisma',
    name: 'Yazışma',
    accent: Color(0xFF2B3A67),
    motion: ThemeMotion.sway,
    steps: ['zarf', 'dolma_kalem', 'pul', 'posta_kutusu'],
    reward: 'koli',
    rewardName: 'Kargo kolisi',
    rewardLine: 'Kargon geldi!',
    badge: 'zarf',
    badgeName: 'Mühür',
    decor: ['posta_kutusu', 'zarf'],
    lessonInvite: 'Yeni bir e-postan var!',
    storyInvite: 'Mektup okunuyor!',
    testInvite: 'Gönder tuşuna bas!',
    chestInvite: 'Kapıda kargo var!',
  ),
  TopicTheme(
    id: 'duygular',
    name: 'Duygular ve ilişkiler',
    accent: Color(0xFFEE7FA6),
    motion: ThemeMotion.pulse,
    steps: ['gulen_yuz', 'kalp_balon', 'saskin_yuz', 'buket'],
    reward: 'pasta',
    rewardName: 'Kutlama pastası',
    rewardLine: 'Mumları üfle!',
    badge: 'kalp',
    badgeName: 'Kalp',
    decor: ['cicek', 'kalp_balon'],
    lessonInvite: 'İçini dök, başla!',
    storyInvite: 'Duygusal bir hikâye!',
    testInvite: 'Kalbin hazır mı?',
    chestInvite: 'Sürpriz parti!',
    hat: 'sapka_parti',
  ),
  TopicTheme(
    id: 'doga',
    name: 'Doğa',
    accent: Color(0xFF5BA55B),
    motion: ThemeMotion.sway,
    steps: ['yaprak', 'zeytin_dali', 'ari', 'agac'],
    reward: 'bal_kavanozu',
    rewardName: 'Bal kavanozu',
    rewardLine: 'Petekten taze bal!',
    badge: 'zeytin_dali',
    badgeName: 'Zeytin dalı',
    decor: ['cicek', 'agac'],
    lessonInvite: 'Yaprak kıpırdadı, başla!',
    storyInvite: 'Ağacın altında hikâye!',
    testInvite: 'Hasat zamanı!',
    chestInvite: 'Arılar bal yaptı!',
    hat: 'sapka_hasir',
  ),
  TopicTheme(
    id: 'spor',
    name: 'Spor ve beceriler',
    accent: Color(0xFF5BA55B),
    motion: ThemeMotion.bob,
    steps: ['top', 'raket', 'bisiklet', 'madalya'],
    reward: 'kupa_odul',
    rewardName: 'Şampiyonluk kupası',
    rewardLine: 'Şampiyon sensin!',
    badge: 'madalya',
    badgeName: 'Madalya',
    decor: ['top', 'agac'],
    lessonInvite: 'Isındın mı? Hadi!',
    storyInvite: 'Soyunma odasında hikâye!',
    testInvite: 'Final maçı başlıyor!',
    chestInvite: 'Kupayı kaldır!',
  ),
  TopicTheme(
    id: 'sanat',
    name: 'Müzik ve sanat',
    accent: Color(0xFF8E5BC9),
    motion: ThemeMotion.sway,
    steps: ['nota', 'gitar', 'palet', 'film_seridi'],
    reward: 'patlamis_misir',
    rewardName: 'Patlamış mısır',
    rewardLine: 'Film başlıyor, mısırlar hazır!',
    badge: 'nota',
    badgeName: 'Nota',
    decor: ['nota', 'palet'],
    lessonInvite: 'Sahne senin, çal bakalım!',
    storyInvite: 'Perde açılıyor!',
    testInvite: 'Konser vakti!',
    chestInvite: 'Mısırlar patladı!',
    hat: 'sapka_bere',
  ),
  TopicTheme(
    id: 'kutuphane',
    name: 'Eğitim ve kütüphane',
    accent: Color(0xFF3C7DD9),
    motion: ThemeMotion.sway,
    steps: ['kitap', 'kalem', 'gozluk', 'kep'],
    reward: 'kure',
    rewardName: 'Dünya küresi',
    rewardLine: 'Dünya avucunda!',
    badge: 'kep',
    badgeName: 'Kep',
    decor: ['kitap', 'kure'],
    lessonInvite: 'Sayfayı çevir!',
    storyInvite: 'Rafta bir masal var!',
    testInvite: 'Sınav kâğıdın hazır!',
    chestInvite: 'Küreyi çevir bakalım!',
    hat: 'kep',
  ),
  TopicTheme(
    id: 'haber',
    name: 'Haber ve medya',
    accent: Color(0xFFE4572E),
    motion: ThemeMotion.blink,
    steps: ['gazete', 'mikrofon', 'kamera', 'radyo'],
    reward: 'televizyon',
    rewardName: 'Televizyon',
    rewardLine: 'Son dakika: kazandın!',
    badge: 'mikrofon',
    badgeName: 'Mikrofon',
    decor: ['gazete', 'kamera'],
    lessonInvite: 'Yayındasın!',
    storyInvite: 'Manşette bir hikâye!',
    testInvite: 'Canlı yayın sınavı!',
    chestInvite: 'Ekranı aç!',
  ),
  TopicTheme(
    id: 'toplanti',
    name: 'Toplantı ve tartışma',
    accent: Color(0xFFF39A3D),
    motion: ThemeMotion.blink,
    steps: ['ampul', 'konusma', 'grafik', 'sunum_panosu'],
    reward: 'el_sikisma',
    rewardName: 'Anlaşma',
    rewardLine: 'El sıkıştık, anlaştık!',
    badge: 'ampul',
    badgeName: 'Fikir',
    decor: ['grafik', 'kupa'],
    lessonInvite: 'Söz sende!',
    storyInvite: 'Toplantı odasında hikâye!',
    testInvite: 'Oylama başlıyor!',
    chestInvite: 'Anlaşma imzalandı!',
  ),
  TopicTheme(
    id: 'sahne',
    name: 'Deyimler ve sahne',
    accent: Color(0xFFE4572E),
    motion: ThemeMotion.sway,
    steps: ['maske', 'spot', 'perde', 'mikrofon'],
    reward: 'buket',
    rewardName: 'Çiçek buketi',
    rewardLine: 'Ayakta alkış!',
    badge: 'maske',
    badgeName: 'Maske',
    decor: ['spot', 'buket'],
    lessonInvite: 'Perde! Sahne senin!',
    storyInvite: 'Kuliste bir hikâye!',
    testInvite: 'Büyük gala!',
    chestInvite: 'Çiçekler sana!',
    hat: 'sapka_bere',
  ),
  TopicTheme(
    id: 'dedektif',
    name: 'İpuçları ve tahmin',
    accent: Color(0xFFA0673A),
    motion: ThemeMotion.sway,
    steps: ['buyutec', 'ayak_izi', 'parmak_izi', 'fotr'],
    reward: 'kasa',
    rewardName: 'Gizli kasa',
    rewardLine: 'Kasa açıldı, dava çözüldü!',
    badge: 'buyutec',
    badgeName: 'Büyüteç',
    decor: ['ayak_izi', 'sokak_lambasi'],
    lessonInvite: 'Bir ipucu buldum!',
    storyInvite: 'Dosya açılıyor!',
    testInvite: 'Katil uşak mı?',
    chestInvite: 'Şifreyi çözdün!',
    hat: 'fotr',
  ),
  TopicTheme(
    id: 'olasilik',
    name: 'Olasılıklar',
    accent: Color(0xFF5BA55B),
    motion: ThemeMotion.wiggle,
    steps: ['yol_ayrimi', 'zar', 'madeni_para', 'yonca'],
    reward: 'hazine_sandigi',
    rewardName: 'Şans sandığı',
    rewardLine: 'Şansın yaver gitti!',
    badge: 'yonca',
    badgeName: 'Yonca',
    decor: ['yonca', 'tabela'],
    lessonInvite: 'Zarı at!',
    storyInvite: 'Ya öyle olsaydı?',
    testInvite: 'Yazı mı, tura mı?',
    chestInvite: 'Dört yapraklı yonca!',
  ),
  TopicTheme(
    id: 'tamir',
    name: 'Tamir ve hizmet',
    accent: Color(0xFFF4C542),
    motion: ThemeMotion.wiggle,
    steps: ['ingiliz_anahtari', 'boya_rulosu', 'makas', 'araba'],
    reward: 'alet_cantasi',
    rewardName: 'Alet çantası',
    rewardLine: 'Usta işi hediye!',
    badge: 'ingiliz_anahtari',
    badgeName: 'Anahtar',
    decor: ['boya_rulosu', 'agac'],
    lessonInvite: 'Kolları sıvadık!',
    storyInvite: 'Tamirhanede hikâye!',
    testInvite: 'Usta işi sınav!',
    chestInvite: 'Çantayı aç, usta!',
    hat: 'sapka_kask',
  ),
  TopicTheme(
    id: 'mulakat',
    name: 'İş görüşmesi',
    accent: Color(0xFF2B3A67),
    motion: ThemeMotion.bob,
    steps: ['cv', 'kravat', 'mulakat_masasi', 'el_sikisma'],
    reward: 'evrak_cantasi',
    rewardName: 'Yeni iş çantası',
    rewardLine: 'İşe alındın!',
    badge: 'kravat',
    badgeName: 'Kravat',
    decor: ['cicek_saksi', 'kupa'],
    lessonInvite: 'Kravatını düzelt!',
    storyInvite: 'Bekleme salonunda hikâye!',
    testInvite: 'Mülakat masası hazır!',
    chestInvite: 'Teklif mektubu geldi!',
  ),
  TopicTheme(
    id: 'otel',
    name: 'Otel resepsiyonu',
    accent: Color(0xFF8E5BC9),
    motion: ThemeMotion.wiggle,
    steps: ['resepsiyon_zili', 'oda_anahtari', 'havlu', 'kapi_askisi'],
    reward: 'hediye_kutusu',
    rewardName: 'Karşılama hediyesi',
    rewardLine: 'Odana hediye bırakıldı!',
    badge: 'resepsiyon_zili',
    badgeName: 'Zil',
    decor: ['palmiye', 'bavul'],
    lessonInvite: 'Zil çaldı, misafir geldi!',
    storyInvite: 'Lobide bir hikâye!',
    testInvite: 'Beş yıldız sınavı!',
    chestInvite: 'Oda servisi!',
  ),
  TopicTheme(
    id: 'kod',
    name: 'Kod ve terminal',
    accent: Color(0xFF2EA4A6),
    motion: ThemeMotion.blink,
    steps: ['terminal', 'kod', 'git_dali', 'bocek'],
    reward: 'robot',
    rewardName: 'Robot',
    rewardLine: 'Build başarılı!',
    badge: 'kod',
    badgeName: 'Kod',
    decor: ['kupa', 'dizustu'],
    lessonInvite: 'git commit -m "ders"',
    storyInvite: 'Kod incelemesinde hikâye!',
    testInvite: 'Testler koşuyor!',
    chestInvite: 'Merge edildi!',
    hat: 'kulaklik',
  ),
];

final topicThemes = {for (final t in _themes) t.id: t};

/// The theme of a software vocabulary topic (Yazılımcı İngilizcesi).
const softwareThemeId = 'kod';

/// Object for a software vocabulary topic, by its position.
String softwareTopicObject(int index) =>
    const ['kod', 'git_dali', 'bocek', 'terminal', 'dizustu', 'robot', 'kupa', 'kulaklik'][index % 8];
