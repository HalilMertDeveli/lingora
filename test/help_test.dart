import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/sss.dart';
import 'package:lingora/screens/help_screen.dart';

void main() {
  test('normalisation ignores case and Turkish accents', () {
    expect(sssNormalize('İPTAL'), 'iptal');
    expect(sssNormalize('Çocuk Gözetimi'), 'cocuk gozetimi');
    expect(sssNormalize('IŞIK'), 'isik');
  });

  test('every topic the owner asked for has an answer', () {
    const topics = {
      'iptal': 'abonelik iptal',
      'iade': 'iade',
      'geri yükle': 'restore',
      'mikrofon': 'mikrofon',
      'ses gelmiyor': 'ses',
      'yeni telefon': 'cihaz değiştirme',
      'hesabımı sil': 'hesap silme',
      'aile planı': 'aile planı',
      'kurum': 'kurum kodu',
      'çocuk ebeveyn': 'çocuk modu',
      'bildirim': 'bildirimler',
      'gizlilik veri': 'veri ve gizlilik',
    };
    for (final e in topics.entries) {
      expect(searchSss(e.key), isNotEmpty, reason: e.value);
    }
    for (final q in sssListesi) {
      expect(q.soru.trim(), isNotEmpty);
      expect(q.cevap.length, greaterThan(40), reason: q.soru);
    }
  });

  test('answers point at the labels the Profile actually shows', () {
    // Galaxy QA: the FAQ sent people to "Kurum koduyla katıl" and "Çocuk modu",
    // which the Profile no longer has (it shows "Okul ve kurum" and "Ebeveyn gözetimli mod").
    final all = sssListesi.map((q) => q.cevap).join(' ');
    expect(all, isNot(contains('Kurum koduyla katıl')));
    expect(all, contains('Lisans kodu'));
    expect(all, contains('Sınıf koduyla katıl'));
    expect(all, contains('Ebeveyn gözetimli mod'));
    expect(all, isNot(contains('Çocuk modu Profil')));
  });

  test('search needs every word and returns all for an empty query', () {
    expect(searchSss(''), sssListesi);
    expect(searchSss('  '), sssListesi);
    expect(searchSss('mikrofon izin').single.soru, contains('Mikrofon'));
    expect(searchSss('zzzz'), isEmpty);
  });

  test('support mail has version, device, system and uid, nothing else', () {
    const info = SupportInfo(appVersion: '0.1.0 (7)', device: 'Xiaomi 2201117TY', os: 'Android 13 (SDK 33)');
    final uri = supportMailUri(info, 'abc123');
    expect(uri.scheme, 'mailto');
    expect(uri.path, destekEposta);
    final s = uri.toString();
    expect(s, isNot(contains('+')), reason: 'spaces as %20');
    final body = Uri.decodeComponent(s.split('body=').last);
    expect(body, contains('Uygulama sürümü: 0.1.0 (7)'));
    expect(body, contains('Cihaz: Xiaomi 2201117TY'));
    expect(body, contains('Sistem: Android 13 (SDK 33)'));
    expect(body, contains('Kullanıcı kimliği: abc123'));
    expect(Uri.decodeComponent(supportMailUri(info, null).toString()), contains('giriş yok'));
  });

  testWidgets('screen lists questions, filters and shows the empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supportInfoProvider.overrideWith(
            (ref) async => const SupportInfo(appVersion: '1', device: 'x', os: 'y'),
          ),
        ],
        child: const MaterialApp(home: HelpScreen()),
      ),
    );
    expect(find.text('Yardım ve SSS'), findsOneWidget);
    expect(find.text(sssListesi.first.soru), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sss-search')), 'iade');
    await tester.pumpAndSettle();
    expect(find.text('Ücret iadesi alabilir miyim?'), findsOneWidget);
    expect(find.text(sssListesi.first.soru), findsNothing);
    // A single hit opens by itself.
    expect(find.textContaining('48 saat'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sss-search')), 'qqqq');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sss-empty')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sss-write')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('sss-write')), findsOneWidget);
  });
}
