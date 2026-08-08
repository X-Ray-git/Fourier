import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/mac_header_pane.dart';
import '../../common/widgets/macos_window_drag_area.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/local_article_db_service.dart';
import '../../services/external_link_service.dart';
import '../../services/mac_article_shortcut_service.dart';
import '../../services/undo_service.dart';
import '../../common/widgets/feedback_toast.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../widgets/article_card.dart';
import 'recent_read_controller.dart';
import '../../utils/scroll_utils.dart';

class RecentReadPage extends StatefulWidget {
  const RecentReadPage({super.key});

  @override
  State<RecentReadPage> createState() => _RecentReadPageState();
}

class _RecentReadPageState extends State<RecentReadPage> {
  late final RecentReadController controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _emptyDetailFocusNode = FocusNode(
    debugLabel: 'recent-read-empty-detail',
  );

  // 用于记录 Mac 分栏模式下的双击等状态
  DateTime? _lastArticleTapAt;
  String? _lastArticleTapEntryId;
  final selectedArticle = Rxn<ArticleModel>();
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    controller = Get.put(RecentReadController());
    if (Platform.isMacOS) {
      MacArticleShortcutService.instance.register(
        this,
        isActive: () =>
            mounted &&
            _isActiveMacRecentRead &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        hasSelection: () => selectedArticle.value != null,
        selectBoundary: (direction) {
          _selectRelativeArticle(direction);
          return controller.articles.isNotEmpty;
        },
      );
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      MacArticleShortcutService.instance.unregister(this);
    }
    _scrollController.dispose();
    _emptyDetailFocusNode.dispose();
    super.dispose();
  }

  void _clearSelectionAndFocusEmptyDetail() {
    selectedArticle.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isActiveMacRecentRead) {
        _emptyDetailFocusNode.requestFocus();
      }
    });
  }

  void _selectRelativeArticle(int delta) {
    final list = controller.articles;
    if (list.isEmpty) return;

    final selected = selectedArticle.value;
    if (selected == null) {
      final next = delta < 0 ? list.last : list.first;
      selectedArticle.value = next;
      _scrollToArticle(next.entryId);
      return;
    }
    final currentIndex = list.indexWhere((a) => a.entryId == selected.entryId);
    final nextIndex = (currentIndex + delta).clamp(0, list.length - 1);
    if (nextIndex < 0 || nextIndex >= list.length) return;
    selectedArticle.value = list[nextIndex];
    _scrollToArticle(list[nextIndex].entryId);
  }

  bool get _isActiveMacRecentRead {
    if (!Platform.isMacOS) return false;
    if (!Get.isRegistered<MainController>()) return true;
    return Get.find<MainController>().currentIndex.value == 2;
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
    await ExternalLinkService.openUrlWithFeedback(article.url);
  }

  void _handleMacArticleTap(ArticleModel article) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastArticleTapEntryId == article.entryId &&
        _lastArticleTapAt != null &&
        now.difference(_lastArticleTapAt!).inMilliseconds < 300;

    // 只记录最近阅读，不标记已读；本次页面会话不立即按最新阅读时间重排，
    // 下次重新进入或明确刷新时再排序，避免列表跳动。
    LocalArticleDbService.recordReadHistory(article.entryId);
    selectedArticle.value = article;
    _lastArticleTapEntryId = article.entryId;
    _lastArticleTapAt = now;

    if (isDoubleTap) {
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      _openOriginalAndMarkRead(article);
    }
  }

  void _openOriginalAndMarkRead(ArticleModel article) {
    _selectRelativeArticle(1);
    unawaited(_openOriginalArticle(article));
    if (!article.isRead) {
      unawaited(UndoService.markAsRead(article, showSuccess: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Platform.isMacOS
          ? null
          : const MobileBlurAppBar(
              title: Text(
                '最近阅读',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
      body: Obx(() {
        final state = controller.loadingState.value;

        final content = switch (state) {
          Loading() => const Center(child: CircularProgressIndicator()),
          LoadError(:final errMsg) => Center(child: Text(errMsg ?? '加载失败')),
          Success() => _buildListView(context),
        };

        if (Platform.isMacOS) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: MacHeaderPane(
                  headerHeight: kToolbarHeight,
                  header: AppBar(
                    title: const MacOSWindowDragArea(
                      child: Text(
                        '最近阅读',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    backgroundColor: Colors.transparent,
                    centerTitle: false,
                    elevation: 0,
                    scrolledUnderElevation: 0,
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
                  final selected = selectedArticle.value;
                  if (selected == null) {
                    return MacSplitDetailEmptyPlaceholder(
                      topInset:
                          MediaQuery.paddingOf(context).top + kToolbarHeight,
                      focusNode: _emptyDetailFocusNode,
                    );
                  }
                  return ArticlePageView(
                    key: ValueKey(selected.entryId),
                    article: selected,
                    isSplitView: true,
                    isActive: () => _isActiveMacRecentRead,
                    isSelectedArticle: (entryId) =>
                        selectedArticle.value?.entryId == entryId,
                    onClose: _clearSelectionAndFocusEmptyDetail,
                    onPrevious: () => _selectRelativeArticle(-1),
                    onNext: () => _selectRelativeArticle(1),
                    onOpenOriginalAndMarkRead: () {
                      final current = selectedArticle.value;
                      if (current != null) _openOriginalAndMarkRead(current);
                    },
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

  Widget _buildListView(BuildContext context) {
    return Obx(() {
      return controller.articles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无阅读记录',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: 0,
                bottom: 8 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: controller.articles.length,
              itemBuilder: (context, index) {
                final article = controller.articles[index];
                return Obx(() {
                  final selectedId = selectedArticle.value?.entryId;
                  return ArticleCard(
                    key: _itemKeys.putIfAbsent(
                      article.entryId,
                      () => GlobalKey(),
                    ),
                    article: article,
                    isSelected:
                        Platform.isMacOS && selectedId == article.entryId,
                    stableTitleWeight: true,
                    onTap: () {
                      if (Platform.isMacOS) {
                        _handleMacArticleTap(article);
                      } else {
                        // 只记录最近阅读；本次会话不重排列表，固定当前可见
                        // 顺序与选中文章，避免列表跳到顶部。
                        LocalArticleDbService.recordReadHistory(
                          article.entryId,
                        );
                        final sequence = controller.articles.toList();
                        // PageView 索引按 entryId 重新查找，禁止使用可能
                        // 已过期的旧下标。
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
                      }
                    },
                  );
                });
              },
            );
    });
  }
}
