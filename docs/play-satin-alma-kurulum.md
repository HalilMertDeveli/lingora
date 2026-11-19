# Google Play satın alma doğrulaması: kurulum

Bu belge, gerçek Google Play satın almalarının Premium açması için **senin**
(uygulama sahibinin) bir kez yapman gerekenleri anlatır. Kod hazır:

- `verifyPurchase` (Cloud Functions, europe-west1): uygulama satın alma
  jetonunu gönderir, sunucu Google Play Developer API'ye sorar, doğruysa
  `entitlements/{uid}` belgesine Premium'u (veya sınav paketini) yazar ve
  satın almayı onaylar (acknowledge). Onaylanmayan satın almaları Google
  3 gün sonra iade eder; bunu sunucu otomatik yapar.
- `playRtdn` (Pub/Sub, `play-rtdn` konusu): Google'ın gerçek zamanlı
  bildirimlerini dinler. Yenileme, iptal, ödeme sorunu (grace / on hold),
  süre bitişi ve iade olduğunda Premium'u günceller veya kapatır.
- Bir satın alma jetonu yalnızca **bir** Çenebaz hesabına bağlanır. Başka
  hesap aynı jetonu denerse "Bu abonelik başka bir Çenebaz hesabına bağlı"
  hatası görür.
- Hiçbir anahtar dosyası yoktur: sunucu, Cloud Functions'ın kendi servis
  hesabıyla (Application Default Credentials) giriş yapar.

Aşağıdaki adımları sırayla yap. Proje: **dilbaz-3392e**, paket adı:
**com.lingora.lingora**.

---

## 1. Hangi servis hesabı?

2. nesil (v2) Cloud Functions, varsayılan olarak **Compute Engine varsayılan
servis hesabıyla** çalışır (App Engine hesabı `dilbaz-3392e@appspot.gserviceaccount.com`
yalnızca eski 1. nesil fonksiyonlarda kullanılır). Bizim proje numaramız
`1069247179653`, yani hesap:

```
1069247179653-compute@developer.gserviceaccount.com
```

Emin olmak için (fonksiyonlar bir kez deploy edildikten sonra):
Google Cloud Console > **Cloud Run** > `verifypurchase` hizmeti > **Güvenlik**
sekmesi > "Hizmet hesabı". Orada yazan e-posta neyse 3. adımda onu davet et.

## 2. Google Play Android Developer API'yi aç

Google Cloud Console'da (proje **dilbaz-3392e**):
**API'ler ve Hizmetler > Kitaplık** > "Google Play Android Developer API" > **Etkinleştir**.

Ya da terminalden:

```bash
gcloud services enable androidpublisher.googleapis.com --project dilbaz-3392e
```

## 3. Servis hesabını Play Console'a davet et

Play Console > **Kullanıcılar ve izinler** > **Yeni kullanıcıları davet et**:

1. E-posta: 1. adımdaki hesap (`1069247179653-compute@developer.gserviceaccount.com`).
2. **Uygulama izinleri** sekmesi > **Uygulama ekle** > Çenebaz'ı seç.
3. Şu iki izni işaretle:
   - **Finansal verileri, siparişleri ve iptal anketi yanıtlarını görüntüleme**
   - **Siparişleri ve abonelikleri yönetme**
4. Daveti gönder (servis hesabının daveti kabul etmesi gerekmez).

Play Console'da hâlâ **Kurulum > API erişimi** sayfası görünüyor ve bir Google
Cloud projesi bağlamanı istiyorsa `dilbaz-3392e` projesini bağla; sayfa yoksa
bu adım gerekmez (Google bağlama zorunluluğunu kaldırdı).

> Not: İznin Google tarafında etkinleşmesi **24-36 saat** sürebilir. Bu
> sürede sunucu `play_unavailable` hatası verir; uygulama bu durumda Play'in
> cevabına geçici olarak güvenir ve sonra yeniden doğrular. Kimse Premium'u
> kaybetmez.

## 4. Bildirim konusunu (Pub/Sub) hazırla

Fonksiyonlar deploy edilince `play-rtdn` konusu otomatik oluşur. Önce
oluşturmak istersen:

```bash
gcloud pubsub topics create play-rtdn --project dilbaz-3392e
```

Google Play'in bu konuya mesaj yazabilmesi için izin ver:

```bash
gcloud pubsub topics add-iam-policy-binding play-rtdn --project dilbaz-3392e --member=serviceAccount:google-play-developer-notifications@system.gserviceaccount.com --role=roles/pubsub.publisher
```

(Konsoldan: Pub/Sub > Konular > `play-rtdn` > **İzinler** > Asıl hesap ekle >
`google-play-developer-notifications@system.gserviceaccount.com` > rol
**Pub/Sub Yayıncısı**.)

## 5. Konuyu Play Console'a bağla

Play Console > Çenebaz > **Para kazanma kurulumu** (Monetization setup) >
**Google Play Faturalandırma** > **Gerçek zamanlı geliştirici bildirimleri**:

