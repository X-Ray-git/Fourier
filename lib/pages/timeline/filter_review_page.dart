import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/article_relation_service.dart';
import '../../services/article_relation_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/android_haptics_service.dart';
import '../../services/external_link_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/mac_article_shortcut_service.dart';
import '../../services/summary_service.dart';
import '../../services/undo_service.dart';
import '../../utils/storage.dart';
import '../article/article_page.dart';
import '../main/main_controller.dart';
import '../timeline/timeline_controller.dart';
import '../widgets/article_card.dart';
import '../../common/widgets/article_card_chrome.dart';
import '../../common/widgets/article_length_label.dart';
import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/implicitly_animated_list.dart';
import '../../common/widgets/card_press_effect.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/app_glass_sync_button.dart';
import '../../common/widgets/mac_split_article_list_coordinator.dart';
import '../../common/widgets/mac_header_pane.dart';
import '../../common/widgets/macos_window_drag_area.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../common/widgets/mobile_viewport_insets.dart';
import '../../utils/scroll_utils.dart';
import '../widgets/article_actions_menu.dart';
import 'widgets/filter_review_pipeline_status.dart';

class _ReviewAnimProbe {
  static const bool _requested = bool.fromEnvironment(
    'FOURIER_ANIMATION_PROBE',
  );
  static final Stopwatch _clock = Stopwatch()..start();
  static _ReviewAnimProbeSession? _active;
  static bool _timingsInstalled = false;

  static bool get enabled => _requested && kDebugMode && Platform.isMacOS;

  static void begin(
    String entryId, {
    required String source,
    required String event,
    Map<String, Object?> fields = const {},
  }) {
    if (!enabled) return;
    _installTimingsProbe();
    final active = _active;
    if (active != null &&
        active.entryId == entryId &&
        active.source == source) {
      log(entryId, event, fields);
      return;
    }
    _active = _ReviewAnimProbeSession(
      entryId: entryId,
      source: source,
      startedAtUs: _clock.elapsedMicroseconds,
    );
    log(entryId, event, fields);
  }

  static void log(
    String entryId,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!enabled) return;
    final session = _active;
    if (session == null || session.entryId != entryId) return;
    final elapsedMs = (_clock.elapsedMicroseconds - session.startedAtUs) / 1000;
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrintSynchronously(
      '[ReviewAnimProbe +${elapsedMs.toStringAsFixed(1)}ms '
      'id=${_shortId(entryId)} source=${session.source}] '
      '$event${details.isEmpty ? '' : ' $details'}',
      wrapWidth: 2000,
    );
  }

  static void finish(String entryId) {
    if (!enabled) return;
    log(entryId, 'session.finish-scheduled');
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      final session = _active;
      if (session == null || session.entryId != entryId) return;
      log(entryId, 'session.finished');
      _active = null;
    });
  }

  static void _installTimingsProbe() {
    if (_timingsInstalled) return;
    _timingsInstalled = true;
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  static void _handleFrameTimings(List<FrameTiming> timings) {
    final session = _active;
    if (session == null) return;
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      if (buildMs < 16.7 && rasterMs < 16.7) continue;
      log(session.entryId, 'frame.slow', {
        'buildMs': buildMs.toStringAsFixed(1),
        'rasterMs': rasterMs.toStringAsFixed(1),
        'totalMs': timing.totalSpan.inMicroseconds ~/ 1000,
      });
    }
  }

  static String _shortId(String entryId) {
    if (entryId.length <= 8) return entryId;
    return entryId.substring(entryId.length - 8);
  }
}

class _ReviewAnimProbeSession {
  const _ReviewAnimProbeSession({
    required this.entryId,
    required this.source,
    required this.startedAtUs,
  });

  final String entryId;
  final String source;
  final int startedAtUs;
}

class FilterReviewPage extends StatefulWidget {
  final bool embeddedInMainNavigation;

  const FilterReviewPage({super.key, this.embeddedInMainNavigation = false});

  @override
  State<FilterReviewPage> createState() => _FilterReviewPageState();
}

class _FilterReviewPageState extends State<FilterReviewPage> {
  final _articles = <ArticleModel>[].obs;
  final _selectedArticle = Rxn<ArticleModel>();
  final FocusNode _emptyDetailFocusNode = FocusNode(
    debugLabel: 'filter-review-empty-detail',
  );
  final Set<String> _seenIds = {};
  final Set<String> _trackpadDismissedIds = {};
  final Set<String> _pendingReviewActionIds = {};
  final Map<String, UndoRestoreEvent> _deferredTrackpadRestores = {};
  final Map<String, ArticleModel> _pendingOriginalOpenAfterRemoval = {};
  bool _reloadAfterPendingReviewAction = false;
  bool _isViewingRelatedArticle = false;
  late final MacSplitArticleListCoordinator _listCoordinator;
  Worker? _articleStateWorker;
  Worker? _filterCountWorker;
  Worker? _undoRestoreWorker;

