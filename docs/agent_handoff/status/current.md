# 当前状态

截至 2026-07-19：

- `main` 是当前集成分支。
- Android 设计迁移已通过 merge commit `bd8c1b8` 合入 `main`；新代理应以 `main` 中的移动端实现为当前事实，不再等待旧 `android` 分支。
- 本地 `main` 仍可能领先远端；提交/推送前必须先看 `git status --short --branch`。
- 最近一批 worktree 功能已经用 merge commit 合入 `main`，保留了分支历史。
- 除非用户明确要求，否则不要创建 release/tag。
- `AGENT_HANDOFF.md` 现在只作为短入口。维护型交接知识库位于 `docs/agent_handoff/`。
- 旧单文件时间线已拆入 `docs/agent_handoff/history/archive/`；`history/chronology.md` 提供全部旧章节索引，`history/timeline.md` 仅保留兼容入口。当前事实不得写入历史归档。

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
- 工具链已对齐到本地与 GitHub Actions 均使用 Flutter `3.44.6`，项目最低约束为 Flutter `>=3.44.0`、Dart `^3.12.2`。macOS 插件完成纯 SwiftPM 迁移，`screen_retriever 0.2.2` 修复最后一个不兼容项；CocoaPods 工程引用、Podfile/lock 和旧并行签名补丁已删除。Android Debug、macOS Debug/Release 均已本地构建通过，Release 主程序确认为 arm64。
- macOS 中间时间线在具体订阅源筛选状态下，header 不再显示重复的订阅源级按钮，也不再显示清除筛选按钮；用户验证该视觉调整符合预期。
- 垃圾拦截页开始复用普通时间线的同步按钮和文章 AI 右键菜单：刷新按钮位置已按时间线 header 对齐，文章审核行右键也有翻译/摘要相关动作。
- `flutter run -d macos --no-pub` 的“构建成功但等不到 debug connection”问题已定位为 Xcode Debug Dylib 被 macOS 系统策略拒载，并通过 Debug 配置 `ENABLE_DEBUG_DYLIB = NO` 修复。
- macOS 分屏文章详情右下角圆角安全区处理已由用户验证方向正确：正文 body 使用右下角 clip 避开窗口外框圆弧，避免内容贴到应用外框圆角。
- 最近阅读页文章进入详情后不应显示“标为已读”。根因是 `ArticleController` 只读 `GStorage.readStatus`，忽略了传入文章自身的 `isRead`；已修为 `LocalArticleDbService.readOverrideOf(entryId) ?? article.isRead`。时间线和最近阅读列表的本地已读合并也同步改为 `readOverrideOf()`，同时支持本地标已读和恢复未读。
- macOS 中间栏 header 的底部分隔线已统一取消，覆盖最近阅读、订阅源详情和垃圾拦截。普通时间线此前已取消同类分隔线。
- `ArticleCardChrome` 现在统一文章卡片外壳参数：外边距、内部 padding、圆角、普通态填充和边框。普通时间线 `ArticleCard` 与垃圾拦截 `_MacReviewRow` 都应从这里取值；垃圾拦截行只保留自身动作按钮和信息块结构差异。
- macOS 圆角收敛第一阶段已完成：原生窗口圆角、Flutter 外框、红黄绿圆心、侧边栏面板、大玻璃默认半径、设置/任务中心大面板和分屏文章右下角安全裁剪已联动调整。图片、代码块、小标签、`999` 胶囊和 Android 端刻意未纳入本轮。
- 玻璃控件颜色状态第一阶段已集中到 `AppGlassControlPalette`：通用玻璃按钮、文章目录项、文章摘要/翻译 pill、时间线排序/范围选项、设置页部分控件已改为通过 palette 取 hover/pressed/active/border/disabled 色。用户验证第一阶段体感基本和改动前一致，这是预期。
- 设置页 macOS 下拉菜单 overlay 已补局部静态底色，并让底色圆角和外框圆角对齐，解决透明背景导致选项和背后内容混在一起的问题。
- macOS 固定圆形工具按钮继续由 `AppGlassRoundControlChrome` 统一外壳。深色按钮专属 control tint 现为普通 control alpha 的 `0.52`，有效白色 tint 约 `12%`；浅色按钮采用参考工程的冷白 `12%` tint、`12` 光学厚度、`5` blur、左上高光、`0.15` 环境光、`1.2` 折射/饱和度和轻微色散，并使用只绘制在形状外部的反向裁切双层阴影。tooltip、菜单、大面板和红/绿语义按钮不随这组参数改变。
- macOS 主时间线与订阅源详情的 `未读/全部` 已放弃紧凑 switch，改为和排序相同的 `34px` 圆形 morph 选择按钮。两者与排序统一复用 `AppGlassMorphSelectionButton`；旧 `AppGlassCompactSwitch` 和时间线私有排序 morph 代码已删除。展开菜单标题为“文章范围”，只包含“未读/全部”，不重新引入“已读”。
- `未读/全部` 触发图标使用 `filter_alt_rounded` / `filter_alt_off_rounded`，不以橙色表达选中：深色固定白色，浅色使用主题 `onSurface` 深色前景；菜单内选项仍按通用选择项规则显示当前项。设置页 segmented 保持独立，不随本轮迁移。
- macOS 分栏文章列表协调器已覆盖垃圾拦截和主时间线：垃圾拦截的 `M`、保留、移除以及主时间线的 `M`、双击都会在业务状态变化前登记后继项，退出动画期间保持旧详情，真实 `onRemoveEnd` 后才切换并 reveal 下一篇。最近阅读继续保留现有实现，是否迁移取决于后续是否出现同类故障。
- 垃圾拦截审核交互已收敛：macOS 卡片改为仅触控板双指横滑（右滑保留、左滑移除），鼠标拖动不触发；`K/M` 和右键菜单作为后备入口。横滑背景使用圆角路径差集，只显示在卡片真实让出的区域，用户已确认视觉符合预期；快速 `Command-Z` 会等待旧退出动画结束后再恢复同一文章。
- Android 垃圾拦截继续使用 `Dismissible` 处理手势和阈值，但保留/移除背景已移出其原生 background 槽位，改由固定圆角 `ClipRRect > Stack` 在下层绘制圆角路径差集，`Dismissible` 只移动上层卡片。这样既保留外侧 `16px` 圆角，也不会让 Flutter 内部矩形 `_DismissibleClipper` 截断彩色背景与移动卡片交界处的圆弧；用户已在 Android 真机 Debug 中确认视觉正确。
- macOS 顶部玻璃工具按钮、共享 morph 选择按钮和目录 morph 按钮均通过圆形 control chrome 接入 `MacOSWindowDragGuard`：指针按住这些控件时临时关闭 AppKit 窗口拖动，避免轻微位移把按钮点击误判为移动窗口；空白 header 区域仍可拖动窗口。
- macOS `AppGlassTooltip` 已加入共享窗口碰撞布局：气泡按真实尺寸限制在四周 `8px` 内，并在底部/右侧空间不足时自动翻转；缩放动画锚点同步跟随最终方向，始终靠近触发控件。文章右上角长 tooltip 和其他靠边 tooltip 不再伸出窗口被裁切；三类边界/方向回归测试已覆盖，用户视觉验证通过。
- macOS 时间线 header 现在依次使用 `34px` 文章范围按钮、`34px` 排序按钮和同步按钮；范围→排序 `8px`、排序→同步 `8px`、同步→右边界 `10px`。文章范围从旧 `58px` switch 收敛为圆形入口后，不应再按旧轨道/滑块参数调整布局。
- macOS 右侧分屏正文已移除显式 scrollbar，并继续关闭 Flutter 自动 scrollbar；顶部阅读进度条承担位置反馈，正文基础左右 padding 保持 `11px`。中间时间线/垃圾拦截、设置页、侧边栏和 Android 的 scrollbar 均未随之改动。
- macOS 垃圾拦截的 `M/K`、右键和触控板审核操作不再让 `ArticleStateNotifier` 提前删除列表项。页面用 pending action 隔离同步状态回调，并在帧边界只提交一次列表删除；用户连续验证 `M/K` 动画正常。
- macOS 主时间线双击标为已读会把本地持久化与可视列表更新拆到两个帧边界，避免同步数据库写入吞掉 180ms 移除动画。需要移除卡片时，外部浏览器只在 `remove.end` 后的下一帧打开，避免动画中途失焦；用户视觉验证通过。
- macOS 主时间线偶发无动画和 `M` 后回到顶部已完成分层修复并由用户确认：列表实例保持稳定，`M`/双击共用 `MacSplitArticleListCoordinator`；会移除卡片时只增量删除当前可见项，完整 `_applyFilter()`、角标/计数和 `ArticleStateNotifier` 跨页面扇出延后到真实 `onRemoveEnd` 后。最终日志在约 `4799` 篇本地文章下确认两次 `M`、四次双击都完整经过 `4→3→2→1→0` 动画阶段，增量更新约 164–671 微秒，移除期间没有列表 reset。
- 已读文章偶发重新出现的状态竞态已定位并修复：mark-read 与未读列表请求并发时，旧代码会在同步成功后过早清除本地 true 覆盖，较早发出的旧未读快照随后把文章降级。当前 true 覆盖保留到成功未读快照明确不再包含该文章；主时间线和订阅源详情规则一致。
- 两条动画链保留默认关闭的诊断埋点。仅在 Debug 并显式传 `--dart-define=AUTO_FOLO_ANIMATION_PROBE=true` 时启用；Release 和普通 Debug 不注册帧耗时回调，也不挂载动画监听器。
- macOS 静默订阅源分组不再因“被选中”而自动展开。点击分组行只进入静默时间线，只有独立展开按钮会改变子列表展开状态。
- macOS 普通订阅源分类已分离手动展开与当前订阅源触发的临时展开：查看具体订阅源时父分类锁定展开，切到最近阅读等其他页面后解除锁定并恢复用户原来的展开状态；用户已验证该交互符合预期。
- macOS 订阅源分类行现在共用整行 hover/press 反馈；展开箭头保留独立点击和 tooltip，但不再绘制第二套圆形 overlay。用户已确认箭头区域与分类其余区域的视觉反馈一致。
- macOS 订阅源侧边栏已改为独立显式 scrollbar 和精确总高度滚动区，避免粗粒度懒加载大组在滑动时反复修正总滚动范围。折叠分类仍不构建内部订阅源，展开/选择等业务语义不变。
- macOS 透明 header + soft scroll edge 实验已按用户长期视觉反馈撤销。主时间线、垃圾拦截、最近阅读和订阅源详情改用共享 `MacHeaderPane`：固定 `surface` header，内容和 scrollbar 从其下方开始，中间栏 header 仍无底部分隔线。
- macOS 文章 header 保持固定 `surface`，且继续不使用整块 `BackdropFilter`，避免采样相邻按钮高光。顶部状态不再显示“文章详情”、分隔线和阅读进度；正文大标题接近完全滚出后，文章标题左对齐进入 header，`1px outlineVariant / alpha 0.30` 分隔线与橙色阅读进度同步渐显。用户已完成视觉验证。
- 垃圾拦截同步按钮与主时间线共用 `AppGlassSyncButton`，右侧 inset 也统一为 `10px`。
- 正文图片文章级预取/清理机制已覆盖 macOS 与 Android：macOS 预取全部本地未读文章，每篇最多 8 张、并发 16、当前文章优先 4 张；Android 预取前 50 篇本地未读文章，每篇最多 4 张、并发 4、当前文章优先 2 张，当前不区分 Wi-Fi 与移动网络。两端都不使用 hover，正常加载和查看器统一使用文章级缓存键；保持已读 5 分钟后串行清理该文章登记的原图/缩放缓存，恢复未读可重入队列。历史 `v2_` 缓存暂不清理。
- 自动翻译/摘要只在正文持久化后、准备入队时读取最新本地已读状态：当时已读则不入队，当时未读则正常入队且后续不因标记已读而取消。这取代了长期使用中效果很有限的“已读后移出等待队列”机制；手动操作和垃圾拦截判定不受影响。
- HTML 清洗修复了半透明内容被误删、顶层转义文本变成标签、同一文章正文更新命中旧缓存，以及 `<p><span><br></span></p>` 格式包装空段未被删除的问题。空段清洗保护媒体与 `id/name` 锚点，不合并正常非空段落。规范化缓存以正文 SHA-256 指纹校验变化，不额外长期保存第二份原始 HTML。没有有效地址的 iframe、video 或 audio 保留为明确的不可用提示，并提供经过 HTTP/HTTPS 校验的原文入口；video 与 audio 都支持从子级 `<source src>` 提取资源。
- Bilibili 官方站外播放器已作为常见正文视频媒介接入：少数派最近 5 篇“本周看什么”在本地文章库中共确认 23 个标准 embed，另有少数派其他文章和小众软件使用相同结构。`BilibiliEmbedInfo` 只接受精确 `player.bilibili.com/player.html` 与有效 `bvid/aid`；readability 仅对白名单内的 YouTube/Bilibili iframe 放行。两者共用懒加载 `WebEmbedVideoPlayer`，但各自维护严格解析、导航域名和外部地址；Bilibili 未播放态不额外请求封面 API，也不解析真实媒体流。
- 原文 Markdown 转换已从 `article_page.dart` 提取到 `ArticleMarkdownExportService`；单篇复制和批量构建共享标题去重、元数据、正文结构和转义规则。页面层只处理当前内容、剪贴板与反馈，后续静默订阅源批量功能不得再维护页面内 exporter。
- 来源专属正文兼容已集中到 `ArticleContentCompatibility`。Hugging Face Blog 的 `BlogAuthorsByline` 会转换为单个紧凑作者 chunk，以 `36px` 圆形头像、姓名和账号横向换行展示；站点装饰头像仅在头像域名/路径和明确头像语义同时成立时移除。原文与已保存译文都在解析前走同一规范化路径，历史文章不需要数据库迁移。
- Debug 与 Release 网络请求现在统一使用系统 HTTPS 证书信任链，不再通过 `badCertificateCallback` 无条件接受无效证书；自定义 `HttpClient` 的 `15s` idle timeout 保持不变。需要抓包时应安装并信任代理证书，而不是在应用内关闭校验。
- 设置页保存语义已统一并经用户运行确认：离散选择直接保存，LLM 卡片不再保留整卡保存按钮；Temperature、并发数、正文宽度、滚动速度和已读窗口等单值数字输入按 Enter/失焦静默保存，不再排列保存按钮。Folo Session Token 与 DeepSeek API Key 已合并到“服务认证”，共用右下角“测试连接 + 保存认证”：测试使用当前输入但不保存，分别调用 Folo `/subscriptions` 与 DeepSeek `/models`；DeepSeek 留空时显示“未配置，已跳过”，不影响 Folo 测试结果。Folo 只要求 Session Token，DeepSeek 留空表示清除磁盘值和翻译/摘要服务的运行时 Key；旧备份中的 Client ID 和 Session ID 可被兼容导入但会忽略、清理且不再导出。Prompt 继续明确保存。macOS 外观 segmented 独占完整一行，重置默认立即落盘，快速离散切换按最后一次选择串行写入。
- macOS 红黄绿按钮已从“不受支持地移动系统标准按钮”切回可控的 AppKit 自绘 `NSControl` 容器。用户已验证 hover 和点击符合预期：任一圆形按钮触发三颗同步显示符号，按钮间空隙不触发，命中范围和视觉一致；动作仍转发给隐藏系统按钮的 target/action。
- macOS 26 侧边栏已从“全窗口 `NSVisualEffectView` + Flutter 白色/模糊覆盖”迁移为局部 `NSGlassEffectView(.regular)`。用户确认纯原生版本整体观感很好；浅色/深色跟随应用 appearance，同一原生组件不分叉维护。旧系统保留局部 `NSVisualEffectView` 回退。
- 侧边栏原生 backdrop 向 Flutter 连续曲率开口后方外扩 `1px`，堵住系统圆角与 Flutter 抗锯齿不一致造成的漏底细缝。最终轮廓为 `0.5px` 环境描边（浅色黑 `12%`、深色白 `12%`），浅色另加轻微外侧阴影；用户明确不增加原生玻璃之外的二次模糊。
- 浅色玻璃控件已补齐明暗同步和材质一致性：原生 AppKit appearance、Flutter theme 和 renderer platform brightness 同步；浅色选中控件使用稳定冷白基底；文章目录关闭态复用普通圆形玻璃按钮，只有形变期间使用 morph layer；复制/已读按钮恢复 own layer 边界层次。
- macOS 文章目录展开态已增加浮动玻璃可读性遮罩：深色模式黑色 `32%`、浅色模式白色 `18%`，在 morph 后半段平滑渐入并先于目录文字到位。它避免目录覆盖白色图片等高亮正文时浅色文字完全消失；关闭态圆形按钮、玻璃折射、边缘和既有展开/收起动画不变。用户已完成视觉检查并确认效果良好。
- macOS 正文链接 hover 的瞬时卡顿已修复并经用户验证。根因是所有 `HtmlChunkCard` 监听共享 `_hoveredUrl`，任意链接进入/离开都会让全篇 HTML 缓存失效并重新解析。当前取消动态下划线和 chunk 监听，只保留主题色、手型光标、点击及底部 URL 预览。
- 详情页补抓普通全文或 Inbox 正文成功后，现已和后台 Readability 共用 `AutoAiQueueCoordinator.onArticleContentAvailable()`：只给最新状态仍为未读的文章排摘要，并按订阅源开关排翻译。打开页面期间后台译文完成后，`ArticleController` 会解析并刷新当前译文，不再要求切走后重开。已读取消策略、已开始请求和手动 AI 操作保持原语义。
- macOS 阅读快捷键已扩展：`B` 打开原文，`Shift+B` 确保已读并打开（垃圾拦截为移除并打开），`Cmd+1/2/0` 分别导航到全部文章、垃圾拦截和静默订阅源。无选择时 `Right/Left` 分别选择当前列表首篇/末篇；应用级快捷键注册器先于默认焦点移动处理，`Esc` 后使用空详情中立焦点节点，避免侧边栏“全部文章”残留灰色焦点高亮。设置页说明和回归测试已同步。
- macOS 原生菜单已从 Flutter 模板收敛为 `Auto Folo / 编辑 / 显示 / 文章 / 窗口 / 帮助`。业务 Undo/Redo 使用 50 项双栈，`Cmd+Z`/`Shift+Cmd+Z` 可连续处理标为已读、垃圾拦截保留/移除以及静默文章整批标为已读；输入框保留文本 Undo/Redo。业务栈在整个应用进程中保持一致，不因页面或 scope 切换而清空，也不跨重启持久化。单篇菜单显示动作和截断标题，批量菜单显示动作和篇数。`Cmd+W` 已恢复为与红色按钮一致的隐藏窗口行为。
- macOS 静默订阅源汇总视图新增批量导出模式：默认空选，卡片角标独立勾选且卡片本体仍可阅读；支持复制/保存 Markdown 及各自的“并标为已读”组合动作。单篇和批量 Markdown 统一由 `ArticleMarkdownExportService` 生成，不加批次总标题，按列表顺序以 `---` 分隔；正文未缓存时只输出已有元数据和明确提示，不触发网络抓取。组合动作导出成功后才提交读状态；远端分块与补偿结果逐篇追踪，本地和 Undo/Redo 历史只反映最终确认改变的子集。当前代码和自动化测试、macOS Debug 构建已通过，尚待用户运行做视觉与真实剪贴板/文件流程确认。
- Android 设计迁移五个阶段已合入主线：主时间线与订阅源详情共享圆形文章范围按钮和玻璃选择面板，最近阅读移入订阅源页，文章已读/目录改为移动端玻璃控件，设置/任务中心和次级页面完成移动端适配。纯 Flutter 玻璃组件跨平台复用，AppKit 原生能力继续隔离。
- Android Inbox 展开出现灰色块的根因不是页面动画，而是静默订阅源路径未在 `Obx` 中读取 Rx；`unreadFor()` 已调整读取顺序。用户在 Debug 中确认红色 GetX 错误和 Release 灰色块均消失，原有页面淡入淡出和分类展开动画已保留。
- 用户已视觉验证 Android 主时间线、订阅源详情、文章目录/已读按钮、底部导航、设置页、任务中心、下拉选择面板和次级页面。底栏最终采用目标设备视觉确认的 `12px` 边距、`56px` 高、`28px` 连续半径；普通移动端 AppBar 收敛为共享 `48px` 工具栏。当前可以把本轮描述为 Android 设计迁移完成，但仍需在不同系统导航模式和屏幕圆角设备上复查底栏兼容性。
- 合并时又把 Android 文章范围改为圆形按钮 + 玻璃选择面板，并把普通/垃圾拦截卡片字级统一为 `14/12px`。横滑圆角已经在本轮真机 Debug 中完成最终视觉确认；前两项继续按验证记录维护，不再把圆角列为开放项。

仍需持续观察的少量项目集中记录在[验证记录](verification.md)，不要再把完整验证清单追加到当前事实页。

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
