import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/constants/macos_layout_metrics.dart';
import '../../../common/widgets/app_context_menu.dart';
import '../../../common/widgets/app_glass.dart';
import '../../../common/widgets/continuous_rectangle.dart';
import '../../../common/widgets/feedback_toast.dart';
import '../../../common/widgets/macos_window_drag_area.dart';
import '../../../http/init.dart';
import '../../../models/feed.dart';
import '../../../services/feed_readability_settings_service.dart';
import '../../../services/feed_silent_settings_service.dart';
import '../../../services/feed_translation_settings_service.dart';
import '../../../services/subscription_management_service.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../subscriptions/macos_subscription_dialog.dart';
import '../../timeline/timeline_controller.dart';

const macOSSidebarExpandedWidth = MacOSLayoutMetrics.sidebarExpandedWidth;

enum _FeedManagementAction { edit, unsubscribe }

enum _CategoryManagementAction { rename, ungroup }

class MacOSSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  const MacOSSidebar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timelineController = Get.find<TimelineController>();
    final subController = Get.find<SubscriptionsController>();

    return _MacOSSidebarSlot(
      width: macOSSidebarExpandedWidth,
      child: _MacOSGlassPane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SidebarHeader(),
            Obx(() {
              final isSelected =
                  currentIndex == 0 &&
                  timelineController.isSilentSelected.value == false &&
                  timelineController.selectedFeedId.value == null &&
                  timelineController.selectedCategory.value == null;
              final _ = FeedSilentSettingsService.version.value;
              final unreadCount = timelineController.unreadCount;
              return _SidebarItem(
                icon: Icons.article_outlined,
                label: '全部文章',
                isSelected: isSelected,
                badgeCount: unreadCount,
                onTap: () {
                  timelineController.setTimelineScope();
                  onIndexChanged(0);
                },
              );
            }),
            Obx(() {
              final filterCount = timelineController.filterCount.value;
              return _SidebarItem(
                icon: Icons.shield_outlined,
                label: '垃圾拦截',
                isSelected: currentIndex == 1,
                badgeCount: filterCount,
                onTap: () => onIndexChanged(1),
              );
            }),
            _SidebarItem(
              icon: Icons.history_rounded,
              label: '最近阅读',
              isSelected: currentIndex == 2,
              badgeCount: 0,
              onTap: () => onIndexChanged(2),
            ),
            const SizedBox(height: 10),
            _SectionLabel(
              label: '订阅源',
              action: _SidebarSectionAction(
                icon: Icons.add_rounded,
                tooltip: '添加 RSS 订阅',
                onPressed: () => _showAddSubscription(
                  context,
                  timelineController: timelineController,
                  subController: subController,
                ),
              ),
            ),
            Expanded(
              child: Obx(() {
                final state = subController.loadingState.value;
                if (state is Loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is LoadError) {
                  return Center(
                    child: Text(
                      '加载失败',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                final nodes = subController.sidebarNodes;
                final silentFeeds = subController.silentFeeds;
                if (nodes.isEmpty && silentFeeds.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无订阅源',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                return _SidebarSubscriptionsScrollArea(
                  children: [
                    for (final viewNode in nodes)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ViewLabel(label: viewNode.name),
                          ...viewNode.categories.map((category) {
                            final categoryKey =
                                'cat:${viewNode.name}:${category.name}';
                            return Obx(() {
                              final selectedFeedId =
                                  timelineController.selectedFeedId.value;
                              final selectedCategory =
                                  timelineController.selectedCategory.value;
                              final isSelected =
                                  currentIndex == 0 &&
                                  selectedCategory == category.name &&
                                  selectedFeedId == null;
                              final containsSelectedFeed =
                                  selectedFeedId != null &&
                                  category.feeds.any(
                                    (feed) => feed.feedId == selectedFeedId,
                                  );
                              final isSearchActive =
                                  subController.searchQuery.value.isNotEmpty;
                              final isRevealedBySelection =
                                  currentIndex == 0 && containsSelectedFeed;
                              final isTemporarilyRevealed =
                                  isSearchActive || isRevealedBySelection;
                              final isManuallyExpanded = subController
                                  .isExpanded(categoryKey);
                              final isExpanded =
                                  isTemporarilyRevealed || isManuallyExpanded;
                              return _CategoryGroup(
                                category: category,
                                isExpanded: isExpanded,
                                isSelected: isSelected,
                                badgeCount: subController.unreadForCategory(
                                  category.name,
                                  category.feeds,
                                ),
                                onToggle: isTemporarilyRevealed
                                    ? null
                                    : () {
                                        subController.setExpanded(
                                          categoryKey,
                                          !isManuallyExpanded,
                                        );
                                      },
                                toggleTooltip: isRevealedBySelection
                                    ? '当前订阅源位于此分组'
                                    : isSearchActive
                                    ? '搜索期间保持展开'
                                    : null,
                                onTap: () {
                                  timelineController.setTimelineScope(
                                    category: category.name,
                                  );
                                  onIndexChanged(0);
                                },
                                onSecondaryTapDown: (details) =>
                                    _showCategoryMenu(
                                      context,
                                      details.globalPosition,
                                      category: category,
                                      view: viewNode.view,
                                      timelineController: timelineController,
                                      subController: subController,
                                    ),
                                feedBuilder: (feed) {
                                  return Obx(() {
                                    final feedSelected =
                                        currentIndex == 0 &&
                                        timelineController
                                                .selectedFeedId
                                                .value ==
                                            feed.feedId;
                                    return _SidebarItem(
                                      icon: Icons.rss_feed,
                                      imageUrl: feed.image,
                                      label: feed.title,
                                      isSelected: feedSelected,
                                      badgeCount: subController.unreadFor(
                                        feed.feedId,
                                      ),
                                      indentLevel: 2,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _FeedAutoReadabilityIcon(
                                            feedId: feed.feedId,
                                          ),
                                          const SizedBox(width: 2),
                                          _FeedAutoTranslateIcon(
                                            feedId: feed.feedId,
                                          ),
                                          const SizedBox(width: 2),
                                          _FeedSilentIcon(feedId: feed.feedId),
                                        ],
                                      ),
                                      onTap: () {
                                        timelineController.setTimelineScope(
                                          feedId: feed.feedId,
                                        );
                                        onIndexChanged(0);
                                      },
                                      onSecondaryTapDown: (details) =>
                                          _showFeedMenu(
                                            context,
                                            details.globalPosition,
                                            feed: feed,
                                            timelineController:
                                                timelineController,
                                            subController: subController,
                                          ),
                                    );
                                  });
                                },
                              );
                            });
                          }),
                        ],
                      ),
                    _SilentFeedsGroup(
                      currentIndex: currentIndex,
                      timelineController: timelineController,
                      subController: subController,
                      onIndexChanged: onIndexChanged,
                      onFeedSecondaryTapDown: (feed, details) => _showFeedMenu(
                        context,
                        details.globalPosition,
                        feed: feed,
                        timelineController: timelineController,
                        subController: subController,
                      ),
                    ),
                  ],
                );
              }),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.28),
            ),
            _SidebarItem(
              icon: Icons.settings_outlined,
              label: '设置',
              isSelected: currentIndex == 3,
              badgeCount: 0,
              onTap: () => onIndexChanged(3),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  List<String> _categories(SubscriptionsController controller) {
    final categories = controller.allFeeds
        .where((feed) => !feed.isInbox)
        .map((feed) => feed.category?.trim())
        .whereType<String>()
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  Future<void> _showAddSubscription(
    BuildContext context, {
    required TimelineController timelineController,
    required SubscriptionsController subController,
  }) async {
    final feed = await showMacSubscriptionEditor(
      context,
      categories: _categories(subController),
    );
    if (feed == null) return;
    timelineController.setTimelineScope(feedId: feed.feedId);
    onIndexChanged(0);
  }

  Future<void> _showFeedMenu(
    BuildContext context,
    Offset position, {
    required FeedModel feed,
    required TimelineController timelineController,
    required SubscriptionsController subController,
  }) async {
    if (feed.isInbox) return;
    final action = await AppContextMenu.show<_FeedManagementAction>(
      context,
      position: position,
      entries: const [
        AppContextMenuAction(
          value: _FeedManagementAction.edit,
          icon: Icons.edit_outlined,
          label: '编辑订阅',
        ),
        AppContextMenuDivider(),
        AppContextMenuAction(
          value: _FeedManagementAction.unsubscribe,
          icon: Icons.remove_circle_outline_rounded,
          label: '取消订阅',
          destructive: true,
        ),
      ],
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case _FeedManagementAction.edit:
        await showMacSubscriptionEditor(
          context,
          feed: feed,
          categories: _categories(subController),
        );
        return;
      case _FeedManagementAction.unsubscribe:
        if (!await showMacUnsubscribeConfirmation(context, feed: feed) ||
            !context.mounted) {
          return;
        }
        final result = await SubscriptionManagementService.unsubscribe(feed);
        if (result is LoadError<void>) {
          AppFeedback.error('取消订阅失败', result.errMsg ?? '请稍后重试');
          return;
        }
        if (timelineController.selectedFeedId.value == feed.feedId) {
          timelineController.setTimelineScope();
        }
        AppFeedback.success('已取消订阅', '可使用 Command + Z 撤销');
        return;
    }
  }

  Future<void> _showCategoryMenu(
    BuildContext context,
    Offset position, {
    required SourceCategoryNode category,
    required int view,
    required TimelineController timelineController,
    required SubscriptionsController subController,
  }) async {
    if (category.name == '未分类') return;
    final action = await AppContextMenu.show<_CategoryManagementAction>(
      context,
      position: position,
      entries: const [
        AppContextMenuAction(
          value: _CategoryManagementAction.rename,
          icon: Icons.drive_file_rename_outline_rounded,
          label: '重命名分类',
        ),
        AppContextMenuAction(
          value: _CategoryManagementAction.ungroup,
          icon: Icons.folder_off_outlined,
          label: '取消分组',
        ),
      ],
    );
    if (!context.mounted || action == null) return;

    var newCategory = '';
    if (action == _CategoryManagementAction.rename) {
      final renamed = await showMacCategoryRenameDialog(
        context,
        category: category.name,
      );
      if (renamed == null) return;
      newCategory = renamed;
    }

    final affectedFeeds = subController.allFeeds
        .where(
          (feed) =>
              !feed.isInbox &&
              (feed.view ?? 0) == view &&
              feed.displayCategory == category.name,
        )
        .toList(growable: false);
    final result = await SubscriptionManagementService.renameCategory(
      feeds: affectedFeeds,
      newCategory: newCategory,
    );
    if (result is LoadError<int>) {
      AppFeedback.error('分类更新不完整', result.errMsg ?? '请稍后重试');
      return;
    }
    if (timelineController.selectedCategory.value == category.name) {
      timelineController.setTimelineScope(
        category: newCategory.isEmpty ? '未分类' : newCategory,
      );
    }
    AppFeedback.success(
      action == _CategoryManagementAction.rename ? '分类已重命名' : '已取消分组',
      '${affectedFeeds.length} 个订阅源已更新',
    );
  }
}

class _SidebarSubscriptionsScrollArea extends StatefulWidget {
  final List<Widget> children;

  const _SidebarSubscriptionsScrollArea({required this.children});

  @override
  State<_SidebarSubscriptionsScrollArea> createState() =>
      _SidebarSubscriptionsScrollAreaState();
}

class _SidebarSubscriptionsScrollAreaState
    extends State<_SidebarSubscriptionsScrollArea> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      notificationPredicate: (notification) => notification.depth == 0,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

class _SilentFeedsGroup extends StatelessWidget {
  final int currentIndex;
  final TimelineController timelineController;
  final SubscriptionsController subController;
  final ValueChanged<int> onIndexChanged;
  final void Function(FeedModel feed, TapDownDetails details)
  onFeedSecondaryTapDown;

  const _SilentFeedsGroup({
    required this.currentIndex,
    required this.timelineController,
    required this.subController,
    required this.onIndexChanged,
    required this.onFeedSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final silentFeeds = subController.silentFeeds;
      if (silentFeeds.isEmpty) return const SizedBox.shrink();

      const groupKey = 'special:silent';
      final isSilentSelected =
          currentIndex == 0 && timelineController.isSilentSelected.value;
      final isExpanded = subController.isExpanded(groupKey);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          const _ViewLabel(label: '静默'),
          _CategoryItem(
            label: '静默订阅源',
            collapsedIcon: Icons.notifications_off_outlined,
            expandedIcon: Icons.notifications_off,
            isSelected:
                isSilentSelected &&
                timelineController.selectedFeedId.value == null,
            badgeCount: timelineController.silentUnreadCount,
            isExpanded: isExpanded,
            onToggle: () {
              subController.setExpanded(groupKey, !isExpanded);
            },
            onTap: () {
              timelineController.setTimelineScope(silent: true);
              onIndexChanged(0);
            },
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: silentFeeds.map((feed) {
                        return Obx(() {
                          final feedSelected =
                              currentIndex == 0 &&
                              timelineController.selectedFeedId.value ==
                                  feed.feedId &&
                              timelineController.isSilentSelected.value;
                          return _SidebarItem(
                            icon: Icons.rss_feed,
                            imageUrl: feed.image,
                            label: feed.title,
                            isSelected: feedSelected,
                            badgeCount: subController.rawUnreadFor(feed.feedId),
                            indentLevel: 2,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FeedAutoReadabilityIcon(feedId: feed.feedId),
                                const SizedBox(width: 2),
                                _FeedAutoTranslateIcon(feedId: feed.feedId),
                                const SizedBox(width: 2),
                                _FeedSilentIcon(feedId: feed.feedId),
                              ],
                            ),
                            onTap: () {
                              timelineController.setTimelineScope(
                                silent: true,
                                feedId: feed.feedId,
                              );
                              onIndexChanged(0);
                            },
                            onSecondaryTapDown: (details) =>
                                onFeedSecondaryTapDown(feed, details),
                          );
                        });
                      }).toList(),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      );
    });
  }
}

