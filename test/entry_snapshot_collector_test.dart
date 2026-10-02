import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/common/constants/constants.dart';
import 'package:fourier/http/feed_http.dart';
import 'package:fourier/http/init.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/account_service.dart';
import 'package:fourier/services/account_session_guard.dart';
import 'package:fourier/services/article_image_cache_service.dart';
import 'package:fourier/services/entry_snapshot_collector.dart';
import 'package:fourier/services/folo_request_metadata.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final ResponseBody Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _reply(Object? data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode({'code': 0, 'data': data}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
ArticleModel _article(String id, {String date = '2026-10-01T00:00:00Z'}) =>
    ArticleModel(
      entryId: id,
      feedId: 'feed',
      feedTitle: 'Test',
      title: 'Article $id',
      url: '',
      publishedAt: date,
    );
Map<String, Object?> _row(String id) => {
  'entries': {
    'id': id,
    'title': 'Article $id',
    'url': '',
    'publishedAt': '2026-10-01T00:00:00Z',
  },
  'feeds': {'id': 'feed'},
};
void main() {
  var initialized = false;
  setUp(() async {
    await HiveTestHelper.setUp();
    LocalArticleDbService.invalidateCache();
    ArticleImageCacheService.setEnabledForTesting(false);
    if (!initialized) {
      await FoloRequestMetadata.init();
      initialized = true;
    }
    Request();
    Request.dio.interceptors.clear();
    // Any unexpected endpoint fails locally; there is no live HTTP adapter.
    Request.dio.httpClientAdapter = _Adapter((_) => _reply([], status: 503));
  });
  tearDown(() async {
    await Get.delete<AccountService>(force: true);
    ArticleImageCacheService.setEnabledForTesting(null);
    await HiveTestHelper.tearDown();
  });
  Future<LoadingState<List<ArticleModel>>> collect(
    List<LoadingState<List<ArticleModel>>> pages, {
    int? maxPages,
  }) {
    var index = 0;
    return EntrySnapshotCollector.collect(
      source: 'feeds',
      read: false,
      limit: 2,
      maxPages: maxPages,
      loadPage: (_) async => pages[index++],
    );
  }

  Map audit(LoadingState<List<ArticleModel>> result) =>
      GStorage.analysisEvents.get(
        EntrySnapshotCollector.sequenceOf(result)!.toString().padLeft(12, '0'),
      ) as Map;
  test('normal exhaustion is complete and records page boundaries', () async {
    final result = await collect([
      Success([_article('1'), _article('2')]),
      const Success([]),
    ]);
    expect(EntrySnapshotCollector.isComplete(result), isTrue);
    final data = audit(result)['data'] as Map;
    expect(data['stopReason'], 'empty_page');
    expect((data['pages'] as List).length, 2);
    expect((data['pages'] as List).first['lastId'], '2');
    expect(data['count'], 2);
  });
  test('a short final page is complete', () async {
    final result = await collect([
      Success([_article('1')]),
    ]);
    expect(EntrySnapshotCollector.isComplete(result), isTrue);
  });
  test(
    'partial request failure preserves results but forbids inference',
    () async {
      final result = await collect([
        Success([_article('1'), _article('2')]),
        const LoadError('failed'),
      ]);
      expect((result as Success<List<ArticleModel>>).response.length, 2);
      expect(EntrySnapshotCollector.isComplete(result), isFalse);
      expect((audit(result)['data'] as Map)['stopReason'], 'request_failed');
    },
  );
  test('a repeated page is incomplete', () async {
    final page = Success([_article('1'), _article('2')]);
    final result = await collect([page, page]);
    expect(EntrySnapshotCollector.isComplete(result), isFalse);
    expect((audit(result)['data'] as Map)['stopReason'], 'no_progress');
  });
  test('a repeated cursor with new IDs is incomplete', () async {
    final result = await collect([
      Success([_article('1'), _article('2')]),
      Success([_article('3'), _article('4')]),
    ]);
    expect(EntrySnapshotCollector.isComplete(result), isFalse);
    expect((audit(result)['data'] as Map)['stopReason'], 'repeated_cursor');
  });
  test('missing cursor and explicit page cap are incomplete', () async {
    final missing = await collect([
      Success([_article('1'), _article('2', date: '')]),
    ]);
    expect(EntrySnapshotCollector.isComplete(missing), isFalse);
    final limited = await collect([
      Success([_article('1'), _article('2')]),
    ], maxPages: 1);
    expect(EntrySnapshotCollector.isComplete(limited), isFalse);
    expect((audit(limited)['data'] as Map)['stopReason'], 'page_limit');
  });
  test('parsing failure is audited without exception content', () async {
    final result = await EntrySnapshotCollector.collect(
      source: 'feeds',
      read: false,
      limit: 2,
      loadPage: (_) async => throw StateError('private-body-marker'),
    );
    expect(result, isA<LoadError<List<ArticleModel>>>());
    final events = GStorage.analysisEvents.values.whereType<Map>();
    expect(events.last['data']['stopReason'], 'parse_exception');
    expect(events.toString(), isNot(contains('private-body-marker')));
  });
  test(
    'malformed successful HTTP body is not treated as an empty snapshot',
    () async {
      Request.dio.httpClientAdapter = _Adapter((_) => _reply(null));
      expect(await FeedHttp.getEntries(), isA<LoadError<List<ArticleModel>>>());
      expect(
        await FeedHttp.getInboxEntries(inboxId: 'inbox'),
        isA<LoadError<List<ArticleModel>>>(),
      );
      expect(
        await FeedHttp.getInboxes(),
        isA<LoadError<List<Map<String, dynamic>>>>(),
      );
    },
  );
  test('one failed inbox prevents completeness of the aggregate', () async {
    Request.dio.httpClientAdapter = _Adapter((options) {
      if (options.path == ApiConstants.inboxesList) {
        return _reply([
          {'id': 'good'},
          {'id': 'bad'},
        ]);
      }
      final inbox = (options.data as Map)['inboxId'];
      return inbox == 'good' ? _reply([_row('1')]) : _reply(null, status: 503);
    });
    final result = await FeedHttp.collectAllInboxEntries();
    expect((result as Success<List<ArticleModel>>).response.length, 1);
    expect(EntrySnapshotCollector.isComplete(result), isFalse);
    expect((audit(result)['data'] as Map)['stopReason'], 'partial_inboxes');
  });
  testWidgets(
    'timeline keeps missing local articles unread for incomplete pages',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          navigatorObservers: [FlutterSmartDialog.observer],
          home: const Scaffold(),
        ),
      );
      await tester.runAsync(() async {
        Get.put(AccountService());
        LocalArticleDbService.upsertOne(_article('missing'));
        var feedsCalls = 0;
        Request.dio.httpClientAdapter = _Adapter((options) {
          if (options.path == ApiConstants.inboxesList) return _reply([]);
          if ((options.data as Map)['view'] == 1) return _reply([]);
          feedsCalls++;
          // A full page followed by a transport failure is a partial snapshot.
          return feedsCalls == 1
              ? _reply(
                  List.generate(
                    AppConstants.defaultPageSize,
                    (i) => _row('returned-$i'),
                  ),
                )
              : _reply(null, status: 503);
        });
        final controller = TimelineController();
        await controller.loadData();
        expect(LocalArticleDbService.readArticle('missing')?.isRead, isFalse);
        expect(LocalArticleDbService.readArticle('returned-0'), isNotNull);
        expect(
          GStorage.analysisEvents.values.whereType<Map>().where(
            (event) =>
                event['type'] == 'mark_read' && event['articleId'] == 'missing',
          ),
          isEmpty,
        );
        await SmartDialog.dismiss(status: SmartStatus.allToast);
      });
      await tester.pumpAndSettle();
    },
  );
  test(
    'account change stops old collection without writing into the new ledger',
    () async {
      final before = GStorage.analysisEvents.length;
      final result = await EntrySnapshotCollector.collect(
        source: 'feeds',
        read: false,
        limit: 2,
        loadPage: (_) async {
          AccountSessionGuard.invalidate();
          return Success([_article('old')]);
        },
      );
      expect(result, isA<LoadError<List<ArticleModel>>>());
      expect(GStorage.analysisEvents.length, before);
    },
  );
}
