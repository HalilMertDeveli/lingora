# Okullar ve kurumlar: sınıf ve lisans (Spark planı)

Okullar, dershaneler ve kurumlar öğrencileri için **lisans kodu** satın alır. Kodu giren öğrenciye kurumun
sözleşme süresi boyunca Premium açılır. Öğretmen uygulamada sınıf açar ve sınıf kodunu paylaşır. Öğrenci
bu kodla sınıfa katılır, öğretmen de öğrencilerin ilerleme özetini görür.

Bu akış **Cloud Functions olmadan**, yalnızca Firestore kurallarıyla çalışır. Uygulama Firebase'in ücretsiz
Spark planında olduğu için böyle tasarlandı. Kurallar `firestore.rules` dosyasındaki "Kurum lisansı ve
sınıflar" bölümünde, kod `lib/kurum/` klasöründe.

> `docs/kurumsal.md`, PR #15 ile gelen eski ve **callable tabanlı** kurumsal modeli anlatır: kurumlar, web
> paneli, ödevler. O model Blaze planı ve deploy edilmiş fonksiyonlar ister, bu yüzden Spark planında
> çalışmaz. Bu belge onun yerine bugün çalışan yolu anlatır.

---

## 1. Mevcut altyapının durumu (2026-11-17 incelemesi)

| Parça | Durum |
|---|---|
| `lib/org/*`: Profil'deki "Kurum koduyla katıl" kartı ve Öğren sekmesindeki "Ödevlerim" kartı | `orgJoin`, `orgMine` ve `orgLeave` callable'larını çağırır. Fonksiyonlar deploy edilmediği için katılma her zaman "Şu an olmadı" hatasıyla bitiyordu. **Profil'deki kart yeni `KurumSection` ile değiştirildi.** "Ödevlerim" kartı, `orgMine` başarısız olunca zaten kendini gizliyor. |
| `lib/admin/*`: web paneli (kurum, kişiler, sınıflar, ödev, CSV) | Bütünüyle `org*` callable'larına dayanıyor. Spark'ta açılır ama veri gelmez. Dokunulmadı; Blaze'e geçilirse kullanılabilir. |
| `functions/src/orgs*.ts`: koltuk sayma, `entitlements/{uid}` içine kurum Premium'u yazma | Kod ve testler hazır, ama deploy edilmediği için Spark'ta etkisiz. |
| `lib/screens/invite_screen.dart`: arkadaş daveti | `referral` callable'ı. Kurumla ilgisi yok, aynı Spark sınırına takılıyor. Dokunulmadı. |
| `lib/services/billing/entitlement_backend.dart` | `entitlements/{uid}` belgesini yalnızca sunucu yazabiliyor. Spark'ta kurum Premium'u buraya yazılamıyor. Bu yüzden lisans `licenses/{uid}` belgesinde tutuluyor ve `premiumProvider` onu da hesaba katıyor. |

**Eksik olanlar ve bu çalışmayla eklenenler:**
- Fonksiyonsuz lisans etkinleştirme.
- Öğretmenin uygulama içinden sınıf açması.
- Öğrencinin kodla katılması.
- Öğretmenin seri, ünite, haftalık XP ve en sık hata türlerini görmesi.
- Operatörün kod üretme betiği.

## 2. Akış

**Öğretmen**
1. Kurumdan aldığı **öğretmen lisans kodunu** girer: Profil → "Okul ve kurum" → "Lisans kodu gir". Hem Premium
   açılır hem de "Öğretmen paneli" görünür.
2. "Öğretmen paneli" → "Sınıf aç" ile sınıf adını (ör. "8-A İngilizce") ve öğrencilerin göreceği adını yazar.
   Uygulama 8 karakterlik bir **sınıf kodu** üretir (ör. `K7PM2XQA`). Öğretmen kodu kopyalar ya da paylaşır.
3. Öğrenciler katıldıktan sonra **"Yeni öğrenci katılabilir"** anahtarını kapatır. Kod başkasına geçse bile
   kimse sınıfa giremez.
