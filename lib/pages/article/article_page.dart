import 'package:cached_network_image/cached_network_image.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/constants/constants.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/liquid_glass/liquid_glass.dart' as glass;
import '../../services/article_image_service.dart';
import '../../services/local_article_db_service.dart';
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

  ArticleController(this.article);

  @override
  void onInit() {
    super.onInit();
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

  Future<void> _initContent({String? overrideContent}) async {
    isParsingContent.value = true;

    final rawHtml = overrideContent ?? article.content ?? '';
    final entryId = article.entryId;
    final hasTranslation = TranslationService.hasTranslation(entryId);
    final tContent = hasTranslation
        ? (TranslationService.translatedContentFor(entryId) ?? '')
        : '';

    try {
      final result = await Isolate.run(() {
        final normalized = ArticleContentUtils.normalizeHtml(rawHtml);
        final urls = ArticleContentUtils.extractImageUrls(normalized);
        final parsedChunks = HtmlChunkParser.parseSync(normalized);

        List<HtmlChunk> tParsedChunks = const [];
        if (hasTranslation && tContent.isNotEmpty) {
          tParsedChunks = HtmlChunkParser.parseSync(tContent);
        }

        return (
          normalizedContent: normalized,
          imageUrls: urls,
          chunks: parsedChunks,
          translatedChunks: tParsedChunks,
        );
      });

      normalizedContent = result.normalizedContent;
      imageUrls = result.imageUrls;
      chunks.value = result.chunks;

      if (hasTranslation) {
        isTranslated.value = true;
        translationContent.value = tContent;
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

  Future<void> _fetchInboxContent() async {
    final result = await FeedHttp.getInboxEntryDetail(entryId: article.entryId);
    if (result is Success<String> && result.response.isNotEmpty) {
      _initContent(overrideContent: result.response);
      // 持久化到本地，下次打开无需重复拉取
      LocalArticleDbService.upsertOne(
        ArticleModel(
          entryId: article.entryId,
          feedId: article.feedId,
          feedTitle: article.feedTitle,
          feedImage: article.feedImage,
          title: article.title,
          url: article.url,
          content: result.response,
          publishedAt: article.publishedAt,
          category: article.category,
          subscriptionCategory: article.subscriptionCategory,
          author: article.author,
          imageUrl: article.imageUrl,
          isRejectedByAi: article.isRejectedByAi,
          filterReason: article.filterReason,
          filterReviewed: article.filterReviewed,
          filteredAt: article.filteredAt,
        ),
      );
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
          _initContent(overrideContent: articleNode.outerHtml);
          // 持久化抓取结果，下次打开无需重复抓
          LocalArticleDbService.upsertOne(
            ArticleModel(
              entryId: article.entryId,
              feedId: article.feedId,
              feedTitle: article.feedTitle,
              feedImage: article.feedImage,
              title: article.title,
              url: article.url,
              content: articleNode.outerHtml,
              publishedAt: article.publishedAt,
              category: article.category,
              subscriptionCategory: article.subscriptionCategory,
              author: article.author,
              imageUrl: article.imageUrl,
              isRejectedByAi: article.isRejectedByAi,
              filterReason: article.filterReason,
              filterReviewed: article.filterReviewed,
              filteredAt: article.filteredAt,
            ),
          );
        }
      } catch (e) {
        // silently fail on auto-fetch
      } finally {
        isFetchingReadability.value = false;
        isFetchingContent.value = false;
      }
    });
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

    // 同步结束（无论成败），清理本次乐观更新留下的临时状态。
    ReadSyncService.removeMany([article.entryId]);
    GStorage.readStatus.delete(article.entryId);

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
        translationContent.value = record.translatedContent!;
        isTranslated.value = true;
        // 同步解析译文的块
        final tChunks = HtmlChunkParser.parseSync(record.translatedContent!);
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
  final bool Function()? isActive;
  final bool Function(String entryId)? isSelectedArticle;

  const ArticlePageView({
    super.key,
    required this.article,
    this.pageLabel,
    this.isSplitView = false,
    this.onClose,
    this.onPrevious,
    this.onNext,
    this.onMKeyPressed,
    this.isActive,
    this.isSelectedArticle,
  });

  @override
  State<ArticlePageView> createState() => _ArticlePageViewState();
}

class _ArticlePageViewState extends State<ArticlePageView> {
  static const double _macToolbarButtonSize = 34;
  static const double _macToolbarButtonGap = 8;
  static const double _macToolbarButtonRightInset = 10;

  late final String _tag;
  late final ArticleController controller;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;

  // 1. 改为使用 ValueNotifier 以实现局部刷新
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0.0);
  final ValueNotifier<String?> _hoveredUrl = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _activeTocId = ValueNotifier<String?>(null);
  bool _allowBodyBuild = Platform.isMacOS;
  bool _isTocOpen = false;
  bool _activeTocUpdateScheduled = false;
  final Map<String, GlobalKey> _headingKeys = {};
  final Map<String, String> _headingTextCache = {};
  final Map<String, List<_ArticleTocEntry>> _tocEntriesCache = {};

  @override
  void initState() {
    super.initState();
    _tag = widget.article.entryId;
    controller = Get.put(ArticleController(widget.article), tag: _tag);
    _scrollController = ScrollController();
    _scrollController.addListener(_scheduleActiveTocUpdate);
    _focusNode = FocusNode();
    LocalArticleDbService.recordReadHistory(widget.article.entryId);
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
      }
    });
  }

  @override
  void dispose() {
    if (_usesGlobalShortcuts) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    }
    _scrollController.dispose();
    _scrollProgress.dispose();
    _hoveredUrl.dispose();
    _activeTocId.dispose();
    _focusNode.dispose();
    if (Get.isRegistered<ArticleController>(tag: _tag)) {
      Get.delete<ArticleController>(tag: _tag);
    }
    super.dispose();
  }

  bool get _usesGlobalShortcuts => Platform.isMacOS && widget.isSplitView;

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

  Future<void> _copyOriginalArticleMarkdown() async {
    final chunks = controller.chunks.toList(growable: false);
    if (chunks.isEmpty) {
      AppFeedback.warning('暂无可复制正文', '当前文章还没有已加载的原文内容');
      return;
    }

    final markdown = _OriginalArticleMarkdownExporter(
      article: controller.article,
      chunks: chunks,
    ).build();

    if (markdown.trim().isEmpty) {
      AppFeedback.warning('暂无可复制正文', '当前文章还没有可复制的原文内容');
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: markdown));
      AppFeedback.success('已复制原文', 'Markdown 已复制到剪贴板');
    } catch (e) {
      AppFeedback.error('复制失败', e.toString());
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
    final maxWidth = _articleContentMaxWidth(screenWidth - 32);

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
                padding: const EdgeInsets.all(16),
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

                          _ToolbarRow(controller: controller, cs: colorScheme),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

              // 底部间距：移动端需要避让右下角 FAB，macOS 仅保留小的视觉间距。
              SliverPadding(
                padding: EdgeInsets.only(bottom: Platform.isMacOS ? 16 : 80),
              ),
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
    }

    Widget scaffold = Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pageLabel ?? '文章详情',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 2.0,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.5),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),
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
                          tooltip: '复制原文全文',
                          useOwnLayer: false,
                          onPressed: _copyOriginalArticleMarkdown,
                        ),
                        const SizedBox(width: _macToolbarButtonGap),
                        AppGlassIconButton(
                          icon: isRead
                              ? Icons.undo
                              : Icons.check_circle_outline,
                          tooltip: isRead ? '恢复未读' : '标为已读 (M)',
                          selected: !isRead,
                          selectedFillOpacity: 0.07,
                          useOwnLayer: false,
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
          child: ValueListenableBuilder<double>(
            valueListenable: _scrollProgress,
            builder: (context, progress, child) {
              return progress > 0.0
                  ? LinearProgressIndicator(
                      value: progress,
                      minHeight: 1.0,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    )
                  : ColoredBox(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.22),
                      child: const SizedBox(height: 1),
                    );
            },
          ),
        ),
      ),
      floatingActionButton: Platform.isMacOS
          ? null
          : Obx(() {
              final isRead = controller.isRead.value;
              final isUpdating = controller.isUpdatingReadState.value;
              return Opacity(
                opacity: 0.85,
                child: FloatingActionButton(
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
                  tooltip: isRead ? '恢复未读' : '标为已读',
                  child: Icon(isRead ? Icons.undo : Icons.check),
                ),
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
                      key == LogicalKeyboardKey.keyM) {
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
              return KeyEventResult.ignored;
            },
            child: result,
          )
        : result;
  }
}

