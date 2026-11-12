# Giriş ve ilerleme testleri

Misafir hesabını e-posta, Google ya da telefonla bağlama ve ilerlemenin korunması iki yoldan test edilir:

1. **Otomatik:** Firebase Emulator Suite (`demo-lingora`) ve Android emülatörü ile `integration_test/auth_flows_test.dart`.
   Gerçek projeye (`dilbaz-3392e`) hiç bağlanmaz.
2. **Elle, gerçek projede:** Aşağıdaki kontrol listesi. Bunu sahip yapar; gerçek SMS, gerçek Google hesabı ve Play
   imzası ancak orada denenebilir.

## 1. Otomatik testler (emülatör)

Gerekenler: Firebase CLI (`firebase --version` ≥ 15), Java 21, çalışan bir Android emülatörü.

```bash
firebase emulators:start --only auth,firestore --project demo-lingora
```

İkinci bir terminalde:

```bash
flutter test integration_test/auth_flows_test.dart -d emulator-5554
```

Ya da tek komutla (emülatörleri açar, testten sonra kapatır):

```bash
firebase emulators:exec --only auth,firestore --project demo-lingora "flutter test integration_test/auth_flows_test.dart -d emulator-5554"
```

- Android emülatörü bilgisayardaki emülatörlere `10.0.2.2` ile ulaşır. Gerçek telefonda
  `--dart-define=LINGORA_EMULATOR_HOST=<bilgisayarın LAN IP'si>` ver ve emülatörleri `0.0.0.0`'da başlat.
- Testler başlarken emülatördeki tüm hesapları ve belgeleri siler.
- Her "cihaz" ayrı bir `FirebaseApp` (kendi oturumu ve Firestore önbelleği) ve boş depolama ile başlar. Böylece
  "başka telefondan giriş" aynı test içinde denenir.
- Premium, emülatörün yönetici REST ucu ile `entitlements/{uid}` yazılarak verilir (verifyPurchase'ın yaptığı gibi).
- SMS kodu Auth emülatörünün `GET /emulator/v1/projects/demo-lingora/verificationCodes` ucundan okunur.
- Google girişi için emülatörün kabul ettiği imzasız JSON `id_token` kullanılır.

CI'da `.github/workflows/auth-e2e.yml` aynı testi Linux'ta bir Android emülatörüyle çalıştırır (giriş, eşitleme,
Firebase veya Android dosyaları değişince ve elle tetiklenince).

### Senaryolar

| # | Senaryo | Beklenen |
|---|---|---|
| 1 | Misafir 2 ders bitirir, e-postayla hesap açar | uid aynı, dersler cihazda; Premium'da bulut kopyası aynı uid'de |
| 2 | Aynı hesaba temiz bir cihazdan giriş | Premium: cihaz + bulut birleşir. Ücretsiz: bulut kopyası yok, cihazdaki ilerleme kalır |
| 3 | Telefonla giriş | Misafir bağlanır (uid aynı). Numara başka hesaptaysa o hesaba geçilir, ilerleme birleşir |
| 4 | Google ile giriş | Misafir bağlanır; hesap varsa (`credential-already-in-use`) ona geçilir, ilerleme birleşir |
| 5 | Çıkış | Yeni misafir hesabı; cihazdaki ilerleme kalır; önceki hesabın Premium'u yeni misafire geçmez |
| 6 | Bağlantı yok | Çökme yok; ilerleme cihazda; yazmalar "bekliyor" durumunda kalır, bağlantı gelince gider |
| 7 | Hata mesajları | Hatalı/boş/zayıf şifre, kayıtlı e-posta, şifremi unuttum, geçersiz numara, hatalı SMS kodu Türkçe |

## 2. Elle deneme: gerçek proje (`dilbaz-3392e`)

Uygulamayı gerçek projeyle kur (varsayılan mod `prod`):

```bash
flutter run --release
```

Her adımı bitirince Firebase konsolunda **Authentication > Users** ve **Firestore > users/{uid}** ile kontrol et.
Kendi e-postanı, kendi Google hesabını ve kendi numaranı kullan. Denemeden sonra test hesaplarını konsoldan
silebilirsin.

### Hazırlık

- [ ] Konsolda Authentication > Sign-in method: Anonim, E-posta/Şifre, Google, Telefon açık.
- [ ] Telefon için: Authentication > Settings > SMS region policy'de Türkiye izinli.
- [ ] Yüklediğin APK'yı imzalayan anahtarın SHA-1 ve SHA-256'sı projede kayıtlı (debug için kayıtlı; mağaza
      sürümü için Play App Signing anahtarı eklenmeli, bkz. `docs/firebase.md`).
- [ ] İsteğe bağlı test numarası: Authentication > Sign-in method > Telefon > "Phone numbers for testing"
      (ör. `+90 555 000 00 01`, kod `123456`). SMS kotası harcanmaz.

### A. Misafir → e-posta

1. [ ] Uygulamayı sil, yeniden kur, ilk açılışı tamamla. Profil > Hesap'ta "Misafir hesabı" yazmalı.
2. [ ] Konsolda yeni bir **anonim** kullanıcı göründü mü? uid'sini not et.
3. [ ] İki ders bitir.
4. [ ] Profil > Hesap > "Giriş yap / Hesap oluştur" > "Hesap oluştur": e-posta + 6+ karakter şifre.
5. [ ] "Hesabın oluşturuldu." görünmeli. Hesap kartında e-posta adresin yazmalı.
6. [ ] Konsolda aynı uid artık e-posta sağlayıcılı olmalı (yeni kullanıcı açılmamalı).
7. [ ] İki ders hâlâ tamamlanmış görünmeli.

### B. Başka cihazdan giriş (Premium yedekleme)

Bulut yedekleme Premium'a özel. Ücretsiz hesapta B adımı yalnızca girişin çalıştığını gösterir; ilerleme
birleşmez (beklenen davranış).

1. [ ] A'daki hesapla Premium al (ya da test için konsoldan `entitlements/<uid>` belgesine `active: true`,
       `expiresAt: <ileri tarih (timestamp)>` ekle).
