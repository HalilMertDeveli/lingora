# Firebase sunucu (Firestore kuralları + Cloud Functions)

Uygulamanın sunucu tarafı tamamen Firebase üzerindedir. İstemci tarafı (giriş, ilerleme eşitleme,
emülatöre bağlanma) için bkz. [firebase.md](firebase.md).

| Parça | Dosya | Ne yapar |
| --- | --- | --- |
| Proje ayarı | `firebase.json`, `.firebaserc` | Varsayılan proje `demo-lingora` (yalnızca emülatör). Emülatörler: Auth 9099, Firestore 8080, Functions 5001, UI kapalı. |
| Güvenlik kuralları | `firestore.rules` | Aşağıdaki tabloya bak. |
| İndeksler | `firestore.indexes.json` | Şimdilik boş: sorguların hepsi tek alanlı, otomatik indeksler yetiyor. |
| Fonksiyonlar | `functions/` (TypeScript, Node 22, 2. nesil, bölge `europe-west1`) | Lig, yapay zekâ sohbeti, satın alma doğrulama. |

## Veri modeli ve kurallar

| Yol | Kim okur | Kim yazar | İçerik |
| --- | --- | --- | --- |
| `users/{uid}` | sahibi | sahibi, gerçek bir hesapla (Google, e-posta, telefon; anonim misafir değil; şekil ve boyut doğrulamalı) | `schemaVersion, progress, totalXp, displayName, clientUpdatedAt, updatedAt` — `updatedAt` sunucu saati olmak zorunda, `progress` en çok 60 anahtar, başka alan yok, silme yok. |
| `leagueState/{uid}` | sahibi | yalnızca fonksiyonlar | `tier, weekKey, groupId, optedOut, lastResult{weekKey, oldTier, newTier, rank, size, xp}` ve XP sınır sayaçları (`xpDay/xpDayTotal`, `xpMinute/xpMinuteTotal`, `lastXpAt`). |
| `leagues/{hafta}_{lig}_{grup}` ve `.../members/{uid}` | yalnızca o grubun üyeleri | yalnızca fonksiyonlar | Dünya Ligi grubu (en çok 100 kişi). Grup: `weekKey, tier, group, size, settled`. Üye: `name, avatar, country, photo (≤ 8 KiB JPEG), xp, joinedAt, updatedAt, rank`. |
| `entitlements/{uid}` | sahibi | yalnızca fonksiyonlar | `active, premium, status, productId, platform, expiresAt, source, updatedAt`. |
| `friendCodes/{kod}` | hesabı olan herkes tek tek (`get`); listeleme yalnızca kendi kodu | sahibi, gerçek bir hesapla | `uid, name, avatar, createdAt`. Kod 8 karakter, karışmayan harf ve rakamlar (`0/O`, `1/I` yok). |
| `friendships/{a}_{b}` (`a < b`) | yalnızca iki üye | üyeler, gerçek bir hesapla; fonksiyon gerekmez | `members, code, names, avatars, done{uid: gün}, streak, best, streakDay, createdAt`. Ayrıntı aşağıda. |
| `friendships/{a}_{b}/cheers/{gönderen}_{gün}_{tür}` | iki üye | gönderen üye | `from, to, kind (tebrik, destek, hadi, harika), day, createdAt`. Serbest metin yok; her türden günde bir. |
| `usage/*`, `purchases/*`, `leagueWeeks/*` | kimse | yalnızca fonksiyonlar | Günlük mesaj kotası, satın alma jetonu → kullanıcı bağı, grup doluluk sayacı. |

Fonksiyonlar Admin SDK kullandığı için kurallardan etkilenmez. Diğer her yol istemciye kapalıdır.

## Fonksiyonlar

Hepsi çağrılabilir (callable) fonksiyondur ve giriş yapmış kullanıcı ister (`unauthenticated`).

- **`joinLeague {name?, avatar?, country?, photo?}` → `{groupId, weekKey, tier}`**: Yalnızca hesabı olanlar
  (misafir `permission-denied`). Kullanıcıyı bu haftanın, kendi ligindeki 100 kişilik bir Dünya Ligi grubuna
  yerleştirir (ülke fark etmez; dolunca yeni grup açılır). Tekrar çağrılabilir; her çağrıda satırdaki ad, ülke
  (ISO 3166 iki harf) ve küçük fotoğraf (base64 JPEG, ≤ 8 KiB) güncellenir. Herkes Bronz'dan başlar: cihazdaki
  çevrimdışı lig seviyesine güvenilmez. Önceki haftası henüz kapanmamışsa önce onu kapatır.
