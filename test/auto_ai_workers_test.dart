import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/account_session_guard.dart';
import 'package:fourier/services/auto_filter_worker.dart';
import 'package:fourier/services/auto_summary_worker.dart';
import 'package:fourier/services/auto_translation_worker.dart';
import 'package:fourier/services/feed_translation_settings_service.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/services/translation_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

ArticleModel _article(int index) {
  return ArticleModel(
    entryId: 'entry-$index',
    feedId: 'feed-1',
    feedTitle: '测试源',
    title: '文章 $index',
    url: 'https://example.com/$index',
    content: '<p>内容 $index</p>',
    publishedAt: '2026-08-0${(index % 9) + 1}T00:00:00Z',
  );
}

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    // 清理跨用例残留的静态内存态。
    TranslationService.resetForAccountChange();
    SummaryService.resetForAccountChange();
    await GStorage.setting.put('llm_translate_concurrency', 2);
    await GStorage.setting.put('llm_summary_concurrency', 2);
    await GStorage.setting.put('llm_filter_concurrency', 2);
    await FeedTranslationSettingsService.setAutoTranslate('feed-1', true);
  });

  tearDown(() async {
    AutoTranslationWorker.cancelProcessing();
    AutoSummaryWorker.cancelProcessing();
    AutoFilterWorker.cancelProcessing();
    AutoTranslationWorker.debugRunOverride = null;
    AutoSummaryWorker.debugRunOverride = null;
    AutoFilterWorker.debugRunOverride = null;
    await HiveTestHelper.tearDown();
  });

  group('AutoTranslationWorker 滚动补位调度', () {
    test('最大并发不超过配置值 N', () async {
      final started = <String>[];
      final blocked = <Completer<void>>[];
      AutoTranslationWorker.debugRunOverride = (article) {
        started.add(article.entryId);
        final completer = Completer<void>();
        blocked.add(completer);
        return completer.future;
      };

      AutoTranslationWorker.enqueueIfEnabledMany(List.generate(5, _article));

      // 立即启动的并发数不超过 2。
      expect(AutoTranslationWorker.runningCount, 2);
      expect(started, hasLength(2));

      blocked[0].complete();
      blocked[1].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 完成两个后立即补位两个，总并发仍不超过 2。
      expect(AutoTranslationWorker.runningCount, 2);
      expect(started, hasLength(4));

      for (final completer in blocked.skip(2)) {
        completer.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoTranslationWorker.runningCount, 1);
      expect(started, hasLength(5));

      blocked.last.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoTranslationWorker.runningCount, 0);
      expect(AutoTranslationWorker.queueSize, 0);
    });

    test('任一任务完成后立即补位，不等待最慢任务', () async {
      final completers = <Completer<void>>[];
      final started = <String>[];
      AutoTranslationWorker.debugRunOverride = (article) {
        started.add(article.entryId);
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      AutoTranslationWorker.enqueueIfEnabledMany(List.generate(3, _article));

      expect(started, hasLength(2));
      // 完成其中一个任务（另一个慢任务仍在运行）→ 立即补位队列中的第 3 篇，
      // 不等待最慢任务完成。
      completers[0].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoTranslationWorker.runningCount, 2);
      expect(started, hasLength(3));

      for (final c in completers.toList()) {
        if (!c.isCompleted) c.complete();
      }
    });

    test('运行中修改并发数在后续补位时生效，不中断运行任务', () async {
      final completers = <Completer<void>>[];
      AutoTranslationWorker.debugRunOverride = (_) {
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      AutoTranslationWorker.enqueueIfEnabledMany(List.generate(4, _article));
      expect(AutoTranslationWorker.runningCount, 2);

      // 并发降到 1：正在运行的 2 个任务不受影响。
      await GStorage.setting.put('llm_translate_concurrency', 1);

      completers[0].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 补位受新并发限制：只剩 1 个任务运行，不再启动新任务。
      expect(AutoTranslationWorker.runningCount, 1);
      expect(AutoTranslationWorker.queueSize, 2);

      completers[1].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 运行中清空后按新并发 1 补位一篇。
      expect(AutoTranslationWorker.runningCount, 1);
      expect(AutoTranslationWorker.queueSize, 1);

      for (var i = 0; i < 10 && completers.any((c) => !c.isCompleted); i++) {
        for (final c in completers.toList()) {
          if (!c.isCompleted) c.complete();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(AutoTranslationWorker.runningCount, 0);
      expect(AutoTranslationWorker.queueSize, 0);
    });

    test('取消清空队列与运行中集合', () async {
      final completers = <Completer<void>>[];
      AutoTranslationWorker.debugRunOverride = (_) {
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      AutoTranslationWorker.enqueueIfEnabledMany(List.generate(4, _article));
      expect(AutoTranslationWorker.runningCount, 2);
      expect(AutoTranslationWorker.queueSize, 2);

      AutoTranslationWorker.cancelProcessing();
      expect(AutoTranslationWorker.runningCount, 0);
      expect(AutoTranslationWorker.queueSize, 0);

      for (final c in completers) {
        if (!c.isCompleted) c.complete();
      }
    });

    test('旧账号任务完成不会移除新账号同 entryId 的运行标记', () async {
      await GStorage.setting.put('llm_translate_concurrency', 1);
      final completers = <Completer<void>>[];
      AutoTranslationWorker.debugRunOverride = (_) {
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      AutoTranslationWorker.enqueueIfEnabled(_article(20));
      expect(AutoTranslationWorker.runningCount, 1);

      AccountSessionGuard.beginAccountChange();
      AutoTranslationWorker.cancelProcessing();
      TranslationService.resetForAccountChange();
      AccountSessionGuard.finishAccountChange();
      AutoTranslationWorker.enqueueIfEnabled(_article(20));
      expect(completers, hasLength(2));

      completers.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoTranslationWorker.runningCount, 1);

      completers.last.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoTranslationWorker.runningCount, 0);
    });
  });

  group('AutoSummaryWorker 滚动补位调度', () {
    test('最大并发不超过配置值，完成后立即补位', () async {
      final started = <String>[];
      final blocked = <Completer<void>>[];
      AutoSummaryWorker.debugRunOverride = (article) {
        started.add(article.entryId);
        final completer = Completer<void>();
        blocked.add(completer);
        return completer.future;
      };

      AutoSummaryWorker.enqueueIfNeededMany(List.generate(4, _article));
      expect(AutoSummaryWorker.runningCount, 2);
      expect(started, hasLength(2));

      blocked[0].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoSummaryWorker.runningCount, 2);
      expect(started, hasLength(3));

      // 完成全部（含补位启动的新任务），队列最终排空。
      for (var i = 0; i < 10 && blocked.any((c) => !c.isCompleted); i++) {
        for (final c in blocked.toList()) {
          if (!c.isCompleted) c.complete();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(AutoSummaryWorker.runningCount, 0);
      expect(AutoSummaryWorker.queueSize, 0);
    });

    test('取消前任务完成不会干扰新代次同 entryId 任务', () async {
      await GStorage.setting.put('llm_summary_concurrency', 1);
      final completers = <Completer<void>>[];
      AutoSummaryWorker.debugRunOverride = (_) {
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      AutoSummaryWorker.enqueueIfNeeded(_article(21));
      AutoSummaryWorker.cancelProcessing();
      AutoSummaryWorker.enqueueIfNeeded(_article(21));
      expect(completers, hasLength(2));

      completers.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoSummaryWorker.runningCount, 1);

      completers.last.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoSummaryWorker.runningCount, 0);
    });
  });

  group('AutoFilterWorker 滚动补位调度', () {
    test('最大并发不超过配置值，已读文章出队时跳过', () async {
      final started = <String>[];
      final blocked = <Completer<void>>[];
      AutoFilterWorker.debugRunOverride = (article) {
        started.add(article.entryId);
        final completer = Completer<void>();
        blocked.add(completer);
        return completer.future;
      };

      for (var i = 0; i < 4; i++) {
        LocalArticleDbService.upsertOne(_article(i));
        AutoFilterWorker.enqueue(_article(i));
      }
      // 并发 2：第 1、2 篇运行，第 3、4 篇等待。
      expect(AutoFilterWorker.runningCount, 2);
      expect(started, hasLength(2));

      // 等待中的第 3 篇被标为已读 → 出队时跳过。
      LocalArticleDbService.setReadState('entry-2', true);

      blocked[0].complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // entry-1 仍在运行，entry-2 被跳过，entry-3 补位进入运行。
      expect(AutoFilterWorker.runningCount, 2);
      expect(started, hasLength(3));
      expect(started, isNot(contains('entry-2')));

      for (final c in blocked) {
        if (!c.isCompleted) c.complete();
      }
    });

    test('取消清空队列，账号 revision 变更后新队列不再启动旧任务', () async {
      final started = <String>[];
      final blocked = <Completer<void>>[];
      AutoFilterWorker.debugRunOverride = (article) {
        started.add(article.entryId);
        final completer = Completer<void>();
        blocked.add(completer);
        return completer.future;
      };

      LocalArticleDbService.upsertOne(_article(0));
      AutoFilterWorker.enqueue(_article(0));
      expect(started, hasLength(1));

      // 账号切换：revision 失效并取消队列。
      AccountSessionGuard.beginAccountChange();
      AutoFilterWorker.cancelProcessing();
      expect(AutoFilterWorker.runningCount, 0);
      expect(AutoFilterWorker.queueSize, 0);

      // 新账号 session 内重新入队照常工作。
      AccountSessionGuard.finishAccountChange();
      LocalArticleDbService.upsertOne(_article(1));
      AutoFilterWorker.enqueue(_article(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(started, hasLength(2));

      for (final c in blocked) {
        if (!c.isCompleted) c.complete();
      }
    });

    test('旧过滤任务完成不会移除新代次同 entryId 的运行标记', () async {
      await GStorage.setting.put('llm_filter_concurrency', 1);
      final completers = <Completer<void>>[];
      AutoFilterWorker.debugRunOverride = (_) {
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      };

      LocalArticleDbService.upsertOne(_article(22));
      AutoFilterWorker.enqueue(_article(22));
      AutoFilterWorker.cancelProcessing();
      AutoFilterWorker.enqueue(_article(22));
      expect(completers, hasLength(2));

      completers.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoFilterWorker.runningCount, 1);

      completers.last.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(AutoFilterWorker.runningCount, 0);
    });
  });
}
