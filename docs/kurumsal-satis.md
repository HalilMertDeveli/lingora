# Dilmaç Kurumsal: satış sayfası

> Dershane, okul ya da şirket ziyaretinde gösterilecek tek sayfa. Altta, sahibin bilmesi gereken
> süreç ve teknik notlar var (bunlar müşteriye gösterilmez).

---

## Dilmaç Kurumsal

**Öğrencileriniz İngilizceyi konuşarak çalışsın, siz ilerlemeyi görün.**

Dilmaç, Türkçe konuşanlar için hazırlanmış bir İngilizce uygulamasıdır. Kurumsal pakette her öğrenci
Dilmaç Premium kullanır, öğretmen de sınıfının ilerlemesini telefonundan izler.

### Öğrenci ne yapar?
- Günde 5–10 dakikalık kısa dersler: kelime, gramer, okuma, telaffuz.
- **Yapay zekâ ile sesli konuşma:** kafede sipariş, otel resepsiyonu, iş görüşmesi gibi gerçek senaryolar.
- Her konuşmadan sonra **konuşma karnesi:** Türkçe değerlendirme, düzeltilen cümleler, zorlandığı kelimeler.
- **LGS** ve **YDS/YÖKDİL** soru tiplerinde açıklamalı pratik ve mini denemeler.
- Reklam yok, ceza ya da can sistemi yok.

### Öğretmen ne görür?
| Her öğrenci için | Sınıfın tamamı için |
|---|---|
| Seri (kaç gündür aralıksız çalışıyor) | Haftalık toplam XP |
| Tamamlanan ünite ve ders | Sınıfın en sık hata türleri |
| Bu haftanın XP'si | Kaç öğrencinin konuşma pratiği yaptığı, toplam dakika |
| En sık 3 hata türü | |
| **Konuşma:** sayı, yaklaşık dakika, son karne özeti, son düzeltmeler, telaffuzda zorlandığı kelimeler | |

Öğretmen sınıfı uygulamadan açar, sınıf kodunu paylaşır. Herkes katılınca katılımı kapatır.

### Gizlilik (KVKK)
- Öğretmen öğrencinin e-postasını, telefonunu, notlarını ve sohbetlerinin tamamını **görmez**.
- Öğrenci sınıfa ilk adıyla ya da takma adla katılır; ayrıldığı anda öğretmenin erişimi biter.
- Ses kaydı sunucuya gitmez. Reklam ve reklam kimliği yok.
- Sözleşmeyle birlikte veli bilgilendirme metni örneği verilir.

### Fiyat
**Koltuk başı yıllık lisans; size özel teklif.** Fiyat öğrenci sayısı, süre (eğitim yılı ya da 12 ay) ve
öğretmen sayısına göre belirlenir. Öğretmen koltukları pakete dahildir. Fatura kurum adına kesilir.

### 30 gün ücretsiz deneme
Bir öğretmen ve bir sınıf için deneme kodları. Kart bilgisi yok, otomatik ücret yok; 30. günün sonunda
kodlar kendiliğinden kapanır.

### Başlamak için
- Web: **dilbaz-3392e.web.app/kurumsal** → "Teklif alın" formu
- E-posta: **dilmac.destek@gmail.com**

---

## Sahibin notları (müşteriye gösterilmez)

### Ziyaret akışı
1. Bu sayfayı ya da telefondan `/kurumsal` sayfasını gösterin. Uygulamada bir sınıf açıp öğretmen panelini
   canlı gösterin.
2. İlgilenirlerse ya formu orada doldurun ya da panelden doğrudan deneme kodu üretin (aşağıda).
3. Deneme süresince bir kez arayın: kaç öğrenci katıldı, kaç konuşma yapıldı (öğretmen panelinde görünür).
4. 30. günden önce teklif: fiyat aralıkları `docs/kurumlar.md` bölüm 5'te (öğrenci başı yıllık 175–250 TL,
   en az 20 koltuk). Fiyatı sayfaya yazmıyoruz; görüşmede verin.

### Talepler (lead) nereye düşer?
- Form `POST /api/kurumsal-talep` → `submitLead` fonksiyonu → Firestore `leads/`. **E-posta gönderilmez.**
- Görmek için yönetim paneli (Flutter web, `lib/admin`) → Dilmaç ekibi hesabıyla giriş → **Talepler**.
  Durum (Yeni, Arandı, Denemede, Müşteri, Kapandı), not ekleme, silme (KVKK silme talebi) ve
  **"Deneme kodu üret"** buradadır.
