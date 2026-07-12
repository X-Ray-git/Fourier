import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../services/article_image_service.dart';
import '../../../utils/macos_webview_controls.dart';
import '../../../utils/youtube_embed_utils.dart';
import 'media_play_button.dart';

class YouTubeEmbedPlayer extends StatefulWidget {
  const YouTubeEmbedPlayer({super.key, required this.info});

  final YouTubeEmbedInfo info;

  @override
  State<YouTubeEmbedPlayer> createState() => _YouTubeEmbedPlayerState();
}

class _YouTubeEmbedPlayerState extends State<YouTubeEmbedPlayer> {
  WebViewController? _controller;
  bool _isLoading = false;
  bool _hasError = false;

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
            if (!request.isMainFrame ||
                _isAllowedYouTubeUrl(request.url) ||
                _isClientDocumentUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null) {
              unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      await controller.loadHtmlString(
        widget.info.embedDocument,
        baseUrl: YouTubeEmbedInfo.clientBaseUrl,
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

  bool _isAllowedYouTubeUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
  }

  bool _isClientDocumentUrl(String rawUrl) {
    final requested = Uri.tryParse(rawUrl);
    final client = Uri.parse(YouTubeEmbedInfo.clientBaseUrl);
    if (requested == null) return false;
    return requested.scheme == client.scheme &&
        requested.host == client.host &&
        requested.path == client.path;
  }

  Future<void> _openExternally() => launchUrl(
    Uri.https('www.youtube.com', '/watch', {'v': widget.info.videoId}),
    mode: LaunchMode.externalApplication,
  );

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
                CachedNetworkImage(
                  imageUrl: widget.info.thumbnailUri.toString(),
                  httpHeaders: ArticleImageService.httpHeaders,
                  fit: BoxFit.contain,
                  placeholder: (_, _) =>
                      ColoredBox(color: colorScheme.surfaceContainerHighest),
                  errorWidget: (_, _, _) =>
                      ColoredBox(color: colorScheme.surfaceContainerHighest),
                ),
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
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 36,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'YouTube 加载失败，点击重试',
                            style: TextStyle(color: Colors.white, fontSize: 13),
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
}
