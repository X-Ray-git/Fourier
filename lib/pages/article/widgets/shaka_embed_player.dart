import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../services/article_image_service.dart';
import '../../../utils/macos_webview_controls.dart';
import 'article_video_playback_shortcut.dart';
import 'media_play_button.dart';

typedef ShakaPlayerUriBuilder = Future<Uri> Function();

class ShakaEmbedPlayer extends StatefulWidget {
  const ShakaEmbedPlayer({
    super.key,
    required this.debugLabel,
    required this.playerUriBuilder,
    required this.onFallback,
    this.thumbnailUri,
    this.idleBackground,
    this.onArticleScroll,
  });

  final String debugLabel;
  final ShakaPlayerUriBuilder playerUriBuilder;
  final VoidCallback onFallback;
  final Uri? thumbnailUri;
  final Widget? idleBackground;
  final ValueChanged<double>? onArticleScroll;

  @override
  State<ShakaEmbedPlayer> createState() => _ShakaEmbedPlayerState();
}

class _ShakaEmbedPlayerState extends State<ShakaEmbedPlayer> {
  static const _loadTimeout = Duration(seconds: 35);

  WebViewController? _controller;
  Timer? _timeout;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _didFallback = false;

  @override
  void dispose() {
    ArticleVideoPlaybackShortcut.deactivate(this);
    _timeout?.cancel();
    super.dispose();
  }

  void _activatePlaybackShortcut() {
    ArticleVideoPlaybackShortcut.activate(this, _togglePlayback);
  }

  Future<void> _togglePlayback() async {
    await _controller?.runJavaScript(
      'globalThis.FourierVideoControls?.togglePlayPause();',
    );
  }

  Future<void> _startPlayback() async {
    if (_isLoading || _controller != null || _didFallback) return;
    setState(() => _isLoading = true);

    try {
      final playerUri = await widget.playerUriBuilder();
      if (!mounted || _didFallback) return;

      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final controller = WebViewController.fromPlatformCreationParams(params);
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      } else if (controller.platform is WebKitWebViewController) {
        await MacOSWebViewControls.enableElementFullscreen(
          (controller.platform as WebKitWebViewController).webViewIdentifier,
        );
      }

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (kDebugMode) {
        await controller.setOnConsoleMessage((message) {
          debugPrint(
            '[${widget.debugLabel}PlayerConsole ${message.level.name}] '
            '${message.message}',
          );
        });
      }
      await controller.addJavaScriptChannel(
        'FourierVideoPlayer',
        onMessageReceived: _handlePlayerMessage,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _fallback(
                'main-frame error ${error.errorCode}: ${error.description}',
              );
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            if (uri.scheme == playerUri.scheme &&
                uri.host == playerUri.host &&
                uri.port == playerUri.port &&
                uri.pathSegments.isNotEmpty &&
                uri.pathSegments.first == playerUri.pathSegments.first) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

      if (!mounted || _didFallback) return;
      setState(() => _controller = controller);
      _activatePlaybackShortcut();
      _timeout = Timer(
        _loadTimeout,
        () => _fallback('playback timeout after ${_loadTimeout.inSeconds}s'),
      );
      await controller.loadRequest(playerUri);
    } catch (error, stackTrace) {
      _fallback('Dart setup error: $error', stackTrace);
    }
  }

  void _handlePlayerMessage(JavaScriptMessage message) {
    if (_didFallback) return;
    try {
      final payload = jsonDecode(message.message) as Map<String, dynamic>;
      switch (payload['type']) {
        case 'playing':
          _timeout?.cancel();
          _activatePlaybackShortcut();
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isPlaying = true;
            });
          }
        case 'activated':
          _activatePlaybackShortcut();
        case 'togglePlayback':
          _activatePlaybackShortcut();
          ArticleVideoPlaybackShortcut.requestToggle(this);
        case 'scroll':
          final detail = payload['detail'];
          if (detail is num && detail.isFinite) {
            widget.onArticleScroll?.call(detail.toDouble());
          }
        case 'error':
          _fallback('JavaScript player error: ${payload['detail']}');
      }
    } catch (error, stackTrace) {
      _fallback('invalid player message: $error', stackTrace);
    }
  }

  void _fallback(String reason, [StackTrace? stackTrace]) {
    if (_didFallback || !mounted) return;
    if (kDebugMode) {
      debugPrint('[${widget.debugLabel}PlayerFallback] $reason');
      if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    }
    _didFallback = true;
    _timeout?.cancel();
    widget.onFallback();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null)
                WebViewWidget(controller: _controller!)
              else
                _buildIdleBackground(colorScheme),
              if (_controller == null)
                ColoredBox(color: Colors.black.withValues(alpha: 0.2)),
              if (_controller == null && !_isLoading)
                Center(
                  child: MediaPlayButton(
                    isLoading: false,
                    onPressed: _startPlayback,
                  ),
                ),
              if (_isLoading && !_isPlaying)
                const Center(
                  child: MediaPlayButton(isLoading: true, onPressed: null),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleBackground(ColorScheme colorScheme) {
    final thumbnailUri = widget.thumbnailUri;
    if (thumbnailUri != null) {
      return CachedNetworkImage(
        imageUrl: thumbnailUri.toString(),
        httpHeaders: ArticleImageService.httpHeaders,
        fit: BoxFit.contain,
        placeholder: (_, _) =>
            ColoredBox(color: colorScheme.surfaceContainerHighest),
        errorWidget: (_, _, _) =>
            ColoredBox(color: colorScheme.surfaceContainerHighest),
      );
    }
    return widget.idleBackground ??
        ColoredBox(color: colorScheme.surfaceContainerHighest);
  }
}
