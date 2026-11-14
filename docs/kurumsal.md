# Dilbaz Kurumsal

Oteller, turizm şirketleri, işletmeler ve okullar için Dilbaz. Kurum, çalışanları ya da öğrencileri
için koltuk (lisans) satın alır; kişiler uygulamada **kurum kodu** ile katılır ve plan süresince Premium
kullanır. Yönetici ve öğretmenler web panelinden ilerlemeyi izler, sınıf kurar ve ödev verir.

Bu belge: satış teklifi, kurulum adımları, KVKK notları, faturalama ve teknik ayrıntılar.

---

## 1. Satış teklifi

### Otel / turizm / şirket ne alır?

- **Her çalışana Dilbaz Premium** (plan bitişine kadar): yapay zekâ konuşma partneri,
  sınırsız deneme, ayrıntılı hata analizi.
- **Mesleğe özel içerik:** Turizm İngilizcesi (resepsiyon, restoran, rehberlik) ve İş Görüşmesi İngilizcesi
  paketleri; genel İngilizce A1–A2 yolu ve A1–C1 gramer yolu.
- **Web yönetim paneli:** koltuk kullanımı, kim ne kadar çalışıyor (ders, XP, seri, son aktif gün),
  "bir haftadır girmeyenler" listesi, departman bazlı gruplar (ör. Resepsiyon, Restoran, Kat hizmetleri).
- **Ödev:** departmana belirli bir dersi (ör. "Check-in", "Şikâyet karşılama") son tarihle atama ve
  tamamlanma oranını izleme.
- **CSV rapor:** Excel'de açılan, insan kaynakları ve eğitim kayıtları için hazır rapor.
- Reklam yok, can/ceza sistemi yok; çalışan istediği zaman, telefonundan, günde 5–10 dakika çalışır.

### Okul / dershane / öğretmen ne alır?

- Her öğrenciye (ve öğretmene) Premium.
- **Öğretmen modu:** sınıf (ör. 8-A) oluşturma, sınıfa özel katılım kodu, ödev verme:
  - bir ders (genel ya da mesleki yoldan),
  - bir gramer konusu (gramer yolu, A1–C1),
  - bir sınav denemesi (LGS, YDS/YÖKDİL mini deneme).
- Ödev takibi: kim tamamladı, kim gecikti; sınıf başına tamamlama çubuğu.
- Öğretmen yalnızca kendi sınıflarını görür; okul yöneticisi tüm okulu görür.

### Önerilen fiyatlar (KDV hariç, yıllık)

`docs/gelir-plani.md` ile uyumlu başlangıç fiyatları. Bireysel Premium yıllık 599,99 TL'dir; kurumsal fiyat
kişi başı bunun yaklaşık yarısıdır.

| Koltuk sayısı | Kişi başı / yıl | Örnek |
|---|---|---|
| 10–24 | 600 TL | 15 kişilik butik otel: 9.000 TL |
| 25–99 | 450 TL | 60 kişilik otel: 27.000 TL |
| 100–499 | 350 TL | 250 kişilik zincir otel: 87.500 TL |
| 500+ | 300 TL (görüşmeye açık) | Okul zinciri, büyük işletme |

- **Okul fiyatı:** öğrenci başı yıllık 250 TL ya da sınıf başı (35 öğrenciye kadar) 7.500 TL;
  öğretmenler ücretsiz ama koltuk sayılır (aşağıya bakın).
- **Ücretsiz pilot:** 10 koltuk, 30 gün. Pilot sonunda plan uzatılır ya da kendiliğinden biter.
- **Sezonluk turizm planı:** 6 aylık plan (Nisan–Ekim), yıllık fiyatın %60'ı.
- Ödeme peşin ve yıllık; koltuk artırımı yıl içinde kalan süreye oranlanarak faturalanır.

### Koltuk kuralları

