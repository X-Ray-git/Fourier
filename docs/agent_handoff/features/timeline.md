# 时间线

相关文件：

- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/widgets/article_card.dart`
- `lib/common/widgets/article_card_chrome.dart`
- `lib/common/widgets/app_glass_sync_button.dart`
- `lib/pages/widgets/article_actions_menu.dart`
- `lib/common/widgets/mac_split_article_list_coordinator.dart`

当前行为：

- 模式：未读、全部、已读。
- macOS 中间 header 快速切换只暴露未读/全部，并使用紧凑二态开关，而不是完整 segment。
- macOS 中间栏 header 不显示底部分隔线；当前视觉依赖卡片间距和轻填充区分层级。这个规则包括主时间线、订阅源详情、最近阅读和垃圾拦截，不要只在某个页面单独处理。
- macOS 文章卡片普通态使用极轻中性色填充，统一由 `ArticleCardChrome` 控制；当前深色模式 alpha 为 `0.018`，浅色模式为 `0.012`。时间线、最近阅读和垃圾拦截不要分别覆盖该值。
- macOS 普通文章卡片与垃圾拦截审核卡片的标题字号统一为 `14`，由 `ArticleCardChrome.titleFontSize` 提供；普通卡片辅助正文在 macOS 使用 `12`，由 `ArticleCardChrome.bodyFontSize` 提供。Android 保持原字号，不要在两个 macOS 卡片实现中分别硬编码标题字号。
- macOS 主时间线和垃圾拦截列表共用 `MacArticleListChrome` 的两层下边距：`viewportPadding` 是滚动过程中始终存在的窗口下边界，`contentPadding` 是滚到列表末尾后出现的内容留白。不要只增加 `ListView.padding.bottom` 来替代视口边界，也不要在两个页面分别硬编码。
- macOS 主时间线、垃圾拦截、最近阅读和订阅源详情通过 `MacHeaderPane` 共享固定 header/body 几何。内容和 scrollbar 自然从 header 下方开始；thumb 宽度及右侧 margin 继续由 `MacGlassScrollbarStyle.articlePaneTheme` 提供（`8px`、`1px`），`MacArticleListChrome.contentPadding` 另保留 `2px` 右侧内容间隔。
- macOS 订阅源详情页的 header 筛选也应跟随这个二态开关语言；不要重新引入 `仅已读` 入口。
- 已读模式/页面仍在其他入口存在，不应删除。
- 过滤支持选中订阅源、分类和静默订阅源。
- 本地文章库支撑时间线状态。
- 已读/未读变化会更新本地状态并通知其他视图。
- 时间线和最近阅读列表合并本地已读状态时，使用 `LocalArticleDbService.readOverrideOf(entryId)`，没有覆盖时保留 `ArticleModel.isRead`。该规则同时支持本地标为已读和恢复未读，不要退回到只处理 `readStatus == true` 的旧逻辑。
- 本地标为已读后的 `readStatus == true` 是跨请求竞态保护，不能在 mark-read HTTP 成功时立即删除。未读请求可能比 mark-read 更早发出并返回旧快照；只在后续成功未读快照明确不再包含该文章时，才清除覆盖并以本地数据库中的已读状态继续。主时间线和订阅源详情必须遵循同一规则。
- 垃圾拦截/审核这类列表如果语义要求稳定追加，新文章应稳定附加。

macOS 分栏选择与移除协调：

- `MacSplitArticleListCoordinator` 统一承载分栏文章列表中的稳定 item key、删除前后继项计算、删除期间选择保持、`onRemoveEnd` 后详情切换、相对导航和 reveal 回调。页面继续负责已读、审核、数据库和网络等业务动作，不要把这些业务塞进协调器。
- 页面必须在任何数据库写入、`ArticleStateNotifier.tick()` 或列表删除之前调用 `beginRemoval(entryId)`。垃圾拦截曾在动画开始前由 `_pruneInvalidSelection()` 立即切换右侧详情，首次正文构建因此抢占移除动画帧；协调器通过 `reconcileSelection()` 在退出期间保留旧详情，直到真实 `onRemoveEnd`。
- 垃圾拦截已接入协调器，`M`、保留、移除共用同一删除生命周期；移动端仍保持原业务路径。
- 主时间线的 `M` 和双击也已接入协调器：未读卡片退出期间保留当前详情，真实 `onRemoveEnd` 后才切换并 reveal 后继文章。动画期间的 `Command-Z` 通过 `restoreSelection()` 取消待切换目标，避免恢复后的文章再次被选走。
- 最近阅读尚未接入。后续迁移时需要先确认恢复未读后的选择语义。不要为了共享而把三个页面强行做成同一个大 Widget。

排序：

- `TimelineSortMode.newest`：默认，最新优先。
- `TimelineSortMode.longest`：估算长文优先。
- `TimelineSortMode.shortest`：估算短文优先。
- 排序只作用于当前本地/已加载文章集合，不是远端全历史。
- 长度估算使用 `ArticleLengthEstimator`、规范化 HTML、解析后的 chunk 和缓存签名。
- 排序刻意保持本地化。UI 文案不能让用户误以为是远端/全历史排序。

性能决策：

- macOS 时间线列表使用 `ImplicitlyAnimatedList`，但只应把动画用于普通标记已读/恢复未读带来的局部插入/移除。
- 批量变化必须无动画同步，不应做大规模 diff 动画。批量变化包括：切换未读/全部等模式、切换订阅源/分类/静默范围、切换排序、本地库批量回填、同步/加载更多，以及单篇元数据确实改变列表成员或排序的情况。
- `TimelineController.timelineListResetVersion` 是这个边界的核心：批量变化递增它，并作为 `ImplicitlyAnimatedList.batchUpdateVersion` 传入。组件在同一个 `AnimatedList` 和 `ScrollController` 上以零时长协调项目，不再把 version 放进 key 重建整列，因此不会仅因刷新或元数据通知把滚动位置重置为顶部。
- 列表外层 key 只包含 selected mode 和 scope key；模式/范围切换仍可建立新的列表语义。`markAsReadLocal` / `markAsUnreadLocal` 不递增 batch version，所以普通读状态局部动画保留。
- 单篇数据库通知先比较过滤后的 entry id 顺序。标题、正文、摘要等非结构元数据更新不触发 batch version；只有列表成员或顺序确实改变时才做零时长同步。不要恢复成“任何非已读字段变化都重建整列”的旧判断。
- `TimelineController.setTimelineScope()` 负责批量更新 `isSilentSelected`、`selectedFeedId`、`selectedCategory`，避免侧边栏一次点击触发多次 `_applyFilter()`。
- 不要重新在侧边栏或文章页里直接连续设置 `selectedFeedId.value` / `selectedCategory.value` / `isSilentSelected.value`；这会恢复“多次过滤 + 多次重建”的卡顿。
- 普通标记已读时，单项移除动画仍保留。
- 首次长文/短文排序可能需要一次估算；用户验证时未观察到不可接受的成本。
- 避免批量重排或模式切换触发大型列表动画；这曾经让文章 loading spinner 等无关动画也卡住。

状态与交互：

- 卡片右键菜单操作如果影响当前选中文章，必须立即刷新可见详情状态。
- backing service 记录被删除后，不要回退到过期 controller 字段。
- 即使同步在按钮订阅 controller 前已经开始，同步按钮也必须开始旋转。
- macOS 刷新/排序/操作按钮在用户明确要求时，应对齐文章卡片边界。
- macOS 未读/全部切换控件是二态筛选开关：只显示当前状态文字，另一侧保留很窄空隙，滑块在两端切换。用户认为完整 segment 占据太多 header 空间，所以不要回退到两个等宽文字 segment。
- 当前视觉实验后的精确尺寸是轨道 `58`、滑块 `42`、外层 padding `0`。空余轨道因此收窄，但仍保留横向切换动势；最外层静态 rim 宽 `1px`，局部 opacity multiplier 为 `1.0`。继续缩窄会让中文文字贴边或削弱切换动势。
- 该 switch 视觉上应接近右侧圆形玻璃工具按钮，但语义上不是主操作按钮。滑块使用不含主色 tint 的中性玻璃，文字使用自适应 `onSurface`；深色模式使用按钮专属的较低 glass tint。不要把滑块或文字重新改成橙色。
- switch 外层轨道保留清晰的玻璃边界，用于和周围控件形成同一组控制语言；当前局部 `staticBorderWidth` 为 `1`、`staticBorderOpacity` 为 `1.0`，不要回退到视觉实验前过淡的 rim。
- macOS 中间时间线处于具体订阅源筛选时，header 只保留时间线级操作，例如排序和同步。
- 不要在该 header 重复放置订阅源级设置按钮，例如自动拉取全文、自动翻译、静默等；这些入口属于左侧侧边栏订阅源项。
- 该 header 也不显示“清除筛选”。用户通过左侧侧边栏切换范围或回到全部文章。
- 这个取舍来自一次拥挤问题：进入某个分类下的具体订阅源后，刷新、清除筛选、拉取全文、自动翻译等按钮挤在同一行，视觉负担过重且功能重复。
- macOS 时间线 header 的横向间距已经按文章卡片右边界校准：`未读/全部`→排序 `8px`、排序→同步 `8px`、同步→中间栏右边界 `10px`。文章卡片右边缘到时间线右边界也保持 `10px`；文章详情右上角三个按钮的既有间距不随这里联动。
- 同步按钮样式和旋转逻辑集中在 `AppGlassSyncButton`。普通时间线通过 `_MacSyncButton` 订阅 `TimelineController.isSyncing`，垃圾拦截页也复用同一个按钮。
- 文章卡片的长按/右键 AI 操作集中在 `ArticleActionsMenu`。不要再把翻译/摘要菜单逻辑塞回 `article_card.dart`。
- 文章列表卡片的基础“外壳”样式集中在 `ArticleCardChrome`：macOS 普通态使用极高透明度中性色填充，不使用普通边框；选中态仍使用主色背景和边框。外边距、内部 padding 和圆角也从这里取值，不要在普通时间线、最近阅读、垃圾拦截审核行之间复制常量。
- 垃圾拦截审核行有保留/移除按钮、拒绝理由和摘要块，所以不强行复用完整 `ArticleCard`；但卡片外壳必须复用 `ArticleCardChrome`，避免之后调整卡片密度时漏改。
- 最近阅读页里的文章本来都属于“已读语境”，标题不要再因 `isRead` 降低字重；只保留已读颜色淡化即可，否则和其他页面的标题观感不统一。
- 不要在文章卡片上使用重型玻璃、BackdropFilter、渐变边框或阴影。用户尝试过细线边框后认为不好看，最终取舍是轻填充 + 较大的卡片间距。
- macOS 空态占位符应在左右分栏中对齐。左侧列表有 AppBar/header 时，右侧详情空态使用 `MacSplitDetailEmptyPlaceholder` 预留对应顶部 inset；不要用临时 `Padding(top: 64)` 推动左侧空态。
- 订阅源筛选或无文章状态下，macOS 空态应使用安静的图标占位，不要回退到移动端旧文案如“一切就绪”“没有阅读文章”“强制同步”。

当前文章保持可见：

- macOS 上切换文章时，如果目标卡片已经构建，继续使用 `ScrollUtils.ensureVisible` 做短距离校正。
- 如果目标卡片因为列表虚拟化尚未构建，先根据当前已构建卡片和估算 item 高度 `jumpTo` 到附近，再做短距离 `ensureVisible` 校正。
- 不要用长距离 `animateTo` 粗定位；它会和右侧文章切换同时竞争 UI isolate，用户曾观察到明显掉帧。

标为已读的动画时序：

- 主时间线在未读模式下处理 `M` 或双击时，先登记后继文章，但保持当前详情；卡片真实完成退出后再切换详情并把后继卡片留在可见区域。非移除模式继续使用普通相对选择。
- 本地数据库写入是同步重工作；不能在 `addPostFrameCallback` 中同时做持久化和列表变更。post-frame callback 仍属于当前帧，实测会让 180ms 动画只剩约 30–55ms 可见时间。
- `UndoService.markAsRead(... deferTimelineVisualUpdate: true)` 供 macOS 双击路径使用；主时间线 `M` 在未读模式下也直接要求 `TimelineController.markAsReadLocal(... deferVisualUpdateToFrameBoundary: true, deferArticleStateNotification: true)`。控制器先持久化，再等待新的 `endOfFrame` 才更新当前可见列表；其他调用方默认行为不变。
- 单篇已读不能在动画首帧调用完整 `_applyFilter()`。日志曾确认本地模型约有 `4799` 篇文章，全量扫描、应用角标/计数并通知所有订阅者会占用约 73–90ms。当前移除路径只从可见 `articles` 中增量删除对应项，离场文章的 `allArticles`、角标、计数和其他页面状态在动画完成后统一维护。
- `ArticleStateNotifier.tick()` 会同步扇出到最近阅读全库读取/排序、订阅源未读计数、订阅源详情和垃圾拦截等页面。会移除卡片时，跨页面通知由 `completeDeferredReadTransition(entryId)` 在真实 `onRemoveEnd` 后再跨一个 `endOfFrame` 发出，避免其他页面的同步工作吞掉 180ms 退场动画。若生命周期异常没有回调，控制器用 1 秒 fallback 保证通知最终发生。
- 延后的视觉更新和跨页面通知分别带一次性 token；在执行前恢复未读会同时取消它们，避免极快 `Command-Z` 被迟到的“标为已读”更新覆盖。
- 退场期间不要更新当前选中文章对象，也不要为单篇已读重复写入 `loadingState = Success(...)` 或额外执行 `allArticles.refresh()`；这些更新会无意义地重建右侧详情或放大通知成本。
- 如果当前是未读模式并会删除卡片，原文浏览器必须等列表 `onRemoveEnd` 后再跨一帧打开。固定 `200ms` 延迟曾在动画中途抢走前台，视觉上看起来像没有动画。
- 不要把这个特殊时序全局套到文章页按钮或 Android；默认参数刻意保持原行为。
- 最终诊断结果：在约 `4799` 篇本地文章的环境中，增量可视更新耗时约 164–671 微秒；两次 `M` 和四次双击都完整经过动画 bucket `4→3→2→1→0`，双击在 141–166ms 内识别，且移除期间没有列表 reset。用户随后完成视觉确认。
