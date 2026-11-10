# Play Console "Veri güvenliği" formu için cevaplar

Kaynak: `gizlilik-politikasi.md`. Play Console > Uygulama içeriği > Veri güvenliği.

Genel:

- Uygulamanız gerekli kullanıcı verisi türlerinden herhangi birini topluyor veya paylaşıyor mu? **Evet**
- Toplanan tüm kullanıcı verileri aktarım sırasında şifreleniyor mu? **Evet**
- Kullanıcıların verilerinin silinmesini istemesi için bir yol sağlıyor musunuz? **Evet** (e-posta ile; hesap silme özelliği eklenince uygulama içinden)

| Veri türü | Toplanıyor | Paylaşılıyor | İsteğe bağlı mı | Amaç |
| --- | --- | --- | --- | --- |
| Kişisel bilgiler > E-posta adresi | Evet (hesap bağlanırsa) | Hayır | İsteğe bağlı | Hesap yönetimi |
| Kişisel bilgiler > Ad | Evet (Google adı / lig takma adı) | Hayır | İsteğe bağlı | Uygulama işlevselliği, hesap yönetimi |
| Kişisel bilgiler > Kullanıcı kimlikleri | Evet | Hayır | İsteğe bağlı (hesap) | Uygulama işlevselliği, hesap yönetimi, sahtekârlığı önleme (davet) |
| Finansal bilgiler > Satın alma geçmişi | Evet | Hayır | İsteğe bağlı | Uygulama işlevselliği (Premium) |
| Mesajlar > Diğer uygulama içi mesajlar | Evet (yapay zekâ sohbeti) | Evet (Anthropic, hizmet sağlayıcı)* | İsteğe bağlı | Uygulama işlevselliği |
| Ses > Ses kayıtları | Hayır (cihazın konuşma tanıma hizmeti işler, Lingora almaz) | – | – | – |
| Uygulama etkinliği > Uygulama etkileşimleri | Evet (izinle) | Hayır | İsteğe bağlı | Analiz |
| Uygulama bilgileri ve performansı > Kilitlenme günlükleri | Hayır (Crashlytics yok) | – | – | – |
| Cihaz veya diğer kimlikler | Evet (Firebase kurulum/analiz kimliği, rastgele kurulum kimliği özeti) | Hayır | Analiz isteğe bağlı | Analiz, sahtekârlığı önleme, uygulama işlevselliği |
| Konum | Hayır | – | – | – |

\* Play'in tanımına göre veriyi sizin adınıza işleyen hizmet sağlayıcıya aktarmak
"paylaşım" sayılmaz; Anthropic'i hizmet sağlayıcı olarak bildirip "Paylaşılıyor: Hayır"
seçmek de doğrudur. Emin değilsen "Evet" seçmek daha güvenli.
