# Açılış süresi ölçümü

Soğuk açılıştan kullanılabilir yol ekranına kadar geçen süreyi ölçmek için.

## Zaman çizelgesi

`lib/core/startup_trace.dart`, açılışın adımlarını işaretler. Her işaret
DevTools zaman çizelgesine bir olay yazar (profile). Uygulama
`--dart-define=LINGORA_STARTUP_TRACE=true` ile derlenirse logcat'e de
`STARTUP <adım> <main'den beri ms>` satırı basar.

| İşaret | Anlamı |
|---|---|
| `main` | Dart `main()` başladı |
| `prefs` / `firebase` | SharedPreferences ve Firebase hazır (ikisi birlikte istenir) |
| `first_frame` | İlk Flutter karesi çizildi |
| `asset_manifest` | Varlık listesi okundu |
| `course_outline` | Yolun özeti (`assets/course_index/`) hazır |
| `path_build` / `path_drawn` | Yol ekranı kuruldu / ilk karesi çizildi (**hedef**) |
| `course_full` | Tam kurs (dersler) arka planda hazır |

## Cihazda ölçüm

```bash
flutter build apk --release --target-platform android-x64 -t tool/perf/startup_main.dart \
  --dart-define=LINGORA_STARTUP_TRACE=true --dart-define=LINGORA_FIREBASE=emulator \
  --dart-define=PERF_TRACK=yds --dart-define=PERF_DONE_UNITS=20
bash tool/perf/measure_startup.sh build/app/outputs/flutter-apk/app-release.apk 15 com.lingora.lingora
```

- `startup_main.dart`, ilk açılışta onboarding'i geçmiş bir öğrenci yazar
  (`PERF_TRACK` parçası, ilk `PERF_DONE_UNITS` ünitesi bitmiş). Sonraki her
  soğuk açılış doğrudan yol ekranına gider.
- `measure_startup.sh`, her turda uygulamayı durdurur, `am start -W` ile
  başlatır ve her işareti başlatma isteğine (ActivityTaskManager `START`)
  göre ms olarak yazar. Sonda medyanları verir.
- **`LINGORA_FIREBASE` varsayılanı `prod`dur.** Ölçüm derlemelerinde
  `emulator` (demo-lingora) ya da `off` kullan. Aksi hâlde uygulama gerçek
  projede anonim hesap açar.
- Emülatör başka oturumlarla paylaşılıyorsa ölçüm derlemesini ayrı bir paket
  adıyla kur (örneğin geçici `applicationIdSuffix = ".perf"`) ve paket adını
  betiğe üçüncü argüman olarak ver.
- Ölçüm sırasında bilgisayarda derleme ya da test çalıştırma. Emülatör aynı
  CPU'yu paylaşır ve sonuçlar kayar.

## 3 kat içerik

```bash
dart run tool/perf/triple_content.dart     # her üniteyi iki kez kopyalar
dart run tool/build_course_index.dart      # özetleri yeniden üretir
# ... derle, ölç ...
git checkout -- assets/courses assets/course_index
```

`test/startup_perf_test.dart` de aynı 3 kat içerikle özetin küçük ve hızlı
kaldığını, yolun yalnızca açık bölümleri kurduğunu denetler.

## Emülatörle ilgili not

Android emülatöründe Impeller, OpenGLES kullanır. İlk Android çiziminde
shader programlarını derlerken platform iş parçacığını ~400 ms bekletir
(atrace: `ReactorGLES::React` / `LinkProgram`). Flutter bu iş parçacığını UI
iş parçacığıyla birleştirdiği için Dart da bu sürede çalışamaz. Gerçek
cihazlarda Vulkan kullanılır ve bu bekleme yaşanmaz. Bu yüzden emülatör
sayıları gerçek cihaz sayılarından kötümserdir.
