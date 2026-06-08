import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/refresh_aware_scroll_physics.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../common/widgets/shimmer_card.dart';
import '../../common/widgets/mac_empty_placeholder.dart';

import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/article_state_notifier.dart';
import '../../services/feed_readability_settings_service.dart';
import '../../services/feed_translation_settings_service.dart';
import '../../services/undo_service.dart';
import '../../utils/security_utils.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../widgets/article_card.dart';
import 'timeline_controller.dart';
import '../../utils/scroll_utils.dart';

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
  late final TimelineController controller;
  final ScrollController _scrollController = ScrollController();
  final _refreshKey = GlobalKey<custom_refresh.RefreshIndicatorState>();
  late final _refreshPhysics = RefreshAwareScrollPhysics(
    refreshKey: _refreshKey,
  );
  DateTime? _lastTapTime;
  String? _lastArticleTapEntryId;
  DateTime? _lastArticleTapAt;
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    controller = Get.put(TimelineController());
    controller.bindScrollToTopHandler(_scrollToTop);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    controller.bindScrollToTopHandler(null);
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

  void _selectRelativeArticle(int delta) {
    final list = controller.articles;
    if (list.isEmpty) return;

    final selected = controller.selectedArticle.value;
    if (selected == null) {
      controller.selectedArticle.value = list.first;
      return;
    }

    final currentIndex = list.indexWhere((a) => a.entryId == selected.entryId);
    if (currentIndex != -1) {
      final nextIndex = (currentIndex + delta).clamp(0, list.length - 1);
      controller.selectedArticle.value = list[nextIndex];
      _scrollToArticle(list[nextIndex].entryId);
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
            _scrollToArticle(allList[i].entryId);
            return;
          }
        }
        // 向后找尽，停留在当前可用列表的最后一篇
        controller.selectedArticle.value = list.last;
        _scrollToArticle(list.last.entryId);
      } else {
        // 向前寻找上一个存在的文章
        for (int i = allIndex - 1; i >= 0; i--) {
          if (listEntryIds.contains(allList[i].entryId)) {
            controller.selectedArticle.value = allList[i];
            _scrollToArticle(allList[i].entryId);
            return;
          }
        }
        // 向前找尽，停留在当前可用列表的第一篇
        controller.selectedArticle.value = list.first;
        _scrollToArticle(list.first.entryId);
      }
    } else {
      // 极端兜底情况：全量列表里都找不到
      controller.selectedArticle.value = list.first;
      _scrollToArticle(list.first.entryId);
    }
  }

  void _scrollToArticle(String entryId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[entryId];
      if (key != null && key.currentContext != null) {
        ScrollUtils.ensureVisible(key.currentContext!);
      }
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
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      _openOriginalArticle(article);

      if (!article.isRead) {
        unawaited(UndoService.markAsRead(article, showSuccess: false));
      }
    }
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
                child: Scaffold(
                  appBar: _MacTimelineAppBar(controller: controller),
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
                    return const MacEmptyPlaceholder();
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
      return ScrollConfiguration(
        behavior: const NoOverscrollIndicatorBehavior(),
        child: controller.articles.isEmpty
            ? ListView(
                physics: _refreshPhysics,
                padding: EdgeInsets.only(
                  top: Platform.isMacOS ? 0 : MediaQuery.paddingOf(context).top,
                  bottom:
                      8 +
                      (Platform.isMacOS ? 0 : kBottomNavigationBarHeight) +
                      MediaQuery.of(context).padding.bottom,
                ),
                children: [
                  if (!Platform.isMacOS) _buildFilterBar(filterCount),
                  Padding(
                    padding: const EdgeInsets.only(top: 64),
                    child: _EmptyView(
                      message: controller.emptyMessage,
                      onRetry: controller.loadFeedsThenArticles,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: _refreshPhysics,
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: Platform.isMacOS ? 0 : MediaQuery.paddingOf(context).top,
                  bottom:
                      8 +
                      (Platform.isMacOS ? 0 : kBottomNavigationBarHeight) +
                      MediaQuery.of(context).padding.bottom,
                ),
                itemCount: controller.articles.length + filterBarCount,
                itemBuilder: (context, index) {
                  if (!Platform.isMacOS && index == 0) {
                    return _buildFilterBar(filterCount);
                  }
                  final articleIndex = index - filterBarCount;
                  if (articleIndex == controller.articles.length) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final article = controller.articles[articleIndex];
                  final articleKey = _itemKeys.putIfAbsent(
                    article.entryId,
                    () => GlobalKey(),
                  );
                  return Obx(() {
                    final selectedId =
                        controller.selectedArticle.value?.entryId;
                    return ArticleCard(
                      key: articleKey,
                      article: article,
                      isSelected:
                          Platform.isMacOS && selectedId == article.entryId,
                      onTap: () {
                        if (Platform.isMacOS) {
                          _handleMacArticleTap(article);
                        } else {
                          Get.toNamed(
                            Routes.article,
                            arguments: {
                              'article': article,
                              'sequence': controller.articles.toList(),
                              'index': articleIndex,
                            },
                          );
                        }
                      },
                    );
                  });
                },
              ),
      );
    });
  }
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
      Widget? trailing;

      if (feedId != null && Get.isRegistered<SubscriptionsController>()) {
        final sub = Get.find<SubscriptionsController>();
        final feed = sub.allFeeds.firstWhereOrNull((f) => f.feedId == feedId);
        if (feed != null) {
          title = feed.title;
          final unread = controller.articles.where((a) => !a.isRead).length;
          final total = controller.articles.length;
          subtitle = unread > 0 ? '$unread 篇未读 · $total 篇当前列表' : '$total 篇当前列表';
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FeedToggleIcon(
                icon: Icons.article_outlined,
                activeIcon: Icons.article,
                enabled:
                    FeedReadabilitySettingsService.isAutoReadabilityEnabled(
                      feedId,
                    ),
                tooltip: '自动拉取全文',
                onToggle: () {
                  FeedReadabilitySettingsService.toggleAutoReadability(feedId);
                },
                colorScheme: cs,
              ),
              const SizedBox(width: 2),
              _FeedToggleIcon(
                icon: Icons.translate_outlined,
                activeIcon: Icons.translate,
                enabled: FeedTranslationSettingsService.isAutoTranslateEnabled(
                  feedId,
                ),
                tooltip: '自动翻译',
                onToggle: () {
                  FeedTranslationSettingsService.toggleAutoTranslate(feedId);
                },
                colorScheme: cs,
              ),
            ],
          );
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
        backgroundColor: cs.surface.withValues(alpha: 0.5),
        centerTitle: false,
        actions: [
          ?trailing,
          if (feedId != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              tooltip: '清除筛选',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                controller.selectedFeedId.value = null;
                controller.selectedCategory.value = null;
              },
            ),
          _MacSyncButton(controller: controller, colorScheme: cs),
        ],
      );
    });
  }
}

