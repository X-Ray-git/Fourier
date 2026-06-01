import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/refresh_aware_scroll_physics.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../common/widgets/shimmer_card.dart';

import 'dart:io';
import '../../http/init.dart';
import '../../router/app_pages.dart';
import '../../services/article_state_notifier.dart';
import '../article/article_page.dart';
import '../widgets/article_card.dart';
import 'timeline_controller.dart';

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 380,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('时间线', style: TextStyle(fontSize: 16)),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.5),
                    centerTitle: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.sync, size: 20),
                        tooltip: '同步',
                        onPressed: () => controller.loadFeedsThenArticles(),
                      ),
                    ],
                  ),
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
                    return const Center(child: Text('请在左侧选择文章'));
                  }
                  return ArticlePageView(
                    key: ValueKey(selected.entryId),
                    article: selected,
                    isSplitView: true,
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
                  _buildFilterBar(filterCount),
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
                itemCount: controller.articles.length + 1, // +1 for filter bar
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildFilterBar(filterCount);
                  }
                  final articleIndex = index - 1;
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
                  return ArticleCard(
                    article: article,
                    isSelected:
                        Platform.isMacOS &&
                        controller.selectedArticle.value?.entryId ==
                            article.entryId,
                    onTap: () {
                      if (Platform.isMacOS) {
                        controller.selectedArticle.value = article;
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
