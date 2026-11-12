# Genel kurs müfredatı: derinleştirme ve C1

Dayanak: [genel-arastirma.md](genel-arastirma.md). Bu belge içerik ekibinin (genel-icerik) çalışma spesifikasyonudur. Her faz ayrı bir PR'dır ve kendi başına çalışır durumda olmalıdır.

**Hedef:** Kursu bitiren kişi dört beceride B2'yi (Faz 4–5'ten sonra C1'i) gerçekten yapabilsin. Her bölümün sonunda bunu ölçen bir beceri testi olsun.

---

## 1. Genel yapı

```
Bölüm N (mevcut, dokunulmaz)          Bölüm N ek dosyası (yeni)
 uN1 … uN12  dil üniteleri      →      sNu13 … sNu15  beceri üniteleri
 son test = bölüm kilidi (aynı)        son ünitenin testi = bölüm beceri testi
```

- Mevcut ünite ve düğüm ID'leri değişmez. Bölüm kilidi değişmez: bir sonraki bölüm hâlâ temel dosyanın son ünite sınavıyla açılır.
- Beceri üniteleri bölümün sonunda durur. Ama dilbilgisi olarak yalnızca o bölümün ve önceki bölümlerin yapılarını kullanır. Kullanıcı bölümü bitirmeden ileri geçebilir; "bölüm tamamlandı" rozeti ise beceri testini ister.
- Hedef pay:
  - A1–A2'de zamanın ~%30'u beceri ünitelerinde geçer.
  - B1–B2'de bu pay ~%45'e çıkar. Bu oran, dört kol dengesini (araştırma §5.1) yavaş yavaş kurar.

### Beceri ünitesi deseni

Desen mevcut desenle aynı: `lesson, lesson, story, lesson, lesson, test, chest`.

