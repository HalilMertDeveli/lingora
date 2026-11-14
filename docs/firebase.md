# Firebase (istemci)

Dilbaz varsayılan olarak gerçek Firebase projesine (`dilbaz-3392e`) bağlanır. Mod derleme sırasında
`--dart-define=LINGORA_FIREBASE=...` ile değiştirilebilir:

| Değer | Ne olur |
|---|---|
| `off` | Firebase hiç başlatılmaz, ilerleme sadece cihazda (`shared_preferences`). |
| `emulator` | `demo-lingora` projesi ile yerel Firebase Emulator Suite'e bağlanır (Auth 9099, Firestore 8080, Functions 5001). |
| *(yok)* / `prod` | Varsayılan. Gerçek proje `dilbaz-3392e` (`firebase_options_prod.dart`, `android/app/google-services.json`). |

Başlatma başarısız olursa (yapılandırma yok, ağ yok…) uygulama çökmez, yerel modda devam eder.

## Kod nerede

`lib/services/firebase/`

- `firebase_config.dart` — mod (`FirebaseMode`), emülatör portları/host'u, Functions bölgesi.
- `firebase_bootstrap.dart` — `initFirebase(mode)`; emülatör bağlantıları.
- `demo_firebase_options.dart` — `demo-lingora` için elle yazılmış seçenekler (yalnızca emülatörle çalışır).
- `firebase_options_prod.dart` — `flutterfire configure --project=dilbaz-3392e` çıktısı (Android, iOS, web).
- `firebase_providers.dart` — diğer modüllerin kullandığı sözleşme:
  - `firebaseReadyProvider` (`bool`), `authStateProvider` (`Stream<AppUser?>`), `currentUidProvider` (`String?`)
  - `firebaseAuthProvider`, `firestoreProvider`, `functionsProvider` (Firebase kapalıyken `null`)
- `account_service.dart` — anonim giriş, e-posta / Google / telefon (SMS) ile hesaba bağlama (aynı uid korunur), çıkış. `normalizePhoneTr` Türk numaralarını `+90…` biçimine çevirir.
- `progress_merge.dart` — iki ilerleme kopyasını birleştirme kuralı.
- `progress_sync.dart` — `users/{uid}` ile çevrimdışı öncelikli iki yönlü eşitleme.

Profil ekranındaki "Hesap" kartı: `lib/screens/account_section.dart`.

## Veri modeli: `users/{uid}`

```json
{
  "schemaVersion": 1,
  "progress": { "...": "Progress.toJson()" },
  "totalXp": 1234,
  "displayName": "…" ,
  "clientUpdatedAt": 1762770000000,
  "updatedAt": "<serverTimestamp>"
}
```

İstemci yalnızca bu alanları yazar (`SetOptions(mergeFields: ...)`), Cloud Functions aynı belgeye başka
alanlar ekleyebilir. `leagues/*` ve `entitlements/*` istemci tarafından yazılmaz.

## Eşitleme ve birleştirme kuralı

**İlerleme hesaba bağlıdır ve ücretsizdir.** Google, e-posta ya da telefonla giriş yapan herkesin ilerlemesi
hesabına kaydedilir; başka bir telefonda aynı hesapla girince geri gelir. `progressSyncProvider` yalnızca
misafir (anonim) kullanıcıda durur: durum `SyncState.guest` olur, her şey cihazda kalır ve hesap kartı
"İlerlemen yalnızca bu telefonda" der. Karşılama ekranında ve Profil > Hesap'ta "Giriş yap" vardır.

- Giriş yapılınca hemen eşitlenir: önce hesaptaki kopya çekilip birleştirilir,
  sonra hesaba yazılır. Misafirken yapılan düzenlemelerin zamanı da tutulur; bu sayede o dönemde
  değişen ayarlar birleştirmede "en yeni" sayılır.
- Çıkış yapılınca eşitleme durur. Cihazdaki veriler silinmez; hesaptaki kopya olduğu gibi kalır.
- Sunucu tarafında da `users/{uid}` yazmaları gerçek bir hesap ister (Firestore kuralı `hasAccount()`:
  giriş sağlayıcısı `anonymous` olmamalı). Bir yazma reddedilirse istemci 30 sn sonra tekrar dener.

- Kullanıcı Firebase açıkken otomatik olarak **anonim** giriş yapar; Profil > Hesap'tan Google ya da
  e-posta ile hesabını bağlayabilir (`linkWithCredential` — uid değişmez, ilerleme korunur). Hesap zaten
  varsa ona giriş yapılır ve cihazdaki ilerleme o hesapla birleştirilir.
- Her yerel kayıttan sonra 3 sn bekleyip tek yazma yapılır; ağ yoksa Firestore yazmayı kuyrukta tutar
  ("İnternet gelince buluta yedeklenecek").
- Bulut belgesi dinlenir; farklıysa birleştirilir:
  - XP, gün gün XP, tamamlanan dersler, ders/cevap sayaçları, görev sayaçları, sınav rekorları, hata
    istatistikleri → anahtar bazında **en büyük** değer;
  - alınan görev ödülleri, günlük (diary), kişisel kelimeler → **birleşim**;
  - seri → en son aktif olunan kopyadan (aynı gün ise uzun olan);
  - kelime tekrarı → kelime başına vadesi daha ileri olan;
  - lig → daha yeni haftadaki kopya;
  - ayarlar (günlük hedef, hatırlatma, kurs, hata listesi) → en son değiştirilen kopya
    (`clientUpdatedAt`).
