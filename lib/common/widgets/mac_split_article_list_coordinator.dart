import 'package:flutter/widgets.dart';

import '../../models/article.dart';

typedef ArticleListReader = List<ArticleModel> Function();
typedef SelectedArticleReader = ArticleModel? Function();
typedef SelectedArticleWriter = void Function(ArticleModel? article);
typedef ArticleRevealCallback = void Function(String entryId);

/// Coordinates selection while an item leaves a macOS split-view article list.
///
/// Business actions remain in the page. This class only owns selection order,
/// removal lifecycle state, stable item keys, and the final reveal request.
class MacSplitArticleListCoordinator {
  MacSplitArticleListCoordinator({
    required ArticleListReader articles,
    required SelectedArticleReader selectedArticle,
    required SelectedArticleWriter setSelectedArticle,
    required ArticleRevealCallback revealArticle,
  }) : _articles = articles,
       _selectedArticle = selectedArticle,
       _setSelectedArticle = setSelectedArticle,
       _revealArticle = revealArticle;

  final ArticleListReader _articles;
  final SelectedArticleReader _selectedArticle;
  final SelectedArticleWriter _setSelectedArticle;
  final ArticleRevealCallback _revealArticle;

  final Map<String, GlobalKey> itemKeys = {};
  final Map<String, GlobalKey> removingItemKeys = {};
  _PendingRemoval? _pendingRemoval;

  bool get isRemovingSelectedArticle => _pendingRemoval != null;

  GlobalKey itemKeyFor(String entryId) {
    return itemKeys.putIfAbsent(entryId, GlobalKey.new);
  }

  Key removedItemKeyFor(String entryId) {
    return removingItemKeys[entryId] ??
        itemKeys[entryId] ??
        ValueKey('removed-$entryId');
  }

  /// Stages the successor before business state changes can prune selection.
  /// Returns false while another selected-item removal is still running.
  bool beginRemoval(String entryId) {
    if (_pendingRemoval != null) return false;
    final selected = _selectedArticle();
    if (selected?.entryId != entryId) return true;

    final articles = _articles();
    final index = articles.indexWhere((article) => article.entryId == entryId);
    if (index < 0) return true;

    String? successorEntryId;
    if (articles.length > 1) {
      final successorIndex = index < articles.length - 1
          ? index + 1
          : index - 1;
      successorEntryId = articles[successorIndex].entryId;
    }
    _pendingRemoval = _PendingRemoval(
      removedEntryId: entryId,
      successorEntryId: successorEntryId,
      removedIndex: index,
    );
    return true;
  }

  void onRemoveStart(ArticleModel article) {
    final key = itemKeys.remove(article.entryId);
    if (key != null) removingItemKeys[article.entryId] = key;
  }

  void onRemoveEnd(ArticleModel article) {
    removingItemKeys.remove(article.entryId);
    final pending = _pendingRemoval;
    if (pending == null || pending.removedEntryId != article.entryId) return;
    _pendingRemoval = null;

    final articles = _articles();
    if (articles.isEmpty) {
      _setSelectedArticle(null);
      return;
    }

    ArticleModel? successor;
    final successorEntryId = pending.successorEntryId;
    if (successorEntryId != null) {
      for (final article in articles) {
        if (article.entryId == successorEntryId) {
          successor = article;
          break;
        }
      }
    }
    successor ??= articles[pending.removedIndex.clamp(0, articles.length - 1)];

    _setSelectedArticle(successor);
    _revealArticle(successor.entryId);
  }

  /// Keeps the outgoing detail mounted until its list animation completes.
  void reconcileSelection() {
    final selected = _selectedArticle();
    if (selected == null) return;

    final articles = _articles();
    if (articles.any((article) => article.entryId == selected.entryId)) return;
    if (_pendingRemoval?.removedEntryId == selected.entryId) return;

    _setSelectedArticle(articles.isEmpty ? null : articles.first);
  }

  bool selectRelative(int delta) {
    if (_pendingRemoval != null) return false;
    final articles = _articles();
    if (articles.isEmpty) return false;

    final selected = _selectedArticle();
    final currentIndex = selected == null
        ? -1
        : articles.indexWhere((article) => article.entryId == selected.entryId);
    final nextIndex = (currentIndex + delta).clamp(0, articles.length - 1);
    final next = articles[nextIndex];
    _setSelectedArticle(next);
    _revealArticle(next.entryId);
    return true;
  }

  bool restoreSelection(String entryId) {
    _pendingRemoval = null;
    for (final article in _articles()) {
      if (article.entryId != entryId) continue;
      _setSelectedArticle(article);
      _revealArticle(entryId);
      return true;
    }
    return false;
  }

  void cancelPendingRemoval() {
    _pendingRemoval = null;
  }

  void dispose() {
    _pendingRemoval = null;
    itemKeys.clear();
    removingItemKeys.clear();
  }
}

class _PendingRemoval {
  const _PendingRemoval({
    required this.removedEntryId,
    required this.successorEntryId,
    required this.removedIndex,
  });

  final String removedEntryId;
  final String? successorEntryId;
  final int removedIndex;
}
