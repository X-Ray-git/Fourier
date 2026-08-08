import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/account_session_guard.dart';
import 'package:fourier/services/auto_ai_queue_coordinator.dart';
import 'package:fourier/services/auto_filter_worker.dart';
import 'package:fourier/services/auto_readability_worker.dart';
import 'package:fourier/services/auto_summary_worker.dart';
import 'package:fourier/services/auto_translation_worker.dart';
import 'package:fourier/services/feed_readability_settings_service.dart';
import 'package:fourier/services/feed_translation_settings_service.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

ArticleModel _article(int index, {String content = ''}) {
  return ArticleModel(
    entryId: 'entry-$index',
    feedId: 'feed-1',
    feedTitle: '测试源',
    title: '文章 $index',
    url: 'https://example.com/$index',
    content: content,
    publishedAt: '2026-08-01T00:00:00Z',
  );
}

final String _longHtml = '<div><p>${'很长的有效正文内容。' * 40}</p></div>';

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    await FeedReadabilitySettingsService.setAutoReadability('feed-1', true);
    await FeedTranslationSettingsService.setAutoTranslate('feed-1', true);
    // 默认拦截下游 AI 真实调用，避免测试触发真实网络请求。
    AutoTranslationWorker.debugRunOverride = (article) async {};
    AutoSummaryWorker.debugRunOverride = (article) async {};
    AutoFilterWorker.debugRunOverride = (article) async {};
  });

  tearDown(() async {
    AutoReadabilityWorker.cancelProcessing();
    AutoTranslationWorker.cancelProcessing();
    AutoSummaryWorker.cancelProcessing();
    AutoFilterWorker.cancelProcessing();
    AutoReadabilityWorker.debugFetchOverride = null;
    AutoTranslationWorker.debugRunOverride = null;
    AutoSummaryWorker.debugRunOverride = null;
    AutoFilterWorker.debugRunOverride = null;
    await HiveTestHelper.tearDown();
  });

  group('AutoReadabilityWorker 成功标记', () {
    test('成功解析并持久化有效正文后才写入成功标记', () async {
      AutoReadabilityWorker.debugFetchOverride = (article) async => _longHtml;
      LocalArticleDbService.upsertOne(_article(0));

      AutoReadabilityWorker.enqueueOne(_article(0));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final persisted = GStorage.articleDb.get('entry-0');
      expect(persisted, isA<Map>());
      final content = (persisted as Map)['content'] as String;
      expect(content.length, greaterThan(100));
      // 成功标记已写入，且失败状态不存在。
      expect(GStorage.setting.get('readability_fetched_entry-0'), true);
      expect(GStorage.setting.get('readability_fetch_state_entry-0'), isNull);
    });

    test('抓取失败不会写成功标记，并登记可诊断的失败状态', () async {
      var calls = 0;
      AutoReadabilityWorker.debugFetchOverride = (article) async {
        calls++;
        return null; // 抓取失败
      };
      LocalArticleDbService.upsertOne(_article(1));

      AutoReadabilityWorker.enqueueOne(_article(1));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(calls, 1);
      expect(GStorage.setting.get('readability_fetched_entry-1'), isNull);
      final state = GStorage.setting.get('readability_fetch_state_entry-1');
      expect(state, isA<Map>());
      expect((state as Map)['attempts'], 1);
      expect((state)['lastError'], isA<String>());
    });

    test('解析出的正文未比摘要长时不写成功标记', () async {
      AutoReadabilityWorker.debugFetchOverride = (article) async => '<p>短</p>';
      LocalArticleDbService.upsertOne(_article(2, content: '<p>短</p>'));

      AutoReadabilityWorker.enqueueOne(_article(2, content: '<p>短</p>'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(GStorage.setting.get('readability_fetched_entry-2'), isNull);
      expect(
        GStorage.setting.get('readability_fetch_state_entry-2'),
        isA<Map>(),
      );
    });
  });

  group('AutoReadabilityWorker 已读语义', () {
    test('已开始抓取的文章完成前被标为已读，仍继续下游翻译和摘要', () async {
      final translated = <String>[];
      final summarized = <String>[];
      AutoTranslationWorker.debugRunOverride = (article) async {
        translated.add(article.entryId);
      };
      AutoSummaryWorker.debugRunOverride = (article) async {
        summarized.add(article.entryId);
      };
      AutoFilterWorker.debugRunOverride = (article) async {};

      var releaseFetch = Completer<void>();
      AutoReadabilityWorker.debugFetchOverride = (article) async {
        await releaseFetch.future;
        return _longHtml;
      };
      LocalArticleDbService.upsertOne(_article(3));

      AutoReadabilityWorker.enqueueOne(_article(3));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 抓取完成前把文章标为已读。
      LocalArticleDbService.setReadState('entry-3', true);

      releaseFetch.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 已开始的流水线继续进入翻译和摘要。
      expect(translated, contains('entry-3'));
      expect(summarized, contains('entry-3'));
    });

    test('尚在等待队列的文章被标为已读后取消', () async {
      final fetched = <String>[];
      final blocked = <Completer<void>>[];
      AutoReadabilityWorker.debugFetchOverride = (article) async {
        fetched.add(article.entryId);
        final completer = Completer<void>();
        blocked.add(completer);
        await completer.future;
        return _longHtml;
      };

      // 并发 3：前三篇立即开始，第四篇留在等待队列。
      for (var i = 0; i < 4; i++) {
        LocalArticleDbService.upsertOne(_article(10 + i));
        AutoReadabilityWorker.enqueueOne(_article(10 + i));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fetched, hasLength(3));

      // 等待中的第 4 篇被标为已读 → 出队时取消。
      LocalArticleDbService.setReadState('entry-13', true);

      for (final c in blocked) {
        c.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(fetched, hasLength(3));
      expect(fetched, isNot(contains('entry-13')));
    });
  });

  group('AutoReadabilityWorker 账号会话', () {
    test('账号 revision 失效后抓取结果不落库', () async {
      var releaseFetch = Completer<void>();
      AutoReadabilityWorker.debugFetchOverride = (article) async {
        await releaseFetch.future;
        return _longHtml;
      };
      LocalArticleDbService.upsertOne(_article(4));

      AutoReadabilityWorker.enqueueOne(_article(4));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 抓取完成前发生账号切换。
      AccountSessionGuard.beginAccountChange();
      AutoReadabilityWorker.cancelProcessing();
      releaseFetch.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 过期会话的结果不写入正文，也不写成功标记。
      final persisted = GStorage.articleDb.get('entry-4');
      expect(persisted, isA<Map>());
      expect(((persisted as Map)['content'] as String? ?? ''), isEmpty);
      expect(GStorage.setting.get('readability_fetched_entry-4'), isNull);
      AccountSessionGuard.finishAccountChange();
    });
  });
}
