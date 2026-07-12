import 'package:autofolo/utils/youtube_embed_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses supported YouTube URL forms', () {
    const videoId = 'sH6mlUzAMzU';
    final urls = [
      'https://www.youtube-nocookie.com/embed/$videoId?rel=0',
      'https://www.youtube.com/watch?v=$videoId',
      'https://youtu.be/$videoId',
      'https://youtube.com/shorts/$videoId',
    ];

    for (final url in urls) {
      expect(YouTubeEmbedInfo.tryParse(url)?.videoId, videoId);
    }
  });

  test('rejects unrelated and malformed URLs', () {
    expect(
      YouTubeEmbedInfo.tryParse('https://example.com/embed/abcdef'),
      isNull,
    );
    expect(YouTubeEmbedInfo.tryParse('https://youtube.com/embed/'), isNull);
    expect(YouTubeEmbedInfo.tryParse(null), isNull);
  });

  test('creates privacy-enhanced autoplay embed and thumbnail URLs', () {
    final info = YouTubeEmbedInfo.tryParse(
      'https://www.youtube.com/watch?v=sH6mlUzAMzU',
    )!;

    expect(info.embedUri.host, 'www.youtube-nocookie.com');
    expect(info.embedUri.queryParameters['autoplay'], '1');
    expect(info.embedUri.queryParameters['playsinline'], '1');
    expect(info.thumbnailUri.toString(), contains('/vi/sH6mlUzAMzU/'));
    expect(info.embedDocument, contains('allowfullscreen'));
    expect(
      info.embedDocument,
      contains('referrerpolicy="strict-origin-when-cross-origin"'),
    );
    expect(info.embedDocument, contains('autoplay=1&amp;playsinline=1'));
  });
}
