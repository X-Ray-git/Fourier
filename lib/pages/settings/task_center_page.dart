import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../common/widgets/feedback_toast.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/auto_summary_worker.dart';
import '../../services/auto_translation_worker.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../services/summary_service.dart';
import '../../services/translation_service.dart';

class TaskCenterPage extends StatefulWidget {
  const TaskCenterPage({super.key});

  @override
  State<TaskCenterPage> createState() => _TaskCenterPageState();
}

class _TaskCenterPageState extends State<TaskCenterPage> {
  Timer? _refreshTimer;
  bool _syncingReads = false;

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final articles = LocalArticleDbService.readAllArticles();
    final pendingReads = ReadSyncService.pendingReadItems.length;
    final rejected = articles
        .where((a) => a.isRejectedByAi && !a.isRead)
        .length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('后台任务与同步'),
        centerTitle: true,
        backgroundColor: cs.surface.withValues(alpha: 0.72),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          _OverviewCard(
            articles: articles,
            pendingReads: pendingReads,
            rejectedCount: rejected,
          ),
          const SizedBox(height: 12),
          _SectionTitle(title: '同步', subtitle: '查看已读同步队列和本地文章库'),
          const SizedBox(height: 8),
          _SyncCard(
            pendingReads: pendingReads,
            lastSyncAt: ReadSyncService.lastReadSyncAt,
            syncing: _syncingReads,
            onSync: _syncPendingReads,
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'AI 任务', subtitle: '后台翻译、摘要和过滤的当前状态'),
          const SizedBox(height: 8),
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
              actionLabel: rejected > 0 ? '去审核' : null,
              onAction: rejected > 0
                  ? () => Get.toNamed(Routes.filterReview)
                  : null,
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
          ),
          const SizedBox(height: 8),
          _TaskStatusCard(
            icon: Icons.summarize,
            title: '自动摘要',
            subtitle: '所有有正文的文章都会自动摘要',
            queued: AutoSummaryWorker.queueSize,
            processing: AutoSummaryWorker.processingCount.value,
            failed: SummaryService.countByStatus(SummaryStatus.error),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final List<ArticleModel> articles;
  final int pendingReads;
  final int rejectedCount;

  const _OverviewCard({
    required this.articles,
    required this.pendingReads,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final unread = articles.where((a) => !a.isRead).length;
    final working =
        pendingReads +
        AutoFilterWorker.queueSize +
        AutoTranslationWorker.queueSize +
        AutoSummaryWorker.queueSize;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  working > 0 ? Icons.sync : Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  working > 0 ? '后台处理中' : '后台空闲',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
    return Card(
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
              child: FilledButton.icon(
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

  const _TaskStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.queued,
    required this.processing,
    required this.failed,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = queued > 0 || processing > 0;
    return Card(
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
                if (actionLabel != null && onAction != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
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
                  child: _MetricTile(label: '失败', value: failed),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: value > 0 ? cs.primary : cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

String _formatTime(int? millis) {
  if (millis == null || millis <= 0) return '暂无记录';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return DateFormat('MM-dd HH:mm').format(dt);
}
