# Dilbaz Gizlilik Politikası ve KVKK Aydınlatma Metni (TASLAK)

> **Taslak.** Yayından önce köşeli parantezli alanları doldur ve bir hukukçuya
> kontrol ettir. Metin uygulamanın bugünkü davranışına göre yazıldı
> (bkz. `docs/analitik.md`, `docs/firebase.md`, `docs/abonelik.md`); yeni bir veri
> akışı eklendiğinde güncellenmelidir.

Son güncelleme: [GG.AA.YYYY]

## 1. Veri sorumlusu

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında veri sorumlusu:
**[Ad Soyad / Şirket unvanı]**, [adres], e-posta: **[destek@alanadi]**
("Dilbaz", "biz").

Dilbaz, Türkçe konuşanlara İngilizce öğreten bir mobil uygulamadır. Bu metin
uygulamayı kullanırken hangi verilerin işlendiğini, neden işlendiğini ve
haklarını açıklar.

## 2. Kısaca

- Hesap açmadan kullanabilirsin; ilerlemen **cihazında** tutulur.
- Reklam yok; verilerini satmayız, reklam için kullanmayız.
- Kullanım istatistikleri **yalnızca izin verirsen** toplanır ve istediğin an kapatılabilir.
- Yazdıkların ve ses kayıtların bizim sunucularımızda saklanmaz.

## 3. Hangi verileri, neden işliyoruz?

### 3.1 Yalnızca cihazında kalan veriler

İlerleme (tamamlanan dersler, XP, seri, günlük hedef), sınav sonuçları, kelime
kartları ve notlar, günlük (diary) yazıları, hata istatistikleri, bildirim ve
uygulama ayarları, analiz izni kararın, rastgele üretilen bir kurulum kimliği.
Bu veriler telefonunun uygulama alanında saklanır; uygulamayı silince silinir.
**Hukuki sebep:** sözleşmenin ifası (hizmeti sunmak), KVKK m. 5/2-c.

### 3.2 Mikrofon ve konuşma tanıma

Konuşma ve telaffuz alıştırmalarında mikrofon yalnızca sen düğmeye bastığında
açılır. Ses, telefonundaki konuşma tanıma hizmetine (Android'de genellikle
Google) iletilir ve metne çevrilir; Dilbaz ses kaydı saklamaz ve sunucularına
göndermez. Sesli okuma (metinden sese) cihazda yapılır. İzni Android
ayarlarından istediğin zaman geri alabilirsin.

### 3.3 Hesap ve bulut yedekleme (isteğe bağlı)

Hesap bağlarsan (Google ile ya da e-posta ile) Firebase Authentication
(Google LLC) kullanılır: kullanıcı kimliği (uid), e-posta, ad (Google'dan
geliyorsa) işlenir. Bulut yedekleme açıksa ilerleme özetin (3.1'deki
ilerleme, XP, görünen adın) Cloud Firestore'da saklanır; böylece başka bir
cihazda devam edebilirsin. Misafir (anonim) hesap da oluşturulabilir.
**Hukuki sebep:** sözleşmenin ifası, m. 5/2-c.

### 3.4 Haftalık lig

Lige katılırsan takma adın, seçtiğin simge ve haftalık XP'n aynı gruptaki
(en fazla 15 kişi) diğer kullanıcılara gösterilir. Gerçek adını takma ad olarak
kullanmak zorunda değilsin.

### 3.5 Yapay zekâ sohbet partneri (Premium)

Canlı sohbette yazdığın mesajlar ve seçtiğin senaryo, cevap üretmek için
sunucumuz (Google Cloud Functions, Avrupa bölgesi) üzerinden Anthropic PBC'nin
Claude yapay zekâ hizmetine gönderilir. Mesajlar Dilbaz tarafından
saklanmaz; yalnızca günlük kullanım sayısı (kota için) tutulur. Anthropic,
API üzerinden gelen verileri kendi politikası gereği model eğitiminde
kullanmaz ve sınırlı bir süre güvenlik amacıyla saklayabilir. Sohbete kişisel
bilgilerini (TC kimlik no, adres, sağlık bilgisi vb.) yazmamanı öneririz.
**Hukuki sebep:** sözleşmenin ifası, m. 5/2-c; yurt dışına aktarım için 6. bölüm.

### 3.6 Satın almalar

Premium aboneliği Google Play üzerinden satılır. Ödeme bilgilerin (kart vb.)
Google tarafından işlenir; biz görmeyiz. Aboneliği doğrulamak için Google
Play'in verdiği satın alma belirteci (token), ürün kimliği ve abonelik bitiş
tarihi işlenir; belirtecin yalnızca özeti (hash) ve Premium durumu
(`entitlements`) saklanır. **Hukuki sebep:** sözleşmenin ifası (m. 5/2-c) ve
hukuki yükümlülük (m. 5/2-ç, vergi/muhasebe kayıtları Google Play tarafından tutulur).

### 3.7 Davet programı

Davet kodun hesabınla ilişkilendirilir. Bir kod kullanıldığında: kodu kullanan
ve davet eden hesapların kimlikleri, tarih, kurulum kimliğinin özeti (aynı
cihazda tekrar kullanımı önlemek için) ve verilen Premium günleri saklanır.
Davet ettiğin kişinin adı ya da e-postası sana gösterilmez.
**Hukuki sebep:** sözleşmenin ifası (m. 5/2-c) ve kötüye kullanımı önlemede
meşru menfaat (m. 5/2-f).

### 3.8 Kullanım istatistikleri (yalnızca izinle)

