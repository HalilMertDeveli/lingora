# Yapılacaklar

Son güncelleme: 12 Kasım 2026, main = PR #81 sonrası.

İşler iki gruba ayrıldı:
- **Ekip tarafı:** Claude ve geliştirme oturumları kendi başına yapabilir.
- **Sahip tarafı:** hesap, para, imza ya da senin kararını gerektirir; bunları yalnızca sen yapabilirsin.

Bir maddeyi bitirdiğinde `[x]` ile işaretle.

---

## 🧑‍💼 Senin tarafın (sahip)

### Mağazaya çıkış için şart

- [ ] **Google Play Console hesabı aç.** Tek seferlik 25 $ ücreti var. Uygulamayı `com.lingora.lingora` paketiyle oluştur.
- [ ] **Abonelik ürünlerini Play Console'da tanımla.**
  - Ürünler: `lingora_premium_monthly`, `lingora_premium_yearly`, aile planı ve sınav paketleri. Ürün kimlikleri [abonelik.md](abonelik.md)'de yazıyor.
  - Fiyatları sen belirle.
- [ ] **Yayın (upload) imza anahtarı oluştur.**
  - Anahtarı 4 GitHub secret'ı olarak ekle. Adımlar README'deki "Sürüm ve imzalama" bölümünde.
  - Anahtarın şifresini kaybetme, güvenli bir yerde sakla.
- [ ] **Yayın anahtarının SHA-1 ve SHA-256 değerlerini bana gönder.** Firebase'e ben eklerim. Bu yapılmazsa mağaza sürümünde Google ve telefonla giriş çalışmaz.
- [ ] **Gizlilik politikasını gözden geçirip bir web adresinde yayınla.**
  - Taslak hazır: [magaza/gizlilik-politikasi.md](magaza/gizlilik-politikasi.md).
  - KVKK aydınlatma metni için gerekirse bir hukukçuya göster.
- [ ] **Mağaza metinlerini ve veri güvenliği formunu onayla.**
  - Dosyalar: [magaza/play-store.md](magaza/play-store.md) ve [magaza/veri-guvenligi.md](magaza/veri-guvenligi.md).
  - Mağaza görselleri için `docs/onizleme/` kullanılabilir.

### Firebase ve sunucu

- [ ] **Firebase projesini Blaze (kullandıkça öde) planına geçir.** Cloud Functions için şart. Bir bütçe uyarısı koy, ör. aylık 10 $.
- [ ] **Anthropic API anahtarı al ve bana haber ver.** Anahtarı Firebase secret olarak ben eklerim, sonra Functions'ı dağıtırım. Bu yapılmadan yapay zekâ sohbeti demo modunda kalır.
- [ ] **Firestore bölgesine karar ver.**
  - Veritabanı şu an ABD'de (`nam5`).
  - Türkiye'ye yakın olsun istersen veritabanı boşken Console'dan silip `europe-west1`'de yeniden oluştur. Gerisini ben hallederim.
- [ ] *(İsteğe bağlı)* **SMS test numarası ekle.** Telefonla girişi SMS harcamadan denemek için:
  - Console → Authentication → Sign-in method → Phone → "Phone numbers for testing"
  - Örnek: `+90 555 000 00 00` / kod `123456`

### İş ve marka

- [ ] **"Dilbaz" adını TÜRKPATENT'te ve Play Store'da arat.** Marka başvurusu yapmak isteyebilirsin.
- [ ] **Dilbaz Kurumsal için şirket ve fatura bilgilerini belirle:** şahıs/şirket, vergi, e-fatura. Ayrıntılar [kurumsal.md](kurumsal.md)'de.
- [ ] *(İsteğe bağlı)* **iOS:** Apple Developer hesabı (yıllık 99 $) ve derleme için bir Mac gerekir.

### İçerik incelemesi (senin gözün)

