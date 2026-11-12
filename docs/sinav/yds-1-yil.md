# YDS 1 yıllık program: sıfırdan 80–90 puana

**Kimin için:** İngilizcesi sıfır ya da çok az olan, 52 hafta boyunca haftada 6 gün, günde 3–4 saat çalışacak aday. Haftanın 7. günü hafif gündür, yaklaşık 1,5 saat.

**Toplam süre:** yaklaşık 52 × (6 × 3,5 + 1,5) ≈ **1.170 saat**.

**Hedef:** YDS'de 80–90 puan, yani 64–72 doğru.

**Dayanak:** Araştırma ve kaynaklar `docs/sinav/yds-arastirma.md` dosyasında. 20 haftalık hızlı yol (A2/B1 başlangıç için) `docs/sinav/yds-plan.md` dosyasındadır. Bu belge onu sıfır başlangıca göre genişletir.

**Makine-okunur plan:** `assets/plans/yds_1_yil.json`.
- Haftalık hedefleri içerir ve yöntem ekibinin günlük plan özelliği bunu okur.
- Henüz `pubspec.yaml`'a eklenmedi; kullanan PR ekler.
- - Tablo ve JSON aynı veriden üretilir: `node tool/yds_plan/gen_plan.js .`. Haftaları değiştirmek için betiği düzenleyip yeniden çalıştırın.

---

## 1. Hesap: neden bu sayılar?

| Hedef | Değer | Gerekçe |
|---|---|---|
| Tanıma sözlüğü | **~6.600 kelime ailesi** (planda 6.590) | YDS metinlerinde ~%96–97 kapsam. %95 asgari, %98 rahat anlama eşiğidir (araştırma §1.5). |
| Okuma | **~420.000 kelime** | Bol okuma + yoğun okuma + hızlı yeniden okuma (§2.5) |
| Soru | **~9.500 soru çözümü**, ~6.000+ benzersiz soru | Günlük 25–40 soru × ~250 gün. Hata defteri yanlışları tekrar sorar. |
| Tam deneme | **20** (80 soru / 180 dk) | Son 23 haftaya yayılır. Son 4 haftada haftada 2 deneme. |
| Yarım deneme | **8** (40 soru / 90 dk) | Konu evrelerinde ölçme ve tanı |
| Dilbilgisi | A1 → C1 sınav dilbilgisi | Genel kurs s1–s8 + YDS ys1 |

**Rehberli saat karşılaştırması:** Cambridge'in kümülatif rehberli saat değerleri `docs/genel-arastirma.md` dosyasında. Planın saatleri bunlarla şöyle karşılaşıyor:

| Evre sonu | Planın kümülatif saati | Cambridge değeri |
|---|---|---|
| A2 (H10) | ≈ 180 sa | 180–200 |
| B1 (H20) | ≈ 400 sa | 350–400 |
| B2 (H34) | ≈ 740 sa | 500–600 |

Hesap şöyle:
- H1–4: haftada ~15 sa
- H5–10: ~19,5 sa
- H11–20: ~22,5 sa
- H21–34: ~24 sa

B2'deki fazla saat sınav pratiğinden ve akademik kelimeden gelir.

**Birim notu:** Kelime hedefleri bu belgede **aile** olarak verilir. Genel kurs belgesi **lemma** kullanır. Aile sayısı lemma sayısından küçüktür.

**Saat dağılımı:** Nation'ın dört kolu, sınava uyarlanmış hâliyle:

| Kol | Pay |
|---|---|
| Kelime ve tekrar | ~%20 |
| Okuma (anlam odaklı girdi) | ~%25 |
| Yeni ders (dil odaklı) | ~%30 |
| Soru ve deneme (sınav becerisi ve akıcılık) | ~%25 |

Konuşma ve yazma YDS'de ölçülmez. Yine de Evre 1–2'de genel kursun dinleme ve konuşma alıştırmaları kalır: kelimeyi sesle birlikte öğrenmek kalıcılığı artırır ve kullanıcının motivasyonunu korur.