class _MacSplitArticleCornerClipper extends CustomClipper<Path> {
  static const _outerRadius = 28.0;
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

class _OriginalArticleMarkdownExporter {
  final ArticleModel article;
  final List<HtmlChunk> chunks;

  const _OriginalArticleMarkdownExporter({
    required this.article,
    required this.chunks,
  });

  String build() {
    final blocks = <String>[];

    final title = article.title.trim();
    if (title.isNotEmpty) {
      blocks.add('# ${_escapeHeading(title)}');
    }

    final metadata = <String>[];
    final feedTitle = article.feedTitle.trim();
    if (feedTitle.isNotEmpty && feedTitle != '?') {
      metadata.add('来源：$feedTitle');
    }
    final author = article.author?.trim();
    if (author != null && author.isNotEmpty) {
      metadata.add('作者：$author');
    }
    final publishedAt = article.publishedAt.trim();
    if (publishedAt.isNotEmpty) {
      metadata.add('发布：$publishedAt');
    }
    final url = article.url.trim();
    if (url.isNotEmpty) {
      metadata.add('原文：$url');
    }
    if (metadata.isNotEmpty) {
      blocks.add(metadata.map((line) => '> $line').join('\n'));
    }

    final body = chunks
        .asMap()
        .entries
        .where(
          (entry) => entry.key != 0 || !_isDuplicateTitleHeading(entry.value),
        )
        .map((entry) => _chunkToMarkdown(entry.value))
        .where((block) => block.trim().isNotEmpty)
        .join('\n\n');
    if (body.trim().isNotEmpty) {
      blocks.add(body);
    }

    return _normalizeBlockSpacing(blocks.join('\n\n'));
  }

