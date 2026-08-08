import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/constants/app_semantic_colors.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/continuous_rectangle.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/mobile_article_range_button.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/feed_silent_settings_service.dart';
import '../../utils/move_to_background.dart';
import '../settings/settings_page.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../subscriptions/subscriptions_page.dart';
import '../timeline/filter_review_page.dart';
import '../timeline/timeline_controller.dart';
import '../timeline/timeline_page.dart';
import '../recent_read/recent_read_page.dart';
import '../widgets/article_search_delegate.dart';
import 'main_controller.dart';
import 'widgets/macos_sidebar.dart';

const _macOSWindowContentRadius = 24.0;

/// 主页面 — 移动端保留底部导航，macOS 使用桌面分栏布局。
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final MainController controller;
  late final TimelineController _timelineController;

  static const _mobileTitles = ['时间线', '垃圾拦截', '订阅源', '设置'];

  static const _mobilePages = <Widget>[
    TimelinePage(showAppBar: false),
    FilterReviewPage(embeddedInMainNavigation: true),
    SubscriptionsPage(),
    SettingsPage(showAppBar: false),
  ];

  List<Widget> get _macPages => [
    const TimelinePage(showAppBar: false),
    const FilterReviewPage(),
    const RecentReadPage(),
    const SettingsPage(showAppBar: false),
  ];

  @override
  void initState() {
    super.initState();
    controller = Get.put(MainController());
    _timelineController = Get.put(TimelineController());
    if (Platform.isMacOS) {
      Get.put(SubscriptionsController());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (Platform.isMacOS) {
      return _buildMacOSLayout(colorScheme);
    }

    return _buildMobileLayout(context);
  }

  Widget _buildMacOSLayout(ColorScheme colorScheme) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ContinuousRectangleClip(
        radius: _macOSWindowContentRadius,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  const SizedBox(width: macOSSidebarExpandedWidth),
                  Expanded(
                    child: ColoredBox(
                      color: colorScheme.surface,
                      child: Obx(
                        () => IndexedStack(
                          index: controller.currentIndex.value,
                          children: _macPages,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Obx(() {
                return MacOSSidebar(
                  currentIndex: controller.currentIndex.value,
                  onIndexChanged: controller.changeIndex,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        MoveToBackground.moveTaskToBack();
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: MobileBlurAppBar(
          leadingWidth: 60,
          leading: Obx(() {
            if (controller.currentIndex.value != 0) {
              return const SizedBox.shrink();
            }
            final mode = _timelineController.selectedMode.value;
            return Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MobileArticleRangeButton(
                  unreadOnly: mode == TimelineViewMode.unread,
                  onChanged: (unreadOnly) => _timelineController.setViewMode(
                    unreadOnly ? TimelineViewMode.unread : TimelineViewMode.all,
                  ),
                ),
              ),
            );
          }),
          title: Obx(() {
            final index = controller.currentIndex.value;
            if (index == 1) {
              return const FilterReviewStatusTitle();
            }
            return Text(
              _mobileTitles[index],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            );
          }),
          actions: [
            Obx(() {
              if (controller.currentIndex.value != 0) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppGlassIconButton(
                    icon: Icons.search_rounded,
                    tooltip: '搜索',
                    size: 36,
                    iconSize: 19,
                    onPressed: () => _openTimelineSearch(context),
                  ),
                  const SizedBox(width: 12),
                ],
              );
            }),
          ],
        ),
        body: Obx(
          () => _FadeIndexedStack(
            index: controller.currentIndex.value,
            children: _mobilePages,
          ),
        ),
        bottomNavigationBar: Obx(() {
          final _ = FeedSilentSettingsService.version.value;
          return _MobileFloatingNavigation(
            selectedIndex: controller.currentIndex.value,
            timelineUnreadCount: _timelineController.unreadCount,
            filterReviewCount: _timelineController.filterCount.value,
            onSelected: controller.changeIndex,
          );
        }),
      ),
    );
  }

  Future<void> _openTimelineSearch(BuildContext context) async {
    if (controller.currentIndex.value != 0) {
      AppFeedback.info('无法搜索', '当前仅支持时间线文章搜索');
      return;
    }
    if (!Get.isRegistered<TimelineController>()) {
      return;
    }

    final timelineCtrl = Get.find<TimelineController>();
    final selected = await showSearch<ArticleModel?>(
      context: context,
      delegate: ArticleSearchDelegate(
        source: timelineCtrl.searchSourceArticles,
      ),
    );
    if (selected == null) return;

    final source = timelineCtrl.searchSourceArticles;
    final index = source.indexOf(selected);
    Get.toNamed(
      Routes.article,
      arguments: {
        'article': selected,
        'sequence': source,
        'index': index < 0 ? 0 : index,
      },
    );
  }
}

/// 淡入淡出切换三个主页，同时保留各页面状态。
class _FadeIndexedStack extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const _FadeIndexedStack({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(children.length, (i) {
        final active = i == index;
        return IgnorePointer(
          ignoring: !active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: TickerMode(enabled: active, child: children[i]),
          ),
        );
      }),
    );
  }
}