---

## 2. Evreler

| Evre | Hafta | Seviye | Ana içerik | Günlük süre | Kelime (toplam) |
|---|---|---|---|---|---|
| 1. Sıfır → A2 temel | 1–10 | A0 → A2 | Genel kurs s1–s4 (48 ünite) | H1–4: 2–2,5 sa; H5–10: 3 sa | 1.480 |
| 2. A2 → B1 ve YDS temeli | 11–20 | A2 → B1 | Genel s5–s6, YDS Temel köprü (ys1u11–16), ys1u1–u4, **Kelime bankası 1**, **Okuma evi 1** | 3,5 sa | 2.680 |
| 3. B1 → B2 akademik | 21–34 | B1 → B2 | YDS ys1u5–u10, ys2 (15 ünite), genel s7–s8'den seçme üniteler, Kelime bankası 2, Okuma evi 2 | 3,5–4 sa | 4.430 |
| 4. Sınav stratejisi | 35–42 | B2 | YDS ys3 (14 ünite), Kelime bankası 3, Okuma evi 3 (alan metinleri) | 3,5–4 sa | 5.710 |
| 5. Deneme kampı | 43–52 | B2+ | YDS ys4 (9 ünite), 14 tam deneme, hata defteri | 4 sa | 6.590 |

**Evre geçiş ölçütleri.** Ölçütü tutmayan aday bir sonraki evreye geçebilir, ama uygulama tekrar haftası önerir ve sınav tarihini kaydırmayı teklif eder.

| Nokta | Ölçüt | Tutmazsa |
|---|---|---|
| H10 sonu | Genel s4 ünite testleri ≥ %70; kelime kontrolü 1k bandı ≥ %85 | 1–2 hafta s3–s4 tekrarı |
| H20 yarım deneme 1 (tanı) | ≥ 18/40 | Evre 2'yi 2 hafta uzat. Kelime bankası 1 tekrarı. |
| H30 tam deneme 1 | ≥ 40/80 (50 puan) | ys1 zayıf üniteler ve kelime setleri |
| H42 tam deneme 6 | ≥ 52/80 (65 puan) | Sınavı 4–6 hafta ertele |
| H47 tam deneme 11 | ≥ 60/80 (75 puan) | Zayıf tür haftası ekle |
| H51 son 4 deneme ortalaması | ≥ 64/80 (80 puan) | Hedef 80 için sınava gir. 90 için 4–8 hafta daha deneme kampı. |

> Gerçekçilik: Sıfırdan bir yılda 80 puan, düzenli çalışan bir aday için ulaşılabilir bir hedeftir. 90 puan, kelime ve okuma hedeflerinin tamamen tutturulmasını gerektirir. Uygulama, adaya kendi verisine dayalı bir **tahmini puan aralığı** gösterir ve sözü bu aralık üzerinden verir.

---

## 3. Günlük oturum şablonu

### 3.1 Standart gün (Evre 2–4, ~210 dk)

| Sıra | Blok | Süre | İçerik | Yöntem |
|---|---|---|---|---|
| 1 | Tekrar kartları | 30 dk | Vadesi gelen kelime kartları, ardından hata defteri kartları. Tekrar 40 dk'yı aşarsa o gün yeni kelime azalır. | Aralıklı tekrar, geri çağırma |
| 2 | Yeni ders | 60 dk | Yolun sıradaki ünitesi: ön test (3–5 soru) → rehber (en fazla 10 dk) → 2 ders. Ardından o günün yeni kelimeleri (~25). | Geri çağırma, derinlemesine işleme |
| — | Mola | 10 dk | Mola hatırlatıcısı | |
| 3 | Okuma | 45 dk | 25 dk bol okuma (kolay metin, sayaç) + 20 dk yoğun okuma (YDS uzunluğunda 1 metin, 4 soru, cümle çözümleme) | Bol ve yoğun okuma, bağlamda tekrar |
| 4 | Soru | 45 dk | Haftanın soru tipi (25 soru) + son 3–4 haftadan karışık set (10–15 soru). Haftada 2 gün tamamen karışık. | Karışık çalışma, geri çağırma |
| 5 | Hata defteri | 20 dk | Günün yanlışlarına neden etiketi. Vadesi gelen hata kartları. "Neden yanıldım" notu. | Hata analizi, hedefli tekrar |

