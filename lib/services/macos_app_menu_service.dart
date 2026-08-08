import 'package:flutter/foundation.dart';

import '../models/article.dart';

typedef MacMenuPredicate = bool Function();

class MacOSArticleMenuTarget {
  const MacOSArticleMenuTarget({
    required this.article,
    required this.isActive,
    required this.isRead,
    required this.isReviewContext,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.openOriginal,
    required this.copyMarkdown,
    required this.performPrimaryAction,
    required this.performMisclassifyAction,
    required this.goPrevious,
    required this.goNext,
    required this.performTranslationAction,
    required this.translationLabel,
    required this.performSummaryAction,
    required this.summaryLabel,
    this.keepReviewArticle,
  });

  final ArticleModel article;
  final MacMenuPredicate isActive;
  final bool Function() isRead;
  final bool isReviewContext;
  final MacMenuPredicate canGoPrevious;
  final MacMenuPredicate canGoNext;
  final VoidCallback openOriginal;
  final VoidCallback copyMarkdown;
  final VoidCallback performPrimaryAction;
  final VoidCallback? performMisclassifyAction;
  final VoidCallback goPrevious;
  final VoidCallback goNext;
  final VoidCallback? Function() performTranslationAction;
  final String Function() translationLabel;
  final VoidCallback? Function() performSummaryAction;
  final String Function() summaryLabel;
  final VoidCallback? keepReviewArticle;

  String get primaryActionLabel {
    if (isReviewContext) return '移除《${article.title}》';
    return isRead() ? '将《${article.title}》恢复未读' : '将《${article.title}》标为已读';
  }

  String get misclassifyLabel {
    return isReviewContext ? '保留并标为已读' : '移入垃圾拦截并标为已读';
  }

  String get misclassifyDisabledLabel {
    if (isRead()) return '已读文章不可标记为误分类';
    return '已在垃圾拦截中，请前往垃圾拦截页面标记误分类';
  }

  bool get misclassifyEnabled {
    if (isReviewContext) return true;
    return !isRead() && !article.isRejectedByAi;
  }
}

class MacOSAppMenuService {
  MacOSAppMenuService._();

  static final instance = MacOSAppMenuService._();

  final revision = ValueNotifier<int>(0);
  final Map<Object, MacOSArticleMenuTarget> _articleTargets = {};

  void registerArticleTarget(Object owner, MacOSArticleMenuTarget target) {
    _articleTargets[owner] = target;
    notifyChanged();
  }

  void unregisterArticleTarget(Object owner) {
    if (_articleTargets.remove(owner) != null) notifyChanged();
  }

  MacOSArticleMenuTarget? get activeArticleTarget {
    for (final target in _articleTargets.values.toList().reversed) {
      if (target.isActive()) return target;
    }
    return null;
  }

  void notifyChanged() {
    revision.value++;
  }
}
