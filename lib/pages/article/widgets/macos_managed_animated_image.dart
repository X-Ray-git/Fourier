import 'package:flutter/material.dart';

import '../../../services/animated_image_playback_monitor.dart';
import '../../../services/macos_window_activity_service.dart';

const double _animatedImageViewportMargin = 200;

@visibleForTesting
bool isRectNearViewport(
  Rect child,
  Rect viewport, {
  double margin = _animatedImageViewportMargin,
}) {
  return child.overlaps(viewport.inflate(margin));
}

@visibleForTesting
bool shouldPlayManagedAnimatedImage({
  required bool windowActive,
  required bool nearViewport,
}) {
  return windowActive && nearViewport;
}

/// Keeps a macOS article animation decoded only while the window is active and
/// the image is close to the article viewport. Removing the stream listener
/// stops Flutter's multi-frame codec while [RawImage] retains the latest frame.
class MacosManagedAnimatedImage extends StatefulWidget {
  const MacosManagedAnimatedImage({
    super.key,
    required this.imageProvider,
    required this.width,
    required this.placeholder,
    required this.errorWidget,
    this.fit = BoxFit.contain,
    this.onLoaded,
    this.onError,
  });

  final ImageProvider imageProvider;
  final double width;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;
  final VoidCallback? onLoaded;
  final VoidCallback? onError;

  @override
  State<MacosManagedAnimatedImage> createState() =>
      _MacosManagedAnimatedImageState();
}

class _MacosManagedAnimatedImageState extends State<MacosManagedAnimatedImage> {
  final Object _monitorToken = Object();
  late final ImageStreamListener _imageStreamListener;
  ScrollableState? _scrollable;
  ScrollPosition? _scrollPosition;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  bool _nearViewport = false;
  bool _streamAttached = false;
  bool _loadedReported = false;
  bool _failed = false;
  bool _visibilityCheckScheduled = false;

  bool get _windowActive => MacosWindowActivityService.isActive.value;

  @override
  void initState() {
    super.initState();
    _imageStreamListener = ImageStreamListener(
      _handleImageFrame,
      onError: _handleImageError,
    );
    AnimatedImagePlaybackMonitor.register(_monitorToken);
    MacosWindowActivityService.isActive.addListener(_handleWindowActivity);
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScrollable = Scrollable.maybeOf(context);
    final nextPosition = nextScrollable?.position;
    if (!identical(_scrollPosition, nextPosition)) {
      _scrollPosition?.removeListener(_handleScroll);
      _scrollable = nextScrollable;
      _scrollPosition = nextPosition;
      _scrollPosition?.addListener(_handleScroll);
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant MacosManagedAnimatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _detachImageStream();
      _replaceImage(null);
      _loadedReported = false;
      _failed = false;
      _scheduleVisibilityCheck();
    }
  }

  void _handleScroll() {
    _scheduleVisibilityCheck();
  }

  void _handleWindowActivity() {
    _updatePlayback();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      _updateNearViewport();
    });
  }

  void _updateNearViewport() {
    final childRenderObject = context.findRenderObject();
    final viewportRenderObject = _scrollable?.context.findRenderObject();
    var nextNearViewport = true;
    if (childRenderObject is RenderBox &&
        childRenderObject.hasSize &&
        viewportRenderObject is RenderBox &&
        viewportRenderObject.hasSize) {
      final childRect =
          childRenderObject.localToGlobal(Offset.zero) & childRenderObject.size;
      final viewportRect =
          viewportRenderObject.localToGlobal(Offset.zero) &
          viewportRenderObject.size;
      nextNearViewport = isRectNearViewport(childRect, viewportRect);
    }
    if (_nearViewport != nextNearViewport) {
      _nearViewport = nextNearViewport;
    }
    _updatePlayback();
  }

  void _updatePlayback() {
    if (!mounted) return;
    final shouldPlay = shouldPlayManagedAnimatedImage(
      windowActive: _windowActive,
      nearViewport: _nearViewport,
    );
    if (shouldPlay && !_failed) {
      _attachImageStream();
    } else {
      _detachImageStream();
    }
    _publishMonitorState();
  }

  void _attachImageStream() {
    if (_streamAttached) return;
    final configuration = createLocalImageConfiguration(
      context,
      size: Size(widget.width, widget.width),
    );
    _imageStream = widget.imageProvider.resolve(configuration);
    _streamAttached = true;
    AnimatedImagePlaybackMonitor.recordStreamResolve();
    _imageStream!.addListener(_imageStreamListener);
  }

  void _detachImageStream() {
    if (!_streamAttached) return;
    _imageStream?.removeListener(_imageStreamListener);
    _imageStream = null;
    _streamAttached = false;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    if (!mounted) return;
    AnimatedImagePlaybackMonitor.recordFrameCallback();
    _replaceImage(imageInfo);
    _failed = false;
    if (!_loadedReported) {
      _loadedReported = true;
      widget.onLoaded?.call();
    }
    _publishMonitorState();
    setState(() {});
  }

  void _handleImageError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    _failed = true;
    _detachImageStream();
    widget.onError?.call();
    _publishMonitorState();
    setState(() {});
  }

  void _replaceImage(ImageInfo? nextImageInfo) {
    final previous = _imageInfo;
    _imageInfo = nextImageInfo;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _publishMonitorState() {
    AnimatedImagePlaybackMonitor.update(
      _monitorToken,
      windowActive: _windowActive,
      nearViewport: _nearViewport,
      playing: _streamAttached,
      hasFrame: _imageInfo != null,
    );
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_handleScroll);
    MacosWindowActivityService.isActive.removeListener(_handleWindowActivity);
    _detachImageStream();
    _imageInfo?.dispose();
    _imageInfo = null;
    AnimatedImagePlaybackMonitor.unregister(_monitorToken);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.errorWidget;
    final imageInfo = _imageInfo;
    if (imageInfo == null) return widget.placeholder;
    return RawImage(
      image: imageInfo.image,
      width: widget.width,
      scale: imageInfo.scale,
      fit: widget.fit,
    );
  }
}
