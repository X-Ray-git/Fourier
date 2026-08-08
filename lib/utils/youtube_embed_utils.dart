import 'dart:convert';

class YouTubeEmbedInfo {
  const YouTubeEmbedInfo._(this.videoId);

  static const clientBaseUrl = 'https://github.com/X-Ray-git/Fourier/';

  final String videoId;

  Uri get thumbnailUri =>
      Uri.https('i.ytimg.com', '/vi/$videoId/hqdefault.jpg');

  Uri get embedUri => Uri.https(
    'www.youtube-nocookie.com',
    '/embed/$videoId',
    const {'autoplay': '1', 'playsinline': '1', 'rel': '0', 'enablejsapi': '1'},
  );

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
    title="YouTube video player"
    allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin">
  </iframe>
</body>
</html>
''';
  }

  static YouTubeEmbedInfo? tryParse(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return null;

    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    String? videoId;

    if (host == 'youtu.be') {
      videoId = segments.firstOrNull;
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      if (segments.length >= 2 &&
          const {'embed', 'shorts', 'live'}.contains(segments.first)) {
        videoId = segments[1];
      } else {
        videoId = uri.queryParameters['v'];
      }
    }

    if (videoId == null || !RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(videoId)) {
      return null;
    }
    return YouTubeEmbedInfo._(videoId);
  }
}
