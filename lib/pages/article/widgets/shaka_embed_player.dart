import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../services/article_image_service.dart';
import '../../../services/youtube_playback_server.dart';
import '../../../utils/macos_webview_controls.dart';
import 'article_video_playback_shortcut.dart';
import 'media_play_button.dart';

typedef ShakaPlayerUriBuilder = Future<Uri> Function();

class ShakaEmbedSession {
  const ShakaEmbedSession({required this.pageUri, this.injectionScript});

  final Uri pageUri;
  final String? injectionScript;
}

typedef ShakaSessionBuilder = Future<ShakaEmbedSession> Function();

class ShakaEmbedPlayer extends StatefulWidget {
  const ShakaEmbedPlayer({
    super.key,
    required this.debugLabel,
    required this.sessionBuilder,
    required this.onFallback,
    this.thumbnailUri,
    this.idleBackground,
    this.onArticleScroll,
  });

  final String debugLabel;
  final ShakaSessionBuilder sessionBuilder;
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
  bool _didInject = false;
  bool _tickerEnabled = true;
  String? _pendingInjection;

  @override
  void dispose() {
    ArticleVideoPlaybackShortcut.deactivate(this);
    _timeout?.cancel();
    unawaited(_pauseWebViewPlayback());
    super.dispose();
  }

  Future<void> _pauseWebViewPlayback() async {
    try {
      await _controller?.runJavaScript(
        'document.querySelectorAll("video").forEach(function(v){v.pause();});',
      );
    } catch (_) {
      // WebView 可能已随页面一起销毁。
    }
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
      final session = await widget.sessionBuilder();
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
        final androidController =
            controller.platform as AndroidWebViewController;
        await androidController.setMediaPlaybackRequiresUserGesture(false);
        if (session.pageUri.scheme == 'https' &&
            session.injectionScript != null) {
          // YouTube 的真实 HTTPS embed 页需要访问只监听 127.0.0.1 的
          // HTTP 媒体代理。Android 没有 macOS 的运行时 OpenSSL，因而仅对
          // 这类注入会话放行 mixed content；network security config 仍将
          // 外部明文请求限制在 localhost 之外。
          await androidController.setMixedContentMode(
            MixedContentMode.alwaysAllow,
          );
        }
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
      _pendingInjection = session.injectionScript;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _fallback(
                'main-frame error ${error.errorCode}: ${error.description}',
              );
            }
          },
          onPageFinished: (_) => _injectRuntimeScript(controller),
          onSslAuthError: _handleSslAuthError,
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            final pageUri = session.pageUri;
            if (uri.scheme == pageUri.scheme &&
                uri.host == pageUri.host &&
                uri.port == pageUri.port) {
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
      await controller.loadRequest(session.pageUri);
    } catch (error, stackTrace) {
      _fallback('Dart setup error: $error', stackTrace);
    }
  }

  Future<void> _injectRuntimeScript(WebViewController controller) async {
    final injection = _pendingInjection;
    if (_didInject || injection == null || _didFallback) return;
    _pendingInjection = null;
    _didInject = true;
    try {
      await controller.runJavaScript(injection);
    } catch (error, stackTrace) {
      _fallback('runtime injection error: $error', stackTrace);
    }
  }

  /// 只对 YouTube 播放器自己生成的 loopback 自签名证书放行：证书 DER 必须
  /// 与当前进程生成的一致，且 host/port 属于本机 loopback 服务。其余 TLS
  /// 错误一律取消，不削弱 WebView 对其他主机的校验。
  void _handleSslAuthError(SslAuthError error) {
    final platform = error.platform;
    final webKitError = platform is WebKitSslAuthError ? platform : null;
    final accepted = YouTubePlaybackServer.isTrustedLoopbackCertificate(
      certificateDer: error.certificate?.data,
      host: webKitError?.host,
      port: webKitError?.port,
    );
    if (accepted) {
      unawaited(error.proceed());
    } else {
      unawaited(error.cancel());
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
    // 路由被覆盖（例如从文章进入相关文章）时 ModalRoute 会关闭非当前路由
    // 的 Ticker；此时必须暂停 WebView 里的播放，否则声音会从下层路由传出。
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled && !tickerEnabled) {
      unawaited(_pauseWebViewPlayback());
    }
    _tickerEnabled = tickerEnabled;

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
