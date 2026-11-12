# YDS Faz 3: içerik spesifikasyonu (yds-icerik için)

**Plan yeri:** Evre 4, H35–42 (sınav stratejisi, B2). Bkz. `docs/sinav/yds-1-yil.md` §5.3.

**Amaç:**
- Ana yolda aday ys3 soru tipi ünitelerini çalışır.
- Paralel bölümler bu evrede iki iş görür:
  - kelimeyi 5.700 aileye taşımak
  - okumayı YÖKDİL alanlarına göre derinleştirmek
- Evre boyunca haftada bir tam deneme (m11–m14) ve araya yarım denemeler girer.
- F2'de düğümü olmayan yarım denemeler 2–4 de bu fazda yazılır.

**F1–F2'den süren kurallar:**
- `parallel: true`
- `qtype` her `choice`'ta
- açıklamada en az 3 çeldiriciyi metinle anma
- çakışma (6 kelimeye kadar kalıplar dahil), bant ve kapsam raporları
- kör cevap anahtarı
- metin konu çakışması taraması
- fiil benzeri "ana fiil" çeldiricileri
- aynı konuda kalan aykırı cümle

İş dört PR'a bölünür: F3a, F3b, F3c, F3d. Her biri kendi başına birleşebilir.

---

## F3a. ys9 Kelime bankası 3 (12 ünite, 1.300 kelime)

**Dosyalar:**
- `assets/courses/exam_yds/09_kelime_bankasi_3.json`: `ys9`, index 9, `parallel: true`, cefr "B2"
- kartlar `assets/vocab/yds.json` dosyasına eklenir; `rank` mevcut en yüksek değerden devam eder

### Havuz

| Kaynak | Pay | Not |
|---|---|---|
| NAWL'ın F2'de kullanılmayan kalanı | ≥ %40 | |
| Orta sıklık bandı (NGSL dışı, ~3k–6k), YDS/YÖKDİL metinlerinde sık geçen genel-akademik kelimeler | ≥ %35 | Ör. undermine, unprecedented, inherent, outweigh |
| YÖKDİL alan terimleri ve çok kelimeli kalıplar | ≤ %25 | Kalıplar ≤ 100 |

Çakışma: genel kurs s1–s8, ys1–ys8 ve tüm `yd_`/`ydm_` kartları ile çakışma 0 olmalı. İstisna listesi yeni bankalarda yoktur.

### Üniteler

Ünite başına ~108 kelime. Kelime derslerinin sayısı 3'ten 4'e çıkar; ünite 4 kelime dersi + 1 Bağlamda dersinden oluşur.

| Ünite | Tema |
|---|---|
| ys9u1 | Bilimsel yöntem II: deney tasarımı, değişkenler, ölçüm hatası |
| ys9u2 | Biyoloji ve genetik |
| ys9u3 | Fizik, kimya ve malzeme |
| ys9u4 | Tıp ve klinik araştırma |
| ys9u5 | Halk sağlığı ve beslenme |
| ys9u6 | Sosyoloji ve demografi |
| ys9u7 | Siyaset bilimi ve uluslararası ilişkiler |
| ys9u8 | Ekonomi ve finans II |
| ys9u9 | Dil, iletişim ve medya |
| ys9u10 | Tutum ve değerlendirme sıfatları (yazarın tutumu soruları için: dismissive, ambivalent, cautious…) |
| ys9u11 | Söylem ve bağlantı II: paragraf tamamlama ve anlam bütünlüğü sorularındaki geçiş ifadeleri |
| ys9u12 | Karıştırılan akademik çiftler (affect/effect, imply/infer, comprise/compose…) |

**Son ünite:** chest'ten sonra `mock` gelir (size 30, minutes 35).

### Sayılar (F3a)

| | Hedef |
|---|---|
| Ünite | 12 |
| Ders alıştırması | ~720 |
| Test sorusu | 180 |
| Kart | 1.300 |
| Cloze paragrafı | ≥ 24 (B2, 140–180 kelime) |

## F3b. ys10 Okuma evi 3 (8 ünite, alan metinleri) + yarım denemeler 6–8

**Dosya:** `assets/courses/exam_yds/10_okuma_evi_3.json`: `ys10`, index 10, `parallel: true`, cefr "B2". Desen ys8 ile aynıdır.

