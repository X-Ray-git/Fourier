import 'package:flutter/widgets.dart';

import '../../../services/youtube_playback_server.dart';
import '../../../utils/youtube_embed_utils.dart';
import 'shaka_embed_player.dart';

class YouTubeSabrPlayer extends StatelessWidget {
  const YouTubeSabrPlayer({
    super.key,
    required this.info,
    required this.onFallback,
    this.onArticleScroll,
  });

  final YouTubeEmbedInfo info;
  final VoidCallback onFallback;
  final ValueChanged<double>? onArticleScroll;

  @override
  Widget build(BuildContext context) {
    return ShakaEmbedPlayer(
      debugLabel: 'YouTube',
      sessionBuilder: () async {
        final session = await YouTubePlaybackServer.embedSession(info.videoId);
        return ShakaEmbedSession(
          pageUri: session.pageUri,
          injectionScript: session.injectionScript,
        );
      },
      thumbnailUri: info.thumbnailUri,
      onArticleScroll: onArticleScroll,
      onFallback: onFallback,
    );
  }
}