**4 saatlik gün:** Okuma bloğu 60 dk olur (bol okuma 40 dk). Fazladan 15 dk karışık soru eklenir.

### 3.2 Evre 1 günü (H1–10)

İlk 4 hafta 120–150 dk, sonra 180 dk:
- 20–30 dk kelime kartları
- 60–90 dk genel kurs dersleri (dinleme ve konuşma dahil)
- 20–40 dk kolay okuma: genel kurs hikâyeleri ve okuma ekranı
- 15 dk tekrar/yanlışlar
- H8'den sonra 10 dk "YDS tadımı" (5 şıklı A2 soruları)

### 3.3 Deneme günü (Evre 4–5)

| Blok | Süre |
|---|---|
| Tekrar kartları (kısa) | 20 dk |
| Tam deneme (tek oturum, mola yok, gerçek koşul) | 180 dk |
| Sonuç ekranı: tür bazında açık ve süre raporu | 10 dk |

**Ertesi gün:** standart gün. Ancak blok 4 (Soru) yerine **denemenin hata analizi** yapılır (45–60 dk):
- her yanlışa neden etiketi
- hedefli öneriler

### 3.4 Hafif gün (her haftanın 7. günü, ~90 dk)

- Tekrar kartları
- Haftanın hata defteri
- Bol okuma (keyif için)
- Haftalık rapor: kelime, okuma, doğru oranı, tahmini puan

Yeni ders yoktur.

---

## 4. 52 haftalık tablo

Sütunlar:
- **Yol / ders:** o hafta bitirilecek yol üniteleri. "Genel sN uM" genel kurs bölüm ve ünitesidir; "ysN uM" YDS yoludur.
- **Kelime yeni / toplam:** o hafta öğrenilecek yeni kelime ailesi ve kümülatif toplam. Kaynak sırası: genel kursun kelimeleri → YDS yolu kelimeleri → Kelime bankası (§5).
- **Okuma:** günlük okuma hedefi (kelime) ve günde kaç yoğun YDS metni.
- **Soru:** haftanın soru tipi ve günlük 5 şıklı soru sayısı.
- **Deneme:** bölüm, yarım ve tam denemeler.
  - `yds_m1–m8` mevcut paketteki denemelerdir; yolda ys4u2–ys4u9'a bağlıdır ve H44–51'de sırayla gelir.
  - `yds_m9–m20` yeni yazılacak: H30–43'teki 7 deneme ve son haftaların ikinci denemeleri. Böylece aynı deneme iki kez çözülmez.
  - Yeni denemeler gelene kadar H30–43'te mevcut paket denemeleri kullanılabilir, ama o zaman ys4'te tekrar çözülürler. Puan şişer, bunu sonuç ekranında belirtin.

