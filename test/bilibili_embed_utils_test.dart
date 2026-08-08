import 'package:fourier/utils/bilibili_embed_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses official Bilibili player URLs from supported feeds', () {
    final sspai = BilibiliEmbedInfo.tryParse(
      'https://player.bilibili.com/player.html?bvid=BV1ZiM86BEwu&#x26;autoplay=false',
    );
    final appinn = BilibiliEmbedInfo.tryParse(
      '//player.bilibili.com/player.html?aid=116826868746469&amp;bvid=BV1tMTM6xE8Z&amp;cid=39476987666&amp;p=2',
    );

    expect(sspai?.bvid, 'BV1ZiM86BEwu');
    expect(appinn?.bvid, 'BV1tMTM6xE8Z');
    expect(appinn?.aid, 116826868746469);
    expect(appinn?.cid, 39476987666);
    expect(appinn?.page, 2);
  });

  test('accepts aid-only embeds and rejects unrelated or malformed URLs', () {
    expect(
      BilibiliEmbedInfo.tryParse(
        'https://player.bilibili.com/player.html?aid=123456',
      )?.aid,
      123456,
    );
    expect(
      BilibiliEmbedInfo.tryParse('https://www.bilibili.com/video/BV1ZiM86BEwu'),
      isNull,
    );
    expect(
      BilibiliEmbedInfo.tryParse(
        'https://player.bilibili.example/player.html?bvid=BV1ZiM86BEwu',
      ),
      isNull,
    );
    expect(
      BilibiliEmbedInfo.tryParse(
        'https://player.bilibili.com/player.html?bvid=invalid',
      ),
      isNull,
    );
    expect(BilibiliEmbedInfo.tryParse(null), isNull);
  });

  test('creates a canonical autoplay embed and external video URL', () {
    final info = BilibiliEmbedInfo.tryParse(
      'https://player.bilibili.com/player.html?bvid=BV1ZiM86BEwu&p=3',
    )!;

    expect(info.embedUri.host, 'player.bilibili.com');
    expect(info.embedUri.queryParameters['bvid'], 'BV1ZiM86BEwu');
    expect(info.embedUri.queryParameters['autoplay'], '1');
    expect(
      info.externalUri.toString(),
      'https://www.bilibili.com/video/BV1ZiM86BEwu/?p=3',
    );
    expect(info.embedDocument, contains('allowfullscreen'));
    expect(
      info.embedDocument,
      contains('bvid=BV1ZiM86BEwu&amp;p=3&amp;autoplay=1'),
    );
  });
}
