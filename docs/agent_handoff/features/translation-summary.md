# 翻译与摘要

自动任务只在入队时检查文章的最新已读状态。已经是已读的文章不进入自动翻译和摘要队列；以未读状态入队后，后续即使标记为已读也不追踪取消，任务照常完成。这是经长期使用后确认的取舍：旧取消机制只能命中尚未被高并发 Worker 取入批次的少量任务，收益不足以支撑额外状态分支。手动翻译/摘要和垃圾拦截判定均不受影响。

新正文可用后的自动 AI 流转由 `AutoAiQueueCoordinator.onArticleContentAvailable()` 统一负责。后台 Readability、文章详情页直接补抓全文和 Inbox 详情补正文都必须在成功持久化正文后调用该入口；入口读取数据库中的最新已读状态，只给当时仍未读的文章排摘要，并按订阅源自动翻译开关排翻译。不要让详情页只更新显示和数据库而遗漏 AI 队列，也不要在 `setReadState()` 中重新加入队列取消副作用。

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
- 过滤：独立配置；仓库默认只做保守、通用的内容质量审核，不表达特定用户的主题或来源偏好。用户保存/导入的自定义过滤 Prompt 优先于默认值。

重试：

- 翻译和摘要使用由 `auto_retry_max_count` 控制的原地重试。
- 重试期间 pending 状态应可见。

UI 注意点：

- macOS 翻译/摘要工具栏按钮是普通胶囊控件，不是重型 Liquid Glass。
- 灰色非激活按钮 hover 时不应闪烁；hover 只轻微改变边框。
- 从卡片右键菜单删除摘要后，文章详情必须立即更新。`SummaryService` 记录删除后，不要回退到过期 controller summary text。
- 卡片右键操作会直接调用 service 方法；确保跨页面 UI 观察 service 状态或 notifier 状态。
- 文章在详情页打开后，后台译文仍可能稍后完成。`ArticleController` 监听 `TranslationService.recordsVersion`，只为当前文章解析最终译文并刷新 `translatedChunks`；删除译文也必须清理详情页旧状态。不要重新把是否已有译文只固定在控制器初始化时判断。
- 文章列表里的长按/右键 AI 菜单由 `lib/pages/widgets/article_actions_menu.dart` 统一维护。
- 普通时间线卡片和垃圾拦截审核行都应通过 `ArticleActionsMenu` 提供翻译、删除翻译、生成摘要、删除摘要。这样新增或修复文章级 AI 动作时不需要同时改两套页面。
- `ArticleActionsMenu` 只封装文章级动作和反馈，不拥有文章详情状态；删除翻译/摘要后的可见刷新仍依赖 service/notifier 和页面已有观察链路。
