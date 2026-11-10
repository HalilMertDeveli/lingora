# Lingora Premium (abonelik)

Bu belge Lingora Premium'un ne olduğunu, nasıl çalıştığını ve yayına almak için
Google Play Console ile Firebase'de **senin** yapman gerekenleri anlatır.

## 1. Ne ücretsiz, ne Premium?

İlke: **öğrenmenin kendisi her zaman ücretsiz.** Can/kalp yok, ceza yok, reklam
duvarı yok. Premium yalnızca bize gerçek maliyet çıkaran ya da ileri seviye
ekstraları açar.

| Ücretsiz (her zaman) | Premium |
| --- | --- |
| Tüm dersler, gramer yolu, notlar, kelime tekrarı | 🤖 **Yapay zekâ sohbet partneri** (Konuş sekmesi, sunucu bağlıyken) |
| Okuma, telaffuz | 📝 **Sınırsız mini deneme** (YDS/YÖKDİL, LGS) |
| Sınav **konu pratiği** (sınırsız) + **günde 1 mini deneme** | 📊 **Detaylı hata analizi** (tüm kategoriler, oranlar, her biri için ipucu) |
| Sohbet senaryolarının **demo modu** (hazır senaryo + kural tabanlı düzeltme) | |
| Türk hata dedektörü ve profilde **en sık 3 hata** | |

Neden bu ayrım?

- **Yapay zekâ sohbeti** her mesajda Claude API maliyeti üretir; ücretsiz
  sunmak sürdürülemez. Ama kullanıcı ne aldığını görebilsin diye aynı
  senaryoların **demo modu ücretsiz** kalır: paywall'da "Ücretsiz demo ile
  dene" butonu vardır.
- **Mini deneme** süreli, puanlı ve sınava hazırlananlar için ileri bir araç.
  Konu konu pratik (açıklamalı) tamamen ücretsiz; günde 1 deneme de ücretsiz.
  Sınırsız deneme Premium.
- **Detaylı hata analizi** ileri istatistik. Temel geri bildirim (en sık 3
  hata + ipucu) ücretsiz kalır.

Uygulama kodunda bu liste tek yerde: `PremiumFeature` (`lib/services/billing/products.dart`)
ve paywall'daki `freeItems` (`lib/screens/paywall_screen.dart`).

## 2. Ürünler ve fiyat önerisi (Türkiye)

| Ürün kimliği | Tür | Önerilen fiyat |
| --- | --- | --- |
| `lingora_premium_monthly` | Abonelik, 1 aylık otomatik yenilenen temel plan | **129,99 TL / ay** |
| `lingora_premium_yearly` | Abonelik, 1 yıllık otomatik yenilenen temel plan | **799,99 TL / yıl** (~66,67 TL/ay, aylığa göre ~%49 tasarruf) |

Notlar:

- Fiyatlar yalnızca **öneri**; gerçek fiyatı Play Console'da sen belirlersin.
  Uygulama fiyatı her zaman Google Play'den okur (`₺…` biçimiyle) ve yıllık
  tasarruf yüzdesini **gerçek mağaza fiyatlarından** hesaplar; uydurma fiyat
  göstermez.
- Türkiye'de dil uygulamalarının aylık bandı yaklaşık 100–200 TL. Öğrenci ağırlıklı
  kitle için aylığı bu bandın alt-orta kısmında, yıllığı belirgin şekilde
  avantajlı tutmak dönüşümü artırır. Enflasyon nedeniyle fiyatları 6 ayda bir
  gözden geçir (Play Console'da mevcut aboneler için fiyat değişikliği ayrı
  bir onay akışıdır).
- İstersen ileride yıllık plana **7 günlük ücretsiz deneme** teklifi (offer)
  eklenebilir; uygulama ilk (temel) planı satar, teklif eklemek için kodda
  küçük bir değişiklik gerekir.
- KDV dahil fiyat girilir (Play Console Türkiye için vergiyi fiyata dahil eder).

## 3. Play Console'da yapılacaklar

Henüz Google Play geliştirici hesabı yok; sırasıyla:

1. **Geliştirici hesabı aç** (play.google.com/console, tek seferlik 25 USD).
   Kimlik doğrulamasını tamamla.
2. **Ödeme profili** oluştur (Ayarlar > Ödeme profili). Abonelik satmak için
   şart; banka hesabını ve vergi bilgilerini gir.
3. **Uygulamayı oluştur**, paket adı: `com.lingora.lingora`
   (`android/app/build.gradle.kts` içindeki `applicationId`).
