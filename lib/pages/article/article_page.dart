import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;

import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/constants/constants.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/macos_window_drag_guard.dart';
import '../../common/liquid_glass/liquid_glass.dart' as glass;
import '../../services/article_image_service.dart';
import '../../services/article_image_cache_service.dart';
import '../../services/article_markdown_export_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/macos_app_menu_service.dart';
import '../../services/auto_ai_queue_coordinator.dart';
import '../../services/read_sync_service.dart';
import '../../services/translation_service.dart';
import '../../services/summary_service.dart';
import '../../services/article_state_notifier.dart';
import '../../utils/article_content_utils.dart';
import '../../utils/html_chunk_parser.dart';
import '../../utils/security_utils.dart';
import '../../utils/storage.dart';
import '../../services/undo_service.dart';
import '../timeline/timeline_controller.dart';
import 'widgets/html_chunk_card.dart';
import 'package:flutter_html/flutter_html.dart';
import 'widgets/image_gallery_page.dart';
import '../../common/widgets/hero_dialog_route.dart';

/// 文章详情控制器
class ArticleController extends GetxController {
  final ArticleModel article;
  String normalizedContent = '';
  List<String> imageUrls = [];
  final chunks = <HtmlChunk>[].obs;
  final translatedChunks = <HtmlChunk>[].obs;
  final showTranslation = false.obs;
  final isRead = false.obs;
  final isUpdatingReadState = false.obs;
  final isTranslated = false.obs;
  final translationContent = ''.obs;
  final isTranslating = false.obs;
  final summaryText = ''.obs;
  final isSummarized = false.obs;
  final isSummarizing = false.obs;
  final showSummary = true.obs;
  final isFetchingReadability = false.obs;
  final isFetchingContent = false.obs;
  final isParsingContent = false.obs;
  Worker? _translationRecordWorker;
  String _translationSourceContent = '';

  ArticleController(this.article);

  @override
  void onInit() {
    super.onInit();
    _translationRecordWorker = ever(
      TranslationService.recordsVersion,
      (_) => _refreshTranslationFromService(),
    );
    isRead.value =
        LocalArticleDbService.readOverrideOf(article.entryId) ?? article.isRead;
    if (article.category == 'inbox' &&
        (article.content == null || article.content!.trim().isEmpty)) {
      isFetchingContent.value = true;
      _fetchInboxContent();
    } else if (article.content != null && article.content!.isNotEmpty) {
      _initContent();
    } else {
      _initContent();
      isFetchingContent.value = true;
      if (article.url.isNotEmpty) {
        fetchReadabilityContent();
      }
    }
  }

  @override
  void onClose() {
    _translationRecordWorker?.dispose();
    super.onClose();
  }

  Future<void> _initContent({String? overrideContent}) async {
    isParsingContent.value = true;

    final rawHtml = overrideContent ?? article.content ?? '';
    final entryId = article.entryId;
    final hasTranslation = TranslationService.hasTranslation(entryId);
    final tContent = hasTranslation
        ? (TranslationService.translatedContentFor(entryId) ?? '')
        : '';
    final sourceUrl = article.url;

    try {
      final result = await Isolate.run(() {
        final normalized = ArticleContentUtils.normalizeHtml(
          rawHtml,
          sourceUrl: sourceUrl,
        );
        final urls = ArticleContentUtils.extractImageUrls(normalized);
        final parsedChunks = HtmlChunkParser.parseSync(normalized);

        var normalizedTranslation = '';
        List<HtmlChunk> tParsedChunks = const [];
        if (hasTranslation && tContent.isNotEmpty) {
          normalizedTranslation = ArticleContentUtils.normalizeHtml(
            tContent,
            sourceUrl: sourceUrl,
          );
          tParsedChunks = HtmlChunkParser.parseSync(normalizedTranslation);
        }

        return (
          normalizedContent: normalized,
          normalizedTranslation: normalizedTranslation,
          imageUrls: urls,
          chunks: parsedChunks,
          translatedChunks: tParsedChunks,
        );
      });

      normalizedContent = result.normalizedContent;
      imageUrls = result.imageUrls;
      ArticleImageCacheService.prioritizeArticle(entryId, imageUrls);
      chunks.value = result.chunks;

      if (hasTranslation) {
        _translationSourceContent = tContent;
        isTranslated.value = true;
        translationContent.value = result.normalizedTranslation;
        if (result.translatedChunks.isNotEmpty) {
          translatedChunks.value = result.translatedChunks;
        }
        showTranslation.value = true;
      }

      if (SummaryService.hasSummary(entryId)) {
        isSummarized.value = true;
        summaryText.value = SummaryService.summaryFor(entryId) ?? '';
        showSummary.value = true;
      }
    } finally {
      isParsingContent.value = false;
    }
  }

  Future<void> _refreshTranslationFromService() async {
    final record = TranslationService.recordOf(article.entryId);
    if (record == null) {
      _translationSourceContent = '';
      isTranslated.value = false;
      translationContent.value = '';
      translatedChunks.clear();
      showTranslation.value = false;
      return;
    }

    final sourceContent = record.translatedContent?.trim() ?? '';
    if (!record.isTranslated || sourceContent.isEmpty) return;
    if (_translationSourceContent == sourceContent &&
        translatedChunks.isNotEmpty) {
      isTranslated.value = true;
      return;
    }

    final shouldReveal = !isTranslated.value;
    final sourceUrl = article.url;
    final result = await Isolate.run(() {
      final normalized = ArticleContentUtils.normalizeHtml(
        sourceContent,
        sourceUrl: sourceUrl,
      );
      return (
        normalized: normalized,
        chunks: HtmlChunkParser.parseSync(normalized),
      );
    });
    if (isClosed) return;

    final latestSourceContent =
        TranslationService.translatedContentFor(article.entryId)?.trim() ?? '';
    if (latestSourceContent != sourceContent) return;
    _translationSourceContent = sourceContent;
    translationContent.value = result.normalized;
    translatedChunks.value = result.chunks;
    isTranslated.value = true;
    if (shouldReveal) showTranslation.value = true;
  }

  Future<void> _fetchInboxContent() async {
    final result = await FeedHttp.getInboxEntryDetail(entryId: article.entryId);
    if (result is Success<String> && result.response.isNotEmpty) {
      await _initContent(overrideContent: result.response);
      _persistFetchedContent(result.response);
      update(); // 通知 UI 重建
    }
    isFetchingContent.value = false;
  }

  Future<void> fetchReadabilityContent() async {
    if (article.url.isEmpty) return;

    // We shouldn't block initialization, run async
    Future.microtask(() async {
      isFetchingReadability.value = true;
      try {
        final response = await Request.dio.get(article.url);
        final htmlStr = response.data.toString();
        final document = html_parser.parse(htmlStr);
        final articleNode = ArticleContentUtils.getReadabilityContent(document);
        if (articleNode != null) {
          await _initContent(overrideContent: articleNode.outerHtml);
          _persistFetchedContent(articleNode.outerHtml);
        }
      } catch (e) {
        // silently fail on auto-fetch
      } finally {
        isFetchingReadability.value = false;
        isFetchingContent.value = false;
      }
    });
  }

  void _persistFetchedContent(String content) {
    final fetchedArticle = ArticleModel(
      entryId: article.entryId,
      feedId: article.feedId,
      feedTitle: article.feedTitle,
      feedImage: article.feedImage,
      title: article.title,
      url: article.url,
      content: content,
      publishedAt: article.publishedAt,
      isRead: isRead.value,
      category: article.category,
      subscriptionCategory: article.subscriptionCategory,
      author: article.author,
      imageUrl: article.imageUrl,
      isRejectedByAi: article.isRejectedByAi,
      filterReason: article.filterReason,
      filterReviewed: article.filterReviewed,
      filteredAt: article.filteredAt,
    );
    LocalArticleDbService.upsertOne(fetchedArticle);
    ArticleContentUtils.clearCacheForEntry(article.entryId);
    AutoAiQueueCoordinator.onArticleContentAvailable(fetchedArticle);
  }