- Her **üye** (çalışan/öğrenci) ve **öğretmen** bir koltuk kullanır ve plan bitişine kadar Premium alır.
- **Yönetici** koltuk kullanmaz ve Premium almaz; yalnızca paneli kullanır.
- Biri kurumdan ayrılınca ya da çıkarılınca koltuğu hemen boşalır, başkası kullanabilir.
- Plan biterse yeni katılım yapılamaz ve kurum Premium'u biter. Kişilerin kendi ilerlemesi (XP, seri,
  tamamlanan dersler) her zaman kendilerinde kalır.
- Kişinin kendi aldığı ve daha uzun süren bir Premium aboneliği varsa kurum onu kısaltmaz.

---

## 2. Kurulum (sahibin yapacakları)

### Bir kerelik hazırlık

1. Firebase projesi, Blaze planı ve `flutterfire configure` (bkz. `docs/firebase.md`, `docs/firebase-backend.md`).
   Web için de yapılandırın: `--platforms=android,ios,web`.
2. **Authentication → Sign-in method → E-posta/Şifre** sağlayıcısını açın (panel girişi için).
3. **Dilbaz yöneticisi tanımlayın** (kurum oluşturma yetkisi). İki yoldan biri:
   - Firestore konsolunda `config/lingoraAdmins` belgesi oluşturun: `{ uids: ["<sizin uid'iniz>"] }`.
     Uid'i Authentication → Users listesinden alırsınız (önce panelde bir hesap açın).
   - ya da Admin SDK ile özel claim: `admin.auth().setCustomUserClaims(uid, { isLingoraAdmin: true })`.
4. Fonksiyonları ve kuralları yayınlayın:
   ```bash
   firebase deploy --only functions,firestore:rules
   ```
