import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/refresh_aware_scroll_physics.dart';
import '../../common/widgets/shimmer_card.dart';
import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/implicitly_animated_list.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/app_glass_sync_button.dart';
import '../../common/widgets/mac_header_pane.dart';
import '../../common/widgets/article_card_chrome.dart';
import '../../common/widgets/mac_split_article_list_coordinator.dart';
import '../../common/liquid_glass/liquid_glass.dart' as glass;

import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/article_state_notifier.dart';
import '../../services/read_sync_service.dart';
import '../../services/undo_service.dart';
import '../../utils/security_utils.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../widgets/article_card.dart';
import 'timeline_controller.dart';
import '../../utils/scroll_utils.dart';

class _TimelineAnimationProbe {
  static const bool _requested = bool.fromEnvironment(
    'AUTO_FOLO_ANIMATION_PROBE',
  );
  static final Stopwatch _clock = Stopwatch()..start();
  static String? _activeEntryId;
  static String? _activeSource;
  static int _startedAtUs = 0;
  static bool _timingsInstalled = false;

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
    log(entryId, event, fields);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_activeEntryId != entryId) return;
      log(entryId, 'session.timeout');
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
    debugPrintSynchronously(
      '[TimelineAnimationProbe +${elapsedMs.toStringAsFixed(1)}ms '
      'id=${shortId(entryId)} source=$_activeSource] '
      '$event${details.isEmpty ? '' : ' $details'}',
      wrapWidth: 2000,
    );
  }

  static void finish(String entryId) {
    if (!enabled || _activeEntryId != entryId) return;
    log(entryId, 'session.finished');
    _activeEntryId = null;
    _activeSource = null;
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
        if (buildMs < 16.7 && rasterMs < 16.7) continue;
        log(entryId, 'frame.slow', {
          'buildMs': buildMs.toStringAsFixed(1),
          'rasterMs': rasterMs.toStringAsFixed(1),
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
  final VoidCallback? onOpenFilterReview;

  const TimelinePage({
    super.key,
    this.showAppBar = true,
    this.onOpenFilterReview,
  });

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  static const double _defaultMacTimelineItemExtent = 124;

  late final TimelineController controller;
  final ScrollController _scrollController = ScrollController();
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
  Worker? _undoRestoreWorker;

  Map<String, GlobalKey> get _itemKeys => _listCoordinator.itemKeys;

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
    _undoRestoreWorker = ever(
      UndoService.restoredAction,
      _handleUndoRestoreEvent,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    controller.bindScrollToTopHandler(null);
    _listCoordinator.dispose();
    _undoRestoreWorker?.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!controller.isLoadingMore && controller.hasMore) {
        controller.loadMore();
      }
    }
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
      controller.selectedArticle.value = list.first;
      if (scrollTo) _scrollToArticle(list.first.entryId);
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

  void _handleUndoRestoreEvent(UndoRestoreEvent? event) {
    if (!mounted || event == null || !_isActiveMacTimeline) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActiveMacTimeline) return;
      _listCoordinator.restoreSelection(event.article.entryId);
    });
  }

  Future<void> _openOriginalArticle(ArticleModel article) async {
    if (article.url.isEmpty) return;

    final uri = SecurityUtils.parseHttpUrl(article.url);
    if (uri == null) {
      AppFeedback.error('无法打开链接', '链接格式无效或协议不受支持');
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      AppFeedback.error('无法打开链接', '未找到默认浏览器');
    }
  }

  Map<String, Object?> _timelineProbeFields({ArticleModel? article}) {
    final attachedPositions = _scrollController.positions.length;
    return {
      'count': controller.articles.length,
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
    };
  }

  void _handleMacArticleTap(ArticleModel article) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastArticleTapEntryId == article.entryId &&
        _lastArticleTapAt != null &&
        now.difference(_lastArticleTapAt!).inMilliseconds < 300;

    controller.selectedArticle.value = article;
    _lastArticleTapEntryId = article.entryId;
    _lastArticleTapAt = now;

    if (isDoubleTap) {
      final expectsRemoval =
          !article.isRead &&
          controller.selectedMode.value == TimelineViewMode.unread;
      _TimelineAnimationProbe.begin(
        article.entryId,
        source: 'doubleTap',
        event: 'action.detected',
        fields: _timelineProbeFields(article: article),
      );
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      if (expectsRemoval) {
        if (!_listCoordinator.beginRemoval(article.entryId)) {
          _TimelineAnimationProbe.log(article.entryId, 'coordinator.rejected');
          _TimelineAnimationProbe.finish(article.entryId);
          return;
        }
      } else {
        _selectRelativeArticle(1, scrollTo: false);
      }
      _TimelineAnimationProbe.log(
        article.entryId,
        expectsRemoval ? 'selection.held-for-removal' : 'selection.advanced',
        _timelineProbeFields(article: article),
      );

      // Run persistence after the current frame has fully ended. A post-frame
      // callback still belongs to that frame and can consume the first part of
      // the removal animation when local database writes are slow.
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
            _TimelineAnimationProbe.log(
              article.entryId,
              'mark-read.dispatched',
              {
                'before': before,
                'after': controller.articles.length,
                'listVersion': controller.timelineListResetVersion,
              },
            );
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
            // No list removal will run, so only leave time for press feedback.
            Future<void>.delayed(const Duration(milliseconds: 200), () {
              if (mounted) unawaited(_openOriginalArticle(article));
            });
          }
        }),
      );
    }
  }

  void _handleTimelineRemoveStart(ArticleModel article) {
    _TimelineAnimationProbe.log(
      article.entryId,
      'remove.start',
      _timelineProbeFields(article: article),
    );
    _listCoordinator.onRemoveStart(article);
  }

  void _handleTimelineRemoveEnd(ArticleModel article) {
    _listCoordinator.onRemoveEnd(article);
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
    } else {
      _selectRelativeArticle(1, scrollTo: false);
    }
    _TimelineAnimationProbe.log(
      current.entryId,
      expectsRemoval ? 'selection.held-for-removal' : 'selection.advanced',
      _timelineProbeFields(article: current),
    );

    UndoService.recordRead(current);
    controller.markAsReadLocal(
      current.entryId,
      deferVisualUpdateToFrameBoundary: expectsRemoval,
    );
    _TimelineAnimationProbe.log(
      current.entryId,
      'mark-read.dispatched',
      _timelineProbeFields(article: current),
    );
    ReadSyncService.enqueue(
      current.entryId,
      isInbox: current.category == 'inbox',
    );
    unawaited(ReadSyncService.syncPendingReads());

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

  Widget _buildFilterBar(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () {
          if (Platform.isMacOS && widget.onOpenFilterReview != null) {
            widget.onOpenFilterReview!();
            return;
          }
          Get.toNamed(Routes.filterReview);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI 智能过滤',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '拦截了 $count 篇低质量或无关内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFFB45309).withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFD97706),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? (Platform.isMacOS
                ? null
                : AppBar(
                    title: GestureDetector(
                      onTap: _onAppBarTap,
                      child: const Text('时间线'),
                    ),
                    scrolledUnderElevation: 1,
                    bottom: const PreferredSize(
                      preferredSize: Size.fromHeight(0.5),
                      child: Divider(height: 0.5, thickness: 0.5),
                    ),
                  ))
          : null,
      body: Obx(() {
        final state = controller.loadingState.value;

        final content = switch (state) {
          Loading() => const _LocalTimelineSkeleton(), // 使用定制化的优雅骨架屏
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
                  header: _MacTimelineAppBar(controller: controller),
                  body: content,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Expanded(
                child: Obx(() {
                  final selected = controller.selectedArticle.value;
                  if (selected == null) {
                    return MacSplitDetailEmptyPlaceholder(
                      topInset:
                          MediaQuery.paddingOf(context).top + kToolbarHeight,
                    );
                  }
                  return ArticlePageView(
                    key: ValueKey(selected.entryId),
                    article: selected,
                    isSplitView: true,
                    isActive: () =>
                        !Get.isRegistered<MainController>() ||
                        Get.find<MainController>().currentIndex.value == 0,
                    isSelectedArticle: (entryId) =>
                        controller.selectedArticle.value?.entryId == entryId,
                    onClose: () => controller.selectedArticle.value = null,
                    onPrevious: () => _selectRelativeArticle(-1),
                    onNext: () => _selectRelativeArticle(1),
                    onMKeyPressed: _handleMacReadShortcut,
                  );
                }),
              ),
            ],
          );
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
      ArticleStateNotifier.version.value; // 订阅变更通知
      final filterCount = controller.filterCount.value;
      final filterBarCount = Platform.isMacOS ? 0 : 1;
      Widget content;
      if (Platform.isMacOS) {
        content = ScrollbarTheme(
          data: MacGlassScrollbarStyle.articlePaneTheme(context),
          child: Padding(
            padding: MacArticleListChrome.viewportPadding,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ImplicitlyAnimatedList<ArticleModel>(
                    key: ValueKey(
                      '${controller.selectedMode.value}:${controller.timelineScopeKey}',
                    ),
                    batchUpdateVersion: controller.timelineListResetVersion,
                    physics: _refreshPhysics,
                    controller: _scrollController,
                    padding: MacArticleListChrome.contentPadding(context),
                    items: controller.articles.toList(),
                    itemKey: (article) => article.entryId,
                    itemBuilder: _buildAnimatedTimelineItem,
                    removedItemBuilder: _buildRemovedTimelineItem,
                    onRemoveStart: _handleTimelineRemoveStart,
                    onRemoveEnd: _handleTimelineRemoveEnd,
                  ),
                ),
                if (controller.articles.isEmpty)
                  Positioned.fill(
                    child: DelayedVisibility(
                      visible: controller.articles.isEmpty,
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
            top: MediaQuery.paddingOf(context).top,
            bottom:
                8 +
                kBottomNavigationBarHeight +
                MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _buildFilterBar(filterCount),
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
            top: MediaQuery.paddingOf(context).top,
            bottom:
                8 +
                kBottomNavigationBarHeight +
                MediaQuery.of(context).padding.bottom,
          ),
          itemCount: controller.articles.length + filterBarCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildFilterBar(filterCount);
            }
            final articleIndex = index - filterBarCount;
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
                Get.toNamed(
                  Routes.article,
                  arguments: {
                    'article': article,
                    'sequence': controller.articles.toList(),
                    'index': articleIndex,
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
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 1,
      child: FadeTransition(
        opacity: animation,
        child: Obx(() {
          final selectedId = controller.selectedArticle.value?.entryId;
          return ArticleCard(
            key: articleKey,
            article: article,
            isSelected: selectedId == article.entryId,
            onTap: () => _handleMacArticleTap(article),
          );
        }),
      ),
    );
  }

  Widget _buildRemovedTimelineItem(
    BuildContext context,
    ArticleModel article,
    int index,
    Animation<double> animation,
  ) {
    final articleKey = _listCoordinator.removedItemKeyFor(article.entryId);
    final transition = SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: ArticleCard(
          key: articleKey,
          article: article,
          isSelected:
              controller.selectedArticle.value?.entryId == article.entryId,
          onTap: () {},
        ),
      ),
    );
    if (!_TimelineAnimationProbe.enabled) return transition;
    return _TimelineRemovalAnimationProbe(
      entryId: article.entryId,
      animation: animation,
      child: transition,
    );
  }
}

