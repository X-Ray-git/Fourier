import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/llm_failure_policy.dart';
import 'package:fourier/services/llm_usage_ledger.dart';

import 'support/hive_test_helper.dart';

DioException _contentRiskError({Object? data}) => DioException(
  requestOptions: RequestOptions(path: '/chat/completions'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/chat/completions'),
    statusCode: 400,
    data:
        data ??
        {
          'error': {
            'message': 'Content Exists Risk',
            'type': 'invalid_request_error',
          },
        },
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('classifies DeepSeek content rejection from map and encoded body', () {
    expect(
      LlmFailurePolicy.classify(_contentRiskError())?.code,
      LlmFailureCode.contentRisk,
    );
    expect(
      LlmFailurePolicy.classify(
        _contentRiskError(
          data: utf8.encode(
            jsonEncode({
              'error': {'message': 'Content Exists Risk'},
            }),
          ),
        ),
      )?.userMessage,
      LlmFailurePolicy.contentRiskMessage,
    );
  });

  test('does not classify transient transport failures', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/chat/completions'),
      type: DioExceptionType.connectionError,
      message: 'temporary failure',
    );
    expect(LlmFailurePolicy.classify(error), isNull);
    expect(LlmFailurePolicy.displayMessage(error), 'temporary failure');
  });

  test('persists task-specific automatic retry blocks', () async {
    final decision = LlmFailurePolicy.classify(_contentRiskError())!;
    await LlmAutoRetryBlockService.block(
      LlmTaskType.summary,
      'article-1',
      decision,
    );

    expect(
      LlmAutoRetryBlockService.isBlocked(LlmTaskType.summary, 'article-1'),
      isTrue,
    );
    expect(
      LlmAutoRetryBlockService.isBlocked(LlmTaskType.translation, 'article-1'),
      isFalse,
    );

    await LlmAutoRetryBlockService.clear(LlmTaskType.summary, 'article-1');
    expect(
      LlmAutoRetryBlockService.isBlocked(LlmTaskType.summary, 'article-1'),
      isFalse,
    );
  });
}
