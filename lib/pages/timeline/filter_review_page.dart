import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../services/summary_service.dart';
import '../../services/undo_service.dart';
import '../../utils/storage.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../timeline/timeline_controller.dart';
import '../widgets/article_card.dart';
import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/implicitly_animated_list.dart';
import '../../common/widgets/card_press_effect.dart';
import '../../common/widgets/app_glass_sync_button.dart';
import '../../utils/scroll_utils.dart';
import '../widgets/article_actions_menu.dart';

class FilterReviewPage extends StatefulWidget {
  const FilterReviewPage({super.key});

  @override
  State<FilterReviewPage> createState() => _FilterReviewPageState();
}

class _FilterReviewPageState extends State<FilterReviewPage> {
  final _articles = <ArticleModel>[].obs;
  final _selectedArticle = Rxn<ArticleModel>();
  final Set<String> _seenIds = {};
  final Map<String, GlobalKey> _itemKeys = {};
  final Map<String, GlobalKey> _removingItemKeys = {};
  Worker? _articleStateWorker;
  Worker? _filterCountWorker;
  Worker? _undoRestoreWorker;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _loadArticles();
    _articleStateWorker = ever(ArticleStateNotifier.version, (_) {
      final entryId = ArticleStateNotifier.lastEntryId;
      if (entryId != null) {
        _syncArticleFromDb(entryId);
      } else {
        _loadArticles();
      }
    });
    if (Get.isRegistered<TimelineController>()) {
      _filterCountWorker = ever(
        Get.find<TimelineController>().filterCount,
        (_) => _loadArticles(),
      );
    }
    _undoRestoreWorker = ever(
      UndoService.restoredAction,
      _handleUndoRestoreEvent,
    );
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
    _articleStateWorker?.dispose();
    _filterCountWorker?.dispose();
    _undoRestoreWorker?.dispose();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    super.dispose();
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) return false;
    if (event is! KeyDownEvent) return false;

    if (Platform.isMacOS) {
      if (event.logicalKey == LogicalKeyboardKey.keyK) {
        final selected = _selectedArticle.value;
        if (selected != null) {
          _keep(selected);
          return true;
        }
      }
    }
    return false;
  }

  void _loadArticles() {
    final all = LocalArticleDbService.readAllArticles()
        .where((a) => a.isRejectedByAi && !a.isRead)
        .toList();
    all.sort((a, b) {
      final tA = a.filteredAt ?? 0;
      final tB = b.filteredAt ?? 0;
      return tA.compareTo(tB);
    });
    for (final a in all) {
      _seenIds.add(a.entryId);
    }
    _articles.value = all;
    _pruneInvalidSelection();
  }

  Future<void> _syncReviewArticles() async {
    if (Get.isRegistered<TimelineController>()) {
      await Get.find<TimelineController>().loadFeedsThenArticles();
    }
    _loadArticles();
  }

  void _syncArticleFromDb(String entryId) {
    final raw = GStorage.articleDb.get(entryId);
    final index = _articles.indexWhere((a) => a.entryId == entryId);

    if (raw is! Map) {
      if (index >= 0) {
        _articles.removeAt(index);
      }
      _pruneInvalidSelection();
      return;
    }

    final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
    final shouldShow = article.isRejectedByAi && !article.isRead;
    if (!shouldShow) {
      if (index >= 0) {
        _articles.removeAt(index);
      }
      _pruneInvalidSelection();
      return;
    }

    _seenIds.add(entryId);
    if (index >= 0) {
      _articles[index] = article;
    } else {
      _articles.add(article);
    }
    if (_selectedArticle.value?.entryId == entryId) {
      _selectedArticle.value = article;
    }
  }

  void _pruneInvalidSelection() {
    final selected = _selectedArticle.value;
    if (selected == null) return;
    if (_articles.any((a) => a.entryId == selected.entryId)) return;
    _selectedArticle.value = _articles.isEmpty ? null : _articles.first;
  }

  ArticleModel? _nextArticleAfterRemoving(String entryId) {
    final index = _articles.indexWhere((a) => a.entryId == entryId);
    if (index < 0 || _articles.length <= 1) return null;

    final nextIndex = index < _articles.length - 1 ? index + 1 : index - 1;
    return _articles[nextIndex];
  }

  void _removeReviewedArticle(String entryId) {
    _articles.removeWhere((a) => a.entryId == entryId);
  }

  void _selectReviewedSuccessor(ArticleModel? nextArticle) {
    if (nextArticle == null) {
      _selectedArticle.value = null;
      return;
    }

    ArticleModel selected = nextArticle;
    for (final article in _articles) {
      if (article.entryId == nextArticle.entryId) {
        selected = article;
        break;
      }
    }

    _selectedArticle.value = selected;
    _scrollToArticle(selected.entryId);
  }

  void _selectRelativeArticle(int delta) {
    if (_articles.isEmpty) return;

    final selected = _selectedArticle.value;
    final currentIndex = selected == null
        ? -1
        : _articles.indexWhere((a) => a.entryId == selected.entryId);
    final nextIndex = (currentIndex + delta).clamp(0, _articles.length - 1);
    if (nextIndex < 0 || nextIndex >= _articles.length) return;
    _selectedArticle.value = _articles[nextIndex];
    _scrollToArticle(_articles[nextIndex].entryId);
  }

  void _scrollToArticle(String entryId) {
    _scrollToArticleWhenReady(entryId);
  }

  void _scrollToArticleWhenReady(String entryId, {int attempt = 0}) {
    if (!mounted) return;

    if (attempt == 0) {
      Future.delayed(const Duration(milliseconds: 220), () {
        _scrollToArticleWhenReady(entryId, attempt: 1);
      });
      return;
    }

    final key = _itemKeys[entryId];
    if (key != null && key.currentContext != null) {
      ScrollUtils.ensureVisible(key.currentContext!);
      return;
    }
    if (attempt >= 4) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToArticleWhenReady(entryId, attempt: attempt + 1);
    });
  }

  bool get _isActiveMacReviewPage {
    if (!Platform.isMacOS) return false;
    if (!Get.isRegistered<MainController>()) return true;
    return Get.find<MainController>().currentIndex.value == 1;
  }

  void _handleUndoRestoreEvent(UndoRestoreEvent? event) {
    if (!mounted || event == null || !_isActiveMacReviewPage) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActiveMacReviewPage) return;

      var index = _articles.indexWhere(
        (a) => a.entryId == event.article.entryId,
      );
      if (index < 0) {
        _loadArticles();
        index = _articles.indexWhere((a) => a.entryId == event.article.entryId);
      }
      if (index < 0) return;

      final article = _articles[index];
      _selectedArticle.value = article;
      _scrollToArticle(article.entryId);
    });
  }

  void _keep(ArticleModel article) {
    final bool shouldAdvance =
        _selectedArticle.value?.entryId == article.entryId;
    final ArticleModel? nextArticle = shouldAdvance
        ? _nextArticleAfterRemoving(article.entryId)
        : null;

    UndoService.recordFilterAction(article, UndoActionType.filterKeep);
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

    _removeReviewedArticle(article.entryId);
    if (shouldAdvance) {
      _selectReviewedSuccessor(nextArticle);
    }
  }

  void _reject(ArticleModel article) {
    final bool shouldAdvance =
        _selectedArticle.value?.entryId == article.entryId;
    final ArticleModel? nextArticle = shouldAdvance
        ? _nextArticleAfterRemoving(article.entryId)
        : null;

    UndoService.recordFilterAction(article, UndoActionType.filterReject);
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
        filteredAt: article.filteredAt,
      ),
    );
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(
        article.entryId,
        true,
        recordHistory: true,
      );
    }
    ReadSyncService.enqueue(
      article.entryId,
      isInbox: article.category == 'inbox',
    );
    unawaited(ReadSyncService.syncPendingReads());
    ArticleStateNotifier.tick(article.entryId);

    _removeReviewedArticle(article.entryId);
    if (shouldAdvance) {
      _selectReviewedSuccessor(nextArticle);
    }
  }

  void _handleReviewRemoveStart(ArticleModel article) {
    final key = _itemKeys.remove(article.entryId);
    if (key != null) {
      _removingItemKeys[article.entryId] = key;
    }
  }

  void _handleReviewRemoveEnd(ArticleModel article) {
    _removingItemKeys.remove(article.entryId);
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
                          child: Obx(() {
                            final selectedId = _selectedArticle.value?.entryId;
                            return ArticleCard(
                              article: article,
                              isSelected:
                                  Platform.isMacOS &&
                                  selectedId == article.entryId,
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
                            );
                          }),
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
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MacReviewHeader(
                  articles: _articles,
                  colorScheme: cs,
                  onSync: _syncReviewArticles,
                ),
                Expanded(
                  child: Obx(() {
                    final q = AutoFilterWorker.queuedCount.value;
                    final p = AutoFilterWorker.processingCount.value;
                    final llmActive = q > 0 || p > 0;

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ImplicitlyAnimatedList<ArticleModel>(
                            items: _articles.toList(),
                            itemKey: (article) => article.entryId,
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: _buildAnimatedReviewRow,
                            removedItemBuilder: _buildRemovedReviewRow,
                            onRemoveStart: _handleReviewRemoveStart,
                            onRemoveEnd: _handleReviewRemoveEnd,
                          ),
                        ),
                        if (_articles.isEmpty)
                          Positioned.fill(
                            child: DelayedVisibility(
                              visible: _articles.isEmpty,
                              delay: const Duration(milliseconds: 220),
                              child: _buildEmptyState(
                                cs,
                                llmActive: llmActive,
                                llmCount: q + p,
                              ),
                            ),
                          ),
                      ],
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
                return const MacEmptyPlaceholder();
              }
              return ArticlePageView(
                key: ValueKey(selected.entryId),
                article: selected,
                isSplitView: true,
                isActive: () =>
                    !Get.isRegistered<MainController>() ||
                    Get.find<MainController>().currentIndex.value == 1,
                isSelectedArticle: (entryId) =>
                    _selectedArticle.value?.entryId == entryId,
                onClose: () => _selectedArticle.value = null,
                onPrevious: () => _selectRelativeArticle(-1),
                onNext: () => _selectRelativeArticle(1),
                onMKeyPressed: () {
                  final currentSelected = _selectedArticle.value;
                  if (currentSelected != null) {
                    _reject(currentSelected);
                  }
                },
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allDone ? Icons.check_circle_outline : Icons.shield_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.15),
          ),
          if (llmActive) ...[
            const SizedBox(height: 16),
            _LlmPill(cs: cs, count: llmCount),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedReviewRow(
    BuildContext context,
    ArticleModel article,
    int index,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 1,
      child: FadeTransition(
        opacity: animation,
        child: Obx(() {
          final selected = _selectedArticle.value?.entryId == article.entryId;
          return _MacReviewRow(
            key: _itemKeys.putIfAbsent(article.entryId, () => GlobalKey()),
            article: article,
            selected: selected,
            onTap: () => _selectedArticle.value = article,
            onKeep: () {
              _selectedArticle.value = article;
              _keep(article);
            },
            onReject: () {
              _selectedArticle.value = article;
              _reject(article);
            },
          );
        }),
      ),
    );
  }

  Widget _buildRemovedReviewRow(
    BuildContext context,
    ArticleModel article,
    int index,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: _MacReviewRow(
          key:
              _removingItemKeys[article.entryId] ??
              _itemKeys[article.entryId] ??
              ValueKey('removed-${article.entryId}'),
          article: article,
          selected: false,
          onTap: () {},
          onKeep: () {},
          onReject: () {},
        ),
      ),
    );
  }
}

