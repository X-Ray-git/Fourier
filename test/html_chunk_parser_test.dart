import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/pages/article/widgets/html_chunk_card.dart';
import 'package:autofolo/utils/html_chunk_parser.dart';

void main() {
  test('resource-less media remains as an unavailable chunk', () {
    final chunks = HtmlChunkParser.parseSync('<audio></audio>');

    expect(chunks, hasLength(1));
    expect(chunks.single.type, HtmlChunkType.iframeVideo);
    expect(chunks.single.attributes['mediaTag'], 'audio');
    expect(chunks.single.attributes['mediaUnavailableReason'], 'missingSource');
    expect(chunks.single.imageSrc, isNull);
  });

  test('media with a source is not marked unavailable', () {
    final chunks = HtmlChunkParser.parseSync(
      '<video src="https://example.com/video.mp4"></video>',
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.attributes['mediaTag'], 'video');
    expect(chunks.single.attributes, isNot(contains('mediaUnavailableReason')));
    expect(chunks.single.imageSrc, 'https://example.com/video.mp4');
  });

  test('audio with a child source is not marked unavailable', () {
    final chunks = HtmlChunkParser.parseSync(
      '<audio><source src="https://example.com/audio.mp3"></audio>',
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.attributes['mediaTag'], 'audio');
    expect(chunks.single.attributes, isNot(contains('mediaUnavailableReason')));
    expect(chunks.single.imageSrc, 'https://example.com/audio.mp3');
  });

  test('compact author markup becomes one author-list chunk', () {
    const html = '''
<auto-folo-author-list>
  <auto-folo-author name="Jane Doe" handle="jane"
      avatar="https://example.com/jane.png"
      profile="https://huggingface.co/jane"></auto-folo-author>
  <auto-folo-author name="John Doe" handle="john"
      avatar="https://example.com/john.png"
      profile="https://huggingface.co/john"></auto-folo-author>
</auto-folo-author-list>
''';

    final chunks = HtmlChunkParser.parseSync(html);

    expect(chunks, hasLength(1));
    expect(chunks.single.type, HtmlChunkType.authorList);
    expect(chunks.single.authors, hasLength(2));
    expect(chunks.single.authors.first.name, 'Jane Doe');
    expect(chunks.single.authors.first.handle, 'jane');
    expect(
      chunks.single.authors.first.profileUrl,
      'https://huggingface.co/jane',
    );
  });

  testWidgets('resource-less media explains the problem instead of hiding it', (
    tester,
  ) async {
    final chunk = HtmlChunkParser.parseSync('<iframe></iframe>').single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlChunkCard(
            chunk: chunk,
            articleId: 'entry-id',
            articleUrl: 'https://example.com/article',
            maxWidth: 420,
          ),
        ),
      ),
    );

    expect(find.text('嵌入内容不可用'), findsOneWidget);
    expect(find.text('源内容未提供可用的媒体地址'), findsOneWidget);
    expect(find.text('打开原文'), findsOneWidget);
  });
}
