import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/constants.dart';
import '../../utils/storage.dart';

/// 禁用所有 overscroll 指示器（Glow / Stretch）。
///
/// 用于配合 [RefreshIndicator] 使用——RefreshIndicator 自己管理下拉刷新的
/// 视觉效果，不需要平台自带的发光/拉伸动画干扰。
class NoOverscrollIndicatorBehavior extends MaterialScrollBehavior {
  const NoOverscrollIndicatorBehavior({this.macosMaxFlingVelocity});

  static const int macosMinFlingVelocity = 1000;
  static const int macosMaxAllowedFlingVelocity = 8000;

  final double? macosMaxFlingVelocity;

  static ScrollPhysics applyMacosFlingCap(
    ScrollPhysics physics, {
    double? maxFlingVelocity,
  }) {
    if (!Platform.isMacOS) {
      return physics;
    }
    return CappedMacosFlingPhysics(
      maxFlingVelocity: maxFlingVelocity,
    ).applyTo(physics);
  }

  static double get currentMacosMaxFlingVelocity {
    final raw = GStorage.setting.get(
      StorageKeys.macosMaxFlingVelocity,
      defaultValue: AppConstants.defaultMacosMaxFlingVelocity,
    );
    final value = switch (raw) {
      int v => v,
      double v => v.round(),
      _ => AppConstants.defaultMacosMaxFlingVelocity,
    };
    return value
        .clamp(macosMinFlingVelocity, macosMaxAllowedFlingVelocity)
        .toDouble();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 不添加任何平台指示器，直接返回 child
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final physics = super.getScrollPhysics(context);
    if (!Platform.isMacOS) {
      return physics;
    }
    return applyMacosFlingCap(physics, maxFlingVelocity: macosMaxFlingVelocity);
  }
}

/// macOS 触控板 fling 容易在长内容中滑出过远。该 physics 只限制
/// 松手后的 ballistic/fling 速度，不拦截手指仍在触控板上的滚动 delta。
class CappedMacosFlingPhysics extends ScrollPhysics {
  const CappedMacosFlingPhysics({super.parent, double? maxFlingVelocity})
    : _maxFlingVelocity = maxFlingVelocity;

  final double? _maxFlingVelocity;

  @override
  double get maxFlingVelocity =>
      _maxFlingVelocity ??
      NoOverscrollIndicatorBehavior.currentMacosMaxFlingVelocity;

  double _cap(double velocity) =>
      velocity.clamp(-maxFlingVelocity, maxFlingVelocity).toDouble();

  @override
  CappedMacosFlingPhysics applyTo(ScrollPhysics? ancestor) {
    return CappedMacosFlingPhysics(
      parent: buildParent(ancestor),
      maxFlingVelocity: _maxFlingVelocity,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    return super.createBallisticSimulation(position, _cap(velocity));
  }

  @override
  double carriedMomentum(double existingVelocity) {
    return _cap(super.carriedMomentum(_cap(existingVelocity)));
  }
}
