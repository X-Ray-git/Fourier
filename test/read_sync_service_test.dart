import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/undo_service.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/services/article_image_cache_service.dart';
import 'package:fourier/utils/storage.dart';
import 'package:fourier/http/init.dart';
import 'package:fourier/services/read_sync_service.dart';
import 'package:fourier/services/folo_request_metadata.dart';

import 'support/hive_test_helper.dart';

import 'package:fourier/http/feed_http.dart';
import 'package:fourier/services/analysis_event_ledger.dart';
import 'package:fourier/services/account_session_guard.dart';

class BlockingAdapter implements HttpClientAdapter {
  BlockingAdapter({this.failFirst = false});
  final bool failFirst;
  final entered = Completer<void>();
  final release = Completer<void>();
  final calls = <List<String>>[];
  final methods = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data as Map;
    final ids = data['entryIds'] is List
        ? List<String>.from(data['entryIds'] as List)
        : <String>[data['entryId'] as String];
    methods.add(options.method);
    calls.add(ids);
    final first = calls.length == 1;
    if (first) {
      entered.complete();
      await release.future;
    }
    return ResponseBody.fromString(
      first && failFirst ? '{"code":1}' : '{"code":0}',
      first && failFirst ? 503 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SuccessAdapter implements HttpClientAdapter {
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      '{"code":0}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SecondBatchAdapter implements HttpClientAdapter {
  final entered = Completer<void>();
  final release = Completer<void>();
  final methods = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    if (methods.length == 2) {
      entered.complete();
      await release.future;
    }
    return ResponseBody.fromString(
      '{"code":0}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  var metadataInitialized = false;
  setUp(() async {
    await HiveTestHelper.setUp();
    ReadSyncService.clear();
    UndoService.clear();
    ArticleImageCacheService.setEnabledForTesting(false);
    if (!metadataInitialized) {
      await FoloRequestMetadata.init();
      metadataInitialized = true;
    }
    Request();
    Request.dio.interceptors.clear();
  });
  tearDown(() async {
    ReadSyncService.clear();
    ArticleImageCacheService.setEnabledForTesting(null);
    await HiveTestHelper.tearDown();
  });
  test('cancelled task is not retried after the first request fails', () async {
    final adapter = BlockingAdapter(failFirst: true);
    Request.dio.httpClientAdapter = adapter;
    ReadSyncService.enqueue('cancelled-entry', isInbox: false);
    final run = ReadSyncService.syncPendingReads();
    await adapter.entered.future;
    ReadSyncService.removeMany(['cancelled-entry']);
    expect(ReadSyncService.pendingReadItems, isEmpty);
    adapter.release.complete();
    await run;
    expect(adapter.calls, [
      ['cancelled-entry'],
    ]);
  });
  test(
    'cancelled later batch is not sent after the first batch completes',
    () async {
      final adapter = BlockingAdapter();
      Request.dio.httpClientAdapter = adapter;
      for (var i = 0; i < 51; i++) {
        ReadSyncService.enqueue('entry-$i', isInbox: false);
      }
      final run = ReadSyncService.syncPendingReads();
      await adapter.entered.future;
      final laterId = List.generate(
        51,
        (i) => 'entry-$i',
      ).firstWhere((id) => !adapter.calls.first.contains(id));
      ReadSyncService.removeMany([laterId]);
      expect(
        ReadSyncService.pendingReadItems.any((e) => e.entryId == laterId),
        isFalse,
      );
      adapter.release.complete();
      await run;
      expect(adapter.calls.length, 1);
    },
  );
  testWidgets(
    'undo without a detail controller cancels the pending read item',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          navigatorObservers: [FlutterSmartDialog.observer],
          home: const Scaffold(),
        ),
      );
      final adapter = SuccessAdapter();
      Request.dio.httpClientAdapter = adapter;
      final article = ArticleModel(
        entryId: 'undo-entry',
        feedId: 'feed',
        feedTitle: 'Test',
        title: 'Synthetic article',
        url: 'https://example.com/entry',
      );
      await tester.runAsync(() async {
        await GStorage.articleDb.put(
          article.entryId,
          article.copyWith(isRead: true).toJson(),
        );
        await GStorage.readStatus.put(article.entryId, true);
        ReadSyncService.enqueue(article.entryId, isInbox: false);
        UndoService.recordRead(article);
        final result = await UndoService.undoLastAction();
        expect(result?.entryId, article.entryId);
        expect(
          LocalArticleDbService.readArticle(article.entryId)?.isRead,
          isFalse,
        );
        expect(ReadSyncService.pendingReadItems, isEmpty);
        expect(adapter.paths.length, 1);

        await SmartDialog.dismiss(status: SmartStatus.allToast);
      });
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  test('old success retains and sends a newly enqueued revision', () async {
    final adapter = BlockingAdapter();
    Request.dio.httpClientAdapter = adapter;
    final old = ReadSyncService.enqueue('entry', isInbox: false);
    final run = ReadSyncService.syncPendingReads();
    await adapter.entered.future;
    final fresh = ReadSyncService.enqueue('entry', isInbox: false);
    expect(fresh.revision, greaterThan(old.revision));
    ReadSyncService.removeMatching([old]);
    expect(ReadSyncService.isCurrent(fresh), isTrue);
    adapter.release.complete();
    await run;
    expect(adapter.calls, [
      ['entry'],
      ['entry'],
    ]);
    expect(ReadSyncService.pendingReadItems, isEmpty);
  });
  test(
    'same article unread waits for an in-flight read and is audited',
    () async {
      final adapter = BlockingAdapter();
      Request.dio.httpClientAdapter = adapter;
      final read = FeedHttp.markRead(
        entryIds: ['entry'],
        auditSource: RemoteReadRequestSource.articleController,
      );
      await adapter.entered.future;
      final unread = FeedHttp.markUnread(
        entryId: 'entry',
        auditSource: RemoteReadRequestSource.singleAction,
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.methods, ['POST']);
      adapter.release.complete();
      await Future.wait([read, unread]);
      expect(adapter.methods, ['POST', 'DELETE']);
      final events = GStorage.analysisEvents.values.whereType<Map>().toList();
      expect(
        events.map((e) => e['type']),
        containsAll([
          'remote_mark_unread_attempt',
          'remote_mark_unread_result',
        ]),
      );
      final result = events.singleWhere(
        (e) => e['type'] == 'remote_mark_unread_result',
      );
      expect((result['data'] as Map)['success'], isTrue);
    },
  );
  test(
    'pending request cancelled while awaiting another source is suppressed',
    () async {
      final adapter = BlockingAdapter();
      Request.dio.httpClientAdapter = adapter;
      final read = FeedHttp.markRead(
        entryIds: ['entry'],
        auditSource: RemoteReadRequestSource.articleController,
      );
      await adapter.entered.future;
      ReadSyncService.enqueue('entry', isInbox: false);
      final pending = ReadSyncService.syncPendingReads();
      ReadSyncService.removeMany(['entry']);
      final unread = FeedHttp.markUnread(
        entryId: 'entry',
        auditSource: RemoteReadRequestSource.singleAction,
      );
      adapter.release.complete();
      await Future.wait([read, pending, unread]);
      expect(adapter.methods, ['POST', 'DELETE']);
      expect(
        GStorage.analysisEvents.values.whereType<Map>().map((e) => e['type']),
        contains('read_request_suppressed'),
      );
    },
  );
  test('unrelated articles remain concurrent', () async {
    final adapter = BlockingAdapter();
    Request.dio.httpClientAdapter = adapter;
    final first = FeedHttp.markRead(
      entryIds: ['a'],
      auditSource: RemoteReadRequestSource.articleController,
    );
    await adapter.entered.future;
    final second = await FeedHttp.markRead(
      entryIds: ['b'],
      auditSource: RemoteReadRequestSource.articleController,
    );
    expect(second, isA<Success<void>>());
    expect(adapter.calls, [
      ['a'],
      ['b'],
    ]);
    adapter.release.complete();
    await first;
  });
  test(
    'new account drain is independent and old completion cannot clear it',
    () async {
      final adapter = BlockingAdapter();
      Request.dio.httpClientAdapter = adapter;
      ReadSyncService.enqueue('entry', isInbox: false);
      final old = ReadSyncService.syncPendingReads();
      await adapter.entered.future;
      AccountSessionGuard.invalidate();
      await GStorage.localCache.clear();
      ReadSyncService.enqueue('entry', isInbox: false);
      final fresh = ReadSyncService.syncPendingReads();
      await fresh;
      expect(adapter.calls.length, 2);
      adapter.release.complete();
      await old;
      expect(ReadSyncService.pendingReadItems, isEmpty);
    },
  );
  test('legacy queue format drains without a destructive migration', () async {
    final adapter = SuccessAdapter();
    Request.dio.httpClientAdapter = adapter;
    await GStorage.localCache.put('pending_read_items', ['legacy-entry']);
    await ReadSyncService.syncPendingReads();
    expect(adapter.paths.length, 1);
    expect(ReadSyncService.pendingReadItems, isEmpty);
  });
  test(
    'account change suppresses an old request waiting for an article lock',
    () async {
      final adapter = BlockingAdapter();
      Request.dio.httpClientAdapter = adapter;
      final oldRead = FeedHttp.markRead(
        entryIds: ['entry'],
        auditSource: RemoteReadRequestSource.articleController,
      );
      await adapter.entered.future;
      final oldUnread = FeedHttp.markUnread(
        entryId: 'entry',
        auditSource: RemoteReadRequestSource.articleController,
      );
      AccountSessionGuard.invalidate();
      await GStorage.analysisEvents.clear();
      await FeedHttp.markRead(
        entryIds: ['entry'],
        auditSource: RemoteReadRequestSource.singleAction,
      );
      adapter.release.complete();
      await Future.wait([oldRead, oldUnread]);
      expect(adapter.methods, ['POST', 'POST']);
      final events = GStorage.analysisEvents.values.whereType<Map>().toList();
      expect(events.map((e) => e['type']), [
        'remote_mark_read_attempt',
        'remote_mark_read_result',
      ]);
      expect(
        events.every((e) => e['data']['source'] == 'singleAction'),
        isTrue,
      );
    },
  );
  test('old batch does not compensate into or modify a new account', () async {
    final adapter = _SecondBatchAdapter();
    Request.dio.httpClientAdapter = adapter;
    final articles = List.generate(
      51,
      (i) => ArticleModel(
        entryId: 'entry-$i',
        feedId: 'feed',
        feedTitle: 'Test',
        title: 'Synthetic',
        url: '',
      ),
    );
    final run = UndoService.markBatchAsRead(articles);
    await adapter.entered.future;
    AccountSessionGuard.invalidate();
    await GStorage.localCache.clear();
    final fresh = ReadSyncService.enqueue('entry-0', isInbox: false);
    adapter.release.complete();
    final result = await run;
    expect(result.changedArticles, isEmpty);
    expect(adapter.methods, ['POST', 'POST']);
    expect(ReadSyncService.isCurrent(fresh), isTrue);
    expect(GStorage.articleDb.isEmpty, isTrue);
  });
}
