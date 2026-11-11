# Görsel varlıklar ve kaynakları

## Kaynak

Maskot, uygulama ikonu, bayraklar, Google "G" logosu ve giriş ekranı tasarım referansları **uygulama
sahibi tarafından sağlandı** (Lexigo tasarım seti). Orijinal dosyalar repoya girmedi; uygulamada
yalnızca aşağıdaki işlenmiş kopyalar var.

| Repo dosyası | Kaynak (Lexigo seti) | İşlem |
|---|---|---|
| `assets/mascot/hello.png` | `maskot/03` (el sallayan) | Beyaz zemin şeffaf, kırpıldı, 512 px |
| `assets/mascot/cool.png` | `maskot/05` (güneş gözlüklü) | aynı |
| `assets/mascot/calm.png` | `maskot/13` (meditasyon) | aynı |
| `assets/mascot/sad.png` | `maskot/04` (üzgün) | aynı |
| `assets/mascot/dance.png` | `maskot/07` (dans eden) | aynı |
| `assets/mascot/point.png` | `maskot/08` (işaret eden) | aynı |
| `assets/mascot/face.png` | `maskot/01` (kare yüz) | Köşeler şeffaf, 256 px; marka logosu (`LingoraLogo`) |
| `assets/icon/icon.png`, `icon_foreground.png` | `maskot/01` | Launcher ikonu kaynağı (aşağıda) |
| `assets/flags/gb.png` | `bayraklar/15` (Birleşik Krallık) | 120×60 |
| `assets/brand/google_g.png` | `yuvarlak-gorseller/09` (Google "G") | Beyaz zemin şeffaf, 144 px; renk/oran değişmedi |

Kullanılmayanlar: `maskot/02` (telefon çizimi), `maskot/26` ve `27` (yalnızca giriş/şifre ekranı
tasarım referansı), `ikonlar/*` (kişiler, video, YouTube, App Store ikonları), X / GitHub / Apple
logoları (bu sağlayıcılar desteklenmiyor) ve İngilizce dışı bayraklar (İspanya, Suudi Arabistan,
Pakistan, Fransa, Hindistan). ABD bayrağı da sette var; kurs İngiliz İngilizcesi ağırlıklı olduğu
için şimdilik yalnızca Birleşik Krallık bayrağı kullanılıyor.

## Maskot: Pofu

Turuncu yastık karakter **Pofu**, Dilbaz'ın rehberi (`lib/ui/mascot.dart`). Ruh hâli (`Mood`) poz
seçer: `happy/idle → hello`, `cheer → cool` (ders sonu başarı: kusursuz ya da %90+), `calm → calm`
(seri ve mola ekranları, boş durumlar), `sad → sad`, `think → point`, `joy → dance`.
Çocuk modunda büyük ve hafif hareketli; yetişkin modunda küçük (44–72 px) ve hareketsiz. Koyu temada
Pofu krem bir daire üstünde durur, böylece koyu kolları ve bacakları kaybolmaz. Kol ile gövde
arasındaki kapalı küçük beyaz alanlar görselde kalmıştır; açık zeminde fark edilmez, koyu temada
krem daire bunları da örter.

## Uygulama ikonu

`flutter_launcher_icons` ile üretilir (`pubspec.yaml` içindeki ayarlar):

```bash
dart run flutter_launcher_icons
```

- Android adaptive icon: arka plan Pofu turuncusu `#D37209`, ön plan Pofu'nun yüzü.
- iOS: alfa kanalsız tam kare (köşeleri sistem yuvarlar).
- Web: `web/icons/*`, `favicon.png`.

Not: Araç iOS `project.pbxproj` içinde `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`
satırını bozuyor ve `Contents.json`'u küçültüyor; yeniden üretince bu iki dosyadaki değişikliği geri
alın (`git checkout`), PNG'ler aynı adlarla yerinde güncellenir.

## Google logosu

Giriş ekranındaki Google butonu, Google'ın resmî çok renkli "G" logosunu
[Google Sign-In marka kurallarına](https://developers.google.com/identity/branding-guidelines) uygun
kullanır: logo değiştirilmeden (renk, oran, döndürme yok) beyaz zemin üstünde, yeterli boşlukla
gösterilir; buton metni "Google" ve buton yalnızca Google ile giriş başlatır. Logo başka bir yerde
süsleme amacıyla kullanılmaz.
