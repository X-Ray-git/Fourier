import 'package:flutter/material.dart';

import '../../common/widgets/app_context_menu.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../models/article.dart';
import '../../services/summary_service.dart';
import '../../services/translation_service.dart';

abstract final class ArticleActionsMenu {
  static void showBottomSheet(
    BuildContext context, {
    required ArticleModel article,
    VoidCallback? onTranslateSuccess,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = _ArticleActionState.from(article);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: state.isTranslationPending
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.translate, color: colorScheme.primary),
                title: Text(
                  state.isTranslationPending
                      ? '翻译中...'
                      : (state.isTranslated ? '重新翻译' : '翻译文章'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                enabled: !state.isTranslationPending,
                onTap: state.isTranslationPending
                    ? null
                    : () {
                        Navigator.pop(context);
                        translateArticle(
                          article,
                          onTranslateSuccess: onTranslateSuccess,
                        );
                      },
              ),
              if (state.isTranslated) ...[
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    '删除翻译',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    TranslationService.deleteTranslation(article.entryId);
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: state.isSummaryPending
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.secondary,
                        ),
                      )
                    : Icon(Icons.summarize, color: colorScheme.secondary),
                title: Text(
                  state.isSummaryPending
                      ? '摘要中...'
                      : (state.hasSummary ? '重新摘要' : '生成摘要'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                enabled: !state.isSummaryPending,
                onTap: state.isSummaryPending
                    ? null
                    : () {
                        Navigator.pop(context);
                        summarizeArticle(article);
                      },
              ),
              if (state.hasSummary) ...[
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    '删除摘要',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    SummaryService.deleteSummary(article.entryId);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Future<void> showMacOSContextMenu(
    BuildContext context, {
    required Offset position,
    required ArticleModel article,
    VoidCallback? onTranslateSuccess,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final state = _ArticleActionState.from(article);

    final result = await AppContextMenu.show<String>(
      context,
      position: position,
      entries: [
        AppContextMenuAction(
          value: 'translate',
          icon: Icons.translate,
          label: state.isTranslationPending
              ? '翻译中...'
              : (state.isTranslated ? '重新翻译' : '翻译文章'),
          color: colorScheme.primary,
          enabled: !state.isTranslationPending,
          loading: state.isTranslationPending,
        ),
        if (state.isTranslated)
          AppContextMenuAction(
            value: 'delete_translation',
            icon: Icons.delete_outline,
            label: '删除翻译',
            destructive: true,
          ),
        const AppContextMenuDivider(),
        AppContextMenuAction(
          value: 'summarize',
          icon: Icons.summarize,
          label: state.isSummaryPending
              ? '摘要中...'
              : (state.hasSummary ? '重新摘要' : '生成摘要'),
          color: colorScheme.secondary,
          enabled: !state.isSummaryPending,
          loading: state.isSummaryPending,
        ),
        if (state.hasSummary)
          AppContextMenuAction(
            value: 'delete_summary',
            icon: Icons.delete_outline,
            label: '删除摘要',
            destructive: true,
          ),
      ],
    );

    if (result == 'translate') {
      await translateArticle(article, onTranslateSuccess: onTranslateSuccess);
    } else if (result == 'delete_translation') {
      TranslationService.deleteTranslation(article.entryId);
    } else if (result == 'summarize') {
      await summarizeArticle(article);
    } else if (result == 'delete_summary') {
      SummaryService.deleteSummary(article.entryId);
    }
  }

  static Future<void> translateArticle(
    ArticleModel article, {
    VoidCallback? onTranslateSuccess,
  }) async {
    try {
      final record = await TranslationService.translateArticle(article);
      if (record.translatedContent != null &&
          record.translatedContent!.isNotEmpty) {
        onTranslateSuccess?.call();
        AppFeedback.success('翻译完成', '已生成文章译文');
      } else {
        AppFeedback.error('翻译失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('翻译失败', e.toString());
    }
  }

  static Future<void> summarizeArticle(ArticleModel article) async {
    try {
      final record = await SummaryService.summarizeArticle(article);
      if (record.summaryText != null && record.summaryText!.isNotEmpty) {
        AppFeedback.success('摘要完成', '已生成文章摘要');
      } else {
        AppFeedback.error('摘要失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('摘要失败', e.toString());
    }
  }
}

class _ArticleActionState {
  final bool isTranslated;
  final bool isTranslationPending;
  final bool hasSummary;
  final bool isSummaryPending;

  const _ArticleActionState({
    required this.isTranslated,
    required this.isTranslationPending,
    required this.hasSummary,
    required this.isSummaryPending,
  });

  factory _ArticleActionState.from(ArticleModel article) {
    final translationRecord = TranslationService.recordOf(article.entryId);
    final summaryRecord = SummaryService.recordOf(article.entryId);
    return _ArticleActionState(
      isTranslationPending: translationRecord?.isPending ?? false,
      isTranslated:
          (translationRecord?.translatedTitle?.isNotEmpty ?? false) ||
          (translationRecord?.translatedContent?.isNotEmpty ?? false),
      isSummaryPending: summaryRecord?.isPending ?? false,
      hasSummary:
          (summaryRecord?.isSummarized ?? false) &&
          (summaryRecord?.summaryText?.trim().isNotEmpty ?? false),
    );
  }
}