  @override
  void initState() {
    super.initState();
    _listCoordinator = MacSplitArticleListCoordinator(
      articles: () => _articles.toList(),
      selectedArticle: () => _selectedArticle.value,
      setSelectedArticle: (article) => _selectedArticle.value = article,
      revealArticle: _revealCoordinatedArticle,
    );
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    if (Platform.isMacOS) {
      MacArticleShortcutService.instance.register(
        this,
        isActive: () =>
            mounted &&
            _isActiveMacReviewPage &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        hasSelection: () => _selectedArticle.value != null,
        selectBoundary: (direction) {
          final selected = _listCoordinator.selectRelative(direction);
          return selected;
        },
      );
      UndoService.registerRedoPreparation(
        this,
        isActive: () =>
            mounted &&
            _isActiveMacReviewPage &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        prepare: _prepareRedo,
      );
    }
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
    _listCoordinator.dispose();
    _articleStateWorker?.dispose();
    _filterCountWorker?.dispose();
    _undoRestoreWorker?.dispose();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    if (Platform.isMacOS) {
      MacArticleShortcutService.instance.unregister(this);
      UndoService.unregisterRedoPreparation(this);
    }
    _emptyDetailFocusNode.dispose();
    super.dispose();
  }

  void _clearSelectionAndFocusEmptyDetail() {
    _selectedArticle.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isActiveMacReviewPage) {
        _emptyDetailFocusNode.requestFocus();
      }
    });
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) return false;
    if (event is! KeyDownEvent) return false;

    if (!Platform.isMacOS || !_isActiveMacReviewPage) return false;
    if (_isViewingRelatedArticle) return false;
    if (MacArticleShortcutService.hasNonShiftModifier) {
      return false;
    }
    final selected = _selectedArticle.value;
    if (selected == null) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyK:
        _keep(selected, source: 'keyK');
        return true;
      case LogicalKeyboardKey.keyM:
        _reject(selected, source: 'keyM');
        return true;
      case LogicalKeyboardKey.keyN:
        _misclassifyKeep(selected, source: 'keyN');
        return true;
      default:
        return false;
    }
  }

  void _loadArticles() {
    if (Platform.isMacOS && _pendingReviewActionIds.isNotEmpty) {
      _reloadAfterPendingReviewAction = true;
      return;
    }
    final all = LocalArticleDbService.readAllArticles()
        .where(
          (a) =>
              a.isRejectedByAi &&
              !a.isRead &&
              !_trackpadDismissedIds.contains(a.entryId),
        )
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
    if (Platform.isMacOS && _pendingReviewActionIds.contains(entryId)) {
      _ReviewAnimProbe.log(entryId, 'state-sync.deferred');
      return;
    }
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

    if (index < 0 && _trackpadDismissedIds.contains(entryId)) return;

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
    if (Platform.isMacOS) {
      _listCoordinator.reconcileSelection();
      return;
    }
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
    _ReviewAnimProbe.log(entryId, 'list.remove-request', {
      'before': _articles.length,
    });
    _articles.removeWhere((a) => a.entryId == entryId);
    _ReviewAnimProbe.log(entryId, 'list.remove-complete', {
      'after': _articles.length,
    });
    _refreshPointerAnnotationsAfterReviewChange();
  }

  void _scheduleReviewedArticleRemoval(String entryId) {
    if (!Platform.isMacOS) {
      _removeReviewedArticle(entryId);
      return;
    }

    _ReviewAnimProbe.log(entryId, 'list.remove-scheduled-after-frame');
    SchedulerBinding.instance.endOfFrame.then((_) {
      if (!mounted || !_pendingReviewActionIds.contains(entryId)) return;
      _ReviewAnimProbe.log(entryId, 'list.remove-frame-boundary');
      _removeReviewedArticle(entryId);
      _pendingReviewActionIds.remove(entryId);

      if (_pendingReviewActionIds.isEmpty && _reloadAfterPendingReviewAction) {
        _reloadAfterPendingReviewAction = false;
        _loadArticles();
      }
    });
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
    _refreshPointerAnnotationsAfterReviewChange();
  }

  void _refreshPointerAnnotationsAfterReviewChange() {
    if (!Platform.isMacOS) return;

    void update() {
      if (!mounted) return;
      RendererBinding.instance.mouseTracker.updateAllDevices();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      update();
      Future<void>.delayed(const Duration(milliseconds: 90), update);
      Future<void>.delayed(const Duration(milliseconds: 190), update);
    });
  }

  void _revealCoordinatedArticle(String entryId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToArticleWhenReady(entryId, attempt: 1);
      _refreshPointerAnnotationsAfterReviewChange();
    });
  }

  void _selectRelativeArticle(int delta) {
    _listCoordinator.selectRelative(delta);
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

    final key = _listCoordinator.itemKeys[entryId];
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

      if (_trackpadDismissedIds.contains(event.article.entryId)) {
        _deferredTrackpadRestores[event.article.entryId] = event;
        _listCoordinator.cancelPendingRemoval();
        return;
      }

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

  void _keep(
    ArticleModel article, {
    bool removalAlreadyStaged = false,
    String source = 'unknown',
  }) {
    _ReviewAnimProbe.begin(
      article.entryId,
      source: source,
      event: 'action.keep',
      fields: {
        'selected': _selectedArticle.value?.entryId == article.entryId,
        'index': _articles.indexWhere((a) => a.entryId == article.entryId),
        'count': _articles.length,
        'preStaged': removalAlreadyStaged,
      },
    );
    if (Platform.isMacOS && !removalAlreadyStaged) {
      final accepted = _listCoordinator.beginRemoval(article.entryId);
      _ReviewAnimProbe.log(article.entryId, 'coordinator.begin', {
        'accepted': accepted,
      });
      if (!accepted) {
        _ReviewAnimProbe.finish(article.entryId);
        return;
      }
    } else if (Platform.isMacOS) {
      _ReviewAnimProbe.log(article.entryId, 'coordinator.pre-staged');
    }
    if (Platform.isMacOS) {
      _pendingReviewActionIds.add(article.entryId);
    }
    final bool shouldAdvance =
        _selectedArticle.value?.entryId == article.entryId;
    final ArticleModel? nextArticle = shouldAdvance && !Platform.isMacOS
        ? _nextArticleAfterRemoving(article.entryId)
        : null;

    UndoService.applyFilterKeep(article);

    _scheduleReviewedArticleRemoval(article.entryId);
    if (shouldAdvance && !Platform.isMacOS) {
      _selectReviewedSuccessor(nextArticle);
    }
  }

  void _reject(
    ArticleModel article, {
    bool removalAlreadyStaged = false,
    String source = 'unknown',
  }) {
    _ReviewAnimProbe.begin(
      article.entryId,
      source: source,
      event: 'action.reject',
      fields: {
        'selected': _selectedArticle.value?.entryId == article.entryId,
        'index': _articles.indexWhere((a) => a.entryId == article.entryId),
        'count': _articles.length,
        'preStaged': removalAlreadyStaged,
      },
    );
    if (Platform.isMacOS && !removalAlreadyStaged) {
      final accepted = _listCoordinator.beginRemoval(article.entryId);
      _ReviewAnimProbe.log(article.entryId, 'coordinator.begin', {
        'accepted': accepted,
      });
      if (!accepted) {
        _ReviewAnimProbe.finish(article.entryId);
        return;
      }
    } else if (Platform.isMacOS) {
      _ReviewAnimProbe.log(article.entryId, 'coordinator.pre-staged');
    }
    if (Platform.isMacOS) {
      _pendingReviewActionIds.add(article.entryId);
    }
    final bool shouldAdvance =
        _selectedArticle.value?.entryId == article.entryId;
    final ArticleModel? nextArticle = shouldAdvance && !Platform.isMacOS
        ? _nextArticleAfterRemoving(article.entryId)
        : null;

    UndoService.applyFilterReject(article);

    _scheduleReviewedArticleRemoval(article.entryId);
    if (shouldAdvance && !Platform.isMacOS) {
      _selectReviewedSuccessor(nextArticle);
    }
  }

  void _misclassifyKeep(
    ArticleModel article, {
    bool removalAlreadyStaged = false,
    String source = 'unknown',
  }) {
    _ReviewAnimProbe.begin(
      article.entryId,
      source: source,
      event: 'action.misclassifyKeep',
      fields: {
        'selected': _selectedArticle.value?.entryId == article.entryId,
        'index': _articles.indexWhere((a) => a.entryId == article.entryId),
        'count': _articles.length,
        'preStaged': removalAlreadyStaged,
      },
    );
    if (Platform.isMacOS && !removalAlreadyStaged) {
      final accepted = _listCoordinator.beginRemoval(article.entryId);
      _ReviewAnimProbe.log(article.entryId, 'coordinator.begin', {
        'accepted': accepted,
      });
      if (!accepted) {
        _ReviewAnimProbe.finish(article.entryId);
        return;
      }
    } else if (Platform.isMacOS) {
      _ReviewAnimProbe.log(article.entryId, 'coordinator.pre-staged');
    }
    if (Platform.isMacOS) {
      _pendingReviewActionIds.add(article.entryId);
    }
    final bool shouldAdvance =
        _selectedArticle.value?.entryId == article.entryId;
    final ArticleModel? nextArticle = shouldAdvance && !Platform.isMacOS
        ? _nextArticleAfterRemoving(article.entryId)
        : null;

    UndoService.applyMisclassify(article, reject: false);

    _scheduleReviewedArticleRemoval(article.entryId);
    if (shouldAdvance && !Platform.isMacOS) {
      _selectReviewedSuccessor(nextArticle);
    }
  }

  bool? _prepareRedo(UndoAction action) {
    if (action.type != UndoActionType.filterKeep &&
        action.type != UndoActionType.filterReject &&
        action.type != UndoActionType.misclassifyKeep &&
        action.type != UndoActionType.misclassifySpam) {
      return null;
    }
    final index = _articles.indexWhere(
      (article) => article.entryId == action.article.entryId,
    );
    if (index < 0) return true;
    if (!_listCoordinator.beginRemoval(action.article.entryId)) return false;
    _pendingReviewActionIds.add(action.article.entryId);
    _scheduleReviewedArticleRemoval(action.article.entryId);
    return true;
  }

  void _rejectAndOpenOriginal(ArticleModel article) {
    _reject(article, source: 'shiftB');
    if (!_pendingReviewActionIds.contains(article.entryId)) return;

    _pendingOriginalOpenAfterRemoval[article.entryId] = article;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final pending = _pendingOriginalOpenAfterRemoval.remove(article.entryId);
      if (pending != null) unawaited(_openOriginalArticle(pending));
    });
  }

  Future<void> _openOriginalArticle(ArticleModel article) async {
    await ExternalLinkService.openUrlWithFeedback(article.url);
  }

  void _handleReviewRemoveStart(ArticleModel article) {
    _ReviewAnimProbe.log(article.entryId, 'remove.start', {
      'selected': _selectedArticle.value?.entryId == article.entryId,
      'count': _articles.length,
    });
    _listCoordinator.onRemoveStart(article);
  }

  void _handleReviewRemoveEnd(ArticleModel article) {
    _ReviewAnimProbe.log(article.entryId, 'remove.end-before-selection', {
      'selected': _selectedArticle.value?.entryId,
    });
    _trackpadDismissedIds.remove(article.entryId);
    _listCoordinator.onRemoveEnd(article);
    _ReviewAnimProbe.log(article.entryId, 'remove.end-after-selection', {
      'selected': _selectedArticle.value?.entryId,
    });
    _ReviewAnimProbe.finish(article.entryId);

    final pendingOpen = _pendingOriginalOpenAfterRemoval.remove(
      article.entryId,
    );
    if (pendingOpen != null) {
      unawaited(
        SchedulerBinding.instance.endOfFrame.then((_) {
          if (mounted) unawaited(_openOriginalArticle(pendingOpen));
        }),
      );
    }

    final restored = _deferredTrackpadRestores.remove(article.entryId);
    if (restored == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActiveMacReviewPage) return;
      _syncArticleFromDb(restored.article.entryId);
      _listCoordinator.restoreSelection(restored.article.entryId);
    });
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
    final body = Obx(() {
      final q = AutoFilterWorker.queuedCount.value;
      final p = AutoFilterWorker.processingCount.value;
      ArticleRelationService.recordsVersion.value;
      final relationActive =
          ArticleRelationService.pendingCount > 0 ||
          ArticleRelationWorker.processingCount.value > 0;
      final llmActive = q > 0 || p > 0 || relationActive;

      return Column(
        children: [
          Expanded(
            child: _articles.isEmpty
                ? _buildEmptyState(cs, llmActive: llmActive)
                : ListView.builder(
                    padding: EdgeInsets.only(
                      top:
                          6 +
                          (widget.embeddedInMainNavigation
                              ? MobileViewportInsets.listTopInset(context).top
                              : 0),
                      bottom:
                          16 +
                          MediaQuery.of(context).padding.bottom +
                          (widget.embeddedInMainNavigation
                              ? kBottomNavigationBarHeight
                              : 0),
                    ),
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return Padding(
                        padding: ArticleCardChrome.outerPadding,
                        child: _MobileReviewDismissible(
                          key: ValueKey('mobile-swipe-${article.entryId}'),
                          dismissibleKey: ValueKey(article.entryId),
                          confirmDismiss: (direction) async {
                            // 侧滑达到阈值且动作确认：中等反馈。
                            // 振动只在手势层触发一次，业务层不再重复。
                            await AndroidHapticsService.mediumImpact();
                            if (direction == DismissDirection.startToEnd) {
                              _keep(article);
                            } else {
                              _reject(article);
                            }
                            return false;
                          },
                          keepColor: const Color(0xFF10B981),
                          rejectColor: cs.error,
                          child: Obx(() {
                            final selectedId = _selectedArticle.value?.entryId;
                            return ArticleCard(
                              article: article,
                              isSelected:
                                  Platform.isMacOS &&
                                  selectedId == article.entryId,
                              showFeedTitle: true,
                              showSummary: true,
                              outerPadding: EdgeInsets.zero,
                              onTap: () {
                                if (Platform.isMacOS) {
                                  _selectedArticle.value = article;
                                } else {
                                  final sequence = _articles.toList();
                                  // PageView 索引按 entryId 重新查找。
                                  final resolvedIndex = sequence.indexWhere(
                                    (candidate) =>
                                        candidate.entryId == article.entryId,
                                  );
                                  Get.toNamed(
                                    Routes.article,
                                    arguments: {
                                      'article': article,
                                      'sequence': sequence,
                                      'index': resolvedIndex < 0
                                          ? 0
                                          : resolvedIndex,
                                    },
                                  );
                                }
                              },
                            );
                          }),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });

    if (widget.embeddedInMainNavigation) {
      return body;
    }

    return Scaffold(
      appBar: MobileBlurAppBar(title: const FilterReviewStatusTitle()),
      body: body,
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
            child: MacHeaderPane(
              headerHeight: kToolbarHeight,
              header: _MacReviewHeader(
                articles: _articles,
                colorScheme: cs,
                onSync: _syncReviewArticles,
              ),
              body: Obx(() {
                final q = AutoFilterWorker.queuedCount.value;
                final p = AutoFilterWorker.processingCount.value;
                ArticleRelationService.recordsVersion.value;
                final relationActive =
                    ArticleRelationService.pendingCount > 0 ||
                    ArticleRelationWorker.processingCount.value > 0;
                final llmActive = q > 0 || p > 0 || relationActive;

                return ScrollbarTheme(
                  data: MacGlassScrollbarStyle.articlePaneTheme(context),
                  child: Padding(
                    padding: MacArticleListChrome.viewportPadding,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ImplicitlyAnimatedList<ArticleModel>(
                            items: _articles.toList(),
                            itemKey: (article) => article.entryId,
                            padding: MacArticleListChrome.contentPadding(
                              context,
                            ),
                            separatorBuilder: (_, _) => const SizedBox.shrink(),
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
                              child: _buildEmptyState(cs, llmActive: llmActive),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
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
                return MacSplitDetailEmptyPlaceholder(
                  topInset: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  focusNode: _emptyDetailFocusNode,
                );
              }
              bool isDetailActive() =>
                  !Get.isRegistered<MainController>() ||
                  Get.find<MainController>().currentIndex.value == 1;
              return MacArticleDetailStack(
                key: ValueKey(selected.entryId),
                isActive: isDetailActive,
                onRelatedNavigationChanged: (isViewingRelated) {
                  _isViewingRelatedArticle = isViewingRelated;
                },
                rootBuilder: (_, openRelatedArticle) => ArticlePageView(
                  article: selected,
                  isSplitView: true,
                  isActive: isDetailActive,
                  isSelectedArticle: (entryId) =>
                      _selectedArticle.value?.entryId == entryId,
                  isReviewContext: true,
                  onKeepReviewArticle: () {
                    final currentSelected = _selectedArticle.value;
                    if (currentSelected != null) {
                      _keep(currentSelected, source: 'menuKeep');
                    }
                  },
                  onMisclassifyKeyPressed: () {
                    final currentSelected = _selectedArticle.value;
                    if (currentSelected != null) {
                      _misclassifyKeep(currentSelected, source: 'keyN');
                    }
                  },
                  onClose: _clearSelectionAndFocusEmptyDetail,
                  onPrevious: () => _selectRelativeArticle(-1),
                  onNext: () => _selectRelativeArticle(1),
                  onMKeyPressed: () {
                    final currentSelected = _selectedArticle.value;
                    if (currentSelected != null) {
                      _reject(currentSelected, source: 'keyM');
                    }
                  },
                  onOpenRelatedArticle: openRelatedArticle,
                  onOpenOriginalAndMarkRead: () {
                    final currentSelected = _selectedArticle.value;
                    if (currentSelected != null) {
                      _rejectAndOpenOriginal(currentSelected);
                    }
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, {required bool llmActive}) {
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const FilterReviewPipelineStatus(
                layout: FilterReviewPipelineLayout.column,
                fontSize: 11,
              ),
            ),
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
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: animation,
        child: _MacTrackpadReviewSwipe(
          key: ValueKey('review-swipe-${article.entryId}'),
          probeId: article.entryId,
          keepColor: const Color(0xFF059669),
          rejectColor: Theme.of(context).colorScheme.error,
          onWillCommit: () => _listCoordinator.beginRemoval(article.entryId),
          onCommitAborted: _listCoordinator.cancelPendingRemoval,
          onCommitted: (action) {
            _trackpadDismissedIds.add(article.entryId);
            switch (action) {
              case _ReviewSwipeAction.keep:
                _keep(
                  article,
                  removalAlreadyStaged: true,
                  source: 'trackpadKeep',
                );
              case _ReviewSwipeAction.reject:
                _reject(
                  article,
                  removalAlreadyStaged: true,
                  source: 'trackpadReject',
                );
            }
          },
          child: Obx(() {
            final selected = _selectedArticle.value?.entryId == article.entryId;
            return _MacReviewRow(
              key: _listCoordinator.itemKeyFor(article.entryId),
              article: article,
              selected: selected,
              onTap: () => _selectedArticle.value = article,
              onKeep: () => _keep(article, source: 'contextMenuKeep'),
              onReject: () => _reject(article, source: 'contextMenuReject'),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRemovedReviewRow(
    BuildContext context,
    ArticleModel article,
    int index,
    Animation<double> animation,
  ) {
    final transition = SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation,
        child: Opacity(
          opacity: _trackpadDismissedIds.contains(article.entryId) ? 0 : 1,
          child: _MacReviewRow(
            key: _listCoordinator.removedItemKeyFor(article.entryId),
            article: article,
            selected: false,
            onTap: () {},
            onKeep: () {},
            onReject: () {},
          ),
        ),
      ),
    );
    if (!_ReviewAnimProbe.enabled) return transition;
    return _ReviewRemovalAnimationProbe(
      entryId: article.entryId,
      animation: animation,
      child: transition,
    );
  }
}

class FilterReviewStatusTitle extends StatelessWidget {
  const FilterReviewStatusTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '垃圾拦截',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: FilterReviewPipelineStatus(fontSize: 9.5),
        ),
      ],
    );
  }
}

class _ReviewRemovalAnimationProbe extends StatefulWidget {
  const _ReviewRemovalAnimationProbe({
    required this.entryId,
    required this.animation,
    required this.child,
  });

  final String entryId;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_ReviewRemovalAnimationProbe> createState() =>
      _ReviewRemovalAnimationProbeState();
}

class _ReviewRemovalAnimationProbeState
    extends State<_ReviewRemovalAnimationProbe> {
  int? _lastBucket;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_handleAnimation);
    widget.animation.addStatusListener(_handleStatus);
    _ReviewAnimProbe.log(widget.entryId, 'remove.builder-attached', {
      'value': widget.animation.value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
    _handleAnimation();
  }

  @override
  void didUpdateWidget(_ReviewRemovalAnimationProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeListener(_handleAnimation);
    oldWidget.animation.removeStatusListener(_handleStatus);
    _lastBucket = null;
    widget.animation.addListener(_handleAnimation);
    widget.animation.addStatusListener(_handleStatus);
    _handleAnimation();
  }

  @override
  void dispose() {
    widget.animation.removeListener(_handleAnimation);
    widget.animation.removeStatusListener(_handleStatus);
    _ReviewAnimProbe.log(widget.entryId, 'remove.builder-disposed', {
      'value': widget.animation.value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    _ReviewAnimProbe.log(widget.entryId, 'remove.animation-status', {
      'status': status.name,
      'value': widget.animation.value.toStringAsFixed(3),
    });
  }

  void _handleAnimation() {
    final value = widget.animation.value;
    final bucket = switch (value) {
      >= 0.95 => 4,
      >= 0.70 => 3,
      >= 0.45 => 2,
      >= 0.20 => 1,
      _ => 0,
    };
    if (_lastBucket == bucket) return;
    _lastBucket = bucket;
    _ReviewAnimProbe.log(widget.entryId, 'remove.animation-progress', {
      'bucket': bucket,
      'value': value.toStringAsFixed(3),
      'status': widget.animation.status.name,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _ReviewSwipeAction { keep, reject }

class _MobileReviewDismissible extends StatefulWidget {
  const _MobileReviewDismissible({
    super.key,
    required this.dismissibleKey,
    required this.confirmDismiss,
    required this.keepColor,
    required this.rejectColor,
    required this.child,
  });

  final Key dismissibleKey;
  final ConfirmDismissCallback confirmDismiss;
  final Color keepColor;
  final Color rejectColor;
  final Widget child;

  @override
  State<_MobileReviewDismissible> createState() =>
      _MobileReviewDismissibleState();
}

class _MobileReviewDismissibleState extends State<_MobileReviewDismissible> {
  double _width = 0;
  double _offset = 0;

  void _handleUpdate(DismissUpdateDetails details) {
    final direction = switch (details.direction) {
      DismissDirection.startToEnd => 1.0,
      DismissDirection.endToStart => -1.0,
      _ => 0.0,
    };
    final nextOffset = direction * details.progress * _width;
    if (nextOffset == _offset) return;
    setState(() => _offset = nextOffset);
  }

  Widget _buildBackground({
    required Color color,
    required Alignment alignment,
    required EdgeInsets padding,
    required IconData icon,
  }) {
    return ClipPath(
      clipper: _ReviewSwipeRevealClipper(
        _offset,
        outerPadding: EdgeInsets.zero,
        radius: ArticleCardChrome.radius,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: _offset >= 0
                    ? _buildBackground(
                        color: widget.keepColor,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 24),
                        icon: Icons.restore_rounded,
                      )
                    : _buildBackground(
                        color: widget.rejectColor,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        icon: Icons.delete_sweep_rounded,
                      ),
              ),
              Dismissible(
                key: widget.dismissibleKey,
                direction: DismissDirection.horizontal,
                dismissThresholds: const {
                  DismissDirection.startToEnd: 0.35,
                  DismissDirection.endToStart: 0.35,
                },
                confirmDismiss: widget.confirmDismiss,
                onUpdate: _handleUpdate,
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MacTrackpadReviewSwipe extends StatefulWidget {
  const _MacTrackpadReviewSwipe({
    super.key,
    required this.probeId,
    required this.child,
    required this.keepColor,
    required this.rejectColor,
    required this.onWillCommit,
    required this.onCommitAborted,
    required this.onCommitted,
  });

  final String probeId;
  final Widget child;
  final Color keepColor;
  final Color rejectColor;
  final bool Function() onWillCommit;
  final VoidCallback onCommitAborted;
  final ValueChanged<_ReviewSwipeAction> onCommitted;

  @override
  State<_MacTrackpadReviewSwipe> createState() =>
      _MacTrackpadReviewSwipeState();
}

class _MacTrackpadReviewSwipeState extends State<_MacTrackpadReviewSwipe>
    with SingleTickerProviderStateMixin {
  static const double _distanceThreshold = 0.30;
  static const double _minimumFlingDistance = 32;
  static const double _flingVelocityThreshold = 900;

  late final AnimationController _offsetController;
  double _width = 0;
  bool _committing = false;
  bool _didCommit = false;

  @override
  void initState() {
    super.initState();
    _offsetController = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    if (_committing && !_didCommit) widget.onCommitAborted();
    _offsetController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (_committing) return;
    _offsetController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_committing || _width <= 0) return;
    final next = _offsetController.value + (details.primaryDelta ?? 0);
    _offsetController.value = next.clamp(-_width * 0.82, _width * 0.82);
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    if (_committing || _width <= 0) return;

    final offset = _offsetController.value;
    final velocity = details.primaryVelocity ?? 0;
    final crossedDistance = offset.abs() >= _width * _distanceThreshold;
    final crossedFling =
        offset.abs() >= _minimumFlingDistance &&
        velocity.abs() >= _flingVelocityThreshold &&
        velocity.sign == offset.sign;
    if (!crossedDistance && !crossedFling) {
      await _reset();
      return;
    }
    final action = offset > 0
        ? _ReviewSwipeAction.keep
        : _ReviewSwipeAction.reject;
    final source = action == _ReviewSwipeAction.keep
        ? 'trackpadKeep'
        : 'trackpadReject';
    _ReviewAnimProbe.begin(
      widget.probeId,
      source: source,
      event: 'swipe.commit-request',
      fields: {
        'offset': offset.toStringAsFixed(1),
        'width': _width.toStringAsFixed(1),
        'velocity': velocity.toStringAsFixed(1),
      },
    );
    if (!widget.onWillCommit()) {
      _ReviewAnimProbe.log(widget.probeId, 'swipe.commit-rejected');
      _ReviewAnimProbe.finish(widget.probeId);
      await _reset();
      return;
    }

    _committing = true;
    _ReviewAnimProbe.log(widget.probeId, 'swipe.horizontal-start');
    await _offsetController.animateTo(
      offset > 0 ? _width : -_width,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    _ReviewAnimProbe.log(widget.probeId, 'swipe.horizontal-end');
    _didCommit = true;
    widget.onCommitted(action);
  }

  Future<void> _reset() async {
    await _offsetController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          supportedDevices: const {PointerDeviceKind.trackpad},
          onHorizontalDragStart: _handleDragStart,
          onHorizontalDragUpdate: _handleDragUpdate,
          onHorizontalDragEnd: _handleDragEnd,
          onHorizontalDragCancel: _reset,
          child: AnimatedBuilder(
            animation: _offsetController,
            builder: (context, child) {
              final offset = _offsetController.value;
              final action = offset >= 0
                  ? _ReviewSwipeAction.keep
                  : _ReviewSwipeAction.reject;
              final color = action == _ReviewSwipeAction.keep
                  ? widget.keepColor
                  : widget.rejectColor;
              final progress = _width <= 0
                  ? 0.0
                  : (offset.abs() / (_width * _distanceThreshold)).clamp(
                      0.0,
                      1.0,
                    );

              return ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipPath(
                          clipper: _ReviewSwipeRevealClipper(
                            offset,
                            outerPadding: ArticleCardChrome.outerPadding,
                            radius: ArticleCardChrome.radius,
                          ),
                          child: Opacity(
                            opacity: progress,
                            child: Padding(
                              padding: ArticleCardChrome.outerPadding,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(
                                    ArticleCardChrome.radius,
                                  ),
                                ),
                                child: Align(
                                  alignment: action == _ReviewSwipeAction.keep
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          action == _ReviewSwipeAction.keep
                                              ? Icons.restore_rounded
                                              : Icons.delete_sweep_outlined,
                                          size: 20,
                                          color: color,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          action == _ReviewSwipeAction.keep
                                              ? '保留'
                                              : '移除',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    ),
                  ],
                ),
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _ReviewSwipeRevealClipper extends CustomClipper<Path> {
  const _ReviewSwipeRevealClipper(
    this.offset, {
    required this.outerPadding,
    required this.radius,
  });

  final double offset;
  final EdgeInsets outerPadding;
  final double radius;

  @override
  Path getClip(Size size) {
    final originalRect = Rect.fromLTRB(
      outerPadding.left,
      outerPadding.top,
      size.width - outerPadding.right,
      size.height - outerPadding.bottom,
    );
    if (offset == 0 || originalRect.isEmpty) return Path();

    final corner = Radius.circular(radius);
    final original = Path()
      ..addRRect(RRect.fromRectAndRadius(originalRect, corner));
    final translated = Path()
      ..addRRect(
        RRect.fromRectAndRadius(originalRect.shift(Offset(offset, 0)), corner),
      );
    return Path.combine(PathOperation.difference, original, translated);
  }

  @override
  bool shouldReclip(_ReviewSwipeRevealClipper oldClipper) {
    return oldClipper.offset != offset ||
        oldClipper.outerPadding != outerPadding ||
        oldClipper.radius != radius;
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
              final timelineController = Get.isRegistered<TimelineController>()
                  ? Get.find<TimelineController>()
                  : null;
              final syncing = timelineController?.isSyncing.value ?? false;

              return Row(
                children: [
                  Expanded(
                    child: MacOSWindowDragArea(
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
                            humanCount == 0 ? '全部处理完毕' : '$humanCount 篇待处理',
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
                  ),
                  const FilterReviewPipelineStatus(
                    layout: FilterReviewPipelineLayout.column,
                  ),
                  const SizedBox(width: 10),
                  AppGlassSyncButton(
                    syncing: syncing,
                    onPressed: onSync,
                    syncingColor: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                ],
              );
            }),
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

    return Padding(
      padding: ArticleCardChrome.outerPadding,
      child: CardPressEffect(
        onTap: onTap,
        onSecondaryTapDown: Platform.isMacOS
            ? (details) {
                ArticleActionsMenu.showMacOSContextMenu(
                  context,
                  position: details.globalPosition,
                  article: article,
                  onKeep: onKeep,
                  onReject: onReject,
                );
              }
            : null,
        enableHover: true,
        enablePress: true,
        borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
        child: Material(
          color: ArticleCardChrome.fillColor(context, selected: selected),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
            side: ArticleCardChrome.borderSide(context, selected: selected),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: ArticleCardChrome.contentPadding,
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
                          fontSize: ArticleCardChrome.titleFontSize,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              feedTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ArticleLengthLabel(article: article),
                        ],
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
              ],
            ),
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
      SummaryStatus.done => const Color(0xFF64748B),
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