class _MacOSSidebarSlot extends StatelessWidget {
  final double width;
  final Widget child;

  const _MacOSSidebarSlot({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _MacOSSidebarSlotPainter(
          backgroundColor: cs.surface,
          panelMargin: MacOSLayoutMetrics.sidebarPanelMargin,
          panelRadius: MacOSLayoutMetrics.sidebarPanelRadius,
          isDark: isDark,
        ),
        child: child,
      ),
    );
  }
}

class _MacOSSidebarSlotPainter extends CustomPainter {
  final Color backgroundColor;
  final EdgeInsets panelMargin;
  final double panelRadius;
  final bool isDark;

  const _MacOSSidebarSlotPainter({
    required this.backgroundColor,
    required this.panelMargin,
    required this.panelRadius,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final panelRect = Rect.fromLTWH(
      panelMargin.left,
      panelMargin.top,
      size.width - panelMargin.horizontal,
      size.height - panelMargin.vertical,
    );
    final panel = continuousRectanglePath(panelRect, panelRadius);
    final backgroundPath = Path.combine(PathOperation.difference, outer, panel);
    canvas.drawPath(backgroundPath, Paint()..color = backgroundColor);
    if (!isDark) {
      canvas.save();
      canvas.clipPath(backgroundPath);
      _drawShadow(
        canvas,
        panel,
        color: Colors.black.withValues(alpha: 0.045),
        blurRadius: 6,
        offset: const Offset(0, 1.5),
      );
      _drawShadow(
        canvas,
        panel,
        color: Colors.black.withValues(alpha: 0.055),
        blurRadius: 1.5,
        offset: const Offset(0, 0.75),
      );
      canvas.restore();
    }
  }

  void _drawShadow(
    Canvas canvas,
    Path path, {
    required Color color,
    required double blurRadius,
    required Offset offset,
  }) {
    canvas.drawPath(
      path.shift(offset),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
    );
  }

  @override
  bool shouldRepaint(covariant _MacOSSidebarSlotPainter oldDelegate) {
    return backgroundColor != oldDelegate.backgroundColor ||
        panelMargin != oldDelegate.panelMargin ||
        panelRadius != oldDelegate.panelRadius ||
        isDark != oldDelegate.isDark;
  }
}

class _MacOSGlassPane extends StatelessWidget {
  final Widget child;

