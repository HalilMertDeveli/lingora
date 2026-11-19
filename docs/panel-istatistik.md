# Satış ve kullanım paneli

Yönetim panelinde (Flutter web, `lib/admin/`) Çenebaz ekibi hesabıyla
giriş yapınca **Kurumlar** sayfasının üstünde **Panel** düğmesi çıkar.
Panel günlük ve haftalık sayıları gösterir. Yalnızca Çenebaz ekibi
(`config/lingoraAdmins.uids` listesindekiler ya da `isLingoraAdmin` claim'i
olanlar) görebilir; kurum yöneticileri ve öğretmenler göremez.

## Neden ayrı sayaçlar?

Firebase Analytics (GA4) verisi panelden doğrudan sorgulanamaz (BigQuery
dışa aktarımı ve ek yetki gerekir). Bu yüzden sunucu, gün başına yalnızca
**toplam sayıları** tutar. Kimin ne yaptığı saklanmaz: kullanıcı kimliği,
cihaz kimliği, e-posta, ürün ya da tutar yoktur.

```
stats/daily/days/{yyyy-mm-dd}   (Türkiye günü)
  first_open, first_lesson, paywall_view, purchase_start,
  return_d1, return_d7, purchase_verified, premium_active, updatedAt
```

İstemciler `stats/` altını okuyamaz ve yazamaz (`firestore.rules`, testi
`functions/test/stats_rules.test.ts`). Panel veriyi `getStats` callable'ı ile
alır.

## Sütunlar ve kaynakları

| Panel sütunu | Sayaç | Nereden | Kimleri kapsar |
| --- | --- | --- | --- |
| Kurulum (ilk açılış) | `first_open` | Uygulama, kurulumdan sonraki ilk açılışta | Analiz izni verenler |
| İlk ders bitti | `first_lesson` | Uygulama, ilk ders bitince | Analiz izni verenler |
| Paywall görüldü | `paywall_view` | Uygulama, `paywall_view` olayı gönderilince (cihaz başına günde 1) | Analiz izni verenler |
| Satın alma başladı | `purchase_start` | Uygulama, satın al düğmesi (cihaz başına günde 1) | Analiz izni verenler |
| Satın alma doğrulandı | `purchase_verified` | Sunucu: `verifyPurchase` / Play bildirimi bir satın alımı **ilk kez** onayladığında (abonelik, aile, sınav paketi; yenilemeler sayılmaz) | Herkes |
| Aktif Premium | `premium_active` | Sunucu: her gün 23:50'de `snapshotStats`; üstteki kutu canlı sayımdır | Herkes (ücretli, aile, davet, kurum) |
| D1 / D7 | `return_d1`, `return_d7` | Uygulama, kurulumdan 1 ve 7 gün sonra açılınca | Analiz izni verenler |

- **D1 (yaklaşık):** X günü kurulanlardan X+1 günü açanların oranı
  = `return_d1(X+1) / first_open(X)`. **D7:** `return_d7(X+7) / first_open(X)`.
  "Yaklaşık" çünkü kurulum günü cihaz saatine göre, sayım günü Türkiye saatine
  göredir ve izin sonradan verilirse ilk açılış o güne yazılır.
- Haftalık satırlar bugünle biten 7'şer günlük bloklardır.
- Uygulama sayaçları **analiz izni** ile çalışır (Firebase Analytics gibi).
  İzin oranı düşükse mutlak sayılar küçük çıkar; oranlar (ilk ders / kurulum,
  satın alma başladı / paywall, D1, D7) yine anlamlıdır. Gerçek kurulum sayısı
  için Play Console > İstatistikler'e bak.
- Bu özellikten önce kurulmuş uygulamalar (güncellemeyle gelenler) yeni
  kurulum sayılmaz ve D1/D7'ye girmez.
- Bir sayaç gönderilemezse (çevrimdışı) sonraki açılışta bir kez daha denenir;
  kayıp olabilir, çift sayım neredeyse olmaz.

## Kod

| Dosya | Görev |
| --- | --- |
| `functions/src/stats.ts`, `stats_api.ts` | `countFunnel`, `getStats`, `snapshotStats` (her gün 23:50), sayaç yardımcıları |
| `functions/src/purchase.ts` | `purchase_verified` (satın alma belgesinde `statsCounted` ile bir kez) |
| `lib/services/growth/funnel_stats.dart` | Uygulama tarafı: kurulum günü (yalnızca cihazda), tek seferlik gönderim, izin kontrolü |
| `lib/admin/stats_panel.dart` | Panel sayfası, günlük/haftalık ve D1/D7 hesabı |
| `firestore.indexes.json` | `entitlements (active, expiresAt)` bileşik dizini (aktif Premium sayımı) |

Yayına alırken: `firebase deploy --only functions,firestore:rules,firestore:indexes`.
Dizin oluşana kadar (birkaç dakika) aktif Premium sayımı hata verebilir.

## Firebase / GA4 hunisi (ayrıntılı analiz için)

Panel hızlı bakış içindir. Kırılımlar (paywall yerleşimi, A/B varyantı, kurs
yolu) için Firebase Console > Analytics kullanılır. Olayların tam listesi:
`docs/analitik.md`.

**Huni (Funnel) raporu:** Firebase Console > Analytics > *Google Analytics'te
görüntüle* > Keşfet (Explore) > **Huni keşfi** (Funnel exploration).

1. Adımları sırayla ekle:
   1. `first_open` (otomatik olay)
   2. `onboarding_complete`
   3. `lesson_finish`
   4. `paywall_view`
   5. `purchase_start`
   6. `trial_start` **veya** `purchase` (adımda "veya" koşulu)
2. "Açık huni" kapalı (kullanıcı ilk adımdan başlamalı), süre: 7 gün içinde.
3. Kırılım (Breakdown): `placement` olay parametresi (paywall'ın nerede
   açıldığı) ya da `paywall_variant` kullanıcı özelliği (A/B).
   Özel boyut olarak önce kaydet: Yönetici > Özel tanımlar > `placement`,
   `variant`, `plan` (olay kapsamı) ve `paywall_variant`, `premium`, `track`
   (kullanıcı kapsamı).
4. Tarih aralığını seç, "Kaydet" ile keşfi sakla.

**Tutma (D1/D7):** Analytics > Kullanıcı tutma (Retention) raporu; ya da
Keşfet > **Kohort keşfi**: kohort `first_open`, dönüş `user_engagement`,
günlük ayrıntı. Panelin D1/D7'si bununla aynı yönde ama birebir aynı olmayabilir.

**Gelir:** Play Console > Gelir raporları ve Abonelikler (deneme → ücretli
dönüşüm, iptal nedenleri). Firebase'in Play bağlantısı açıksa
`in_app_purchase` olayı Analytics'te de görünür. Uygulama tutar göndermez.

**Uyarı:** GA4 verisi 24–48 saat gecikmeli olabilir ve yalnızca analiz izni
verenleri içerir; panel ile Play Console sayıları arasındaki fark normaldir.
