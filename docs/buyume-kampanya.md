# Büyüme kampanyaları: Arkadaşını getir, sınav sezonu, Günün okuması

Ücretsiz ve organik büyüme için üç parça. Fiyatlar değişmez (Premium aylık
149 TL, mevcut Play ürünleri). Hiçbiri Çocuk modunda Premium/davet arayüzü
göstermez.

## 1. Arkadaşını getir (davet)

Kod sistemi ve kurallar: [analitik.md#davet](analitik.md#davet). Bu sürümle
değişenler:

- **Ödül zamanı:** Arkadaş kodu girer (`redeemInvite`) → kayıt `pending`.
  Arkadaşın ilk dersi eşitlenince (`users/{uid}.progress.lessonsDone >= 1`)
  `inviteFirstLesson` Firestore tetikleyicisi iki tarafa da **7 gün Premium**
  yazar. Arkadaş kodu girmeden önce ders bitirmişse ödül hemen verilir.
- **Kaynak:** `entitlements/{uid}` → `source: "invite"`, `productId: "referral"`
  (eski uygulama sürümleri tanısın diye ürün kimliği aynı kaldı), `referralDays` artar.
- **Daha uzun Premium kısalmaz:** Süren Play/aile/kurum Premium'u kaynağını
  korur, bitişine 7 gün eklenir. Bitişi olmayan (süresiz) bir Premium'a
  dokunulmaz. Bitmiş davet Premium'u bugünden yeniden başlar.
- **Kötüye kullanım:** aynı cihaz (`device_used`, `same_device`: davet edenin
  telefonu), kendi kod (`own_code`), karşılıklı davet, yalnızca yeni ve bağlı
  hesap, davet eden için **ayda 5 ödül** sınırı (sınır ödül anında sayılır).
- **Bilinen sınır:** `lessonsDone` istemcinin yazdığı ilerleme belgesinden
  okunur; hile ile 1 yazılabilir. Cihaz/hesap/aylık sınırlar zararı sınırlar.

Uygulamada görünür yerler (Çocuk modunda hiçbiri yok, Remote Config
`referral_enabled` kapalıysa da yok):

| Yer | Dosya |
| --- | --- |
| Profil: "Arkadaşını getir" vurgulu kartı | `lib/screens/growth_profile_section.dart` |
| Kusursuz ders sonu (stoacı söz kartı yoksa) | `lib/screens/lesson_result_screen.dart` → `InviteNudge` |
| Seri kutlaması (3+ gün, 7/30/100 Premium kartı olmayan günler) | aynı dosya |
| Paylaş sayfası: hazır mesaj + `dilmacPlayStoreUrl` (kodlu referrer) | `lib/services/growth/referral.dart`, `lib/screens/invite_nudge.dart` |

Ders sonu ve seri kartı birlikte **3 günde en çok bir kez** görünür
(`growth.invite_nudge.shown_ms`).

## 2. Sınav sezonu: "Sınava kadar Premium"

Sınava **8 hafta** kala, hedefi o sınav olan kullanıcı Öğren'in üstünde geri
sayım ve "Sınava kadar Premium" kartı görür. Hedef = "Hedefin ne?" sınavı
(YDS/YÖKDİL); yoksa çalıştığı sınav yolu (YDS, LGS).

- Kart `PaywallPacer.canOffer` ile açılır: Premium, Çocuk modu ve son günlerde
  kapatılmış paywall varken teklif yok, yalnızca geri sayım kalır (kullanıcının
  kendi sınav tarihi zaten hedef kartında sayılıyorsa o da gizlenir).
- Kart kapatılırsa 7 gün teklif gösterilmez (`growth.exam_season.dismissed_ms`).
- Dokununca mevcut paywall açılır (`placement: exam_season`), aynı ürünler ve fiyatlar.

### Tarihleri güncelleme (sahip)

Firestore'da `config/examCampaigns` belgesi (giriş yapmış herkes okuyabilir,
kimse yazamaz; konsoldan düzenlenir). Belge yoksa uygulamadaki varsayılanlar
kullanılır (`lib/services/growth/exam_campaign.dart`):

```json
{
  "exams": {
    "yds":    { "label": "YDS",    "dates": ["2027-03-28", "2027-11-21"], "weeksBefore": 8, "enabled": true, "promoOfferId": "" },
    "yokdil": { "label": "YÖKDİL", "dates": ["2027-02-28", "2027-07-25"], "weeksBefore": 8, "enabled": true, "promoOfferId": "" },
    "lgs":    { "label": "LGS",    "dates": ["2027-06-13"],               "weeksBefore": 8, "enabled": true, "promoOfferId": "" }
  }
}
```

