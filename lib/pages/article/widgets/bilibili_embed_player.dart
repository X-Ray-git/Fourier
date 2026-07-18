import 'package:flutter/material.dart';

import '../../../utils/bilibili_embed_utils.dart';
import 'web_embed_video_player.dart';

class BilibiliEmbedPlayer extends StatelessWidget {
  const BilibiliEmbedPlayer({super.key, required this.info});

  final BilibiliEmbedInfo info;

  @override
  Widget build(BuildContext context) {
    return WebEmbedVideoPlayer(
      providerName: 'Bilibili',
      embedDocument: info.embedDocument,
      clientBaseUrl: BilibiliEmbedInfo.clientBaseUrl,
      externalUri: info.externalUri,
      isAllowedMainFrameUri: (uri) =>
          uri.host.toLowerCase() == 'player.bilibili.com',
      idleBackground: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF26282B), Color(0xFF17181A)],
          ),
        ),
        child: const Align(
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
      ),
    );
  }
}