4. Sınıf ekranında her öğrenci için şunları görür:
   - 🔥 seri,
   - tamamlanan ünite ve ders sayısı,
   - bu haftanın XP'si,
   - en sık 3 hata türü.

   Ayrıca sınıfın toplam haftalık XP'si ve "sınıfın en sık hataları" (her hata türünde kaç öğrenci var)
   gösterilir.
5. Öğrenciyi sınıftan çıkarabilir ya da sınıfı silebilir. Sınıf silinince öğrencilerin o sınıftaki özetleri de
   silinir.

**Öğrenci**
1. Kurumdan aldığı **öğrenci lisans kodunu** girer ve Premium açılır. Lisans için hesap gerekir: misafir
   girişle kod girilemez, çünkü telefon kaybolunca koltuk da kaybolurdu.
2. Profil → "Sınıf koduyla katıl" bölümünde sınıf kodunu ve öğretmeninin göreceği adı yazar. Ad alanı yalnızca
   ilk adla doldurulur.
3. Uygulama, ilerleme değiştikçe özetini birkaç saniye sonra katıldığı sınıflara yazar.
4. Sınıfa dokunup "Sınıftan ayrıl" diyebilir. Öğretmen o anda erişimi kaybeder.

Sınıf açmak **öğretmen lisansı** ister, sınıfa katılmak ise lisans istemez. Böylece okul isterse yalnızca
öğretmen koltuğu alır: öğrenciler ücretsiz sürümle sınıfa katılır, öğretmen ilerlemelerini yine görür. Öğrenci
koltuğu ise öğrenciye Premium'u açar.

## 3. Lisansın güvenliği (Cloud Function olmadan)

| Koleksiyon | Kim yazar | Kural |
|---|---|---|
| `licenseCodes/{kod}` `{org, role, expiresAt, batch, claimedBy, claimedAt}` | Yalnızca operatör (Admin SDK) oluşturur | Uygulama kodu **id ile okuyabilir, listeleyemez**. Tek değişiklik "sahiplenme"dir: `claimedBy` boşsa ve kodun süresi dolmamışsa, aynı toplu yazmada `licenses/{uid}` bu kodu gösteriyorsa ve kullanıcının hâlihazırda etkin bir lisansı yoksa `claimedBy = uid` yazılabilir. |
| `licenses/{uid}` `{code, org, role, expiresAt, claimedAt}` | Kullanıcının kendisi | `org`, `role` ve `expiresAt` alanları, kullanıcının sahiplendiği koddan **birebir kopyalanmak zorundadır**. Etkin bir lisans başka bir kodla değiştirilemez ve silinemez. |
| `classes/{sınıfKodu}` `{ownerUid, name, teacherName, org, open, createdAt}` | Öğretmen | Yalnızca etkin bir **öğretmen** lisansı olan ve kodu hâlâ kendisine bağlı olan kullanıcı oluşturabilir. Listeleme yalnızca kendi sınıfları için açıktır. |
| `classes/{kod}/members/{uid}` `{name, streak, lessonsDone, unitsDone, weekXp, week, topErrors, joinedAt, updatedAt}` | Öğrencinin kendisi | Yalnızca bu alanlar yazılabilir. E-posta, telefon ya da başka bir alan kuralca reddedilir. Belgeyi yalnızca öğrencinin kendisi ve sınıfın öğretmeni okur. Kapalı sınıfa yeni kayıt yapılamaz. |
| `classLinks/{uid}` `{codes, updatedAt}` | Kullanıcının kendisi | En fazla 5 sınıf. |

Bu tasarımla sağlananlar:
- Bir kod **tek kullanımlıktır**.
- Rol (öğrenci ya da öğretmen), kurum adı ve bitiş tarihi uydurulamaz.
- Bir kişi aynı anda ikinci bir koltuğu harcayamaz.
- Süresi dolmuş kod etkinleştirilemez.
- Sınıfı yalnızca gerçek öğretmen koltuğu olan kişi açar.
- Öğretmen başka sınıfların verisini göremez.

**Bilinen sınırlar (dürüst not):**
- **Premium kontrolü istemcide yapılır.** Mağaza aboneliğinde de durum aynıdır: değiştirilmiş bir APK
  Premium'u kendi başına açabilir. Kurallar yalnızca sunucu tarafındaki koltuk sayısını korur.
