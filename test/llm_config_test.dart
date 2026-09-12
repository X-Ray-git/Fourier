import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/services/llm_config.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('copyWith changes one LLM setting without touching the others', () {
    const original = LlmConfig(
      model: 'model-a',
      thinking: false,
      reasoningEffort: 'high',
      temperature: 0.2,
      maxTokens: 2048,
      concurrency: 16,
    );

    final updated = original.copyWith(model: 'model-b');

    expect(updated.model, 'model-b');
    expect(updated.thinking, original.thinking);
    expect(updated.reasoningEffort, original.reasoningEffort);
    expect(updated.temperature, original.temperature);
    expect(updated.maxTokens, original.maxTokens);
    expect(updated.concurrency, original.concurrency);
  });

  test('request body explicitly disables thinking when configured off', () {
    const config = LlmConfig(
      model: 'model-a',
      thinking: false,
      reasoningEffort: 'max',
      temperature: 0.2,
      maxTokens: 2048,
    );

    final body = config.toRequestBody();

    expect(body['thinking'], {'type': 'disabled'});
    expect(body.containsKey('reasoning_effort'), isFalse);
  });

  test(
    'request body enables thinking and sends its effort when configured on',
    () {
      const config = LlmConfig(
        model: 'model-a',
        thinking: true,
        reasoningEffort: 'max',
        temperature: 0.2,
        maxTokens: 2048,
      );

      final body = config.toRequestBody();

      expect(body['thinking'], {'type': 'enabled'});
      expect(body['reasoning_effort'], 'max');
    },
  );

  test('load rejects concurrency values that would stall a worker', () async {
    await GStorage.setting.put('llm_filter_concurrency', 0);

    expect(
      LlmConfig.loadFilter().concurrency,
      LlmConfig.filterDefault.concurrency,
    );

    await GStorage.setting.put('llm_filter_concurrency', 1025);
    expect(
      LlmConfig.loadFilter().concurrency,
      LlmConfig.filterDefault.concurrency,
    );
  });

  test('relation defaults use the expanded output budget', () {
    expect(LlmConfig.translateDefault.model, LlmConfig.flashModel);
    expect(LlmConfig.summaryDefault.model, LlmConfig.flashModel);
    expect(LlmConfig.filterDefault.model, LlmConfig.flashModel);
    expect(LlmConfig.relationDefault.model, LlmConfig.flashModel);
    expect(LlmConfig.relationDefault.maxTokens, 32768);
    expect(LlmConfig.relationDefault.concurrency, 1);
  });

  test(
    'vision model settings default, persist, and reset independently',
    () async {
      expect(LlmConfig.loadSummaryVisionModel(), LlmConfig.defaultVisionModel);
      expect(LlmConfig.loadFilterVisionModel(), LlmConfig.defaultVisionModel);

      await LlmConfig.saveSummaryVisionModel(LlmConfig.defaultVisionModel);
      await LlmConfig.saveFilterVisionModel(LlmConfig.defaultVisionModel);

      expect(
        GStorage.setting.get(LlmConfig.summaryVisionModelKey),
        LlmConfig.defaultVisionModel,
      );
      expect(
        GStorage.setting.get(LlmConfig.filterVisionModelKey),
        LlmConfig.defaultVisionModel,
      );

      await LlmConfig.resetSummary();
      expect(
        GStorage.setting.containsKey(LlmConfig.summaryVisionModelKey),
        isFalse,
      );
      expect(
        GStorage.setting.containsKey(LlmConfig.filterVisionModelKey),
        isTrue,
      );
    },
  );

  test('legacy Flash aliases migrate to the canonical V4.1 model', () async {
    await GStorage.setting.putAll({
      'llm_translate_model': 'deepseek-v4-flash',
      'llm_summary_model': 'deepseek-v4-flash-vision-exp',
      LlmConfig.summaryVisionModelKey: 'deepseek-v4-flash-vision-exp',
    });

    expect(LlmConfig.loadTranslate().model, LlmConfig.flashModel);
    expect(LlmConfig.loadSummary().model, LlmConfig.flashModel);
    expect(LlmConfig.loadSummaryVisionModel(), LlmConfig.flashModel);

    await LlmConfig.migrateLegacyModelAliases();

    expect(GStorage.setting.get('llm_translate_model'), LlmConfig.flashModel);
    expect(GStorage.setting.get('llm_summary_model'), LlmConfig.flashModel);
    expect(
      GStorage.setting.get(LlmConfig.summaryVisionModelKey),
      LlmConfig.flashModel,
    );
  });

  test(
    'unsupported stored vision models fall back and cannot be saved',
    () async {
      await GStorage.setting.put(
        LlmConfig.summaryVisionModelKey,
        'unsupported-vision-model',
      );

      expect(LlmConfig.loadSummaryVisionModel(), LlmConfig.defaultVisionModel);
      await expectLater(
        LlmConfig.saveSummaryVisionModel('unsupported-vision-model'),
        throwsArgumentError,
      );
    },
  );
}
