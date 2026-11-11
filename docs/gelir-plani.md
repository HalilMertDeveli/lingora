# Dilbaz gelir ve geliştirme planı

Bu belge, uygulamanın nasıl para kazanacağını ve bunun için hangi geliştirmelerin hangi sırayla
yapılacağını tanımlar. İlke: **öğrenmenin çekirdeği ücretsiz kalır**; can sistemi, ceza ya da reklam
yoktur. Para, gerçek maliyeti olan ya da ileri seviye değer üreten şeylerden kazanılır.

## Gelir kalemleri

| # | Kalem | Kime | Model | Neden işe yarar |
|---|---|---|---|---|
| 1 | **Dilbaz Premium** | Bireysel | Aylık / yıllık abonelik | AI konuşma partneri, bulut yedekleme ve cihazlar arası senkron, sınırsız deneme, ayrıntılı hata analizi |
| 2 | **Aile planı** | Aileler | Yıllık, 5 kişiye kadar | Özellikle LGS çocuğu olan aileler; tek ödeme, çok hesap |
| 3 | **Sınav paketleri** | YDS/YÖKDİL ve LGS adayları | Tek seferlik satın alma | Tam deneme setleri, ayrıntılı çözümler. Sınav dönemlerinde satış patlaması yapar, abonelik istemeyen kullanıcıyı da kazanır |
| 4 | **Kurumsal (otel, turizm, şirket)** | İşletmeler | Kişi başı yıllık lisans | Personel eğitimi için ödeme yapan kurum, bireysel abonelikten çok daha büyük ve düzenli gelir getirir |
| 5 | **Okul ve öğretmen** | Okullar, dershaneler | Sınıf başı lisans | Öğretmen paneli: sınıf, ödev, ilerleme takibi; öğrenciler ücretsiz ya da indirimli Premium |
| 6 | **Davet programı** | Tüm kullanıcılar | Ücretsiz Premium günleri | Büyüme kanalı: davet eden ve gelen 7'şer gün Premium kazanır |

Reklam kullanılmaz: uygulamanın "sakin, premium" hissini bozar ve Türkiye'de reklam geliri düşüktür.

## Fiyat önerisi (başlangıç)

- Premium: aylık 79,99 TL, yıllık 599,99 TL (aylık ~50 TL); 7 gün ücretsiz deneme.
- Aile: yıllık 899,99 TL.
- Sınav paketi: 149,99 TL (YDS/YÖKDİL tam set), 99,99 TL (LGS tam set).
- Kurumsal: kişi başı yıllık 300–600 TL (adet indirimi), 10 kişilik deneme.
- Fiyatlar Firebase Remote Config ile değiştirilebilir ve A/B test edilir.

## Geliştirme aşamaları

### Aşama 1: Bireysel gelir (şimdi)
- Bulut yedekleme ve senkronu Premium'a bağla (ücretsiz kullanıcı cihazda devam eder; giriş ve lig ücretsiz).
- Sınav paketleri: tek seferlik ürünler, tam deneme setleri, satın alma ve kilit açma.
- Aile planı: üyelik daveti ve paylaşılan hak.
- Ölçüm: Firebase Analytics olayları (paywall görüldü, deneme başladı, satın alma), Remote Config ile fiyat/paywall deneyleri.
- Davet programı: davet kodu, iki tarafa Premium günü.
- Mağaza: Türkçe mağaza metinleri ve ekran görüntüsü planı.

### Aşama 2: Kurumsal ve okul (ardından)
- Kurum hesabı, koltuk (lisans) sayısı, kurum kodu ile katılım.
- Web yönetim paneli (Firebase Hosting): personel/öğrenci listesi, ilerleme, rapor indirme.
- Öğretmen modu: sınıf, ödev (ders/gramer konusu/deneme), teslim takibi.
- Faturalama: kurumsal satışlar mağaza dışından (havale/fatura); hak, kurum kodu ile verilir.

### Aşama 3: Ölçek
- iOS sürümü ve App Store aboneliği.
- Gerçek mağaza doğrulaması (Play Developer API servis hesabı) ve abonelik yenileme olayları.
- Satış sayfası (web) ve kurumsal demo talep formu.

## Sahibin yapması gerekenler

1. Google Play geliştirici hesabı ve ürünlerin Play Console'da tanımlanması.
2. Firebase projesi (`firebase login`, `flutterfire configure`), Blaze planı ve Anthropic API anahtarı secret'ı.
3. Kurumsal satış için şirket/fatura bilgileri.

## Başarı ölçütleri

- Ücretsiz → deneme oranı, deneme → ücretli dönüşüm (hedef %4–6), 30. gün tutma.
- Sınav dönemlerinde paket satışları.
- Kurumsal: ilk 3 otel/okul pilotu.
