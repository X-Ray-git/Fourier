import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../http/init.dart';
import '../../../models/feed.dart';
import '../../../services/feed_readability_settings_service.dart';
import '../../../services/feed_silent_settings_service.dart';
import '../../../services/feed_translation_settings_service.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../timeline/timeline_controller.dart';

class MacOSSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onCollapse;

  const MacOSSidebar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timelineController = Get.find<TimelineController>();
    final subController = Get.find<SubscriptionsController>();

    return SizedBox(
      width: 268,
      child: _MacOSGlassPane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarHeader(onCollapse: onCollapse),
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
                  timelineController.isSilentSelected.value = false;
                  timelineController.selectedFeedId.value = null;
                  timelineController.selectedCategory.value = null;
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
            Obx(() {
              final isSelected =
                  currentIndex == 0 &&
                  timelineController.isSilentSelected.value == true;
              final silentFeeds = subController.silentFeeds;
              final isExpanded = isSelected;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SidebarItem(
                    icon: Icons.notifications_off_outlined,
                    label: '静默订阅源',
                    isSelected: isSelected && timelineController.selectedFeedId.value == null,
                    badgeCount: timelineController.silentUnreadCount,
                    onTap: () {
                      timelineController.isSilentSelected.value = true;
                      timelineController.selectedFeedId.value = null;
                      timelineController.selectedCategory.value = null;
                      onIndexChanged(0);
                    },
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: isExpanded && silentFeeds.isNotEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: silentFeeds.map((feed) {
                                return Obx(() {
                                  final feedSelected =
                                      currentIndex == 0 &&
                                      timelineController.selectedFeedId.value == feed.feedId &&
                                      timelineController.isSilentSelected.value == true;
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
                                      timelineController.isSilentSelected.value = true;
                                      timelineController.selectedCategory.value = null;
                                      timelineController.selectedFeedId.value = feed.feedId;
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
            }),
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
                if (nodes.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无订阅源',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 18),
                  itemCount: nodes.length,
                  itemBuilder: (context, index) {
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
                                timelineController.isSilentSelected.value = false;
                                timelineController.selectedFeedId.value = null;
                                timelineController.selectedCategory.value =
                                    category.name;
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
                                        _FeedSilentIcon(
                                          feedId: feed.feedId,
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      timelineController.isSilentSelected.value = false;
                                      timelineController
                                              .selectedCategory
                                              .value =
                                          null;
                                      timelineController.selectedFeedId.value =
                                          feed.feedId;
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

class MacOSCollapsedSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onExpand;

  const MacOSCollapsedSidebar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: _MacOSGlassPane(
        child: Column(
          children: [
            const SizedBox(height: 42),
            _RailButton(
              icon: Icons.keyboard_double_arrow_right_rounded,
              tooltip: '展开侧边栏',
              onTap: onExpand,
            ),
            const SizedBox(height: 10),
            Obx(() {
              final timelineController = Get.find<TimelineController>();
              final isAllSelected = currentIndex == 0 &&
                  timelineController.isSilentSelected.value == false &&
                  timelineController.selectedFeedId.value == null &&
                  timelineController.selectedCategory.value == null;
              return _RailButton(
                icon: Icons.article_outlined,
                tooltip: '全部文章',
                selected: isAllSelected,
                onTap: () {
                  timelineController.isSilentSelected.value = false;
                  timelineController.selectedFeedId.value = null;
                  timelineController.selectedCategory.value = null;
                  onIndexChanged(0);
                },
              );
            }),
            _RailButton(
              icon: Icons.shield_outlined,
              tooltip: '垃圾拦截',
              selected: currentIndex == 1,
              onTap: () => onIndexChanged(1),
            ),
            _RailButton(
              icon: Icons.history_rounded,
              tooltip: '最近阅读',
              selected: currentIndex == 2,
              onTap: () => onIndexChanged(2),
            ),
            Obx(() {
              final timelineController = Get.find<TimelineController>();
              final isSilentSelected = currentIndex == 0 &&
                  timelineController.isSilentSelected.value == true;
              return _RailButton(
                icon: Icons.notifications_off_outlined,
                tooltip: '静默订阅源',
                selected: isSilentSelected,
                onTap: () {
                  timelineController.isSilentSelected.value = true;
                  timelineController.selectedFeedId.value = null;
                  timelineController.selectedCategory.value = null;
                  onIndexChanged(0);
                },
              );
            }),
            const Spacer(),
            _RailButton(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              selected: currentIndex == 3,
              onTap: () => onIndexChanged(3),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _MacOSGlassPane extends StatelessWidget {
  final Widget child;

  const _MacOSGlassPane({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseTint = isDark ? const Color(0xFF1E2024) : Colors.white;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: baseTint.withValues(alpha: isDark ? 0.26 : 0.18),
            border: Border(
              right: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.24),
                width: 0.5,
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.08 : 0.24),
                baseTint.withValues(alpha: isDark ? 0.16 : 0.10),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final VoidCallback onCollapse;

  const _SidebarHeader({required this.onCollapse});

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
  final bool isExpanded;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _CategoryItem({
    required this.label,
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
                IconButton(
                  icon: AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.chevron_right_rounded),
                  ),
                  iconSize: 18,
                  tooltip: isExpanded ? '折叠' : '展开',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onToggle,
                ),
                Icon(
                  isExpanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined,
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
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
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
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
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
    return Tooltip(
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
    return Tooltip(
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
    return Tooltip(
      message: _enabled ? '已开启静默' : '设为静默',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _enabled ? Icons.notifications_off : Icons.notifications_off_outlined,
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

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 38,
              height: 36,
              child: Icon(
                icon,
                size: 19,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
