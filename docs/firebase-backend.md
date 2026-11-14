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
| `leagueState/{uid}` | sahibi | yalnızca fonksiyonlar | `tier, weekKey, groupId, name, avatar, lastResult{weekKey, oldTier, newTier, rank}` ve XP hız sınırı sayaçları. |
| `leagues/{hafta}_{lig}_{grup}` ve `.../members/{uid}` | yalnızca o grubun üyeleri | yalnızca fonksiyonlar | Grup: `weekKey, tier, group, size, settled`. Üye: `name, avatar, xp, rank`. |
| `entitlements/{uid}` | sahibi | yalnızca fonksiyonlar | `active, premium, status, productId, platform, expiresAt, source, updatedAt`. |
| `usage/*`, `purchases/*`, `leagueWeeks/*` | kimse | yalnızca fonksiyonlar | Günlük mesaj kotası, satın alma jetonu → kullanıcı bağı, grup doluluk sayacı. |

Fonksiyonlar Admin SDK kullandığı için kurallardan etkilenmez. Diğer her yol istemciye kapalıdır.

## Fonksiyonlar

Hepsi çağrılabilir (callable) fonksiyondur ve giriş yapmış kullanıcı ister (`unauthenticated`).

- **`joinLeague {name?, avatar?, tier?}` → `{groupId, weekKey, tier}`**: Kullanıcıyı bu haftanın, kendi
  ligindeki 15 kişilik bir gruba yerleştirir (dolunca yeni grup açılır). Tekrar çağrılabilir. `tier` yalnızca
  ilk kez katılan kullanıcı için dikkate alınır (cihazdaki çevrimdışı lig seviyesi). Önceki haftası henüz
  kapanmamışsa önce onu kapatır.
- **`addLeagueXp {xp}` → `{xp, accepted}`**: Haftalık XP'ye ekler. Çağrı başına 1–500 XP, iki çağrı
  arasında en az 3 saniye (`resource-exhausted`), Türkiye saatiyle günde en çok 3000 XP (fazlası kabul
  edilmez, `accepted` daha küçük döner). Önce `joinLeague` gerekir (`failed-precondition`).
- **`settleLeagues`** (zamanlanmış, her pazartesi 00:05, `Europe/Istanbul`): Biten haftaların gruplarını
  kapatır. Kurallar uygulamadaki yerel ligle aynıdır: XP'si olan ilk 5 üst lige çıkar, 11–15. sıralar alt
  lige düşer (Bronz düşmez, Elmas çıkmaz). Beraberlikte gruba önce katılan önde. Sonuç
  `leagueState/{uid}.lastResult` alanına yazılır.
- **`converse {scenarioId, messages}` → `{reply, correction, tip_tr, done, remaining}`**: Eski Supabase
  proxy'sinin aynısı: senaryo komutları sunucuda (`functions/src/scenarios.ts`), model `claude-opus-5-5`,
  düşük effort, JSON şemalı yanıt, güvenlik reddinde sahneye dönen sabit yanıt, sunucu tarafı yedek model
  (`fallbacks: "default"`). Ek olarak: etkin Premium (`entitlements/{uid}`, `active` ya da `premium` ve
  `expiresAt` gelecekte) yoksa `permission-denied`; günde 60 mesaj kotası dolunca `resource-exhausted`;
  Anthropic hatasında `unavailable` ve o mesaj kotadan düşülmez. API anahtarı Secret Manager'daki
  `ANTHROPIC_API_KEY` gizli değerinden okunur.
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

Maliyet notu: `converse` her mesajda yaklaşık 2–3 bin girdi ve birkaç yüz çıktı jetonu kullanır. Günlük
kota (`DAILY_MESSAGE_LIMIT`) ve model `functions/src/converse.ts` içinde tek satırlık ayarlardır; daha
ucuz bir modele geçmeden önce gerçek sohbetlerde kaliteyi ölç.

## Eski Supabase kodu neden silindi

`server/supabase/functions/converse/` (Deno Edge Function) hiç yayına alınmamıştı ve arka uç tamamen
Firebase'e taşındı. Senaryo komutları ve doğrulama mantığı aynen `functions/src/` içine taşındı, uygulamadaki
HTTP istemcisi (`LINGORA_AI_URL` / `LINGORA_AI_KEY`) yerine `converse` çağrılabilir fonksiyonu kullanılıyor.
İki ayrı arka ucu bakımda tutmanın faydası olmadığı için kod kaldırıldı; gerekirse git geçmişinde duruyor.

## Uygulamadaki bağlantı

- `lib/services/league_remote.dart`: Firebase hazır ve kullanıcı giriş yapmışsa `joinLeague` çağırır,
  cihazdaki bu haftanın XP'sinden sunucuda eksik olanı `addLeagueXp` ile yükler ve grubu Firestore'dan
  canlı dinler. Firebase kapalıysa, çevrimdışıysa ya da hata olursa lig ekranı simüle rakiplerle çalışır.
- `lib/services/conversation.dart`: Firebase hazır ve giriş yapılmışsa `converse` fonksiyonunu çağırır,
  değilse çevrimdışı demo çalışır. Hata kodları Türkçe mesajlara çevrilir.

## İlerleme hesaba bağlı, herkese ücretsiz

`users/{uid}` yazmak için giriş sağlayıcısı anonim olmamalı (`hasAccount()`: `request.auth.token.firebase.sign_in_provider
!= 'anonymous'`). Google, e-posta ya da telefonla giren herkes ilerlemesini hesabına yazar; Premium gerekmez.
Misafir (anonim) yazamaz, ilerlemesi cihazda kalır. Giriş yapınca aynı uid korunur ve cihazdaki ilerleme hesaba geçer.
