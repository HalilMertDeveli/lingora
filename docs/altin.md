# Altın ve Mağaza

Altın, Dilmaç'ın oyun içi para birimidir. **Yalnızca çalışarak kazanılır, gerçek
parayla satılmaz.** Gelirin ana kaynağı abonelik; Altın ve Mağaza bir motivasyon
aracıdır. Can/kalp sistemi ve reklam yoktur.

## Kazanma

| Olay | Altın | Nerede |
| --- | --- | --- |
| Ders bitirmek (cevaplı her ders) | 5 | `ProgressNotifier.completeNode` |
| Hatasız ders | +3 | aynı |
| Günlük XP hedefine ilk ulaşma (günde bir) | 10 | aynı, `goal:<gün>` |
| Seri kilometre taşı: 3, 7, 14, 30, 60, 100, 200, 365 gün | 15 … 1000 | aynı, `streak:<gün>:<başlangıç>` |
| Günlük görev ödülü | görevin XP'si kadar (5–15) | `claimQuest` |
| Haftalık lig sonucu (o hafta XP varsa) | yükselme 60, kalma 30, düşme 15; ilk 3'e +20 | `settleLeague`, Dünya Ligi için `HomeScreen` |

Hedef: günde 3 ders yapan biri haftada ~370 altın kazanır; ortanca ürün fiyatı
~250, yani haftada 1–2 ürün (`test/altin_test.dart`, "a normal week").

Ders sonu ekranında "+N altın" animasyonu (`GoldGain`) ve dökümü gösterilir.

### Başka özellikler için API

```dart
ref.read(goldWalletProvider).earn(20, GoldReason.rewardedAd, onceKey: 'ad:2026-11-17:1');
```

`onceKey` verilirse ödül en fazla bir kez verilir (anahtarlar 60 gün saklanır).

## Harcama (Mağaza)

`lib/screens/shop_screen.dart`, girişler: üst bardaki altın bakiyesi (her sekme)
ve Profil'deki "Mağaza" kartı. Kategoriler: avatarlar, çerçeveler, Çaycı Dayı
aksesuarları, temalar (ana renk), seri dondurma.

- Alınan ürün hemen kuşanılır; "Kullan" ile değiştirilir, "Çıkar" ile varsayılana dönülür.
- **Seri dondurma** sarf malzemesidir (en fazla 2 stok). Kaçırılan her gün için
  bir tane harcanır; çalışma planının haftalık otomatik dondurması önce kullanılır
  (`Progress.streakCover`). Harcama bir sonraki derste yapılır.

## Senkron

Cüzdan `Progress.wallet` içindedir: hesabı olanlarda mevcut ilerleme senkronuyla
`users/{uid}.progress.wallet`'a gider, misafirde cihazda kalır.

Bakiye cihaz başına yalnızca artan sayaçlardır (G-counter): `earned[cihaz]`,
`spent[cihaz]`. Birleştirme cihaz başına en büyüğü alır, sahip olunan ürünler
birleşir, kuşanılanlar ve vitrin son değişen kopyadan gelir (`mergeWallets`).
Böylece iki telefon senkronlanınca altın ne kaybolur ne iki kez sayılır. İki
telefon aynı anda çevrimdışı harcarsa bakiye geçici olarak 0 görünür ve yeni
kazançla kapanır.

## Arkadaş vitrini

Kuşanılan avatar ve çerçeve ile seçilen en fazla 3 ürün
`profiles/{uid}.showcase = {avatar, frame, items}` alanına yazılır
(`lib/services/showcase.dart`, yalnızca hesabı olanlar). Görünür: arkadaş
listesi, arkadaş profili (karta dokun) ve lig satırı (kendin ve arkadaşların).

`firestore.rules`: yalnızca sahibi yazar, yalnızca arkadaşlar okur; şekil
doğrulanır (ürün kimliği kalıbı, avatar `av_`, çerçeve `fr_`, en fazla 3 ürün).
Cloud Functions olmadığı için ürünün gerçekten alındığı sunucuda doğrulanamaz;
en kötü durumda biri sahip olmadığı bir ürünü yalnızca arkadaşlarına gösterebilir.
Testler: `functions/test/profile_rules.test.ts`.
