import 'package:get/get.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';
import 'account_data_service.dart';
import 'account_session_guard.dart';

/// 账号服务 — Token 存取 + 登录状态
class AccountService extends GetxController {
  static AccountService get instance => Get.find<AccountService>();

  final isLoggedIn = false.obs;
  final accountRevision = 0.obs;

  AccountService() {
    _checkLogin();
  }

  void reload({bool notifyAccountChange = false}) {
    _checkLogin();
    if (notifyAccountChange) accountRevision.value++;
  }

  void _checkLogin() {
    final token =
        GStorage.setting.get(StorageKeys.sessionToken, defaultValue: '')
            as String;
    GStorage.setting.delete(StorageKeys.clientId);
    GStorage.setting.delete(StorageKeys.sessionId);
    isLoggedIn.value = token.isNotEmpty;
  }

  Future<void> switchSessionToken(String sessionToken) {
    return applyAccountChange(
      nextSessionToken: sessionToken,
      persist: () async {
        await GStorage.setting.put(StorageKeys.sessionToken, sessionToken);
        await GStorage.setting.delete(StorageKeys.clientId);
        await GStorage.setting.delete(StorageKeys.sessionId);
      },
    );
  }

  Future<void> signOutLocally() {
    return applyAccountChange(
      nextSessionToken: null,
      persist: () async {
        await GStorage.setting.delete(StorageKeys.sessionToken);
        await GStorage.setting.delete(StorageKeys.clientId);
        await GStorage.setting.delete(StorageKeys.sessionId);
      },
    );
  }

  Future<T> applyAccountChange<T>({
    required String? nextSessionToken,
    required Future<T> Function() persist,
  }) async {
    final current = sessionToken?.trim() ?? '';
    final next = nextSessionToken?.trim() ?? '';
    final changed = current != next;
    if (!changed) {
      final result = await persist();
      _checkLogin();
      return result;
    }

    try {
      await AccountDataService.clearForAccountChange();
      return await persist();
    } finally {
      // Invalidate again so requests started during the cleanup window with
      // the previous token cannot write into the next account's state.
      AccountSessionGuard.finishAccountChange();
      // Even a rare cleanup/storage failure may leave a partial reset. Re-read
      // the persisted token and force account-aware controllers to reload.
      _checkLogin();
      accountRevision.value++;
    }
  }

  String? get sessionToken =>
      GStorage.setting.get(StorageKeys.sessionToken) as String?;
}