- **`addLeagueXp {weekXp, weekKey?}` → `{xp, accepted, pending}`**: Uygulama bu haftaki **toplam** XP'sini
  bildirir; sunucu kendinde olanla farkı ekler. Aynı çağrı tekrarlanırsa XP iki kez sayılmaz. Sınırlar:
  dakikada 300, Türkiye saatiyle günde 3000 XP; iki çağrı arasında en az 2 sn (`resource-exhausted`).
  Sınıra takılan kısım `pending` olarak döner, uygulama bir dakika sonra yeniden dener. `weekKey` sunucunun
  haftası değilse (başka saat diliminde hafta dönümü) `failed-precondition`.
- **`leaveLeague {}` → `{left}`**: Satırı bu haftanın grubundan siler, `optedOut` yapar. Lig seviyesi
  korunur; yeniden katılınca `joinLeague` bayrağı kaldırır.
- **`settleLeagues`** (zamanlanmış, her pazartesi 00:05, `Europe/Istanbul`): Biten haftaların gruplarını
  kapatır. 100 kişilik grupta XP'si olan ilk 15 (Bronz–Altın) ya da 10 (Safir–Obsidyen) kişi üst lige çıkar;
  son 5 (Gümüş–Yakut) ya da 10 (Zümrüt–Elmas) kişi alt lige geçer. Bronz'da alt lige geçiş, Elmas'ta yükselme
  yok. Küçük gruplarda sayılar orantılı küçülür (yükselme yukarı, iniş aşağı yuvarlanır). Beraberlikte o
  XP'ye önce ulaşan önde. Sonuç `leagueState/{uid}.lastResult` alanına yazılır.
- **`converse {scenarioId, messages}` → `{reply, correction, tip_tr, done, remaining}`**: Eski Supabase
  proxy'sinin aynısı: senaryo komutları sunucuda (`functions/src/scenarios.ts`), model `claude-opus-5-5`,
  düşük effort, JSON şemalı yanıt, güvenlik reddinde sahneye dönen sabit yanıt, sunucu tarafı yedek model
  (`fallbacks: "default"`). Ek olarak: etkin Premium (`entitlements/{uid}`, `active` ya da `premium` ve
  `expiresAt` gelecekte) yoksa `permission-denied`; günde 60 mesaj kotası dolunca `resource-exhausted`;
  Anthropic hatasında `unavailable` ve o mesaj kotadan düşülmez. API anahtarı Secret Manager'daki
  `ANTHROPIC_API_KEY` gizli değerinden okunur.
- **`talk` (akışlı callable) — Doğal konuşma** (`functions/src/talk.ts`, `talk_context.ts`, `tts.ts`):
  `{scenarioId | mode: "free" | characterId, topic?, level?, goal?, voice?, messages}`. Claude
  (`claude-sonnet-5-5`, düşünme kapalı `between_tools`, low effort, JSON şeması) akışla okunur; yanıtın
  `reply` alanı yazılırken cümle cümle bölünür ve her cümle `{type: "sentence", i, text, audio}` parçası
  olarak gönderilir (`audio`: Chirp 3 HD MP3, base64; ücretsiz kullanıcıda `null`, telefon sesi okur).
  Sonuç: `{reply, correction, tip_tr, done, remaining, free, voice, talkSecondsLeft, timing}`. Düzeltmeler
  sohbet içinde söylenmez (doğal tekrar, "recast"); `correction`/`tip_tr` karneye gider. Ücretsiz: günde 3
  mesaj (`usage/{uid}`, `converse` ile ortak). Premium: günde 30 dakika adil kullanım
  (`voiceUsage/{uid}.talkSeconds`, aşınca `resource-exhausted` / `fair_use`; aylık adil kullanım
  sınırını aşan Premium kullanıcıda ay sonuna kadar günde 10 dakika ve 50 mesaj, aşınca
  `resource-exhausted` / `monthly_fair_use`, bkz. docs/ai-maliyet-korumasi.md) ve günde 30.000 yeni TTS
  karakteri (`voiceUsage/{uid}.ttsChars`; aşınca hata değil, telefon sesine düşer). Karakterler (Alfie,
  Maya, Daniel Reed, Emma, Dr. Eleanor Hughes, Zoe) ve 8 ses `talk_context.ts` içinde. Her tur
  `talk_turn` günlüğüne `firstTextMs`/`firstAudioMs`/`totalMs` yazar.
