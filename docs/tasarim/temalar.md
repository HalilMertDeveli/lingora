# Konu temaları

Yol ekranında her ünite kendi konusunu gösterir. Çay temasını yalnızca selamlaşma, misafirlik, mahalle ve sohbet üniteleri kullanır. Seyahat ünitesinde düğümler bavul → bilet → uçak → oda anahtarı sırasıyla gelir. Yemek ünitesinde sunucu aşçı şapkası takar ve "Bir lokma daha!" der.

- Figma dosyası: <https://www.figma.com/design/0U87RtDyx2lmEu0tRTe0Og> ("Temalar" sayfası). Stil rehberi en üstte. Altında her tema için bir sayfa var: nesneler, ödül, rozet, süsler, kostüm ve sunucu cümleleri.
- Kod: `lib/data/topic_themes.dart` (katalog), `lib/ui/theme_art.dart` (çizim, hareket, rozet, kostüm), `lib/screens/path_map.dart` (`TeaNode(theme:, object:)`, `nodeObject`, `nodeInvite`, `UnitBand`, `RoadsideDecor`, `PathMascot(theme:)`).
- Assetler: `assets/themes/<tema>/<nesne>.svg`. 29 klasör, 181 dosya, toplam yaklaşık 140 KB. Assetleri `flutter_svg` çizer.
- Üretim: nesneler `tool/themes/objects.mjs` içinde elle yazılmış SVG'lerdir. `node tool/themes/gen_theme_svgs.mjs` komutu, kataloğun andığı her nesneyi tema klasörüne yazar ve eksik nesne varsa hata verir. Figma'ya yüklenen sayfaları `node tool/themes/figma_sheets.mjs` üretir (`build/figma/`).

## Stil rehberi

- 64×64 ızgara, tek nesne, ortada.
- Tek mürekkep çizgisi: `#3D2B1F`, 2,5 px, yuvarlak birleşim ve uç.
- Düz dolgu, gradyan yok. Renkler yalnızca aşağıdaki paletten gelir.
- Bir beyaz parlama (%70) ve zeminde mürekkep renginde, %12 opaklıkta yumuşak bir gölge. Gölge yalnızca yerde duran nesnelerde olur.
- Metin kullanılmaz. Tek istisnalar takvimdeki "7", etiketteki "₺" ve madeni paradaki "1"dir.

| Ad | Renk | | Ad | Renk |
|---|---|---|---|---|
| ink | `#3D2B1F` | | brown | `#A0673A` |
| red | `#E4572E` | | cream | `#FFF4DE` |
| orange | `#F39A3D` | | white | `#FFFFFF` |
| yellow | `#F4C542` | | gray | `#A9B2BC` |
| green | `#5BA55B` | | light | `#DDE3E8` |
| teal | `#2EA4A6` | | skin | `#F2C29B` |
| blue | `#3C7DD9` | | tea | `#B23A17` |
| navy | `#2B3A67` | | purple / pink | `#8E5BC9` / `#EE7FA6` |

### Durumlar tek nesneden türetilir

- **Bitti:** nesne tam renklidir. Altındaki tabak temanın vurgu rengini alır ve kalın bir halkayla çevrilir. Üstünde onay rozeti durur.
- **Aktif:** temanın hareketini yapar (`ThemeMotion`):
  - `sway`: yaprak ya da tabela gibi sallanır.
  - `bob`: süzülür.
  - `pulse`: kalp gibi atar.
  - `blink`: arkasında ekran ya da lamba ışığı gibi yanıp söner.
  - `wiggle`: çalar saat gibi titrer.

  Arkasında vurgu renginde bir parıltı vardır. Azaltılmış animasyon açıksa nesne durur.
- **Kilitli:** gri ton filtresi uygulanır (`greyscale`), opaklık %55'e (koyu temada %45'e) düşer ve kilit rozeti eklenir.
- **Ünite sınavı:** vurgu renginde fistolu bir rozet ve iki kurdele çizilir (`BadgePainter`). Ortasında temanın amblemi durur.
- **Ödül:** temanın sürprizi gösterilir (piknik sepeti, hediye bavulu, zaman kapsülü…). Açılınca yanında parıltılar belirir. Ödül penceresinde bu nesne sallanır ve temanın kendi cümlesi çıkar.

### Bant, yol kenarı, kostüm

- **Ünite bandı:** temanın iki süs nesnesi beyaz damgalar hâlinde desen oluşturur. Desen bandın ortasından sağa doğru belirginleşir. Bandın açık hâlinde ünitenin ilk hikâye nesnesi beyaz bir dairede eğik durur. Çay temasında İznik çini deseni korunur.
- **Yol kenarı:** yol bir yana kıvrıldığında, iki satırda bir, karşı tarafa temanın süslerinden biri (34 px) konur.
- **Kostüm:** bazı temalarda sunucu kostüm giyer. Kostüm, Çaycı Dayı'nın kutucuğunun ya da Pofuduk'un başının üstüne ayrı bir katman olarak konur. Maskot görsellerine dokunulmaz. Kostümler:
  - aşçı şapkası (yemek)
  - kaptan şapkası (seyahat)
  - hasır şapka (hava, doğa)
  - kulaklık (teknoloji, kod)
  - parti şapkası (duygular)
  - bere (sanat, sahne)
  - kep (kütüphane)
  - fötr (dedektif)
  - baret (tamir)
