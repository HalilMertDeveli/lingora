import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public privacy policy (Google Play requires a link inside the app too).
/// Publish docs/magaza/gizlilik-politikasi.md at this address, or build with
/// `--dart-define=LINGORA_PRIVACY_URL=https://…`.
const privacyPolicyUrl = String.fromEnvironment(
  'LINGORA_PRIVACY_URL',
  defaultValue: 'https://dilbaz-3392e.web.app/gizlilik',
);

/// Opens [url] in the browser; shows a Turkish message if that fails.
Future<void> openExternalLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Bağlantı açılamadı. Tarayıcıda şu adresi aç: $url')));
  }
}