- Uygulamadan hiç kimse `leads/` okuyamaz (kural); yalnızca `leadList` callable'ı ve yalnızca Dilmaç
  yöneticisi (`config/lingoraAdmins` ya da `isLingoraAdmin` claim).

### Deneme kodu
- Panel → **Deneme kodu** (ya da bir talebin üstünde "Deneme kodu üret"): kurum adı, öğrenci koltuğu
  (en fazla 60), öğretmen koltuğu (1–3). `trialCreate` callable'ı her koltuk için bir `licenseCodes/{kod}`
  yazar: `trial: true`, bitiş = 30 gün sonrası, Türkiye saatiyle 23.59.
- Kodlar mevcut lisans sistemiyle aynıdır (`docs/kurumlar.md`): öğretmen kodu girip sınıf açar,
  öğrenciler kendi kodlarını girer. Süre bitince kural sahiplenmeyi reddeder, uygulama Premium'u kapatır;
  ayrıca bir şey yapmak gerekmez.
- Müşteri olunca: yeni parti `license_codes.mjs create` ile üretilir ya da deneme partisi
  `extend --batch <parti> --until <tarih>` ile uzatılır (öğrenciler kod değiştirmez).

### Konuşma raporu nereden gelir?
- Öğrenci Ses Koçu'nda karne istediğinde (`conversationReport`) sunucu `speakingStats/{uid}`'i günceller:
  konuşma sayısı, tahmini dakika (konuşmadaki kelime sayısı / 100), son karne özeti, son 5 düzeltme,
  zorlanılan kelimeler. Konuşma metni saklanmaz.
- Aynı anda öğrencinin üye olduğu her sınıfa bir kopya yazar: `classes/{kod}/speaking/{uid}`
  (yalnızca `classes/{kod}/members/{uid}` varken). Öğretmen ve öğrenci okuyabilir, ikisi de silebilir;
  uygulama yazamaz. Öğrenci ayrılınca / çıkarılınca / sınıf silinince kopya silinir.
- Callable modelindeki kurum paneli (`orgReport`) aynı özeti "Konuşma" sütununda gösterir; yalnızca
  kuruma katılmış üyeler için.
- Not: Öğrenci yeni katıldıysa özet ilk karnesinden sonra görünür (önceki konuşmalar o an kopyalanmaz).

### Yayına almak için (orkestratör; bu PR yayınlamaz)
```bash
firebase deploy --project prod --only functions:submitLead,functions:leadList,functions:leadUpdate,functions:leadDelete,functions:trialCreate,functions:conversationReport,functions:orgReport,functions:deleteAccount
firebase deploy --project prod --only firestore:rules
firebase deploy --project prod --only hosting:yasal     # /kurumsal + /api/kurumsal-talep rewrite
```
- Hosting rewrite fonksiyondan önce yayınlanırsa form "Gönderilemedi" der; önce fonksiyonları yayınlayın.
- İsteğe bağlı: Firestore TTL politikası `leadRate` koleksiyonunda `expireAt` alanına (sayaçlar 2 gün sonra silinir).
- Admin paneli yeniden derlenip `hosting:admin`'e yayınlanmalı (Talepler ve Deneme kodu ekranları).

### Güvenlik ve sınırlar
- Form: alan doğrulaması, gizli "website" tuzak alanı, aynı IP'den günde 3, toplamda günde 100 talep,
  yalnızca `dilbaz-3392e.web.app` / `firebaseapp.com` kaynaklı tarayıcı istekleri. IP saklanmaz; günlük
  sayaç için gün + IP'nin SHA-256 özeti kullanılır. Projede App Check kullanılmadığı için eklenmedi.
- IP, Firebase Hosting'in `Fastly-Client-IP` başlığından alınır; doğrudan fonksiyon adresine giden biri
  bunu değiştirebilir, bu yüzden genel günlük sınır da var.
- Gizlilik metni (`/gizlilik` 2.6, 2.8, 2.12, 5) güncellendi. `docs/magaza/veri-guvenligi.md` (Play veri
  güvenliği formu) `yayin-oncesi` çalışmasına ait olduğu için değiştirilmedi: Ses Koçu satırına "karne özeti
  ve son düzeltmeler hesapta saklanır, öğretmenle paylaşılır" eklenmeli.
