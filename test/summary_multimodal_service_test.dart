import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/llm_failure_policy.dart';
import 'package:fourier/services/llm_usage_ledger.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/services/article_visual_context_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';
import 'support/visual_image_test_helper.dart';

ArticleModel _imageArticle() => ArticleModel(
  entryId: 'summary-image-entry',
  feedId: 'feed-1',
  feedTitle: '测试源',
  title: '图片文章',
  url: 'https://example.com/article',
  content: '<p>请看图片</p><img src="https://example.com/evidence.png">',
  publishedAt: '2026-08-01T00:00:00Z',
);

Response<dynamic> _response(String content) => Response<dynamic>(
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
  message: 'vision unavailable',
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
    await GStorage.setting.put('auto_retry_max_count', 0);
    SummaryService.resetForAccountChange();
  });

  tearDown(() async {
    SummaryService.debugPostOverride = null;
    SummaryService.resetForAccountChange();
    await HiveTestHelper.tearDown();
    await VisualImageTestHelper.tearDown();
  });

  test(
    'uses the configured vision model when text requests visual context',
    () async {
      final models = <String>[];
      SummaryService.debugPostOverride = (_, {data, options}) async {
        final body = Map<String, dynamic>.from(data! as Map);
        models.add(body['model'] as String);
        if (models.length == 1) {
          return _response(
            '{"needs_visual_context":true,"summary":"图片承载核心内容"}',
          );
        }
        final messages = body['messages'] as List<dynamic>;
        final userMessage = Map<String, dynamic>.from(messages.last as Map);
        expect(userMessage['content'], isA<List<dynamic>>());
        expect(
          userMessage['content'][1]['image_url']['url'],
          startsWith('data:image/png;base64,'),
        );
        return _response('{"summary":"图片展示了关键性能表格"}');
      };

      final record = await SummaryService.summarizeArticle(
        _imageArticle(),
        deferRelationTail: true,
      );

      expect(record.status, SummaryStatus.done);
      expect(record.summaryText, '图片展示了关键性能表格');
      expect(models, ['deepseek-v4-flash', 'deepseek-v4-flash-vision-exp']);
    },
  );

  test('does not use vision when the text summary is sufficient', () async {
    ArticleVisualContextService.debugImageFileLoader = (_, _) async =>
        throw StateError('must not download');
    var requests = 0;
    SummaryService.debugPostOverride = (_, {data, options}) async {
      requests++;
      return _response(
        '{"needs_visual_context":false,"summary":"正文已经完整说明核心内容"}',
      );
    };

    final record = await SummaryService.summarizeArticle(
      _imageArticle(),
      deferRelationTail: true,
    );

    expect(requests, 1);
    expect(record.status, SummaryStatus.done);
    expect(record.summaryText, '正文已经完整说明核心内容');
  });

  test(
    'content rejection stops retries and persists a readable error',
    () async {
      await GStorage.setting.put('auto_retry_max_count', 3);
      var requests = 0;
      SummaryService.debugPostOverride = (_, {data, options}) async {
        requests++;
        throw _contentRiskFailure();
      };

      final record = await SummaryService.summarizeArticle(
        _imageArticle(),
        deferRelationTail: true,
        automatic: true,
      );

      expect(requests, 1);
      expect(record.status, SummaryStatus.error);
      expect(record.errorMessage, LlmFailurePolicy.contentRiskMessage);
    },
  );

  test('manual summary retries clear an automatic retry block', () async {
    const decision = LlmFailureDecision(
      code: LlmFailureCode.contentRisk,
      userMessage: LlmFailurePolicy.contentRiskMessage,
    );
    await LlmAutoRetryBlockService.block(
      LlmTaskType.summary,
      _imageArticle().entryId,
      decision,
    );
    SummaryService.debugPostOverride = (_, {data, options}) async =>
        _response('{"needs_visual_context":false,"summary":"手动重试成功"}');

    final record = await SummaryService.summarizeArticle(
      _imageArticle(),
      deferRelationTail: true,
    );

    expect(record.summaryText, '手动重试成功');
    expect(
      LlmAutoRetryBlockService.isBlocked(
        LlmTaskType.summary,
        _imageArticle().entryId,
      ),
      isFalse,
    );
  });

  test('image download failure retains existing text fallback', () async {
    ArticleVisualContextService.debugImageFileLoader = (_, _) async =>
        throw StateError('offline');
    var requests = 0;
    SummaryService.debugPostOverride = (_, {data, options}) async {
      requests++;
      return _response('{"needs_visual_context":true,"summary":"文本降级结果"}');
    };
    final record = await SummaryService.summarizeArticle(
      _imageArticle(),
      deferRelationTail: true,
    );
    expect(requests, 1);
    expect(record.summaryText, '文本降级结果');
    expect(record.status, SummaryStatus.done);
  });

  test('keeps the text summary when the vision request fails', () async {
    var requests = 0;
    SummaryService.debugPostOverride = (_, {data, options}) async {
      requests++;
      if (requests == 1) {
        return _response(
          '{"needs_visual_context":true,"summary":"当前只能确认文章附有图片"}',
        );
      }
      throw _requestFailure();
    };

    final record = await SummaryService.summarizeArticle(
      _imageArticle(),
      deferRelationTail: true,
    );

    expect(requests, 2);
    expect(record.status, SummaryStatus.done);
    expect(record.summaryText, '当前只能确认文章附有图片');
  });
}