<!-- TABLO:BAŞ -->
| Hafta | Evre | Yol / ders | Dilbilgisi odağı | Kelime yeni / toplam | Okuma (kelime/gün; yoğun metin/gün) | Soru çalışması (soru/gün) | Deneme |
|---|---|---|---|---|---|---|---|
| 1 | 1 | Genel s1 u1–u5 | to be, isim çoğulu, a/an, this/that | 100 / 100 | 300; 0 | — |  |
| 2 | 1 | Genel s1 u6–u12 | present simple, there is/are, can, past simple giriş | 100 / 200 | 300; 0 | — |  |
| 3 | 1 | Genel s2 u1–u6 | present simple 3. tekil, sıklık zarfları, iyelik | 160 / 360 | 300; 0 | — |  |
| 4 | 1 | Genel s2 u7–u12 | edatlar (yer/zaman), emir, can/can't | 160 / 520 | 300; 0 | — |  |
| 5 | 1 | Genel s3 u1–u6 | past simple, past continuous | 160 / 680 | 600; 0 | — |  |
| 6 | 1 | Genel s3 u7–u12 | nesne zamirleri, karşılaştırma, much/many, going to/will | 160 / 840 | 600; 0 | — |  |
| 7 | 1 | Genel s4 u1–u4 | present perfect (ever/never, just/already/yet) | 160 / 1.000 | 600; 0 | — |  |
| 8 | 1 | Genel s4 u5–u8 | should/must/have to, too/enough, first conditional, -ing/to | 160 / 1.160 | 600; 0 | Tadım: 5 şıklı dilbilgisi (A2) (10) |  |
| 9 | 1 | Genel s4 u9–u12 | who/which/that (giriş), resmî e-posta dili | 160 / 1.320 | 600; 0 | Tadım: kelime ve dilbilgisi (A2) (10) |  |
| 10 | 1 | Tekrar haftası: s1–s4 ünite testleri | A1–A2 karışık | 160 / 1.480 | 600; 0 | Tadım: kısa paragraf (A2) (10) | Seviye kontrolü (genel kurs s4 sonu) |
| 11 | 2 | Genel s5 u1–u4 | present perfect continuous, used to, edilgen (giriş) | 120 / 1.600 | 1.000; 0 | Dilbilgisi (B1) (25) |  |
| 12 | 2 | Genel s5 u5–u8 | edilgen, second conditional, reported speech, phrasal verbs | 120 / 1.720 | 1.000; 0 | Dilbilgisi, kelime (25) |  |
| 13 | 2 | YDS ys1u11 Cümlenin iskeleti, ys1u12 İsim öbeği ve gönderim | özne–yüklem, isim öbeği, gönderim | 120 / 1.840 | 1.000; 0 | Dilbilgisi, kelime (25) |  |
| 14 | 2 | YDS ys1u13 Temel zamanlar, Genel s5 u9–u12 | zaman çekirdeği, modal of deduction | 120 / 1.960 | 1.000; 0 | Dilbilgisi, cümle tamamlama (giriş) (25) |  |
| 15 | 2 | YDS ys1u14 Sözcük türetme, Genel s6 u1–u3 | ek ile türetme, past perfect | 120 / 2.080 | 1.000; 1 | Kelime, cloze (giriş) (25) |  |
| 16 | 2 | YDS ys1u15 Temel bağlaçlar, ys1u16 Uzun cümle | bağlaç ve edat çekirdeği, sıfat cümleciği | 120 / 2.200 | 1.000; 1 | Cümle tamamlama, çeviri (giriş) (25) |  |
| 17 | 2 | YDS ys1u1 Zamanlar, Genel s6 u4–u6 | zaman uyumu, so/such…that, wish | 120 / 2.320 | 1.000; 1 | Dilbilgisi, cloze (25) |  |
| 18 | 2 | YDS ys1u2 Kipler, Genel s6 u7–u9 | kipler, question tags | 120 / 2.440 | 1.000; 1 | Dilbilgisi, cümle tamamlama (25) |  |
| 19 | 2 | YDS ys1u3 Edilgen ve ettirgen, Genel s6 u10–u12 | edilgen, ettirgen, karşıtlık (yine de) | 120 / 2.560 | 1.000; 1 | Dilbilgisi, çeviri (25) |  |
| 20 | 2 | YDS ys1u4 Koşul ve wish | koşul türleri, wish/if only | 120 / 2.680 | 1.000; 1 | Karışık set (H11–20) (25) | Yarım deneme 1 (tanı, 40 soru / 90 dk) |
| 21 | 3 | YDS ys1u5 Sıfat cümlecikleri | relative clause, kısaltma | 125 / 2.805 | 1.500; 1 | Dilbilgisi, çeviri (35) |  |
| 22 | 3 | YDS ys1u6 İsim cümlecikleri, Genel s7 u1–u2 | noun clause, mixed conditionals | 125 / 2.930 | 1.500; 1 | Dilbilgisi, cümle tamamlama (35) | Yarım deneme 2 |
| 23 | 3 | YDS ys1u7 Gerund ve infinitive, Genel s7 u3 | gerund/infinitive, should have | 125 / 3.055 | 1.500; 1 | Dilbilgisi, cloze (35) |  |
| 24 | 3 | YDS ys1u8 Bağlaçlar ve geçişler, Genel s7 u4 | bağlaç ve geçiş ifadeleri, haber dili | 125 / 3.180 | 1.500; 1 | Cümle tamamlama, paragraf tamamlama (giriş) (35) | Yarım deneme 3 |
| 25 | 3 | YDS ys1u9 Edatlar, Genel s7 u7 | edat + eşdizim, causative | 125 / 3.305 | 1.500; 1 | Kelime, cloze (35) |  |
| 26 | 3 | YDS ys1u10 Miktar ve karşılaştırma, Genel s7 u8 | quantifier, karşılaştırma, inversion | 125 / 3.430 | 1.500; 1 | Karışık set (ys1) (35) | Bölüm 1 denemesi (ys1 sonu) |
| 27 | 3 | YDS ys2u1 Akademik fiiller, ys2u2 Sıfatlar ve zarflar | akademik fiil kalıpları | 125 / 3.555 | 1.500; 1 | Kelime, cümle tamamlama (35) | Yarım deneme 4 |
| 28 | 3 | YDS ys2u3 Phrasal verbs, ys2u4 İsim kalıpları | phrasal verb, eşdizim | 125 / 3.680 | 1.500; 1 | Kelime, cloze (35) |  |
| 29 | 3 | YDS ys2u5 Eş anlamlılar, ys2u6 Karıştırılanlar, Genel s8 u2 | eş anlam, bağlamdan anlam, yazıda bağlantı | 125 / 3.805 | 1.500; 1 | Kelime, restatement (giriş) (35) |  |
| 30 | 3 | YDS ys2u7–u9 YÖKDİL alan kelimeleri (hedef alana ağırlık) | alan terimleri | 125 / 3.930 | 1.500; 1 | Okuma (alan metinleri) (35) | Tam deneme 1 (yeni: yds_m9) |
| 31 | 3 | YDS ys2u10–u11 Kelime setleri 1–2, Genel s8 u8 | ince anlam farkları | 125 / 4.055 | 1.500; 1 | Kelime, cloze (35) |  |
| 32 | 3 | YDS ys2u12–u13 Kelime setleri 3–4, Genel s8 u10 | akademik ses | 125 / 4.180 | 1.500; 1 | Kelime, okuma (35) | Yarım deneme 5 |
| 33 | 3 | YDS ys2u14–u15 Kelime setleri 5–6 | zarf ve kalıplar | 125 / 4.305 | 1.500; 1 | Karışık set (ys2) (35) | Bölüm 2 denemesi (ys2 sonu) |
| 34 | 3 | Tekrar haftası: ys1–ys2 zayıf üniteler (analize göre) | zayıf konular | 125 / 4.430 | 1.500; 1 | Karışık set (ys1–ys2) (35) | Tam deneme 2 (yeni: yds_m10) |
| 35 | 4 | YDS ys3u1 Cloze, ys3u2 Cümle tamamlama | — | 160 / 4.590 | 1.800; 2 | Cloze, cümle tamamlama (strateji) (40) |  |
| 36 | 4 | YDS ys3u3 Çeviri İng→Tr, ys3u4 Çeviri Tr→İng | — | 160 / 4.750 | 1.800; 2 | Çeviri (iki yön) (40) | Tam deneme 3 (yeni: yds_m11) |
| 37 | 4 | YDS ys3u5 Ana fikir, ys3u6 Paragraf soruları | — | 160 / 4.910 | 1.800; 2 | Okuma (strateji) (40) | Yarım deneme 6 |
| 38 | 4 | YDS ys3u7 Diyalog, ys3u8 Restatement (YÖKDİL: çeviri tekrarı) | — | 160 / 5.070 | 1.800; 2 | Diyalog, restatement (40) | Tam deneme 4 (yeni: yds_m12) |
| 39 | 4 | YDS ys3u9 Paragraf tamamlama, ys3u10 Anlam bütünlüğü | — | 160 / 5.230 | 1.800; 2 | Paragraf tamamlama, anlam bütünlüğü (40) | Yarım deneme 7 |
| 40 | 4 | YDS ys3u11 Okuma kampı: fen, ys3u12 sağlık | — | 160 / 5.390 | 1.800; 2 | Okuma (zamanlı) (40) | Tam deneme 5 (yeni: yds_m13) + Bölüm 3 denemesi |
| 41 | 4 | YDS ys3u13 Okuma kampı: sosyal, ys3u14 tarih/kültür | — | 160 / 5.550 | 1.800; 2 | Okuma (zamanlı) (40) | Yarım deneme 8 + okuma kampı denemesi |
| 42 | 4 | Tekrar haftası: ys3 zayıf soru tipleri | zayıf konular | 160 / 5.710 | 1.800; 2 | Karışık set (tüm tipler) (40) | Tam deneme 6 (yeni: yds_m14) |
| 43 | 5 | YDS ys4u1 Karışık set 1 | — | 110 / 5.820 | 2.000; 2 | Karışık (tam dağılım) (40) | Tam deneme 7 (yeni: yds_m15) |
| 44 | 5 | YDS ys4u2 Karışık set 2 | — | 110 / 5.930 | 2.000; 2 | Karışık (tam dağılım) (40) | Tam deneme 8 (yds_m1, ys4u2) |
| 45 | 5 | YDS ys4u3 Süre stratejisi | — | 110 / 6.040 | 2.000; 2 | Bölüm süre çalışması (40) | Tam deneme 9 (yds_m2, ys4u3) |
| 46 | 5 | YDS ys4u4 Hata analizi | — | 110 / 6.150 | 2.000; 2 | Hata defteri yoğun (40) | Tam deneme 10 (yds_m3, ys4u4) |
| 47 | 5 | YDS ys4u5 Deneme haftası 1: dilbilgisi | — | 110 / 6.260 | 2.000; 2 | Zayıf tip (analize göre) (40) | Tam deneme 11 (yds_m4, ys4u5) |
| 48 | 5 | YDS ys4u6 Deneme haftası 2: kelime | — | 110 / 6.370 | 2.000; 2 | Zayıf tip (40) | Tam deneme 12 (yds_m5, ys4u6) ve 13 (yeni: yds_m16) |
| 49 | 5 | YDS ys4u7 Deneme haftası 3: çeviri | — | 110 / 6.480 | 2.000; 2 | Zayıf tip (40) | Tam deneme 14 (yds_m6, ys4u7) ve 15 (yeni: yds_m17) |
| 50 | 5 | YDS ys4u8 Deneme haftası 4: okuma | — | 110 / 6.590 | 2.000; 2 | Zayıf tip (40) | Tam deneme 16 (yds_m7, ys4u8) ve 17 (yeni: yds_m18) |
| 51 | 5 | YDS ys4u9 Deneme haftası 5: son prova | — | 0 / 6.590 | 2.000; 2 | Zayıf tip (40) | Tam deneme 18 (yds_m8, ys4u9) ve 19 (yeni: yds_m19) |
| 52 | 5 | Son hafta: yalnızca tekrar ve hata defteri | — | 0 / 6.590 | 2.000; 2 | Hafif karışık set (40) | Tam deneme 20 (yeni: yds_m20, sınavdan 4–5 gün önce) |

