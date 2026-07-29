import 'package:autofolo/services/bilibili_playback_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BilibiliPlaybackServer identity resolution', () {
    test('selects the requested part CID', () {
      final data = {
        'cid': 100,
        'pages': [
          {'cid': 101},
          {'cid': 102},
        ],
      };

      expect(BilibiliPlaybackServer.selectCid(data, null), 101);
      expect(BilibiliPlaybackServer.selectCid(data, 2), 102);
      expect(BilibiliPlaybackServer.selectCid({'cid': 200}, null), 200);
    });

    test('rejects responses without a usable CID', () {
      expect(
        () => BilibiliPlaybackServer.selectCid({'pages': const []}, null),
        throwsFormatException,
      );
    });
  });

  group('BilibiliPlaybackServer media allowlist', () {
    test('accepts Bilibili HTTPS media hosts', () {
      const targets = [
        'https://upos-sz-mirrorcos.bilivideo.com/video.m4s',
        'https://cn-sh-fx-01.bilivideo.com/video.m4s',
        'https://upos-hz-mirrorakam.akamaized.net/video.m4s',
      ];

      for (final target in targets) {
        expect(
          BilibiliPlaybackServer.isAllowedMediaTarget(Uri.parse(target)),
          isTrue,
          reason: target,
        );
      }
    });

    test('rejects non-HTTPS, ports, credentials, and lookalikes', () {
      const targets = [
        'http://cn-sh-fx-01.bilivideo.com/video.m4s',
        'https://user@cn-sh-fx-01.bilivideo.com/video.m4s',
        'https://cn-sh-fx-01.bilivideo.com:444/video.m4s',
        'https://bilivideo.com.example.net/video.m4s',
        'https://example.com/video.m4s',
      ];

      for (final target in targets) {
        expect(
          BilibiliPlaybackServer.isAllowedMediaTarget(Uri.parse(target)),
          isFalse,
          reason: target,
        );
      }
    });
  });

  test('builds a scoped Bilibili danmaku segment URL', () {
    final uri = BilibiliPlaybackServer.danmakuSegmentUri(39731333932, 2);

    expect(uri.scheme, 'https');
    expect(uri.host, 'api.bilibili.com');
    expect(uri.path, '/x/v2/dm/web/seg.so');
    expect(uri.queryParameters, {
      'type': '1',
      'oid': '39731333932',
      'segment_index': '2',
    });
    expect(
      () => BilibiliPlaybackServer.danmakuSegmentUri(0, 1),
      throwsArgumentError,
    );
  });

  test('converts Bilibili subtitle JSON to WebVTT', () {
    final vtt = BilibiliPlaybackServer.subtitleJsonToVtt({
      'body': [
        {'from': 1.25, 'to': 3.5, 'content': '第一行'},
        {'from': 65, 'to': 66.125, 'content': '第二行'},
        {'from': 4, 'to': 3, 'content': '无效'},
      ],
    });

    expect(vtt, startsWith('WEBVTT\n\n'));
    expect(vtt, contains('00:00:01.250 --> 00:00:03.500'));
    expect(vtt, contains('00:01:05.000 --> 00:01:06.125'));
    expect(vtt, isNot(contains('无效')));
  });
}
