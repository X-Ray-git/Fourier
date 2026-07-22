import 'package:autofolo/services/app_license_service.dart';
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
        'Auto Folo',
        'Folo',
        'Auto Folo third-party notices',
        'PiliPlus',
        'Flutter',
        'interactiveviewer_gallery',
        'liquid_glass_widgets',
        'liquid_glass_renderer',
      }),
    );
  });
}