  String _chunkToMarkdown(HtmlChunk chunk) {
    return switch (chunk.type) {
      HtmlChunkType.heading => _headingToMarkdown(chunk),
      HtmlChunkType.paragraph ||
      HtmlChunkType.rawHtml => _htmlToMarkdown(chunk.content),
      HtmlChunkType.image => _imageToMarkdown(chunk),
      HtmlChunkType.codeBlock => _codeToMarkdown(chunk.content),
      HtmlChunkType.blockquote => _blockquoteToMarkdown(chunk.content),
      HtmlChunkType.table => _tableToMarkdown(chunk.content),
      HtmlChunkType.list => _listToMarkdown(chunk.content),
      HtmlChunkType.horizontalRule => '---',
      HtmlChunkType.iframeVideo => _iframeToMarkdown(chunk),
    };
  }

  String _headingToMarkdown(HtmlChunk chunk) {
    final level = (chunk.headingLevel ?? 2).clamp(1, 6);
    final text = _htmlToMarkdown(chunk.content).replaceAll('\n', ' ').trim();
    if (text.isEmpty) return '';
    return '${'#' * level} ${_escapeHeading(text)}';
  }

  bool _isDuplicateTitleHeading(HtmlChunk chunk) {
    if (chunk.type != HtmlChunkType.heading) return false;
    final heading = _normalizeComparableText(_htmlToMarkdown(chunk.content));
    final title = _normalizeComparableText(article.title);
    return heading.isNotEmpty && heading == title;
  }

