# Lingora

Türkçe konuşanlar için İngilizce öğrenme uygulaması (Flutter). İçerik, karakterler, maskot ve
tasarım projeye özgüdür.

## Özellikler

- **Genel İngilizce:** A1–A2, 12 ünite. Her ünitede dersler, karakterli hikâye, ünite sınavı ve
  ödül sandığı var. Alıştırma türleri: seçmeli, çeviri, boşluk doldurma, dinleme, eşleştirme, konuşma.
- **Meslek paketleri:** Turizm İngilizcesi (resepsiyon, restoran, rehberlik, şikâyet çözme) ve
  İş Görüşmesi İngilizcesi.
- **Sınav hazırlık:** YDS/YÖKDİL ve LGS soru bankaları. Konu çalışmada Türkçe açıklama, süreli
  mini deneme ve cevap anahtarı. Sorular özgündür, resmî sınav soruları değildir.
- **Notlarım:** Notion'da tutulan kişisel İngilizce notlarından üretilen içerik:
  - Gramer Yolu: notlardan hazırlanan, A1'den C1'e 80 adım adım ders (formül kartı, zaman çizelgesi,
    Türkçe karşılaştırma, notundan alıntı, yaygın hatalar, mini test),
  - kişisel sözlük (aralıklı tekrar kartları ve kelime testi),
  - gramer notları (kendi örneklerinden otomatik alıştırma),
  - İngilizce günlük,
  - hedefler.
- **Konuş:** Rol yapma sohbetleri. Hatalar Türkçe açıklamayla düzeltilir. Sunucu bağlı değilken
  demo modunda çalışır.
- **Cezasız öğrenme:** Can sistemi yok. Yanlış cevaplar tekrar sorulur ve "Hatalarını çalış"
  listesine eklenir.
- **Motivasyon:** Seri, XP, günlük hedef, günlük görevler, haftalık lig (cihazda simülasyon) ve
  yerel hatırlatma bildirimleri.
- **Görünüm:** Animasyonlar ve tamamen kodla çizilen maskot "Lino".

Tüm ilerleme cihazda saklanır (shared_preferences). Hesap ya da sunucu gerekmez.

## Çalıştırma

```bash
flutter pub get
flutter run
```

Testler:

```bash
flutter test
```

## Yapay zekâ sohbet sunucusu

`server/` klasöründe Claude ile konuşan bir Supabase Edge Function var. Kurulumu ve uygulamaya
bağlamak için [server/README.md](server/README.md) dosyasına bak. Bağlanmadığında "Konuş" sekmesi
demo modunda çalışır.

## Notion notlarını güncelleme

Notlar `assets/notes/` altındadır. Notion'dan dönüştürülmüş JSON dosyalarını birleştirmek için:

```bash
node tool/import_notes.js <dönüştürülmüş-notlar-klasörü>
```

## Proje yapısı

- `lib/models`, `lib/data`: içerik modelleri, ilerleme, lig, görevler, aralıklı tekrar
- `lib/screens`: ekranlar
- `lib/exercises`: alıştırma türleri
- `lib/ui`: animasyonlar ve maskot
- `assets/courses`, `assets/exams`, `assets/notes`: içerik
- `test/`: mantık ve arayüz testleri (içerik doğrulaması dahil)
