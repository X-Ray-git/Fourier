import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/common/widgets/implicitly_animated_list.dart';
import 'package:fourier/http/init.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/main/main_controller.dart';
import 'package:fourier/pages/timeline/filter_review_page.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/pages/subscriptions/subscriptions_controller.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';
import 'package:fourier/pages/widgets/article_card.dart';
import 'package:fourier/services/account_service.dart';
import 'package:fourier/services/article_image_cache_service.dart';
import 'package:fourier/services/article_state_notifier.dart';
import 'package:fourier/services/classification_updates.dart';
import 'package:fourier/services/folo_request_metadata.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/services/read_sync_service.dart';
import 'package:fourier/services/undo_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

class _LocalSubscriptions extends SubscriptionsController {
  int singleFeedRecounts = 0;
  @override
  void refreshUnreadCounts([String? eid]) {
    if (eid != null) singleFeedRecounts++;
    super.refreshUnreadCounts(eid);
  }

  @override
  Future<void> loadData() async => refreshUnreadCounts();
}

class _Timeline extends TimelineController {
  @override
  Future<void> loadFeedsThenArticles({bool showToast = true}) async {}
}

class _SuccessAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"code":0}',
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

ArticleModel _article(String id, int? time) => ArticleModel(
  entryId: id,
  feedId: 'synthetic-feed',
  feedTitle: 'Synthetic feed',
  title: 'Synthetic $id',
  url: '',
  isRejectedByAi: true,
  filteredAt: time,
);

List<String> _order(WidgetTester tester) {
  if (Platform.isMacOS) {
    return tester
        .widget<ImplicitlyAnimatedList<ArticleModel>>(
          find.byType(ImplicitlyAnimatedList<ArticleModel>),
        )
        .items
        .map((a) => a.entryId)
        .toList();
  }
  return tester
      .widgetList<ArticleCard>(find.byType(ArticleCard))
      .map((card) => card.article.entryId)
      .toList();
}

