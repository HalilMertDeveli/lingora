# Zorunlu ve önerilen güncelleme

Eski bir sürümü kapatmak (ör. ciddi bir hata, değişen sunucu sözleşmesi) ya da
kullanıcıları yeni sürüme nazikçe yönlendirmek için uygulama yeniden
yayımlanmadan kullanılabilir. Ayar Firestore'daki tek bir belgededir.

## Belge: `config/app`

| Alan | Tür | Anlamı |
| --- | --- | --- |
| `minVersionCode` | sayı | Bu sürüm kodunun **altındaki** uygulamalar kapanmayan "Lütfen güncelle" ekranı gösterir. Tek düğme Google Play sayfasını açar. |
| `recommendedVersionCode` | sayı | Bu kodun altındakiler (ama en düşüğün üstündekiler) üstte kapatılabilir bir "Yeni sürüm hazır" şeridi görür. Kullanıcı kapatırsa aynı öneri bir daha gösterilmez; daha yüksek bir öneri yazıldığında yeniden çıkar. |
| `message` | metin | Engelleme ekranındaki açıklama (Türkçe). Boş bırakılırsa hazır metin kullanılır: "Çenebaz'ın bu sürümü artık desteklenmiyor…" |

**Sürüm kodu** `pubspec.yaml` içindeki `version: 0.1.0+N` satırındaki `N`'dir
(Play Console > Uygulama paketleri'nde "Sürüm kodu" olarak da görünür).
Sürüm adı (`0.1.0`) değil, kod (`N`) yazılır.

Örnek:

```json
{
  "minVersionCode": 12,
  "recommendedVersionCode": 15,
  "message": "Bu sürümde ders kaydı bozuluyordu. Lütfen güncelle, ilerlemen kaybolmaz."
}
```

## En düşük sürümü yükseltme (adım adım)

1. Yeni sürümü Play'de **yayımla ve tam dağıtıma aç** (kademeli dağıtım %100
   olmadan zorunlu yapma: henüz güncellemeyi göremeyen kullanıcı kilitli kalır).
   Play'in sürümü kullanıcılara ulaştırması birkaç saat sürebilir.
2. Firebase Console > Firestore Database > `config` koleksiyonu > `app`
   belgesi. Belge yoksa "Belge ekle" ile kimliği `app` olarak oluştur.
3. Önce `recommendedVersionCode`'u yeni sürüm koduna yükselt (birkaç gün
   şerit görünür, çoğu kullanıcı kendiliğinden günceller).
4. Gerçekten gerekiyorsa `minVersionCode`'u yükselt ve `message`'ı yaz.
   Alan **sayı** (number) türünde olmalı; metin olarak yazılan değer
   (`"12"`) yok sayılır ve kimseyi kilitlemez.
5. Geri almak için `minVersionCode`'u `0` yap ya da alanı sil.

## Uygulama ne zaman kontrol eder?

- Açılışta (Firebase hazır olur olmaz) ve uygulama arka plandan döndüğünde,
  en fazla **6 saatte bir**. Yani değişiklik açık uygulamalara birkaç saat
  içinde, yeni açılışlara hemen ulaşır.
- Belge yalnızca **sunucudan** okunur (önbellekten değil), 8 saniyede yanıt
  gelmezse vazgeçilir.
- **İnternet yoksa, belge yoksa, alanlar bozuksa ya da sürüm kodu
  okunamıyorsa uygulama asla engellenmez.** Bir oturumda sunucu "güncelle"
  dedikten sonra bağlantı koparsa son cevap geçerli kalır.
- Firebase'siz yerel derlemeler ve testler hiç kontrol etmez.

## Güvenlik

`firestore.rules`: `config/app` herkes tarafından okunabilir (giriş yapmadan
da), hiçbir istemci yazamaz; yalnızca Firebase Console'dan (ya da Admin SDK
ile) değiştirilir. `config/` altındaki diğer belgeler (`lingoraAdmins`)
istemcilere kapalıdır. Testler: `functions/test/stats_rules.test.ts`.

## Kod

| Dosya | Görev |
| --- | --- |
| `lib/core/app_update.dart` | Belgeyi okuma, karşılaştırma, `UpdateGate`, engelleme ekranı, şerit |
| `lib/main.dart` | `MaterialApp.builder` içinde `UpdateGate` (tüm sayfaları kapsar) |
| `test/app_update_test.dart` | Kurallar, çevrimdışı/bozuk belge, şeridin hatırlanması, 6 saatlik sınır |

## Play uygulama içi güncelleme (isteğe bağlı, şimdilik yok)

Google Play'in "In-app updates" API'si (`in_app_update` paketi) güncellemeyi
uygulamadan çıkmadan indirebilir. Şimdilik eklenmedi: yalnızca Play'den
kurulan sürümlerde çalışır, test etmek için iç test kanalı gerekir ve mevcut
düğme zaten Play sayfasını açıyor. Eklenirse `openPlayStore` önce
`performImmediateUpdate` denemeli, olmazsa bugünkü bağlantıya düşmelidir.
