import 'dart:convert';

import 'html_entity_utils.dart';

class BilibiliEmbedInfo {
  const BilibiliEmbedInfo._({
    required this.bvid,
    required this.aid,
    required this.cid,
    required this.page,
  });

  static const clientBaseUrl = 'https://github.com/X-Ray-git/auto-folo/';

  final String? bvid;
  final int? aid;
  final int? cid;
  final int? page;

  Uri get externalUri {
    final path = bvid != null ? '/video/$bvid/' : '/video/av$aid/';
    Map<String, String>? queryParameters;
    if (page != null) queryParameters = {'p': '$page'};
    return Uri.https('www.bilibili.com', path, queryParameters);
  }

  Uri get embedUri {
    final query = <String, String>{};
    if (bvid case final value?) {
      query['bvid'] = value;
    } else {
      query['aid'] = '$aid';
    }
    if (cid case final value?) query['cid'] = '$value';
    if (page case final value?) query['p'] = '$value';
    query['autoplay'] = '1';
    return Uri.https('player.bilibili.com', '/player.html', query);
  }

  String get embedDocument {
    final escapedUrl = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(embedUri.toString());
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
    iframe { display: block; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe
    src="$escapedUrl"
    title="Bilibili video player"
    allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin">
  </iframe>
</body>
</html>
''';
  }

  static BilibiliEmbedInfo? tryParse(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    var normalized = HtmlEntityUtils.decodeText(rawUrl.trim());
    if (normalized.startsWith('//')) normalized = 'https:$normalized';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.toLowerCase() != 'player.bilibili.com') {
      return null;
    }
    if (uri.path != '/player.html') return null;

    final rawBvid = uri.queryParameters['bvid']?.trim();
    final bvid =
        rawBvid != null && RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(rawBvid)
        ? rawBvid
        : null;
    final aid = _positiveInt(uri.queryParameters['aid']);
    if (bvid == null && aid == null) return null;

    return BilibiliEmbedInfo._(
      bvid: bvid,
      aid: aid,
      cid: _positiveInt(uri.queryParameters['cid']),
      page: _positiveInt(uri.queryParameters['p']),
    );
  }

  static int? _positiveInt(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value != null && value > 0 ? value : null;
  }
}
