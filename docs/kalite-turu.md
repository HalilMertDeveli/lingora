# Kalite turu raporu (Kasım 2026)

Bu turda main'de bulunan içeriğin metinleri bağımsız olarak tarandı ve düzeltildi.
Ünite, düğüm ve alıştırma ID'leri ile alıştırma ve şık sayıları değişmedi; yalnızca metin alanları, `answer` değerleri ve `answers`/`tokens` dizileri düzenlendi.

## Kapsam

| Bölüm | Dosyalar | Ünite | Alıştırma | Ek |
|---|---|---|---|---|
| Genel kurs | `tr_en/02..08_*.json` | 82 | 3.180 | 1.184 hikâye adımı |
| LGS | `exam_lgs.json`, `exam_lgs/02_ikinci_donem.json` | 10 | 510 | 10 rehber |
| YDS | `exam_yds.json`, `exam_yds/02..04_*.json` | 54 | 3.252 | 54 rehber |

`tr_en.json` (Bölüm 1) ve `pro_*.json` bu turun kapsamı dışında kaldı.

## Yöntem

1. İçerik ünite sınırlarına göre 20 parçaya bölündü. Her parçayı ayrı bir inceleyici baştan sona okudu.
   - İnceleyici her `choice`, `select`, `fillBlank` ve hikâye sorusunu önce cevap anahtarına bakmadan kendisi çözdü.
   - Bulgular makine tarafından okunabilir düzeltme satırları olarak yazıldı: dosya, JSON yolu, eski değer, yeni değer.
2. Düzeltmeler bir betikle uygulandı.
   - Betik her düzeltmede eski değeri doğruladı.
   - Dosyaların biçimi (satır yapısı, girinti) korundu.
3. Dosyalar arası tekrarlar ayrıca betikle tarandı: birebir aynı sorular ve 3 kelimelik dizilere göre benzerlik.
4. **Cevap anahtarı teyidi:** Şüpheli 41 soru, cevapları gizlenerek ikinci bir bağımsız çözücüye verildi.
   - Çözücü her sorunun hem eski hem düzeltilmiş sürümünde doğru sayılabilecek tüm şıkları listeledi.
   - Düzeltilmiş sürümlerin hepsinde tek doğru şık kaldı.
   - Reddedilen şüphelerin hepsinde de, gösterilen çeviriyle birlikte tek doğru şık olduğu teyit edildi.
5. Mekanik taramalar (düzeltmelerden sonra) temiz çıktı:
   - Boşluktan önce gelen ve cevabı ele veren a/an (cloze parçaları dahil): 0.
   - Şıkları konumla anan açıklama ("birinci şık", "A şıkkı" gibi): 0.
6. İçerik testleri her commit öncesinde geçti: `content_quality_test`, `course_content_test`, `sinav_yolu_test`, `exam_packs_test`, `logic_test`.

## Sayılar

Bir alıştırmada birkaç alan değişse bile tek sorun olarak sayıldı.
"Not" sütunu düzeltme gerektirmeyen ya da karar bekleyen kayıtları gösterir; bunlar aşağıda listelenmiştir.

| Kategori | Genel | LGS | YDS | Toplam düzeltilen | Not | Reddedilen |
|---|---|---|---|---|---|---|
| Cevap anahtarı (ikinci doğru şık, a/an ipucu) | 16 | 0 | 6 | **22** | 6 | 13 |
| Türkçe çeviri / açıklama / rehber | 13 | 4 | 39 | **56** | 0 | 0 |
| Eksik `translate` varyantı | 43 | 6 | – | **49** (53 yeni varyant) | 0 | 0 |
| İngilizce dilbilgisi / doğallık / mantık | 6 | 0 | 10 | **16** | 1 | 0 |
| Tekrar / aşırı benzer soru | 8 | 0 | 8 | **16** | 11 | 0 |
| Yazım ve noktalama | 4 | 3 | 18 | **25** | 0 | 0 |
| Seviye uyumsuzluğu | 0 | 0 | 0 | 0 | 0 | 0 |
| **Toplam** | **90** | **13** | **81** | **184** | **18** | **13** |

Bunlara ek olarak mekanik bir tırnak düzeltmesi yapıldı:

- YDS'deki 1.130 açıklamada kıvrık tek tırnak (‘ ’) düz tırnağa (') çevrildi.
- İçeriğin çoğunluğu zaten düz tırnak kullanıyordu; 270 açıklamada ise iki biçim aynı metinde karışıktı.

Seviye kategorisinde belirgin bir uyumsuzluk bulunmadı.

## Örnek düzeltmeler

**Cevap anahtarı**

- `ys2u5t#8–11` (cloze parçası): Parçada "once had a (1) ---- supply" yazıyordu, doğru cevap ise *abundant*.
  - Bu hem dilbilgisi hatasıydı ("a abundant") hem de ünlüyle başlayan şıkkı eleyen bir ipucuydu.
  - Düzeltme: "once had (1) ---- supplies". Aynı parçayı kullanan 4 soruda birlikte düzeltildi.
