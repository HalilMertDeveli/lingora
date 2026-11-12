# YDS Faz 1: içerik spesifikasyonu (yds-icerik için)

**Plan yeri:** Evre 2, H11–20 (A2 → B1). Bkz. `docs/sinav/yds-1-yil.md` §5.3.

**Amaç:** Genel kursun A1–A2 bölümünü bitiren adayı YDS'nin akademik diline taşıyacak iki paralel bölüm:
- **ys5 Kelime bankası 1:** 800 yeni kelime
- **ys6 Okuma evi 1:** 36 yoğun okuma metni

Ek olarak 1 yarım deneme yazılır: H20 tanı denemesi.

Sabit kurallar `D:\Lingora\_cikti\buyuk_plan.md` ve `_cikti/sinav_yolu_plan.md` dosyalarındadır:
- özgün içerik
- `choice` 5 şık ve Türkçe açıklama
- a/an ipucu yok
- açıklamada şık konumu anılmaz
- mevcut ID'ler değişmez

---

## 1. Dosyalar

| Dosya | Bölüm | İçerik |
|---|---|---|
| `assets/courses/exam_yds/05_kelime_bankasi_1.json` | `ys5`, index 5, `"parallel": true` | 10 ünite |
| `assets/courses/exam_yds/06_okuma_evi_1.json` | `ys6`, index 6, `"parallel": true` | 6 ünite |
| `assets/vocab/yds.json` | — | Kelime kartları, `VocabEntry` biçiminde (`assets/vocab/software.json` ile aynı şema) |

**`"parallel": true` hakkında:**
- Bu alanla bölüm, önceki bölümün sınavını beklemeden açık olur.
- Altyapıyı yds-yontem yazar (yöntem spesifikasyonu §2). Alan bilinmiyorsa yok sayılır, yani içerik PR'ı bağımsız olarak da birleşebilir.
- `test/course_content_test.dart` her bölümün son ünitesinin bir `mock` ile bitmesini ister. Bu yüzden iki bölüm de bir denemeyle biter:
  - **ys5:** son ünitede chest'ten sonra "Kelime bankası 1 denemesi" gelir: `examId: "yds"`, `size: 30`, `minutes: 35`. Sorular bölümün `choice` sorularından seçilir.
  - **ys6:** yarım deneme 1 ile biter (§4).

## 2. ys5 Kelime bankası 1 (10 ünite, 800 kelime)

### 2.1 Kelime seçimi

- **Kaynak:** NGSL (CC BY-SA 4.0; bkz. `docs/kaynaklar.md`) **referans** olarak kullanılır. Sıklık bandı yaklaşık 1.000–3.000 arasıdır. Liste dosya olarak repoya konmaz.
- **Hedef:** genel B1 kelimeleri + YDS metinlerinde sık geçen "yarı akademik" çekirdek. Örnekler: increase, decline, cause, affect, evidence, research, approximately, significant, despite.
- **Tekrar yasağı:** Şu kaynaklarda öğretilmiş kelimeler **seçilmez**:
  - genel kurs s1–s6
  - mevcut YDS yolu kelimeleri: 54 ünitenin `vocab: true` derslerindeki `match` çiftleri
  
  PR'da bunu yapan bir kontrol betiği ya da test olmalı. Çıktı: "800 kelime, 0 çakışma".
- **Kelime ailesi sayımı:** Bir kart bir **baş kelime**dir (ör. `analyse`). Ailesi (analysis, analytical, analyst) kartın `family` alanında verilir ve aileyi tek kelime sayarız.

### 2.2 Üniteler (öneri; sıra değişebilir)

| Ünite | Tema | Örnek kelimeler (yalnızca yön göstermek için) |
|---|---|---|
| ys5u1 | Süreç ve değişim fiilleri | increase, reduce, develop, improve, remain, occur |
| ys5u2 | İnsan ve toplum | population, community, generation, behaviour, attitude |
| ys5u3 | İş, para, ekonomi | income, cost, trade, demand, supply, budget |
| ys5u4 | Bilim ve araştırma (temel) | research, evidence, experiment, result, method, data |
| ys5u5 | Sağlık ve beden | disease, treatment, patient, symptom, prevent, recover |
| ys5u6 | Çevre ve doğa | climate, pollution, species, resource, protect, waste |
| ys5u7 | Düşünce ve iletişim | argue, claim, suggest, assume, opinion, describe |
| ys5u8 | Miktar, zaman, derece | approximately, majority, rate, period, gradually, recent |
| ys5u9 | Sık sıfat ve zarflar | significant, likely, available, similar, especially, rather |
| ys5u10 | Söylem ve bağlantı + temel phrasal verbs | however, therefore, although, carry out, find out, set up |

### 2.3 Ünite deseni

Her ünite 80 kelime ve şu düğümlerden oluşur:

```
lesson (vocab:true) → lesson (vocab:true) → lesson (vocab:true) → lesson (bağlamda) → test → chest
```

