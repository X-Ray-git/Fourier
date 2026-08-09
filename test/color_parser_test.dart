import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/utils/color_parser.dart';

void main() {
  group('ColorParser', () {
    test('parses supported hexadecimal CSS colors', () {
      expect(ColorParser.parseCssColor('#0f8'), const Color(0xFF00FF88));
      expect(ColorParser.parseCssColor('#123456'), const Color(0xFF123456));
      expect(ColorParser.parseCssColor('#12345680'), const Color(0x80123456));
    });

    test(
      'returns null instead of throwing for malformed hexadecimal colors',
      () {
        expect(ColorParser.parseCssColor('#0g0'), isNull);
        expect(ColorParser.parseCssColor('#12345z'), isNull);
        expect(ColorParser.parseCssColor('#'), isNull);
      },
    );
  });
}
