# Ölçüm, Remote Config ve davet programı

Bu belge Lingora'nın büyüme ve ölçüm katmanını anlatır: hangi olayların neden
ölçüldüğü, kullanıcı iznini nasıl aldığımız, Remote Config parametreleri, ilk
A/B deneyi ve "Arkadaşını davet et" programının kuralları.

İlkeler:

- **İzin olmadan hiçbir şey gönderilmez.** Firebase Analytics cihazda kapalı
  başlar (AndroidManifest / Info.plist) ve yalnızca kullanıcı "İzin ver" derse açılır.
- **Kişisel veri yok.** Olaylarda ad, e-posta, kullanıcı kimliği (uid), davet
  kodu, yazılan metin, ses, konum bulunmaz. `setUserId` hiç çağrılmaz; reklam
  kimliği ve reklam sinyalleri her zaman kapalıdır.
- **Uygulama izinsiz de tam çalışır.** Analiz, Firebase kapalıyken (varsayılan
  derleme) ve emülatör modunda tamamen devre dışıdır (no-op).
- Reklam yok, can/kalp yok; paywall her zaman kapatılabilir ve öğrenme yolunu kesmez.

## 1. Kod haritası

| Dosya | Görev |
| --- | --- |
| `lib/services/growth/analytics_events.dart` | Olay sözlüğü: tüm olay adları ve parametreleri tek yerde |
| `lib/services/growth/analytics.dart` | `AnalyticsService` (izin + no-op), `AnalyticsSink`, `FirebaseAnalyticsSink`, izin durumu |
| `lib/services/growth/remote_flags.dart` | Remote Config parametreleri, gömülü varsayılanlar, `remoteFlagsProvider` |
| `lib/services/growth/paywall_trigger.dart` | "N dersten sonra paywall" kuralı |
| `lib/services/growth/growth.dart` | `main()` override'ları, açılıştaki kayıp (churn) sinyalleri, kullanıcı özellikleri |
| `lib/services/growth/referral.dart` | Davet servisi (callable), cihaz kurulum kimliği, paylaşım metni |
| `lib/screens/consent_sheet.dart` | İzin ekranı (`ConsentGate`) ve Profil anahtarı |
| `lib/screens/invite_screen.dart`, `growth_profile_section.dart` | "Arkadaşını davet et" ve Profil > Gizlilik |
| `functions/src/referral.ts`, `referral_api.ts` | `getInviteCode`, `redeemInvite` callable'ları |
| `test/growth_test.dart`, `functions/test/referral.test.ts` | Testler |

Analiz ve Remote Config yalnızca `--dart-define=LINGORA_FIREBASE=prod` ile
derlenen sürümde gerçek Firebase'e bağlanır (`growthOverrides`). Diğer tüm
durumlarda `analyticsSinkProvider` ve `remoteConfigSourceProvider` `null` kalır.

## 2. İzin (KVKK)

- **Ne zaman sorulur?** Uygulama ilk açıldığında, onboarding'in ilk ekranının
  üstünde (`ConsentGate`). Eski kullanıcılara güncellemeden sonraki ilk açılışta
  bir kez sorulur. Yalnızca analiz gerçekten varsa (prod derleme) sorulur.
- **Nasıl?** Kapatılamayan bir alt sayfa; "İzin ver" ve "İzin verme" eşit
  ağırlıkta, önceden seçili cevap yok. Metin neyin ölçüldüğünü, neyin
  ölçülmediğini ve kararın Profil > Gizlilik'ten değiştirilebileceğini söyler.
- **Karar verilene kadar** olaylar en fazla 30 adet olarak yalnızca bellekte
  bekler; "İzin ver" denirse gönderilir, "İzin verme" denirse silinir.
  Böylece onboarding hunisi izin verenler için eksiksiz ölçülür.
- **İzin geri alınırsa** toplama kapatılır ve `resetAnalyticsData()` ile
  cihazdaki analiz kimliği ve bekleyen veriler silinir.
