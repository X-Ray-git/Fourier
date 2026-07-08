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
- 垃圾拦截页开始复用普通时间线的同步按钮和文章 AI 右键菜单：刷新按钮位置已按时间线 header 对齐，文章审核行右键也有翻译/摘要相关动作。
- `flutter run -d macos --no-pub` 的“构建成功但等不到 debug connection”问题已定位为 Xcode Debug Dylib 被 macOS 系统策略拒载，并通过 Debug 配置 `ENABLE_DEBUG_DYLIB = NO` 修复。

本次待用户继续验证：

- macOS 无文章订阅源/筛选状态下，左侧列表空态勾图标和右侧文章空态图标的 y 轴对齐。
- 从具体订阅源回到“全部文章”时，中间时间线不再出现明显掉帧。
- 标为已读/恢复未读仍保留局部列表动画。
- 排序、切换筛选范围、同步回填、加载更多不再播放大规模新增/重排序动画。
- macOS 垃圾拦截页保留/移除按钮：保持圆形、右侧玻璃 tooltip，并在审核后下一篇移动到鼠标下方时立即刷新 hover。
- macOS 侧边栏订阅源分类展开/折叠 tooltip、订阅源搜索清空、设置/任务中心返回、订阅源详情 header 按钮等旧 tooltip/button 是否都符合当前玻璃/轻量控件语言。
- macOS 文章详情右上角“复制原文全文”按钮：复制 Markdown，包含元信息和当前已加载原文，不复制译文/摘要/目录，不触发额外网络拉取。
- 垃圾拦截页颜色：摘要完成态改为灰蓝，保留按钮改为沉稳 emerald；拒绝理由仍为 amber，移除仍为 `cs.error`。
- macOS 订阅源详情页仍可从订阅源 view/category 的“全部”入口进入；其 header 筛选已改为主时间线一致的二态 `未读/全部` switch，不应再出现 `仅已读` 三项菜单。
- macOS 文章列表卡片普通态已从“无底色/尝试细线边框”调整为 `ArticleCardChrome` 统一的极轻中性色填充；普通时间线和垃圾拦截审核行都应复用该样式，header 底部分隔线不再显示。

工具最近已验证：

- `dart analyze lib test`
- `flutter analyze lib test`
- `flutter test`
- `flutter build macos --debug`
- `flutter run -d macos --no-pub`
- `dart analyze lib/common/widgets lib/pages/widgets lib/pages/timeline`
- `dart analyze lib/pages/timeline/timeline_controller.dart lib/pages/timeline/timeline_page.dart lib/pages/main/widgets/macos_sidebar.dart lib/pages/article/article_page.dart lib/common/widgets/mac_empty_placeholder.dart lib/pages/feed_detail/feed_detail_page.dart lib/pages/timeline/filter_review_page.dart lib/pages/recent_read/recent_read_page.dart`

已知 analyzer 注意点：

- 完整 `dart analyze` 会扫描 `reference/`，并报告复制来的参考工程中的大量无关错误。使用限定项目范围的 analyze 命令。

文档维护规则：

- 更新当前工作对应的专题页。
- 将长期有效的取舍写入 `history/decisions.md`。
- 用 `history/historical-map.md` 定位旧上下文。
- 除非确实要保留原始时间线记录，否则不要继续向完整归档追加新工作。
