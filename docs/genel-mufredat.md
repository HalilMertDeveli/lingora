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

- Ünite başına yeni lemma: A1–A2 en fazla 25 (hedef kelime grubu olan ünitede, ör. sayılar, aşılabilir); B1+ en fazla 50, bunların en az 20'si l1–l4'te yeniden geçer.
- Aynı bölümün önceki ünitelerinden en az 15 kelime ve 2 yapı yeniden kullanılır (sarmal).
- Kadro mevcut: Elif, Kerem, Sam, Mia, Deniz… Bölümün hikâye çizgisi sürdürülür (`side-session-notes` dosyalarındaki dersler-a, dersler-b1 ve dersler-b2 notlarına bakın).

### Faz 1: A1–A2 (S1–S4), 12 ünite

**S1 Temeller (A1)**: ek dosya `tr_en/01x_beceri.json`, `"extends": "s1"`. S1 ünite id'leri `u1..u12`; yeni id'ler `s1u13..s1u15` (her ek ünite `sN` önekiyle başlar, test bunu zorunlu tutar).

| Ünite | Başlık | Can-do | Dinleme / okuma | Konuşma / yazma | Türk hatası odağı |
|---|---|---|---|---|---|
| s1u13 | Adım, numaram | Adını heceler; telefon ve e-posta söyler ve anlar; form doldurur | Harf ve sayı dikte (*thirteen/thirty*, *a/e/i* harf adları), kayıt formu okuma | Kendini tanıtma turu; üyelik formu cümleleri | *I am ~~a~~* atlama; *my name is* / *I'm* |
| s1u14 | Kafede ve markette | Fiyatı ve miktarı anlar; menüden sipariş verir | Fiyat dinleme (*£3.50*, *fifteen/fifty*), menü ve fiyat etiketi okuma | Sipariş diyaloğu; alışveriş listesi | *a/an*, *some*, çoğul (*two coffee~~s~~*) |
| s1u15 | Kısa mesajlar | Kısa mesajları okur ve yazar; saat ve yer belirler | Sesli mesaj (saat ve yer), arkadaş mesajları okuma | Buluşma ayarlama; 3–4 cümlelik mesaj yazma | *at 5*, *on Monday*, *in the park*; soru dizilimi |

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

#### Faz 2b ders kalıbı (B1–B2 beceri ünitesi)

Faz 2a'da yds-yontem ile kesinleşen veri modeline göre (§3) yazılır. Desen aynı: `lesson, lesson, story, lesson, lesson, test, chest`.

| Düğüm | İçerik (8–10 alıştırma) |
|---|---|
| `l1` Dinleme | `listen` ×4 (B1 10–16, B2 12–20 kelime; bağlantılı konuşma), `shadow` ×2 (aynı konudan doğal cümleler), `fillBlank` ×2 (zayıf biçim / eşdizim), `match` ×1 |
| `l2` Okuma | Tek metin üzerine `choice` ×5–6 (B1 200–300, B2 300–450 kelime; en az 1 çıkarım ve 1 yazarın tutumu sorusu), `match` ×1, `fillBlank` / `select` ×2 |
| `s` Dinleme hikâyesi | `"listenFirst": true`; B1 250–350, B2 350–500 kelime; 5 soru (2 ayrıntı, 1 ana fikir, 1 tutum veya çıkarım, 1 zamir veya gönderim) |
| `l3` Konuşma | `shadow` ×2, `speak` ×4 (bir uzun konuşma turu, ör. 1 dakikalık anlatım cümle cümle), `select` ×2 (pragmatik, üslup), `translate` ×1 |
| `l4` Yazma | **`write` ×1** (Ana görev tablosundaki metin), hazırlık olarak `translate` ×3 (model metnin anahtar cümleleri), `fillBlank` ×3 (bağlaç, artikel, kalıp), `select` ×1 (üslup / paragraf düzeni), `match` ×1 |

`write` kuralları:

