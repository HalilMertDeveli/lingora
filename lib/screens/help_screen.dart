import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/sss.dart';
import '../services/firebase/firebase_providers.dart';
import '../theme.dart';

/// Profil > Yardım ve SSS: searchable questions (lib/data/sss.dart) and a
/// "Bize yaz" e-mail with the details support needs. Nothing is sent by
/// itself: the mail app opens with a draft the user can read and change.
Future<void> openHelp(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

/// Lower-case without Turkish accents, so "iptal", "İPTAL" and "ıptal" match.
String sssNormalize(String s) {
  const from = 'çğıöşüâîû';
  const to = 'cgiosuaiu';
  final lower = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// The questions matching every word of [query] (in the question, answer,
/// group or tags). An empty query returns all of them.
List<Sss> searchSss(String query, [List<Sss> all = sssListesi]) {
  final words = sssNormalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return all;
  return [
    for (final q in all)
      if (words.every(sssNormalize('${q.baslik} ${q.soru} ${q.cevap} ${q.etiketler.join(' ')}').contains)) q,
  ];
}

/// What the support e-mail says about the phone. No logs, no progress.
class SupportInfo {
  const SupportInfo({required this.appVersion, required this.device, required this.os});
  final String appVersion;
  final String device;
  final String os;
}

final supportInfoProvider = FutureProvider<SupportInfo>((ref) async {
  var app = 'bilinmiyor';
  var device = 'bilinmiyor';
  var os = defaultTargetPlatform.name;
  try {
    final p = await PackageInfo.fromPlatform();
    app = '${p.version} (${p.buildNumber})';
  } catch (_) {}
  try {
    final info = DeviceInfoPlugin();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      device = '${a.manufacturer} ${a.model}';
      os = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await info.iosInfo;
      device = i.utsname.machine;
      os = '${i.systemName} ${i.systemVersion}';
    }
  } catch (_) {}
  return SupportInfo(appVersion: app, device: device, os: os);
});

/// The `mailto:` link of "Bize yaz". Spaces stay %20 (some mail apps show
/// `+` literally).
Uri supportMailUri(SupportInfo info, String? uid) {
  final body = [
    'Merhaba Dilmaç ekibi,',
    '',
    '(Sorununu buraya yaz. Ekran görüntüsü eklemek çok yardımcı olur.)',
    '',
    '',
    '---',
    'Bu bilgiler sorunu bulmamıza yardım eder, silebilirsin:',
    'Uygulama sürümü: ${info.appVersion}',
    'Cihaz: ${info.device}',
    'Sistem: ${info.os}',
    'Kullanıcı kimliği: ${uid ?? 'giriş yok'}',
  ].join('\n');
  String enc(String s) => Uri.encodeComponent(s);
  return Uri.parse('mailto:$destekEposta?subject=${enc('Dilmaç destek')}&body=${enc(body)}');
}

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    final info = await ref.read(supportInfoProvider.future);
    final uri = supportMailUri(info, ref.read(currentUidProvider));
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-posta uygulaması açılamadı. Bize $destekEposta adresinden yazabilirsin.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final results = searchSss(_query);
    return Scaffold(
      appBar: AppBar(title: const Text('Yardım ve SSS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('sss-search'),
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Ara: iptal, mikrofon, ses…',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Bu konuda bir cevap bulamadık. Aşağıdan bize yazabilirsin.',
                key: const ValueKey('sss-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.muted),
              ),
            ),
          for (final (i, q) in results.indexed) ...[
            if (i == 0 || results[i - 1].baslik != q.baslik)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(q.baslik, style: t.titleSmall?.copyWith(color: Brand.muted)),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey('sss-${q.soru}'),
                // Searching opens a single hit right away.
                initiallyExpanded: results.length == 1,
                shape: const Border(),
                title: Text(q.soru, style: t.titleMedium),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [SelectableText(q.cevap, style: t.bodyMedium?.copyWith(height: 1.45))],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Cevabını bulamadın mı?', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'E-posta uygulaman açılır; uygulama sürümü, cihaz modeli ve kullanıcı kimliğin taslağa eklenir. '
            'Göndermeden önce görebilir ve silebilirsin. Kayıt dosyası gönderilmez.',
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('sss-write'),
            onPressed: _write,
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Bize yaz'),
          ),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(destekEposta, style: TextStyle(color: Brand.muted)),
          ),
        ],
      ),
    );
  }
}
