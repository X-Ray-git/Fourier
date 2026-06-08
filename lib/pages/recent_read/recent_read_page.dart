import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/local_article_db_service.dart';
import '../../services/undo_service.dart';
import '../../utils/security_utils.dart';
import '../../common/widgets/feedback_toast.dart';
import '../article/article_page.dart';
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

  // 用于记录 Mac 分栏模式下的双击等状态
  DateTime? _lastArticleTapAt;
  String? _lastArticleTapEntryId;
  final selectedArticle = Rxn<ArticleModel>();
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    controller = Get.put(RecentReadController());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectRelativeArticle(int delta) {
    final list = controller.articles;
    if (list.isEmpty) return;

    final selected = selectedArticle.value;
    final currentIndex = selected == null
        ? -1
        : list.indexWhere((a) => a.entryId == selected.entryId);
    final nextIndex = (currentIndex + delta).clamp(0, list.length - 1);
    if (nextIndex < 0 || nextIndex >= list.length) return;
    selectedArticle.value = list[nextIndex];
    _scrollToArticle(list[nextIndex].entryId);
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

    LocalArticleDbService.recordReadHistory(article.entryId);
    controller.refreshData();
    selectedArticle.value = article;
    _lastArticleTapEntryId = article.entryId;
    _lastArticleTapAt = now;

    if (isDoubleTap) {
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      _selectRelativeArticle(1);
      _openOriginalArticle(article);

      if (!article.isRead) {
        unawaited(UndoService.markAsRead(article, showSuccess: false));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text(
                      '最近阅读',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.5),
                    centerTitle: false,
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
                    return const MacEmptyPlaceholder();
                  }
                  return ArticlePageView(
                    key: ValueKey(selected.entryId),
                    article: selected,
                    isSplitView: true,
                    isSelectedArticle: (entryId) =>
                        selectedArticle.value?.entryId == entryId,
                    onClose: () => selectedArticle.value = null,
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

  Widget _buildListView(BuildContext context) {
    return Obx(() {
      return ScrollConfiguration(
        behavior: const NoOverscrollIndicatorBehavior(),
        child: controller.articles.isEmpty
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
                  top: Platform.isMacOS ? 0 : MediaQuery.paddingOf(context).top,
                  bottom:
                      8 +
                      (Platform.isMacOS ? 0 : kBottomNavigationBarHeight) +
                      MediaQuery.of(context).padding.bottom,
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
                      onTap: () {
                        if (Platform.isMacOS) {
                          _handleMacArticleTap(article);
                        } else {
                          LocalArticleDbService.recordReadHistory(
                            article.entryId,
                          );
                          controller.refreshData();
                          Get.toNamed(
                            Routes.article,
                            arguments: {
                              'article': article,
                              'sequence': controller.articles.toList(),
                              'index': index,
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
