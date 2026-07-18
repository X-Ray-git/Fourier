import 'package:flutter/widgets.dart';

import '../../../utils/youtube_embed_utils.dart';
import 'web_embed_video_player.dart';

class YouTubeEmbedPlayer extends StatelessWidget {
  const YouTubeEmbedPlayer({super.key, required this.info});

  final YouTubeEmbedInfo info;

  @override
  Widget build(BuildContext context) {
    return WebEmbedVideoPlayer(
      providerName: 'YouTube',
      embedDocument: info.embedDocument,
      clientBaseUrl: YouTubeEmbedInfo.clientBaseUrl,
      externalUri: Uri.https('www.youtube.com', '/watch', {'v': info.videoId}),
      thumbnailUri: info.thumbnailUri,
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