  const _MacOSGlassPane({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: MacOSLayoutMetrics.sidebarPanelMargin,
      child: CustomPaint(
        foregroundPainter: _MacOSSidebarBorderPainter(
          radius: MacOSLayoutMetrics.sidebarPanelRadius,
          isDark: isDark,
        ),
        child: ContinuousRectangleClip(
          radius: MacOSLayoutMetrics.sidebarPanelRadius,
          child: child,
        ),
      ),
    );
  }
}

class _MacOSSidebarBorderPainter extends CustomPainter {
  final double radius;
  final bool isDark;

  const _MacOSSidebarBorderPainter({
    required this.radius,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = continuousRectanglePath(
      (Offset.zero & size).deflate(0.25),
      radius - 0.25,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MacOSSidebarBorderPainter oldDelegate) {
    return radius != oldDelegate.radius || isDark != oldDelegate.isDark;
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return const MacOSWindowDragArea(child: SizedBox(height: 38));
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Widget? action;

  const _SectionLabel({required this.label, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
        ),
        if (action != null) Positioned(right: 24, top: 4, child: action!),
      ],
    );
  }
}

class _SidebarSectionAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SidebarSectionAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_SidebarSectionAction> createState() => _SidebarSectionActionState();
}

class _SidebarSectionActionState extends State<_SidebarSectionAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillAlpha = _pressed
        ? (isDark ? 0.11 : 0.08)
        : _hovered
        ? (isDark ? 0.06 : 0.045)
        : 0.0;

    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: fillAlpha),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: cs.onSurfaceVariant.withValues(
              alpha: _hovered || _pressed ? 0.92 : 0.72,
            ),
          ),
        ),
      ),
    );

    return AppGlassTooltip(message: widget.tooltip, child: button);
  }
}