5. Paneli Firebase Hosting'e yayınlayın. Ayrı bir site önerilir (ör. `lingora-panel`):
   ```bash
   firebase hosting:sites:create lingora-panel
   firebase target:apply hosting admin lingora-panel
   flutter build web -t lib/admin/main_admin.dart --dart-define=LINGORA_FIREBASE=prod -o "$PWD/build/admin"
   firebase deploy --only hosting:admin
   ```
   Panel adresi: `https://lingora-panel.web.app` (Hosting'den özel alan adı bağlanabilir, ör. `panel.lingora.app`).
6. Uygulamanın Firebase açık sürümü (`--dart-define=LINGORA_FIREBASE=prod`) mağazada olmalı; Profil'deki
   "Kurum koduyla katıl" yalnızca Firebase açıkken görünür.

### Her yeni müşteri için

1. Sözleşme ve fatura (bkz. bölüm 4); ödeme alınır.
2. Panelde Dilbaz yöneticisi olarak giriş yapın → **Yeni kurum**: ad, tür (kurum/okul), koltuk sayısı,
   plan bitişi. Panel bir **yönetici kodu** gösterir.
3. Kodu müşterinin yetkilisine iletin. Yetkili panelde e-postasıyla hesap açar, kodu ve adını girer;
   artık kurumun yöneticisidir.
4. Yönetici panelde **Sınıflar** (departman) ve **Davet kodları** oluşturur, kodları çalışanlarla paylaşır.
   Çalışan: Dilbaz uygulaması → Profil → **Kurum koduyla katıl** → kod + ad soyad.
5. Yenileme: panelde kurumun yanındaki düzenle düğmesinden plan bitişini uzatın; tüm üyelerin Premium'u
   otomatik uzar. Koltuk artırımı da aynı yerden.

### Yerelde deneme (emülatör)

```bash
cd functions && npm ci && npm run serve        # auth, firestore, functions emülatörleri
flutter run -d chrome -t lib/admin/main_admin.dart --dart-define=LINGORA_FIREBASE=emulator
```
Emülatörde Firestore'a `config/lingoraAdmins = { uids: [...] }` belgesini emülatör arayüzünden ya da
bir betikle ekleyin.

---

## 3. KVKK ve gizlilik

Dilbaz, kurumla yalnızca **öğrenme ilerlemesini** paylaşır:

| Paylaşılır | Paylaşılmaz |
|---|---|
| Kurumda görünen ad (kişinin katılırken yazdığı) | Günlük (diary) yazıları |
| Rol ve sınıf | Kişisel notlar, kendi kelime listesi |
| Tamamlanan ders sayısı, toplam XP, son 7 gün XP | Yapay zekâ konuşma içerikleri |
| Seri ve son aktif gün | Hata listeleri ve hata istatistikleri |
| Ödev durumu (tamamlandı / bekliyor / gecikti) | E-posta, telefon, cihaz bilgisi |

Teknik güvence:
- Kurum verisi istemciden doğrudan okunamaz (`firestore.rules` → "Dilbaz Kurumsal" bölümü). Panel her şeyi
  Cloud Functions üzerinden alır; rapor `functions/src/orgs.ts` içindeki `progressSummary()` beyaz listesiyle
  üretilir. Testler (`functions/test/orgs.test.ts`) günlük metninin rapora sızmadığını doğrular.
- Öğretmen yalnızca kendi sınıflarındaki öğrencileri görür.
- Kişi istediği zaman Profil → Kurumdan ayrıl ile ayrılır; kurumun ona dair görebildiği her şey o anda kesilir.

Sözleşme ve aydınlatma için:
- Kurum **veri sorumlusu**, Dilbaz **veri işleyen** sıfatındadır (çalışan/öğrenci verisinin eğitim takibi
  amacıyla işlenmesi). Sözleşmeye bir **veri işleme eki** konur: amaç (dil eğitimi takibi), kategori
  (yukarıdaki tablo), saklama (üyelik süresi + 30 gün), yurt dışına aktarım (Firebase, AB bölgesi
  `europe-west1`) ve alt işleyenler (Google Cloud).
- Kurum, çalışanlarına/velilere bir **aydınlatma metni** verir. Örnek cümle: "Dilbaz uygulamasındaki ders,
  XP, seri ve ödev durumunuz eğitim takibi amacıyla kurumumuzla paylaşılır; günlük, not ve sohbet
  içerikleriniz paylaşılmaz."
- 18 yaş altı öğrenciler için okul, veli onayını kendi süreçleriyle alır; uygulamada reklam ve üçüncü taraf
  takip yoktur.
- Silme talebi: kişi kurumdan ayrılır (kurumun erişimi hemen biter); hesabın tamamen silinmesi destek üzerinden yapılır.

---

## 4. Faturalama (mağaza dışı)

Kurumsal satışlar Google Play / App Store üzerinden **yapılmaz**:

1. Teklif → sözleşme (koltuk sayısı, süre, fiyat, veri işleme eki).
2. **E-fatura / e-arşiv fatura** kesilir (şirket bilgileriyle; KDV %20). Ödeme havale/EFT ile, peşin.
3. Ödeme gelince panelde kurum oluşturulur ya da plan uzatılır. Hak, **kurum kodu** ile verilir; uygulamada
   satın alma ekranı görünmez ve mağaza komisyonu oluşmaz.
4. Mağaza kuralları: uygulama içinde kurumsal satın alma bağlantısı ya da fiyat gösterilmez; yalnızca kod
   girişi vardır. Bu, uygulama dışında satın alınmış içeriğe erişim modelidir; yayından önce Google Play
   ve App Store'un güncel ödeme politikalarıyla yeniden kontrol edin.
5. Yenileme hatırlatması: plan bitişinden 30 gün önce müşteriye e-posta (şimdilik elle; panelde bitişe
   30 günden az kalınca tarih kırmızı görünür).

---

## 5. Teknik özet

**Veri modeli** (yalnızca Cloud Functions yazar):

```
orgs/{orgId}                    {name, type: kurum|okul, seats, seatsUsed, planExpiresAt, ...}
orgs/{orgId}/members/{uid}      {role: admin|teacher|member, displayName, classIds, seat, joinedAt}
orgs/{orgId}/classes/{classId}  {name, teacherUid}
orgs/{orgId}/assignments/{id}   {classId, kind: lesson|grammar|exam, targetId, courseId, title, dueAt}
orgCodes/{code}                 {orgId, role, classId, active, uses}
memberships/{uid}               {orgId, role}            (sahibi okuyabilir)
entitlements/{uid}              {..., source: "org", orgId, expiresAt = plan bitişi}
config/lingoraAdmins            {uids: [...]}
```

**Callable fonksiyonlar** (`functions/src/orgs_api.ts`, bölge `europe-west1`):

| Fonksiyon | Kim | Ne yapar |
|---|---|---|
| `orgCreate`, `orgUpdate` | Dilbaz yöneticisi | Kurum oluşturur (yönetici kodu döner); koltuk/plan değiştirir, üyelerin Premium'unu günceller |
| `orgList` | Herkes | Dilbaz yöneticisine tüm kurumlar, kurum yöneticisi/öğretmene kendi kurumu |
| `orgReport` | Yönetici, öğretmen | Panel verisi: kurum, sınıflar, ödevler, kodlar, kişiler ve ilerleme özeti |
| `orgCreateCode`, `orgRotateCode`, `orgRevokeCode` | Yönetici; öğretmen kendi sınıfına üye kodu | Davet kodları |
| `orgRemoveMember`, `orgSetRole` | Yönetici | Kişi çıkarma, rol değiştirme (koltuk ve Premium buna göre) |
| `orgCreateClass`, `orgDeleteClass`, `orgSetClassMember` | Yönetici; öğretmen kendi sınıfı | Sınıf yönetimi |
| `orgCreateAssignment`, `orgDeleteAssignment` | Yönetici; öğretmen kendi sınıfı | Ödev |
| `orgJoin`, `orgLeave`, `orgMine` | Uygulama kullanıcısı | Kodla katıl, ayrıl, kendi kurum ve ödevleri |

**Ödev tamamlanması** kişinin bulutla eşitlenen ilerlemesinden hesaplanır: ders → `completed[nodeId]`,
gramer → `completed["gl_<id>"]`, deneme → `examBest[examId]` (bir mini deneme bitirilmiş olmalı).
Uygulama aynı kuralı yerel ilerlemeyle uygular, bu yüzden "Ödevlerim" kartı ders biter bitmez güncellenir.
Panelde "Uygulama henüz eşitlenmedi" yazan kişinin ilerlemesi buluta hiç yedeklenmemiştir.

**Uygulama:** Profil → "Kurum" kartı (`lib/org/org_widgets.dart`), Öğren sekmesinde "Ödevlerim" kartı;
ödeve dokununca ilgili ders, gramer dersi ya da sınav ekranı açılır.

**Panel:** `lib/admin/main_admin.dart` (Flutter web). Bölümler: Genel bakış, Kişiler (arama, sınıf filtresi,
sıralanabilir tablo, rol/sınıf/çıkarma), Sınıflar, Ödevler, Davet kodları, CSV indir (`;` ayraçlı, UTF-8,
Excel uyumlu).

**Testler:** `functions/test/orgs.test.ts` (koltuk, rol, plan, gizlilik), `functions/test/orgs_rules.test.ts`
(kurallar), `test/org_test.dart` (katılım akışı, Ödevlerim), `test/admin_test.dart` (panel, CSV).

### Bilinen sınırlar / sonraki adımlar

- Bir kişi aynı anda tek kuruma bağlı olabilir.
- Bir ödev, kişi o içeriği ödevden önce bitirmişse de tamamlanmış sayılır.
- Plan bitişi yaklaşınca otomatik e-posta yok (elle takip).
- Kurum silme yok; plan bitince kurum pasif kalır.
