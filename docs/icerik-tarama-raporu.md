# İçerik tarama raporu (İngilizce yazım, dil bilgisi, noktalama)

Bu rapor `tool/icerik_tarama.dart` tarafından üretildi. **Yalnızca rapordur: hiçbir içerik dosyası değiştirilmedi.** Bulgular otomatik olduğu için her satır bir *şüphedir*; düzeltmeden önce cümleyi bağlamında okuyun.

## Nasıl çalıştırılır

```
dart run tool/icerik_tarama.dart                  # yalnızca yerel kurallar
dart run tool/icerik_tarama.dart --ai             # + YZ kontrolü (Anthropic API, varsayılan 300 cümle)
dart run tool/icerik_tarama.dart --ai --ai-limit 120 --limit 500 --out docs/icerik-tarama-raporu.md
```

- **Taranan:** 54 dosya, 53562 İngilizce metin alanı (46786 benzersiz, yaklaşık 74276 cümle/öbek).
- **Sözlük:** sistem sözlüğü yok; içeriğin kendisinden (22732 farklı kelime) ve kelime listelerinden (`assets/vocab`, sözlük alanları, glossary anahtarları; 13342 kelime) kuruldu. Az geçen (≤2), listelerde olmayan, özel isim olmayan ve sık bir kelimeye tek harf uzaklıkta olan kelimeler işaretlenir.
- **Atlananlar:** Türkçe alanlar (`tr`, `translation`, `explanation`, `why`, `guide`, …) ve Türkçe karakter/kelime oranı yüksek metinler; çoktan seçmeli **çeldiriciler** (yalnızca doğru şık `options[answer]` denetlenir), kelime bankaları (`tokens`), eşleştirme çiftleri, `mistakes.wrong` gibi bilerek yanlış örnekler. Boşluklar (`___`, `----`) tek boşluklu ve cevabı bilinen alıştırmalarda doğru cevapla doldurulur, aksi halde `BLANK` kelimesi olarak sayılır.
- Aynı metin birden çok yerde geçiyorsa (ör. her soruda tekrarlanan okuma parçası) bir kez denetlenir; tabloda ilk geçtiği yer gösterilir.
- **YZ kontrolü (`--ai`, model `claude-haiku-5-5`):** 300 cümle 5 istekte gönderildi; 0 bulgu (kaynak **YZ**). Öncelik: yerel kuralların orta/düşük işaretledikleri, sonra her dosyadan en uzun cümleler.

## Ayarlama notları (yanlış alarm azaltma)

İlk çalıştırmalarda elle incelenen ~150 şüphenin neredeyse tamamı yanlış alarmdı; kurallar buna göre daraltıldı:

- **Yazım (sözlük):** yalnızca klasik yazım kalıpları (komşu harf yer değiştirmesi, çift harfin teklenmesi/tek harfin çiftlenmesi) ve ilk harf dışındaki düzenlemeler işaretlenir. Harf değiştirme/ekleme (wafers→waters, tusk→task, fallow→follow, preach→reach) içerikte hep nadir ama gerçek kelimelerdi; bunlar YZ kontrolüne bırakıldı. İngiliz/Amerikan yazımı (colour, centre, organise, travelled) ve ekle türetilebilen kelimeler hata sayılmaz.
- **Türkçe sızıntı:** Türkçe şık listeleri (bir şık Türkçeyse tüm liste), `lang: tr` kaynak metinleri, eşleştirme çiftlerinin Türkçe tarafı, tek kelimelik Türkçe istemler ve küçük harfli kelimelerinin yarısından azı İngilizce sözlükte olan metinler atlanır.
- **Noktalama:** boşluk biçimi `---- .` hata sayılmaz; kısaltma sonrası virgül (Bros., D.C., a.m.,) normaldir; kod/yol içeren metinler (`../`, `?page=2`, camelCase) noktalama kurallarından muaftır; sonda noktalama kuralı yalnızca aynı alanın ≥%90’ı noktalamayla bitiyorsa ve metin tek cümleyse çalışır (commit mesajları, imzalı notlar, parantezli ipuçları hariç).
- **Diğer:** özel isim ve sayı tekrarları (Santorio Santorio, five five five), *its very first*, *the day when I met you was*, *as if it were*, *Does she have* gibi doğru yapılar kurallardan çıkarıldı; küçük harfle başlayıp noktasız biten öbekler (*the man who spoke to you*) cümle sayılmaz; tanımlıkta harf harf okunmayan kısaltmalar (NASA, REST, UNESCO) belirsiz kabul edilir.