- **`speak {text, voice?, rate?}` → `{audio | null, cached, reason?}`**: Premium'a Chirp 3 HD sesi
  (açılış cümleleri, tekrar dinleme). Aynı cümle `ttsCache/{sha256}` içinde önbellekte (60 gün,
  `expireAt` alanına Firestore TTL kuralı eklenebilir). ElevenLabs canlı sohbette kullanılmaz.
- **`assessWriting {taskId, text}` → `{scores{task,accuracy,range,coherence}, corrections[{from,to,why_tr,type}], next_tr, remaining}`**:
  Genel kursun `write` alıştırmaları için yapay zekâ geri bildirimi (`functions/src/assess_writing.ts`,
  docs/genel-mufredat.md §3). Görev ve rubrik sunucuda (`functions/src/writing_tasks.ts`, anahtar
  `<düğüm id>w`); bilinmeyen görev `not-found`, yarısından kısa metin `failed-precondition`. Puanlar 0–3'e
  sıkıştırılır; düzeltmeler görevin odak türleri (article, tense, preposition, word_order, be) ve en çok 3 diğer
  hatayla sınırlanır. Premium ve günde 20 istek (`usageWriting/{uid}`), hata ya da retde istek kotadan
  düşülmez. Sunucuya ulaşılamazsa uygulama yerel kontrolle (kelime sayısı, kontrol listesi) devam eder.
- **`verifyPurchase {platform?, productId, purchaseToken}` → `{active, premium, status, productId, expiresAt}`**:
  Ürünler `lingora_premium_monthly` (31 gün) ve `lingora_premium_yearly` (366 gün). Jeton başka hesaba
  bağlıysa `already-exists`. **Yalnızca emülatörde** jetona güvenip `entitlements/{uid}` yazar. Gerçek
  projede şimdilik `unimplemented` döner: Google Play Developer API doğrulaması `functions/src/purchase.ts`
  içindeki `TODO(play-billing)` ile işaretli, bir servis hesabı gerektirir (aşağıya bak).

## Yerelde çalıştırma ve test

Gerekenler: Node 22+, Java 21, `firebase-tools` (15.x). Giriş yapmak gerekmez; `demo-` projesi hiçbir
Google sunucusuna dokunmaz.

```bash
cd functions
npm ci
npm test
```

`npm test`, Firestore emülatörünü açıp derlenmiş testleri çalıştırır: kurallar
(`@firebase/rules-unit-testing`), lig, sohbet (Anthropic istemcisi her zaman sahte, gerçek API çağrılmaz),
satın alma. Uygulamayla birlikte denemek için:

```bash
cd functions
npm run serve
```

