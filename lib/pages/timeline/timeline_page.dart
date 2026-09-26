import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/refresh_aware_scroll_physics.dart';
import '../../common/widgets/shimmer_card.dart';
import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/implicitly_animated_list.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/app_glass_selection_button.dart';
import '../../common/widgets/app_glass_sync_button.dart';
import '../../common/widgets/mac_header_pane.dart';
import '../../common/widgets/macos_window_drag_area.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../common/widgets/mobile_edge_fade.dart';
import '../../common/widgets/mobile_viewport_insets.dart';
import '../../common/widgets/article_card_chrome.dart';
import '../../common/widgets/mac_split_article_list_coordinator.dart';

import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/mac_article_shortcut_service.dart';
import '../../services/article_markdown_export_service.dart';
import '../../services/external_link_service.dart';
import '../../services/feed_silent_settings_service.dart';
import '../../services/undo_service.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../widgets/article_card.dart';
import 'timeline_controller.dart';
import '../../utils/scroll_utils.dart';

enum _SilentBatchAction { copy, save, copyAndMarkRead, saveAndMarkRead }

class _TimelineScopeSnapshot {
  final bool silent;
  final String? silentGroupId;
  final String? feedId;
  final String? category;

  const _TimelineScopeSnapshot({
    required this.silent,
    required this.silentGroupId,
    required this.feedId,
    required this.category,
  });
}

class _SourceReturnContext {
  final _TimelineScopeSnapshot previousScope;
  final String destinationFeedId;
  final String articleEntryId;
  final double timelineScrollOffset;
  final double articleScrollOffset;
  final bool showTranslation;
  final bool showSummary;

  const _SourceReturnContext({
    required this.previousScope,
    required this.destinationFeedId,
    required this.articleEntryId,
    required this.timelineScrollOffset,
    required this.articleScrollOffset,
    required this.showTranslation,
    required this.showSummary,
  });

  bool matchesDestination(TimelineController controller) {
    return !controller.isSilentSelected.value &&
        controller.selectedFeedId.value == destinationFeedId &&
        controller.selectedCategory.value == null;
  }
}

class _PendingArticleRestore {
  final String entryId;
  final double scrollOffset;
  final bool showTranslation;
  final bool showSummary;

  const _PendingArticleRestore({
    required this.entryId,
    required this.scrollOffset,
    required this.showTranslation,
    required this.showSummary,
  });
}

extension on _SilentBatchAction {
  bool get writesClipboard =>
      this == _SilentBatchAction.copy ||
      this == _SilentBatchAction.copyAndMarkRead;

  bool get writesFile =>
      this == _SilentBatchAction.save ||
      this == _SilentBatchAction.saveAndMarkRead;

  bool get marksRead =>
      this == _SilentBatchAction.copyAndMarkRead ||
      this == _SilentBatchAction.saveAndMarkRead;
}

class _SilentBatchSelectionIndicator extends StatelessWidget {
  final bool selected;
  final VoidCallback onPressed;

  const _SilentBatchSelectionIndicator({
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      checked: selected,
      label: selected ? '取消选择文章' : '选择文章',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 26,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? cs.primary
                      : cs.surface.withValues(alpha: isDark ? 0.76 : 0.88),
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.58),
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 13, color: cs.onPrimary)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineAnimationProbe {
  static const bool _requested = bool.fromEnvironment(
    'FOURIER_ANIMATION_PROBE',
  );
  static final Stopwatch _clock = Stopwatch()..start();
  static String? _activeEntryId;
  static String? _activeSource;
  static int _startedAtUs = 0;
  static bool _timingsInstalled = false;
  static final List<String> _bufferedLines = <String>[];
  static double _frameBudgetMs = 1000 / 60;
  static int _sessionGeneration = 0;

  static bool get enabled => _requested && kDebugMode && Platform.isMacOS;

  static void begin(
    String entryId, {
    required String source,
    required String event,
    Map<String, Object?> fields = const {},
  }) {
    if (!enabled) return;
    _installTimingsProbe();
    _activeEntryId = entryId;
    _activeSource = source;
    _startedAtUs = _clock.elapsedMicroseconds;
    final generation = ++_sessionGeneration;
    final refreshRate = fields['refreshHz'];
    if (refreshRate is num && refreshRate > 0) {
      _frameBudgetMs = 1000 / refreshRate.toDouble();
    }
    _bufferedLines.clear();
    log(entryId, event, fields);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_activeEntryId != entryId || _sessionGeneration != generation) {
        return;
      }
      log(entryId, 'session.timeout');
      _flushBufferedLines();
      _activeEntryId = null;
      _activeSource = null;
    });
  }

  static void log(
    String entryId,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!enabled || _activeEntryId != entryId) return;
    final elapsedMs = (_clock.elapsedMicroseconds - _startedAtUs) / 1000;
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    _bufferedLines.add(
      '[TimelineAnimationProbe +${elapsedMs.toStringAsFixed(1)}ms '
      'id=${shortId(entryId)} source=$_activeSource] '
      '$event${details.isEmpty ? '' : ' $details'}',
    );
  }

  static void finish(String entryId) {
    if (!enabled || _activeEntryId != entryId) return;
    final generation = _sessionGeneration;
    log(entryId, 'session.finished');
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (_activeEntryId != entryId || _sessionGeneration != generation) {
        return;
      }
      log(entryId, 'session.closed');
      _flushBufferedLines();
      _activeEntryId = null;
      _activeSource = null;
    });
  }

  static void _flushBufferedLines() {
    if (_bufferedLines.isEmpty) return;
    final lines = List<String>.from(_bufferedLines);
    _bufferedLines.clear();
    for (final line in lines) {
      debugPrint(line, wrapWidth: 2000);
    }
  }

  static void logTap(
    String entryId, {
    required bool isDoubleTap,
    required int elapsedSincePreviousTapMs,
  }) {
    if (!enabled) return;
    debugPrint(
      '[TimelineTapProbe] id=${shortId(entryId)} '
      'double=$isDoubleTap previousMs=$elapsedSincePreviousTapMs',
      wrapWidth: 2000,
    );
  }

  static void _installTimingsProbe() {
    if (_timingsInstalled) return;
    _timingsInstalled = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      final entryId = _activeEntryId;
      if (entryId == null) return;
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMicroseconds / 1000;
        final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
        if (buildMs < _frameBudgetMs && rasterMs < _frameBudgetMs) continue;
        log(entryId, 'frame.slow', {
          'buildMs': buildMs.toStringAsFixed(1),
          'rasterMs': rasterMs.toStringAsFixed(1),
          'budgetMs': _frameBudgetMs.toStringAsFixed(1),
          'totalMs': timing.totalSpan.inMicroseconds ~/ 1000,
        });
      }
    });
  }

  static String shortId(String? entryId) {
    if (entryId == null) return 'none';
    if (entryId.length <= 8) return entryId;
    return entryId.substring(entryId.length - 8);
  }
}

/// 时间线页 — 本地文章库（未读/全部/已读）
class TimelinePage extends StatefulWidget {
  final bool showAppBar;

  const TimelinePage({super.key, this.showAppBar = true});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  static const double _defaultMacTimelineItemExtent = 124;

  late final TimelineController controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _emptyDetailFocusNode = FocusNode(
    debugLabel: 'timeline-empty-detail',
  );
  final _refreshKey = GlobalKey<custom_refresh.RefreshIndicatorState>();
  late final _refreshPhysics = RefreshAwareScrollPhysics(
    refreshKey: _refreshKey,
  );
  DateTime? _lastTapTime;
  String? _lastArticleTapEntryId;
  DateTime? _lastArticleTapAt;
  late final MacSplitArticleListCoordinator _listCoordinator;
  final Map<String, ArticleModel> _pendingOriginalOpenAfterRemoval = {};
  double _estimatedMacTimelineItemExtent = _defaultMacTimelineItemExtent;
  bool _isHandlingMacReadShortcut = false;
  Worker? _undoPrepareWorker;
  Worker? _undoRestoreWorker;
  Worker? _batchScopeWorker;
  bool _isSilentBatchMode = false;
  bool _isSilentBatchProcessing = false;
  final Set<String> _silentBatchSelection = {};
  final Map<String, GlobalKey<_TimelineArticleCardHostState>>
  _timelineCardHostKeys = {};
  final Set<String> _preAnimatedRemovals = {};
  final Map<String, ArticleModel> _preAnimatedRemovalArticles = {};
  final Set<String> _pendingRemovalCompletions = {};
  final Set<String> _pendingAnimatedEntrances = {};
  final Map<String, UndoRestoreEvent> _pendingUndoSelectionRestores = {};
  _SourceReturnContext? _sourceReturnContext;
  _PendingArticleRestore? _pendingArticleRestore;
  bool _isRestoringSourceContext = false;
  int _sourceScopeValidationGeneration = 0;