class _ViewLabel extends StatelessWidget {
  final String label;

  const _ViewLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.primary.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  final SourceCategoryNode category;
  final bool isExpanded;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback? onToggle;
  final String? toggleTooltip;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final Widget Function(FeedModel feed) feedBuilder;

  const _CategoryGroup({
    required this.category,
    required this.isExpanded,
    required this.isSelected,
    required this.badgeCount,
    required this.onToggle,
    this.toggleTooltip,
    required this.onTap,
    this.onSecondaryTapDown,
    required this.feedBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryItem(
          label: category.name,
          isExpanded: isExpanded,
          isSelected: isSelected,
          badgeCount: badgeCount,
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onToggle: onToggle,
          toggleTooltip: toggleTooltip,
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: category.feeds.map(feedBuilder).toList(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final String label;
  final IconData collapsedIcon;
  final IconData expandedIcon;
  final bool isExpanded;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final VoidCallback? onToggle;
  final String? toggleTooltip;

  const _CategoryItem({
    required this.label,
    this.collapsedIcon = Icons.folder_outlined,
    this.expandedIcon = Icons.folder_open_outlined,
    required this.isExpanded,
    required this.isSelected,
    required this.badgeCount,
    required this.onTap,
    this.onSecondaryTapDown,
    required this.onToggle,
    this.toggleTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.62)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Row(
              children: [
                AppGlassTooltip(
                  message: toggleTooltip ?? (isExpanded ? '折叠' : '展开'),
                  child: IconButton(
                    icon: AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.chevron_right_rounded),
                    ),
                    iconSize: 18,
                    tooltip: '',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    style: const ButtonStyle(
                      overlayColor: WidgetStatePropertyAll(Colors.transparent),
                    ),
                    // Keep this hit target separate from the category action.
                    // When expansion is temporarily locked, it intentionally
                    // consumes the click without changing either state.
                    onPressed: onToggle ?? () {},
                  ),
                ),
                Icon(
                  isExpanded ? expandedIcon : collapsedIcon,
                  size: 16,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                _UnreadBadge(count: badgeCount, selected: isSelected),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String? imageUrl;
  final String label;
  final bool isSelected;
  final int badgeCount;
  final int indentLevel;
  final Widget? trailing;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  const _SidebarItem({
    required this.icon,
    this.imageUrl,
    required this.label,
    required this.isSelected,
    required this.badgeCount,
    this.indentLevel = 0,
    this.trailing,
    required this.onTap,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 12.0 + (indentLevel * 12.0),
        right: 12.0,
        top: 2.0,
        bottom: 2.0,
      ),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.62)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      width: 16,
                      height: 16,
                      errorWidget: (_, _, _) =>
                          Icon(icon, size: 16, color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?trailing,
                _UnreadBadge(count: badgeCount, selected: isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  final bool selected;

  const _UnreadBadge({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? cs.primary
            : cs.onSurfaceVariant.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─── Feed 侧边栏自动拉取/翻译开关图标 ──────────────────

class _FeedAutoReadabilityIcon extends StatefulWidget {
  final String feedId;
  const _FeedAutoReadabilityIcon({required this.feedId});

  @override
  State<_FeedAutoReadabilityIcon> createState() =>
      _FeedAutoReadabilityIconState();
}

class _FeedAutoReadabilityIconState extends State<_FeedAutoReadabilityIcon> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = FeedReadabilitySettingsService.isAutoReadabilityEnabled(
      widget.feedId,
    );
  }

  void _toggle() {
    final next = !_enabled;
    FeedReadabilitySettingsService.setAutoReadability(widget.feedId, next);
    setState(() => _enabled = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppGlassTooltip(
      message: _enabled ? '已开启自动拉取全文' : '自动拉取全文',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _enabled ? Icons.article : Icons.article_outlined,
            size: 14,
            color: _enabled
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _FeedAutoTranslateIcon extends StatefulWidget {
  final String feedId;
  const _FeedAutoTranslateIcon({required this.feedId});

  @override
  State<_FeedAutoTranslateIcon> createState() => _FeedAutoTranslateIconState();
}

class _FeedAutoTranslateIconState extends State<_FeedAutoTranslateIcon> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = FeedTranslationSettingsService.isAutoTranslateEnabled(
      widget.feedId,
    );
  }

  void _toggle() {
    final next = !_enabled;
    FeedTranslationSettingsService.setAutoTranslate(widget.feedId, next);
    setState(() => _enabled = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppGlassTooltip(
      message: _enabled ? '已开启自动翻译' : '自动翻译',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _enabled ? Icons.translate : Icons.translate_outlined,
            size: 14,
            color: _enabled
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _FeedSilentIcon extends StatefulWidget {
  final String feedId;
  const _FeedSilentIcon({required this.feedId});

  @override
  State<_FeedSilentIcon> createState() => _FeedSilentIconState();
}

class _FeedSilentIconState extends State<_FeedSilentIcon> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = FeedSilentSettingsService.isSilent(widget.feedId);
  }

  void _toggle() {
    final next = !_enabled;
    FeedSilentSettingsService.setSilent(widget.feedId, next);
    setState(() => _enabled = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppGlassTooltip(
      message: _enabled ? '已开启静默' : '设为静默',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _enabled
                ? Icons.notifications_off
                : Icons.notifications_off_outlined,
            size: 14,
            color: _enabled
                ? cs.error
                : cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