- Çıkış yapınca cihazdaki ilerleme silinmez; yeni bir anonim hesap açılır.

## Emülatörle çalıştırma

Emülatörler, kurallar ve Cloud Functions sunucu tarafındadır (`firebase.json`, `.firebaserc`, `functions/`);
ayrıntılar için `docs/firebase-backend.md`. Kısaca:

```bash
cd functions && npm run serve
```

```bash
flutter run --dart-define=LINGORA_FIREBASE=emulator
```

Android emülatöründen bilgisayara `10.0.2.2` ile, diğer platformlardan `localhost` ile bağlanılır. Gerçek
telefonda: `--dart-define=LINGORA_EMULATOR_HOST=<bilgisayarın-LAN-IP'si>`. Emülatör arayüzü
http://localhost:4000 adresindedir. Emülatörde e-posta/şifre ile bağlama denenebilir; Google girişi
gerçek proje ister.

Android'de varsayılan Firebase uygulaması `google-services.json`'dan (gerçek proje) yerel olarak kurulur. Bu yüzden
emülatör modu ayrı bir uygulama (`lingora-emulator`, bkz. `lingoraFirebaseApp`) kullanır. Debug sürümünde Auth
emülatörünün düz HTTP'sine izin verilir (`android/app/src/debug/AndroidManifest.xml`). Giriş akışlarının uçtan uca
testleri ve gerçek projede elle deneme listesi: `docs/giris-testleri.md`.

## Gerçek projeyi bağlamak (sahibin yapacakları)

1. https://console.firebase.google.com adresinde proje oluştur (ör. `lingora-app`), Blaze planı
   (Functions için gerekir).
2. **Authentication > Sign-in method**: *Anonymous*, *Email/Password* ve *Google* sağlayıcılarını aç.
3. **Firestore Database**: üretim modunda oluştur, bölge `europe-west1` (Functions ile aynı olsun).
4. Bilgisayarda:

   ```bash
   firebase login
   ```

   ```bash
   flutterfire configure --project=<proje-id> --out=lib/services/firebase/firebase_options_prod.dart --platforms=android,ios,web --android-package-name=com.lingora.lingora --ios-bundle-id=com.lingora.lingora
   ```

   Bu komut yer tutucu `firebase_options_prod.dart` dosyasını gerçek değerlerle değiştirir ve
   `android/app/google-services.json` ile `ios/Runner/GoogleService-Info.plist` dosyalarını ekler.
   (Proje herkese açık bir depoda; bu değerler gizli değildir, güvenlik Firestore kuralları ve
   App Check ile sağlanır.)
5. **Google ile giriş (Android)**: Firebase konsolunda Android uygulamasına debug ve release imza
   anahtarlarının SHA-1/SHA-256 parmak izlerini ekle (`cd android` ve `./gradlew signingReport`).
   Ardından `flutterfire configure`'ı tekrar çalıştır. Gerekirse "Web client" OAuth kimliğini
   `--dart-define=LINGORA_GOOGLE_SERVER_CLIENT_ID=<...>.apps.googleusercontent.com` ile ver.
   iOS için `GoogleService-Info.plist` içindeki `REVERSED_CLIENT_ID`'yi `ios/Runner/Info.plist`'e URL
   şeması olarak ekle.
6. `.firebaserc`'ye gerçek proje kimliğini ekle ve kuralları/fonksiyonları yayınla (sunucu tarafı,
   bkz. `firebase.json`): `firebase deploy --only firestore,functions --project <proje-id>`.
7. Uygulamayı gerçek projeyle derle:

   ```bash
   flutter build appbundle --dart-define=LINGORA_FIREBASE=prod
   ```

   CI/release iş akışında da aynı `--dart-define` eklenmelidir; eklenmezse uygulama yerel modda kalır.

## Gerçek proje: dilbaz-3392e

- Kayıtlı uygulamalar: Android `com.lingora.lingora`, iOS `com.lingora.lingora`, web. Teknik kimlikler eski adla kalır.
- Giriş yöntemleri açık: anonim, e-posta/şifre, Google, telefon. Google için web OAuth istemcisi
  `googleServerClientId` varsayılanında (`firebase_config.dart`).
- Android debug anahtarının SHA-1/SHA-256'sı projeye ekli. **Yayın (release) anahtarı oluşturulunca onun SHA-1 ve
  SHA-256'sı da** `npx -y firebase-tools@latest apps:android:sha:create <APP_ID> <SHA>` ile eklenmeli; yoksa Google ve
  telefon girişi mağaza sürümünde çalışmaz. Ardından `google-services.json` yeniden indirilmeli
  (`apps:sdkconfig ANDROID <APP_ID>`).
- Firestore: `(default)` veritabanı, kurallar ve indeksler `npx -y firebase-tools@latest deploy --only firestore --project dilbaz-3392e`
  ile yüklenir.
- `.firebaserc`: `default` = `demo-lingora` (emülatör), `prod` = `dilbaz-3392e`. Gerçek projeye komut verirken her zaman
  `--project dilbaz-3392e` (ya da `--project prod`) yaz.
