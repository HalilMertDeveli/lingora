# Ekran görüntüsü planı

Play Console: telefon için en az 2, en fazla 8 ekran görüntüsü (önerilen 8),
9:16 dikey, en az 1080×1920 px. Her görselde üstte kısa bir Türkçe başlık
(en fazla ~5 kelime), altında gerçek uygulama ekranı. Arka plan marka moru
(`#6C4CF1`) ile açık yüzey (`#F7F6FB`) arasında değişir; yazı tipi uygulamadakiyle aynı.
Tasarım yenilemesi (`docs/tasarim.md`) birleştikten sonra çekilmeli.

Çekim: `flutter run --release` ile gerçek cihaz ya da masaüstü (Windows) pencere
1080×1920'ye ayarlanarak; durum çubuğu temiz (saat 09:41, tam pil, bildirim yok).
Örnek kullanıcı adı "Deniz", seri 12 gün, XP gerçekçi. Kişisel veri, gerçek
e-posta görünmez.

| # | Ekran | Başlık (üst yazı) | Alt yazı (isteğe bağlı) | Hazırlık |
| --- | --- | --- | --- | --- |
| 1 | Ana sayfa / öğrenme yolu | **Günde 5 dakikada İngilizce** | Can yok, ceza yok, reklam yok | Genel İngilizce, 2. ünite ortası, seri 12 |
| 2 | Ders, yanlış cevap + "Neden yanlış?" | **Hatanı Türkçe anlatır** | Türklere özel hata dedektörü | Çeviri sorusu, "the" eksik hatası |
| 3 | Seviye testi sonucu | **Seviyeni ölç, doğru yerden başla** | | A2 sonucu ve önerilen yol |
| 4 | Sınav: YDS/LGS ana ekranı | **YDS, YÖKDİL ve LGS pratiği** | Konu konu açıklamalı | YDS seçili, konu listesi |
| 5 | Okuma: hikâye + kelime kartı | **Hikâyelerle oku, kelime topla** | | Kelime dokunulmuş, alt sayfa açık |
| 6 | Telaffuz ünitesi | **Doğru telaffuz, adım adım** | | "th" sesi ünitesi |
| 7 | Sohbet senaryosu (yapay zekâ) | **Yapay zekâ ile konuş** | Premium | Kafe senaryosu, düzeltme balonu görünür |
| 8 | Profil: seri, lig, davet | **Serini koru, arkadaşını davet et** | İkiniz de 7 gün Premium | Haftalık grafik dolu, davet kartı görünür |

Notlar:

- Sıralama dönüşüme göre: ilk üç görsel aramada görünür; değer önerisi
  (ücretsiz + Türklere özel) ilk ikide olmalı.
- Premium özelliği gösteren görselde "Premium" etiketi açıkça yazılır (yanıltıcı
  olmasın).
- **Öne çıkan grafik** (1024×500): logo + "Dilbaz: İngilizce Öğren" + "Günde 5
  dakika. Can sistemi yok." ve maskot.
- **Uygulama simgesi** 512×512, mevcut "L" logosu.
- İsteğe bağlı tanıtım videosu (30 sn): ders → hata açıklaması → seri → sınav pratiği.
- Play mağaza kaydı deneyi (Store listing experiment): görsel 1 için "Günde 5
  dakikada İngilizce" vs "Türkler için İngilizce" başlıklarını dene.
