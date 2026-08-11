import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../common/widgets/app_glass.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../common/widgets/macos_window_drag_area.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/auto_summary_worker.dart';
import '../../services/auto_translation_worker.dart';
import '../../services/article_relation_service.dart';
import '../../services/article_relation_worker.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../services/summary_service.dart';
import '../../services/translation_service.dart';
import '../main/main_controller.dart';
import 'widgets/mobile_settings_chrome.dart';

class TaskCenterPage extends StatefulWidget {
  final bool embedded;

  const TaskCenterPage({super.key, this.embedded = false});

  @override
  State<TaskCenterPage> createState() => _TaskCenterPageState();
}

enum _AiTaskType { translation, summary }

class _TaskCenterPageState extends State<TaskCenterPage> {
  Timer? _refreshTimer;
  bool _syncingReads = false;
  final _macScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _macScrollController.dispose();
    super.dispose();
  }

  Future<void> _syncPendingReads() async {
    if (_syncingReads) return;
    setState(() => _syncingReads = true);
    try {
      await ReadSyncService.syncPendingReads();
      if (!mounted) return;
      AppFeedback.success('已读同步完成', '待同步队列已处理');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('已读同步失败', e.toString());
    } finally {
      if (mounted) setState(() => _syncingReads = false);
    }
  }

  void _openFilterReview() {
    if (Get.isRegistered<MainController>()) {
      final shouldCloseCurrentSurface = Platform.isMacOS
          ? widget.embedded
          : true;
      if (shouldCloseCurrentSurface) Get.back();
      Future<void>.delayed(
        Duration(milliseconds: shouldCloseCurrentSurface ? 120 : 0),
        () {
          Get.find<MainController>().changeIndex(1);
        },
      );
      return;
    }
    Get.toNamed(Routes.filterReview);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final articles = LocalArticleDbService.readAllArticles();
    final pendingReads = ReadSyncService.pendingReadItems.length;
    final rejected = articles
        .where((a) => a.isRejectedByAi && !a.isRead)
        .length;

    if (Platform.isMacOS) {
      final content = _buildMacOSContent(
        context,
        articles: articles,
        rejected: rejected,
        pendingReads: pendingReads,
      );
      if (widget.embedded) return content;
      return Scaffold(
        backgroundColor: cs.surface.withValues(alpha: 0.74),
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: content,
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const MobileBlurAppBar(
        title: Text(
          '后台任务与同步',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          MediaQuery.paddingOf(context).top + mobileAppBarToolbarHeight + 16,
          12,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          _OverviewCard(articles: articles, rejectedCount: rejected),
          const SizedBox(height: 20),
          const MobileSettingsSectionHeader(
            icon: Icons.sync_rounded,
            title: '同步',
            subtitle: '查看已读同步队列和本地文章库',
          ),
          _SyncCard(
            pendingReads: pendingReads,
            lastSyncAt: ReadSyncService.lastReadSyncAt,
            syncing: _syncingReads,
            onSync: _syncPendingReads,
          ),
          const SizedBox(height: 20),
          const MobileSettingsSectionHeader(
            icon: Icons.auto_awesome_rounded,
            title: 'AI 任务',
            subtitle: '后台翻译、摘要和过滤的当前状态',
          ),
          Obx(() {
            final filterQueued = AutoFilterWorker.queuedCount.value;
            final filterProcessing = AutoFilterWorker.processingCount.value;
            return _TaskStatusCard(
              icon: Icons.auto_awesome,
              title: 'AI 过滤',
              subtitle: rejected > 0 ? '$rejected 篇待人工审核' : '暂无待审核文章',
              queued: filterQueued,
              processing: filterProcessing,
              failed: 0,
              actionLabel: rejected > 0 ? '去审核' : '暂无待审核',
              onAction: rejected > 0 ? _openFilterReview : null,
            );
          }),
          const SizedBox(height: 8),
          _TaskStatusCard(
            icon: Icons.translate,
            title: '自动翻译',
            subtitle: '按订阅源开关自动处理',
            queued: AutoTranslationWorker.queueSize,
            processing: AutoTranslationWorker.processingCount.value,
            failed: TranslationService.countByStatus(TranslationStatus.error),
            failureHint: '失败文章不会显示半截译文。点“查看失败”可按文章排查并单篇重试。',
            actionLabel:
                TranslationService.countByStatus(TranslationStatus.error) > 0
                ? '查看失败'
                : null,
            onAction:
                TranslationService.countByStatus(TranslationStatus.error) > 0
                ? () => Get.to(
                    () =>
                        const _AiFailureListPage(type: _AiTaskType.translation),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _TaskStatusCard(
            icon: Icons.summarize,
            title: '自动摘要',
            subtitle: '所有有正文的文章都会自动摘要',
            queued: AutoSummaryWorker.queueSize,
            processing: AutoSummaryWorker.processingCount.value,
            failed: SummaryService.countByStatus(SummaryStatus.error),
            failureHint: '失败文章不会影响阅读。点“查看失败”可按文章排查并单篇重试。',
            actionLabel: SummaryService.countByStatus(SummaryStatus.error) > 0
                ? '查看失败'
                : null,
            onAction: SummaryService.countByStatus(SummaryStatus.error) > 0
                ? () => Get.to(
                    () => const _AiFailureListPage(type: _AiTaskType.summary),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _buildRelationTaskCard(),
        ],
      ),
    );
  }

  Widget _buildMacOSContent(
    BuildContext context, {
    required List<ArticleModel> articles,
    required int rejected,
    required int pendingReads,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!widget.embedded) ...[
              AppGlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '返回',
                onPressed: Get.back,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: widget.embedded
                  ? _TaskCenterTitle(colorScheme: cs, embedded: true)
                  : MacOSWindowDragArea(
                      child: _TaskCenterTitle(colorScheme: cs, embedded: false),
                    ),
            ),
            if (widget.embedded) const SizedBox(width: 46),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: MacGlassScrollArea(
            controller: _macScrollController,
            child: ListView(
              controller: _macScrollController,
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              children: [
                _OverviewCard(articles: articles, rejectedCount: rejected),
                const SizedBox(height: 14),
                _MacTaskSectionHeader(title: '同步', subtitle: '已读同步队列和本地文章库'),
                const SizedBox(height: 8),
                _SyncCard(
                  pendingReads: pendingReads,
                  lastSyncAt: ReadSyncService.lastReadSyncAt,
                  syncing: _syncingReads,
                  onSync: _syncPendingReads,
                ),
                const SizedBox(height: 14),
                _MacTaskSectionHeader(
                  title: 'AI 任务',
                  subtitle: '后台翻译、摘要和过滤的当前状态',
                ),
                const SizedBox(height: 8),
                Obx(() {
                  final filterQueued = AutoFilterWorker.queuedCount.value;
                  final filterProcessing =
                      AutoFilterWorker.processingCount.value;
                  return _TaskStatusCard(
                    icon: Icons.auto_awesome,
                    title: 'AI 过滤',
                    subtitle: rejected > 0 ? '$rejected 篇待人工审核' : '暂无待审核文章',
                    queued: filterQueued,
                    processing: filterProcessing,
                    failed: 0,
                    actionLabel: rejected > 0 ? '去审核' : '暂无待审核',
                    onAction: rejected > 0 ? _openFilterReview : null,
                  );
                }),
                const SizedBox(height: 8),
                _TaskStatusCard(
                  icon: Icons.translate,
                  title: '自动翻译',
                  subtitle: '按订阅源开关自动处理',
                  queued: AutoTranslationWorker.queueSize,
                  processing: AutoTranslationWorker.processingCount.value,
                  failed: TranslationService.countByStatus(
                    TranslationStatus.error,
                  ),
                  failureHint: '失败文章不会显示半截译文。点“查看失败”可按文章排查并单篇重试。',
                  actionLabel:
                      TranslationService.countByStatus(
                            TranslationStatus.error,
                          ) >
                          0
                      ? '查看失败'
                      : null,
                  onAction:
                      TranslationService.countByStatus(
                            TranslationStatus.error,
                          ) >
                          0
                      ? () => Get.to(
                          () => const _AiFailureListPage(
                            type: _AiTaskType.translation,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                _TaskStatusCard(
                  icon: Icons.summarize,
                  title: '自动摘要',
                  subtitle: '所有有正文的文章都会自动摘要',
                  queued: AutoSummaryWorker.queueSize,
                  processing: AutoSummaryWorker.processingCount.value,
                  failed: SummaryService.countByStatus(SummaryStatus.error),
                  failureHint: '失败文章不会影响阅读。点“查看失败”可按文章排查并单篇重试。',
                  actionLabel:
                      SummaryService.countByStatus(SummaryStatus.error) > 0
                      ? '查看失败'
                      : null,
                  onAction:
                      SummaryService.countByStatus(SummaryStatus.error) > 0
                      ? () => Get.to(
                          () => const _AiFailureListPage(
                            type: _AiTaskType.summary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                _buildRelationTaskCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRelationTaskCard() {
    return Obx(() {
      // recordsVersion 让落盘后的 pending/history/group 变化触发刷新。
      ArticleRelationService.recordsVersion.value;
      final queued = ArticleRelationService.pendingCount;
      final running = ArticleRelationWorker.processingCount.value;
      final currentNew = ArticleRelationWorker.currentNewCount.value;
      final currentHistory = ArticleRelationWorker.currentHistoryCount.value;
      final completed = ArticleRelationWorker.completedThisSession.value;
      final failed = ArticleRelationWorker.failedThisSession.value;
      final error = ArticleRelationWorker.lastError.value;
      final runningLabel = running > 0
          ? '当前批次 $currentNew + $currentHistory'
          : '历史 ${ArticleRelationService.historyCount}/'
                '${ArticleRelationService.historyLimit}';
      return _TaskStatusCard(
        icon: Icons.hub_outlined,
        title: '关系建立',
        subtitle:
            '$runningLabel · 本次完成 $completed 批 · ${ArticleRelationService.groupCount} 组关系',
        queued: queued,
        processing: running,
        failed: failed,
        failureHint: error == null ? null : '最近失败：$error。待处理摘要仍保留，可安全重试。',
        actionLabel: error == null ? null : '重试',
        onAction: error == null ? null : ArticleRelationWorker.retryPending,
      );
    });
  }
}

class _TaskCenterTitle extends StatelessWidget {
  const _TaskCenterTitle({required this.colorScheme, required this.embedded});

  final ColorScheme colorScheme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '后台任务与同步',
          style: TextStyle(
            fontSize: embedded ? 22 : 28,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '查看已读同步、AI 过滤、翻译、摘要和关系建立任务状态。',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AiFailureListPage extends StatefulWidget {
  final _AiTaskType type;

  const _AiFailureListPage({required this.type});

  @override
  State<_AiFailureListPage> createState() => _AiFailureListPageState();
}

class _AiFailureListPageState extends State<_AiFailureListPage> {
  final Set<String> _retrying = {};
  final _macScrollController = ScrollController();

  bool get _isTranslation => widget.type == _AiTaskType.translation;

  @override
  void dispose() {
    _macScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failures = _failureItems();

    if (Platform.isMacOS) {
      return Scaffold(
        backgroundColor: cs.surface.withValues(alpha: 0.74),
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppGlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: '返回',
                      onPressed: Get.back,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MacOSWindowDragArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isTranslation ? '翻译失败文章' : '摘要失败文章',
                              style: TextStyle(
                                fontSize: 28,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '按文章排查失败原因，并支持单篇重试。',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: failures.isEmpty
                      ? _MacEmptyTaskState(colorScheme: cs)
                      : MacGlassScrollArea(
                          controller: _macScrollController,
                          child: ListView.separated(
                            controller: _macScrollController,
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom + 24,
                            ),
                            itemBuilder: (context, index) {
                              final item = failures[index];
                              final article = item.article;
                              final retrying =
                                  article != null &&
                                  _retrying.contains(article.entryId);
                              return _FailureArticleCard(
                                item: item,
                                type: widget.type,
                                retrying: retrying,
                                onRetry: retrying || article == null
                                    ? null
                                    : () => _retry(article),
                                onOpen: article == null
                                    ? null
                                    : () => _openArticle(article),
                              );
                            },
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemCount: failures.length,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: MobileBlurAppBar(
        title: Text(
          _isTranslation ? '翻译失败文章' : '摘要失败文章',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: failures.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '没有失败文章',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                12,
                MediaQuery.paddingOf(context).top +
                    mobileAppBarToolbarHeight +
                    16,
                12,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              itemBuilder: (context, index) {
                final item = failures[index];
                final article = item.article;
                final retrying =
                    article != null && _retrying.contains(article.entryId);
                return _FailureArticleCard(
                  item: item,
                  type: widget.type,
                  retrying: retrying,
                  onRetry: retrying || article == null
                      ? null
                      : () => _retry(article),
                  onOpen: article == null ? null : () => _openArticle(article),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemCount: failures.length,
            ),
    );
  }

  List<_AiFailureItem> _failureItems() {
    final articleById = {
      for (final article in LocalArticleDbService.readAllArticles())
        article.entryId: article,
    };
    final records = _isTranslation
        ? TranslationService.recordsByStatus(TranslationStatus.error).map(
            (entryId, record) => MapEntry(
              entryId,
              _AiFailureRecord(record.errorMessage, record.updatedAt),
            ),
          )
        : SummaryService.recordsByStatus(SummaryStatus.error).map(
            (entryId, record) => MapEntry(
              entryId,
              _AiFailureRecord(record.errorMessage, record.updatedAt),
            ),
          );

    final items = <_AiFailureItem>[];
    for (final entry in records.entries) {
      items.add(
        _AiFailureItem(
          entryId: entry.key,
          article: articleById[entry.key],
          record: entry.value,
        ),
      );
    }
    items.sort((a, b) => b.record.updatedAt.compareTo(a.record.updatedAt));
    return items;
  }

  Future<void> _retry(ArticleModel article) async {
    setState(() => _retrying.add(article.entryId));
    try {
      if (_isTranslation) {
        final record = await TranslationService.translateArticle(article);
        if (record.status == TranslationStatus.done) {
          AppFeedback.success('翻译完成', article.title);
        } else {
          AppFeedback.error('翻译失败', record.errorMessage ?? '请稍后再试');
        }
      } else {
        final record = await SummaryService.summarizeArticle(article);
        if (record.status == SummaryStatus.done) {
          AppFeedback.success('摘要完成', article.title);
        } else {
          AppFeedback.error('摘要失败', record.errorMessage ?? '请稍后再试');
        }
      }
    } catch (e) {
      AppFeedback.error(_isTranslation ? '翻译失败' : '摘要失败', e.toString());
    } finally {
      if (mounted) {
        setState(() => _retrying.remove(article.entryId));
      }
    }
  }

  void _openArticle(ArticleModel article) {
    Get.toNamed(Routes.article, arguments: article);
  }
}

class _AiFailureRecord {
  final String? errorMessage;
  final int updatedAt;

  const _AiFailureRecord(this.errorMessage, this.updatedAt);
}

class _AiFailureItem {
  final String entryId;
  final ArticleModel? article;
  final _AiFailureRecord record;

  const _AiFailureItem({
    required this.entryId,
    required this.article,
    required this.record,
  });
}

class _FailureArticleCard extends StatelessWidget {
  final _AiFailureItem item;
  final _AiTaskType type;
  final bool retrying;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;

  const _FailureArticleCard({
    required this.item,
    required this.type,
    required this.retrying,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final article = item.article;
    final canOpen = article != null;
    final retryBlockedReason = _retryBlockedReason(article);
    final canRetry = onRetry != null && retryBlockedReason == null;
    final error = item.record.errorMessage?.trim();

    return _TaskPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article?.title ?? '本地文章已清理',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              article?.feedTitle ?? item.entryId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error == null || error.isEmpty ? '未记录失败原因' : error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatTime(item.record.updatedAt),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                if (Platform.isMacOS)
                  AppGlassButton(
                    label: '打开',
                    onPressed: canOpen ? onOpen : null,
                  )
                else
                  TextButton(
                    onPressed: canOpen ? onOpen : null,
                    child: const Text('打开'),
                  ),
                const SizedBox(width: 6),
                if (Platform.isMacOS)
                  AppGlassButton(
                    label: retrying ? '重试中' : retryBlockedReason ?? '重试',
                    icon: type == _AiTaskType.translation
                        ? Icons.translate
                        : Icons.summarize,
                    onPressed: canRetry ? onRetry : null,
                    role: AppGlassButtonRole.primary,
                  )
                else
                  FilledButton.icon(
                    onPressed: canRetry ? onRetry : null,
                    icon: retrying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            type == _AiTaskType.translation
                                ? Icons.translate
                                : Icons.summarize,
                            size: 16,
                          ),
                    label: Text(retrying ? '重试中' : retryBlockedReason ?? '重试'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _retryBlockedReason(ArticleModel? article) {
    if (article == null) return '无法重试';
    return null;
  }
}

class _OverviewCard extends StatelessWidget {
  final List<ArticleModel> articles;
  final int rejectedCount;

  const _OverviewCard({required this.articles, required this.rejectedCount});

  @override
  Widget build(BuildContext context) {
    final unread = articles.where((a) => !a.isRead).length;
    final working =
        ReadSyncService.pendingReadItems.length +
        AutoFilterWorker.queuedCount.value +
        AutoFilterWorker.processingCount.value +
        AutoTranslationWorker.queueSize +
        AutoTranslationWorker.processingCount.value +
        AutoSummaryWorker.queueSize +
        AutoSummaryWorker.processingCount.value +
        ArticleRelationService.pendingCount +
        ArticleRelationWorker.processingCount.value;
    final cs = Theme.of(context).colorScheme;

    return _TaskPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  working > 0 ? Icons.sync : Icons.check_circle_outline,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  working > 0 ? '后台处理中' : '后台空闲',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(label: '本地文章', value: articles.length),
                ),
                Expanded(
                  child: _MetricTile(label: '未读', value: unread),
                ),
                Expanded(
                  child: _MetricTile(label: '待审核', value: rejectedCount),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  final int pendingReads;
  final int? lastSyncAt;
  final bool syncing;
  final VoidCallback onSync;

  const _SyncCard({
    required this.pendingReads,
    required this.lastSyncAt,
    required this.syncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TaskPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pendingReads > 0 ? '$pendingReads 篇已读待同步' : '已读同步队列为空',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '最近同步：${_formatTime(lastSyncAt)}',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Platform.isMacOS
                  ? AppGlassButton(
                      label: syncing ? '同步中' : '同步已读',
                      tooltip: syncing ? '同步中' : '同步已读',
                      icon: Icons.sync,
                      onPressed: syncing ? null : onSync,
                      role: AppGlassButtonRole.primary,
                    )
                  : FilledButton.icon(
                      onPressed: syncing ? null : onSync,
                      icon: syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(syncing ? '同步中' : '同步已读'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int queued;
  final int processing;
  final int failed;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? failureHint;

  const _TaskStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.queued,
    required this.processing,
    required this.failed,
    this.actionLabel,
    this.onAction,
    this.failureHint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = queued > 0 || processing > 0;
    final hasFailure = failed > 0 && failureHint != null;
    return _TaskPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: active ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  Platform.isMacOS
                      ? AppGlassButton(label: actionLabel!, onPressed: onAction)
                      : TextButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(label: '排队', value: queued),
                ),
                Expanded(
                  child: _MetricTile(label: '处理中', value: processing),
                ),
                Expanded(
                  child: _MetricTile(
                    label: '失败',
                    value: failed,
                    tone: failed > 0 ? _MetricTone.warning : _MetricTone.normal,
                  ),
                ),
              ],
            ),
            if (hasFailure) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.error.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        failureHint!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int value;
  final _MetricTone tone;

  const _MetricTile({
    required this.label,
    required this.value,
    this.tone = _MetricTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final valueColor = switch (tone) {
      _MetricTone.warning when value > 0 => cs.error,
      _ when value > 0 => cs.primary,
      _ => cs.onSurface,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

enum _MetricTone { normal, warning }

class _TaskPanel extends StatelessWidget {
  final Widget child;

  const _TaskPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return AppGlassSurface(
        borderRadius: AppGlassRadii.panel,
        padding: EdgeInsets.zero,
        tone: AppGlassTone.surface,
        nativeBackdrop: true,
        staticMaterial: true,
        child: child,
      );
    }

    return MobileSettingsPanel(child: child);
  }
}

class _MacEmptyTaskState extends StatelessWidget {
  final ColorScheme colorScheme;

  const _MacEmptyTaskState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppGlassSurface(
        borderRadius: AppGlassRadii.prominentPanel,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        tone: AppGlassTone.panel,
        nativeBackdrop: true,
        staticMaterial: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              '没有失败文章',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacTaskSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _MacTaskSectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(int? millis) {
  if (millis == null || millis <= 0) return '暂无记录';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return DateFormat('MM-dd HH:mm').format(dt);
}