- `taskId` = `<düğümId>w` (ör. `s5u13l4w`). Sunucu rubriği bu id ile tutulur. İçerik PR'ı her görev için rubrik metnini de vermeli: görev başarısı ölçütü ve beklenen yapılar.
- `focus` en fazla 3 tür ve yalnızca şu adlar: `article`, `tense`, `preposition`, `word_order`, `be`. Ünitenin dilbilgisi hedefi ve bölümün Türk hatası odağıyla eşleşmeli.
- `minWords` / `maxWords` ana görev tablosundaki uzunluk; aralık ±%20.
- `checklist` 3–5 madde, Türkçe, gözlemlenebilir: "en az 2 bağlaç kullandın", "görüşünü bir örnekle destekledin".
- `model` metin `maxWords` sınırını aşmaz. l4'teki `translate` cümleleri model metinden alınır.
- `write` ve `shadow` ünite sınavına ve hata defterine girmez (speak gibi). Bu yüzden yazma becerisi bölüm sonunda l4 `write` ile ölçülür (§4).

### Faz 3: yeni türler A1–A2'ye ve eski hikâyelere

Sıra kararı (orkestra şefi): önce Faz 3, sonra Faz 6, en son Faz 4–5. Faz 3 yeni ünite eklemez; var olan düğümlerin alıştırmalarını değiştirir. Düğüm id'leri aynı kalır. Kullanıcının ilerlemesi düğüm bazında tutulduğu için tamamlanmış ders tamamlanmış kalır.

**A. S1–S4 beceri üniteleri (12 ünite, `01x`–`04x`)**

| Düğüm | Değişiklik | Sonuç |
|---|---|---|
| `l1` Dinleme | 1 `listen` ve 1 `speak` yerine 2 `shadow` (`rate`: A1 0.8, A2 0.85) | listen 5, shadow 2, fillBlank 2, match 1 |
| `l3` Konuşma | 1 `speak` yerine 1 `shadow` | shadow 1, speak 4, select 2, translate 2, match 1 |
| `l4` Yazma | 1 `write` eklenir. Ders 10'u aşarsa 1 `fillBlank` çıkar. | translate 4, fillBlank 2–3, select 1, match 1, write 1 |

`write` uzunlukları:

| Bölüm | Kelime | Örnek görev |
|---|---|---|
| S1 | 20–40 | kısa mesaj, form cümleleri |
| S2 | 30–50 | rutin paragrafı, davet mesajı |
| S3 | 50–80 | kartpostal, özür e-postası |
| S4 | 60–90 | şikâyet e-postası, iş profili |

- `model` metin l4'ün `translate` cümlelerinden kurulur. Bu cümleler zaten model metni oluşturuyor; Faz 1 tasarımı buna hazır.
- `focus` en fazla 2 tür. A1–A2'de öncelik `be`, `article`, `word_order`; S3–S4'te `tense` de olabilir.
- `checklist` 3 madde, çok somut olmalı: "Merhaba ile başladın", "saat ve yeri yazdın".
- Her görevin `writing_tasks.json` kaydı olur (level A1/A2). Eşleşme testi zaten var.
- **Tamamlama kuralı:** S1–S4'te `write` alıştırma amaçlıdır. `sectionCompleted` A1–A2 bölümlerinde yalnızca beceri testine bakmaya devam eder (ör. `section.cefr` A1/A2 ise write şartı yok). Faz 1'den beri "tamamlandı" görünen bölüm geri düşmemeli. Bunun için bir test yazılmalı.

**B. `listenFirst` bayrağı**

| Hikâyeler | Karar |
|---|---|
| S1–S4 beceri ünitelerinin hikâyeleri (12) | `listenFirst: true`. Zaten dinleme için yazıldılar. |
| S5–S8 temel hikâyeleri (`05_`–`08_`, 46) | `listenFirst: true`, ama her hikâye kontrol edildikten sonra (aşağıda) |
| S1–S4 temel hikâyeleri | Değişmez. Başlangıçta metin okuma desteği gerekli. |

Kontrol listesi (S5–S8 temel hikâyeleri):

