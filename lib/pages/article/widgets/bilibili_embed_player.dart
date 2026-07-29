import 'dart:io';

import 'package:flutter/material.dart';

import '../../../utils/bilibili_embed_utils.dart';
import 'bilibili_sabr_player.dart';
import 'web_embed_video_player.dart';

class BilibiliEmbedPlayer extends StatefulWidget {
  const BilibiliEmbedPlayer({
    super.key,
    required this.info,
    this.onArticleScroll,
  });

  final BilibiliEmbedInfo info;
  final ValueChanged<double>? onArticleScroll;

  @override
  State<BilibiliEmbedPlayer> createState() => _BilibiliEmbedPlayerState();
}

class _BilibiliEmbedPlayerState extends State<BilibiliEmbedPlayer> {
  bool _useOfficialPlayer = false;

  @override
  void didUpdateWidget(covariant BilibiliEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.externalUri != widget.info.externalUri) {
      _useOfficialPlayer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useOfficialPlayer && (Platform.isMacOS || Platform.isAndroid)) {
      return BilibiliSabrPlayer(
        key: ValueKey('bilibili-sabr-${widget.info.externalUri}'),
        info: widget.info,
        onArticleScroll: widget.onArticleScroll,
        onFallback: () {
          if (mounted) setState(() => _useOfficialPlayer = true);
        },
      );
    }

    final info = widget.info;
    return WebEmbedVideoPlayer(
      key: ValueKey('bilibili-official-${info.externalUri}'),
      providerName: 'Bilibili',
      embedDocument: info.embedDocument,
      clientBaseUrl: BilibiliEmbedInfo.clientBaseUrl,
      externalUri: info.externalUri,
      startOnMount: _useOfficialPlayer,
      isAllowedMainFrameUri: (uri) =>
          uri.host.toLowerCase() == 'player.bilibili.com',
      idleBackground: const BilibiliIdleBackground(),
    );
  }
}
