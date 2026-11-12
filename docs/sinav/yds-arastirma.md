# YDS araştırması: sınav analizi ve öğrenme bilimi

Bu belge, sıfırdan başlayıp **bir yıl boyunca günde 3–4 saat** çalışan bir adayın YDS'de **80–90 puan** alması için gereken bilimsel temeli toplar. Yıllık program bu temele göre `docs/sinav/yds-1-yil.md` dosyasında kurulur. Lisans durumu `docs/kaynaklar.md` dosyasındadır.

Her bölüm üç parçadan oluşur:
- **Bulgu:** araştırma ne diyor.
- **Karar:** Dilbaz'da ne yapıyoruz.
- **Uygulamada:** hangi ekran ya da özellik bunu yapıyor.

Kaynaklar en sonda numaralıdır ve metinde `[n]` olarak anılır.

> Dürüstlük notu: ÖSYM soru tipi sayılarını kılavuzda sabitlemez. Aşağıdaki dağılımlar son oturumların gözlenen düzenidir. Kesin bilgi her dönemin kılavuzundadır ([1], [2]). Rakamları "kesin" diye kullanıcıya göstermeyiz; "son oturumlarda genellikle" deriz.

---

## 1. Sınavlar

### 1.1 YDS ve e-YDS

| | YDS (kâğıt) | e-YDS (bilgisayar) |
|---|---|---|
| Soru / süre | 80 soru, 180 dk | 80 soru, 180 dk |
| Şık | 5 | 5 |
| Puan | Her doğru 1,25; yanlış doğruyu götürmez | Aynı |
| Sıklık | Yılda 2 | Yılda 10'a yakın oturum (yalnızca İngilizce, birkaç ilde) |
| Geçerlilik | 5 yıl (kurum daha kısa isteyebilir) | Aynı |

Kaynak: [1], [2].

**Sonuç:**
- 80 puan = 64 doğru, 85 puan = 68 doğru, 90 puan = 72 doğru.
- Yanlış ceza olmadığı için **boş bırakmak her zaman kötü bir stratejidir**. Süre biterken boş kalan her soru işaretlenmelidir. Bunu deneme sonuç ekranında söyleriz.

### 1.2 YDS soru tipi dağılımı (son oturumlarda gözlenen)

| Tip | Soru | Pay | Ölçtüğü beceri |
|---|---|---|---|
| Kelime | 6 | %7,5 | Akademik kelime, eşdizim, phrasal verb |
| Dilbilgisi | 10 | %12,5 | Zaman, kip, edilgen, yan cümle, bağlaç, edat |
| Cloze test | 10 | %12,5 | Metin içinde dilbilgisi ve bağlaç |
| Cümle tamamlama | 10 | %12,5 | Bağlaç anlamı, zaman uyumu, mantık |
| Çeviri (2 yön) | 6 | %7,5 | Cümle iskeleti ve anlam ayrıntısı |
| Okuma (5 metin × 4) | 20 | %25 | Ana fikir, ayrıntı, çıkarım, gönderim, tutum |
| Diyalog tamamlama | 5–6 | ~%7 | Bağlam, ton |
| Restatement | 3–4 | ~%4 | Yapı dönüşümü (although ↔ despite gibi) |
| Paragraf tamamlama | 4 | %5 | Bağlılık ve gönderim |
| Anlam bütünlüğünü bozan | 5 | %6 | Konu birliği |

Bkz. `docs/sinav/yds-plan.md` §2; uygulamadaki tam denemeler (`yds_full`) bu düzeni kullanır.

**Gözlem:**
- Puanın **yaklaşık %55'i** metin tabanlıdır: okuma, cloze, paragraf tamamlama, anlam bütünlüğü ve diyalog. Doğrudan kelime ya da dilbilgisi soruları yalnızca 16 sorudur.
- Yine de **kelime bilgisi neredeyse her sorunun ön koşuludur**. Bilinmeyen kelime oranı yüksek bir metinde strateji işe yaramaz (bkz. §2).
- Yıllık programın ağırlığı bu yüzden **kelime + okuma** üzerindedir. Dilbilgisi, okuma ve cümle çözümlemenin aracı olarak öğretilir.

### 1.3 YÖKDİL ve e-YÖKDİL

- 80 soru, 180 dakika. Fen, Sağlık ve Sosyal Bilimler alanları vardır. Metinler adayın alanından seçilir.
- Hazırlık kaynaklarında en çok tekrar eden dağılım [3]:
  - Okuma 15
  - Dilbilgisi 14
  - Çeviri 12 (6 + 6)
  - Cümle tamamlama 11
  - Cloze 10
  - Kelime 6
  - Paragraf tamamlama 6
  - Anlam bütünlüğü 6
