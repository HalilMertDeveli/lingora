import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/legal_links.dart';

void main() {
  // The app links to pages published from hosting/sayfalar (cleanUrls: /x -> x.html).
  for (final (name, url) in [('privacy', privacyPolicyUrl), ('account deletion', accountDeletionUrl)]) {
    test('$name link points at a page in hosting/sayfalar', () {
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'dilbaz-3392e.web.app');
      expect(File('hosting/sayfalar${uri.path}.html').existsSync(), isTrue, reason: uri.path);
    });
  }
}