Varsayılanlar ÖSYM'nin 28 Ekim 2026'da yayımladığı 2027 takvimi ve MEB 2027
sınav takviminden alındı; ÖSYM tarihleri değiştirirse belgeyi güncelleyin.
Eksik alan varsayılanı korur; bilinmeyen sınavlar yok sayılır. Uygulama son
okunan sürümü telefonda saklar.

### Play promosyon teklifi (isteğe bağlı, yer tutucu)

Fiyat değişmez; istenirse sınav dönemine özel ücretsiz deneme süresi Play'de
bir **teklif (offer)** olarak tanımlanabilir:

1. Play Console > Para kazanma > Ürünler > Abonelikler > Premium aboneliği >
   temel plan (aylık veya yıllık) > **Teklif ekle**.
2. Uygunluk: "Yeni müşteri edinme" (daha önce abone olmamışlar). Aşama:
   örn. 7 günlük ücretsiz deneme. Fiyat aşaması eklemeyin (fiyat aynı kalsın).
3. Teklif kimliği verin, örn. `yds-2027-bahar`, ve etiket ekleyin.
4. Kimliği `config/examCampaigns.exams.yds.promoOfferId` alanına yazın.

Not: Uygulama bu kimliği şimdilik yalnızca okur (`ExamCampaign.promoOfferId`);
satın almada bu teklifi seçmek `IapBillingService.loadProducts`'a küçük bir
ekleme ister (o dosya başka bir oturumda değişiyor). Bugün Play, kullanıcıya
uygun teklifi kendisi döndürür.

## 3. Günün okuması

Her gün Türkiye saatiyle 00:20'de `generateDailyReadings` (zamanlanmış Cloud
Function, `functions/src/daily_reading.ts`) her CEFR bandı (A1–C1) için bir
kısa özgün metin üretir: 5 açıklamalı kelime, 3 soru, Türkçe özet ve sohbet
başlatma sorusu. Model: `claude-sonnet-5-5` (diğer fonksiyonlarla aynı
`ANTHROPIC_API_KEY` sırrı). Günde 5 çağrı.

- Konum: `daily/{yyyy-mm-dd}` (gün özeti) ve `daily/{yyyy-mm-dd}/levels/{A1..C1}`.
  (Firestore'da belge yolu çift parçalı olmalı; bu yüzden `levels` alt koleksiyonu.)
- Güvenlik: yalnızca giriş yapmış kullanıcılar okur, yazma yalnızca fonksiyon.
- İçerik kuralları: tamamen özgün kurgu ya da uydurma "haber tadında" yerel
  hikâye; gerçek haber, gerçek kişi, marka, alıntı yok; gençlere uygun konu
  listesi (`TOPICS`). Çıktı doğrulanır (uzunluk, 5 kelime metinde geçiyor,
  3 soru × 4 şık); geçmezse bir kez yeniden denenir, olmazsa o bant atlanır.
- Yeniden çalıştırma yalnızca eksik bantları doldurur; hata olursa fonksiyon
  hata verir ve Cloud Scheduler 2 kez yeniden dener.
- Uygulama: Öğren'de "Günün okuması · B1" satırı (bugün bitirince gizlenir),
  `lib/screens/daily_reading_screen.dart`. Bant: son Seviye Karnesi, yoksa
  yola göre tahmin; kullanıcı değiştirebilir. Bugünkü yoksa dünkü gösterilir.
- **Çevrimdışı:** son 5 günün okumaları telefonda (`growth.daily_reading.cache`).

### "Bunu konuşalım" (Premium) — sesli sohbet ile sözleşme

`lib/services/talk_about.dart`: `talkAboutLauncherProvider` ve `TalkTopic`
(`topic` ≤ 60 karakter = sunucudaki `cleanTopic` sınırı, `context` = metnin
tamamı, `opener`, `level`). Sesli sohbet ekranı (`feature/dogal-konusma`)
`main.dart`'ta bu sağlayıcıyı kendi açıcısıyla override eder ve sunucuya
`{ mode: "free", topic }` gönderir. Açıcı kayıtlı değilken düğme gizlidir;
Premium olmayan kullanıcıda düğme kilitli görünür ve paywall'u açar
(`placement: daily_reading_talk`).

## Dağıtım (sahip, onaylı)

```bash
firebase deploy --only firestore:rules,functions:generateDailyReadings,functions:inviteFirstLesson,functions:getInviteStatus,functions:getInviteCode,functions:redeemInvite --project dilbaz-3392e
```

- `inviteFirstLesson` bir Firestore tetikleyicisidir (europe-west1); veritabanı
  konumunun bölgeyle uyumlu olduğunu kontrol edin.
- Cloud Scheduler API açık olmalı (zamanlanmış fonksiyon için).
- `config/examCampaigns` belgesini konsoldan oluşturmak isteğe bağlıdır.