- **Diyalog ve restatement yoktur.** Çeviri payı YDS'nin iki katıdır.
- Bu sayılar hazırlık sitelerinden derlenmiştir ve ÖSYM belgesiyle doğrulanamamıştır.

**Karar:**
- Ortak çekirdek aynıdır.
- Son 10 haftada kullanıcının seçtiği hedefe göre ağırlık değişir:
  - **YDS:** diyalog ve restatement eklenir.
  - **YÖKDİL:** çeviri iki katına çıkar ve okumalar seçilen alandan gelir.
- Uygulamada hedef sınav seçimi (YDS / YÖKDİL-Fen / Sağlık / Sosyal) günlük planı ve deneme türünü belirler.

### 1.4 Zorluk

- YDS metinleri akademik ve yarı akademik düzyazıdır: bilim haberi, sağlık, tarih, sosyoloji ve çevre konuları. Uzunluk 150–250 kelimedir.
- Dil düzeyi **B2–C1** aralığındadır:
  - cümleler uzundur, iç içe yan cümle, edilgen ve isimleştirme çoktur
  - AWL/NAWL türü akademik kelime yoğundur
- 80+ puan, metinleri **sözlüksüz ve dakikada 120–150 kelime hızla** anlayabilmeyi gerektirir. Hız hedefi süre hesabından gelir (bkz. §3.9).

### 1.5 Kelime kapsamı: kaç kelime gerekiyor?

| Bulgu | Kaynak |
|---|---|
| Yazılı metni yardımsız rahat anlamak için **%98 kapsam** gerekir. Bu da **8.000–9.000 kelime ailesi** demektir (özel adlar dahil). Konuşma dili için 6.000–7.000 aile yeter. | Nation 2006 [4] |
| **%95 kapsam** "asgari" anlamayı sağlar; bu yaklaşık **4.000–5.000 aile** demektir. %98 ise "optimal" düzeydir, yaklaşık 8.000 aile. | Laufer & Ravenhorst-Kalovski 2010 [5]; Schmitt vd. 2011 [6] |
| İlk 2.000–3.000 aile genel metnin %85–90'ını kapsar. Akademik liste (AWL ~570 aile) akademik metinde %10 civarı ek kapsam getirir. | Coxhead 2000 [7] |
| NGSL (2.800 lemma) genel metnin ~%92'sini kapsar. NAWL (~960 kelime) ile akademik metinde kapsam belirgin artar. | Browne vd. [8] |

**YDS'ye uyarlama:**
- YDS çoktan seçmelidir ve metindeki her kelimeyi bilmek gerekmez. Ama hız ve doğruluk birlikte isteniyor. 80–90 puan için gerçekçi hedef:
  - **Anlama (tanıma) sözlüğü:** yıl sonunda **6.500–7.000 kelime ailesi**. Bu, YDS metinlerinde yaklaşık %96–97 kapsam demektir.
  - **Bileşim:** NGSL çekirdeği (~2.800) + akademik liste (NAWL/AWL karşılığı ~1.000) + sınava özgü kalıp, phrasal verb ve eşdizim (~700) + orta sıklık bandı (4.000–7.000 arasından ~2.000–2.500).
- Bu sayı görev tanımındaki 6–8 bin bandının alt-orta kısmıdır.
- **Yıllık takvim için hesap:**
  - Yaklaşık 46 haftada ~6.500 yeni aile. Bu, haftada ~140, günde ~23 yeni kelime demektir.
  - Bu yük aralıklı tekrarla sürdürülebilir. Tekrar kartları günde 25–40 dakika tutar (bkz. §2.1).
- **Ölçüm:**
  - Uygulamada ayda bir kısa **kelime boyutu kontrolü** yapılır: bant başına 10 kelime, 1k–8k bantları.
  - Bu, Nation'ın Vocabulary Size Test fikrinden esinlenen **özgün** bir testtir; VST soruları kopyalanmaz.

### 1.6 Türk adayların tipik zorlukları

Hata analizi çalışmalarında Türk öğrencilerde en sık görülen hatalar şunlardır: **artikel, kelime seçimi, edat, sözcük dizimi ve özne–yüklem uyumu** [9], [10]. Bunların bir kısmı ana dilden aktarımdır (özellikle artikel, edat ve dizim). YDS'ye yansıyan biçimleri:

| Zorluk | Neden | YDS'de nerede vurur | Uygulamadaki karşılık |
|---|---|---|---|
| Cümleyi Türkçe sırayla okumak (SOV → SVO) | Türkçede fiil sondadır | Uzun cümle, çeviri, okuma | "Cümlenin iskeleti" dersleri; okuma metinlerinde ana fiil vurgulama ipucu |
| Yan cümlenin fiilini ana fiil sanmak | Türkçe sıfat-fiil (-en, -dığı) öne gelir | Çeviri, restatement | ys1u11, ys1u16; çeviri ünitelerinde "önce iskelet" adımı |
| `-dı` = past mı present perfect mı? | Türkçede tek ek | Dilbilgisi, cloze | ys1u1; hata etiketi `tense` |
| Bağlaç anlamını karıştırmak (although / because / whereas / unless) | Türkçede çoğu ek ile yapılır | Cümle tamamlama, cloze, paragraf | ys1u8, ys1u15; bağlaç anlam kartları |
| Edat ve eşdizim (depend *on*, interested *in*) | Türkçe hâl ekleri farklı eşleşir | Kelime, cloze | ys1u9, ys2u4; eşdizim kartları |
| Artikel ve sayılabilirlik | Türkçede artikel yok | Dilbilgisi (az), okuma (gönderim) | Genel kurs A1–A2; gönderim (`this`, `such`, `the former`) dersleri |
| Edilgen ve isimleştirmeyi yavaş çözmek | Akademik İngilizce yoğun kullanır | Okuma hızı | ys1u3, isim öbeği dersleri, yoğun okuma |
| "Kelimeyi biliyorum ama metinde tanımıyorum" | Kelime tek anlamla ve bağlamsız ezberlenmiş | Okuma, kelime | Kelime kartlarında örnek cümle ve türetme ailesi; kelime en az 2 farklı bağlamda görülür |
| Süre: okumaya 60 dk'dan az kalması | Baştaki sorularda takılma | Okuma ve paragraf | Süre stratejisi (ys4u3), deneme sonunda tür bazında süre raporu |

Uygulama bu hataları zaten "Türk hata dedektörü" kategorileriyle (`lib/core/tr_errors.dart`) etiketliyor. YDS soruları için hata defterine **soru tipi** etiketi de eklenmelidir (yöntem ekibi spesifikasyonu, §1.3).

---

## 2. Öğrenme bilimi ve uygulamadaki karşılığı

Dunlosky vd. (2013), on çalışma tekniğini kanıt düzeyine göre sınıflamıştır. Yalnızca ikisi "yüksek fayda" almıştır: **aralıklı tekrar** ve **kendini sınama (geri çağırma)**. Yeniden okuma ve altını çizme ise "düşük fayda" almıştır [11]. Programın omurgası bu yüzden bu iki tekniktir.

### 2.1 Aralıklı tekrar (spaced repetition)

**Bulgu:**
- Aynı süre, zamana yayıldığında yığılmış çalışmadan çok daha kalıcıdır.
- En iyi tekrar aralığı, bilginin ne kadar süre hatırlanması gerektiğiyle büyür. Cepeda vd. (2008) bunu yaklaşık **bu sürenin %10–20'si** olarak bulmuştur; süre uzadıkça oran küçülür [12].
- Sınava 12 ay varken kelimelerin aralığı haftalar ve aylar ölçeğine çıkmalıdır.