4. **İmzalı bir sürümü** (AAB) en az **Dahili test** kanalına yükle. Google Play,
   faturalandırma iznini (`com.android.vending.BILLING`, `in_app_purchase`
   eklentisi otomatik ekler) içeren bir sürüm yüklenmeden abonelik ürünü
   oluşturmana izin vermez.
5. **Abonelikleri oluştur**: Para kazanma > Ürünler > Abonelikler:
   - `lingora_premium_monthly` → temel plan: otomatik yenilenen, 1 ay, fiyat.
   - `lingora_premium_yearly` → temel plan: otomatik yenilenen, 1 yıl, fiyat.
   - Her temel planı **Etkinleştir**. Ürün kimlikleri koddakiyle birebir aynı olmalı.
   - Önerilen: **Ödemesiz dönem (grace period)** 7 gün, **hesap askıya alma**
     açık. Uygulama "grace" durumunu da Premium sayar.
6. **Lisans test kullanıcıları**: Ayarlar > Lisans testi → test edecek Gmail
   adreslerini ekle, yanıt "RESPOND_NORMALLY". Bu hesaplar gerçek ücret
   ödemeden satın alır; test aboneliği birkaç dakikada yenilenir/biter.
   Aynı hesapları Dahili test kanalına test kullanıcısı olarak da ekle ve
   uygulamayı **Play Store'dan** yükle (sideload edilen APK'de satın alma çalışmaz).
7. **Sunucu doğrulaması için servis hesabı** (bkz. bölüm 4):
   - Google Cloud Console'da (Firebase projesiyle aynı proje önerilir)
     **Google Play Android Developer API**'yi etkinleştir.
   - Cloud Functions'ın çalıştığı servis hesabını (varsayılan:
     `PROJE_ID@appspot.gserviceaccount.com` ya da Functions için seçilen hesap)
     Play Console > **Kullanıcılar ve izinler** > Yeni kullanıcı davet et ile
     ekle; uygulama izinleri: **Finansal verileri görüntüleme** ve
     **Siparişleri ve abonelikleri yönetme**.
   - JSON anahtar dosyası indirmen **gerekmez** (Functions kendi kimliğiyle
     çağırır). Yetkilerin etkinleşmesi 24 saate kadar sürebilir.
8. (Önerilen) **Gerçek zamanlı geliştirici bildirimleri (RTDN)**: Para kazanma
   kurulumu > Pub/Sub konusu gir (ör. `projects/PROJE_ID/topics/play-billing`).
   Sunucu bu konuyu dinleyip yenileme/iptal/iade olduğunda
   `entitlements/{uid}`'yi günceller. RTDN yoksa da sistem çalışır: uygulama
   her açılışta aboneliği sessizce yeniden doğrular.
9. Mağaza kaydında ve gizlilik politikasında abonelik koşullarını yaz (fiyat,
   otomatik yenileme, iptal yolu). Paywall bu metni zaten gösteriyor.

## 4. Yetki (entitlement) Firebase'den nasıl akar?

```
Kullanıcı ── satın al ──▶ Google Play ── purchaseStream ──▶ PremiumController
                                                              │
                         Firebase hazırsa                     │ hazır değilse
                         verifyPurchase(productId, token) ◀───┤
                                   │                          ▼
                     Play Developer API ile doğrula     Mağazaya güven (yerel)
                     entitlements/{uid} yaz              süre: dönem + 3 gün
                                   │
             { active, productId, expiresAt } ──▶ yerel önbellek
```

1. **Satın alma**: Paywall `in_app_purchase` ile Google Play satın alma
   ekranını açar. Sonuç `purchaseStream` üzerinden gelir: `pending`
   (ör. havale/nakit onayı bekliyor), `purchased`, `restored`, `canceled`, `error`.
2. **Doğrulama**: Firebase hazırsa (`entitlementBackendProvider` dolu) uygulama
   satın alma token'ını `verifyPurchase` callable fonksiyonuna (bölge `europe-west1`) gönderir:
   - Girdi: `{productId, purchaseToken}` (uid, oturumdan alınır;
     girdiye asla güvenilmez).
   - Sunucu: `purchases.subscriptionsv2.get` ile Play'den sorgular, gerekirse
     onaylar (acknowledge), token'ı tek bir uid'ye bağlar (başka hesapta
     yeniden kullanılamaz) ve `entitlements/{uid}` belgesini yazar.
   - Çıktı: `{active, productId, expiresAt (ms)}`. Hatalar: `invalid-argument`, `already-exists` (token başka hesaba bağlı → Premium açılmaz, kullanıcıya söylenir), `unimplemented` (Play doğrulaması henüz kurulmadı → geçici olarak mağazaya güvenilir).
