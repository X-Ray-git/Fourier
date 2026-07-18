// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import '../../../common/widgets/app_context_menu.dart';
import '../../../common/widgets/app_glass.dart';
import '../../../common/widgets/feedback_toast.dart';
import '../../../common/widgets/interactiveviewer_gallery/interactive_viewer_boundary.dart';
import '../../../services/article_image_service.dart';
import '../../../services/article_image_cache_service.dart';
import '../../../utils/image_clipboard.dart';

/// PiliPlus 架构图片查看器 — 基于 vendored InteractiveViewerBoundary
/// 实现单指下拉退出 + 双指缩放的零冲突手势交互。
class ImageGalleryPage extends StatefulWidget {
  final String articleId;
  final List<String> imageUrls;
  final int initialIndex;

  const ImageGalleryPage({
    super.key,
    required this.articleId,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  bool _enablePageView = true;
  late Offset _doubleTapLocalPosition;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_animationListener);
  }

  void _animationListener() {
    _transformationController.value = _animation?.value ?? Matrix4.identity();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController
      ..removeListener(_animationListener)
      ..dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // ─── 缩放与边界联动 ───

  void _onScaleChanged(double scale) {
    final bool initialScale = scale <= 1.01;
    if (initialScale && !_enablePageView) {
      setState(() => _enablePageView = true);
    } else if (!initialScale && _enablePageView) {
      setState(() => _enablePageView = false);
    }
  }

  void _onLeftBoundaryHit() {
    if (!_enablePageView && _pageController.page!.floor() > 0) {
      setState(() => _enablePageView = true);
    }
  }

  void _onRightBoundaryHit() {
    if (!_enablePageView &&
        _pageController.page!.floor() < widget.imageUrls.length - 1) {
      setState(() => _enablePageView = true);
    }
  }

  void _onNoBoundaryHit() {
    if (_enablePageView) {
      setState(() => _enablePageView = false);
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentIndex = page);
    if (_transformationController.value != Matrix4.identity()) {
      _animation = _animationController.drive(
        Matrix4Tween(
          begin: _transformationController.value,
          end: Matrix4.identity(),
        ).chain(CurveTween(curve: Curves.easeOut)),
      );
      _animationController.forward(from: 0);
    }
  }

  // ─── 双击缩放 ───

  void _onDoubleTap() {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.storage[0];
    final targetScale = currentScale <= 1.01 ? 3.2 : 1.0;
    final fp = _doubleTapLocalPosition;

    final offSetX = targetScale == 1.0 ? 0.0 : -fp.dx * (targetScale - 1);
    final offSetY = targetScale == 1.0 ? 0.0 : -fp.dy * (targetScale - 1);

    final targetMatrix = Matrix4.fromList([
      targetScale,
      matrix.row1.x,
      matrix.row2.x,
      matrix.row3.x,
      matrix.row0.y,
      targetScale,
      matrix.row2.y,
      matrix.row3.y,
      matrix.row0.z,
      matrix.row1.z,
      targetScale,
      matrix.row3.z,
      offSetX,
      offSetY,
      matrix.row2.w,
      matrix.row3.w,
    ]);

    _animation = _animationController.drive(
      Matrix4Tween(
        begin: _transformationController.value,
        end: targetMatrix,
      ).chain(CurveTween(curve: Curves.easeOut)),
    );
    _animationController
        .forward(from: 0)
        .whenComplete(() => _onScaleChanged(targetScale));
  }

  // ─── 现代化的长按悬浮菜单 ───

  void _showImageMenu(String imageUrl) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AppMobileGlassSheet(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text(
                  '图片操作',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text(
                  '分享图片',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareImage(imageUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text(
                  '保存到相册',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveImage(imageUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text(
                  '复制链接',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: imageUrl));
                  AppFeedback.success('已复制', '图片链接已复制到剪贴板');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showImageContextMenu(Offset position, String imageUrl) {
    AppContextMenu.show<String>(
      context,
      position: position,
      entries: const [
        AppContextMenuAction(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: '复制图片',
        ),
        AppContextMenuAction(
          value: 'share',
          icon: Icons.share_rounded,
          label: '分享图片',
        ),
        AppContextMenuAction(
          value: 'save',
          icon: Icons.save_alt_rounded,
          label: '保存到相册',
        ),
        AppContextMenuAction(
          value: 'copyLink',
          icon: Icons.link_rounded,
          label: '复制链接',
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'copy':
          _copyImage(imageUrl);
        case 'share':
          _shareImage(imageUrl);
        case 'save':
          _saveImage(imageUrl);
        case 'copyLink':
          Clipboard.setData(ClipboardData(text: imageUrl));
          AppFeedback.success('已复制', '图片链接已复制到剪贴板');
        case null:
          break;
      }
    });
  }

  Future<void> _copyImage(String url) async {
    final bytes = await _downloadBytes(url);
    if (bytes == null) {
      AppFeedback.error('复制失败', '无法下载图片数据');
      return;
    }
    final ok = await ImageClipboard.copyImageToClipboard(bytes);
    if (ok) {
      AppFeedback.success('已复制', '图片已复制到剪贴板');
    } else {
      AppFeedback.error('复制失败', '请稍后重试');
    }
  }

  Future<void> _shareImage(String url) async {
    try {
      final file = await _downloadToTemp(url);
      if (file != null) {
        await Share.shareXFiles([XFile(file.path)]);
      } else {
        await Share.share(url);
      }
    } catch (e) {
      AppFeedback.error('分享失败', e.toString());
    }
  }

  Future<void> _saveImage(String url) async {
    try {
      final bytes = await _downloadBytes(url);
      if (bytes == null) {
        AppFeedback.error('保存失败', '无法下载图片数据');
        return;
      }

      if (Platform.isMacOS) {
        final ext = url.split('.').last.split('?').first;
        final extension = ext.isEmpty || ext.length > 4 ? 'jpg' : ext;
        final fileName =
            'folo_image_${DateTime.now().millisecondsSinceEpoch}.$extension';

        final FileSaveLocation? result = await getSaveLocation(
          suggestedName: fileName,
        );
        if (result != null) {
          final file = File(result.path);
          await file.writeAsBytes(bytes);
          AppFeedback.success('已保存', '图片已保存到本地');
        }
      } else {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          AppFeedback.warning('权限不足', '请授予存储权限后重试');
          return;
        }

        final result = await ImageGallerySaverPlus.saveImage(bytes);
        if (result != null && result['isSuccess'] == true) {
          AppFeedback.success('已保存', '图片已保存到相册');
        } else {
          AppFeedback.error('保存失败', '请稍后重试');
        }
      }
    } catch (e) {
      AppFeedback.error('保存失败', e.toString());
    }
  }

  Future<File?> _downloadToTemp(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/share_img_${url.hashCode}.jpg');
      if (!file.existsSync()) {
        final bytes = await _downloadBytes(url);
        if (bytes != null) await file.writeAsBytes(bytes);
      }
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // 核心：PiliPlus 架构的 InteractiveViewerBoundary
            // 单指下拉 → dismiss 动画（缩放+偏移+背景渐隐）
            // 双指 → zoom/pan（无冲突）
            InteractiveViewerBoundary(
              controller: _transformationController,
              boundaryWidth: MediaQuery.widthOf(context),
              onScaleChanged: _onScaleChanged,
              onLeftBoundaryHit: _onLeftBoundaryHit,
              onRightBoundaryHit: _onRightBoundaryHit,
              onNoBoundaryHit: _onNoBoundaryHit,
              maxScale: 5.0,
              minScale: 1.0,
              onDismissed: () => Navigator.of(context).pop(),
              onReset: () {
                if (!_enablePageView) {
                  setState(() => _enablePageView = true);
                }
              },
              child: PageView.builder(
                onPageChanged: _onPageChanged,
                controller: _pageController,
                physics: _enablePageView
                    ? null
                    : const NeverScrollableScrollPhysics(),
                itemCount: widget.imageUrls.length,
                itemBuilder: (context, index) {
                  final url = widget.imageUrls[index];
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final cacheWidth = (MediaQuery.of(context).size.width * dpr)
                      .round();
                  final diskCacheWidth = cacheWidth * 2;
                  ArticleImageCacheService.registerImage(
                    widget.articleId,
                    url,
                    maxWidth: diskCacheWidth,
                  );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    onDoubleTapDown: (details) {
                      _doubleTapLocalPosition = details.localPosition;
                    },
                    onDoubleTap: _onDoubleTap,
                    onLongPress: () => _showImageMenu(url),
                    onSecondaryTapDown: Platform.isMacOS
                        ? (details) =>
                              _showImageContextMenu(details.globalPosition, url)
                        : null,
                    child: Center(
                      child: Hero(
                        tag: url,
                        child: SizedBox.expand(
                          child: CachedNetworkImage(
                            cacheKey: ArticleImageCacheService.displayCacheKey(
                              widget.articleId,
                              url,
                            ),
                            imageUrl: url,
                            fit: BoxFit.contain,
                            httpHeaders: ArticleImageService.httpHeaders,
                            memCacheWidth: cacheWidth,
                            maxWidthDiskCache: diskCacheWidth,
                            fadeInDuration: const Duration(milliseconds: 250),
                            fadeOutDuration: const Duration(milliseconds: 80),
                            placeholder: (context, url) => const SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.white70,
                                  size: 42,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '加载失败',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 顶部控制栏
            Positioned(
              top: topPadding + 12,
              left: 16,
              right: 16,
              child: IgnorePointer(
                ignoring: !_enablePageView, // 缩放时不拦截手势
                child: AnimatedOpacity(
                  opacity: _enablePageView ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.imageUrls.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.imageUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
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
    );
  }
}