class _TimelineRemovalAnimationProbe extends StatefulWidget {
  const _TimelineRemovalAnimationProbe({
    required this.entryId,
    required this.animation,
    required this.child,
  });

  final String entryId;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_TimelineRemovalAnimationProbe> createState() =>
      _TimelineRemovalAnimationProbeState();
}

class _TimelineRemovalAnimationProbeState
    extends State<_TimelineRemovalAnimationProbe> {
  int? _lastBucket;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_handleAnimation);
    widget.animation.addStatusListener(_handleStatus);
    _TimelineAnimationProbe.log(widget.entryId, 'remove.builder-attached', {
      'value': widget.animation.value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
    _handleAnimation();
  }

  @override
  void didUpdateWidget(_TimelineRemovalAnimationProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeListener(_handleAnimation);
    oldWidget.animation.removeStatusListener(_handleStatus);
    _lastBucket = null;
    widget.animation.addListener(_handleAnimation);
    widget.animation.addStatusListener(_handleStatus);
    _handleAnimation();
  }

  @override
  void dispose() {
    widget.animation.removeListener(_handleAnimation);
    widget.animation.removeStatusListener(_handleStatus);
    _TimelineAnimationProbe.log(widget.entryId, 'remove.builder-disposed', {
      'value': widget.animation.value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    _TimelineAnimationProbe.log(widget.entryId, 'remove.animation-status', {
      'status': status.name,
      'value': widget.animation.value.toStringAsFixed(3),
    });
  }

  void _handleAnimation() {
    final value = widget.animation.value;
    final bucket = switch (value) {
      >= 0.95 => 4,
      >= 0.70 => 3,
      >= 0.45 => 2,
      >= 0.20 => 1,
      _ => 0,
    };
    if (_lastBucket == bucket) return;
    _lastBucket = bucket;
    _TimelineAnimationProbe.log(widget.entryId, 'remove.animation-progress', {
      'bucket': bucket,
      'value': value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── 优雅的加载骨架屏（与新版卡片像素级对齐） ───

class _LocalTimelineSkeleton extends StatelessWidget {
  const _LocalTimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerFadeList(
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.done_all_rounded,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '一切就绪',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '当前没有未读的新文章\n您可以去订阅源发现更多内容',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('强制同步'),
                style: OutlinedButton.styleFrom(
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

// ─── macOS 时间线上下文 AppBar ──────────────────

class _MacTimelineAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final TimelineController controller;

  const _MacTimelineAppBar({required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final feedId = controller.selectedFeedId.value;
      final category = controller.selectedCategory.value;

      String title = '时间线';
      String? subtitle;

      if (feedId != null && Get.isRegistered<SubscriptionsController>()) {
        final sub = Get.find<SubscriptionsController>();
        final feed = sub.allFeeds.firstWhereOrNull((f) => f.feedId == feedId);
        if (feed != null) {
          title = feed.title;
          final unread = controller.articles.where((a) => !a.isRead).length;
          final total = controller.articles.length;
          subtitle = unread > 0 ? '$unread 篇未读 · $total 篇当前列表' : '$total 篇当前列表';
        }
      } else if (category != null) {
        title = category;
        final unread = controller.articles.where((a) => !a.isRead).length;
        subtitle = '$unread 篇未读';
      }

      return AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
        backgroundColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (controller.selectedMode.value != TimelineViewMode.read) ...[
            _MacTimelineModeToggle(controller: controller),
            const SizedBox(width: 8),
          ],
          _MacTimelineSortButton(controller: controller, colorScheme: cs),
          const SizedBox(width: 8),
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

class _MacTimelineModeToggleState extends State<_MacTimelineModeToggle> {
  TimelineViewMode? _visualMode;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = _visualMode ?? widget.controller.selectedMode.value;
      final selectedIndex = mode == TimelineViewMode.unread ? 0 : 1;

      return AppGlassCompactSwitch(
        selectedIndex: selectedIndex,
        labels: const ['未读', '全部'],
        onChanged: (index) => _setMode(
          index == 0 ? TimelineViewMode.unread : TimelineViewMode.all,
        ),
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

class _MacTimelineSortButton extends StatefulWidget {
  final TimelineController controller;
  final ColorScheme colorScheme;

  const _MacTimelineSortButton({
    required this.controller,
    required this.colorScheme,
  });

  @override
  State<_MacTimelineSortButton> createState() => _MacTimelineSortButtonState();
}

class _MacTimelineSortButtonState extends State<_MacTimelineSortButton>
    with SingleTickerProviderStateMixin {
  static const double _buttonSize = 34;
  static const double _panelWidth = 188;
  static const double _panelHeight = 166;
  static const glass.LiquidGlassSettings _sortGlassSettings =
      glass.LiquidGlassSettings(
        blur: 12,
        thickness: 12,
        glassColor: Color.fromRGBO(255, 255, 255, 0.14),
        lightIntensity: 0.68,
        ambientStrength: 0.38,
        saturation: 1.18,
        refractiveIndex: 0.62,
        chromaticAberration: 0.0,
      );

  final _buttonKey = GlobalKey();
  late final glass.GlassMorphController _morphController;
  OverlayEntry? _overlayEntry;
  bool _hovered = false;
  bool _pressed = false;
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _morphController = glass.GlassMorphController(
      vsync: this,
      speed: glass.MorphSpeed.normal,
    )..addListener(_handleMorphTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _morphController.setDisableAnimations(
      MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void dispose() {
    _removeOverlay(immediate: true);
    _morphController.dispose();
    super.dispose();
  }

  void _handleMorphTick() {
    _overlayEntry?.markNeedsBuild();
    if (_overlayEntry == null ||
        !_morphController.isClosing ||
        _morphController.isShowing) {
      return;
    }

    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    if (mounted) {
      setState(() => _isMenuOpen = false);
    } else {
      _isMenuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = widget.controller.selectedSortMode.value;
      final selected = mode != TimelineSortMode.newest || _isMenuOpen;

      return AppGlassTooltip(
        message: '排序：${mode.label}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            key: _buttonKey,
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _toggleOverlay,
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AppGlassRoundControlChrome(
                enabled: true,
                hovered: _hovered,
                pressed: _pressed,
                size: _buttonSize,
                child: Icon(
                  mode.icon,
                  size: 18,
                  color: selected
                      ? widget.colorScheme.primary
                      : widget.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (renderObject is! RenderBox || overlayBox == null) return;

    final buttonTopLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final buttonRight = buttonTopLeft.dx + renderObject.size.width;
    final left = (buttonRight - _panelWidth)
        .clamp(8.0, math.max(8.0, overlayBox.size.width - _panelWidth - 8))
        .toDouble();
    final top = buttonTopLeft.dy
        .clamp(8.0, math.max(8.0, overlayBox.size.height - _panelHeight - 8))
        .toDouble();

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: _MacTimelineSortOverlayPanel(
                morphController: _morphController,
                selected: widget.controller.selectedSortMode.value,
                onClose: _removeOverlay,
                onSelected: (mode) {
                  widget.controller.setSortMode(mode);
                  _removeOverlay();
                },
                colorScheme: widget.colorScheme,
                glassSettings: _sortGlassSettings,
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_overlayEntry!);
    setState(() => _isMenuOpen = true);
    _morphController.open();
  }

  void _removeOverlay({bool immediate = false}) {
    final entry = _overlayEntry;
    if (entry == null) return;
    if (immediate) {
      entry.remove();
      _overlayEntry = null;
      _isMenuOpen = false;
      return;
    }

    if (_morphController.isClosing) return;
    _morphController.close();
  }
}

class _MacTimelineSortOverlayPanel extends StatelessWidget {
  final glass.GlassMorphController morphController;
  final TimelineSortMode selected;
  final ValueChanged<TimelineSortMode> onSelected;
  final VoidCallback onClose;
  final ColorScheme colorScheme;
  final glass.LiquidGlassSettings glassSettings;

  const _MacTimelineSortOverlayPanel({
    required this.morphController,
    required this.selected,
    required this.onSelected,
    required this.onClose,
    required this.colorScheme,
    required this.glassSettings,
  });

  static const double _buttonSize = 34;
  static const double _panelWidth = 188;
  static const double _panelHeight = 166;

  @override
  Widget build(BuildContext context) {
    final rawValue = morphController.value;
    final effectiveValue =
        morphController.isClosing && morphController.hasHandedOff
        ? 0.0
        : rawValue;
    final clampedValue = effectiveValue.clamp(0.0, 1.0);
    final baseMorphT = morphController.isClosing
        ? _anchoredCloseSettleT(clampedValue)
        : Curves.linearToEaseOut.transform(clampedValue);
    final elasticTail = morphController.isClosing
        ? _anchoredCloseTail(clampedValue)
        : _anchoredOpenTail(clampedValue);
    final morphMin = morphController.isClosing ? -0.014 : 0.0;
    final morphT = (baseMorphT + elasticTail).clamp(morphMin, 1.024);
    final currentWidth = lerpDouble(_buttonSize, _panelWidth, morphT)!;
    final currentHeight = lerpDouble(_buttonSize, _panelHeight, morphT)!;
    final maxRadius = math.min(currentWidth, currentHeight) / 2;
    final radiusT = Curves.easeOutCubic.transform(morphT.clamp(0.0, 1.0));
    final currentRadius = lerpDouble(maxRadius, 16, radiusT)!;
    final contentOpacity = ((clampedValue - 0.82) / 0.18).clamp(0.0, 1.0);
    final showContent = clampedValue > 0.82 && !morphController.isClosing;
    final showIcon = clampedValue < 0.34;
    final iconOpacity = (1 - clampedValue / 0.34).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: _panelWidth,
        height: _panelHeight,
        child: glass.LiquidGlassLayer(
          settings: glassSettings,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: glass.GlassContainer(
                  width: currentWidth,
                  height: currentHeight,
                  useOwnLayer: false,
                  settings: glassSettings,
                  quality: glass.GlassQuality.standard,
                  allowElevation: false,
                  clipBehavior: Clip.antiAlias,
                  shape: glass.LiquidRoundedSuperellipse(
                    borderRadius: currentRadius,
                  ),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      if (showIcon)
                        Opacity(
                          opacity: iconOpacity,
                          child: SizedBox(
                            width: _buttonSize,
                            height: _buttonSize,
                            child: Icon(
                              selected.icon,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (showContent)
                        Opacity(
                          opacity: contentOpacity,
                          child: IgnorePointer(
                            ignoring: contentOpacity < 0.95,
                            child: _MacTimelineSortPanelContent(
                              selected: selected,
                              onSelected: onSelected,
                              onClose: onClose,
                            ),
                          ),
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

  double _anchoredOpenTail(double t) {
    const start = 0.42;
    if (t <= start || t >= 1.0) return 0.0;
    final u = ((t - start) / (1.0 - start)).clamp(0.0, 1.0);
    return math.sin(u * math.pi) * 0.028;
  }

  double _anchoredCloseSettleT(double t) {
    final progress = (1.0 - t).clamp(0.0, 1.0);
    const omega = 5.0;
    final settled =
        1.0 - (1.0 + omega * progress) * math.exp(-omega * progress);
    final normalizer = 1.0 - (1.0 + omega) * math.exp(-omega);
    return (1.0 - settled / normalizer).clamp(0.0, 1.0);
  }

  double _anchoredCloseTail(double t) {
    const end = 0.24;
    if (t <= 0.0 || t >= end) return 0.0;
    final u = (t / end).clamp(0.0, 1.0);
    return -math.sin(u * math.pi) * 0.032;
  }
}

class _MacTimelineSortPanelContent extends StatelessWidget {
  final TimelineSortMode selected;
  final ValueChanged<TimelineSortMode> onSelected;
  final VoidCallback onClose;

  const _MacTimelineSortPanelContent({
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: _MacTimelineSortOverlayPanel._panelWidth,
      height: _MacTimelineSortOverlayPanel._panelHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.sort_rounded, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '排序',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                _MacTimelineSortCloseButton(onTap: onClose),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.28)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Column(
                children: [
                  for (final mode in TimelineSortMode.values)
                    _MacTimelineSortOption(
                      mode: mode,
                      selected: mode == selected,
                      onTap: () => onSelected(mode),
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

class _MacTimelineSortOption extends StatefulWidget {
  final TimelineSortMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _MacTimelineSortOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MacTimelineSortOption> createState() => _MacTimelineSortOptionState();
}

class _MacTimelineSortOptionState extends State<_MacTimelineSortOption> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final foreground = widget.selected ? cs.primary : cs.onSurface;
    final backgroundColor = controls.optionFill(
      selected: widget.selected,
      hovered: _hovered,
      pressed: _pressed,
    );
    final borderColor = controls.optionBorder(
      selected: widget.selected,
      hovered: _hovered,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: _pressed
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(widget.mode.icon, size: 17, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.mode.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(Icons.check_rounded, size: 17, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MacTimelineSortCloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _MacTimelineSortCloseButton({required this.onTap});

  @override
  State<_MacTimelineSortCloseButton> createState() =>
      _MacTimelineSortCloseButtonState();
}

class _MacTimelineSortCloseButtonState
    extends State<_MacTimelineSortCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final backgroundColor = controls.neutralOverlay(
      hovered: _hovered,
      pressed: _pressed,
      darkHoverAlpha: 0.09,
      lightHoverAlpha: 0.055,
      darkPressedAlpha: 0.14,
      lightPressedAlpha: 0.08,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: _pressed
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

extension _TimelineSortModeUi on TimelineSortMode {
  String get label => switch (this) {
    TimelineSortMode.newest => '最新优先',
    TimelineSortMode.longest => '长文优先',
    TimelineSortMode.shortest => '短文优先',
  };

  IconData get icon => switch (this) {
    TimelineSortMode.newest => Icons.schedule_rounded,
    TimelineSortMode.longest => Icons.vertical_align_bottom_rounded,
    TimelineSortMode.shortest => Icons.vertical_align_top_rounded,
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