  /// 标为已读（本地 + 云端同步 + 失败重试最多 5 次）
  Future<void> markAsRead({bool showSuccess = true}) async {
    if (isRead.value) return;
    if (isUpdatingReadState.value) return;

    isUpdatingReadState.value = true;
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
    final isInbox = article.category == 'inbox';
    ReadSyncService.enqueue(article.entryId, isInbox: isInbox);
    isRead.value = true;
    UndoService.recordRead(article);
    ArticleStateNotifier.tick(article.entryId);

    final ok = await _retrySync(
      action: () =>
          FeedHttp.markRead(entryIds: [article.entryId], isInbox: isInbox),
      successMsg: showSuccess ? '已标记已读' : null,
      maxRetries: 5,
    );

    // 同步结束后移出待同步队列；本地已读覆盖保留到未读快照确认。
    ReadSyncService.removeMany([article.entryId]);

    if (!ok) {
      // 5 次失败 → 恢复本地未读，与服务器保持一致
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
      } else {
        LocalArticleDbService.setReadState(article.entryId, false);
      }
      isRead.value = false;
      UndoService.clearForEntry(article.entryId);
      ArticleStateNotifier.tick(article.entryId);
      AppFeedback.error('标记已读失败', '已重试5次，已恢复为未读');
    }
    isUpdatingReadState.value = false;
  }

  Future<void> markAsUnread() async {
    if (!isRead.value || isUpdatingReadState.value) return;

    isUpdatingReadState.value = true;
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    } else {
      LocalArticleDbService.setReadState(article.entryId, false);
    }
    isRead.value = false;
    ArticleStateNotifier.tick(article.entryId);

    final ok = await _retrySync(
      action: () => FeedHttp.markUnread(entryId: article.entryId),
      successMsg: '已恢复未读',
      maxRetries: 5,
    );

    if (!ok) {
      // 5 次失败 → 恢复本地已读
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsReadLocal(
          article.entryId,
          recordHistory: false,
        );
      } else {
        GStorage.readStatus.put(article.entryId, true);
        LocalArticleDbService.setReadState(article.entryId, true);
      }
      isRead.value = true;
      ArticleStateNotifier.tick(article.entryId);
      AppFeedback.error('恢复未读失败', '已重试5次，已恢复为已读');
    }
    isUpdatingReadState.value = false;
  }

  /// 带重试的云端同步。成功返回 true，5 次均失败返回 false。
  Future<bool> _retrySync({
    required Future<LoadingState<void>> Function() action,
    required String? successMsg,
    int maxRetries = 5,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final result = await action();
      if (result is Success<void>) {
        if (successMsg != null) {
          if (attempt == 1) {
            AppFeedback.success(successMsg, '已同步到云端');
          } else {
            AppFeedback.success(successMsg, '重试 $attempt 次后成功');
          }
        }
        return true;
      }
      if (attempt < maxRetries) {
        final delay = Duration(milliseconds: 800 * attempt);
        await Future.delayed(delay);
        AppFeedback.info('同步失败，重试中', '第 $attempt/$maxRetries 次');
      }
    }
    return false;
  }

  Future<void> translateArticle() async {
    if (normalizedContent.isEmpty) {
      AppFeedback.warning('无法翻译', '文章内容为空');
      return;
    }

    isTranslating.value = true;
    try {
      final record = await TranslationService.translateArticle(
        article,
        targetLang: '简体中文',
        overrideContent: normalizedContent,
      );

      if (record.translatedContent != null &&
          record.translatedContent!.isNotEmpty) {
        _translationSourceContent = record.translatedContent!.trim();
        final normalizedTranslation = ArticleContentUtils.normalizeHtml(
          record.translatedContent!,
          sourceUrl: article.url,
        );
        translationContent.value = normalizedTranslation;
        isTranslated.value = true;
        // 同步解析译文的块
        final tChunks = HtmlChunkParser.parseSync(normalizedTranslation);
        translatedChunks.value = tChunks;
        showTranslation.value = true;
        AppFeedback.success('翻译完成', '已生成文章译文');
      } else {
        AppFeedback.error('翻译失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('翻译出错', e.toString());
    } finally {
      isTranslating.value = false;
    }
  }

  Future<void> summarizeArticle() async {
    if (normalizedContent.isEmpty) {
      AppFeedback.warning('无法摘要', '文章内容为空');
      return;
    }

    isSummarizing.value = true;
    try {
      final record = await SummaryService.summarizeArticle(
        article,
        targetLang: '简体中文',
        overrideContent: normalizedContent,
      );

      if (record.summaryText != null && record.summaryText!.isNotEmpty) {
        summaryText.value = record.summaryText!;
        isSummarized.value = true;
        showSummary.value = true;
        AppFeedback.success('摘要完成', '已生成文章摘要');
      } else {
        AppFeedback.error('摘要失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('摘要出错', e.toString());
    } finally {
      isSummarizing.value = false;
    }
  }

  void toggleTranslationDisplay() {
    if (!isTranslated.value) return;
    showTranslation.toggle();
  }

  Future<void> openInBrowser() async {
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

  Future<void> openLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = SecurityUtils.parseHttpUrl(url);
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

  Future<void> openSource() async {
    if (article.feedId.isEmpty) return;
    if (Platform.isMacOS) {
      final tc = Get.find<TimelineController>();
      tc.setTimelineScope(feedId: article.feedId);
      return;
    }
    Get.toNamed(
      Routes.feedDetail,
      arguments: {'feedId': article.feedId, 'feedTitle': article.feedTitle},
    );
  }

  void openImagePreview(String imageUrl, BuildContext context) {
    Navigator.of(context).push(
      HeroDialogRoute(
        builder: (context) => ImageGalleryPage(
          articleId: article.entryId,
          imageUrls: imageUrls,
          initialIndex: imageUrls
              .indexOf(imageUrl)
              .clamp(0, imageUrls.length - 1),
        ),
      ),
    );
  }
}

// ─── 路由参数解析 ───────────────────────────────

class _ArticleRouteRequest {
  final ArticleModel article;
  final List<ArticleModel>? sequence;
  final int index;

  const _ArticleRouteRequest({
    required this.article,
    this.sequence,
    this.index = 0,
  });

  bool get hasSequence => sequence != null && sequence!.length > 1;

  static _ArticleRouteRequest fromArguments(dynamic arguments) {
    if (arguments is ArticleModel) {
      return _ArticleRouteRequest(article: arguments);
    }

    if (arguments is Map) {
      final article = arguments['article'];
      final sequence = arguments['sequence'];
      final index = arguments['index'];
      if (article is ArticleModel) {
        final items = sequence is List<ArticleModel> ? sequence : null;
        final safeIndex = index is int && index >= 0
            ? index.clamp(0, (items?.length ?? 1) - 1).toInt()
            : 0;
        return _ArticleRouteRequest(
          article: article,
          sequence: items,
          index: safeIndex,
        );
      }
    }

    throw StateError('Invalid article route arguments');
  }
}

class ArticleSourceOpenRequest {
  final ArticleModel article;
  final double articleScrollOffset;
  final bool showTranslation;
  final bool showSummary;

  const ArticleSourceOpenRequest({
    required this.article,
    required this.articleScrollOffset,
    required this.showTranslation,
    required this.showSummary,
  });
}

// ─── 入口页（处理分页器） ───────────────────────

class ArticlePage extends StatelessWidget {
  const ArticlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final request = _ArticleRouteRequest.fromArguments(Get.arguments);
    if (request.sequence != null && request.sequence!.length > 1) {
      return _ArticlePagerPage(request: request);
    }
    return ArticlePageView(article: request.article);
  }
}

// ─── 分页器（多篇文章左右滑动） ──────────────────

class _ArticlePagerPage extends StatefulWidget {
  final _ArticleRouteRequest request;
  const _ArticlePagerPage({required this.request});

  @override
  State<_ArticlePagerPage> createState() => _ArticlePagerPageState();
}

class _ArticlePagerPageState extends State<_ArticlePagerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.request.index;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articles = widget.request.sequence!;
    return PageView.builder(
      controller: _pageController,
      allowImplicitScrolling: true,
      itemCount: articles.length,
      onPageChanged: (index) {
        _currentIndex = index;
      },
      itemBuilder: (context, index) => ArticlePageView(
        key: ValueKey(articles[index].entryId),
        article: articles[index],
        pageLabel: '${index + 1} / ${articles.length}',
      ),
    );
  }
}

// ─── 文章视图（核心） ───────────────────────────

class ArticlePageView extends StatefulWidget {
  final ArticleModel article;
  final String? pageLabel;
  final bool isSplitView;
  final VoidCallback? onClose;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onMKeyPressed;
  final VoidCallback? onOpenOriginalAndMarkRead;
  final bool Function()? isActive;
  final bool Function(String entryId)? isSelectedArticle;
  final bool isReviewContext;
  final VoidCallback? onKeepReviewArticle;
  final ValueChanged<ArticleSourceOpenRequest>? onOpenSource;
  final double? initialScrollOffset;
  final bool? initialShowTranslation;
  final bool? initialShowSummary;

  const ArticlePageView({
    super.key,
    required this.article,
    this.pageLabel,
    this.isSplitView = false,
    this.onClose,
    this.onPrevious,
    this.onNext,
    this.onMKeyPressed,
    this.onOpenOriginalAndMarkRead,
    this.isActive,
    this.isSelectedArticle,
    this.isReviewContext = false,
    this.onKeepReviewArticle,
    this.onOpenSource,
    this.initialScrollOffset,
    this.initialShowTranslation,
    this.initialShowSummary,
  });

  @override
  State<ArticlePageView> createState() => _ArticlePageViewState();
}

class _ArticlePageViewState extends State<ArticlePageView> {
  static const double _macToolbarButtonSize = 34;
  static const double _macToolbarButtonGap = 8;
  static const double _macToolbarButtonRightInset = 10;
  static const double _articleTitleTopOffset = 20;

  late final String _tag;
  late final ArticleController controller;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;
  final GlobalKey _articleTitleKey = GlobalKey();

  // 1. 改为使用 ValueNotifier 以实现局部刷新
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0.0);
  final ValueNotifier<double> _headerCollapseProgress = ValueNotifier(0.0);
  final ValueNotifier<String?> _hoveredUrl = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _activeTocId = ValueNotifier<String?>(null);
  double _articleTitleHeight = 30.0;
  bool _articleTitleMeasurementScheduled = false;
  bool _allowBodyBuild = Platform.isMacOS;
  bool _isTocOpen = false;
  bool _isCopyingMarkdown = false;
  bool _activeTocUpdateScheduled = false;
  final Map<String, GlobalKey> _headingKeys = {};
  final Map<String, String> _headingTextCache = {};
  final Map<String, List<_ArticleTocEntry>> _tocEntriesCache = {};
  Worker? _menuStateWorker;
  Worker? _initialViewRestoreWorker;
  double? _pendingInitialScrollOffset;
  late final bool? _initialShowTranslation;
  late final bool? _initialShowSummary;

  @override
  void initState() {
    super.initState();
    _tag = widget.article.entryId;
    controller = Get.put(ArticleController(widget.article), tag: _tag);
    if (Platform.isMacOS) {
      _registerMacOSMenuTarget();
      _menuStateWorker = everAll(<RxInterface<dynamic>>[
        controller.isRead,
        controller.isTranslated,
        controller.showTranslation,
        controller.isTranslating,
        controller.isSummarized,
        controller.showSummary,
        controller.isSummarizing,
      ], (_) => MacOSAppMenuService.instance.notifyChanged());
    }
    _scrollController = ScrollController();
    _pendingInitialScrollOffset = widget.initialScrollOffset;
    _initialShowTranslation = widget.initialShowTranslation;
    _initialShowSummary = widget.initialShowSummary;
    _scrollController.addListener(_handleArticleScroll);
    _focusNode = FocusNode();
    LocalArticleDbService.recordReadHistory(widget.article.entryId);
    ArticleImageCacheService.markArticleActive(widget.article.entryId);
    if (_usesGlobalShortcuts) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    }
    if (!Platform.isMacOS) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() => _allowBodyBuild = true);
        }
      });
    }
    // 请求焦点以确保方向键导航生效，防止焦点落在 SelectionArea 內容上
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _restoreInitialViewState();
      }
    });
    if (_pendingInitialScrollOffset != null ||
        _initialShowTranslation != null ||
        _initialShowSummary != null) {
      _initialViewRestoreWorker = ever(
        controller.isParsingContent,
        (_) => _restoreInitialViewState(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleArticleTitleMeasurement();
  }

  void _scheduleArticleTitleMeasurement() {
    if (_articleTitleMeasurementScheduled ||
        !Platform.isMacOS ||
        !widget.isSplitView) {
      return;
    }
    _articleTitleMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _articleTitleMeasurementScheduled = false;
      if (!mounted) return;
      final renderObject = _articleTitleKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      _articleTitleHeight = renderObject.size.height;
      _updateHeaderCollapseProgress();
    });
  }

  @override
  void dispose() {
    if (_usesGlobalShortcuts) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    }
    if (Platform.isMacOS) {
      MacOSAppMenuService.instance.unregisterArticleTarget(this);
      _menuStateWorker?.dispose();
    }
    _initialViewRestoreWorker?.dispose();
    _scrollController.dispose();
    _scrollProgress.dispose();
    _headerCollapseProgress.dispose();
    _hoveredUrl.dispose();
    _activeTocId.dispose();
    _focusNode.dispose();
    ArticleImageCacheService.markArticleInactive(widget.article.entryId);
    if (Get.isRegistered<ArticleController>(tag: _tag)) {
      Get.delete<ArticleController>(tag: _tag);
    }
    super.dispose();
  }

  bool get _usesGlobalShortcuts => Platform.isMacOS && widget.isSplitView;

  void _restoreInitialViewState() {
    if (!mounted || controller.isParsingContent.value) return;

    final showTranslation = _initialShowTranslation;
    if (showTranslation != null && controller.isTranslated.value) {
      controller.showTranslation.value = showTranslation;
    }
    final showSummary = _initialShowSummary;
    if (showSummary != null && controller.isSummarized.value) {
      controller.showSummary.value = showSummary;
    }

    final targetOffset = _pendingInitialScrollOffset;
    if (targetOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(target.toDouble());
      _pendingInitialScrollOffset = null;
      _initialViewRestoreWorker?.dispose();
      _initialViewRestoreWorker = null;
    });
  }

  void _openSource() {
    final callback = widget.onOpenSource;
    if (callback == null) {
      unawaited(controller.openSource());
      return;
    }
    callback(
      ArticleSourceOpenRequest(
        article: controller.article,
        articleScrollOffset: _scrollController.hasClients
            ? _scrollController.offset
            : 0,
        showTranslation: controller.showTranslation.value,
        showSummary: controller.showSummary.value,
      ),
    );
  }

  void _registerMacOSMenuTarget() {
    MacOSAppMenuService.instance.registerArticleTarget(
      this,
      MacOSArticleMenuTarget(
        article: widget.article,
        isActive: () {
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
            return false;
          }
          if (widget.isActive != null && !widget.isActive!()) return false;
          final isSelected = widget.isSelectedArticle;
          return isSelected == null || isSelected(widget.article.entryId);
        },
        isRead: () => controller.isRead.value,
        isReviewContext: widget.isReviewContext,
        canGoPrevious: () => widget.onPrevious != null,
        canGoNext: () => widget.onNext != null,
        openOriginal: () => unawaited(controller.openInBrowser()),
        copyMarkdown: () => unawaited(_copyOriginalArticleMarkdown()),
        performPrimaryAction: () {
          if (widget.onMKeyPressed != null) {
            widget.onMKeyPressed!();
          } else {
            _toggleReadState();
          }
        },
        goPrevious: () => widget.onPrevious?.call(),
        goNext: () => widget.onNext?.call(),
        performTranslationAction: () {
          if (controller.isTranslating.value) return null;
          return controller.isTranslated.value
              ? controller.showTranslation.toggle
              : () => unawaited(controller.translateArticle());
        },
        translationLabel: () {
          if (controller.isTranslating.value) return '翻译中…';
          if (!controller.isTranslated.value) return '翻译';
          return controller.showTranslation.value ? '隐藏译文' : '显示译文';
        },
        performSummaryAction: () {
          if (controller.isSummarizing.value) return null;
          return controller.isSummarized.value
              ? controller.showSummary.toggle
              : () => unawaited(controller.summarizeArticle());
        },
        summaryLabel: () {
          if (controller.isSummarizing.value) return '摘要中…';
          if (!controller.isSummarized.value) return '摘要';
          return controller.showSummary.value ? '隐藏摘要' : '显示摘要';
        },
        keepReviewArticle: widget.onKeepReviewArticle,
      ),
    );
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (!mounted) return false;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) {
      return false;
    }

    if (widget.isActive != null && !widget.isActive!()) {
      return false;
    }

    // 只有当前组件对应外层页面选中的文章时才响应快捷键，避免同一路由内
    // 已失活的分栏 ArticlePageView 残留监听器误处理按键。
    final isSelectedArticle = widget.isSelectedArticle;
    if (isSelectedArticle != null &&
        !isSelectedArticle(widget.article.entryId)) {
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _closeArticle();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft && widget.onPrevious != null) {
      if (_hasShortcutModifierPressed()) return false;
      widget.onPrevious!();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight && widget.onNext != null) {
      if (_hasShortcutModifierPressed()) return false;
      widget.onNext!();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_hasShortcutModifierPressed()) return false;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.offset - 150,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_hasShortcutModifierPressed()) return false;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.offset + 150,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
      return true;
    }

    if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyRepeatEvent) return true;
      if (widget.onMKeyPressed != null) {
        widget.onMKeyPressed!();
        return true;
      }
      if (controller.isUpdatingReadState.value) return true;
      final wasUnread = !controller.isRead.value;
      _toggleReadState();
      if (wasUnread && widget.onNext != null) {
        widget.onNext!();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.keyC) {
      if (_hasShortcutModifierPressed()) return false;
      if (event is KeyRepeatEvent) return true;
      _copyOriginalArticleMarkdown();
      return true;
    }

    if (key == LogicalKeyboardKey.keyB) {
      if (event is KeyRepeatEvent) return true;
      final keyboard = HardwareKeyboard.instance;
      final hasNonShiftModifier =
          keyboard.isAltPressed ||
          keyboard.isControlPressed ||
          keyboard.isMetaPressed;
      if (hasNonShiftModifier) return false;

      if (keyboard.isShiftPressed) {
        final combinedAction = widget.onOpenOriginalAndMarkRead;
        if (combinedAction != null) {
          combinedAction();
        } else {
          final wasUnread = !controller.isRead.value;
          if (wasUnread && !controller.isUpdatingReadState.value) {
            unawaited(controller.markAsRead(showSuccess: false));
            widget.onNext?.call();
          }
          unawaited(controller.openInBrowser());
        }
      } else {
        unawaited(controller.openInBrowser());
      }
      return true;
    }

    return false;
  }

  bool _hasShortcutModifierPressed() {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  void _closeArticle() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Get.back();
    }
  }

  void _toggleReadState() {
    if (controller.isUpdatingReadState.value) return;
    if (controller.isRead.value) {
      controller.markAsUnread();
    } else {
      controller.markAsRead();
    }
  }

  void _updateScrollProgress(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return;

    final maxScroll = metrics.maxScrollExtent;
    final currentScroll = metrics.pixels;
    double nextProgress;
    if (maxScroll > 0) {
      nextProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
    } else if (metrics.hasContentDimensions) {
      nextProgress = 1.0;
    } else {
      return;
    }
    if (_scrollProgress.value != nextProgress) {
      _scrollProgress.value = nextProgress;
    }
  }

  void _handleArticleScroll() {
    _scheduleActiveTocUpdate();
    if (!Platform.isMacOS || !widget.isSplitView) return;

    _updateHeaderCollapseProgress();
  }

  void _updateHeaderCollapseProgress() {
    if (!Platform.isMacOS || !widget.isSplitView) return;

    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final transitionStart = _articleTitleTopOffset + _articleTitleHeight * 0.82;
    final transitionEnd = _articleTitleTopOffset + _articleTitleHeight + 14;
    final nextProgress =
        ((offset - transitionStart) / (transitionEnd - transitionStart)).clamp(
          0.0,
          1.0,
        );
    if (_headerCollapseProgress.value != nextProgress) {
      _headerCollapseProgress.value = nextProgress;
    }
  }

  double _articleContentMaxWidth(double availableWidth) {
    if (!Platform.isMacOS) return availableWidth;

    final raw = GStorage.setting.get(
      StorageKeys.articleContentMaxWidth,
      defaultValue: AppConstants.defaultArticleContentMaxWidth,
    );
    final configured = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    final width = configured ?? AppConstants.defaultArticleContentMaxWidth;
    return math.min(availableWidth, width.clamp(480, 1200).toDouble());
  }

  String _tocIdFor(bool showTranslation, int index) {
    return '${showTranslation ? "trans" : "orig"}_$index';
  }

  GlobalKey _headingKeyFor(bool showTranslation, int index) {
    final key = _tocIdFor(showTranslation, index);
    return _headingKeys.putIfAbsent(key, GlobalKey.new);
  }

  List<_ArticleTocEntry> _tocEntriesFor(
    List<HtmlChunk> chunks,
    bool showTranslation,
  ) {
    final cacheKey = _tocEntriesCacheKey(chunks, showTranslation);
    final cached = _tocEntriesCache[cacheKey];
    if (cached != null) return cached;

    final entries = <_ArticleTocEntry>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (chunk.type != HtmlChunkType.heading) continue;
      final title = _plainHeadingText(chunk.content);
      if (title.isEmpty) continue;
      entries.add(
        _ArticleTocEntry(
          id: _tocIdFor(showTranslation, i),
          key: _headingKeyFor(showTranslation, i),
          title: title,
          level: chunk.headingLevel ?? 2,
        ),
      );
    }
    _tocEntriesCache
      ..clear()
      ..[cacheKey] = entries;
    return entries;
  }

  String _tocEntriesCacheKey(List<HtmlChunk> chunks, bool showTranslation) {
    final buffer = StringBuffer(showTranslation ? 'trans' : 'orig')
      ..write('|')
      ..write(chunks.length);
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (chunk.type != HtmlChunkType.heading) continue;
      buffer
        ..write('|')
        ..write(i)
        ..write(':')
        ..write(chunk.headingLevel ?? 2)
        ..write(':')
        ..write(chunk.content.length)
        ..write(':')
        ..write(chunk.content);
    }
    return buffer.toString();
  }

  String _plainHeadingText(String html) {
    final cached = _headingTextCache[html];
    if (cached != null) return cached;
    final text = html_parser.parseFragment(html).text ?? '';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    _headingTextCache[html] = normalized;
    return normalized;
  }

  double _tocAnchorY() {
    return MediaQuery.paddingOf(context).top + kToolbarHeight + 24;
  }

  double _macToolbarButtonTop(BuildContext context) {
    return MediaQuery.paddingOf(context).top +
        (kToolbarHeight - _macToolbarButtonSize) / 2;
  }

  double get _macTocButtonRight {
    return _macToolbarButtonRightInset +
        _macToolbarButtonSize * 2 +
        _macToolbarButtonGap * 2;
  }

  Future<void> _showMobileToc(List<_ArticleTocEntry> entries) async {
    if (entries.isEmpty || !mounted) return;

    setState(() => _isTocOpen = true);
    _updateActiveTocEntry();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = math.min(
      screenHeight * 0.72,
      76.0 + entries.length * 48.0,
    );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final controls = appGlassControlPalette(sheetContext);
        return AppMobileGlassSheet(
          height: panelHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_list_bulleted_rounded,
                      size: 20,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '目录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭目录',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.28),
              ),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: _activeTocId,
                  builder: (context, activeTocId, child) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final active = entry.id == activeTocId;
                        final indent = ((entry.level - 1).clamp(0, 3)) * 14.0;
                        return Padding(
                          padding: EdgeInsets.only(left: indent, bottom: 2),
                          child: Material(
                            color: active
                                ? controls.activeFill(accentAlpha: 0.05)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                unawaited(_scrollToTocEntry(entry));
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    entry.title,
                                    style: TextStyle(
                                      fontSize: entry.level <= 2 ? 14 : 13,
                                      height: 1.35,
                                      fontWeight: active
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: active
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (mounted) setState(() => _isTocOpen = false);
  }

  Future<void> _copyOriginalArticleMarkdown() async {
    if (_isCopyingMarkdown) return;
    final chunks = controller.chunks.toList(growable: false);
    if (chunks.isEmpty) {
      AppFeedback.warning('暂无可复制正文', '当前文章还没有已加载的原文内容');
      return;
    }

    _isCopyingMarkdown = true;
    try {
      final markdown = await ArticleMarkdownExportService.buildArticleAsync(
        article: controller.article,
        chunks: chunks,
      );
      if (markdown.trim().isEmpty) {
        AppFeedback.warning('暂无可复制正文', '当前文章还没有可复制的原文内容');
        return;
      }
      await Clipboard.setData(ClipboardData(text: markdown));
      AppFeedback.success('已复制原文', 'Markdown 已复制到剪贴板');
    } catch (e) {
      AppFeedback.error('复制失败', e.toString());
    } finally {
      _isCopyingMarkdown = false;
    }
  }

  Future<void> _scrollToTocEntry(_ArticleTocEntry entry) async {
    final targetContext = entry.key.currentContext;
    if (targetContext == null) return;
    _activeTocId.value = entry.id;

    final renderObject = targetContext.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        _scrollController.hasClients) {
      final currentOffset = _scrollController.offset;
      final targetGlobalY = renderObject.localToGlobal(Offset.zero).dy;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = (currentOffset + targetGlobalY - _tocAnchorY()).clamp(
        0.0,
        maxExtent,
      );
      final distance = (target - currentOffset).abs();
      final durationMs = (180 + distance / 2400 * 240)
          .clamp(180.0, 420.0)
          .round();
      await _scrollController.animateTo(
        target,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        alignment: 0.08,
      );
    }
    if (mounted) {
      _focusNode.requestFocus();
      _scheduleActiveTocUpdate();
    }
  }

  List<_ArticleTocEntry> _currentTocEntries() {
    final showTrans =
        controller.showTranslation.value &&
        controller.translatedChunks.isNotEmpty;
    final activeChunks = showTrans
        ? controller.translatedChunks
        : controller.chunks;
    return _tocEntriesFor(activeChunks, showTrans);
  }

  void _scheduleActiveTocUpdate() {
    if (!Platform.isMacOS ||
        !mounted ||
        _activeTocUpdateScheduled ||
        !_scrollController.hasClients) {
      return;
    }
    _activeTocUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeTocUpdateScheduled = false;
      if (mounted) {
        _updateActiveTocEntry();
      }
    });
  }

  void _updateActiveTocEntry() {
    if (!_scrollController.hasClients) return;
    final entries = _currentTocEntries();
    if (entries.isEmpty) {
      if (_activeTocId.value != null) {
        _activeTocId.value = null;
      }
      return;
    }

    final referenceY = _tocAnchorY();
    String? activeId;
    var bestPastY = double.negativeInfinity;
    String? firstFutureId;
    var firstFutureY = double.infinity;

    for (final entry in entries) {
      final entryContext = entry.key.currentContext;
      final renderObject = entryContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final y = renderObject.localToGlobal(Offset.zero).dy;
      if (y <= referenceY && y > bestPastY) {
        activeId = entry.id;
        bestPastY = y;
      } else if (y > referenceY && y < firstFutureY) {
        firstFutureId = entry.id;
        firstFutureY = y;
      }
    }

    activeId ??= firstFutureId;
    if (_activeTocId.value != activeId) {
      _activeTocId.value = activeId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = _articleContentMaxWidth(screenWidth - 22);

    Widget articleBody = SelectionArea(
      child: Padding(
        padding: Platform.isMacOS
            ? const EdgeInsets.only(bottom: 8)
            : EdgeInsets.zero,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _updateScrollProgress(notification.metrics);
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ─── 元数据区域 ──────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(11, 16, 11, 16),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: controller.openInBrowser,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    controller.article.title,
                                    key: _articleTitleKey,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 元数据
                          _MetadataSection(
                            controller: controller,
                            cs: colorScheme,
                            onOpenSource: _openSource,
                          ),
                          const SizedBox(height: 8),

                          if (controller.article.publishedAt.isNotEmpty)
                            Text(
                              '发布于: ${controller.article.publishedAt}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),

                          const Divider(height: 24),

                          _ToolbarRow(controller: controller),
                          _SummaryCard(controller: controller),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // （已删除：高度为 0 的隐藏预加载栈代码）

              // ─── 正文区域：逐块渲染 ──────────────
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                sliver: Obx(() {
                  if (controller.isParsingContent.value || !_allowBodyBuild) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 64),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '正在排版内容…',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final activeChunks =
                      controller.showTranslation.value &&
                          controller.translatedChunks.isNotEmpty
                      ? controller.translatedChunks
                      : controller.chunks;

                  if (activeChunks.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: controller.isFetchingContent.value
                            ? Column(
                                children: [
                                  const SizedBox(height: 32),
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '正在加载正文…',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Icon(
                                    Icons.article_outlined,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '暂无正文内容',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (controller.article.url.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.open_in_browser,
                                        size: 18,
                                      ),
                                      label: const Text('在浏览器中查看原文'),
                                      onPressed: () =>
                                          controller.openInBrowser(),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    );
                  }

                  final totalChunks = activeChunks.length;
                  final showTrans = controller.showTranslation.value;

                  return SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: List.generate(totalChunks, (idx) {
                            final chunk = activeChunks[idx];
                            final card = HtmlChunkCard(
                              key: ValueKey(
                                '${showTrans ? "trans" : "orig"}_$idx',
                              ),
                              chunk: chunk,
                              articleId: controller.article.entryId,
                              articleUrl: controller.article.url,
                              maxWidth: maxWidth,
                              hoveredUrl: _hoveredUrl,
                              contentAnchorKey:
                                  chunk.type == HtmlChunkType.heading
                                  ? _headingKeyFor(showTrans, idx)
                                  : null,
                              onImageTap: (url) =>
                                  controller.openImagePreview(url, context),
                            );
                            return card;
                          }),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // 移动端按实际操作按钮数量避让，避免正文被悬浮控件遮挡。
              if (Platform.isMacOS)
                const SliverPadding(padding: EdgeInsets.only(bottom: 16))
              else
                Obx(() {
                  final showTrans =
                      controller.showTranslation.value &&
                      controller.translatedChunks.isNotEmpty;
                  final activeChunks = showTrans
                      ? controller.translatedChunks
                      : controller.chunks;
                  final hasToc = _tocEntriesFor(
                    activeChunks,
                    showTrans,
                  ).isNotEmpty;
                  return SliverPadding(
                    padding: EdgeInsets.only(bottom: hasToc ? 144 : 88),
                  );
                }),
            ],
          ),
        ),
      ),
    );

    if (Platform.isMacOS && widget.isSplitView) {
      articleBody = ClipPath(
        clipper: const _MacSplitArticleCornerClipper(),
        clipBehavior: Clip.antiAlias,
        child: articleBody,
      );
      articleBody = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: articleBody,
      );
    }

    final usesCollapsibleMacHeader = Platform.isMacOS && widget.isSplitView;
    final headerRule = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ValueListenableBuilder<double>(
          valueListenable: _scrollProgress,
          builder: (context, progress, child) {
            return FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: colorScheme.primary),
            );
          },
        ),
      ],
    );

    Widget scaffold = Scaffold(
      appBar: AppBar(
        title: usesCollapsibleMacHeader
            ? ValueListenableBuilder<double>(
                valueListenable: _headerCollapseProgress,
                builder: (context, progress, child) {
                  final eased = Curves.easeOutCubic.transform(progress);
                  return Opacity(
                    opacity: eased,
                    child: Transform.translate(
                      offset: Offset(0, (1 - eased) * 6),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: _macToolbarButtonSize + _macToolbarButtonGap,
                  ),
                  child: Text(
                    controller.article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              )
            : Text(
                widget.pageLabel ?? '文章详情',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.0,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
        centerTitle: !usesCollapsibleMacHeader,
        titleSpacing: usesCollapsibleMacHeader ? 11 : null,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: Platform.isMacOS
            ? [
                Obx(() {
                  final isRead = controller.isRead.value;
                  final isUpdating = controller.isUpdatingReadState.value;
                  return Padding(
                    padding: const EdgeInsets.only(
                      right: _macToolbarButtonRightInset,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppGlassIconButton(
                          icon: Icons.content_copy_rounded,
                          tooltip: '复制原文全文 (C)',
                          onPressed: _copyOriginalArticleMarkdown,
                        ),
                        const SizedBox(width: _macToolbarButtonGap),
                        AppGlassIconButton(
                          icon: isRead
                              ? Icons.undo
                              : Icons.check_circle_outline,
                          tooltip: isRead ? '恢复未读' : '标为已读 (M)',
                          selected: !isRead,
                          onPressed: isUpdating
                              ? null
                              : () {
                                  if (isRead) {
                                    controller.markAsUnread();
                                  } else {
                                    if (widget.onMKeyPressed != null) {
                                      widget.onMKeyPressed!();
                                    } else {
                                      controller.markAsRead();
                                      if (widget.onNext != null) {
                                        widget.onNext!();
                                      }
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  );
                }),
              ]
            : const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: SizedBox(
            width: double.infinity,
            height: 1.0,
            child: usesCollapsibleMacHeader
                ? ValueListenableBuilder<double>(
                    valueListenable: _headerCollapseProgress,
                    child: headerRule,
                    builder: (context, progress, child) {
                      return Opacity(
                        opacity: Curves.easeOutCubic.transform(progress),
                        child: child,
                      );
                    },
                  )
                : headerRule,
          ),
        ),
      ),
      floatingActionButton: Platform.isMacOS
          ? null
          : Obx(() {
              final isRead = controller.isRead.value;
              final isUpdating = controller.isUpdatingReadState.value;
              final showTrans =
                  controller.showTranslation.value &&
                  controller.translatedChunks.isNotEmpty;
              final activeChunks = showTrans
                  ? controller.translatedChunks
                  : controller.chunks;
              final entries = _tocEntriesFor(activeChunks, showTrans);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entries.isNotEmpty) ...[
                    AppGlassIconButton(
                      icon: Symbols.format_list_bulleted_rounded,
                      tooltip: '目录',
                      size: 48,
                      iconSize: 24,
                      iconWeight: 700,
                      onPressed: () => _showMobileToc(entries),
                    ),
                    const SizedBox(height: 8),
                  ],
                  AppGlassIconButton(
                    icon: isRead ? Symbols.undo_rounded : Symbols.check_rounded,
                    tooltip: isRead ? '恢复未读' : '标为已读',
                    selected: !isRead,
                    size: 48,
                    iconSize: 24,
                    iconWeight: 700,
                    onPressed: isUpdating
                        ? null
                        : () {
                            if (isRead) {
                              controller.markAsUnread();
                            } else if (widget.onMKeyPressed != null) {
                              widget.onMKeyPressed!();
                            } else {
                              controller.markAsRead();
                              widget.onNext?.call();
                            }
                          },
                  ),
                ],
              );
            }),
      body: articleBody,
    );

    final result = Stack(
      children: [
        scaffold,
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<String?>(
            valueListenable: _hoveredUrl,
            builder: (context, url, child) {
              if (url == null || url.isEmpty) return const SizedBox.shrink();
              return Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        url,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (Platform.isMacOS && _isTocOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _isTocOpen = false),
            ),
          ),
        if (Platform.isMacOS)
          Obx(() {
            final showTrans =
                controller.showTranslation.value &&
                controller.translatedChunks.isNotEmpty;
            final activeChunks = showTrans
                ? controller.translatedChunks
                : controller.chunks;
            final entries = _tocEntriesFor(activeChunks, showTrans);
            if (entries.isEmpty) return const SizedBox.shrink();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scheduleActiveTocUpdate();
              }
            });
            return Positioned(
              top: _macToolbarButtonTop(context),
              right: _macTocButtonRight,
              child: ValueListenableBuilder<String?>(
                valueListenable: _activeTocId,
                builder: (context, activeTocId, child) {
                  return _ArticleTocOverlay(
                    entries: entries,
                    activeTocId: activeTocId,
                    isOpen: _isTocOpen,
                    onToggle: () => setState(() => _isTocOpen = !_isTocOpen),
                    onEntryTap: _scrollToTocEntry,
                  );
                },
              ),
            );
          }),
      ],
    );

    return Platform.isMacOS
        ? Focus(
            focusNode: _focusNode,
            onKeyEvent: (node, event) {
              if (_usesGlobalShortcuts) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.keyM ||
                      (key == LogicalKeyboardKey.keyC &&
                          !_hasShortcutModifierPressed())) {
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft ||
                      key == LogicalKeyboardKey.arrowRight ||
                      key == LogicalKeyboardKey.arrowUp ||
                      key == LogicalKeyboardKey.arrowDown) {
                    if (_hasShortcutModifierPressed()) {
                      return KeyEventResult.ignored;
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              }

              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }

              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _closeArticle();
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                  widget.onPrevious != null) {
                widget.onPrevious!();
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                  widget.onNext != null) {
                widget.onNext!();
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.keyM) {
                _toggleReadState();
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.keyC &&
                  !_hasShortcutModifierPressed()) {
                _copyOriginalArticleMarkdown();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: result,
          )
        : result;
  }
}