3. **Firestore belgesi** `entitlements/{uid}`:
   `{active, productId, expiresAt: Timestamp, source: 'play'|'test', updatedAt}`; Premium = `active && expiresAt > şimdi`.
   Yalnızca Cloud Functions yazar; kullanıcı yalnızca kendi belgesini okur
   (`firestore.rules`). Uygulama bu belgeyi dinler: başka cihazda giriş yapınca
   Premium oraya da gelir; sunucu iptal/iade görürse Premium kapanır.
4. **Yerel önbellek**: Sonuç `SharedPreferences`'ta (`premium.cache`) bitiş
   tarihiyle saklanır; çevrimdışıyken Premium çalışmaya devam eder. Sunucu
   yoksa bitiş = dönem uzunluğu + 3 gün; uygulama her açılışta Play'den
   aboneliği sessizce geri yükleyip süreyi uzatır. İptal edilen abonelik bu
   yüzden kendiliğinden biter.
5. **Onay (acknowledge)**: Her satın alma `completePurchase` ile onaylanır;
   onaylanmayan abonelik Google tarafından 3 gün içinde iade edilir.
6. **Sunucuya ulaşılamazsa**: Kullanıcı mağazadan ödediyse cezalandırılmaz;
   yerel olarak açılır ve sonraki açılışta yeniden doğrulanır. Sunucu
   satın almayı açıkça reddederse (`active: false` ya da `already-exists`) Premium açılmaz.
7. **Geri yükleme**: "Satın alımları geri yükle" Play'deki aktif abonelikleri
   yeniden getirir (yeni telefon, yeniden kurulum). Bulunamazsa bunu söyler.

**Önemli (sunucu tarafı)**: İstemcideki kilit tek başına yeterli değildir.
Yapay zekâ sohbet sunucusu (`server/`) her istekte kullanıcının
`entitlements/{uid}` belgesini kontrol etmeli; aksi hâlde değiştirilmiş bir
istemci ücretsiz kullanabilir.

## 5. Kod haritası

| Dosya | Görev |
| --- | --- |
| `lib/services/billing/products.dart` | Ürün kimlikleri, önerilen fiyatlar, `PremiumFeature`, günlük ücretsiz deneme sayısı |
| `lib/services/billing/billing_service.dart` | Mağaza soyutlaması (`BillingService`), testte sahtesi kullanılır |
| `lib/services/billing/iap_billing_service.dart` | `in_app_purchase` ile Google Play uygulaması |
| `lib/services/billing/entitlement_backend.dart` | Sunucu arayüzü (`verifyPurchase` + `entitlements/{uid}`), `entitlementBackendProvider` |
| `lib/services/billing/premium.dart` | `PremiumController`, `premiumProvider`, geliştirici anahtarı, deneme kotası |
| `lib/screens/paywall_screen.dart` | Paywall ve `requirePremium(...)` kapısı |
| `lib/screens/error_analysis_screen.dart` | Premium: detaylı hata analizi |
| `test/premium_test.dart` | Sahte mağaza/sunucu ile testler |

Firebase bağlantısı: `entitlementBackendProvider` varsayılan olarak `null`dır
(sunucu yok). Firebase istemci katmanı hazır olduğunda (`firebaseReadyProvider`)
bu provider'ı `cloud_functions` + `cloud_firestore` kullanan bir uygulamayla
override eder.

## 6. Geliştirirken test

- **Satın almadan Premium**: `flutter run --dart-define=LINGORA_PREMIUM=1`
  (yalnızca debug/profile; release derlemede yok sayılır).
- **Gerçek satın alma akışı**: lisans test hesabıyla, Dahili test kanalından
  Play Store'dan kurulan sürümde dene. Test kartlarıyla "her zaman onayla",
  "her zaman reddet", "yavaş kart (pending)" senaryolarını dene.
- Masaüstü/web/testlerde mağaza yoktur (`UnavailableBillingService`): paywall
  "Satın alma bu cihazda şu an kullanılamıyor" der.
- iOS (App Store) daha sonra: aynı ürün kimlikleriyle App Store Connect'te
  abonelik grubu açılır, sunucuya App Store doğrulaması eklenir.
