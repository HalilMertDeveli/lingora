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

İletişim adresi (sayfalarda doğrudan yazılı): **dilmac.destek@gmail.com**. Değişirse
`sayfalar/*.html` içinde hepsini birlikte değiştir.

## Derleme ve yayın

```bash
node hosting/build.mjs                               # build/hosting'e kopyalar ve denetler
firebase deploy --project prod --only hosting:yasal  # predeploy aynı derlemeyi çalıştırır
```

`build.mjs` sayfalarda `{{…}}` biçiminde bir yer tutucu kalırsa ya da bir iç bağlantı kırıksa durur.

`yasal` hedefi `.firebaserc`'te varsayılan siteye (`dilbaz-3392e`) bağlıdır. `firebase deploy`'u
`--only` olmadan çalıştırma: yönetim paneli hedefi (`admin`) ayrı bir siteye bağlanır
(bkz. `docs/kurumsal.md`).

CI aynı `node hosting/build.mjs` denetimini çalıştırır.

## Metni güncellerken

Yeni bir veri akışı (yeni izin, yeni hizmet sağlayıcı, sunucuya giden yeni veri) eklenince
`sayfalar/gizlilik.html`, gerekirse `sayfalar/hesap-silme.html` ve `docs/magaza/veri-guvenligi.md`
birlikte güncellenir; "Son güncelleme" tarihini değiştir. Hesap silme kapsamı `functions/src/account.ts`
ile aynı kalmalıdır.