class _MobileFloatingNavigation extends StatelessWidget {
  final int selectedIndex;
  final int timelineUnreadCount;
  final int filterReviewCount;
  final ValueChanged<int> onSelected;

  const _MobileFloatingNavigation({
    required this.selectedIndex,
    required this.timelineUnreadCount,
    required this.filterReviewCount,
    required this.onSelected,
  });

  static const _items =
      <({IconData icon, IconData selectedIcon, String label})>[
        (
          icon: Icons.article_outlined,
          selectedIcon: Icons.article_rounded,
          label: '时间线',
        ),
        (
          icon: Icons.shield_outlined,
          selectedIcon: Icons.shield_rounded,
          label: '垃圾拦截',
        ),
        (
          icon: Icons.rss_feed_outlined,
          selectedIcon: Icons.rss_feed_rounded,
          label: '订阅源',
        ),
        (
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: '设置',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        height: 56,
        child: CustomPaint(
          painter: _MobileNavigationShadowPainter(isDark: isDark),
          child: AppGlassSurface(
            borderRadius: 28,
            padding: EdgeInsets.zero,
            tone: AppGlassTone.panel,
            nativeBackdrop: true,
            child: Row(
              children: List.generate(_items.length, (index) {
                final item = _items[index];
                final selected = selectedIndex == index;
                final badgeCount = switch (index) {
                  0 => timelineUnreadCount,
                  1 => filterReviewCount,
                  _ => 0,
                };
                return Expanded(
                  child: Semantics(
                    selected: selected,
                    button: true,
                    label: badgeCount > 0
                        ? '${item.label}，$badgeCount 篇未读'
                        : item.label,
                    child: Tooltip(
                      message: item.label,
                      child: InkWell(
                        onTap: () => onSelected(index),
                        customBorder: const StadiumBorder(),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 52,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.transparent,
                            ),
                            child: AnimatedScale(
                              scale: selected ? 1 : 0.96,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutBack,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    selected ? item.selectedIcon : item.icon,
                                    size: 24,
                                    color: selected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  if (badgeCount > 0)
                                    Positioned(
                                      top: 1,
                                      left: 28,
                                      child: _NavigationBadge(
                                        count: badgeCount,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationBadge extends StatelessWidget {
  final int count;

  const _NavigationBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppSemanticColors.unreadBadge,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: AppSemanticColors.onUnreadBadge,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _MobileNavigationShadowPainter extends CustomPainter {
  final bool isDark;

  const _MobileNavigationShadowPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final path = continuousRectanglePath(Offset.zero & size, 28);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(32))
      ..addPath(path, Offset.zero);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawPath(
      path.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.46 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.28 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MobileNavigationShadowPainter oldDelegate) {
    return isDark != oldDelegate.isDark;
  }
}
