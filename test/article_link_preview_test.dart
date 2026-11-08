import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/widgets/article_link_preview.dart';
import 'package:fourier/pages/article/widgets/html_chunk_card.dart';
import 'package:fourier/utils/html_chunk_parser.dart';
import 'package:fourier/utils/macos_link_cursor.dart';

void main() {
  testWidgets(
    'bottom HTML link keeps hover and cursor when preview overlaps it',
    (tester) async {
      final url = ValueNotifier<String?>(null);
      final events = <bool>[];
      final chunk = HtmlChunkParser.parseSync(
        '<p>before <a href="https://example.com">LINK</a> after</p>',
      ).single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 30,
                  top: 570,
                  width: 600,
                  child: SelectionArea(
                    child: HtmlChunkCard(
                      chunk: chunk,
                      articleId: 'synthetic',
                      maxWidth: 600,
                      onLinkHover: (value, exit) {
                        events.add(exit);
                        url.value = exit ? null : value;
                      },
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ArticleLinkPreview(url: url),
                ),
              ],
            ),
          ),
        ),
      );
      final rich = find
          .byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('LINK'),
          )
          .last;
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      final start = paragraph.text.toPlainText().indexOf('LINK');
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 4),
          )
          .first;
      final point = paragraph.localToGlobal(box.toRect().center);
      expect(point.dy, greaterThan(568)); // Inside the preview's bottom 32px.
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(point);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          Platform.isMacOS
              ? MacOSLinkCursor.instance
              : SystemMouseCursors.click,
        );
        expect(url.value, 'https://example.com');
      }
      expect(events, [false]);
      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(events, [false, true]);
      expect(url.value, isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      url.dispose();
    },
  );

  testWidgets(
    'preview lets clicks and wheel signals reach underlying content',
    (tester) async {
      final url = ValueNotifier<String?>('https://example.com');
      var taps = 0;
      var scrolls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (_) => scrolls++,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ArticleLinkPreview(url: url),
              ),
            ],
          ),
        ),
      );
      const position = Offset(300, 584);
      await tester.tapAt(position);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, 20),
        ),
      );
      expect(taps, 1);
      expect(scrolls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      url.dispose();
    },
  );
}
