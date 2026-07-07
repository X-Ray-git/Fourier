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
- 垃圾拦截页同步时可以复用 `TimelineController.loadFeedsThenArticles()`，然后刷新本页本地审核列表。
- 垃圾拦截页仍保留自己的审核业务布局，例如保留/移除、拒绝理由、审核状态和下一篇选择逻辑。
- 已读/未读切换不需要同步到垃圾拦截页；这是普通时间线的阅读状态筛选，不是审核页核心任务。

不要回退：

- 不要再在 `ArticleCard` 和垃圾拦截审核行里分别复制翻译/摘要菜单逻辑。
- 不要把垃圾拦截页改成完全通用的 ArticleCard 列表而丢失审核操作。
- 如果未来普通时间线新增文章级上下文菜单动作，优先扩展 `ArticleActionsMenu`，再确认垃圾拦截页是否也应继承。
