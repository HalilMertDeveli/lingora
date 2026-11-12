# YDS Faz 4: içerik spesifikasyonu (yds-icerik için)

**Plan yeri:** Evre 5, H43–52 (deneme kampı, B2+). Bkz. `docs/sinav/yds-1-yil.md` §5.3.

**Amaç:**
- 52 haftalık programın son 10 haftasını içerikle doldurmak.
- Ana yolda aday ys4 ünitelerini çalışır ve haftada 1–2 tam deneme çözer.
- Paralel bölüm, kelimeyi 6.500 aileye taşır.
- Bol okuma son sete ulaşır.
- YÖKDİL hedefleyen aday son haftalarda **YÖKDİL biçiminde** deneme çözer.

**F1–F3'ten süren kurallar:**
- **Gönderilmiş bölümlere dokunulmaz.** Düğüm ekleme ve ID değiştirme yok. `yds_shipped_sections_test` fikstürü ys11'e kadar donmuş kalır.
- **Dosya sırası:** `NN == section.index`, ardışık. Doğrulayıcı gevşetilmez.
- `parallel: true`, her `choice`'ta `qtype`, açıklamada en az 3 çeldiriciyi metinle anma.
- Çakışma 0 (6 kelimelik kalıplar dahil, istisna yok). Bant ve kapsam raporları.
- Kör çözüm ve uyuşmazlıkların tek tek gerekçesi.
- Konu taraması (`overlap.js`, `topic_scan.js`) tüm uygulamaya karşı yapılır.
- Kart `rank` değeri mevcut en yüksek değerden (4.086) devam eder. Eski kartların `rank`'i değişmez.

İş üç PR'a bölünür: F4a, F4b, F4c. Birleştirme sırası serbesttir. Yalnızca F4a dosya sırası nedeniyle `12_*` olarak gelir; ys11 zaten gönderildi.

---

## F4a. ys12 Kelime bankası 4 (8 ünite, 900 kelime)

**Dosyalar:**
- `assets/courses/exam_yds/12_kelime_bankasi_4.json`: `ys12`, index 12, `parallel: true`, cefr "B2–C1"
- kartlar `assets/vocab/yds.json` içinde, `rank` 4.087–4.986

### Havuz

| Kaynak | Pay | Not |
|---|---|---|
| Orta–ileri sıklık (wordfreq Zipf 2,8–4,0), YDS/YÖKDİL metinlerinde görülen genel-akademik kelimeler | ≥ %60 | Ör. exacerbate, ubiquitous, mitigate, detrimental, notwithstanding |
| Sınavda sık çıkan çeldirici aileleri ve ileri eşdizimler | ≤ %20 | Ör. "adverse/averse", "pose a threat", "bear the brunt of" |
| Alan terimleri ve çok kelimeli kalıplar (≤ 120) | ≤ %20 | |

### Üniteler

Ünite başına ~112 kelime. Desen ys9 ile aynıdır: 4 kelime dersi + Bağlamda dersi + 15 soruluk test + chest. Son ünite chest'ten sonra mock ile biter (size 30, minutes 35).

| Ünite | Tema | Hafta |
|---|---|---|
| ys12u1 | Neden–sonuç ve etki fiilleri II (exacerbate, precipitate, curb…) | H43 |
| ys12u2 | Değerlendirme ve eleştiri (dubious, compelling, flawed…) | H44 |
| ys12u3 | Değişim ve süreç zarfları (incrementally, abruptly, invariably…) | H45 |
| ys12u4 | Fen ve teknoloji III | H46 |
| ys12u5 | Sağlık ve yaşam bilimleri III | H47 |
| ys12u6 | Toplum, hukuk ve ekonomi III | H48 |
| ys12u7 | İleri eşdizimler ve deyimsel kalıplar | H49 |
| ys12u8 | Sınavda karışan kelime aileleri (adverse/averse, eminent/imminent, discrete/discreet…) | H50 |

### Sayılar (F4a)

| | Hedef |
|---|---|
| Ünite | 8 |
| Ders alıştırması | ~520 |
| Test sorusu | 120 |
| Kart | 900 |
| Cloze paragrafı | ≥ 16 (B2–C1, 150–190 kelime) |

## F4b. Bol okuma 3: `assets/reading/yds_bol_okuma_3.json`

| Ölçüt | Değer |
|---|---|
| Metin | 110 |
| Düzey | B2 (110). Uygulamanın düzey listesinde C1 yoktur; B2 olarak işaretlenir. |
| Uzunluk | 600–900 kelime |
| Tür | 40 popüler bilim ve sağlık, 30 toplum ve tarih, 20 biyografi, 20 anlatı ve deneme. Son haftalarda yorgunluğu azaltmak için keyifle okunacak metinler. |
| Bilinmeyen kelime | glosslardan sonra ≤ %2 |
| Geri dönüşüm | Her metinde ≥ 8 ys9 ve ys12 kelimesi |
| Soru | 2 anlama sorusu |
| Biçim | ReadingStory şeması, id `yb_` |