  Map<String, GlobalKey> get _itemKeys => _listCoordinator.itemKeys;

  bool get _isSilentGroupScope =>
      controller.isSilentSelected.value &&
      controller.selectedSilentGroupId.value != null &&
      controller.selectedFeedId.value == null &&
      controller.selectedCategory.value == null;

  @override
  void initState() {
    super.initState();
    controller = Get.put(TimelineController());
    _listCoordinator = MacSplitArticleListCoordinator(
      articles: () => controller.articles.toList(),
      selectedArticle: () => controller.selectedArticle.value,
      setSelectedArticle: (article) =>
          controller.selectedArticle.value = article,
      revealArticle: _scrollToArticle,
    );
    controller.bindScrollToTopHandler(_scrollToTop);
    _undoPrepareWorker = ever(
      UndoService.preparingRestoreAction,
      _handleUndoPrepareEvent,
    );
    _undoRestoreWorker = ever(
      UndoService.restoredAction,
      _handleUndoRestoreEvent,
    );
    _batchScopeWorker = everAll(
      [
        controller.isSilentSelected,
        controller.selectedFeedId,
        controller.selectedCategory,
        controller.selectedSilentGroupId,
      ],
      (_) {
        if (_isSilentBatchMode) {
          setState(_resetSilentBatchState);
        }
        _scheduleSourceReturnValidation();
      },
    );
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
      MacArticleShortcutService.instance.register(
        this,
        isActive: () =>
            mounted &&
            _isActiveMacTimeline &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        hasSelection: () => controller.selectedArticle.value != null,
        selectBoundary: (direction) {
          _selectRelativeArticle(direction);
          return controller.articles.isNotEmpty;
        },
      );
      UndoService.registerRedoPreparation(
        this,
        isActive: () =>
            mounted &&
            _isActiveMacTimeline &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        prepare: _prepareRedo,
      );
    }
  }

  @override
  void dispose() {
    controller.bindScrollToTopHandler(null);
    controller.silentBatchProcessing.value = false;
    UndoService.flushDeferredHistoryNotification();
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
      MacArticleShortcutService.instance.unregister(this);
      UndoService.unregisterRedoPreparation(this);
    }
    _listCoordinator.dispose();
    _undoPrepareWorker?.dispose();
    _undoRestoreWorker?.dispose();
    _batchScopeWorker?.dispose();
    _scrollController.dispose();
    _emptyDetailFocusNode.dispose();
    super.dispose();
  }

  void _clearSelectionAndFocusEmptyDetail() {
    controller.selectedArticle.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isActiveMacTimeline) {
        _emptyDetailFocusNode.requestFocus();
      }
    });
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (!_isActiveMacTimeline) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;

    if (_isSilentBatchMode) {
      _exitSilentBatchMode();
      return true;
    }
    // The article view owns the first Esc while a destination article is open.
    if (controller.selectedArticle.value != null) return false;
    if (_sourceReturnContext == null) {
      if (!Get.isRegistered<MainController>()) return false;
      return Get.find<MainController>().tryReturnFromTimelineSource(
        silent: controller.isSilentSelected.value,
        feedId: controller.selectedFeedId.value,
        category: controller.selectedCategory.value,
      );
    }

    _restoreSourceContext();
    return true;
  }

  void _scheduleSourceReturnValidation() {
    final generation = ++_sourceScopeValidationGeneration;
    Future<void>.microtask(() {
      if (!mounted || generation != _sourceScopeValidationGeneration) return;
      final returnContext = _sourceReturnContext;
      if (returnContext != null &&
          !_isRestoringSourceContext &&
          !returnContext.matchesDestination(controller)) {
        _sourceReturnContext = null;
        _pendingArticleRestore = null;
      }
      if (Get.isRegistered<MainController>()) {
        Get.find<MainController>().validateTimelineSourceNavigation(
          silent: controller.isSilentSelected.value,
          feedId: controller.selectedFeedId.value,
          category: controller.selectedCategory.value,
        );
      }
    });
  }

  void _openArticleSource(ArticleSourceOpenRequest request) {
    final feedId = request.article.feedId.trim();
    if (feedId.isEmpty) return;

    final alreadyInDestination =
        !controller.isSilentSelected.value &&
        controller.selectedFeedId.value == feedId &&
        controller.selectedCategory.value == null;
    if (alreadyInDestination) return;

    _sourceReturnContext = _SourceReturnContext(
      previousScope: _TimelineScopeSnapshot(
        silent: controller.isSilentSelected.value,
        silentGroupId: controller.selectedSilentGroupId.value,
        feedId: controller.selectedFeedId.value,
        category: controller.selectedCategory.value,
      ),
      destinationFeedId: feedId,
      articleEntryId: request.article.entryId,
      timelineScrollOffset: _scrollController.hasClients
          ? _scrollController.offset
          : 0,
      articleScrollOffset: request.articleScrollOffset,
      showTranslation: request.showTranslation,
      showSummary: request.showSummary,
    );
    _pendingArticleRestore = null;
    controller.setTimelineScope(feedId: feedId);
  }

  void _restoreSourceContext() {
    final returnContext = _sourceReturnContext;
    if (returnContext == null) return;

    _isRestoringSourceContext = true;
    _sourceReturnContext = null;
    _pendingArticleRestore = _PendingArticleRestore(
      entryId: returnContext.articleEntryId,
      scrollOffset: returnContext.articleScrollOffset,
      showTranslation: returnContext.showTranslation,
      showSummary: returnContext.showSummary,
    );

    final scope = returnContext.previousScope;
    controller.setTimelineScope(
      silent: scope.silent,
      silentGroupId: scope.silentGroupId,
      feedId: scope.feedId,
      category: scope.category,
    );

    ArticleModel? article;
    for (final candidate in controller.allArticles) {
      if (candidate.entryId == returnContext.articleEntryId) {
        article = candidate;
        break;
      }
    }
    if (article != null) {
      controller.selectedArticle.value = article;
    } else {
      _pendingArticleRestore = null;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        final target = returnContext.timelineScrollOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        _scrollController.jumpTo(target.toDouble());
      }
      _isRestoringSourceContext = false;
    });
  }

  _PendingArticleRestore? _takeArticleRestore(String entryId) {
    final restore = _pendingArticleRestore;
    if (restore == null || restore.entryId != entryId) return null;
    _pendingArticleRestore = null;
    return restore;
  }

  void _enterSilentBatchMode() {
    if (!Platform.isMacOS || !_isSilentGroupScope) return;
    setState(() {
      _isSilentBatchMode = true;
      _silentBatchSelection.clear();
    });
  }

  void _exitSilentBatchMode() {
    if (_isSilentBatchProcessing) return;
    setState(_resetSilentBatchState);
  }

  void _resetSilentBatchState() {
    _isSilentBatchMode = false;
    _isSilentBatchProcessing = false;
    _silentBatchSelection.clear();
    controller.silentBatchProcessing.value = false;
  }

  void _toggleSilentBatchArticle(String entryId) {
    if (!_isSilentBatchMode || _isSilentBatchProcessing) return;
    setState(() {
      if (!_silentBatchSelection.add(entryId)) {
        _silentBatchSelection.remove(entryId);
      }
    });
  }

  void _toggleAllSilentBatchArticles() {
    if (!_isSilentBatchMode || _isSilentBatchProcessing) return;
    final visibleIds = controller.articles
        .map((article) => article.entryId)
        .toSet();
    setState(() {
      if (visibleIds.isNotEmpty &&
          visibleIds.every(_silentBatchSelection.contains)) {
        _silentBatchSelection.clear();
      } else {
        _silentBatchSelection
          ..clear()
          ..addAll(visibleIds);
      }
    });
  }

  List<ArticleModel> get _selectedSilentBatchArticles => controller.articles
      .where((article) => _silentBatchSelection.contains(article.entryId))
      .toList(growable: false);

  int get _activeSilentBatchSelectedCount =>
      _selectedSilentBatchArticles.length;

  Future<void> _performSilentBatchAction(_SilentBatchAction action) async {
    if (_isSilentBatchProcessing) return;
    final articles = _selectedSilentBatchArticles;
    if (articles.isEmpty) {
      AppFeedback.warning('尚未选择文章', '请先勾选要导出的静默文章');
      return;
    }

    setState(() => _isSilentBatchProcessing = true);
    controller.silentBatchProcessing.value = true;
    try {
      final markdown = await ArticleMarkdownExportService.buildBatch(articles);
      if (markdown.trim().isEmpty) {
        AppFeedback.warning('暂无可导出内容', '所选文章没有可用的标题、链接或正文');
        return;
      }

      if (action.writesClipboard) {
        await Clipboard.setData(ClipboardData(text: markdown));
      } else if (action.writesFile) {
        final saved = await _saveSilentBatchMarkdown(markdown);
        if (!saved) return;
      }

      if (action.marksRead) {
        final result = await UndoService.markBatchAsRead(articles);
        final changedIds = result.changedArticles
            .map((article) => article.entryId)
            .toSet();
        if (changedIds.contains(controller.selectedArticle.value?.entryId)) {
          controller.selectedArticle.value = null;
        }
        if (!result.allApplied) {
          if (result.changedArticles.isEmpty) {
            AppFeedback.error('导出成功，批量已读失败', '服务端未改变任何文章状态，可以直接重试');
          } else {
            AppFeedback.warning(
              '导出成功，部分标为已读',
              '已标记 ${result.changedArticles.length} 篇；其余 ${result.unchangedArticles.length} 篇仍保持未读',
            );
          }
          return;
        }
        controller.selectedArticle.value = null;
        if (!mounted) return;
        setState(_resetSilentBatchState);
        AppFeedback.success('已导出并标记已读', '已处理 ${articles.length} 篇静默文章');
        return;
      }

      AppFeedback.success(
        action.writesClipboard ? '已复制 Markdown' : '已保存 Markdown',
        '已导出 ${articles.length} 篇静默文章',
      );
    } catch (error) {
      AppFeedback.error('批量导出失败', error.toString());
    } finally {
      if (mounted && _isSilentBatchMode) {
        setState(() => _isSilentBatchProcessing = false);
      }
      controller.silentBatchProcessing.value = false;
    }
  }

  Future<bool> _saveSilentBatchMarkdown(String markdown) async {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final suggestedName =
        'fourier-silent-${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}.md';
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
    );
    if (location == null) return false;
    await File(location.path).writeAsString(markdown, flush: true);
    return true;
  }

  void _onAppBarTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _scrollToTop();
      _lastTapTime = null;
    } else {
      _lastTapTime = now;
    }
  }

  Future<void> _scrollToTop() async {
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _selectRelativeArticle(int delta, {bool scrollTo = true}) {
    if (Platform.isMacOS && _listCoordinator.isRemovingSelectedArticle) return;

    final list = controller.articles;
    if (list.isEmpty) return;

    final selected = controller.selectedArticle.value;
    if (selected == null) {
      final next = delta < 0 ? list.last : list.first;
      controller.selectedArticle.value = next;
      if (scrollTo) _scrollToArticle(next.entryId);
      return;
    }

    final currentIndex = list.indexWhere((a) => a.entryId == selected.entryId);
    if (currentIndex != -1) {
      final nextIndex = (currentIndex + delta).clamp(0, list.length - 1);
      controller.selectedArticle.value = list[nextIndex];
      if (scrollTo) _scrollToArticle(list[nextIndex].entryId);
      return;
    }

    // 在当前过滤后的列表中找不到（通常是因为刚被标记为已读，从未读列表中消失）
    // 回退到未过滤的底层全量列表寻找其绝对坐标
    final allList = controller.allArticles;
    final allIndex = allList.indexWhere((a) => a.entryId == selected.entryId);

    if (allIndex != -1) {
      // 提前构建哈希集合，将寻找过程降为 O(N)，避免 O(N^2) 导致 UI 卡顿
      final listEntryIds = list.map((a) => a.entryId).toSet();

      if (delta > 0) {
        // 向后寻找下一个存在的文章
        for (int i = allIndex + 1; i < allList.length; i++) {
          if (listEntryIds.contains(allList[i].entryId)) {
            controller.selectedArticle.value = allList[i];
            if (scrollTo) _scrollToArticle(allList[i].entryId);
            return;
          }
        }
        // 向后找尽，停留在当前可用列表的最后一篇
        controller.selectedArticle.value = list.last;
        if (scrollTo) _scrollToArticle(list.last.entryId);
      } else {
        // 向前寻找上一个存在的文章
        for (int i = allIndex - 1; i >= 0; i--) {
          if (listEntryIds.contains(allList[i].entryId)) {
            controller.selectedArticle.value = allList[i];
            if (scrollTo) _scrollToArticle(allList[i].entryId);
            return;
          }
        }
        // 向前找尽，停留在当前可用列表的第一篇
        controller.selectedArticle.value = list.first;
        if (scrollTo) _scrollToArticle(list.first.entryId);
      }
    } else {
      // 极端兜底情况：全量列表里都找不到
      controller.selectedArticle.value = list.first;
      if (scrollTo) _scrollToArticle(list.first.entryId);
    }
  }

  void _scrollToArticle(String entryId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_ensureBuiltArticleVisible(entryId)) return;
      if (!Platform.isMacOS) return;
      unawaited(_scrollToVirtualizedArticle(entryId));
    });
  }

  bool _ensureBuiltArticleVisible(String entryId, {int durationMs = 250}) {
    final context = _itemKeys[entryId]?.currentContext;
    if (context == null) return false;

    _updateEstimatedMacTimelineItemExtent(context);
    ScrollUtils.ensureVisible(context, durationMs: durationMs);
    return true;
  }

  Future<void> _scrollToVirtualizedArticle(String entryId) async {
    if (!_scrollController.hasClients) return;

    final targetIndex = controller.articles.indexWhere(
      (article) => article.entryId == entryId,
    );
    if (targetIndex < 0) return;

    final position = _scrollController.position;
    final targetTop = _estimateMacTimelineArticleTop(targetIndex);
    final targetOffset =
        targetTop -
        (position.viewportDimension - _estimatedMacTimelineItemExtent) / 2;
    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    // 粗定位可能跨越很长距离。用动画滚过去会和右侧文章切换同时竞争
    // UI isolate，导致明显掉帧；先 jump 到附近，再做短距离精确校正。
    _scrollController.jumpTo(clampedOffset.toDouble());

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    if (_ensureBuiltArticleVisible(entryId, durationMs: 180)) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    _ensureBuiltArticleVisible(entryId, durationMs: 160);
  }

  double _estimateMacTimelineArticleTop(int targetIndex) {
    final articles = controller.articles;
    final indexByEntryId = <String, int>{
      for (var i = 0; i < articles.length; i++) articles[i].entryId: i,
    };

    double? closestKnownTop;
    int? closestKnownIndex;
    var closestDistance = articles.length + 1;

    for (final entry in _itemKeys.entries) {
      final context = entry.value.currentContext;
      final builtIndex = indexByEntryId[entry.key];
      if (context == null || builtIndex == null) continue;

      _updateEstimatedMacTimelineItemExtent(context);
      final renderObject = context.findRenderObject();
      if (renderObject == null) continue;
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;

      final distance = (builtIndex - targetIndex).abs();
      if (distance >= closestDistance) continue;

      closestDistance = distance;
      closestKnownIndex = builtIndex;
      closestKnownTop = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    }

    if (closestKnownTop != null && closestKnownIndex != null) {
      return closestKnownTop +
          (targetIndex - closestKnownIndex) * _estimatedMacTimelineItemExtent;
    }

    return targetIndex * _estimatedMacTimelineItemExtent;
  }

  void _updateEstimatedMacTimelineItemExtent(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final height = renderObject.size.height;
    if (height < 48 || height > 260) return;

    _estimatedMacTimelineItemExtent =
        _estimatedMacTimelineItemExtent * 0.82 + height * 0.18;
  }

  bool get _isActiveMacTimeline {
    if (!Platform.isMacOS) return false;
    if (!Get.isRegistered<MainController>()) return true;
    return Get.find<MainController>().currentIndex.value == 0;
  }

  void _handleUndoPrepareEvent(UndoRestoreEvent? event) {
    if (!mounted || event == null || !_isActiveMacTimeline) return;
    final entryId = event.article.entryId;
    _TimelineAnimationProbe.begin(
      entryId,
      source: 'commandZ.restore',
      event: 'restore.preparing',
      fields: _timelineProbeFields(article: event.article),
    );
    _preAnimatedRemovals.remove(entryId);
    _preAnimatedRemovalArticles.remove(entryId);
    _pendingRemovalCompletions.remove(entryId);
    final host = _timelineCardHostKeys[entryId]?.currentState;
    if (host != null) {
      host.restore();
    } else {
      _pendingAnimatedEntrances.add(entryId);
    }
  }

  void _handleUndoRestoreEvent(UndoRestoreEvent? event) {
    if (!mounted || event == null || !_isActiveMacTimeline) return;
    final entryId = event.article.entryId;
    _pendingUndoSelectionRestores[entryId] = event;
    _TimelineAnimationProbe.log(
      entryId,
      'restore.completed',
      _timelineProbeFields(article: event.article),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActiveMacTimeline) return;
      final host = _timelineCardHostKeys[entryId]?.currentState;
      if (host?.isEntering ?? false) return;
      _completeUndoSelectionRestore(entryId);
    });
  }

  void _handleTimelineEntranceCompleted(String entryId) {
    if (!mounted || !_isActiveMacTimeline) return;
    _completeUndoSelectionRestore(entryId);
  }

  void _completeUndoSelectionRestore(String entryId) {
    final event = _pendingUndoSelectionRestores.remove(entryId);
    if (event == null) return;
    _listCoordinator.restoreSelection(entryId);
    _TimelineAnimationProbe.log(
      entryId,
      'restore.selection-restored',
      _timelineProbeFields(article: event.article),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      _TimelineAnimationProbe.finish(entryId);
    });
  }

  Future<void> _openOriginalArticle(ArticleModel article) async {
    if (article.url.isEmpty) return;
    await ExternalLinkService.openUrlWithFeedback(article.url);
  }

  Map<String, Object?> _timelineProbeFields({ArticleModel? article}) {
    final attachedPositions = _scrollController.positions.length;
    final lastTapAgeMs = _lastArticleTapAt == null
        ? -1
        : DateTime.now().difference(_lastArticleTapAt!).inMilliseconds;
    return {
      'count': controller.articles.length,
      'allCount': controller.allArticles.length,
      'index': article == null
          ? -1
          : controller.articles.indexWhere(
              (candidate) => candidate.entryId == article.entryId,
            ),
      'selected': _TimelineAnimationProbe.shortId(
        controller.selectedArticle.value?.entryId,
      ),
      'mode': controller.selectedMode.value.name,
      'listVersion': controller.timelineListResetVersion,
      'scrollPositions': attachedPositions,
      'offset': attachedPositions == 1
          ? _scrollController.offset.toStringAsFixed(1)
          : attachedPositions == 0
          ? 'detached'
          : 'multiple',
      'lastTapAgeMs': lastTapAgeMs,
      'refreshHz': View.of(context).display.refreshRate,
    };
  }

  void _handleMacArticleTap(ArticleModel article) {
    final now = DateTime.now();
    final elapsedSincePreviousTap = _lastArticleTapAt == null
        ? -1
        : now.difference(_lastArticleTapAt!).inMilliseconds;
    final isDoubleTap =
        _lastArticleTapEntryId == article.entryId &&
        _lastArticleTapAt != null &&
        elapsedSincePreviousTap < 300;
    _TimelineAnimationProbe.logTap(
      article.entryId,
      isDoubleTap: isDoubleTap,
      elapsedSincePreviousTapMs: elapsedSincePreviousTap,
    );

    controller.selectedArticle.value = article;
    _lastArticleTapEntryId = article.entryId;
    _lastArticleTapAt = now;

    if (isDoubleTap) {
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      _openOriginalAndMarkRead(article, source: 'doubleTap');
    }
  }

  void _openOriginalAndMarkRead(
    ArticleModel article, {
    required String source,
  }) {
    final expectsRemoval =
        !article.isRead &&
        controller.selectedMode.value == TimelineViewMode.unread;
    _TimelineAnimationProbe.begin(
      article.entryId,
      source: source,
      event: 'action.detected',
      fields: _timelineProbeFields(article: article),
    );
    if (expectsRemoval) {
      if (!_listCoordinator.beginRemoval(article.entryId)) {
        _TimelineAnimationProbe.log(article.entryId, 'coordinator.rejected');
        _TimelineAnimationProbe.finish(article.entryId);
        return;
      }
      _stageTimelineCardExit(article.entryId);
    } else {
      _selectRelativeArticle(1, scrollTo: false);
    }
    _TimelineAnimationProbe.log(
      article.entryId,
      expectsRemoval ? 'selection.held-for-removal' : 'selection.advanced',
      _timelineProbeFields(article: article),
    );

    // Persistence starts after the outgoing card has rendered its first
    // removal frame, preserving the same animation path for double-click and
    // Shift+B.
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        _TimelineAnimationProbe.log(
          article.entryId,
          'frame-boundary',
          _timelineProbeFields(article: article),
        );
        if (!article.isRead) {
          final before = controller.articles.length;
          final future = UndoService.markAsRead(
            article,
            showSuccess: false,
            deferTimelineVisualUpdate: true,
          );
          _TimelineAnimationProbe.log(article.entryId, 'mark-read.dispatched', {
            'before': before,
            'after': controller.articles.length,
            'listVersion': controller.timelineListResetVersion,
          });
          unawaited(future);
          unawaited(
            SchedulerBinding.instance.endOfFrame.then((_) {
              _TimelineAnimationProbe.log(
                article.entryId,
                'visual-update.frame-boundary',
                {
                  'count': controller.articles.length,
                  'listVersion': controller.timelineListResetVersion,
                },
              );
            }),
          );
        } else {
          _TimelineAnimationProbe.log(article.entryId, 'mark-read.skipped');
        }

        if (expectsRemoval) {
          _pendingOriginalOpenAfterRemoval[article.entryId] = article;
          _TimelineAnimationProbe.log(
            article.entryId,
            'browser.deferred-until-remove-end',
          );
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            final pending = _pendingOriginalOpenAfterRemoval.remove(
              article.entryId,
            );
            if (pending == null) return;
            unawaited(_openOriginalArticle(pending));
          });
        } else {
          Future<void>.delayed(const Duration(milliseconds: 200), () {
            if (mounted) unawaited(_openOriginalArticle(article));
          });
        }
      }),
    );
  }

  void _handleTimelineRemoveStart(ArticleModel article) {
    _TimelineAnimationProbe.log(
      article.entryId,
      'remove.start',
      _timelineProbeFields(article: article),
    );
    _listCoordinator.onRemoveStart(article);
    scheduleMicrotask(() {
      _TimelineAnimationProbe.log(article.entryId, 'remove.microtask');
    });
    Timer.run(() {
      _TimelineAnimationProbe.log(article.entryId, 'remove.event-turn');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _TimelineAnimationProbe.log(article.entryId, 'remove.next-frame');
    });
  }

  void _handleTimelineRemoveEnd(ArticleModel article) {
    _preAnimatedRemovals.remove(article.entryId);
    _preAnimatedRemovalArticles.remove(article.entryId);
    _pendingRemovalCompletions.remove(article.entryId);
    _timelineCardHostKeys.remove(article.entryId);
    _listCoordinator.onRemoveEnd(article);
    controller.completeDeferredReadTransition(article.entryId);
    UndoService.flushDeferredHistoryNotification();
    _TimelineAnimationProbe.log(
      article.entryId,
      'remove.end',
      _timelineProbeFields(article: article),
    );
    final pendingOpen = _pendingOriginalOpenAfterRemoval.remove(
      article.entryId,
    );
    if (pendingOpen != null) {
      _TimelineAnimationProbe.log(
        article.entryId,
        'browser.scheduled-after-remove-end',
      );
      unawaited(
        SchedulerBinding.instance.endOfFrame.then((_) {
          if (mounted) unawaited(_openOriginalArticle(pendingOpen));
        }),
      );
    }
    _TimelineAnimationProbe.finish(article.entryId);
  }

  void _stageTimelineCardExit(String entryId) {
    ArticleModel? article;
    for (final candidate in controller.articles) {
      if (candidate.entryId == entryId) {
        article = candidate;
        break;
      }
    }
    if (article == null) {
      for (final candidate in controller.allArticles) {
        if (candidate.entryId == entryId) {
          article = candidate;
          break;
        }
      }
    }
    if (article == null) return;
    _preAnimatedRemovalArticles[entryId] = article;
    _preAnimatedRemovals.add(entryId);
    final host = _timelineCardHostKeys[entryId]?.currentState;
    host?.animateOut();
  }

  void _scheduleCompletedTimelineRemovals(List<ArticleModel> articles) {
    if (_preAnimatedRemovalArticles.isEmpty) return;
    final visibleEntryIds = articles.map((article) => article.entryId).toSet();
    for (final entry in _preAnimatedRemovalArticles.entries.toList()) {
      final entryId = entry.key;
      if (visibleEntryIds.contains(entryId) ||
          !_pendingRemovalCompletions.add(entryId)) {
        continue;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingRemovalCompletions.remove(entryId);
        if (!mounted) return;
        final restored = controller.articles.any(
          (article) => article.entryId == entryId,
        );
        if (restored) {
          _preAnimatedRemovals.remove(entryId);
          _preAnimatedRemovalArticles.remove(entryId);
          _timelineCardHostKeys[entryId]?.currentState?.restore();
          return;
        }
        final removedArticle = _preAnimatedRemovalArticles[entryId];
        if (removedArticle == null) return;
        _handleTimelineRemoveStart(removedArticle);
        _handleTimelineRemoveEnd(removedArticle);
      });
    }
  }

  void _handleMacReadShortcut() {
    if (_isHandlingMacReadShortcut) return;

    final currentSelected = controller.selectedArticle.value;
    if (currentSelected == null) return;

    final currentIndex = controller.allArticles.indexWhere(
      (article) => article.entryId == currentSelected.entryId,
    );
    final current = currentIndex >= 0
        ? controller.allArticles[currentIndex]
        : currentSelected;

    _TimelineAnimationProbe.begin(
      current.entryId,
      source: current.isRead ? 'keyM.restoreUnread' : 'keyM.markRead',
      event: 'action.detected',
      fields: _timelineProbeFields(article: current),
    );

    _isHandlingMacReadShortcut = true;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _isHandlingMacReadShortcut = false;
    });

    if (current.isRead) {
      if (Get.isRegistered<ArticleController>(tag: current.entryId)) {
        unawaited(
          Get.find<ArticleController>(tag: current.entryId).markAsUnread(),
        );
      } else {
        controller.markAsUnreadLocal(current.entryId);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _TimelineAnimationProbe.log(
          current.entryId,
          'restore-unread.next-frame',
          _timelineProbeFields(article: current),
        );
      });
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        _TimelineAnimationProbe.finish(current.entryId);
      });
      return;
    }

    final expectsRemoval =
        controller.selectedMode.value == TimelineViewMode.unread;
    if (expectsRemoval) {
      if (!_listCoordinator.beginRemoval(current.entryId)) {
        _TimelineAnimationProbe.log(current.entryId, 'coordinator.rejected');
        _TimelineAnimationProbe.finish(current.entryId);
        return;
      }
      _stageTimelineCardExit(current.entryId);
    } else {
      _selectRelativeArticle(1, scrollTo: false);
    }
    _TimelineAnimationProbe.log(
      current.entryId,
      expectsRemoval ? 'selection.held-for-removal' : 'selection.advanced',
      _timelineProbeFields(article: current),
    );

    UndoService.applyReadLocally(
      current,
      deferTimelineVisualUpdate: expectsRemoval,
    );
    _TimelineAnimationProbe.log(
      current.entryId,
      'mark-read.dispatched',
      _timelineProbeFields(article: current),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _TimelineAnimationProbe.log(
        current.entryId,
        'action.next-frame',
        _timelineProbeFields(article: current),
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _TimelineAnimationProbe.log(
        current.entryId,
        'action.after-250ms',
        _timelineProbeFields(article: current),
      );
    });
  }

  void _handleMacMisclassifyShortcut() {
    if (_isHandlingMacReadShortcut) return;

    final currentSelected = controller.selectedArticle.value;
    if (currentSelected == null) return;

    final currentIndex = controller.allArticles.indexWhere(
      (article) => article.entryId == currentSelected.entryId,
    );
    final current = currentIndex >= 0
        ? controller.allArticles[currentIndex]
        : currentSelected;

    if (current.isRead || current.isRejectedByAi) return;

    _TimelineAnimationProbe.begin(
      current.entryId,
      source: 'keyN.misclassify',
      event: 'action.detected',
      fields: _timelineProbeFields(article: current),
    );

    _isHandlingMacReadShortcut = true;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _isHandlingMacReadShortcut = false;
    });

    final expectsRemoval =
        controller.selectedMode.value == TimelineViewMode.unread;
    if (expectsRemoval) {
      if (!_listCoordinator.beginRemoval(current.entryId)) {
        _TimelineAnimationProbe.log(
          current.entryId,
          'coordinator.rejected',
          _timelineProbeFields(article: current),
        );
        _TimelineAnimationProbe.finish(current.entryId);
        return;
      }
      _stageTimelineCardExit(current.entryId);
    } else {
      _selectRelativeArticle(1, scrollTo: false);
    }
    _TimelineAnimationProbe.log(
      current.entryId,
      expectsRemoval ? 'selection.held-for-removal' : 'selection.advanced',
      _timelineProbeFields(article: current),
    );

    UndoService.applyMisclassify(
      current,
      reject: true,
      deferTimelineVisualUpdate: expectsRemoval,
    );
    _TimelineAnimationProbe.log(
      current.entryId,
      'misclassify.dispatched',
      _timelineProbeFields(article: current),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _TimelineAnimationProbe.log(
        current.entryId,
        'action.next-frame',
        _timelineProbeFields(article: current),
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _TimelineAnimationProbe.log(
        current.entryId,
        'action.after-250ms',
        _timelineProbeFields(article: current),
      );
    });
  }

  bool? _prepareRedo(UndoAction action) {
    if (action.type != UndoActionType.read &&
        action.type != UndoActionType.misclassifyKeep &&
        action.type != UndoActionType.misclassifySpam) {
      return null;
    }
    final index = controller.articles.indexWhere(
      (article) => article.entryId == action.article.entryId,
    );
    if (index < 0) return true;

    final article = controller.articles[index];
    final expectsRemoval =
        controller.selectedMode.value == TimelineViewMode.unread;
    if (expectsRemoval) {
      if (!_listCoordinator.beginRemoval(article.entryId)) return false;
      _stageTimelineCardExit(article.entryId);
    }
    if (!expectsRemoval &&
        controller.selectedArticle.value?.entryId == article.entryId) {
      _selectRelativeArticle(1, scrollTo: false);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: !Platform.isMacOS && widget.showAppBar,
      appBar: widget.showAppBar
          ? (Platform.isMacOS
                ? null
                : MobileBlurAppBar(
                    blurBackground: false,
                    clipBehavior: Clip.none,
                    title: GestureDetector(
                      onTap: _onAppBarTap,
                      child: const Text('时间线'),
                    ),
                  ))
          : null,
      body: Obx(() {
        final state = controller.loadingState.value;

        final content = switch (state) {
          Loading() => _LocalTimelineSkeleton(
            bodyExtendsBehindAppBar: !Platform.isMacOS,
          ),
          LoadError(:final errMsg) => _ErrorView(
            message: errMsg,
            onRetry: controller.loadFeedsThenArticles,
          ),
          Success() => _buildSuccessContent(context),
        };

        if (Platform.isMacOS) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: MacHeaderPane(
                  headerHeight: kToolbarHeight,
                  header: _MacTimelineAppBar(
                    controller: controller,
                    batchMode: _isSilentBatchMode,
                    batchProcessing: _isSilentBatchProcessing,
                    selectedCount: _activeSilentBatchSelectedCount,
                    onEnterBatchMode: _enterSilentBatchMode,
                    onExitBatchMode: _exitSilentBatchMode,
                    onToggleAll: _toggleAllSilentBatchArticles,
                    onBatchAction: _performSilentBatchAction,
                  ),
                  body: content,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: 0.3),
              ),
              Expanded(
                child: Obx(() {
                  final selected = controller.selectedArticle.value;
                  if (selected == null) {
                    return MacSplitDetailEmptyPlaceholder(
                      topInset:
                          MediaQuery.paddingOf(context).top + kToolbarHeight,
                      focusNode: _emptyDetailFocusNode,
                    );
                  }
                  final restore = _takeArticleRestore(selected.entryId);
                  bool isDetailActive() =>
                      mounted &&
                      controller.selectedArticle.value?.entryId ==
                          selected.entryId &&
                      (!Get.isRegistered<MainController>() ||
                          Get.find<MainController>().currentIndex.value == 0);
                  return MacArticleDetailStack(
                    key: ValueKey(selected.entryId),
                    isActive: isDetailActive,
                    onOpenSource: _openArticleSource,
                    rootBuilder: (_, openRelatedArticle) => ArticlePageView(
                      article: selected,
                      isSplitView: true,
                      isActive: isDetailActive,
                      isSelectedArticle: (entryId) =>
                          controller.selectedArticle.value?.entryId == entryId,
                      onClose: _clearSelectionAndFocusEmptyDetail,
                      onOpenSource: _openArticleSource,
                      initialScrollOffset: restore?.scrollOffset,
                      initialShowTranslation: restore?.showTranslation,
                      initialShowSummary: restore?.showSummary,
                      onPrevious: () => _selectRelativeArticle(-1),
                      onNext: () => _selectRelativeArticle(1),
                      onMKeyPressed: _handleMacReadShortcut,
                      onMisclassifyKeyPressed: _handleMacMisclassifyShortcut,
                      onOpenRelatedArticle: openRelatedArticle,
                      onOpenOriginalAndMarkRead: () {
                        final current = controller.selectedArticle.value;
                        if (current != null) {
                          _openOriginalAndMarkRead(current, source: 'shiftB');
                        }
                      },
                    ),
                  );
                }),
              ),
            ],
          );
        }

        if (widget.showAppBar) {
          return MobileEdgeFadeStack(child: content);
        }
        return content;
      }),
    );
  }

  Widget _buildSuccessContent(BuildContext context) {
    return Platform.isMacOS
        ? _buildListView(context)
        : custom_refresh.RefreshIndicator(
            key: _refreshKey,
            edgeOffset: MediaQuery.paddingOf(context).top,
            displacement: 20,
            onRefresh: () async {
              await controller.loadFeedsThenArticles();
            },
            child: _buildListView(context),
          );
  }

  Widget _buildListView(BuildContext context) {
    return Obx(() {
      Widget content;
      if (Platform.isMacOS) {
        final articles = controller.articles.toList(growable: false);
        _scheduleCompletedTimelineRemovals(articles);
        content = ScrollbarTheme(
          data: MacGlassScrollbarStyle.articlePaneTheme(context),
          child: Padding(
            padding: MacArticleListChrome.viewportPadding,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    key: ValueKey(
                      '${controller.selectedMode.value}:${controller.timelineScopeKey}',
                    ),
                    physics: _refreshPhysics,
                    controller: _scrollController,
                    padding: MacArticleListChrome.contentPadding(context),
                    itemCount: articles.length,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<_TimelineRowIdentity>) return null;
                      final entryId = key.value.entryId;
                      final index = articles.indexWhere(
                        (article) => article.entryId == entryId,
                      );
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (context, index) {
                      return _buildAnimatedTimelineItem(
                        context,
                        articles[index],
                        index,
                        kAlwaysCompleteAnimation,
                      );
                    },
                  ),
                ),
                if (articles.isEmpty)
                  Positioned.fill(
                    child: DelayedVisibility(
                      visible: articles.isEmpty,
                      delay: const Duration(milliseconds: 220),
                      child: _EmptyView(
                        message: controller.emptyMessage,
                        onRetry: controller.loadFeedsThenArticles,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      } else if (controller.articles.isEmpty) {
        content = ListView(
          physics: _refreshPhysics,
          padding: EdgeInsets.only(
            top:
                MobileViewportInsets.listTopInset(
                  context,
                  bodyExtendsBehindAppBar: true,
                ).top +
                mobileEdgeListTopPadding,
            bottom:
                MobileViewportInsets.listBottomInset(context).bottom +
                mobileEdgeBottomTransitionExtent,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 64),
              child: _EmptyView(
                message: controller.emptyMessage,
                onRetry: controller.loadFeedsThenArticles,
              ),
            ),
          ],
        );
      } else {
        content = ListView.builder(
          physics: _refreshPhysics,
          controller: _scrollController,
          padding: EdgeInsets.only(
            top:
                MobileViewportInsets.listTopInset(
                  context,
                  bodyExtendsBehindAppBar: true,
                ).top +
                mobileEdgeListTopPadding,
            bottom:
                MobileViewportInsets.listBottomInset(context).bottom +
                mobileEdgeBottomTransitionExtent,
          ),
          itemCount: controller.articles.length,
          itemBuilder: (context, index) {
            final articleIndex = index;
            final article = controller.articles[articleIndex];
            final articleKey = _itemKeys.putIfAbsent(
              article.entryId,
              () => GlobalKey(),
            );
            return ArticleCard(
              key: articleKey,
              article: article,
              isSelected: false,
              onTap: () {
                final sequence = controller.articles.toList();
                // PageView 索引按 entryId 重新查找，禁止使用可能已过期的
                // 旧下标（点击前固定当前可见顺序）。
                final resolvedIndex = sequence.indexWhere(
                  (candidate) => candidate.entryId == article.entryId,
                );
                Get.toNamed(
                  Routes.article,
                  arguments: {
                    'article': article,
                    'sequence': sequence,
                    'index': resolvedIndex < 0 ? 0 : resolvedIndex,
                  },
                );
              },
            );
          },
        );
      }

      return content;
    });
  }

  Widget _buildAnimatedTimelineItem(
    BuildContext context,
    ArticleModel article,
    int index,
    Animation<double> animation,
  ) {
    final articleKey = _itemKeys.putIfAbsent(
      article.entryId,
      () => GlobalKey(),
    );
    final hostKey = _timelineCardHostKeys.putIfAbsent(
      article.entryId,
      () => GlobalKey<_TimelineArticleCardHostState>(),
    );
    final animateEntrance = _pendingAnimatedEntrances.remove(article.entryId);
    return KeyedSubtree(
      key: ValueKey<_TimelineRowIdentity>(
        _TimelineRowIdentity(article.entryId),
      ),
      child: Obx(() {
        final selectedId = controller.selectedArticle.value?.entryId;
        return _TimelineArticleCardHost(
          key: hostKey,
          animateEntrance: animateEntrance,
          articleKey: articleKey,
          article: article,
          isSelected: selectedId == article.entryId,
          onTap: () => _handleMacArticleTap(article),
          isSilentBatchMode: _isSilentBatchMode,
          isSilentBatchSelected: _silentBatchSelection.contains(
            article.entryId,
          ),
          onToggleSilentBatch: () => _toggleSilentBatchArticle(article.entryId),
          onEntranceCompleted: () =>
              _handleTimelineEntranceCompleted(article.entryId),
        );
      }),
    );
  }
}

