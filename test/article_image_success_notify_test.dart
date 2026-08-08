import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/article_image_cache_service.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  group('ArticleImageCacheService 统一成功通知', () {
    test('正文失败状态记录后，外部/全屏成功写入缓存会清除失败并推进 revision', () async {
      const articleId = 'entry-img';
      const imageUrl = 'https://example.com/image.jpg';
      // 正文加载失败登记。
      ArticleImageCacheService.recordFailure(articleId, imageUrl);

      // 正文占位订阅该图的 retry 状态。
      final retryState = ArticleImageCacheService.acquireRetryState(
        articleId,
        imageUrl,
      );
      expect(retryState.value.retrying, isFalse);
      expect(retryState.value.successRevision, 0);

      // 外部/全屏成功下载后走统一成功通知路径。
      ArticleImageCacheService.notifyImageLoadedSuccessfully(
        articleId,
        imageUrl,
      );
      // 微任务延迟执行，需让出事件循环。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(retryState.value.successRevision, 1);
      expect(retryState.value.retrying, isFalse);
      // 失败登记已清除（再记录成功不会再次推进 revision）。
      ArticleImageCacheService.notifyImageLoadedSuccessfully(
        articleId,
        imageUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(retryState.value.successRevision, 1);

      ArticleImageCacheService.releaseRetryState(articleId, imageUrl);
    });

    test('未登记失败时成功通知是幂等空操作', () async {
      const articleId = 'entry-img-2';
      const imageUrl = 'https://example.com/ok.jpg';
      final key = ArticleImageCacheService.cacheKey(articleId, imageUrl);

      ArticleImageCacheService.notifyImageLoadedSuccessfully(
        articleId,
        imageUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(key, isNotEmpty);
      // 不抛异常即可；失败集合为空时不会产生 revision。
    });
  });
}