## Dosya bazında

| Dosya | İngilizce alan | Yüksek | Orta | Düşük |
|---|---:|---:|---:|---:|
| `assets/courses/exam_lgs.json` | 545 | 0 | 0 | 0 |
| `assets/courses/exam_lgs/02_ikinci_donem.json` | 547 | 0 | 0 | 0 |
| `assets/courses/exam_yds.json` | 1811 | 0 | 0 | 0 |
| `assets/courses/exam_yds/02_kelime_ve_kaliplar.json` | 1683 | 0 | 0 | 0 |
| `assets/courses/exam_yds/03_soru_tipleri.json` | 1734 | 0 | 0 | 0 |
| `assets/courses/exam_yds/04_deneme_ve_zaman.json` | 1118 | 0 | 0 | 0 |
| `assets/courses/exam_yds/05_kelime_bankasi_1.json` | 1085 | 0 | 0 | 0 |
| `assets/courses/exam_yds/06_okuma_evi_1.json` | 772 | 0 | 0 | 0 |
| `assets/courses/exam_yds/07_kelime_bankasi_2.json` | 1653 | 0 | 0 | 0 |
| `assets/courses/exam_yds/08_okuma_evi_2.json` | 1242 | 0 | 0 | 0 |
| `assets/courses/exam_yds/09_kelime_bankasi_3.json` | 1558 | 0 | 0 | 0 |
| `assets/courses/exam_yds/10_okuma_evi_3.json` | 1181 | 0 | 0 | 0 |
| `assets/courses/exam_yds/11_ara_denemeler.json` | 621 | 0 | 0 | 0 |
| `assets/courses/exam_yds/12_kelime_bankasi_4.json` | 1033 | 0 | 0 | 0 |
| `assets/courses/pro_dev.json` | 478 | 0 | 0 | 0 |
| `assets/courses/pro_interview.json` | 790 | 0 | 0 | 0 |
| `assets/courses/pro_tourism.json` | 817 | 0 | 0 | 0 |
| `assets/courses/tr_en.json` | 778 | 0 | 0 | 0 |
| `assets/courses/tr_en/01x_beceri.json` | 343 | 0 | 0 | 0 |
| `assets/courses/tr_en/02_gunluk_hayat.json` | 1007 | 0 | 0 | 0 |
| `assets/courses/tr_en/02x_beceri.json` | 332 | 0 | 0 | 0 |
| `assets/courses/tr_en/03_kendini_anlatmak.json` | 1041 | 0 | 0 | 0 |
| `assets/courses/tr_en/03x_beceri.json` | 325 | 0 | 0 | 0 |
| `assets/courses/tr_en/04_sehirde_ve_iste.json` | 1097 | 0 | 0 | 0 |
| `assets/courses/tr_en/04x_beceri.json` | 374 | 0 | 0 | 0 |
| `assets/courses/tr_en/05_deneyimler.json` | 1170 | 0 | 0 | 0 |
| `assets/courses/tr_en/05x_beceri.json` | 342 | 0 | 0 | 0 |
| `assets/courses/tr_en/06_fikirler_ve_hikayeler.json` | 1081 | 0 | 0 | 1 |
| `assets/courses/tr_en/06x_beceri.json` | 345 | 0 | 0 | 0 |
| `assets/courses/tr_en/07_is_ve_tartisma.json` | 1159 | 0 | 0 | 0 |
| `assets/courses/tr_en/07x_beceri.json` | 374 | 0 | 0 | 0 |
| `assets/courses/tr_en/08_akicilik.json` | 964 | 0 | 0 | 0 |
| `assets/courses/tr_en/08x_beceri.json` | 357 | 0 | 0 | 0 |
| `assets/courses/tr_en/09_derinlik.json` | 1367 | 0 | 0 | 0 |
| `assets/courses/tr_en/10_ustalik.json` | 1394 | 0 | 0 | 0 |
| `assets/exam_packs/lgs_full.json` | 96 | 0 | 0 | 0 |
| `assets/exam_packs/yds_full.json` | 3969 | 0 | 0 | 0 |
| `assets/exams/lgs.json` | 99 | 0 | 0 | 0 |
| `assets/exams/yds.json` | 186 | 0 | 0 | 0 |
| `assets/notes/grammar.json` | 1954 | 0 | 0 | 0 |
| `assets/notes/lessons.json` | 1038 | 0 | 0 | 0 |
| `assets/notes/words.json` | 116 | 0 | 0 | 0 |
| `assets/placement/questions.json` | 85 | 0 | 0 | 0 |
| `assets/pronunciation/units.json` | 39 | 0 | 0 | 0 |
| `assets/quotes/stoic.json` | 45 | 0 | 0 | 0 |
| `assets/reading/genel_okuma_a.json` | 120 | 0 | 0 | 0 |
| `assets/reading/genel_okuma_b.json` | 118 | 0 | 0 | 0 |
| `assets/reading/genel_okuma_c.json` | 30 | 0 | 0 | 0 |
| `assets/reading/stories.json` | 128 | 0 | 0 | 0 |
| `assets/reading/yds_bol_okuma_1.json` | 360 | 0 | 0 | 0 |
| `assets/reading/yds_bol_okuma_2.json` | 480 | 0 | 0 | 0 |
| `assets/reading/yds_bol_okuma_3.json` | 660 | 0 | 0 | 0 |
| `assets/vocab/software.json` | 1549 | 0 | 0 | 2 |
| `assets/vocab/yds.json` | 9972 | 0 | 1 | 0 |

