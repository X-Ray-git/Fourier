import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScrollUtils {
  /// 确保关联 [context] 的元素平滑滚动到可视区域内。
  /// 如果元素在可视区域上方，则会向上滚动；如果在下方，则会向下滚动。
  /// 相比于 `Scrollable.ensureVisible` 配合固定的 `alignmentPolicy`，
  /// 它可以自动判断方向，实现双向最小幅度的跟随滚动。
  static void ensureVisible(BuildContext context, {int durationMs = 250}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject == null) return;
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) return;

      final scrollableState = Scrollable.maybeOf(context);
      if (scrollableState == null) return;

      final position = scrollableState.position;
      final revealOffset = viewport.getOffsetToReveal(renderObject, 0.0);
      
      final targetTop = revealOffset.offset;
      final targetBottom = targetTop + renderObject.paintBounds.height;
      
      final viewTop = position.pixels;
      final viewBottom = position.pixels + position.viewportDimension;

      if (targetTop < viewTop) {
        // Item 跑到了可视区域上方 -> 向上滚动，使其对齐到顶部 (Start)
        Scrollable.ensureVisible(
          context,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      } else if (targetBottom > viewBottom) {
        // Item 跑到了可视区域下方 -> 向下滚动，使其对齐到底部 (End)
        Scrollable.ensureVisible(
          context,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }
}