2. [ ] Hesap kartında "İlerlemem buluta yedeklendi" görünmeli; Firestore'da `users/<uid>` oluşmalı.
3. [ ] İkinci bir cihaza (ya da uygulamayı silip yeniden kurduğun aynı cihaza) kur, misafir olarak 1 ders bitir.
4. [ ] "Giriş yap" ile A'daki e-posta ve şifreyle gir.
5. [ ] Birkaç saniye içinde A'daki dersler ve yeni ders birlikte görünmeli. Firestore'daki `progress.completed`
       hepsini içermeli.

### C. Telefon

1. [ ] Temiz kurulum, misafir, 1 ders.
2. [ ] Giriş ekranı > Telefon > numaranı `0532 123 45 67` biçiminde yaz > "Kod gönder".
3. [ ] SMS gelmeli (ya da Android numarayı kendisi doğrulayıp pencereyi kapatmalı).
4. [ ] Kodu gir > "Onayla". Konsolda aynı uid'ye telefon sağlayıcısı eklenmeli.
5. [ ] Uygulamayı sil, yeniden kur, misafir olarak 1 ders bitir, aynı numarayla gir.
6. [ ] Hata çıkmadan o hesaba geçmeli (uid C.4'teki ile aynı). Premium varsa dersler birleşmeli.
7. [ ] Yanlış kod gir: "Kod hatalı. SMS ile gelen 6 haneli kodu gir." görünmeli.

### D. Google

1. [ ] Temiz kurulum, misafir, 1 ders. Giriş ekranı > Google > hesabını seç.
2. [ ] Hesap kartında Gmail adresin görünmeli; konsolda aynı uid'ye `google.com` eklenmeli.
3. [ ] Uygulamayı sil, yeniden kur, misafir olarak 1 ders bitir, yine Google ile gir.
4. [ ] Hata çıkmadan aynı hesaba geçmeli; Premium varsa dersler birleşmeli.
5. [ ] Google penceresini "geri" ile kapat: hata mesajı çıkmamalı, misafir kalmalı.
6. [ ] Mağaza (release) sürümünde de dene. "Bir sorun oluştu" çıkarsa yayın anahtarının SHA'sı eksiktir.

### E. Çıkış

1. [ ] Giriş yapılmış hesapta Profil > Hesap > "Çıkış yap".
2. [ ] Kart "Misafir hesabı" olmalı; konsolda yeni bir anonim kullanıcı açılmalı.
3. [ ] Cihazdaki dersler yerinde durmalı.
4. [ ] Önceki hesap Premium idiyse yeni misafirde "Buluta yedekleme Premium'a özel" yazmalı.

### F. Bağlantı yok

1. [ ] Uçak modunu aç, uygulamayı kapatıp aç: çökmemeli, dersler açılmalı.
2. [ ] Bir ders bitir. Premium hesapta kart "İnternet gelince buluta yedeklenecek" demeli.
3. [ ] Giriş ekranında e-postayla girmeyi dene: "İnternet bağlantısı yok. Bağlanınca tekrar dene."
4. [ ] Uçak modunu kapat: kısa süre sonra "İlerlemem buluta yedeklendi" olmalı, Firestore'da yeni ders görünmeli.

### G. Mesajlar

| Ne yap | Beklenen mesaj |
|---|---|
| Kayıtlı e-posta, yanlış şifre | E-posta ya da şifre hatalı. |
| Kayıtlı olmayan e-postayla giriş | E-posta ya da şifre hatalı. |
| Şifre boş | Şifreni yaz. |
| Hesap oluştur, şifre `123` | Şifre en az 6 karakter olmalı. |
| Hesap oluştur, kayıtlı e-posta | Bu e-posta ile zaten bir hesap var. "Giriş yap"ı dene. |
| Şifremi unuttum (e-posta boş) | Önce e-posta adresini yaz. |
| Şifremi unuttum (kayıtlı ya da kayıtsız adres) | Şifre sıfırlama bağlantısı … adresine gönderildi. (Kayıtlı adrese e-posta gelmeli) |
| Telefon `123` | Telefon numarası geçerli değil. Örnek: 0532 123 45 67 |
| Yanlış SMS kodu | Kod hatalı. SMS ile gelen 6 haneli kodu gir. |
| Uçak modunda giriş | İnternet bağlantısı yok. Bağlanınca tekrar dene. |

Bir adım beklenenden farklıysa ekran görüntüsünü ve saati not et; konsolda Authentication > Users ve
Firestore'daki ilgili belgeyle birlikte bildir.
