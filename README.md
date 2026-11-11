# Dilbaz

[![CI](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml)
[![Release APK](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml)

Türkçe konuşanlar için İngilizce öğrenme uygulaması (Flutter). İçerik, karakterler ve
tasarım projeye özgüdür; maskot (Çaycı Dayı) ve görseller uygulama sahibi tarafından sağlandı.

> Uygulamanın adı **Dilbaz**'dır ("dili güzel, lafı akıcı"). Teknik kimlikler eski adla kalır: Dart
> paket adı `lingora`, Android `applicationId`/namespace ve iOS bundle id `com.lingora.lingora`, Firebase
> proje kimlikleri (`demo-lingora`), Firestore koleksiyon/alan adları (ör. `config/lingoraAdmins`,
> `isLingoraAdmin` claim'i), analitik olay adları, shared_preferences anahtarları, Play ürün kimlikleri
> (`lingora_premium_*`, `lingora_pack_*`), kod içi sınıf adları (`LingoraApp`, `LingoraTheme`, `LingoraSans`
> font ailesi) ve GitHub repo adı.

## Özellikler

- **Genel İngilizce:** A1–A2, 12 ünite. Her ünitede dersler, karakterli hikâye, ünite sınavı ve
  ödül sandığı var. Alıştırma türleri: seçmeli, çeviri, boşluk doldurma, dinleme, eşleştirme, konuşma.
- **Meslek paketleri:** Turizm İngilizcesi (resepsiyon, restoran, rehberlik, şikâyet çözme) ve
  İş Görüşmesi İngilizcesi.
- **Sınav hazırlık:** YDS/YÖKDİL ve LGS soru bankaları. Konu çalışmada Türkçe açıklama, süreli
  mini deneme ve cevap anahtarı. Sorular özgündür, resmî sınav soruları değildir.
- **Notlarım:** Notion'da tutulan kişisel İngilizce notlarından üretilen içerik:
  - Gramer Yolu: notlardan hazırlanan, A1'den C1'e 80 adım adım ders (formül kartı, zaman çizelgesi,
    Türkçe karşılaştırma, notundan alıntı, yaygın hatalar, mini test),
  - kişisel sözlük (aralıklı tekrar kartları ve kelime testi),
  - gramer notları (kendi örneklerinden otomatik alıştırma),
  - İngilizce günlük.
- **Konuş:** Rol yapma sohbetleri. Hatalar Türkçe açıklamayla düzeltilir. Sunucu bağlı değilken
  demo modunda çalışır.
- **Cezasız öğrenme:** Can sistemi yok. Yanlış cevaplar tekrar sorulur ve "Hatalarını çalış"
  listesine eklenir.
- **Motivasyon:** Seri, XP, günlük hedef, günlük görevler, haftalık lig (cihazda simülasyon) ve
  yerel hatırlatma bildirimleri.
- **Görünüm:** Animasyonlar ve maskot **Çaycı Dayı** (görsel kaynağı: `docs/assets.md`).

Tüm ilerleme cihazda saklanır (shared_preferences). Hesap ya da sunucu gerekmez.

## Çalıştırma

```bash
flutter pub get
flutter run
```

Testler:

```bash
flutter test
```

## Sunucu (Firebase)

Lig, yapay zekâ sohbeti ve abonelik doğrulaması Firebase üzerinde çalışır: Firestore kuralları
`firestore.rules`, Cloud Functions `functions/` klasöründe. Kurulum, emülatörle yerel çalıştırma ve
yayına alma adımları için [docs/firebase-backend.md](docs/firebase-backend.md) dosyasına bak.
Firebase kapalıyken lig cihazda simüle edilir, "Konuş" sekmesi demo modunda çalışır.

## Notion notlarını güncelleme

Notlar `assets/notes/` altındadır. Notion'dan dönüştürülmüş JSON dosyalarını birleştirmek için:

```bash
node tool/import_notes.js <dönüştürülmüş-notlar-klasörü>
```

## Proje yapısı

- `lib/models`, `lib/data`: içerik modelleri, ilerleme, lig, görevler, aralıklı tekrar
- `lib/screens`: ekranlar
- `lib/exercises`: alıştırma türleri
- `lib/ui`: animasyonlar ve maskot
- `assets/courses`, `assets/exams`, `assets/notes`: içerik
- `test/`: mantık ve arayüz testleri (içerik doğrulaması dahil)

## Sürüm ve imzalama

- Her `main` push'unda **Release APK** iş akışı bir release APK derler ve Actions sayfasında
  `lingora-apk` artifact'ı olarak yükler.
- `v*` etiketi gönderildiğinde (ör. `git tag v0.2.0 && git push origin v0.2.0`) aynı APK ile bir
  GitHub Release oluşturulur.

Şu an APK **debug anahtarıyla** imzalanır (Play Store'a yüklenemez). Gerçek bir anahtar eklemek için:

1. Bir upload keystore oluştur (keystore dosyasını ve şifreleri asla repoya koyma):

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Dosyayı base64'e çevir: `base64 -w0 upload-keystore.jks` (Windows PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))`).
3. GitHub'da **Settings → Secrets and variables → Actions** altında şu repository secret'larını ekle:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

İş akışı secret'ları görünce `android/key.properties` ve `android/app/upload-keystore.jks` dosyalarını
üretir; `android/app/build.gradle.kts` bu dosya varsa gerçek anahtarı, yoksa debug anahtarını kullanır.
Yerelde imzalı derleme için aynı `key.properties` dosyasını elle oluşturabilirsin (git'e eklenmez).
