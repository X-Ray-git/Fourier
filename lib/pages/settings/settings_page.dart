import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';

import '../../common/constants/constants.dart';
import '../../common/constants/macos_layout_metrics.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../models/folo_account_profile.dart';
import '../../services/account_service.dart';
import '../../services/android_haptics_service.dart';
import '../../services/app_version_service.dart';
import '../../services/article_filter_service.dart';
import '../../services/llm_config.dart';
import '../../services/settings_backup_service.dart';
import '../../services/folo_auth_service.dart';
import '../../services/summary_service.dart';
import '../../services/translation_service.dart';
import '../../router/app_pages.dart';
import '../../utils/security_utils.dart';
import '../../utils/storage.dart';
import '../main/main_controller.dart';
import 'task_center_page.dart';
import 'widgets/mobile_settings_chrome.dart';

/// 设置页 — Token 输入
class SettingsPage extends StatefulWidget {
  final bool showAppBar;

  const SettingsPage({super.key, this.showAppBar = true});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AccountService _accountService;

  final _tokenController = TextEditingController();
  final _deepseekApiKeyController = TextEditingController();
  final _readSyncWindowDaysController = TextEditingController();
  final _articleContentMaxWidthController = TextEditingController();
  final _macosMaxFlingVelocityController = TextEditingController();
  final _readSyncWindowDaysFocusNode = FocusNode();
  final _articleContentMaxWidthFocusNode = FocusNode();
  final _macosMaxFlingVelocityFocusNode = FocusNode();
  final _macSettingsScrollController = ScrollController();
  final _macAuthKey = GlobalKey();
  final _macPreferencesKey = GlobalKey();
  final _macAiKey = GlobalKey();
  final _macPromptKey = GlobalKey();
  final _macShortcutsKey = GlobalKey();
  final _macAboutKey = GlobalKey();
  bool _obscureToken = true;
  bool _obscureDeepseekKey = true;
  bool _testingCredentials = false;
  bool _changingAccount = false;
  bool _loggingIn = false;
  late String _appearanceMode;
  late String _badgeStrategy;
  late int _autoRetryMaxCount;
  late bool _androidHapticsEnabled;

