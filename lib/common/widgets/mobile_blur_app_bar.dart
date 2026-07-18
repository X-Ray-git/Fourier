import 'dart:ui';

import 'package:flutter/material.dart';

const mobileAppBarToolbarHeight = 48.0;

class MobileBlurAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget>? actions;
  final bool centerTitle;
  final double toolbarHeight;

  const MobileBlurAppBar({
    super.key,
    this.title,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.centerTitle = true,
    this.toolbarHeight = mobileAppBarToolbarHeight,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      title: title,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
      backgroundColor: cs.surface.withValues(alpha: 0.74),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
