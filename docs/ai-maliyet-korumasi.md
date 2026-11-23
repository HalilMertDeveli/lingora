# Yapay zekâ maliyet koruması (App Check, cihaz sınırı, günlük bütçe, aylık adil kullanım)

Yapay zekâ çağıran Cloud Functions (`converse`, `talk`, `conversationReport`,
`explainMore`, `assessWriting`, `analyzeRehearsal`) Claude'a gitmeden önce bu
kontrollerden geçer (`functions/src/ai_guard.ts`):

1. **Firebase App Check**: yalnızca Google Play'den yüklenen gerçek uygulama
   çağırabilir (Android'de Play Integrity). Token yoksa cevap
   `failed-precondition / app_check_required`.
2. **Cihaz başına ücretsiz sınır**: uygulama her yapay zekâ isteğine rastgele
   `installId`'sini ekler. Aynı telefonda açılan yeni misafir hesaplar aynı
   günlük ücretsiz hakkı paylaşır (varsayılan 20 çağrı/gün). Premium muaf.
   Sunucu yalnızca kimliğin SHA-256 özetini saklar (`aiDevices/{hash}`, uid yok).
3. **Günlük harcama sigortası**: her Claude cevabının token kullanımı
   fiyatlanıp `aiSpend/{gün}_{parça}` belgelerine eklenir. Günlük toplam
   `freeDailyUsd`'yi geçince ücretsiz kullanıcılar, `dailyUsd`'yi geçince
   herkes o gün için `resource-exhausted / ai_budget` alır. Yeni gün (Türkiye
   saati) sıfırdan başlar.
4. **Premium için aylık adil kullanım**: aynı maliyet kullanıcı başına
   `aiUserSpend/{uid}_{yyyy-aa}` belgesine de eklenir (`usd`, `calls`,
   `updatedAt`; Türkiye saatine göre ay). Bir Premium kullanıcının bu ayki
   yapay zekâ maliyeti `premiumMonthlyUsd`'ye (varsayılan 4 $) ulaşınca
   günlük yapay zekâ hakları ay sonuna kadar azalır. Bu bir engel değil,
   yavaşlatmadır; dersler ve yapay zekâ kullanmayan özellikler etkilenmez.
   Azaltılmış hak da dolunca cevap `resource-exhausted / monthly_fair_use`
   olur ve uygulama şu mesajı gösterir: "Bu ay yapay zekâ kullanımın adil
   kullanım sınırını aştı. Ay sonuna kadar günlük hakların azaltıldı; dersler
   ve diğer özellikler sınırsız açık." Yeni ay sıfırdan başlar. Ücretsiz
   kullanıcıların sınırları değişmez.

   | Günlük hak (Premium) | Normal | Aylık sınır aşılınca |
   | --- | --- | --- |
   | Sesli konuşma (`talk`) | 30 dakika | 10 dakika |
   | Mesaj (`converse` + `talk`, ortak) | 300 | 50 |
   | Ek açıklama (`explainMore`) | 30 | 10 |
   | Yazma geri bildirimi (`assessWriting`) | 20 | 5 |
   | Konuşma karnesi (`conversationReport`) | 10 | 3 |
   | Mülakat provası analizi (`analyzeRehearsal`) | 8 | 2 |

   Değerler `ai_guard.ts` içindeki `THROTTLED` ve
   `PREMIUM_MONTHLY_USD_CAP` sabitlerinde. `aiUserSpend` yalnızca sunucuya
   açık (firestore.rules varsayılan kapalı kuralı) ve hesap silinince silinir.

## Ayarlar: `config/aiGuard` (Firestore, isteğe bağlı)

Firebase konsolu > Firestore > `config` koleksiyonu > `aiGuard` belgesi.
Hiç yoksa varsayılanlar geçerli. Değişiklik en geç 1 dakikada etkili olur.

| Alan | Varsayılan | Anlamı |
| --- | --- | --- |
| `appCheck` | `"enforce"` (emülatörde `"off"`) | `"enforce"`: token yoksa reddet. `"monitor"`: yalnızca logla (`ai_app_check_missing`). `"off"`: kapalı. |
| `deviceFreeDaily` | `20` | Bir kurulumun günlük ücretsiz yapay zekâ çağrısı. |
| `freeDailyUsd` | `30` | Bu kadar dolar harcandıktan sonra ücretsiz kullanıcılara yapay zekâ kapanır. |
| `dailyUsd` | `150` | Bu kadar dolar harcandıktan sonra herkese kapanır (acil fren). |
| `premiumMonthlyUsd` | `4` | Bir Premium kullanıcının bu ayki yapay zekâ maliyeti bu kadar dolara ulaşınca günlük hakları ay sonuna kadar azalır. |

Fiyatlar `ai_guard.ts` içindeki `PRICE` sabitinde (claude-sonnet-5-5: girdi
2 $, çıktı 10 $ / milyon token). Model değişirse orayı da güncelleyin.

## Sahibin yapması gerekenler (yayından ÖNCE)

> Önemli: Bu sürüm yayına alınmadan önce 1-3 tamamlanmazsa, varsayılan
> `"enforce"` modunda tüm yapay zekâ özellikleri `app_check_required` döner.
> Konsol adımları bitmediyse önce `config/aiGuard` belgesine
> `appCheck: "monitor"` yazın, sonra deploy edin.

1. **Play Console > Uygulama bütünlüğü (App integrity) > Play Integrity API**:
   uygulamayı bir Google Cloud projesine bağlayın: `dilbaz-3392e` projesini
   seçin ("Link a Cloud project").
2. **Firebase konsolu > App Check > Apps > Android uygulaması
   (`com.cenebaz.app`)**: sağlayıcı olarak **Play Integrity**'yi kaydedin.
   İstenirse uygulama imzalama anahtarının **SHA-256** parmak izini girin
   (Play Console > Uygulama bütünlüğü > Uygulama imzalama > "App signing key
   certificate"). Yükleme anahtarı değil, Play'in imzalama anahtarı.
3. **Debug token'ları** (geliştirme ve QA telefonları, `flutter run` / debug
   APK): uygulama debug sağlayıcıyla açılır ve logcat'e bir kez
   `Enter this debug secret into the allow list ...` satırı yazar. Bu
   değeri Firebase konsolu > App Check > Android uygulaması > menü >
   **Manage debug tokens** bölümüne ekleyin. Sideload edilen release APK'lar
   (ör. `_cikti/Lingora.apk`) Play'den yüklenmediği için Play Integrity'yi
   geçemez: test için debug yapı kullanın.
4. Yayından sonra **Firebase konsolu > App Check > APIs > Cloud Functions**
   ekranında "Verified requests" oranını izleyin. Sunucu zorlamayı kendisi
   yaptığı için konsoldaki "Enforce" düğmesine gerek yok. Firestore için
   "Enforce" AÇMAYIN: eski sürümler doğrudan Firestore'a yazıyor.
5. (İsteğe bağlı) Google Cloud > Faturalandırma > **Bütçeler ve uyarılar**
   ile Anthropic dışındaki maliyetler için ayrıca e-posta uyarısı kurun;
   Anthropic konsolunda da aylık harcama limiti tanımlayın. Bu sigorta
   uygulama içi bir frendir, faturanın yerine geçmez.

## Emülatör ve CI

- Fonksiyon emülatöründe `appCheck` varsayılanı `"off"`; uygulama emülatör
  modunda App Check'i hiç başlatmaz. CI'daki testler (`npm test`) etkilenmez.
- Testler: `functions/test/ai_guard.test.ts`, `functions/test/monthly_fair_use.test.ts`,
  `test/ai_guard_messages_test.dart`.

## Uygulama tarafı

- `lib/services/firebase/firebase_bootstrap.dart`: `firebase_app_check`
  release'te Play Integrity, debug/profile'da debug sağlayıcı.
- `lib/services/conversation.dart` `aiInvoker`: istek verisine `installId`
  ekler; `aiGuardMessage` yeni hata nedenleri için Türkçe mesaj verir.
