import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/article_filter_service.dart';
import 'package:fourier/services/llm_usage_ledger.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

ArticleModel _article() => ArticleModel(
  entryId: 'filter-entry',
  feedId: 'feed-1',
  feedTitle: '测试源',
  title: '测试文章',
  url: 'https://example.com/article',
  content: '<p>正文内容</p>',
  publishedAt: '2026-08-01T00:00:00Z',
);

Response<dynamic> _successResponse() => Response<dynamic>(
  requestOptions: RequestOptions(path: '/chat/completions'),
  statusCode: 200,
  data: {
    'choices': [
      {
        'message': {'content': '{"should_reject":false,"reason":"内容正常"}'},
      },
    ],
  },
);

DioException _requestFailure() => DioException(
  requestOptions: RequestOptions(path: '/chat/completions'),
  type: DioExceptionType.connectionError,
  message: 'temporary failure',
);

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    await GStorage.setting.put('deepseek_api_key', 'test-key');
    await GStorage.setting.put('auto_retry_max_count', 2);
    ArticleFilterService.debugRetryDelayOverride = (_) async {};
  });

  tearDown(() async {
    ArticleFilterService.debugPostOverride = null;
    ArticleFilterService.debugRetryDelayOverride = null;
    await HiveTestHelper.tearDown();
  });

  test('retries transient failures and records every attempt', () async {
    var attempts = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      attempts++;
      if (attempts < 3) throw _requestFailure();
      return _successResponse();
    };

    final result = await ArticleFilterService.filterArticle(_article());

    expect(result.shouldReject, isFalse);
    expect(result.reason, '内容正常');
    expect(attempts, 3);
    final usage = LlmUsageLedger.summarize(task: LlmTaskType.filter);
    expect(usage.requestCount, 3);
    expect(usage.failureCount, 2);
    expect(usage.successCount, 1);
  });

  test('rethrows after retry exhaustion without producing a result', () async {
    var attempts = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      attempts++;
      throw _requestFailure();
    };

    await expectLater(
      ArticleFilterService.filterArticle(_article()),
      throwsA(isA<DioException>()),
    );

    expect(attempts, 3);
    final usage = LlmUsageLedger.summarize(task: LlmTaskType.filter);
    expect(usage.requestCount, 3);
    expect(usage.failureCount, 3);
    expect(usage.successCount, 0);
  });
}