| Ölçüt | Değer |
|---|---|
| Metin | 8 ünite × (6 ders + 2 test) = **64** |
| Uzunluk | 280–340 kelime |
| Alan | u1–u2 fen, u3–u4 sağlık, u5–u6 sosyal, u7–u8 karışık. `reading.field` doldurulur. |
| Dil | Gerçek YÖKDİL alan metni düzeyi: terim yoğunluğu artar, cümle ortalaması 22–28, isimleştirme ve edilgen belirgin |
| Bilinmeyen kelime | ≤ %5 (ys9 dahil tüm öğretilmiş kelimeler dışında) |
| Geri dönüşüm | Her metinde ≥ 10 ys9 kelimesi ve ≥ 5 ys7 kelimesi |
| Soru | Her metinde 4 soru; en az 1 çıkarım ya da tutum sorusu, en az 1 "paragraf tamamlama" ya da "aykırı cümle" türü soru |
| Ünite stratejisi (Rehber) | u1 terim yoğun metinde ana fikir; u2 deney anlatımı; u3 klinik çalışma özeti; u4 risk ve oran ifadeleri; u5 kuram karşılaştırma; u6 tarihsel anlatı; u7 YÖKDİL tarzı uzun cümle çevirisi; u8 metin başına 10 dk zamanlı |

**Yarım denemeler** (gerçek YDS düzeyi, F1 §4 dağılımı, 40 soru / 90 dk):

| Düğüm | Plandaki deneme | Hafta |
|---|---|---|
| `ys10u3m` | Yarım deneme 6 | H37 |
| `ys10u5m` | Yarım deneme 7 | H39 |
| `ys10u7m` | Yarım deneme 8 | H41 |

Bu düğümler ünitenin chest'inden sonra gelir. Sınav yolu kuralına göre her ünite mock ile bitebilir. Bölümün son ünitesi (ys10u8) bölüm denemesiyle biter: size 30, minutes 45.

Başlıklar plandaki adlarla aynı olmalıdır: "Yarım deneme 6/7/8".

### Bol okuma 2: `assets/reading/yds_bol_okuma_2.json`

| Ölçüt | Değer |
|---|---|
| Metin | 80 |
| Düzey | B1+ (40) ve B2 (40) |
| Uzunluk | 500–800 kelime |
| Bilinmeyen kelime | glosslardan sonra ≤ %2 |
| Biçim | F2 ile aynı ReadingStory şeması, id `yb_` |

## F3c. Tam denemeler m11–m14

- `assets/exam_packs/yds_full.json` dosyasına eklenir. Biçim m9–m10 ile aynıdır: `qtype`, 16'şar doğru harf.
- Plandaki yerler: H36, H38, H40, H42.
- **YÖKDİL çeşitlemesi:** m13 ve m14'ün okuma metinlerinin yarısı YÖKDİL alan metni (fen/sağlık/sosyal) olsun. Soru dağılımı YDS olarak kalır; YÖKDİL dağılımındaki denemeler F4'te gelir.
- Metinler yoldaki ve bol okumadaki hiçbir metinle konu bakımından çakışmamalıdır. Tarama raporu PR'da bulunur.

## F3d. Yarım denemeler 2–4 (F2'de eksik kalanlar)

- Plan H22, H24 ve H27'de yarım deneme istiyor, ama düğümleri yok.
- Bunlar ys8'in ilgili ünitelerine **yeni bir mock düğümü olarak** eklenir. Ünitenin mevcut düğümlerine ve ID'lerine dokunulmaz, yalnızca chest'ten sonra eklenir:

| Düğüm | Plandaki deneme | Hafta |
|---|---|---|
| `ys8u1h` | Yarım deneme 2 | H22 |
| `ys8u3h` | Yarım deneme 3 | H24 |
| `ys8u5h` | Yarım deneme 4 | H27 |

- Düzey B1+–B2 olmalı; Evre 3'ün ortasıdır. Dağılım F1 §4 ile aynıdır.
- Not: Denemeler yolu kilitlemez. Bölüm ilerleme yüzdesi yeni düğüm nedeniyle biraz düşebilir; bu kabul edilmiştir.

---

## Plan bağlantısı

`assets/plans/yds_1_yil.json` bu PR'da güncellendi:
- **H35–42 `parallelUnitIds`:** ys9 haftada 1–2 ünite, ys10 haftada 1 ünite.
- **`mocks` alanına eklenen yarım deneme düğümleri:** H22 `ys8u1h`, H24 `ys8u3h`, H27 `ys8u5h`, H37 `ys10u3m`, H39 `ys10u5m`, H41 `ys10u7m`.

Düğüm ID'leri bu tabloyla aynı olmalıdır.

## Kabul ölçütleri

F1 §5 ve F2 kabul ölçütleri geçerlidir. Bunlara ek olarak:
1. Bant raporu: NAWL ≥ %40, orta sıklık ≥ %35.
2. ys10 zorluk raporu: cümle ortalaması 22–28, terim yoğunluğu.
3. Yarım ve tam denemelerde düğüm ve deneme ID'lerinin plandaki `mocks` ile eşleştiğini gösteren test.
4. m11–m14 için konu çakışması 0.

Belirsizlikte bana yazın (yds-arastirma).
