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
| ✅ | **Crashlytics** (yayın-öncesi dalı) | `firebase_crashlytics` + Crashlytics Gradle eklentisi 3.0.6 (google-services 4.4.4). FlutterError ve PlatformDispatcher hataları fatal; satın alma, eşitleme ve hesap hataları non-fatal (`CrashReporter.nonFatal`, sabit `reason` anahtarı). **Yalnızca prod derlemede ve analiz izniyle** açılır; manifest/plist ile kapalı başlar, izin geri alınınca gönderilmemiş raporlar silinir. Kullanıcı kimliği olarak yalnızca Firebase uid. Release derlemesi R8 eşleme dosyasını (`mapping.txt`) Crashlytics'e kendisi yükler (`uploadCrashlyticsMappingFileRelease`; ağ gerekir). Dart kodu `--obfuscate` ile derlenmiyor, Dart yığın izleri okunur; ileride `--obfuscate --split-debug-info=build/symbols` eklenirse her sürümde `firebase crashlytics:symbols:upload --app=<android app id> build/symbols` çalıştır. |
| ✅ | **Uygulama içi değerlendirme** | `in_app_review`: kusursuz ders, ünite sınavı geçme (seviye atlama) ve 7+ günlük seride, yol ekranına dönünce. En fazla 30 günde bir; ilk açılıştan 3 gün geçmeden, ebeveyn gözetimli modda, paywall'dan sonraki 1 saat içinde ve paywall ile aynı ders sonunda asla (`lib/services/growth/review_prompt.dart`). Play kendi kotasını da uygular; ekranın gösterilip gösterilmediğini uygulama bilmez. |
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
| ⏳ | **Hesap silme web bağlantısı** | Sayfa hazır: `hosting/sayfalar/hesap-silme.html` → `https://dilbaz-3392e.web.app/hesap-silme`. İletişim: dilmac.destek@gmail.com. Kalan: `firebase deploy --project prod --only hosting:yasal`, adresi Play Console'a gir (bkz. `hosting/README.md`). Önceki not: Play, uygulamayı kurmadan da silme isteyebilmek için bir **web adresi** istiyor (Uygulama içeriği > Veri güvenliği > Hesap silme). Bir sayfa yayınla. Örnek: `https://dilbaz-3392e.web.app/hesap-silme`, "Uygulamada Profil > Hesap > Hesabımı sil; uygulaman yoksa destek adresine kayıtlı e-postandan yaz" metniyle. |
| ✅ | Uygulama içi gizlilik politikası bağlantısı | QA'da eklendi: Profil > Gizlilik > **Gizlilik Politikası**, tarayıcıda açılıyor. Adres: `https://dilbaz-3392e.web.app/gizlilik` (`lib/core/legal_links.dart`; `--dart-define=LINGORA_PRIVACY_URL=` ile değiştirilebilir). |
| ⏳ | **Gizlilik politikasını yayınla** | Güncel metin: `hosting/sayfalar/gizlilik.html` (hesap silme, reklam kimliği yok, profil fotoğrafı, Ses Koçu / Mülakat Provası metni, Çocuk modu eklendi; `veri-guvenligi.md` silme yanıtı güncellendi). İletişim: dilmac.destek@gmail.com. Kalan: hukukçu kontrolü, yayın. Önceki not: `docs/magaza/gizlilik-politikasi.md` taslağındaki `[Ad Soyad / Şirket]`, `[adres]`, `[destek@alanadi]` ve tarih alanlarını doldur. Hukukçu kontrolünü yap. Sonra yukarıdaki adreste yayınla ve aynı adresi Play Console'a gir. Taslaktaki "[Hesap silme özelliği eklendiğinde…]" notu artık gerçek: "Profil > Hesap > Hesabımı sil" yaz. `veri-guvenligi.md`'deki silme yanıtını da "uygulama içinden" olarak güncelle. |
| ✅ | **Hedef kitle ve Aileler politikası** | **Karar (a), 2026-11-19:** hedef kitle **13+** (13–15, 16–17, 18+); 13 yaş altı seçilmez, Aileler programına girilmez. Eski "Çocuk modu" artık **Ebeveyn gözetimli mod**: onboarding seçeneği "Ebeveyn olarak, çocuğumla birlikte" (ebeveyn hesabıyla, ebeveyn gözetiminde; ortaokul ve LGS), Profil > Görünüm anahtarı "Ebeveyn gözetimli mod". "İlkokul" ifadesi kaldırıldı. Modda yapay zekâ kapalı (sohbet hazır senaryoyla; yazma değerlendirmesi ve Mülakat Provası yapay zekâsız: `conversationServiceProvider`, `writingServiceProvider`, `rehearsalServiceProvider`), arkadaş ekleme ve çevrimiçi lig kapalı, Çaycı Dayı yok (Pofuduk). Mağaza metni ve görseller çocuklara pazarlama yapmaz (`magaza/play-store.md`). Gizlilik politikası §7 güncellendi. |
| ⚠️ | Veri güvenliği formu | **Crashlytics eklendi:** "Uygulama bilgileri ve performansı > Kilitlenme günlükleri" ve "> Teşhis" artık **toplanıyor** (izinle, isteğe bağlı, amaç Analiz, paylaşılmıyor); "Kullanıcı kimlikleri" ve "Cihaz veya diğer kimlikler" satırlarına Crashlytics eklendi (`veri-guvenligi.md`). `veri-guvenligi.md`'yi şu güncel durumla karşılaştır. E-posta/telefon (hesap), kullanıcı kimliği, uygulama etkileşimleri (ilerleme), isteğe bağlı analiz (onaylı), kişiler (karma), profil fotoğrafı, ses (konuşma tanıma cihazda; mülakat provası ve ses koçu metni sunucuya ve yapay zekâ sağlayıcısına gidiyor). Reklam kimliği yok. |
| ✅ | İçerik derecelendirme | Eğitim. Kullanıcılar arası serbest mesajlaşma yok (lig: takma ad + XP; arkadaş: hazır tezahürat). Beklenen sonuç: Herkes / 3+. |

