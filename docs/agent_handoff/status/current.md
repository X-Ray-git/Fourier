# 当前状态

截至 2026-07-14：

- `main` 是当前集成分支。
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
- macOS 分屏文章详情右下角圆角安全区处理已由用户验证方向正确：正文 body 使用右下角 clip 避开窗口外框圆弧，避免内容贴到应用外框圆角。
- 最近阅读页文章进入详情后不应显示“标为已读”。根因是 `ArticleController` 只读 `GStorage.readStatus`，忽略了传入文章自身的 `isRead`；已修为 `LocalArticleDbService.readOverrideOf(entryId) ?? article.isRead`。时间线和最近阅读列表的本地已读合并也同步改为 `readOverrideOf()`，同时支持本地标已读和恢复未读。
- macOS 中间栏 header 的底部分隔线已统一取消，覆盖最近阅读、订阅源详情和垃圾拦截。普通时间线此前已取消同类分隔线。
- `ArticleCardChrome` 现在统一文章卡片外壳参数：外边距、内部 padding、圆角、普通态填充和边框。普通时间线 `ArticleCard` 与垃圾拦截 `_MacReviewRow` 都应从这里取值；垃圾拦截行只保留自身动作按钮和信息块结构差异。
- macOS 圆角收敛第一阶段已完成：原生窗口圆角、Flutter 外框、红黄绿圆心、侧边栏面板、大玻璃默认半径、设置/任务中心大面板和分屏文章右下角安全裁剪已联动调整。图片、代码块、小标签、`999` 胶囊和 Android 端刻意未纳入本轮。
- 玻璃控件颜色状态第一阶段已集中到 `AppGlassControlPalette`：通用玻璃按钮、文章目录项、文章摘要/翻译 pill、时间线排序项、主时间线/订阅源详情二态开关、设置页部分控件已改为通过 palette 取 hover/pressed/active/border/disabled 色。用户验证第一阶段体感基本和改动前一致，这是预期。
- 设置页 macOS 下拉菜单 overlay 已补局部静态底色，并让底色圆角和外框圆角对齐，解决透明背景导致选项和背后内容混在一起的问题。
- 玻璃按钮角色统一第二阶段已完成并由用户验证：`AppGlassRoundControlChrome` 统一圆形工具按钮外壳；排序/同步按钮背景保持中性，非默认排序和同步中只让图标变橙；刷新空闲态图标回到更接近白色的中性前景；目录按钮关闭态材质调浅，和复制按钮不再明显割裂。未读文章“标为已读”按钮继续保留橙色图标和浅橙背景，作为主动作语义。
- `未读/全部` 紧凑二态 switch 的 2.1 结构收敛已完成并由用户验证：主时间线与订阅源详情页现在共用 `AppGlassCompactSwitch`，点击、滑块动画、hover/press、筛选结果和性能体感保持一致。
- `未读/全部` switch 与设置页 segmented 的 2.2 视觉收敛已完成并由用户验证：选中滑块改为中性 `AppGlassSurface` control 材质，橙色只作为极弱 tint 和文字状态色；外层静态 rim 通过 `staticBorderOpacity` 局部降弱，用户确认效果不错且没有明显掉帧。
- macOS 分栏文章列表协调器第一阶段已完成：新增 `MacSplitArticleListCoordinator`，垃圾拦截的 `M`、保留和移除在业务状态变化前登记后继项，退出动画期间保持旧详情，真实 `onRemoveEnd` 后才切换并 reveal 下一篇。用户初步验证体验良好；主时间线和最近阅读仍待分阶段迁移。
- 垃圾拦截审核交互已收敛：macOS 卡片改为仅触控板双指横滑（右滑保留、左滑移除），鼠标拖动不触发；`K/M` 和右键菜单作为后备入口。横滑背景使用圆角路径差集，只显示在卡片真实让出的区域，用户已确认视觉符合预期；快速 `Command-Z` 会等待旧退出动画结束后再恢复同一文章。
- Android 垃圾拦截继续使用 `Dismissible`，但卡片外边距移到滑动组件外部，解决圆角卡片与保留/移除背景之间的空带。`ArticleCard` 的可选 `outerPadding` 默认不改变其他页面。
- macOS 顶部玻璃工具按钮、紧凑 switch 和目录 morph 按钮已接入 `MacOSWindowDragGuard`：指针按住这些控件时临时关闭 AppKit 窗口拖动，避免轻微位移把按钮点击误判为移动窗口；空白 header 区域仍可拖动窗口。
- macOS `未读/全部` 紧凑 switch 已按用户视觉实验收窄为 `58px` 轨道、`42px` 滑块，去掉外层内缩 padding，并把静态 rim 提高到 `0.70`；时间线 header 间距为 switch→排序 `8px`、排序→同步 `8px`、同步→右边界 `10px`。
- macOS 右侧文章正文 scrollbar 保持 `8px` 宽，距离文章面板右边界改为 `4px`；中间时间线/垃圾拦截列表仍是 `8px` 宽、距离各自右边界 `1px`，不要混淆两套 margin。
- macOS 垃圾拦截的 `M/K`、右键和触控板审核操作不再让 `ArticleStateNotifier` 提前删除列表项。页面用 pending action 隔离同步状态回调，并在帧边界只提交一次列表删除；用户连续验证 `M/K` 动画正常。
- macOS 主时间线双击标为已读会把本地持久化与可视列表更新拆到两个帧边界，避免同步数据库写入吞掉 180ms 移除动画。需要移除卡片时，外部浏览器只在 `remove.end` 后的下一帧打开，避免动画中途失焦；用户视觉验证通过。
- 两条动画链保留默认关闭的诊断埋点。仅在 Debug 并显式传 `--dart-define=AUTO_FOLO_ANIMATION_PROBE=true` 时启用；Release 和普通 Debug 不注册帧耗时回调，也不挂载动画监听器。
- macOS 静默订阅源分组不再因“被选中”而自动展开。点击分组行只进入静默时间线，只有独立展开按钮会改变子列表展开状态。
- macOS 中间栏与文章详情已接入透明 header + soft scroll edge：内容滚入 header 后按 ease-in-out alpha 融入页面背景，不做逐位置动态模糊。主时间线、垃圾拦截、最近阅读和订阅源详情共用 `MacHeaderScrollEdge`。
- header-aware scrollbar 已改为显式 `RawScrollbar.padding`，轨道真正从 header 下缘开始，渐隐层避开 thumb。主时间线和最近阅读内部会覆盖共享行为的旧局部 `ScrollConfiguration` 已清理；用户确认主时间线 scrollbar 起点和卡片遮挡关系正常。
- macOS 文章 header 的整块 `BackdropFilter` 已移除，避免相邻按钮光效被采样到左侧；阅读进度条移至文章面板最顶端。Android header/进度条行为不变。
- Android 垃圾拦截横滑背景已补齐和 macOS 相同的圆角路径差集裁剪；移动端仍由 `Dismissible` 处理手势和阈值，只共享卡片前后层级的几何规则。

