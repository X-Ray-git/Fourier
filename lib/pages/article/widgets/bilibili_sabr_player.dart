import 'package:flutter/material.dart';

import '../../../services/bilibili_playback_server.dart';
import '../../../utils/bilibili_embed_utils.dart';
import 'shaka_embed_player.dart';

class BilibiliSabrPlayer extends StatelessWidget {
  const BilibiliSabrPlayer({
    super.key,
    required this.info,
    required this.onFallback,
    this.onArticleScroll,
  });

  final BilibiliEmbedInfo info;
  final VoidCallback onFallback;
  final ValueChanged<double>? onArticleScroll;

  @override
  Widget build(BuildContext context) {
    return ShakaEmbedPlayer(
      debugLabel: 'Bilibili',
      playerUriBuilder: () => BilibiliPlaybackServer.playerUri(info),
      idleBackground: const BilibiliIdleBackground(),
      onArticleScroll: onArticleScroll,
      onFallback: onFallback,
    );
  }
}

class BilibiliIdleBackground extends StatelessWidget {
  const BilibiliIdleBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF26282B), Color(0xFF17181A)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Bilibili',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
