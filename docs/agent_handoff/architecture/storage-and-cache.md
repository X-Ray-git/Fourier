# 存储与缓存

Hive box 在 `lib/utils/storage.dart` 中初始化。

重要 box：

- `setting`：凭据和用户设置。
- `articleDb`：本地文章库。
- `localCache`：通用本地缓存。
- `readStatus`：本地已读覆盖状态。
- `translations`：翻译记录。
- `summaries`：摘要记录。

关键规则：

- 在当前用法下，Hive 写入后足以立即读取。
- `readStatus` 只是本地已读/未读覆盖状态，不是文章真实已读状态的唯一来源。同步成功或本地库刷新后，覆盖状态可能被清掉。
- 读取文章已读状态时优先使用 `LocalArticleDbService.readOverrideOf(entryId)`；如果没有本地覆盖，再回退到 `ArticleModel.isRead`。不要直接把 `GStorage.readStatus.get(entryId, defaultValue: false)` 当作最终状态，否则最近阅读等已读文章会被错误显示为未读。
- `ArticleModel.isRejectedByAi`、`filterReason`、`filterReviewed`、`filteredAt` 在 upsert/merge 时不能丢失。
- 不要提交真实 API 响应、文章 HTML、token 或调试脚本。使用已忽略的 `scratch/`。
- 设置导入/导出刻意使用白名单；新增需要跨设备迁移的持久设置时，要加入 `SettingsBackupService`。

近期设置 key：

- `appearance_mode`：`system`、`light` 或 `dark`。
- `article_content_max_width`：文章正文/图片宽度上限。
- `macos_max_fling_velocity`：macOS fling 上限。
- LLM 配置 key 使用 `llm_translate_`、`llm_summary_`、`llm_filter_` 前缀。