Toplam ~80.000 kelime. Bol okuma 1–3 birlikte ~170.000 kelime eder. Planın okuma hedefinin kalanını hızlı yeniden okuma (araştırma §2.5) karşılar.

## F4c. Tam denemeler: YDS m15–m20 ve YÖKDİL m1–m3

### YDS biçimi: `yds_m15`–`yds_m20` (6 deneme)

- `assets/exam_packs/yds_full.json` dosyasına eklenir. Biçim m11–m14 ile aynıdır.
- Plandaki yerleri: H43, H48, H49, H50, H51, H52.
- **Zorluk:** m15–m18 gerçek sınav düzeyindedir. m19–m20 biraz üstündedir: daha uzun cümle, daha yoğun okuma. Son prova adayı sınavdan biraz zor bir denemeyle karşılaştırmalıdır.

### YÖKDİL biçimi: `yokdil_m1`–`yokdil_m3` (3 deneme)

- Aynı pakete eklenir, ama **YÖKDİL soru dağılımıyla** (araştırma §1.3; bölüm kimlikleri `yokdil_*`):

  | Tür | Soru |
  |---|---|
  | Okuma | 15 |
  | Dilbilgisi | 14 |
  | Çeviri (6 + 6) | 12 |
  | Cümle tamamlama | 11 |
  | Cloze | 10 |
  | Kelime | 6 |
  | Paragraf tamamlama | 6 |
  | Anlam bütünlüğü | 6 |
  | **Toplam** | **80** (180 dk) |

  Diyalog ve restatement yoktur.
- **Ağırlıklar:** m1 fen, m2 sağlık, m3 sosyal. Okuma, cloze, paragraf ve çeviri metinlerinin en az %70'i o alandan gelir.
- **Plan bağlantısı:** `yds_1_yil.json` içinde `yds_m16`, `yds_m18` ve `yds_m19` kayıtları `"yokdil": "yokdil_m1|m2|m3"` alanını taşır. YÖKDİL hedefli öğrenci (planın `exam` alanı `yokdil_*`) bu haftalarda YDS denemesi yerine bunları çözer. Bu yönlendirmeyi yds-yontem yapar.
- **`qtype`:** mevcut değerler kullanılır; yeni tür yoktur. Sınav türü bölüm kimliğinden okunur.
- **Paket açıklaması:** "14 YDS + 3 YÖKDİL denemesi" diye güncellenir. YÖKDİL denemelerinin başlığında alan yazar, ör. "YÖKDİL Fen denemesi 1".

### Sayılar (F4c)

| | Hedef |
|---|---|
| YDS denemesi | 6 × 80 = 480 soru |
| YÖKDİL denemesi | 3 × 80 = 240 soru |
| Konu taraması | 0 çakışma |

---

## Plan bağlantısı (bu PR'da)

`assets/plans/yds_1_yil.json`:
- **H43–50 `parallelUnitIds`:** `ys12u1`–`ys12u8` (haftada bir ünite).
- **`mocks`:** `yds_m16`, `yds_m18` ve `yds_m19` kayıtlarında `yokdil` alanı.

## 52. haftadan sonra: dersler bitmesin (yds-yontem notu)

Program 52 haftada biter, ama uygulama kullanıcıyı boşta bırakmamalıdır. H52'den sonra "Bugün" planı **sürdürme moduna** geçer. İçerik ekibi için yeni iş çıkarmaz; mevcut içeriği döndürür:

- **Tekrar kartları:** FSRS ya da Leitner aralıkları sürer. Yeni kart yoksa kalan bankalardan rastgele yeni kart.
- **Haftalık deneme:** henüz çözülmemiş bir tam deneme. Hepsi çözüldüyse en eski denemenin yeniden çözümü. Tahmini puana girmez (ilk deneme kuralı).
- **Okuma:** okunmamış bol okuma metni, yoksa hızlı yeniden okuma.
- **Soru:** hata defteri + tüm bölümlerden karışık set.

## Kabul ölçütleri

Önceki fazların ölçütleri geçerlidir. Bunlara ek olarak:
1. F4a bant raporu: orta–ileri sıklık ≥ %60.
2. YÖKDİL denemelerinde bölüm dağılımı 15/14/12/11/10/6/6/6, 180 dk. Diyalog ve restatement 0.
3. `yds_plan_mocks_test` genişletilir: planın `yokdil` alanındaki her ID, gönderildiğinde pakette 80 soru / 180 dk olarak bulunmalıdır.
4. `yds_shipped_sections_test` fikstürü ys11'i kapsar. ys12 gönderildikten sonra, bir sonraki fazda ys12 de dondurulur.

Belirsizlikte bana yazın (yds-arastirma).
