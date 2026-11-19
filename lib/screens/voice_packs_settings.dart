import 'package:flutter/material.dart';

import '../services/voice_library.dart';
import '../theme.dart';

String formatMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB'.replaceAll('.', ',');
}

/// Profile settings block: the course audio downloaded on Wi-Fi
/// (docs/ses.md), with its size and a way to delete it.
class VoicePacksSettings extends StatefulWidget {
  const VoicePacksSettings({super.key, this.library});

  /// Injected in tests; the app uses [VoiceLibrary.instance].
  final VoiceLibrary? library;

  @override
  State<VoicePacksSettings> createState() => _VoicePacksSettingsState();
}

class _VoicePacksSettingsState extends State<VoicePacksSettings> {
  VoiceLibrary get _lib => widget.library ?? VoiceLibrary.instance;

  @override
  void initState() {
    super.initState();
    _lib.init();
  }

  String _subtitle(VoiceDownloadState s) {
    final total = formatMb(s.totalBytes);
    if (s.complete) return 'Hepsi indirildi · $total';
    final done = '${formatMb(s.downloadedBytes)} / $total';
    if (!s.enabled) return s.downloadedBytes > 0 ? '$done indirildi' : 'Toplam $total · telefonun sesi okur';
    if (s.running) return 'İndiriliyor · $done';
    if (s.waitingForWifi) return 'Wi-Fi bekleniyor · $done';
    return done;
  }

  Future<void> _confirmDelete(VoiceDownloadState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('İndirilen sesler silinsin mi?'),
        content: Text(
          '${formatMb(s.downloadedBytes)} yer açılır. Bu cümleleri telefonun sesi okur; '
          'istediğinde yeniden indirebilirsin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await _lib.deleteAll();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _lib.state,
      builder: (context, s, _) {
        if (s.totalBytes == 0) return const SizedBox.shrink();
        final card = TapCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('voice-packs-switch'),
                secondary: Icon(Icons.download_for_offline_rounded, color: Brand.primary),
                title: const Text(
                  'Ses paketlerini indir (Wi-Fi)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_subtitle(s)),
                value: s.enabled,
                onChanged: _lib.setEnabled,
              ),
              if (s.running && s.totalBytes > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: LinearProgressIndicator(value: s.downloadedBytes / s.totalBytes),
                ),
              if (s.downloadedBytes > 0)
                ListTile(
                  key: const ValueKey('voice-packs-delete'),
                  leading: Icon(Icons.delete_outline_rounded, color: Brand.primary),
                  title: const Text('İndirilen sesleri sil', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(formatMb(s.downloadedBytes)),
                  onTap: () => _confirmDelete(s),
                ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ses', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            card,
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