本次待用户继续验证：

- macOS 圆角收敛：外框和红黄绿是否仍自然对齐；侧边栏是否比旧版略收敛但不生硬；设置/后台任务大面板是否一致；文章卡片 `10` 圆角是否比旧 `8` 更符合预期。
- macOS 最近阅读页文章标题：已读状态只靠颜色淡化区分，不再降低标题字重。
- macOS 中间栏 header：主时间线、订阅源详情、最近阅读、垃圾拦截均不应再出现横向底部分隔线。
- macOS 垃圾拦截审核行：卡片顶部、左右、内部 padding 和圆角应与主时间线文章卡片一致。
- macOS 最近阅读页进入文章详情时，右上角应显示符合已读状态的操作，不应把最近阅读文章误判为未读。
- macOS 无文章订阅源/筛选状态下，左侧列表空态勾图标和右侧文章空态图标的 y 轴对齐。
- 从具体订阅源回到“全部文章”时，中间时间线不再出现明显掉帧。
- 标为已读/恢复未读仍保留局部列表动画。
- 排序、切换筛选范围、同步回填、加载更多不再播放大规模新增/重排序动画。
- macOS 垃圾拦截横滑：右滑保留、左滑移除；鼠标拖动不应触发，短距离应回弹，越过阈值后应先横向离场再纵向收缩，快速 `Command-Z` 应恢复并重新选中文章。
- macOS 侧边栏订阅源分类展开/折叠 tooltip、订阅源搜索清空、设置/任务中心返回、订阅源详情 header 按钮等旧 tooltip/button 是否都符合当前玻璃/轻量控件语言。
- macOS 文章详情右上角“复制原文全文”按钮：复制 Markdown，包含元信息和当前已加载原文，不复制译文/摘要/目录，不触发额外网络拉取。
- 垃圾拦截页颜色：摘要完成态改为灰蓝，保留按钮改为沉稳 emerald；拒绝理由仍为 amber，移除仍为 `cs.error`。
- macOS 订阅源详情页仍可从订阅源 view/category 的“全部”入口进入；其 header 筛选已改为主时间线一致的二态 `未读/全部` switch，不应再出现 `仅已读` 三项菜单。
- macOS 文章列表卡片普通态已从“无底色/尝试细线边框”调整为 `ArticleCardChrome` 统一的极轻中性色填充；普通时间线和垃圾拦截审核行都应复用该样式，header 底部分隔线不再显示。
- macOS 侧边栏：静默订阅源应出现在 `订阅源` 滚动列表末尾，作为特殊订阅源分组；旧折叠侧边栏入口和分支已清理，侧边栏只保留展开态。

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
