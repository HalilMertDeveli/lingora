# İçerik kalite raporu

Tarih: 10 Kasım 2026 · Dal: `feature/icerik-kalite`

Bu rapor, uygulamadaki tüm içerik dosyalarının ilk kapsamlı gözden geçirmesini anlatır. İçerik daha önce yapay zekâ
ajanlarıyla hızlıca yazılmış ve hiç incelenmemişti. Her dosya baştan sona okundu, hatalar doğrudan JSON'da düzeltildi
ve bulunan hata türlerinin tekrar etmemesi için otomatik testler eklendi.

## Neye bakıldı

- **İngilizce:** dil bilgisi doğruluğu ve doğallık (gerçek hayatta böyle söylenir mi?).
- **Türkçe:** doğallık, yazım ve Türkçe karakterler (ı ş ğ ü ö ç İ), çeviri kokan (calque) ifadeler.
- **Çeviri eşleşmesi:** İngilizce cümle ile Türkçe karşılığı aynı şeyi mi söylüyor?
- **Cevapların doğruluğu ve tekliği:** çoktan seçmeli/boşluk doldurmada yalnızca bir savunulabilir seçenek olmalı;
  çeldirici dil bilgisi açısından da doğruysa soru hatalıdır.
- **Kabul edilen cevap listeleri:** çeviri ve dinleme alıştırmalarında yaygın doğru varyantlar (kısaltmalar,
  "I'm"/"I am", zamirli/zamirsiz Türkçe, siz/sen, rakam/yazı) eksik mi?
- **Açıklamalar:** sınav ve quiz açıklamaları anahtarla tutarlı ve doğru mu?
- **Seviye uygunluğu:** A1 içerikte B2 dil bilgisi, okuma metinlerinde seviyeye göre cümle uzunluğu.
- **Tutarlılık:** hikâye karakterleri (Elif, Kerem, Sam) ve olay örgüsü üniteler arasında çelişiyor mu?
- **Özgünlük:** sınav soruları formata benzemeli ama gerçek ÖSYM/MEB sorularından ya da bilinen ders kitabı
  cümlelerinden kopya olmamalı.
- **Uygunsuz içerik ve kişisel veri.**

Kimlikler (`id`) hiç değiştirilmedi, böylece kullanıcıların ilerlemesi korunur. Sahibin kendi notlarında
(`grammar.json`, `words.json`) yalnızca gerçek hatalar düzeltildi; üslup, yapı ve kişisel anlatım olduğu gibi kaldı.

## Dosya ve kategori bazında düzeltme sayıları

Toplam: **yaklaşık 297 düzeltme** (bazı satırlarda birden çok değişiklik var; "eksik varyant" sayısı alıştırma
başına sayıldı).

| Dosya | Toplam | Dağılım |
|---|---:|---|
| `courses/tr_en.json` | 60 | belirsiz cevap 12, eksik varyant 38, Türkçe doğallık 3, çeviri uyumsuzluğu 2, İngilizce 2, tutarlılık 2, yinelenen cevap 1 |
| `courses/pro_tourism.json` | 58 | eksik varyant 43 (~130 varyant), belirsiz cevap 6, Türkçe doğallık 4, Türkçe yazım 3, İngilizce 2 |
| `courses/pro_interview.json` | 40 | eksik varyant 31 (~85 varyant), Türkçe doğallık 3, Türkçe yazım 2, İngilizce 2, çeviri 1, belirsiz cevap 1 |
| `exams/yds.json` | 7 | açıklama hatası 3, belirsiz çeldirici 2, özgünlük 1, (bir soruda iki düzeltme) |
| `exams/lgs.json` | 2 | ipucu sızıntısı (a/an) 1, İngilizce 1 |
| `notes/grammar.json` | 12 | İngilizce örnek 3, kural hatası 2, çeviri 2, olgu hatası 2, Türkçe yazım 1, içe aktarma kalıntısı 1, diğer 1 |
| `notes/lessons.json` | 39 | İngilizce örnek/formül 12, belirsiz quiz 9, kural hatası 8, açıklama 3, biçim 3, seviye 2, Türkçe 1 |
| `notes/words.json` | 47 | İngilizce yazım 22, Türkçe yazım 13, örnek cümle 7, içe aktarma kalıntısı 4, yanlış anlam 1 |
| `notes/meta.json` | 0 | — |
| `reading/stories.json` | 18 | çeviri/sözlük 7, Türkçe ek gösterimi 7, İngilizce 2, mantık 2 |
| `pronunciation/units.json` | 9 | fonetik 6, Türkçe açıklama 1, yazım ipucu 1, diğer 1 |
| `placement/questions.json` | 5 | belirsiz cevap 4, açıklama 1 |

