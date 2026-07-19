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
