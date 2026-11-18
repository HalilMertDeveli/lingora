# Dilmaç Gizlilik Politikası ve KVKK Aydınlatma Metni

**Yayınlanan metin artık burada değil:** [`hosting/sayfalar/gizlilik.html`](../../hosting/sayfalar/gizlilik.html)
(adres: `https://dilbaz-3392e.web.app/gizlilik`). Hesap silme sayfası:
[`hosting/sayfalar/hesap-silme.html`](../../hosting/sayfalar/hesap-silme.html)
(`https://dilbaz-3392e.web.app/hesap-silme`). Derleme ve yayın: [`hosting/README.md`](../../hosting/README.md).

İki kopya birbirinden kopmasın diye metin yalnızca HTML'de tutulur. Bu dosya, yayından önce
yapılacakları ve son sürümde nelerin değiştiğini izler.

## Yayından önce

- [x] İletişim e-postası: **dilmac.destek@gmail.com** (sayfalara yazıldı).
- [ ] Hukukçu kontrolü: özellikle yurt dışına aktarım (KVKK m. 9, standart sözleşmenin imzalanıp
      Kurum'a bildirilmesi) ve Çocuk modu / hedef kitle kararı (`docs/play-store-hazirlik.md` §3).
- [ ] `firebase deploy --project prod --only hosting:yasal`, sonra iki adresi Play Console'a gir.

## 18 Kasım 2026 sürümünde değişenler (taslağa göre)

- Veri sorumlusu: yayıncı **Dilmaç Studio**; adres alanı kaldırıldı, iletişim tek e-posta.
- Uygulama içi silme artık gerçek: **Profil > Hesap > Hesabımı sil**; ayrı hesap silme sayfası eklendi.
- Reklam yok, **reklam kimliği (AD_ID) okunmuyor** bölümü eklendi.
- **Profil fotoğrafı** (küçültülmüş JPEG, Firestore'da; arkadaşlar ve lig görür; misafirde cihazda kalır).
- Rehber: yalnızca istek üzerine, numaraların tuzlu SHA-256 özetleri; adlar ve ham numaralar gönderilmez.
- Mikrofon: konuşma tanıma cihazda; **Sesli Konuşma Koçu ve Mülakat Provası metni** (ses değil)
  sunucuya ve Anthropic'e gider; Mülakat Provası geçmişi hesap silinene kadar saklanır.
- Yazma değerlendirmesi, aile paketi ve kurum / okul lisansı (kurumun gördüğü sınırlı özet) eklendi.
- Telefon numarasıyla giriş, lig ve sıralamada ülke bilgisi eklendi.
- Saklama süreleri ve silme sonrası kalan kayıtlar (`functions/src/account.ts`) netleşti.
- Çocuklar: hedef kitle 13+, Çocuk modu ebeveyn gözetiminde.