Future<void> _pumpReview(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // Keep restore notifications from mounting a detail subtree: this suite tests
  // the real review list and undo service, not article media or remote parsing.
  Get.put(MainController());
  await tester.pumpWidget(
    MaterialApp(
      builder: FlutterSmartDialog.init(),
      navigatorObservers: [FlutterSmartDialog.observer],
      home: const Scaffold(body: FilterReviewPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drainFeedback(WidgetTester tester) async {
  await tester.runAsync(
    () => SmartDialog.dismiss(status: SmartStatus.allToast),
  );
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  var metadataInitialized = false;
  setUp(() async {
    await HiveTestHelper.setUp();
    LocalArticleDbService.invalidateCache();
    if (!metadataInitialized) {
      await FoloRequestMetadata.init();
      metadataInitialized = true;
    }
    ArticleImageCacheService.setEnabledForTesting(false);
    Request();
    Request.dio.interceptors.clear();
    Request.dio.httpClientAdapter = _SuccessAdapter();
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.github.xraygit.fourier/badge'),
          (_) async => null,
        );
  });
  tearDown(() async {
    ReadSyncService.clear();
    UndoService.clear();
    Get.reset();
    ArticleImageCacheService.setEnabledForTesting(null);
    await HiveTestHelper.tearDown();
  });

  testWidgets(
    'one classification burst uses latest state, retains order and does not recount unread feeds',
    (tester) async {
      Get.put(AccountService());
      final timeline = Get.put<TimelineController>(_Timeline());
      final initial = [
        for (final id in ['a', 'b', 'c', 'd'])
          _article(id, 0).copyWith(isRejectedByAi: false),
      ];
      await tester.runAsync(
        () => GStorage.articleDb.putAll({
          for (final a in initial) a.entryId: a.toJson(),
        }),
      );
      timeline.allArticles.assignAll(initial);
      timeline.articles.assignAll(initial.reversed);
      final subs = Get.put<SubscriptionsController>(_LocalSubscriptions());
      await _pumpReview(tester);
      final delivered = <ClassificationBatch>[];
      final sub = ClassificationUpdates.batches.listen(delivered.add);
      addTearDown(sub.cancel);
      await tester.runAsync(
        () => GStorage.articleDb.putAll({
          for (final a in initial)
            a.entryId: a
                .copyWith(
                  isRejectedByAi: true,
                  filteredAt: a.entryId == 'd' ? 1 : 2,
                )
                .toJson(),
        }),
      );
      for (final id in ['b', 'd', 'a', 'c', 'd']) {
        ClassificationUpdates.enqueue(id);
      }
      // A manual decision lands after enqueue and before UI delivery.
      await tester.runAsync(
        () => GStorage.articleDb.put(
          'c',
          initial[2].copyWith(filterReviewed: true).toJson(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      expect(delivered, hasLength(1));
      expect(timeline.articles.map((a) => a.entryId), ['d', 'c', 'b', 'a']);
      expect(timeline.filterCount.value, 3);
      expect(_order(tester), ['d', 'a', 'b']);
      expect(timeline.articles[1].filterReviewed, true);
      expect(subs.rawUnreadFor('synthetic-feed'), 4);
      expect((subs as _LocalSubscriptions).singleFeedRecounts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final action in ['M', 'K', 'N']) {
    testWidgets('$action undo/redo restores review order, state and count', (
      tester,
    ) async {
      Get.put(AccountService());
      final timeline = Get.put<TimelineController>(_Timeline());
      final articles = [
        _article('a', 10),
        _article('b', 20),
        _article('c', 30),
      ];
      await tester.runAsync(() async {
        for (final a in articles) {
          await GStorage.articleDb.put(a.entryId, a.toJson());
        }
      });
      timeline.allArticles.assignAll(articles);
      timeline.filterCount.value = 3;
      final group = (await tester.runAsync(() async {
        final group = await FeedSilentSettingsService.createGroup('Daily');
        await FeedSilentSettingsService.setSilent(
          'synthetic-feed',
          true,
          groupId: group.id,
        );
        return group;
      }))!;
      final subs = Get.put<SubscriptionsController>(_LocalSubscriptions());
      await _pumpReview(tester);
      expect(_order(tester), ['a', 'b', 'c']);
      await tester.runAsync(() async {
        switch (action) {
          case 'M':
            UndoService.applyFilterReject(articles[1]);
          case 'K':
            UndoService.applyFilterKeep(articles[1]);
          case 'N':
            UndoService.applyMisclassify(articles[1], reject: false);
        }
        await ReadSyncService.syncPendingReads();
      });
      await tester.pumpAndSettle();
      expect(_order(tester), ['a', 'c']);
      expect(timeline.filterCount.value, 2);
      expect(subs.unreadForSilentGroup(group.id), action == 'K' ? 3 : 2);

      for (var cycle = 0; cycle < 2; cycle++) {
        await tester.runAsync(() async {
          expect((await UndoService.undoLastAction())?.entryId, 'b');
        });
        await _drainFeedback(tester);
        expect(_order(tester), ['a', 'b', 'c']);
        expect(timeline.filterCount.value, 3);
        expect(subs.unreadForSilentGroup(group.id), 3);
        final restored = LocalArticleDbService.readArticle('b')!;
        expect(restored.isRead, false);
        expect(restored.isRejectedByAi, true);
        expect(restored.filteredAt, 20);
        expect(restored.userAction, articles[1].userAction);
        final live = timeline.allArticles.firstWhere((a) => a.entryId == 'b');
        expect(live.isRead, false);
        expect(live.isRejectedByAi, true);

        if (cycle == 0) {
          await tester.runAsync(() async {
            await UndoService.redoLastAction();
            await ReadSyncService.syncPendingReads();
          });
          await _drainFeedback(tester);
          // Redo defers the read notification until the exit transition, with
          // a one-second fallback. Let that existing fan-out finish as well.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1100)),
          );
          await tester.pumpAndSettle();
          expect(_order(tester), ['a', 'c']);
          expect(timeline.filterCount.value, 2);
          expect(subs.unreadForSilentGroup(group.id), action == 'K' ? 3 : 2);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets(
    'incremental restores and classification batches keep full-load order without a count reload',
    (tester) async {
      // Deliberately omit TimelineController: ordering cannot rely on its count.
      final articles = [
        _article('b', null),
        _article('a', null),
        _article('d', 20),
        _article('c', 20),
      ];
      await tester.runAsync(() async {
        for (final a in articles) {
          await GStorage.articleDb.put(a.entryId, a.toJson());
        }
      });
      await _pumpReview(tester);
      expect(_order(tester), ['a', 'b', 'c', 'd']);
      for (final id in ['a', 'c']) {
        final original = articles.firstWhere((a) => a.entryId == id);
        await tester.runAsync(
          () => GStorage.articleDb.put(
            id,
            original.copyWith(isRead: true).toJson(),
          ),
        );
        ArticleStateNotifier.tick(id);
        await tester.pumpAndSettle();
        expect(_order(tester), isNot(contains(id)));
        await tester.runAsync(
          () => GStorage.articleDb.put(id, original.toJson()),
        );
        ArticleStateNotifier.tick(id);
        await tester.pumpAndSettle();
        expect(_order(tester), ['a', 'b', 'c', 'd']);
      }
      final inserted = _article('middle', 10);
      await tester.runAsync(
        () => GStorage.articleDb.put(inserted.entryId, inserted.toJson()),
      );
      ClassificationUpdates.enqueue(inserted.entryId);
      ClassificationUpdates.enqueue(inserted.entryId);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      expect(_order(tester), ['a', 'b', 'middle', 'c', 'd']);
      await tester.runAsync(
        () => GStorage.articleDb.put('d', _article('d', 5).toJson()),
      );
      ArticleStateNotifier.tick('d');
      await tester.pumpAndSettle();
      expect(_order(tester), ['a', 'b', 'd', 'middle', 'c']);
      LocalArticleDbService.invalidateCache();
      ArticleStateNotifier.tickAll();
      await tester.pumpAndSettle();
      expect(_order(tester), ['a', 'b', 'd', 'middle', 'c']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