class _TimelineRowIdentity {
  const _TimelineRowIdentity(this.entryId);

  final String entryId;

  @override
  bool operator ==(Object other) {
    return other is _TimelineRowIdentity && other.entryId == entryId;
  }

  @override
  int get hashCode => entryId.hashCode;
}

/// Owns the only transition layer used by a macOS timeline row.
///
/// The surrounding list is deliberately non-animated. The live card first
/// animates to zero here; only then does the controller remove the already
/// invisible row from the lazy list.
class _TimelineArticleCardHost extends StatefulWidget {
  const _TimelineArticleCardHost({
    super.key,
    required this.animateEntrance,
    required this.articleKey,
    required this.article,
    required this.isSelected,
    required this.onTap,
    required this.isSilentBatchMode,
    required this.isSilentBatchSelected,
    required this.onToggleSilentBatch,
    required this.onEntranceCompleted,
  });

  final bool animateEntrance;
  final GlobalKey articleKey;
  final ArticleModel article;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isSilentBatchMode;
  final bool isSilentBatchSelected;
  final VoidCallback onToggleSilentBatch;
  final VoidCallback onEntranceCompleted;

  @override
  State<_TimelineArticleCardHost> createState() =>
      _TimelineArticleCardHostState();
}

class _TimelineArticleCardHostState extends State<_TimelineArticleCardHost>
    with SingleTickerProviderStateMixin {
  late Widget _card;
  late final AnimationController _transitionController;
  late final Animation<double> _entranceAnimation;
  late final Animation<double> _exitAnimation;
  bool _isEntering = false;
  bool _isExiting = false;
  bool _entranceStartScheduled = false;
  int? _lastEntranceProbeBucket;
  int? _lastExitProbeBucket;

  bool get isEntering => _isEntering;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: TimelineController.deferredCardExitDuration,
      value: widget.animateEntrance ? 0 : 1,
    );
    _entranceAnimation = _transitionController.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _exitAnimation = _transitionController.drive(
      CurveTween(curve: Curves.easeInCubic),
    );
    _transitionController.addListener(_logExitTick);
    _transitionController.addListener(_logEntranceTick);
    _transitionController.addStatusListener(_handleTransitionStatus);
    _rebuildCard();
    if (widget.animateEntrance) {
      _isEntering = true;
      _scheduleEntrance();
    }
  }

  @override
  void didUpdateWidget(_TimelineArticleCardHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.articleKey, widget.articleKey) ||
        !identical(oldWidget.article, widget.article) ||
        oldWidget.isSelected != widget.isSelected ||
        oldWidget.isSilentBatchMode != widget.isSilentBatchMode ||
        oldWidget.isSilentBatchSelected != widget.isSilentBatchSelected) {
      _rebuildCard();
    }
  }

  void _rebuildCard() {
    final card = ArticleCard(
      key: widget.articleKey,
      article: widget.article,
      isSelected: widget.isSelected,
      onTap: _handleTap,
    );
    if (!widget.isSilentBatchMode) {
      _card = card;
      return;
    }
    _card = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 1,
          right: 5,
          child: _SilentBatchSelectionIndicator(
            selected: widget.isSilentBatchSelected,
            onPressed: widget.onToggleSilentBatch,
          ),
        ),
      ],
    );
  }

  void _handleTap() => widget.onTap();

  void animateOut() {
    if (_isExiting) return;
    _TimelineAnimationProbe.log(widget.article.entryId, 'local-exit.start');
    _lastExitProbeBucket = null;
    setState(() {
      _isEntering = false;
      _isExiting = true;
    });
    _transitionController.reverse(from: 1);
  }

  void restore() {
    if (_transitionController.value >= 1 && !_isExiting) {
      return;
    }
    setState(() {
      _isExiting = false;
      _isEntering = true;
    });
    _lastEntranceProbeBucket = null;
    _scheduleEntrance();
  }

  void _scheduleEntrance() {
    if (_entranceStartScheduled) return;
    _entranceStartScheduled = true;
    _TimelineAnimationProbe.log(
      widget.article.entryId,
      'local-entrance.queued',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceStartScheduled = false;
      if (!mounted || !_isEntering) return;
      _TimelineAnimationProbe.log(
        widget.article.entryId,
        'local-entrance.start',
      );
      _transitionController.forward();
    });
  }

  void _handleTransitionStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && _isEntering) {
      _TimelineAnimationProbe.log(
        widget.article.entryId,
        'local-entrance.completed',
      );
      setState(() => _isEntering = false);
      widget.onEntranceCompleted();
      return;
    }
    if (status == AnimationStatus.dismissed && _isExiting) {
      _TimelineAnimationProbe.log(
        widget.article.entryId,
        'local-exit.completed',
      );
    }
  }

  void _logExitTick() {
    if (!_TimelineAnimationProbe.enabled) return;
    if (!_isExiting) return;
    final value = _transitionController.value;
    final bucket = switch (value) {
      >= 0.95 => 4,
      >= 0.70 => 3,
      >= 0.45 => 2,
      >= 0.20 => 1,
      _ => 0,
    };
    if (_lastExitProbeBucket == bucket && value > 0) return;
    _lastExitProbeBucket = bucket;
    _TimelineAnimationProbe.log(
      widget.article.entryId,
      'local-exit.animation-tick',
      {
        'raw': value.toStringAsFixed(3),
        'curved': _exitAnimation.value.toStringAsFixed(3),
        'opacity': _exitAnimation.value.toStringAsFixed(3),
        'status': _transitionController.status.name,
        'scheduler': SchedulerBinding.instance.schedulerPhase.name,
        'systemFrameUs': SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds,
      },
    );
  }

  void _logEntranceTick() {
    if (!_TimelineAnimationProbe.enabled || !_isEntering) return;
    final value = _transitionController.value;
    final bucket = switch (value) {
      >= 0.95 => 4,
      >= 0.70 => 3,
      >= 0.45 => 2,
      >= 0.20 => 1,
      _ => 0,
    };
    if (_lastEntranceProbeBucket == bucket && value < 1) return;
    _lastEntranceProbeBucket = bucket;
    _TimelineAnimationProbe.log(
      widget.article.entryId,
      'local-entrance.animation-tick',
      {
        'raw': value.toStringAsFixed(3),
        'curved': _entranceAnimation.value.toStringAsFixed(3),
        'opacity': _entranceAnimation.value.toStringAsFixed(3),
        'status': _transitionController.status.name,
      },
    );
  }

  @override
  void dispose() {
    _transitionController.removeListener(_logExitTick);
    _transitionController.removeListener(_logEntranceTick);
    _transitionController.removeStatusListener(_handleTransitionStatus);
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isExiting) {
      return IgnorePointer(
        child: SizeTransition(
          sizeFactor: _exitAnimation,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: _exitAnimation, child: _card),
        ),
      );
    }
    if (_isEntering) {
      return SizeTransition(
        sizeFactor: _entranceAnimation,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: _entranceAnimation, child: _card),
      );
    }
    return _card;
  }
}