1. Konu adı: `projects/dilbaz-3392e/topics/play-rtdn`
2. Bildirim içeriği: **Abonelikler, geçersiz kılınan satın almalar ve tüm tek seferlik ürünler**
   (hepsini al; iadeler de bu yolla gelir).
3. **Test bildirimi gönder**'e bas. Firebase Console > Functions > `playRtdn`
   günlüğünde `play_rtdn` satırında `outcome: "test"` görünmeli.
4. **Kaydet**.

## 6. Ürünleri oluştur (kimlikler birebir aynı olmalı)

Kimlikler `lib/services/billing/products.dart` dosyasındakilerle aynı olmalı;
bir harf farkı bile satın almayı bozar.

**Para kazanma > Abonelikler** (her birinde tek, otomatik yenilenen temel plan):

| Ürün kimliği | Ne |
|---|---|
| `lingora_premium_monthly` | Aylık Premium |
| `lingora_premium_yearly` | Yıllık Premium (7 günlük deneme teklifi: docs/abonelik.md §3.1) |
| `lingora_premium_family_yearly` | Aile planı, yıllık |

**Para kazanma > Uygulama içi ürünler** (tek seferlik, tüketilmeyen):

| Ürün kimliği | Ne |
|---|---|
| `lingora_pack_yds_full` | YDS tam paket |
| `lingora_pack_lgs_full` | LGS tam paket |

Fiyatları gir ve her ürünü **Etkinleştir**.

Ödeme sorunları için Play Console'da aboneliklerde **ek süre (grace period)**
ve **askıya alma (account hold)** açık kalsın: sunucu ek sürede Premium'u
açık tutar, askıda kapatır, ödeme düzelince yeniden açar.

## 7. Lisans test kullanıcıları

Play Console (ana sayfa, uygulama dışı) > **Ayarlar** > **Lisans testi**:
kendi Gmail adresini ve test edecek kişileri ekle, "Lisans yanıtı" =
**RESPOND_NORMALLY**.

Test kullanıcıları gerçek para ödemez. Test aboneliklerinde süreler kısadır
(aylık abonelik yaklaşık 5 dakikada yenilenir, birkaç yenilemeden sonra
biter); böylece yenileme ve süre bitişi bildirimleri hızlıca denenebilir.

Uygulamanın Play'den yüklenmiş olması gerekir: dahili test kanalına bir
sürüm yükle, test kullanıcısı olarak katıl ve uygulamayı Play Store'dan kur.

## 8. Uçtan uca deneme

1. Lisans test hesabıyla uygulamaya gir, aylık Premium'u satın al.
2. Firebase Console > Firestore > `entitlements/{uid}`: `active: true`,
   `source: "play"`, `productId: "lingora_premium_monthly"`, `expiresAt`
   Play'in bitiş tarihi olmalı.
3. Play Store > Abonelikler'den iptal et: belge `active: true` kalır
   (ödenen süre bitene kadar), süre bitince `active: false`, `status: "expired"` olur.
4. Play Console > Siparişler'den bir test siparişini **iade et ve hakkı kaldır**:
   Premium hemen kapanmalı.
5. Sınav paketi al: `entitlements/{uid}.packs.yds == true` olmalı.

Sorun olursa Firebase Console > Functions günlüklerinde `play_api_error`
(401/403 = 3. adımdaki izin henüz etkin değil veya yanlış hesap davet
edildi) ya da `play_rtdn` satırlarına bak.

---

## Teknik notlar (geliştirici için)

- Kod: `functions/src/play.ts` (API istemcisi, durum yorumlama),
  `functions/src/purchase.ts` (`verifyPurchase`, `syncSubscription`,
  `syncPack`, `handleRtdn`), `functions/src/index.ts` (`verifyPurchase`,
  `playRtdn`). Testler sahte Play istemcisi kullanır
  (`functions/test/purchase_play.test.ts`); Google hiç çağrılmaz.
- Premium açık: `ACTIVE`, `IN_GRACE_PERIOD` (`status: "grace"`) ve
  `CANCELED` (bitiş tarihine kadar). Kapalı: `PENDING` (`status: "pending"`),
  `ON_HOLD`, `PAUSED`, `EXPIRED`, iade (voided).
- `purchases/{sha256(jeton)}`: jeton → uid bağı (yalnızca sunucu). Yükseltme
  veya yeniden abonelikte yeni jeton, `linkedPurchaseToken` üzerinden eski
  jetonun sahibine bağlanır.
- `entitlements/{uid}` alanları: `active`, `premium`, `status`, `productId`,
  `expiresAt`, `source: "play"`, `purchaseTokenHash`, `playExpiresAt`,
  `autoRenewing`, `playState`; paketler için `packs` ve `packTokens`.
  Premium'u yalnızca onu açan jeton kapatabilir; başka kaynaktan (kurum,
  aile, davet) gelen daha uzun Premium kısaltılmaz, iadede geri verilir.
- Emülatörde (`FUNCTIONS_EMULATOR=true`) jeton doğrulanmadan kabul edilir
  (`source: "test"`).
