import 'package:fourier/services/app_license_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers bundled project and third-party licenses', () async {
    AppLicenseService.register();

    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((entry) => entry.packages).toSet();

    expect(
      packages,
      containsAll(<String>{
        'Fourier',
        'Folo',
        'Fourier third-party notices',
        'PiliPlus',
        'Flutter',
        'interactiveviewer_gallery',
        'liquid_glass_widgets',
        'liquid_glass_renderer',
      }),
    );
  });

  test('builds a sorted package catalog without duplicate text', () async {
    final records = await AppLicenseService.loadCatalog();

    expect(records, isNotEmpty);
    expect(records.first.packageName, 'Fourier');
    expect(records.map((record) => record.packageName), contains('PiliPlus'));
    expect(records.every((record) => record.text.trim().isNotEmpty), isTrue);
  });
}