Sonra uygulamayı `--dart-define=LINGORA_FIREBASE=emulator` ile çalıştır (bkz. [firebase.md](firebase.md)).
Emülatörde gerçek Claude ile konuşmak istersen `functions/.secret.local` dosyasına
`ANTHROPIC_API_KEY=...` yaz (git'e girmez); yoksa `converse` yalnızca doğrulama ve kota hatalarını gösterir.

Emülatörde gerçek sinirsel ses (Chirp 3 HD) için: `gcloud auth login` ile giriş yapılmış olsun ve
emülatörü `LINGORA_TTS_QUOTA_PROJECT=<Text-to-Speech API açık proje>` ortam değişkeniyle başlat.
`speak`/`talk` sesi senin gcloud jetonunla ve bu projenin kotasıyla üretir (yalnızca sentez; projeye bir şey
yazılmaz). Değişken yoksa `demo-lingora` için kimlik olmadığından ses telefonun kendi sesine düşer
("Project demo-lingora not found"). Bu yol yalnızca `FUNCTIONS_EMULATOR=true` iken çalışır, üretimde kapalıdır.

## Yayına alma (sahibin yapacakları)

1. Giriş yap: `firebase login`
2. [Firebase konsolunda](https://console.firebase.google.com/) proje oluştur (ör. `lingora-app`). Proje
   kimliğini `.firebaserc` dosyasına ekle (varsayılanı `demo-lingora` bırakmak testleri korur):
   ```bash
   firebase use --add
   ```
   Takma ad olarak `prod` ver; sonraki komutlarda `--project prod` kullan.
3. **Blaze (kullandıkça öde) planına geç.** Cloud Functions, Secret Manager ve zamanlanmış fonksiyonlar
   ücretsiz Spark planında çalışmaz. Bütçe uyarısı kurmayı unutma (Google Cloud > Faturalandırma > Bütçeler).
4. Firestore'u oluştur: üretim modu, bölge `europe-west1`.
5. Authentication'da kullanılan giriş yöntemlerini aç (bkz. [firebase.md](firebase.md)).
6. Anthropic API anahtarını gizli değer olarak kaydet (anahtar sorulur, ekrana yazılmaz):
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY --project prod
   ```
7. Yayınla:
   ```bash
   firebase deploy --only firestore,functions --project prod
   ```
   İlk yayında Cloud Scheduler ve Secret Manager API'lerini açmak isteyebilir; onayla.
8. **Satın almadan önce:** `verifyPurchase` gerçek projede `unimplemented` döner. Play Console'da bir
   servis hesabına uygulama için "finansal verileri görüntüleme / siparişleri yönetme" izni ver, Google Play
   Android Developer API'yi aç ve `functions/src/purchase.ts` içindeki TODO'yu tamamla (abonelik durumu,
   bitiş tarihi, onaylama, gerçek zamanlı bildirimler).

**Doğal konuşma için (talk/speak):** Cloud Text-to-Speech API'yi aç ve fonksiyonları yayınla:
```bash
gcloud services enable texttospeech.googleapis.com --project dilbaz-3392e
firebase deploy --only functions:talk,functions:speak,functions:conversationReport,functions:converse,functions:deleteAccount --project prod
```
Fonksiyonlar varsayılan servis hesabıyla (ADC) çağırır; ek anahtar gerekmez. İstersen Firestore TTL
kuralı: koleksiyon `ttsCache`, alan `expireAt`.

Maliyet notu: `converse` her mesajda yaklaşık 2–3 bin girdi ve birkaç yüz çıktı jetonu kullanır. Günlük
kota (`DAILY_MESSAGE_LIMIT`) ve model `functions/src/converse.ts` içinde tek satırlık ayarlardır; daha
ucuz bir modele geçmeden önce gerçek sohbetlerde kaliteyi ölç.

## Eski Supabase kodu neden silindi

`server/supabase/functions/converse/` (Deno Edge Function) hiç yayına alınmamıştı ve arka uç tamamen
Firebase'e taşındı. Senaryo komutları ve doğrulama mantığı aynen `functions/src/` içine taşındı, uygulamadaki
HTTP istemcisi (`LINGORA_AI_URL` / `LINGORA_AI_KEY`) yerine `converse` çağrılabilir fonksiyonu kullanılıyor.
İki ayrı arka ucu bakımda tutmanın faydası olmadığı için kod kaldırıldı; gerekirse git geçmişinde duruyor.

## Arkadaşlar ve ortak seri (Cloud Functions gerekmez)

Arkadaşlık yalnızca Firestore kurallarıyla çalışır, bu yüzden Spark (ücretsiz) planda da açıktır. Kod:
`lib/services/friends.dart`, ekran `lib/screens/friends_screen.dart` (Lig ve Profil'den açılır, Çocuk modunda
gizli). Kural testleri: `functions/test/friends_rules.test.ts`.

- **Arkadaş ekleme:** Herkesin bir kodu var. Arkadaşının kodunu bilen, onunla arkadaşlık belgesini açabilir;
  kural, kodun gerçekten o kişiye ait olduğunu ve yazılan ad ile simgenin koddakiyle aynı olduğunu denetler.
  İki taraf da arkadaşlığı silebilir. Misafir (anonim) hesaplar katılamaz.
- **Gün:** Türkiye günü, `floor((ms + 3 saat) / 1 gün)`. Kurallarda `trDay()`, uygulamada `friendDay()`;
  kural `request.time` kullanır, yani telefonun saatine güvenilmez.
- **Ortak seri:** Günlük hedefe ulaşan üye `done.{uid}` alanına bugünü yazar. Arkadaşı da bugün yazmışsa aynı
  yazmada seri bir artar (dün de artmışsa `streak + 1`, değilse `1`) ve `best` güncellenir. Kural geçişi
  birebir denetler; seriyi uydurmak ya da günde iki kez artırmak reddedilir. Bir gün kaçarsa ekranda seri 0
  görünür ve bir sonraki ortak günde 1'den başlar. Ceza yok.
- **Destek ve tebrik:** Dört hazır mesaj; her türden günde bir tane.
- **Bilinen sınır:** Günlük hedefe ulaşıldığını telefon bildirir (XP sunucuda doğrulanmıyor). Para ya da ödül
  bağlı olmadığı için kabul edilebilir. Bildirim (push) yok; mesajlar uygulama açılınca görünür.
- **Rehberden bulma ve arkadaşlık istekleri** (`phoneIndex`, `friendRequests`): `docs/arkadaslar.md`.
- **Arkadaşlıktan çıkarma** önce destek mesajlarını (`cheers`) siler; aynı iki kişi aynı gün yeniden arkadaş
  olursa mesajlar baştan gönderilebilir.

## Profil fotoğrafı ve görünen ad (Storage gerekmez)

Kod: `lib/services/profile.dart`, başlık `lib/screens/profile_header.dart`. Kural testleri:
`functions/test/profile_rules.test.ts`.

- **Fotoğraf:** Galeriden ya da kameradan seçilir (`image_picker`), ortadan kare kırpılır, 256 px JPEG'e
  küçültülür ve en fazla 60 KiB olur (`image` paketi). Cloud Storage varsayılan bucket'ı Blaze ister; bu yüzden
  görsel `profiles/{uid}` belgesinde `photo` (bytes) alanında durur.
- **Misafir:** Fotoğraf ve ad yalnızca cihazda (SharedPreferences, `profile_v1`). Hesaba girince yüklenir.
- **Hesap:** Her değişiklik `profiles/{uid}` belgesine yazılır: `{name, photo, clientUpdatedAt, updatedAt}` (birleştirerek yazılır; yanında Mağaza vitrini `showcase` durur, bkz. `docs/altin.md`).
  Girişte cihazdaki kopya ile buluttaki karşılaştırılır, yenisi kazanır; bu telefonda başka bir hesaptan kalan
  kopya yüklenmez.
- **Kurallar:** Yalnızca sahibi yazar (misafir yazamaz). Okuyabilenler: sahibi ve arkadaşları
  (`friendships/{a}_{b}` belgesi olanlar). `photo` JPEG imzasıyla (FF D8 FF) başlamalı, 100 bayt ile 60 KiB
  arasında olmalı; `name` 1-24 karakter. Başka alan kabul edilmez.
- **Nerede görünür:** Profil başlığı, Arkadaşlar listesi ve Lig (kendi satırın; gerçek ligde arkadaşın olan
  üyeler). Fotoğrafı olmayan için maskot ya da hayvan simgesi kalır.
- **Çocuk modu:** Fotoğraf yükleme kapalı, avatar Pofuduk.
- **Android:** İzin gerekmez. Galeri sistem Fotoğraf Seçici'yi kullanır; kamera için manifestte yalnızca
  `IMAGE_CAPTURE` sorgusu var (CAMERA izni bilerek eklenmedi).

## Uygulamadaki bağlantı

- `lib/services/league_remote.dart` (Dünya Ligi, ayrıntı aşağıda): hesabı olan kullanıcı ilk kez lig ekranında
  ne paylaşılacağını görüp **Lige katıl**'a basar; sonra her hafta otomatik yerleşir. Haftanın XP'si
  `leagueXpSyncProvider` ile her ders sonrası bildirilir. Firebase kapalıysa, çevrimdışıysa ya da hata olursa
  lig ekranı simüle rakiplerle çalışır.
- `lib/services/conversation.dart`: Firebase hazır ve giriş yapılmışsa `converse` fonksiyonunu çağırır,
  değilse çevrimdışı demo çalışır. Hata kodları Türkçe mesajlara çevrilir.

## İlerleme hesaba bağlı, herkese ücretsiz

`users/{uid}` yazmak için giriş sağlayıcısı anonim olmamalı (`hasAccount()`: `request.auth.token.firebase.sign_in_provider
!= 'anonymous'`). Google, e-posta ya da telefonla giren herkes ilerlemesini hesabına yazar; Premium gerekmez.
Misafir (anonim) yazamaz, ilerlemesi cihazda kalır. Giriş yapınca aynı uid korunur ve cihazdaki ilerleme hesaba geçer.

## Dünya Ligi

Arkadaş tablosundan ayrı, haftalık, ülke fark etmeksizin 100 kişilik gruplar. Ligler (alttan üste): Bronz,
Gümüş, Altın, Safir, Yakut, Zümrüt, Ametist, İnci, Obsidyen, Elmas. Hafta pazartesi 00:00 Türkiye saatinde
başlar ve biter (her ülke için aynı an).

- **Kim katılır:** Google, e-posta ya da telefonla giriş yapmış kullanıcılar. Misafir tabloyu örnek olarak
  görür ve giriş yapmaya davet edilir. Çocuk modunda Dünya Ligi yoktur (yalnızca cihazdaki simüle lig).
- **Gizlilik:** İlk katılımda kart, gruptaki herkesin adını, profil fotoğrafını ve ülke bayrağını göreceğini
  söyler. Fotoğraf `profiles/{uid}` kuralları değiştirilmeden, katılırken 64 px'lik küçük bir kopyası olarak
  üye satırına yazılır (yalnızca o grubun üyeleri okuyabilir). **Ligden ayrıl** satırı hemen siler.
- **Ülke:** Telefonun bölgesinden gelir, Profil > "Ligde ülkem" ile değişir (cihazda `league_country_v1`).
- **Ekran:** Kendi satırın vurgulu, açılınca oraya kaydırılır; yükselme (yeşil) ve alt lig (kehribar) çizgileri,
  dakikada bir yenilenen geri sayım. Hafta bitince tam ekran sonuç sayfası çıkar (bir kez, `league_result_seen_v1`).
  Metinler yarış dilindedir: ceza, can ya da "düştün" yok.
- **Hile koruması:** Satırlara ve `leagueState`'e yalnızca fonksiyonlar yazar (kurallar istemciye kapalı,
  `functions/test/rules.test.ts`). XP dakikalık ve günlük sınırla kırpılır; sunucu haftalık toplamı alır, tekrar
  sayılmaz. Herkes Bronz'dan başlar.

### Blaze olmadan (yalnızca kurallarla) olur mu?

Değerlendirildi, **seçilmedi**. Grup atama, sayaç ve XP hız sınırı kurallarla (`getAfter`, `request.time`)
kısmen kurulabilir; ama hafta kapanışında sıralamayı ve yeni ligi hesaplayacak güvenilir bir taraf kalmaz.
Rakamları istemci hesaplarsa herkes kendini terfi ettirebilir, kurallar 100 satırı sayıp sırayı doğrulayamaz.
Bu yüzden lig Cloud Functions ile tamamlandı; Spark'ta uygulama "Çevrimdışı mod" (simüle rakipler) ile çalışmaya
devam eder.

### Gerçek projede (`dilbaz-3392e`) açmak için

1. Konsolda **Blaze** planına geç ve **bütçe uyarısı** kur (ör. aylık 5 USD; %50/%90/%100 e-posta).
2. Cloud Functions, Cloud Build, Artifact Registry ve Cloud Scheduler API'leri ilk deploy'da açılır (onay ister).
3. Kuralları ve fonksiyonları yayınla:
   ```bash
   firebase deploy --only firestore:rules,functions:joinLeague,functions:addLeagueXp,functions:leaveLeague,functions:settleLeagues --project dilbaz-3392e
   ```
   (`converse`/`assessWriting` `ANTHROPIC_API_KEY` gizli değerini ister; onları ayrıca yayınla.)

**Tahmini maliyet** (Firestore europe-west1, Functions ücretsiz kotası ayda 2 milyon çağrı):
lig ekranı her açılışta en çok 100 belge okur; günde 3 açılış × 1000 aktif kullanıcı ≈ 300 bin okuma/gün.
Ücretsiz kota 50 bin okuma/gün, üstü 100 binde ~0,06 USD → ayda ~4–5 USD. XP bildirimi ders başına bir çağrı
(ücretsiz kotada kalır). 100 kullanıcıya kadar fiilen ücretsiz; Cloud Scheduler 3 işe kadar ücretsiz.