// ─── 优雅的加载骨架屏（与新版卡片像素级对齐） ───

class _LocalTimelineSkeleton extends StatelessWidget {
  final bool bodyExtendsBehindAppBar;

  const _LocalTimelineSkeleton({required this.bodyExtendsBehindAppBar});

  @override
  Widget build(BuildContext context) {
    // 与真实列表共用共享顶部 inset，避免骨架卡片埋入毛玻璃 AppBar。
    return ShimmerFadeList(
      padding:
          MobileViewportInsets.listTopInset(
            context,
            bodyExtendsBehindAppBar: bodyExtendsBehindAppBar,
          ) +
          const EdgeInsets.only(top: mobileEdgeListTopPadding),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: ArticleCardChrome.outerPadding,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: ArticleCardChrome.fillColor(context, selected: false),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
            side: ArticleCardChrome.borderSide(context, selected: false),
          ),
          child: Padding(
            padding: ArticleCardChrome.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: double.infinity, height: 18),
                const SizedBox(height: 10),
                _SkeletonBlock(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 18,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _SkeletonBlock(width: 48, height: 20, borderRadius: 10),
                    const SizedBox(width: 8),
                    _SkeletonBlock(width: 48, height: 20, borderRadius: 10),
                    const Spacer(),
                    _SkeletonBlock(width: 64, height: 14),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ─── 优雅的错误页 ───

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '数据加载异常',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '请检查网络连接后重试',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 优雅的空状态页 ───

class _EmptyView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _EmptyView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const MacEmptyPlaceholder(icon: Icons.done_all_rounded);
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all_rounded,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            Text(
              message ?? '当前没有文章',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '下拉即可刷新',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── macOS 时间线上下文 AppBar ──────────────────

class _MacTimelineAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final TimelineController controller;
  final bool batchMode;
  final bool batchProcessing;
  final int selectedCount;
  final VoidCallback onEnterBatchMode;
  final VoidCallback onExitBatchMode;
  final VoidCallback onToggleAll;
  final ValueChanged<_SilentBatchAction> onBatchAction;

  const _MacTimelineAppBar({
    required this.controller,
    required this.batchMode,
    required this.batchProcessing,
    required this.selectedCount,
    required this.onEnterBatchMode,
    required this.onExitBatchMode,
    required this.onToggleAll,
    required this.onBatchAction,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final _ = FeedSilentSettingsService.version.value;
      final feedId = controller.selectedFeedId.value;
      final category = controller.selectedCategory.value;
      final isSilentGroup =
          controller.isSilentSelected.value &&
          controller.selectedSilentGroupId.value != null &&
          feedId == null &&
          category == null;
      final totalCount = controller.articles.length;
      final allSelected = totalCount > 0 && selectedCount == totalCount;

      final selectedGroupId = controller.selectedSilentGroupId.value;
      final selectedGroup = FeedSilentSettingsService.groupById(
        selectedGroupId,
      );
      String title = isSilentGroup ? (selectedGroup?.name ?? '未分组') : '时间线';
      String? subtitle;

      if (batchMode) {
        title = '批量选择';
        subtitle = '已选择 $selectedCount 篇 · 当前列表 $totalCount 篇';
      }

      if (!batchMode &&
          feedId != null &&
          Get.isRegistered<SubscriptionsController>()) {
        final sub = Get.find<SubscriptionsController>();
        final feed = sub.allFeeds.firstWhereOrNull((f) => f.feedId == feedId);
        if (feed != null) {
          title = feed.title;
          final unread = controller.articles.where((a) => !a.isRead).length;
          final total = controller.articles.length;
          subtitle = unread > 0 ? '$unread 篇未读 · $total 篇当前列表' : '$total 篇当前列表';
        }
      } else if (!batchMode && category != null) {
        title = category;
        final unread = controller.articles.where((a) => !a.isRead).length;
        subtitle = '$unread 篇未读';
      }

      return AppBar(
        title: MacOSWindowDragArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: batchMode
            ? [
                AppGlassIconButton(
                  icon: allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  tooltip: allSelected ? '全不选' : '全选当前列表',
                  onPressed: batchProcessing ? null : onToggleAll,
                ),
                const SizedBox(width: 8),
                _MacSilentBatchActionsButton(
                  enabled: selectedCount > 0 && !batchProcessing,
                  processing: batchProcessing,
                  onSelected: onBatchAction,
                ),
                const SizedBox(width: 8),
                AppGlassIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '退出批量选择',
                  onPressed: batchProcessing ? null : onExitBatchMode,
                ),
                const SizedBox(width: 10),
              ]
            : [
                if (controller.selectedMode.value != TimelineViewMode.read) ...[
                  _MacTimelineModeToggle(controller: controller),
                  const SizedBox(width: 8),
                ],
                _MacTimelineSortButton(controller: controller),
                const SizedBox(width: 8),
                if (isSilentGroup) ...[
                  AppGlassIconButton(
                    icon: Icons.checklist_rounded,
                    tooltip: '批量处理静默文章',
                    onPressed: onEnterBatchMode,
                  ),
                  const SizedBox(width: 8),
                ],
                _MacSyncButton(controller: controller, colorScheme: cs),
                const SizedBox(width: 10),
              ],
      );
    });
  }
}

class _MacTimelineModeToggle extends StatefulWidget {
  final TimelineController controller;