class _MacSplitArticleCornerClipper extends CustomClipper<Path> {
  static const _outerRadius = 24.0;
  static const _safeInset = 8.0;

  const _MacSplitArticleCornerClipper();

  @override
  Path getClip(Size size) {
    final width = math.max(0.0, size.width - _safeInset);
    final height = math.max(0.0, size.height - _safeInset);
    final radius = math.max(0.0, _outerRadius - _safeInset);
    final rect = Rect.fromLTWH(0, 0, width, height);
    return Path()..addRRect(
      RRect.fromRectAndCorners(rect, bottomRight: Radius.circular(radius)),
    );
  }

  @override
  bool shouldReclip(covariant _MacSplitArticleCornerClipper oldClipper) {
    return false;
  }
}

// ─── 小型辅助组件 ─────────────────────────────

class _ArticleTocEntry {
  final String id;
  final GlobalKey key;
  final String title;
  final int level;

  const _ArticleTocEntry({
    required this.id,
    required this.key,
    required this.title,
    required this.level,
  });
}

class _ArticleTocOverlay extends StatefulWidget {
  final List<_ArticleTocEntry> entries;
  final String? activeTocId;
  final bool isOpen;
  final VoidCallback onToggle;
  final ValueChanged<_ArticleTocEntry> onEntryTap;