| Düğüm | Rol | Faz 1'de kullanılan türler | Faz 2+ ile eklenenler |
|---|---|---|---|
| `l1` | **Dinleme dersi** | `listen` ×5–6 (bağlantılı konuşma içeren cümleler), `fillBlank` ×2 (zayıf biçim, ör. *I'd like ___ tea*), `speak` ×1 (aynı cümleyi tekrar), `match` ×1 (kalıplar) | `shadow` |
| `l2` | **Okuma dersi** | Bir metin üzerine `choice` ×4–5 (`passage` aynı metin, 4 şık, Türkçe açıklama), `match` ×1–2 (metindeki kelimeler), `select` / `fillBlank` ×2 | Daha uzun metin (B1+) |
| `s` | **Dinleme hikâyesi** | Story: 14–20 satır, 4–5 soru. En az 2 soru duyulan ayrıntıyı sorar (sayı, saat, isim, yer), en az 1 soru zamir veya çıkarım ister. | `"listenFirst": true` |
| `l3` | **Konuşma dersi** | `speak` ×4–5 (bir diyaloğun öğrenci repliklerini sırayla söyletir: tam bir "tur"), `select` ×2 ("En uygun cevap hangisi?", pragmatik), `translate` ×2 (konuşma dilinde tr→en), `match` ×1 | `shadow`, ünitenin Konuş senaryosu |
| `l4` | **Yazma dersi** | `translate` ×4 (sırayla birleşince model metni oluşturan cümleler: mesaj, e-posta, paragraf), `fillBlank` ×3 (bağlaç, artikel, noktalama, kalıp), `select` ×1 (üslup / biçim: selamlama, kapanış), `match` ×1 | `write` (serbest metin, model, kontrol listesi, yapay zekâ geri bildirimi) |
| `t` | Ünite sınavı | Boş bırakılır, derslerden örneklenir. Bölümün son beceri ünitesinde **bölüm beceri testi** olur (§4). | |
| `c` | Sandık | Mevcut gibi. | |

Ünite alanları: `id`, `title`, `description`, `color`, `theme` (zorunlu, `lib/data/topic_themes.dart`'taki kimliklerden biri) ve `guide`. `guide` markdown biçimindedir ve şunları içerir:

- **Bu ünitede yapabileceklerin:** 3–4 can-do ifadesi, Türkçe.
- **Strateji:** Nasıl dinlenir, okunur, konuşulur ya da yazılır; 3–5 madde.
- **Model metin:** l4'ün birleşik hâli.
- **Türklerin sık hatası:** 2 madde.

Uygulama `guide`'ı tr_en ünitelerinde göstermiyorsa bu Faz 1a'da eklenir (§3).

---

## 2. Bölüm bölüm plan

Her ünite için: can-do (CEFR satırından), görev ve Türk hatası odağı. Kelime kuralı:

- Ünite başına en fazla 25 yeni lemma.
- Aynı bölümün önceki ünitelerinden en az 15 kelime ve 2 yapı yeniden kullanılır (sarmal).
- Kadro mevcut: Elif, Kerem, Sam, Mia, Deniz… Bölümün hikâye çizgisi sürdürülür (`side-session-notes` dosyalarındaki dersler-a, dersler-b1 ve dersler-b2 notlarına bakın).

### Faz 1: A1–A2 (S1–S4), 12 ünite

**S1 Temeller (A1)**: ek dosya `tr_en/01x_beceri.json`, `"extends": "s1"`. S1 ünite id'leri `u1..u12` olduğu için yeni id'ler `u13..u15` (altyapı S1 için `u` önekini bekler).

| Ünite | Başlık | Can-do | Dinleme / okuma | Konuşma / yazma | Türk hatası odağı |
|---|---|---|---|---|---|
| u13 | Adım, numaram | Adını heceler; telefon ve e-posta söyler ve anlar; form doldurur | Harf ve sayı dikte (*thirteen/thirty*, *a/e/i* harf adları), kayıt formu okuma | Kendini tanıtma turu; üyelik formu cümleleri | *I am ~~a~~* atlama; *my name is* / *I'm* |
| u14 | Kafede ve markette | Fiyatı ve miktarı anlar; menüden sipariş verir | Fiyat dinleme (*£3.50*, *fifteen/fifty*), menü ve fiyat etiketi okuma | Sipariş diyaloğu; alışveriş listesi | *a/an*, *some*, çoğul (*two coffee~~s~~*) |
| u15 | Kısa mesajlar | Kısa mesajları okur ve yazar; saat ve yer belirler | Sesli mesaj (saat ve yer), arkadaş mesajları okuma | Buluşma ayarlama; 3–4 cümlelik mesaj yazma | *at 5*, *on Monday*, *in the park*; soru dizilimi |

**S2 Günlük hayat (A1)**: `tr_en/02x_beceri.json`, `s2u13..s2u15`.

| Ünite | Başlık | Can-do | Dinleme / okuma | Konuşma / yazma | Türk hatası odağı |
|---|---|---|---|---|---|
| s2u13 | Bir günüm | Günlük rutinini 5–6 cümleyle anlatır; başkasının rutinini anlar | Bir öğrencinin günü (dinleme), kısa blog yazısı | 30 saniyelik rutin anlatımı (speak turu); 5 cümlelik paragraf | 3. tekil *-s*, *does/doesn't*, sıklık zarfının yeri |
| s2u14 | Nasıl giderim? | Yol tarifi sorar, verir ve anlar | Tarif dinleme (*second left*, *opposite*), tabela okuma | Yol sorma diyaloğu; arkadaşa adres tarifi mesajı | *go to ~~the~~ home*, *next to*, emir kipi |
| s2u15 | Davet | Davet eder; kabul eder ya da kibarca reddeder | Telefonda davet, davetiye okuma | Kabul/ret turu; davet mesajı yazma | *Would you like to…?*, *can* sonrası yalın fiil, *I ~~am~~ agree* |

**S3 Kendini anlatmak (A2)**: `tr_en/03x_beceri.json`, `s3u13..s3u15`.

| Ünite | Başlık | Can-do | Dinleme / okuma | Konuşma / yazma | Türk hatası odağı |
|---|---|---|---|---|---|
| s3u13 | Geçen yaz | Geçmiş bir olayı sırayla anlatır | Arkadaşın tatil anlatısı, kartpostal ya da blog | 45 saniyelik anı anlatımı; 6–8 cümlelik kartpostal | Düzensiz geçmiş biçimleri; *first / then / after that*; *he/she* takibi |
| s3u14 | Anons var | Kısa duyurulardaki kritik bilgiyi alır; bilgi sorar | Tren, havalimanı ve market anonsları; tarife okuma | Danışmada bilgi sorma; arkadaşa değişikliği bildiren mesaj | Saat ve peron sayıları, *delayed / cancelled*; dolaylı soru öncesi kalıp |
| s3u15 | Teşekkürler, özür dilerim | Kısa kişisel e-posta yazar (teşekkür, özür, açıklama) | Sesli mesaj, kişisel e-posta okuma | Özür dileme turu; 60–80 kelimelik e-posta | *because / so*; *thank you for ~~to~~ + -ing*; artikel |

**S4 Şehirde ve işte (A2)**: `tr_en/04x_beceri.json`, `s4u13..s4u15`.

| Ünite | Başlık | Can-do | Dinleme / okuma | Konuşma / yazma | Türk hatası odağı |
|---|---|---|---|---|---|
| s4u13 | Doktorda ve eczanede | Şikâyetini anlatır; talimatı anlar | Doktor ve eczacı konuşması, ilaç prospektüsü (basitleştirilmiş) | Randevu alma ve belirti anlatma; okula ya da işe mazeret mesajı | *I have a headache* (artikel), *since/for*, *should* |
| s4u14 | Bir sorun var | Ürün veya hizmetle ilgili sorunu açıklar, çözüm ister | Müşteri hizmetleri telefonu, iade politikası okuma | Şikâyet turu; kısa şikâyet e-postası | *It doesn't work*, present perfect (*I've already tried*), kibarlık (*Could you…*) |
| s4u15 | İşimi anlatıyorum | İşini ya da okulunu 1 dakikada anlatır; kısa profil yazar | İş tanıtım konuşması, iş ilanı okuma | 1 dakikalık tanıtım (speak turu); 80 kelimelik profil | *I work as ~~a~~*, *responsible for*, gerund |

Faz 1 toplamı:

| Kalem | Sayı |
|---|---|
| Ünite | 12 |
| Ders | 48 (~460 alıştırma) |
| Dinleme hikâyesi | 12 |
| Bölüm beceri testi | 4 × 20 soru |
| Okuma metni | ~12 (A1 60–90 kelime, A2 100–150) |

Tahmini ek süre: ~8 saat ders, ~2 saat test.

### Faz 2: B1–B2 (S5–S8), 12 ünite + yeni türler

Faz 2 altyapısı (§3) birleştikten sonra yazılır. Her ünitede en az bir `write` ve bir `shadow` bulunur; hikâyeler `listenFirst` olur.

| Ünite | Başlık | Can-do | Ana görev |
|---|---|---|---|
| s5u13 | Bir anı anlat | Deneyimi ayrıntılarla ve duygularla anlatır | 1 dakikalık anlatım; 120 kelimelik hikâye (`write`) |
| s5u14 | Haberi aktar | Kısa bir haberin ana noktalarını başkasına aktarır (**aracılık**) | 2 dakikalık radyo haberi; İngilizce haberin Türkçe özeti ve Türkçe notun İngilizce özeti |
| s5u15 | Bir sorunu çözelim | Resmî bir şikâyet ya da talep yazar | Belediyeye veya şirkete 120–150 kelimelik e-posta |
| s6u13 | Film ve kitap yorumu | Bir eser hakkında görüşünü gerekçeyle yazar | 150 kelimelik yorum; yorumları karşılaştırma okuması |
| s6u14 | Bence… çünkü… | Forumda görüş bildirir, karşı görüşe yanıt verir | Forum zinciri okuma; 100 kelimelik yanıt; görüş turu |
| s6u15 | Dönüm noktası | Hayatından bir dönüm noktasını sunar | 2 dakikalık sunum (4/3/2); blog yazısı |
| s7u13 | Artılar ve eksiler | Bir konunun lehine ve aleyhine yazar | 180–220 kelimelik deneme (giriş, iki görüş, sonuç) |
| s7u14 | Bir konuşmayı izle | 3–4 dakikalık sunum veya podcastten not alır | Not alma ve özet; dictogloss |
| s7u15 | Toplantıda ikna | Öneri sunar, itirazı karşılar | Teklif e-postası; Konuş senaryosu "toplantı" |
| s8u11 | Rapor | Veri ve bulguları rapor biçiminde yazar | 200 kelimelik rapor (başlıklar, öneriler) |
| s8u12 | Podcast tartışması | Hızlı, doğal tartışmayı izler; konuşmacıların tutumunu ayırır | 4 dakikalık iki kişilik tartışma; tutum soruları |
| s8u13 | Mülakat | İş mülakatında kendini ayrıntılı ve esnek anlatır | Mülakat simülasyonu (Konuş); ön yazı (cover letter) |

S8'de 10 ünite olduğu için id'ler `s8u11..s8u13`.

### Faz 4–5: C1 (S9–S10)

Yeni bölüm dosyaları `tr_en/09_derinlik.json` ve `tr_en/10_ustalik.json`. Bunlar ek dosya değil, normal bölüm dosyası. S9, S8'in son sınavıyla açılır; mevcut mantık ilerlemeyi bozmaz. Her biri 12 ünitedir. C1'de beceri dersleri bölümün içinde: dört dersten ikisi dil, ikisi beceri dersi (dinleme/konuşma ya da okuma/yazma, sırayla).

**S9 Derinlik (C1).** Dilbilgisi:

- katılımcı ve kısaltılmış cümleler (*Having finished…*),
- adlaştırma (nominalisation),
- ileri devrik yapı (*Not only… / Rarely…*),
- vurgu (*What I need is…*, *It was… that*),
- ileri çıkarım kipleri (*might have been*),
- subjunctive (*I suggest he be*),
- eksiltme ve yerine koyma (*so do I*, *I hope so*),
- ileri bağlaçlar,
- ileri phrasal verbs ve eşdizimler.

Beceri: akademik dersten not alma, uzun makale, ikna edici konuşma, tartışmalı deneme.

**S10 Ustalık (C1).** Üslup ve aracılık:

- resmî / samimi yazışma geçişleri,
- dolaylı eleştiri ve diplomasi,
- deyim ve mecaz,
- dizi ve film dili (konuşma dili, argo farkındalığı),
- müzakere,
- rapor ve teklif,
- özetleme ve aktarma (aracılık),
- sunum ve soru-cevap,
- edebi metin.

Bölüm sonu: C1 beceri testi.

Süre: iki bölüm ~25–30 saat ders ve 20+ saat açık uçlu görev.

---

## 3. Altyapı gereksinimleri

### Faz 1a: ek dosya (Faz 1 ile aynı PR'da olabilir)

1. **Ek bölüm dosyası.** `assets/courses/tr_en/NNx_slug.json`, biçim `{"extends": "sN", "units": [...]}`, `section` alanı yok.
   - `loadSections` bunu, id'si `sN` olan bölümün ünitelerinin sonuna ekler. Sıralama dosya adına göre: `02_…` < `02x_…`.
   - S1 `tr_en.json` içinde olduğu için `01x_beceri.json`, `after` kursunun bölümünü (s1) genişletir.
   - Çakışan id ya da bozuk dosya: yalnızca ek dosya atlanır ve loglanır, temel bölüm etkilenmez.
2. **Bölüm kilidi sabit.** `Section.exam`, temel dosyanın son `test` düğümü olarak kalır. Ek üniteler kilidi taşımaz.
   - Bir test eklenmeli: "S2'nin temel sınavını geçmiş kullanıcı, ek üniteler eklenince de S3'e girebilir."
   - "Bölüme atla" (`sectionSkipItems`) ek üniteleri de kapsayabilir; bu serbest.
3. **`course_content_test`:**
   - Ek dosyalar da aynı ünite ve alıştırma kurallarıyla doğrulanır.
   - Dosya adındaki NN, genişletilen bölümün index'ine eşit olmalı.
   - `extends` var olan bir bölüme işaret etmeli.
   - Ünite id'si `sN` ile başlamalı.
   - Ünite `theme` zorunlu.
4. **`choice` alıştırması tr_en derslerinde.** Ders ekranında çalıştığı ve doğrulamadan geçtiği emülatörde gösterilmeli: 4 şık, `passage`, Türkçe `explanation`.
5. **Test düğümünün kendi soruları (tr_en).** `test.exercises` 15–20 soru ise bunlar kullanılır (`practice.dart` zaten böyle). Doğrulama:
   - türler `listen`, `choice`, `translate`, `fillBlank`, `select` olabilir; `speak` ve `match` olmaz,
   - her biri `validateExercise`'tan geçmeli.
6. **`guide` tr_en ünitelerinde.** Ünite başlığında "Rehber" düğmesi; sınav yolundaki bileşen yeniden kullanılır. Zaten varsa dokunulmaz.

### Faz 2a: yeni türler (ayrı PR; içerik Faz 2 bunu bekler)

```jsonc
// Serbest yazma
{"type": "write",
 "prompt": "Sam'e geçen hafta sonunu anlatan bir e-posta yaz.",   // Türkçe görev
 "model": "Hi Sam, …",                                            // model metin (gönderimden sonra gösterilir)
 "minWords": 60, "maxWords": 100,
 "checklist": ["Selamlama ve kapanış var", "En az 3 geçmiş zaman fiili", "first / then / after that"],
 "focus": ["past_simple", "article"],                             // geri bildirimin odak türleri (en fazla 3)
 "taskId": "s5u13l4w"}
// Tamamlama: kelime sayısı ≥ minWords + kontrol listesi işaretlendi (ücretsiz).
// Premium: sunucu fonksiyonu assessWriting({taskId, text}) → {scores:{task,accuracy,range,coherence} 0–3,
//          corrections:[{from,to,why_tr,type}] (yalnızca focus türleri + en fazla 3 diğer), next_tr}
//          Rubrik ve prompt sunucuda (scenarios.ts gibi). Öğrenciden yeniden yazma istenir.

// Gölgeleme
{"type": "shadow", "text": "…", "translation": "…", "rate": 0.9}
// Akış: dinle (metin gizli) → metinle dinle → birlikte söyle (kayıt + ASR) → kendi kaydını dinle.
// Geçme: kelime eşleşmesi ≥ 0.6 (speak 0.7). Mikrofon yoksa "atla" serbest, ceza yok.

// Metni gizli dinleme hikâyesi
{"type": "story", "listenFirst": true, …}
// Satırlar ses olarak çalınır, metin sorular cevaplanana kadar gizli kalır, sonra "metni gör".
// Hız düğmesi 0.75× / 1×.
```

Ayrıca her B1+ beceri ünitesine bağlı bir **Konuş senaryosu**. `scenarios.ts` ve `scenarios.dart`'a eklenir; ünitede `"scenarioId"` alanı olur. Bitişte 3 maddelik geri bildirim verilir. Yapay zekâ kısmı premium; ücretsiz kullanıcı ünitenin geri kalanını tamamen bitirebilir.

---

## 4. Bölüm sonu beceri testi (bitiş ölçütü)

Her bölümün son beceri ünitesinin `t` düğümü kendi sorularını taşır. Başlık: `"Bölüm N beceri testi"`. Açıklama: `"Bu bölümün hedeflerini ölçer"`.

| Bölüm | Soru | Dinleme (`listen`) | Okuma (`choice` + passage) | Yazma (`translate` cümle / Faz 2+ `write`) | Dil (`fillBlank` / `select`) |
|---|---|---|---|---|---|
| S1–S2 (A1) | 20 | 6 | 6 (2 kısa metin × 3) | 5 | 3 |
| S3–S4 (A2) | 20 | 6 | 6 (2 metin × 3) | 5 | 3 |
| S5–S8 (B1–B2) | 20 + 1 `write` | 6 | 8 (2 metin × 4) | 1 `write` + 3 | 3 |

Kurallar:

- Sorular yeni yazılır; derslerden kopyalanmaz.
- Her soru bölümün can-do tablosundaki bir ifadeye bağlanır. Eşleme `guide`'da listelenir.
- Geçme eşiği mevcut ünite sınavıyla aynı (%80). `write`, kontrol listesiyle tamamlanır.
- Test bir sonraki bölümü kilitlemez. Geçilince bölüm "tamamlandı" sayılır ve sertifika rozeti açılır. Rozet ekranı ayrı bir UI işi; yds-yontem ilerleme analiziyle ortak.
- Konuşma testi Faz 2'de eklenir: ünite senaryosu bitince yapay zekâ rubriği. Premium değilse kendini değerlendirme can-do listesi kullanılır.

---

## 5. Kalite ölçütleri (inceleme listesi)

İçerik PR'larını bu listeyle inceleyeceğim:

1. `flutter test test/course_content_test.dart test/content_quality_test.dart test/konu_temalari_test.dart` geçer.
2. Desen, id ve tema kuralları; ek dosyada `extends`.
3. **Dinleme:**
   - `listen` cümlelerinin en az yarısında bağlantılı konuşma ya da zayıf biçim var (*want to, going to, did you, a lot of, can* zayıf).
   - Sayı ve saat dinlemesi A1–A2'de var.
4. **Okuma:**
   - Metin uzunluğu seviyeye uygun (A1 60–90, A2 100–150, B1 200–300, B2 300–450 kelime).
   - Sorular metinden cevaplanabilir, dünya bilgisiyle cevaplanamaz.
   - Şıklar benzersiz, a/an ipucu yok, açıklama Türkçe ve şıkkı metniyle anıyor (konumla değil).
5. **Konuşma:** `speak` turları gerçek bir diyalog sırası oluşturuyor; tek tek kopuk cümle değil.
6. **Yazma:**
   - l4'ün `translate` cümleleri birleşince tutarlı bir metin çıkıyor.
   - `answers` doğal varyantları kapsıyor: kısaltmalar, *a/the*, *so/therefore*.
7. **Türk hatası:** Her derste en az bir alıştırma §2'deki odak hatayı hedefliyor (yanlış şık ya da yanıltıcı token).
8. **Sarmal kelime:** Ünite başına en fazla 25 yeni lemma; önceki ünitelerden en az 15 kelime yeniden kullanılmış. İçerik ekibi PR açıklamasında sayıyı versin.
9. **Özgünlük:** Ders kitabı, sınav ya da başka uygulama metni kopyalanmamış. Açık lisanslı kaynak kullanıldıysa `docs/kaynaklar.md`'ye yazılmış.
10. Dil doğruluğu: İngilizce doğal (doğal konuşan kontrolü), Türkçe çeviri doğru. Cevap anahtarı bağımsız bir çözümle doğrulanmış.

---

## 6. Faz planı

| Faz | Kapsam | Sahip | Boyut | Bağımlılık |
|---|---|---|---|---|
| **1** (bu tur) | 1a altyapı: ek dosya, kilit sabitleme, test, tr_en `choice`, test soruları, `guide`. 1b içerik: S1–S4 için 12 beceri ünitesi ve 4 bölüm beceri testi. | genel-icerik | ~460 alıştırma + 80 test sorusu + küçük Dart değişikliği | yok |
| **2a** | `write`, `shadow`, `listenFirst`; `assessWriting` sunucu fonksiyonu; ünite–senaryo bağı | altyapı oturumu (orkestra şefi atar) ya da genel-icerik | orta | Faz 1a |
| **2b** | S5–S8 için 12 beceri ünitesi; B1–B2 beceri testleri (`write` ile) | genel-icerik | ~460 alıştırma + 12 `write` + 12 senaryo metni | 2a |
| **3** | Mevcut B1–B2 hikâyelerine `listenFirst`; S1–S4 beceri ünitelerindeki l3/l4'e `shadow` ve `write` eklenmesi (yeni ders değil, alıştırma değişimi ya da ek ders) | genel-icerik | küçük–orta | 2a |
| **4** | C1 Bölüm 9 (12 ünite) | genel-icerik | ~470 alıştırma | 2a |
| **5** | C1 Bölüm 10 (12 ünite) + C1 beceri testi | genel-icerik | ~470 alıştırma | 4 |
| **6** | Okuma ve dinleme kütüphanesi: B1, B2 ve C1 için 20'şer metin (`assets/reading/`, dinleme için TTS). Kelime kapsamı denetimi (NGSL, CC BY-SA 4.0; lisans `docs/kaynaklar.md`'ye). | genel-icerik + okuma | ~60 metin | yok |

Faz sonrası toplam (yaklaşık):

| | Ünite | Ders | Süre |
|---|---|---|---|
| Bugün | 94 | 364 | ~34 sa |
| 5. faz sonu | ~142 | ~556 | ~60 sa ders + 50–80 sa açık uçlu görev |

Kütüphane ve tekrarla birlikte B2 sonuna kadar ~200–250 sa uygulama içi süre. Kalan saat için araştırma §3.1'e bakın.

**Sıra gerekçesi:** A1–A2 en kalabalık kullanıcı kitlesi ve yeni altyapı gerektirmiyor; Faz 1 bu yüzden hemen yazılabilir. B1–B2'deki asıl boşluk (serbest yazma, uzun dinleme) yeni türler olmadan kapanmaz; bu yüzden 2a önce gelir. C1, B2 derinleşmeden eklenirse kursun "genişliği" artar ama "bitiren bilir" hedefi değişmez; bu yüzden C1 en son gelir.
