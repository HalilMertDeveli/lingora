# YDS Faz 1: yöntem spesifikasyonu (yds-yontem için)

**Amaç:** Araştırmadaki yöntemleri (`docs/sinav/yds-arastirma.md` §2) uygulama özelliklerine dönüştürmek. Ayrıca bir yıllık programı (`docs/sinav/yds-1-yil.md`) **günlük plana** çevirmek.

**Faz 1 öncelik sırası:**
1. Aralıklı tekrar
2. Paralel bölüm
3. Günlük plan
4. Hata defteri
5. İlerleme analizi
6. Yöntemlerimiz

Her madde kendi başına birleştirilebilir olmalı. İsterseniz 2–3 PR'a bölün.

Sabit kurallar:
- can/ceza yok
- ilerleme verisi bozulmaz: yeni alanlar isteğe bağlı, eski kayıtlar okunabilir
- `progress_merge` (Firebase birleştirme) yeni alanları da birleştirir
- `dart format -l 110 lib test`

---

## 1. Aralıklı tekrar

### 1.1 Leitner aralıklarını uzat (zorunlu)

- `lib/data/progress.dart`: `reviewIntervals = [0, 1, 3, 7, 14, 30]` → `[0, 1, 3, 7, 14, 30, 60, 120, 240]`.
- **Neden:** Bir yıllık programda 30 gün tavanı, bilinen 6.000+ kelimenin her ay geri gelmesi demektir. Tekrar yükü şişer (araştırma §2.1, Cepeda 2008).
- **Yanlış cevap:** kutu 0'a değil `max(0, box - 2)` değerine iner. Kutusu 0–2 arasında olan kart için davranış aynı kalır.
- **`knownBox` eşiği değişmemeli.** "Bilinen kelime" sayısı birden düşmesin.
- **Test:** eski kayıtta kutu 5 olan kelime doğru cevapla 6'ya (60 gün) çıkar; yanlışla 3'e iner.

### 1.2 YDS kelime kartları

- `assets/vocab/yds.json` (içerik ekibi yazar, `VocabEntry` şeması + `family`) kelime pratiğine eklenir. id öneki `yd_`.
- **Geçiş köprüsü:** `yds.json` gelene kadar ve mevcut 2.630 YDS kelimesi için, YDS yolundaki `vocab: true` derslerin `match` çiftlerinden **basit kartlar** üretilir.
  - Kart Türkçe ↔ İngilizce, örneksizdir.
  - id: `ydm_<kelime>`.
  - Kelime kullanıcı o dersi bitirince desteye girer.
- **Günlük tavan:**
  - Vadesi gelen tekrar, kullanıcının tekrar bütçesini aşarsa (varsayılan 30 dk ≈ 150 kart) yeni kart sayısı o gün kısılır.
  - Ekranda şu mesaj gösterilir: "Bugün tekrar günü: yeni kelime azaltıldı".

### 1.3 Hata defteri kartları

- Yanlış yapılan `choice` soruları (mevcut `mistakes` anahtarları `nodeId#index`) şu aralıklarla geri gelir: **1 → 3 → 7 → 21 gün**.
- **Arka arkaya 2 doğru** → defterden çıkar.
- Mevcut "doğru cevap yanlışı temizler" davranışı değişir: ilk doğru bir sonraki aralığa taşır, ikinci doğru temizler. Eski kayıtlar 0. aralıkta sayılır.

### 1.4 FSRS (Faz 2, bu turda değil)

Faz 2 için not: FSRS'ye geçiş, MIT lisanslı bir uygulamanın Dart portuyla ya da kendi uygulamamızla yapılır. Hedef hatırlama %90 olur. Bu turda yalnızca veri modelini buna engel olmayacak biçimde bırakın; örneğin son tekrar tarihini de saklayın.

## 2. Paralel bölüm ve deneme düğümü

### 2.1 Paralel bölüm

- `Section` modeline isteğe bağlı `parallel` (bool) alanı eklenir.
- `sectionOpen` içinde: `section.parallel` ise bölüm her zaman açıktır, kendi içinde sıralı ilerler.
- `activeNodes` paralel bölümün sıradaki düğümünü de verir. Yol ekranında paralel bölümler ayrı bir başlıkla gösterilir, ör. "Yan yollar: Kelime bankası, Okuma evi".
- **Neden:** Kelime ve okuma bir yıl boyunca her gün, dilbilgisi yoluyla **paralel** yürür. Ana yolun sonuna kilitlenirse Evre 2'de kullanılamaz.

### 2.2 Mock düğümü kendi sorularını taşısın

- Test düğümündeki gibi: `{"type":"mock", ..., "exercises":[40 choice]}`.
- Doluysa sorular sabit ve sıralı gelir, değilse eski davranış geçerlidir.
- Bu özellik, yarım deneme 1 (ys6 sonu) için gerekiyor.

## 3. Günlük plan ("Bugün")