1. Her soru **duyarak** cevaplanabilmeli. Yazımı, noktalamayı ya da "metinde hangi kelime geçiyor" bilgisini soran sorular yeniden yazılır.
2. Ses ile anlaşılmayan öğeler (yalnızca yazıda belli olan kısaltma, e-posta adresi, uzun rakam dizisi) ya düzeltilir ya da soru dışında bırakılır.
3. Değişiklik yalnızca bayrak satırı ve gereken soru düzeltmeleridir. **kalite-turu oturumu** (`local_4dfa23d5-81b3-4c0c-8be2-db2302ed1932`) aynı dosyalarda çalışıyor. Başlamadan önce ona hangi hikâye düğümlerine dokunacağını bildir ve çakışmayı önle.

**C. Kelime kuralı (tüm yeni genel içerik):** YDS kelime bankasının (ys5/ys7) kelimeleri genel kursta **hedef kelime** olarak öğretilmez (match ve kelime `select` maddeleri). Metinde geçebilirler. Bunu denetleyen test var.

**Kabul ölçütleri:**

- Testler geçer: course_content, writing_tasks eşleşmesi, sectionCompleted (A1–A2 yalnızca test), YDS çakışması.
- PR açıklamasında şunlar olmalı:
  - hikâye başına "listenFirst uygun mu" tablosu (soru düzeltmeleri dahil),
  - 12 yeni `write` görevi ve rubrikleri,
  - emülatörde bir A1 önce-dinle hikâyesinin ekran görüntüsü.

### Faz 6: okuma ve dinleme kütüphanesi (ortak kütüphane)

**İkinci kütüphane kurulmaz.** Uygulamada tek bir okuma kütüphanesi var:

