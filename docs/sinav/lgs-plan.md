# LGS İngilizce çalışma yolu — araştırma ve plan

Bu belge, Dilbaz'daki LGS yolunun (`assets/courses/exam_lgs*`) neye göre yazıldığını anlatır. İçerik bu plana göre üretilir ve `test/course_content_test.dart` planın ölçülebilir kurallarını denetler.

Tüm sorular **özgündür**. Geçmiş yılların soruları yalnızca **soru tipi ve konu dağılımı** için incelendi; hiçbir soru, metin ya da görsel kopyalanmadı.

---

## 1. Sınavın biçimi

| Konu | Bilgi | Kaynak / not |
|---|---|---|
| Oturum | İngilizce, LGS'nin **sözel oturumunda** yer alır | MEB sıkça sorulan sorular (31 Mart 2025) |
| Soru sayısı | **10 soru**, 4 şıklı (A–D) | Sözel oturum 50 soru: Türkçe 20, İnkılap 10, Din 10, Yabancı dil 10 |
| Süre | Oturumun tamamı **75 dakika**; İngilizceye ayrı süre yok | Soru başına ortalama 1,5 dk → İngilizce için **~15 dk** bütçe |
| Puanlama | 3 yanlış 1 doğruyu götürür | LGS genel kuralı; uygulamadaki denemede net gösterilir |
| Kapsam | 8. sınıf İngilizce programının 10 ünitesi | 2026-27'de 8. sınıf henüz Maarif Modeline geçmedi; yeni programa uygun soru modeli ilk kez 2028'de |

> Uygulamadaki **bölüm denemeleri** bu yüzden gerçek biçimde: **10 soru, 15 dakika, 4 şık**. Sonuçta yüzde ile birlikte **net** (doğru − yanlış/3) gösterilir.

### Soru tiplerinin dağılımı (son yıllar)

Son 3–4 yılın (2022–2025) sınav kitapçıkları ve kurs/eğitimci analizleri incelendi. Yıldan yıla küçük oynamalar olsa da 10 sorunun yaklaşık dağılımı şöyle:

| Soru tipi | Yaklaşık sayı | Nasıl görünür |
|---|---|---|
| Okuduğunu anlama (paragraf, e-posta, blog, mesaj) | 3 | "Which is true / NOT mentioned?", "Which question can't be answered?", ana fikir |
| Görsel / tablo / grafik / anket yorumlama | 1–2 | Anket sonucu, program çizelgesi, ilan; "According to the chart…" |
| Kelime bilgisi (bağlamda anlam, eş anlam) | 2 | Boşluk doldurma, kelimenin metindeki anlamı |
| Kalıp / dil bilgisi (metin ya da diyalog içinde) | 2 | Kural doğrudan sorulmaz; kalıp diyalogda kullanılır |
| Diyalog tamamlama / sıralama | 1 | "----" ile boşluk, ya da (I)–(IV) sıralama |
| Durum – uygun ifade | 1 | "What does Ali say in this situation?" |

Gözlemler:
- Son yıllarda metinler **uzadı** ve **anlam odaklı** oldu; dil bilgisi kuralı yerine kalıbın bağlamda doğru kullanımı soruluyor.
- Hemen her soruda bir metin ya da görsel var; yalnızca kelime soran "çıplak" soru az.
- Ünite dağılımı: çoğu yıl her üniteden ~1 soru; ilk dönem üniteleri (1–5) çoğu zaman 5–6 soruyla biraz ağır basar.

Uygulamada görseller **metin tablosuyla** verilir (markdown tablo, ekranda gerçek tablo olarak çizilir), çünkü sorular özgün ve resim kullanılmıyor.

