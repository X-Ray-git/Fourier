import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/continuous_rectangle.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
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

  static const _titles = ['时间线', '订阅源', '设置'];

  static const _mobilePages = <Widget>[
    TimelinePage(showAppBar: false),
    SubscriptionsPage(),
    SettingsPage(showAppBar: false),
  ];

  List<Widget> get _macPages => [
    TimelinePage(
      showAppBar: false,
      onOpenFilterReview: () => controller.changeIndex(1),
    ),
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

    return _buildMobileLayout(context, colorScheme);
  }

  Widget _buildMacOSLayout(ColorScheme colorScheme) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ContinuousRectangleClip(
        radius: _macOSWindowContentRadius,
        child: Row(
          children: [
            Obx(() {
              return MacOSSidebar(
                currentIndex: controller.currentIndex.value,
                onIndexChanged: controller.changeIndex,
              );
            }),
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
    );
  }

  Widget _buildMobileLayout(BuildContext context, ColorScheme colorScheme) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        MoveToBackground.moveTaskToBack();
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leadingWidth: 130,
          leading: Obx(() {
            if (controller.currentIndex.value != 0) {
              return const SizedBox.shrink();
            }
            final mode = _timelineController.selectedMode.value;
            final _ = _timelineController.allArticles.length;
            return Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Center(
                child: _TimelineModeButton(
                  mode: mode,
                  controller: _timelineController,
                  onSelected: _timelineController.setViewMode,
                ),
              ),
            );
          }),
          title: Obx(
            () => Text(
              _titles[controller.currentIndex.value],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: colorScheme.surface.withValues(alpha: 0.50),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: '搜索',
              onPressed: () => _openTimelineSearch(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Obx(
          () => _FadeIndexedStack(
            index: controller.currentIndex.value,
            children: _mobilePages,
          ),
        ),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                ),
              ),
              child: Obx(
                () => NavigationBar(
                  elevation: 0,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.50),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  indicatorColor: colorScheme.primary.withValues(alpha: 0.80),
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: controller.currentIndex.value,
                  onDestinationSelected: controller.changeIndex,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: '时间线',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.rss_feed_outlined),
                      selectedIcon: Icon(Icons.rss_feed),
                      label: '订阅源',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _TimelineModeButton extends StatelessWidget {
  final TimelineViewMode mode;
  final TimelineController controller;
  final ValueChanged<TimelineViewMode> onSelected;

  const _TimelineModeButton({
    required this.mode,
    required this.controller,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Builder(
        builder: (buttonContext) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final button = buttonContext.findRenderObject() as RenderBox;
            final overlay =
                Navigator.of(context).overlay!.context.findRenderObject()
                    as RenderBox;
            final position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(
                  Offset(0, button.size.height + 8),
                  ancestor: overlay,
                ),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero) + const Offset(0, 8),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );
            showMenu<TimelineViewMode>(
              context: context,
              position: position,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.95,
              ),
              elevation: 4,
              items: [
                PopupMenuItem(
                  value: TimelineViewMode.unread,
                  child: Text('未读 ${controller.unreadCount}'),
                ),
                PopupMenuItem(
                  value: TimelineViewMode.all,
                  child: Text('全部 ${controller.allCount}'),
                ),
                PopupMenuItem(
                  value: TimelineViewMode.read,
                  child: Text('已读 ${controller.readCount}'),
                ),
              ],
            ).then((value) {
              if (value != null) onSelected(value);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: mode == TimelineViewMode.unread
                  ? colorScheme.primary.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: mode == TimelineViewMode.unread
                    ? colorScheme.primary.withValues(alpha: 0.3)
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _modeIcon(mode),
                  size: 16,
                  color: mode == TimelineViewMode.unread
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_modeLabel(mode)} ${_modeCount(controller, mode)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: mode == TimelineViewMode.unread
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _modeIcon(TimelineViewMode mode) => switch (mode) {
    TimelineViewMode.unread => Icons.mark_email_unread_rounded,
    TimelineViewMode.all => Icons.inbox_rounded,
    TimelineViewMode.read => Icons.done_all_rounded,
  };

  String _modeLabel(TimelineViewMode mode) => switch (mode) {
    TimelineViewMode.unread => '未读',
    TimelineViewMode.all => '全部',
    TimelineViewMode.read => '已读',
  };

  int _modeCount(TimelineController controller, TimelineViewMode mode) =>
      switch (mode) {
        TimelineViewMode.unread => controller.unreadCount,
        TimelineViewMode.all => controller.allCount,
        TimelineViewMode.read => controller.readCount,
      };
}

/// 优雅的淡入淡出堆叠组件，保留页面状态。
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
            opacity: active ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: TickerMode(enabled: active, child: children[i]),
          ),
        );
      }),
    );
  }
}