- [ ] **LGS yolunu dene.** [lgs-plan.md](sinav/lgs-plan.md) ve PR #29'daki "nasıl incelenir" listesini kullan.
- [ ] **YDS/YÖKDİL yolunu dene.** [yds-plan.md](sinav/yds-plan.md) ve PR #30–#31'deki listeleri kullan.
- [ ] **Genel kursun Bölüm 2–8'ine göz at.** Tuhaf bulduğun cümleleri not al, toplu düzeltirim.
- [ ] **Çaycı Dayı ve Pofuduk'un kullanıldığı yerleri onayla.**

---

## 🤖 Ekip tarafı (Claude ve geliştirme oturumları)

### Hemen

- [x] README ve ekran önizlemeleri.
- [x] Kurs seçicideki "A1–A2" yazısını "A1–B2" yap.
- [x] **Bağımsız içerik kalite turu** (PR #36, #38, #54, #57, #80). Bölüm 2–8, LGS ve YDS'de dilbilgisi, doğal İngilizce ve Türkçe açıklama kontrolü; hataları toplu düzelt.
- [x] **Açılış hızı** (PR #40; gerçek telefonda ölçülmeli). Kurs dosyalarını arka planda (isolate) ayrıştır. Yayın sürümünde açılış süresini ölç ve hedefi < 1 sn yap.
- [x] **Uçtan uca test** (PR #37, emülatör projesiyle; gerçek projede elle deneme: docs/giris-testleri.md). Gerçek projede misafir → e-posta / Google / telefon bağlama; ilerlemenin kaybolmadığını doğrula.

### Senin adımın gelince

- [ ] **Yayın anahtarı gelince:** SHA'ları Firebase'e ekle, `google-services.json`'u yenile, imzalı AAB derle.
- [ ] **Blaze ve Anthropic anahtarı gelince:** Functions'ı dağıt (lig, yapay zekâ sohbeti, satın alma doğrulama); güvenlik kurallarını denetle (security-rules auditor).
- [ ] **Play ürünleri gelince:** gerçek satın alma akışını kapalı test kanalında dene.
- [ ] **Firestore bölgesi değişirse:** kuralları ve indeksleri yeniden yükle.

### Tamamlanan büyük işler

- [x] YDS 1 yıllık program (52 hafta) ve öğrenme yöntemleri (Bugün, aralıklı tekrar, hata defteri, deneme raporu, sürdürme modu).
- [x] Genel kurs A1–C1: beceri üniteleri, yazma/gölgeleme/önce dinle, okuma–dinleme kütüphanesi, C1 bölümleri.
- [x] Şıkların karışık sırada gösterilmesi (PR #74).

### Sıradaki

- [ ] **YDS puan tahmini kalibrasyonu:** gerçek sınav sonuçları toplandıkça tahmin ayarlanmalı.
- [ ] **YÖKDİL dağılımı:** ÖSYM belgesiyle teyit (şu an hazırlık kaynaklarına dayanıyor).

### Geliştirme

- [ ] **Onboarding'i yenile.** Pofuduk/Çaycı Dayı karşılaması, hedef seçimi (genel / LGS / YDS / yazılımcı), seviye testi.
- [ ] **Sesli içerik.** Cihaz TTS'i yerine doğal ses seçeneği; dinleme alıştırmalarında yavaş oynatma.
- [ ] **Ana ekran widget'ı:** seri ve günlük hedef.
- [ ] **Erişilebilirlik turu:** ekran okuyucu etiketleri, büyük yazı tipi, renk kontrastı.
- [ ] **Yönetim paneli** ile içerik düzenleme ve hata bildirimi ("Bu soruda hata var" butonu).
- [ ] **Analitik panosu:** hangi ünitede bırakılıyor, hangi sorular çok yanlış yapılıyor.
- [ ] **Eski dalları ve çalışma klasörlerini temizle.** Silme izni sende; bana onay verirsen listeyi hazırlarım.