  void _showOpenSourceLicenses() {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppVersionService.version,
      applicationLegalese: 'Licensed under AGPL-3.0-only.',
    );
  }

  @override
  void initState() {
    super.initState();
    _accountService = AccountService.instance;
    unawaited(_accountService.refreshProfileIfMissing());

    _loadPersistedSettings();
    _readSyncWindowDaysFocusNode.addListener(_onReadSyncWindowFocusChanged);
    _articleContentMaxWidthFocusNode.addListener(
      _onArticleContentWidthFocusChanged,
    );
    _macosMaxFlingVelocityFocusNode.addListener(
      _onMacosFlingVelocityFocusChanged,
    );
  }

  void _loadPersistedSettings() {
    _tokenController.text = _accountService.sessionToken ?? '';
    _deepseekApiKeyController.text = TranslationService.getApiKey() ?? '';
    final readWindowDays = GStorage.setting.get(
      StorageKeys.readSyncWindowDays,
      defaultValue: AppConstants.defaultReadSyncWindowDays,
    );
    _readSyncWindowDaysController.text = readWindowDays.toString();
    final articleContentMaxWidth = GStorage.setting.get(
      StorageKeys.articleContentMaxWidth,
      defaultValue: AppConstants.defaultArticleContentMaxWidth,
    );
    _articleContentMaxWidthController.text = articleContentMaxWidth.toString();
    final macosMaxFlingVelocity = GStorage.setting.get(
      StorageKeys.macosMaxFlingVelocity,
      defaultValue: AppConstants.defaultMacosMaxFlingVelocity,
    );
    _macosMaxFlingVelocityController.text = macosMaxFlingVelocity.toString();
    _appearanceMode = _normalizeAppearanceMode(
      GStorage.setting.get(
        StorageKeys.appearanceMode,
        defaultValue: AppConstants.defaultAppearanceMode,
      ),
    );
    _badgeStrategy = GStorage.setting.get(
      StorageKeys.badgeStrategy,
      defaultValue: 'unread_count',
    );
    _autoRetryMaxCount = GStorage.setting.get(
      'auto_retry_max_count',
      defaultValue: 3,
    );
    _androidHapticsEnabled = AndroidHapticsService.isEnabled;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _deepseekApiKeyController.dispose();
    _readSyncWindowDaysController.dispose();
    _articleContentMaxWidthController.dispose();
    _macosMaxFlingVelocityController.dispose();
    _readSyncWindowDaysFocusNode.dispose();
    _articleContentMaxWidthFocusNode.dispose();
    _macosMaxFlingVelocityFocusNode.dispose();
    _macSettingsScrollController.dispose();
    super.dispose();
  }

  void _onReadSyncWindowFocusChanged() {
    if (!_readSyncWindowDaysFocusNode.hasFocus) {
      unawaited(_saveReadSyncWindowDays());
    }
  }

  void _onArticleContentWidthFocusChanged() {
    if (!_articleContentMaxWidthFocusNode.hasFocus) {
      unawaited(_saveArticleContentMaxWidth());
    }
  }

  void _onMacosFlingVelocityFocusChanged() {
    if (!_macosMaxFlingVelocityFocusNode.hasFocus) {
      unawaited(_saveMacosMaxFlingVelocity());
    }
  }

  Future<bool> _saveCredentials({bool showSuccess = true}) async {
    if (_changingAccount) return false;
    final token = SecurityUtils.normalizeCredential(_tokenController.text);
    final deepseekKey = _deepseekApiKeyController.text.trim();

    if (token.isEmpty) {
      AppFeedback.warning('认证未保存', '请填写 Session Token');
      return false;
    }

    if (!SecurityUtils.isSafeCookieValue(token) ||
        (deepseekKey.isNotEmpty &&
            !SecurityUtils.isSafeHeaderValue(deepseekKey))) {
      AppFeedback.error('认证未保存', '输入格式不合法，请检查是否包含换行或特殊分隔符');
      return false;
    }

    setState(() => _changingAccount = true);
    try {
      final candidate = await FoloAuthService.validateSessionToken(token);
      if (!await _confirmAccountReplacement(candidate)) return false;
      await _accountService.switchSessionToken(
        candidate.sessionToken,
        profile: candidate.profile,
      );
    } catch (error) {
      AppFeedback.error('认证未保存', error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _changingAccount = false);
    }

    if (deepseekKey.isNotEmpty) {
      TranslationService.setApiKey(deepseekKey);
      SummaryService.setApiKey(deepseekKey);
      GStorage.setting.put('deepseek_api_key', deepseekKey);
    } else {
      TranslationService.setApiKey('');
      SummaryService.setApiKey('');
      GStorage.setting.delete('deepseek_api_key');
    }
    if (showSuccess) {
      AppFeedback.success(
        '认证已保存',
        deepseekKey.isEmpty
            ? 'Folo 认证已更新，DeepSeek API Key 已清除'
            : 'Folo 与 DeepSeek 认证已更新',
      );
    }
    return true;
  }

  Future<bool> _confirmAccountReplacement(
    FoloAccountCandidate candidate,
  ) async {
    final currentToken = _accountService.sessionToken?.trim() ?? '';
    if (currentToken.isEmpty || currentToken == candidate.sessionToken) {
      return true;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _SettingsConfirmDialog(
        title: '切换 Folo 账号',
        content:
            '将登录“${candidate.displayName}”。当前账号的本地文章、摘要、翻译、阅读记录、图片缓存和撤销历史会被清理；Prompt、AI 参数和界面偏好会保留。',
        confirmLabel: '清理并切换',
        onCancel: () => Get.back(result: false),
        onConfirm: () => Get.back(result: true),
      ),
    );
    return result == true;
  }

  Future<void> _loginWithBrowser() async {
    if (_changingAccount || (!Platform.isMacOS && !Platform.isAndroid)) {
      return;
    }
    if (Platform.isAndroid) {
      await _loginOnAndroid();
      return;
    }

    setState(() {
      _changingAccount = true;
      _loggingIn = true;
    });
    try {
      final session = await FoloAuthService.startPlatformLogin();
      if (!mounted) {
        await session.cancel();
        return;
      }
      final candidate = await showDialog<FoloAccountCandidate>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BrowserLoginDialog(session: session),
      );
      if (candidate != null && mounted) await _applyLoginCandidate(candidate);
    } catch (error) {
      if (mounted) AppFeedback.error('Folo 登录失败', error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _changingAccount = false;
          _loggingIn = false;
        });
      }
    }
  }

  Future<void> _loginOnAndroid() async {
    setState(() {
      _changingAccount = true;
      _loggingIn = true;
    });
    try {
      final providers = (await FoloAuthService.fetchAuthProviders())
          .where((provider) => provider.id != 'apple')
          .toList(growable: false);
      if (!mounted) return;
      final provider = await showModalBottomSheet<FoloAuthProvider>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => _AndroidLoginProviderSheet(providers: providers),
      );
      if (provider == null || !mounted) return;

      FoloAccountCandidate? candidate;
      if (provider.isCredential) {
        candidate = await showDialog<FoloAccountCandidate>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _AndroidEmailLoginDialog(),
        );
      } else {
        final session = await FoloAuthService.startAndroidSocialLogin(
          providerId: provider.id,
          providerName: provider.name,
        );
        if (!mounted) {
          await session.cancel();
          return;
        }
        candidate = await showDialog<FoloAccountCandidate>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _BrowserLoginDialog(
            session: session,
            providerName: provider.name,
          ),
        );
      }

      if (candidate != null && mounted) await _applyLoginCandidate(candidate);
    } catch (error) {
      if (mounted) AppFeedback.error('Folo 登录失败', error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _changingAccount = false;
          _loggingIn = false;
        });
      }
    }
  }

  Future<void> _applyLoginCandidate(FoloAccountCandidate candidate) async {
    if (!await _confirmAccountReplacement(candidate)) return;
    await _accountService.switchSessionToken(
      candidate.sessionToken,
      profile: candidate.profile,
    );
    _tokenController.text = candidate.sessionToken;
    AppFeedback.success('Folo 登录成功', '已登录 ${candidate.displayName}，正在重建本地内容');
  }

  Future<void> _testCredentials() async {
    if (_testingCredentials) return;
    final token = SecurityUtils.normalizeCredential(_tokenController.text);
    final deepseekKey = _deepseekApiKeyController.text.trim();

    setState(() => _testingCredentials = true);
    late final List<_ConnectionTestResult> results;
    try {
      results = await Future.wait([
        _testFoloConnection(token),
        _testDeepSeekConnection(deepseekKey),
      ]);
    } finally {
      if (mounted) setState(() => _testingCredentials = false);
    }
    if (!mounted) return;

    final folo = results[0];
    final deepseek = results[1];
    final message = 'Folo：${folo.message}；DeepSeek：${deepseek.message}';
    if (folo.ok && deepseek.ok) {
      AppFeedback.success('连接测试通过', message);
    } else {
      AppFeedback.error('连接测试未全部通过', message);
    }
  }

  Future<_ConnectionTestResult> _testFoloConnection(String token) async {
    if (token.isEmpty) {
      return const _ConnectionTestResult(false, 'Session Token 未填写');
    }
    if (!SecurityUtils.isSafeCookieValue(token)) {
      return const _ConnectionTestResult(false, '凭据格式不合法');
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        headers: {
          'Accept': 'application/json',
          'Origin': 'https://app.folo.is',
          'Cookie':
              '__Secure-better-auth.session_token=$token; '
              'better-auth.last_used_login_method=google',
        },
      ),
    );
    try {
      final response = await dio.get(ApiConstants.subscriptions);
      final data = response.data;
      final body = data is Map ? Map<String, dynamic>.from(data) : null;
      if (response.statusCode == 200 &&
          body != null &&
          (body['code'] == 0 || body['code'] == '0')) {
        return const _ConnectionTestResult(true, '正常');
      }
      return const _ConnectionTestResult(false, '服务拒绝了当前凭据');
    } on DioException catch (error) {
      return _connectionFailure(error);
    } catch (_) {
      return const _ConnectionTestResult(false, '接口返回内容异常');
    } finally {
      dio.close(force: true);
    }
  }

  Future<_ConnectionTestResult> _testDeepSeekConnection(String apiKey) async {
    if (apiKey.isEmpty) {
      return const _ConnectionTestResult(true, '未配置，已跳过');
    }
    if (!SecurityUtils.isSafeHeaderValue(apiKey)) {
      return const _ConnectionTestResult(false, 'API Key 格式不合法');
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.deepseek.com',
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );
    try {
      final response = await dio.get('/models');
      final data = response.data;
      final body = data is Map ? Map<String, dynamic>.from(data) : null;
      if (response.statusCode == 200 && body?['data'] is List) {
        return const _ConnectionTestResult(true, '正常');
      }
      return const _ConnectionTestResult(false, '接口返回内容异常');
    } on DioException catch (error) {
      return _connectionFailure(error);
    } catch (_) {
      return const _ConnectionTestResult(false, '接口返回内容异常');
    } finally {
      dio.close(force: true);
    }
  }

  _ConnectionTestResult _connectionFailure(DioException error) {
    if (error.response?.statusCode == 401 ||
        error.response?.statusCode == 403) {
      return const _ConnectionTestResult(false, '认证失败');
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const _ConnectionTestResult(false, '连接超时');
    }
    return const _ConnectionTestResult(false, '网络连接失败');
  }

  Future<void> _saveReadSyncWindowDays() async {
    final previous =
        GStorage.setting.get(
              StorageKeys.readSyncWindowDays,
              defaultValue: AppConstants.defaultReadSyncWindowDays,
            )
            as int;
    final readWindowDays = int.tryParse(
      _readSyncWindowDaysController.text.trim(),
    );
    if (readWindowDays == null || readWindowDays < 1) {
      _readSyncWindowDaysController.text = previous.toString();
      AppFeedback.warning('已恢复原值', '已读拉取窗口请填写大于 0 的天数');
      return;
    }
    if (readWindowDays == previous) return;
    try {
      await GStorage.setting.put(
        StorageKeys.readSyncWindowDays,
        readWindowDays,
      );
    } catch (_) {
      _readSyncWindowDaysController.text = previous.toString();
      AppFeedback.error('设置保存失败', '已读拉取窗口已恢复原值');
    }
  }

  Future<void> _saveArticleContentMaxWidth() async {
    final previous =
        GStorage.setting.get(
              StorageKeys.articleContentMaxWidth,
              defaultValue: AppConstants.defaultArticleContentMaxWidth,
            )
            as int;
    final articleContentMaxWidth = int.tryParse(
      _articleContentMaxWidthController.text.trim(),
    );
    if (articleContentMaxWidth == null ||
        articleContentMaxWidth < 480 ||
        articleContentMaxWidth > 1200) {
      _articleContentMaxWidthController.text = previous.toString();
      AppFeedback.warning('已恢复原值', '正文最大宽度请填写 480～1200 之间的整数');
      return;
    }
    if (articleContentMaxWidth == previous) return;
    try {
      await GStorage.setting.put(
        StorageKeys.articleContentMaxWidth,
        articleContentMaxWidth,
      );
    } catch (_) {
      _articleContentMaxWidthController.text = previous.toString();
      AppFeedback.error('设置保存失败', '正文最大宽度已恢复原值');
    }
  }

  Future<void> _saveMacosMaxFlingVelocity() async {
    final previous =
        GStorage.setting.get(
              StorageKeys.macosMaxFlingVelocity,
              defaultValue: AppConstants.defaultMacosMaxFlingVelocity,
            )
            as int;
    final macosMaxFlingVelocity = int.tryParse(
      _macosMaxFlingVelocityController.text.trim(),
    );
    if (macosMaxFlingVelocity == null ||
        macosMaxFlingVelocity <
            NoOverscrollIndicatorBehavior.macosMinFlingVelocity ||
        macosMaxFlingVelocity >
            NoOverscrollIndicatorBehavior.macosMaxAllowedFlingVelocity) {
      _macosMaxFlingVelocityController.text = previous.toString();
      AppFeedback.warning('已恢复原值', 'macOS 滚动惯性上限请填写 1000～8000 之间的整数');
      return;
    }
    if (macosMaxFlingVelocity == previous) return;
    try {
      await GStorage.setting.put(
        StorageKeys.macosMaxFlingVelocity,
        macosMaxFlingVelocity,
      );
    } catch (_) {
      _macosMaxFlingVelocityController.text = previous.toString();
      AppFeedback.error('设置保存失败', 'macOS 滚动惯性上限已恢复原值');
    }
  }

  void _setBadgeStrategy(String value) {
    setState(() => _badgeStrategy = value);
    GStorage.setting.put(StorageKeys.badgeStrategy, value);
  }

  void _setAutoRetryMaxCount(int value) {
    setState(() => _autoRetryMaxCount = value);
    GStorage.setting.put('auto_retry_max_count', value);
  }

  void _setAppearanceMode(String value) {
    final normalized = _normalizeAppearanceMode(value);
    setState(() => _appearanceMode = normalized);
    GStorage.setting.put(StorageKeys.appearanceMode, normalized);
  }

  static String _normalizeAppearanceMode(Object? value) {
    return switch (value) {
      'light' || 'dark' || 'system' => value as String,
      _ => AppConstants.defaultAppearanceMode,
    };
  }

  static String _appearanceModeLabel(String value) {
    return switch (value) {
      'light' => '浅色',
      'dark' => '深色',
      _ => '跟随系统',
    };
  }

  Future<void> _signOutLocally() async {
    if (_changingAccount || !_accountService.isLoggedIn.value) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _SettingsConfirmDialog(
        title: '退出 Folo 账号',
        content:
            '将从 Fourier 移除当前登录并清理本地文章、摘要、翻译、阅读记录、图片缓存和撤销历史。Prompt、AI 参数、DeepSeek Key 和界面偏好会保留；浏览器中的 Folo 登录不会退出。',
        confirmLabel: '退出并清理',
        onCancel: () => Get.back(result: false),
        onConfirm: () => Get.back(result: true),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _changingAccount = true);
    try {
      await _accountService.signOutLocally();
      _tokenController.clear();
      AppFeedback.info('已退出 Folo', '普通设置与 AI 配置均已保留');
    } catch (error) {
      AppFeedback.error('退出失败', error.toString());
    } finally {
      if (mounted) setState(() => _changingAccount = false);
    }
  }

  Future<bool> _confirmSettingsExport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        const content =
            '导出的 JSON 会包含 Folo 登录凭据、DeepSeek API Key、Prompt 和订阅源偏好。'
            '请只保存或发送给你信任的位置。';
        return _SettingsConfirmDialog(
          title: '导出配置',
          content: content,
          confirmLabel: '导出到剪贴板',
          onCancel: () => Get.back(result: false),
          onConfirm: () => Get.back(result: true),
        );
      },
    );
    return result == true;
  }

  Future<bool> _confirmSettingsImport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        const content =
            '将从剪贴板读取 Fourier 配置 JSON，并覆盖当前已保存的账号、AI、Prompt 和订阅源偏好设置。'
            '文章缓存、已读历史、摘要和翻译结果不会被导入。';
        return _SettingsConfirmDialog(
          title: '导入配置',
          content: content,
          confirmLabel: '从剪贴板导入',
          onCancel: () => Get.back(result: false),
          onConfirm: () => Get.back(result: true),
        );
      },
    );
    return result == true;
  }

  Future<void> _exportSettingsToClipboard() async {
    if (!await _confirmSettingsExport()) return;
    try {
      final summary = await SettingsBackupService.exportToClipboard();
      AppFeedback.success('配置已导出', '已复制 ${summary.settingCount} 项设置到剪贴板');
    } catch (e) {
      AppFeedback.error('导出失败', e.toString());
    }
  }

  Future<void> _importSettingsFromClipboard() async {
    if (!await _confirmSettingsImport()) return;
    try {
      final payload = await SettingsBackupService.readFromClipboard();
      final nextToken = payload.sessionToken?.trim() ?? '';
      final candidate = nextToken.isEmpty
          ? null
          : await FoloAuthService.validateSessionToken(nextToken);
      final summary = await _accountService.applyAccountChange(
        nextSessionToken: nextToken.isEmpty ? null : nextToken,
        nextProfile: candidate?.profile,
        persist: () async {
          await SettingsBackupService.applyPayload(payload);
          return payload.summary;
        },
      );
      setState(_loadPersistedSettings);
      AppFeedback.success(
        '配置已导入',
        '已写入 ${summary.settingCount} 项设置，其中 ${summary.feedPreferenceCount} 项订阅源偏好',
      );
    } catch (e) {
      AppFeedback.error('导入失败', e.toString());
    }
  }

  void _openTaskCenter() {
    if (!Platform.isMacOS) {
      Get.toNamed(Routes.taskCenter);
      return;
    }
    const dialogRadius = 28.0;
    const closeButtonSize = 34.0;
    const closeButtonInset = dialogRadius - closeButtonSize / 2;
    final overlayTint = Theme.of(context).colorScheme.surface;
    final sidebarWidth = Get.isRegistered<MainController>()
        ? MacOSLayoutMetrics.sidebarExpandedWidth
        : 0.0;
    showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭后台任务',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: sidebarWidth,
              top: 0,
              right: 0,
              bottom: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: ColoredBox(color: overlayTint.withValues(alpha: 0.62)),
                ),
              ),
            ),
            Positioned(
              left: sidebarWidth,
              top: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 34,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 760,
                      maxHeight: 760,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Stack(
                        children: [
                          AppGlassSurface(
                            borderRadius: dialogRadius,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                            tone: AppGlassTone.panel,
                            nativeBackdrop: true,
                            child: const TaskCenterPage(embedded: true),
                          ),
                          Positioned(
                            top: closeButtonInset,
                            right: closeButtonInset,
                            child: AppGlassIconButton(
                              icon: Icons.close_rounded,
                              tooltip: '关闭',
                              onPressed: Get.back,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildShortcutItem(BuildContext context, String keys, String desc) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(desc, style: TextStyle(color: cs.onSurface)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              keys,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMacShortcutItems(BuildContext context) => [
    _buildShortcutItem(context, 'Cmd + ,', '打开设置'),
    _buildShortcutItem(context, 'Cmd + 1', '打开全部文章'),
    _buildShortcutItem(context, 'Cmd + 2', '打开垃圾拦截'),
    _buildShortcutItem(context, 'Cmd + 0', '打开静默订阅源'),
    _buildShortcutItem(context, 'Cmd + Z', '撤销最近一次已读'),
    _buildShortcutItem(context, 'Esc', '关闭当前阅读文章'),
    _buildShortcutItem(context, '↑ / ↓', '上下滚动文章'),
    _buildShortcutItem(context, '← / →', '切换文章；未选择时定位末篇 / 首篇'),
    _buildShortcutItem(context, 'Cmd + R', '刷新文章列表'),
    _buildShortcutItem(context, 'M', '时间线切换已读；垃圾拦截移除'),
    _buildShortcutItem(context, 'K', '垃圾拦截保留文章'),
    _buildShortcutItem(context, 'N', '纠正分类：时间线移入垃圾拦截；垃圾拦截保留文章（同时标为已读）'),
    _buildShortcutItem(context, 'B', '在浏览器中打开原文'),
    _buildShortcutItem(context, 'Shift + B', '标为已读并打开；垃圾拦截移除并打开'),
    _buildShortcutItem(context, 'C', '复制原文全文为 Markdown'),
  ];

  void _scrollToMacSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  Widget _visibilityToggleButton({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    final icon = obscured ? Icons.visibility : Icons.visibility_off;
    final tooltip = obscured ? '显示' : '隐藏';
    if (Platform.isMacOS) {
      return AppGlassIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
  }

  Widget _buildMacOSScaffold(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _buildMacOSSettingsSidebar(context, colorScheme),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView(
                    controller: _macSettingsScrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      _MacSettingsSection(
                        key: _macAuthKey,
                        icon: Icons.key_rounded,
                        title: '服务认证',
                        subtitle: 'Folo 与 DeepSeek 凭据只保存在本机。',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppGlassButton(
                              label: _loggingIn
                                  ? '正在连接 Folo…'
                                  : _accountService.isLoggedIn.value
                                  ? '在浏览器中重新登录 Folo'
                                  : '使用浏览器登录 Folo',
                              icon: Icons.open_in_browser_rounded,
                              loading: _loggingIn,
                              onPressed: _changingAccount
                                  ? null
                                  : () => unawaited(_loginWithBrowser()),
                              role: AppGlassButtonRole.primary,
                              expand: true,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '也可以手动填写长期 Session Token',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppGlassTextField(
                              controller: _tokenController,
                              label: 'Session Token',
                              hint: 'T9VlefMC...',
                              suffixIcon: _visibilityToggleButton(
                                obscured: _obscureToken,
                                onPressed: () {
                                  setState(
                                    () => _obscureToken = !_obscureToken,
                                  );
                                },
                              ),
                              obscureText: _obscureToken,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            AppGlassTextField(
                              controller: _deepseekApiKeyController,
                              label: 'DeepSeek API Key',
                              hint: 'sk-...',
                              helper: '翻译、摘要和过滤共用此 Key',
                              suffixIcon: _visibilityToggleButton(
                                obscured: _obscureDeepseekKey,
                                onPressed: () {
                                  setState(
                                    () => _obscureDeepseekKey =
                                        !_obscureDeepseekKey,
                                  );
                                },
                              ),
                              obscureText: _obscureDeepseekKey,
                              textInputAction: TextInputAction.done,
                            ),
                            const SizedBox(height: 12),
                            _CredentialActions(
                              useGlass: true,
                              testing: _testingCredentials || _changingAccount,
                              onTest: _testCredentials,
                              onSave: _saveCredentials,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macPreferencesKey,
                        icon: Icons.tune_rounded,
                        title: '阅读与后台偏好',
                        subtitle: '控制桌面角标、文章宽度、已读同步和后台任务容错。',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MacGlassSegmentedField<String>(
                              value: _appearanceMode,
                              labelFor: _appearanceModeLabel,
                              options: const ['system', 'light', 'dark'],
                              label: '外观模式',
                              helper: '选择后立即生效；跟随系统会响应 macOS 外观变化',
                              onChanged: _setAppearanceMode,
                            ),
                            const SizedBox(height: 12),
                            _MacSettingsGrid(
                              children: [
                                _MacGlassSelectField<String>(
                                  value: _badgeStrategy,
                                  labelFor: (value) => switch (value) {
                                    'unread_count' => '显示未读数量',
                                    'dot_only' => '仅显示红点',
                                    'off' => '关闭角标',
                                    _ => value,
                                  },
                                  options: const [
                                    'unread_count',
                                    'dot_only',
                                    'off',
                                  ],
                                  label: '桌面角标显示规则',
                                  helper: '退到后台后图标右上角的红点行为',
                                  onChanged: _setBadgeStrategy,
                                ),
                                _AutoSavedSettingsTextField(
                                  controller: _articleContentMaxWidthController,
                                  focusNode: _articleContentMaxWidthFocusNode,
                                  label: '正文最大宽度（px）',
                                  useGlass: true,
                                  hint: '720',
                                  helper: 'macOS 文章页生效；建议 640～800 之间调试',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onCommit: _saveArticleContentMaxWidth,
                                ),
                                _AutoSavedSettingsTextField(
                                  controller: _macosMaxFlingVelocityController,
                                  focusNode: _macosMaxFlingVelocityFocusNode,
                                  label: 'macOS 滚动惯性上限',
                                  useGlass: true,
                                  hint: '4500',
                                  helper: '限制松手后的惯性滚动速度；范围 1000～8000，默认 4500',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onCommit: _saveMacosMaxFlingVelocity,
                                ),
                                _AutoSavedSettingsTextField(
                                  controller: _readSyncWindowDaysController,
                                  focusNode: _readSyncWindowDaysFocusNode,
                                  label: '已读拉取窗口（天）',
                                  useGlass: true,
                                  hint: '2',
                                  helper: '后台静默拉取最近已读文章的时间范围',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onCommit: _saveReadSyncWindowDays,
                                ),
                                _MacGlassSelectField<int>(
                                  value: _autoRetryMaxCount,
                                  labelFor: (value) => switch (value) {
                                    0 => '0 次（不重试）',
                                    1 => '1 次',
                                    3 => '3 次',
                                    5 => '5 次',
                                    _ => '$value 次',
                                  },
                                  options: const [0, 1, 3, 5],
                                  label: '自动重试次数',
                                  helper: '设为 0 表示不重试',
                                  onChanged: _setAutoRetryMaxCount,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macAiKey,
                        icon: Icons.auto_awesome_rounded,
                        title: 'AI 服务与模型参数',
                        subtitle: '分别调整翻译、摘要、过滤和关系判断任务的模型参数。',
                        child: Column(
                          children: [
                            _LlmConfigCard(
                              title: '翻译 LLM 参数',
                              defaultConfig: LlmConfig.translateDefault,
                              loadConfig: LlmConfig.loadTranslate,
                              saveConfig: LlmConfig.saveTranslate,
                              resetConfig: LlmConfig.resetTranslate,
                            ),
                            const SizedBox(height: 10),
                            _LlmConfigCard(
                              title: '摘要 LLM 参数',
                              defaultConfig: LlmConfig.summaryDefault,
                              loadConfig: LlmConfig.loadSummary,
                              saveConfig: LlmConfig.saveSummary,
                              resetConfig: LlmConfig.resetSummary,
                            ),
                            const SizedBox(height: 10),
                            _LlmConfigCard(
                              title: '过滤 LLM 参数',
                              defaultConfig: LlmConfig.filterDefault,
                              loadConfig: LlmConfig.loadFilter,
                              saveConfig: LlmConfig.saveFilter,
                              resetConfig: LlmConfig.resetFilter,
                            ),
                            const SizedBox(height: 10),
                            _LlmConfigCard(
                              title: '关系判断 LLM 参数',
                              defaultConfig: LlmConfig.relationDefault,
                              loadConfig: LlmConfig.loadRelation,
                              saveConfig: LlmConfig.saveRelation,
                              resetConfig: LlmConfig.resetRelation,
                              showConcurrency: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macPromptKey,
                        icon: Icons.edit_note_rounded,
                        title: 'Prompt',
                        subtitle: '自定义摘要、翻译和 AI 过滤规则。修改后从下一次请求开始生效。',
                        child: Column(
                          children: [
                            _PromptCard(
                              title: '摘要 AI Prompt',
                              subtitle: '自定义摘要规则（返回必须是特定 JSON 格式）',
                              hintText: '输入摘要规则...',
                              emptyWarning: '请保留默认的 JSON 结构指令',
                              savedMessage: '新摘要将从下次请求生效',
                              helpText:
                                  '这里配置 System Prompt。程序会自动拼接文章标题和 HTML 正文作为 User Prompt；如需动态目标语言，可保留 {targetLang}。',
                              loadPrompt: () =>
                                  SummaryService.getPrompt('{targetLang}'),
                              savePrompt: SummaryService.setPrompt,
                              resetPrompt: SummaryService.resetPrompt,
                            ),
                            const SizedBox(height: 10),
                            _PromptCard(
                              title: '翻译 AI Prompt',
                              subtitle: '自定义翻译规则（返回必须是特定 JSON 格式）',
                              hintText: '输入翻译规则...',
                              emptyWarning: '请保留默认的 JSON 结构指令',
                              savedMessage: '新翻译将从下次请求生效',
                              helpText:
                                  '这里配置 System Prompt。程序会自动拼接文章或分块正文作为 User Prompt；如需动态目标语言，可保留 {targetLang}。',
                              loadPrompt: () =>
                                  TranslationService.getPrompt('{targetLang}'),
                              savePrompt: TranslationService.setPrompt,
                              resetPrompt: TranslationService.resetPrompt,
                            ),
                            const SizedBox(height: 10),
                            _PromptCard(
                              title: 'AI 过滤 Prompt',
                              subtitle: '自定义文章过滤规则（LLM 判定）',
                              hintText: '输入过滤规则...',
                              emptyWarning: '请保留至少一条过滤规则',
                              savedMessage: '新过滤将从下次请求生效',
                              loadPrompt: ArticleFilterService.getPrompt,
                              savePrompt: ArticleFilterService.setPrompt,
                              resetPrompt: ArticleFilterService.resetPrompt,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macShortcutsKey,
                        icon: Icons.keyboard_rounded,
                        title: '快捷键',
                        subtitle: 'macOS 端常用键盘操作。',
                        child: Column(
                          children: _buildMacShortcutItems(context),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macAboutKey,
                        icon: Icons.info_outline_rounded,
                        title: '关于',
                        subtitle: '版本、项目边界和服务信息。',
                        child: _buildMacAboutContent(context, colorScheme),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMacOSSettingsSidebar(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final navItems = [
      (Icons.key_rounded, '认证', _macAuthKey),
      (Icons.tune_rounded, '偏好', _macPreferencesKey),
      (Icons.auto_awesome_rounded, 'AI 参数', _macAiKey),
      (Icons.edit_note_rounded, 'Prompt', _macPromptKey),
      (Icons.keyboard_rounded, '快捷键', _macShortcutsKey),
      (Icons.info_outline_rounded, '关于', _macAboutKey),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(16),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          staticMaterial: true,
          child: Obx(() {
            final loggedIn = _accountService.isLoggedIn.value;
            return _FoloAccountIdentity(
              loggedIn: loggedIn,
              profile: _accountService.profile.value,
              avatarSize: 48,
              loggedOutSubtitle: '可使用浏览器或 Token 登录',
            );
          }),
        ),
        const SizedBox(height: 12),
        AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(12),
          tone: AppGlassTone.surface,
          nativeBackdrop: true,
          staticMaterial: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppGlassButton(
                onPressed: _accountService.isLoggedIn.value
                    ? () => unawaited(_signOutLocally())
                    : null,
                icon: Icons.logout_rounded,
                label: '退出账号',
                role: AppGlassButtonRole.destructive,
                expand: true,
              ),
              const SizedBox(height: 8),
              AppGlassButton(
                onPressed: _openTaskCenter,
                icon: Icons.hub_outlined,
                label: '后台任务',
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(12),
          tone: AppGlassTone.surface,
          nativeBackdrop: true,
          staticMaterial: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '配置迁移',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              AppGlassButton(
                onPressed: _exportSettingsToClipboard,
                icon: Icons.upload_rounded,
                label: '导出到剪贴板',
                expand: true,
              ),
              const SizedBox(height: 8),
              AppGlassButton(
                onPressed: _importSettingsFromClipboard,
                icon: Icons.download_rounded,
                label: '从剪贴板导入',
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AppGlassSurface(
            borderRadius: AppGlassRadii.panel,
            padding: const EdgeInsets.symmetric(vertical: 8),
            tone: AppGlassTone.surface,
            nativeBackdrop: true,
            staticMaterial: true,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final (icon, label, key) = navItems[index];
                return _MacSettingsNavItem(
                  icon: icon,
                  label: label,
                  onTap: () => _scrollToMacSection(key),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMacAboutContent(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppConstants.appName} v${AppVersionService.version}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '基于 Folo API 的 RSS 信息流浏览器。支持 Android 和 macOS。',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          '非官方个人二次开发客户端，不隶属于 Folo 或 RSSNext。',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 12),
        _MacSettingsMetadataRow(label: 'Folo API', value: 'api.folo.is'),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _showOpenSourceLicenses,
          icon: const Icon(Icons.description_outlined, size: 17),
          label: const Text('开源许可证'),
        ),
      ],
    );
  }

  Widget _buildAndroidScaffold(BuildContext context, ColorScheme colorScheme) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final topPadding =
        mediaPadding.top + (widget.showAppBar ? mobileAppBarToolbarHeight : 0);
    final bottomPadding =
        mediaPadding.bottom +
        (widget.showAppBar ? 24 : kBottomNavigationBarHeight + 32);
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        inputDecorationTheme: mobileSettingsInputTheme(
          context,
          baseTheme.inputDecorationTheme,
        ),
        expansionTileTheme: baseTheme.expansionTileTheme.copyWith(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: colorScheme.primary,
          collapsedIconColor: colorScheme.onSurfaceVariant,
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: widget.showAppBar
            ? const MobileBlurAppBar(title: Text('设置'))
            : null,
        body: ListView(
          padding: EdgeInsets.fromLTRB(12, topPadding + 12, 12, bottomPadding),
          children: [
            if (!widget.showAppBar) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                child: Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
            Obx(
              () => MobileSettingsPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: _FoloAccountIdentity(
                  loggedIn: _accountService.isLoggedIn.value,
                  profile: _accountService.profile.value,
                  avatarSize: 52,
                  loggedOutSubtitle: '登录后即可同步文章',
                ),
              ),
            ),
            const SizedBox(height: 10),
            MobileSettingsActionTile(
              icon: Icons.hub_outlined,
              title: '后台任务与同步',
              subtitle: '同步队列、AI 任务和失败记录',
              onTap: _openTaskCenter,
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.key_rounded,
              title: '服务认证',
              subtitle: 'Folo 账号与 DeepSeek API Key',
            ),
            MobileSettingsPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _changingAccount
                          ? null
                          : () => unawaited(_loginWithBrowser()),
                      icon: _loggingIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(
                        _loggingIn
                            ? '正在连接 Folo…'
                            : _accountService.isLoggedIn.value
                            ? '重新登录 Folo'
                            : '登录 Folo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '也可以手动填写长期 Session Token',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      labelText: 'Session Token',
                      hintText: 'T9VlefMC...',
                      suffixIcon: _visibilityToggleButton(
                        obscured: _obscureToken,
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                    obscureText: _obscureToken,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _deepseekApiKeyController,
                    decoration: InputDecoration(
                      labelText: 'DeepSeek API Key',
                      hintText: 'sk-...',
                      helperText: '翻译、摘要和过滤共用',
                      suffixIcon: _visibilityToggleButton(
                        obscured: _obscureDeepseekKey,
                        onPressed: () => setState(
                          () => _obscureDeepseekKey = !_obscureDeepseekKey,
                        ),
                      ),
                    ),
                    obscureText: _obscureDeepseekKey,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 14),
                  _CredentialActions(
                    useGlass: false,
                    testing: _testingCredentials || _changingAccount,
                    onTest: _testCredentials,
                    onSave: _saveCredentials,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _accountService.isLoggedIn.value
                          ? () => unawaited(_signOutLocally())
                          : null,
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      label: Text(
                        '退出 Folo 账号',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.tune_rounded,
              title: '阅读与后台偏好',
              subtitle: '选择立即保存；数字输入在完成编辑后保存',
            ),
            MobileSettingsPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  MobileSettingsSelectField<String>(
                    value: _appearanceMode,
                    options: const ['system', 'light', 'dark'],
                    labelFor: _appearanceModeLabel,
                    label: '外观模式',
                    onChanged: _setAppearanceMode,
                  ),
                  const SizedBox(height: 12),
                  MobileSettingsSelectField<String>(
                    value: _badgeStrategy,
                    options: const ['unread_count', 'dot_only', 'off'],
                    labelFor: (value) {
                      return switch (value) {
                        'unread_count' => '显示未读数量',
                        'dot_only' => '仅显示红点',
                        'off' => '关闭角标',
                        _ => value,
                      };
                    },
                    label: '应用角标',
                    onChanged: _setBadgeStrategy,
                  ),
                  const SizedBox(height: 12),
                  _AutoSavedSettingsTextField(
                    controller: _readSyncWindowDaysController,
                    focusNode: _readSyncWindowDaysFocusNode,
                    label: '已读拉取窗口（天）',
                    useGlass: false,
                    hint: '2',
                    helper: '后台静默拉取最近已读文章的范围',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onCommit: _saveReadSyncWindowDays,
                  ),
                  const SizedBox(height: 12),
                  MobileSettingsSelectField<int>(
                    value: _autoRetryMaxCount,
                    options: const [0, 1, 3, 5],
                    labelFor: (value) {
                      return switch (value) {
                        0 => '0 次（不重试）',
                        1 => '1 次',
                        3 => '3 次',
                        5 => '5 次',
                        _ => '$value 次',
                      };
                    },
                    label: '自动重试次数',
                    onChanged: _setAutoRetryMaxCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.swap_horiz_rounded,
              title: '配置迁移',
              subtitle: '通过剪贴板迁移账号、AI、Prompt 和订阅源偏好',
            ),
            MobileSettingsPanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exportSettingsToClipboard,
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: const Text('导出'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importSettingsFromClipboard,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('导入'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.auto_awesome_rounded,
              title: 'AI 模型参数',
              subtitle: '离散选择立即保存；数值在完成编辑后保存',
            ),
            _LlmConfigCard(
              title: '翻译 LLM 参数',
              defaultConfig: LlmConfig.translateDefault,
              loadConfig: LlmConfig.loadTranslate,
              saveConfig: LlmConfig.saveTranslate,
              resetConfig: LlmConfig.resetTranslate,
            ),
            const SizedBox(height: 10),
            _LlmConfigCard(
              title: '摘要 LLM 参数',
              defaultConfig: LlmConfig.summaryDefault,
              loadConfig: LlmConfig.loadSummary,
              saveConfig: LlmConfig.saveSummary,
              resetConfig: LlmConfig.resetSummary,
            ),
            const SizedBox(height: 10),
            _LlmConfigCard(
              title: '过滤 LLM 参数',
              defaultConfig: LlmConfig.filterDefault,
              loadConfig: LlmConfig.loadFilter,
              saveConfig: LlmConfig.saveFilter,
              resetConfig: LlmConfig.resetFilter,
            ),
            const SizedBox(height: 10),
            _LlmConfigCard(
              title: '关系判断 LLM 参数',
              defaultConfig: LlmConfig.relationDefault,
              loadConfig: LlmConfig.loadRelation,
              saveConfig: LlmConfig.saveRelation,
              resetConfig: LlmConfig.resetRelation,
              showConcurrency: false,
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.notes_rounded,
              title: 'Prompt',
              subtitle: '大段文本保留明确的保存与重置操作',
            ),
            _PromptCard(
              title: '摘要 AI Prompt',
              subtitle: '自定义摘要规则（返回必须是特定 JSON 格式）',
              hintText: '输入摘要规则...',
              emptyWarning: '请保留默认的 JSON 结构指令',
              savedMessage: '新摘要将从下次请求生效',
              helpText: '程序会自动拼接文章标题和 HTML 正文；动态目标语言可保留 {targetLang}。',
              loadPrompt: () => SummaryService.getPrompt('{targetLang}'),
              savePrompt: SummaryService.setPrompt,
              resetPrompt: SummaryService.resetPrompt,
            ),
            const SizedBox(height: 10),
            _PromptCard(
              title: '翻译 AI Prompt',
              subtitle: '自定义翻译规则（返回必须是特定 JSON 格式）',
              hintText: '输入翻译规则...',
              emptyWarning: '请保留默认的 JSON 结构指令',
              savedMessage: '新翻译将从下次请求生效',
              helpText: '程序会自动拼接文章或分块正文；动态目标语言可保留 {targetLang}。',
              loadPrompt: () => TranslationService.getPrompt('{targetLang}'),
              savePrompt: TranslationService.setPrompt,
              resetPrompt: TranslationService.resetPrompt,
            ),
            const SizedBox(height: 10),
            _PromptCard(
              title: 'AI 过滤 Prompt',
              subtitle: '自定义文章过滤规则（LLM 判定）',
              hintText: '输入过滤规则...',
              emptyWarning: '请保留至少一条过滤规则',
              savedMessage: '新过滤将从下次请求生效',
              loadPrompt: ArticleFilterService.getPrompt,
              savePrompt: ArticleFilterService.setPrompt,
              resetPrompt: ArticleFilterService.resetPrompt,
            ),
            const SizedBox(height: 24),
            const MobileSettingsSectionHeader(
              icon: Icons.info_outline_rounded,
              title: '关于',
              subtitle: '应用身份与服务信息',
            ),
            MobileSettingsPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppConstants.appName} v${AppVersionService.version}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '基于 Folo API 的非官方个人二次开发客户端，不隶属于 Folo 或 RSSNext。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Folo API: api.folo.is',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showOpenSourceLicenses,
                    icon: const Icon(Icons.description_outlined, size: 17),
                    label: const Text('开源许可证'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (Platform.isMacOS) {
      return _buildMacOSScaffold(context, colorScheme);
    }

    if (Platform.isAndroid) {
      return _buildAndroidScaffold(context, colorScheme);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.showAppBar
          ? AppBar(
              leadingWidth: Platform.isMacOS ? 88 : null,
              leading: Platform.isMacOS && Navigator.of(context).canPop()
                  ? Padding(
                      padding: const EdgeInsets.only(left: 66),
                      child: AppGlassIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: '返回',
                        onPressed: Get.back,
                        useOwnLayer: false,
                      ),
                    )
                  : null,
              title: const Text('设置'),
              centerTitle: true,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.7),
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 8,
          16,
          MediaQuery.paddingOf(context).bottom +
              (Platform.isMacOS ? 0 : kBottomNavigationBarHeight) +
              32,
        ),
        children: [
          // 登录状态
          Obx(
            () => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _FoloAccountIdentity(
                  loggedIn: _accountService.isLoggedIn.value,
                  profile: _accountService.profile.value,
                  avatarSize: 52,
                  loggedOutSubtitle: '登录后即可同步文章',
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            child: ListTile(
              leading: Icon(Icons.hub_outlined, color: colorScheme.primary),
              title: const Text('后台任务与同步'),
              subtitle: const Text('查看同步队列、AI 任务和本地文章状态'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(Routes.taskCenter),
            ),
          ),

          const SizedBox(height: 24),

          // 服务认证
          Text(
            '服务认证',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '配置 Folo Session Token 与 DeepSeek API Key',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: 'Session Token',
              hintText: 'T9VlefMC...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureToken ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureToken = !_obscureToken);
                },
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureToken,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _deepseekApiKeyController,
            decoration: InputDecoration(
              labelText: 'DeepSeek API Key',
              hintText: 'sk-...',
              helperText: '翻译、摘要和过滤共用此 Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureDeepseekKey ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureDeepseekKey = !_obscureDeepseekKey);
                },
                icon: Icon(
                  _obscureDeepseekKey ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureDeepseekKey,
            textInputAction: TextInputAction.done,
          ),

          const SizedBox(height: 12),

          _CredentialActions(
            useGlass: false,
            testing: _testingCredentials || _changingAccount,
            onTest: _testCredentials,
            onSave: _saveCredentials,
          ),

          const SizedBox(height: 32),

          // 外观模式
          Text(
            '外观模式',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '控制应用使用浅色、深色，或跟随系统外观',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _appearanceMode,
            decoration: const InputDecoration(
              labelText: '外观模式',
              border: OutlineInputBorder(),
              helperText: '选择后立即生效',
            ),
            items: const [
              DropdownMenuItem(value: 'system', child: Text('跟随系统')),
              DropdownMenuItem(value: 'light', child: Text('浅色')),
              DropdownMenuItem(value: 'dark', child: Text('深色')),
            ],
            onChanged: (val) {
              if (val != null) _setAppearanceMode(val);
            },
          ),

          const SizedBox(height: 32),

          // 通知与角标
          Text(
            '通知与角标',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '控制桌面图标角标显示',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _badgeStrategy,
            decoration: const InputDecoration(
              labelText: '桌面角标显示规则',
              border: OutlineInputBorder(),
              helperText: '退到后台后图标右上角的红点行为',
            ),
            items: const [
              DropdownMenuItem(value: 'unread_count', child: Text('显示未读数量')),
              DropdownMenuItem(value: 'dot_only', child: Text('仅显示红点')),
              DropdownMenuItem(value: 'off', child: Text('关闭角标')),
            ],
            onChanged: (val) {
              if (val != null) _setBadgeStrategy(val);
            },
          ),

          const SizedBox(height: 32),

          // 交互反馈（仅 Android）
          if (Platform.isAndroid) ...[
            Text(
              '交互反馈',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '文章翻页、垃圾拦截侧滑确认、已读切换等关键动作的触觉反馈',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                title: const Text('触觉反馈'),
                subtitle: const Text('开启后关键操作会轻微振动'),
                value: _androidHapticsEnabled,
                onChanged: (enabled) {
                  setState(() => _androidHapticsEnabled = enabled);
                  unawaited(AndroidHapticsService.setEnabled(enabled));
                },
              ),
            ),
            const SizedBox(height: 32),
          ],

          // 阅读排版
          Text(
            '阅读排版',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '控制文章详情页正文与图片的最大显示宽度',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          _AutoSavedSettingsTextField(
            controller: _articleContentMaxWidthController,
            focusNode: _articleContentMaxWidthFocusNode,
            label: '正文最大宽度（px）',
            useGlass: false,
            hint: '720',
            helper: 'macOS 文章页生效；默认 720，建议 640～800 之间调试',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onCommit: _saveArticleContentMaxWidth,
          ),

          const SizedBox(height: 12),

          _AutoSavedSettingsTextField(
            controller: _macosMaxFlingVelocityController,
            focusNode: _macosMaxFlingVelocityFocusNode,
            label: 'macOS 滚动惯性上限',
            useGlass: false,
            hint: '4500',
            helper: '限制松手后的惯性滚动速度；范围 1000～8000，默认 4500',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onCommit: _saveMacosMaxFlingVelocity,
          ),

          const SizedBox(height: 12),

          _AutoSavedSettingsTextField(
            controller: _readSyncWindowDaysController,
            focusNode: _readSyncWindowDaysFocusNode,
            label: '已读拉取窗口（天）',
            useGlass: false,
            hint: '2',
            helper: '后台静默拉取最近已读文章的时间范围',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onCommit: _saveReadSyncWindowDays,
          ),

          const SizedBox(height: 32),

          // 后台重试设置
          Text(
            '后台任务容错设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '配置翻译和摘要任务失败时的自动重试次数',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<int>(
            initialValue: _autoRetryMaxCount,
            decoration: const InputDecoration(
              labelText: '自动重试次数',
              border: OutlineInputBorder(),
              helperText: '遇到网络或解析错误时的最大原地重试次数。设为 0 表示不重试。',
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0 次（不重试）')),
              DropdownMenuItem(value: 1, child: Text('1 次')),
              DropdownMenuItem(value: 3, child: Text('3 次')),
              DropdownMenuItem(value: 5, child: Text('5 次')),
            ],
            onChanged: (val) {
              if (val != null) _setAutoRetryMaxCount(val);
            },
          ),

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _accountService.isLoggedIn.value
                ? () => unawaited(_signOutLocally())
                : null,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出 Folo 账号'),
          ),

          const SizedBox(height: 24),

          // 配置迁移
          Text(
            '配置迁移',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '导出和导入账号、AI、Prompt 与订阅源偏好设置',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exportSettingsToClipboard,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('导出到剪贴板'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importSettingsFromClipboard,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('从剪贴板导入'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),

          // ─── LLM 参数配置 ─────────────────────
          _LlmConfigCard(
            title: '翻译 LLM 参数',
            defaultConfig: LlmConfig.translateDefault,
            loadConfig: LlmConfig.loadTranslate,
            saveConfig: LlmConfig.saveTranslate,
            resetConfig: LlmConfig.resetTranslate,
          ),
          const SizedBox(height: 16),
          _LlmConfigCard(
            title: '摘要 LLM 参数',
            defaultConfig: LlmConfig.summaryDefault,
            loadConfig: LlmConfig.loadSummary,
            saveConfig: LlmConfig.saveSummary,
            resetConfig: LlmConfig.resetSummary,
          ),

          const SizedBox(height: 12),

          _LlmConfigCard(
            title: '过滤 LLM 参数',
            defaultConfig: LlmConfig.filterDefault,
            loadConfig: LlmConfig.loadFilter,
            saveConfig: LlmConfig.saveFilter,
            resetConfig: LlmConfig.resetFilter,
          ),

          const SizedBox(height: 12),

          _LlmConfigCard(
            title: '关系判断 LLM 参数',
            defaultConfig: LlmConfig.relationDefault,
            loadConfig: LlmConfig.loadRelation,
            saveConfig: LlmConfig.saveRelation,
            resetConfig: LlmConfig.resetRelation,
            showConcurrency: false,
          ),

          const SizedBox(height: 12),

          // Prompt 配置
          _PromptCard(
            title: '摘要 AI Prompt',
            subtitle: '自定义摘要规则（返回必须是特定 JSON 格式）',
            hintText: '输入摘要规则...',
            emptyWarning: '请保留默认的 JSON 结构指令',
            savedMessage: '新摘要将从下次请求生效',
            helpText:
                '这里配置 System Prompt。程序会自动拼接文章标题和 HTML 正文作为 User Prompt；如需动态目标语言，可保留 {targetLang}。',
            loadPrompt: () => SummaryService.getPrompt('{targetLang}'),
            savePrompt: SummaryService.setPrompt,
            resetPrompt: SummaryService.resetPrompt,
          ),
          const SizedBox(height: 12),
          _PromptCard(
            title: '翻译 AI Prompt',
            subtitle: '自定义翻译规则（返回必须是特定 JSON 格式）',
            hintText: '输入翻译规则...',
            emptyWarning: '请保留默认的 JSON 结构指令',
            savedMessage: '新翻译将从下次请求生效',
            helpText:
                '这里配置 System Prompt。程序会自动拼接文章或分块正文作为 User Prompt；如需动态目标语言，可保留 {targetLang}。',
            loadPrompt: () => TranslationService.getPrompt('{targetLang}'),
            savePrompt: TranslationService.setPrompt,
            resetPrompt: TranslationService.resetPrompt,
          ),
          const SizedBox(height: 12),
          _PromptCard(
            title: 'AI 过滤 Prompt',
            subtitle: '自定义文章过滤规则（LLM 判定）',
            hintText: '输入过滤规则...',
            emptyWarning: '请保留至少一条过滤规则',
            savedMessage: '新过滤将从下次请求生效',
            loadPrompt: ArticleFilterService.getPrompt,
            savePrompt: ArticleFilterService.setPrompt,
            resetPrompt: ArticleFilterService.resetPrompt,
          ),

          const SizedBox(height: 24),

          if (Platform.isMacOS) ...[
            Text(
              '快捷键 (macOS)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: _buildMacShortcutItems(context)),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 关于
          Text(
            '关于',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppConstants.appName} v${AppVersionService.version}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '基于 Folo API 的 RSS 信息流浏览器。'
                    '支持 Android 和 macOS。',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '非官方个人二次开发客户端，不隶属于 Folo 或 RSSNext。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Folo API: api.folo.is',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showOpenSourceLicenses,
                    icon: const Icon(Icons.description_outlined, size: 17),
                    label: const Text('开源许可证'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacSettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _MacSettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    return AppGlassSurface(
      borderRadius: AppGlassRadii.panel,
      padding: const EdgeInsets.all(18),
      tone: AppGlassTone.panel,
      nativeBackdrop: true,
      staticMaterial: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: controls.activeFill(accentAlpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MacSettingsGrid extends StatelessWidget {
  final List<Widget> children;

  const _MacSettingsGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 720;
        if (!useTwoColumns) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: (constraints.maxWidth - 12) / 2, child: child),
          ],
        );
      },
    );
  }
}

class _MacSettingsNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MacSettingsNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_MacSettingsNavItem> createState() => _MacSettingsNavItemState();
}

class _MacSettingsNavItemState extends State<_MacSettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.onSurface.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 17, color: cs.onSurfaceVariant),
              const SizedBox(width: 9),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacSettingsMetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MacSettingsMetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _MacInlineExpansion extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _MacInlineExpansion({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  State<_MacInlineExpansion> createState() => _MacInlineExpansionState();
}

class _MacInlineExpansionState extends State<_MacInlineExpansion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _heightFactor;
  late final Animation<double> _contentOpacity;
  late final Animation<Offset> _contentOffset;
  bool _expanded = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _contentOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 0.74, curve: Curves.easeInCubic),
    );
    _contentOffset =
        Tween<Offset>(begin: const Offset(0, -0.025), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _pressed = false;
    });
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overlayAlpha = _pressed
        ? 0.04
        : _hovered
        ? 0.022
        : 0.0;
    final borderAlpha = _pressed
        ? 0.36
        : _hovered
        ? 0.32
        : 0.28;
    const panelFill = Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: panelFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.onSurfaceVariant.withValues(alpha: borderAlpha),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          if (overlayAlpha > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: overlayAlpha),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() {
                  _hovered = false;
                  _pressed = false;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTapUp: (_) => setState(() => _pressed = false),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _heightFactor,
                child: FadeTransition(
                  opacity: _contentOpacity,
                  child: SlideTransition(
                    position: _contentOffset,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: widget.child,
                    ),
                  ),
                ),
                builder: (context, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _heightFactor.value,
                      child: child,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FoloAccountIdentity extends StatelessWidget {
  const _FoloAccountIdentity({
    required this.loggedIn,
    required this.profile,
    required this.avatarSize,
    required this.loggedOutSubtitle,
  });

  final bool loggedIn;
  final FoloAccountProfile? profile;
  final double avatarSize;
  final String loggedOutSubtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = profile?.displayName ?? 'Folo 账号';
    return Row(
      children: [
        _buildAvatar(context, displayName),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loggedIn ? displayName : '未登录 Folo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: loggedIn ? cs.onSurface : cs.error,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                loggedIn ? '已连接到 Folo' : loggedOutSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, String displayName) {
    final cs = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: loggedIn ? cs.primaryContainer : cs.errorContainer,
      child: Center(
        child: loggedIn
            ? Text(
                profile?.initials ?? 'F',
                style: TextStyle(
                  fontSize: avatarSize * 0.38,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimaryContainer,
                ),
              )
            : Icon(
                Icons.person_outline_rounded,
                size: avatarSize * 0.52,
                color: cs.onErrorContainer,
              ),
      ),
    );
    final imageUrl = loggedIn ? profile?.imageUrl?.trim() : null;

    return Semantics(
      image: true,
      label: loggedIn ? '$displayName 的头像' : '未登录 Folo',
      child: ClipOval(
        child: SizedBox.square(
          dimension: avatarSize,
          child: imageUrl == null || imageUrl.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: (avatarSize * 3).round(),
                  memCacheHeight: (avatarSize * 3).round(),
                  fadeInDuration: const Duration(milliseconds: 160),
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SettingsConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _SettingsConfirmDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return AlertDialog(
        title: Text(title),
        content: Text(content, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('取消')),
          FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(18),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                content,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  AppGlassButton(label: '取消', onPressed: onCancel),
                  const SizedBox(width: 10),
                  AppGlassButton(
                    label: confirmLabel,
                    onPressed: onConfirm,
                    role: AppGlassButtonRole.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidLoginProviderSheet extends StatelessWidget {
  const _AndroidLoginProviderSheet({required this.providers});

  final List<FoloAuthProvider> providers;

  IconData _iconFor(String providerId) {
    return switch (providerId) {
      'credential' => Icons.mail_outline_rounded,
      'github' => Icons.code_rounded,
      'google' => Icons.public_rounded,
      _ => Icons.login_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...providers]
      ..sort((a, b) {
        const order = {'credential': 0, 'google': 1, 'github': 2};
        return (order[a.id] ?? 10).compareTo(order[b.id] ?? 10);
      });
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '登录 Folo',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选择与 Folo 账号一致的登录方式',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final provider in sorted)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(_iconFor(provider.id), color: cs.onSurface),
              title: Text('使用 ${provider.name} 登录'),
              subtitle: Text(provider.isCredential ? '输入邮箱和密码' : '在系统浏览器中继续'),
              trailing: const Icon(Icons.chevron_right_rounded),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Navigator.of(context).pop(provider),
            ),
        ],
      ),
    );
  }
}

class _AndroidEmailLoginDialog extends StatefulWidget {
  const _AndroidEmailLoginDialog();

  @override
  State<_AndroidEmailLoginDialog> createState() =>
      _AndroidEmailLoginDialogState();
}

class _AndroidEmailLoginDialogState extends State<_AndroidEmailLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();
  String? _twoFactorCookie;
  String? _error;
  bool _busy = false;
  bool _obscurePassword = true;

  bool get _requiresTwoFactor => _twoFactorCookie != null;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_requiresTwoFactor) {
        final candidate = await FoloAuthService.verifyEmailTotp(
          code: _totpController.text,
          twoFactorCookie: _twoFactorCookie!,
        );
        if (mounted) Navigator.of(context).pop(candidate);
        return;
      }

      final result = await FoloAuthService.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      final candidate = result.candidate;
      if (candidate != null) {
        Navigator.of(context).pop(candidate);
        return;
      }
      setState(() {
        _twoFactorCookie = result.twoFactorCookie;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(
        _requiresTwoFactor
            ? Icons.verified_user_outlined
            : Icons.mail_outline_rounded,
        color: cs.primary,
      ),
      title: Text(_requiresTwoFactor ? '二步验证' : '使用 Email 登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_requiresTwoFactor)
            TextField(
              controller: _totpController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '6 位验证码',
                counterText: '',
              ),
              onSubmitted: (_) => unawaited(_submit()),
            )
          else ...[
            TextField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '密码',
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_requiresTwoFactor ? '验证' : '登录'),
        ),
      ],
    );
  }
}

class _BrowserLoginDialog extends StatefulWidget {
  const _BrowserLoginDialog({required this.session, this.providerName});

  final FoloLoginSession session;
  final String? providerName;

  @override
  State<_BrowserLoginDialog> createState() => _BrowserLoginDialogState();
}

class _BrowserLoginDialogState extends State<_BrowserLoginDialog>
    with WidgetsBindingObserver {
  String? _error;
  bool _finished = false;
  bool _finishScheduled = false;
  FoloAccountCandidate? _candidate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.result
        .then((candidate) {
          _candidate = candidate;
          _finishWhenReady();
        })
        .catchError((Object error) {
          _finished = true;
          if (mounted) setState(() => _error = error.toString());
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _finishWhenReady();
  }

  void _finishWhenReady() {
    if (!mounted || _candidate == null || _finishScheduled) return;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (Platform.isAndroid &&
        lifecycleState != null &&
        lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    if (!Platform.isAndroid) {
      _completeLogin();
      return;
    }

    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishScheduled = false;
      _completeLogin();
    });
  }

  void _completeLogin() {
    final candidate = _candidate;
    if (!mounted || candidate == null || _finished) return;
    _finished = true;
    assert(() {
      final reason = Platform.isAndroid
          ? 'after app resume'
          : 'after localhost callback';
      debugPrint('[FoloAuthProbe] Closing login dialog $reason');
      return true;
    }());
    Navigator.of(context, rootNavigator: true).pop(candidate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_finished) unawaited(widget.session.cancel());
    super.dispose();
  }

  Future<void> _cancel() async {
    if (!_finished) {
      _finished = true;
      await widget.session.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) return _buildAndroidDialog(context);

    final cs = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(20),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '在浏览器中登录 Folo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _error ??
                    '已打开 Folo 官方登录页面。完成登录后，Fourier 会在后台自动接收授权；无需点击网页中的“打开 Folo”按钮。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _error == null ? cs.onSurfaceVariant : cs.error,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (_error == null) ...[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '等待浏览器确认',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  AppGlassButton(
                    label: _error == null ? '取消' : '关闭',
                    onPressed: () => unawaited(_cancel()),
                  ),
                  if (_error == null) ...[
                    const SizedBox(width: 10),
                    AppGlassButton(
                      label: '重新打开浏览器',
                      icon: Icons.open_in_browser_rounded,
                      onPressed: () => unawaited(widget.session.openBrowser()),
                      role: AppGlassButtonRole.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final providerName = widget.providerName ?? 'Folo';
    return AlertDialog(
      icon: Icon(Icons.open_in_browser_rounded, color: cs.primary),
      title: Text('使用 $providerName 登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error ?? '已在系统浏览器中打开 $providerName 登录。完成授权后会自动返回 Fourier，认证会自动保存。',
            style: TextStyle(
              height: 1.45,
              color: _error == null ? cs.onSurfaceVariant : cs.error,
            ),
          ),
          if (_error == null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '等待浏览器确认',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_cancel()),
          child: Text(_error == null ? '取消' : '关闭'),
        ),
        if (_error == null)
          FilledButton.icon(
            onPressed: () => unawaited(widget.session.openBrowser()),
            icon: const Icon(Icons.open_in_browser_rounded),
            label: Text('重新打开 $providerName 登录'),
          ),
      ],
      actionsAlignment: MainAxisAlignment.end,
      scrollable: true,
    );
  }
}

class _MacGlassSegmentedField<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;
  final String label;
  final String? helper;

  const _MacGlassSegmentedField({
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
    required this.label,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final rawIndex = options.indexOf(value);
    final selectedIndex = rawIndex < 0 ? 0 : rawIndex;
    return SelectionContainer.disabled(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          AppGlassSurface(
            borderRadius: 14,
            padding: const EdgeInsets.all(4),
            tone: AppGlassTone.control,
            nativeBackdrop: true,
            staticMaterial: true,
            staticBorderOpacity: 0.35,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: controls.compactControlTrackFill(),
              ),
              child: SizedBox(
                height: 34,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final segmentWidth = constraints.maxWidth / options.length;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 230),
                          curve: Curves.easeOutBack,
                          left: segmentWidth * selectedIndex,
                          top: 0,
                          bottom: 0,
                          width: segmentWidth,
                          child: AppGlassSurface(
                            borderRadius: 11,
                            padding: EdgeInsets.zero,
                            tone: AppGlassTone.control,
                            useOwnLayer: false,
                            interactive: true,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                color: controls.activeFill(accentAlpha: 0.014),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < options.length; i++)
                              Expanded(
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => onChanged(options[i]),
                                    child: Center(
                                      child: Text(
                                        labelFor(options[i]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: selectedIndex == i
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: selectedIndex == i
                                              ? cs.primary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                helper!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MacGlassSelectField<T> extends StatefulWidget {
  final T value;
  final List<T> options;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;
  final String label;
  final String? helper;

  const _MacGlassSelectField({
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
    required this.label,
    this.helper,
  });

  @override
  State<_MacGlassSelectField<T>> createState() =>
      _MacGlassSelectFieldState<T>();
}

class _MacGlassSelectFieldState<T> extends State<_MacGlassSelectField<T>> {
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _hideOptions(rebuild: false);
    super.dispose();
  }

  void _toggleOptions() {
    if (_overlayEntry != null) {
      _hideOptions();
    } else {
      _showOptions();
    }
  }

  void _showOptions() {
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final cs = Theme.of(overlayContext).colorScheme;
        final isDark = Theme.of(overlayContext).brightness == Brightness.dark;
        final menuFill = Color.alphaBlend(
          cs.surface.withValues(alpha: isDark ? 0.88 : 0.92),
          cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.78 : 0.86),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideOptions,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.975 + value * 0.025,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: size.width,
                      maxWidth: size.width,
                      maxHeight: 280,
                    ),
                    child: AppGlassSurface(
                      borderRadius: 16,
                      padding: EdgeInsets.zero,
                      tone: AppGlassTone.panel,
                      nativeBackdrop: true,
                      staticMaterial: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: menuFill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.zero,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final option in widget.options)
                                    _MacGlassSelectOption<T>(
                                      value: option,
                                      label: widget.labelFor(option),
                                      selected: option == widget.value,
                                      onSelected: (value) {
                                        widget.onChanged(value);
                                        _hideOptions();
                                      },
                                      colorScheme: cs,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayEntry!);
    if (mounted) setState(() {});
  }

  void _hideOptions({bool rebuild = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final open = _overlayEntry != null;
    return SelectionContainer.disabled(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CompositedTransformTarget(
            link: _link,
            child: GestureDetector(
              key: _fieldKey,
              behavior: HitTestBehavior.opaque,
              onTap: _toggleOptions,
              child: AppGlassSurface(
                borderRadius: 12,
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                tone: AppGlassTone.control,
                nativeBackdrop: true,
                staticMaterial: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.labelFor(widget.value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.helper!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MacGlassSelectOption<T> extends StatefulWidget {
  final T value;
  final String label;
  final bool selected;
  final ValueChanged<T> onSelected;
  final ColorScheme colorScheme;

  const _MacGlassSelectOption({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.colorScheme,
  });

  @override
  State<_MacGlassSelectOption<T>> createState() =>
      _MacGlassSelectOptionState<T>();
}

class _MacGlassSelectOptionState<T> extends State<_MacGlassSelectOption<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final controls = appGlassControlPalette(context);
    final fill = widget.selected
        ? controls.activeFill(accentAlpha: 0.05)
        : _hovered
        ? controls.subtleNeutralOverlay(hovered: true, pressed: false)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: widget.selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ),
              if (widget.selected)
                Icon(Icons.check_rounded, size: 17, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Prompt 配置卡片 ───────────────────

class _PromptCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String hintText;
  final String emptyWarning;
  final String savedMessage;
  final String? helpText;
  final String Function() loadPrompt;
  final Future<void> Function(String) savePrompt;
  final void Function() resetPrompt;

  const _PromptCard({
    required this.title,
    required this.subtitle,
    required this.hintText,
    required this.emptyWarning,
    required this.savedMessage,
    this.helpText,
    required this.loadPrompt,
    required this.savePrompt,
    required this.resetPrompt,
  });

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.loadPrompt());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      AppFeedback.warning('Prompt 不能为空', widget.emptyWarning);
      return;
    }
    await widget.savePrompt(text);
    if (mounted) AppFeedback.success('Prompt 已保存', widget.savedMessage);
  }

  void _reset() {
    widget.resetPrompt();
    _controller.text = widget.loadPrompt();
    setState(() {});
    AppFeedback.success('已重置', 'Prompt 恢复为默认');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMac = Platform.isMacOS;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.helpText != null) ...[
          Text(
            widget.helpText!,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
        ],
        if (isMac)
          AppGlassTextField(
            controller: _controller,
            label: 'Prompt',
            hint: widget.hintText,
            helper: '${_controller.text.split('\n').length} 行',
            maxLines: 12,
            monospace: true,
          )
        else
          TextField(
            controller: _controller,
            maxLines: 12,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.hintText,
              helperText: '${_controller.text.split('\n').length} 行',
              helperStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        const SizedBox(height: 12),
        if (isMac)
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppGlassButton(
                  label: '保存此 Prompt',
                  onPressed: _save,
                  role: AppGlassButtonRole.primary,
                ),
                const SizedBox(width: 10),
                AppGlassButton(label: '重置此 Prompt', onPressed: _reset),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('保存')),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reset, child: const Text('默认')),
            ],
          ),
      ],
    );

    if (isMac) {
      return _MacInlineExpansion(
        title: widget.title,
        subtitle: widget.subtitle,
        child: content,
      );
    }

    final expansion = ExpansionTile(
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(widget.subtitle),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: content,
        ),
      ],
    );
    if (Platform.isAndroid) {
      return MobileSettingsPanel(child: expansion);
    }
    return Card(child: expansion);
  }
}

class _ConnectionTestResult {
  final bool ok;
  final String message;

  const _ConnectionTestResult(this.ok, this.message);
}

class _CredentialActions extends StatelessWidget {
  final bool useGlass;
  final bool testing;
  final Future<void> Function() onTest;
  final Future<bool> Function({bool showSuccess}) onSave;

  const _CredentialActions({
    required this.useGlass,
    required this.testing,
    required this.onTest,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final actions = useGlass
        ? <Widget>[
            AppGlassButton(
              label: testing ? '正在测试' : '测试连接',
              icon: testing ? Icons.sync_rounded : Icons.cable_rounded,
              onPressed: testing ? null : () => unawaited(onTest()),
            ),
            const SizedBox(width: 8),
            AppGlassButton(
              label: '保存认证',
              icon: Icons.save_rounded,
              onPressed: testing
                  ? null
                  : () => unawaited(onSave(showSuccess: true)),
              role: AppGlassButtonRole.primary,
            ),
          ]
        : <Widget>[
            OutlinedButton.icon(
              onPressed: testing ? null : () => unawaited(onTest()),
              icon: Icon(testing ? Icons.sync_rounded : Icons.cable_rounded),
              label: Text(testing ? '正在测试' : '测试连接'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: testing
                  ? null
                  : () => unawaited(onSave(showSuccess: true)),
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存认证'),
            ),
          ];
    return Align(
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [...actions]),
    );
  }
}

// ─── LLM 参数配置卡片 ────────────────────

class _AutoSavedSettingsTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final VoidCallback onCommit;
  final bool useGlass;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _AutoSavedSettingsTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onCommit,
    required this.useGlass,
    this.hint,
    this.helper,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    if (useGlass) {
      return AppGlassTextField(
        controller: controller,
        focusNode: focusNode,
        label: label,
        hint: hint,
        helper: helper,
        textInputAction: TextInputAction.done,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onFieldSubmitted: (_) => onCommit(),
      );
    }

    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.done,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: (_) => onCommit(),
    );
  }
}

class _LlmConfigCard extends StatefulWidget {
  final String title;
  final LlmConfig defaultConfig;
  final LlmConfig Function() loadConfig;
  final Future<void> Function(LlmConfig) saveConfig;
  final Future<void> Function() resetConfig;
  final bool showConcurrency;

  const _LlmConfigCard({
    required this.title,
    required this.defaultConfig,
    required this.loadConfig,
    required this.saveConfig,
    required this.resetConfig,
    this.showConcurrency = true,
  });

  @override
  State<_LlmConfigCard> createState() => _LlmConfigCardState();
}

class _LlmConfigCardState extends State<_LlmConfigCard> {
  late LlmConfig _config;
  late final TextEditingController _temperatureController;
  late final TextEditingController _concurrencyController;
  final _temperatureFocusNode = FocusNode();
  final _concurrencyFocusNode = FocusNode();
  Future<void> _writeQueue = Future.value();
  int _writeRevision = 0;

  static const _models = ['deepseek-v4-flash', 'deepseek-v4-pro'];
  static const _efforts = ['high', 'max'];
  static const _maxTokenOptions = [2048, 8192, 32768, 131072];

  @override
  void initState() {
    super.initState();
    _config = _normalizedConfig(widget.loadConfig());
    _temperatureController = TextEditingController(
      text: _config.temperature.toString(),
    );
    _concurrencyController = TextEditingController(
      text: _config.concurrency.toString(),
    );
    _temperatureFocusNode.addListener(_onTemperatureFocusChanged);
    _concurrencyFocusNode.addListener(_onConcurrencyFocusChanged);
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _concurrencyController.dispose();
    _temperatureFocusNode.dispose();
    _concurrencyFocusNode.dispose();
    super.dispose();
  }

  void _onTemperatureFocusChanged() {
    if (!_temperatureFocusNode.hasFocus) {
      unawaited(_saveTemperature());
    }
  }

  void _onConcurrencyFocusChanged() {
    if (!_concurrencyFocusNode.hasFocus) {
      unawaited(_saveConcurrency());
    }
  }

  LlmConfig _normalizedConfig(LlmConfig config) {
    return config.copyWith(maxTokens: _normalizeMaxTokens(config.maxTokens));
  }

  void _applyConfig(LlmConfig config) {
    final normalized = _normalizedConfig(config);
    _config = normalized;
    _temperatureController.text = normalized.temperature.toString();
    _concurrencyController.text = normalized.concurrency.toString();
  }

  int _normalizeMaxTokens(int value) {
    if (_maxTokenOptions.contains(value)) return value;
    return _maxTokenOptions.reduce((best, candidate) {
      final bestDistance = (best - value).abs();
      final candidateDistance = (candidate - value).abs();
      return candidateDistance < bestDistance ? candidate : best;
    });
  }

  Future<bool> _enqueueWrite(Future<void> Function() write) async {
    final revision = ++_writeRevision;
    final operation = _writeQueue.then((_) async {
      if (revision == _writeRevision) await write();
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );

    try {
      await operation;
      return true;
    } catch (_) {
      if (mounted && revision == _writeRevision) {
        setState(() => _applyConfig(widget.loadConfig()));
        AppFeedback.error('设置保存失败', '已恢复为上一次成功保存的参数');
      }
      return false;
    }
  }

  void _saveImmediately(LlmConfig config) {
    final normalized = _normalizedConfig(config);
    setState(() => _config = normalized);
    unawaited(_enqueueWrite(() => widget.saveConfig(normalized)));
  }

  Future<void> _saveTemperature() async {
    final temp = double.tryParse(_temperatureController.text.trim());
    if (temp == null || temp < 0 || temp > 2) {
      _temperatureController.text = _config.temperature.toString();
      AppFeedback.warning('已恢复原值', 'Temperature 请输入 0～2 之间的小数');
      return;
    }
    if (temp == _config.temperature) return;

    final next = _config.copyWith(temperature: temp);
    setState(() => _config = next);
    await _enqueueWrite(() => widget.saveConfig(next));
  }

  Future<void> _saveConcurrency() async {
    final concurrency = int.tryParse(_concurrencyController.text.trim());
    if (concurrency == null || concurrency < 1 || concurrency > 1024) {
      _concurrencyController.text = _config.concurrency.toString();
      AppFeedback.warning('已恢复原值', '并发数请输入 1～1024 之间的整数');
      return;
    }
    if (concurrency == _config.concurrency) return;

    final next = _config.copyWith(concurrency: concurrency);
    setState(() => _config = next);
    await _enqueueWrite(() => widget.saveConfig(next));
  }

  Future<void> _reset() async {
    setState(() => _applyConfig(widget.defaultConfig));
    if (await _enqueueWrite(widget.resetConfig) && mounted) {
      AppFeedback.success('${widget.title}已重置', '默认参数已立即保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    final content = isMac ? _buildMacContent() : _buildMobileContent();

    if (isMac) {
      return _MacInlineExpansion(
        title: widget.title,
        subtitle: widget.showConcurrency
            ? '${_config.model}  |  并发 ${_config.concurrency}'
            : '${_config.model}  |  单批串行',
        child: content,
      );
    }

    final expansion = ExpansionTile(
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        widget.showConcurrency
            ? '${_config.model}  |  并发 ${_config.concurrency}'
            : '${_config.model}  |  单批串行',
      ),
      children: [
        Padding(
          // 顶部预留 10px：第一个子项是带浮动 label 的下拉框（InputDecorator +
          // OutlineInputBorder），浮动起来的 label 会向上突出到自身布局框之外，
          // 而 ExpansionTile 内部对 body 用 ClipRect 裁切、外层 MobileSettingsPanel
          // 又是 Clip.antiAlias，top=0 会把 "模型" 等浮动文字的上半部分切掉。
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: content,
        ),
      ],
    );
    if (Platform.isAndroid) {
      return MobileSettingsPanel(child: expansion);
    }
    return Card(child: expansion);
  }

  Widget _buildMacContent() {
    return Column(
      children: [
        _MacGlassSegmentedField<String>(
          value: _config.model,
          options: _models,
          labelFor: (value) => value,
          label: '模型',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(model: value)),
        ),
        const SizedBox(height: 10),
        _MacGlassSegmentedField<bool>(
          value: _config.thinking,
          options: const [false, true],
          labelFor: (value) => value ? '开启' : '关闭',
          label: '思考模式',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(thinking: value)),
        ),
        if (_config.thinking) ...[
          const SizedBox(height: 10),
          _MacGlassSegmentedField<String>(
            value: _config.reasoningEffort,
            options: _efforts,
            labelFor: (value) => value == 'high' ? '标准 (high)' : '最大 (max)',
            label: '思考强度',
            onChanged: (value) =>
                _saveImmediately(_config.copyWith(reasoningEffort: value)),
          ),
        ],
        const SizedBox(height: 10),
        _AutoSavedSettingsTextField(
          controller: _temperatureController,
          focusNode: _temperatureFocusNode,
          label: 'Temperature',
          useGlass: true,
          helper: _config.thinking ? '思考模式下此参数不生效' : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onCommit: _saveTemperature,
        ),
        const SizedBox(height: 10),
        _MacGlassSegmentedField<int>(
          value: _config.maxTokens,
          options: _maxTokenOptions,
          labelFor: (value) => value >= 1024 ? '${value ~/ 1024}K' : '$value',
          label: '最大输出 (max_tokens)',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(maxTokens: value)),
        ),
        if (widget.showConcurrency) ...[
          const SizedBox(height: 10),
          _AutoSavedSettingsTextField(
            controller: _concurrencyController,
            focusNode: _concurrencyFocusNode,
            label: '并发数',
            useGlass: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onCommit: _saveConcurrency,
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: AppGlassButton(label: '重置此参数', onPressed: _reset),
        ),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Column(
      children: [
        MobileSettingsSelectField<String>(
          value: _config.model,
          options: _models,
          labelFor: (value) => value,
          label: '模型',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(model: value)),
        ),
        const SizedBox(height: 12),
        MobileSettingsSelectField<bool>(
          value: _config.thinking,
          options: const [false, true],
          labelFor: (value) => value ? '开启' : '关闭',
          label: '思考模式',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(thinking: value)),
        ),
        const SizedBox(height: 12),
        if (_config.thinking)
          MobileSettingsSelectField<String>(
            value: _config.reasoningEffort,
            options: _efforts,
            labelFor: (value) => value == 'high' ? '标准 (high)' : '最大 (max)',
            label: '思考强度',
            onChanged: (value) =>
                _saveImmediately(_config.copyWith(reasoningEffort: value)),
          ),
        if (_config.thinking) const SizedBox(height: 12),
        _AutoSavedSettingsTextField(
          controller: _temperatureController,
          focusNode: _temperatureFocusNode,
          label: 'Temperature',
          useGlass: false,
          helper: _config.thinking ? '思考模式下此参数不生效' : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onCommit: _saveTemperature,
        ),
        const SizedBox(height: 12),
        MobileSettingsSelectField<int>(
          value: _config.maxTokens,
          options: _maxTokenOptions,
          labelFor: (value) =>
              value >= 1024 ? '${value ~/ 1024}K' : value.toString(),
          label: '最大输出 (max_tokens)',
          onChanged: (value) =>
              _saveImmediately(_config.copyWith(maxTokens: value)),
        ),
        if (widget.showConcurrency) ...[
          const SizedBox(height: 12),
          _AutoSavedSettingsTextField(
            controller: _concurrencyController,
            focusNode: _concurrencyFocusNode,
            label: '并发数',
            useGlass: false,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onCommit: _saveConcurrency,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(onPressed: _reset, child: const Text('重置默认')),
        ),
      ],
    );
  }
}
