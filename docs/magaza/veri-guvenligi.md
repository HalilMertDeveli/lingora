# Play Console "Veri güvenliği" formu için cevaplar

Kaynak: yayınlanan gizlilik politikası `hosting/sayfalar/gizlilik.html` (`https://dilbaz-3392e.web.app/gizlilik`). Play Console > Uygulama içeriği > Veri güvenliği.

Genel:

- Uygulamanız gerekli kullanıcı verisi türlerinden herhangi birini topluyor veya paylaşıyor mu? **Evet**
- Toplanan tüm kullanıcı verileri aktarım sırasında şifreleniyor mu? **Evet**
- Kullanıcıların verilerinin silinmesini istemesi için bir yol sağlıyor musunuz? **Evet**: uygulama içinden **Profil > Hesap > Hesabımı sil** (sunucudaki veriler ve Auth kullanıcısı hemen silinir, `functions/src/account.ts`); uygulama olmadan e-postayla (en geç 30 gün).
- Hesap silme URL'si (Uygulama içeriği > Veri güvenliği > Hesap silme): **`https://dilbaz-3392e.web.app/hesap-silme`** (`hosting/sayfalar/hesap-silme.html`).
- Uygulama hesap oluşturmaya izin veriyor mu? **Evet** (Google, e-posta, telefon; misafir de olur).
- Reklam kimliği: **Hayır**, uygulama reklam kimliği kullanmıyor (`AD_ID` manifestten çıkarıldı).

