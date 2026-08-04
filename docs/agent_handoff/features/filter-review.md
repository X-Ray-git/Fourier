# 垃圾拦截与审核

垃圾拦截/审核页用于审核被 AI 拒绝的文章。

关键预期：

- 用户可以审核被拒绝文章。
- Android 将垃圾拦截作为四项底部主导航中的一级入口；常驻实例使用嵌入模式，不创建第二层 AppBar。独立路由继续可用，但时间线顶部不再保留重复的“AI 智能过滤”入口卡片。
- Android 时间线角标与垃圾拦截角标允许重叠：被 AI 拒绝的未读文章仍按既有逻辑留在普通时间线，同时进入待审核列表。时间线数字使用非静默未读总数，垃圾拦截数字使用 `isRejectedByAi && !isRead`；这不是互斥队列。
- 移除/通过条目后，应跳转到下一篇合适文章，并在 macOS 上保持焦点行为可用。
- Header 和面板样式应遵循当前 macOS 轻量面板语言。
- 文章卡片/审核行应保持和时间线卡片一致的交互反馈。
- 垃圾拦截页不应成为一套完全分叉的时间线实现；能和普通时间线共享的时间线级操作、按钮和文章动作菜单应尽量共享。

状态字段：

- `ArticleModel.isRejectedByAi`
- `ArticleModel.filterReason`
- `ArticleModel.filterReviewed`
- `ArticleModel.filteredAt`
- `ArticleModel.userAction`：用户动作标记，事后统计误分类用。取值 `'k'`（拦截页保留）、`'m'`（拦截页确认拒绝）、`'n_keep'`（拦截页误分类：保留+已读）、`'n_spam'`（常规页误分类：拒绝+已读）、null（未表态）。同一文章多次动作时 latest wins。
- 统计仅覆盖当前 `articleDb` 中仍保留的近期文章，不是永久操作历史。它受 5000 篇缓存上限和账号数据清理约束；这是用户确认的产品边界，不要为此另建长期日志或把记录加入设置备份。

本地数据库 merge 时不要丢失这些字段。

误分类（`N` / 右上角旗帜按钮）：

- 拦截页语义：当前文章应该保留，但用户已读完 → 保留 + 标为已读，写 `userAction='n_keep'`；复用 `_keep` 的 pending/退场/后继选中机制。
- 常规时间线语义：标为已读且应放进垃圾拦截 → 拒绝 + 标为已读，写 `userAction='n_spam'`；复用 `M` 的列表离场/后继选择路径。已读或已在拦截中的文章按钮置灰。
- 两类误分类都是一条原子 UndoAction，撤销/重做同时恢复分类与已读状态。
- 所有过滤动作的撤销路径（`filterKeep`/`filterReject`/`misclassifyKeep`/`misclassifySpam`）都使用 `upsertOne(forceReplace: true)` 整条还原动作前快照；不能用普通 merge，`item.userAction ?? existing?.userAction` 会把动作标记留在已回滚的文章上。
- `LocalArticleDbService.setReadState` 重建文章时必须保留 `userAction`（及全部过滤字段），否则标已读/未读会把标记覆盖成 null。
- macOS 拦截页的 `K/M/N` 由页面级 `HardwareKeyboard` 处理器执行（`_handleHardwareKeyEvent`），不依赖详情面板是否挂载；`ArticlePageView` 在 `isReviewContext` 下对 `M/N` 只消费按键不执行回调，避免与页面级处理器双触发。`HardwareKeyboard` 会调用全部注册处理器，不能依赖返回 true 短路。
- 页面级 `K/M/N` 必须在 Alt/Control/Command 按下时放行，尤其不能让 `Cmd+M`、`Cmd+N` 同时触发业务操作。统一使用 `MacArticleShortcutService.hasNonShiftModifier` 判断。
- 统计口径：FP = `'k'` + `'n_keep'`，FN = `'n_spam'`，`'m'` 是弱信号（可能同意也可能懒得分辨），null 无信号。
- 保留动作（`K`、`'n_keep'`）不再清空 `filterReason`/`filteredAt`，供事后按 AI 原判理由聚合 FP；UI 已按 `isRejectedByAi` 隐藏显示，不受影响。
- `upsertMany` 合并使用 `item.userAction ?? existing?.userAction`，网络同步数据不得覆盖本地动作标记；旧版本二进制重写文章时会丢弃该字段（不可修复），统计语义为"只有真的没有假的"。
- 所有从现有 `ArticleModel` 重建新实例的路径都必须复制 `userAction`。数据库 merge 能保护落盘值，但内存模型丢字段会让后续 Undo 快照无法精确恢复上一个动作。
- 时间线 `N` 复用已读退场的帧边界通知；`applyMisclassify` 不得在 `applyReadLocally(...deferTimelineVisualUpdate: true)` 后额外立即调用 `ArticleStateNotifier.tick`，否则会绕过动画保护。

与普通时间线的复用边界：