**Toplam:** 6.590 yeni kelime ailesi (genel kurs + YDS yolu + kelime bankası), yaklaşık 421.200 kelime okuma (haftada 6 gün).
<!-- TABLO:SON -->

---

## 5. Mevcut içerik bu plana nasıl oturuyor ve eksikler

### 5.1 Var olan

| İçerik | Miktar | Plandaki yeri |
|---|---|---|
| Genel kurs s1–s4 (A1–A2) | 48 ünite, ~1.730 alıştırma | H1–10. Evre 1'in tamamı. |
| Genel kurs s5–s6 (B1) | 24 ünite, ~900 alıştırma | H11–19, YDS temel köprüyle paralel |
| Genel kurs s7–s8 (B2) | 22 ünite | H22–32 arası seçme 8 ünite: mixed conditional, should have, haber dili, causative, inversion, yazıda bağlantı, ince farklar, akademik ses. Gerisi isteğe bağlı. |
| YDS ys1 (16 ünite) | Temel köprü + 10 dilbilgisi | H13–26 |
| YDS ys2 (15 ünite) | Akademik kelime, eşdizim, 6 kelime seti | H27–33 |
| YDS ys3 (14 ünite) | 10 soru tipi + 4 okuma kampı | H35–41 |
| YDS ys4 (9 ünite) | Karışık setler, süre, hata analizi, 5 deneme haftası | H43–51 |
| YDS soruları | 54 ünite: 2.273 ders alıştırması + 979 ünite testi = 3.252 | Evre 2–5 soru bloğu |
| Uzun metin (≥100 kelime) | 135 | Yoğun okuma, H15–42 |
| Tam deneme | 8 (`yds_full`, paket) | Plandaki tam deneme 8–11, 12, 14, 16, 18 (H44–51, ys4 üniteleri) |
| Soru bankası | 91 (`assets/exams/yds.json`) | Pratik ve yarım deneme dolgusu |
| YDS kelime ve kalıp | 2.630 madde, ama kelime derslerindeki benzersiz kelime **~930** (F2c sayımı) | Toplam 6.600 hedefinin ~%14'ü. 2.630, dilbilgisi ve kalıp cevaplarını da sayıyordu. |

