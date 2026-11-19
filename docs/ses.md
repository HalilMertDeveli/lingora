# Seslendirme

Ders cümleleri üç kaynaktan okunur, bu sırayla:

1. **Uygulamadaki stüdyo kaydı** (`assets/voice/`, ~10 MB): ElevenLabs'in hazır sesleriyle üretilmiş MP3'lerin küçük çekirdeği (kurs sırasıyla ilk 10 MB; şu an Bölüm 1'in tamamı). Kalan kayıtlar da aynı seslerle üretildi ama Firebase Storage'dan indirilir (aşağıda **Ses paketleri**).
   - Matilda (kadın, Amerikan) varsayılan ses. Üç kelimeden uzun cümlelerin yaklaşık dörtte biri Eric (erkek, Amerikan).
   - Hikâyelerde kadın karakterler Matilda, erkek karakterler Eric.
   - Dosya adı, cümlenin `voiceKey` değeri (`lib/core/voice_key.dart`); `index.json` hangi cümlelerin kayıtlı olduğunu tutar.
2. **İndirilen stüdyo kaydı**: Wi-Fi'de arka planda inen kayıtlar (uygulama deposunda).
3. **Telefonun ses motoru**: Kaydı olmayan ya da henüz inmemiş her cümle, önceki gibi cihazın metin okuma motoruyla okunur (`lib/services/speech.dart`).

## Ses ayarları

Model `eleven_multilingual_v2`, çıktı `mp3_44100_64`. Daha canlı ve anlaşılır okuma için:
stability 0.3, similarity_boost 0.8, style 0.5, use_speaker_boost açık (`voiceSettings`, `tool/voice_elevenlabs.dart`).

## Kayıt üretmek

```bash
dart run tool/voice_elevenlabs.dart --all --dry --budget 50000   # kaç karakter gerekiyor, bütçe nereye kadar yeter
dart run tool/voice_elevenlabs.dart --all --budget 50000 --keep 20000 --max-mb 10 --overflow D:/DilmacSes/voice
dart run tool/voice_elevenlabs.dart --regen --budget 20000       # assets/voice'taki kayıtları baştan üretir
```

- `--budget N`: bu çalıştırmada en çok N karakter harcanır (metin uzunluğuyla sayılır; hesaptaki sayaç bundan az ya da geç düşebilir).
- `--keep N`: hesapta en az N karakter bırakılır (`/v1/user/subscription` ile başta kontrol edilir).
- `--max-mb M --overflow DİZİN`: `assets/voice` M MB'a ulaşınca yeni kayıtlar depo dışındaki DİZİN'e, kendi `index.json`'ıyla yazılır (APK boyutu için).
- `--regen`: `assets/voice/index.json`'daki kayıtları yeniden üretir; ilerleme `.dart_tool/voice_regen_done.txt`'de tutulur, yarıda kalırsa kaldığı yerden sürer.
- Kayıtlı cümleler (`assets/voice`, `voice/` ve taşma dizinindeki `index.json`) atlanır; sıra kurs sırasıdır.
- Yeni kayıtlar indirilecek seslere girer: ardından **Ses paketleri → Kayıt ekleyince** adımlarını uygula.

API anahtarı `ELEVENLABS_API_KEY` ortam değişkeninden ya da `%USERPROFILE%\.dilbaz\elevenlabs_key.txt` dosyasından okunur. Anahtar depoya girmez, ekrana yazılmaz.

## Durum ve lisans

- **18 Kasım 2026: tüm kayıtlar ücretli Creator planıyla üretildi; ticari kullanım lisanslıdır.** 16 Kasım'da ücretsiz planla yapılan 603 kayıt aynı seslerle (Matilda, Eric) ve yeni ayarlarla baştan üretildi; ücretsiz plandan kalan dosya yok.
- `assets/voice/`: 839 dosya, 10,0 MB, uygulamada (Bölüm 1'in tamamı).
- `voice/`: 1.128 dosya, depoda ama uygulamada değil; indirilir.
- `D:\DilmacSes\voice\`: 1.613 dosya, ~27 MB, kendi `index.json`'ı ile; depoda değil, indirilir. Kurs sırasında s5u9 ünitesinin ortasına kadar.
- İndirilecek toplam: 2.741 kayıt, 41,6 MB (s2 8,5 · s3 10,5 · s4 12,5 · s5 10,1 MB).
- Harcanan: 99.978 karakter (603 yeniden kayıt 9.859 + yeni kayıtlar 90.119). Hesap sayacı 18 Kasım akşamı 44.082 kullanılmış, 78.146 kalan gösteriyor (Creator, 122.228 aylık); sayaç metin uzunluğundan az ya da geç düşüyor, bu yüzden bütçe metin uzunluğuyla tutuldu.
- Kursun kaydı olmayan kısmı: ~4.700 metin, ~244.000 karakter. Kalanlar sonraki aylarda `--overflow` ile üretilmeli.

## Eller serbest konuşma (otomatik dinleme)

Derslerdeki "Bu cümleyi sesli oku" ve gölgeleme (3. adım) alıştırmalarında ve
Telaffuz koçunun "Söyle" adımlarında mikrofona basmak gerekmez
(`lib/exercises/hands_free.dart`, `HandsFreeTurn`):

1. Cümle (kayıt ya da telefonun sesi) **sonuna kadar** çalınır
   (`linePlayerProvider.sayLine`); uygulama ses çalarken asla dinlemez (yankı yok).
2. Mikrofon kendiliğinden açılır, "Dinliyorum" göstergesi titreşir.
3. İlk kelime duyulduktan sonra **1 sn sessizlik** (`endOfSpeechSilence`)
   turu bitirir; tanıyıcının son sonucu gelince cevap otomatik kontrol edilir.
   Konuşmanın başındaki sessizlik turu bitirmez: eklentinin `pauseFor` süresi
   dinlemenin başından sayıldığı için bu sayaç uygulamada tutulur.
4. **7 sn** (`noSpeechTimeout`) hiç kelime yoksa nazik bir ipucu ve tek
   "Tekrar dene" düğmesi çıkar; "Şu an konuşamıyorum" yine durur.
5. Mikrofon izni/tanıyıcı yoksa düğmeli akış sürer; o oturumda bir daha
   kendiliğinden denenmez (izin penceresi tekrar tekrar açılmasın).
6. Mikrofona dokunmak her zaman çalışır (erişilebilirlik); dinlerken dokunmak
   turu hemen bitirir.

Ayar: Profil > Görünüm > "Konuşma alıştırmalarında otomatik dinle"
(`hands_free_listen_v1`, varsayılan açık). Kapalıyken eski düğmeli akış
(uzun duraklama süreleri, `listenTimes`) aynen çalışır.

### Mikrofonsuz eşdeğer yol

Konuşma alıştırmasında her zaman iki çıkış vardır, ikisi de cezasızdır:

- **Yazarak cevapla**: cümle yazılır, konuşmayla aynı hoşgörüyle (büyük
  harf, noktalama, kısaltma) kontrol edilir ve normal bir cevap gibi sayılır.
- **Şu an konuşamıyorum**: soru çözülmüş sayılır; yanlış, can kaybı ya da
  "hatasız" bonusu kaybı yoktur. XP ve seri, cevaplanmış gibi aynıdır
  (`test/konusma_esdeger_test.dart`).
## Ses paketleri (indirme)

Play'den inen uygulama küçük kalsın diye kayıtların çoğu uygulamada değil, Firebase Storage'da (`dilbaz-3392e.firebasestorage.app`, `voice/`) durur.

- **Manifest** `assets/voice_manifest.json` (`lib/core/voice_manifest.dart`): bölüm (s2, s3…) başına paketler, kurs sırasıyla; her kayıt için SHA-256'nın ilk 32 hanesi ve boyutu. Bucket'taki adı `voice/<voiceKey>_<hash8>.mp3`: yeniden kaydedilen cümle yeni ad alır, bu yüzden dosyalar bir yıl `immutable` önbelleklenir.
- **Uygulama** (`lib/services/voice_library.dart`, `voice_store.dart`): açılıştan 8 sn sonra, yalnızca Wi-Fi'deyken, eksik kayıtları dörder dörder indirir. Boyutu ya da hash'i tutmayan dosya atılır (o cümleyi telefonun sesi okur). Dosyalar uygulama deposunda (`<app support>/voice/files`) durur, internetsiz çalar. Wi-Fi kesilince durur, gelince sürer.
- **Yeni kayıtlar güncelleme olmadan:** uygulama indirmeye başlarken bucket'taki `voice/manifest.json`'a bakar; sürümü yüksekse onu kullanır.
- **Ayar:** Profil → Ses → "Ses paketlerini indir (Wi-Fi)" (toplam ve inen boyut, ilerleme) ve "İndirilen sesleri sil" (anahtarı da kapatır).
- **Kurallar** (`storage.rules`): `voice/` herkese okunur (giriş gerekmez), listelenemez; istemciden yazma yok; geri kalan her yol kapalı. Yükleme gsutil/IAM ile yapılır, kurallara tabi değildir.

### Kayıt ekleyince

```bash
dart run tool/voice_manifest.dart --extra D:/DilmacSes/voice                            # manifest'i yeniler
dart run tool/voice_manifest.dart --rebalance --core-mb 10 --extra D:/DilmacSes/voice   # çekirdeği yeniden böler (isteğe bağlı)
dart run tool/upload_voice.dart --extra D:/DilmacSes/voice                              # hazırlar, hash'leri doğrular, komutları yazar
dart run tool/upload_voice.dart --extra D:/DilmacSes/voice --run                        # gerçek bucket'a yükler (gcloud auth login)
```

Önce kayıtlar (`Cache-Control: public, max-age=31536000, immutable`), en son manifest (`max-age=300`) yüklenir; böylece hiçbir uygulama dosyası olmayan bir manifest görmez. `--check` manifest güncel değilse hata verir. Kurallar ayrıca deploy edilir: `firebase deploy --only storage`.

### Test

```bash
flutter test test/voice_store_test.dart test/voice_pack_test.dart
firebase emulators:exec --only storage --project demo-lingora "flutter test test/voice_storage_emulator_test.dart"
dart run tool/upload_voice.dart --extra D:/DilmacSes/voice --emulator 127.0.0.1:9199    # emülatör açıkken tam yükleme provası
```

Uygulamayı emülatörden indirtmek için `--dart-define=LINGORA_STORAGE_EMULATOR=10.0.2.2:9199`. CI: `.github/workflows/storage.yml`.
