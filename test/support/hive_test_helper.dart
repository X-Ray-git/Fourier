import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:fourier/utils/storage.dart';

/// 测试用 Hive 基础设施：把 path_provider 指到临时目录并初始化 [GStorage]。
class HiveTestHelper {
  static Directory? _dir;

  static Future<void> setUp() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _dir = await Directory.systemTemp.createTemp('fourier_hive_test_');
    PathProviderPlatform.instance = _FakePathProvider(_dir!.path);
    await GStorage.init();
  }

  static Future<void> tearDown() async {
    await GStorage.close();
    if (_dir != null) {
      try {
        await _dir!.delete(recursive: true);
      } catch (_) {}
      _dir = null;
    }
  }
}

class _FakePathProvider extends PathProviderPlatform {
  final String _base;

  _FakePathProvider(this._base);

  @override
  Future<String?> getApplicationDocumentsPath() async => _base;

  @override
  Future<String?> getApplicationSupportPath() async => _base;

  @override
  Future<String?> getTemporaryPath() async => _base;
}
