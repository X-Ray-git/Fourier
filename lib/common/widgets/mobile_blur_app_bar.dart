import 'dart:ui';

import 'package:flutter/material.dart';

const mobileAppBarToolbarHeight = 48.0;

class MobileBlurAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final double? leadingWidth;
  final double? titleSpacing;
  final List<Widget>? actions;
  final bool centerTitle;
  final double toolbarHeight;
  final bool blurBackground;
  final Clip clipBehavior;

  const MobileBlurAppBar({
    super.key,
    this.title,
    this.leading,
    this.leadingWidth,
    this.titleSpacing,
    this.actions,
    this.centerTitle = true,
    this.toolbarHeight = mobileAppBarToolbarHeight,
    this.blurBackground = true,
    this.clipBehavior = Clip.hardEdge,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      title: title,
      leading: leading,
      leadingWidth: leadingWidth,
      titleSpacing: titleSpacing,
      actions: actions,
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
      clipBehavior: clipBehavior,
      forceMaterialTransparency: !blurBackground,
      backgroundColor: blurBackground
          ? cs.surface.withValues(alpha: 0.74)
          : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: blurBackground
          ? ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const SizedBox.expand(),
              ),
            )
          : null,
    );
  }
}
