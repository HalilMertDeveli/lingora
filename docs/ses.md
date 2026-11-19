# Seslendirme

Ders cümleleri iki kaynaktan okunur:

1. **Stüdyo kaydı** (`assets/voice/`): ElevenLabs'in hazır sesleriyle önceden üretilmiş MP3'ler.
   - Matilda (kadın, Amerikan) varsayılan ses. Üç kelimeden uzun cümlelerin yaklaşık dörtte biri Eric (erkek, Amerikan).
   - Hikâyelerde kadın karakterler Matilda, erkek karakterler Eric.
   - Dosya adı, cümlenin `voiceKey` değeri (`lib/core/voice_key.dart`); `index.json` hangi cümlelerin kayıtlı olduğunu tutar.
2. **Telefonun ses motoru**: Kaydı olmayan her cümle, önceki gibi cihazın metin okuma motoruyla okunur (`lib/services/speech.dart`).

## Ses ayarları

Model `eleven_multilingual_v2`, çıktı `mp3_44100_64`. Daha canlı ve anlaşılır okuma için:
stability 0.3, similarity_boost 0.8, style 0.5, use_speaker_boost açık (`voiceSettings`, `tool/voice_elevenlabs.dart`).

## Kayıt üretmek

```bash
dart run tool/voice_elevenlabs.dart --all --dry --budget 50000   # kaç karakter gerekiyor, bütçe nereye kadar yeter
dart run tool/voice_elevenlabs.dart --all --budget 50000 --keep 20000 --max-mb 25 --overflow D:/DilmacSes/voice
dart run tool/voice_elevenlabs.dart --regen --budget 20000       # assets/voice'taki kayıtları baştan üretir
```

- `--budget N`: bu çalıştırmada en çok N karakter harcanır (metin uzunluğuyla sayılır; hesaptaki sayaç bundan az ya da geç düşebilir).
- `--keep N`: hesapta en az N karakter bırakılır (`/v1/user/subscription` ile başta kontrol edilir).
- `--max-mb M --overflow DİZİN`: `assets/voice` M MB'a ulaşınca yeni kayıtlar depo dışındaki DİZİN'e, kendi `index.json`'ıyla yazılır (APK boyutu için).
- `--regen`: `assets/voice/index.json`'daki kayıtları yeniden üretir; ilerleme `.dart_tool/voice_regen_done.txt`'de tutulur, yarıda kalırsa kaldığı yerden sürer.
- Kayıtlı cümleler (iki dizindeki `index.json`) atlanır; sıra kurs sırasıdır.

API anahtarı `ELEVENLABS_API_KEY` ortam değişkeninden ya da `%USERPROFILE%\.dilbaz\elevenlabs_key.txt` dosyasından okunur. Anahtar depoya girmez, ekrana yazılmaz.

## Durum ve lisans

- **18 Kasım 2026: tüm kayıtlar ücretli Creator planıyla üretildi; ticari kullanım lisanslıdır.** 16 Kasım'da ücretsiz planla yapılan 603 kayıt aynı seslerle (Matilda, Eric) ve yeni ayarlarla baştan üretildi; ücretsiz plandan kalan dosya yok.
- `assets/voice/`: 1.967 dosya, ~25 MB (Bölüm 1'in tamamı ve sonrası, kurs sırasıyla).
- `D:\DilmacSes\voice\`: 1.613 dosya, ~27 MB, kendi `index.json`'ı ile; depoda değil. İlk dinlemede indirilmek üzere barındırılacak (ayrı iş). Kurs sırasında s5u9 ünitesinin ortasına kadar.
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