  const _MacTimelineModeToggle({required this.controller});

  @override
  State<_MacTimelineModeToggle> createState() => _MacTimelineModeToggleState();
}

class _MacSilentBatchActionsButton extends StatelessWidget {
  final bool enabled;
  final bool processing;
  final ValueChanged<_SilentBatchAction> onSelected;

  const _MacSilentBatchActionsButton({
    required this.enabled,
    required this.processing,
    required this.onSelected,
  });

  static const _actions = [
    AppGlassSelectionOption(
      value: _SilentBatchAction.copy,
      icon: Icons.content_copy_rounded,
      label: '复制 Markdown',
    ),
    AppGlassSelectionOption(
      value: _SilentBatchAction.save,
      icon: Icons.save_alt_rounded,
      label: '保存 Markdown 文件',
    ),
    AppGlassSelectionOption(
      value: _SilentBatchAction.copyAndMarkRead,
      icon: Icons.library_add_check_rounded,
      label: '复制并标为已读',
    ),
    AppGlassSelectionOption(
      value: _SilentBatchAction.saveAndMarkRead,
      icon: Icons.download_done_rounded,
      label: '保存并标为已读',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppGlassMorphActionButton<_SilentBatchAction>(
      actions: _actions,
      title: '批量导出',
      titleIcon: Icons.ios_share_rounded,
      triggerIcon: processing
          ? Icons.hourglass_top_rounded
          : Icons.ios_share_rounded,
      tooltip: processing ? '正在处理' : '批量导出',
      enabled: enabled,
      panelWidth: 210,
      onSelected: onSelected,
    );
  }
}

class _MacTimelineModeToggleState extends State<_MacTimelineModeToggle> {
  static const _options = [
    AppGlassSelectionOption(
      value: TimelineViewMode.unread,
      label: '未读',
      icon: Icons.filter_alt_rounded,
    ),
    AppGlassSelectionOption(
      value: TimelineViewMode.all,
      label: '全部',
      icon: Icons.filter_alt_off_rounded,
    ),
  ];