  String _imageToMarkdown(HtmlChunk chunk) {
    final url = (chunk.imageSrc ?? chunk.attributes['src'] ?? '').trim();
    if (url.isEmpty) return '';
    final alt = (chunk.imageAlt ?? chunk.attributes['alt'] ?? '').trim();
    return '![${_escapeImageAlt(alt)}]($url)';
  }

  String _codeToMarkdown(String code) {
    final fence = code.contains('```') ? '````' : '```';
    return '$fence\n${code.trim()}\n$fence';
  }

  String _blockquoteToMarkdown(String html) {
    final text = _htmlToMarkdown(html);
    if (text.trim().isEmpty) return '';
    return text
        .split('\n')
        .map((line) => line.trim().isEmpty ? '>' : '> ${line.trim()}')
        .join('\n');
  }

  String _iframeToMarkdown(HtmlChunk chunk) {
    final src = (chunk.attributes['src'] ?? chunk.content).trim();
    if (src.isEmpty) return '';
    return src;
  }

  String _listToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    final rootList =
        fragment.querySelector('ol') ?? fragment.querySelector('ul');
    final items = (rootList ?? fragment).children
        .where((element) => element.localName == 'li')
        .toList();
    if (items.isEmpty) return _htmlToMarkdown(html);

    final ordered = rootList?.localName == 'ol';
    return items
        .asMap()
        .entries
        .map((entry) {
          final marker = ordered ? '${entry.key + 1}. ' : '- ';
          final text = _nodesToMarkdown(entry.value.nodes).trim();
          return '$marker${text.replaceAll('\n', '\n  ')}';
        })
        .join('\n');
  }

  String _tableToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    final rows = fragment
        .querySelectorAll('tr')
        .map((row) {
          return row.children
              .where((cell) => cell.localName == 'th' || cell.localName == 'td')
              .map((cell) => _markdownTableCell(_nodesToMarkdown(cell.nodes)))
              .toList();
        })
        .where((row) => row.isNotEmpty)
        .toList();

    if (rows.isEmpty) return _htmlToMarkdown(html);

    final columnCount = rows
        .map((row) => row.length)
        .fold<int>(0, (max, length) => math.max(max, length));
    if (columnCount == 0) return '';

    List<String> pad(List<String> row) {
      return [...row, for (var i = row.length; i < columnCount; i++) ''];
    }

