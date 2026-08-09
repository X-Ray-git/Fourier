import 'dart:async';

import 'package:get/get.dart';

import '../common/constants/constants.dart';
import '../models/folo_account_profile.dart';
import '../utils/storage.dart';
import 'account_data_service.dart';
import 'account_session_guard.dart';
import 'folo_auth_service.dart';

/// Folo 单活动账号的凭据、显示资料与切换生命周期。
class AccountService extends GetxController {
  static AccountService get instance => Get.find<AccountService>();

  final isLoggedIn = false.obs;
  final accountRevision = 0.obs;
  final profile = Rxn<FoloAccountProfile>();
  bool _refreshingProfile = false;

  AccountService() {
    _checkLogin();
    unawaited(refreshProfileIfMissing());
  }

  void reload({bool notifyAccountChange = false}) {
    _checkLogin();
    if (notifyAccountChange) accountRevision.value++;
  }

  void _checkLogin() {
    final token =
        GStorage.setting.get(StorageKeys.sessionToken, defaultValue: '')
            as String;
    isLoggedIn.value = token.isNotEmpty;
    profile.value = token.isEmpty
        ? null
        : FoloAccountProfile.fromJson(
            GStorage.setting.get(StorageKeys.foloAccountProfile),
          );
  }

  Future<void> switchSessionToken(
    String sessionToken, {
    FoloAccountProfile? profile,
  }) {
    return applyAccountChange(
      nextSessionToken: sessionToken,
      nextProfile: profile,
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
      nextProfile: null,
      persist: () async {
        await GStorage.setting.delete(StorageKeys.sessionToken);
        await GStorage.setting.delete(StorageKeys.clientId);
        await GStorage.setting.delete(StorageKeys.sessionId);
      },
    );
  }

  Future<T> applyAccountChange<T>({
    required String? nextSessionToken,
    FoloAccountProfile? nextProfile,
    required Future<T> Function() persist,
  }) async {
    final current = sessionToken?.trim() ?? '';
    final next = nextSessionToken?.trim() ?? '';
    final changed = current != next;
    if (!changed) {
      final result = await persist();
      await _persistProfile(next.isEmpty ? null : nextProfile);
      _checkLogin();
      return result;
    }

    final previousProfile = profile.value;
    var nextCredentialsPersisted = false;
    AccountDataService.beginAccountChange();
    try {
      final result = await persist();
      await _persistProfile(next.isEmpty ? null : nextProfile);
      nextCredentialsPersisted = true;
      await AccountDataService.clearForAccountChange();
      return result;
    } catch (error, stackTrace) {
      if (!nextCredentialsPersisted) {
        if (current.isEmpty) {
          await GStorage.setting.delete(StorageKeys.sessionToken);
        } else {
          await GStorage.setting.put(StorageKeys.sessionToken, current);
        }
        await _persistProfile(previousProfile);
      }
      Error.throwWithStackTrace(error, stackTrace);
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

  Future<void> refreshProfileIfMissing() async {
    final token = sessionToken?.trim() ?? '';
    if (token.isEmpty || profile.value != null || _refreshingProfile) return;
    _refreshingProfile = true;
    try {
      final candidate = await FoloAuthService.validateSessionToken(token);
      if ((sessionToken?.trim() ?? '') != token) return;
      await _persistProfile(candidate.profile);
      _checkLogin();
    } catch (_) {
      // Account metadata is optional. Network failures must not block startup.
    } finally {
      _refreshingProfile = false;
    }
  }

  Future<void> _persistProfile(FoloAccountProfile? nextProfile) async {
    if (nextProfile == null) {
      await GStorage.setting.delete(StorageKeys.foloAccountProfile);
      return;
    }
    await GStorage.setting.put(
      StorageKeys.foloAccountProfile,
      nextProfile.toJson(),
    );
  }
}