- Karar cihazda `analytics.consent` anahtarında tutulur (sunucuya gönderilmez).
- Consent Mode: `analytics_storage` yalnızca izinle `granted`; `ad_storage`,
  `ad_user_data`, `ad_personalization` her zaman `denied`.

## 3. Olay sözlüğü

Adlar `snake_case`, en fazla 40 karakter; metin değerleri en fazla 100
karakter. Yeni olay eklerken önce `analytics_events.dart`'a ve bu tabloya ekle;
`test/growth_test.dart` ikisinin uyumunu denetler.

### Onboarding

| Olay | Parametreler | Ne zaman |
| --- | --- | --- |
| `onboarding_step` | `step` (welcome, course, goal, level), `index` (0–3) | Onboarding sayfası her göründüğünde |
| `placement_start` | – | Onboarding'den seviye testi başlatıldı |
| `onboarding_complete` | `method` (placement, scratch), `daily_goal` (XP), `track` | Onboarding bitti |

Huni: `onboarding_step(0)` → `onboarding_step(3)` → `onboarding_complete` → ilk `lesson_finish`.

### Öğrenme

| Olay | Parametreler | Ne zaman |
| --- | --- | --- |
| `lesson_start` | `lesson_id` (ders/düğüm kimliği), `mode` (lesson, test, practice) | Ders, ünite sınavı ya da hata tekrarı açıldı |
| `lesson_finish` | `lesson_id`, `mode`, `accuracy` (0–100), `xp`, `duration_s` | Ders bitti (sınavda geçince) |
| `track_chosen` | `track`, `source` (onboarding, home) | Kurs yolu seçildi |
| `feature_use` | `feature` (ai_chat, demo_chat, reading, pronunciation, exam_practice, mock_exam, error_analysis, grammar) | Özellik açıldı |

### Gelir

| Olay | Parametreler | Ne zaman |
| --- | --- | --- |
| `paywall_view` | `placement` (profile, after_lessons, ai_chat, mock_exam, error_analysis), `variant` (a, b) | Paywall Premium olmayan kullanıcıya göründü |
| `paywall_close` | `placement`, `variant` | Paywall satın almadan kapandı |
| `purchase_start` | `plan` (monthly, yearly), `placement` | Satın al düğmesine basıldı |
| `trial_start` | `plan`, `trial_days` | Ücretsiz denemeyle yeni abonelik başladı (Play deneme teklifi) |
| `purchase` | `plan`, `item_id` (Play ürün kimliği) | Denemesiz yeni ücretli abonelik |
| `purchase_restore` | `found` (1/0) | "Satın alımları geri yükle" bitti |

Gelir tutarı uygulamadan gönderilmez; gerçek gelir Play Console'dan ve
Firebase'in Play bağlantısından (otomatik `in_app_purchase`) okunur.

### Kayıp (churn) sinyalleri

| Olay | Parametreler | Ne zaman |
| --- | --- | --- |
| `session_return` | `days_away` (2–60) | Uygulama, son çalışmadan en az 2 gün sonra açıldı |
| `streak_lost` | `length` (kırılan seri) | Açılışta serinin kırıldığı görüldü |
| `premium_lapsed` | `source` (store, referral) | Premium aktifken kapandı (iptal, süre bitti, iade, davet ödülü bitti) |

### Davet

| Olay | Parametreler | Ne zaman |
| --- | --- | --- |
| `invite_share` | – | Davet metni paylaşım sayfası açıldı |
| `invite_redeem` | `result` (ok ya da hata kodu: invalid_code, own_code, already_redeemed, device_used, mutual_invite, not_new_user, sign_in_required, offline) | Davet kodu girildi |

### Kullanıcı özellikleri

`premium` (yes/no), `track` (kurs yolu), `paywall_variant` (a/b). Kişisel değildir;
segmentlere ayırmak ve A/B sonuçlarını kırmak için kullanılır.

### Temel metrikler