- **Öğrenci özeti öğrencinin kendi uygulaması tarafından yazılır.** Kurallar değer aralıklarını ve alan
  listesini denetler, ama bilerek sahte sayı yazan bir öğrenciyi engelleyemez. Bunu ancak bir Cloud Function
  özeti `users/{uid}` ilerlemesinden hesaplayarak çözebilir.
- **Kod tahmini:** 12 karakter ve 32 harflik alfabe, yaklaşık 60 bit eder. Listeleme kapalı olduğu için
  kodlar tek tek tahmin edilmek zorundadır, bu da pratikte mümkün değildir. Sınıf kodu 8 karakterdir (yaklaşık
  40 bit). Tahmin edilse bile yalnızca *katılmaya* yarar, kimsenin verisini göstermez; ayrıca öğretmen
  katılımı kapatabilir.
- **Öğretmen başına sınıf sayısı** kuralla sınırlanamaz, çünkü kurallar belge sayamaz.
- **Çıkarılan öğrenci** sınıf açıkken kodla yeniden katılabilir. Öğretmen katılımı kapatarak bunu önler.
- **Koltuk devri** (mezun olan ya da ayrılan öğrencinin koltuğunun başkasına verilmesi): operatör
  `release` komutunu çalıştırır. Uygulama kodun artık kullanıcıya ait olmadığını görür ve Premium'u kapatır.
- Blaze planına geçilirse önerilen sertleştirme: lisans sahiplenmeyi bir callable'a taşımak,
  `entitlements/{uid}` belgesine `source: "org"` yazmak ve özeti sunucuda hesaplamak.

## 4. Kod üretme ve satış süreci

### Satış
1. **Teklif:** kurum adı, öğrenci ve öğretmen koltuk sayısı, süre (genellikle eğitim yılı sonu).
2. **Sözleşme:** fiyat, süre, aşağıdaki KVKK veri işleme eki ve okul için aydınlatma metni örneği.
3. **E-fatura ya da e-arşiv fatura** (KDV %20). Ödeme havale veya EFT ile, peşin yapılır. Google Play ve App
   Store dışında satılır. Uygulamada kurumsal fiyat ya da satın alma bağlantısı **gösterilmez**; yalnızca kod
   girişi vardır. Yayından önce mağazaların güncel ödeme politikalarını yeniden kontrol edin.
4. Ödeme gelince kodlar üretilir ve CSV dosyası kurum yetkilisine **şifreli bir kanaldan** gönderilir (ör.
   parolalı ZIP; parola ayrı bir kanaldan iletilir). Kodları öğrencilere okul dağıtır.
5. **Yenileme:** bitişten 30 gün önce kuruma hatırlatma gönderilir (şimdilik elle). Ödeme gelince `extend`
   komutu tüm partiyi ve etkin lisansları uzatır; öğrencilerin yeniden kod girmesi gerekmez.

### Kod üretme (operatörün bilgisayarında)
Betik: `functions/scripts/license_codes.mjs`. Admin SDK ile çalışır, Cloud Functions gerekmez.
`--project` verilmezse yalnızca emülatöre yazar, gerçek projeye kazara yazmayı engeller.

```bash
cd functions && npm ci
# Önce emülatörde deneyin:
firebase emulators:exec --only firestore --project demo-lingora \
  "node scripts/license_codes.mjs create --org \"Deneme Ortaokulu\" --seats 30 --teachers 2 --until 2027-06-30 --out kodlar.csv"
```

Gerçek proje için Firebase konsolundan (Proje ayarları → Hizmet hesapları) bir anahtar indirin. Anahtar
**repoya girmez** ve güvenli bir yerde saklanır.

