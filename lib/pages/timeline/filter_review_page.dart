import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../utils/storage.dart';
import '../article/article_page.dart';
import '../timeline/timeline_controller.dart';
import '../widgets/article_card.dart';

class FilterReviewPage extends StatefulWidget {
  const FilterReviewPage({super.key});

  @override
  State<FilterReviewPage> createState() => _FilterReviewPageState();
}

class _FilterReviewPageState extends State<FilterReviewPage> {
  final _articles = <ArticleModel>[].obs;
  final _selectedArticle = Rxn<ArticleModel>();
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    _loadArticles();
    AutoFilterWorker.onRejected = (entryId, title, reason) {
      if (!mounted) return;
      if (_seenIds.contains(entryId)) return;
      _seenIds.add(entryId);
      final raw = GStorage.articleDb.get(entryId);
      if (raw is Map) {
        final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
        if (article.isRejectedByAi && !article.isRead) {
          _articles.add(article);
        }
      }
    };
  }

  @override
  void deactivate() {
    AutoFilterWorker.onRejected = null;
    super.deactivate();
  }

  @override
  void dispose() {
    AutoFilterWorker.onRejected = null;
    super.dispose();
  }

  void _loadArticles() {
    final all = LocalArticleDbService.readAllArticles()
        .where((a) => a.isRejectedByAi && !a.isRead)
        .toList();
    for (final a in all) {
      _seenIds.add(a.entryId);
    }
    _articles.value = all;
  }

  void _keep(ArticleModel article) {
    ArticleStateNotifier.tick(article.entryId);
    AutoFilterWorker.unReject(article.entryId);
    // 清除遗留的 readStatus 覆盖（不应写入 false，用户只是保留文章，不是标未读）
    GStorage.readStatus.delete(article.entryId);
    // 更新 TimelineController 内存状态，使文章立即可见（清除 AI 拦截标记）
    if (Get.isRegistered<TimelineController>()) {
      final tc = Get.find<TimelineController>();
      final idx = tc.allArticles.indexWhere(
        (a) => a.entryId == article.entryId,
      );
      if (idx >= 0) {
        final raw = GStorage.articleDb.get(article.entryId);
        if (raw is Map) {
          tc.allArticles[idx] = ArticleModel.fromCache(
            Map<String, dynamic>.from(raw),
          );
          tc.allArticles.refresh();
        }
      }
    }
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
    if (_selectedArticle.value?.entryId == article.entryId) {
      _selectedArticle.value = null;
    }
  }

  void _reject(ArticleModel article) {
    LocalArticleDbService.upsertOne(
      ArticleModel(
        entryId: article.entryId,
        feedId: article.feedId,
        feedTitle: article.feedTitle,
        feedImage: article.feedImage,
        title: article.title,
        url: article.url,
        content: article.content,
        publishedAt: article.publishedAt,
        isRead: article.isRead,
        category: article.category,
        subscriptionCategory: article.subscriptionCategory,
        author: article.author,
        imageUrl: article.imageUrl,
        isRejectedByAi: article.isRejectedByAi,
        filterReason: article.filterReason,
        filterReviewed: true,
      ),
    );
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(article.entryId, true);
    }
    ReadSyncService.enqueue(
      article.entryId,
      isInbox: article.category == 'inbox',
    );
    ArticleStateNotifier.tick(article.entryId);
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
    if (_selectedArticle.value?.entryId == article.entryId) {
      _selectedArticle.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (Platform.isMacOS) {
      return _buildMacOSLayout(context, cs);
    }

    return _buildMobileScaffold(context, cs);
  }

  Widget _buildMobileScaffold(BuildContext context, ColorScheme cs) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5),
        ),
        title: Obx(() {
          final humanCount = _articles.length;
          final q = AutoFilterWorker.queuedCount.value;
          final p = AutoFilterWorker.processingCount.value;
          final llmActive = q > 0 || p > 0;
          final llmCount = q + p;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '垃圾拦截',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (humanCount == 0 && !llmActive) ...[
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '全部处理完毕',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ] else ...[
                      if (humanCount > 0) ...[
                        Icon(Icons.touch_app, size: 12, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          '$humanCount 篇待处理',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.primary,
                          ),
                        ),
                      ],
                      if (humanCount > 0 && llmActive)
                        Text(
                          '  ·  ',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (llmActive) ...[
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$llmCount 篇判定中',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          );
        }),
      ),
      body: Obx(() {
        final q = AutoFilterWorker.queuedCount.value;
        final p = AutoFilterWorker.processingCount.value;
        final llmActive = q > 0 || p > 0;

        return Column(
          children: [
            Expanded(
              child: _articles.isEmpty
                  ? _buildEmptyState(cs, llmActive: llmActive, llmCount: q + p)
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        top: 6,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return Dismissible(
                          key: ValueKey(article.entryId),
                          direction: DismissDirection.horizontal,
                          dismissThresholds: const {
                            DismissDirection.startToEnd: 0.35,
                            DismissDirection.endToStart: 0.35,
                          },
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              _keep(article);
                            } else {
                              _reject(article);
                            }
                            return false;
                          },
                          background: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: const Color(0xFF10B981),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 24),
                                child: const Icon(
                                  Icons.restore_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                          secondaryBackground: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: cs.error,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                child: const Icon(
                                  Icons.delete_sweep_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                          child: Obx(
                            () => ArticleCard(
                              article: article,
                              isSelected:
                                  Platform.isMacOS &&
                                  _selectedArticle.value?.entryId ==
                                      article.entryId,
                              showFeedTitle: true,
                              showSummary: true,
                              onTap: () {
                                if (Platform.isMacOS) {
                                  _selectedArticle.value = article;
                                } else {
                                  Get.toNamed(
                                    Routes.article,
                                    arguments: {
                                      'article': article,
                                      'sequence': _articles,
                                      'index': index,
                                    },
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMacOSLayout(BuildContext context, ColorScheme cs) {
    return ColoredBox(
      color: cs.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 392,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MacReviewHeader(articles: _articles, colorScheme: cs),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                Expanded(
                  child: Obx(() {
                    final q = AutoFilterWorker.queuedCount.value;
                    final p = AutoFilterWorker.processingCount.value;
                    final llmActive = q > 0 || p > 0;

                    if (_articles.isEmpty) {
                      return _buildEmptyState(
                        cs,
                        llmActive: llmActive,
                        llmCount: q + p,
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
                      itemCount: _articles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return Obx(() {
                          final selected =
                              _selectedArticle.value?.entryId ==
                              article.entryId;
                          return _MacReviewRow(
                            article: article,
                            selected: selected,
                            onTap: () => _selectedArticle.value = article,
                            onKeep: () => _keep(article),
                            onReject: () => _reject(article),
                          );
                        });
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: Obx(() {
              final selected = _selectedArticle.value;
              if (selected == null) {
                return Center(
                  child: Text(
                    '未选择文章',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                );
              }
              return ArticlePageView(
                key: ValueKey(selected.entryId),
                article: selected,
                isSplitView: true,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    ColorScheme cs, {
    required bool llmActive,
    required int llmCount,
  }) {
    final bool allDone = !llmActive;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: allDone
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                allDone ? Icons.check_circle_outline : Icons.shield_outlined,
                size: 56,
                color: allDone ? const Color(0xFF10B981) : cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              allDone ? '处理完毕' : '暂无待处理内容',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (llmActive)
              _LlmPill(cs: cs, count: llmCount)
            else
              Text(
                allDone ? '所有文章已审核，阅读流保持清爽' : 'AI 过滤系统正在默默守护你的阅读流',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _MacReviewHeader extends StatelessWidget {
  final RxList<ArticleModel> articles;
  final ColorScheme colorScheme;

  const _MacReviewHeader({required this.articles, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 14, 7),
        child: Obx(() {
          final humanCount = articles.length;
          final q = AutoFilterWorker.queuedCount.value;
          final p = AutoFilterWorker.processingCount.value;
          final llmActive = q > 0 || p > 0;
          final llmCount = q + p;

          return Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '垃圾拦截',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      llmActive
                          ? '$humanCount 篇待处理 · $llmCount 篇判定中'
                          : humanCount == 0
                          ? '全部处理完毕'
                          : '$humanCount 篇待处理',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (llmActive)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _MacReviewRow extends StatelessWidget {
  final ArticleModel article;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onKeep;
  final VoidCallback onReject;

  const _MacReviewRow({
    required this.article,
    required this.selected,
    required this.onTap,
    required this.onKeep,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final feedTitle = article.feedTitle == '?' ? '未知来源' : article.feedTitle;
    final reason = article.filterReason?.trim();

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.58)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      feedTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (reason != null && reason.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  _SideTooltip(
                    message: '保留',
                    child: IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: const Color(0xFF10B981),
                      onPressed: onKeep,
                    ),
                  ),
                  _SideTooltip(
                    message: '移除',
                    child: IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: cs.error,
                      onPressed: onReject,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const _SideTooltip({required this.message, required this.child});

  @override
  State<_SideTooltip> createState() => _SideTooltipState();
}

class _SideTooltipState extends State<_SideTooltip> {
  OverlayEntry? _entry;

  void _show() {
    if (_entry != null) return;

    final target = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (target is! RenderBox || overlay is! RenderBox) return;

    final targetOffset = target.localToGlobal(Offset.zero, ancestor: overlay);
    final targetSize = target.size;
    final top = (targetOffset.dy + targetSize.height / 2 - 16).clamp(
      8.0,
      overlay.size.height - 40.0,
    );
    final rightSide = targetOffset.dx + targetSize.width + 8;
    final left = rightSide + 72 < overlay.size.width
        ? rightSide
        : targetOffset.dx - 72;

    _entry = OverlayEntry(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.inverseSurface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _hide(),
      child: widget.child,
    );
  }
}

// ── 状态药片行 ──────────
class _LlmPill extends StatelessWidget {
  final ColorScheme cs;
  final int count;

  const _LlmPill({required this.cs, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count 篇判定中',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
