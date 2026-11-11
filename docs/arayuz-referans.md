# Arayüz referansı: davranış tarifi

Bu belge, referans dil uygulamasının (çözülmüş APK) arayüzünün **nasıl davrandığını** kendi cümlelerimizle anlatır.
Burada kod, metin, görsel, ses, animasyon dosyası, maskot, marka ya da renk paleti kopyası yoktur.
Temiz oda kuralı geçerlidir: davranış ve kalıplar taklit edilebilir, varlıklar ise kopyalanmaz.
Sayılar, kaynak koddaki sabitlerden ve `res/anim*` dosyalarındaki değerlerden okundu.

Son sütun, aynı davranışın Dilbaz'da nerede durduğunu gösterir.

> Kısaltmalar: dp = Android yoğunluktan bağımsız piksel (Flutter'da mantıksal piksel). "Overshoot" = hedefi
> biraz aşıp geri oturan eğri. "fast-out-slow-in" = hızlı başlayıp yumuşak biten eğri (Flutter `Curves.fastOutSlowIn`).

## 1. Ana ekran sekmeleri

| Davranış | Referans | Dilbaz |
|---|---|---|
| Sekme seti | Kullanıcıya göre değişen bir alt küme. Tipik sıra: Öğren · Pratik · Lig · Görevler · Profil (+ Daha fazla) | `tabsFor(kind)`: genel kurs için Öğren · Pratik · Lig · Görevler · Profil; kelime (Yazılımcı) parçası için Keşfet · Tekrar · Harita · Senaryolar · Profil (`lib/nav/nav_target.dart`) |
| Alt çubuk | Yaklaşık 86 dp yüksek. Seçili sekmenin ikonunun arkasında vurgu zemini var; ikonda rozet ya da nokta gösterilebiliyor | `NavigationBar`, seçili sekmede turuncu yarı saydam gösterge, Görevler ve Tekrar sekmesinde sayı rozeti |
| Sekme durumu | Her sekme kendi kabında canlı kalıyor, görünürlükle değişiyor | `IndexedStack` + sekme başına `TabNavigator` (PR #18) |
| Geçiş | Referansta anlık. Dokunuşta kısa bir tuş titreşimi var | Görev isteği gereği **fade-through**: yeni sekme 260 ms içinde, ilk %30'luk bekleme sonrası 0.92→1 büyüyerek belirir (`FadeThroughIn`, `lib/ui/transitions.dart`). Animasyonlar azaltılmışsa anlık |
| Aynı sekmeye tekrar dokunma | İçteki sayfaları kapatıp sekme köküne dönüyor; kökteyse başa kaydırıyor | Aynı kural (`_select`, `TabScope.reselected`) |

## 2. Üst çubuk ve açılır paneller

- **Çubuk:** 48 dp yüksek, altında 2 dp çizgi var. Soldan sağa sırayla kurs bayrağı, seri (alev ve sayı), enerji/kalp ya da mağaza ve elmas (para birimi) duruyor. Bazı sekmelerde başlık ve ayar ikonu da çıkıyor. Öğren sekmesinde çubuğun zemini o anki ünitenin rengine boyanıyor.
- **Paneller:** her öğeye dokununca çubuğun altından aşağı doğru bir panel kayıyor: seri takvimi, elmas, enerji, kurs seçici. Açılış ve kapanış 300 ms sürüyor ve yavaş başlayıp hızlanıyor. Arkadaki içerik karartılıyor. Panel yukarı kaydırılarak ya da alttaki boş alana dokunularak kapanıyor.
- **Dilbaz:** `LingoraTopBar` (`lib/nav/top_bar.dart`, PR #18) kurs, seri ve XP öğeleriyle aynı yapıda. Can ya da enerji öğesi yok (can/ceza yok kuralı). Bu PR'da çubuğa dokunulmadı.

## 3. Yol ekranı (path)

### Düğüm dizilimi
- Düğümler beş yatay şeritte duruyor: sol, yarı sol, orta, yarı sağ, sağ. Sekizlik bir dalga deseni tekrarlanıyor: orta, yarı sol, sol, yarı sol, orta, yarı sağ, sağ, yarı sağ.
- Tek numaralı ünitelerde desen aynalanıyor. Ünitenin son düğümü her zaman ortada.
- Toplam salınım genişliği yaklaşık 140 dp, yani merkezden her iki yana ±70 dp.
- İki ardışık düğümün merkezleri arasındaki doğrusal uzaklık sabit (yarıçaplar + 64 dp). Bu yüzden çapraz komşular dikeyde biraz daha yakın duruyor.
- **Dilbaz:** `zigzag(i, count:, mirror:)` aynı dalgayı üretir, son düğümü ortalar. Salınım `min(70, genişlik × 0.2)` (`lib/screens/path_map.dart`). Satır yüksekliği sabit; aktif satırda balon için ek 58 px yer var.

### Düğüm görünümü ve durumları
- Ders düğümü yaklaşık 70 dp boyunda yuvarlak bir yüz; altında 8 dp kalınlığında daha koyu bir dudak (lip) var. Basınca yüz aşağı iniyor.
- Aktif düğümün çevresinde bir ilerleme halkası var (~98 dp; gri iz, renkli dolgu, yuvarlak uçlar).
- Durumlar:
  - **Kilitli:** gri yüz ve gri ikon.
  - **Aktif:** ünite rengi, halka ve "Başla" balonu.
  - **Bitmiş:** ünite rengi ve onay ikonu.
  - **Efsanevi:** altın.
- Sandık düğümü daha büyük (yaklaşık 80×90). Ünite sınavı kupa şeklinde.
- Bir düğüm kilitliden aktife geçince şu sıra oynuyor:
  - ikon 300 ms'de küçülüp kayboluyor, değişiyor, sonra 300 ms'de overshoot ile büyüyerek geri geliyor
  - zemin 400 ms'de renk değiştiriyor
  - halka ve balon 400 ms'de beliriyor
  - bu geçiş, yola dönüldükten ~800 ms sonra başlıyor
- **Dilbaz:** `PathNodeButton`:
  - 70 px yüz ve 7 px dudak; basınca 70 ms'de iniyor.
  - Kilitli: gri yüz ve kilit ikonu.
  - Aktif: ünite tonu, radyal parlama ve halka (`active-ring`).
  - Bitmiş: ünite tonu ve onay ikonu.
  - Sandık amber renkte ve hediye ikonlu; ünite sınavı kupa ikonlu; hikâye kitap ikonlu.
  - Yeni ulaşılan düğüm 2,4 sn parlıyor (`NodeHighlight`, PR #18'den).
  - Düğümün altında, referanstan farklı olarak kısa başlığı yazıyor; Türkçe ders adları yolu okunur kılıyor.

### "Başla" balonu
- Aktif düğümün üstünde, aşağıyı işaret eden bir konuşma balonu duruyor.
- Sürekli 8 dp yukarı-aşağı süzülüyor: her yön 1000 ms, yavaş başlayıp yavaş biten eğriyle, ileri-geri tekrar.
- Kapanırken 250 ms'de soluyor.
- **Dilbaz:** `StartBalloon`, aynı salınım değerleri (`StartBalloon.leg`, `amplitude`). Balona dokunmak adımı doğrudan başlatıyor. Animasyonlar azaltılmışsa balon durgun.

### Düğüme dokununca açılan ders kartı
- Kart ünite renginde. Yer varsa düğümün altında açılıyor ve oku yukarıyı gösteriyor; yer yoksa düğümün üstünde açılıyor ve oku aşağıyı gösteriyor. Ok her zaman düğümün ortasına bakıyor.
- İçerik: başlık, "Ders x / y" alt yazısı, beyaz yüzlü ve ünite rengi yazılı tam genişlik 3B buton ("Başla +XP").
- Başla'ya basınca kart ekran ortasına doğru büyüyor (220 ms), beyaz bir perde ile ders açılıyor.
- Kartın dışına dokununca kart kapanıyor.
- **Dilbaz:** `LessonCard` + `OverlayPortal`/`CompositedTransformFollower`:
  - Düğüm ekranın alt %45'indeyse kart üstte açılıyor. Açılış 200 ms ölçek + saydamlık (`_CardPop`).
  - İçerikte başlık, "Ders x / y", ilerleme çubuğu ve açıklama var. Buton beyaz yüzlü, yazısı ünite renginin koyusu.
  - Bitmiş adımda buton "Tekrar et", sandıkta "Aç", sınavda "Sınava başla".
  - Kilitli adımda buton yok, nasıl açılacağı yazıyor.
  - Kaydırmaya başlamak ya da dışarı dokunmak kartı kapatıyor.
  - Ders, perde yerine aşağıdan yukarı tam ekran geçişle açılıyor (bölüm 6).

### Ünite bandı ve rehber
- Her ünitenin başında ünite renginde bir kart var: "Bölüm X, Ünite Y", hedef metni ve sağda 56 dp genişliğinde bir defter (rehber) butonu. Kartın altında %20 karanlık bir dudak var.
- Kaydırırken bu bant ekranın üstüne yapışıyor. Başka bir üniteye geçilince renk 250 ms'de değişiyor.
- **Dilbaz:**
  - `UnitBand`: hero zemin, koyu dudak, "Rehber" butonu.
  - Ünitenin kendi bandı yarısından fazla yukarı kaydığında aynı bandın kısa sürümü üste yapışıyor (`sticky-unit-band`, 250 ms yer değiştirme).
  - Rehber (`showUnitGuide`) bir alt sayfa: ünite açıklaması, alıştırmalardan derlenen "Anahtar ifadeler" (İngilizce → Türkçe) ve adımların durum listesi.

### Bölüm kartları ve katlama
Referansta bölüm seçimi ayrı bir ekranda yapılıyor. Dilbaz'daki bölüm başlıkları, kilitli ve bitmiş bölümlerin katlanması (PR #25) ve "Bulunduğun yere dön" düğmesi aynen korundu.

### Karakterler
- Yolun kenarında, ünitenin düğümleri arasına eşit aralıklarla karakter animasyonları yerleşiyor (dil kurslarında ilk ünitede 1, diğerlerinde 2).
- **Dilbaz:** dört ve daha fazla düğümlü ünitelerde 3. satırda, yolun uzaklaştığı tarafta Çaycı Dayı duruyor (`PathMascot`). Ünite bitince sevinçli ruh hâline geçiyor. Çocuk modunda 104 px ve hareketli, yetişkinde 84 px ve durgun.

## 4. Ders oturumu

### Üst çubuk
- Yaklaşık 64 dp yüksekliğinde: kapat X (32 dp), 16 dp kalınlığında ilerleme çubuğu ve sağda can göstergesi.
- **Dilbaz:** `SessionHeader`. Canın yerinde ders sayacı ("3/8") ya da mod ikonu duruyor; can yok.

### İlerleme çubuğu ve seri vurgusu
- Dolgu, eski değerden yeni değere 400 ms'de overshoot eğrisiyle ilerliyor (200 ms gecikmeli). Üstünde ince bir parlama şeridi var.
- Doğru cevap serisi renge yansıyor: 0–2 doğru → temel yeşil; 3–4 doğru → sarı; 5 ve üstü → turuncu. Renk değişimi yumuşak bir geçişle oluyor.
- Seri sayısı ("N in a row" benzeri) etiket olarak overshoot ile beliriyor.
- **Dilbaz:**
  - `SessionProgressBar`: 16 px, 400 ms, `Curves.easeOutBack`, parlama şeridi.
  - Seri 3–4 olunca dolgu amber, 5 ve üstünde seri turuncusu.
  - Her yeni seri adımında çubuğun üstünden bir ışık süpürülüyor (900 ms).
  - Altta "🔥 N DOĞRU ÜST ÜSTE" etiketi pop-in ile çıkıyor (`combo-label`; emoji yalnız çocuk modunda).

### Seçenek kartları ve butonlar (3B basılma)
- Kartlarda 4 dp dudak, 2 dp kenar ve 16 dp köşe var. Basma **anlık**: yüz (dudak − kenar) kadar iniyor, dudak inceliyor.
- Seçili kart "seçili" rengine geçiyor.
- Tüm kart ve butonlarda basışta kısa bir tuş titreşimi var.
- **Dilbaz:**
  - `TapCard` artık **iki modda da** dokunulabilir olduğunda 3B. Yetişkinde 2 px kenar ve 3 px dudak; çocukta 2 px kenar ve 4 px dudak. Basınca iniyor.
  - `PressableButton` iki modda da yuvarlak (hap) ve dudaklı. Yetişkinde 50+4 px, cümle düzeni; çocukta 54+5 px, büyük harf. Basınca 70 ms'de iniyor.

### "Kontrol et" ve geçişler
- Altta tam genişlik "Kontrol et" butonu var. Cevap seçilmeden pasif.
- Sonraki soru sağdan kayarak geliyor, eskisi sola çıkıyor: ±%100 kayma ve saydamlık, 500 ms, fast-out-slow-in.
- Yanlış cevapta seçenekler yatay sallanıyor: 15 → −12 → 9 → −6 → 0 dp, 5 adım × 85 ms.
- **Dilbaz:** `CheckBar`. Soru geçişi 500 ms `fastOutSlowIn` ve tam genişlikte kayma. `Shake` aynı ana kareleri kullanıyor (yetişkinde %60 genlik).

### Geri bildirim paneli
- Alttan yukarı 300 ms'de kayarak açılıyor.
  - Doğruysa açık yeşil zemin, yeşil başlık (övgü) ve yeşil "Devam".
  - Yanlışsa açık kırmızı zemin, kırmızı "Doğru cevap:" başlığı, doğru cevap metni ve kırmızı "Devam".
- "Kontrol et" butonu aynı yerde "Devam"a dönüşüyor.
- **Dilbaz:** `AnswerFeedbackPanel`:
  - 300 ms `easeOutCubic` kayma.
  - Doğru: `successBg` zemin. Yanlış: `errorBg` zemin; turuncu marka rengiyle karışmasın diye kırmızı seçildi.
  - Yanlışta "Neden yanlış?" (Türk hata dedektörü) ya da kelime ipucu da gösteriliyor.
  - Sağda Çaycı Dayı tepki veriyor: doğruda sevinç zıplaması, yanlışta hafif sarkma.
- Vocab tekrar ekranı da aynı paneli, "Kelimeye bak" ikincil eylemiyle kullanıyor.

### Ses ve titreşim
- Referansta doğru, yanlış ve yazım hatası için ayrı sesler var. 5 ve 10 seride, kusursuz derste, ders sonunda ve her istatistik kartında ek bir ses çalıyor.
- Titreşim, ayar izin veriyorsa her basışta kısa bir tuş titreşimi.
- **Dilbaz:**
  - Ses dosyası yok ve eklenmedi.
  - `SessionFx`: doğruda hafif titreşim ve platformun kendi kısa tık sesi; yanlışta orta titreşim; kutlamada orta titreşim ve tık.
  - Ses, Profil > Görünüm > **Ses efektleri** ile kapatılabiliyor (`AppSettings.sound`); titreşim her zaman çalışıyor.

## 5. Oturum sonu kutlama zinciri

- Ekranlar yatay kaydırma kapalı bir sayfa dizisinde duruyor ve "Devam" ile ilerleniyor. Bazı geçişler sağdan sola 400 ms.
- Tipik sıra:
  1. ders tamamlandı (istatistik kartları ve karakter animasyonu)
  2. günlük görev ilerlemesi ve ödül
  3. aylık hedef
  4. **seri uzadı** (alev ve sayaç)
  5. diğer seri, lig ve başarı ekranları
- İstatistik kartları üç tane: toplam XP, doğruluk ve süre. Her biri renkli bir başlık bandı ve içte beyaz bir kart. Sayı yuvarlanarak sayıyor.
  - Kartlar sırayla 175 ms'de (100 ms gecikmeyle) büyüyerek beliriyor.
  - 600 ms sonra 300 ms'lik bir vurgu, ardından 900 ms'lik bir parlama geçiyor.
  - Her kartta bir ses çalıyor.
- Seri ekranında alev ve sayaç 400 ms'de canlanıyor; havai fişek ve konfeti animasyon dosyasıyla yapılıyor.
- **Dilbaz:** `celebrationSteps` + `showEndSequence`:
  1. **Sonuç** (`LessonResultScreen`):
     - Konfeti, tepki veren Çaycı Dayı ve üç renkli istatistik kartı (XP sayacı 1100 ms count-up; doğruluk ve süre).
     - Kartlar 140 ms arayla pop-in ile geliyor.
  2. **Günlük görevler** (`QuestProgressScreen`), görev ya da hedef ilerlediyse gösteriliyor:
     - Günlük hedef ve her görev çubuğu eski değerden yeni değere 700 ms'de doluyor, çubuklar 350 ms arayla.
     - Tamamlanan görevde "Ödül hazır" yazısı çıkıyor, ekrana konfeti ve maskot sevinci geliyor.
  3. **Seri** (`StreakCelebrationScreen`), seri bugün uzadıysa gösteriliyor:
     - Alev pop-in ile çıkıyor; sayaç dünkü değerden bugüne sayıyor.
     - Son yedi günün noktaları sırayla yanıyor (90 ms arayla).
  4. Mevcut **çay molası** ve kapatılabilir paywall adımları zincirin sonunda kalıyor.
  - Konfeti kendi `CustomPainter`'ımızla çiziliyor (`ConfettiPainter`):
    - 110 parça kâğıt ekranın üst üçte birinden fırlıyor, hava sürtünmesiyle yavaşlıyor, düşerken dönüyor.
    - Parçalar en ve boy daralarak takla atıyor. Şekiller şerit, kare ve nokta; renkler aktif paletten geliyor.
    - Süre 2800 ms.

## 6. Geçiş ve animasyon süreleri

### Referans `res/anim*` (davranış özeti)

| Dosya ailesi | Davranış |
|---|---|
| challenge_slide_in/out (sağ/sol) | ±%100 yatay kayma ve saydamlık, 500 ms, fast-out-slow-in |
| slide_in_bottom / slide_out_bottom | Aşağıdan yukarı, %100 ↔ 0, 200 ms (`_medium` türevi 400 ms) |
| slide_in_right / slide_out_left | Yatay %100 kayma, 400 ms (çıkan sayfa yarı saydama iniyor) |
| fade_in / fade_out | Saydamlık 0.5 ↔ 1, 400 ms |
| fade_zoom_in | 0.7 → 1 ölçek ve saydamlık, 400 ms |
| popup_in/out, popup_scale_in/out | Saydamlık ya da 0 ↔ 1 ölçek, 200 ms |
| popup_slide_in | %5 aşağıdan kayma ve saydamlık, 400 ms |
| stay | 500 ms boyunca eski ekranı yerinde tutma |
| animator/shake | 5 × 85 ms yatay sallanma (15 / −12 / 9 / −6 / 0 dp) |

### Referans kod sabitleri ve Dilbaz karşılıkları

| Öğe | Referans | Dilbaz sabiti |
|---|---|---|
| İlerleme dolgusu | 400 ms, +200 ms gecikme, overshoot | `SessionProgressBar.fillDuration` 400 ms, `easeOutBack` |
| Geri bildirim paneli | 300 ms alttan kayma | `AnswerFeedbackPanel.slideDuration` 300 ms |
| Soru geçişi | 500 ms fast-out-slow-in | `lesson_screen.dart` AnimatedSwitcher 500 ms |
| Yanlış sallanması | 5 × 85 ms | `Shake` 425 ms, aynı ana kareler |
| Başla balonu | 8 dp, 1000 ms her yön | `StartBalloon.amplitude` 8, `StartBalloon.leg` 1000 ms |
| Kart / popup | 200 ms ölçek ve saydamlık | `_CardPop` 200 ms |
| Üst çubuk panelleri | 300 ms | (PR #18 panelleri; bu PR'da değişmedi) |
| Ünite bandı rengi | 250 ms | yapışkan bant `AnimatedSwitcher` 250 ms |
| İstatistik kartları | 175 / 300 / 900 ms | `PopIn` 260 ms (çocukta elastik 420 ms), 140 ms arayla |
| Seri sayacı | 400 ms | `CountUp` 700 ms |
| Ders açılışı | Kartın büyüyüp beyaz perdeye dönüşmesi | `DilbazPageTransitionsBuilder`: tam ekran akışlar (`fullscreenDialog`) aşağıdan yukarı, `easeOutCubic` / kapanışta `easeInCubic`, rota süresi 300 ms |
| Sekmeler | Anlık | `FadeThroughIn` 260 ms (görev isteği) |

### Animasyonları azalt
- Referansta erişilebilirlik bayrağı açıksa soru kaymaları tamamen kapanıyor.
- **Dilbaz** iki yerden dinliyor: telefonun "animasyonları kaldır" ayarı (`MediaQuery.disableAnimations`) ve Profil > Görünüm > **Animasyonları azalt** anahtarı. Anahtar, uygulama kökünde `MediaQuery`'yi `disableAnimations: true` ile sarıyor; böylece tek bir yerden her şey kapanıyor.
- Azaltılmış modda şunlar oluyor:
  - konfeti çizilmiyor
  - balon ve maskot döngüleri duruyor
  - ilerleme çubuğu, sayaçlar, pop-in'ler ve geri bildirim paneli doğrudan son hâlinde görünüyor
  - sallanma, sekme fade-through, soru kayması ve sayfa geçişleri anlık oluyor

## 7. Renk ve biçim (Dilbaz'a özgü)
- **Vurgu rengi:** sahibin Lexigo setinden turuncu. Ana renkler: yetişkin açık `#E06C00`, yetişkin koyu `#F39A3D` (koyu yazıyla), çocuk açık `#F17F04`, çocuk koyu `#FF9F43`.
- **Butonlar:** referanstaki gibi kalın dudaklı ama Lexigo'daki gibi tam yuvarlak hap biçiminde.
- **Doğru/yanlış renkleri:** paletin `success` ve `error` tokenları; referans renkleri kullanılmadı.
- **Koyu tema ve Çocuk modu:** dört palet de çalışıyor. Çocuk modu büyük harf ve büyük maskotla devam ediyor.
