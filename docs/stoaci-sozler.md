# Stoacı sözler

Ders ve pratik bitince sonuç ekranında gösterilen kısa sözler. Ders sırasında söz kartı çıkmaz; kullanıcı dersin bölünmesini istemedi. Veri dosyası `assets/quotes/stoic.json`, kod `lib/data/stoic.dart` ve `lib/ui/stoic_card.dart`.

## Kaynaklar (telif hakkı serbest)

| Yazar | Eser | İngilizce metnin kaynağı |
|---|---|---|
| Marcus Aurelius | Kendime Düşünceler (*Meditations*) | George Long çevirisi, 1862 |
| Seneca | Lucilius'a Mektuplar (*Epistulae Morales*) | Richard M. Gummere çevirisi, Loeb, 1917–1925 |
| Epiktetos | Enchiridion; bir söz *Söylevler* 1.15'ten | George Long çevirisi, 1877 |

- Üç çeviri de kamu malıdır. Modern ve telifli çevirilerden (Hays, Robin Hard vb.) ve internetteki "motivasyon sözü" derlemelerinden hiçbir şey alınmadı.
- İngilizce metinler kısaltıldı. A2–B1 düzeyine uysun diye *thou/thy/thee* gibi eski zamirler *you/your* yapıldı. Birkaç cümlede eski sözcükler sadeleştirildi; örneğin Marcus 4.49'da *promontory* yerine *rock* kullanıldı. Anlam korundu.
- Türkçe çeviriler Dilmaç için yazıldı. Hiçbir Türkçe yayından alınmadı.
- Her sözün kaynağı eser ve bölüm numarasıyla yazılır, örneğin "Marcus Aurelius, Kendime Düşünceler 5.1".

## Alanlar

- `id`, `author` (`marcus` / `seneca` / `epictetus`), `work` (`meditations` / `letters` / `enchiridion` / `discourses`), `ref`, `en`, `tr`.
- `kid: true`: Çocuk modunda yalnızca bu sade sözler çıkar.

## Ne zaman çıkar

- **Ders sonu:** Sonuç ekranında, sayaçların altında bir kart çıkar. Kartın üstünde bugün kaç ders yapıldığı ve toplam doğru sayısı, altında söz var.
- Ünite sınavlarının sonunda söz çıkmaz.
- Son gösterilen 20 söz tekrar gelmez (`stoic_recent_v1`).
- Çocuk modunda yalnızca sade sözler (`kid`) seçilir.
- Profil > Görünüm > "Stoacı sözler" anahtarıyla kapanır.
- Ders içindeki kısa övgüler ve atasözleri ayrı bir özelliktir; `lib/ui/session.dart` dosyasında, `teaPraises` ve `proverbPraises` listelerinde.

## Yeni söz eklemek

Sözü kamu malı bir çeviriden al ve kısa tut; 30 sözcüğü geçmesin. Türkçesini kendin yaz ve kaynağını bölüm numarasıyla ekle. `test/stoic_test.dart` boş alanları, bilinmeyen yazar ve eserleri, uzun sözleri ve en az 40 söz şartını denetler.
