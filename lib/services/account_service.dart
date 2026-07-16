import 'package:get/get.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';

/// 账号服务 — Token 存取 + 登录状态
class AccountService extends GetxController {
  static AccountService get instance => Get.find<AccountService>();

  final isLoggedIn = false.obs;

  AccountService() {
    _checkLogin();
  }

  void reload() {
    _checkLogin();
  }

  void _checkLogin() {
    final token =
        GStorage.setting.get(StorageKeys.sessionToken, defaultValue: '')
            as String;
    GStorage.setting.delete(StorageKeys.clientId);
    GStorage.setting.delete(StorageKeys.sessionId);
    isLoggedIn.value = token.isNotEmpty;
  }

  void saveSessionToken(String sessionToken) {
    GStorage.setting.put(StorageKeys.sessionToken, sessionToken);
    GStorage.setting.delete(StorageKeys.clientId);
    GStorage.setting.delete(StorageKeys.sessionId);
    isLoggedIn.value = true;
  }

  void clearTokens() {
    GStorage.setting.delete(StorageKeys.sessionToken);
    GStorage.setting.delete(StorageKeys.clientId);
    GStorage.setting.delete(StorageKeys.sessionId);
    isLoggedIn.value = false;
  }

  String? get sessionToken =>
      GStorage.setting.get(StorageKeys.sessionToken) as String?;
}