- 同步按钮使用 `AppGlassSyncButton`，避免时间线和垃圾拦截页各维护一套旋转、tooltip、hover 和玻璃样式。
- 右键/长按文章 AI 操作使用 `ArticleActionsMenu`，普通时间线卡片和垃圾拦截审核行共享翻译、删除翻译、生成摘要、删除摘要等入口。
- macOS 垃圾拦截左栏审核行也应复用 `ArticleCardChrome` 的基础卡片外壳样式，保持和普通时间线卡片一致的轻填充、选中态和无普通边框。不要再在 `_MacReviewRow` 里单独手写透明/选中背景。
- macOS `_MacReviewRow` 保留拒绝理由和摘要等独立结构，但订阅源行右侧的预计内容高度必须复用 `ArticleLengthLabel`；Android 审核卡片通过共享 `ArticleCard` 自动获得同一标签。不要复制估算或格式化规则。
- 垃圾拦截页同步时可以复用 `TimelineController.loadFeedsThenArticles()`，然后刷新本页本地审核列表。
- 垃圾拦截页仍保留自己的审核业务布局，例如保留/移除、拒绝理由、审核状态和下一篇选择逻辑。
- 已读/未读切换不需要同步到垃圾拦截页；这是普通时间线的阅读状态筛选，不是审核页核心任务。
- macOS 不再为每张审核卡片显示常驻“保留/移除”按钮。触控板双指右滑表示保留，左滑表示移除；鼠标按住拖动不能触发审核。`K/M` 快捷键继续保留，右键菜单提供“保留”和危险色“移除”作为无触控板时的后备入口。
- macOS 横滑不能直接复用 `Dismissible`，否则会和现有 `ImplicitlyAnimatedList` 的纵向退出重复。当前由 `_MacTrackpadReviewSwipe` 负责横向跟手、阈值判断和横向离场，业务状态变化后再由列表完成纵向收缩。
- macOS 操作背景只允许出现在卡片实际让出的区域。由于卡片半透明，不能把背景铺满后依赖卡片遮挡；当前用“固定卡片圆角路径减去横移后卡片圆角路径”的差集裁剪，避免背景透过卡片、圆角旁出现直角裁剪线或外边距空带。颜色透明度随滑动距离增加。
- Android 继续使用 `Dismissible` 处理手势、阈值和卡片位移，但列表外边距必须位于滑动组件外部，内部 `ArticleCard` 使用零外边距，使操作背景与真实卡片同尺寸。`ArticleCard.outerPadding` 是可选覆盖项，其他入口默认仍使用 `ArticleCardChrome.outerPadding`。
- Android 的操作背景不能传给 `Dismissible.background/secondaryBackground`。Flutter 会在该槽位外层追加矩形 `_DismissibleClipper`，只保留已让出的矩形宽度；即使内部使用圆角差集，移动卡片一侧伸入该矩形之外的圆弧仍会被截断，真机表现为彩色背景与卡片交界处的直角。
- 当前 Android 结构是固定圆角 `ClipRRect > Stack`：底层 `Positioned.fill` 根据 `_offset` 选择保留/移除背景，并用 `_ReviewSwipeRevealClipper` 计算“固定圆角卡片减去平移后圆角卡片”的差集；上层无 background 的 `Dismissible` 只移动 `ArticleCard`。固定外边界、背景差集和卡片都取 `ArticleCardChrome.radius`。不能只套外层 `ClipRRect`，也不能把背景放回 `Dismissible` 的原生背景槽位。
- 横滑完成后立即 `Command-Z` 时，不得在旧卡片退出动画结束前把相同 entry id 重新插入列表。当前先恢复数据库状态并延迟 UI 重插，等 `onRemoveEnd` 后再重新加入并选中，否则恢复项会被旧退出生命周期吞掉。
- `M/K`、右键保留/移除和触控板提交在 macOS 上都必须先登记 `_pendingReviewActionIds`。`AutoFilterWorker.unReject()` 与 `TimelineController.markAsReadLocal()` 会同步触发 `ArticleStateNotifier`；如果页面立即响应该通知，列表项会在显式删除前先消失一次，移除动画会随机压缩或瞬移。
- pending action 期间，单篇 `_syncArticleFromDb()` 和整表 `_loadArticles()` 都不能提前改写审核列表。业务持久化完成后，页面在 `SchedulerBinding.endOfFrame` 边界只执行一次 `_removeReviewedArticle()`，然后再处理被延后的 reload。
- 这不是延长动画或增加滤波：列表仍使用原来的 180ms 移除曲线，只是把同步存储/状态广播与动画起点隔开。

颜色语义：

- 拒绝理由使用 amber/orange，表达 AI 判定依据和警示感。
- 摘要完成态使用灰蓝 `#64748B`，表达辅助阅读信息，不再使用绿色，避免和“保留”动作混淆。
- 保留按钮使用较沉稳的 emerald `#059669`，不要回到偏亮的 `#10B981`。
- 移除按钮继续使用主题 `cs.error`，保持明确破坏性动作语义。

不要回退：

- 不要再在 `ArticleCard` 和垃圾拦截审核行里分别复制翻译/摘要菜单逻辑。
- 不要把垃圾拦截页改成完全通用的 ArticleCard 列表而丢失审核操作。
- 如果未来普通时间线新增文章级上下文菜单动作，优先扩展 `ArticleActionsMenu`，再确认垃圾拦截页是否也应继承。
- 不要恢复每张 macOS 审核卡片上的常驻保留/移除按钮；用户已确认横滑方案可以解决按钮缺少对齐对象的问题。
- 不要让鼠标拖拽触发审核横滑，也不要用第二套纵向收缩动画替换现有列表退出生命周期。
