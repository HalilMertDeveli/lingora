# Lingora

[![CI](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml)
[![Release APK](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml)

Türkçe konuşanlar için İngilizce öğrenme uygulaması (Flutter). İçerik, karakterler, maskot ve
tasarım projeye özgüdür.

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
- **Görünüm:** Animasyonlar ve tamamen kodla çizilen maskot "Lino".

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

## Yapay zekâ sohbet sunucusu

`server/` klasöründe Claude ile konuşan bir Supabase Edge Function var. Kurulumu ve uygulamaya
bağlamak için [server/README.md](server/README.md) dosyasına bak. Bağlanmadığında "Konuş" sekmesi
demo modunda çalışır.

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