Kaynaklar (erişim Kasım 2026):
- MEB, "LGS kapsamındaki merkezi sınava ilişkin sıkça sorulan sorular yanıtlandı" (31.03.2025) — meb.gov.tr
- Soru tipi analizleri: rehberpanda.com (son 5 yıl analizi), bilimsenligi.com (soru tiplerine göre çözüm), unirehberi.com ve egitimgo.net (ünite dağılımı tabloları; birbiriyle küçük farklar var)
- Maarif Modeli geçişi: basarisiralamalari.com, askakitap.com (8. sınıf 2026-27'de mevcut programla)

---

## 2. Yolun yapısı

- **Bölüm 1 (ls1) = ünite 1–5**, **Bölüm 2 (ls2) = ünite 6–10**; her bölümün sonunda **bölüm denemesi** (10 soru / 15 dk).
- Her ünite aynı deseni izler:

| Düğüm | İçerik | Alıştırma |
|---|---|---|
| Konu anlatımı (Rehber) | Özet tablo, hedef kalıplar, anahtar kelimeler, Türk hataları, 3 sınav ipucu | — |
| Ders 1 — Kelimeler | select (resimli kart) + match (eşleştirme) ağırlıklı, sonda bağlamda kelime soruları | 11 |
| Ders 2 — Kalıplar | Hedef kalıplar: boşluk doldurma, kelime bankasıyla çeviri, kalıp seçimi | 11 |
| Ders 3 — Diyaloglar ve durumlar | Diyalog tamamlama, diyalog sıralama, durum–uygun ifade, tablo yorumu | 10 |
| Ders 4 — Okuma | Metin A (110–150 kelime) + 5 soru; Metin B (kısa ilan/anket/mesaj, tablo olabilir) + 4 soru | 9 |
| Mini LGS testi | **10 soru, LGS dağılımında**, sabit sorular; geçmek için %80 | 10 |
| Ödül | Bonus XP | — |

Ders başına alıştırma dağılımı:

| Ders | select | match | fillBlank | translate | choice |
|---|---|---|---|---|---|
| 1 Kelimeler | 3 | 2 (5'er çift) | 1 | — | 5 (bağlamda kelime) |
| 2 Kalıplar | — | — | 2 | 1 | 8 |
| 3 Diyaloglar | — | — | — | — | 10 |
| 4 Okuma | — | — | — | — | 9 (2 metin) |
| Mini test | — | — | — | — | 10 |

Ünite başına 51 alıştırma, bunların 42'si LGS tipi 4 şıklı soru. Toplam 510 alıştırma.

**Mini LGS testinin sırası** (her ünitede aynı, sınavdaki gibi karışık):
1–2 kelime (bağlamda) · 3–4 kalıp (diyalog içinde) · 5 diyalog tamamlama · 6 durum–uygun ifade · 7 tablo/anket yorumu · 8–10 okuma (bir metin + 3 soru).

**Zorluk:** ünite içinde kelime → kalıp → diyalog → okuma diye artar; mini test ders 3–4 düzeyindedir. Metinler A2 (8. sınıf) düzeyinde, cümleler genellikle 20 kelimeyi geçmez.

**Dil:** Soru kökleri İngilizce (LGS gibi). Açıklamalar Türkçe, sıcak ve cesaretlendirici ("Harika!", "Bu kalıbı LGS çok sever"). Açıklama her zaman doğru şıkkın **neden** doğru olduğunu ve en güçlü çeldiricinin neden yanlış olduğunu söyler; şıkları konumla ("ilk şık") değil metinle anar.

---

## 3. Ünite planları

Her ünite için: hedef işlevler, kalıplar, kelime listesi (40–60), tipik soru tipleri, Türk öğrencilerin tuzakları. Ünite rehberi bunların özetidir; ders 1 kelimelerin en az 25'ini, mini test ve okuma metinleri kalanların çoğunu kullanır.

### Ünite 1 — Friendship (ls1u1, tema: duygular)
- **İşlevler:** arkadaşı tanıtma/kişiliğini anlatma; davet etme, daveti kabul ve reddetme; özür dileme ve sebep bildirme; özrü kabul etme.
- **Kalıplar:** Would you like to …? / Do you want to …? / How about …ing? · Sure, I'd love to. / Why not? · Sorry, I can't. I have to … / I'm afraid I can't because … · I'm sorry for/about … · Never mind. / Don't worry. / That's OK. · He/She is … and … . · a true friend shares/supports/keeps secrets.
- **Kelimeler (52):** friendship, friend, best friend, true friend, reliable, honest, generous, supportive, easygoing, funny, kind, helpful, friendly, polite, patient, cheerful, shy, selfish, rude, jealous, lazy, mean, bossy, moody, trust, share, support, keep a secret, tell lies, gossip, argue, make up, apologize, accept, refuse, invite, invitation, excuse, reason, party, birthday party, sleepover, hang out, get on well, rely on, count on, keep a promise, break a promise, misunderstanding, forgive, upset, offended.
- **Soru tipleri:** davete uygun ret/kabul cevabı; kişilik sıfatını tanımdan bulma; özür e-postası okuma; "Which is NOT a feature of a good friend according to the text?"
- **Tuzaklar:** "Would you like come?" (to unutulur) · "I am agree" · ret cevabında sebep vermeden "No" (kaba) · *jealous*/*generous* karışması · "How about go?" (-ing unutulur).

### Ünite 2 — Teen Life (ls1u2, tema: gunluk)
- **İşlevler:** sevdiği/sevmediği şeyleri söyleme, tercih bildirme ve sebep verme; günlük rutini ve sıklığı anlatma; hobiler ve müzik türleri.
- **Kalıplar:** love/like/enjoy/don't mind/dislike/hate/can't stand + V-ing · be fond of / be keen on / be interested in + V-ing · prefer X to Y · I'd rather … than … · always/usually/often/sometimes/rarely/never · once/twice a week · because / so.
- **Kelimeler (50):** teenager, hobby, free time, spare time, routine, weekday, weekend, hang out, chat, surf the net, play video games, go shopping, go to the cinema, read comics, collect stamps, play chess, ride a bike, skateboarding, swimming, music, pop, rock, jazz, classical, rap, folk music, concert, band, singer, instrument, guitar, drums, violin, prefer, enjoy, can't stand, don't mind, fond of, keen on, interested in, boring, exciting, relaxing, entertaining, annoying, always, usually, sometimes, rarely, never.
- **Soru tipleri:** anket tablosundan "who likes what"; sıklık zarfı ile rutin metni; "Which person prefers …?"; tercih cümlesine uygun cevap.
- **Tuzaklar:** "I like play" (-ing yerine yalın) · "I prefer tea than coffee" (to olmalı) · "I am interesting in" (interested) · sıklık zarfının yeri ("I go always").

### Ünite 3 — In the Kitchen (ls1u3, tema: yemek)
- **İşlevler:** bir süreci/tarifi sırayla anlatma; malzeme ve miktar söyleme; yemek tarif etme ve öneri.
- **Kalıplar:** First, … Then, … Next, … After that, … Finally, … · emir kipi (Chop the onions.) · How much/How many … ? · a cup of / a spoonful of / a pinch of · It is made with … / It is served with … (basit edilgen) · You need …
- **Kelimeler (52):** recipe, ingredient, dish, menu, kitchen, cook, chef, bowl, plate, pan, pot, oven, cooker, knife, spoon, fork, cup, glass, chop, slice, cut, peel, grate, boil, fry, bake, roast, grill, mix, stir, pour, add, put, serve, taste, heat, melt, flour, sugar, salt, pepper, butter, oil, egg, milk, onion, garlic, tomato, cheese, a pinch of, a slice of, delicious.
- **Soru tipleri:** tarif sıralaması (adımları sıraya koyma); resimsiz "hangi adım eksik"; menü/tablo yorumu; "Which ingredient is NOT used?"
- **Tuzaklar:** sayılamayan isme a/an (*a sugar*) · *cook* (aşçı) / *cooker* (ocak) karışması · *How many sugar* · sıra kelimeleri olmadan adım verme.

### Ünite 4 — On the Phone (ls1u4, tema: yazisma)
- **İşlevler:** telefon görüşmesi başlatma/sonlandırma; mesaj alma ve bırakma; plan yapma ve teklif.
- **Kalıplar:** Hello, this is … · Can/Could I speak to …? · Who's calling, please? · Hold on / Hold the line, please. · He isn't available right now. · Can I take a message? / Can I leave a message? · I'll call back later. · Sorry, wrong number. · The line is busy. · I'm going to … / I'll … (plan ve karar).
- **Kelimeler (48):** phone, mobile phone, call, phone call, ring, answer, hang up, call back, dial, phone number, message, text message, voice message, leave a message, take a message, available, busy, engaged, hold on, wrong number, speak to, caller, receiver, signal, battery, charge, contact, app, video call, invite, plan, appointment, arrange, meet, make plans, cancel, postpone, confirm, free, schedule, tonight, tomorrow, later, sure, sorry, of course, see you, bye for now.
- **Soru tipleri:** telefon diyaloğu tamamlama; mesaj notunu okuma ("Who called?"); "What will Ali do next?"; (I)–(IV) telefon diyaloğu sıralama.
- **Tuzaklar:** "I am Ali" yerine "This is Ali" · "Can I talk with Ayşe?" (speak to) · *will* ile *going to* ayrımı (plan vs anlık karar) · *busy* hattın meşgul olması anlamında.

### Ünite 5 — The Internet (ls1u5, tema: teknoloji)
- **İşlevler:** internet kullanımını ve sıklığını anlatma; çevrimiçi güvenlik için tavsiye ve kural; görüş bildirme; anket/grafik sonucu yorumlama.
- **Kalıplar:** I use the internet to/for … · should / shouldn't · must / mustn't · You'd better … · I think … / In my opinion … / I agree / I disagree · percent of students …
- **Kelimeler (52):** internet, online, offline, website, browser, search engine, download, upload, browse, surf, log in, log out, sign up, account, password, username, profile, post, share, comment, like, follow, social media, chat, message, email, attachment, link, virus, hacker, cyberbullying, digital footprint, privacy, personal information, secure, safe, risk, addiction, screen time, smartphone, tablet, laptop, wifi, connection, update, app, online shopping, research, homework, survey, percent, majority.
- **Soru tipleri:** anket/grafik ("Most of the students use the internet to …"); güvenlik kuralları metni; tavsiye cümlesi seçme; görüş bildiren diyalog.
- **Tuzaklar:** *must* ile *have to* olumsuzlarının farkı (mustn't = yasak) · "should to" · *download/upload* karışması · yüzdeleri tablodan yanlış okuma (en çok / en az).

### Ünite 6 — Adventures (ls2u1, tema: spor)
- **İşlevler:** macera sporlarını tanıtma; karşılaştırma yapma; tercih bildirip sebep verme.
- **Kalıplar:** -er than / more … than · the -est / the most … · as … as / not as … as · I prefer … to … · I'd rather … · It's too dangerous for me. · because / but.
- **Kelimeler (50):** adventure, extreme sport, rafting, paragliding, scuba diving, rock climbing, bungee jumping, skydiving, skiing, snowboarding, surfing, canoeing, camping, hiking, trekking, mountain biking, horse riding, safety, equipment, helmet, life jacket, rope, instructor, guide, experience, challenge, adrenaline, brave, scared, nervous, exciting, thrilling, dangerous, risky, safe, boring, tiring, fun, extraordinary, unforgettable, try, attempt, prefer, compare, fear, height, cliff, river, wave, valley.
- **Soru tipleri:** karşılaştırma tablosu (fiyat/zorluk/süre); "Which is the most …?"; tercih cümlesine uygun gerekçe; macera blogu okuma.
- **Tuzaklar:** "more safer" (çift karşılaştırma) · "the most good" (best) · *than* yerine *from* ("taller from") · *prefer to* ile *rather than* karışması.

### Ünite 7 — Tourism (ls2u2, tema: seyahat)
- **İşlevler:** turistik yerleri tanıtma; geçmiş tatil deneyimini anlatma; öneri verme.
- **Kalıplar:** I visited / stayed / saw / tried … (geçmiş zaman) · Have you ever been to …? · You should visit … / Don't miss … · It is famous for … · It is located in … · What did you do there?
- **Kelimeler (50):** tourism, tourist, travel, trip, journey, holiday, vacation, abroad, sightseeing, landmark, historical site, ancient city, ruins, museum, palace, castle, mosque, tower, beach, coast, island, cave, waterfall, accommodation, hotel, hostel, campsite, booking, guided tour, tour guide, souvenir, local food, passport, luggage, map, ticket, flight, crowded, peaceful, breathtaking, historical, ancient, famous, popular, amazing, worth visiting, recommend, explore, visit, culture.
- **Soru tipleri:** gezi blogu okuma; tur programı tablosu; "Which place should Ali visit?"; geçmiş deneyim diyaloğu.
- **Tuzaklar:** düzensiz geçmiş fiiller (*goed*, *buyed*) · "I went to abroad" · *travel/trip/journey* ayrımı · "Did you visited?"

### Ünite 8 — Chores (ls2u3, tema: tamir)
- **İşlevler:** ev işlerini ve sorumlulukları anlatma; zorunluluk ve gereksizlik bildirme; rica ve teklif; ev işleri hakkında görüş.
- **Kalıplar:** have to / has to / don't have to · must · need to · Can/Could you …? · Shall I …? / I'll help you. · It's my turn to … · I don't mind …ing / I hate …ing.
- **Kelimeler (48):** chore, housework, duty, responsibility, do the laundry, do the dishes, do the shopping, do the ironing, wash the dishes, vacuum the carpet, dust the furniture, sweep the floor, mop the floor, make the bed, tidy the room, clean the windows, take out the rubbish, feed the pet, walk the dog, water the plants, set the table, clear the table, cook dinner, iron the clothes, fold the clothes, hang out the washing, mess, messy, tidy, dirty, clean, vacuum cleaner, dishwasher, washing machine, broom, bucket, share, help, turn, rota, schedule, weekly, daily, fair, unfair, tiring, boring, easy.
- **Soru tipleri:** ev işi çizelgesi (kim, hangi gün); "Who has to … on Monday?"; rica/teklif diyaloğu; görüş anketi.
- **Tuzaklar:** "He have to" (has to) · *mustn't* ile *don't have to* farkı · *do/make* eşlemeleri (*make the bed*, *do the dishes*) · *Could you* cevabında "Yes, I could" yerine "Sure / Of course".

### Ünite 9 — Science (ls2u4, tema: kutuphane)
- **İşlevler:** buluşları ve bilim insanlarını tanıtma; bir deneyi/süreci anlatma; geçmişteki bilimsel olayları sıralama.
- **Kalıplar:** It is made of / is used for … (edilgen, geniş zaman) · It was invented by … in … · It was discovered … · First, … Then, … (deney adımları) · past simple (He studied …).
- **Kelimeler (50):** science, scientist, research, researcher, experiment, laboratory, invention, inventor, invent, discovery, discover, develop, observe, test, result, theory, data, sample, measure, technology, engineer, telescope, microscope, robot, artificial intelligence, electricity, light bulb, battery, engine, vaccine, medicine, planet, space, satellite, gravity, chemical, liquid, gas, solid, temperature, energy, renewable, award, Nobel Prize, molecule, DNA, mathematics, physics, chemistry, biology.
- **Soru tipleri:** buluş zaman çizelgesi (tablo); bilim insanı biyografisi okuma; deney adımlarını sıralama; edilgen cümle içeren diyalog.
- **Tuzaklar:** *invent* / *discover* ayrımı · edilgende *by* unutma ya da "was invent" · *experience* / *experiment* karışması · tarih okuma (in 1879).

### Ünite 10 — Natural Forces (ls2u5, tema: hava)
- **İşlevler:** doğal afetleri tanıtma; tahmin yapma; uyarı ve tavsiye; çevre sorunları ve çözümleri; neden–sonuç.
- **Kalıplar:** will / won't (tahmin) · be going to (kanıta dayalı tahmin) · If we …, … will … (1. tip koşul) · You should … / Don't … / Make sure you … · because / so / as a result.
- **Kelimeler (52):** natural disaster, earthquake, flood, drought, landslide, avalanche, wildfire, forest fire, storm, thunderstorm, hurricane, tornado, tsunami, volcano, eruption, heavy rain, snowstorm, emergency, emergency kit, first aid kit, flashlight, whistle, shelter, rescue, survivor, damage, destroy, warn, warning, prepare, protect, evacuate, safe, dangerous, climate change, global warming, pollution, air pollution, recycle, reuse, reduce, save energy, renewable energy, carbon footprint, environment, nature, species, extinct, prediction, future, temperature, sea level.
- **Soru tipleri:** afet sırasında ne yapılmalı listesi; acil durum çantası tablosu; tahmin cümlesi seçme; çevre kampanyası afişi (metin).
- **Tuzaklar:** "If it will rain" (koşul cümlesinde will) · *will* / *going to* kanıt ayrımı · *flood* / *drought* karışması · *should* sonrası fiilin yalın olmaması.

---

## 4. Rehber (konu anlatımı) şablonu

Her ünitenin `guide` alanı şu bölümleri bu sırayla içerir:

1. `## Bu ünitede ne öğreneceğiz?` — 2–3 cümle.
2. `## Özet tablo` — markdown tablo: **Ne yapmak istiyorsun? | Kalıp | Örnek** (5–7 satır).
3. `## Hedef kalıplar` — 5–8 madde, kalıp kalın, Türkçe anlam, örnek.
4. `## Anahtar kelimeler` — 15–20 en önemli kelime (`- **word**: anlam`).
5. `## Türklerin sık yaptığı hatalar` — 3 madde (yanlış → doğru).
6. `## Sınav ipuçları` — tam **3** satır: `> **Sınav ipucu 1:** …`, `> **Sınav ipucu 2:** …`, `> **Sınav ipucu 3:** …` (her biri ayrı paragraf).

## 5. Bölüm denemeleri

- Bölüm 1 denemesi (ls1m) ve Bölüm 2 denemesi (ls2m): **10 soru, 15 dakika, 4 şık**.
- Sorular bölümün **mini LGS testlerinden** seçilir: her üniteden 2 soru, LGS dağılımını koruyacak biçimde (okuma, tablo, diyalog, kelime). Yetmezse ders soruları, sonra LGS soru bankası kullanılır.
- Sonuç ekranı yüzde, **net** (doğru − yanlış/3) ve süreyi gösterir; en iyi sonuç ve son süre yolda görünür.
