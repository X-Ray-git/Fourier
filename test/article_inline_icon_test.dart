import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/widgets/article_inline_icon.dart';
import 'package:fourier/pages/article/widgets/html_chunk_card.dart';
import 'package:fourier/pages/article/widgets/macos_managed_animated_image.dart';
import 'package:fourier/services/article_image_cache_service.dart';
import 'package:fourier/utils/html_chunk_parser.dart';

void main() {
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
  );
  setUp(() {
    ArticleImageCacheService.setEnabledForTesting(false);
    ArticleInlineIcon.debugImageProvider = (_) => MemoryImage(pngBytes);
  });
  tearDown(() {
    ArticleImageCacheService.setEnabledForTesting(null);
    ArticleInlineIcon.debugImageProvider = null;
  });

  testWidgets('inline icon follows surrounding font and system text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: ArticleInlineIcon(
              articleId: 'inline-test',
              imageUrl: 'https://example.com/icon.png',
              label: '[doge]',
              textStyle: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 24);
    expect(image.height, 24);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('image failure leaves the original readable label', (
    tester,
  ) async {
    ArticleInlineIcon.debugImageProvider = (_) =>
        MemoryImage(Uint8List.fromList([0, 1, 2]));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArticleInlineIcon(
            articleId: 'inline-test',
            imageUrl: 'https://example.com/broken.png',
            label: '[doge]',
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.text('[doge]'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GIF inline icons reuse macOS managed playback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArticleInlineIcon(
            articleId: 'inline-test',
            imageUrl: 'https://example.com/icon.gif',
            label: '[doge]',
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    expect(
      find.byType(MacosManagedAnimatedImage),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('article icon preserves label during selection and copy', (
    tester,
  ) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync(
      '<p>Text before [doge] text after.</p>',
      sourceUrl: 'https://weibo.com/123/Abc',
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selected = value,
            child: SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'inline-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArticleInlineIcon), findsOneWidget);
    final paragraph = find
        .byType(RichText)
        .evaluate()
        .map((element) => element.renderObject)
        .whereType<RenderParagraph>()
        .firstWhere((p) => p.text.toPlainText().contains('Text before'));
    // The layout uses one placeholder; Flutter's patched selection path
    // substitutes rawText only when copying the selected content.
    expect(paragraph.text.toPlainText(), 'Text before \uFFFC text after.');
    WidgetSpan? iconSpan;
    paragraph.text.visitChildren((span) {
      if (span is WidgetSpan && span.rawText == '[doge]') iconSpan = span;
      return true;
    });
    expect(iconSpan?.alignment, PlaceholderAlignment.middle);
    Offset position(int offset) => paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    final mouse = await tester.startGesture(
      position(1),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(position(paragraph.text.toPlainText().length - 1));
    await mouse.up();
    await tester.pump();
    expect(selected?.plainText, contains('[doge]'));
    expect(selected?.plainText, isNot(contains('\uFFFC')));
  });

  testWidgets('heading icon inherits heading size', (tester) async {
    final chunk = HtmlChunkParser.parseSync(
      '<h2>Heading[doge]</h2>',
      sourceUrl: 'https://weibo.com/123/Abc',
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlChunkCard(
            chunk: chunk,
            articleId: 'inline-test',
            maxWidth: 600,
          ),
        ),
      ),
    );
    final icon = tester.widget<ArticleInlineIcon>(
      find.byType(ArticleInlineIcon),
    );
    expect(icon.textStyle.fontSize, 20);
    expect(icon.textStyle.fontWeight, FontWeight.bold);
  });

  testWidgets('RichText scales inline image exactly once', (tester) async {
    final chunk = HtmlChunkParser.parseSync(
      '<h2>Heading[doge]</h2>',
      sourceUrl: 'https://weibo.com/123/Abc',
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: HtmlChunkCard(
              chunk: chunk,
              articleId: 'inline-test',
              maxWidth: 600,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(pngBytes),
        tester.element(find.byType(ArticleInlineIcon)),
      ),
    );
    await tester.pumpAndSettle();
    final image = find.byType(Image);
    final height =
        tester.getBottomRight(image).dy - tester.getTopLeft(image).dy;
    expect(height, closeTo(36, 0.01));
  });
}