  TimelineViewMode? _visualMode;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = _visualMode ?? widget.controller.selectedMode.value;
      final isUnread = mode == TimelineViewMode.unread;
      final theme = Theme.of(context);

      return AppGlassMorphSelectionButton<TimelineViewMode>(
        value: mode,
        options: _options,
        title: '文章范围',
        titleIcon: Icons.filter_alt_rounded,
        tooltip: isUnread ? '范围：未读' : '范围：全部',
        active: isUnread,
        triggerForegroundColor: theme.brightness == Brightness.dark
            ? Colors.white
            : theme.colorScheme.onSurface,
        onChanged: _setMode,
      );
    });
  }

  void _setMode(TimelineViewMode mode) {
    if (widget.controller.selectedMode.value == mode) return;

    setState(() => _visualMode = mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.setViewMode(mode);
      setState(() => _visualMode = null);
    });
  }
}

class _MacTimelineSortButton extends StatelessWidget {
  final TimelineController controller;

  const _MacTimelineSortButton({required this.controller});

  static const _options = [
    AppGlassSelectionOption(
      value: TimelineSortMode.newest,
      label: '最新优先',
      icon: Icons.schedule_rounded,
    ),
    AppGlassSelectionOption(
      value: TimelineSortMode.longest,
      label: '长文优先',
      icon: Icons.vertical_align_bottom_rounded,
    ),
    AppGlassSelectionOption(
      value: TimelineSortMode.shortest,
      label: '短文优先',
      icon: Icons.vertical_align_top_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = controller.selectedSortMode.value;
      return AppGlassMorphSelectionButton<TimelineSortMode>(
        value: mode,
        options: _options,
        title: '排序',
        titleIcon: Icons.sort_rounded,
        tooltip: '排序：${mode.label}',
        active: mode != TimelineSortMode.newest,
        onChanged: controller.setSortMode,
      );
    });
  }
}

extension _TimelineSortModeUi on TimelineSortMode {
  String get label => switch (this) {
    TimelineSortMode.newest => '最新优先',
    TimelineSortMode.longest => '长文优先',
    TimelineSortMode.shortest => '短文优先',
  };
}

class _MacSyncButton extends StatefulWidget {
  final TimelineController controller;
  final ColorScheme colorScheme;

  const _MacSyncButton({required this.controller, required this.colorScheme});

  @override
  State<_MacSyncButton> createState() => _MacSyncButtonState();
}

class _MacSyncButtonState extends State<_MacSyncButton> {
  StreamSubscription? _syncSub;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _syncSub = widget.controller.isSyncing.listen(_syncSpinAnimation);
    _syncSpinAnimation(widget.controller.isSyncing.value);
  }

  void _syncSpinAnimation(bool syncing) {
    if (!mounted) return;
    setState(() => _syncing = syncing);
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassSyncButton(
      syncing: _syncing,
      onPressed: widget.controller.loadFeedsThenArticles,
      syncingColor: widget.colorScheme.primary,
    );
  }
}