- **Bölüm şeritleri** (`DistrictPainter`) olduğu gibi kaldı. Mekânları zaten bölüm konularıyla örtüşüyor: Mahalle (temeller), Çarşı (günlük hayat), Vapur, Ofis (şehirde ve işte), Yolculuk (deneyimler), Kütüphane (fikirler ve hikâyeler), Toplantı (iş ve tartışma), Sahne (akıcılık, deyimler).

## Temalar

| Tema | Hikâye (adımlar) | Ödül | Rozet | Hareket | Ders cümlesi |
|---|---|---|---|---|---|
| `cay` Çay ve sohbet | çay bardağı, simit, demlik (çizim) | çaydanlık | lale | buhar | Hadi, bir çay daha! |
| `yemek` Yemek ve içecek | simit, çorba, tabak, elma | piknik sepeti | altın kaşık | wiggle | Bir lokma daha! |
| `aile` Aile ve ev | kapı, ev, pencere, anahtar | kurabiye kavanozu | ev | blink | Kapı açık, gir içeri! |
| `zaman` Sayılar ve zaman | çalar saat, duvar saati, takvim, kum saati | zaman kapsülü | saat | wiggle | Tik tak, ders vakti! |
| `alisveris` Alışveriş ve renkler | boya kalemi, etiket, poşet, cüzdan | hediye kutusu | etiket | sway | Sepete bir ders ekle! |
| `gunluk` Günlük hayat | çalar saat, diş fırçası, kupa, sırt çantası | kahvaltı tepsisi | kupa | bob | Günaydın, hadi başla! |
| `seyahat` Seyahat | bavul, bilet, uçak, oda anahtarı | hediye bavulu | pusula | sway | Biniş kartın hazır! |
| `sehir` Şehir | tabela, tramvay, trafik lambası, vapur | balonlar | tabela | blink | Tramvay kalkıyor, atla! |
| `gecmis` Geçmiş zaman | fotoğraf albümü, polaroid, radyo, günlük | anı sandığı | fotoğraf | blink | Albümü açalım mı? |
| `saglik` Sağlık | kalp, termometre, stetoskop, ilaç | ilk yardım çantası | kalp | pulse | Geçmiş olsun, başlayalım! |
| `hava` Hava ve mevsimler | güneş, bulut, şemsiye, kar tanesi | gökkuşağı | güneş | sway | Hava ders için şahane! |
| `hayaller` Planlar ve hayaller | harita, yıldız, roket, dilek feneri | hazine sandığı | yıldız | pulse | Bir dilek tut, başla! |
| `is` İş ve ofis | evrak çantası, dosya, kupa, ataş | ayın çalışanı kupası | çanta | bob | Mesai başladı! |
| `teknoloji` Teknoloji | telefon, kulaklık, dizüstü, wifi | robot | sinyal | blink | Telefon çalıyor, aç! |
| `yazisma` Yazışma | zarf, dolma kalem, pul, posta kutusu | kargo kolisi | mühür | sway | Yeni bir e-postan var! |
| `duygular` Duygular ve ilişkiler | gülen yüz, kalpli balon, şaşkın yüz, buket | kutlama pastası | kalp | pulse | İçini dök, başla! |
| `doga` Doğa | yaprak, zeytin dalı, arı, ağaç | bal kavanozu | zeytin dalı | sway | Yaprak kıpırdadı, başla! |
| `spor` Spor ve beceriler | top, raket, bisiklet, madalya | şampiyonluk kupası | madalya | bob | Isındın mı? Hadi! |
| `sanat` Müzik ve sanat | nota, gitar, palet, film şeridi | patlamış mısır | nota | sway | Sahne senin, çal bakalım! |
| `kutuphane` Eğitim ve kütüphane | kitap, kalem, gözlük, kep | dünya küresi | kep | sway | Sayfayı çevir! |
| `haber` Haber ve medya | gazete, mikrofon, kamera, radyo | televizyon | mikrofon | blink | Yayındasın! |
| `toplanti` Toplantı ve tartışma | ampul, konuşma balonları, grafik, sunum panosu | el sıkışma | fikir | blink | Söz sende! |
| `sahne` Deyimler ve sahne | maske, spot, perde, mikrofon | çiçek buketi | maske | sway | Perde! Sahne senin! |
| `dedektif` İpuçları ve tahmin | büyüteç, ayak izi, parmak izi, fötr | gizli kasa | büyüteç | sway | Bir ipucu buldum! |
| `olasilik` Olasılıklar | yol ayrımı, zar, madeni para, yonca | şans sandığı | yonca | wiggle | Zarı at! |
| `tamir` Tamir ve hizmet | İngiliz anahtarı, boya rulosu, makas, araba | alet çantası | anahtar | wiggle | Kolları sıvadık! |
| `mulakat` İş görüşmesi | özgeçmiş, kravat, mülakat masası, el sıkışma | yeni iş çantası | kravat | bob | Kravatını düzelt! |
| `otel` Otel resepsiyonu | resepsiyon zili, oda anahtarı, havlu, kapı askısı | karşılama hediyesi | zil | wiggle | Zil çaldı, misafir geldi! |
| `kod` Kod ve terminal | terminal, kod, git dalı, böcek | robot | kod | blink | `git commit -m "ders"` |

