# Katkı rehberi

Lingora'ya katkı için kısa çalışma düzeni.

## Dal (branch) akışı

- `main` her zaman çalışır ve derlenir durumda tutulur; doğrudan `main`'e push yapılmaz.
- Her iş için `main`'den yeni bir dal aç:
  - `feature/<kisa-ad>`: yeni özellik (ör. `feature/okuma`, `feature/seviye-testi`)
  - `fix/<kisa-ad>`: hata düzeltme
  - `chore/<kisa-ad>`: araç, CI, bağımlılık güncellemesi
- Dalı küçük ve tek konuya odaklı tut. Uzun süren işlerde `main`'i düzenli olarak dalına al
  (`git pull --rebase origin main` ya da merge).

## Pull request

1. Dalını push'la: `git push -u origin feature/<kisa-ad>`.
2. `main`'e bir PR aç. Başlık ve açıklama Türkçe olsun: ne değişti, neden, nasıl test edildi.
3. **CI yeşil olmadan PR birleştirilmez.** CI şunları çalıştırır:
   - `dart format --set-exit-if-changed -l 110 lib test`
   - `flutter analyze`
   - `flutter test`
4. Bir inceleme onayından sonra PR birleştirilir; birleşen dal silinir.

PR açmadan önce aynı kontrolleri yerelde çalıştır:

```bash
flutter pub get
dart format -l 110 lib test
flutter analyze
flutter test
```

## Commit mesajları

Conventional Commits biçimi, açıklama Türkçe:

```
<tür>(<kapsam>): <kısa açıklama>
```

Türler:

| Tür        | Ne için                                  |
| ---------- | ---------------------------------------- |
| `feat`     | yeni özellik                             |
| `fix`      | hata düzeltme                            |
| `docs`     | yalnızca belge                           |
| `style`    | biçimlendirme, davranış değişmez         |
| `refactor` | davranışı değiştirmeyen kod düzenlemesi  |
| `test`     | test ekleme/düzeltme                     |
| `chore`    | araç, bağımlılık, yapılandırma           |
| `ci`       | GitHub Actions iş akışları               |

Örnekler:

```
feat(okuma): seviyeye göre okuma metinleri eklendi
fix(ders): yanlış cevap tekrar kuyruğuna eklenmiyordu
ci: APK derleme ve GitHub Release iş akışı eklendi
```

Kısa açıklama küçük harfle başlar, sonunda nokta olmaz ve 72 karakteri geçmez. Gerekirse boş bir
satırdan sonra ayrıntılı açıklama ekle.

## Kod ve içerik

- Satır uzunluğu 110 karakter (`dart format -l 110`).
- Yeni mantık için `test/` altına test ekle; içerik JSON'ları testlerde diskten okunur ve doğrulanır.
- İçerik (`assets/`) özgün olmalı; resmî sınav sorularını ya da telifli metinleri kopyalama.

## Sürüm

`main`'e her birleşmede release APK derlenir. Sürüm çıkarmak için `pubspec.yaml`'daki `version`'ı
artır, ardından `v<sürüm>` etiketi gönder; ayrıntılar README'deki "Sürüm ve imzalama" bölümünde.
