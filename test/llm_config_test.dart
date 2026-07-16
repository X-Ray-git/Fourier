import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/services/llm_config.dart';

void main() {
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
}
