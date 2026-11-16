# Seslendirme

Ders cümleleri iki kaynaktan okunur:

1. **Stüdyo kaydı** (`assets/voice/`): ElevenLabs'in hazır sesleriyle önceden üretilmiş MP3'ler.
   - Matilda (kadın, Amerikan) varsayılan ses. Üç kelimeden uzun cümlelerin yaklaşık dörtte biri Eric (erkek, Amerikan).
   - Hikâyelerde kadın karakterler Matilda, erkek karakterler Eric.
   - Dosya adı, cümlenin `voiceKey` değeri (`lib/core/voice_key.dart`); `index.json` hangi cümlelerin kayıtlı olduğunu tutar.
2. **Telefonun ses motoru**: Kaydı olmayan her cümle, önceki gibi cihazın metin okuma motoruyla okunur (`lib/services/speech.dart`).

## Kayıt üretmek

```bash
dart run tool/voice_elevenlabs.dart --all --dry   # kaç karakter gerekiyor
dart run tool/voice_elevenlabs.dart --all         # kredi bitene kadar sırayla kaydeder
```

API anahtarı `ELEVENLABS_API_KEY` ortam değişkeninden ya da `%USERPROFILE%\.dilbaz\elevenlabs_key.txt` dosyasından okunur. Anahtar depoya girmez. Kayıtlı cümleler atlanır, bu yüzden her ay krediler yenilenince komut yeniden çalıştırılabilir.

## Durum ve lisans

- 16 Kasım 2026: ücretsiz krediyle 603 metin kaydedildi (Bölüm 1'in ilk 15 ünitesi tam). Tüm genel kurs ~264.000 karakter.
- **Ücretsiz ElevenLabs planı ticari kullanıma izin vermez.** Uygulama mağazaya çıkmadan ya da Premium satışı başlamadan önce kayıtlar ücretli bir planla (Starter ve üstü) yeniden üretilmeli ya da o planda üretilmiş olmalı.
- Kursun tamamı ~7.000 dosya, ~90 MB eder. Bu boyut APK'ya sığmaz; tamamı üretildiğinde kayıtlar uygulamaya gömülmek yerine ilk dinlemede indirilmeli.
