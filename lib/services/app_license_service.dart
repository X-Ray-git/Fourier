import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppLicenseRecord {
  const AppLicenseRecord({required this.packageName, required this.text});

  final String packageName;
  final String text;
}

class AppLicenseService {
  AppLicenseService._();

  static const _licenseAssets = <(List<String>, String)>[
    (<String>['Fourier', 'Folo'], 'LICENSE'),
    (<String>['Fourier third-party notices'], 'THIRD_PARTY_NOTICES.md'),
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

  /// Builds a package-oriented catalog from Flutter's shared license registry.
  /// Multiple entries for one package are retained without duplicating text.
  static Future<List<AppLicenseRecord>> loadCatalog() async {
    final textsByPackage = <String, LinkedHashSet<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs
          .map((paragraph) {
            final indent = '  ' * paragraph.indent;
            return '$indent${paragraph.text}';
          })
          .join('\n\n')
          .trim();
      if (text.isEmpty) continue;
      for (final package in entry.packages) {
        final name = package.trim();
        if (name.isEmpty) continue;
        textsByPackage.putIfAbsent(name, LinkedHashSet.new).add(text);
      }
    }

    final records = textsByPackage.entries
        .map(
          (entry) => AppLicenseRecord(
            packageName: entry.key,
            text: entry.value.join('\n\n---\n\n'),
          ),
        )
        .toList(growable: false);
    records.sort((a, b) {
      if (a.packageName == 'Fourier') return -1;
      if (b.packageName == 'Fourier') return 1;
      return a.packageName.toLowerCase().compareTo(b.packageName.toLowerCase());
    });
    return records;
  }
}
