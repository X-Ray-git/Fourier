import 'package:fourier/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson decodes cached title without touching translated HTML', () {
    final record = TranslationRecord.fromJson({
      'status': 'done',
      'translatedTitle': 'AI&ensp;News &middot; Daily',
      'translatedContent': '<p>AI &ensp; News</p>',
      'updatedAt': 1,
    });

    expect(record.translatedTitle, 'AI News \u00B7 Daily');
    expect(record.translatedContent, '<p>AI &ensp; News</p>');
  });
}
