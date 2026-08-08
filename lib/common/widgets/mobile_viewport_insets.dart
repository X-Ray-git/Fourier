import 'package:flutter/material.dart';

/// 移动端主页面（extendBodyBehindAppBar: true）的共享内容 inset。
///
/// 真实列表、空态与所有时间线 / 垃圾拦截 / 订阅源骨架屏必须使用同一
/// 来源，禁止复制魔法数字，避免骨架卡片埋入毛玻璃 AppBar 后方。
abstract final class MobileViewportInsets {
  /// 顶部内容 inset：状态栏高度（列表从 AppBar 后方开始滚动）。
  static EdgeInsets listTopInset(BuildContext context) {
    return EdgeInsets.only(top: MediaQuery.paddingOf(context).top);
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