- **Ders 1–3:** Her birinde ~27 yeni kelime ve 10–12 alıştırma.
  - En az 2 `match` (5 çift). Bunlar kelimeleri tanıtır ve mevcut kart üretimi için de kaynaktır.
  - En az 3 `fillBlank`. Türkçe çevirili örnek cümle içinde verilir.
  - En az 4 `choice`. Bağlamda kelime sorusu, YDS kelime soru tipi ama B1 düzeyinde.
  - 1–2 `translate` (Tr → İng). Kısa cümle, hedef kelimeyi üretme. Bu derinlemesine işlemedir; bkz. araştırma §2.4.
- **Ders 4 "Bağlamda":** 10–12 alıştırma.
  - 2 kısa paragraf (80–120 kelime) cloze: `choice` + `passage`, paragraf başına 3–4 boşluk sorusu.
  - Kalanı ünitenin karışık kelime soruları.
  - Paragraflar ünitenin kelimelerinin **en az 15'ini** tekrar kullanır.
- **Test:** 15 `choice`.
  - 10 kelime sorusu
  - 3 cümle tamamlama, B1 düzeyi
  - 2 kısa paragraf sorusu
  - Kelimelerin bir kısmı **önceki ünitelerden** gelir (karışık çalışma; en az 4 soru).
- **Rehber (`guide`):** kısa tutulur (en fazla ~250 kelime).
  - Ünitenin kelime aileleri
  - 3 tipik Türk hatası, ör. *make/do*, *say/tell*, edat eşdizimi
  - "Bu kelimeleri nasıl çalışmalı" ipucu: kartlar + bağlam. Yöntem tanıtımı, araştırma §2.6'ya göre.

### 2.4 Kelime kartları (`assets/vocab/yds.json`)

Şema `VocabEntry` ile aynıdır. Fazladan bir alan eklenir: `family`. Bilinmeyen alanlar yok sayılır.

```json
{
  "id": "yd_increase",
  "word": "increase",
  "pos": "verb",
  "rank": 1,
  "topic": "ys5u1",
  "senses": [{"tr": "artmak; artırmak", "def": "to become or make something larger in amount"}],
  "examples": [
    {"en": "The number of students learning online increased sharply last year.",
     "tr": "Geçen yıl çevrim içi öğrenen öğrenci sayısı keskin biçimde arttı.",
     "context": "genel", "target": "increased"}
  ],
  "collocations": [{"phrase": "increase sharply", "answer": "increase", "tr": "keskin biçimde artmak"}],
  "family": ["increase (n)", "increasing", "increasingly"],
  "synonym": "rise",
  "tip": "Türkçedeki 'artmak' ve 'artırmak' tek fiille karşılanır: The price increased / They increased the price."
}
```

- **id:** `yd_` + kelime (boşluk yerine `_`).
- **rank:** bankadaki öğretim sırası, 1–800.
- **topic:** ünite kimliği. Uygulama bunu "konu" olarak gösterir.
- Her kartta zorunlu olanlar:
  - en az **1 örnek cümle** (Türkçe çevirili)
  - en az **1 eşdizim**
  - fiil ve isimlerde `family`
- Örnek cümleler özgün olmalı. Sözlük örnekleri kopyalanmaz.

### 2.5 Sayılar (ys5)

