import 'package:dio/dio.dart';

import '../common/constants/constants.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../services/analysis_event_ledger.dart';
import '../services/account_session_guard.dart';
import '../services/remote_read_request_coordinator.dart';
import '../services/entry_snapshot_collector.dart';
import 'init.dart';
import 'folo_api_contract.dart';

/// Folo API 封装
class FeedHttp {
  FeedHttp._();

  // ─── 订阅源 ──────────────────────────────────

  /// 获取全部订阅源
  static Future<LoadingState<List<FeedModel>>> getSubscriptions() async {
    try {
      final response = await Request().get(ApiConstants.subscriptions);
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final feeds = FoloApiContract.parseFeedSubscriptions(body['data']);
          return Success(feeds);
        }
        return LoadError(_messageOf(body, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 通过 RSS URL 新增订阅。
  static Future<LoadingState<FeedModel?>> createSubscription({
    required String url,
    required int view,
    String? title,
    String? category,
  }) async {
    try {
      final response = await Request().post(
        ApiConstants.subscriptions,
        data: FoloApiContract.createSubscriptionRequest(
          url: url,
          view: view,
          title: _nullableText(title),
          category: _nullableText(category),
        ),
      );
      final body = _responseMap(response);
      if (_isSuccessfulResponse(response, body)) {
        final feed = FoloApiContract.parseCreatedFeed(
          body,
          customTitle: _nullableText(title),
          category: _nullableText(category),
          view: view,
          fallbackUrl: url,
        );
        return Success(feed);
      }
      return LoadError(
        body == null
            ? '添加订阅失败: ${response.statusCode}'
            : _messageOf(body, fallback: '添加订阅失败'),
      );
    } on DioException catch (e) {
      return LoadError(_dioMessage(e, fallback: '添加订阅失败'));
    }
  }

  /// 修改用户侧订阅元数据；RSS URL 本身不可修改。
  static Future<LoadingState<void>> updateSubscription({
    required String feedId,
    required int view,
    String? title,
    String? category,
  }) async {
    try {
      final response = await Request().patch(
        ApiConstants.subscriptions,
        data: FoloApiContract.updateSubscriptionRequest(
          feedId: feedId,
          view: view,
          title: _nullableText(title),
          category: _nullableText(category),
        ),
      );
      final body = _responseMap(response);
      if (_isSuccessfulResponse(response, body)) {
        return const Success(null);
      }
      return LoadError(
        body == null
            ? '更新订阅失败: ${response.statusCode}'
            : _messageOf(body, fallback: '更新订阅失败'),
      );
    } on DioException catch (e) {
      return LoadError(_dioMessage(e, fallback: '更新订阅失败'));
    }
  }

  /// 取消一个普通 RSS 订阅。
  static Future<LoadingState<void>> deleteSubscription({
    required String feedId,
  }) async {
    try {
      final response = await Request().delete(
        ApiConstants.subscriptions,
        data: FoloApiContract.deleteSubscriptionRequest(feedId),
      );
      final body = _responseMap(response);
      if (_isSuccessfulResponse(response, body)) {
        return const Success(null);
      }
      return LoadError(
        body == null
            ? '取消订阅失败: ${response.statusCode}'
            : _messageOf(body, fallback: '取消订阅失败'),
      );
    } on DioException catch (e) {
      return LoadError(_dioMessage(e, fallback: '取消订阅失败'));
    }
  }

  // ─── 文章条目 ────────────────────────────────

  /// 获取条目（view: 0=feeds, 1=social）。read=false=未读。
  static Future<LoadingState<List<ArticleModel>>> getEntries({
    int view = 0,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    bool withContent = false,
    String? publishedAfter,
    Map<String, FeedModel>? feedMap,
  }) async {
    try {
      final body = FoloApiContract.entryListRequest(
        view: view,
        limit: limit,
        read: read,
        withContent: withContent,
        publishedAfter: publishedAfter,
      );

      final response = await Request().post(ApiConstants.entries, data: body);

      final bodyMap = _responseMap(response);
      if (response.statusCode == 200 && bodyMap != null) {
        if (_isSuccess(bodyMap)) {
          final data = bodyMap['data'];
          if (data is! List || data.any((item) => item is! Map)) {
            return const LoadError('服务器未返回完整的条目列表', code: 200);
          }
          final articles = data.whereType<Map>().map((item) {
            final json = Map<String, dynamic>.from(item);
            final feedId =
                (json['feeds'] as Map<String, dynamic>?)?['id'] as String? ??
                '';
            final f = feedMap?[feedId];
            return ArticleModel.fromEntryJson(
              json,
              feedTitle: f?.title,
              feedImage: f?.image,
              subscriptionCategory: f?.category,
              view: view,
              feedView: f?.view,
            );
          }).toList();
          if (articles.any((article) => article.entryId.isEmpty)) {
            return const LoadError('条目缺少有效 ID', code: 200);
          }
          return Success(articles);
        }
        return LoadError(_messageOf(bodyMap, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 分页收集条目，适合需要尽量完整回填状态的场景。
  static Future<LoadingState<List<ArticleModel>>> collectEntries({
    int view = 0,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    bool withContent = false,
    String? publishedAfter,
    Map<String, FeedModel>? feedMap,
    int? maxPages,
  }) async {
    return EntrySnapshotCollector.collect(
      source: view == 1 ? 'social' : 'feeds',
      read: read,
      limit: limit,
      initialCursor: publishedAfter,
      maxPages: maxPages,
      loadPage: (cursor) => getEntries(
        view: view,
        limit: limit,
        read: read,
        withContent: withContent,
        publishedAfter: cursor,
        feedMap: feedMap,
      ),
    );
  }

  /// 收集所有 inbox 的未读条目。
  static Future<LoadingState<List<ArticleModel>>> collectAllInboxEntries({
    int limit = AppConstants.defaultPageSize,
  }) async {
    final accountRevision = AccountSessionGuard.revision;
    final inboxesResult = await getInboxes();
    if (!AccountSessionGuard.isCurrent(accountRevision)) {
      return const LoadError('账号已变化');
    }
    if (inboxesResult is LoadError<List<Map<String, dynamic>>>) {
      EntrySnapshotCollector.result(
        [],
        source: 'inbox',
        read: false,
        complete: false,
        stopReason: 'inbox_list_failed',
        limit: limit,
        pages: [],
      );
      return LoadError(inboxesResult.errMsg ?? '获取收件箱列表失败');
    }
    if (inboxesResult is! Success<List<Map<String, dynamic>>>) {
      return const LoadError('获取收件箱列表失败');
    }

    final inboxes = inboxesResult.response;
    final items = <ArticleModel>[];
    var complete = true;
    final sequences = <int>[];

    for (final inbox in inboxes) {
      if (!AccountSessionGuard.isCurrent(accountRevision)) {
        return const LoadError('账号已变化');
      }
      final FeedModel source;
      try {
        source = FeedModel.fromInboxJson(inbox);
      } catch (_) {
        complete = false;
        continue;
      }
      final inboxId = source.feedId;
      if (inboxId.isEmpty) {
        complete = false;
        continue;
      }

      final result = await collectInboxEntries(
        inboxId: inboxId,
        limit: limit,
        inboxTitle: source.title,
        inboxImage: source.image,
        inboxCategory: source.category,
      );

      if (!AccountSessionGuard.isCurrent(accountRevision)) {
        return const LoadError('账号已变化');
      }
      complete = complete && EntrySnapshotCollector.isComplete(result);
      final sequence = EntrySnapshotCollector.sequenceOf(result);
      if (sequence != null) sequences.add(sequence);
      if (result is Success<List<ArticleModel>>) {
        items.addAll(result.response);
      }
    }

    final deduped = <String, ArticleModel>{};
    for (final item in items) {
      if (item.entryId.isEmpty) continue;
      deduped[item.entryId] = item;
    }
    return EntrySnapshotCollector.result(
      deduped.values.toList(),
      source: 'inbox',
      read: false,
      complete: complete,
      stopReason: complete ? 'all_inboxes_complete' : 'partial_inboxes',
      limit: limit,
      pages: [],
      childSequences: sequences,
    );
  }

  // ─── 收件箱 ──────────────────────────────────

  /// 获取收件箱列表
  static Future<LoadingState<List<Map<String, dynamic>>>> getInboxes() async {
    try {
      final response = await Request().get(ApiConstants.inboxesList);
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final data = body['data'];
          if (data is! List || data.any((item) => item is! Map)) {
            return const LoadError('服务器未返回完整的收件箱列表', code: 200);
          }
          final inboxes = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          return Success(inboxes);
        }
        return LoadError(_messageOf(body, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 获取指定收件箱的未读条目
  static Future<LoadingState<List<ArticleModel>>> getInboxEntries({
    required String inboxId,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    String? publishedAfter,
    String? inboxTitle,
    String? inboxImage,
    String? inboxCategory,
  }) async {
    try {
      final body = FoloApiContract.inboxEntryListRequest(
        inboxId: inboxId,
        limit: limit,
        read: read,
        publishedAfter: publishedAfter,
      );

      final response = await Request().post(
        ApiConstants.entriesInbox,
        data: body,
      );

      final bodyMap = _responseMap(response);
      if (response.statusCode == 200 && bodyMap != null) {
        if (_isSuccess(bodyMap)) {
          final data = bodyMap['data'];
          if (data is! List || data.any((item) => item is! Map)) {
            return const LoadError('服务器未返回完整的条目列表', code: 200);
          }
          final articles = data
              .whereType<Map>()
              .map(
                (item) => ArticleModel.fromInboxJson(
                  Map<String, dynamic>.from(item),
                  feedTitle: inboxTitle,
                  feedImage: inboxImage,
                  subscriptionCategory: inboxCategory,
                ),
              )
              .toList();
          if (articles.any((article) => article.entryId.isEmpty)) {
            return const LoadError('条目缺少有效 ID', code: 200);
          }
          return Success(articles);
        }
        return LoadError(_messageOf(bodyMap, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 分页收集指定 Inbox 的条目。
  static Future<LoadingState<List<ArticleModel>>> collectInboxEntries({
    required String inboxId,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    String? publishedAfter,
    String? inboxTitle,
    String? inboxImage,
    String? inboxCategory,
    int? maxPages,
  }) async {
    return EntrySnapshotCollector.collect(
      source: 'inbox:$inboxId',
      read: read,
      limit: limit,
      initialCursor: publishedAfter,
      maxPages: maxPages,
      loadPage: (cursor) => getInboxEntries(
        inboxId: inboxId,
        limit: limit,
        read: read,
        publishedAfter: cursor,
        inboxTitle: inboxTitle,
        inboxImage: inboxImage,
        inboxCategory: inboxCategory,
      ),
    );
  }

  /// 获取指定 inbox 条目的详情（含正文）
  static Future<LoadingState<String>> getInboxEntryDetail({
    required String entryId,
  }) async {
    try {
      final response = await Request().get(
        ApiConstants.entriesInboxDetail,
        queryParameters: {'id': entryId},
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final data = body['data'] as Map<String, dynamic>?;
          final entries = data?['entries'] as Map<String, dynamic>?;
          final content = entries?['content'] as String? ?? '';
          return Success(content);
        }
        return LoadError(_messageOf(body, fallback: '获取详情失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  // ─── 已读管理 ────────────────────────────────

  /// 标已读（一次最多 50 条）
  static Future<LoadingState<void>> markRead({
    required List<String> entryIds,
    bool isInbox = false,
    required RemoteReadRequestSource auditSource,
    Map<String, int>? queuedAtByEntryId,
    List<String> Function()? currentEntryIds,
    bool Function()? shouldSend,
  }) {
    final revision = AccountSessionGuard.revision;
    return RemoteReadRequestCoordinator.run(entryIds, () {
      final allowed = currentEntryIds?.call().toSet();
      final ids = entryIds
          .where((id) => allowed == null || allowed.contains(id))
          .toList();
      if (!AccountSessionGuard.isCurrent(revision)) {
        return Future.value(const LoadError<void>('账号已变化'));
      }
      if ((shouldSend != null && !shouldSend()) || ids.isEmpty) {
        AnalysisEventLedger.recordReadRequestSuppressed(
          entryIds: entryIds,
          source: auditSource,
          targetIsRead: true,
        );
        return Future.value(const LoadError<void>('已读操作已取消或被更新'));
      }
      return _markReadNow(
        entryIds: ids,
        isInbox: isInbox,
        auditSource: auditSource,
        queuedAtByEntryId: queuedAtByEntryId == null
            ? null
            : {
                for (final id in ids)
                  if (queuedAtByEntryId.containsKey(id))
                    id: queuedAtByEntryId[id]!,
              },
      );
    });
  }

  static Future<LoadingState<void>> _markReadNow({
    required List<String> entryIds,
    required bool isInbox,
    required RemoteReadRequestSource auditSource,
    Map<String, int>? queuedAtByEntryId,
  }) async {
    final accountRevision = AccountSessionGuard.revision;
    final stopwatch = Stopwatch()..start();
    final attemptSequence = AnalysisEventLedger.recordRemoteMarkReadAttempt(
      entryIds: entryIds,
      isInbox: isInbox,
      source: auditSource,
      queuedAtByEntryId: queuedAtByEntryId,
    );

    LoadingState<void> finish(
      LoadingState<void> result, {
      int? statusCode,
      String? failureKind,
    }) {
      stopwatch.stop();
      if (!AccountSessionGuard.isCurrent(accountRevision)) return result;
      AnalysisEventLedger.recordRemoteMarkReadResult(
        attemptSequence: attemptSequence,
        entryIds: entryIds,
        source: auditSource,
        success: result is Success<void>,
        durationMs: stopwatch.elapsedMilliseconds,
        statusCode: statusCode,
        failureKind: failureKind,
      );
      return result;
    }

    try {
      final response = await Request().post(
        ApiConstants.reads,
        data: FoloApiContract.markReadRequest(
          entryIds: entryIds,
          isInbox: isInbox,
        ),
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          return finish(const Success(null), statusCode: response.statusCode);
        }
        return finish(
          LoadError(_messageOf(body, fallback: '标已读失败')),
          statusCode: response.statusCode,
          failureKind: 'api_rejected',
        );
      }
      return finish(
        LoadError('请求失败: ${response.statusCode}'),
        statusCode: response.statusCode,
        failureKind: 'http_status',
      );
    } on DioException catch (e) {
      return finish(
        LoadError('网络错误: ${e.message}'),
        statusCode: e.response?.statusCode,
        failureKind: e.type.name,
      );
    } catch (_) {
      finish(const LoadError('已读同步异常'), failureKind: 'unexpected_exception');
      rethrow;
    }
  }

  /// 标未读
  static Future<LoadingState<void>> markUnread({
    required String entryId,
    bool isInbox = false,
    required RemoteReadRequestSource auditSource,
    bool Function()? shouldSend,
  }) {
    final revision = AccountSessionGuard.revision;
    return RemoteReadRequestCoordinator.run([entryId], () {
      if (!AccountSessionGuard.isCurrent(revision)) {
        return Future.value(const LoadError<void>('账号已变化'));
      }
      if (shouldSend != null && !shouldSend()) {
        AnalysisEventLedger.recordReadRequestSuppressed(
          entryIds: [entryId],
          source: auditSource,
          targetIsRead: false,
        );
        return Future.value(const LoadError<void>('未读操作已取消或被更新'));
      }
      return _markUnreadNow(
        entryId: entryId,
        isInbox: isInbox,
        auditSource: auditSource,
      );
    });
  }

  static Future<LoadingState<void>> _markUnreadNow({
    required String entryId,
    required bool isInbox,
    required RemoteReadRequestSource auditSource,
  }) async {
    final accountRevision = AccountSessionGuard.revision;
    final stopwatch = Stopwatch()..start();
    final sequence = AnalysisEventLedger.recordRemoteMarkReadAttempt(
      entryIds: [entryId],
      isInbox: isInbox,
      source: auditSource,
      targetIsRead: false,
    );
    LoadingState<void> finish(
      LoadingState<void> result, {
      int? statusCode,
      String? failureKind,
    }) {
      stopwatch.stop();
      if (!AccountSessionGuard.isCurrent(accountRevision)) return result;
      AnalysisEventLedger.recordRemoteMarkReadResult(
        attemptSequence: sequence,
        entryIds: [entryId],
        source: auditSource,
        targetIsRead: false,
        success: result is Success<void>,
        durationMs: stopwatch.elapsedMilliseconds,
        statusCode: statusCode,
        failureKind: failureKind,
      );
      return result;
    }

    try {
      final response = await Request().delete(
        ApiConstants.reads,
        data: FoloApiContract.markUnreadRequest(
          entryId: entryId,
          isInbox: isInbox,
        ),
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          return finish(const Success(null), statusCode: response.statusCode);
        }
        return finish(
          LoadError(_messageOf(body, fallback: '标未读失败')),
          statusCode: response.statusCode,
          failureKind: 'api_rejected',
        );
      }
      return finish(
        LoadError('请求失败: ${response.statusCode}'),
        statusCode: response.statusCode,
        failureKind: 'http_status',
      );
    } on DioException catch (e) {
      return finish(
        LoadError('网络错误: ${e.message}'),
        statusCode: e.response?.statusCode,
        failureKind: e.type.name,
      );
    } catch (_) {
      finish(const LoadError('未读同步异常'), failureKind: 'unexpected_exception');
      rethrow;
    }
  }

  /// 批量修改订阅分类，对标 Folo categories API。
  static Future<LoadingState<void>> updateCategory({
    required List<String> feedIds,
    required String category,
  }) async {
    try {
      final response = await Request().patch(
        ApiConstants.categories,
        data: FoloApiContract.updateCategoryRequest(
          feedIds: feedIds,
          category: category,
        ),
      );
      final body = _responseMap(response);
      if (_isSuccessfulResponse(response, body)) {
        return const Success(null);
      }
      return LoadError(
        body == null
            ? '更新分类失败: ${response.statusCode}'
            : _messageOf(body, fallback: '更新分类失败'),
      );
    } on DioException catch (e) {
      return LoadError(_dioMessage(e, fallback: '更新分类失败'));
    }
  }

  static Map<String, dynamic>? _responseMap(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static bool _isSuccess(Map<String, dynamic> body) =>
      body['code'] == 0 || body['code'] == '0';

  static bool _isSuccessfulResponse(
    Response response,
    Map<String, dynamic>? body,
  ) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return false;
    return body != null && _isSuccess(body);
  }

  static String? _nullableText(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _dioMessage(DioException error, {required String fallback}) {
    final data = error.response?.data;
    if (data is Map) {
      return _messageOf(Map<String, dynamic>.from(data), fallback: fallback);
    }
    return error.message?.trim().isNotEmpty == true
        ? '$fallback: ${error.message}'
        : fallback;
  }

  static String _messageOf(
    Map<String, dynamic> body, {
    required String fallback,
  }) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return _normalizeServerMessage(message);
    }
    return fallback;
  }

  /// 服务端抓取失败（如源站 Cloudflare 挑战）不代表订阅 URL 无效，
  /// 统一转成可操作的提示，避免误报「URL 无效」。
  static String _normalizeServerMessage(String message) {
    final lowered = message.toLowerCase();
    if (lowered.contains('feed fetch error') ||
        lowered.contains('fetch error')) {
      return 'Folo 暂时无法抓取该订阅源，源站可能阻止服务端访问';
    }
    return message;
  }
}