```bash
GOOGLE_APPLICATION_CREDENTIALS=~/anahtarlar/dilbaz-admin.json \
  node scripts/license_codes.mjs create --project <proje-id> --org "Örnek Ortaokulu" \
  --seats 120 --teachers 4 --until 2027-06-30 --batch ornek-2026 --out ornek-2026.csv
node scripts/license_codes.mjs status  --project <proje-id> --batch ornek-2026      # kaç koltuk kullanıldı
node scripts/license_codes.mjs release --project <proje-id> --code ABCD-EFGH-JKLM   # koltuğu boşalt
node scripts/license_codes.mjs extend  --project <proje-id> --batch ornek-2026 --until 2028-06-30
```

CSV dosyası Excel'de açılır ve şu sütunları içerir: Kod, Rol (Öğretmen/Öğrenci), Kurum, Bitiş. Bitiş,
verilen günün Türkiye saatiyle 23.59'udur.

## 5. Önerilen fiyatlandırma (KDV hariç, yıllık)

Bireysel Premium yıllık 599,99 TL'dir (`docs/gelir-plani.md`). Okul fiyatı bunun kabaca %40'ı olarak
önerilir. Okul, toplu ve peşin ödediği, dağıtımı da kendisi yaptığı için bu indirim makuldür.

| Öğrenci koltuğu | Öğrenci başı / yıl | Örnek |
|---|---|---|
| **En az 20** (20–99) | 250 TL | 30 kişilik bir sınıf: 7.500 TL |
| 100–499 | 200 TL | 250 öğrencili ortaokul: 50.000 TL |
| 500+ | 175 TL (görüşmeye açık) | Okul zinciri, dershane ağı |

- **En az sipariş: 20 öğrenci koltuğu.** Daha küçük gruplar bireysel ya da aile planına yönlendirilir.
- **Öğretmen koltuğu:** her 30 öğrenci koltuğuna 1 öğretmen koltuğu ücretsizdir. Ek öğretmen koltuğu
  öğrenci fiyatından satılır.