- `assets/reading/stories.json` ve ek dosyalar, `ReadingStory` şeması.
- Okuma ekranında TTS ile cümle cümle "Dinle" ve yavaş okuma var. Yani her metin aynı zamanda bir dinleme metni.
- YDS ekibi bu kütüphaneye `yds_bol_okuma_*.json` ile 60 B1/B1+ bol okuma metni ekliyor (400–700 kelime; PR #56). Bu metinler genel kullanıcıya da görünür.

Genel kursun işi, kütüphanenin geri kalan seviyelerini doldurmak.

**Mevcut durum ve hedef:**

| Seviye | Şu an | YDS ekliyor | Faz 6 ekler | Uzunluk | Soru |
|---|---|---|---|---|---|
| A1 | 5 | – | **15** | 100–180 | 3 |
| A2 | 5 | – | **20** | 150–250 | 3 |
| B1 | 5 | 40 | **10** (gündelik konular: iş, şehir, ilişkiler; YDS metinleri biyografi ve bilim ağırlıklı) | 250–400 | 3 |
| B1+ | 0 | 20 | – | | |
| B2 | 0 | – | **20** | 400–650 | 3 |
| C1 | 0 | – | Faz 4–5 ile birlikte (seviye eklenince) | | |

Toplam 65 yeni metin.

**İlkeler (bol okuma; ayrıntılar sinav/yds-arastirma.md §2.5):**

- Metin okurun seviyesinin **bir tık altında** olmalı. Glossary'den sonra bilinmeyen kelime **≤ %2**. Kontrol, YDS'nin NGSL tabanlı betiğiyle yapılır (`tool/yds/check_bol.js` ya da genelleştirilmiş kopyası).
- Sorular anlamayı kontrol eder, sınav sorusu değildir. 4 şık, Türkçe `explain`, cevabı metniyle anar.
- Türler karışık olmalı: kısa öykü, kişisel anlatı, mektup/e-posta zinciri, röportaj, haber, nasıl yapılır. B2'de görüş yazısı ve popüler bilim de olur.
- En az ⅓'ü **diyalog ağırlıklı** olmalı. Bunlar TTS ile dinleme için uygun.
- Kadro (Elif, Kerem, Sam, Mia, Deniz) metinlerin yarısında kullanılabilir. Diğer yarısı bağımsız olsun ki kütüphane kurstan bağımsız da okunabilsin.
- **Konu çakışması yok:** YDS bol okuma ve okuma evi konularıyla (BRIEF_bol.md listesi) ve genel kurs hikâyeleriyle aynı konu seçilmez.
- **Kelime kuralı:** YDS ys5/ys7 bankası kelimeleri gloss'ta geçebilir. Metin onları hedef kelime gibi tekrar tekrar öğretmez.

**Altyapı (küçük, yds-yontem ile kararlaştırılır):**

1. **Ek dosya öneki.** `loadStories` şu an yalnızca `yds_bol_okuma_` önekini okuyor. Bunu `assets/reading/*_okuma_*.json` biçimindeki tüm dosyaları okuyacak şekilde genelleştirin, ya da bir önek listesi tutun. Genel dosyalar: `genel_okuma_a.json` (A1–A2) ve `genel_okuma_b.json` (B1–B2). Id öneki `go_`.
2. **"Önce dinle" düğmesi** okuma ekranında: metin gizli, TTS baştan sona okur, sorular cevaplanınca metin açılır. Böylece kütüphane dinleme kütüphanesi olarak da çalışır. Hikâyedeki `listenFirst` ile aynı davranış.
3. Okunan kelime sayacı yds-yontem'de var (Faz 1/C). Genel metinler de sayılır; ek iş yok.

**Kabul ölçütleri:**

- Test: id benzersiz, seviye geçerli, uzunluk aralıkta, glossary anahtarları metinde birebir geçiyor, ≤ %2 kontrolü geçiyor, cevap konumları dengeli.
- `docs/kaynaklar.md`'ye NGSL satırı eklenir; YDS'nin açtığı yapıda "## Genel kurs kaynakları" altına.
- PR açıklamasında şunlar olmalı: seviye başına metin sayısı ve kelime toplamı, tür dağılımı, konu listesi (çakışma kontrolü için), "Önce dinle" ekran görüntüsü.

### Faz 4–5: C1 (S9–S10)

İki normal bölüm dosyası:

| Faz | Dosya | Bölüm |
|---|---|---|
| 4 | `tr_en/09_derinlik.json` | `{"id":"s9","index":9,"title":"Derinlik","cefr":"C1"}` |
| 5 | `tr_en/10_ustalik.json` | `{"id":"s10","index":10,"title":"Ustalık","cefr":"C1"}` |

Ek dosya değiller. Ünite id'leri `s9u1..s9u12` ve `s10u1..s10u12`.

**İlerleme güvenliği:**

- S9, S8'in temel sınavı (`s8u10t`) geçilince açılır. S10, S9'un son testi geçilince açılır.
- Yeni bölüm eklemek önceki bölümlerin kilidini, "tamamlandı" durumunu ya da düğüm durumunu değiştirmez. Kursu bitirmiş kullanıcı için S9 "yeni bölüm" olarak açılır; bitmiş bir bölüm yeniden açık hâle gelmez.
- Test: "S1–S8'i bitirmiş bir ilerleme, S9 eklendikten sonra S1–S8'i bitmiş, S9'u açık ve başlanmamış görür."

#### Ünite deseni (C1)

Desen aynı: `lesson, lesson, story, lesson, lesson, test, chest`. C1'de beceri bölümün içinde; ayrıca ek dosya yok.

| Düğüm | Tek numaralı ünite (u1, u3…) | Çift numaralı ünite (u2, u4…, u12) |
|---|---|---|
| `l1` | Dil: yapı (dilbilgisi) | Dil: yapı |
| `l2` | Dil: kelime ve eşdizim | Dil: kelime ve eşdizim |
| `s` | `listenFirst` hikâye/podcast, 450–650 kelime, 5 soru (en az 1 örtük anlam, 1 tutum veya ton) | aynı |
| `l3` | **Dinleme:** 4 `listen` (15–25 kelime, hızlı ve bağlantılı), 2 `shadow` (`rate` 1.0), 2 `fillBlank`, 1 `match` | **Okuma:** tek metin (500–800 kelime) üzerine 6 `choice`: ana fikir, çıkarım, tutum, gönderim, kelimenin bağlamdaki anlamı, metin düzeni |
| `l4` | **Konuşma:** 2 `shadow`, 4 `speak` (bir uzun tur: 90 saniyelik görüş ya da sunum, cümle cümle), 2 `select` (üslup, diplomasi), 1 `translate` | **Yazma:** 1 `write` (220–300 kelime), 3 `translate` (model metinden), 3 `fillBlank`, 1 `select`, 1 `match` |
| `t` | Ünite sınavı (derslerden örneklenir) | u12: **C1 beceri testi** (kendi 20 sorusu: 6 listen, 8 choice, 4 translate tr→en, 2 dil) |

- `write` focus adları aynı (article, tense, preposition, word_order, be). C1'de ağırlık `article` ve `preposition` (Türklerin C1'de bile süren hataları). Ayrıca rubrik notunda üslup ve bağlantı.
- `sectionCompleted`: B1+ kuralı geçerli, yani u12 testi ve u12 l4 `write` birlikte.
- Ünite `guide`'ı zorunlu (Türkçe, en az 200 karakter): yapının Türkçe açıklaması, can-do, strateji, Türklerin sık hatası.

