# 垃圾拦截与审核

垃圾拦截/审核页用于审核被 AI 拒绝的文章。

关键预期：

- 用户可以审核被拒绝文章。
- 移除/通过条目后，应跳转到下一篇合适文章，并在 macOS 上保持焦点行为可用。
- Header 和面板样式应遵循当前 macOS 轻量面板语言。
- 文章卡片/审核行应保持和时间线卡片一致的交互反馈。
- 垃圾拦截页不应成为一套完全分叉的时间线实现；能和普通时间线共享的时间线级操作、按钮和文章动作菜单应尽量共享。

状态字段：

- `ArticleModel.isRejectedByAi`
- `ArticleModel.filterReason`
- `ArticleModel.filterReviewed`
- `ArticleModel.filteredAt`

本地数据库 merge 时不要丢失这些字段。

与普通时间线的复用边界：

- 同步按钮使用 `AppGlassSyncButton`，避免时间线和垃圾拦截页各维护一套旋转、tooltip、hover 和玻璃样式。
- 右键/长按文章 AI 操作使用 `ArticleActionsMenu`，普通时间线卡片和垃圾拦截审核行共享翻译、删除翻译、生成摘要、删除摘要等入口。
- macOS 垃圾拦截左栏审核行也应复用 `ArticleCardChrome` 的基础卡片外壳样式，保持和普通时间线卡片一致的轻填充、选中态和无普通边框。不要再在 `_MacReviewRow` 里单独手写透明/选中背景。
- 垃圾拦截页同步时可以复用 `TimelineController.loadFeedsThenArticles()`，然后刷新本页本地审核列表。
- 垃圾拦截页仍保留自己的审核业务布局，例如保留/移除、拒绝理由、审核状态和下一篇选择逻辑。
- 已读/未读切换不需要同步到垃圾拦截页；这是普通时间线的阅读状态筛选，不是审核页核心任务。
- macOS 不再为每张审核卡片显示常驻“保留/移除”按钮。触控板双指右滑表示保留，左滑表示移除；鼠标按住拖动不能触发审核。`K/M` 快捷键继续保留，右键菜单提供“保留”和危险色“移除”作为无触控板时的后备入口。
- macOS 横滑不能直接复用 `Dismissible`，否则会和现有 `ImplicitlyAnimatedList` 的纵向退出重复。当前由 `_MacTrackpadReviewSwipe` 负责横向跟手、阈值判断和横向离场，业务状态变化后再由列表完成纵向收缩。
- macOS 操作背景只允许出现在卡片实际让出的区域。由于卡片半透明，不能把背景铺满后依赖卡片遮挡；当前用“固定卡片圆角路径减去横移后卡片圆角路径”的差集裁剪，避免背景透过卡片、圆角旁出现直角裁剪线或外边距空带。颜色透明度随滑动距离增加。
- Android 继续使用 `Dismissible`，但列表外边距必须位于 `Dismissible` 外部，滑动组件内部的 `ArticleCard` 使用零外边距，使操作背景与真实圆角卡片同尺寸。`ArticleCard.outerPadding` 是可选覆盖项，其他入口默认仍使用 `ArticleCardChrome.outerPadding`。
- Android 的操作背景也必须复用 `_ReviewSwipeRevealClipper`：根据 `DismissUpdateDetails.progress` 还原当前横移距离，用“原卡片圆角路径减去移动后卡片圆角路径”的差集只绘制真实让出的区域。仅给整块背景套 `ClipRRect` 不能得到和 macOS 一致的圆角遮挡关系，会在移动卡片圆角旁露出不应出现的背景。
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
