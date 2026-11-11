# Görsel varlıklar ve kaynakları

## Kaynak

Tüm görseller **uygulama sahibi tarafından sağlandı**:

- **Resmî maskot: Çaycı Dayı** (`cayci_dayi_logo.svg`, 512×512 SVG). Turuncu yuvarlak kare
  (`#FF9A2E` → `#F17F04`) üstünde kasketli, bıyıklı, elinde ince belli çay bardağı tutan çaycı.
  Sahibin notu: "maskot bu".
- **Lexigo tasarım seti:** turuncu yastık karakter **Pofuduk** (ikinci maskot), bayraklar, ikonlar, sosyal
  logolar ve giriş/şifre ekranı tasarım referansları.

Setin orijinal dosyaları repoya eklenmedi; uygulamada yalnızca aşağıdaki işlenmiş kopyalar var. İşleme betiği
`tool/lexigo_assets.dart.txt` (beyaz zemin ve zemin gölgesi kenardan taşma doldurmayla şeffaf yapıldı, kol ile
gövde arasındaki kapalı beyaz boşluklar da silindi, göz akları korundu; kırpıldı, en uzun kenar 420 px).

| Repo dosyası | Kaynak | Nerede |
|---|---|---|
| `assets/mascot/cayci_dayi.svg` / `.png` | Çaycı Dayı SVG | Yetişkin modunun sunucusu, logo, davet balonundaki yüz |
| `assets/icon/icon.png`, `icon_foreground.png` | aynı | Uygulama ikonu |
| `assets/mascot/pofuduk_avatar.png` | `maskot/01` kare yüz | Çocuk modu profil avatarı, Çocuk modu davet balonu |
| `assets/mascot/pofuduk_hesap.png` | `maskot/02` telefonlu çizim | Giriş / hesap ekranı çizimi |
| `assets/mascot/pofuduk_selam.png` | `maskot/03` el sallayan | Karşılama (iki mod), `Mood.wave` |
| `assets/mascot/pofuduk_uzgun.png` | `maskot/04` üzgün, işaret eden | Çocuk modu yanlış cevap ("doğrusu şurada") |
| `assets/mascot/pofuduk_gozluk.png` | `maskot/05` gözlüklü | Ders sonu kutlaması (iki mod), `Mood.cheer` |
| `assets/mascot/pofuduk_dans.png` | `maskot/07` dans eden | Seri kutlaması (iki mod), Çocuk modu doğru cevap |
| `assets/mascot/pofuduk_isaret.png` | `maskot/08` yukarı işaret eden | Çocuk modu düşünme / ipucu, yol kenarı |
| `assets/mascot/pofuduk_meditasyon.png` | `maskot/13` meditasyon | Çay molası (iki mod), `Mood.calm` |
| `assets/flags/gb.png`, `us.png` | `bayraklar/15`, `20` | Kurs çekmecesi aksan seçimi, kurs bayrağı, misafir kartı |
| `assets/flags/es.png`, `fr.png` | `bayraklar/21`, `18` | Misafir kartı; karşılamada "Yakında" dilleri |
| `assets/flags/in.png`, `pk.png`, `sa.png` | `bayraklar/19`, `17`, `16` | Turizm İngilizcesi "Misafirlerin nereden geliyor?" kartı |
| `assets/brand/google_g.png` | `yuvarlak-gorseller/09` | Giriş ekranı Google butonu |
| `assets/brand/arkadaslar.png` | `ikonlar/06` | "Arkadaşını davet et" ekranı |
| `assets/brand/video.png` | `ikonlar/23` | Pratik > Konuşma (sahne) |

Bayraklar 3:2 ortadan kırpılıp 120×80 yapıldı.

**Kullanılmayanlar ve nedenleri:**
- `bayraklar/14`: İspanya bayrağı, `21` ile aynı; daha yüksek çözünürlüklü `21` kullanıldı.
- `ikonlar/22`: Google "G", `yuvarlak-gorseller/09` ile aynı logo; giriş butonunda tek logo yeterli.
- `ikonlar/24` (YouTube): Dilbaz'ın YouTube kanalı yok; boş bir bağlantı yanıltıcı olur.
- `ikonlar/25` (App Store): uygulama şimdilik yalnızca Google Play'de ve abonelik Google Play üzerinden.
- `yuvarlak-gorseller/10–12` (X, GitHub, Apple): bu girişler desteklenmiyor; yalnızca Google var.
- `maskot/26`, `27`: giriş/şifre ekranı tasarım referansı; görsel olarak değil, düzen olarak kullanıldı (giriş ekranı bu düzende, renkler yeni paletten).

## Maskotlar

**Çaycı Dayı** (`Dayi`): yetişkin modunun sunucusu. Küçük (44–72 px) ve hareketsiz; turuncu karo kendi zeminini
taşıdığı için açık ve koyu temada aynı görünür.

**Pofuduk** (`Pofuduk`): Çocuk modunun ana karakteri. Her `Mood` için ayrı poz (`pofudukPose`), hareket poza uyar
(neşede zıplayıp jelibon gibi ezilme, meditasyonda süzülme, selamda sallanma). Karşılama, kutlama ve mola
anlarında iki modda da görünür.

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
