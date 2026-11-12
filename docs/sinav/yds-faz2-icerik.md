# YDS Faz 2: içerik spesifikasyonu (yds-icerik için)

**Plan yeri:** Evre 3, H21–34 (B1 → B2 akademik). Bkz. `docs/sinav/yds-1-yil.md` §5.3.

**Amaç:** Ana yolda adayı ys1 dilbilgisi ve ys2 kelime üniteleriyle B2'ye taşırken, paralel bölümlerde akademik kelimeyi ve okuma hacmini büyütmek. Bu evrenin sonunda aday ~5.000 kelime ailesi tanır ve ilk tam denemeye girer (H30).

**F1'den süren kurallar:**
- `parallel: true`
- ünite deseni
- `qtype` her `choice`'ta
- açıklamada en az 3 çeldiriciyi metinle anma
- kelime çakışma, bant ve kapsam raporları
- kör cevap anahtarı kontrolü

F1 inceleme notları da geçerlidir:
- "Ana fiil hangisi" sorularında çeldiriciler fiil benzeri biçimler olmalı: yan cümle fiili, participle, yardımcı fiil.
- Anlam bütünlüğü sorusunda aykırı cümle **aynı konunun başka bir yönü** olmalı, konu sıçraması olmamalı.

İş üç PR'a bölünür: F2a, F2b, F2c. Her biri kendi başına birleşebilir.

---

## F2a. ys7 Kelime bankası 2 (15 ünite, 1.200 kelime)

**Dosyalar:**
- `assets/courses/exam_yds/07_kelime_bankasi_2.json`: `ys7`, index 7, `parallel: true`, cefr "B1+–B2"
- `assets/vocab/yds.json`: kartlar aynı dosyaya eklenir; `rank` 801–2000

### Kelime havuzu ve bant hedefi

| Kaynak | Pay | Not |
|---|---|---|
| NAWL (CC BY-SA, yalnızca referans) | ≥ %40 | Akademik çekirdek: hypothesis, framework, derive, empirical, subsequent… |
| NGSL 1001–2809'dan F1'de seçilmemiş kalanlar | ≥ %35 | |
| Orta sıklık (NGSL dışı, sınav metinlerinde sık) ve çok kelimeli kalıplar | ≤ %25 | Çok kelimeli kalıplar ayrı satırda raporlanır, ≤ 100 |

**Çakışma yasağı:** genel kurs s1–s8, ys1–ys4, ys5 ve F1 kartları ile çakışma 0 olmalı.

**Bant raporu:** NAWL / NGSL bandı / dışı dağılımı. NAWL listesi repoya girmez, `bands.js` gibi dışarıdan okunur.

### Üniteler

Tema ve hedef dağılımı (öneri):

| Ünite | Tema | Yön |
|---|---|---|
| ys7u1 | Araştırma süreci | hypothesis, sample, conduct, data collection |
| ys7u2 | Kanıt ve iddia | claim, support, contradict, evidence-based |
| ys7u3 | Neden–sonuç | trigger, contribute to, consequence, stem from |
| ys7u4 | Değişim ve eğilim | fluctuate, steady, decline, surge |
| ys7u5 | Toplum ve politika | policy, welfare, inequality, implement |
| ys7u6 | Ekonomi ve kalkınma | growth, investment, sustainable, sector |
| ys7u7 | Teknoloji ve yenilik | innovation, device, automate, adopt |
| ys7u8 | Sağlık bilimi | chronic, diagnosis, clinical, side effect |
| ys7u9 | Çevre ve enerji | renewable, emission, biodiversity, depletion |
| ys7u10 | Tarih ve kültür | ancient, civilisation, heritage, empire |
| ys7u11 | Psikoloji ve eğitim | cognitive, motivation, perception, acquire |
| ys7u12 | Hukuk ve etik | regulation, consent, legitimate, violate |
| ys7u13 | İsimleştirme | -tion, -ment, -ity, -ance: fiil → isim aileleri |
| ys7u14 | Temkin ve tutum | likely, arguably, tend to, it is suggested that |
| ys7u15 | Akademik phrasal verbs ve kalıplar | account for, give rise to, in terms of, with regard to |

### Ünite deseni

ys5 ile aynıdır:
- 3 kelime dersi + 1 "Bağlamda" dersi + 15 soruluk test + chest
- son ünite chest'ten sonra `mock` ile biter (size 30, minutes 35)

**Düzey farkı:**
- Bağlamda dersindeki cloze paragrafları 120–160 kelime, B2 düzeyinde olur.
- Test sorularının en az 3'ü YDS kelime soru tipi (tek cümle, 5 akademik şık) ve gerçek sınav zorluğundadır.

### Sayılar

| | Hedef |
|---|---|
| Ünite | 15 |
| Ders alıştırması | ~700 |
| Test sorusu | 225 |
| Kart | 1.200 |
| Cloze paragrafı | ≥ 30 |

## F2b. ys8 Okuma evi 2 (10 ünite, 80 akademik metin) + bol okuma 1

### Yoğun okuma: `assets/courses/exam_yds/08_okuma_evi_2.json`

Bölüm `ys8`, index 8, `parallel: true`, cefr "B2". Deseni ys6 ile aynıdır:
- 3 metin dersi (2 metin, 4 soru, 2 ek alıştırma)
- cümle çözümleme dersi
- test (2 yeni metin + 6 cümle sorusu)
- chest

