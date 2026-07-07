# 当前状态

截至 2026-07-08：

- `main` 是当前集成分支。
- 本次文档重构前，最新已推送提交是 `5e11c9d fix: refresh summary controls immediately`。
- 本地 `main` 仍可能领先远端；提交/推送前必须先看 `git status --short --branch`。
- 最近一批 worktree 功能已经用 merge commit 合入 `main`，保留了分支历史。
- 除非用户明确要求，否则不要创建 release/tag。
- `AGENT_HANDOFF.md` 现在只作为短入口。维护型交接知识库位于 `docs/agent_handoff/`。
- `docs/agent_handoff/history/timeline.md` 是完整时间线归档，不是维护当前事实的首选位置。

当前产品形态：

- Flutter 应用，使用 GetX、Hive、Dio 和本地缓存。
- 产品名：`Auto Folo`。
- Dart package 名仍是 `autofolo`。
- Android application id、macOS bundle id、MethodChannel 命名空间使用 `io.github.xraygit.autofolo`。
- 这是 X-Ray 个人使用的软件，围绕 Folo 使用场景构建，但不能暗示官方 Folo 所有权。

用户最近已验证：

- 大批 worktree 合入后的 macOS 视觉检查可接受。
- macOS 文章工具栏 hover 闪烁已修复。
- 从卡片右键菜单删除摘要后，文章详情能立即更新。
- macOS debug 构建/运行在关闭 CocoaPods 并行签名并放开 debug library validation 后恢复正常。
- macOS 中间时间线在具体订阅源筛选状态下，header 不再显示重复的订阅源级按钮，也不再显示清除筛选按钮；用户验证该视觉调整符合预期。

工具最近已验证：

- `dart analyze lib test`
- `flutter analyze lib test`
- `flutter test`
- `flutter build macos --debug`
- `flutter run -d macos --no-pub`

已知 analyzer 注意点：

- 完整 `dart analyze` 会扫描 `reference/`，并报告复制来的参考工程中的大量无关错误。使用限定项目范围的 analyze 命令。

文档维护规则：

- 更新当前工作对应的专题页。
- 将长期有效的取舍写入 `history/decisions.md`。
- 用 `history/historical-map.md` 定位旧上下文。
- 除非确实要保留原始时间线记录，否则不要继续向完整归档追加新工作。