| | Hedef |
|---|---|
| Ünite | 10 |
| Ders | 40 (30 kelime dersi + 10 bağlam dersi) |
| Ders alıştırması | ~440 (bunun ~200'ü `choice`) |
| Test sorusu | 150 |
| Kelime kartı | 800 |
| Cloze paragrafı | 20 |

## 3. ys6 Okuma evi 1 (6 ünite, 36 metin)

### 3.1 Metin ölçütleri

| Ölçüt | Değer |
|---|---|
| Uzunluk | ys6u1–u2: 150–220 kelime (A2+); ys6u3–u6: 200–350 kelime (B1) |
| Konu | Bilim haberi, sağlık, tarih, toplum, çevre, teknoloji, biyografi. YDS'nin konu yelpazesi. |
| Bilinmeyen kelime | Genel kurs s1–s6 + ys5'te öğretilenlerin dışında en fazla **%5**. Özel adlar hariç. |
| Geri dönüşüm | Her metin ys5'ten en az **8 kelime** kullanır. Hangi kelimeler olduğu metnin `description` alanında yazılır. |
| Cümle | Ortalama 15–22 kelime. Her metinde en az 2 edilgen ve 2 yan cümle bulunur, ama aşırı iç içe yapı olmaz. |
| Kaynak | Özgün. Olgular açık kaynaklardan alınabilir: OpenStax CC BY, NASA/NIH kamu malı. Uyarlama yapılırsa `docs/kaynaklar.md` kayıt tablosuna satır eklenir. |

### 3.2 Ünite deseni

```
lesson (2 metin) → lesson (2 metin) → lesson (2 metin) → lesson (cümle çözümleme) → test → chest
```

**Metin dersleri (Ders 1–3):** her metin için 4 `choice`. Hepsinde aynı `passage` kullanılır. Soru dağılımı:

| Soru | Tür |
|---|---|
| 1 | Ana fikir / amaç |
| 2 | Ayrıntı |
| 3 | Çıkarım ya da gönderim: "it/this/they neyi gösterir" |
| 4 | Kelime: bağlamda anlam ya da yazarın tutumu |

Her derse 2 ek alıştırma eklenir: metindeki kelimelerle `match` ya da `fillBlank`.

**Ders 4 "Cümle çözümleme":** ünitenin metinlerinden seçilmiş 8–10 uzun cümle üzerinde çalışılır.
- "Ana fiil hangisi?"
- "Bu cümlenin en iyi Türkçesi hangisi?" (YDS çeviri tipi)
- "Altı çizili *which* neyi niteler?"

Bu ders, Türk adayların SOV → SVO zorluğunu hedefler (araştırma §1.6).

**Test:**
- 2 yeni metin × 4 soru + 6 cümle düzeyi soru (çeviri, cümle tamamlama) = 14–16 soru.
- Bu iki test metni de okuma sayacına girer, yani ünite başına 8 metin olur.

**Rehber:** ünitenin okuma stratejisi:
- u1: önce soruyu oku
- u2: ana fikir paragrafın neresinde
- u3: gönderim zincirleri
- u4: bağlaçla yön değişimi (however, in contrast)
- u5: bilinmeyen kelimeyi bağlamdan tahmin
- u6: zamanlı okuma, metin başına 10 dk

### 3.3 Sayılar (ys6)

| | Hedef |
|---|---|
| Ünite | 6 |
| Metin | 36 ders metni + 12 test metni = **48** |
| Ders alıştırması | ~200 |
| Test sorusu | ~90 |

## 4. Yarım deneme 1 (tanı)

- ys6'nın son ünitesinin sonuna, chest'ten sonra bir `mock` düğümü eklenir: `examId: "yds"`, `size: 40`, `minutes: 90`.
- Bu düğümün **kendi 40 sorusu** olmalıdır. Paket olmadan rastgele seçim yerine sabit bir tanı denemesi isteriz.
- Altyapı mock düğümünde `exercises` alanını desteklemiyorsa, test düğümündeki gibi `exercises` taşımasını yöntem ekibinden isteyin. Bkz. yöntem spesifikasyonu §2.2.
- **Dağılım** (yarım YDS):

| Tür | Soru |
|---|---|
| Kelime | 3 |
| Dilbilgisi | 5 |
| Cloze (1 metin) | 5 |
| Cümle tamamlama | 5 |
| Çeviri | 3 |
| Okuma (2 metin) | 8 |
| Diyalog | 3 |
| Restatement | 2 |
| Paragraf tamamlama | 2 |
| Anlam bütünlüğü | 4 |

- **Düzey:** B1–B1+. Bu bir tanı denemesidir; gerçek YDS'den bir basamak kolaydır. Açıklamada bunu söyleyin.

## 5. Kabul ölçütleri (inceleme listem)

PR'ınızı şu listeyle inceleyeceğim:

1. `test/` içindeki içerik testleri geçiyor (course_content_test, content_quality_test).
2. Sayılar §2.5, §3.3 ve §4'teki hedeflerin en az %90'ı. PR açıklamasında tablo var.
3. **Kelime çakışma raporu:** 800 kelimenin genel kurs s1–s6 ve mevcut YDS yolu ile çakışması 0. Betik ya da test PR'da.
4. **Bilinmeyen kelime oranı:** her okuma metni için ≤ %5 raporu. Basit bir betik yeter: metin kelimeleri − (genel kurs + ys5 + çok sık 1.000 işlev kelimesi).
5. **Geri dönüşüm:** her metinde ≥ 8 ys5 kelimesi; her ys5 kelimesi ys5/ys6 içinde en az 2 kez bağlamda geçiyor. Kapsam raporu PR'da.
6. **Cevap anahtarı bağımsız çözümle kontrol edildi** (ayrı bir ajan ya da betik çözümü; uyuşmazlık 0).
7. `docs/kaynaklar.md`'ye uyarlama kaydı (varsa).
8. Ekran görüntüleri `D:\Lingora\_cikti\yds-icerik\` klasöründe:
   - kelime dersi
   - okuma dersi
   - kelime kartı
   - yarım deneme sonucu

## 6. Sonraki fazlar (bilgi için)

- **F2 (Evre 3):** Kelime bankası 2 (1.200 kelime: NAWL + orta sıklık), Okuma evi 2 (60 akademik + 60 bol okuma metni), 4 yarım deneme. Ek iş: mevcut 2.630 YDS kelimesinin `yds.json` kartlarına dönüştürülmesi.
- **F3–F4:** `yds-1-yil.md` §5.3.

Belirsizlikte bana yazın (yds-arastirma). Karar gerektirmeyen ayrıntılarda kendi yargınızı kullanın ve PR açıklamasında belirtin.
