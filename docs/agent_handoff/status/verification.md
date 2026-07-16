# 验证记录

## 仍需持续观察

- 自动 AI 队列：刷新后快速把等待翻译/摘要的文章标为已读，后台等待数量应下降，文章不应长期停留在“翻译中”。已经进入处理批次的任务继续完成属于预期。
- macOS 空状态对齐：在没有文章的订阅源或筛选范围中，左侧列表空态勾图标与右侧文章空态图标应处于同一视觉高度。该项修复后没有留下明确的最终用户确认，因此继续保留观察。

其余曾列在 `status/current.md` 的 macOS 视觉、列表动画、横滑、tooltip、复制、卡片和侧边栏检查均已在后续使用或提交前验证中通过，不再作为开放验证项重复维护。

## 2026-07-16 Android 设计迁移阶段验证

用户已在真机 Debug/Release 路径完成视觉检查：

- 主时间线与订阅源详情 `未读/全部` 筛选、滑块边界和 `12px` 卡片对齐正确。
- 最近阅读入口、文章圆形已读按钮、目录面板和订阅源设置面板可用。
- 底部悬浮导航选中反馈、三页淡入淡出和仅向外扩散的阴影符合预期。
- Inbox 展开不再出现 Debug 红色 GetX 错误或 Release 灰色色块。
- 底部面板统一 `32px` 圆角后未发现屏幕边缘溢出。

仍需在后续阶段验证：Android 设置页、后台任务中心和其余次级页面迁移；最终物理屏幕圆角同心关系。

推荐 Android 检查：

```bash
dart analyze lib test
flutter test --no-pub
flutter build apk --debug --no-pub
flutter run -d <device-id> --no-pub
```

## 常规检查

推荐检查：

```bash
dart analyze lib test
flutter analyze lib test
flutter test
flutter build macos --debug
```

迭代时可以使用更小范围的检查：

```bash
dart analyze lib/pages/article/article_page.dart
flutter test test/article_model_test.dart test/feed_model_test.dart test/html_entity_utils_test.dart
```

不要依赖：

```bash
dart analyze
```

原因：仓库的 `reference/` 下有复制来的参考工程；完整 `dart analyze` 会把它们也扫进去，并产生无关错误。

macOS 本地 UI 验证：

```bash
flutter run -d macos
```

或者：

```bash
flutter build macos --debug
open "build/macos/Build/Products/Debug/Auto Folo.app"
```

不要把本地 macOS release 构建作为主要 UI 验证目标。本地环境可能把 release 产物视为 ad-hoc 签名或未知证书链，从而造成启动/framework 加载问题；这不一定和当前代码有关。

如果 macOS Debug 出现“构建成功但等不到 debug connection”：

```bash
flutter clean
flutter pub get
flutter run -d macos --no-pub
```

当前 Debug 配置依赖 `ENABLE_DEBUG_DYLIB = NO` 避免 `Auto Folo.debug.dylib` 被 macOS 系统策略拒载。验证时应看到 `A Dart VM Service on macOS is available at:`。
