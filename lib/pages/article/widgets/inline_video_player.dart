import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../services/article_image_service.dart';
import '../../../utils/duration_extension.dart';
import 'fullscreen_video_page.dart';
import 'media_play_button.dart';

/// 内联视频播放器 — poster → 加载 → 播放（含进度条 + 拖拽定位）
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;

  const InlineVideoPlayer({super.key, required this.videoUrl, this.posterUrl});

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideTimer;
  final FocusNode _focusNode = FocusNode();

  static _InlineVideoPlayerState? activePlayer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    if (activePlayer == this) {
      activePlayer = null;
    }
    _focusNode.dispose();
    _hideTimer?.cancel();
    _controller
      ?..removeListener(_onControllerUpdate)
      ..dispose();
    super.dispose();
  }

  void _onControllerUpdate() => setState(() {});

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      if (activePlayer == this) {
        if (_controller != null && _controller!.value.isInitialized) {
          _togglePlayPause();
          return true; // 拦截事件
        }
      }
    }
    return false;
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
    final shouldRestoreActivePlayer = activePlayer == this;
    if (shouldRestoreActivePlayer) {
      activePlayer = null;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPage(controller: _controller!),
      ),
    );

    if (mounted &&
        shouldRestoreActivePlayer &&
        _controller != null &&
        _controller!.value.isInitialized) {
      activePlayer = this;
      _focusNode.requestFocus();
    }
  }

  Future<void> _initAndPlay() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        setState(() => _hasError = true);
        return;
      }

      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      controller.addListener(_onControllerUpdate);
      await controller.play();
      activePlayer = this;
      if (mounted) _focusNode.requestFocus();
      setState(() {});
      _startHideTimer();
    } catch (e) {
      setState(() => _hasError = true);
      _controller?.dispose();
      _controller = null;
    }
  }

  Future<void> _togglePlayPause() async {
    if (_controller == null) return;
    activePlayer = this;
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
    activePlayer = this;
    if (mounted) _focusNode.requestFocus();
    setState(() => _showControls = !_showControls);
    _startHideTimer();
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _hasError = false;
                    _isInitializing = false;
                  });
                  _initAndPlay();
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 36),
                    SizedBox(height: 8),
                    Text('播放失败，点击重试', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
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
