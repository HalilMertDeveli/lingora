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
