# 翻译与摘要

相关服务：

- `lib/services/translation_service.dart`
- `lib/services/summary_service.dart`
- `lib/services/llm_config.dart`

存储：

- 翻译记录在 `GStorage.translations`。
- 摘要记录在 `GStorage.summaries`。

LLM 默认取向：

- 翻译：flash、低 temperature、大输出。
- 摘要：pro、按配置启用 thinking、紧凑输出。
- 过滤：独立配置。

重试：

- 翻译和摘要使用由 `auto_retry_max_count` 控制的原地重试。
- 重试期间 pending 状态应可见。

UI 注意点：

- macOS 翻译/摘要工具栏按钮是普通胶囊控件，不是重型 Liquid Glass。
- 灰色非激活按钮 hover 时不应闪烁；hover 只轻微改变边框。
- 从卡片右键菜单删除摘要后，文章详情必须立即更新。`SummaryService` 记录删除后，不要回退到过期 controller summary text。
- 卡片右键操作会直接调用 service 方法；确保跨页面 UI 观察 service 状态或 notifier 状态。
- 文章列表里的长按/右键 AI 菜单由 `lib/pages/widgets/article_actions_menu.dart` 统一维护。
- 普通时间线卡片和垃圾拦截审核行都应通过 `ArticleActionsMenu` 提供翻译、删除翻译、生成摘要、删除摘要。这样新增或修复文章级 AI 动作时不需要同时改两套页面。
- `ArticleActionsMenu` 只封装文章级动作和反馈，不拥有文章详情状态；删除翻译/摘要后的可见刷新仍依赖 service/notifier 和页面已有观察链路。
