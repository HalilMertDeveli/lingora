import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/league.dart' show flagEmoji;
import '../services/league_remote.dart';
import '../theme.dart';

/// Countries offered for the Dünya Ligi flag (ISO 3166 alpha-2, Turkish
/// names). The phone's region is used even when it is not listed.
const leagueCountries = {
  'TR': 'Türkiye',
  'AZ': 'Azerbaycan',
  'CY': 'Kıbrıs',
  'DE': 'Almanya',
  'NL': 'Hollanda',
  'AT': 'Avusturya',
  'BE': 'Belçika',
  'FR': 'Fransa',
  'GB': 'Birleşik Krallık',
  'IE': 'İrlanda',
  'CH': 'İsviçre',
  'SE': 'İsveç',
  'NO': 'Norveç',
  'DK': 'Danimarka',
  'FI': 'Finlandiya',
  'IT': 'İtalya',
  'ES': 'İspanya',
  'PT': 'Portekiz',
  'GR': 'Yunanistan',
  'PL': 'Polonya',
  'CZ': 'Çekya',
  'HU': 'Macaristan',
  'RO': 'Romanya',
  'BG': 'Bulgaristan',
  'RS': 'Sırbistan',
  'BA': 'Bosna-Hersek',
  'MK': 'Kuzey Makedonya',
  'AL': 'Arnavutluk',
  'XK': 'Kosova',
  'UA': 'Ukrayna',
  'RU': 'Rusya',
  'GE': 'Gürcistan',
  'KZ': 'Kazakistan',
  'UZ': 'Özbekistan',
  'KG': 'Kırgızistan',
  'TM': 'Türkmenistan',
  'IR': 'İran',
  'IQ': 'Irak',
  'SY': 'Suriye',
  'LB': 'Lübnan',
  'JO': 'Ürdün',
  'SA': 'Suudi Arabistan',
  'AE': 'Birleşik Arap Emirlikleri',
  'QA': 'Katar',
  'KW': 'Kuveyt',
  'EG': 'Mısır',
  'LY': 'Libya',
  'TN': 'Tunus',
  'DZ': 'Cezayir',
  'MA': 'Fas',
  'PK': 'Pakistan',
  'AF': 'Afganistan',
  'IN': 'Hindistan',
  'CN': 'Çin',
  'JP': 'Japonya',
  'KR': 'Güney Kore',
  'ID': 'Endonezya',
  'MY': 'Malezya',
  'US': 'ABD',
  'CA': 'Kanada',
  'BR': 'Brezilya',
  'MX': 'Meksika',
  'AR': 'Arjantin',
  'AU': 'Avustralya',
  'NZ': 'Yeni Zelanda',
  'ZA': 'Güney Afrika',
  'NG': 'Nijerya',
};

/// "🇹🇷 Türkiye", or the bare code for an unlisted region.
String countryLabel(String? code) {
  if (code == null) return 'Seçilmedi';
  return '${flagEmoji(code)} ${leagueCountries[code] ?? code}'.trim();
}

/// Profil row: the flag shown next to the learner in the Dünya Ligi.
class CountryButton extends ConsumerWidget {
  const CountryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(leagueCountryProvider);
    return TextButton.icon(
      key: const ValueKey('profile-country'),
      onPressed: () => _pick(context, ref, code),
      icon: const Icon(Icons.public_rounded, size: 18),
      label: Text('Ligde ülkem: ${countryLabel(code)}'),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, String? current) async {
    final device = deviceCountry();
    final codes = [
      if (device != null && !leagueCountries.containsKey(device)) device,
      ...leagueCountries.keys,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Dünya Ligi’nde adının yanında bu ülkenin bayrağı görünür.',
                style: TextStyle(color: Brand.muted),
              ),
            ),
            for (final code in codes)
              ListTile(
                key: ValueKey('country-$code'),
                leading: Text(flagEmoji(code), style: const TextStyle(fontSize: 24)),
                title: Text(leagueCountries[code] ?? code),
                trailing: code == current ? Icon(Icons.check_rounded, color: Brand.primary) : null,
                onTap: () => Navigator.pop(c, code),
              ),
          ],
        ),
      ),
    );
    if (picked != null) ref.read(leagueCountryProvider.notifier).set(picked);
  }
}
