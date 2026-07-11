import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/app_glass.dart';
import '../../../common/widgets/continuous_rectangle.dart';
import '../../../http/init.dart';
import '../../../models/feed.dart';
import '../../../services/feed_readability_settings_service.dart';
import '../../../services/feed_silent_settings_service.dart';
import '../../../services/feed_translation_settings_service.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../timeline/timeline_controller.dart';

const _macOSSidebarPanelRadius = 18.0;
const EdgeInsets _macOSSidebarPanelMargin = EdgeInsets.fromLTRB(8, 8, 8, 8);
const macOSSidebarExpandedWidth = 290.0;

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
            const _SectionLabel(label: '订阅源'),
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

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 18),
                  itemCount: nodes.length + 1,
                  itemBuilder: (context, index) {
                    if (index == nodes.length) {
                      return _SilentFeedsGroup(
                        currentIndex: currentIndex,
                        timelineController: timelineController,
                        subController: subController,
                        onIndexChanged: onIndexChanged,
                      );
                    }

                    final viewNode = nodes[index];
                    return Column(
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
                            final forceExpanded =
                                subController.searchQuery.value.isNotEmpty ||
                                containsSelectedFeed;
                            final isExpanded =
                                forceExpanded ||
                                subController.isExpanded(categoryKey);
                            return _CategoryGroup(
                              category: category,
                              isExpanded: isExpanded,
                              isSelected: isSelected,
                              badgeCount: subController.unreadForCategory(
                                category.name,
                                category.feeds,
                              ),
                              onToggle: () {
                                subController.setExpanded(
                                  categoryKey,
                                  !isExpanded,
                                );
                              },
                              onTap: () {
                                timelineController.setTimelineScope(
                                  category: category.name,
                                );
                                onIndexChanged(0);
                              },
                              feedBuilder: (feed) {
                                return Obx(() {
                                  final feedSelected =
                                      currentIndex == 0 &&
                                      timelineController.selectedFeedId.value ==
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
                                  );
                                });
                              },
                            );
                          });
                        }),
                      ],
                    );
                  },
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
}

class _SilentFeedsGroup extends StatelessWidget {
  final int currentIndex;
  final TimelineController timelineController;
  final SubscriptionsController subController;
  final ValueChanged<int> onIndexChanged;

  const _SilentFeedsGroup({
    required this.currentIndex,
    required this.timelineController,
    required this.subController,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final silentFeeds = subController.silentFeeds;
      if (silentFeeds.isEmpty) return const SizedBox.shrink();

      const groupKey = 'special:silent';
      final isSilentSelected =
          currentIndex == 0 && timelineController.isSilentSelected.value;
      final isExpanded = isSilentSelected || subController.isExpanded(groupKey);

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
              subController.setExpanded(groupKey, true);
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
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _MacOSSidebarSlotPainter(
          backgroundColor: cs.surface,
          panelMargin: _macOSSidebarPanelMargin,
          panelRadius: _macOSSidebarPanelRadius,
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

  const _MacOSSidebarSlotPainter({
    required this.backgroundColor,
    required this.panelMargin,
    required this.panelRadius,
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
  }

  @override
  bool shouldRepaint(covariant _MacOSSidebarSlotPainter oldDelegate) {
    return backgroundColor != oldDelegate.backgroundColor ||
        panelMargin != oldDelegate.panelMargin ||
        panelRadius != oldDelegate.panelRadius;
  }
}

class _MacOSGlassPane extends StatelessWidget {
  final Widget child;

  const _MacOSGlassPane({required this.child});

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      borderRadius: _macOSSidebarPanelRadius,
      margin: _macOSSidebarPanelMargin,
      tone: AppGlassTone.panel,
      nativeBackdrop: true,
      child: child,
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.only(right: 10, top: 10),
        child: Align(
          alignment: Alignment.centerRight,
          // 实验性 UI 精简：暂时取消“收起”按钮以避开 macOS 红绿灯，
          // 但保留原有对齐逻辑和 SizedBox 高度占位，以便需要时随时恢复为 IconButton。
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
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
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final Widget Function(FeedModel feed) feedBuilder;

  const _CategoryGroup({
    required this.category,
    required this.isExpanded,
    required this.isSelected,
    required this.badgeCount,
    required this.onToggle,
    required this.onTap,
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
          onToggle: onToggle,
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
  final VoidCallback onToggle;

  const _CategoryItem({
    required this.label,
    this.collapsedIcon = Icons.folder_outlined,
    this.expandedIcon = Icons.folder_open_outlined,
    required this.isExpanded,
    required this.isSelected,
    required this.badgeCount,
    required this.onTap,
    required this.onToggle,
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
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 10),
            child: Row(
              children: [
                AppGlassTooltip(
                  message: isExpanded ? '折叠' : '展开',
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
                    onPressed: onToggle,
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

  const _SidebarItem({
    required this.icon,
    this.imageUrl,
    required this.label,
    required this.isSelected,
    required this.badgeCount,
    this.indentLevel = 0,
    this.trailing,
    required this.onTap,
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