Bir ünitenin beşinci adımı varsa liste başa döner. Hikâye düğümü de bu sırada yer alır, ayrıca kitap rozetini taşır.

## Ünite → tema

Ünite JSON'undaki alan: `"theme": "<id>"`. Alan yoksa ya da bilinmeyen bir id varsa `cay` kullanılır (`themeById`).

- **Bölüm 1:**
  1. cay
  2. yemek
  3. aile
  4. zaman
  5. alisveris
  6. gunluk
  7. aile
  8. seyahat
  9. gecmis
  10. saglik
  11. hava
  12. hayaller
- **Bölüm 2:**
  1. gunluk
  2. is
  3. cay
  4. sanat
  5. aile
  6. cay (Mahallem)
  7. sehir
  8. sehir
  9. spor
  10. yemek
  11. zaman
  12. seyahat
- **Bölüm 3:**
  1. gecmis
  2. gecmis
  3. doga
  4. seyahat
  5. dedektif
  6. zaman
  7. duygular
  8. spor
  9. alisveris
  10. hayaller
  11. olasilik
  12. hayaller
- **Bölüm 4:**
  1. aile
  2. seyahat
  3. zaman
  4. is
  5. is
  6. alisveris
  7. hava
  8. spor
  9. cay (hangi kafe)
  10. yazisma
  11. teknoloji
  12. sehir
- **Bölüm 5:**
  1. zaman
  2. tamir
  3. gecmis
  4. doga
  5. kutuphane
  6. olasilik
  7. haber
  8. gunluk
  9. dedektif
  10. seyahat
  11. mulakat
  12. duygular
- **Bölüm 6:**
  1. gecmis
  2. kutuphane
  3. dedektif
  4. haber
  5. duygular
  6. hayaller
  7. duygular
  8. cay (sohbeti sürdürmek)
  9. duygular
  10. toplanti
  11. toplanti
  12. sanat
- **Bölüm 7:**
  1. olasilik
  2. olasilik
  3. dedektif
  4. haber
  5. toplanti
  6. yazisma
  7. tamir
  8. sahne
  9. is
  10. toplanti
  11. alisveris
  12. haber
- **Bölüm 8:**
  1. cay (konuşma belirteçleri)
  2. yazisma
  3. toplanti
  4. sahne
  5. sahne
  6. is
  7. toplanti
  8. dedektif
  9. yazisma
  10. kutuphane
- **Meslek parçaları:**
  - İş Görüşmesi: mulakat ×4
  - Turizm: otel, otel, yemek, seyahat, otel
- **Yazılımcı İngilizcesi:** öğrenme yolu yok. Konu kartlarında `kod` temasının nesneleri görünür: kod, git dalı, böcek, terminal… (`softwareTopicObject`).

## Performans ve erişilebilirlik

- SVG'ler küçük, toplamı yaklaşık 140 KB. `flutter_svg` her resmi bir kez ayrıştırıp önbelleğe alır.
- Açılışta yalnızca güncel ünitenin teması önceden yüklenir (`precacheTheme`). Diğer temalar ekrana geldikçe yüklenir.
- Katlanmış bölümler hiç düğüm kurmaz.
- Hareketler `MediaQuery.disableAnimations` ayarına uyar. Uygulamanın "Azaltılmış animasyon" ayarı da bu ayarı açar.
- Süsler ve bant deseni ekran okuyucudan gizlenir (`ExcludeSemantics`). Düğümlerin etiketi ve durumu ("Bitti / Sıradaki / Kilitli") değişmedi.
- Koyu temada nesneler, tabak sayesinde okunur kalır. Çocuk modunda Pofuduk aynı kostümleri giyer.

## Lisans

Tüm tema nesneleri bu proje için elle yazıldı (`tool/themes/objects.mjs`). Hiçbir uygulamanın, ikon setinin ya da stok görselin kopyası değildir. Projenin lisansı geçerlidir. Figma'daki sayfalar bu SVG'lerden üretildi. Figma'nın ücretli yapay zekâ üreticisi kullanılmadı: aynı çizgi ve paleti tutturmak ve lisansı temiz tutmak için nesneler elle yazıldı.
