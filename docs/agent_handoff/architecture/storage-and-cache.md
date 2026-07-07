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
- `ArticleModel.isRejectedByAi`、`filterReason`、`filterReviewed`、`filteredAt` 在 upsert/merge 时不能丢失。
- 不要提交真实 API 响应、文章 HTML、token 或调试脚本。使用已忽略的 `scratch/`。
- 设置导入/导出刻意使用白名单；新增需要跨设备迁移的持久设置时，要加入 `SettingsBackupService`。

近期设置 key：

- `appearance_mode`：`system`、`light` 或 `dark`。
- `article_content_max_width`：文章正文/图片宽度上限。
- `macos_max_fling_velocity`：macOS fling 上限。
- LLM 配置 key 使用 `llm_translate_`、`llm_summary_`、`llm_filter_` 前缀。
