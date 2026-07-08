import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common/constants/constants.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../services/account_service.dart';
import '../../services/app_version_service.dart';
import '../../services/article_filter_service.dart';
import '../../services/llm_config.dart';
import '../../services/settings_backup_service.dart';
import '../../services/summary_service.dart';
import '../../services/translation_service.dart';
import '../../router/app_pages.dart';
import '../../utils/security_utils.dart';
import '../../utils/storage.dart';
import '../main/main_controller.dart';
import 'task_center_page.dart';

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
  final _clientIdController = TextEditingController();
  final _sessionIdController = TextEditingController();
  final _deepseekApiKeyController = TextEditingController();
  final _readSyncWindowDaysController = TextEditingController();
  final _articleContentMaxWidthController = TextEditingController();
  final _macosMaxFlingVelocityController = TextEditingController();
  final _macSettingsScrollController = ScrollController();
  final _macAuthKey = GlobalKey();
  final _macPreferencesKey = GlobalKey();
  final _macAiKey = GlobalKey();
  final _macPromptKey = GlobalKey();
  final _macShortcutsKey = GlobalKey();
  final _macAboutKey = GlobalKey();
  bool _obscureToken = true;
  bool _obscureClientId = true;
  bool _obscureSessionId = true;
  bool _obscureDeepseekKey = true;
  late String _appearanceMode;
  late String _badgeStrategy;
  late int _autoRetryMaxCount;

  @override
  void initState() {
    super.initState();
    _accountService = AccountService.instance;

    _loadPersistedSettings();
  }

  void _loadPersistedSettings() {
    _tokenController.text = _accountService.sessionToken ?? '';
    _clientIdController.text = _accountService.clientId ?? '';
    _sessionIdController.text = _accountService.sessionId ?? '';
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
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _clientIdController.dispose();
    _sessionIdController.dispose();
    _deepseekApiKeyController.dispose();
    _readSyncWindowDaysController.dispose();
    _articleContentMaxWidthController.dispose();
    _macosMaxFlingVelocityController.dispose();
    _macSettingsScrollController.dispose();
    super.dispose();
  }

  void _save() {
    final token = SecurityUtils.normalizeCredential(_tokenController.text);
    final clientId = SecurityUtils.normalizeCredential(
      _clientIdController.text,
    );
    final sessionId = SecurityUtils.normalizeCredential(
      _sessionIdController.text,
    );

    if (token.isEmpty || clientId.isEmpty || sessionId.isEmpty) {
      AppFeedback.warning('配置未保存', '请填写全部三项');
      return;
    }

    if (!SecurityUtils.isSafeCookieValue(token) ||
        !SecurityUtils.isSafeHeaderValue(clientId) ||
        !SecurityUtils.isSafeHeaderValue(sessionId)) {
      AppFeedback.error('配置未保存', '输入格式不合法，请检查是否包含换行或特殊分隔符');
      return;
    }

    _accountService.saveTokens(
      sessionToken: token,
      clientId: clientId,
      sessionId: sessionId,
    );

    // 保存 DeepSeek API key
    final deepseekKey = _deepseekApiKeyController.text.trim();
    if (deepseekKey.isNotEmpty) {
      TranslationService.setApiKey(deepseekKey);
      GStorage.setting.put('deepseek_api_key', deepseekKey);
    }

    final readWindowDays = int.tryParse(
      _readSyncWindowDaysController.text.trim(),
    );
    if (readWindowDays == null || readWindowDays < 1) {
      AppFeedback.warning('配置未保存', '已读拉取窗口请填写大于 0 的天数');
      return;
    }
    final articleContentMaxWidth = int.tryParse(
      _articleContentMaxWidthController.text.trim(),
    );
    if (articleContentMaxWidth == null ||
        articleContentMaxWidth < 480 ||
        articleContentMaxWidth > 1200) {
      AppFeedback.warning('配置未保存', '正文最大宽度请填写 480～1200 之间的整数');
      return;
    }
    final macosMaxFlingVelocity = int.tryParse(
      _macosMaxFlingVelocityController.text.trim(),
    );
    if (macosMaxFlingVelocity == null ||
        macosMaxFlingVelocity <
            NoOverscrollIndicatorBehavior.macosMinFlingVelocity ||
        macosMaxFlingVelocity >
            NoOverscrollIndicatorBehavior.macosMaxAllowedFlingVelocity) {
      AppFeedback.warning('配置未保存', 'macOS 滚动惯性上限请填写 1000～8000 之间的整数');
      return;
    }
    GStorage.setting.put(StorageKeys.readSyncWindowDays, readWindowDays);
    GStorage.setting.put(
      StorageKeys.articleContentMaxWidth,
      articleContentMaxWidth,
    );
    GStorage.setting.put(
      StorageKeys.macosMaxFlingVelocity,
      macosMaxFlingVelocity,
    );
    GStorage.setting.put(StorageKeys.appearanceMode, _appearanceMode);
    GStorage.setting.put(StorageKeys.badgeStrategy, _badgeStrategy);
    GStorage.setting.put('auto_retry_max_count', _autoRetryMaxCount);

    AppFeedback.success('配置已保存', '设置已更新');
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

  void _clear() {
    _tokenController.clear();
    _clientIdController.clear();
    _sessionIdController.clear();
    _deepseekApiKeyController.clear();
    _accountService.clearTokens();
    GStorage.setting.delete('deepseek_api_key');

    AppFeedback.info('配置已清除', '已移除本地配置');
  }

  Future<bool> _confirmSettingsExport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        const content =
            '导出的 JSON 会包含 Folo 登录凭据、DeepSeek API Key、Prompt 和订阅源偏好。'
            '请只保存或发送给你信任的位置。';
        if (Platform.isMacOS) {
          return _MacSettingsConfirmDialog(
            title: '导出配置',
            content: content,
            confirmLabel: '导出到剪贴板',
            onCancel: () => Get.back(result: false),
            onConfirm: () => Get.back(result: true),
          );
        }
        return AlertDialog(
          title: const Text('导出配置'),
          content: const Text(content),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('导出到剪贴板'),
            ),
          ],
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
            '将从剪贴板读取 Auto Folo 配置 JSON，并覆盖当前已保存的账号、AI、Prompt 和订阅源偏好设置。'
            '文章缓存、已读历史、摘要和翻译结果不会被导入。';
        if (Platform.isMacOS) {
          return _MacSettingsConfirmDialog(
            title: '导入配置',
            content: content,
            confirmLabel: '从剪贴板导入',
            onCancel: () => Get.back(result: false),
            onConfirm: () => Get.back(result: true),
          );
        }
        return AlertDialog(
          title: const Text('导入配置'),
          content: const Text(content),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('从剪贴板导入'),
            ),
          ],
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
      final summary = await SettingsBackupService.importFromClipboard();
      _accountService.reload();
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
        ? (Get.find<MainController>().isMacSidebarCollapsed.value
              ? 80.0
              : 290.0)
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
                        title: 'Folo API 认证',
                        subtitle: '登录凭据只保存在本机，用于请求 Folo API。',
                        child: Column(
                          children: [
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
                            _MacSettingsGrid(
                              children: [
                                AppGlassTextField(
                                  controller: _clientIdController,
                                  label: 'Client ID',
                                  hint: 'YlxGJddT...',
                                  suffixIcon: _visibilityToggleButton(
                                    obscured: _obscureClientId,
                                    onPressed: () {
                                      setState(
                                        () => _obscureClientId =
                                            !_obscureClientId,
                                      );
                                    },
                                  ),
                                  obscureText: _obscureClientId,
                                  textInputAction: TextInputAction.next,
                                ),
                                AppGlassTextField(
                                  controller: _sessionIdController,
                                  label: 'Session ID',
                                  hint: 'TepZonTA...',
                                  suffixIcon: _visibilityToggleButton(
                                    obscured: _obscureSessionId,
                                    onPressed: () {
                                      setState(
                                        () => _obscureSessionId =
                                            !_obscureSessionId,
                                      );
                                    },
                                  ),
                                  obscureText: _obscureSessionId,
                                  textInputAction: TextInputAction.next,
                                ),
                              ],
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
                        child: _MacSettingsGrid(
                          children: [
                            _MacGlassSegmentedField<String>(
                              value: _appearanceMode,
                              labelFor: _appearanceModeLabel,
                              options: const ['system', 'light', 'dark'],
                              label: '外观模式',
                              helper: '选择后立即生效；跟随系统会响应 macOS 外观变化',
                              onChanged: _setAppearanceMode,
                            ),
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
                              onChanged: (val) {
                                setState(() => _badgeStrategy = val);
                              },
                            ),
                            AppGlassTextField(
                              controller: _articleContentMaxWidthController,
                              label: '正文最大宽度（px）',
                              hint: '720',
                              helper: 'macOS 文章页生效；建议 640～800 之间调试',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                            AppGlassTextField(
                              controller: _macosMaxFlingVelocityController,
                              label: 'macOS 滚动惯性上限',
                              hint: '4500',
                              helper: '限制松手后的惯性滚动速度；范围 1000～8000，默认 4500',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                            AppGlassTextField(
                              controller: _readSyncWindowDaysController,
                              label: '已读拉取窗口（天）',
                              hint: '2',
                              helper: '后台静默拉取最近已读文章的时间范围',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
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
                              onChanged: (val) {
                                setState(() => _autoRetryMaxCount = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MacSettingsSection(
                        key: _macAiKey,
                        icon: Icons.auto_awesome_rounded,
                        title: 'AI 服务与模型参数',
                        subtitle: '翻译、摘要和过滤共用 DeepSeek API Key，各任务可单独调整模型参数。',
                        child: Column(
                          children: [
                            AppGlassTextField(
                              controller: _deepseekApiKeyController,
                              label: 'DeepSeek API Key',
                              hint: 'sk-...',
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
                            const SizedBox(height: 14),
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
                          children: [
                            _buildShortcutItem(context, 'Cmd + ,', '打开设置'),
                            _buildShortcutItem(context, 'Cmd + Z', '撤销最近一次已读'),
                            _buildShortcutItem(context, 'Esc', '关闭当前阅读文章'),
                            _buildShortcutItem(context, '↑ / ↓', '上下滚动文章'),
                            _buildShortcutItem(
                              context,
                              '← / →',
                              '切换上一篇 / 下一篇文章',
                            ),
                            _buildShortcutItem(context, 'Cmd + R', '刷新文章列表'),
                            _buildShortcutItem(context, 'M', '切换文章已读 / 未读状态'),
                          ],
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
            return Row(
              children: [
                Icon(
                  loggedIn ? Icons.check_circle : Icons.error_outline,
                  color: loggedIn ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? '已配置 Token' : '未配置 Token',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: loggedIn
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loggedIn ? '可以正常同步文章' : '需要填写 Folo API 认证',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                onPressed: _save,
                icon: Icons.save_rounded,
                label: '保存账号与偏好',
                role: AppGlassButtonRole.primary,
                expand: true,
              ),
              const SizedBox(height: 8),
              AppGlassButton(
                onPressed: _clear,
                icon: Icons.delete_outline_rounded,
                label: '清除账号',
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
          'Auto Folo v${AppVersionService.version}',
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (Platform.isMacOS) {
      return _buildMacOSScaffold(context, colorScheme);
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
                child: Row(
                  children: [
                    Icon(
                      _accountService.isLoggedIn.value
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: _accountService.isLoggedIn.value
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _accountService.isLoggedIn.value
                          ? '已配置 Token'
                          : '未配置 Token',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _accountService.isLoggedIn.value
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                  ],
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

          // Token 输入
          Text(
            'Folo API 认证',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '从 Folo Web 应用的 Cookie 中获取',
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
            controller: _clientIdController,
            decoration: InputDecoration(
              labelText: 'Client ID',
              hintText: 'YlxGJddT...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureClientId ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureClientId = !_obscureClientId);
                },
                icon: Icon(
                  _obscureClientId ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureClientId,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _sessionIdController,
            decoration: InputDecoration(
              labelText: 'Session ID',
              hintText: 'TepZonTA...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureSessionId ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureSessionId = !_obscureSessionId);
                },
                icon: Icon(
                  _obscureSessionId ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureSessionId,
            textInputAction: TextInputAction.next,
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
              if (val != null) setState(() => _badgeStrategy = val);
            },
          ),

          const SizedBox(height: 32),

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

          TextField(
            controller: _articleContentMaxWidthController,
            decoration: const InputDecoration(
              labelText: '正文最大宽度（px）',
              hintText: '720',
              border: OutlineInputBorder(),
              helperText: 'macOS 文章页生效；默认 720，建议 640～800 之间调试',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _macosMaxFlingVelocityController,
            decoration: const InputDecoration(
              labelText: 'macOS 滚动惯性上限',
              hintText: '4500',
              border: OutlineInputBorder(),
              helperText: '限制松手后的惯性滚动速度；范围 1000～8000，默认 4500',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),

          const SizedBox(height: 32),

          // DeepSeek 翻译服务
          Text(
            '翻译服务设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '使用 DeepSeek API 为文章提供翻译功能',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _deepseekApiKeyController,
            decoration: InputDecoration(
              labelText: 'DeepSeek API Key',
              hintText: 'sk-...',
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

          const SizedBox(height: 16),

          TextField(
            controller: _readSyncWindowDaysController,
            decoration: const InputDecoration(
              labelText: '已读拉取窗口（天）',
              hintText: '2',
              border: OutlineInputBorder(),
              helperText: '后台静默拉取最近已读文章的时间范围',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              if (val != null) setState(() => _autoRetryMaxCount = val);
            },
          ),

          const SizedBox(height: 24),

          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('保存')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  child: const Text('清除'),
                ),
              ),
            ],
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
                child: Column(
                  children: [
                    _buildShortcutItem(context, 'Cmd + ,', '打开设置'),
                    _buildShortcutItem(context, 'Cmd + Z', '撤销最近一次已读'),
                    _buildShortcutItem(context, 'Esc', '关闭当前阅读文章'),
                    _buildShortcutItem(context, '↑ / ↓', '上下滚动文章'),
                    _buildShortcutItem(context, '← / →', '切换上一篇 / 下一篇文章'),
                    _buildShortcutItem(context, 'Cmd + R', '刷新文章列表'),
                    _buildShortcutItem(context, 'M', '切换文章已读 / 未读状态'),
                  ],
                ),
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
                    'Auto Folo v${AppVersionService.version}',
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
                  color: appGlassActiveControlFill(context, accentAlpha: 0.05),
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

class _MacSettingsConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _MacSettingsConfirmDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
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
            child: SizedBox(
              height: 34,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final segmentWidth = constraints.maxWidth / options.length;
                  return Stack(
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
                          staticMaterial: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: appGlassActiveControlFill(
                                context,
                                accentAlpha: 0.045,
                              ),
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
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      tone: AppGlassTone.panel,
                      nativeBackdrop: true,
                      staticMaterial: true,
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
    final fill = widget.selected
        ? appGlassActiveControlFill(context, accentAlpha: 0.05)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.035)
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
        Row(
          children: [
            Expanded(
              child: isMac
                  ? AppGlassButton(
                      label: '保存此 Prompt',
                      onPressed: _save,
                      role: AppGlassButtonRole.primary,
                      expand: true,
                    )
                  : FilledButton(onPressed: _save, child: const Text('保存')),
            ),
            const SizedBox(width: 12),
            isMac
                ? AppGlassButton(label: '重置此 Prompt', onPressed: _reset)
                : OutlinedButton(onPressed: _reset, child: const Text('默认')),
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

    return Card(
      child: ExpansionTile(
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
      ),
    );
  }
}

// ─── LLM 参数配置卡片 ────────────────────

class _LlmConfigCard extends StatefulWidget {
  final String title;
  final LlmConfig defaultConfig;
  final LlmConfig Function() loadConfig;
  final Future<void> Function(LlmConfig) saveConfig;
  final void Function() resetConfig;

  const _LlmConfigCard({
    required this.title,
    required this.defaultConfig,
    required this.loadConfig,
    required this.saveConfig,
    required this.resetConfig,
  });

  @override
  State<_LlmConfigCard> createState() => _LlmConfigCardState();
}

class _LlmConfigCardState extends State<_LlmConfigCard> {
  late String _model;
  late bool _thinking;
  late String _reasoningEffort;
  late String _temperature;
  late int _maxTokens;
  late int _concurrency;

  static const _models = ['deepseek-v4-flash', 'deepseek-v4-pro'];
  static const _efforts = ['high', 'max'];
  static const _maxTokenOptions = [2048, 8192, 32768, 131072];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final c = widget.loadConfig();
    _model = c.model;
    _thinking = c.thinking;
    _reasoningEffort = c.reasoningEffort;
    _temperature = c.temperature.toString();
    _maxTokens = _normalizeMaxTokens(c.maxTokens);
    _concurrency = c.concurrency;
  }

  int _normalizeMaxTokens(int value) {
    if (_maxTokenOptions.contains(value)) return value;
    return _maxTokenOptions.reduce((best, candidate) {
      final bestDistance = (best - value).abs();
      final candidateDistance = (candidate - value).abs();
      return candidateDistance < bestDistance ? candidate : best;
    });
  }

  void _reset() {
    widget.resetConfig();
    _load();
    setState(() {});
  }

  Future<void> _save() async {
    final temp = double.tryParse(_temperature.trim());
    if (temp == null || temp < 0 || temp > 2) {
      if (mounted) {
        AppFeedback.warning('Temperature 无效', '请输入 0~2 之间的小数');
      }
      return;
    }
    await widget.saveConfig(
      LlmConfig(
        model: _model,
        thinking: _thinking,
        reasoningEffort: _reasoningEffort,
        temperature: temp,
        maxTokens: _maxTokens,
        concurrency: _concurrency,
      ),
    );
    if (mounted) {
      AppFeedback.success('${widget.title}已保存', '新配置将从下一次请求生效');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMac = Platform.isMacOS;
    final content = isMac
        ? _buildMacContent(context, cs)
        : _buildMobileContent(cs);

    if (isMac) {
      return _MacInlineExpansion(
        title: widget.title,
        subtitle: '$_model  |  并发 $_concurrency',
        child: content,
      );
    }

    return Card(
      child: ExpansionTile(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('$_model  |  并发 $_concurrency'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildMacContent(BuildContext context, ColorScheme cs) {
    return Column(
      children: [
        _MacGlassSegmentedField<String>(
          value: _model,
          options: _models,
          labelFor: (value) => value,
          label: '模型',
          onChanged: (value) => setState(() => _model = value),
        ),
        const SizedBox(height: 10),
        _MacGlassSegmentedField<bool>(
          value: _thinking,
          options: const [false, true],
          labelFor: (value) => value ? '开启' : '关闭',
          label: '思考模式',
          onChanged: (value) => setState(() => _thinking = value),
        ),
        if (_thinking) ...[
          const SizedBox(height: 10),
          _MacGlassSegmentedField<String>(
            value: _reasoningEffort,
            options: _efforts,
            labelFor: (value) => value == 'high' ? '标准 (high)' : '最大 (max)',
            label: '思考强度',
            onChanged: (value) => setState(() => _reasoningEffort = value),
          ),
        ],
        const SizedBox(height: 10),
        AppGlassTextField(
          initialValue: _temperature,
          label: 'Temperature',
          helper: _thinking ? '思考模式下此参数不生效' : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _temperature = v,
        ),
        const SizedBox(height: 10),
        _MacGlassSegmentedField<int>(
          value: _normalizeMaxTokens(_maxTokens),
          options: _maxTokenOptions,
          labelFor: (value) => value >= 1024 ? '${value ~/ 1024}K' : '$value',
          label: '最大输出 (max_tokens)',
          onChanged: (value) => setState(() => _maxTokens = value),
        ),
        const SizedBox(height: 10),
        AppGlassTextField(
          initialValue: _concurrency.toString(),
          label: '并发数',
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed > 0 && parsed <= 1024) {
              _concurrency = parsed;
            }
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppGlassButton(
                label: '保存此参数',
                onPressed: _save,
                role: AppGlassButtonRole.primary,
                expand: true,
              ),
            ),
            const SizedBox(width: 12),
            AppGlassButton(label: '重置此参数', onPressed: _reset),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileContent(ColorScheme cs) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _model,
          decoration: const InputDecoration(
            labelText: '模型',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _models
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => setState(() => _model = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          initialValue: _thinking,
          decoration: const InputDecoration(
            labelText: '思考模式',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: false, child: Text('关闭')),
            DropdownMenuItem(value: true, child: Text('开启')),
          ],
          onChanged: (v) => setState(() => _thinking = v!),
        ),
        const SizedBox(height: 12),
        if (_thinking)
          DropdownButtonFormField<String>(
            initialValue: _reasoningEffort,
            decoration: const InputDecoration(
              labelText: '思考强度',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _efforts
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e == 'high' ? '标准 (high)' : '最大 (max)'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _reasoningEffort = v!),
          ),
        if (_thinking) const SizedBox(height: 12),
        TextFormField(
          initialValue: _temperature,
          decoration: InputDecoration(
            labelText: 'Temperature',
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: _thinking ? '思考模式下此参数不生效' : null,
            helperStyle: TextStyle(color: cs.onSurfaceVariant),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: true,
          onChanged: (v) => _temperature = v,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _maxTokenOptions.contains(_maxTokens)
              ? _maxTokens
              : _maxTokenOptions.first,
          decoration: const InputDecoration(
            labelText: '最大输出 (max_tokens)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _maxTokenOptions
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t >= 1024 ? '${t ~/ 1024}K' : t.toString()),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _maxTokens = v!),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _concurrency.toString(),
          decoration: const InputDecoration(
            labelText: '并发数',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed > 0 && parsed <= 1024) {
              _concurrency = parsed;
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _reset, child: const Text('重置默认')),
          ],
        ),
      ],
    );
  }
}
