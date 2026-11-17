# Arkadaşlar: kod, istek, rehberden bulma

Arkadaşlık ve ortak seri Cloud Functions olmadan, yalnızca istemci ve `firestore.rules` ile çalışır (Spark planı).
Genel tasarım (ortak seri, gün hesabı, destek mesajları): `docs/firebase-backend.md` > "Arkadaşlar ve ortak seri".
Bu belge iki yolu, rehberden bulmayı ve sınırlarını anlatır.

Kod: `lib/services/friends.dart`, `lib/services/contacts/` (numara, hash, rehber), ekranlar
`lib/screens/friends_screen.dart` ve `lib/screens/contacts_friends_screen.dart`.

## İki yol

| Yol | Rıza | Sonuç |
| --- | --- | --- |
| **Kodla ekle** | Kodun sahibi kodunu kendisi paylaşmıştır. Kodu bilmek rıza sayılır. | Hemen arkadaş olunur (`friendships/{a}_{b}`, `code` = kod). |
| **Rehberden istek** | Numara kullanıcının kendi paylaşımı değildir; numarası rehberde olan herkes onu bulabilir. | `friendRequests/{gönderen}_{alıcı}` açılır. Alıcı kabul edince arkadaş olunur (`code` = `''`), reddederse istek silinir. |

