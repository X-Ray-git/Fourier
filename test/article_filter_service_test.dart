import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/article_filter_service.dart';
import 'package:fourier/services/article_visual_context_service.dart';
import 'package:fourier/services/llm_config.dart';
import 'package:fourier/services/llm_usage_ledger.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';
import 'support/visual_image_test_helper.dart';

ArticleModel _article() => ArticleModel(
  entryId: 'filter-entry',
  feedId: 'feed-1',
  feedTitle: '测试源',
  title: '测试文章',
  url: 'https://example.com/article',
  content: '<p>正文内容</p>',
  publishedAt: '2026-08-01T00:00:00Z',
);

ArticleModel _imageArticle() => ArticleModel(
  entryId: 'filter-image-entry',
  feedId: 'feed-1',
  feedTitle: '测试源',
  title: '图片文章',
  url: 'https://example.com/article',
  content: '<p>正文很短</p><img src="https://example.com/evidence.png">',
  publishedAt: '2026-08-01T00:00:00Z',
);

Response<dynamic> _successResponse([
  String content = '{"should_reject":false,"reason":"内容正常"}',
]) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/chat/completions'),
  statusCode: 200,
  data: {
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  },
);

DioException _requestFailure() => DioException(
  requestOptions: RequestOptions(path: '/chat/completions'),
  type: DioExceptionType.connectionError,
  message: 'temporary failure',
);

DioException _contentRiskFailure() => DioException(
  requestOptions: RequestOptions(path: '/chat/completions'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/chat/completions'),
    statusCode: 400,
    data: {
      'error': {'message': 'Content Exists Risk'},
    },
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    await VisualImageTestHelper.setUp();
    await GStorage.setting.put('deepseek_api_key', 'test-key');
    await GStorage.setting.put('auto_retry_max_count', 2);
    ArticleFilterService.debugRetryDelayOverride = (_) async {};
  });

  tearDown(() async {
    ArticleFilterService.debugPostOverride = null;
    ArticleFilterService.debugRetryDelayOverride = null;
    await HiveTestHelper.tearDown();
    await VisualImageTestHelper.tearDown();
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

  test('does not retry deterministic provider content rejection', () async {
    var attempts = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      attempts++;
      throw _contentRiskFailure();
    };

    await expectLater(
      ArticleFilterService.filterArticle(_article(), automatic: true),
      throwsA(isA<DioException>()),
    );

    expect(attempts, 1);
  });

  test('hands image-centric filtering to the configured vision model', () async {
    final models = <String>[];
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      final body = Map<String, dynamic>.from(data! as Map);
      models.add(body['model'] as String);
      if (models.length == 1) {
        return _successResponse(
          '{"needs_visual_context":true,"should_reject":false,"reason":"需要图片"}',
        );
      }
      final messages = body['messages'] as List<dynamic>;
      final userMessage = Map<String, dynamic>.from(messages.last as Map);
      expect(userMessage['content'], isA<List<dynamic>>());
      expect(
        userMessage['content'][1]['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
      return _successResponse('{"should_reject":false,"reason":"图片包含有效信息"}');
    };

    final result = await ArticleFilterService.filterArticle(_imageArticle());

    expect(result.shouldReject, isFalse);
    expect(result.reason, '图片包含有效信息');
    expect(models, [LlmConfig.flashModel, LlmConfig.flashModel]);
  });

  test('does not use vision when text evidence is sufficient', () async {
    ArticleVisualContextService.debugImageFileLoader = (_, _) async =>
        throw StateError('must not download');
    var requests = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      requests++;
      return _successResponse(
        '{"needs_visual_context":false,"should_reject":false,"reason":"文字证据充分"}',
      );
    };

    final result = await ArticleFilterService.filterArticle(_imageArticle());

    expect(requests, 1);
    expect(result.shouldReject, isFalse);
    expect(result.reason, '文字证据充分');
  });

  test('reuses prepared images across existing retries', () async {
    var loads = 0;
    var requests = 0;
    ArticleVisualContextService.debugImageFileLoader = (_, _) async {
      loads++;
      return VisualImageTestHelper.image;
    };
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      requests++;
      final body = Map<String, dynamic>.from(data! as Map);
      final messages = body['messages'] as List<dynamic>;
      final userMessage = Map<String, dynamic>.from(messages.last as Map);
      final isVisualRequest = userMessage['content'] is List<dynamic>;
      if (!isVisualRequest) {
        return _successResponse(
          '{"needs_visual_context":true,"should_reject":false,"reason":"需要图片"}',
        );
      }
      if (requests == 2) throw _requestFailure();
      return _successResponse();
    };
    final result = await ArticleFilterService.filterArticle(_imageArticle());
    expect(result.shouldReject, isFalse);
    expect(requests, 4);
    expect(loads, 1);
  });

  test('image preparation failure conservatively keeps article', () async {
    await GStorage.setting.put('auto_retry_max_count', 0);
    ArticleVisualContextService.debugImageFileLoader = (_, _) async =>
        throw StateError('offline');
    var requests = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      requests++;
      return _successResponse(
        '{"needs_visual_context":true,"should_reject":true,"reason":"文字不足"}',
      );
    };
    final result = await ArticleFilterService.filterArticle(_imageArticle());
    expect(result.shouldReject, isFalse);
    expect(requests, 1);
  });

  test(
    'missing handoff field falls back to vision for image articles',
    () async {
      var requests = 0;
      ArticleFilterService.debugPostOverride = (_, {data, options}) async {
        requests++;
        if (requests == 1) {
          return _successResponse(
            '{"should_reject":true,"reason":"旧 Prompt 返回结构"}',
          );
        }
        return _successResponse(
          '{"should_reject":false,"reason":"视觉证据推翻文本判断"}',
        );
      };

      final result = await ArticleFilterService.filterArticle(_imageArticle());

      expect(requests, 2);
      expect(result.shouldReject, isFalse);
      expect(result.reason, '视觉证据推翻文本判断');
    },
  );

  test('vision failure conservatively keeps the article', () async {
    await GStorage.setting.put('auto_retry_max_count', 0);
    var requests = 0;
    ArticleFilterService.debugPostOverride = (_, {data, options}) async {
      requests++;
      if (requests == 1) {
        return _successResponse(
          '{"needs_visual_context":true,"should_reject":false,"reason":"需要图片"}',
        );
      }
      throw _requestFailure();
    };

    final result = await ArticleFilterService.filterArticle(_imageArticle());

    expect(requests, 2);
    expect(result.shouldReject, isFalse);
    expect(result.reason, contains('视觉信息暂不可用'));
  });
}
