<div align="center">

# Dilbaz

### Türkler için, Türkçe düşünerek İngilizce

**Can yok · ceza yok · reklam yok.** Her yanlışın arkasındaki Türkçe alışkanlığı gösteren, A1'den C1'e kadar giden
bir öğrenme yolu. Sıfırdan başlayan biri için YDS/YÖKDİL'e 52 haftalık bir program ve LGS hazırlığı da içinde.

[![CI](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/ci.yml)
[![Functions](https://github.com/HalilMertDeveli/lingora/actions/workflows/functions.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/functions.yml)
[![Sign-in E2E](https://github.com/HalilMertDeveli/lingora/actions/workflows/auth-e2e.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/auth-e2e.yml)
[![Release APK](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/HalilMertDeveli/lingora/actions/workflows/release.yml)

<img src="docs/onizleme/01_genel_yol.jpg" width="190" alt="Öğrenme yolu">
<img src="docs/onizleme/04_seyahat.jpg" width="190" alt="Seyahat ünitesi">
<img src="docs/onizleme/10_dogru_cevap.jpg" width="190" alt="Doğru cevap">
<img src="docs/onizleme/21_yds_bugun.jpg" width="190" alt="YDS Bugün planı">

</div>

---

## İçindekiler

1. [Dilbaz nedir, neden var?](#1-dilbaz-nedir-neden-var)
2. [Rakamlarla](#2-rakamlarla)
3. [Ekranlar](#3-ekranlar)
4. [Öğrenme mantığı](#4-öğrenme-mantığı)
5. [Parçalar: Genel İngilizce, YDS/YÖKDİL, LGS ve diğerleri](#5-parçalar)
6. [Mimari](#6-mimari)
7. [Veri modeli ve içerik biçimi](#7-veri-modeli-ve-içerik-biçimi)
8. [Ekranların teknik işleyişi](#8-ekranların-teknik-işleyişi)
9. [Performans: neyi neden böyle yaptık](#9-performans)
10. [Sunucu (Firebase)](#10-sunucu-firebase)
11. [Gelir modeli](#11-gelir-modeli)
12. [Kalite: testler, CI, içerik denetimi](#12-kalite)
13. [Geliştirme: çalıştırma, derleme, yapılandırma](#13-geliştirme)
14. [Proje haritası ve belgeler](#14-proje-haritası-ve-belgeler)
15. [Yapılacaklar ve bilinen sınırlar](#15-yapılacaklar-ve-bilinen-sınırlar)

---

## 1. Dilbaz nedir, neden var?

Dilbaz ("dili güzel, lafı akıcı"), Türkçe konuşanlar için yazılmış bir İngilizce öğrenme uygulamasıdır. Flutter ile
yazıldı; Android, iOS ve web'de çalışır.

Yaygın dil uygulamaları bütün dünyaya aynı dersi verir. Türk öğrencinin hataları ise kendine özgüdür: Türkçe yapıdan
gelen birkaç kalıp hata defalarca yapılır. Örnekler:

| Türkçe alışkanlık | Hatalı İngilizce | Doğrusu |
|---|---|---|
| "Katılıyorum" tek kelime, fiil gibi | *I am agree* | I agree |
| Türkçede şahıs eki fiilin içinde | *He don't like it* | He doesn't like it |
| "Hatayı çözmek" | *solve the bug* | fix the bug |
| "Ben ... yaşındayım" | *I have 20 years* | I am 20 |

Dilbaz bunun üzerine kurulu:

- **Türk hata dedektörü:** 106 kural, yazdığın cümledeki Türkçe kaynaklı hatayı yakalar ve neden yanlış olduğunu
  Türkçe açıklar.
- **Cezasız öğrenme:** Can sistemi yok. Yanlış cevap seni durdurmaz; soru sonra yeniden gelir ve hata defterine düşer.
  Dersten çıkmak bile cezasız.
- **Reklam yok.** Temel öğrenme ücretsizdir.
- **Türk kimliği:** Sunucu karakter **Çaycı Dayı**, Çocuk modunun karakteri **Pofuduk**. Selamlaşma ünitelerinde düğümler
  ince belli çay bardağıdır; diğer ünitelerde konunun kendi nesneleri kullanılır (seyahatte bavul ve uçak, yemekte simit
  ve tabak).

İçeriğin tamamı bu proje için özgün yazıldı. Resmî sınav soruları, ders kitabı metinleri ya da başka uygulamaların
içerikleri kullanılmadı. Açık lisanslı kaynakların listesi [docs/kaynaklar.md](docs/kaynaklar.md) dosyasında.

---

## 2. Rakamlarla

| Parça | İçerik |
|---|---|
| **Genel İngilizce (A1 → C1)** | 10 bölüm · 142 ünite · 556 ders · 5.504 alıştırma · her bölümde dinleme, okuma, konuşma (gölgeleme) ve yazma üniteleri + bölüm beceri testi |
| **YDS / YÖKDİL: 1 yıllık program** | 52 hafta, günde 3–4 saat (~1.170 saat) · 126 ünite · 524 ders · 8.113 soru · 4 kelime bankası (4.986 kart) · 3 okuma evi · 20 YDS + 3 YÖKDİL tam deneme, 8 yarım deneme · 52. haftadan sonra sürdürme modu |
| **LGS İngilizce (8. sınıf)** | MEB'in 10 ünitesi · 40 ders · 510 soru · gerçek formatta 2 bölüm denemesi |
| **Okuma ve dinleme kütüphanesi** | A1'den C1'e 345 metin · "Önce dinle" modu · kelimeye dokununca anlam |
| **Yazılımcı İngilizcesi** | 604 kelime · bilgi haritası · aralıklı tekrar · 8 iş senaryosu |
| **Meslek paketleri** | Turizm (5 ünite) · İş görüşmesi (4 ünite) |
| **Notlarım** | Notion notlarından 80 adımlık Gramer Yolu, 856 kelimelik sözlük, 193 gramer notu |
| **Kod** | ~39 bin satır Dart · 935 Flutter testi · 71 Cloud Functions testi · 23 uçtan uca giriş testi |

---

## 3. Ekranlar

### Öğrenme yolu: her ünite kendi konusunu anlatır

<p>
<img src="docs/onizleme/01_genel_yol.jpg" width="190" alt="Genel yol">
<img src="docs/onizleme/02_yemek.jpg" width="190" alt="Yemek ünitesi">
<img src="docs/onizleme/03_ev_ve_sehir.jpg" width="190" alt="Ev ve şehir">
<img src="docs/onizleme/04_seyahat.jpg" width="190" alt="Seyahat">
</p>

Yol, on bölümden oluşan kıvrımlı bir patikadır. A1'den B2'ye uzanan ilk sekiz bölüm bir mekân olarak çizilir: Mahalle,
Çarşı, Vapur, Ofis, Yolculuk, Kütüphane, Toplantı ve Sahne. Ardından iki C1 bölümü gelir: Derinlik ve Ustalık.

Her ünitenin bir teması var (29 tema). Düğümler konunun hikâyesini sırayla anlatır, örneğin seyahatte bilet → uçak →
otel anahtarı. Bitmiş, sıradaki ve kilitli dersler görsel olarak ayrışır; sıradaki ders hafifçe hareket eder.

### Ders akışı

<p>
<img src="docs/onizleme/08_ders_karti.jpg" width="190" alt="Ders kartı">
<img src="docs/onizleme/09_ders_soru.jpg" width="190" alt="Soru">
<img src="docs/onizleme/10_dogru_cevap.jpg" width="190" alt="Doğru cevap">
<img src="docs/onizleme/12_cikis.jpg" width="190" alt="Cezasız çıkış">
</p>

### YDS: bir yıllık program ve çalışma sistemi

<p>
<img src="docs/onizleme/21_yds_bugun.jpg" width="190" alt="Bugün planı">
<img src="docs/onizleme/23_tekrar_karti.jpg" width="190" alt="Tekrar kartı">
<img src="docs/onizleme/25_hata_defteri.jpg" width="190" alt="Hata defteri">
<img src="docs/onizleme/26_deneme_raporu.jpg" width="190" alt="Deneme raporu">
</p>
<p>
<img src="docs/onizleme/22_nasil_ogretiyoruz.jpg" width="190" alt="Nasıl öğretiyoruz">
<img src="docs/onizleme/27_okuma_evi.jpg" width="190" alt="Okuma evi">
<img src="docs/onizleme/14_yds_yol.jpg" width="190" alt="YDS yolu">
<img src="docs/onizleme/28_surdurme_modu.jpg" width="190" alt="Sürdürme modu">
</p>

### Dört beceri, C1'e kadar

<p>
<img src="docs/onizleme/29_beceri_unitesi.jpg" width="190" alt="Beceri ünitesi">
<img src="docs/onizleme/30_once_dinle.jpg" width="190" alt="Önce dinle">
<img src="docs/onizleme/31_okuma_kutuphanesi.jpg" width="190" alt="Okuma kütüphanesi">
<img src="docs/onizleme/32_c1_ustalik.jpg" width="190" alt="C1 Ustalık">
</p>

### LGS, sınav rehberi, kurs seçici

<p>
<img src="docs/onizleme/06_lgs_yol.jpg" width="190" alt="LGS yolu">
<img src="docs/onizleme/07_lgs_rehber.jpg" width="190" alt="Konu anlatımı">
<img src="docs/onizleme/13_kurs_secici.jpg" width="190" alt="Kurs seçici">
<img src="docs/onizleme/05_yazilimci.jpg" width="190" alt="Yazılımcı İngilizcesi">
</p>

### Pratik, lig, görevler, profil, Çocuk modu, koyu tema

<p>
<img src="docs/onizleme/15_pratik.jpg" width="150" alt="Pratik">
<img src="docs/onizleme/16_lig.jpg" width="150" alt="Lig">
<img src="docs/onizleme/17_gorevler.jpg" width="150" alt="Görevler">
<img src="docs/onizleme/18_profil.jpg" width="150" alt="Profil">
<img src="docs/onizleme/19_cocuk_modu.jpg" width="150" alt="Çocuk modu">
<img src="docs/onizleme/20_koyu_tema.jpg" width="150" alt="Koyu tema">
</p>

---

## 4. Öğrenme mantığı

Uygulamadaki her özellik bir öğrenme yöntemine dayanır. Kullanıcı bunu uygulama içindeki **"Nasıl öğretiyoruz?"**
ekranında, kaynaklarıyla birlikte görür. Yöntemlerin araştırması ve 29 kaynağı:
[docs/sinav/yds-arastirma.md](docs/sinav/yds-arastirma.md).

| Yöntem | Neden işe yarar | Uygulamada nerede |
|---|---|---|
| **Aralıklı tekrar** | Unutmanın tam eşiğinde tekrar etmek kalıcılığı artırır | 9 kutulu Leitner kelime kartları: 0, 1, 3, 7, 14, 30, 60, 120, 240 gün |
| **Geri çağırma pratiği** | Hatırlamaya çalışmak, yeniden okumaktan daha kalıcıdır | Kart önce "hatırladın mı?" diye sorar; bütün alıştırmalar üretmeye dayalıdır |
| **Hata defteri** | Hatalar hedefli tekrar edilince düzelir | Yanlış soru 1, 3, 7 ve 21 gün sonra yeniden gelir; iki kez doğru yapılınca çıkar |
| **Hatanın nedeni** | Nedeni bilinen hata tekrar edilmez | "Neden yanıldın?" etiketi; Türk hata dedektörünün Türkçe açıklaması |
| **Karışık çalışma** | Konular karışınca ayırt etme gelişir | Bitmiş ünitelerden karışık tekrar setleri |
| **Bol ve yoğun okuma** | Kelime dağarcığı en çok okumayla büyür | Okuma evleri (yoğun) ve geniş okuma setleri (YDS'de ~420 bin kelime) |
| **Önce dinle** | Metni görmeden anlamak dinleme becerisini ayrıca geliştirir | Hikâyelerde ve kütüphanede metin, dinledikten sonra açılır |
| **Gölgeleme** | Duyduğunu tekrar etmek telaffuzu ve akıcılığı geliştirir | Konuşma alıştırmaları, telaffuz koçu (th, w/v, ship/sheep) |
| **Deneme → analiz → hedefli tekrar** | Bilinçli pratik ve kendini sınama | Deneme raporu: soru tipi ve süre analizi, tahmini puan |
| **Zaman yönetimi** | YDS'de okuma sorularına zaman kalması puanı korur | Soru tipi başına hedef süreler |
| **Alışkanlık** | Alışkanlık ortalama 66 günde oturur; tek bir kaçırılan gün bozmaz | Bugün planı, hatırlatıcı, haftada bir otomatik seri dondurma |

### Bir dersin içindeki döngü

```mermaid
flowchart LR
    A[Soru] --> B{Cevap}
    B -- doğru --> C[Övgü + XP]
    B -- yanlış --> D[Doğru cevap + Türkçe açıklama]
    D --> E[Soru dersin sonunda tekrar gelir]
    D --> F[Hata defterine düşer<br/>1-3-7-21 gün]
    C --> G{Ders bitti mi?}
    E --> G
    G -- hayır --> A
    G -- evet --> H[Kutlama: XP, seri, görev]
    H --> I[Yolda sıradaki derse dönüş]
```

### Çalışma günü (YDS "Bugün")

Uygulama, seçilen süreye göre (30 dakika – 4 saat) günü bloklara böler: **tekrar kartları → yeni ders → okuma → soru →
hata defteri**. Haftalar takvimle değil adım adım ilerler: haftanın üniteleri bitince yeni hafta açılır. Bu yüzden
kaçırılan bir gün iş biriktirmez.

---

## 5. Parçalar

### Genel İngilizce (A1 → C1)

- **10 bölüm:** Her bölüm bir CEFR seviyesine karşılık gelir.
  - Bölüm başında cezasız bir **"Bölüme atla"** sınavı var: 15 soruda %80 yapan bölümü açar.
  - **Seviye testine** göre başlangıç bölümü değişir: A2 → Bölüm 3, B1 → Bölüm 5, B2 → Bölüm 7.
- **Ünite yapısı:** 4 ders, bir hikâye, bir ünite sınavı ve bir ödül. Her ünitede bir **rehber** (konu anlatımı) var.
- **Beceri üniteleri:** Her bölümde dinleme, okuma, konuşma (gölgeleme) ve yazma ayrı üniteler olarak çalışılır.
  - Yazma görevleri ölçütlerle değerlendirilir.
  - Premium'da yapay zekâ geri bildirim verir.
  - Ücretsiz sürümde yerel kontrol ve öz değerlendirme var.
- **C1 bölümleri** (Derinlik, Ustalık): eşdizim, üslup ve söylem üzerine. Akademik kelime YDS yolunda kalır.
- Müfredat ve araştırma: [docs/genel-mufredat.md](docs/genel-mufredat.md) · [docs/genel-arastirma.md](docs/genel-arastirma.md)

### YDS / YÖKDİL: bir yılda sıfırdan yüksek puana

Program sıfırdan başlayan biri için tasarlandı: 52 hafta, günde 3–4 saat. ALES'te İngilizce bölümü olmadığı için hedef
YDS, e-YDS ve YÖKDİL'dir.

```mermaid
flowchart LR
    E1[Evre 1<br/>Hafta 1-10<br/>Temel] --> E2[Evre 2<br/>Hafta 11-20<br/>A2→B1]
    E2 --> E3[Evre 3<br/>Hafta 21-34<br/>B1→B2 akademik]
    E3 --> E4[Evre 4<br/>Hafta 35-42<br/>Strateji]
    E4 --> E5[Evre 5<br/>Hafta 43-52<br/>Deneme kampı]
    E5 --> S[Sürdürme modu<br/>dersler bitmez]
```

- **Ana yol:** dilbilgisi, kelime ve kalıplar, soru tipi stratejileri (cloze, cümle tamamlama, çeviri, paragraf, diyalog,
  yakın anlam, anlam bütünlüğü), deneme ve zaman yönetimi.
- **Paralel yollar:** ana yolun sonunda kilitli beklemez, onunla birlikte açılır.
  - 4 kelime bankası: toplam 4.986 kart, akademik kelime listelerine göre.
  - 3 okuma evi: fen, sağlık ve sosyal alan metinleri.
  - Ara denemeler.
- **Denemeler:**
  - 20 YDS tam denemesi (80 soru / 180 dakika).
  - 3 YÖKDİL denemesi, alan başına bir tane. YÖKDİL'e hazırlanana son haftalarda bunlar açılır.
  - 8 yarım deneme ve bölüm denemeleri.
- **Planlar:** [docs/sinav/yds-1-yil.md](docs/sinav/yds-1-yil.md) · plan verisi
  [assets/plans/yds_1_yil.json](assets/plans/yds_1_yil.json)

### LGS (8. sınıf)

MEB 8. sınıf İngilizce programının 10 ünitesi sırayla işlenir: Friendship'ten Natural Forces'a kadar.

- Her ünitede Türkçe konu anlatımı, özet tablo ve sınav ipuçları var.
- Dersler kelime, kalıp, diyalog ve okuma olarak ayrılır; her ünite 10 soruluk bir mini LGS testiyle biter.
- Bölüm denemeleri gerçek LGS formatındadır. Plan: [docs/sinav/lgs-plan.md](docs/sinav/lgs-plan.md)

### Diğer parçalar

- **Yazılımcı İngilizcesi:** 604 kelime ve bir bilgi haritası. Kelimeler önem sırasına göre ayıklanır, kartlarla tekrar
  edilir. Stand-up, code review ve teknik mülakat senaryoları var.
- **Meslek paketleri:** Turizm (resepsiyon, restoran, rehberlik) ve İş görüşmesi.
- **Notlarım:** Notion'daki kişisel İngilizce notlarından üretilir. İçinde 80 adımlık Gramer Yolu, sözlük, gramer notları
  ve İngilizce günlük var.
- **Pratik:**
  - Yapay zekâ ile rol yapma sohbeti
  - Telaffuz koçu
  - Hatalarını çalış
  - 60 saniyelik hızlı eşleştirme
  - Okuma hikâyeleri
  - Hata analizi
- **Motivasyon:** seri, XP, günlük hedef, günlük görevler, haftalık lig, hatırlatma bildirimleri.

---

## 6. Mimari

```mermaid
flowchart TB
    subgraph App[Flutter uygulaması]
        UI[Ekranlar<br/>lib/screens, lib/exercises]
        NAV[Gezinme<br/>lib/nav: sekme başına Navigator]
        ST[Durum: Riverpod<br/>progressProvider, courseProvider...]
        DATA[Veri katmanı<br/>lib/data, lib/study]
        LOCAL[(shared_preferences<br/>progress_v1)]
        ASSETS[(Asset içerik<br/>JSON + SVG)]
    end
    subgraph FB[Firebase · dilbaz-3392e]
        AUTH[Auth<br/>anonim, e-posta, Google, telefon]
        FS[(Firestore)]
        CF[Cloud Functions<br/>lig, sohbet, yazma, satın alma, aile, kurum]
        RC[Remote Config + Analytics]
    end
    AI[Anthropic API<br/>claude-opus-5-5]
    PLAY[Google Play Billing]

    UI --> NAV --> ST --> DATA
    DATA --> LOCAL
    DATA --> ASSETS
    ST <--> AUTH
    ST <--> FS
    UI --> CF
    CF --> FS
    CF --> AI
    CF --> PLAY
    ST --> RC
```

**Temel ilke: yerel önce.** Bütün öğrenme cihazda çalışır. İlerleme `shared_preferences` içindeki tek bir `progress_v1`
kaydında tutulur, internet gerekmez. Firebase şu işler için var:

- hesap ve cihazlar arası eşitleme (giriş yapan herkese ücretsiz: Google, e-posta ya da telefon)
- lig
- yapay zekâ özellikleri
- satın alma doğrulama
- aile ve kurum hesapları

Firebase açılamazsa uygulama çökmez, yerel modda devam eder.

| Katman | Teknoloji |
|---|---|
| Arayüz | Flutter 3.47 / Dart 3.13, Material 3, kendi tema sistemi (açık/koyu, yetişkin/Çocuk modu) |
| Durum | Riverpod 3 |
| Yerel depolama | shared_preferences (ilerleme), asset JSON (içerik) |
| Ses | flutter_tts (sesli okuma, UK/US aksan), speech_to_text (konuşma ve gölgeleme) |
| Bildirim | flutter_local_notifications (seri ve mola hatırlatma) |
| Görseller | flutter_svg (tema nesneleri, bir kez bitmap'e çevrilir), CustomPainter (çay bardağı, patika, çini, mekânlar) |
| Sunucu | Firebase Auth, Firestore, Cloud Functions (TypeScript, Node 22), Remote Config, Analytics |
| Ödeme | in_app_purchase (Google Play Billing), sunucuda doğrulama |
| Yapay zekâ | Anthropic API (sohbet ve yazma değerlendirmesi), yalnızca sunucudan çağrılır |
| Yönetim paneli | Flutter web (`lib/admin/`): kurum, sınıf ve ödev yönetimi |

### Gezinme

- **Sekmeler:** Seçili parçaya göre değişir.
  - Genel kurs: Öğren · Pratik · Lig · Görevler · Profil.
  - Yazılımcı İngilizcesi: Keşfet · Tekrar · Harita · Senaryolar · Profil.
- **Sekme geçmişi:** Her sekmenin kendi `Navigator`'ı var. Alt sayfalarda alt çubuk görünür kalır; sekme değişince
  geçmiş korunur.
- **Tam ekran açılanlar:** Ders, sınav, hikâye, seviye testi ve paywall kök Navigator'da tam ekran açılır.
- **Geri tuşu:** Önce sekme içinde geri gider. Sekmenin başındaysa ilk sekmeye döner, oradaysa uygulamadan çıkar. Ders
  sırasında geri tuşu cezasız bir çıkış onayı açar.
- **Aynı sekmeye tekrar dokunma:** Geçmişi köke indirir, kökteyse yolda kaldığın derse kaydırır.

---

## 7. Veri modeli ve içerik biçimi

İçerik uygulamanın içinde, `assets/` altında JSON olarak gelir. Bu yüzden ders çalışmak için internet gerekmez.

```mermaid
classDiagram
    Course "1" --> "*" Section
    Section "1" --> "*" Unit
    Unit "1" --> "*" PathNode
    PathNode "1" --> "*" Exercise
    class Course { id, title, sections }
    class Section { id, index, title, cefr, grammar, parallel }
    class Unit { id, title, theme, guide, color }
    class PathNode { id, type: lesson|story|test|chest|mock }
    class Exercise { type: select|translate|fillBlank|listen|match|speak|choice|write|shadow }
```

- **Dosya düzeni:** Bir kurs bir ana dosya (`assets/courses/tr_en.json`) ve bölüm dosyalarından
  (`assets/courses/tr_en/NN_slug.json`) oluşur. Bir bölüme sonradan ünite eklemek için `NNx_slug.json` gibi ek dosyalar
  kullanılır. Sınav yolları da aynı biçimdedir (`exam_lgs`, `exam_yds`).
- **Kimlikler değişmez:** Ünite ve düğüm kimlikleri (ör. `s2u1l1`, `ys7u3l2`) asla değişmez ve silinmez. İlerleme bu
  kimliklere bağlıdır; yeni içerik her zaman yeni dosyalara eklenir. Bitmiş bölümlerin yeni içerikle yeniden açılmadığını
  bir test korur.
- **Alıştırma türleri:**

| Tür | Ne yapar |
|---|---|
| `select` | Resimli/emoji kartlardan anlamı seç |
| `translate` | Kelime bankasıyla ya da yazarak çevir (cevap varyantları kabul edilir) |
| `fillBlank` | Boşluğu doldur |
| `listen` | Dinle ve yaz |
| `match` | Eşleri bul |
| `speak` | Sesli oku (konuşma tanıma) |
| `choice` | Sınav tipi çoktan seçmeli; uzun okuma parçası ve Türkçe açıklama |
| `write` | Ölçütlü yazma görevi |
| `shadow` | Gölgeleme: dinle, tekrar et |

- **Kurs özeti** (`assets/course_index/`): Kurs dosyalarından derleme sırasında üretilir; içerikte ünite başlıkları,
  kimlikler ve temalar var. Yol ekranı bu küçük özetten çizilir, tam kurs arka planda yüklenir. İçerik değişince
  `dart run tool/build_course_index.dart` çalıştırılır; güncel olmadığında bir test bunu yakalar.
- **Kelime bankaları** (`assets/vocab/yds.json`): her kartta Türkçe anlam, örnek cümle ve çevirisi, eşdizim ve kelime
  ailesi var.
- **İlerleme** (`Progress`): bitmiş düğümler, XP, seri, kelime kutuları (`wordBox`, `wordDue`), hata defteri, sınav
  sonuçları, ayarlar. Her alanın eski kayıtlarla uyumu testlerle korunur.

---

## 8. Ekranların teknik işleyişi

### Yol ekranı (`lib/screens/path_screen.dart`, `path_map.dart`)

- **Tembel liste:** Yalnızca ekrana yakın ünite blokları kurulur ve çizilir (`ListView`, 800 px önbellek). Yüzlerce ünite
  olsa da yalnız görünenler maliyet çıkarır.
- **Katlama:** Kilitli ve bitmiş bölümler katlanmış gelir. Açık ve devam eden bölümler açıktır.
- **Odaklanma:** Açılışta yol, kaldığın derse gelir. Tembel listede o ders henüz kurulmamış olabilir; bu yüzden önce
  kabaca atlanır, sonra ekran ekran yaklaşılır ve ders kurulunca ortalanır.
- **Sabit ünite bandı:** Okunan ünitenin bandı üstte durur, sonraki bant gelince onu yukarı iter (üst üste binmez).
  "Bulunduğun yere dön" düğmesiyle birlikte `ValueNotifier` ile güncellenir; kaydırma yolu yeniden kurmaz.
- **Çizim:** Çay bardağı, demlik, lale rozeti, patika, çini deseni ve bölüm mekânları `CustomPainter` ile çizilir. 29
  temanın nesneleri özgün SVG'lerdir.

### Ders ekranı (`lesson_screen.dart`, `lib/exercises/`)

- Her alıştırma türü ayrı bir bileşendir; ders ekranı bunları sırayla gösterir.
- **Şıklar** soru metnine bağlı, sabit ama karışık bir sırayla gösterilir (`stableShuffle`). İçerik dosyalarında doğru
  cevap çoğu zaman ilk sıradadır; bu sayede "hep ilk şık" stratejisi işe yaramaz.
- **Geri bildirim paneli:** Doğruysa değişen Türkçe övgüler gelir ("Tavşan kanı gibi!"). Yanlışsa doğru cevap ve
  Türkçe açıklama çıkar.
- **Yanlış yapılan soru** dersin sonunda yeniden sorulur.

### Çalışma sistemi (`lib/study/`, `lib/screens/study/`)

| Dosya | Görevi |
|---|---|
| `daily_plan.dart` | "Bugün": 52 haftalık plandan günün bloklarını kurar |
| `review_queue.dart` | Leitner kutuları ve günlük tekrar kuyruğu |
| `mixed_review.dart` | Bitmiş ünitelerden karışık setler |
| `analysis.dart`, `mistake_reasons.dart` | Hata defteri, neden etiketleri, zayıf nokta analizi |
| `year_plan.dart`, `study_state.dart` | Plan haftası, sürdürme modu, YÖKDİL deneme yönlendirmesi |
| `answer_recorder.dart`, `question_types.dart` | Her cevabın türü ve süresi (deneme raporu ve tahmini puan için) |

---

## 9. Performans

Bir ekranın akıcı görünmesi için her karenin 16 ms içinde hem hazırlanması (UI) hem çizilmesi (raster) gerekir.
Ölçmek için yerleşik bir araç var: `--dart-define=LINGORA_FRAME_STATS=true` ile derlenen uygulama, her 30 karede bir
ortalama ve en kötü süreleri yazar. Açılış adımları için `LINGORA_STARTUP_TRACE` kullanılır.

| Sorun | Neden | Çözüm | Sonuç |
|---|---|---|---|
| Yol açılışta yavaştı | 94 ünitenin hepsi baştan çiziliyordu | Kilitli ve bitmiş bölümler katlanmış; derleme zamanında kurs özeti | İlk çizim 1,9 sn → 0,9 sn (debug) |
| Kaydırırken takılıyordu | Kaydırmanın her karesinde `setState` bütün yolu yeniden kuruyordu | Sabit bant ve dön düğmesi `ValueNotifier`'a; tembel liste | Kare hazırlama 60–95 ms → ~1 ms |
| Gri ve soluk görseller pahalıydı | `Opacity` + `ColorFiltered` her düğüm için ayrı katman açıyordu | Tek bir renk matrisi, doğrudan görselin üzerinde | Ek katman yok |
| Kesik çizgi pahalıydı | Ünite başına ~100 ayrı `drawPath`, her karede | Uçlar bir kez hesaplanıp tek `drawRawPoints` çağrısı | Kaydırma raster ~22 → ~17 ms |
| SVG'ler her karede yeniden çiziliyordu | Bant desenlerinde bant başına onlarca vektör görsel | Her görsel bir kez bitmap'e çevrilip önbellekten çiziliyor | Kaydırma raster ~14–16 ms |
| Hareketli düğüm bütün yolu boyatıyordu | Animasyon üst katmanı da yeniden çizdiriyordu | Düğüm, buhar, davet balonu ve maskot `RepaintBoundary` içinde | Yalnız kendi katmanı |

Diğer sekmeler (Pratik, Lig, Görevler, Profil) kaydırmada ~2 ms raster ile çalışıyor. Ölçümler emülatörde (`-gpu host`,
profile derleme) yapıldı; gerçek telefonda ayrıca ölçülmeli.

---

## 10. Sunucu (Firebase)

Proje: `dilbaz-3392e`. Cloud Functions TypeScript ile yazıldı, `functions/` klasöründe.

| Fonksiyon | Ne yapar |
|---|---|
| `joinLeague`, `addLeagueXp`, `settleLeagues` (zamanlanmış) | Haftalık XP ligi: gruplama, puan, hafta sonu yükselme ve düşme |
| `converse` | Yapay zekâ ile rol yapma sohbeti; hatalar Türkçe açıklanır (Premium, günlük kota, başarısız çağrı iade edilir) |
| `assessWriting` | Yazma görevini ölçütlerle değerlendirir (Premium, günde 20, ölçütler sunucuda) |
| `verifyPurchase` | Google Play satın almasını doğrular, hakları (`entitlements`) yazar |
| `createFamilyInvite`, `redeemFamilyCode`, `getFamily`... | Aile planı (koltuklar, davet kodu) |
| `orgs_api` | Dilbaz Kurumsal: kurum, koltuk, kod, sınıf, ödev |
| `referral_api` | Davet programı |

- **Firestore koleksiyonları:** `users`, `entitlements`, `leagues`, `leagueState`, `memberships`, `orgs`, `orgCodes`.
  Her koleksiyonun okuma ve yazma kuralları `firestore.rules` dosyasında.
- **Giriş:** anonim (misafir), e-posta/şifre, Google, telefon (SMS). Misafir hesabı başka bir yöntemle bağlanınca aynı
  kimlik korunur, ilerleme kaybolmaz.
- **Gizli anahtarlar:** Anthropic API anahtarı yalnızca sunucuda, Firebase secret olarak tutulur; uygulamada anahtar yok.
- **Ayrıntılar:** [docs/firebase.md](docs/firebase.md) · [docs/firebase-backend.md](docs/firebase-backend.md) ·
  [docs/giris-testleri.md](docs/giris-testleri.md)

---

## 11. Gelir modeli

- **Ücretsiz:** Bütün dersler, sınav yolları, bölüm denemeleri, tekrar kartları ve hata defteri. Reklam yok.
- **Dilbaz Premium (aylık/yıllık):** yapay zekâ sohbeti, yapay zekâ yazma geri bildirimi, detaylı hata analizi,
  sınırsız deneme. (Hesapla ilerleme eşitleme Premium değildir, giriş yapan herkese ücretsizdir.)
- **Aile planı** ve **sınav paketleri:** YDS paketi 23 tam deneme içerir, LGS paketi de var.
- **Dilbaz Kurumsal:** okul ve şirketler için koltuk, sınıf ve ödev; web yönetim paneli.
- **Ayrıntılar:** [docs/gelir-plani.md](docs/gelir-plani.md) · [docs/abonelik.md](docs/abonelik.md) ·
  [docs/kurumsal.md](docs/kurumsal.md)

---

## 12. Kalite

| Kontrol | Ne zaman | Ne yapar |
|---|---|---|
| **CI** (`ci.yml`) | Her PR ve push | Format kontrolü (`dart format -l 110`), `flutter analyze`, 935 test |
| **Functions** (`functions.yml`) | Her PR ve push | Firebase emülatörüyle 71 sunucu testi |
| **Sign-in E2E** (`auth-e2e.yml`) | Her PR ve push | Android emülatörü + Firebase emülatörü üzerinde 23 uçtan uca giriş testi |
| **Release APK** (`release.yml`) | `main` ve `v*` etiketleri | APK derler; etiketle GitHub Release oluşturur |

**İçerik testleri** her içerik dosyasını otomatik denetler. Kontroller:
- Kimlikler benzersiz mi, düğüm deseni doğru mu?
- Her alıştırmada türüne göre gereken alanlar var mı, `answer` şıkların içinde mi?
- Cevap, verilen kelime kartlarıyla kurulabiliyor mu?
- Cevabı ele veren durumlar var mı? Örneğin boşluktan önceki "a/an", şıklarda ✅/❌ emojisi, açıklamada "birinci şık"
  gibi sıraya dayalı ifade.
- YDS kelime bankaları önceki derslerle çakışıyor mu?
- Yayındaki bölümler değişmeden duruyor mu?

**İnsan ve yapay zekâ incelemesi:**
- Her içerik PR'ının cevap anahtarı, ayrı bir çözücü tarafından anahtarı görmeden çözülerek kontrol edildi.
- Uzman inceleme oturumları ayrıca denetledi.
- Kalite turunda 184 sorun düzeltildi: [docs/kalite-turu.md](docs/kalite-turu.md).

---

## 13. Geliştirme

```bash
flutter pub get
flutter run
flutter test
```

Format kuralı: `dart format -l 110 lib test`. Kurs içeriği değişince:

```bash
dart run tool/build_course_index.dart
```

### Derleme ayarları (`--dart-define`)

| Ayar | Değerler | Anlamı |
|---|---|---|
| `LINGORA_FIREBASE` | `prod` (varsayılan), `emulator`, `off` | Gerçek proje, yerel Firebase emülatörü ya da tamamen yerel |
| `LINGORA_EMULATOR_HOST` | IP | Emülatör modunda gerçek telefondan bağlanmak için |
| `LINGORA_FUNCTIONS_REGION` | `europe-west1` | Cloud Functions bölgesi |
| `LINGORA_GOOGLE_SERVER_CLIENT_ID` | OAuth istemci kimliği | Google girişi (varsayılanı ayarlı) |
| `LINGORA_PREMIUM` | `true` | Geliştirmede Premium'u açar |
| `LINGORA_FRAME_STATS` | `true` | Kare süresi günlüğü (performans ölçümü) |
| `LINGORA_STARTUP_TRACE` | `true` | Açılış adımlarının süreleri |

### Sürüm ve imzalama

- **APK:** Her `main` push'unda **Release APK** iş akışı bir APK derler. `v*` etiketi gönderilince GitHub Release
  oluşur.
- **Yayın imzası:** Gerçek yayın imzası için keystore'u base64 olarak dört repository secret'ına ekle:
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Bu secret'lar
  yoksa APK debug anahtarıyla imzalanır.
- **Telefona özel APK:** `flutter build apk --release --split-per-abi` ile arm64 için ~33 MB'lık APK çıkar.

### Firebase emülatörüyle yerel çalışma

```bash
npx -y firebase-tools@latest emulators:start
flutter run --dart-define=LINGORA_FIREBASE=emulator
```

<details>
<summary><b>Teknik kimlikler neden "lingora"?</b></summary>

Uygulamanın adı Dilbaz'dır. Bazı teknik kimlikler eski adla kaldı, çünkü bunları değiştirmek Firebase'i ve
abonelikleri bozar:
- Dart paket adı `lingora`
- `com.lingora.lingora`: Android `applicationId` ve iOS bundle id
- Play ürün kimlikleri `lingora_premium_*`, `lingora_pack_*`
- Firestore alan adları ve analitik olay adları
- GitHub repo adı

</details>

---

## 14. Proje haritası ve belgeler

```
lib/
  main.dart            açılış: Firebase'i beklemeden ilk kare, prefs, sağlayıcılar
  theme.dart           renk paleti, yetişkin/Çocuk modu, açık/koyu tema
  core/                Türk hata dedektörü (tr_errors), metin normalleştirme, açılış ve kare ölçümü
  models/              Course/Section/Unit/PathNode/Exercise, sınav, okuma, kelime, plan
  data/                ilerleme, kurs yükleyici, bölümler, temalar, lig, görevler, seviye testi
  study/               günlük plan, aralıklı tekrar, hata defteri, analiz, yıllık plan
  screens/             yol, ders, hikâye, sınav, pratik, profil, kütüphane, study/ (Bugün, kartlar, rapor)
  exercises/           alıştırma türleri (select, translate, fillBlank, listen, match, speak, choice, write, shadow)
  nav/                 sekme başına Navigator, üst çubuk, tam ekran akışlar
  ui/                  çay sanatı (CustomPainter), tema görselleri, maskotlar, animasyonlar
  services/            Firebase, satın alma, sesli okuma/konuşma, bildirim, analitik
  admin/               web yönetim paneli (kurumsal)
assets/
  courses/             genel kurs, sınav yolları, meslek paketleri (JSON)
  course_index/        derleme zamanında üretilen kurs özetleri
  vocab/ reading/      kelime bankaları, okuma ve dinleme kütüphanesi
  exam_packs/ exams/   tam denemeler, soru bankaları
  plans/               YDS 52 haftalık plan verisi
  themes/              29 tema, özgün SVG nesneleri
functions/             Cloud Functions (TypeScript) ve testleri
test/                  935 test: mantık, arayüz, içerik doğrulama, performans
integration_test/      uçtan uca giriş testleri (Firebase emülatörü)
tool/                  içerik araçları (kurs özeti, not içe aktarma, YDS planı ve banka derleyicileri)
docs/                  araştırma, müfredat, planlar, tasarım, mağaza ve Firebase belgeleri
```

| Konu | Belge |
|---|---|
| YDS araştırması ve 1 yıllık plan | [yds-arastirma.md](docs/sinav/yds-arastirma.md) · [yds-1-yil.md](docs/sinav/yds-1-yil.md) |
| LGS planı | [lgs-plan.md](docs/sinav/lgs-plan.md) |
| Genel kurs araştırması ve müfredat | [genel-arastirma.md](docs/genel-arastirma.md) · [genel-mufredat.md](docs/genel-mufredat.md) |
| Tasarım ve temalar | [tasarim.md](docs/tasarim.md) · [tasarim/temalar.md](docs/tasarim/temalar.md) |
| Firebase | [firebase.md](docs/firebase.md) · [firebase-backend.md](docs/firebase-backend.md) |
| Gelir, abonelik, kurumsal | [gelir-plani.md](docs/gelir-plani.md) · [abonelik.md](docs/abonelik.md) · [kurumsal.md](docs/kurumsal.md) |
| Mağaza ve gizlilik | [magaza/](docs/magaza/) |
| İçerik kalitesi ve kaynaklar | [kalite-turu.md](docs/kalite-turu.md) · [kaynaklar.md](docs/kaynaklar.md) |
| Görsellerin kaynağı | [assets.md](docs/assets.md) |

---

## 15. Yapılacaklar ve bilinen sınırlar

**Mağazaya çıkış için gerekenler** (uygulama sahibinin adımları):
1. Google Play Console hesabı ve abonelik ürünleri.
2. Yayın imza anahtarı ve SHA değerlerinin Firebase'e eklenmesi.
3. Firebase Blaze planı ve Anthropic API anahtarı. Bunlar olmadan sohbet, yazma geri bildirimi, lig ve satın alma
   doğrulaması gerçek ortamda çalışmaz.
4. Gizlilik politikasının bir web adresinde yayınlanması.

**Bilinen sınırlar:**
- Performans emülatörde ölçüldü; gerçek telefonda ayrıca ölçülmeli.
- YDS tahmini puanı henüz gerçek sınav sonuçlarıyla karşılaştırılmadı.
- YÖKDİL soru dağılımı resmî ÖSYM belgesine değil, hazırlık kaynaklarına dayanıyor.
- Firestore veritabanı ABD bölgesinde (`nam5`).

Güncel liste: [docs/yapilacaklar.md](docs/yapilacaklar.md)

---

<div align="center">
<sub>Görseller: Çaycı Dayı ve Pofuduk uygulama sahibine aittir; ünite temaları bu proje için çizilmiştir
(<a href="docs/assets.md">docs/assets.md</a>). İçerik bu proje için özgün olarak yazılmıştır.</sub>
</div>
