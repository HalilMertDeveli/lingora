# Varlıklar (görsel kaynakları ve lisanslar)

Uygulamaya giren her görselin kaynağı ve lisansı burada. Başka bir uygulamanın
görseli, adı ya da kodu kullanılmaz. Ayrıntılı maskot ve bayrak notları için
`docs/assets.md`'ye bakın.

## Altın (oyun içi para birimi)

| Dosya | Kaynak | Lisans |
| --- | --- | --- |
| `assets/gold/altin.svg` | Çenebaz için elle çizildi (2026-11-17): altın para, yüzünde kabartma ince belli çay bardağı. | Projenin kendi çizimi; atıf gerekmez, ticari kullanım serbest. |

Arama notu: OpenGameArt'ta CC0 lisanslı altın para ikonları var (ör.
"Gold Coin/Token", BizmasterStudios, CC0,
https://opengameart.org/content/gold-cointoken). Bunlar 16–32 px piksel sanatı
olduğu için uygulamanın sakin vektör stiline uymadı; indirilmedi ve
kullanılmadı. Bunun yerine yukarıdaki özgün SVG çizildi.

Kod içinde `GoldCoin` (`lib/ui/gold_coin.dart`) bu SVG'yi `flutter_svg` ile
gösterir.

## Mağaza ürünleri

Mağazadaki bütün ürünler özgündür (`lib/data/shop_catalog.dart`):

- **Avatarlar:** sistem emojileri (🦊, 🦉, 🌷, 🧿 …) yuvarlak bir zemin üstünde.
  Emoji telefonun kendi yazı tipiyle çizilir; dosya olarak dağıtılmaz.
- **Çerçeveler:** kodda çizilen renk halkaları (`FramedAvatar`, SweepGradient).
- **Animasyonlu çerçeveler:** kodda çizilen dönen / parlayan halkalar.
- **Pofuduk kıyafetleri (Çocuk modu):** Pofuduk görselinin (sahibin çizimi) üstüne konan emoji (🎩, 🎀, 🧢, 🌼, 👑).
- **Çaycı Dayı aksesuarları:** mevcut maskot görseli (`assets/mascot/cayci_dayi.png`,
  sahibin kendi çizimi) üstüne konan emoji (🕶️, 🧣, 🏅, 🌷, 👑).
- **Temalar:** uygulamanın ana rengini değiştiren renk çiftleri (açık/koyu).
- **Seri dondurma:** 🧊 emojisi.
