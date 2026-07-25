# 发布与构建

除非用户明确要求，否则不要创建 release。

当前发布流程：

- 使用 `scripts/release.sh`。
- 脚本只允许在 `main` 分支运行；不要从功能分支直接创建发布 tag。
- release tag 必须是 annotated tag。
- GitHub Actions 会从 tag 构建 Android APK 和 macOS arm64 产物。
- 本地和 GitHub Actions 统一使用 Flutter `3.44.6`；项目最低约束为 Flutter `>=3.44.0`、Dart `^3.12.2`。升级 SDK 时必须同步检查 `pubspec.yaml`、lockfile 和工作流中的两个 Flutter pin，不能只改本机。
- macOS 发布包必须保持 arm64。
- macOS job 固定使用 `macos-26` ARM64 runner。原生侧边栏使用了 macOS 26 SDK 的 `NSGlassEffectView`，不要改回默认仍可能选择 Xcode 16 的 `macos-latest`，否则 CI 可能在 Swift 编译阶段失败。
- macOS 原生插件已迁移为纯 Swift Package Manager。仓库不再保留 `macos/Podfile`、`Podfile.lock` 或 Xcode Pods 引用；`screen_retriever` 至少保持 `0.2.2`，该版本修复了其 macOS SwiftPM manifest。若构建再次输出 `Running pod install`，应先排查是否误恢复 CocoaPods 集成。
- 每次发布的可复现命令追加到 `docs/agent_handoff/history/releases.md`；根 `AGENT_HANDOFF.md` 始终保持为短入口。

## 版本号规则

`pubspec.yaml` 的 `version: X.Y.Z+N` 是唯一版本来源：

- `X.Y.Z` 是用户可见版本，并对应 annotated tag `vX.Y.Z`。
- `N` 是单调递增的内部构建号；Android 使用它作为 `versionCode`，macOS 使用它作为 `CFBundleVersion`。
- Major、Minor 或 Patch 变化时都不能重置构建号。
- 普通 commit 不修改版本号；只有真正创建发布时才由 `scripts/release.sh` 更新版本并把构建号加一。
- 不要手工同步 Android、macOS、设置页或请求头中的版本；这些位置应继续从 Flutter/pubspec 版本读取。

面向当前个人应用的版本语义：

- **Major（`2.0.0`）**：产品定位根本变化，或配置、本地数据、安装身份和核心工作流出现无法平滑迁移的不兼容。单纯 UI 大改通常不升 Major。
- **Minor（`1.2.0`）**：新增明确功能或工作流，一批相关功能形成新阶段，或者完成重要但保持用户数据兼容的 UI/架构重构。
- **Patch（`1.2.1`）**：Bug 修复、性能优化、视觉微调和小范围行为完善，不引入新的主要工作流。

历史 `v1.1.1` 到 `v1.1.28` 长期把功能和重构也作为 Patch 发布，不重写这些历史。从下一次发布开始执行上述规则。`v1.1.28` 之后已积累 Android 主导航与设计迁移、静默订阅源批量导出、macOS Undo/Redo、媒体与缓存能力、认证/设置收敛、SwiftPM 和许可证体系，因此观察稳定后应进入 `v1.2.0`；如果期间没有其他发布，对应 pubspec 为 `1.2.0+31`。

当前脚本和 CI 只接受纯 `X.Y.Z`，尚未支持 `1.2.0-beta.1`。不要只改 tag 或 pubspec 来临时创建预发布版；若未来确实需要 Beta，必须先统一修改 release 脚本、pubspec/tag 校验、GitHub Actions 和 GitHub Release 的 prerelease 标记。

Release notes 规则：

- `scripts/release.sh` 默认拒绝 `-m` 中的字面量 `\n`。
- 真实换行使用 ANSI-C quoting：

```bash
./scripts/release.sh 1.2.3 -m $'- fix: first item\n- feat: second item' --push
```

- 如果确实需要字面量 backslash-n，使用 `--allow-literal-backslash-n`。

签名：

- Android 包名相同但签名 key 不同时会安装冲突。
- 项目已通过 GitHub Secrets 让 GitHub 内部构建签名与用户本地 debug keystore 对齐。
- GitHub Secrets 不存放在仓库中。

本地构建命令：

```bash
flutter build apk --debug
flutter build macos --debug
```

Flutter `3.44.6` 迁移完成时，本机已通过 Android Debug、macOS Debug 和 macOS Release 构建，Release 主程序确认为 arm64。以后本地 release 失败仍应先区分签名/framework 环境问题与代码回归。