- **Ücretsiz pilot:** 1 öğretmen ve 20 öğrenci, 30 gün. Kodlar `--until` ile 30 gün sonrasına üretilir.
- **Eğitim yılı lisansı:** Eylül–Haziran dönemi için tam yıllık fiyat uygulanır; yaz dönemi hediye edilir
  (bitiş 31 Ağustos'a da çekilebilir).
- Şirketler için (otel, turizm) `docs/kurumsal.md` tablosu geçerlidir: en az 10 koltuk, kişi başı 600, 450
  ya da 350 TL. Kod üretimi aynıdır; çalışanlara `--teachers 0` ile öğrenci rolü verilir, eğitim sorumlusuna
  da öğretmen koltuğu verilir.
- Yıl içinde koltuk eklemek kalan süreye oranlanır: yeni bir parti aynı `--until` ile üretilir.

## 6. KVKK ve gizlilik notu

Okul ya da kurum **veri sorumlusu**, Çenebaz ise öğretmene sınıf özeti göstermesi bakımından **veri
işleyen** sıfatındadır. Bu bir hukuki görüş değildir: sözleşme öncesinde bir hukuk danışmanıyla teyit edin.

**Öğretmenin gördüğü ve göremediği**

| Öğretmen görür | Öğretmen görmez |
|---|---|
| Öğrencinin sınıf için yazdığı ad (ilk ad ya da takma ad) | E-posta, telefon, hesap adı, profil fotoğrafı |
| Seri (gün) | Günlük (diary), kişisel notlar, kelime listesi |
| Tamamlanan ünite ve ders sayısı | Yapay zekâ konuşmalarının tamamı, yazılan cevapların metni |
| Bu haftanın XP'si | Konum, cihaz ve reklam kimliği |
| En sık 3 hata **türü** (ör. "Zaman uyumu"; cevabın kendisi değil) | Başka sınıflardaki ya da başka okullardaki öğrenciler |
| Ses Koçu özeti: konuşma sayısı, tahmini dakika, son karne özeti, son 3 düzeltilen cümle, zorlandığı kelimeler (`classes/{kod}/speaking/{uid}`, yalnızca sunucu yazar; bkz. `docs/kurumsal-satis.md`) | |

Teknik güvenceler:
- Özet belgesi kuralca yalnızca yukarıdaki alanları kabul eder. E-posta veya telefon alanı yazılmaya
  çalışılırsa istek reddedilir (`functions/test/kurum_rules.test.ts`).
- Öğrencinin tam ilerlemesi (`users/{uid}`) yalnızca öğrencinin kendisine açıktır.
- Belge kimliği, Firebase'in rastgele kullanıcı kimliğidir (uid). Kişiyi doğrudan tanımlamaz ve ekranda
  gösterilmez.

**Çocuklar (LGS ve 18 yaş altı)**
- Ad alanı yalnızca ilk adla doldurulur, öğrenci isterse takma ad yazabilir. Okul öğrencilere "tam adını
  yazma" diye yönlendirmelidir.
- 18 yaş altı öğrencilerde, veli bilgilendirmesi ve gerektiğinde açık rıza okulun sorumluluğundadır.
  Sözleşmeye bir **aydınlatma metni örneği** eklenir. Örnek cümle: "Çenebaz uygulamasında çocuğunuzun seri,
  tamamladığı ünite, haftalık XP ve en sık hata türleri, eğitimin takibi amacıyla yalnızca İngilizce
  öğretmeniyle paylaşılır. Notları, günlüğü, yazışmaları ve iletişim bilgileri paylaşılmaz."
- Uygulamada reklam yoktur. Sınıf özelliğinde öğrenciler birbirini göremez ve aralarında mesajlaşma yoktur.
- Lisans etkinleştirmek için hesap gerekir; hesap açma sırasında e-posta ya da telefon bilgisi okulla
  paylaşılmaz.

**Saklama ve silme**
- Öğrenci "Sınıftan ayrıl" dediğinde, öğretmen öğrenciyi çıkardığında ya da sınıfı sildiğinde özet hemen
  silinir.
- Önerilen saklama süresi: sözleşme bitişinden sonra 30 gün içinde sınıflar silinir. Bunu şimdilik operatör
  elle yapar; otomatik temizlik için Cloud Function ya da zamanlanmış bir görev gerekir.
- Lisans belgesi (`licenses/{uid}`) yalnızca kurum adını, rolü ve bitiş tarihini içerir. Kurum, hangi kodun
  hangi uid'e bağlandığını göremez; bunu yalnızca operatör görür.

**Yurt dışına aktarım:** Veriler Firebase (Google Cloud) üzerinde, projenin Firestore konumunda tutulur.
Sözleşmede bu konum ve alt işleyen (Google) belirtilir. KVKK md. 9 kapsamındaki yurt dışı aktarım şartları
(ör. standart sözleşme ve Kurul'a bildirim) hukuk danışmanıyla kontrol edilmelidir.

## 7. Teknik özet

- **Uygulama:**
  - `lib/kurum/kurum.dart`: model, `FirestoreKurumApi`, sağlayıcılar ve `classReportSyncProvider`.
    `main.dart` bu sağlayıcıyı dinler; özet değiştiğinde 5 saniye sonra yazılır.
  - `lib/kurum/kurum_widgets.dart`: Profil'deki "Okul ve kurum" bölümü ve kod diyalogları.
  - `lib/kurum/teacher_screen.dart`: öğretmen paneli ve sınıf ekranı.
  - `premiumProvider` (`lib/services/billing/premium.dart`): etkin bir kurum lisansında `true` döner.
- **Kurallar:** `firestore.rules` dosyasındaki "Kurum lisansı ve sınıflar" bölümü.
  **Gerçek projeye henüz yayınlanmadı.** Yayınlamak sahibin onayını gerektirir:
  `firebase deploy --only firestore:rules --project <proje-id>`.
- **Testler:**
  - `functions/test/kurum_rules.test.ts`: emülatörde 15 kural testi (tek kullanımlık kod, uydurma lisans,
    ikinci koltuk, öğretmen yetkisi, gizlilik alanları, kapalı sınıf).
  - `test/kurum_test.dart`: kod biçimi, özet hesabı, sahte Firestore ile akışlar ve ekranlar.
- **İndeks:** `classes` üzerinde `ownerUid ==` ve `licenseCodes` üzerinde `batch ==` sorguları tek alanlıdır,
  Firestore'un otomatik indeksleri yeter.