class _MacReviewHeader extends StatelessWidget {
  final RxList<ArticleModel> articles;
  final ColorScheme colorScheme;
  final VoidCallback onSync;

  const _MacReviewHeader({
    required this.articles,
    required this.colorScheme,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: Obx(() {
              final humanCount = articles.length;
              final q = AutoFilterWorker.queuedCount.value;
              final p = AutoFilterWorker.processingCount.value;
              final llmActive = q > 0 || p > 0;
              final llmCount = q + p;
              final timelineController = Get.isRegistered<TimelineController>()
                  ? Get.find<TimelineController>()
                  : null;
              final syncing = timelineController?.isSyncing.value ?? false;

              return Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 17,
                    color: colorScheme.onSurfaceVariant,
                  ),
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
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          llmActive
                              ? '$humanCount 篇待处理 · $llmCount 篇判定中'
                              : humanCount == 0
                              ? '全部处理完毕'
                              : '$humanCount 篇待处理',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
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
                  const SizedBox(width: 10),
                  AppGlassSyncButton(
                    syncing: syncing,
                    onPressed: onSync,
                    idleColor: colorScheme.onSurfaceVariant,
                    syncingColor: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
              );
            }),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              child: const SizedBox(height: 1),
            ),
          ),
        ],
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
    super.key,
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

    return CardPressEffect(
      onTap: onTap,
      onSecondaryTapDown: Platform.isMacOS
          ? (details) {
              ArticleActionsMenu.showMacOSContextMenu(
                context,
                position: details.globalPosition,
                article: article,
              );
            }
          : null,
      enableHover: true,
      enablePress: true,
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected
              ? BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
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
                        fontWeight: FontWeight.w600,
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
                    Obx(() {
                      final summaryRecord = SummaryService.recordOf(
                        article.entryId,
                      );
                      final summaryStatus =
                          summaryRecord?.status ?? SummaryStatus.idle;
                      final summaryText = _summaryTextFor(summaryRecord);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (reason != null && reason.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            _ReviewInfoBlock(
                              icon: Icons.auto_awesome,
                              label: '拒绝理由',
                              text: reason,
                              color: const Color(0xFFD97706),
                              maxLines: 2,
                            ),
                          ],
                          if (summaryText.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            _ReviewInfoBlock(
                              icon: _summaryIconFor(summaryStatus),
                              label: '摘要',
                              text: summaryText,
                              color: _summaryColorFor(cs, summaryStatus),
                              maxLines: summaryStatus == SummaryStatus.done
                                  ? 3
                                  : 1,
                            ),
                          ],
                        ],
                      );
                    }),
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

  String _summaryTextFor(SummaryRecord? record) {
    final status = record?.status ?? SummaryStatus.idle;
    final text = record?.summaryText?.trim();
    if (status == SummaryStatus.done && text != null && text.isNotEmpty) {
      return text;
    }
    if (status == SummaryStatus.pending) return '摘要生成中...';
    if (status == SummaryStatus.error) {
      final message = record?.errorMessage?.trim();
      if (message != null && message.isNotEmpty) return '摘要生成失败：$message';
      return '摘要生成失败';
    }
    return '排队等待摘要...';
  }

  IconData _summaryIconFor(SummaryStatus status) {
    return switch (status) {
      SummaryStatus.done => Icons.format_quote_rounded,
      SummaryStatus.pending => Icons.sync_rounded,
      SummaryStatus.error => Icons.error_outline_rounded,
      SummaryStatus.idle => Icons.hourglass_empty_rounded,
    };
  }

  Color _summaryColorFor(ColorScheme cs, SummaryStatus status) {
    return switch (status) {
      SummaryStatus.done => const Color(0xFF0F766E),
      SummaryStatus.pending => cs.primary,
      SummaryStatus.error => cs.error,
      SummaryStatus.idle => cs.onSurfaceVariant,
    };
  }
}

class _ReviewInfoBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;
  final int maxLines;

  const _ReviewInfoBlock({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.16), width: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ],
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