### 5.2 Eksikler

1. **Kelime (en büyük açık).**
   - Genel kurs (~1.500) + YDS yolunun kelime dersleri (~930) birlikte yaklaşık 2.400 aile eder.
   - Not: İlk sürümde YDS yolu 2.630 sayılmıştı. F2c sayımı bunun kelime dersi dışındaki cevapları da içerdiğini gösterdi (2026-11-12 düzeltmesi).
   - Hedef 6.600. **Yaklaşık 4.200 yeni kelime gerekir.** Kelime bankaları bunu karşılar: ys5 800 + ys7 1.200 (gönderildi) + F3 1.300 + F4 900. Kaynaklar aşağıda.
   - Haftalık hedefler bu kaynaklara göre dengelendi: Evre 2'de haftada 120 (ys5 + genel s5–s6 + ys1), Evre 3'te 125 (ys7 + ys2 + genel s7–s8), Evre 4'te 160 (Kelime bankası 3), Evre 5'te 110 (Kelime bankası 4). Kaynak listesi:
     - NGSL çekirdeğinde eksik kalanlar
     - NAWL/akademik
     - orta sıklık bandı
     - YÖKDİL alan terimleri
2. **Okuma hacmi.**
   - Mevcut 135 uzun metin, H15–52 arasındaki yaklaşık 220 günlük yoğun okuma ihtiyacının yarısından azdır. **~150 yeni yoğun metin** gerekir.
   - Bol okuma için seviyeli ve tamamlanabilir **~250 kısa metin** (300–800 kelime) gerekir.
