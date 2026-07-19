import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/constants/constants.dart';
import '../../pages/main/main_controller.dart';
import '../../pages/timeline/timeline_controller.dart';
import '../../router/app_pages.dart';
import '../../services/macos_app_menu_service.dart';
import '../../services/undo_service.dart';

class MacOSAppMenu extends StatefulWidget {
  const MacOSAppMenu({super.key, required this.child});

  final Widget child;

  @override
  State<MacOSAppMenu> createState() => _MacOSAppMenuState();
}

class _MacOSAppMenuState extends State<MacOSAppMenu> {
  static const _menuStateChannel = MethodChannel(
    'io.github.xraygit.autofolo/app_menu',
  );
  static const _projectUrl = 'https://github.com/X-Ray-git/auto-folo';
  static const _issuesUrl = 'https://github.com/X-Ray-git/auto-folo/issues';

  MacOSAppMenuService get _menuService => MacOSAppMenuService.instance;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    UndoService.historyRevision.addListener(_handleStateChanged);
    _menuService.revision.addListener(_handleStateChanged);
    FocusManager.instance.addListener(_handleStateChanged);
  }

  @override
  void dispose() {
    UndoService.historyRevision.removeListener(_handleStateChanged);
    _menuService.revision.removeListener(_handleStateChanged);
    FocusManager.instance.removeListener(_handleStateChanged);
    super.dispose();
  }

  void _handleStateChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() {});
      return;
    }
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final article = _menuService.activeArticleTarget;
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        _buildApplicationMenu(),
        _buildEditMenu(),
        _buildViewMenu(),
        _buildArticleMenu(article),
        _buildWindowMenu(),
        _buildHelpMenu(),
      ],
      child: widget.child,
    );
  }

  PlatformMenu _buildApplicationMenu() {
    return PlatformMenu(
      label: AppConstants.appName,
      menus: <PlatformMenuItem>[
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.about,
        ),
        PlatformMenuItem(
          label: '设置…',
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
          onSelected: _openSettings,
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    );
  }

  PlatformMenu _buildEditMenu() {
    final editingText = _editingText;
    final undoAction = UndoService.nextUndoAction;
    final redoAction = UndoService.nextRedoAction;
    return PlatformMenu(
      label: '编辑',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: editingText ? '撤销' : _historyLabel('撤销', undoAction),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: editingText || UndoService.canUndo
                  ? _performUndo
                  : null,
            ),
            PlatformMenuItem(
              label: editingText ? '重做' : _historyLabel('重做', redoAction),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: editingText || UndoService.canRedo
                  ? _performRedo
                  : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '剪切',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
              onSelected: editingText ? _cutText : null,
            ),
            PlatformMenuItem(
              label: '复制',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelected: _copyText,
            ),
            PlatformMenuItem(
              label: '粘贴',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelected: editingText ? _pasteText : null,
            ),
            PlatformMenuItem(
              label: '全选',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
              onSelected: _selectAllText,
            ),
          ],
        ),
      ],
    );
  }

  PlatformMenu _buildViewMenu() {
    return PlatformMenu(
      label: '显示',
      onOpen: _syncMenuStates,
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '全部文章',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit1,
                meta: true,
              ),
              onSelected: () => _selectSection(0),
            ),
            PlatformMenuItem(
              label: '垃圾拦截',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit2,
                meta: true,
              ),
              onSelected: () => _selectSection(1),
            ),
            PlatformMenuItem(
              label: '最近阅读',
              onSelected: () => _selectSection(2),
            ),
            PlatformMenuItem(
              label: '静默订阅源',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit0,
                meta: true,
              ),
              onSelected: _selectSilentFeeds,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenu(
              label: '文章范围',
              onOpen: _syncMenuStates,
              menus: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '未读',
                  onSelected: () => _setViewMode(TimelineViewMode.unread),
                ),
                PlatformMenuItem(
                  label: '全部',
                  onSelected: () => _setViewMode(TimelineViewMode.all),
                ),
              ],
            ),
            PlatformMenu(
              label: '排序',
              onOpen: _syncMenuStates,
              menus: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '最新优先',
                  onSelected: () => _setSortMode(TimelineSortMode.newest),
                ),
                PlatformMenuItem(
                  label: '长文优先',
                  onSelected: () => _setSortMode(TimelineSortMode.longest),
                ),
                PlatformMenuItem(
                  label: '短文优先',
                  onSelected: () => _setSortMode(TimelineSortMode.shortest),
                ),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '刷新',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyR,
                meta: true,
              ),
              onSelected: _refresh,
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
      ],
    );
  }

  PlatformMenu _buildArticleMenu(MacOSArticleMenuTarget? target) {
    final title = target?.article.title ?? '';
    final enabled = target != null;
    return PlatformMenu(
      label: '文章',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: enabled ? '在浏览器打开《${_truncate(title, 28)}》' : '在浏览器打开',
              onSelected: enabled ? target.openOriginal : null,
            ),
            PlatformMenuItem(
              label: '复制原文为 Markdown（C）',
              onSelected: enabled ? target.copyMarkdown : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: enabled
                  ? _truncate(target.primaryActionLabel, 34)
                  : '标为已读 / 恢复未读',
              onSelected: enabled ? target.performPrimaryAction : null,
            ),
            if (target?.keepReviewArticle != null)
              PlatformMenuItem(
                label: '保留《${_truncate(title, 28)}》',
                onSelected: target!.keepReviewArticle,
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '上一篇（←）',
              onSelected: target?.canGoPrevious() == true
                  ? target!.goPrevious
                  : null,
            ),
            PlatformMenuItem(
              label: '下一篇（→）',
              onSelected: target?.canGoNext() == true ? target!.goNext : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: target?.translationLabel() ?? '翻译',
              onSelected: target?.performTranslationAction(),
            ),
            PlatformMenuItem(
              label: target?.summaryLabel() ?? '摘要',
              onSelected: target?.performSummaryAction(),
            ),
          ],
        ),
      ],
    );
  }

  PlatformMenu _buildWindowMenu() {
    return PlatformMenu(
      label: '窗口',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: '关闭窗口',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
          onSelected: _closeWindow,
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
    );
  }

  PlatformMenu _buildHelpMenu() {
    return PlatformMenu(
      label: '帮助',
      menus: <PlatformMenuItem>[
        PlatformMenuItem(label: '键盘快捷键', onSelected: _openSettings),
        PlatformMenuItem(
          label: '项目主页',
          onSelected: () => _openUrl(_projectUrl),
        ),
        PlatformMenuItem(label: '报告问题', onSelected: () => _openUrl(_issuesUrl)),
      ],
    );
  }

  bool get _editingText {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _performUndo() {
    if (_invokeTextIntent(
      const UndoTextIntent(SelectionChangedCause.keyboard),
    )) {
      return;
    }
    unawaited(UndoService.undoLastAction());
  }

  void _performRedo() {
    if (_invokeTextIntent(
      const RedoTextIntent(SelectionChangedCause.keyboard),
    )) {
      return;
    }
    unawaited(UndoService.redoLastAction());
  }

  void _cutText() => _invokeTextIntent(
    const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  );

  void _copyText() => _invokeTextIntent(CopySelectionTextIntent.copy);

  void _pasteText() =>
      _invokeTextIntent(const PasteTextIntent(SelectionChangedCause.keyboard));

  void _selectAllText() => _invokeTextIntent(
    const SelectAllTextIntent(SelectionChangedCause.keyboard),
  );

  bool _invokeTextIntent(Intent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final action = Actions.maybeFind<Intent>(focusContext, intent: intent);
    if (action == null || !action.isEnabled(intent)) return false;
    Actions.invoke(focusContext, intent);
    return true;
  }

  void _openSettings() {
    _returnToMain();
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().selectIndex(3);
    }
  }

  void _selectSection(int index) {
    _returnToMain();
    if (!Get.isRegistered<MainController>()) return;
    if (index == 0 && Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().setTimelineScope();
    }
    Get.find<MainController>().selectIndex(index);
    _syncMenuStates();
  }

  void _selectSilentFeeds() {
    _returnToMain();
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().setTimelineScope(silent: true);
    }
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().selectIndex(0);
    }
    _syncMenuStates();
  }

  void _setViewMode(TimelineViewMode mode) {
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().setViewMode(mode);
    }
    _syncMenuStates();
  }

  void _setSortMode(TimelineSortMode mode) {
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().setSortMode(mode);
    }
    _syncMenuStates();
  }

  void _refresh() {
    if (Get.isRegistered<TimelineController>()) {
      unawaited(Get.find<TimelineController>().loadFeedsThenArticles());
    }
  }

  void _closeWindow() {
    unawaited(windowManager.close());
  }

  void _returnToMain() {
    if (Get.currentRoute != Routes.main) {
      Get.until((route) => route.settings.name == Routes.main);
    }
  }

  void _syncMenuStates() {
    final mainIndex = Get.isRegistered<MainController>()
        ? Get.find<MainController>().currentIndex.value
        : -1;
    final timeline = Get.isRegistered<TimelineController>()
        ? Get.find<TimelineController>()
        : null;
    final states = <Map<String, Object>>[
      _menuState(<String>[
        '显示',
        '全部文章',
      ], mainIndex == 0 && timeline?.isSilentSelected.value != true),
      _menuState(<String>['显示', '垃圾拦截'], mainIndex == 1),
      _menuState(<String>['显示', '最近阅读'], mainIndex == 2),
      _menuState(<String>[
        '显示',
        '静默订阅源',
      ], mainIndex == 0 && timeline?.isSilentSelected.value == true),
      _menuState(<String>[
        '显示',
        '文章范围',
        '未读',
      ], timeline?.selectedMode.value == TimelineViewMode.unread),
      _menuState(<String>[
        '显示',
        '文章范围',
        '全部',
      ], timeline?.selectedMode.value == TimelineViewMode.all),
      _menuState(<String>[
        '显示',
        '排序',
        '最新优先',
      ], timeline?.selectedSortMode.value == TimelineSortMode.newest),
      _menuState(<String>[
        '显示',
        '排序',
        '长文优先',
      ], timeline?.selectedSortMode.value == TimelineSortMode.longest),
      _menuState(<String>[
        '显示',
        '排序',
        '短文优先',
      ], timeline?.selectedSortMode.value == TimelineSortMode.shortest),
    ];
    unawaited(_menuStateChannel.invokeMethod<void>('setItemStates', states));
  }

  Map<String, Object> _menuState(List<String> path, bool selected) =>
      <String, Object>{'path': path, 'selected': selected};

  String _historyLabel(String verb, UndoAction? action) {
    if (action == null) return verb;
    if (action.type == UndoActionType.batchRead) {
      return '$verb“${action.actionName}” · ${action.articles.length} 篇';
    }
    final title = _truncate(action.article.title, 18);
    return '$verb“${action.actionName}” · 《$title》';
  }

  String _truncate(String value, int maxCharacters) {
    final characters = value.characters;
    if (characters.length <= maxCharacters) return value;
    return '${characters.take(maxCharacters - 1)}…';
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.parse(rawUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