- Aktivasyon: `onboarding_complete` → aynı gün `lesson_finish` oranı.
- Tutma: 1./7./30. gün geri dönüş (Firebase Retention), `session_return` dağılımı.
- Paywall dönüşümü: `paywall_view` → `purchase_start` → `trial_start`/`purchase`, `placement` ve `variant` kırılımında.
- Deneme → ücretli dönüşüm: Play Console abonelik raporları (hedef %4–6, bkz. `docs/gelir-plani.md`).
- Davet: `invite_share` / aktif kullanıcı, `invite_redeem(ok)` oranı.

## 4. Remote Config

Varsayılanlar uygulamaya gömülüdür (`remoteDefaults`); Remote Config'e hiç
ulaşılamasa da uygulama bu değerlerle çalışır. Geçersiz değerler (aralık dışı,
bilinmeyen metin) sessizce varsayılana döner. Yeni değerler arka planda çekilir
ve **bir sonraki açılışta** etkinleşir; paywall kullanıcının gözü önünde değişmez.
Çekme aralığı release'te 12 saat.

| Parametre | Tür | Varsayılan | Anlamı |
| --- | --- | --- | --- |
| `paywall_variant` | metin | `a` | `a`: özellik listesi önce (kontrol). `b`: planlar önce, kısa başlık |
| `trial_days` | sayı 0–31 | `0` | 0: deneme hiç duyurulmaz. >0: Play bu kullanıcıya deneme teklifi döndürürse paywall "N gün ücretsiz dene" der. Gösterilen süre **her zaman Play'den** gelir |
| `price_copy` | metin | `savings` | Yıllık planın açıklaması: `savings` (%N tasarruf), `monthly_equivalent` (Aylık yalnızca ₺X), `plain`. Hepsi gerçek mağaza fiyatından hesaplanır |
| `paywall_after_lessons` | sayı 0–1000 | `5` | Premium olmayan kullanıcıya, her N bitmiş dersten sonra bir kez paywall göster. 0 = hiç |
| `paywall_cooldown_days` | sayı 1–365 | `7` | İki otomatik paywall arasında en az kaç gün |
| `referral_enabled` | bool | `true` | Profil'de "Arkadaşını davet et" |
| `ai_chat_enabled` | bool | `true` | Canlı yapay zekâ sohbeti. `false` iken senaryolar demo modunda açılır (maliyet/arıza anahtarı) |

Not (`trial_days`): Ücretsiz deneme bir Play Console **teklifidir** (offer).
Uygulama, Play'in o kullanıcıya döndürdüğü deneme teklifini seçer (Play yalnızca
uygun kullanıcılara döndürür). Denemeyi tamamen kapatmak için teklifi Play
Console'da devre dışı bırak; `trial_days=0` yalnızca duyuruyu kapatır.

## 5. İlk A/B deneyi: paywall düzeni

- **Hipotez:** Planları ve fiyatı özellik listesinden önce göstermek (`b`),
  karar vermeye hazır kullanıcıların satın almaya geçişini artırır; açıklama
  önce (`a`) ise güveni artırıp iadeyi azaltır.
- **Kurulum:** Firebase Console > A/B Testing > Remote Config deneyi.
  Hedef: Android uygulaması, tüm kullanıcılar ya da yalnızca yeni kullanıcılar
  (`first_open` son 7 gün). Varyantlar: kontrol `paywall_variant=a`, deney
  `paywall_variant=b`, %50/%50. Etkinleşme olayı: `paywall_view`.
- **Birincil metrik:** `purchase_start` / `paywall_view` (aynı oturum).
  **İkincil:** `trial_start` + `purchase`, 7. gün tutma. **Koruma (guardrail):**
  `paywall_close` oranı, 7. gün tutma düşmemeli, iade/iptal (Play Console).
- **Süre ve büyüklük:** En az 14 gün ve varyant başına en az ~1.000
  `paywall_view`; Firebase "lider" ilan edene kadar erken bitirme.
- **Karar:** Kazanan varyantı Remote Config varsayılanı yap, deneyi kapat.
- Sonraki deney adayları: `price_copy` (`savings` vs `monthly_equivalent`),
  `paywall_after_lessons` (3 / 5 / 0), `trial_days` (0 vs 7, Play'de 7 günlük
  teklif açıkken).