| Veri türü | Toplanıyor | Paylaşılıyor | İsteğe bağlı mı | Amaç |
| --- | --- | --- | --- | --- |
| Kişisel bilgiler > E-posta adresi | Evet (hesap bağlanırsa) | Hayır | İsteğe bağlı | Hesap yönetimi |
| Kişisel bilgiler > Ad | Evet (Google adı / lig takma adı) | Hayır | İsteğe bağlı | Uygulama işlevselliği, hesap yönetimi |
| Kişisel bilgiler > Kullanıcı kimlikleri | Evet (Firebase uid; analiz izni verildiyse çökme raporlarına da eklenir) | Hayır | İsteğe bağlı (hesap) | Uygulama işlevselliği, hesap yönetimi, sahtekârlığı önleme (davet), analiz (çökme raporu) |
| Finansal bilgiler > Satın alma geçmişi | Evet | Hayır | İsteğe bağlı | Uygulama işlevselliği (Premium) |
| Mesajlar > Diğer uygulama içi mesajlar | Evet: yapay zekâ sohbeti, Ses Koçu, Mülakat Provası ve yazma değerlendirmesi metinleri (yazılan ya da konuşma tanımanın metne çevirdiği cevaplar, ses değil); Mülakat Provası metni ve analizi hesap silinene kadar saklanır | Evet (Anthropic, hizmet sağlayıcı)* | İsteğe bağlı | Uygulama işlevselliği |
| Ses > Ses kayıtları | Hayır (konuşma tanıma cihazda; ses Dilmaç sunucusuna ve Anthropic'e gitmez, yalnızca metin gider) | – | – | – |
| Uygulama etkinliği > Uygulama etkileşimleri | Evet (izinle) | Hayır | İsteğe bağlı | Analiz |
| Uygulama bilgileri ve performansı > Kilitlenme günlükleri | **Evet** (Firebase Crashlytics, yalnızca analiz izniyle; kapalı başlar) | Hayır | İsteğe bağlı | Analiz (uygulama kararlılığı) |
| Uygulama bilgileri ve performansı > Teşhis | **Evet** (Crashlytics hata raporlarındaki cihaz modeli, Android sürümü, bellek/disk durumu, yığın izi; aynı izinle) | Hayır | İsteğe bağlı | Analiz (uygulama kararlılığı) |
| Cihaz veya diğer kimlikler | Evet (Firebase kurulum/analiz kimliği, Crashlytics kurulum kimliği, rastgele kurulum kimliği özeti) | Hayır | Analiz isteğe bağlı | Analiz, sahtekârlığı önleme, uygulama işlevselliği |
| Kişiler (rehber) | Evet, **yalnızca geçici işleme** ("processed ephemerally"): numaraların tuzlu SHA-256 özetleri tek tek sorgu için gönderilir, saklanmaz; adlar ve ham numaralar gönderilmez | Hayır | İsteğe bağlı | Uygulama işlevselliği (arkadaş bulma) |
| Fotoğraflar ve videolar > Fotoğraflar | Evet (yalnızca kullanıcı profil fotoğrafı eklerse; küçültülmüş JPEG, hesaba kaydedilir) | Hayır | İsteğe bağlı | Uygulama işlevselliği (profil) |
| Kişisel bilgiler > Telefon numarası | Evet, yalnızca "Telefon numaramla bulunabilirim" açıksa ve yalnızca tuzlu SHA-256 özeti | Hayır | İsteğe bağlı | Uygulama işlevselliği (arkadaş bulma) |
| Konum | Hayır | – | – | – |

\* Play'in tanımına göre veriyi sizin adınıza işleyen hizmet sağlayıcıya aktarmak
"paylaşım" sayılmaz; Anthropic'i hizmet sağlayıcı olarak bildirip "Paylaşılıyor: Hayır"
seçmek de doğrudur. Emin değilsen "Evet" seçmek daha güvenli.

## Rehber izni (READ_CONTACTS) ve Play Kullanıcı Verileri politikası

- İzin yalnızca Arkadaşlar > **Rehberden bul** düğmesine basınca istenir (çalışma anında); öncesinde uygulama
  içinde ne yapılacağı açıklanır (belirgin açıklama, "prominent disclosure"). Reddedilirse kodla ekleme çalışır.
- Rehber verisi cihazdan çıkmaz; adlar ve ham numaralar hiçbir sunucuya gönderilmez. Sunucuya yalnızca numaraların
  uygulamaya özgü önekli SHA-256 özetleri, tek tek belge okuması olarak gider; eşleşmeyenler saklanmaz.
- Gizlilik politikasında 3.10 bölümü bu akışı anlatır. Play Console'da izin beyanı istenirse amaç: "Kullanıcının
  rehberindeki, uygulamayı kullanan ve bulunmayı kabul etmiş kişileri arkadaş olarak bulmak."
- Telefon numarası (özet) yalnızca kullanıcı "Telefon numaramla bulunabilirim" seçeneğini açarsa yazılır; numara
  telefonla girişte doğrulanmış olmalıdır (kurallar bunu denetler).

## Crashlytics (çökme ve hata raporları)

- Kod: `lib/services/growth/crash_reporting.dart`. Yalnızca `prod` derlemede ve yalnızca kullanıcı analiz
  iznine "İzin ver" dediyse açılır (`AndroidManifest.xml` ve `Info.plist`'te
  `firebase_crashlytics_collection_enabled` / `FirebaseCrashlyticsCollectionEnabled` = false ile kapalı başlar).
  İzin metni (`consent_sheet.dart`) çökme raporlarını ve hesap kimliğini açıkça söyler.
- Gönderilen: Flutter ve platform hataları (fatal), satın alma / eşitleme / hesap işlemlerindeki
  hatalar (non-fatal, sabit bir `reason` anahtarıyla; kullanıcı metni yok), cihaz teşhis bilgisi,
  giriş yapılmışsa yalnızca Firebase uid (`setUserIdentifier`). Ad, e-posta, yazılan metin, ses yok.
- İzin geri alınınca toplama kapanır ve gönderilmemiş raporlar silinir (`deleteUnsentReports`).
- Formda: "Kilitlenme günlükleri" ve "Teşhis" = toplanıyor, paylaşılmıyor, isteğe bağlı, amaç "Analiz".
  "Veriler aktarım sırasında şifreleniyor" yanıtı değişmez.
