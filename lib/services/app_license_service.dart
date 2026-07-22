import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppLicenseService {
  AppLicenseService._();

  static const _licenseAssets = <(List<String>, String)>[
    (<String>['Auto Folo', 'Folo'], 'LICENSE'),
    (<String>['Auto Folo third-party notices'], 'THIRD_PARTY_NOTICES.md'),
    (<String>['PiliPlus'], 'third_party/licenses/GPL-3.0.txt'),
    (<String>['Flutter'], 'third_party/licenses/BSD-3-Clause-Flutter.txt'),
    (
      <String>['interactiveviewer_gallery'],
      'third_party/licenses/MIT-interactiveviewer_gallery.txt',
    ),
    (
      <String>['liquid_glass_widgets'],
      'third_party/licenses/MIT-liquid_glass_widgets.txt',
    ),
    (
      <String>['liquid_glass_renderer'],
      'third_party/licenses/MIT-liquid_glass_renderer.txt',
    ),
  ];

  static void register() {
    LicenseRegistry.addLicense(() async* {
      for (final (packages, assetPath) in _licenseAssets) {
        final text = await rootBundle.loadString(assetPath);
        yield LicenseEntryWithLineBreaks(packages, text);
      }
    });
  }
}
