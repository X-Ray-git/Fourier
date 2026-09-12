import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/pages/article/widgets/html_chunk_card.dart';
import 'package:fourier/utils/html_chunk_parser.dart';
import 'package:fourier/utils/selectable_html_compatibility.dart';

void main() {
  test('text flow keeps inline markup and explicit block boundaries', () {
    expect(
      SelectableHtmlCompatibility.normalizeTextFlow(
        '<p>First <strong>bold</strong> paragraph.</p>'
        '<div>Second <em>italic</em> paragraph.</div>',
      ),
      'First <strong>bold</strong> paragraph.<br><br>'
      'Second <em>italic</em> paragraph.',
    );
  });

  testWidgets('macOS mouse drag selects rendered article paragraph', (
    tester,
  ) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync(
      '<p>Fourier article selection remains available on macOS.</p>',
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
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).last,
    );
    Offset textPosition(int offset) => paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );

    final mouse = await tester.startGesture(
      textPosition(2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(textPosition(26));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(selected?.plainText, contains('urier article selection'));
  });

  testWidgets('macOS mouse drag selects rendered article heading', (
    tester,
  ) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync(
      '<h2>Selectable Fourier heading</h2>',
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
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).last,
    );
    Offset textPosition(int offset) => paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    final mouse = await tester.startGesture(
      textPosition(1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(textPosition(18));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(selected?.plainText, contains('electable Fourier'));
  });

  for (final sample in <String, String>{
    'blockquote': '<blockquote><p>Fourier quoted selection remains available.</p></blockquote>',
    'list':
        '<ul><li><p>Fourier listed selection remains available.</p></li></ul>',
  }.entries) {
    testWidgets('macOS mouse drag selects rendered ${sample.key}', (
      tester,
    ) async {
      SelectedContent? selected;
      final chunk = HtmlChunkParser.parseSync(sample.value).single;

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
                  articleId: 'selection-test',
                  maxWidth: 600,
                ),
              ),
            ),
          ),
        ),
      );

      final target = find.byType(RichText).evaluate().firstWhere((element) {
        final paragraph = element.renderObject as RenderParagraph;
        return paragraph.text.toPlainText().contains('Fourier');
      });
      final paragraph = target.renderObject as RenderParagraph;
      Offset textPosition(int offset) => paragraph.localToGlobal(
        paragraph.getOffsetForCaret(
              TextPosition(offset: offset),
              const Rect.fromLTWH(0, 0, 2, 20),
            ) +
            Offset(0, paragraph.preferredLineHeight - 2),
      );
      final mouse = await tester.startGesture(
        textPosition(2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(textPosition(20));
      await tester.pump();
      await mouse.up();
      await tester.pump();

      expect(selected?.plainText, contains('urier'));
    });
  }

  testWidgets(
    'macOS blockquote keeps source br separators without multiplying them',
    (tester) async {
      final chunk = HtmlChunkParser.parseSync(
        '<blockquote>First sentence by <a href="https://example.com">@author</a>.<br><br>Second sentence<br><br>Third sentence</blockquote>',
      ).single;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SelectionArea(
              child: SizedBox(
                width: 600,
                child: HtmlChunkCard(
                  chunk: chunk,
                  articleId: 'selection-test',
                  maxWidth: 600,
                ),
              ),
            ),
          ),
        ),
      );

      final paragraph = find
          .byType(RichText)
          .evaluate()
          .map((element) => element.renderObject)
          .whereType<RenderParagraph>()
          .firstWhere(
            (paragraph) => paragraph.text.toPlainText().contains('First'),
          );

      expect(
        paragraph.text.toPlainText(),
        'First sentence by @author.\n\nSecond sentence\n\nThird sentence',
      );
    },
  );

  testWidgets('Android long press still selects rendered article text', (
    tester,
  ) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync(
      '<p>Fourier Android article selection remains available.</p>',
    ).single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selected = value,
            child: SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).last,
    );
    final wordPosition = paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            const TextPosition(offset: 25),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    await tester.longPressAt(wordPosition);
    await tester.pump();

    expect(selected?.plainText, contains('selection'));
  });

  testWidgets('Android long press selects rendered list text', (tester) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync(
      '<ol><li><p>Fourier Android listed selection remains available.</p></li></ol>',
    ).single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selected = value,
            child: SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final target = find.byType(RichText).evaluate().firstWhere((element) {
      final paragraph = element.renderObject as RenderParagraph;
      return paragraph.text.toPlainText().contains('Fourier');
    });
    final paragraph = target.renderObject as RenderParagraph;
    final wordPosition = paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            const TextPosition(offset: 28),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    await tester.longPressAt(wordPosition);
    await tester.pump();

    expect(selected?.plainText, contains('selection'));
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform keeps selectable list items on separate text flows',
      (tester) async {
        final chunk = HtmlChunkParser.parseSync('''
<ul>
  <li><p>First short list item.</p></li>
  <li><p>Second short list item.</p></li>
</ul>
''').single;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: SelectionArea(
                child: SizedBox(
                  width: 600,
                  child: HtmlChunkCard(
                    chunk: chunk,
                    articleId: 'selection-test',
                    maxWidth: 600,
                  ),
                ),
              ),
            ),
          ),
        );

        final itemParagraphs = find
            .byType(RichText)
            .evaluate()
            .map((element) => element.renderObject)
            .whereType<RenderParagraph>()
            .map((paragraph) => paragraph.text.toPlainText())
            .where(
              (text) =>
                  text.contains('First short list item.') ||
                  text.contains('Second short list item.'),
            )
            .toList();

        expect(itemParagraphs, hasLength(2));
        expect(itemParagraphs.join('\n'), contains('First short list item.'));
        expect(itemParagraphs.join('\n'), contains('Second short list item.'));
      },
    );
  }

  testWidgets(
    'selectable list keeps wrapped content aligned after its marker',
    (tester) async {
      final chunk = HtmlChunkParser.parseSync('''
<ul>
  <li><p>This is a deliberately long list item whose text must wrap onto multiple lines while every continuation line stays aligned with the item text.</p></li>
</ul>
''').single;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SelectionArea(
              child: SizedBox(
                width: 300,
                child: HtmlChunkCard(
                  chunk: chunk,
                  articleId: 'selection-test',
                  maxWidth: 300,
                ),
              ),
            ),
          ),
        ),
      );

      final richTexts = find.byType(RichText).evaluate().map((element) {
        return element.renderObject as RenderParagraph;
      });
      final marker = richTexts.firstWhere(
        (paragraph) => paragraph.text.toPlainText().trim() == '•',
      );
      final item = richTexts.firstWhere(
        (paragraph) =>
            paragraph.text.toPlainText().contains('This is a deliberately'),
      );
      final selectionBoxes = item.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: item.text.toPlainText().length,
        ),
      );

      expect(selectionBoxes.length, greaterThan(1));
      expect(
        item.localToGlobal(Offset.zero).dx,
        greaterThan(marker.localToGlobal(Offset.zero).dx),
      );
      expect(selectionBoxes[1].left, closeTo(selectionBoxes[0].left, 0.01));
    },
  );

  testWidgets('selectable list preserves ordered and nested markers', (
    tester,
  ) async {
    final chunk = HtmlChunkParser.parseSync('''
<ol start="3">
  <li><p>Parent item</p><ul><li><p>Nested item</p></li></ul></li>
  <li><p>Following item</p></li>
</ol>
''').single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: SelectionArea(
            child: SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final plainTexts = find
        .byType(RichText)
        .evaluate()
        .map(
          (element) =>
              (element.renderObject as RenderParagraph).text.toPlainText(),
        )
        .toList();

    expect(plainTexts, contains('3.'));
    expect(plainTexts, contains('•'));
    expect(plainTexts, contains('4.'));
    expect(plainTexts, contains('Parent item'));
    expect(plainTexts, contains('Nested item'));
    expect(plainTexts, contains('Following item'));
  });

  testWidgets('macOS can select across separate list item text flows', (
    tester,
  ) async {
    SelectedContent? selected;
    final chunk = HtmlChunkParser.parseSync('''
<ul>
  <li><p>First selectable item.</p></li>
  <li><p>Second selectable item.</p></li>
</ul>
''').single;

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
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraphs = find.byType(RichText).evaluate().map((element) {
      return element.renderObject as RenderParagraph;
    });
    final first = paragraphs.firstWhere(
      (paragraph) => paragraph.text.toPlainText().contains('First selectable'),
    );
    final second = paragraphs.firstWhere(
      (paragraph) => paragraph.text.toPlainText().contains('Second selectable'),
    );
    Offset textPosition(RenderParagraph paragraph, int offset) {
      return paragraph.localToGlobal(
        paragraph.getOffsetForCaret(
              TextPosition(offset: offset),
              const Rect.fromLTWH(0, 0, 2, 20),
            ) +
            Offset(0, paragraph.preferredLineHeight - 2),
      );
    }

    final mouse = await tester.startGesture(
      textPosition(first, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(textPosition(second, second.text.toPlainText().length));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(selected?.plainText, contains('First selectable item.'));
    expect(selected?.plainText, contains('Second selectable item.'));
  });

  testWidgets('macOS raw HTML keeps one selectable text flow', (tester) async {
    SelectedContent? selected;
    const chunk = HtmlChunk(
      type: HtmlChunkType.rawHtml,
      content:
          '<p>Raw first paragraph for selection.</p>'
          '<p>Raw second paragraph for selection.</p>',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selected = value,
            child: const SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraphs = find
        .byType(RichText)
        .evaluate()
        .map((element) => element.renderObject)
        .whereType<RenderParagraph>()
        .where(
          (paragraph) =>
              paragraph.text.toPlainText().contains('Raw first') ||
              paragraph.text.toPlainText().contains('Raw second'),
        )
        .toList(growable: false);
    expect(paragraphs, hasLength(1));
    final paragraph = paragraphs.single;
    final text = paragraph.text.toPlainText();

    Offset textPosition(int offset) => paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    final mouse = await tester.startGesture(
      textPosition(1),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(textPosition(text.length - 1));
    await mouse.up();
    await tester.pump();

    expect(selected?.plainText, contains('Raw second'));
    expect(selected?.plainText, isNot(contains('\uFFFC')));
  });

  testWidgets('macOS inline code stays in the surrounding selection flow', (
    tester,
  ) async {
    SelectedContent? selected;
    const chunk = HtmlChunk(
      type: HtmlChunkType.paragraph,
      content: 'Text before <code>inline_code</code> text after.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selected = value,
            child: const SizedBox(
              width: 600,
              child: HtmlChunkCard(
                chunk: chunk,
                articleId: 'selection-test',
                maxWidth: 600,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraphs = find
        .byType(RichText)
        .evaluate()
        .map((element) => element.renderObject)
        .whereType<RenderParagraph>()
        .where(
          (paragraph) => paragraph.text.toPlainText().contains('Text before'),
        )
        .toList(growable: false);
    expect(paragraphs, hasLength(1));
    final paragraph = paragraphs.single;
    final text = paragraph.text.toPlainText();
    WidgetSpan? inlineCodeSpan;
    paragraph.text.visitChildren((span) {
      if (span is WidgetSpan && span.rawText == 'inline_code') {
        inlineCodeSpan = span;
      }
      return true;
    });
    expect(inlineCodeSpan, isNotNull);
    final inlineCodeContainer = inlineCodeSpan!.child as Container;
    expect(
      inlineCodeContainer.padding,
      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    );
    expect(
      inlineCodeContainer.margin,
      const EdgeInsets.symmetric(horizontal: 2),
    );
    expect(
      (inlineCodeContainer.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );

    Offset textPosition(int offset) => paragraph.localToGlobal(
      paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 20),
          ) +
          Offset(0, paragraph.preferredLineHeight - 2),
    );
    final mouse = await tester.startGesture(
      textPosition(1),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(textPosition(text.length - 1));
    await mouse.up();
    await tester.pump();

    expect(selected?.plainText, contains('inline_code'));
    expect(selected?.plainText, isNot(contains('\uFFFC')));
  });
}