## 6. Davet programı ("Arkadaşını davet et") {#davet}

Her kullanıcının 7 karakterlik bir davet kodu vardır (karışan harfler yok:
0/O, 1/I/L). Yeni bir kullanıcı kodu Profil > Arkadaşını davet et'e girince
**ikisi de 7 gün Premium** kazanır.

Akış:

1. `getInviteCode` (callable, giriş gerekli) kodu ilk istekte üretir:
   `inviteCodes/{CODE} = {uid}`, `referrals/{uid} = {code, monthKey, monthCount, totalCount}`.
2. Kullanıcı paylaş düğmesiyle (`share_plus`) metni gönderir. Metin kodu ve
   Play Store bağlantısını (`&referrer=invite%3DKOD`) içerir.
3. Arkadaş uygulamayı kurar, hesabını bağlar ve kodu girer → `redeemInvite({code, deviceId})`.
4. Sunucu tek işlemde (transaction) kuralları denetler ve iki tarafın
   `entitlements/{uid}` belgesine yazar:
   `{active: true, source: "referral", productId: "referral", expiresAt}`.
   Uygulama bu belgeyi zaten dinlediği için Premium kendiliğinden açılır.
   Ücretli aboneliği süren kullanıcıda kaynak/ürün değişmez, bitişe 7 gün eklenir.

Kötüye kullanım sınırları (`functions/src/referral.ts`):

| Kural | Hata kodu |
| --- | --- |
| Hesap başına yalnızca bir kez kod kullanılabilir | `already_redeemed` |
| Cihaz başına bir kez (kurulum kimliğinin SHA-256 özeti saklanır) | `device_used` |
| Yalnızca yeni hesaplar: ilk 14 gün | `not_new_user` |
| Misafir (anonim) hesap kullanamaz; Google/e-posta ile bağlı hesap gerekir | `sign_in_required` |
| Kendi kodun olmaz | `own_code` |
| A, B'yi davet ettiyse B, A'yı davet edemez | `mutual_invite` |
| Davet eden ayda en fazla **5** ödül kazanır (Türkiye saatine göre takvim ayı); sınırdan sonra yeni gelen yine ödül alır, davet eden almaz | – |

Cihaz kimliği donanım kimliği değildir: kurulumda üretilen rastgele bir
sayıdır (`install.id`) ve sunucuda yalnızca özeti tutulur. Uygulamayı silip
yeniden kurmak yeni bir kimlik üretir; bu yüzden asıl koruma "yeni hesap + bağlı
hesap + hesap başına bir" kurallarıdır.

Sonraki adım (isteğe bağlı): Play Install Referrer API ile kodu kurulumda
otomatik doldurmak (`play_install_referrer` paketi).

## 7. Sahibin yapması gerekenler

1. Firebase projesinde **Google Analytics'i etkinleştir** (Proje ayarları >
   Entegrasyonlar), `flutterfire configure` ile prod yapılandırmasını üret.
   Veri saklama süresini **2 ay** yap (Analytics > Veri saklama), Google
   sinyallerini ve reklam kişiselleştirmeyi **kapalı** bırak.
2. **Remote Config**'te bölüm 4'teki parametreleri aynı varsayılanlarla oluştur
   (tablo birebir). Koşul eklemeden yayınla.
3. Play Console'da yıllık plana 7 günlük ücretsiz deneme teklifi açtıysan
   `trial_days=7` yap.
4. A/B testini bölüm 5'teki gibi kur.
5. Functions'ı dağıt (`firebase deploy --only functions`); `getInviteCode` ve
   `redeemInvite` yeni callable'lardır. Firestore kuralları değişmedi (yeni
   koleksiyonlar istemcilere zaten kapalı).
6. Firebase Analytics'i Play Console'a bağla (gelir raporları için).
7. Gizlilik politikasını (`docs/magaza/gizlilik-politikasi.md`) kendi
   bilgilerinle tamamlayıp yayınla ve bağlantısını Play Console'a gir.