## 4. Satın almalar (Premium alanı, qa-premium'a da bildirildi)

| Durum | Madde | Ayrıntı |
|---|---|---|
| ✅ (kod) / ❌ (kurulum) | **Satın alma doğrulaması** | `verifyPurchase` artık Google Play Developer API ile doğruluyor, satın almayı onaylıyor; `playRtdn` (Pub/Sub `play-rtdn`) yenileme, iptal, ek süre, askı ve iadeleri izliyor. Senin yapacağın kurulum (servis hesabı izni, API, Pub/Sub, RTDN, ürünler, test kullanıcıları): **docs/play-satin-alma-kurulum.md**. |
| ❌ | Ürünler | Play Console > Para kazanma > Abonelikler / Uygulama içi ürünler: `lib/services/billing/products.dart`'taki ürün kimliklerini birebir oluştur. Fiyatları ve deneme süresini gir. |

## 5. Play Console'da senin yapacakların (sıra önerisi)

1. Yükleme anahtarını oluştur, CI secret'larını ekle, Play App Signing'i aç. Ardından Play imzalama SHA'larını Firebase'e ekle.
2. Gizlilik politikasını doldur ve yayınla. Hesap silme sayfasını yayınla.
3. Uygulama içeriği bölümleri: gizlilik politikası URL'si, reklam yok, reklam kimliği "Hayır", hedef kitle **13–15, 16–17, 18+** (13 altı seçilmez), içerik derecelendirme anketi, veri güvenliği formu, hesap silme URL'si, haber uygulaması değil, devlet uygulaması değil, finans özelliği yok, sağlık değil.
4. Mağaza kaydı: başlık, kısa ve uzun açıklama (`magaza/play-store.md`), 512×512 ikon, 1024×500 öne çıkan görsel ve 8 telefon ekran görüntüsü: hepsi hazır, `D:\Lingora\_cikti\magaza\` (`magaza/ekran-goruntuleri.md`).
4b. Firebase Console > Crashlytics sayfasını bir kez aç. Veri güvenliği formuna Crashlytics satırlarını işle. Güncellenen gizlilik politikasını (Crashlytics, ebeveyn gözetimli mod) yayınla: `firebase deploy --project prod --only hosting:yasal`.
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
- ✅ Android 7–9 emoji kutuları (yayın-öncesi dalı): Android 7.0'ın çizemediği tüm emojiler (tekil Emoji 4.0 ve 5.0+; uygulamada ~135 farklı) bu cihazlarda (API < 29) yükleme anında Android 7.0'da olan bir karşılıkla değiştiriliyor (`lib/core/emoji_compat.dart`, `legacy_emoji.dart`). İçerik dosyaları değişmedi, yeni telefonlar orijinali görür, ek yazı tipi yok (0 bayt). Noto Color Emoji alt kümesi de denendi: Google Fonts'taki sürüm COLRv1 ve elimizdeki alt küme aracı renk tablolarını düşürüyordu; karşılık tablosu hem küçük hem her metin yolunda çalışıyor. `test/legacy_emoji_test.dart`, lib/ ve assets/ içinde karşılığı olmayan yeni bir emoji görünce kırmızı yanar: yeni içerik emojisi eklerken `legacyEmojiMap`'e karşılık ekle. API 24 emülatöründe doğrulandı (`_cikti/yayin-oncesi/api24_*.png`).
