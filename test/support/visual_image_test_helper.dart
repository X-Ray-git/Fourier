import 'dart:convert';
import 'dart:io';

import 'package:fourier/services/article_visual_context_service.dart';

class VisualImageTestHelper {
  static late Directory directory;
  static late File image;
  static final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSfkAAAAASUVORK5CYII=',
  );

  static Future<void> setUp() async {
    directory = await Directory.systemTemp.createTemp('fourier-visual-test-');
    image = await File('${directory.path}/cached-image.bin')
        .writeAsBytes(pngBytes);
    ArticleVisualContextService.debugImageFileLoader = (_, _) async => image;
  }

  static Future<void> tearDown() async {
    ArticleVisualContextService.debugImageFileLoader = null;
    await directory.delete(recursive: true);
  }
}