**Algoritmalar:**
- **SM-2** (SuperMemo, Anki'nin eski varsayılanı) kolaylık katsayısıyla aralığı çarpar. Basittir ve iyi bilinir.
- **FSRS** (Free Spaced Repetition Scheduler) her kart için kararlılık (S), zorluk (D) ve hatırlanabilirlik (R) tahmin eder.
  - Unutma eğrisi üs yasasıyla modellenir: R(t) = (1 + k·t/S)^(−decay).
  - Hedef hatırlama oranı (ör. %90) seçilir ve aralık buna göre hesaplanır.
  - Anki'nin güncel zamanlayıcısıdır. Açık kaynaklıdır: MIT lisanslı Dart/TS/Python uygulamaları var [13].
- **Uygulamanın bugünkü hâli:**
  - Kelimeler için Leitner kutusu var: `reviewIntervals = [0, 1, 3, 7, 14, 30]` gün (`lib/data/progress.dart`).
  - Bu kısa vadeli öğrenme için iyidir, ama **30 günde tavan yapması bir yıllık program için yetersizdir**. 6.500 kelimelik bir yükte bilinen kelimeler her ay tekrar gelir ve günlük tekrar yükü şişer.

**Karar:**
1. **Faz 1:** Leitner aralıklarını uzat: `[0, 1, 3, 7, 14, 30, 60, 120, 240]`. Mevcut kutu değerleri geçerli kalır; yalnızca üst kutular eklenir.
   - Yanlışta kelime 0'a değil **iki kutu aşağı** iner. Bu, FSRS'nin "unutulan kart sıfırdan başlamaz" bulgusunun basit karşılığıdır.
2. **Faz 2:** FSRS'ye geçiş (MIT lisanslı Dart portu ya da kendi uygulaması). Hedef hatırlama %90. Günlük yeni kart sınırı kullanıcının seçtiği tempoya bağlıdır.
3. **Aralıklı tekrar yalnızca kelimeye değil, yanlış yapılan sınav sorularına da uygulanır:** hata defteri kartları 1–3–7–21 gün aralıkla geri gelir (§2.7).
4. **Günlük tekrar tavanı:**
   - Tekrar kartları günlük süreyi aşarsa (ör. 40 dk), yeni kelime sayısı otomatik düşer.
   - Kullanıcıya "Bugün tekrar günü: yeni kelime azaltıldı" denir. Biriken tekrar, yeni öğrenmenin en yaygın bırakma nedenidir.

**Uygulamada:** "Tekrar kartları" (vocab review) + "Hata defteri tekrarı" + günlük plandaki ilk 30 dakikalık blok.

### 2.2 Geri çağırma pratiği (retrieval practice, testing effect)

**Bulgu:**
- Bilgiyi hafızadan çağırmak, onu yeniden okumaktan daha kalıcı öğrenme sağlar. 118 makaleden 272 etki büyüklüğü içeren meta-analiz, kendini sınamanın yeniden çalışmaya ve diğer koşullara üstün olduğunu bulmuştur (Adesope vd. 2017 [14]; Roediger & Karpicke 2006 [15]).
- Geri bildirimle birleşince etki güçlenir.

**Karar:**
- Rehber (konu anlatımı) **kısa** tutulur ve her ünitede hemen sorulara geçilir. Okuma-anlatım oranı en fazla 1'e 4'tür.
- Kelime kartları **önce üretim/hatırlama**, sonra tanıma ister: Türkçesi verilir, İngilizcesi hatırlanır; ya da İngilizcesi verilir, anlamı seçmeden önce düşünülür. Kutusu yükseldikçe kart türü zorlaşır. Bu mantık `vocab_practice.dart` içinde zaten var; YDS kelimelerine de uygulanır.
- Her sorunun Türkçe açıklaması **cevaptan sonra** gösterilir. Açıklama, adayın neden yanıldığını söylemelidir.
- Ünite başında **ön test** (3–5 soru) yapılır. Bilmediğini görmek sonraki öğrenmeyi artırır (pretesting effect). Puan sayılmaz.

**Uygulamada:** dersler, ünite testleri, kelime kartları, ön test.

### 2.3 Karışık çalışma (interleaving)

**Bulgu:**
- Benzer kategorileri karışık çalışmak, ayrım yapma becerisini geliştirir. 59 çalışmalık meta-analizde orta düzey bir etki bulunmuştur (g ≈ 0,4).
- Etki, **birbirine benzeyen ve karıştırılan** kategorilerde en güçlüdür. Kelime listeleri gibi çok farklı malzemede ise zayıftır (Brunmair & Richter 2019 [16]; Rohrer & Taylor 2007 [17]).

**Karar:**
- **Konu ilk öğrenilirken bloklu**, pekiştirmede **karışık** çalışılır. Yeni konu tek başına öğretilir; ünite testi ve sonraki haftalar karışıktır.
- Karıştırmanın en çok işe yaradığı yer YDS'de tam olarak budur:
  - bağlaçlar (although / however / despite / whereas)
  - zamanlar (past simple / present perfect / past perfect)
  - soru tipleri (cümle tamamlama ile paragraf tamamlama)
- "Karışık set" günleri: haftada en az 2 gün soru bloğu **son 3–4 haftanın konularından karışık** gelir.

**Uygulamada:** "Karışık tekrar" düğümü; günlük plandaki soru bloğu, son haftaların ünite havuzundan karışık soru seçer.

### 2.4 Derinlemesine işleme (levels of processing, involvement load)

**Bulgu:**
- Anlam üzerinde düşünülen bilgi daha iyi hatırlanır (Craik & Lockhart 1972 [18]).
- Kelime öğreniminde **katılım yükü** hipotezine göre bir görev üç bileşen ölçüsünde etkilidir (Laufer & Hulstijn 2001 [19]):
  - **ihtiyaç:** kelime görev için gerekli mi
  - **arama:** anlamı ya da biçimi aranıyor mu
  - **değerlendirme:** bağlama uyuyor mu diye karşılaştırılıyor mu
- Kelimeyi bir cümlede **kullanmak**, sadece okuyup geçmekten daha kalıcıdır.

**Karar:**
- Her yeni kelime, **örnek cümle + türetme ailesi** (analyse → analysis → analytical) + **en az bir eşdizim** ile verilir.
- Kelime derslerinde şu görevler bulunur:
  - "bağlama hangisi uyar" (değerlendirme)
  - "kelimeyi türet" (arama)
  - "Türkçe cümleyi İngilizce kur" (üretim)
- Hata defterinde yanlış sorunun altına kullanıcı **kendi cümlesiyle bir not** yazabilir: "neden yanıldım". Bu bir öz-açıklama (self-explanation) adımıdır.

### 2.5 Okuma: bol (extensive) ve yoğun (intensive)

**Bulgu:**
- **Bol okuma** (kolay, çok miktarda, anlam odaklı) okuma becerisini ve kelimeyi geliştirir. Meta-analizde yetişkinlerde ve EFL ortamında etki daha yüksektir (Jeon & Day 2016 [20]).
- Bol okumanın işe yaraması için metindeki kelimelerin **%98'ine yakını** bilinmelidir. Okuma kolay olmalıdır (Nation & Waring [21]).
- Nation'ın **dört kolu** dengeli bir programı şöyle tanımlar [22]:
  - anlam odaklı girdi
  - anlam odaklı çıktı
  - dil odaklı öğrenme
  - akıcılık geliştirme
  
  Her biri zamanın yaklaşık dörtte biri olmalıdır.
- **Yoğun okuma**: metni cümle cümle çözümleme. Gönderim, bağlaç ve çeviri buna dahildir. Sınav tipi beceriyi doğrudan çalıştırır.

**Karar:** Günlük 45 dakikalık okuma bloğu iki bölümdür:
- **Bol okuma (25–30 dk):** Kullanıcının seviyesinin **bir tık altında**, kısa ve tamamlanabilir özgün metinler. Soru 1–2 tanedir ve sadece anlama kontrolüdür. Okunan kelime sayısı sayılır.
- **Yoğun okuma (15–20 dk):** YDS uzunluğunda (150–250 kelime) bir metin ve 4 sınav tipi soru. Ardından "cümle çözümleme" adımı gelir: ana fiil, gönderim, bağlaç.

**Yıllık okuma hedefi:**
- Toplam **~400.000 kelime**. Günlük hedef ilk haftalarda 300 kelimedir ve son evrede 2.000 kelimeye çıkar. Haftalık hedefler `yds-1-yil.md` dosyasındadır.
- Kaynak dağılımı:
  - uygulama içi özgün metinler: ~200 bin
  - aynı metinleri **hızlı yeniden okuma** (akıcılık kolu): ~100 bin
  - açık lisanslı dış okuma önerileri: ~100 bin
- Bu hedef okuma sayacıyla izlenir.

**Uygulamada:** "Okuma" ekranı (`reading_screen.dart`) + yeni okuma setleri. İlerleme ekranında "okunan kelime" sayacı.

### 2.6 Kelime öğreniminde bağlam ve tekrar sayısı

**Bulgu:**
- Tesadüfi (okurken) öğrenmede bir kelimenin öğrenilmesi için gereken karşılaşma sayısı çalışmalarda **2 ile 20+** arasında değişir. Tekrar ile öğrenme arasındaki ilişki ortadır (r ≈ 0,34) (Uchihara, Webb & Yanagisawa 2019 [23]).
- Webb (2007) yaklaşık **10 karşılaşmanın** kelime bilgisinin birçok boyutunda belirgin kazanç sağladığını göstermiştir [24].
- Kasıtlı (kart) öğrenme hızlıdır, ama kelimenin kullanımını öğretmez. Okumadaki karşılaşmalar ise kullanımı öğretir. İkisi birlikte en iyisidir (Schmitt 2008 [25]).

**Karar:** Her hedef kelime yıl içinde **en az 10 kez** görülmelidir:
- 1 kez tanıtım (ders: anlam + örnek + aile)
- 4–6 kez aralıklı tekrar kartı
- 3–5 kez farklı metinlerde ya da sorularda bağlam içinde

İçerik ekibi için kurallar:
- Her okuma metninde hedef kelimelerin **%60–70'i son 4 haftanın** kelimeleri olmalıdır (geri dönüşüm).
- Metindeki bilinmeyen kelime oranı, bol okumada **%2**'yi, yoğun okumada **%5**'i geçmemelidir.
- Bu oran ilgili bandın kelime listesine göre otomatik kontrol edilir; bkz. içerik spesifikasyonu §4.

### 2.7 Deneme → hata analizi → hedefli tekrar döngüsü

**Bulgu:**
- Kendini sınamanın faydası geri bildirimle artar [14].
- Uzmanlaşma araştırmaları, bilinçli pratiğin şu öğelerle işlediğini gösterir: zayıf noktayı hedefleme, anında geri bildirim ve tekrar (Ericsson vd. 1993 [26]).
- Tam deneme süre ve dayanıklılığı ölçer. Ama asıl öğrenme, deneme **sonrası** analizde olur.

**Karar (döngü):**
1. **Deneme:** tam (80/180) ya da yarım (40/90) deneme.
2. **Sonuç:**
   - tür bazında doğru / yanlış / boş ve süre
   - 72 doğru hedefine göre her türdeki açık
3. **Hata analizi (ertesi gün, 20–40 dk):** Her yanlış için **neden** seçilir:
   - kelimeyi bilmiyordum
   - yapıyı bilmiyordum
   - yanlış okudum / acele ettim
   - iki şık arasında kaldım
   - süre yetmedi
   - tahmin
4. **Hedefli tekrar:**
   - Neden "kelime" ise kelime tekrar kartlarına eklenir.
   - Neden "yapı" ise ilgili ünitenin rehberi ve 10 benzer soru önerilir.
   - Neden "süre" ise süre stratejisi çalışılır.
5. **Yeniden sınama:** Yanlış sorular hata defterinde 1–3–7–21 gün sonra yeniden sorulur. Arka arkaya iki doğru → defterden çıkar.

**Uygulamada:** deneme sonuç ekranı, hata defteri (mevcut "yanlışlar" + yeni neden etiketi), ilerleme analizi.

### 2.8 Zaman yönetimi

**Sınav içinde (180 dk, 80 soru):**

| Blok | Soru | Hedef süre |
|---|---|---|
| Kelime + dilbilgisi | 16 | 12 dk |
| Cloze | 10 | 12 dk |
| Cümle tamamlama | 10 | 15 dk |
| Çeviri | 6 | 12 dk |
| Okuma | 20 | 60 dk (metin başı ~12 dk) |
| Diyalog + restatement | 9 | 15 dk |
| Paragraf tamamlama + anlam bütünlüğü | 9 | 20 dk |
| Kontrol + işaretleme | — | 15–20 dk yedek |

- Kural: Bir soruda **2 dakikayı** aşma, işaretleyip geç. Boş bırakma, yanlış ceza yok.
- Hız hedefi: okuma bloğunda 4 metin × ~200 kelime ≈ 1.000 kelime ve 20 soru 60 dk'ya sığmalı. Bu, okuma hızının en az **120 kelime/dk** olmasını gerektirir. Bol okuma ve zamanlı okuma bu hızı geliştirir.

**Çalışma günü içinde:**
- 3–4 saat tek oturumda verimli değildir. Günü **3–4 bloğa** bölüyoruz. Bloklar arası 5–10 dk mola verilir; uygulamadaki mola hatırlatıcısı bunu yapar.
- Aynı gün içinde blok sırası: önce tekrar (taze dikkat, kısa), sonra en zorlayıcı yeni öğrenme, sonra okuma, sonra soru, en son hata defteri.

### 2.9 Motivasyon ve alışkanlık

**Bulgu:**
- Yeni bir davranışın otomatikleşmesi ortalama **66 gün** sürer, ama kişiden kişiye 18–254 gün arasında değişir.
- **Tek bir gün kaçırmak süreci bozmaz.** Düzensizlik ise bozar (Lally vd. 2010 [27]).
- Uygulama niyetleri ("Saat 07:00'de kahveden sonra tekrar kartlarını açacağım") hedefe ulaşmayı orta düzeyde artırır (Gollwitzer & Sheeran 2006 [28]).
- Öz-belirleme kuramına göre sürekli motivasyonun üç dayanağı vardır: özerklik, yetkinlik hissi ve bağlılık (Deci & Ryan [29]).

**Karar:**
- **Can/ceza yok** (sabit kural). Seri (streak) bozulunca sert bir uyarı gösterilmez. Bunun yerine "bir gün kaçırmak alışkanlığı bozmaz" denir ve **seri dondurma** önerilir.
- Kurulumda kullanıcıya şunlar sorulur:
  - **"Ne zaman ve nerede?"** (uygulama niyeti; bildirim saatine bağlanır)
  - **günlük süre** (2 / 3 / 4 saat)
  - **sınav tarihi**
- **Yetkinlik hissi:** Haftalık "tahmini YDS puanı" gösterilir. Son 3 deneme ve tür bazında doğru oranı kullanılır. Bir aralık olarak verilir, kesin sayı verilmez.
- **İlk 66 gün** (yaklaşık 10 hafta): Günlük hedef 2 saatten başlar, 3–4 saate kademeli çıkar. Erken tükenmişlik bir yıllık programın en büyük riskidir.
- Her haftanın sonunda 1 gün **hafif gün** (tekrar + hata defteri, ~1,5 saat) bulunur. Ayda bir **tam dinlenme günü** önerilir.

---

## 3. Yöntem → uygulama özelliği eşleme tablosu

| Yöntem | Kanıt | Uygulama özelliği | Durum |
|---|---|---|---|
| Aralıklı tekrar | [11], [12], [13] | Kelime tekrar kartları (Leitner → FSRS), hata defteri tekrarı | Var (30 güne kadar); Faz 1'de 240 güne uzatılacak; Faz 2'de FSRS |
| Geri çağırma | [11], [14], [15] | Ders soruları, ünite testi, kelime kartlarında hatırlama türleri, ön test | Var; ön test eklenecek |
| Karışık çalışma | [16], [17] | Karışık tekrar düğümü, günlük planın karışık soru bloğu | Kısmen (karışık set üniteleri); günlük karışık blok eklenecek |
| Derinlemesine işleme | [18], [19] | Örnek cümle + türetme ailesi + eşdizim; "neden yanıldım" notu | İçerik kuralı; not alanı eklenecek |
| Bol okuma | [20], [21], [22] | Okuma setleri, okunan kelime sayacı | Okuma ekranı var; YDS okuma setleri ve sayaç eklenecek |
| Yoğun okuma | [22] | YDS uzunluğunda metin + cümle çözümleme | Var (okuma kampı); yeni metinler eklenecek |
| Tekrar sayısı ≥10 | [23], [24], [25] | Kelime geri dönüşüm kuralı, metinlerde son 4 haftanın kelimeleri | İçerik kuralı + otomatik kontrol |
| Deneme → analiz → hedefli tekrar | [14], [26] | Deneme sonuç ekranı, hata nedeni etiketi, hedefli öneri | Deneme var; neden etiketi ve öneri eklenecek |
| Zaman yönetimi | §2.8 | Bölüm süre raporu, 2 dk kuralı uyarısı, günlük blok planı | Eklenecek |
| Alışkanlık | [27], [28], [29] | Günlük plan, uygulama niyeti + bildirim, seri dondurma, hafif gün | Hatırlatıcı var; plan ve niyet eklenecek |
| Kelime kapsamı | [4]–[8] | Bant bazlı kelime hedefi, aylık kelime boyutu kontrolü | Eklenecek |
| Yöntemlerin anlatımı | — | "Yöntemlerimiz" ekranı: her özelliğin hangi bulguya dayandığı, sade dille | Eklenecek |

---

## 4. Kaynaklar

1. ÖSYM, YDS ve e-YDS başvuru kılavuzları ve duyuruları. https://www.osym.gov.tr (ör. e-YDS 2025/10 duyurusu: https://osym.gov.tr/eyds-202510-ingilizce-basvurularin-alinmasi)
2. ÖSYM, 2025-YDS/2 duyurusu. https://www.osym.gov.tr/TR,33517/2025-yds2-basvurularin-alinmasi-30092025.html
3. YÖKDİL soru dağılımı derlemeleri (hazırlık siteleri; ÖSYM belgesi değil): https://sinavtime.com/yokdil-konulari-ve-soru-dagilimi, https://rehberpanda.com/rehberler/yokdil/konu-dagilimi/
4. Nation, I.S.P. (2006). How large a vocabulary is needed for reading and listening? *Canadian Modern Language Review* 63(1), 59–82. https://www.wgtn.ac.nz/__data/assets/pdf_file/0018/1626120/2006-How-large-a-vocab.pdf
5. Laufer, B. & Ravenhorst-Kalovski, G.C. (2010). Lexical threshold revisited. *Reading in a Foreign Language* 22(1), 15–30.
6. Schmitt, N., Jiang, X. & Grabe, W. (2011). The percentage of words known in a text and reading comprehension. *Modern Language Journal* 95(1). https://www.lextutor.ca/cover/papers/schmitt_etal_2011.pdf
7. Coxhead, A. (2000). A new academic word list. *TESOL Quarterly* 34(2), 213–238. https://www.wgtn.ac.nz/lals/resources/academicwordlist/information
8. Browne, C., Culligan, B. & Phillips, J. (2013). The New General Service List; Browne, Culligan & Phillips, The New Academic Word List. https://www.newgeneralservicelist.com
9. Kırmızı, Ö. & Karcı, B. (2017). An investigation of Turkish higher education EFL learners' linguistic and lexical errors. *Educational Process: International Journal*. https://doaj.org/article/d6c3cb9e5247484b810aef5d80f6c14e
10. Türk öğrencilerin yazılı hataları üzerine DergiPark çalışmaları, ör. https://dergipark.org.tr/en/download/article-file/1322056
11. Dunlosky, J. vd. (2013). Improving students' learning with effective learning techniques. *Psychological Science in the Public Interest* 14(1), 4–58.
12. Cepeda, N.J., Vul, E., Rohrer, D., Wixted, J.T. & Pashler, H. (2008). Spacing effects in learning: A temporal ridgeline of optimal retention. *Psychological Science* 19(11), 1095–1102. https://www.evullab.org/pdf/CepedaVulRohrerWixtedPashler-PS-2008.pdf
13. open-spaced-repetition, FSRS (py-fsrs, ts-fsrs, fsrs-rs; MIT). https://github.com/open-spaced-repetition
14. Adesope, O.O., Trevisan, D.A. & Sundararajan, N. (2017). Rethinking the use of tests: A meta-analysis of practice testing. *Review of Educational Research* 87(3), 659–701.
15. Roediger, H.L. & Karpicke, J.D. (2006). Test-enhanced learning. *Psychological Science* 17(3), 249–255.
16. Brunmair, M. & Richter, T. (2019). Similarity matters: A meta-analysis of interleaved learning and its moderators. *Psychological Bulletin* 145(11), 1029–1052. https://pubmed.ncbi.nlm.nih.gov/31556629/
17. Rohrer, D. & Taylor, K. (2007). The shuffling of mathematics problems improves learning. *Instructional Science* 35, 481–498.
18. Craik, F.I.M. & Lockhart, R.S. (1972). Levels of processing. *Journal of Verbal Learning and Verbal Behavior* 11, 671–684.
19. Laufer, B. & Hulstijn, J. (2001). Incidental vocabulary acquisition in a second language: The construct of task-induced involvement. *Applied Linguistics* 22(1), 1–26.
20. Jeon, E.-Y. & Day, R.R. (2016). The effectiveness of ER on reading proficiency: A meta-analysis. *Reading in a Foreign Language* 28(2), 246–265. https://scholarspace.manoa.hawaii.edu/items/b52a5591-ec04-4026-816f-434361a4e899
21. Nation, I.S.P. & Waring, R. (2019). *Teaching Extensive Reading in Another Language*. Routledge.
22. Nation, I.S.P. (2007). The four strands. *Innovation in Language Learning and Teaching* 1(1), 2–13.
23. Uchihara, T., Webb, S. & Yanagisawa, A. (2019). The effects of repetition on incidental vocabulary learning: A meta-analysis of correlational studies. *Language Learning* 69(3), 559–599. https://doi.org/10.1111/lang.12343
24. Webb, S. (2007). The effects of repetition on vocabulary knowledge. *Applied Linguistics* 28(1), 46–65.
25. Schmitt, N. (2008). Instructed second language vocabulary learning. *Language Teaching Research* 12(3), 329–363.
26. Ericsson, K.A., Krampe, R.T. & Tesch-Römer, C. (1993). The role of deliberate practice in the acquisition of expert performance. *Psychological Review* 100(3), 363–406.
27. Lally, P. vd. (2010). How are habits formed: Modelling habit formation in the real world. *European Journal of Social Psychology* 40(6), 998–1009. https://www.ucl.ac.uk/news/2009/aug/how-long-does-it-take-form-habit
28. Gollwitzer, P.M. & Sheeran, P. (2006). Implementation intentions and goal achievement: A meta-analysis. *Advances in Experimental Social Psychology* 38, 69–119.
29. Ryan, R.M. & Deci, E.L. (2000). Self-determination theory and the facilitation of intrinsic motivation. *American Psychologist* 55(1), 68–78.

> Not: [5], [11], [14], [15], [17]–[19], [21], [22] ve [24]–[29] alanın temel çalışmalarıdır. Künyeleri bilinen yayın bilgisidir. Bu turda yalnızca özet ve ikincil kaynaklarla kontrol edildi; tam metin okunmadı. Kullanıcıya gösterilecek "Yöntemlerimiz" metinleri bu belgeyi temel alır ve sayı uydurmaz.
