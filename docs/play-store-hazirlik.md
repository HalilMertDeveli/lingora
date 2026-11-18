# Google Play hazırlık listesi

QA turu (qa-ucretsiz, 2026-11-18) sonunda Dilmaç'ın Play Store'a çıkışı için durum.
✅ hazır · ❌ eksik (yapılması gereken yazılı) · ⚠️ karar ya da kontrol gerekiyor.

Kaynaklar: [Core App Quality](https://developer.android.com/docs/quality-guidelines/core-app-quality),
Play Console politika merkezi. Mağaza metinleri için [magaza/play-store.md](magaza/play-store.md).

## 1. Teknik gereksinimler

| Durum | Madde | Ayrıntı |
|---|---|---|
| ✅ | targetSdk | 36 (Flutter 3.47 varsayılanı). Play'in güncel yeni uygulama şartını karşılıyor. compileSdk 37, minSdk 24 (Android 7). |
| ✅ | App Bundle | `flutter build appbundle --release` başarılı: `app-release.aab` 85 MB. Play'in 200 MB temel modül sınırının altında. |
| ✅ | 64 bit | AAB içinde `arm64-v8a`, `armeabi-v7a`, `x86_64` kütüphaneleri var. |
| ✅ | Hata ayıklama bayrakları | Release manifestinde `debuggable` yok. `LINGORA_PREMIUM` geliştirici bayrağı yalnızca release dışı derlemelerde çalışıyor (`premium.dart`). Release'te cleartext trafik açık değil. |
| ✅ | versionCode / versionName | `pubspec.yaml`: `0.1.0+1` → versionCode 1. İlk yükleme için uygun. Her yeni yüklemede `+N`'i artır. |
| ✅ | Uygulama ikonu | Uyarlanabilir ikon var (`mipmap-anydpi-v26/ic_launcher.xml`: arka plan + ön plan). Android 13 temalı ikon için `monochrome` katmanı yok; isteğe bağlı. |
| ❌ | **Sürüm imzalama** | `android/key.properties` yok, bu yüzden release derlemesi **debug anahtarıyla** imzalanıyor. Play bunu kabul etmez. Yapılacak: bir yükleme anahtarı (upload key) oluştur, Play App Signing'i aç, CI için `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` ve `ANDROID_KEY_PASSWORD` secret'larını ekle (`release.yml` bunları `key.properties`'e yazar). Anahtarı kaybetme; yedekle. |
| ❌ | **Google ile giriş (Play imzası)** | Play App Signing açıldıktan sonra Play'in **uygulama imzalama SHA-1/SHA-256** parmak izlerini Firebase Console > Proje ayarları > Android uygulaması'na ekle. Yoksa Play'den inen sürümde Google girişi "[16] Account reauth failed" verir. |

## 2. İzinler

| Durum | İzin | Gerekçe ve yapılacak |
|---|---|---|
| ✅ | `RECORD_AUDIO` | Konuşma alıştırmaları, ses koçu, mülakat provası. Mikrofona dokununca isteniyor. Reddedilince açık Türkçe mesaj ve "Şu an konuşamıyorum" / yazarak devam seçeneği var (QA'da denendi). |
| ✅ | `POST_NOTIFICATIONS` | Günlük hatırlatma, kullanıcı "Aç" deyince isteniyor. Reddedilince açıklama var. **QA düzeltmesi:** hatırlatma başka telefondan açık geldiyse ve bu telefonda izin yoksa Profil artık uyarıyor ve "İzin ver" sunuyor. |
| ⚠️ | `READ_CONTACTS` | "Rehberden bul": yalnızca düğmeye basınca isteniyor. Numaralar karma (hash) olarak sunucuya gidiyor. Play Console > **Veri güvenliği** formunda "Kişiler" veri türünü işaretle (toplanıyor, paylaşılmıyor, isteğe bağlı, amaç: uygulama işlevi). İstemden önce açıklama ekranı olduğunu gözden geçir (Kullanıcı Verileri politikası: belirgin açıklama). |
| ✅ | `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `WAKE_LOCK` | Hatırlatma zamanlaması. Kesin alarm (exact alarm) izni yok. |
| ✅ | `com.android.vending.BILLING` | Abonelik ve sınav paketleri. |
| ✅ | **AD_ID kaldırıldı** | Firebase Analytics SDK'sı `AD_ID` ve `ACCESS_ADSERVICES_*` izinlerini ekliyordu. Uygulamada reklam yok, bu yüzden QA'da manifestten `tools:node="remove"` ile çıkarıldı. Play Console > Uygulama içeriği > **Reklam kimliği** sorusuna "Hayır" de. |
| ✅ | `USE_BIOMETRIC` / `USE_FINGERPRINT` | Google Credential Manager'dan (Google ile giriş) geliyor. Normal izin, beyan gerekmez. |

## 3. Politika ve kullanıcı verisi

| Durum | Madde | Ayrıntı |
|---|---|---|
| ✅ | **Uygulama içi hesap silme** | QA'da eklendi: Profil > Hesap > **Hesabımı sil**. Onaydan sonra `deleteAccount` (Cloud Function) sunucudaki tüm kullanıcı verisini ve Auth kullanıcısını siler. Kapsam: ilerleme, profil, arkadaşlıklar, lig, aile, kurum koltuğu, kotalar, prova geçmişi, satın alma bağı. Çevrimdışı hata mesajı ve çift dokunma koruması var. Testler: `functions/test/account.test.ts`, `test/account_delete_test.dart`. |
| ❌ | **Hesap silme web bağlantısı** | Play, uygulamayı kurmadan da silme isteyebilmek için bir **web adresi** istiyor (Uygulama içeriği > Veri güvenliği > Hesap silme). Bir sayfa yayınla. Örnek: `https://dilbaz-3392e.web.app/hesap-silme`, "Uygulamada Profil > Hesap > Hesabımı sil; uygulaman yoksa destek adresine kayıtlı e-postandan yaz" metniyle. |
| ✅ | Uygulama içi gizlilik politikası bağlantısı | QA'da eklendi: Profil > Gizlilik > **Gizlilik Politikası**, tarayıcıda açılıyor. Adres: `https://dilbaz-3392e.web.app/gizlilik` (`lib/core/legal_links.dart`; `--dart-define=LINGORA_PRIVACY_URL=` ile değiştirilebilir). |
| ❌ | **Gizlilik politikasını yayınla** | `docs/magaza/gizlilik-politikasi.md` taslağındaki `[Ad Soyad / Şirket]`, `[adres]`, `[destek@alanadi]` ve tarih alanlarını doldur. Hukukçu kontrolünü yap. Sonra yukarıdaki adreste yayınla ve aynı adresi Play Console'a gir. Taslaktaki "[Hesap silme özelliği eklendiğinde…]" notu artık gerçek: "Profil > Hesap > Hesabımı sil" yaz. `veri-guvenligi.md`'deki silme yanıtını da "uygulama içinden" olarak güncelle. |
| ⚠️ | **Hedef kitle ve Aileler politikası** | `play-store.md` hedef kitleyi 13+ öneriyor. Ama uygulamada "Çocuğum için (Çocuk modu): İlkokul, ortaokul ve LGS" seçeneği var. Google bunu çocuklara yönelik içerik sayabilir. 13 yaş altını hedef kitleye eklemek **Aileler politikası**nı getirir: sertifikalı SDK'lar, Analytics kısıtları, ebeveyn izni. Karar ver: (a) 13 yaş altını seçme ve çocuk modunu "ebeveyn gözetiminde, ortaokul/LGS" diye konumla; ya da (b) Aileler programına uy. Bu bir hukuk ve ürün kararı. |
| ⚠️ | Veri güvenliği formu | `veri-guvenligi.md`'yi şu güncel durumla karşılaştır. E-posta/telefon (hesap), kullanıcı kimliği, uygulama etkileşimleri (ilerleme), isteğe bağlı analiz (onaylı), kişiler (karma), profil fotoğrafı, ses (konuşma tanıma cihazda; mülakat provası ve ses koçu metni sunucuya ve yapay zekâ sağlayıcısına gidiyor). Reklam kimliği yok. |
| ✅ | İçerik derecelendirme | Eğitim. Kullanıcılar arası serbest mesajlaşma yok (lig: takma ad + XP; arkadaş: hazır tezahürat). Beklenen sonuç: Herkes / 3+. |

## 4. Satın almalar (Premium alanı, qa-premium'a da bildirildi)

| Durum | Madde | Ayrıntı |
|---|---|---|
| ❌ | **Satın alma doğrulaması** | `functions/src/purchase.ts` `verifyPurchase`, emülatör dışında `play_verification_not_configured` hatası veriyor. Yani **gerçek satın alma Premium açmıyor**. Çıkıştan önce Google Play Developer API doğrulaması (servis hesabı + androidpublisher) ve RTDN (Pub/Sub) bağlanmalı. Ayrıntılar kod içindeki TODO'da. |
| ❌ | Ürünler | Play Console > Para kazanma > Abonelikler / Uygulama içi ürünler: `lib/services/billing/products.dart`'taki ürün kimliklerini birebir oluştur. Fiyatları ve deneme süresini gir. |

## 5. Play Console'da senin yapacakların (sıra önerisi)

1. Yükleme anahtarını oluştur, CI secret'larını ekle, Play App Signing'i aç. Ardından Play imzalama SHA'larını Firebase'e ekle.
2. Gizlilik politikasını doldur ve yayınla. Hesap silme sayfasını yayınla.
3. Uygulama içeriği bölümleri: gizlilik politikası URL'si, reklam yok, reklam kimliği "Hayır", hedef kitle (bkz. Aileler kararı), içerik derecelendirme anketi, veri güvenliği formu, hesap silme URL'si, haber uygulaması değil, devlet uygulaması değil, finans özelliği yok, sağlık değil.
4. Mağaza kaydı: başlık, kısa ve uzun açıklama (`magaza/play-store.md`), 512×512 ikon, 1024×500 öne çıkan görsel, en az 2 telefon ekran görüntüsü (`magaza/ekran-goruntuleri.md`).
5. `verifyPurchase` doğrulaması ve ürünler (madde 4) bitince **Kapalı test**: en az 12 test kullanıcısıyla 14 gün. Yeni kişisel geliştirici hesaplarında üretime çıkmak için bu şart.
6. Cloud Functions'ı deploy et. Bu dalla gelenler: `deleteAccount` ve `firestore.rules` (deletedAccounts mezar taşı). Orkestratör yapar.

## 6. QA'da cihazda doğrulanan Core App Quality maddeleri

Ayrıntılı senaryolar ve ekran görüntüleri: `_cikti/qa-ucretsiz/rapor.md` (repo dışında).

- Geri tuşu: ders ortasında onay ("Dersten çıkılsın mı?"); ödeme ekranından sohbete dönüş; çıkmaz sokak yok.
- Döndürme ve süreç ölümü: ders durumu korunuyor. Arka planda süreç öldürülünce "Kaldığın yerden devam ediyorsun".
- İzin reddi (mikrofon, "bir daha sorma" dahil): uygulama kullanılabilir kalıyor, Türkçe yönlendirme var.
- Çevrimdışı giriş/kayıt/silme: açık Türkçe mesaj, veri kaybı yok.
- En büyük yazı + ekran boyutu (720×1280): üst çubuk taşması ve sekme etiketi bu dalda düzeltildi.
- Koyu mod canlı geçiş. Çocuk modunda Çaycı Dayı yok (Pofuduk).
- Gerçek cihaz (Samsung Galaxy M22, Android 13): soğuk açılış ~2 sn, ders boyunca %0.5 takılan kare. Gerçek mikrofon/STT dinlemeye başlıyor; sessizlik ve çevrimdışı mesajları Türkçe. Samsung klavyesiyle kayıt ve geri hareketi çalışıyor. Samsung en büyük yazıda düzen bozulmuyor. Uçak modunda yapılan ders bağlanınca hesaba eşitleniyor. Gerçek sesle tanıma doğruluğunu elle dene.
- ⚠️ Android 7–9: içerikteki Emoji 12+ karakterleri (ör. 🩺 🧊 🪑 🪙, ~50 farklı) "NO GLYPH" kutusu olarak görünüyor. Rapor bölüm "Açık kararlar"a bak.