3. **Deneme.** 8 tam deneme var, plan 20 istiyor: **12 yeni tam deneme + 8 yarım deneme**.
4. **Soru hacmi.** ~9.500 çözüm ve hata defteri tekrarı için **~2.000 yeni yol sorusu** gerekir. Bunlara yoğun metin soruları ve denemeler dahil değildir.
5. **Evre 1 → YDS köprüsü.**
   - Genel kurs A1–A2 konuşma odaklıdır. YDS adayına okuma odaklı A2 metinler gerekir.
   - Bunu Okuma evi 1'in ilk üniteleri (A2+) kapatır.
6. **Altyapı.**
   - Yeni bölümler dosya sırasıyla kilitlenir: `sections.dart` önceki bölümün sınavı geçilmeden sonrakini açmaz.
   - Kelime bankası ve Okuma evi **paralel** yürümelidir. Bu yüzden bölüme `"parallel": true` alanı gerekir: her zaman açık, kendi içinde sıralı. Yöntem ekibi spesifikasyonu §2.

### 5.3 İçerik hedefleri: fazlar

| Faz | Plan evresi | Bölüm / dosya | Ünite | Ders soruları | Test | Kelime | Metin | Deneme |
|---|---|---|---|---|---|---|---|---|
| **F1 (bu tur)** | Evre 2 (H11–20) | `exam_yds/05_kelime_bankasi_1.json` (ys5), `exam_yds/06_okuma_evi_1.json` (ys6) | 10 + 6 | ~640 | ~240 | 800 | 36 yoğun (B1, 200–350 kelime) | 1 yarım deneme (40) |
| F2 | Evre 3 (H21–34) | `07_kelime_bankasi_2`, `08_okuma_evi_2` | 15 + 10 | ~1.000 | ~375 | 1.200 | 60 akademik (250–300) + 60 bol okuma | 4 yarım + 2 tam deneme (m9–m10) |
| F3 | Evre 4 (H35–42) | `09_kelime_bankasi_3`, `10_okuma_evi_3` | 12 + 8 | ~800 | ~300 | 1.300 | 48 alan metni (fen/sağlık/sosyal) + 80 bol okuma | 3 yarım + 4 tam deneme (m11–m14) |
| F4 | Evre 5 (H43–52) | `11_kelime_bankasi_4`, `assets/exam_packs/yds_full.json` (yeni mock'lar) | 8 | ~500 | ~200 | 900 | 110 bol okuma | 6 tam deneme (m15–m20) |
| **Toplam yeni** | | | **69** | **~2.940** | **~1.115** | **4.200** | **~150 yoğun + ~250 bol** | **12 tam + 8 yarım** |

Yeni bölüm kimlikleri ys5, ys6 ve sonrasıdır. Mevcut ID'lere dokunulmaz.

F1'in ayrıntılı spesifikasyonu: `docs/sinav/yds-faz1-icerik.md` (içerik ekibi) ve `docs/sinav/yds-faz1-yontem.md` (yöntem ekibi).

---

## 6. Sınav tarihi ve uyarlama

- **e-YDS** neredeyse her ay yapılır. Plan bittiğinde (H52) aday en yakın e-YDS'ye girebilir.
- İsteğe bağlı olarak H40 civarında bir gerçek e-YDS'ye "prova" olarak girilebilir.
- **YÖKDİL hedefi:**
  - H30'dan sonra okuma metinleri seçilen alandan gelir.
  - ys3u7 diyalog ve ys3u8 restatement atlanır; yerine çeviri tekrarı yapılır.
  - Tam denemeler YÖKDİL dağılımıyla kurulur (F4'te 3 tanesi YÖKDİL dağılımında).
- **Sınava daha az zaman varsa** (ör. 30 hafta):
  - Uygulama seviye testine göre başlangıç haftasını seçer: A2 → H11, B1 → H21.
  - Evre 3–4'ü sıkıştırır. Tam deneme sayısı sabit kalır.
- **Geride kalan aday:**
  - Plan "hafta" değil "adım" ile ilerler. Kaçırılan gün bir sonraki güne yığılmaz, takvim kayar.
  - Uygulama yeni tahmini bitiş tarihini gösterir.
