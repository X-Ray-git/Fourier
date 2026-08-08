import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../services/article_image_service.dart';
import '../../../services/external_link_service.dart';
import '../../../utils/macos_webview_controls.dart';
import 'media_play_button.dart';

typedef EmbedNavigationPredicate = bool Function(Uri uri);

class WebEmbedVideoPlayer extends StatefulWidget {
  const WebEmbedVideoPlayer({
    super.key,
    required this.providerName,
    required this.embedDocument,
    required this.clientBaseUrl,
    required this.externalUri,
    required this.isAllowedMainFrameUri,
    this.thumbnailUri,
    this.idleBackground,
    this.startOnMount = false,
  });

  final String providerName;
  final String embedDocument;
  final String clientBaseUrl;
  final Uri externalUri;
  final EmbedNavigationPredicate isAllowedMainFrameUri;
  final Uri? thumbnailUri;
  final Widget? idleBackground;
  final bool startOnMount;

  @override
  State<WebEmbedVideoPlayer> createState() => _WebEmbedVideoPlayerState();
}

class _WebEmbedVideoPlayerState extends State<WebEmbedVideoPlayer> {
  WebViewController? _controller;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.startOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startPlayback();
      });
    }
  }

  Future<void> _startPlayback() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
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
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;

            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                (_isClientDocumentUri(uri) ||
                    widget.isAllowedMainFrameUri(uri))) {
              return NavigationDecision.navigate;
            }
            if (uri != null) {
              unawaited(
                ExternalLinkService.openUrlWithFeedback(uri.toString()),
              );
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      await controller.loadHtmlString(
        widget.embedDocument,
        baseUrl: widget.clientBaseUrl,
      );
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _controller = null;
      });
    }
  }

  bool _isClientDocumentUri(Uri requested) {
    final client = Uri.parse(widget.clientBaseUrl);
    return requested.scheme == client.scheme &&
        requested.host == client.host &&
        requested.path == client.path;
  }

  Future<void> _openExternally() =>
      ExternalLinkService.openUrlWithFeedback(widget.externalUri.toString());

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
              if (_controller == null && !_isLoading && !_hasError)
                Center(
                  child: MediaPlayButton(
                    isLoading: false,
                    onPressed: _startPlayback,
                  ),
                ),
              if (_isLoading)
                const Center(
                  child: MediaPlayButton(isLoading: true, onPressed: null),
                ),
              if (_hasError)
                Center(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _startPlayback,
                      onSecondaryTap: _openExternally,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.providerName} 加载失败，点击重试',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