- `ys2u8t#8–11`: "described an (1) ----" ifadesi ünsüzle başlayan üç şıkkı eliyordu. "a serious (1) ----" yapıldı.
- `s8u8l4#4`: "He finally ___ that he had made a mistake." cümlesinde *accepted* da doğruydu.
  - Cümle "He finally ___ making a mistake." yapıldı. Böylece yalnız *admitted* uyuyor.
- `s3u11l3#1`: "The phone is ringing. I'll ___ it." cümlesinde *take* da doğal bir cevaptı ("I'll take it"). Çeldirici *pick* yapıldı.
- `ys4u4t#3`: *would rather you ----* boşluğunda "not publish" Amerikan İngilizcesinde kabul görüyordu. Çeldirici "not to publish" yapıldı.
- `ys4u5l3#2`: *It is essential that ----* boşluğunda "has signed" İngiliz İngilizcesinde kabul görüyordu. Çeldirici "had signed" yapıldı.

**Türkçe ve rehber**

- `ys2u5t#17`: Açıklama şıkları "Birinci şık… dördüncü…" diye anıyordu. Şıklar metinleriyle anılacak biçimde yeniden yazıldı.
- `ys4u5` rehberi: Soru türlerine göre hedeflerin toplamı 71 ediyordu, metin ise 72 diyordu ("okuma 16" → 17). Ayrıca "ilk 30 soru" ifadesi rehberin kendi dağılımıyla çelişiyordu (→ 26).
- `ys1u8l3#11`: *as soon as* "-ır -mız" diye eşleştirilmişti → "-ır -maz".
- `s6u11l4#7`: *even though* "-se bile" diye eşleştirilmişti (bu *even if*'tir) → "-diği hâlde".
- `ls1u2` rehberi: "like'tan sonra fiil yalnızca -ing alır" deniyordu → "-ing (ya da to + fiil)".
- `ys3u12l1#8`, `ys3u13l4#2`: Açıklamalar var olmayan şık metinlerini alıntılıyordu.

**İngilizce ve mantık**

- `ys1u10l4#0–4`: Parçada gözlemevi bir teleskopla karşılaştırılıyordu → "than any other observatory".
- `ys3u5t#2–3`: Parçada "loud noise reduced performance in all groups" yazıyordu, oysa yüksek gürültü yalnızca bir gruba uygulanmıştı.
- `ys4u9t#14`: "a lasting short-term effect" ifadesi kendi içinde çelişkiliydi.
- Deniz karakteri kursun genelinde erkek (he/his). `s6u1s`, `s6u6s` ve `s8u1l4#6` "she/her" kullanıyordu; düzeltildi.

**Tekrar**

- `s5u7l1#7` ile `s3u3l4#4` aynı çeviri sorusuydu ("Bana doğruyu söyledi."). Birincisi "Ona doğruyu söyledim." yapıldı.
- `s8u9l4#1` ile `s4u10l4#1` aynı boşluk sorusuydu. Birincisi "We look forward to ___ with you again." yapıldı.
- YDS kelime ünitelerinde rehberdeki çözümlü örnekle birebir aynı 7 soru vardı: `ys2u6l4#2`, `ys2u7l3#7`, `ys2u8l2#3`, `ys2u9l2#4`, `ys2u10l2#10`, `ys2u11l3#8`, `ys2u12l2#2`.
  - Bu soruların cümleleri değiştirildi; hedef kelime ve doğru şık aynı kaldı.
  - Böylece öğrenci rehberdeki cevabı hatırlamak yerine aynı kalıbı yeni bir cümlede kullanıyor.

**Çeviri varyantları**

Sık yazılacak doğru cevaplardan eksik olanlar eklendi. Örnekler:

- "I am going to call you back later"
- "Kahve çekirdekleri satılmadan önce kavrulurlar"
- "polite" (kibar)
- "I prefer going camping to scuba diving"

## Reddedilen şüpheler (13)

Bunlar `fillBlank` sorularıydı: `s3u2l1#4`, `s3u2l2#1`, `s3u2l2#3`, `s3u3l1#2`, `s3u3l1#4`, `s3u3l2#3`, `s3u3l3#3`, `s3u4l1#2`, `s3u4l2#2`, `s3u4l3#3`, `s3u4l4#1`, `s3u6l4#4`, `s6u2l3#4`.

- İnceleyici, "We go to Büyükada on Sunday" gibi şimdiki zamanlı çeldiricilerin de dilbilgisel olarak doğru olduğunu öne sürdü.
- Ancak `fillBlank` ekranı Türkçe çeviriyi gösteriyor (`lib/exercises/fill_blank_exercise.dart`). Çeviri zamanı ve anlamı belirliyor ("gittik", "sürdü").
- Bu çeldiriciler dersin öğrettiği karşıtlığın kendisi (geçmiş ve şimdiki zaman, past perfect ve past continuous). Ünitenin amacı bu ayrımı çalıştırmak.
- İkinci çözücü, çeviriyle birlikte her birinde tek doğru şık olduğunu doğruladı.

## Düzeltilemeyen ve kararsız kalanlar

**Sınırda, düzeltme yapılmadı**

- `s2u6l2#2`, `s2u10l2#1`: "Are there some…?" soru cümlesinde teklif ya da olumlu beklenti için mümkün. Çeviri "hiç" dediği için cevap *any*. Ders some/any ayrımını öğretiyor.
- `s3u3l2#1`: *brought* İngilizce olarak doğru, ama çeviri "aldı" (*bought*). bought/brought ayrımı dersin hedefi.
- `s7u3l3#4`: *must/should have seen* bağlamsız okunursa savunulabilir. Çeviri "görmemiş olabilir" diyerek *may not*'u belirliyor.
- `s7u10l2#2`: "highly concerned" kullanımda var, ama "deeply concerned" kadar yerleşik değil.
- `ys2u6l4#4`: "adapt local customs" geçişli kullanımla zorlanabilir. "while preserving their own traditions" zıtlığı *adopt*'u açıkça seçtiriyor.
- `ys1u14l4#5`: "The availability of clean drinking water is one of the biggest problems" ifadesinde sorun aslında suyun yokluğu. Yaygın bir kullanım olduğu için bırakıldı.

**Benzer ama kopya değil (not)**

- `s5u12l2#8` ile `s5u6l2#8`: tekrar ünitesinde, farklı alıştırma türü.
- `s7u4l3#1`: "In my opinion" kalıbı üçüncü kez soruluyor. Bunlardan `s7u10l1#6` "As far as I'm concerned" kalıbına çevrildi.
- `ls2u5l2#0` ile `ys1u13l3#3`: farklı kurslar.
- `ys1u4t#5` ile `ys1u4l3#6`: aynı şıklar, farklı cümleler.
- `ys4u9l3#5` (Kerro adası) ile `ys4u6t#12–13` (Pereth adası): içerik çok benzer, soru türleri farklı. Gelecekte biri başka bir konuya taşınabilir.

## İkinci tur (v2)

İlk turdan sonra iki karar alındı ve uygulandı.

**1. Rehber örneğiyle aynı alıştırmalar: alıştırma değişir, rehber kalır**

- Kural: Rehberin öğretici örneği aynen kalır. Onunla birebir ya da neredeyse aynı olan alıştırma, aynı beceri ve zorlukta yeni bir cümle, parça ve şıklarla yeniden yazılır.
- ID, alıştırma türü, şık sayısı ve doğru şıkkın konumu değişmez.
- Bütün sınav dosyalarında rehber ile alıştırma arasındaki 5 kelimelik dizi örtüşmesi tarandı.
  - İlk turda not edilenlerle birlikte 57 kopya bulundu: LGS'de 4, YDS'de 53. Hepsi yeniden yazıldı.
  - Tarama tekrarlandığında yalnızca hedef kalıbın kendisi ortak kaldı ("Have you ever been to").
- Okuma parçası ortak olan dört soruda (`ys3u11l2#1`, `ys3u11l2#5`, `ys3u11l3#7`, `ys4u8l2#0`) parçaya dokunulmadı; yalnızca soru değişti.
- Parçanın kendisi rehber örneği olan dört soruda (`ys3u7l2#6`, `ys3u9l2#6`, `ys3u10l3#3`, `ys4u9l2#2`) yeni parça yazıldı.
- Yeni 57 soru, cevapları gizlenerek bağımsız bir çözücüye verildi. Hepsinde tek doğru şık bulundu ve sonuç anahtarla aynıydı.
  - Sınırda kalan tek çeldirici düzeltildi: `ys1u6l2#5`'te "That" yerine "Unless".

**2. Şıkkı konumla anma kuralı genişletildi (`content_quality_test`)**

- Kural tek bir yardımcı işlevde (`_namesOptionByPosition`) toplandı. Artık şu biçimler de yakalanıyor:
  - "birinci şık", "sonuncu şık"
  - "seçeneği" gibi ekli biçimler (eski kural "seçenek" yazımını arıyordu, "seçeneği"ni kaçırıyordu)
  - Büyük harfle "İkinci" (Dart, büyük/küçük harf duyarsız eşleşmede İ harfini i'ye çevirmiyor)
  - Harfli biçimler: "A şıkkı", "C) seçeneği"
- Kuralın kendi testi var.
- Mevcut içerikte yeni kurala takılan üç açıklama şık metniyle yeniden yazıldı: `ys1u8l4#0` ve `assets/exams/yds.json` içinde iki soru.

## Sonraki adımlar için öneriler

- `tr_en.json` (Bölüm 1) ve `pro_*.json` için aynı tur yapılabilir.
