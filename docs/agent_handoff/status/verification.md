# 验证记录

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
