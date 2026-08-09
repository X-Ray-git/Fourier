import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../services/article_image_service.dart';
import '../../../services/external_link_service.dart';
import '../../../utils/duration_extension.dart';
import 'article_video_playback_shortcut.dart';
import 'fullscreen_video_page.dart';
import 'media_play_button.dart';

/// 普通视频播放错误的分类。
enum _InlineVideoErrorKind { none, authExpiry, generic }

/// 内联视频播放器 — poster → 加载 → 播放（含进度条 + 拖拽定位）
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;

  /// 文章原始 URL：带时效签名的 CDN 地址失效（401/403）时，
  /// 在错误界面安全地提供「打开原文」入口。
  final String? articleUrl;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.posterUrl,
    this.articleUrl,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _hasError = false;
  _InlineVideoErrorKind _errorKind = _InlineVideoErrorKind.none;
  bool _showControls = true;
  Timer? _hideTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    ArticleVideoPlaybackShortcut.deactivate(this);
    _focusNode.dispose();
    _hideTimer?.cancel();
    _controller
      ?..removeListener(_onControllerUpdate)
      ..dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted &&
            _showControls &&
            (_controller?.value.isPlaying ?? false)) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  Future<void> _enterFullscreen() async {
    if (_controller == null) return;
    final shouldRestoreActivePlayer = ArticleVideoPlaybackShortcut.isActive(
      this,
    );
    if (shouldRestoreActivePlayer) {
      ArticleVideoPlaybackShortcut.deactivate(this);
    }

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPage(controller: _controller!),
      ),
    );

    if (mounted &&
        shouldRestoreActivePlayer &&
        _controller != null &&
        _controller!.value.isInitialized) {
      _activatePlaybackShortcut();
      _focusNode.requestFocus();
    }
  }

  void _activatePlaybackShortcut() {
    ArticleVideoPlaybackShortcut.activate(this, _togglePlayPause);
  }

  Future<void> _initAndPlay() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _hasError = false;
      _errorKind = _InlineVideoErrorKind.none;
    });

    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        setState(() {
          _hasError = true;
          _errorKind = _InlineVideoErrorKind.generic;
        });
        return;
      }

      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      if (!mounted || !identical(_controller, controller)) return;
      await controller.setLooping(false);
      if (!mounted || !identical(_controller, controller)) return;
      controller.addListener(_onControllerUpdate);
      await controller.play();
      if (!mounted || !identical(_controller, controller)) return;
      _activatePlaybackShortcut();
      _focusNode.requestFocus();
      setState(() {});
      _startHideTimer();
    } catch (e) {
      if (!mounted) return;
      // 带时效签名的 CDN 地址失效通常表现为 401/403 鉴权错误；
      // 其余播放错误走通用文案。
      final errorText = _controller?.value.errorDescription ?? e.toString();
      setState(() {
        _hasError = true;
        _errorKind = _isAuthOrSignatureExpiry(errorText)
            ? _InlineVideoErrorKind.authExpiry
            : _InlineVideoErrorKind.generic;
      });
      _controller?.dispose();
      _controller = null;
    }
  }

  /// 识别明确的鉴权 / 签名失效（HTTP 401/403 或平台层 unauthorized 描述）。
  static bool _isAuthOrSignatureExpiry(String text) {
    final lowered = text.toLowerCase();
    return lowered.contains('401') ||
        lowered.contains('403') ||
        lowered.contains('unauthorized') ||
        lowered.contains('forbidden') ||
        lowered.contains('access denied') ||
        lowered.contains('signature') ||
        lowered.contains('expired');
  }

  Future<void> _togglePlayPause() async {
    if (_controller == null) return;
    _activatePlaybackShortcut();
    if (mounted) _focusNode.requestFocus();
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
      _hideTimer?.cancel();
      _showControls = true;
    } else {
      final value = _controller!.value;
      if (value.duration > Duration.zero && value.position >= value.duration) {
        await _controller!.seekTo(Duration.zero);
      }
      await _controller!.play();
      _startHideTimer();
    }
    if (mounted) setState(() {});
  }

  void _toggleControls() {
    _activatePlaybackShortcut();
    if (mounted) _focusNode.requestFocus();
    setState(() => _showControls = !_showControls);
    _startHideTimer();
  }

  String? get _articleUrl {
    final raw = widget.articleUrl;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 正在播放或已就绪 → 显示视频
    if (_controller != null && _controller!.value.isInitialized) {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;

      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Focus(
            focusNode: _focusNode,
            child: GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),

                  // 控制层
                  IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 顶部渐变条
                          Container(
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.4),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),

                          // 底部控制栏
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 可拖拽进度条
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: VideoProgressIndicator(
                                    _controller!,
                                    allowScrubbing: true,
                                    colors: VideoProgressColors(
                                      playedColor: cs.primary,
                                      bufferedColor: cs.onSurface.withValues(
                                        alpha: 0.3,
                                      ),
                                      backgroundColor: cs.onSurface.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 时间 + 播放/暂停
                                Row(
                                  children: [
                                    // 播放/暂停
                                    GestureDetector(
                                      onTap: _togglePlayPause,
                                      child: Icon(
                                        _controller!.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // 时间
                                    Text(
                                      '${pos.toVideoFormatString()} / ${dur.toVideoFormatString()}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _enterFullscreen,
                                      child: const Icon(
                                        Icons.fullscreen,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 中央播放/暂停按钮（仅在控制层隐藏且暂停时显示）
                  if (!_showControls && !(_controller!.value.isPlaying))
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _controller!.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 错误态
    if (_hasError) {
      final isAuthExpiry = _errorKind == _InlineVideoErrorKind.authExpiry;
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: cs.surfaceContainerHighest,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 36,
                  color: isAuthExpiry ? cs.error : cs.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  isAuthExpiry ? '视频链接已过期' : '视频无法播放',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isAuthExpiry ? cs.error : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAuthExpiry ? '带时效的播放地址可能已失效' : '点击重试或稍后再试',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAuthExpiry && _articleUrl != null) ...[
                      TextButton.icon(
                        onPressed: () =>
                            ExternalLinkService.openUrlWithFeedback(
                              _articleUrl,
                            ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('打开原文'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _isInitializing = false;
                          _errorKind = _InlineVideoErrorKind.none;
                        });
                        _initAndPlay();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 待播放态
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: widget.posterUrl != null
                  ? CachedNetworkImage(
                      cacheKey: 'v2_${widget.posterUrl}',
                      imageUrl: widget.posterUrl!,
                      httpHeaders: ArticleImageService.httpHeaders,
                      fit: BoxFit.contain,
                      fadeInDuration: const Duration(milliseconds: 80),
                      fadeOutDuration: const Duration(milliseconds: 80),
                      placeholder: (context, url) =>
                          Container(color: cs.surfaceContainerHighest),
                      errorWidget: (context, url, error) =>
                          Container(color: cs.surfaceContainerHighest),
                    )
                  : Container(color: cs.surfaceContainerHighest),
            ),
            Container(color: Colors.black.withValues(alpha: 0.2)),
            Center(
              child: MediaPlayButton(
                isLoading: _isInitializing,
                onPressed: _initAndPlay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
