import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/services/llm_config.dart';
import 'package:fourier/services/llm_usage_ledger.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test(
    'records usage metadata without storing prompt or response content',
    () async {
      final trace = LlmRequestTrace(
        task: LlmTaskType.relation,
        config: LlmConfig.relationDefault,
        prompt: 'private prompt body',
        batchId: 'batch-1',
        attempt: 2,
      );

      await trace.recordResponse({
        'id': 'provider-request',
        'created': 123,
        'model': 'deepseek-v4-flash-actual',
        'system_fingerprint': 'fp_test',
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': 'private response body'},
          },
        ],
        'usage': {
          'prompt_tokens': 100,
          'prompt_cache_hit_tokens': 75,
          'prompt_cache_miss_tokens': 25,
          'completion_tokens': 30,
          'total_tokens': 130,
          'completion_tokens_details': {'reasoning_tokens': 18},
        },
      });
      await trace.complete();

      expect(LlmUsageLedger.count, 1);
      final record = Map<String, dynamic>.from(
        GStorage.llmUsageEvents.get(trace.id) as Map,
      );
      expect(record['outcome'], 'success');
      expect(record['attempt'], 2);
      expect(record['cacheHitTokens'], 75);
      expect(record['cacheMissTokens'], 25);
      expect(record['reasoningTokens'], 18);
      expect(record['providerRequestId'], 'provider-request');
      expect(record['systemFingerprint'], 'fp_test');
      expect(record['promptHash'], hasLength(64));
      expect(record.values, isNot(contains('private prompt body')));
      expect(record.values, isNot(contains('private response body')));
    },
  );

  test('preserves billed usage when local response processing fails', () async {
    final trace = LlmRequestTrace(
      task: LlmTaskType.summary,
      config: LlmConfig.summaryDefault,
      prompt: 'prompt',
      articleId: 'article-1',
    );

    await trace.recordResponse({
      'choices': [
        {'finish_reason': 'length'},
      ],
      'usage': {
        'prompt_tokens': 20,
        'completion_tokens': 10,
        'total_tokens': 30,
      },
    });
    await trace.fail(const FormatException('truncated JSON'));

    final record = Map<String, dynamic>.from(
      GStorage.llmUsageEvents.get(trace.id) as Map,
    );
    expect(record['outcome'], 'processing_failed');
    expect(record['totalTokens'], 30);
    expect(record['finishReason'], 'length');
    expect(record['error'], contains('truncated JSON'));
  });

  test('records request failures even when no usage response exists', () async {
    final trace = LlmRequestTrace(
      task: LlmTaskType.filter,
      config: LlmConfig.filterDefault,
      prompt: 'prompt',
      articleId: 'article-2',
    );

    await trace.fail(StateError('network unavailable'));

    final record = Map<String, dynamic>.from(
      GStorage.llmUsageEvents.get(trace.id) as Map,
    );
    expect(record['outcome'], 'request_failed');
    expect(record, isNot(contains('totalTokens')));
  });

  test('summarizes all requests or one task without double counting', () async {
    final successful = LlmRequestTrace(
      task: LlmTaskType.translation,
      config: LlmConfig.translateDefault,
      prompt: 'translation prompt',
    );
    await successful.recordResponse({
      'usage': {
        'prompt_tokens': 100,
        'prompt_cache_hit_tokens': 80,
        'prompt_cache_miss_tokens': 20,
        'completion_tokens': 30,
        'total_tokens': 130,
        'completion_tokens_details': {'reasoning_tokens': 10},
      },
    });
    await successful.complete();

    final failed = LlmRequestTrace(
      task: LlmTaskType.filter,
      config: LlmConfig.filterDefault,
      prompt: 'filter prompt',
    );
    await failed.fail(StateError('offline'));

    final all = LlmUsageLedger.summarize();
    expect(all.requestCount, 2);
    expect(all.successCount, 1);
    expect(all.failureCount, 1);
    expect(all.totalTokens, 130);
    expect(all.cacheHitRate, 0.8);

    final translation = LlmUsageLedger.summarize(task: LlmTaskType.translation);
    expect(translation.requestCount, 1);
    expect(translation.successCount, 1);
    expect(translation.failureCount, 0);
    expect(translation.reasoningTokens, 10);
  });
}
