<div align="center">

# Dilbaz

**Türkler için, Türkçe düşünerek İngilizce.**
Can yok, ceza yok, reklam yok. Her yanlışın arkasındaki Türkçe alışkanlığı gösteren bir öğrenme yolu.

[![CI](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml)
[![Release APK](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml)

<img src="docs/onizleme/01_genel_yol.jpg" width="200" alt="Öğrenme yolu">
<img src="docs/onizleme/04_seyahat.jpg" width="200" alt="Seyahat ünitesi">
<img src="docs/onizleme/10_dogru_cevap.jpg" width="200" alt="Doğru cevap">
<img src="docs/onizleme/06_lgs_yol.jpg" width="200" alt="LGS yolu">

</div>

---

## Dilbaz nedir?

Dilbaz, Türkçe konuşanlar için yazılmış bir İngilizce öğrenme uygulamasıdır (Flutter, Android/iOS/web).
Adı "dili güzel, lafı akıcı" anlamına gelir. Uygulama bir derse sıradan bir dil uygulaması gibi
yaklaşmaz. Her soruda Türklerin sık yaptığı hataları hedefler: "I am agree", "He don't", "solve the bug"…
Yanlış cevapta hatanın hangi Türkçe alışkanlıktan geldiğini Türkçe olarak açıklar.

Kimlik olarak Türk kültürünü taşır. Sunucu **Çaycı Dayı**, Çocuk modunun karakteri **Pofuduk**'tur.
Selamlaşma ünitelerinde düğümler çay bardağıdır. Diğer ünitelerde ise konunun kendi nesneleri
kullanılır: seyahatte bavul ve uçak, yemekte simit ve tabak, teknolojide terminal.

## Rakamlarla

| Parça | İçerik |
|---|---|
| **Genel İngilizce (A1 → C1)** | 10 bölüm · 142 ünite · 556 ders · 5.504 alıştırma · her bölümde dinleme, okuma, konuşma (gölgeleme) ve yazma üniteleri + bölüm beceri testi |
| **YDS / YÖKDİL — 1 yıllık program** | 52 hafta, günde 3–4 saat · 126 ünite · 524 ders · 8.113 soru · 4 kelime bankası (4.986 kart) · 3 okuma evi · 20 YDS + 3 YÖKDİL tam deneme, 8 yarım deneme · 52. haftadan sonra sürdürme modu |
| **Okuma ve dinleme kütüphanesi** | 345 metin, A1'den C1'e; "Önce dinle" modu, kelimeye dokununca anlam |
| **LGS İngilizce (8. sınıf)** | MEB'in 10 ünitesi · 40 ders · 510 soru · gerçek formatta 2 bölüm denemesi |
| **Yazılımcı İngilizcesi** | 604 kelime · bilgi haritası · aralıklı tekrar · 8 iş senaryosu |
| **Meslek paketleri** | Turizm (5 ünite) · İş görüşmesi (4 ünite) |
| **Notlarım** | Notion notlarından 80 adımlık Gramer Yolu, 856 kelimelik sözlük, 193 gramer notu |
| **Türk hata dedektörü** | 106 kural: yazdığın cümledeki Türkçe kaynaklı hatayı yakalar |

Bütün içerik bu proje için özgün olarak yazılmıştır. Resmî sınav soruları ya da başka uygulamaların
içerikleri kullanılmamıştır.

## Ekranlar

### Öğrenme yolu: her ünite kendi konusunu anlatır

<p>
<img src="docs/onizleme/01_genel_yol.jpg" width="200" alt="Genel yol">
<img src="docs/onizleme/02_yemek.jpg" width="200" alt="Yemek ünitesi">
<img src="docs/onizleme/03_ev_ve_sehir.jpg" width="200" alt="Ev ve şehir ünitesi">
<img src="docs/onizleme/04_seyahat.jpg" width="200" alt="Seyahat ünitesi">
</p>

Yol on bölümden oluşur. A1'den B2'ye uzanan ilk sekiz bölüm Mahalle, Çarşı, Vapur, Ofis, Yolculuk, Kütüphane, Toplantı ve Sahne'dir. Ardından iki C1 bölümü gelir: Derinlik ve Ustalık.
Her bölüm bir CEFR seviyesine karşılık gelir. Bölüm başında "Bölüme atla" sınavı vardır ve cezası yoktur.
Seviye testine göre uygun bölümden başlarsın. Kilitli bölümler katlanmış gelir, bu yüzden uygulama hızlı açılır.

### Ders akışı

<p>
<img src="docs/onizleme/08_ders_karti.jpg" width="200" alt="Ders kartı">
<img src="docs/onizleme/09_ders_soru.jpg" width="200" alt="Soru">
<img src="docs/onizleme/10_dogru_cevap.jpg" width="200" alt="Doğru cevap">
<img src="docs/onizleme/11_eslestirme.jpg" width="200" alt="Eşleştirme">
</p>

Alıştırma türleri: seçmeli, çeviri, boşluk doldurma, dinleme, eşleştirme, konuşma ve sınav tipi
çoktan seçmeli (`choice`, uzun okuma parçalı). Doğru cevapta "Tavşan kanı gibi!" gibi değişen Türkçe
övgüler çıkar. Yanlış cevapta hiçbir şey kaybedilmez: soru tekrar gelir ve "Hatalarını çalış" listesine
düşer. Dersten çıkmak da cezasızdır.

<img src="docs/onizleme/12_cikis.jpg" width="200" alt="Cezasız çıkış">

### Sınav yolları: rastgele soru değil, sıralı çalışma

<p>
<img src="docs/onizleme/06_lgs_yol.jpg" width="200" alt="LGS yolu">
<img src="docs/onizleme/07_lgs_rehber.jpg" width="200" alt="Konu anlatımı">
<img src="docs/onizleme/14_yds_yol.jpg" width="200" alt="YDS yolu">
<img src="docs/onizleme/13_kurs_secici.jpg" width="200" alt="Kurs seçici">
</p>

Her ünite aynı sırayla ilerler:
1. **Rehber:** Türkçe konu anlatımı, özet tablo ve sınav ipuçları.
2. **Dersler:** kelime, kalıp, diyalog ve okuma.
3. **Ünite testi.**
4. **Bölüm denemesi.**

Eski soru bankası ve tam paket denemeler Pratik sekmesinde durur. Planlar ayrı belgelerde:
[LGS planı](docs/sinav/lgs-plan.md) · [YDS/YÖKDİL planı ve 12 haftalık takvim](docs/sinav/yds-plan.md)

> ALES'te İngilizce bölümü yoktur. Yetişkin akademik sınavlar için YDS, e-YDS ve YÖKDİL hedeflenir.

### YDS'ye bir yılda hazırlık: bilimsel yöntemlerle

<p>
<img src="docs/onizleme/21_yds_bugun.jpg" width="200" alt="Bugün planı">
<img src="docs/onizleme/23_tekrar_karti.jpg" width="200" alt="Tekrar kartı">
<img src="docs/onizleme/25_hata_defteri.jpg" width="200" alt="Hata defteri">
<img src="docs/onizleme/26_deneme_raporu.jpg" width="200" alt="Deneme raporu">
</p>
<p>
<img src="docs/onizleme/22_nasil_ogretiyoruz.jpg" width="200" alt="Nasıl öğretiyoruz">
<img src="docs/onizleme/24_hatirladin_mi.jpg" width="200" alt="Hatırladın mı">
<img src="docs/onizleme/27_okuma_evi.jpg" width="200" alt="Okuma evi">
<img src="docs/onizleme/28_surdurme_modu.jpg" width="200" alt="Sürdürme modu">
</p>

Program, sıfırdan başlayan biri için 52 haftalık bir yol olarak tasarlandı. Toplam süre yaklaşık 1.170 saat. Yol üzerinde uygulanan yöntemler şunlar:

- **Bugün:** O günün çalışmasını seçtiğin süreye göre bloklara ayırır. Bloklar sırasıyla tekrar kartları, yeni ders, okuma, soru ve hata defteri.
- **Aralıklı tekrar:** 9 kutulu Leitner sistemi kullanılır. Kart önce "hatırladın mı?" diye sorar.
- **Hata defteri:** Yanlışın nedenini sorar. Soru 1, 3, 7 ve 21 gün sonra yeniden gelir.
- **Deneme raporu:** Soru tipine ve süreye göre analiz yapar, tahmini puanı gösterir.
- **YÖKDİL:** YÖKDİL'e hazırlananlar kendi alanının denemelerini çözer.

Bu yöntemlerin her biri uygulama içindeki **"Nasıl öğretiyoruz?"** ekranında kaynaklarıyla anlatılır. Araştırma ve plan belgeleri:
- [YDS araştırması](docs/sinav/yds-arastirma.md)
- [1 yıllık plan](docs/sinav/yds-1-yil.md)

### Genel kurs: dört beceri, C1'e kadar

<p>
<img src="docs/onizleme/29_beceri_unitesi.jpg" width="200" alt="Beceri ünitesi">
<img src="docs/onizleme/30_once_dinle.jpg" width="200" alt="Önce dinle">
<img src="docs/onizleme/31_okuma_kutuphanesi.jpg" width="200" alt="Okuma kütüphanesi">
<img src="docs/onizleme/32_c1_ustalik.jpg" width="200" alt="C1 Ustalık">
</p>

Her bölümde dört becerinin dersleri var:
- **Dinleme:** Hikâyeler önce dinlenir, metin sonra açılır ("Önce dinle").
- **Konuşma:** Gölgeleme (shadowing) alıştırmaları.
- **Yazma:** Ölçütlü yazma görevleri. Premium'da yapay zekâ geri bildirim verir; ücretsiz sürümde yerel kontrol ve öz değerlendirme var.
- **Okuma:** Okuma dersleri.

Her bölüm bir beceri testiyle biter. Son iki bölüm (Derinlik ve Ustalık) C1 seviyesindedir ve eşdizim, üslup ve söylem üzerine yoğunlaşır. Müfredat: [docs/genel-mufredat.md](docs/genel-mufredat.md)

### Pratik, lig, görevler, profil

<p>
<img src="docs/onizleme/15_pratik.jpg" width="200" alt="Pratik">
<img src="docs/onizleme/16_lig.jpg" width="200" alt="Lig">
<img src="docs/onizleme/17_gorevler.jpg" width="200" alt="Görevler">
<img src="docs/onizleme/18_profil.jpg" width="200" alt="Profil">
</p>

- **Pratik:** yapay zekâ ile rol yapma sohbeti, telaffuz koçu (th, w/v, ship/sheep), hatalarını çalış,
  60 saniyelik hızlı eşleştirme, okuma hikâyeleri ve hata analizi.
- **Lig ve görevler:** haftalık XP ligi, günlük görevler, seri ve günlük hedef.
- **Profil:** istatistikler, sık yaptığın hatalar ve Türkçe ipuçları, hesap ve yedekleme.

### Yazılımcı İngilizcesi, Çocuk modu, koyu tema

<p>
<img src="docs/onizleme/05_yazilimci.jpg" width="200" alt="Yazılımcı İngilizcesi">
<img src="docs/onizleme/19_cocuk_modu.jpg" width="200" alt="Çocuk modu">
<img src="docs/onizleme/20_koyu_tema.jpg" width="200" alt="Koyu tema">
</p>

## Ücretsiz ve Premium

Temel öğrenme her zaman ücretsizdir, reklam yoktur. **Dilbaz Premium** yapay zekâ sohbeti, sınırsız
deneme, detaylı hata analizi ve bulut yedekleme verir. Ek seçenekler aile planı, sınav paketleri ve
**Dilbaz Kurumsal**tır (okul ve şirketler için koltuk, sınıf ve ödev). Ayrıntılar:
[gelir planı](docs/gelir-plani.md) · [abonelik](docs/abonelik.md) · [kurumsal](docs/kurumsal.md)

## Yapılacaklar

Sıradaki işler iki tarafa ayrıldı: geliştirme ekibinin tarafı ve uygulama sahibinin tarafı.
👉 **[docs/yapilacaklar.md](docs/yapilacaklar.md)**

---

## Geliştiriciler için

<details>
<summary><b>Çalıştırma ve test</b></summary>

```bash
flutter pub get
flutter run
flutter test
```

Kod biçimi: `dart format -l 110 lib test`. CI her PR'da format, analyze ve testleri, ayrıca Functions
emülatör testlerini çalıştırır.

</details>

<details>
<summary><b>Firebase</b></summary>

Uygulama varsayılan olarak `dilbaz-3392e` projesine bağlanır. Giriş yöntemleri: anonim, e-posta/şifre,
Google ve telefon. Veriler Firestore'da tutulur. Mod `--dart-define=LINGORA_FIREBASE=off|emulator|prod`
ile değiştirilir. Lig, yapay zekâ sohbeti ve abonelik doğrulaması `functions/` altındaki Cloud Functions
ile çalışır.
Ayrıntılar: [istemci](docs/firebase.md) · [sunucu](docs/firebase-backend.md)

</details>

<details>
<summary><b>Proje yapısı</b></summary>

- `lib/models`, `lib/data`: içerik modelleri, ilerleme, bölümler, lig, görevler, aralıklı tekrar
- `lib/screens`, `lib/nav`: ekranlar ve sekme başına gezinme
- `lib/exercises`: alıştırma türleri
- `lib/ui`: tema, animasyonlar, maskotlar
- `assets/courses`: genel kurs (`tr_en` + bölüm dosyaları), sınav yolları (`exam_lgs`, `exam_yds`), meslek paketleri
- `assets/themes`: ünite temalarının özgün SVG'leri ([tasarım rehberi](docs/tasarim/temalar.md))
- `assets/exams`, `assets/exam_packs`, `assets/notes`, `assets/vocab`: soru bankaları, notlar, kelimeler
- `functions/`: Cloud Functions (TypeScript) · `lib/admin/`: web yönetim paneli
- `test/`: mantık, arayüz ve içerik doğrulama testleri

</details>

<details>
<summary><b>Teknik kimlikler neden "lingora"?</b></summary>

Uygulamanın adı Dilbaz'dır. Ancak bazı teknik kimlikler eski adı taşır, çünkü bunları değiştirmek
Firebase'i ve abonelikleri bozar:
- Dart paket adı `lingora`
- `com.lingora.lingora` (Android `applicationId`, iOS bundle id)
- Play ürün kimlikleri (`lingora_premium_*`)
- Firestore alan adları
- GitHub repo adı

</details>

<details>
<summary><b>Sürüm ve imzalama</b></summary>

Her `main` push'unda **Release APK** iş akışı bir APK derler ve `lingora-apk` artifact'ı olarak yükler.
`v*` etiketi gönderildiğinde GitHub Release oluşturulur. Gerçek imza için keystore dosyasını base64
olarak şu repository secret'larına ekle: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Bu secret'lar yoksa APK debug anahtarıyla imzalanır.

</details>

<details>
<summary><b>Notion notlarını güncelleme</b></summary>

```bash
node tool/import_notes.js <dönüştürülmüş-notlar-klasörü>
```

</details>

Görseller: Çaycı Dayı ve Pofuduk uygulama sahibine aittir. Ünite temaları bu proje için çizilmiştir.
Kaynaklar [docs/assets.md](docs/assets.md) dosyasındadır.
