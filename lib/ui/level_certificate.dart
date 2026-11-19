import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/level_report.dart';
import '../screens/onboarding_screen.dart' show LingoraLogo;
import '../theme.dart';

/// Logical size of the certificate (4:5, Instagram and LinkedIn friendly);
/// rendered at 3× it is 1080 × 1350 pixels.
const certificateSize = Size(360, 450);
const certificatePixelRatio = 3.0;

/// The shareable Seviye Karnesi card: name, estimated level, date, the
/// Çenebaz mark and a footnote that it is not an official certificate.
/// Colours are fixed (not the theme's) so every share looks the same.
class LevelCertificate extends StatelessWidget {
  const LevelCertificate({super.key, required this.name, required this.report, this.kid = false});

  final String name;
  final LevelReport report;

  /// Çocuk modu: Pofuduk instead of Çaycı Dayı's brand mark.
  final bool kid;

  static const _deep = Color(0xFF2B1B6E);
  static const _violet = Color(0xFF6C4CF1);
  static const _gold = Color(0xFFF5B83D);
  static const _paper = Color(0xFFFFFBF3);

  @override
  Widget build(BuildContext context) {
    final level = report.overall;
    final skills = [
      for (final s in LevelSkill.values)
        if (report.skills[s] case final sc?) (s, sc),
    ];
    return SizedBox.fromSize(
      size: certificateSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_deep, _violet],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _gold, width: 3),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: DefaultTextStyle(
                style: const TextStyle(color: _deep, fontFamilyFallback: ['Roboto']),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: kid
                              ? Image.asset('assets/mascot/pofuduk_selam.png', semanticLabel: 'Pofuduk')
                              : const ClipRRect(
                                  borderRadius: BorderRadius.all(Radius.circular(10)),
                                  child: LingoraLogo(size: 40),
                                ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Çenebaz',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _violet),
                          ),
                        ),
                        const Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'SEVİYE KARNESİ',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('İngilizce tahmini seviye', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 116,
                      height: 116,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: [Color(0xFFFFE08A), _gold]),
                        border: Border.all(color: _deep, width: 3),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            level?.code ?? 'A1',
                            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, height: 1),
                          ),
                          Text(
                            level?.name ?? 'yolunda',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (s, sc) in skills)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _violet.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${s.title} ${levelLabel(sc.level)}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      longDateTr(report.date),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: Color(0x332B1B6E)),
                    const SizedBox(height: 6),
                    const Text(
                      'Çenebaz ile ölçüldü. Uygulama içi kısa bir uyarlamalı testin tahminidir; '
                      'resmî bir dil sertifikası değildir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF5A4E86), height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PNG bytes of the widget under [boundaryKey] (a [RepaintBoundary]).
Future<List<int>> certificatePng(GlobalKey boundaryKey) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: certificatePixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Writes the certificate to a temporary PNG and opens the share sheet.
Future<void> shareCertificate(GlobalKey boundaryKey, LevelReport report, {Rect? origin}) => sharePng(
  boundaryKey,
  fileName: 'cenebaz_seviye_${report.day}.png',
  text: 'Çenebaz ile ölçülen tahmini İngilizce seviyem: ${levelLabel(report.overall)}',
  origin: origin,
);

/// Renders the [RepaintBoundary] under [boundaryKey] to a temporary PNG and
/// opens the system share sheet (Instagram, WhatsApp…) with it and [text].
Future<void> sharePng(
  GlobalKey boundaryKey, {
  required String fileName,
  required String text,
  Rect? origin,
}) async {
  final bytes = await certificatePng(boundaryKey);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
      sharePositionOrigin: origin,
    ),
  );
}

/// Full-screen preview of the certificate with a share button.
class CertificateScreen extends StatefulWidget {
  const CertificateScreen({super.key, required this.name, required this.report, required this.kid});
  final String name;
  final LevelReport report;
  final bool kid;

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await shareCertificate(_key, widget.report, origin: origin);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Görsel paylaşılamadı.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sertifika')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _key,
                    child: LevelCertificate(name: widget.name, report: widget.report, kid: widget.kid),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'LinkedIn, Instagram ya da istediğin yerde paylaş. Bu bir tahmindir, resmî sertifika değildir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('certificate-share'),
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Görseli paylaş'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
