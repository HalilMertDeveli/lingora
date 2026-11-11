# Görsel varlıklar ve kaynakları

## Kaynak

Tüm görseller **uygulama sahibi tarafından sağlandı**:

- **Resmî maskot: Çaycı Dayı** (`cayci_dayi_logo.svg`, 512×512 SVG). Turuncu yuvarlak kare
  (`#FF9A2E` → `#F17F04`) üstünde kasketli, bıyıklı, elinde ince belli çay bardağı tutan çaycı.
  Sahibin notu: "maskot bu".
- **Lexigo tasarım seti:** bayraklar, Google "G" logosu ve giriş/şifre ekranı tasarım referansları.
  Setteki turuncu yastık karakter pozları, sahibin resmî maskotu gönderdiği için kullanılmıyor.

Setin orijinal dosyaları repoya eklenmedi; uygulamada yalnızca aşağıdaki kopyalar var.

| Repo dosyası | Kaynak | İşlem |
|---|---|---|
| `assets/mascot/cayci_dayi.svg` | Çaycı Dayı SVG | Değiştirilmemiş orijinal (kaynak olarak saklanıyor) |
| `assets/mascot/cayci_dayi.png` | aynı | 512 px PNG, yuvarlak köşeler şeffaf; uygulama içi maskot ve logo |
| `assets/icon/icon.png` | aynı | 1024 px, köşeler yuvarlatılmamış (iOS, web, eski Android ikonları) |
| `assets/icon/icon_foreground.png` | aynı | 1024 px, tam turuncu zemin; karakter %62 ölçekte, yüzü ortada, gömlek alta uzatıldı (Android adaptive ön planı, dairesel maskede bardak da görünür) |
| `assets/flags/gb.png` | Lexigo `bayraklar/15` (Birleşik Krallık) | 120×60 |
| `assets/brand/google_g.png` | Lexigo `yuvarlak-gorseller/09` (Google "G") | Beyaz zemin şeffaf yapıldı, 144 px; renk ve oran değişmedi |

PNG'ler SVG'den headless Edge ile üretildi (`--screenshot`, şeffaf arka plan).

Kullanılmayanlar: Lexigo setindeki maskot pozları ve kare yüz (`maskot/01–13`), `maskot/26` ve
`27` (yalnızca giriş/şifre ekranı tasarım referansı), `ikonlar/*` (kişiler, video, YouTube ve App
Store ikonları), X / GitHub / Apple logoları (bu sağlayıcılar desteklenmiyor) ve İngilizce dışı
bayraklar (İspanya, Suudi Arabistan, Pakistan, Fransa, Hindistan). Sette ABD bayrağı da var; kurs
İngiliz İngilizcesi ağırlıklı olduğu için şimdilik yalnızca Birleşik Krallık bayrağı kullanılıyor.

## Maskot: Çaycı Dayı

Dilbaz'ın rehberi (`lib/ui/mascot.dart`, `Mascot` ve `Dayi`). Tek bir çizim var; ruh hâli
(`Mood`) yalnızca hareketi değiştiriyor: neşeli zıplama (`cheer`/`joy`), el sallar gibi sekme
(`happy`), sakin salınım (`calm`), düşünceli sallanma (`think`), hafif küçülme (`sad`).

- Çocuk modunda büyük ve hareketli, yetişkin modunda küçük (44–72 px) ve hareketsiz.
- Turuncu karo kendi zeminini taşıdığı için açık ve koyu temada aynı görünüyor.

Kullanıldığı yerler: karşılama ekranı, ders sonu (başarıda `cheer`, normalde `happy`), seri ekranı ve
çay molası hatırlatması (`calm`), boş durumlar (`EmptyState`) ve giriş ekranı. Logo (`LingoraLogo`)
da aynı karo.

Sahip duygu pozları (sevinçli, üzgün, düşünceli…) gönderirse `Mood` için ayrı görseller eklenebilir.

## Uygulama ikonu

`flutter_launcher_icons` ile üretilir (ayarlar `pubspec.yaml` içinde):

```bash
dart run flutter_launcher_icons
```

- **Android adaptive:** arka plan `#F17F04`. Ön plan gradyanı da içeren tam kare olduğu için
  `mipmap-anydpi-v26/ic_launcher.xml` elle `inset` olmadan yazıldı; araç her çalıştığında %16 inset
  ekliyor, bu dosyayı geri alın.
- **iOS:** alfa kanalı olmayan tam kare; köşeleri sistem yuvarlıyor.
- **Web:** `web/icons/*` ve `favicon.png`.
- **Araç hatası:** araç iOS `project.pbxproj` içinde
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` satırını bozuyor ve
  `Contents.json`'u küçültüyor. Yeniden ürettikten sonra bu iki dosyayı `git checkout` ile geri alın;
  PNG'ler aynı adlarla yerinde güncellenir.

## Google logosu

Giriş ekranındaki Google butonu, Google'ın resmî çok renkli "G" logosunu
[Google Sign-In marka kurallarına](https://developers.google.com/identity/branding-guidelines) uygun
kullanır:

- Logo değiştirilmedi: renk, oran ve yön aynı.
- Beyaz zemin üstünde, etrafında yeterli boşlukla gösteriliyor.
- Buton metni "Google" ve buton yalnızca Google ile giriş başlatıyor.
- Logo başka bir yerde süsleme amacıyla kullanılmıyor.
