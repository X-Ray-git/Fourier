import 'package:flutter/material.dart';

import 'mobile_blur_app_bar.dart';

/// 移动端主页面（extendBodyBehindAppBar: true）的共享内容 inset。
///
/// 真实列表、空态与所有时间线 / 垃圾拦截 / 订阅源骨架屏必须使用同一
/// 来源，禁止复制魔法数字，避免骨架卡片埋入毛玻璃 AppBar 后方。
abstract final class MobileViewportInsets {
  /// 顶部内容 inset。主导航 body 延伸到 AppBar 后方时，首项需要避开
  /// 状态栏和工具栏；独立 Scaffold 的 body 已由框架放在 AppBar 下方。
  static EdgeInsets listTopInset(
    BuildContext context, {
    bool bodyExtendsBehindAppBar = true,
  }) {
    if (!bodyExtendsBehindAppBar) return EdgeInsets.zero;
    return EdgeInsets.only(
      top: MediaQuery.paddingOf(context).top + mobileAppBarToolbarHeight,
    );
  }

  /// 底部内容 inset：底部导航栏 + 系统导航栏 + 间距。
  static EdgeInsets listBottomInset(BuildContext context) {
    return EdgeInsets.only(
      bottom:
          8 +
          kBottomNavigationBarHeight +
          MediaQuery.of(context).padding.bottom,
    );
  }
}