| Ölçüt | Değer |
|---|---|
| Uzunluk | 250–320 kelime (gerçek YDS uzunluğu) |
| Alan | 10 ünitenin 3'ü fen, 3'ü sağlık, 3'ü sosyal, 1'i karışık. `reading.field` doldurulur. |
| Bilinmeyen kelime | ≤ %5 (genel kurs + ys5 + ys7 + mevcut YDS kelimeleri dışında) |
| Geri dönüşüm | Her metinde ≥ 10 ys7 kelimesi, ≥ 3 ys5 kelimesi (`reading.ys5`, `reading.ys7`) |
| Yapı | Her metinde ≥ 3 edilgen, ≥ 2 yan cümle, ≥ 2 isimleştirme |
| Soru dağılımı | Gerçek YDS okuma soru türlerine yakın: ana fikir/başlık, ayrıntı, çıkarım, gönderim, yazarın tutumu/amacı, bağlamda kelime. Her metinde en az 1 çıkarım ya da tutum sorusu. |
| Ünite stratejisi (Rehber) | u1 başlık sorusu; u2 çıkarım; u3 yazarın tutumu; u4 karşılaştırma metinleri; u5 sayı ve istatistik içeren metin; u6 tanım ve örnek; u7 problem–çözüm; u8 neden–sonuç zinciri; u9 metin başına 12 dk zamanlı; u10 karışık zamanlı |

Son ünite chest'ten sonra **yarım deneme 5** ile biter (plandaki H32 yarım denemesi; düğüm id `ys8u10m`): 40 soru / 90 dk, F1 §4 dağılımı, gerçek YDS düzeyi (B2).

### Bol okuma: `assets/reading/yds_bol_okuma_1.json`

Mevcut okuma kütüphanesi biçimi kullanılır (`ReadingStory`: id, level, emoji, title, titleTr, text, glosses, questions).

| Ölçüt | Değer |
|---|---|
| Metin | 60 |
| Düzey | B1 (40 metin) ve B1+ (20 metin). Adayın seviyesinin **bir tık altı**. |
| Uzunluk | 400–700 kelime |
| Tür | Anlatı, biyografi, bilim öyküsü, gezi, popüler bilim. Keyifle okunacak metinler, sınav metni değil. |
| Bilinmeyen kelime | ≤ %2. Kalanlar `glosses` ile verilir. |
| Soru | 2 anlama sorusu (`questions`, 4–5 şık). Sınav sorusu değil. |
| id | `yb_<slug>` |

**Altyapı bağımlılığı (yds-yontem'e iletildi):**
- okuma kütüphanesinin birden çok dosya okuması
- `B1+`/`B2` düzeyleri
- okunan kelime sayacı

Bunlar gelene kadar dosya yüklenmez; ama PR'ın bir JSON şema testi olmalıdır.

### Sayılar (F2b)

| | Hedef |
|---|---|
| ys8 ünite | 10 |
| Yoğun metin | 60 ders + 20 test = 80 |
| ys8 alıştırma | ~400 ders + 150 test |
| Yarım deneme | 1 (40 soru) |
| Bol okuma metni | 60 (~33.000 kelime) |

## F2c. Tam denemeler ve mevcut YDS kelimelerinin kartları

### Tam deneme yds_m9 ve yds_m10

- `assets/exam_packs/yds_full.json` dosyasına eklenir.
- Biçim, puanlama ve dağılım mevcut m1–m8 ile aynıdır: 80 soru / 180 dk.
- Plandaki yerleri: H30 ve H34.
- Zorluk: m1–m8 ortalaması. Yeni metinler F2b'deki metinlerden **farklı** olmalıdır; deneme, yolda görülmemiş metinle ölçmelidir.
- Her soruda `qtype` bulunur.

### Mevcut YDS kelime kartları

- Yoldaki ~2.630 kelime/kalıp şu an yalnızca `ydm_` köprü kartı olarak var: örneksiz ve eşdizimsiz.
- Bunlar `assets/vocab/yds.json` biçiminde tam karta dönüştürülür.
- **Anahtar uyumu:** Mevcut `ydm_<kelime>` ilerleme anahtarları korunmalıdır. Kart id'si `ydm_<kelime>` olarak kalır, yalnızca içerik zenginleşir. Bu konuyu yds-yontem ile netleştirin; bridge kartın yerini aynı id'li tam kart almalıdır.
- `rank` 2001+. `topic` mevcut ünite id'si (ys1u1…).
- İsterseniz F2c'yi ikiye bölün: önce ys1+ys2 kelimeleri, sonra ys3+ys4.

### Sayılar (F2c)

| | Hedef |
|---|---|
| Tam deneme | 2 (160 soru, 10 yeni okuma metni + cloze metinleri) |
| Zenginleştirilmiş kart | ~2.600 |

---

## Plan bağlantısı

`assets/plans/yds_1_yil.json` içindeki `parallelUnitIds` alanı H21–34 için ys7 ve ys8 ünitelerini taşır:
- ys7: haftada 1 ünite, H34'te 2 ünite
- ys8: H22–32 arası 10 ünite (son ünitenin denemesi H32 yarım denemesidir)

## Kabul ölçütleri

F1 §5 maddeleri, ayrıca:
1. Bant raporu (NAWL payı ≥ %40) ve çakışma raporu 0.
2. ys8 metinlerinde zorluk raporu:
   - metin başı kelime sayısı
   - bilinmeyen kelime %
   - ortalama cümle uzunluğu (hedef 18–26)
   - edilgen ve isimleştirme sayısı
3. Bol okuma metinlerinde bilinmeyen ≤ %2 raporu.
4. Tam denemelerde dağılım tablosu ve tür başına zorluk notu.
5. Kart dönüşümünde id'lerin değişmediğini gösteren test.

Belirsizlikte bana yazın (yds-arastirma).