  const _ArticleTocOverlay({
    required this.entries,
    required this.activeTocId,
    required this.isOpen,
    required this.onToggle,
    required this.onEntryTap,
  });

  @override
  State<_ArticleTocOverlay> createState() => _ArticleTocOverlayState();
}

class _ArticleTocOverlayState extends State<_ArticleTocOverlay>
    with SingleTickerProviderStateMixin {
  static const double _buttonSize = 34;
  static const double _panelWidth = 304;
  static const double _panelMaxHeight = 430;
  late final glass.GlassMorphController _morphController;
  late bool _showMorphLayer;

  @override
  void initState() {
    super.initState();
    _showMorphLayer = widget.isOpen;
    _morphController =
        glass.GlassMorphController(vsync: this, speed: glass.MorphSpeed.normal)
          ..addListener(() {
            if (!mounted) return;
            if (!widget.isOpen &&
                _showMorphLayer &&
                _morphController.hasHandedOff) {
              setState(() => _showMorphLayer = false);
              return;
            }
            if (_showMorphLayer) setState(() {});
          });
    if (widget.isOpen) {
      _morphController.open();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _morphController.setDisableAnimations(
      MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didUpdateWidget(covariant _ArticleTocOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _showMorphLayer = true;
        _morphController.open();
      } else {
        _morphController.close();
      }
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tocGlassSettings = appGlassSettingsFor(context, AppGlassTone.control);
    final estimatedRowsHeight = widget.entries.fold<double>(
      0,
      (sum, entry) => sum + _estimatedTocRowHeight(entry),
    );
    final panelHeight = math
        .min(_panelMaxHeight, 66 + estimatedRowsHeight)
        .clamp(112.0, _panelMaxHeight);

    return SizedBox(
      width: _panelWidth,
      height: panelHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_showMorphLayer)
            _ArticleTocMorphLayer(
              panelWidth: _panelWidth,
              panelHeight: panelHeight,
              buttonSize: _buttonSize,
              morphController: _morphController,
              entries: widget.entries,
              activeTocId: widget.activeTocId,
              onToggle: widget.onToggle,
              onEntryTap: widget.onEntryTap,
              glassSettings: tocGlassSettings,
            )
          else
            Positioned(
              top: 0,
              right: 0,
              child: AppGlassIconButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: '目录',
                onPressed: widget.onToggle,
              ),
            ),
        ],
      ),
    );
  }

  double _estimatedTocRowHeight(_ArticleTocEntry entry) {
    final levelIndentChars = (entry.level - 1).clamp(0, 3) * 3;
    final effectiveChars = entry.title.length + levelIndentChars;
    return effectiveChars > 24 ? 54.0 : 38.0;
  }
}

