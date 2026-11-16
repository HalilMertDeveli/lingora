# Stoacı sözler

Ders ve pratik sırasında, ders sonunda ve bazen hatadan sonra gösterilen kısa sözler. Veri dosyası `assets/quotes/stoic.json`, kod `lib/data/stoic.dart` ve `lib/ui/stoic_card.dart`.

## Kaynaklar (telif hakkı serbest)

| Yazar | Eser | İngilizce metnin kaynağı |
|---|---|---|
| Marcus Aurelius | Kendime Düşünceler (*Meditations*) | George Long çevirisi, 1862 |
| Seneca | Lucilius'a Mektuplar (*Epistulae Morales*) | Richard M. Gummere çevirisi, Loeb, 1917–1925 |
| Epiktetos | Enchiridion; bir söz *Söylevler* 1.15'ten | George Long çevirisi, 1877 |

- Üç çeviri de kamu malıdır. Modern ve telifli çevirilerden (Hays, Robin Hard vb.) ve internetteki "motivasyon sözü" derlemelerinden hiçbir şey alınmadı.
- İngilizce metinler kısaltıldı. A2–B1 düzeyine uysun diye *thou/thy/thee* gibi eski zamirler *you/your* yapıldı. Birkaç cümlede eski sözcükler sadeleştirildi; örneğin Marcus 4.49'da *promontory* yerine *rock* kullanıldı. Anlam korundu.
- Türkçe çeviriler Dilbaz için yazıldı. Hiçbir Türkçe yayından alınmadı.
- Her sözün kaynağı eser ve bölüm numarasıyla yazılır, örneğin "Marcus Aurelius, Kendime Düşünceler 5.1".

## Alanlar

- `id`, `author` (`marcus` / `seneca` / `epictetus`), `work` (`meditations` / `letters` / `enchiridion` / `discourses`), `ref`, `en`, `tr`.
- `kid: true`: Çocuk modunda yalnızca bu sade sözler çıkar.
- `mistake: true`: hatadan sonraki kartta yalnızca bunlar çıkar. Bu sözler yargı, sabır ve öğrenme üzerinedir.

## Ne zaman çıkar

- **Ara kart:** Her ders ya da pratikte bir kez, yaklaşık yarıda çıkar; 4. ile 8. cevap arasında, `stoicInterludeAt`. 6 sorudan kısa oturumlarda ve ünite sınavlarında çıkmaz.
- **Hatadan sonra:** Oturumdaki 2. yanlıştan itibaren, yanlış cevabın hemen ardından çıkar. Oturumda en fazla bir kez gelir. Diğer karttan en az 3 cevap uzakta durur. İki oturum arasında en az 30 dakika bekler (`stoic_mistake_at_v1`). Tek bir yanlış kart getirmez.
- **Ders sonu:** Sonuç ekranında, sayaçların altında küçük bir söz kartı çıkar.
- Kart bir dokunuşla, "Devam" düğmesiyle, boşluğa dokununca ya da geri tuşuyla kapanır. XP'yi, sayaçları ve "kaldığın yerden devam" kaydını değiştirmez.
- Son gösterilen 20 söz tekrar gelmez (`stoic_recent_v1`).
- Profil > Görünüm > "Stoacı sözler" anahtarıyla hepsi kapanır.

## Yeni söz eklemek

Sözü kamu malı bir çeviriden al ve kısa tut; 30 sözcüğü geçmesin. Türkçesini kendin yaz ve kaynağını bölüm numarasıyla ekle. `test/stoic_test.dart` boş alanları, bilinmeyen yazar ve eserleri, uzun sözleri ve en az 40 söz şartını denetler.
