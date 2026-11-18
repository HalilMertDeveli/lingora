# Yasal sayfalar (Firebase Hosting)

Google Play için herkese açık gizlilik politikası ve hesap silme sayfaları.
Varsayılan Firebase Hosting sitesinde (`dilbaz-3392e.web.app`) yayınlanır:

| Adres | Kaynak |
| --- | --- |
| `https://dilbaz-3392e.web.app/` | `sayfalar/index.html` |
| `https://dilbaz-3392e.web.app/gizlilik` | `sayfalar/gizlilik.html` |
| `https://dilbaz-3392e.web.app/hesap-silme` | `sayfalar/hesap-silme.html` |

Uygulama bu adreslere `lib/core/legal_links.dart` üzerinden bağlanır.
Play Console'a girilecekler: gizlilik politikası URL'si `…/gizlilik`, hesap silme URL'si `…/hesap-silme`.

## İletişim e-postası (tek yer tutucu)

Sayfalardaki tek değişken iletişim adresidir. HTML'de `{{ILETISIM_EPOSTA}}` olarak geçer; değeri
**tek bir yerden** gelir:

1. `ILETISIM_EPOSTA` ortam değişkeni (doluysa öncelikli), yoksa
2. `hosting/site.json` içindeki `iletisimEposta`.

`build.mjs` değer hâlâ `{{ILETISIM_EPOSTA}}` ise **derlemeyi durdurur**; böylece yer tutucu yanlışlıkla
yayınlanmaz. Kişisel bir adres yerine yayına uygun bir destek adresi kullan.

## Derleme ve yayın

```bash
ILETISIM_EPOSTA=destek@ornek.com node hosting/build.mjs   # build/hosting'e yazar
firebase deploy --project prod --only hosting:yasal       # predeploy aynı derlemeyi çalıştırır
```

PowerShell'de: `$env:ILETISIM_EPOSTA='destek@ornek.com'; firebase deploy --project prod --only hosting:yasal`.

`yasal` hedefi `.firebaserc`'te varsayılan siteye (`dilbaz-3392e`) bağlıdır. `firebase deploy`'u
`--only` olmadan çalıştırma: yönetim paneli hedefi (`admin`) ayrı bir siteye bağlanır
(bkz. `docs/kurumsal.md`).

CI, sayfaların derlendiğini ve iç bağlantıların çalıştığını `node hosting/build.mjs --allow-placeholder`
ile denetler (yer tutucuyu olduğu gibi bırakır).

## Metni güncellerken

Yeni bir veri akışı (yeni izin, yeni hizmet sağlayıcı, sunucuya giden yeni veri) eklenince
`sayfalar/gizlilik.html`, gerekirse `sayfalar/hesap-silme.html` ve `docs/magaza/veri-guvenligi.md`
birlikte güncellenir; "Son güncelleme" tarihini değiştir. Hesap silme kapsamı `functions/src/account.ts`
ile aynı kalmalıdır.