## Kural bazında toplamlar

| Kural | Yüksek | Orta | Düşük | Toplam |
|---|---:|---:|---:|---:|
| Olası yazım hatası (sözlük) | 0 | 1 | 1 | 2 |
| Cümle küçük harfle başlıyor | 0 | 0 | 2 | 2 |
| **Toplam** | **0** | **1** | **3** | **4** |

## Bulgular

Güvene göre sıralı tüm bulgular (4).

| # | Dosya | Kimlik | Cümle | Sorun | Öneri | Güven | Kaynak |
|---:|---|---|---|---|---|---|---|
| 1 | `assets/vocab/yds.json` | `yd_nicotine · entries[2477].examples[0].en` | Nicotine patches release small doses of the drug through the skin to help smokers manage their cravings. | Olası yazım hatası: “cravings” (içerikte 1 kez) | “carvings”? | orta | kural |
| 2 | `assets/courses/tr_en/06_fikirler_ve_hikayeler.json` | `s6u7s · units[6].nodes[2].steps[6].text` | And yesterday a customer complained about a cold latte. I ignored it, and now there's a bad review online. | Olası yazım hatası: “latte” (içerikte 1 kez) | “late”? | düşük | kural |
| 3 | `assets/vocab/software.json` | `sw_latency · entries[161].examples[0].en` | p99 latency jumped to 2 seconds after the last deploy. | Cümle küçük harfle başlıyor | İlk harfi büyüt | düşük | kural |
| 4 | `assets/vocab/software.json` | `sw_vulnerability · entries[48].examples[0].en` | npm audit reports two high-severity vulnerabilities in our dependencies. | Cümle küçük harfle başlıyor | İlk harfi büyüt | düşük | kural |