class _ArticleTocMorphLayer extends StatefulWidget {
  final double panelWidth;
  final double panelHeight;
  final double buttonSize;
  final glass.GlassMorphController morphController;
  final List<_ArticleTocEntry> entries;
  final String? activeTocId;
  final VoidCallback onToggle;
  final ValueChanged<_ArticleTocEntry> onEntryTap;
  final glass.LiquidGlassSettings glassSettings;

  const _ArticleTocMorphLayer({
    required this.panelWidth,
    required this.panelHeight,
    required this.buttonSize,
    required this.morphController,
    required this.entries,
    required this.activeTocId,
    required this.onToggle,
    required this.onEntryTap,
    required this.glassSettings,
  });

  @override
  State<_ArticleTocMorphLayer> createState() => _ArticleTocMorphLayerState();
}

class _ArticleTocMorphLayerState extends State<_ArticleTocMorphLayer> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawValue = widget.morphController.value;
    final effectiveValue =
        widget.morphController.isClosing && widget.morphController.hasHandedOff
        ? 0.0
        : rawValue;
    final clampedValue = effectiveValue.clamp(0.0, 1.0);
    final baseMorphT = widget.morphController.isClosing
        ? _anchoredCloseSettleT(clampedValue)
        : Curves.linearToEaseOut.transform(clampedValue);
    final elasticTail = widget.morphController.isClosing
        ? _anchoredCloseTail(clampedValue)
        : _anchoredOpenTail(clampedValue);
    final morphMin = widget.morphController.isClosing ? -0.014 : 0.0;
    final morphT = (baseMorphT + elasticTail).clamp(morphMin, 1.024);
    final currentWidth = lerpDouble(
      widget.buttonSize,
      widget.panelWidth,
      morphT,
    )!;
    final currentHeight = lerpDouble(
      widget.buttonSize,
      widget.panelHeight,
      morphT,
    )!;
    final maxRadius = math.min(currentWidth, currentHeight) / 2;
    final radiusT = Curves.easeOutCubic.transform(morphT.clamp(0.0, 1.0));
    final currentRadius = lerpDouble(maxRadius, 18, radiusT)!;
    final contentOpacity = ((clampedValue - 0.82) / 0.18).clamp(0.0, 1.0);
    final panelScrimOpacity = Curves.easeInOutCubic.transform(
      ((clampedValue - 0.48) / 0.52).clamp(0.0, 1.0),
    );
    final panelScrim = appGlassFloatingPanelScrim(context);
    final showContent =
        clampedValue > 0.82 && !widget.morphController.isClosing;
    final showTriggerIcon = clampedValue < 0.34;
    final triggerIconOpacity = (1 - clampedValue / 0.34).clamp(0.0, 1.0);
    final isIdle = clampedValue < 0.02 && !widget.morphController.isShowing;
    final idleScale = _isPressed ? 0.985 : 1.0;

    return glass.LiquidGlassLayer(
      settings: widget.glassSettings,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: MacOSWindowDragGuard(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() {
                  _isHovered = false;
                  _isPressed = false;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: clampedValue < 0.86
                      ? (_) => setState(() => _isPressed = true)
                      : null,
                  onTapUp: clampedValue < 0.86
                      ? (_) => setState(() => _isPressed = false)
                      : null,
                  onTapCancel: clampedValue < 0.86
                      ? () => setState(() => _isPressed = false)
                      : null,
                  onTap: clampedValue < 0.86 ? widget.onToggle : null,
                  child: AnimatedScale(
                    scale: isIdle ? idleScale : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    child: glass.GlassContainer(
                      width: currentWidth,
                      height: currentHeight,
                      useOwnLayer: false,
                      settings: widget.glassSettings,
                      quality: glass.GlassQuality.standard,
                      allowElevation: false,
                      glowIntensity: isIdle && _isHovered ? 0.14 : 0.0,
                      clipBehavior: Clip.antiAlias,
                      shape: glass.LiquidRoundedSuperellipse(
                        borderRadius: currentRadius,
                      ),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(currentRadius),
                          border: Border.all(
                            color: appGlassBorderColor(
                              context,
                              AppGlassTone.control,
                            ),
                            width: 0.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            if (panelScrimOpacity > 0)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: panelScrim.withValues(
                                      alpha: panelScrim.a * panelScrimOpacity,
                                    ),
                                  ),
                                ),
                              ),
                            if (showTriggerIcon)
                              Opacity(
                                opacity: triggerIconOpacity,
                                child: SizedBox(
                                  width: widget.buttonSize,
                                  height: widget.buttonSize,
                                  child: _TocIconButtonChrome(
                                    icon: Icons.format_list_bulleted_rounded,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            if (showContent)
                              Opacity(
                                opacity: contentOpacity,
                                child: IgnorePointer(
                                  ignoring: contentOpacity < 0.95,
                                  child: SizedBox(
                                    width: widget.panelWidth,
                                    height: widget.panelHeight,
                                    child: _ArticleTocPanelContent(
                                      entries: widget.entries,
                                      activeTocId: widget.activeTocId,
                                      onToggle: widget.onToggle,
                                      onEntryTap: widget.onEntryTap,
                                    ),
                                  ),
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
        ],
      ),
    );
  }

  double _anchoredOpenTail(double t) {
    const start = 0.42;
    if (t <= start || t >= 1.0) return 0.0;
    final u = ((t - start) / (1.0 - start)).clamp(0.0, 1.0);
    return math.sin(u * math.pi) * 0.028;
  }

  double _anchoredCloseSettleT(double t) {
    final progress = (1.0 - t).clamp(0.0, 1.0);
    const omega = 5.0;
    final settled =
        1.0 - (1.0 + omega * progress) * math.exp(-omega * progress);
    final normalizer = 1.0 - (1.0 + omega) * math.exp(-omega);
    return (1.0 - settled / normalizer).clamp(0.0, 1.0);
  }

  double _anchoredCloseTail(double t) {
    const end = 0.24;
    if (t <= 0.0 || t >= end) return 0.0;
    final u = (t / end).clamp(0.0, 1.0);
    return -math.sin(u * math.pi) * 0.032;
  }
}

class _ArticleTocPanelContent extends StatelessWidget {
  final List<_ArticleTocEntry> entries;
  final String? activeTocId;
  final VoidCallback onToggle;
  final ValueChanged<_ArticleTocEntry> onEntryTap;

  const _ArticleTocPanelContent({
    required this.entries,
    required this.activeTocId,
    required this.onToggle,
    required this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: [
              Icon(
                Icons.format_list_bulleted_rounded,
                size: 17,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '目录',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              _TocIconButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: '收起目录',
                onTap: onToggle,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.28)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final indent = ((entry.level - 1).clamp(0, 3)) * 12.0;
              return Padding(
                padding: EdgeInsets.only(
                  left: 8 + indent,
                  right: 8,
                  top: 1,
                  bottom: 1,
                ),
                child: _ArticleTocItem(
                  entry: entry,
                  isActive: entry.id == activeTocId,
                  onTap: () => onEntryTap(entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArticleTocItem extends StatefulWidget {
  final _ArticleTocEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  const _ArticleTocItem({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ArticleTocItem> createState() => _ArticleTocItemState();
}

class _ArticleTocItemState extends State<_ArticleTocItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final entry = widget.entry;
    final foreground = widget.isActive
        ? cs.primary
        : entry.level <= 2
        ? cs.onSurface
        : cs.onSurfaceVariant;
    final backgroundColor = controls.optionFill(
      selected: widget.isActive,
      hovered: _isHovered,
      pressed: _isPressed,
    );
    final borderColor = controls.optionBorder(
      selected: widget.isActive,
      hovered: _isHovered,
    );

    return Semantics(
      button: true,
      selected: widget.isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() {
            _isHovered = false;
            _isPressed = false;
          }),
          child: AnimatedScale(
            scale: _isPressed ? 0.985 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: _isPressed
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: entry.level <= 2 ? 13 : 12,
                  height: 1.25,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : entry.level <= 2
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TocIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TocIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_TocIconButton> createState() => _TocIconButtonState();
}

class _TocIconButtonState extends State<_TocIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final backgroundColor = controls.neutralOverlay(
      hovered: _isHovered,
      pressed: _isPressed,
      darkHoverAlpha: 0.09,
      lightHoverAlpha: 0.055,
      darkPressedAlpha: 0.14,
      lightPressedAlpha: 0.08,
    );

    return AppGlassTooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() {
            _isHovered = false;
            _isPressed = false;
          }),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: _isPressed
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(widget.icon, size: 18, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _TocIconButtonChrome extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _TocIconButtonChrome({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(icon, size: 18, color: color));
  }
}

class _MetadataSection extends StatelessWidget {
  final ArticleController controller;
  final ColorScheme cs;
  final VoidCallback? onOpenSource;
  const _MetadataSection({
    required this.controller,
    required this.cs,
    this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = controller.article.feedImage;
    return InkWell(
      onTap: controller.article.feedId.isEmpty
          ? null
          : onOpenSource ?? controller.openSource,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image(
                    image: CachedNetworkImageProvider(
                      ArticleImageService.toProxiedUrl(imageUrl) ?? imageUrl,
                    ),
                    width: 16,
                    height: 16,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.rss_feed,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: Text(
                controller.article.feedTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  final ArticleController controller;
  const _ToolbarRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final rec = TranslationService.recordOf(controller.article.entryId);
      final isPending =
          (rec?.isPending ?? false) || controller.isTranslating.value;
      final hasTranslation = controller.isTranslated.value;
      final summaryRecord = SummaryService.recordOf(controller.article.entryId);
      final isSummaryPending =
          (summaryRecord?.isPending ?? false) || controller.isSummarizing.value;
      final summary = (summaryRecord?.summaryText ?? '').trim();
      final hasSummary =
          summary.isNotEmpty &&
          ((summaryRecord?.isSummarized ?? false) ||
              controller.isSummarized.value);
      final isFetchingReadability = controller.isFetchingReadability.value;
      final showTranslation = controller.showTranslation.value;
      final showSummary = controller.showSummary.value;
      return _ArticlePillToolbarRow(
        controller: controller,
        isPending: isPending,
        hasTranslation: hasTranslation,
        showTranslation: showTranslation,
        isSummaryPending: isSummaryPending,
        hasSummary: hasSummary,
        showSummary: showSummary,
        isFetchingReadability: isFetchingReadability,
      );
    });
  }
}

class _ArticlePillToolbarRow extends StatelessWidget {
  final ArticleController controller;
  final bool isPending;
  final bool hasTranslation;
  final bool showTranslation;
  final bool isSummaryPending;
  final bool hasSummary;
  final bool showSummary;
  final bool isFetchingReadability;

  const _ArticlePillToolbarRow({
    required this.controller,
    required this.isPending,
    required this.hasTranslation,
    required this.showTranslation,
    required this.isSummaryPending,
    required this.hasSummary,
    required this.showSummary,
    required this.isFetchingReadability,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _ArticlePillActionChip(
        icon: showTranslation ? Icons.translate : Icons.translate_outlined,
        label: isPending
            ? '翻译中...'
            : hasTranslation
            ? showTranslation
                  ? '隐藏译文'
                  : '显示译文'
            : '翻译',
        active: showTranslation || isPending,
        onTap: isPending
            ? null
            : hasTranslation
            ? () => controller.showTranslation.toggle()
            : () => controller.translateArticle(),
      ),
      _ArticlePillActionChip(
        icon: hasSummary && showSummary
            ? Icons.summarize
            : Icons.summarize_outlined,
        label: isSummaryPending
            ? '摘要中...'
            : hasSummary
            ? showSummary
                  ? '隐藏摘要'
                  : '显示摘要'
            : '摘要',
        active: isSummaryPending || (hasSummary && showSummary),
        onTap: isSummaryPending
            ? null
            : hasSummary
            ? () => controller.showSummary.toggle()
            : () => controller.summarizeArticle(),
      ),
      if (isFetchingReadability)
        const _ArticlePillActionChip(
          icon: Icons.sync,
          label: '加载长文中...',
          active: true,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _ArticlePillActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ArticlePillActionChip({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  State<_ArticlePillActionChip> createState() => _ArticlePillActionChipState();
}

class _ArticlePillActionChipState extends State<_ArticlePillActionChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final enabled = widget.onTap != null;
    final foreground = widget.active ? cs.primary : cs.onSurfaceVariant;
    final background = controls.pillFill(active: widget.active);
    final borderColor = controls.pillBorder(
      active: widget.active,
      hovered: _hovered,
    );

    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: _pressed
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              constraints: BoxConstraints(
                minHeight: Platform.isMacOS ? 32 : 40,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: Platform.isMacOS ? 11 : 13,
                vertical: Platform.isMacOS ? 7 : 9,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: foreground),
                  const SizedBox(width: 5),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ArticleController controller;
  const _SummaryCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final record = SummaryService.recordOf(controller.article.entryId);
      final summary = (record?.summaryText ?? '').trim();
      if (!controller.showSummary.value) return const SizedBox.shrink();
      if (summary.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.10)
                : Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.summarize,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '文章摘要',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Html(
                data: summary,
                style: {
                  'body': Style(
                    fontSize: FontSize(14),
                    lineHeight: const LineHeight(1.5),
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                  ),
                  'a': Style(
                    color: Theme.of(context).colorScheme.primary,
                    textDecoration: TextDecoration.none,
                  ),
                },
                onLinkTap: (url, attributes, element) async {
                  if (url != null && url.isNotEmpty) {
                    final uri = Uri.tryParse(url);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}