**Veri:** `assets/plans/yds_1_yil.json` (bu PR'da). Şema: `phases[]` ve `weeks[]`. `weeks[]` şu alanları taşır:
- `week`, `phase`, `units` (metin)
- `newWords`, `wordsTotal`
- `readingWordsPerDay`, `intensiveTextsPerDay`, `choicePerDay`
- `mock`
- `unitIds`: ana yolda o hafta bitirilecek ünite id'leri. Genel kurs (`u1`, `s2u3`…) ve YDS (`ys1u11`…).
- `parallelUnitIds`: o haftanın paralel bölüm üniteleri (ys5/ys6).

Üst düzeyde iki alan daha var:
- `blocks`: blok oranları
- `targetSeconds`: soru tipi başına hedef saniye

Tekrar haftaları (10, 34, 42, 52) boş `unitIds` taşır. Bu haftalarda plan, zayıf üniteleri hata analizine göre önerir.

Dosyayı `pubspec.yaml`'a siz ekleyin.

**Kurulum** (YDS hedefi seçildiğinde, bir kez):
- **Sınav:** YDS / YÖKDİL Fen / Sağlık / Sosyal.
- **Başlangıç:**
  - seviye testi sonucuna göre: A0–A1 → H1, A2 → H11, B1 → H21
  - ya da elle seçim
- **Günlük süre:** 2 / 3 / 4 saat. Bloklar orantılı ölçeklenir.
- **Uygulama niyeti:** "Hangi saatte ve nerede çalışacaksın?" Cevap bildirim saatine bağlanır (Lally 2010; Gollwitzer & Sheeran 2006).
- **Hafif gün:** haftanın hangi günü.

**Bugün ekranı:** blok listesi ve her bloğun hedefi.

| Blok | Süre (3,5 sa) | Ne açar | Bitti sayılır |
|---|---|---|---|
| Tekrar kartları | 30 dk | Kelime tekrar + hata defteri kartları | Vadesi gelenler bitti ya da süre doldu |
| Yeni ders | 60 dk | Ana yolun sıradaki 2 dersi + günün yeni kelimeleri (`newWords / 6`) | 2 ders bitti |
| Okuma | 45 dk | Okuma evi / okuma ekranı | `readingWordsPerDay` kelime okundu |
| Soru | 45 dk | Haftanın soru tipi + karışık set (son 4 haftanın ünitelerinden) | `choicePerDay` soru çözüldü |
| Hata defteri | 20 dk | Günün yanlışları, neden etiketi | Tüm yeni yanlışlar etiketlendi |

**Kurallar:**
- **Plan adım bazlıdır.** Kaçırılan gün yığılmaz; hafta, haftanın hedefleri bitince ilerler. Bitiş tarihi tahmini güncellenir.
- **Deneme günü:** Haftanın `mock` alanı doluysa, kullanıcının seçtiği bir gün "Deneme günü" olur (§3.3, yds-1-yil.md). Ertesi gün Soru bloğu "Deneme analizi" olur.
- **Mola hatırlatıcısı:** Bloklar arasında mevcut `break_reminder` kullanılır.
- **Seri:** Bir gün kaçırmak seriyi bozmaz, "dondurma" otomatik kullanılır; haftada 1 hak. Cezalı dil kullanılmaz.

## 4. Hata defteri: neden etiketi ve hedefli öneri

**Yanlış sonrası "Neden yanıldın?":** tek dokunuşla seçilir, atlanabilir. Seçenekler:
- Kelimeyi bilmiyordum
- Yapıyı/kuralı bilmiyordum
- Yanlış okudum / acele ettim
- İki şık arasında kaldım
- Süre yetmedi
- Tahmin ettim

**Neden → öneri:**

| Neden | Öneri |
|---|---|
| Kelime | Sorudaki ve şıklardaki hedef kelimeler kelime kartlarına eklenir (`yd_`/`ydm_` eşleşirse) |
| Yapı | İlgili ünitenin Rehber'i + o üniteden 10 soru |
| Acele / süre | Süre stratejisi ipucu |
| İki şık | Açıklamayı yeniden göster + 3 gün sonra tekrar |

**Ek alanlar:**
- **Soru tipi etiketi:** `choice` sorularının tipi ünite ya da düğümden türetilir (kelime, dilbilgisi, cloze, cümle tamamlama, çeviri, okuma, diyalog, restatement, paragraf tamamlama, anlam bütünlüğü). İçerik ekibi açık bir `qtype` alanı eklerse o kullanılır.
- **İsteğe bağlı not:** "Neden yanıldım?" sorusuna kullanıcının kendi cümlesi (en fazla 140 karakter). Bu öz-açıklamadır (araştırma §2.4).

## 5. İlerleme analizi

- **Deneme sonucu:**
  - tür bazında doğru / yanlış / boş
  - bölüm süreleri (araştırma §2.8 tablosundaki hedef sürelerle karşılaştırma)
  - 72 doğru hedef tablosuna göre açık: `yds-plan.md` §3
- **Haftalık rapor (hafif gün):**
  - yeni kelime / hedef
  - bilinen kelime toplamı
  - okunan kelime
  - soru doğru oranı (tip bazında)
  - tahmini puan aralığı
- **Tahmini YDS puanı:**
  - Son 3 tam/yarım denemenin ağırlıklı ortalaması; yoksa tip bazında son 200 sorunun doğru oranı × tip ağırlıkları (§1.2 dağılımı).
  - **Aralık olarak** gösterilir, ör. "62–70".
  - 20'den az veriyle gösterilmez.
- **Okuma sayacı:** okuma ekranında ve Okuma evi derslerinde okunan metnin kelime sayısı toplanır.
- **Kelime boyutu kontrolü (Faz 2'ye kalabilir):** Ayda bir yapılır. 1k–8k bantlarından 10'ar kelime ile **özgün** bir test. Sonuç "tahmini kelime sayısı" olarak gösterilir.

## 6. "Yöntemlerimiz" ekranı

**Erişim:** Profil → "Nasıl öğretiyoruz?". Ayrıca her özelliğin yanında küçük bir "?" bulunur ve ilgili karta götürür.

**Kartlar:** Her kart 3 satırdan oluşur: **Ne?** / **Neden?** (tek cümlelik bulgu + kaynak adı) / **Dilbaz'da nerede?**

1. **Aralıklı tekrar:** Unutmadan hemen önce tekrar etmek, aynı süreyi tek seferde harcamaktan daha kalıcıdır. Kaynak: Cepeda vd. 2008; Dunlosky vd. 2013. Yeri: Tekrar kartları, hata defteri.
2. **Kendini sınama:** Hatırlamaya çalışmak, yeniden okumaktan daha iyi öğretir. Kaynak: Roediger & Karpicke 2006; Adesope vd. 2017. Yeri: Dersler, ön test, kartlar.
3. **Karışık çalışma:** Benzer konuları karıştırmak, ayırt etmeyi öğretir. Kaynak: Brunmair & Richter 2019. Yeri: Karışık setler, Soru bloğu.
4. **Derin işleme:** Kelimeyi örnek, aile ve eşdizimle öğrenmek ve kullanmak. Kaynak: Laufer & Hulstijn 2001. Yeri: Kelime dersleri, "neden yanıldım" notu.
5. **Bol okuma:** Kolay ve çok okumak kelimeyi ve hızı geliştirir. Kaynak: Jeon & Day 2016; Nation. Yeri: Okuma evi, okuma sayacı.
6. **Kelime kapsamı:** YDS metinlerini rahat anlamak için ~6.500 kelime ailesi hedefliyoruz. Kaynak: Nation 2006; Laufer & Ravenhorst-Kalovski 2010. Yeri: Kelime bankası, haftalık hedef.
7. **Tekrar sayısı:** Bir kelime yaklaşık 10 karşılaşmada yerleşir. Kaynak: Webb 2007. Yeri: Kartlar + metinlerde geri dönüşüm.
8. **Deneme → analiz → hedefli tekrar.** Kaynak: Ericsson 1993; Adesope 2017. Yeri: Deneme sonucu, hata defteri.
9. **Zaman yönetimi:** 180 dakikayı bölümlere ayırmak ve 2 dakika kuralı. Yeri: Deneme sonucu.
10. **Alışkanlık:** Bir alışkanlık ortalama 66 gün sürer ve tek bir gün kaçırmak onu bozmaz. Kaynak: Lally vd. 2010. Yeri: Bugün planı, hatırlatıcı, seri dondurma.

**Metin kuralları:**
- Kartların metni **sade Türkçe**dir, kısa tutulur ve sayı uydurmaz.
- İddia, araştırma belgesindeki bulgudan daha güçlü yazılmaz. Örneğin "kanıtlanmış en iyi yöntem" denmez.

## 7. Kabul ölçütleri (inceleme listem)

1. `flutter test` geçiyor. Yeni mantık için birim testleri var:
   - aralık uzatma
   - iki kutu düşme
   - hata defteri 2 doğru kuralı
   - paralel bölüm açıklığı
   - planın hafta ilerlemesi
2. Eski ilerleme kayıtları (kutu 0–5, mistakes listesi) hatasız okunuyor. Birleştirme (`progress_merge`) yeni alanları kaybetmiyor.
3. Bugün ekranı: 2/3/4 saat seçenekleri doğru ölçekleniyor. Kaçırılan gün yığılmıyor.
4. Yöntemlerimiz metinleri araştırma belgesiyle tutarlı. Abartılı iddia yok.
5. Can/ceza dili ve mekanizması yok.
6. Emülatörde ekran görüntüleri `D:\Lingora\_cikti\yds-yontem\` klasöründe:
   - Bugün
   - hata defteri neden etiketi
   - deneme sonucu
   - Yöntemlerimiz

Belirsizlikte bana yazın (yds-arastirma).