**Hiçbir dosyada yanlış cevap anahtarı bulunmadı.** En yaygın gerçek hata, ikinci bir doğru seçeneğin bulunmasıydı
(toplam ~34 soru). İkinci en yaygın eksik ise çeviri alıştırmalarında doğru olduğu hâlde reddedilecek varyantlardı.

## Dikkat çeken örnekler (önce → sonra)

**Birden fazla doğru seçenek**

- `tr_en` u1l1: "Good ___!" seçenekleri `morning / night / thanks`. "Good night!" de doğruydu → `morning / hello / thanks`.
- `tr_en` u5l3: "How ___ is this?" seçenekleri `much / many / old`. "How old is this?" da doğruydu → `old` yerine `very`.
- `tr_en` u9l2: "They ___ to the station" sorusunda geniş zaman `walk` da doğruydu → `walking`.
- `tr_en` u2l2: "I eat an ___." → `an` artikeli `bread` ve `cheese`'i baştan eliyordu. Soru, artikeli öğretecek
  şekilde değiştirildi: "I eat ___ apple." (`an / a / two`).
- `yds_grammar_010`: "essential that" sonrası `has signed` İngiliz İngilizcesinde kabul edilebilir → `to sign`.
- `lessons` past_continuous: iki çeldirici ("When the alarm was ringing, I woke up.") dil bilgisi açısından doğruydu
  → açıkça yanlış biçimlerle değiştirildi.
- `placement` b2_v1: `oppose` da boşluğa uyuyordu → değiştirildi.

**Kural ve açıklama hataları**

- `lessons` connectives ve `grammar` tm_baglac_zitlik: *on the contrary* iki grubu karşılaştırmak için yanlış
  kullanılmıştı ("The men were rude; on the contrary, the children were polite") → *in contrast*. Açıklamada
  *on the contrary*'nin önceki ifadeyi reddettiği gösterildi.
- `grammar` yt_relative_clauses: "that her zaman who/which yerine kullanılabilir" → virgüllü (non-defining) yan
  cümlelerde kullanılamayacağı eklendi.
- `lessons` past_perfect: "hatalı" diye gösterilen cümle aslında doğruydu → gerçek bir hatayla değiştirildi.
- `yds_conj_011`: "neither/nor" açıklaması "anket hiç yapılmadı" diyordu → "ne çevrim içi ne de telefonla yapıldı".
- `yds_translation_011`, `yds_reading_004`: açıklama yanlış seçeneği suçluyordu ("ikinci seçenek").

**Türkçe**

- `pro_interview` i3l3: "Maaş konusunda esnekim." → "esneğim".
- `pro_tourism` t2s: "Bunun için üzgünüm." (çeviri kokuyor) → "Bunu duyduğuma üzüldüm."
- `pro_tourism` t4l2: "beş dakika yürüme mesafesinde" → "beş dakikalık yürüme mesafesinde".
- `tr_en` u12s: "Eyvah! Seni özleyeceğiz" → "Olamaz! …" ("eyvah" bir terslik için söylenir).
- `grammar` eb2_be_supposed_to: "aren't supposed to write" → "yazman gerekmiyor" yanlıştı → "yazmaman gerekiyor".

**İngilizce, tutarlılık, olgu**

- `pro_interview` i2l2: "I use Excel very well" → "I am very good at Excel".
- `pro_tourism` t5s: "Please have a free coffee" → "Please have a coffee on us".
- `tr_en` u3s/u4s: Sam 20 yaşında, kız kardeşi de "twenty" idi (istemeden ikiz) → kardeşi on altı yaşında.
- `grammar` yt_plural_nouns: "Spiders are insects" (örümcekler böcek değildir) → "Ants are insects".
- `pronunciation` th_voiceless: sert /θ/ ünitesinin örnek cümlesindeki "breathe" yumuşak /ð/ içeriyordu → değiştirildi.
- `pronunciation` stress_schwa: vurgu farkı olmayan çiftler (comfortable/comfort, record/reward) →
  history/historic, Japan/Japanese.
- `yds_conj_010`: bilinen ders kitabı cümlesi "Take an umbrella in case it rains" → özgün, akademik bir cümle.

## Kod tarafında yapılan küçük düzeltme

`normalizeAnswer` (lib/core/text.dart) Türkçe büyük **İ** harfini Dart'ın `toLowerCase`'i ile "i̇" (birleşik noktalı)
yapıyordu; bu yüzden "İzmir'e gittik" ile "izmir'e gittik" eşleşmiyordu. Artık İ, küçültmeden önce i'ye çevriliyor
(test eklendi). Kelime bankası kontrolleri de aynı normalleştirmeyi kullanıyor.

## Eklenen otomatik testler (`test/content_quality_test.dart`)

- Tüm içerik dosyalarında: baştaki/sondaki boşluk, çift boşluk, içe aktarma kalıntıları (`**`, `&nbsp;`, HTML
  etiketi, bozuk karakter) ve Türkçe karaktersiz yazılmış yaygın kelimeler (ör. "tesekkurler", "ogrenci", "guzel",
  "degil"; `id` alanları hariç).
