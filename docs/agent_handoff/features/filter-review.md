# 垃圾拦截与审核

垃圾拦截/审核页用于审核被 AI 拒绝的文章。

关键预期：

- 用户可以审核被拒绝文章。
- 移除/通过条目后，应跳转到下一篇合适文章，并在 macOS 上保持焦点行为可用。
- Header 和面板样式应遵循当前 macOS 轻量面板语言。
- 文章卡片/审核行应保持和时间线卡片一致的交互反馈。

状态字段：

- `ArticleModel.isRejectedByAi`
- `ArticleModel.filterReason`
- `ArticleModel.filterReviewed`
- `ArticleModel.filteredAt`

本地数据库 merge 时不要丢失这些字段。
