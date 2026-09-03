import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/article_visual_context_service.dart';

import 'support/visual_image_test_helper.dart';

void main() {
  setUp(VisualImageTestHelper.setUp);
  tearDown(VisualImageTestHelper.tearDown);

  test('uses article cache loader in order and preserves exact bytes', () async {
    final calls = <String>[];
    ArticleVisualContextService.debugImageFileLoader = (id, url) async {
      calls.add('$id|$url');
      return VisualImageTestHelper.image;
    };
    final images = await ArticleVisualContextService.loadInlineImages('entry', [
      'first',
      'second',
    ]);
    expect(calls, ['entry|first', 'entry|second']);
    expect(
      images,
      List.filled(
        2,
        'data:image/png;base64,${base64Encode(VisualImageTestHelper.pngBytes)}',
      ),
    );
  });

  test('detects supported formats from bytes, not filename', () async {
    for (final entry in <String, List<int>>{
      'jpeg': [255, 216, 255, 224],
      'gif': ascii.encode('GIF89a'),
      'webp': [...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')],
    }.entries) {
      await VisualImageTestHelper.image.writeAsBytes(entry.value);
      final images = await ArticleVisualContextService.loadInlineImages(
        'entry',
        ['image.png'],
      );
      expect(
        images.single,
        'data:image/${entry.key};base64,${base64Encode(entry.value)}',
      );
    }
  });

  test('rejects HTML error pages instead of declaring them JPEG', () async {
    await VisualImageTestHelper.image.writeAsString(
      '<html>Access denied</html>',
    );
    await expectLater(
      ArticleVisualContextService.loadInlineImages('entry', ['image.jpg']),
      throwsStateError,
    );
  });

  test('rejects empty, oversized and excessive image input', () async {
    await VisualImageTestHelper.image.writeAsBytes([]);
    await expectLater(
      ArticleVisualContextService.loadInlineImages('entry', ['image']),
      throwsStateError,
    );
    final handle = await VisualImageTestHelper.image.open(mode: FileMode.write);
    await handle.truncate(ArticleVisualContextService.maxImageBytes + 1);
    await handle.close();
    await expectLater(
      ArticleVisualContextService.loadInlineImages('entry', ['image']),
      throwsStateError,
    );
    await expectLater(
      ArticleVisualContextService.loadInlineImages(
        'entry',
        List.filled(9, 'image'),
      ),
      throwsStateError,
    );
  });

  test(
    'rejects total payload over budget without silently dropping images',
    () async {
      final handle = await VisualImageTestHelper.image.open(
        mode: FileMode.write,
      );
      await handle.writeFrom([255, 216, 255]);
      await handle.truncate(ArticleVisualContextService.maxImageBytes);
      await handle.close();
      await expectLater(
        ArticleVisualContextService.loadInlineImages(
          'entry',
          List.filled(4, 'image'),
        ),
        throwsStateError,
      );
    },
  );
}