#### S9 Derinlik (Faz 4)

| Ünite | Başlık | Dil odağı (l1/l2) | Beceri (l3/l4) ve görev | Tema |
|---|---|---|---|---|
| s9u1 | Az önce olanlar | katılımcı cümleler (*Having finished…, Written in…*) | Dinleme/Konuşma: bir haber özetini dinle; olayı 90 sn anlat | `haber` |
| s9u2 | Bilimin dili | adlaştırma (*The decision to… / an increase in*) | Okuma/Yazma: popüler bilim makalesi; 250 kelimelik özet ve yorum | `kutuphane` |
| s9u3 | Asla böylesini görmedim | devrik yapı (*Never have I…, Not only…, Rarely…*) | Dinleme/Konuşma: etkileyici bir anı; vurgulu anlatım | `sahne` |
| s9u4 | Asıl önemli olan | cleft ve pseudo-cleft (*What matters is…, It was… who*) | Okuma/Yazma: görüş yazısı; karşı görüş yazısı (250) | `toplanti` |
| s9u5 | Olmuş olabilir | ileri çıkarım kipleri (*must have been, can't have, might well*) | Dinleme/Konuşma: gizemli olay podcast'i; olasılıkları tartış | `dedektif` |
| s9u6 | Öneririm ki | subjunctive ve resmî öneri (*I recommend that he be…, It is essential that*) | Okuma/Yazma: kurum raporu; öneri bölümü yazma (230) | `is` |
| s9u7 | Ben de öyle | eksiltme ve yerine koyma (*so do I, I hope so, if so, if not*) | Dinleme/Konuşma: doğal hızlı sohbet; kısa ve doğal tepkiler | `cay` |
| s9u8 | Bununla birlikte | ileri bağlaçlar (*whereas, notwithstanding, given that, insofar as*) | Okuma/Yazma: karşılaştırmalı makale; karşılaştırma denemesi (260) | `kutuphane` |
| s9u9 | Ortaya çıkmak | ileri phrasal verbs (*come across as, bring about, play down*) | Dinleme/Konuşma: röportaj; kendi deneyimini anlat | `mulakat` |
| s9u10 | Güçlü eşdizimler | eşdizimler (*heavy traffic, bitterly disappointed, raise concerns*) | Okuma/Yazma: dergi yazısı; eşdizim yoğun blog yazısı (230) | `sanat` |
| s9u11 | Ders notları | konuşmada söylem belirteçleri (*to put it another way, the point is*) | Dinleme/Konuşma: 5 dakikalık ders; not al, 90 sn özetle | `kutuphane` |
| s9u12 | Tartışmalı konu | ikna dili ve hedging (*arguably, it could be argued*) | Okuma/Yazma: tartışmalı makale; **tartışmacı deneme (280–300)** ve **C1 beceri testi** | `toplanti` |

#### S10 Ustalık (Faz 5)

| Ünite | Başlık | Dil odağı | Beceri ve görev | Tema |
|---|---|---|---|---|
| s10u1 | Aynı şey, iki ses | resmî ↔ samimi üslup geçişi | Dinleme/Konuşma: aynı haber iki üslupta; arkadaşa ve yöneticiye anlat | `yazisma` |
| s10u2 | Kibarca hayır | dolaylı eleştiri ve diplomasi (*I'm not sure that's quite…*) | Okuma/Yazma: müşteri yazışması; kibar ret e-postası (220) | `is` |
| s10u3 | Mecazen | deyim ve mecaz (*the elephant in the room*) | Dinleme/Konuşma: sohbet programı; deyimleri doğal kullan | `sahne` |
| s10u4 | Dizi dili | konuşma dili, kısaltmalar, argo farkındalığı (öğretilmez, tanınır) | Okuma/Yazma: dizi incelemesi; eleştiri yazısı (250) | `sanat` |
| s10u5 | Pazarlık masası | müzakere dili (*meet halfway, that's a deal-breaker*) | Dinleme/Konuşma: iş müzakeresi; teklif ve karşı teklif | `toplanti` |
| s10u6 | Teklif | teklif ve rapor yapısı | Okuma/Yazma: örnek teklif; proje teklifi (280) | `is` |
| s10u7 | Kısaca şöyle | özetleme ve aktarma (**aracılık**) | Dinleme/Konuşma: Türkçe toplantı notunu İngilizce anlat; İngilizce sunumu Türkçe özetle | `haber` |
| s10u8 | Grafikten metne | veri betimleme (*rose sharply, a slight decline*) | Okuma/Yazma: rapor; grafik betimleme ve yorum (230) | `teknoloji` |
| s10u9 | Söz sizde | sunum ve soru-cevap (*That's a good question; let me come back to it*) | Dinleme/Konuşma: konferans sunumu; 2 dakikalık sunum ve soru-cevap | `toplanti` |
| s10u10 | Edebi bir sayfa | edebi dil, anlatıcı sesi, ima | Okuma/Yazma: kısa öykü (özgün); öykü yorumu (250) | `kutuphane` |
| s10u11 | Kriz anı | baskı altında açık iletişim | Dinleme/Konuşma: kriz toplantısı; durumu açıkla ve çözüm öner | `haber` |
| s10u12 | Ustalık | tümü: üslup, bağlantı, ikna | Okuma/Yazma: köşe yazısı; **köşe yazısı (280–300)** ve **C1 beceri testi** | `sahne` |

#### Kurallar (C1)

- **Uzunluklar:**
  - okuma 500–800 kelime;
  - hikâye ya da podcast 450–650 kelime;
  - `listen` 15–25 kelime;
  - `write` 220–300 kelime, model metin aralıkta.
- **Kelime:**
  - Ünite başına en fazla 60 yeni lemma; en az 25'i l1–l4'te yeniden geçer.
  - **YDS ys7 ve sonrası bankasının kelimeleri hedef kelime (match, kelime `select`) olamaz.** Metinde geçebilir; mevcut test bunu denetliyor.
  - C1 genel kursun ağırlığı akademik kelime değil. Eşdizim, deyim, söylem ve üslup ön planda. Akademik kelime YDS yolunda öğretiliyor.
- **Kadro:** Elif, Kerem, Sam, Mia ve Deniz yetişkin hâlleriyle. Kalite turunun kararıyla Deniz erkektir (he/his). Ünitelerin yarısında bağımsız konuşmacılar olsun ki C1 dinlemede ses ve aksan çeşitliliği artsın; TTS ses seçimi değişebiliyorsa farklı sesler kullanılmalı.
- **Konu çakışması yok:** YDS okuma evi ve bol okuma konuları, genel kütüphane (`go_`) ve S5–S8 beceri üniteleri.
- **Okuma kütüphanesi (Faz 5'in sonunda):**
  - `readingLevels`'a `C1` eklenir.
  - `genel_okuma_c.json` dosyasına 15 C1 metin girer (600–900 kelime, 3 soru, glossary sonrası bilinmeyen kelime ≤ %2).

**Kabul ölçütleri:**

- Testler geçer: course_content, konu temaları, writing_tasks eşleşmesi, sectionCompleted, YDS çakışması, ilerleme güvenliği testi.
- PR açıklamasında şunlar olmalı:
  - ünite başına uzunluk, yeni lemma ve bağlantılı konuşma tablosu;
  - 6 `write` görevinin rubriği (bölüm başına);
  - bir C1 önce-dinle hikâyesi ile bir C1 okuma dersinin ekran görüntüsü.
- Süre tahmini: bölüm başına ~13–15 saat ders ve ~6 saat açık uçlu görev.

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
 "focus": ["tense", "article"],                                   // en fazla 3: article, tense, preposition, word_order, be
 "taskId": "s5u13l4w"}
// Tamamlama: kelime sayısı ≥ minWords + kontrol listesi işaretlendi (ücretsiz).
// Premium: sunucu fonksiyonu assessWriting({taskId, text}) → {scores:{task,accuracy,range,coherence} 0–3,
//          corrections:[{from,to,why_tr,type}] (yalnızca focus türleri + en fazla 3 diğer), next_tr}
//          Rubrik ve prompt sunucuda (scenarios.ts gibi). Öğrenciden yeniden yazma istenir.

// Gölgeleme
{"type": "shadow", "text": "…", "translation": "…", "rate": 0.9}
// Akış: dinle (metin gizli) → metinle dinle → birlikte söyle (ASR).
// Kendi kaydını dinleme Faz 2a'da yok (ses servisi yalnızca tanıma yapıyor); sonra eklenebilir.
// write ve shadow ünite sınavından ve hata defterinden hariç. assessWriting düzeltme türleri errorStats'e yazılır.
// Kesin model yds-yontem ile kararlaştırıldı (side-session-notes/genel-icerik.md).
// Geçme: kelime eşleşmesi ≥ 0.6 (speak 0.7). Mikrofon yoksa "atla" serbest, ceza yok.

// Metni gizli dinleme hikâyesi
{"type": "story", "listenFirst": true, …}
// Satırlar ses olarak çalınır, metin sorular cevaplanana kadar gizli kalır, sonra "metni gör".
// Hız düğmesi 0.75× / 1×.
```

Sonraki adım (kesinleşen Faz 2a kapsamında değil, ayrıca kararlaştırılacak): her B1+ beceri ünitesine bağlı bir **Konuş senaryosu**. `scenarios.ts` ve `scenarios.dart`'a eklenir; ünitede `"scenarioId"` alanı olur. Bitişte 3 maddelik geri bildirim verilir. Yapay zekâ kısmı premium; ücretsiz kullanıcı ünitenin geri kalanını tamamen bitirebilir.

---

## 4. Bölüm sonu beceri testi (bitiş ölçütü)

Her bölümün son beceri ünitesinin `t` düğümü kendi sorularını taşır. Başlık: `"Bölüm N beceri testi"`. Açıklama: `"Bu bölümün hedeflerini ölçer"`.

| Bölüm | Soru | Dinleme (`listen`) | Okuma (`choice` + passage) | Yazma (`translate` cümle / Faz 2+ `write`) | Dil (`fillBlank` / `select`) |
|---|---|---|---|---|---|
| S1–S2 (A1) | 20 | 6 | 6 (2 kısa metin × 3) | 5 | 3 |
| S3–S4 (A2) | 20 | 6 | 6 (2 metin × 3) | 5 | 3 |
| S5–S8 (B1–B2) | 20 | 6 | 8 (2 metin × 4) | 4 (`translate` tr→en, B1+ uzunlukta) | 2 |

`write` sınava giremediği için B1–B2'de bölümün yazma ölçütü, son beceri ünitesindeki l4 `write` görevidir. Bölümün "tamamlandı" sayılması için beceri testi ve bu görevin ikisi de bitmiş olmalı.

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
8. **Sarmal kelime:** Yeni lemma sınırı §2'deki gibi (A1–A2 ≤25, B1+ ≤50); önceki ünitelerden en az 15 kelime yeniden kullanılmış. İçerik ekibi PR açıklamasında sayıyı versin.
9. **Özgünlük:** Ders kitabı, sınav ya da başka uygulama metni kopyalanmamış. Açık lisanslı kaynak kullanıldıysa `docs/kaynaklar.md`'ye yazılmış.
10. Dil doğruluğu: İngilizce doğal (doğal konuşan kontrolü), Türkçe çeviri doğru. Cevap anahtarı bağımsız bir çözümle doğrulanmış.

---

## 6. Faz planı

| Faz | Kapsam | Sahip | Boyut | Bağımlılık |
|---|---|---|---|---|
| **1** (bu tur) | 1a altyapı: ek dosya, kilit sabitleme, test, tr_en `choice`, test soruları, `guide`. 1b içerik: S1–S4 için 12 beceri ünitesi ve 4 bölüm beceri testi. | genel-icerik | ~460 alıştırma + 80 test sorusu + küçük Dart değişikliği | yok |
| **2a** | `write`, `shadow`, `listenFirst`; `assessWriting` sunucu fonksiyonu; ünite–senaryo bağı | altyapı oturumu (orkestra şefi atar) ya da genel-icerik | orta | Faz 1a |
| **2b** | S5–S8 için 12 beceri ünitesi (kalıp §2 "Faz 2b ders kalıbı"); B1–B2 beceri testleri; 12 `write` görevi ve sunucu rubrikleri | genel-icerik | ~460 alıştırma + 12 `write` + 12 rubrik | 2a |
| **3** (PR #59) | §2 "Faz 3": S1–S4 beceri ünitelerine `shadow` ve `write`; beceri hikâyeleri ve S5–S8 temel hikâyelerine `listenFirst` | genel-icerik | küçük–orta | 2a |
| **4** (sıradaki) | §2 "Faz 4–5": C1 Bölüm 9 Derinlik (12 ünite, beceri bölüm içinde) | genel-icerik | ~470 alıştırma + 6 `write` | 2a |
| **5** | C1 Bölüm 10 Ustalık (12 ünite) + C1 beceri testi + 15 C1 kütüphane metni | genel-icerik | ~470 alıştırma + 6 `write` + 15 metin | 4 |
| **6** (PR #66) | §2 "Faz 6": ortak okuma kütüphanesine 65 metin (A1 15, A2 20, B1 10, B2 20); okuma ekranında "Önce dinle"; NGSL kapsam kontrolü | genel-icerik (altyapı yds-yontem ile) | 65 metin + küçük altyapı | yok |

Faz sonrası toplam (yaklaşık):

| | Ünite | Ders | Süre |
|---|---|---|---|
| Bugün | 94 | 364 | ~34 sa |
| 5. faz sonu | ~142 | ~556 | ~60 sa ders + 50–80 sa açık uçlu görev |

Kütüphane ve tekrarla birlikte B2 sonuna kadar ~200–250 sa uygulama içi süre. Kalan saat için araştırma §3.1'e bakın.

**Sıra gerekçesi:** A1–A2 en kalabalık kullanıcı kitlesi ve yeni altyapı gerektirmiyor; Faz 1 bu yüzden hemen yazılabilir. B1–B2'deki asıl boşluk (serbest yazma, uzun dinleme) yeni türler olmadan kapanmaz; bu yüzden 2a önce gelir. C1, B2 derinleşmeden eklenirse kursun "genişliği" artar ama "bitiren bilir" hedefi değişmez; bu yüzden C1 en son gelir.
