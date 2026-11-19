/// Profil > Yardım ve SSS: the questions and answers.
///
/// To edit: change the text below, keep `soru`/`cevap` in plain Turkish
/// (no Markdown). `etiketler` are extra search words that do not appear in
/// the text (e.g. "para", "ücret"). Order = order on screen. The screen is
/// lib/screens/help_screen.dart; the contact address is [destekEposta].
library;

/// Where "Bize yaz" sends the e-mail.
const destekEposta = 'dilmac.destek@gmail.com';

class Sss {
  const Sss({required this.baslik, required this.soru, required this.cevap, this.etiketler = const []});

  /// Short group name shown above the question ("Abonelik", "Ses", …).
  final String baslik;
  final String soru;
  final String cevap;
  final List<String> etiketler;
}

const sssListesi = <Sss>[
  // ---- Abonelik ----
  Sss(
    baslik: 'Abonelik',
    soru: 'Premium aboneliğimi nasıl iptal ederim?',
    cevap:
        'Abonelikler Google Play üzerinden yönetilir. Play Store uygulamasını aç, sağ üstteki profil '
        'resmine dokun, Ödemeler ve abonelikler > Abonelikler bölümünden Çenebaz\'ı seç ve "Aboneliği '
        'iptal et"e dokun. İptal ettiğinde Premium, ödediğin dönemin sonuna kadar açık kalır. '
        'Uygulamayı silmek aboneliği iptal etmez.',
    etiketler: ['abonelik', 'iptal', 'premium', 'durdur', 'yenileme', 'google play'],
  ),
  Sss(
    baslik: 'Abonelik',
    soru: 'Ücret iadesi alabilir miyim?',
    cevap:
        'Ödemeleri Google Play alır, bu yüzden iadeyi de Google Play yapar. Satın alımdan sonraki ilk '
        '48 saat içinde play.google.com adresinde Hesap > Sipariş geçmişi bölümünden ilgili satın alımı '
        'seçip "Sorun bildir" ile iade isteyebilirsin. 48 saat geçtiyse bize "Bize yaz" ile ulaş, '
        'Google Play\'in iade kuralları içinde yardımcı oluruz. İade edilen abonelikte Premium kapanır, '
        'ilerlemen silinmez.',
    etiketler: ['iade', 'para', 'ücret', 'geri ödeme', 'refund'],
  ),
  Sss(
    baslik: 'Abonelik',
    soru: 'Satın aldım ama Premium açılmadı / yeni telefonda Premium yok.',
    cevap:
        'Premium ekranının altındaki "Satın alımları geri yükle"ye dokun. Satın alımı yaptığın Google '
        'hesabının telefonda Play Store\'da açık olması gerekir. Sınav paketleri için paket ekranındaki '
        'aynı düğmeyi kullan. Ödeme bekleniyorsa (ör. nakit ödeme) onaylandığında Premium kendiliğinden '
        'açılır. Hâlâ açılmıyorsa "Bize yaz" ile Google Play sipariş numarasını (GPA. ile başlar) gönder.',
    etiketler: ['geri yükle', 'restore', 'satın alma', 'premium açılmadı', 'ödeme', 'paket'],
  ),
  Sss(
    baslik: 'Abonelik',
    soru: 'Aile planı nasıl çalışır?',
    cevap:
        'Aile planında bir kişi yıllık ödeme yapar, 5 kişiye kadar herkes kendi hesabıyla Premium '
        'kullanır. Planı alan kişi Profil > Aile planı bölümünden bir davet kodu oluşturur ve yalnızca '
        'ailesiyle paylaşır. Kodu alan kişi kendi telefonunda giriş yapar ve aynı bölümden koda katılır. '
        'Herkesin ilerlemesi kendine aittir, kimse başkasının derslerini göremez. Aile planı için giriş '
        'yapmış bir hesap gerekir.',
    etiketler: ['aile', 'family', 'davet kodu', 'paylaş', 'çocuk', 'eş'],
  ),
  Sss(
    baslik: 'Kurum',
    soru: 'Okulumun / kurumumun verdiği kodu nereye yazarım?',
    cevap:
        'Profil > Kurum koduyla katıl bölümüne öğretmeninin ya da kurumunun verdiği kodu yaz. Kurum '
        'lisansı varsa Premium kendiliğinden açılır. Kurum yalnızca ders, XP, seri ve ödev durumunu '
        'görür; notların, yazdıkların ve ses kayıtların paylaşılmaz. Kurumdan ayrılmak için aynı bölümü '
        'kullan.',
    etiketler: ['kurum', 'okul', 'öğretmen', 'sınıf', 'kod', 'lisans', 'şirket'],
  ),

  // ---- Ses ve mikrofon ----
  Sss(
    baslik: 'Ses ve mikrofon',
    soru: 'Mikrofon çalışmıyor, konuştuğumu algılamıyor.',
    cevap:
        '1) Telefonun Ayarlar > Uygulamalar > Çenebaz > İzinler bölümünden Mikrofon iznini aç. '
        '2) Konuşma tanıma Google\'ın ses hizmetini kullanır: Google uygulamasının ve "Google Konuşma '
        'Hizmetleri"nin güncel ve açık olduğundan emin ol. 3) İnternet bağlantını kontrol et. '
        '4) Mikrofona dokunduktan sonra kısa bir an bekleyip net ve normal hızda konuş; ortam '
        'gürültülüyse sessiz bir yere geç. 5) Bluetooth kulaklık bağlıysa bir kez çıkarıp tekrar dene. '
        'Olmazsa her konuşma alıştırmasında yazarak devam edebilirsin.',
    etiketler: ['mikrofon', 'konuşma', 'ses tanıma', 'izin', 'algılamıyor', 'telaffuz'],
  ),
  Sss(
    baslik: 'Ses ve mikrofon',
    soru: 'Ses gelmiyor, İngilizce okunuşları duyamıyorum.',
    cevap:
        'Önce telefonun medya sesini (yalnızca zil sesini değil) aç ve sessiz modu kontrol et. Çenebaz\'ın '
        'Görünüm ayarlarında ses efektlerinin açık olduğuna bak. Okunuşların bir kısmı telefonun metin '
        'okuma motoruyla çalınır: Ayarlar > Erişilebilirlik > Metin okuma çıkışı bölümünde "Google '
        'Konuşma Hizmetleri"ni seç ve İngilizce ses verisini indir. Bluetooth cihaz bağlıysa ses oraya '
        'gidiyor olabilir.',
    etiketler: ['ses', 'hoparlör', 'duyamıyorum', 'okunuş', 'tts', 'sessiz', 'kulaklık'],
  ),

  // ---- Hesap ve ilerleme ----
  Sss(
    baslik: 'Hesap ve ilerleme',
    soru: 'İlerlemem kayboldu / telefon değiştireceğim.',
    cevap:
        'İlerlemen yalnızca giriş yapmış bir hesapta buluta kaydedilir. Misafir olarak kullanıyorsan '
        'ilerleme sadece o telefondadır. Eski telefonunda Profil > Hesap bölümünden Google, e-posta ya da '
        'telefon numarasıyla giriş yap; yeni telefonda aynı yöntemle giriş yaptığında XP, seri ve '
        'derslerin geri gelir. Uygulamayı silmeden önce mutlaka giriş yap. Giriş yaptığın hâlde ilerleme '
        'görünmüyorsa internete bağlanıp birkaç saniye bekle; olmazsa "Bize yaz".',
    etiketler: ['ilerleme', 'kayboldu', 'silindi', 'yeni telefon', 'cihaz', 'yedek', 'giriş', 'senkron'],
  ),
  Sss(
    baslik: 'Hesap ve ilerleme',
    soru: 'Hesabımı nasıl silerim?',
    cevap:
        'Profil > Hesap > "Hesabımı sil" ile hesabın ve sunucudaki tüm verilerin (ilerleme, lig, '
        'arkadaşlıklar) kalıcı olarak silinir. Bu işlem geri alınamaz. Abonelik hesap silinince '
        'kendiliğinden iptal olmaz: önce Google Play\'den iptal et. Uygulamaya erişemiyorsan '
        'dilbaz-3392e.web.app/hesap-silme sayfasındaki adımlarla e-postayla da silme isteyebilirsin.',
    etiketler: ['hesap sil', 'silme', 'kapat', 'verilerimi sil', 'kvkk'],
  ),

  // ---- Çocuk modu ----
  Sss(
    baslik: 'Çocuk modu',
    soru: 'Çocuk modu nedir, çocuğum tek başına kullanabilir mi?',
    cevap:
        'Çocuk modu Profil > Görünüm bölümünden açılır. Daha sade bir görünüm, çocuklara uygun dersler '
        've maskot Pofuduk gelir; arkadaş ekleme kapanır, fotoğraf ve bayraklar gizlenir. Çenebaz çocuklar için bir ebeveyn '
        'ya da öğretmen gözetiminde kullanılmak üzere tasarlandı: hesabı, satın alımları ve ayarları bir '
        'yetişkin yönetmeli. Çocuk modunu yalnızca bir yetişkin kapatmalı.',
    etiketler: ['çocuk', 'ebeveyn', 'veli', 'gözetim', 'yaş', 'pofuduk', 'kid'],
  ),

  // ---- Bildirimler ----
  Sss(
    baslik: 'Bildirimler',
    soru: 'Hatırlatma bildirimleri gelmiyor ya da çok geliyor.',
    cevap:
        'Profil > Bildirimler bölümünden günlük hatırlatmayı açıp kapatabilir ve saatini seçebilirsin. '
        'Bildirim gelmiyorsa telefonun Ayarlar > Uygulamalar > Çenebaz > Bildirimler bölümünden izni aç. '
        'Bazı telefonlarda pil tasarrufu bildirimleri geciktirir: Ayarlar > Pil bölümünden Çenebaz için '
        '"Kısıtlama yok" seç.',
    etiketler: ['bildirim', 'hatırlatma', 'alarm', 'saat', 'pil'],
  ),

  // ---- Gizlilik ----
  Sss(
    baslik: 'Veri ve gizlilik',
    soru: 'Hangi verilerimi topluyorsunuz?',
    cevap:
        'Ders ilerlemen (XP, seri, bitirdiğin dersler) hesabına kaydedilir. Ses kayıtların telefonunda '
        'kalır; konuşma pratiğinde yalnızca yazıya dökülmüş metin işlenir. Kullanım istatistikleri '
        '(Firebase Analytics) yalnızca izin verirsen ve kimliğini içermeden toplanır; reklam yoktur, '
        'verilerin satılmaz. Kararını Profil > Gizlilik bölümünden istediğin zaman değiştirebilirsin. '
        'Ayrıntılar: Profil > Gizlilik > Gizlilik Politikası.',
    etiketler: ['gizlilik', 'veri', 'kvkk', 'izin', 'analitik', 'kişisel', 'reklam'],
  ),
];