İzin verirsen Google Firebase Analytics ile anonim kullanım olayları
toplanır: hangi ekranların açıldığı, ders başlatma/bitirme, doğruluk yüzdesi,
seçilen kurs, Premium ekranının görülmesi ve satın alma adımları, uygulamaya
geri dönüş aralığı. Firebase bunlara cihazına özel rastgele bir analiz
kimliği, cihaz modeli, işletim sistemi sürümü, dil ve yaklaşık ülke bilgisi
ekler. **Gönderilmeyenler:** adın, e-postan, kullanıcı kimliğin, yazdıkların,
ses kayıtların, davet kodların, kesin konumun, reklam kimliğin.
Veriler reklam ya da profil çıkarma için kullanılmaz; saklama süresi 2 aydır.
**Hukuki sebep:** açık rıza (m. 5/1). Rızanı Profil > Gizlilik'ten istediğin an
geri alabilirsin; geri aldığında toplama durur ve cihazdaki analiz kimliği silinir.

### 3.9 Uygulama yapılandırması (Remote Config)

Uygulama, ayarları (ör. hangi Premium ekranı düzeninin gösterileceği)
Firebase Remote Config'ten okur. Bunun için Firebase kurulum kimliği
işlenir; kişisel veri gönderilmez. **Hukuki sebep:** meşru menfaat (m. 5/2-f).

## 4. Kimlerle paylaşıyoruz?

Yalnızca hizmeti sunmak için gerekli hizmet sağlayıcılarla (veri işleyen):

| Alıcı | Ne için | Konum |
| --- | --- | --- |
| Google LLC / Google Ireland (Firebase Auth, Firestore, Cloud Functions, Analytics, Remote Config) | Hesap, yedekleme, sunucu, izinli istatistik | AB (europe-west1) ve ABD |
| Google Play | Abonelik satışı ve doğrulama | Küresel |
| Anthropic PBC | Yapay zekâ sohbet cevapları (Premium) | ABD |

Yasal zorunluluk hâlinde yetkili kamu kurumlarıyla paylaşılabilir. Verilerini
satmayız.

## 5. Saklama süreleri

- Cihazdaki veriler: uygulamayı silene ya da Profil'den sıfırlayana kadar.
- Hesap ve bulut yedeği: hesabını silene kadar; silme talebinden sonra en geç 30 gün.
- Satın alma doğrulama kayıtları: abonelik süresince ve sonrasında yasal süre boyunca.
- Davet kayıtları: kötüye kullanımı önlemek için en fazla 2 yıl.
- Analiz verileri: 2 ay (Firebase saklama ayarı).
- Sunucu günlükleri (hata kayıtları): en fazla 30 gün.

## 6. Yurt dışına aktarım

Hizmet sağlayıcılarımızın bir kısmı (Google, Anthropic) verileri Türkiye dışında
(AB ve ABD) işler. Bu aktarımlar KVKK m. 9 kapsamında, Kurul'un ilan ettiği
standart sözleşmeler ve/veya aktarım anındaki açık rızan ile yapılır.
[Hukukçu kontrolü: standart sözleşmenin imzalanıp Kurum'a bildirildiğini doğrula.]

## 7. Çocuklar

Dilbaz 13 yaş ve üzeri kullanıcılar içindir. 13 yaş altındaki çocukların
uygulamayı bir ebeveyn gözetiminde, hesap bağlamadan kullanmasını öneririz.
Ebeveynsen ve çocuğuna ait veri işlendiğini düşünüyorsan bize yaz; sileriz.

## 8. Güvenlik

Sunucu ile iletişim şifrelidir (HTTPS/TLS). Firestore'da her kullanıcı yalnızca
kendi verisini okuyabilir; Premium ve davet kayıtlarını yalnızca sunucu
yazabilir. Hiçbir yöntem %100 güvenli değildir; bir ihlal olursa KVKK'ya uygun
şekilde Kurul'a ve sana bildiririz.

## 9. Hakların (KVKK m. 11)

Kişisel verilerinin işlenip işlenmediğini öğrenme, bilgi isteme, amacını
öğrenme, aktarıldığı kişileri bilme, düzeltilmesini, silinmesini ya da yok
edilmesini isteme, bunların aktarılan kişilere bildirilmesini isteme, otomatik
analiz sonucu aleyhine bir sonuca itiraz etme ve zarara uğrarsan tazminat
isteme haklarına sahipsin.

Başvurunu **[destek@alanadi]** adresine, kayıtlı e-posta adresinden ya da
kimliğini doğrulayan bir yolla gönderebilirsin; en geç 30 gün içinde
ücretsiz yanıtlarız. Yanıtımızdan memnun kalmazsan Kişisel Verileri Koruma
Kurulu'na şikâyette bulunabilirsin.

Uygulama içinden:

- Kullanım istatistiği izni: Profil > Gizlilik.
- İlerlemeyi sıfırlama: Profil > İlerlemeyi sıfırla.
- Hesaptan çıkış: Profil > Hesap. [Hesap silme özelliği eklendiğinde: Profil > Hesap > Hesabı sil.]
- Abonelik iptali: Google Play > Ödemeler ve abonelikler > Abonelikler.

## 10. Değişiklikler

Bu metni güncellediğimizde uygulamada ve bu sayfada duyururuz. Önemli
değişikliklerde (ör. yeni bir veri türü) yeniden izin isteriz.

## 11. İletişim

[Ad Soyad / Şirket], [adres], **[destek@alanadi]**
