# Ekran görüntüsü planı ve öne çıkan grafik

Play Console: telefon için 2–8 ekran görüntüsü (8 kullanıyoruz), PNG/JPEG, 9:16 dikey,
**1080×1920** (uzun kenar kısa kenarın en fazla 2 katı olmalı; 1080×2400 gibi
oranlar reddedilir). Her görselde üstte kısa bir Türkçe başlık (en fazla ~5 kelime) ve
altında küçük bir açıklama; altında gerçek uygulama ekranı.

Hazır dosyalar (repo dışında): **`D:\Lingora\_cikti\magaza\`**

| Dosya | Boyut |
| --- | --- |
| `01_konusma.png` … `08_lig_seri.png` | 1080×1920, başlıklı |
| `ham/` | Başlıksız ham emülatör ekranları (aynı sıra) |
| `ikon_512.png` | 512×512, 32 bit PNG (Çaycı Dayı uygulama simgesi, `assets/icon/icon.png`) |
| `one_cikan_1024x500.png` | 1024×500 öne çıkan grafik |

Çekim: Android 16 emülatörü (`pixel` profili, 1080×1920, 420 dpi), debug derleme,
`--dart-define=LINGORA_FIREBASE=off --dart-define=LINGORA_PREMIUM=1`. Firebase
kapalı olduğu için hiçbir veri gerçek projeye (`dilbaz-3392e`) gitmez; Premium
bayrağı yalnızca release dışı derlemelerde çalışır. Yapay zekâ sohbeti ekranı bu
modda uygulamanın gerçek sohbet arayüzünü hazır senaryo cevaplarıyla gösterir;
Firebase Functions emülatöründeki yapay zekâ taklidi (`ai_stub.ts`) yalnızca
"[stub]" metni döndürdüğü için mağaza görseline uygun değil. Durum çubuğu temiz,
örnek seri ve XP cihazdaki yerel ilerlemeye yazıldı; kişisel veri yok.

| # | Dosya | Ekran | Başlık | Alt yazı |
| --- | --- | --- | --- | --- |
| 1 | `01_konusma.png` | Konuşma: "Kafede sipariş", Türkçe düzeltme balonu | **İngilizce konuşarak öğren** | Hatanı anında, Türkçe açıklamayla düzeltir |
| 2 | `02_neden_yanlis.png` | YDS sorusu, yanlış cevap ve Türkçe açıklama | **Hatanı Türkçe anlatır** | Her yanlışın nedeni Türkçe açıklanır |
| 3 | `03_yol.png` | Öğren sekmesi, YDS yolu (Ünite 11) | **Günde birkaç dakika** | Kısa dersler, ünite ünite ilerle |
| 4 | `04_yds.png` | YDS "Bugün" planı ve blokları | **YDS ve YÖKDİL'e hazırlan** | 52 haftalık plan, günlük çalışma blokları |
| 5 | `05_mulakat.png` | Mülakat provası girişi | **İngilizce mülakat provası** | Cevabını kaydet, takıldığın yeri çalış |
| 6 | `06_kelime.png` | Pratik merkezi: Bugün, Konuşma, Telaffuz, Tekrar | **Konuş, dinle, tekrar et** | Telaffuz koçu ve tekrar kartları |
| 7 | `07_gramer.png` | Ünite rehberi: Sıfat cümlecikleri | **Gramer, Türkçe anlatımla** | Örnek cümleler ve hafıza ipuçları |
| 8 | `08_lig_seri.png` | Lig: Bronz Ligi, arkadaşlar | **Her gün biraz, birlikte** | Haftalık lig, görevler ve seri |

1. görseldeki düzeltme bu çekimde hazır senaryodaki Türk hata dedektöründen gelir;
Premium yapay zekâ partneri aynı ekranda aynı balonla düzeltir. Başlık bu yüzden
yapay zekâ iddiası taşımaz; yapay zekâ mağaza metninde ve öne çıkan grafikte anlatılır.

Notlar:

- Sıralama dönüşüme göre: ilk iki görsel aramada da görünür; ana değer önerisi
  (yapay zekâyla konuşma + Türkçe açıklama) ilk ikide.
- Premium özelliği gösteren görselde alt yazıda "(Premium)" yazar (yanıltıcı olmasın).
- Görsellerde ebeveyn gözetimli mod ya da çocuklara yönelik ifade kullanılmaz; hedef
  kitle 13+ (`play-store.md`). Pofuduk yalnızca uygulamanın kendi ekranında küçük
  göründüğü kadar yer alır, kapak karakteri değildir.
- Yeniden üretmek: `D:\Lingora\_cikti\magaza\uret.sh` (ffmpeg; Inter yazı tipi
  `assets/fonts/`). Ham ekranları değiştirip betiği yeniden çalıştırmak yeter.

## Öne çıkan grafik (1024×500)

Konsept: marka turuncusu (`#F17F04`, uygulama simgesinin zemini) üzerinde solda
Çaycı Dayı simgesi, sağda iki satır metin:

- Büyük: **İngilizce konuşarak öğren**
- Küçük: **Yapay zekâ partneri · YDS · YÖKDİL · LGS**

Play bu görseli bazı yerlerde kırptığı ve üstüne oynat düğmesi koyabildiği için
önemli öğeler ortadaki güvenli alanda; kenarlarda yalnızca zemin var. Metin,
uygulama adını tekrar etmez (Play adı zaten gösterir). Dosya:
`one_cikan_1024x500.png`.

## İleride

- Mağaza kaydı deneyi (Store listing experiment): görsel 1 için "İngilizce konuşarak
  öğren" ile "YDS ve YÖKDİL'e hazırlan" başlıklarını karşılaştır.
- `dogal-konusma` (canlı sesli sohbet) yayımlanınca görsel 1'i sesli sohbet
  ekranıyla yenile.
- İsteğe bağlı 30 sn tanıtım videosu: sohbet → hata açıklaması → seri → sınav pratiği.