class _MacSyncButton extends StatefulWidget {
  final TimelineController controller;
  final ColorScheme colorScheme;

  const _MacSyncButton({required this.controller, required this.colorScheme});

  @override
  State<_MacSyncButton> createState() => _MacSyncButtonState();
}

class _MacSyncButtonState extends State<_MacSyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    _spinController.repeat();

    try {
      await Future.wait([
        widget.controller.loadFeedsThenArticles(),
        Future<void>.delayed(const Duration(milliseconds: 450)),
      ]);
    } finally {
      if (mounted) {
        _spinController.stop();
        _spinController.reset();
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return IconButton(
      icon: RotationTransition(
        turns: ReverseAnimation(_spinController),
        child: Icon(
          Icons.sync,
          size: 20,
          color: _isSyncing ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      tooltip: _isSyncing ? '同步中' : '同步',
      visualDensity: VisualDensity.compact,
      onPressed: _isSyncing ? null : _sync,
    );
  }
}

/// macOS 时间线 AppBar 内的小型开关图标（带本地状态）
class _FeedToggleIcon extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onToggle;
  final ColorScheme colorScheme;

  const _FeedToggleIcon({
    required this.icon,
    required this.activeIcon,
    required this.enabled,
    required this.tooltip,
    required this.onToggle,
    required this.colorScheme,
  });

  @override
  State<_FeedToggleIcon> createState() => _FeedToggleIconState();
}

class _FeedToggleIconState extends State<_FeedToggleIcon> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
  }

  @override
  void didUpdateWidget(covariant _FeedToggleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _enabled = widget.enabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _enabled ? widget.activeIcon : widget.icon,
        size: 20,
        color: _enabled
            ? widget.colorScheme.primary
            : widget.colorScheme.onSurfaceVariant,
      ),
      tooltip: widget.tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        widget.onToggle();
        setState(() => _enabled = !_enabled);
      },
    );
  }
}