    final header = pad(rows.first);
    final Iterable<List<String>> bodyRows = rows.length > 1
        ? rows.skip(1).map(pad)
        : const Iterable<List<String>>.empty();
    final buffer = StringBuffer();
    buffer.writeln('| ${header.join(' | ')} |');
    buffer.writeln('| ${List.filled(columnCount, '---').join(' | ')} |');
    for (final row in bodyRows) {
      buffer.writeln('| ${row.join(' | ')} |');
    }
    return buffer.toString().trim();
  }

  String _htmlToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    return _normalizeInlineSpacing(_nodesToMarkdown(fragment.nodes));
  }

  String _nodesToMarkdown(List<html_dom.Node> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer.write(_nodeToMarkdown(node));
    }
    return buffer.toString();
  }

  String _nodeToMarkdown(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.text;
    }
    if (node is! html_dom.Element) {
      return node.text ?? '';
    }

    final tag = node.localName;
    String childText() => _nodesToMarkdown(node.nodes);
    return switch (tag) {
      'br' => '\n',
      'p' || 'div' || 'section' || 'article' => '${childText().trim()}\n\n',
      'strong' || 'b' => _wrapInline('**', childText()),
      'em' || 'i' => _wrapInline('*', childText()),
      'code' => _inlineCode(node.text),
      'pre' => _codeToMarkdown(node.text),
      'blockquote' => _blockquoteToMarkdown(node.innerHtml),
      'a' => _linkToMarkdown(node),
      'img' => _imageElementToMarkdown(node),
      'ul' || 'ol' => _listToMarkdown(node.outerHtml),
      'table' => _tableToMarkdown(node.outerHtml),
      'hr' => '\n---\n',
      _ => childText(),
    };
  }

  String _linkToMarkdown(html_dom.Element element) {
    final text = _nodesToMarkdown(element.nodes).trim();
    final href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) return text;
    if (text.isEmpty || text == href) return href;
    return '[${_escapeLinkText(text)}]($href)';
  }

  String _imageElementToMarkdown(html_dom.Element element) {
    final src = (element.attributes['src'] ?? '').trim();
    if (src.isEmpty) return '';
    final alt = (element.attributes['alt'] ?? '').trim();
    return '![${_escapeImageAlt(alt)}]($src)';
  }

  String _wrapInline(String marker, String text) {
    final normalized = _normalizeInlineSpacing(text);
    if (normalized.isEmpty) return '';
    return '$marker$normalized$marker';
  }

  String _inlineCode(String text) {
    final normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) return '';
    final marker = normalized.contains('`') ? '``' : '`';
    return '$marker$normalized$marker';
  }

  String _markdownTableCell(String text) {
    return _normalizeInlineSpacing(
      text,
    ).replaceAll('\n', '<br>').replaceAll('|', r'\|');
  }

  String _normalizeInlineSpacing(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeBlockSpacing(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeComparableText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _escapeHeading(String text) {
    return text.replaceFirst(RegExp(r'^#+\s*'), '').trim();
  }

  String _escapeLinkText(String text) {
    return text.replaceAll('[', r'\[').replaceAll(']', r'\]');
  }

  String _escapeImageAlt(String text) {
    return text.replaceAll('[', r'\[').replaceAll(']', r'\]');
  }
}

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
  static const glass.LiquidGlassSettings _tocGlassSettings =
      glass.LiquidGlassSettings(
        blur: 12,
        thickness: 12,
        glassColor: Color.fromRGBO(255, 255, 255, 0.14),
        lightIntensity: 0.68,
        ambientStrength: 0.38,
        saturation: 1.18,
        refractiveIndex: 0.62,
        chromaticAberration: 0.0,
      );

  late final glass.GlassMorphController _morphController;

  @override
  void initState() {
    super.initState();
    _morphController =
        glass.GlassMorphController(vsync: this, speed: glass.MorphSpeed.normal)
          ..addListener(() {
            if (mounted) setState(() {});
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
          _ArticleTocMorphLayer(
            panelWidth: _panelWidth,
            panelHeight: panelHeight,
            buttonSize: _buttonSize,
            morphController: _morphController,
            entries: widget.entries,
            activeTocId: widget.activeTocId,
            onToggle: widget.onToggle,
            onEntryTap: widget.onEntryTap,
            glassSettings: _tocGlassSettings,
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
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        if (showTriggerIcon)
                          Opacity(
                            opacity: triggerIconOpacity,
                            child: SizedBox(
                              width: widget.buttonSize,
                              height: widget.buttonSize,
                              child: _TocIconButtonChrome(
                                icon: Icons.format_list_bulleted_rounded,
                                color: Theme.of(context).colorScheme.onSurface,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutralOverlay = isDark ? Colors.white : Colors.black;
    final entry = widget.entry;
    final foreground = widget.isActive
        ? cs.primary
        : entry.level <= 2
        ? cs.onSurface
        : cs.onSurfaceVariant;
    final backgroundColor = widget.isActive
        ? cs.primary.withValues(alpha: isDark ? 0.20 : 0.12)
        : _isPressed
        ? neutralOverlay.withValues(alpha: isDark ? 0.12 : 0.08)
        : _isHovered
        ? neutralOverlay.withValues(alpha: isDark ? 0.08 : 0.055)
        : Colors.transparent;
    final borderColor = widget.isActive
        ? cs.primary.withValues(alpha: isDark ? 0.24 : 0.18)
        : _isHovered
        ? neutralOverlay.withValues(alpha: isDark ? 0.08 : 0.06)
        : Colors.transparent;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = isDark ? Colors.white : Colors.black;
    final backgroundColor = _isPressed
        ? overlay.withValues(alpha: isDark ? 0.14 : 0.08)
        : _isHovered
        ? overlay.withValues(alpha: isDark ? 0.09 : 0.055)
        : Colors.transparent;

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
  const _MetadataSection({required this.controller, required this.cs});

  @override
  Widget build(BuildContext context) {
    final imageUrl = controller.article.feedImage;
    return InkWell(
      onTap: controller.article.feedId.isEmpty ? null : controller.openSource,
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
  final ColorScheme cs;
  const _ToolbarRow({required this.controller, required this.cs});

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
      if (Platform.isMacOS) {
        return _MacGlassToolbarRow(
          controller: controller,
          cs: cs,
          isPending: isPending,
          hasTranslation: hasTranslation,
          showTranslation: showTranslation,
          isSummaryPending: isSummaryPending,
          hasSummary: hasSummary,
          showSummary: showSummary,
          isFetchingReadability: isFetchingReadability,
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(
                cs: cs,
                icon: controller.showTranslation.value
                    ? Icons.translate
                    : Icons.translate_outlined,
                label: isPending
                    ? '翻译…'
                    : hasTranslation
                    ? '已译'
                    : '翻译',
                active: controller.showTranslation.value || isPending,
                onTap: isPending
                    ? null
                    : hasTranslation
                    ? () => controller.showTranslation.toggle()
                    : () => controller.translateArticle(),
              ),
              const SizedBox(width: 8),
              _Chip(
                cs: cs,
                icon: hasSummary && controller.showSummary.value
                    ? Icons.summarize
                    : Icons.summarize_outlined,
                label: isSummaryPending
                    ? '摘要…'
                    : hasSummary
                    ? '已摘要'
                    : '摘要',
                active:
                    isSummaryPending ||
                    (hasSummary && controller.showSummary.value),
                onTap: isSummaryPending
                    ? null
                    : hasSummary
                    ? () => controller.showSummary.toggle()
                    : () => controller.summarizeArticle(),
              ),
              if (isFetchingReadability) ...[
                const SizedBox(width: 8),
                _Chip(
                  cs: cs,
                  icon: Icons.sync,
                  label: '加载长文中…',
                  active: true,
                  onTap: null,
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _MacGlassToolbarRow extends StatelessWidget {
  final ArticleController controller;
  final ColorScheme cs;
  final bool isPending;
  final bool hasTranslation;
  final bool showTranslation;
  final bool isSummaryPending;
  final bool hasSummary;
  final bool showSummary;
  final bool isFetchingReadability;

  const _MacGlassToolbarRow({
    required this.controller,
    required this.cs,
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
      _MacPillActionChip(
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
      _MacPillActionChip(
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
        const _MacPillActionChip(
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

class _MacPillActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _MacPillActionChip({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  State<_MacPillActionChip> createState() => _MacPillActionChipState();
}

class _MacPillActionChipState extends State<_MacPillActionChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final foreground = widget.active ? cs.primary : cs.onSurfaceVariant;
    final background = widget.active
        ? cs.primary.withValues(alpha: 0.10)
        : cs.surfaceContainerHighest.withValues(alpha: 0.58);
    final borderColor = widget.active
        ? cs.primary.withValues(alpha: 0.22)
        : cs.outlineVariant.withValues(alpha: _hovered ? 0.62 : 0.52);

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
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

class _Chip extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _Chip({
    required this.cs,
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
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
