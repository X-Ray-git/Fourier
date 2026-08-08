import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/article_relation_service.dart';
import '../../../services/article_relation_worker.dart';
import '../../../services/auto_filter_worker.dart';

enum FilterReviewPipelineLayout { row, column }

/// Shared status presentation for the two pipelines feeding garbage review.
class FilterReviewPipelineStatus extends StatelessWidget {
  const FilterReviewPipelineStatus({
    super.key,
    this.layout = FilterReviewPipelineLayout.row,
    this.fontSize = 10,
  });

  final FilterReviewPipelineLayout layout;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      ArticleRelationService.recordsVersion.value;
      final qualityPending =
          AutoFilterWorker.queuedCount.value +
          AutoFilterWorker.processingCount.value;
      final relationPending = ArticleRelationService.pendingCount;
      final relationRunning = ArticleRelationWorker.processingCount.value > 0;

      final items = <Widget>[
        _PipelineStatusItem(
          label: '质量过滤',
          detail: qualityPending > 0 ? '$qualityPending' : '完成',
          active: qualityPending > 0,
          fontSize: fontSize,
        ),
        _PipelineStatusItem(
          label: '关系建立',
          detail: relationRunning
              ? '处理中'
              : relationPending > 0
              ? '$relationPending/${ArticleRelationService.batchSize}'
              : '完成',
          active: relationRunning,
          fontSize: fontSize,
        ),
      ];

      return switch (layout) {
        FilterReviewPipelineLayout.row => Row(
          mainAxisSize: MainAxisSize.min,
          children: [items.first, const SizedBox(width: 10), items.last],
        ),
        FilterReviewPipelineLayout.column => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [items.first, const SizedBox(height: 2), items.last],
        ),
      };
    });
  }
}

class _PipelineStatusItem extends StatelessWidget {
  const _PipelineStatusItem({
    required this.label,
    required this.detail,
    required this.active,
    required this.fontSize,
  });

  final String label;
  final String detail;
  final bool active;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active
        ? cs.primary
        : cs.onSurfaceVariant.withValues(alpha: 0.72);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 9,
          child: active
              ? CircularProgressIndicator(strokeWidth: 1.5, color: color)
              : Icon(Icons.circle, size: 5, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $detail',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.1,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
