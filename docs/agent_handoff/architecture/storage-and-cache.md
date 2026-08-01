# 存储与缓存

Hive box 在 `lib/utils/storage.dart` 中初始化。

重要 box：

- `setting`：凭据和用户设置。
- `articleDb`：本地文章库。
- `localCache`：通用本地缓存。
- `readStatus`：本地已读覆盖状态。
- `translations`：翻译记录。
- `summaries`：摘要记录。
- `readHistory`：本机最近一次阅读/标记已读时间；最近阅读排序和 macOS 正文图片清理都复用该时间。

关键规则：

- 在当前用法下，Hive 写入后足以立即读取。
- `readStatus` 只是本地已读/未读覆盖状态，不是文章真实已读状态的唯一来源。同步成功或本地库刷新后，覆盖状态可能被清掉。
- 读取文章已读状态时优先使用 `LocalArticleDbService.readOverrideOf(entryId)`；如果没有本地覆盖，再回退到 `ArticleModel.isRead`。不要直接把 `GStorage.readStatus.get(entryId, defaultValue: false)` 当作最终状态，否则最近阅读等已读文章会被错误显示为未读。
- `ArticleModel.isRejectedByAi`、`filterReason`、`filterReviewed`、`filteredAt` 在 upsert/merge 时不能丢失。
- 不要提交真实 API 响应、文章 HTML、token 或调试脚本。使用已忽略的 `scratch/`。
- 设置导入/导出刻意使用白名单；新增需要跨设备迁移的持久设置时，要加入 `SettingsBackupService`。

## 账号数据生命周期

- `setting` 中的 Prompt、DeepSeek Key、模型参数、外观、布局、滚动参数和 feed 偏好属于普通配置，退出或切换 Folo 账号时保留。
- `localCache`、`readStatus`、`articleDb`、`translations`、`summaries`、`readHistory` 属于当前 Folo 账号；Session Token 变化或本地退出时由 `AccountDataService.clearForAccountChange()` 统一清空。
- `setting` 中 `readability_fetched_<entryId>` 和 `inbox_detail_fetched_<entryId>` 虽然位于设置 box，实际是文章级瞬态标记，账号变化时必须删除。`feed_auto_*` 和 `feed_silent_*` 是用户偏好，继续保留。
- 清理前由 `AccountSessionGuard.beginAccountChange()` 进入隔离期，并停止过滤、正文抓取、翻译、摘要和图片预取队列。Folo Dio interceptor 在隔离期拒绝新请求，也会拒绝旧 revision 的迟到响应；翻译、摘要、过滤、正文抓取和图片下载还各自在落盘前复核 revision/generation。凭据写入后由 `finishAccountChange()` 再推进一次 revision，覆盖清理窗口内启动的任务。
- `ReadSyncService` 的旧待同步已读任务和 `SubscriptionCatalogService` 的旧目录同步也必须捕获 revision；账号变化后不得继续重试、补写时间戳、删除新账号队列项或把旧订阅缓存重新写回。
- 图片缓存切换时清空 `DefaultCacheManager`，运行中的旧下载完成后必须依据 generation 删除其结果，不能登记失败、重试或重新写入旧文章索引。
- 清理后必须重置 `LocalArticleDbService` 内存缓存、订阅目录、正文规范化缓存、长度估算缓存、AI 运行时记录和 Undo/Redo，并发出全量文章状态通知。
- 用户接受重建只恢复服务器仍提供的订阅、未读文章和已同步已读状态；本机阅读时间、超出同步窗口的已读旧文、摘要/翻译、审核结果、正文/图片缓存及 Undo/Redo 不保证恢复。

## macOS 正文图片缓存

- `ArticleImageCacheService` 负责 macOS 与 Android 正文图片的文章级缓存键、预取调度和已读后清理。两端正常阅读、后台预取和图片查看器共用同一套文章级键；历史 `v2_<url>` 文件不自动迁移或清理。
- macOS 正文缓存键包含 `entryId + imageUrl`。同一 URL 出现在不同文章时允许重复缓存，以换取按文章可靠清理；底层仍共用一个 `DefaultCacheManager`，不要为每篇文章创建独立 manager/数据库。
- `CachedNetworkImage` 使用 `maxWidthDiskCache` 时会额外生成 `resized_w<width>_<baseKey>`。正文、fallback HTML 和图片查看器必须调用 `registerImage()`，把原图键和实际尺寸变体键都登记到 `localCache` 的 `articleImageKeys:<entryId>` 索引。只删除原图会遗留缩放文件。
- macOS 参数：总图片任务并发上限 `16`；当前打开文章前 `4` 张拥有队列优先级；后台从全部本地未读文章中按时间线顺序取每篇前 `8` 张静态图片。
- Android 参数：总图片任务并发上限 `4`；当前打开文章前 `2` 张拥有队列优先级；刷新时只取时间线前 `50` 篇本地未读文章、每篇前 `4` 张静态图片。恢复未读属于明确用户操作，该文章可单独重新入队，不受批量范围限制。当前不区分 Wi-Fi 与移动网络。
- 两端都不使用 hover 预测，不批量 `precacheImage()` 到内存，明显 GIF/APNG 不后台预取。当前文章的正常图片加载不受后台文章数量限制。
- “前台 4 个”是弹性优先级，不是永久空置 4 个连接。前台空闲时后台可占满 16；打开文章后，其尚未开始的前 4 张会从后台队列提升到队首。已经运行的后台下载不强制取消。
- 用户标记已读或打开已读文章会更新 `readHistory`。保持已读 5 分钟且文章不再打开后，服务串行删除登记的正文图片键；恢复未读会取消清理并重新加入预取。应用运行时由单一 timer 处理，时间线刷新（包括启动后的自动刷新）会补扫遗漏，不单独在启动阶段增加扫描。
- 不清理旧 `v2_` 缓存。新机制验证稳定后再单独提供明确的旧图片缓存清理操作，避免实现和历史迁移同时发生。
- 为未来封面保留独立缓存角色；若加入封面，不要复用正文键，应使用独立 `article-cover` 命名空间，使正文五分钟清理不会误删卡片封面。

近期设置 key：

- `appearance_mode`：`system`、`light` 或 `dark`。
- `article_content_max_width`：文章正文/图片宽度上限。
- `macos_max_fling_velocity`：macOS fling 上限。
- LLM 配置 key 使用 `llm_translate_`、`llm_summary_`、`llm_filter_` 前缀。
