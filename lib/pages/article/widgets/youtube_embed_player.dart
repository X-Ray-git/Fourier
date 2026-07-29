import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../utils/youtube_embed_utils.dart';
import 'web_embed_video_player.dart';
import 'youtube_sabr_player.dart';

class YouTubeEmbedPlayer extends StatefulWidget {
  const YouTubeEmbedPlayer({
    super.key,
    required this.info,
    this.onArticleScroll,
  });

  final YouTubeEmbedInfo info;
  final ValueChanged<double>? onArticleScroll;

  @override
  State<YouTubeEmbedPlayer> createState() => _YouTubeEmbedPlayerState();
}

class _YouTubeEmbedPlayerState extends State<YouTubeEmbedPlayer> {
  bool _useOfficialPlayer = false;

  @override
  void didUpdateWidget(covariant YouTubeEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.videoId != widget.info.videoId) {
      _useOfficialPlayer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useOfficialPlayer && (Platform.isMacOS || Platform.isAndroid)) {
      return YouTubeSabrPlayer(
        key: ValueKey('youtube-sabr-${widget.info.videoId}'),
        info: widget.info,
        onArticleScroll: widget.onArticleScroll,
        onFallback: () {
          if (mounted) setState(() => _useOfficialPlayer = true);
        },
      );
    }

    final info = widget.info;
    return WebEmbedVideoPlayer(
      key: ValueKey('youtube-official-${info.videoId}'),
      providerName: 'YouTube',
      embedDocument: info.embedDocument,
      clientBaseUrl: YouTubeEmbedInfo.clientBaseUrl,
      externalUri: Uri.https('www.youtube.com', '/watch', {'v': info.videoId}),
      thumbnailUri: info.thumbnailUri,
      startOnMount: _useOfficialPlayer,
      isAllowedMainFrameUri: (uri) {
        final host = uri.host.toLowerCase();
        return host == 'youtube.com' ||
            host.endsWith('.youtube.com') ||
            host == 'youtube-nocookie.com' ||
            host.endsWith('.youtube-nocookie.com');
      },
    );
  }
}