- Kurslar: normalleştirme sonrası yinelenen kabul edilen cevap yok; seçim, boşluk doldurma, eşleştirme ve hikâye
  sorularında seçenekler büyük/küçük harf farkı gözetmeden benzersiz; boşluk doldurmada tam bir `___` ve a/an
  ipucu sızıntısı yok; genel kursun ilk üçte birinde cümleler ≤ 10, sonrasında ≤ 16 kelime.
- Sınavlar, seviye testi ve gramer yolu quizleri: seçenekler büyük/küçük harf farkı gözetmeden benzersiz, boşluk
  önündeki a/an seçenekleri elemiyor, açıklamalar seçenekleri sırayla ("ikinci seçenek") anmıyor.
- Okuma: seviyeye göre en uzun cümle sınırı (A1 20, A2 28, B1 35 kelime).

## Ana dili İngilizce olan bir insanın / içerik sahibinin bakması gerekenler

**Genel kurs ve meslek kursları**

- Sam'in zaman çizelgesi: 20 yaşında "öğrenci" ve Elif'le "okulda" tanışıyor. "Okul" üniversite mi, Elif kaç yaşında?
- u5s: 80 liralık ceketin "ucuz" denmesi bugünkü fiyatlarla gerçekçi değil.
- "I feel sick" → "Kendimi hasta hissediyorum" (İngiliz İngilizcesinde genelde "midem bulanıyor" anlamı).
- "I would like a coffee" → "Bir kahve rica ediyorum" yeterince doğal mı?
- Meslek kurslarında gerçek kurum adları geçiyor (İstanbul Üniversitesi, Ege, Excel). Kural gereği genel adlarla
  değiştirilmesi düşünülebilir. Wi-Fi şifresi "lale2024" eskimiş görünecek.
- Bazı boşluk doldurma sorularında çeldirici hâlâ dil bilgisi açısından doğru; doğru cevabı yalnızca altındaki Türkçe
  çeviri belirliyor. Kabul edilebilir ama ideal değil.

**Sınavlar**

- YDS kelime ve cümle tamamlama çeldiricileri gerçek ÖSYM sorularından çok daha kolay (anlamca saçma seçenekler);
  soru eleme ile çözülebiliyor. Bir uzmanın zorluğu artırması gerekir.
- Okuma parçalarındaki olgular (ör. 1884 Meridyen Konferansı) bir konu uzmanınca teyit edilmeli.

**Sahibin notları (`grammar.json`, `words.json`) — üsluba dokunulmadı, karar sahibin**

- Hafıza hikâyelerinde gerçek kişilere ait olabilecek ilk adlar (Ahmet, Ayşe, Osman, Sıla, Esma…) ve `w_pristine`'de
  bir aile kavgası anlatısı var. Yayından önce anonimleştirilmesi düşünülmeli.
- `w_elegant` hikâyesinde kaba sayılabilecek bir ifade ("elin gayinin").
- Bozuk olup güvenle onarılamayan hikâyeler: `w_brief`, `w_originate`, `w_alias`, `w_compose`, `w_scratch`.
  Kelimeyle uyuşmayan hikâyeler: `w_instantiate`, `w_density`, `w_favor`.
- Türkçesi tamamen aynı olan sekiz kelime çifti (impact/influence, tie/bind, ambiguous/vague, evaluation/assessment
  vb.) aynı quizde birlikte çıkarsa iki doğru cevap olur. Bu, kod tarafında `wordQuizItems` içinde aynı Türkçeye
  sahip seçenekleri filtreleyerek çözülebilir (içerikte bırakıldı).
- `grammar.json`'da tartışmalı ~16 madde (present simple, "I wish", "on the contrary/in other words" açıklamaları;
  "a few = biraz", "over there = tam orada" gibi kaba karşılıklar).
- `lessons.json`'da kasıtlı bırakılan sınırda "hatalar": "best student of the class", telefonda "Hello, I am
  Caroline", "didn't used to".

**Telaffuz ve okuma**

- i/ee ve diğer ünitelerdeki Türkçe ağız konumu tarifleri bir fonetikçi tarafından kontrol edilmeli.
- `b1_developer` hikâyesinin kahramanının adı "Can", "can" fiiliyle karışabilir.

## Kapsam dışı (sonraki PR)

Bu inceleme `main`'deki mevcut içerik dosyalarını kapsar. #14 (sınav paketleri) ve #12 (`assets/vocab/software.json`)
ile gelen yeni dosyalar birleştikten sonra ayrı bir PR'da incelenecek; yeni testler `assets/` altındaki tüm JSON
dosyalarını otomatik olarak tarar, bu yüzden o dosyalar da genel kontrollere girecek.