**Neden kodla ekleme doğrudan kaldı:** Kod, sahibinin bilerek verdiği bir davettir; ikinci bir onay adımı
eklemek mevcut akışı (ve Lig > Arkadaşlar'daki "kodumu yaz" paylaşım metinlerini) uzatır, yeni bir güvence
getirmez. Numara ise rehberde kayıtlı olmak gibi kişinin kontrolü dışındaki bir yolla bilinir; bu yüzden orada
karşı tarafın açık onayı (istek → kabul) gerekir. Kodla eklenince aradaki bekleyen istekler silinir. İki taraf
birbirine istek atarsa ikincisi doğrudan kabul sayılır.

**Ortak seri başlat:** Kabul edince (ya da karşı tarafın isteği zaten varken istek atınca) bir pencere çıkar.
"Ortak seri başlat" arkadaşa "⏰ Hadi, bugün sen de!" gönderir. Seri, kodla eklenen arkadaşlıktaki gibi, ikisi
de aynı gün hedefini tamamlayınca 1 olur.

## Rehberden bulma (KVKK, gizlilik öncelikli)

1. **İzin ancak düğmeyle.** Arkadaşlar > **Rehberden bul** ekranı önce ne yapılacağını anlatır; Android
   `READ_CONTACTS` (iOS `NSContactsUsageDescription`) izni yalnızca o ekrandaki düğmeye basınca istenir.
   Reddedilirse kod yöntemi çalışmaya devam eder; kalıcı redde "Ayarlardan izin ver" çıkar.
2. **Rehber telefonda kalır.** Numaralar telefonda E.164'e çevrilir (`normalizePhone`, ülke kodu yoksa +90;
   `0532…`, `532…`, `90 532…`, `0090…`, dahili numaralar). Her numara için
   `sha256('dilmac-rehber-v1:' + E.164)` (küçük harf hex) hesaplanır. Sunucuya yalnızca bu özetler, tek tek
   `get` olarak gider (en fazla 500 farklı numara, 20'şer paralel). Adlar ve ham numaralar hiçbir yere yazılmaz.
   Eşleşen kişi ekranda rehberdeki adıyla görünür.
3. **Bulunabilirlik isteğe bağlı, varsayılan kapalı.** Profil (ve Rehberden bul ekranı) > "Telefon numaramla
   bulunabilirim". Açılınca `phoneIndex/{hash}` → `{uid, createdAt}` yazılır; kapatınca silinir. Yalnızca telefonla
   girişte doğrulanmış numara yayınlanabilir: kural, belge kimliğini Auth jetonundaki `phone_number`'dan kendisi
   hesaplar (`hashing.sha256`), yani başkasının numarası ya da doğrulanmamış bir numara yazılamaz. Google/e-posta
   hesabında numara yoksa seçenek kilitli görünür.
4. **Davet.** Rehberde olup bulunamayanlara "Davet et" paylaşım metni gider: davet (referral) kodu Cloud Functions
   cevap verirse onunla, vermezse Play bağlantısı ve kullanıcının arkadaş koduyla.

## Kurallar (özet)

- `phoneIndex/{hash}`: `get` hesabı olan herkese açık, **`list` yasak**. `create/update` yalnızca
  `hash == sha256(tuz + token.phone_number)` ve `uid == auth.uid` ise (update: numaranın yeni sahibi eski kaydı
  devralır). `delete`: kaydın sahibi ya da numaranın doğrulanmış sahibi.
- `friendRequests/{from}_{to}`: yalnızca iki taraf okur (sorgular `from == ben` ya da `to == ben` süzmeli),
  gönderen kendi adına ve yalnızca arkadaş olmadığı birine yazar, değiştirilemez, iki taraf da siler.
- `friendships` oluşturma: `code != ''` ise koda bakılır (eskisi gibi); `code == ''` ise
  `friendRequests/{arkadaş}_{ben}` var olmalı ve arkadaşın adı/simgesi istektekiyle aynı olmalı. Kabul eden
  uygulama arkadaşlığı yazıp isteği aynı toplu yazmada (batch) siler.
- Testler: `functions/test/friends_rules.test.ts` (kurallar), `test/contacts_friends_test.dart` (birim/widget),
  `integration_test/friends_flow_test.dart` (iki gerçek hesap, emülatörler).

**Deploy:** Kurallar değişti; gerçek projeye (`dilbaz-3392e`) deploy edilmeden rehber ve istek akışı canlıda
çalışmaz (izin hatası verir, uygulama "bağlanılamadı" der). Deploy sahibin onayıyla:
`firebase deploy --only firestore:rules --project dilbaz-3392e`.

## Sınırlar ve riskler

- **Numara özeti gizli değildir.** Türkiye'de cep numarası uzayı küçüktür (~10⁹); tuz uygulamanın içinde
  durduğundan özetler kaba kuvvetle çözülebilir. Bu yüzden asıl koruma özetin gizliliği değil, **dizinin
  listelenememesi**dir: biri tek tek `get` ile numara deneyebilir ama hangi numaraların kayıtlı olduğunu toplu
  göremez. Numarası bilinen birinin Dilmaç kullanıp kullanmadığı (ve uid'i) öğrenilebilir; bunu yalnızca
  seçeneği açanlar kabul eder ve ekranda açıkça yazılır.
- **Toplu deneme (enumeration) maliyeti.** Kural tarafında hız sınırı yoktur (Cloud Functions yok). Hesabı olan
  biri döngüyle çok sayıda `get` yapabilir. Spark'ta günlük 50.000 okuma kotası vardır; kötüye kullanım kotayı
  bitirip herkes için okumaları durdurabilir. Öneriler: Firebase **App Check** (Play Integrity) zorunlu kılınsın;
  Blaze'e geçilirse aramalar sayaçlı bir callable'a taşınsın. Uygulama tek aramada 500 numarayla sınırlıdır.
- **uid sızıntısı.** Eşleşme uid'i verir; uid tek başına ad, e-posta ya da numara açmaz (profiles yalnızca
  arkadaşlara açık). İstek atmak için uid gerekir; istekler kişi başına tektir (belge kimliği `from_to`).
- **İstek spam'i.** Bir kullanıcı uid'ini bildiği herkese bir kez istek atabilir; reddedilen tekrar atabilir.
  Engelleme listesi yok (gerekirse `blocks/{uid}` eklenebilir).
- **Bayat kayıt.** Hesap silinir ya da telefon bağlantısı kaldırılırsa `phoneIndex` kaydı kalabilir. Numaranın
  yeni sahibi SMS ile doğruladığında kaydı devralır ya da siler. Hesap silme özelliği eklenince kaydı da silmeli.
- **Numara değişikliği.** Uygulama yalnızca güncel (jetondaki) numaranın kaydını açar ve siler. Eski numaranın
  kaydı kalır; kuralda kaydın sahibi (`uid`) onu silebilir, ama bunun için henüz bir ekran yok. Numaranın yeni
  sahibi kaydı devralır.
- **Rehber verisi.** Ekran rehberi bellekte tutar, diske yazmaz. Analitik olaylarına rehber bilgisi girmez.
- **Çocuk modu.** Arkadaşlar ekranı ve bulunabilirlik seçeneği Çocuk modunda kapalıdır.

## Arkadaşın adı

- Ekranlar arkadaşın adını canlı olarak `profiles/{uid}.name`'den okur (kart, ortak seri metinleri, destek mesajları,
  arkadaş profili, çıkarma onayı). Arkadaşlık belgesindeki `names` yalnızca profil yokken ya da yüklenirken yedektir.
  Bekleyen istekte gönderen henüz arkadaş olmadığı için profili okunamaz; istekteki ad gösterilir.
- Kullanıcı Profil'de adını değiştirince `friendNameSyncProvider` arkadaş kodunu ve üyesi olduğu her arkadaşlıktaki
  `names.{uid}` alanını günceller (kurallar yalnızca kendi girdisine izin verir; kural değişikliği gerekmedi).
- Ad hâlâ varsayılansa ("Dilmaç öğrencisi") kod oluşturmadan, kodla eklemeden, istek göndermeden, istek kabul
  etmeden ve davet paylaşmadan önce "Arkadaşların seni hangi adla görsün?" diye sorulur; ad Profil adına kaydedilir.
