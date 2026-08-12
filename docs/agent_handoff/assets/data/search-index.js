/* 由 scripts/docs-index.js 生成，随内容提交；阅读端零生成。 */
window.WIKI_SEARCH_MANIFEST = "da0b33b090dcdc37";
window.WIKI_SEARCH_INDEX = [
 {
  "path": "architecture/networking.html",
  "title": "网络",
  "headings": [],
  "text": "网络 Folo API： Base URL： https://api.folo.is 用户身份认证只依赖 __Secure-better-auth.session_token cookie；用户不需要查看、填写或备份 X-Client-Id 、 X-Session-Id 。后二者是 Folo 客户端协议元数据：Fourier 首次运行时内部生成并持久化 installation-level Client ID，每次进程启动生成新的 Session ID，由 FoloRequestMetadata 统一附加。它们不是账号凭据，不进入设置导入导出。 当前接口契约以 2026-08-01 的 Folo 上游提交 3846c90b67da351b6017cd4fe9d0992b8077224e 和 @follow-app/client-sdk 0.3.95 为审计基线。上游升级后应先核对 SDK 类型与官方调用点，再修改 Fourier，避免根据响应样本猜测字段。 lib/http/init.dart 中的 Request 是只允许访问 https://api.folo.is 的认证客户端。interceptor 会拒绝 HTTP、相似域名和任意第三方地址，只有通过域名校验后才注入 Session Cookie。 公共文章网页抓取必须使用 lib/http/public_content_http.dart 的无认证客户端。严禁为了复用连接池而用 Request 获取文章原文，否则会把 Folo Cookie 发送给第三方站点。 /subscriptions 返回 feed/list/inbox 联合类型；普通订阅目录只解析带 feeds 的成员。创建订阅的 feed/list/unread 位于响应顶层，不在 data 中；取消普通订阅使用 feedIdList 。分类改名使用 /categories 的批量 feedIdList + category ，不要逐订阅循环更新。 普通条目与 Inbox 条目的 read 都位于列表元素顶层，不在 entries 中。Inbox 列表不支持 withContent ，但支持 publishedAfter 分页；恢复未读必须同时传递正确的 isInbox 。 设置页“测试连接”和保存/导入共用 /better-auth/get-session 会话验证，不再单独拼 Cookie 调用订阅接口。 macOS 使用 Folo 官方 CLI 同类协议：临时 loopback callback 只绑定 127.0.0.1 随机端口；官方网页返回一次性 token 后，应用通过 /better-auth/one-time-token/apply （兼容 /verify ）换取长期 Session Token，再调用 /better-auth/get-session 验证。callback 服务等待三分钟后自动关闭，用户取消也必须立即关闭。 macOS loopback 回调不依赖应用焦点：候选账号验证完成后必须立即结束等待框并应用账号，即使系统浏览器仍在前台。不要把 Android 为避免深链路由竞态而设置的 resumed 生命周期门禁扩散到 macOS。 Android 不访问 /login 页面：移动 UA 会被重定向至 folo.is ，而桌面 UA WebView 又会被 Google 拒绝。应用优先从 /better-auth/get-providers 动态读取 Folo 当前登录方式，Android 排除需要原生身份令牌的 Apple；provider discovery 是辅助能力而不是登录硬依赖，网络或响应异常时必须回退至 Email、Google、GitHub 本地列表。Google、GitHub 等社交登录复用 Better Auth Expo 浏览器协议，Email 则直接调用 /better-auth/sign-in/email ，并在需要时携带短期 two-factor cookie 调用 /better-auth/two-factor/verify-totp 。社交流程通过 /better-auth/expo-authorization-proxy 让服务端根据 authorization URL 自行签发 OAuth state，授权完成后由 folo://fourier-auth 返回带 Session Cookie 的回调。不要把首个响应中的普通 better-auth.state 当成 Expo 专用 oauth_state 转发，否则授权后会落回 folo.is 。 Android manifest 只匹配 host=fourier-auth ，不宽泛接管其他 folo:// 路径； MainActivity 必须关闭 Flutter 默认 deep-link navigation，回调只能由认证 MethodChannel 消费。否则同一 URI 会额外压入 Flutter 路由，完成登录时 Navigator.pop 会弹错路由，表现为界面闪烁后重新露出“等待浏览器登录”。 loopback 登录 URL 不包含长期 Session Token；返回 token 只在内存中交换和验证。不要把 callback query、Set-Cookie、长期 Token 或完整认证响应写入日志。 /better-auth/get-session 除验证长期 Token 外，也提供当前用户的 id/name/email/image 。这些字段只用于本地账号身份展示并缓存为一份轻量资料；头像图片走普通图片缓存与首字符回退，不应让资料刷新失败阻塞启动或同步。 账号切换使用两阶段隔离：清理开始时进入 transitioning 并推进一次 AccountSessionGuard revision，此时 Request 直接拒绝新 Folo 请求；凭据持久化结束后退出 transitioning 并再次推进 revision。旧账号请求即使网络层成功返回、或恰好在清理窗口内启动，也必须作为 cancel 拒绝，不能进入业务合并逻辑。 DeepSeek API： Base URL： https://api.deepseek.com 用于翻译、摘要和 AI 过滤服务。 API key 以 deepseek_api_key 存在 settings 中。 YouTube 播放： macOS 与 Android 首选仓库内可复现构建的 YouTube.js + googlevideo SABR + Shaka Player 运行时；应用不依赖 Node.js，生产产物位于 assets/embed_video_player/ ，构建源和锁文件位于 tool/embed_video_player_runtime/ 。该运行时的 Shaka 控件壳也由 Bilibili 共用。 运行时页面由进程内 127.0.0.1 随机端口提供。路径包含每次进程随机生成的 256-bit 能力令牌；代理只接受 YouTube/GoogleVideo 明确白名单内的"
 },
 {
  "path": "architecture/overview.html",
  "title": "架构概览",
  "headings": [],
  "text": "架构概览 Fourier 总体架构 自底向上分为平台层、页面层、状态与路由、服务层、存储、网络与内嵌播放器运行时；页面经 GetX 状态接入服务，服务读写 Hive 并调用 Folo 与 DeepSeek API。 平台 macOS · AppKit 原生 侧边栏玻璃 / 红黄绿 / 窗口拖动 / 原生菜单 Android · 移动端组件 玻璃底部面板 / 主导航 / 系统浏览器登录 页面 时间线 未读/全部/排序 文章详情 chunk 渲染/目录 订阅源 分类/静默/管理 垃圾拦截 审核/误分类 设置/任务中心 状态 GetX 路由与响应式状态 Rx / Obx / MainController ArticleStateNotifier 跨页面状态扇出 UndoService 50 项业务撤销/重做 服务 同步服务 订阅目录/已读/Readability AI 队列 翻译/摘要/垃圾拦截 图片缓存与预取 文章级键/失败重试 播放协调 快捷键/全屏/滚动桥 存储 Hive box setting · articleDb · readStatus · translations · summaries · readHistory · localCache 网络 Folo API DeepSeek API loopback 媒体服务 127.0.0.1 核心技术栈： Flutter 3.x / Dart 3.11+ GetX 负责路由与响应式状态 Hive 负责本地存储 Dio 负责 Folo 和 DeepSeek HTTP 调用 cached_network_image 、 video_player 、 share_plus 、 image_gallery_saver_plus 和平台插件 重要入口： 应用启动： lib/main.dart 路由： lib/router/app_pages.dart 主框架： lib/pages/main/main_page.dart 时间线： lib/pages/timeline/ 文章详情： lib/pages/article/ 设置： lib/pages/settings/ 高层流程： Folo 凭据保存在 Hive settings 中。 时间线先加载订阅源，再加载 entries，然后合并本地已读/过滤状态。 文章详情会规范化 HTML、解析 chunk，并通过 chunk widget 渲染。 翻译与摘要服务把记录存入 Hive，并暴露响应式 map。 实现偏好： 除非任务明确要求更大重构，否则遵循现有 GetX/Hive 模式。 macOS 专属 UI 行为要用平台判断保护。 修改 macOS 视觉时保持 Android 行为稳定。"
 },
 {
  "path": "architecture/routing-state.html",
  "title": "路由与状态",
  "headings": [],
  "text": "路由与状态 路由： 路由定义位于 lib/router/app_pages.dart 。 主路由通过 MainController 承载类似 tab 的各个区域。 MainController.currentIndex 的 0/1/3 在两端分别都是时间线、垃圾拦截和设置，但索引 2 有平台差异：Android 是订阅源，macOS 是最近阅读。不要在未检查平台的共享代码中把 2 硬编码为同一页面。 Android 主 shell 的四个常驻页面依次为时间线、垃圾拦截、订阅源和设置；垃圾拦截用 embeddedInMainNavigation 关闭自己的独立 AppBar。独立 Routes.filterReview 仍保留兼容入口。 状态： GetX 响应式值（ Rx 、 Obx ）是主要模式。 Service 经常暴露静态方法，并在内部维护响应式 map。 ArticleStateNotifier 用于跨页面刷新文章状态。 重要体验规则： 当 service 记录被删除时，避免继续回退到过期 controller 缓存。近期 bug：从卡片右键菜单删除摘要后， SummaryService 记录已删除，但文章详情仍显示缓存的 controller.summaryText 。修复后的行为是：可见摘要状态应信任 service 记录。"
 },
 {
  "path": "architecture/storage-and-cache.html",
  "title": "存储与缓存",
  "headings": [
   {
    "id": "账号数据生命周期",
    "text": "账号数据生命周期"
   },
   {
    "id": "macos-正文图片缓存",
    "text": "macOS 正文图片缓存"
   }
  ],
  "text": "存储与缓存 存储与账号数据生命周期 普通配置与账号数据分层存储；Token 变化经两阶段 revision 隔离后清理并重建账号内容。 setting（普通配置 · 保留） Prompt / DeepSeek Key / 模型参数 / 外观 / 布局 / feed 偏好 readability_fetched_* 与 inbox_detail_fetched_* 除外（瞬态标记随账号删除） 账号级数据 · 清理重建 articleDb / readStatus / readHistory / localCache translations / summaries / AI 记录 / Undo-Redo Token 实际变化 登录 / 导入 / 退出 beginAccountChange revision+1 · 请求拒绝 · 队列停止 finishAccountChange revision+1 · 覆盖窗口内迟到写回 从 Folo 服务端重建 订阅 / 未读 / 已同步已读 不保证恢复 本地阅读时间 / 摘要 / 缓存 / 审核结果 Hive box 在 lib/utils/storage.dart 中初始化。 重要 box： setting ：凭据和用户设置。 articleDb ：本地文章库。 localCache ：通用本地缓存。 readStatus ：本地已读覆盖状态。 translations ：翻译记录。 summaries ：摘要记录。 readHistory ：本机最近一次阅读/标记已读时间；最近阅读排序和 macOS 正文图片清理都复用该时间。 关键规则： 在当前用法下，Hive 写入后足以立即读取。 readStatus 只是本地已读/未读覆盖状态，不是文章真实已读状态的唯一来源。同步成功或本地库刷新后，覆盖状态可能被清掉。 读取文章已读状态时优先使用 LocalArticleDbService.readOverrideOf(entryId) ；如果没有本地覆盖，再回退到 ArticleModel.isRead 。不要直接把 GStorage.readStatus.get(entryId, defaultValue: false) 当作最终状态，否则最近阅读等已读文章会被错误显示为未读。 ArticleModel.isRejectedByAi 、 filterReason 、 filterReviewed 、 filteredAt 在 upsert/merge 时不能丢失。 不要提交真实 API 响应、文章 HTML、token 或调试脚本。使用已忽略的 scratch/ 。 设置导入/导出刻意使用白名单；新增需要跨设备迁移的持久设置时，要加入 SettingsBackupService 。 账号数据生命周期 setting 中的 Prompt、DeepSeek Key、模型参数、外观、布局、滚动参数和 feed 偏好属于普通配置，退出或切换 Folo 账号时保留。 localCache 、 readStatus 、 articleDb 、 translations 、 summaries 、 readHistory 属于当前 Folo 账号；Session Token 变化或本地退出时由 AccountDataService.clearForAccountChange() 统一清空。 setting 中 readability_fetched_<entryId> 和 inbox_detail_fetched_<entryId> 虽然位于设置 box，实际是文章级瞬态标记，账号变化时必须删除。 feed_auto_* 和 feed_silent_* 是用户偏好，继续保留。 清理前由 AccountSessionGuard.beginAccountChange() 进入隔离期，并停止过滤、正文抓取、翻译、摘要和图片预取队列。Folo Dio interceptor 在隔离期拒绝新请求，也会拒绝旧 revision 的迟到响应；翻译、摘要、过滤、正文抓取和图片下载还各自在落盘前复核 revision/generation。凭据写入后由 finishAccountChange() 再推进一次 revision，覆盖清理窗口内启动的任务。 ReadSyncService 的旧待同步已读任务和 SubscriptionCatalogService 的旧目录同步也必须捕获 revision；账号变化后不得继续重试、补写时间戳、删除新账号队列项或把旧订阅缓存重新写回。 图片缓存切换时清空 DefaultCacheManager ，运行中的旧下载完成后必须依据 generation 删除其结果，不能登记失败、重试或重新写入旧文章索引。 清理后必须重置 LocalArticleDbService 内存缓存、订阅目录、正文规范化缓存、长度估算缓存、AI 运行时记录和 Undo/Redo，并发出全量文章状态通知。 用户接受重建只恢复服务器仍提供的订阅、未读文章和已同步已读状态；本机阅读时间、超出同步窗口的已读旧文、摘要/翻译、审核结果、正文/图片缓存及 Undo/Redo 不保证恢复。 macOS 正文图片缓存 ArticleImageCacheService 负责 macOS 与 Android 正文图片的文章级缓存键、预取调度和已读后清理。两端正常阅读、后台预取和图片查看器共用同一套文章级键；历史 v2_<url> 文件不自动迁移或清理。 macOS 正文缓存键包含 entryId + imageUrl 。同一 URL 出现在不同文章时允许重复缓存，以换取按文章可靠清理；底层仍共用一个 DefaultCacheManager ，不要为每篇文章创建独立 manager/数据库。 CachedNetworkImage 使用 maxWidthDiskCache 时会额外生成 resized_w<width>_<baseKey> 。正文、fallback HTML 和图片查看器必须调用 registerImage() ，把原图键和实际尺寸变体键都登记到 localCache 的 articleImageKeys:<entryId> 索引。只删除原图会遗留缩放文件。 macOS 参数：总图片任务并发上限 16 ；当前打开文章前 4 张拥有队列优先级；后台从全部本地未读文章中按时间线顺序取每篇前 8 张静态图片。 Android 参数：总图片任务并发上限 4 ；当前打开文章前 2 张拥有队列优先级；刷新时只取时间线前 50 篇本地未读文章、每篇前 4 张静态图片。恢复未读属于明确用户操作，该文章可单独重新入队，不受批量范围限制。当前不区分 Wi-Fi 与移动网络。 两端都不使用 hover 预测，不批量 precacheImage() 到内存，明显 GIF/APNG 不后台预取。当前文章的正常图片加载不受后台文章数量限制。 “前台 4 个”是弹性优先级，不是永久空置 4 个连接。前台空闲时后台可占满 16；打开文章后，其尚未开始的前 4 张会从后台队列提升到队首。已经运行的后台下载不强制取消。"
 },
 {
  "path": "architecture/sync-state.html",
  "title": "数据同步与状态传播",
  "headings": [
   {
    "id": "同步入口",
    "text": "同步入口"
   },
   {
    "id": "已读状态合并规则",
    "text": "已读状态合并规则"
   },
   {
    "id": "账号切换隔离",
    "text": "账号切换隔离"
   },
   {
    "id": "页面传播",
    "text": "页面传播"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "数据同步与状态传播 Fourier 以 Folo 服务端为数据权威，本地 Hive 提供缓存与已读覆盖；同步结果通过共享目录、响应式状态和 ArticleStateNotifier 传播到各页面。 数据同步与状态传播 Folo API 经 Dio 拦截器进入同步服务，写入 Hive 后通过 SubscriptionCatalogService 与 ArticleStateNotifier 扇出到时间线、订阅源、最近阅读与垃圾拦截；账号切换由 session revision 隔离。 Folo API api.folo.is Dio 拦截器 Session Token / revision 门禁 同步服务 订阅目录 / 文章 / 已读 Hive articleDb 等 SubscriptionCatalogService 分区权威快照 / 失败保留缓存 ArticleStateNotifier 跨页面扇出 / 动画后延迟通知 读状态 readOverrideOf 时间线 订阅源侧边栏 最近阅读 账号切换隔离 同步入口 订阅源与文章同步集中在 SubscriptionCatalogService ：启动和手动刷新都会同步普通订阅与 Inbox；成功分区按远端快照新增/移除，失败分区保留旧缓存，从其他客户端新增订阅后无需重启即可出现在侧边栏，同时不会删除历史文章或 feed 级本地设置。 垃圾拦截页同步时可以复用 TimelineController.loadFeedsThenArticles() ，然后刷新本页本地审核列表。 已读同步：本地 + Folo 云端双向。 ReadSyncService 维护待同步已读任务。 已读状态合并规则 readStatus 只是本地已读/未读覆盖状态，不是文章真实已读状态的唯一来源。同步成功或本地库刷新后，覆盖状态可能被清掉。 读取文章已读状态时优先使用 LocalArticleDbService.readOverrideOf(entryId) ；如果没有本地覆盖，再回退到 ArticleModel.isRead 。不要直接把 GStorage.readStatus.get(entryId, defaultValue: false) 当作最终状态，否则最近阅读等已读文章会被错误显示为未读。 本地标为已读后的 readStatus == true 是跨请求竞态保护，不能在 mark-read HTTP 成功时立即删除。未读请求可能比 mark-read 更早发出并返回旧快照；只在后续成功未读快照明确不再包含该文章时，才清除覆盖并以本地数据库中的已读状态继续。主时间线和订阅源详情必须遵循同一规则。 自动翻译/摘要只在正文持久化后、准备入队时读取最新本地已读状态：当时已读则不入队，当时未读则正常入队且后续不因标记已读而取消。 账号切换隔离 账号切换使用两阶段隔离：清理开始时进入 transitioning 并推进一次 AccountSessionGuard revision，此时 Request 直接拒绝新 Folo 请求；凭据持久化结束后退出 transitioning 并再次推进 revision。旧账号请求即使网络层成功返回、或恰好在清理窗口内启动，也必须作为 cancel 拒绝，不能进入业务合并逻辑。 翻译、摘要、过滤、正文抓取和图片下载还各自在落盘前复核 revision/generation； ReadSyncService 的旧待同步已读任务和 SubscriptionCatalogService 的旧目录同步也必须捕获 revision。账号变化后不得继续重试、补写时间戳、删除新账号队列项或把旧订阅缓存重新写回。 图片缓存切换时清空 DefaultCacheManager ，运行中的旧下载完成后必须依据 generation 删除其结果。 清理后必须重置 LocalArticleDbService 内存缓存、订阅目录、正文规范化缓存、长度估算缓存、AI 运行时记录和 Undo/Redo，并发出全量文章状态通知。 页面传播 ArticleStateNotifier 用于跨页面刷新文章状态； ArticleStateNotifier.tick() 会同步扇出到最近阅读全库读取/排序、订阅源未读计数、订阅源详情和垃圾拦截等页面。 会移除卡片时，跨页面通知由 completeDeferredReadTransition(entryId) 在真实 onRemoveEnd 后再跨一个 endOfFrame 发出，避免其他页面的同步工作吞掉 180ms 退场动画。 当 service 记录被删除时，避免继续回退到过期 controller 缓存。近期 bug：从卡片右键菜单删除摘要后， SummaryService 记录已删除，但文章详情仍显示缓存的 controller.summaryText 。修复后的行为是：可见摘要状态应信任 service 记录。 相关页面 网络 ：Folo/DeepSeek 请求层与证书校验。 存储与缓存 ：Hive box 与账号数据生命周期。 路由与状态 ：GetX 响应式状态与路由结构。 时间线 ：同步按钮与列表更新边界。"
 },
 {
  "path": "design/interaction-patterns.html",
  "title": "交互模式",
  "headings": [],
  "text": "交互模式 通用规则： 避免会移动布局的 hover 效果。 Press 反馈可以轻微缩放，但前提是不扰动周围内容。 纯图标控件应提供 tooltip。 浮层 tooltip 必须根据自身真实尺寸限制在应用窗口内；靠边时优先自动向内收或翻转，不应允许文案越过窗口后被裁切。 鼠标指针应匹配可点击性。 文章交互： M 在文章详情中切换已读/未读。 摘要和翻译按钮在底层状态变化时应立即更新文字。 从卡片右键菜单删除翻译/摘要后，可见详情状态应立即更新，不需要重新选择文章。 macOS 右键菜单统一使用 AppContextMenu 。它只统一容器外观、行高、图标、危险色、loading/disabled 状态和弹出位置；不要强行统一不同业务的菜单内容。 当前已迁移的右键菜单包括文章动作菜单、正文内图片菜单和图片查看器菜单。普通筛选/下拉菜单可后续按视觉效果再决定是否迁移。 时间线交互： 模式切换应避免为数百/数千个插入删除操作逐个播放动画。 排序菜单关闭时不应闪过 overflow。 同步 spinner 应反映初始同步状态。"
 },
 {
  "path": "design/liquid-glass.html",
  "title": "Liquid Glass",
  "headings": [],
  "text": "Liquid Glass 当前立场： 选择性使用 Liquid Glass。 避免把每个表面都做成重型玻璃。 当玻璃影响性能或可读性时，密集设置/任务中心 UI 优先使用轻量描边面板。 苹果式玻璃应在能澄清层级或形成有意义浮动控件的位置使用，不应作为整页泛用装饰。 参考工程： 用户已把参考材料复制到 reference/ 。 参考代码不是运行时依赖；需要的效果必须复制或重新实现在本仓库内。 已知限制： Flutter shader 代码不能直接采样应用窗口后方的真实像素。 AppKit/系统 compositor 负责真实的窗口后方玻璃。macOS 26 侧边栏使用 NSGlassEffectView ；旧系统才回退到 NSVisualEffectView 。 尝试从真实外部背景提取鲜艳边框色的方案已经放弃；当前可行方案是白色/高光样式或内部玻璃组件。 中间模糊可以是真实系统材质，但 Flutter 绘制的边框仍不能可靠采样同一批窗口后方像素。 如果未来需要真实窗口后方取色边框，需要 native/AppKit 参与，并应作为专门 renderer 实验处理。 macOS 原生侧边栏玻璃： 早期 Runner 在整个透明窗口下方铺设 .sidebar + .behindWindow 的 NSVisualEffectView ，Flutter 侧边栏再叠加模糊和低透明冷白色。强制浅色模式时，这套组合仍容易受系统灰色 sidebar 材质和窗口后方内容影响，表现为侧边栏偏深、文字反而显淡。 当前 macOS 26 使用只覆盖侧边栏面板的 NSGlassEffectView(style: .regular) ，不设置 tintColor ，Flutter 不再为侧边栏叠加白色或二次模糊。浅色和深色共用同一原生组件，由同步后的 .aqua/.darkAqua 外观驱动。macOS 10.15～15 保留 .sidebar + .behindWindow 的 NSVisualEffectView 回退。 NSGlassEffectView 公开可调项主要是 style （ regular/clear ）、 tintColor 、 cornerRadius 和原生几何；它没有模糊半径、折射、饱和度、高光、阴影或边框强度参数。侧边栏应保持 .regular ； .clear 更适合媒体背景并常需额外 dimming，不适合当前导航侧边栏。 侧边栏 Flutter 开口使用连续曲率，而 AppKit 玻璃使用系统轮廓。为避免两套抗锯齿边缘不完全重合而露出未处理背景，原生 backdrop 在 Flutter 遮罩后方向四周扩展 1px ；最终可见轮廓仍由 Flutter 的 8px margin、 18px 连续曲率裁剪决定。 原生玻璃是 Flutter 视图下方的 AppKit 兄弟节点，Flutter 最外层 ClipPath 无法裁剪它。玻璃直接挂在透明窗口下方时，窗口获得焦点后增强的折射和高光会越过应用外框，在左上、左下圆角表现为透明穿透或不规则锯齿。Runner 现在用覆盖整个内容区的透明 sidebarBackdropHost 承载玻璃，并以 24px AppKit 连续圆角做最终外框裁剪；只裁剪这个原生宿主，不裁剪整个 contentView 、Flutter 页面或红黄绿按钮。侧边栏自身的 1px bleed 继续保留，用途与外框裁剪不同。 原生组件没有可调 border。当前 Flutter 在最终轮廓上补 0.5px 环境描边：浅色为黑色 12% ，深色为白色 12% ；浅色另有克制的外侧主阴影和接触阴影，深色不额外加阴影。描边只用于白色/深色背景下的边界识别，不应重新演变为厚重模拟玻璃。 不要为了“略微增加模糊”给侧边栏重新叠 BackdropFilter 。用户了解原生 API 不支持调模糊半径后，明确选择保持系统模糊。 性能： 大量时间线卡片上的重型玻璃曾造成 macOS 性能回归。 侧边栏未读标签、设置页、任务中心已经简化，以降低渲染成本。 参考工程使用方式： reference/ 下代码是设计与实现参考，不是运行时依赖。 如果采用某个效果，应把必要代码复制或重新实现到本仓库。 对依赖协同 shader/renderer 栈的效果，不要假设局部模仿就足够。 当前实用模式： 侧边栏和少数浮动控件可以使用玻璃/材质语言。 覆盖任意文章内容的浮动玻璃面板不能只依赖主题 onSurface 与背景模糊保证可读性。正文下方可能是纯白图片、表格或代码区域，深色模式的浅色文字会因此失去对比。此类面板应在玻璃内部叠主题相关的中性可读性遮罩，而不是全局提高 AppGlassTone.control 不透明度。 当前 appGlassFloatingPanelScrim() 约定深色模式使用黑色 32% 、浅色模式使用白色 18% 。文章目录只在圆形按钮形变为面板的后半段以 easeInOutCubic 渐入遮罩，并确保目录文字出现前遮罩基本到位；关闭静止态按钮仍使用普通圆形 control 材质。后续菜单或同类浮层可以复用该语义规则，但应先单独视觉验证，不要机械套到按钮、tooltip 或大面积页面。 密集列表、设置行、任务行、未读标签、重复卡片装饰应保持轻量，除非重新验证性能。 边框/高光应细腻稳定。用户只期待高光线时，避免边缘效果把整个内部区域变亮。 Tooltip 属于低频浮层，适合统一使用玻璃样式；但触发 tooltip 的按钮本体不一定要变成玻璃按钮。 垃圾拦截审核行的“保留/移除”按钮数量很多，且用户明确担心重玻璃造成性能问题，因此当前保持圆形轻量按钮，只使用玻璃 tooltip。 macOS header 的 soft edge/透明渐隐曾按参考工程思路完整实验，但用户长时间使用后认为观感不理想，现已撤销。当前中间栏和文章详情均使用固定 surface header，内容从其下方开始；不要把 soft edge 当作当前设计语言重新接入。 玻璃控制色： AppGlassControlPalette 是当前玻璃按钮/控件颜色状态的集中入口。 第一阶段只把散落的 hover、pressed、active、border、disabled 色值收敛到 palette，刻意保持原视觉体感基本不变。 AppGlassRoundControlChrome 是固定 34px 圆形工具按钮的共享外壳。文章右上角普通按钮、时间线范围/排序按钮和同步按钮应复用它，而不是各自手写 AppGlassSurface 。 AppGlassMorphSelectionButton<T> 是低选项数量 header 选择器的共享实现：闭合时复用圆形 control chrome，展开时保持右上角锚点并使用统一的弹性 morph、选项 hover/press、关闭按钮和点击外部收回。当前排序和文章范围共用它；选项很多或需要滚动时仍使用常规菜单，不要无限扩展该组件。 主时间线与 macOS 订阅源详情的文章范围只暴露“未读/全部”，使用 filter_alt_rounded / filter_alt_off_roun"
 },
 {
  "path": "design/macos-ui.html",
  "title": "macOS UI",
  "headings": [],
  "text": "macOS UI 当前设计语言： 高密度分栏视图。 半透明材质的悬浮圆角侧边栏。 系统红黄绿按钮被定位到自定义窗口几何中。 macOS 侧边栏当前只保留展开态。旧折叠 rail 入口已经废弃并清理，不要再新增折叠侧边栏专属按钮或状态分支。 macOS 主几何层第一阶段圆角已收敛：窗口/Flutter 外框 24 ，红黄绿圆心 24 ，侧边栏面板 18 ， AppGlassSurface 默认 16 ， AppGlassPanel 默认 18 ，突出面板 20 。这些值应联动维护，不要单独改其中一个。 侧边栏槽位外围和右侧时间线共用 colorScheme.surface 。macOS 主布局使用分层 Stack ：底层保留 290px 透明侧边栏槽位并布局右侧内容，侧边栏玻璃面板最后绘制且允许越界，让外部阴影自然衰减到时间线左缘。不要改回按顺序绘制的单层 Row ，否则右侧 ColoredBox 会盖住越界阴影，在槽位边界形成断层和“独立底板”错觉。 macOS 26 侧边栏面板是 Runner 中的原生 NSGlassEffectView(.regular) ，仅覆盖 290px 槽位内扣 8px 后的面板，不再在整个窗口下方铺原生 sidebar 材质。Flutter _MacOSGlassPane 只负责连续曲率裁剪、内容和轻量边界，不得重新叠白色 tint 或整块二次模糊。旧 macOS 使用同尺寸 NSVisualEffectView(.sidebar, .behindWindow) 回退。 侧边栏宽度、margin 和圆角的真值统一放在 MacOSLayoutMetrics 。Flutter 启动后通过 MacOSWindowControls.setSidebarGlassGeometry() 同步给 Runner；Swift 中的 290/8/18 只是在 channel 生效前避免首帧错位的兜底值。调整几何时修改 Dart 常量，不要分别改 Flutter 和 Swift。 原生 backdrop 比 Flutter 最终开口向外多 1px ，用于覆盖 AppKit 系统圆角与 Flutter 连续曲率抗锯齿不完全重合产生的漏底细缝；不要误删为“尺寸不一致”。最终可见半径仍是 18 。 侧边栏浅色轮廓使用 0.5px / 12% black ，深色使用 0.5px / 12% white ；只有浅色增加低强度外侧阴影。原生 NSGlassEffectView 没有可调 border 参数，这层线由 Flutter 按最终连续曲率绘制。 当前侧边栏阴影以连续融合为目标，不要求肉眼明确看见。用户已验证断层消失、外围底板消失，且玻璃透视、布局和点击行为没有回归；不要为了强调阴影而主动加深或加宽。 Header 分隔线应克制；中间时间线 header 不再使用大面积玻璃。 macOS 中间栏 header 的底部分隔线已取消。这个规则包括主时间线、订阅源详情、最近阅读和垃圾拦截；列表层级主要依赖卡片轻填充、间距和右侧分栏结构。 macOS 中间栏和文章详情使用固定 surface header，滚动内容从 header 下方开始，不再进入 header，也不再使用顶部渐隐。此前参考 .scrollEdgeEffectStyle(.soft) 的透明 header 实验已因长期观感不理想而撤销。文章详情仅在正文大标题接近滚出后，将同一标题以滚动驱动的淡入/轻微位移放入固定 header；这不是透明叠层，也不改变滚动几何。 header 不使用整块 BackdropFilter ；文章 header 曾因此采样到相邻时间线按钮的高光。玻璃仍只属于 header 内的交互控件。 中间栏 header 不显示底部分隔线。文章 header 是例外：当正文大标题折叠进 header 后，底部显示 1px 、 outlineVariant 、alpha 0.30 的细线，橙色阅读进度在其上按比例覆盖；文章位于顶部时两者均隐藏。 控件： 图标按钮在适当位置使用现有 glass/tooltip 组件。 macOS 上仍能看到的旧 IconButton(tooltip: ...) 应优先迁移为 AppGlassIconButton 或外包 AppGlassTooltip ；如果底层控件必须保留，例如 PopupMenuButton 或尺寸很小的展开箭头，应把原生 tooltip 置空，避免同时出现两套 tooltip。 AppGlassTooltip 当前支持底部和右侧两种首选位置。默认底部用于普通工具栏按钮；垃圾拦截审核行这种靠右的垂直小按钮沿用右侧。共享布局会按气泡真实尺寸保留窗口四周 8px 安全边距：水平越界时向内收，底部空间不足时翻到上方，右侧空间不足时翻到左侧；缩放动画锚点也必须跟随最终方向，始终靠近触发控件。不要再为靠边按钮逐个手调 tooltip offset。 空间紧张的 header 筛选不要默认使用完整 segment。时间线“未读/全部”现采用 34px 圆形范围按钮并展开二项 morph 面板；完整 segment 更适合设置页中需要同时展示所有选项的场景。 翻译/摘要文字胶囊是轻量普通胶囊。 Hover 应微妙且稳定；避免闪烁或布局变化。 密集、重复出现的列表按钮不应为了追求玻璃效果而全部改为重型 glass surface；优先使用轻量 hover/描边，并只把 tooltip 统一到玻璃语言。 密集文章列表卡片不使用普通边框作为默认态。用户验证后认为细线边框不够理想，当前取舍是 macOS 普通态极高透明度白/黑中性色填充，浅色模式反向使用黑/灰透明填充。 full-size content view 不再依赖 AppKit 隐式标题栏拖动：启动时固定 NSWindow.isMovable = false ，仅标题文字和明确的空白标题区使用 MacOSWindowDragArea 调用应用控制的窗口拖动。按钮、输入框、菜单和其他交互控件必须作为拖动区域的同级节点，不能放进其子树。旧 MacOSWindowDragGuard 通过异步 channel 临时切换整个窗口，存在按下与 AppKit 开始拖动之间的竞态，已删除；以后新增 macOS header 时应增加明确拖动区，不能重新采用按钮逐个临时禁用窗口的方式。 间距： 边缘应尽量和侧边栏/窗口 margin 视觉对齐。 Scrollbar 不应占用不对称布局宽度，也不应覆盖正文内容。固定 MacHeaderPane 让中间栏列表及 scrollbar 自然从 header 下缘开始，不需要顶部遮罩或轨道 inset。 MacGlassScrollbarStyle 是 macOS scrollbar 颜色、圆角和尺寸的共享入口。中间文章列表使用 articlePaneTheme （ 8px thumb、右侧 1px margin）；右侧文章正文同样是 8px thumb，但局部使用 crossAxisMargin: 2 。设置页和任务中心的 MacGlassScrollArea 仍默认使用更轻的 5px ，不要盲"
 },
 {
  "path": "features/article-rendering.html",
  "title": "文章渲染",
  "headings": [
   {
    "id": "目录面板大面板原生-backdrop",
    "text": "目录面板：大面板原生 backdrop"
   },
   {
    "id": "macos-行内代码",
    "text": "macOS 行内代码"
   },
   {
    "id": "文章链接-hover-生命周期",
    "text": "文章链接 hover 生命周期"
   },
   {
    "id": "android-骨架与共享-inset",
    "text": "Android 骨架与共享 inset"
   }
  ],
  "text": "文章渲染 文章处理流水线 正文从抓取到渲染与导出的阶段划分：抓取、规范化、解析、缓存、渲染、导出与 AI 队列；修复应尽量放在问题所属阶段。 抓取 readability 详情页补抓 规范化 normalizeHtml 来源兼容层 chunk 解析 HtmlChunkParser 规范化缓存 entryId + 正文 SHA-256 指纹 渲染 Column Markdown 导出 ArticleMarkdownExportService · isolate 单篇复制 / 批量导出共用 AI 队列资格 onArticleContentAvailable 未读 → 摘要 / 订阅源开关 → 翻译 渲染输出 标题折叠/目录锚点/图片 右下角圆角安全裁剪 分层原则 渲染器刻意拆分规范化 / 解析 / widget 渲染 修复应尽量放在问题所属阶段 保留 Column 选择 / 目录锚点 / 图片生命周期 / 滚动稳定 不随意切换 SliverList.builder 相关文件： lib/pages/article/article_page.dart lib/pages/article/widgets/html_chunk_card.dart lib/services/article_markdown_export_service.dart lib/utils/article_content_utils.dart lib/utils/article_content_compatibility.dart lib/utils/html_chunk_parser.dart 当前设计： HTML 在渲染前会先规范化。 解析后的 chunk 在文章 scroll 内通过 Column 渲染。 不要随意把文章正文切换到 SliverList.builder ：此前讨论后保留 Column ，原因是选择、目录锚点 key、图片生命周期和滚动稳定性。 渲染器刻意拆分 HTML 规范化、chunk 解析、widget 渲染。修复应尽量放在问题所属阶段。 ArticleController 初始化右上角已读/未读按钮时，必须使用 LocalArticleDbService.readOverrideOf(article.entryId) ?? article.isRead 。不要只读 GStorage.readStatus ，因为最近阅读页传入的文章本身已经是已读，而同步成功后本地覆盖状态可能不存在。 HTML 空段规范化： ArticleContentUtils._removeEmptyBlocks() 会删除没有可见文本、没有媒体、仅由 <br> 和 span/strong/em 等格式包装组成的空块。 <p><span><br></span></p> 与 <p><br></p> 语义相同，不应因多一层无意义包装而逃过清洗。 带 id 或 name 的空元素可能是目录/页面锚点，必须保留；图片、视频、表格、代码、引用和列表等媒体/结构内容也必须保留。新增格式标签时，只有确定其在无文本时没有独立语义，才能加入格式包装白名单。 新智元文章《奥特曼回斯坦福认错：思考外包给AI，一代人大脑正在萎缩》的源 HTML 把几乎每句话放在独立 <p> 中，并在段落间插入 <p><span><br></span></p> 。旧清洗在 152 个段落中残留 82 个这种空段，chunk 合并又在每个段落之间添加 <br><br> ，最终相邻句子间最多叠加 5 个 <br> 。当前窄修复只删除空格式段，使其回到标准段落间距。 不要自动合并该类“一句话一个 <p> ”的正常非空段落。这是上游排版语义；可靠合并需要复杂启发式，会增加误伤和维护成本，用户已明确暂不考虑。 来源兼容规则： 依赖站点 CSS 才能成立的窄兼容修复集中放在 ArticleContentCompatibility ，由 ArticleContentUtils.normalizeHtml() 在通用安全清洗后、图片 URL 规范化前调用。不要把来源判断散落到 HtmlChunkParser 或普通图片 widget，也不要为单一规则引入动态规则引擎。 Hugging Face Blog 的作者头像没有 width/height ，只使用 Tailwind 的 size-9 sm:size-12 或父容器 h-5/w-5 控制显示尺寸。图片文件的固有像素不能代表网页显示尺寸；不应直接按正文最大宽度放大，也不应加载上游整套 CSS。 官方作者区有稳定的 data-target=\"BlogAuthorsByline\" 。兼容层将其转换为内部 fourier-author-list/fourier-author 语义结构，解析器继续兼容旧缓存中的 auto-folo-* 标签； HtmlChunkParser 生成单个 authorList chunk， HtmlChunkCard 以 36px 圆形头像、姓名和账号横向排列并自动换行；有主页地址时整项可点击。作者头像继续使用文章级图片缓存键。 作者区之外的 Hugging Face 头像堆叠属于站点装饰信息，仍按明确的 cdn-avatars.huggingface.co 或 /avatars/ 头像语义移除；普通正文图片和其他来源即使带有 avatar /圆形类名也不能被误删。 已保存译文此前直接进入 HtmlChunkParser ，会绕过正文规范化。当前原文、历史译文和新生成译文在展示前都统一经过 normalizeHtml() ；历史数据不需要批量迁移，重新构建文章 Controller 即可生效。 normalizeHtml() 接受文章原文 URL 作为来源上下文；来源规则按 URL host 分派，不依赖可变的订阅源标题或 feed ID。MarkTechPost 会移除上游依赖网页脚本的 dm-copy-raw-code 控件；若 Interactive Explainer 后出现被 Folo 展开到正文中的完整内嵌文档（以残留 <title> 为确定边界），则把该尾部替换为“交互内容仅在原文网页中可用”及原文链接。不要据此放宽到任意 iframe、任意 Interactive 文本或其他来源。 来源规则必须依赖稳定的来源标记、域名或明确语义，并配正向/反向最小 HTML 测试。不要按文章标题、订阅源 ID、图片是否圆形或图片固有尺寸做宽泛判断。 超链接： macOS 正文链接保留主题色、手型光标、点击打开和底部 URL 预览，但 hover 时不再动态增加下划线。 底部 URL 预览继续由文章页共享的 _hoveredUrl 驱动；它是 Stack 中的局部覆盖层，不改变正文布局。 HtmlChunkCard 不得监听共享 _hoveredUrl 并把 URL 变化作为 HTML widget 缓存失效条件。旧实现会在鼠标进入/离开任意链接时通知所有 chunk，导致全篇 flutter_html 重新解析和文本布局，滚动经过链接时产生瞬时卡顿。 如果未来重新设计 hover 视觉反馈，必须保证不重新解析全"
 },
 {
  "path": "features/background-tasks.html",
  "title": "后台任务",
  "headings": [
   {
    "id": "当前设计",
    "text": "当前设计"
   },
   {
    "id": "交互注意点",
    "text": "交互注意点"
   },
   {
    "id": "ai-队列滚动补位调度",
    "text": "AI 队列：滚动补位调度"
   },
   {
    "id": "长文章分块翻译",
    "text": "长文章分块翻译"
   },
   {
    "id": "全文抓取成功标记与重试",
    "text": "全文抓取成功标记与重试"
   },
   {
    "id": "关系建立队列",
    "text": "关系建立队列"
   },
   {
    "id": "deepseek-请求用量账本",
    "text": "DeepSeek 请求用量账本"
   },
   {
    "id": "本地分析事件账本",
    "text": "本地分析事件账本"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "后台任务 任务中心在 macOS 和 Android 上都可见，用于展示正在进行或排队中的工作。 当前设计 应和设置页共享同一种轻量面板语言。 列表内部避免密集 Liquid Glass 表面；使用简单描边和微弱 hover 状态。 作为 overlay 打开时，背景应保证可读。 Scrollbar 不应造成左右 padding 不对称或出现重复条。 Android 保持设置页进入的二级页面，使用 MobileBlurAppBar 、 12px 页面边距和 MobileSettingsPanel 轻量外壳。AI 失败记录继续作为下一级页面；不要用旧式透明 Card 或密集实时玻璃重做。 交互注意点 macOS 如需保留上下文可以继续使用 overlay；Android 已确认采用完整二级页面，不应为了跨平台形式一致强行改成 overlay。 “去审核”等操作应符合当前 macOS 控件语言，不要使用旧的移动端按钮样式。 如果某个操作被刻意隐藏或移除，应记录产品原因；否则把它当作 bug。 AI 队列：滚动补位调度 三个 AI worker（自动翻译 / 自动摘要 / AI 过滤）与全文抓取队列采用 滚动补位 调度： 任一任务完成后 立即 补充一个新任务，运行中数量始终不超过各自并发配置；不再整批取并发数后 Future.wait ，慢任务不再阻塞后续任务。 三个 worker 保持完全独立：独立的队列、独立的并发配置（ LlmConfig 的 translate / summary / filter 前缀）与独立生命周期，不合并成共享调度器。 并发数在每次补位时按最新配置读取；运行中修改并发数在后续补位时生效，不中断正在运行的任务。 取消（账号切换时由 AccountDataService 调用）清空队列与运行中集合，并推进各 Worker 自己的运行代次；旧代次任务可以自然结束，但其完成回调不得删除新代次的同 entryId 运行标记或触发补位。账号 revision 失效后的在途结果不落库，全文抓取的旧失败结果也不得写失败状态或安排重试。 AI 过滤出队时按最新持久化状态跳过已读 / 已判定 / 已捞回文章。 全文抓取（ AutoReadabilityWorker ）为并发 3 的滚动补位队列。 所有可导入的 LLM 并发值在运行时限制为 1..1024 ；旧配置或手工 JSON 中的 0 不得让 worker 永久空转。 长文章分块翻译 worker 的翻译并发表示“同时处理的文章数”。不同文章继续按翻译并发配置运行。 单篇超过阈值后，其内部 HTML 分块必须顺序请求，避免 文章并发 × 分块数 放大为瞬时 API 洪峰。 每个分块独立重试；已成功分块在本次翻译过程中保留，一个分块失败不得重发此前成功块。 任一分块最终失败时不保存残缺译文，继续沿用整篇失败/恢复上一完成态的语义。 每次真实分块请求仍独立写入 LlmUsageLedger ，因此重试成本可以准确复盘。 全文抓取成功标记与重试 成功标记 readability_fetched_<entryId> 只在成功解析并持久化有效正文后写入 ；失败不再写标记，因此可重试。 失败登记可诊断状态 readability_fetch_state_<entryId> （attempts / lastError / lastAt），自动重试有限次数 + 指数退避（2s / 5s），达到上限后停止并保留失败状态。 旧版本在请求前就打标记的历史数据 不批量清除 ；只有正文为空或明确失败且文章仍未读时进入有限次兼容重试。 已开始抓取的文章即使完成前被标为已读，也允许这一条已开始的流水线继续进入翻译和摘要（ AutoAiQueueCoordinator.onArticleContentAvailable(allowRead: true) ）；尚未开始的等待任务在出队时若已标为已读则移除。 打开文章只记录最近阅读，不得因此标记已读。 关系建立队列 文章关系是摘要完成后的独立增益链路，不属于现有 AI 质量过滤，也不与翻译、摘要、过滤三个滚动补位 worker 合并： 关系建立是可选的高 token 消耗功能，默认关闭。关闭不是暂停：当前任务结果作废，pending 节点被删除，关闭期间完成的摘要不会排队或在重新开启后补算；已有关系与历史窗口保留。 任务中心在关闭时显示“已关闭”，垃圾拦截 header 的关系建立状态显示“关闭”，不能把已保留的历史关系误报为正在工作。 第一次启用时写入账号级 activatedAt ；只消费此后完成并持久化的结构化摘要，启用前旧摘要不会批量进入关系判断。摘要正文缺失、失败或仍 pending 时不入队。 每次最多取 128 篇新摘要；历史窗口从 0 开始随成功批次增长。请求输入是“本批新摘要 + 当前历史窗口”的一个整体，不生成 128×1024 个请求。 worker 固定单飞。凑满 128 篇立即发车；摘要 worker 完全空闲后，不足 128 篇的尾批也立即发车。冷启动本身不得反复冲刷尾批；失败、空响应、非法 JSON 或输出截断时保留 pending，且不推进历史窗口，重启后恢复任务中心错误提示并等待用户明确重试。 手动生成或重试摘要不依赖自动摘要 worker 的生命周期；单篇完成后会显式请求处理当前尾批，避免少于 128 篇时必须等到重启。 DeepSeek 使用 JSON Object 模式。批次记录保存模型、Prompt/schema 版本、耗时、组数以及 prompt/completion/cache hit/cache miss token，供后续真实数据分析。 JSON 结果区分 equivalent （近似重复）和 same_event （同一事件）两类无向关系。同一事件簇按重叠成员跨批次合并；近似重复组不被事件合并吞并。持久化 schema v1 中没有类型的旧关系按近似重复读取。 关系 Prompt 已纳入设置与 version 1 配置导入导出；每次请求的 Prompt 版本使用内容指纹区分，修改 Prompt 后不会把新旧关系结果误当成同一实验口径。 当前调度参数固定为每批最多 128 篇新摘要、历史阈值 1024、单批串行。关系请求默认输出上限为 32K；仅在明确因输出上限截断时以 64K 重试，其他错误不靠提高上限解决。设置页将调度字段并入“关系判断 LLM 参数”并保持禁用，继续通过真实质量、token、缓存命中和耗时调整。 默认 Prompt 的请求使用单一 articles 数组和末尾 new_ids ：文章以持久 sequence 生成稳定 Axxxxxx ID，历史文章在前、本批新文章只追加到数组末尾；下一批中文章从“新”变成“历史”时不再改标签或移动 JSON 区域，因此除数组尾部外可以继续命中 DeepSeek 自动前缀缓存。由旧 N/H + new/history 默认格式升级后的第一次请求需要重建缓存，之后稳定复用。 成功追加后仅当历史数超过 1024 才从队首固定淘汰 128 篇，因此窗口会在约 897～1024 篇间波动：例如 1024 + 1 - 12"
 },
 {
  "path": "features/filter-review.html",
  "title": "垃圾拦截与审核",
  "headings": [
   {
    "id": "文案语义与事件账本",
    "text": "文案语义与事件账本"
   }
  ],
  "text": "垃圾拦截与审核 垃圾拦截审核流转 文章经 AI 判定进入审核页，K/M/N 三种动作写入 userAction 统计信号；误分类是保留或拒绝与已读的原子组合。 文章流 时间线 / 订阅源 AI 过滤判定 DeepSeek · 可编辑 Prompt 被拒绝？ 保留在 普通时间线 垃圾拦截审核页 独立审核队列 · 横滑 / 快捷键 / 右键 K 保留 写 userAction='k' 保留 filterReason M 确认拒绝 写 userAction='m' 弱信号 N 误分类（旗帜） 拦截页 n_keep / 时间线 n_spam 原子撤销：分类 + 已读 垃圾拦截/审核页用于审核被 AI 拒绝的文章。 关键预期： 用户可以审核被拒绝文章。 Android 将垃圾拦截作为四项底部主导航中的一级入口；常驻实例使用嵌入模式，不创建第二层 AppBar。独立路由继续可用，但时间线顶部不再保留重复的“AI 智能过滤”入口卡片。 Android 时间线角标与垃圾拦截角标允许重叠：被 AI 拒绝的未读文章仍按既有逻辑留在普通时间线，同时进入待审核列表。时间线数字使用非静默未读总数，垃圾拦截数字使用 isRejectedByAi && !isRead ；这不是互斥队列。 移除/通过条目后，应跳转到下一篇合适文章，并在 macOS 上保持焦点行为可用。 Header 和面板样式应遵循当前 macOS 轻量面板语言。 Header 不再使用盾牌图标；macOS 与 Android 都分别显示“质量过滤”和“关系建立”状态。质量过滤显示待处理数量或完成态；关系队列收集时显示待批数量/128，API 批次运行时显示独立转圈状态，不能再用一个加载图标混合表达两条流水线。 文章卡片/审核行应保持和时间线卡片一致的交互反馈。 垃圾拦截页不应成为一套完全分叉的时间线实现；能和普通时间线共享的时间线级操作、按钮和文章动作菜单应尽量共享。 状态字段： ArticleModel.isRejectedByAi ArticleModel.filterReason ArticleModel.filterReviewed ArticleModel.filteredAt ArticleModel.userAction ：用户动作标记，事后统计误分类用。取值 'k' （拦截页保留）、 'm' （拦截页确认拒绝）、 'n_keep' （拦截页误分类：保留+已读）、 'n_spam' （常规页误分类：拒绝+已读）、null（未表态）。同一文章多次动作时 latest wins。 统计仅覆盖当前 articleDb 中仍保留的近期文章，不是永久操作历史。它受 5000 篇缓存上限和账号数据清理约束；这是用户确认的产品边界，不要为此另建长期日志或把记录加入设置备份。 本地数据库 merge 时不要丢失这些字段。 误分类（ N / 右上角旗帜按钮）： 拦截页语义：当前文章应该保留，但用户已读完 → 保留 + 标为已读，写 userAction='n_keep' ；复用 _keep 的 pending/退场/后继选中机制。 常规时间线语义：标为已读且应放进垃圾拦截 → 拒绝 + 标为已读，写 userAction='n_spam' ；复用 M 的列表离场/后继选择路径。已读或已在拦截中的文章按钮置灰。 两类误分类都是一条原子 UndoAction，撤销/重做同时恢复分类与已读状态。 所有过滤动作的撤销路径（ filterKeep / filterReject / misclassifyKeep / misclassifySpam ）都使用 upsertOne(forceReplace: true) 整条还原动作前快照；不能用普通 merge， item.userAction ?? existing?.userAction 会把动作标记留在已回滚的文章上。 LocalArticleDbService.setReadState 重建文章时必须保留 userAction （及全部过滤字段），否则标已读/未读会把标记覆盖成 null。 macOS 拦截页的 K/M/N 由页面级 HardwareKeyboard 处理器执行（ _handleHardwareKeyEvent ），不依赖详情面板是否挂载； ArticlePageView 在 isReviewContext 下对 M/N 只消费按键不执行回调，避免与页面级处理器双触发。 HardwareKeyboard 会调用全部注册处理器，不能依赖返回 true 短路。 页面级 K/M/N 必须在 Alt/Control/Command 按下时放行，尤其不能让 Cmd+M 、 Cmd+N 同时触发业务操作。统一使用 MacArticleShortcutService.hasNonShiftModifier 判断。 统计口径：FP = 'k' + 'n_keep' ，FN = 'n_spam' ， 'm' 是弱信号（可能同意也可能懒得分辨），null 无信号。 保留动作（ K 、 'n_keep' ）不再清空 filterReason / filteredAt ，供事后按 AI 原判理由聚合 FP；UI 已按 isRejectedByAi 隐藏显示，不受影响。 upsertMany 合并使用 item.userAction ?? existing?.userAction ，网络同步数据不得覆盖本地动作标记；旧版本二进制重写文章时会丢弃该字段（不可修复），统计语义为\"只有真的没有假的\"。 所有从现有 ArticleModel 重建新实例的路径都必须复制 userAction 。数据库 merge 能保护落盘值，但内存模型丢字段会让后续 Undo 快照无法精确恢复上一个动作。 时间线 N 复用已读退场的帧边界通知； applyMisclassify 不得在 applyReadLocally(...deferTimelineVisualUpdate: true) 后额外立即调用 ArticleStateNotifier.tick ，否则会绕过动画保护。 N 撤销时可先将动作前的完整快照写回数据库，但时间线内存快照必须暂时保持已读，再由 markAsUnreadLocal 完成唯一一次未读插入。如果内存也提前恢复为未读，标准恢复路径会提前返回，后续数据库通知只能通过整表结构刷新重插卡片，并会取消进场动画。 与普通时间线的复用边界： 同步按钮使用 AppGlassSyncButton ，避免时间线和垃圾拦截页各维护一套旋转、tooltip、hover 和玻璃样式。 右键/长按文章 AI 操作使用 ArticleActionsMenu ，普通时间线卡片和垃圾拦截审核行共享翻译、删除翻译、生成摘要、删除摘要等入口。 macOS 垃圾拦截左栏审核行也应复用 ArticleCardChrome 的基础卡片外壳样式，保持和普通时间线卡片一致的轻填充、选中态和无普通边框。不要再在 _MacReviewRow 里单独手写透明/选中背景。 macOS _MacReviewRow 保留拒绝理由和摘要等独立结构，但订阅源行右侧的预计内容"
 },
 {
  "path": "features/keyboard-shortcuts.html",
  "title": "快捷键与焦点",
  "headings": [
   {
    "id": "重要行为",
    "text": "重要行为"
   },
   {
    "id": "焦点规则",
    "text": "焦点规则"
   },
   {
    "id": "导航规则",
    "text": "导航规则"
   },
   {
    "id": "实现结构",
    "text": "实现结构"
   },
   {
    "id": "回归风险",
    "text": "回归风险"
   }
  ],
  "text": "快捷键与焦点 快捷键支持主要是 macOS 功能。 重要行为 M 根据当前页面改变语义：普通时间线切换当前文章的已读/未读状态，其中标为已读后继续选中下一篇；垃圾拦截页则表示移除当前文章。 K 仅用于垃圾拦截页，表示保留当前文章。垃圾拦截中的 M/K 都会在操作完成后继续选中下一篇。 N 表示纠正分类（右上角旗帜按钮）：垃圾拦截页中保留当前文章并标为已读（等效于先 K 再在常规列表 M ）；常规时间线中标为已读并移入垃圾拦截。这是一条原子业务动作， Cmd+Z 一次撤销同时恢复分类与已读状态。常规时间线中已读或已在拦截中的文章不响应 N （按钮置灰）。 Cmd+N 是 macOS 系统新建窗口，必须继续放行，不能被应用快捷键抢走。“误分类”只作为内部分析语义，不作为按钮文案。 无修饰键 C 在当前 macOS 文章详情中复制已加载原文的 Markdown； Command-C 必须继续交给系统复制正文选区。 无修饰键 B 在默认浏览器打开当前原文； Shift+B 是确保已读后打开原文，已经已读时不能反向恢复未读。垃圾拦截页中 Shift+B 复用该页的 M 语义，即移除当前文章并在退场动画结束后打开原文。 Command-B 保留给 macOS 的常规文本语义，不作为应用快捷键。 Cmd+1 回到无订阅源/分类/静默筛选的“全部文章”， Cmd+2 打开垃圾拦截， Cmd+0 打开静默订阅源。键盘页面切换不能复用侧边栏双击计时，否则连续按键可能意外触发时间线回顶。 垃圾拦截/审核页快捷键不能被主时间线抢走。 Cmd+Z 使用最多 50 项的业务历史连续撤销“标为已读、垃圾拦截保留、垃圾拦截移除、静默文章整批标为已读”； Shift+Cmd+Z 按相反顺序连续重做。新的业务动作会清空 redo 栈；导航、切换时间线范围、订阅源、分类或静默 scope 不清空历史。业务栈在应用本次运行期间保持一致，只有进程彻底退出才自然消失，不持久化到下次启动。 文本输入框继续使用 Flutter 自身的文本 Undo/Redo。原生“编辑”菜单与全局快捷键必须先检查当前焦点，不能让文章业务历史抢走输入框里的 Cmd+Z / Shift+Cmd+Z 。 Cmd+R 触发全局刷新。 Cmd+W 关闭当前主窗口，行为与点击红色按钮相同：隐藏窗口但不退出应用。 当前 inline 视频由 activePlayer 归属空格和媒体键；全屏视频独占这些按键。 全屏视频中 Left / Right 分别后退/前进 5 秒， Esc 退出；这些行为只在全屏视频路由存在时接管，不应影响文章列表的左右导航。 Escape 关闭全屏图片预览。 静默订阅源批量选择模式中， Esc 等效于右上角“退出批量选择”，并清空本次勾选；该模式的处理优先于底层文章详情的关闭行为。批量导出正在提交时，关闭入口和 Esc 都不应中断操作。 macOS 从文章来源进入具体订阅源后， Esc 可以回到跳转前的文章与阅读位置。优先级为：批量选择先退出；目标订阅源中已打开文章时先关闭该文章；详情为空时再消费临时来源返回点。该返回点属于导航上下文，不进入 Cmd+Z /Redo 业务历史，并在用户手动切换其他时间线 scope 后失效。 macOS 从文章页点击相关文章后， Esc 先弹出右侧详情区的相关文章栈，并恢复上一层文章的阅读位置和显隐状态；连续进入多篇时逐层返回。这个临时导航不进入业务 Undo/Redo，也不新增可见返回按钮。 焦点规则 在垃圾拦截/审核页执行移除/标记操作后，焦点必须仍可用于键盘导航。 避免焦点落入非命令区域，导致 Flutter 文本选择光标出现。 Esc 关闭分栏文章后，焦点必须落到当前页面不可见的空详情焦点节点，不能让 Flutter 自动恢复到此前点击过的侧边栏条目，否则“全部文章”等入口会残留灰色键盘焦点高亮。 卡片右键菜单操作后，详情页控件应立即更新，不需要先点别的文章再回来。 导航规则 macOS 分栏应保持中间列表和右侧文章详情同步。 当前列表没有选中文章时， Right 选择当前可见列表第一篇， Left 选择最后一篇；页面必须在文章详情尚未挂载时消费该事件，不能让方向键落到侧边栏并留下错误的焦点高亮。该规则覆盖主时间线及其订阅源/静默 scope、垃圾拦截和最近阅读；设置等没有文章列表的页面不接管裸方向键。 键盘移动列表时，应自动滚动选中卡片到可见区域。 双击和快捷键触发的切换应保留卡片进出场动画，除非出于性能原因明确绕过。 实现结构 macOS 菜单栏由 MacOSAppMenu 的 PlatformMenuBar 管理，结构为 Fourier / 编辑 / 显示 / 文章 / 窗口 / 帮助 。系统 About、Services、隐藏、退出、全屏、最小化和缩放继续使用 PlatformProvidedMenuItem ；XIB 只为这些系统项提供本地化标题和 AppKit selector，不要恢复 Flutter 模板中未使用的拼写、替换、语音等菜单。 “编辑”菜单的业务动作名必须始终放在长标题之前，单篇格式为 撤销“动作” · 《截断标题…》 / 重做“动作” · 《截断标题…》 。整批静默文章使用 撤销“批量标为已读” · N 篇 ，不显示任意一篇文章标题。完整 50 项栈不暴露成菜单列表，只展示下一项。 UndoAction.actionName 是菜单动作名， description 用于反馈正文，不要再把完整句子整体截断。 UndoService 使用 BoundedHistory 保存 undo/redo 双栈，并串行执行撤销/重做，避免快速连续按键造成网络回滚乱序。 UndoAction 可以承载单篇或不可拆分的一批文章；页面只通过 redo preparation 在数据变化前登记列表离场；数据变更集中复用单篇或批量本地状态入口，不能在重做路径复制数据库规则。业务栈是进程级内存状态，不得在 scope 切换时调用 UndoService.clear() 。 当前分栏文章通过 MacOSAppMenuService 注册原文、复制 Markdown、已读/审核动作、前后导航、翻译和摘要能力。注册者必须同时验证 route、当前 macOS 页面和当前选中文章，并在销毁时注销，避免 IndexedStack 中隐藏文章污染“文章”菜单。 应用级组合键和无选中文章时的裸方向键定义在 main.dart 的 Shortcuts/Actions 。主时间线、垃圾拦截和最近阅读通过 MacArticleShortcutService 注册当前页面是否激活、是否已有选择以及首末选择动作。裸方向键必须在 Flutter 默认方向焦点移动之前被消费；不要退回到每个页面各挂一套 HardwareKeyboard 方向键监听，否则侧边栏可能已经先获得灰色焦点高亮。 注册器只在当前 macOS 页面、当前 route、没有文章选中且焦点不在 EditableText 时启用。选择前会释放侧边栏旧焦点；有文章选中时，左右键继续由当前 ArticlePageView 处理。页面销毁时必须注销注册，避免 Ind"
 },
 {
  "path": "features/media-playback.html",
  "title": "媒体播放",
  "headings": [
   {
    "id": "播放器快捷键归属",
    "text": "播放器快捷键归属"
   },
   {
    "id": "普通视频",
    "text": "普通视频"
   },
   {
    "id": "macos-全屏视频",
    "text": "macOS 全屏视频"
   },
   {
    "id": "youtube",
    "text": "YouTube"
   },
   {
    "id": "bilibili",
    "text": "Bilibili"
   },
   {
    "id": "共享播放壳与回退",
    "text": "共享播放壳与回退"
   },
   {
    "id": "macos-触控板滚动桥",
    "text": "macOS 触控板滚动桥"
   },
   {
    "id": "网络与安全边界",
    "text": "网络与安全边界"
   },
   {
    "id": "已确认但暂不修复的源内容边界",
    "text": "已确认但暂不修复的源内容边界"
   },
   {
    "id": "youtube-客户端回退链mweb-ios",
    "text": "YouTube 客户端回退链（MWEB / IOS）"
   },
   {
    "id": "普通视频过期带时效签名-cdn",
    "text": "普通视频过期（带时效签名 CDN）"
   },
   {
    "id": "文章图片缓存统一成功通知",
    "text": "文章图片缓存统一成功通知"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "媒体播放 媒体播放分为两类： 普通视频 （ video_player 本地播放器）与 网页平台视频 （YouTube / Bilibili，首选仓库内可复现构建的 Shaka 网页运行时，失败时回退官方 iframe）。两类播放器共用同一套播放快捷键归属与全屏语义。 媒体播放链路 文章内媒体从点击到播放的回退链路：普通视频走本地 video_player；YouTube 与 Bilibili 走内嵌播放器运行时，首选链路失败后回退官方 iframe。 文章正文媒体 HTML chunk / iframe 严格 URL 解析 普通视频 / YouTube / Bilibili InlineVideoPlayer video_player，16:9 视口 内嵌播放器运行时 YouTube.js SABR / Bilibili 匿名 API ShakaEmbedPlayer WebView / 35s 超时 / 快捷键 / 全屏 官方 iframe 回退 youtube-nocookie / player.bilibili.com 懒加载：点击后才创建 WebView / loopback 服务 播放器快捷键归属 inline player 和全屏 player 都支持空格播放/暂停，但同一时刻只能由当前可见播放器处理全局按键。 普通 inline video 与 YouTube 自定义播放器共用 ArticleVideoPlaybackShortcut ：开始播放或点击播放器会把它设为当前播放器，裸 Space /媒体播放键在文章其他区域仍控制当前播放器；切到另一播放器时转移归属，widget dispose 时释放。YouTube 的 WKWebView 焦点内外会走同一通道并做短时间去重，不得再分别维护两套全局快捷键。 进入全屏前，inline player 如果是 activePlayer ，应暂时释放该身份；全屏页在首帧后请求焦点并接管空格。退出全屏后，inline player 再恢复 activePlayer 和焦点。 普通视频全屏页与图片画廊必须通过 root navigator 打开，避免 macOS 分栏详情区的嵌套路由把全屏内容限制在右栏。YouTube/Bilibili 的 WebView 元素全屏继续由系统原生全屏能力接管，不走 Flutter 嵌套路由。 不要让 inline 与全屏页面同时响应同一次空格事件，否则可能发生连续切换两次、视觉上像“空格无效”。也不要在全屏 widget 尚未挂载完成前同步请求焦点。 普通视频 视频不自动循环：controller 初始化后显式 setLooping(false) ；播放自然结束时停在最后一帧，只有用户再次主动播放才 seek 到开头后继续。这一规则同时适用于 inline 和全屏，因为二者复用同一个 controller。 文章内普通视频视口固定为 16:9 ，不再用 feed HTML 的 width/height 改变正文布局。poster 和真实视频都在黑色视口内按自身比例 contain ，允许黑边但禁止裁切、拉伸和加载后重排正文。全屏仍按视频真实比例显示。 普通视频和 YouTube 播放前共用 MediaPlayButton ：macOS hover 使用手指光标；点击后按钮保持 64x64 ，只把图标替换为转圈。初始化状态必须立即 setState ，避免网络较慢时用户误以为没有点击成功。 AnimatedOpacity 不会自动停止命中测试。inline 与全屏视频控制栏隐藏时必须同时 IgnorePointer ，否则不可见的全屏/退出按钮仍会拦截角落点击。 inline 与全屏普通视频的 VideoProgressIndicator 均已启用 allowScrubbing: true 。 video_player 内部支持点击定位和水平拖拽：拖动开始时暂时暂停，拖动中连续 seek，结束后按拖动前状态恢复。两处进度条都用 MouseRegion(SystemMouseCursors.click) 提示可交互；YouTube 进度条由 WebView/YouTube 自己管理。 macOS 全屏视频 macOS 全屏视频不显示顶部返回、旋转按钮和顶部渐变条：返回按钮与红黄绿位置冲突，旋转对桌面没有意义，底部已有退出全屏入口。Android 仍保留移动端顶部返回和横竖屏控制，不要误删为全平台统一行为。 macOS 进入全屏视频时通过 MacOSWindowControls / window_controls 原生通道临时隐藏 AppKit 红黄绿按钮，退出页面时必须恢复。 MainFlutterWindow 保存显隐状态，窗口重新布局时不得强制把按钮提前显示出来。 全屏视频键盘： Space /媒体键播放暂停， Left 后退 5 秒， Right 前进 5 秒， Esc 退出。seek 必须 clamp 到 0..duration ；只处理首次 KeyDownEvent ，不把系统按键重复当作连续快进。 YouTube Folo/Newtype 等源会返回 youtube.com 或 youtube-nocookie.com/embed/... iframe。它不是媒体文件，不能直接交给 video_player ；严格 URL 解析得到 video ID 后，macOS/Android 首选 YouTubeSabrPlayer ，失败时回退到官方 iframe。 YouTubeEmbedInfo 只识别明确的 YouTube embed/watch/shorts/live/youtu.be URL，并统一生成隐私增强 youtube-nocookie.com 地址。 YouTubeSabrPlayer 只在用户点击后启动进程内 loopback 服务并创建 WebView。本地页面打包 YouTube.js 17.2.0、googlevideo 4.0.4、bgutils-js 3.2.0 和 Shaka Player 4.16.2；依赖锁定、构建说明和完整许可见 tool/embed_video_player_runtime/ 与 THIRD_PARTY_NOTICES.md 。不要在 Dart 中 Base64 搬运媒体数据；GoogleVideo 响应必须从 loopback 代理流式送入 WebView。 SABR 播放器的控制语义要尽量对齐 InlineVideoPlayer ：单击画面只显隐控制栏，不直接切换播放；控制栏播放时 3 秒后淡出、暂停时保持可见；进度条使用应用橙色，左侧为播放和时间，右侧只保留音量、设置和全屏。设置菜单保留字幕、清晰度、语言和倍速，不重新引入网页播放器的章节、循环、画中画或保存帧等入口。WebView 内双击全屏已关闭，避免和应用现有点击语义分叉。 VOD 的 SABR UMP 可能正常结束却没有返回媒体段、重定向或上下文更新。此时先卸载失败请求、关闭 SABR 请求改写但保留同源 GoogleVideo 代理，再由同一个 Shaka 控件加载 YouTube"
 },
 {
  "path": "features/performance.html",
  "title": "性能",
  "headings": [
   {
    "id": "核心原则",
    "text": "核心原则"
   },
   {
    "id": "macos-能耗诊断",
    "text": "macOS 能耗诊断"
   },
   {
    "id": "已知好坏版本对比",
    "text": "已知好坏版本对比"
   },
   {
    "id": "决策",
    "text": "决策"
   },
   {
    "id": "滚动惯性",
    "text": "滚动惯性"
   },
   {
    "id": "相对安全的优化点",
    "text": "相对安全的优化点"
   },
   {
    "id": "高风险优化点",
    "text": "高风险优化点"
   }
  ],
  "text": "性能 时间线列表动画时序 单篇已读走增量删除与 180ms 退场动画，跨页通知延后到 onRemoveEnd；批量变化走零时长 batchUpdateVersion，不做大规模 diff 动画。 单篇 M / 双击 本地持久化立即执行 可见列表增量删除 约 164–671 µs · 无列表 reset 180ms 退场动画 onRemoveEnd 后切换下一篇 completeDeferredReadTransition 真实 onRemoveEnd 后跨 endOfFrame：完整过滤 / 角标计数 / 跨页 ArticleStateNotifier 1 秒 fallback 防异常生命周期丢失通知 外部浏览器 等 remove.end 后再跨一帧 避免动画中途失焦 批量变化（模式/排序/同步/回填） timelineListResetVersion → batchUpdateVersion 同一列表实例零时长协调 · 保留滚动位置 诊断埋点（默认关闭） FOURIER_ANIMATION_PROBE=true 只输出 id 末 8 位与动画阶段 本项目的性能工作主要是：在不破坏阅读体验的前提下，避免 macOS UI isolate 卡顿。 核心原则 如果用户可见结果可以保持等价，优先移除昂贵效果，而不是增加复杂节流。 除非用户明确接受取舍，否则不要通过改变阅读语义来优化。 怀疑性能回归时，和已知良好版本对比。 Android fallback 保持轻量，避免 macOS 专属视觉工作泄漏到 Android。 macOS 能耗诊断 2026-08-12 对已连续运行约一天的正式版做空闲采样：在 macOS 省电模式、无 LLM 请求时，Fourier 当前 CPU 约为 0.0%–0.1% ，没有持有防休眠或网络活跃电源断言。现有证据不支持“空闲状态存在永久高 CPU 循环”；系统显示的高耗电更可能来自启动/刷新阶段的集中工作或近期累计能耗。 当前最值得验证的启动负载是文章图片预取：macOS 刷新会为全部本地未读文章在 isolate 中规划图片，随后最多并发 16 个缓存检查/下载，每篇最多 8 张；这是此前明确选择的激进策略，未取得量化证据前不得擅自降低参数。全文抓取和各 AI worker 同时补位也可能叠加负载。 macOS 构建会在本机写入隐私安全的轮转日志： ~/Library/Application Support/io.github.xraygit.fourier/diagnostics/energy.jsonl ，上一轮为 energy.jsonl.previous 。每 15 秒只读采样一次；有 CPU/帧/后台任务活动时落盘，空闲时每 5 分钟才写心跳，单文件上限 2 MiB。 日志只包含进程 CPU 增量、常驻内存、低电量/温度状态、应用与窗口状态、当前主页面索引、Flutter 帧耗时，以及图片/全文/翻译/摘要/过滤/关系队列的计数。不记录文章标题、正文、URL、订阅源、Prompt、账号信息、Token 或 API Key，也不上传。 macOS IndexedStack 中的隐藏主页现在使用 TickerMode 停止 ticker；隐藏的任务中心不再每秒 setState 。这不改变页面状态和可见交互，只移除确定无意义的后台重建。 后续若再次收到系统高耗电提示，应保留应用继续运行并直接检查上述 JSONL；先对齐高 CPU 区间与图片队列、同步状态、AI worker 或慢帧，再决定是否调整预取策略或渲染实现。 已知好坏版本对比 用户反馈 v1.1.20 明确流畅。 v1.1.23 足够接近，可作为良好对比点。 v1.1.25 有明显 macOS 文章正文滚动回归。 v1.1.25 之后的主要改善来自减少昂贵 Liquid Glass 渲染，尤其是侧边栏未读标签和密集设置/任务中心玻璃效果；这已经是当前实现边界，不是尚未开始的优化计划。 决策 文章正文目前保留 Column 。Sliver 虚拟化可能提高原始性能，但会影响选择、目录锚点、图片生命周期、滚动定位和现有阅读行为。 不要给每个小型重复元素都应用真实玻璃。重复时间线标签、设置行、任务行优先使用轻量描边或静态样式。 macOS 中间时间线 header 不使用完整玻璃背景，也不显示底部分隔线。 未读/全部模式切换、订阅源/分类筛选、排序、同步回填、加载更多等批量时间线变化不应为几千个列表项逐个播放动画。 timelineListResetVersion 作为 ImplicitlyAnimatedList.batchUpdateVersion ，在现有列表实例中执行零时长协调；普通单篇标已读/恢复未读动画保留。 从具体订阅源回到完整时间线曾出现明显卡顿。原因是侧边栏连续修改多个响应式筛选字段，触发多次 _applyFilter() ，且 ImplicitlyAnimatedList 试图把“小列表 -> 大列表”做大量插入动画。当前通过 setTimelineScope() 合并状态更新，并用 batch version 禁用这类批量 diff 动画，同时保留 ScrollController ，避免无关更新回到顶部。 macOS 主时间线单篇标为已读也不能同步走完整 _applyFilter() 和全局 ArticleStateNotifier 扇出。约 4799 篇本地文章时，这条旧路径会在动画首帧产生约 73–90ms UI isolate 工作，导致 180ms 退场动画跳帧。当前先增量删除可见项，持久化仍立即完成；全量内存模型、角标/计数和跨页面通知在真实移除结束后维护。日志测得增量更新约 164–671 微秒。 macOS 正文链接 hover 不再通过共享 _hoveredUrl 让所有 HtmlChunkCard 重建。动态下划线已取消，手型光标、链接点击和底部 URL 预览保留；用户验证滚动经过链接时的瞬时卡顿消失。 macOS 订阅源侧边栏不使用以整个 view/category 大组为 item 的 ListView.builder 。这类少量但高度差异巨大的懒加载 item 会让 Flutter 在滚动中持续修正总滚动范围，使 scrollbar 拇指长度和位置跳变。当前滚动区一次布局分类标题和已展开的订阅源行，以稳定 maxScrollExtent ；折叠分类的订阅源行仍不构建。若未来同时展开大量分类后出现真实性能问题，应先测量，再考虑把每个可见行扁平化为稳定的小粒度 sliver，不能直接恢复粗粒度列表。 滚动惯性 当前 macOS 设置项： macos_max_fling_velocity 。 它限制的是 Flutter fling velocity，不是手指仍在触控板上移动时每一帧的原始 delta。 该设置应全局应用于 macOS。 更深层 native 输入过滤曾作为误操作围栏讨论过，但因为侵入性强，可能破坏平台手感、scrollbar、选择、嵌套滚动和可访问性，已搁置。 相对安全的优化点 如果行为保持一致，这些相对安全： 避免滚动时重建文章 chunk。 "
 },
 {
  "path": "features/settings.html",
  "title": "设置",
  "headings": [
   {
    "id": "android-触觉反馈",
    "text": "Android 触觉反馈"
   }
  ],
  "text": "设置 设置页有 macOS 和移动端布局。 重要设置： 服务认证：Folo Session Token，以及 DeepSeek API Key。 LLM 模型/配置值。 Prompt 模板。 已读同步窗口。 角标策略。 文章内容最大宽度。 macOS max fling velocity。 外观模式： system 、 light 、 dark 。 任何会改变持久用户偏好的设置，都应考虑是否加入备份导出。 导入/导出： 使用剪贴板 JSON。 由 SettingsBackupService 白名单管理。 如果新增持久设置需要跨设备迁移，应加入导出/导入。 导出内容可能包含敏感值；UI 应提醒用户。 备份格式继续保持 version: 1 ，并继续导出长期 session_token ，因此旧备份和当前备份都可以在重新安装后恢复登录，不需要强制重新走浏览器。 导入必须先完整解析并验证候选 Session Token，验证通过后才能替换当前账号数据。无效或过期 Token 不能先覆盖当前设置，也不能触发本地账号数据清理。 Folo 登录与退出： macOS 首选 Folo 官方网页登录。实现对标 Folo CLI：应用在 127.0.0.1 随机端口启动临时 callback，在系统浏览器打开 https://app.folo.is/login?cli_callback=... ，收到一次性 token 后调用 Better Auth one-time-token/apply （404 时兼容 verify ），最后用 /better-auth/get-session 验证长期 Session Token。 Folo 官网在生成 CLI 回调期间仍会显示通用的“打开 Folo”按钮，点击会唤起官方客户端，Fourier 无法从系统浏览器中隐藏它。macOS 等待框必须提示用户无需点击该按钮；localhost 回调一旦验证成功，应立即在后台完成登录，不能等待 Fourier 重新获得焦点。Android 深链仍需等待应用恢复前台后再关闭登录界面。 Android 点击“登录 Folo”后动态读取并显示服务端提供方。当前 Folo 返回 Google、GitHub、Apple、Email；Android 与官方移动端一致地排除 Apple。Google/GitHub 在真实系统浏览器中完成，最终通过仅匹配 folo://fourier-auth 的深链返回；Email 使用本地邮箱/密码表单，并支持 TOTP 二步验证码。不要恢复移动 /login 页面或登录 WebView；前者会跳官网，后者会被 Google 拒绝。 社交登录已有对应网页会话时可能直接返回；Fourier 不读取系统浏览器 cookie，只接收 Better Auth Expo proxy 返回的会话 cookie。Email 密码与 TOTP 只在内存中提交，不写入设置、日志或配置备份。 手动 Session Token 入口继续保留。手动保存同样必须先调用 /better-auth/get-session 验证，不能把任意字符串直接写成已登录状态。 当前采用“单一活动账号”，不维护多账号档案，也不尝试识别不同 Session Token 是否属于同一用户。Token 实际变化时一律重建账号内容；完全相同的 Token 重复保存不清理数据。 “退出账号”是本地退出：删除 Fourier 的 Token 和账号内容，但不调用 Folo 远端 sign-out，也不退出系统浏览器。这样旧配置备份中的长期 Token 仍可导入。若要测试账号密码页面，需要用户自行在浏览器退出 Folo。 浏览器登录、手动 Token、配置导入三条入口最终必须汇入 AccountService.applyAccountChange() ，不要分别维护数据清理逻辑。 登录状态的主视觉使用 Folo 返回的头像和用户名，不再用“已配置 Token”代表用户身份。 /better-auth/get-session 返回的 id/name/email/image 会以轻量资料缓存在本机；旧安装仅在有 Token 但缺少资料时补查一次，头像失败则回退为用户名首字符。账号资料不进入 version 1 配置导出，导入 Token 时利用既有在线验证结果重新生成；切换或退出必须和 Token 一起替换或清除，不能残留上一个账号的头像。 macOS UI： 设置/任务中心已经从重型玻璃面板转向轻量描边面板，以改善性能/可读性。 Scrollbar 不应和内容重叠，也不应出现重复条。 设置顶部 chrome 已简化：不再保留大块冗余标题/说明/版本号区域。 设置底部/右侧 padding 应尽量保持和 macOS frame/侧边栏一致的边缘节奏。 Segmented 控件应使用当前 hover/cursor 行为，中性控件避免橙色 hover。 macOS 设置页 segmented 保留自身极弱主色 tint 和主色文字。时间线 未读/全部 已迁移为圆形 morph 选择按钮，不再和设置 segmented 共用 switch 视觉参数；不要为了机械统一把 header 选择器重新改回 segmented/switch。 macOS 自定义下拉菜单使用 _MacGlassSelectField 。下拉 overlay 不能完全透明：菜单面板需要局部静态底色遮住背后内容，且底色圆角必须和外框圆角对齐。 下拉 overlay 的可读性修复是局部处理，不应通过全局提高 AppGlassSurface 不透明度解决，否则会影响其他已经验证过的玻璃控件。 三选一的外观 segmented 高度和普通下拉/文本输入结构不同，应在“阅读与后台偏好”中独占完整一行；不要为了机械配对压缩其已验证的动画和玻璃规格。其余普通设置再进入响应式两列网格，窄窗口回落为单列。 macOS 的 Folo 与 DeepSeek 凭据位于同一个“服务认证”容器，底部右侧共用紧凑的“测试连接 + 保存认证”按钮行；Prompt 保存/重置仍位于各自容器底部右侧。不要把保存按钮挤在输入框右侧或横向撑满卡片。 开源许可证入口不得再调用 Flutter 默认 showLicensePage() ，否则会在三栏应用上方推入一张脱离 Fourier 设计语言的完整 Material 页面。macOS 使用窗口内居中玻璃面板，并在宽屏内以软件包列表 + 许可证正文双栏呈现。 Android UI： Android 设置页使用独立的移动端分组布局，但继续复用相同保存语义与业务组件。页面水平边距为 12px ，大面板使用 MobileSettingsPanel 的 24px 连续圆角和轻量静态材质；不要把 macOS 双栏设置布局压缩后直接搬到手机。 服务认证卡提供动态登录方式选择、手动长期 Session Token 和本地退出。所有登录方式最终都必须经过 /better-auth/get-session 验证，不能仅凭 OAuth 回调、Email 200 响应或 cookie 存在就切换账号。 点击登录后，"
 },
 {
  "path": "features/subscriptions.html",
  "title": "订阅源",
  "headings": [
   {
    "id": "订阅错误文案区分源站阻止与url-无效",
    "text": "订阅错误文案：区分“源站阻止”与“URL 无效”"
   }
  ],
  "text": "订阅源 订阅源侧边栏结构 分类行、展开箭头与订阅源行职责分离；当前订阅源临时锁定父分类展开；静默订阅源作为独立分组。 分类行 点击 = 切换分类筛选 hover/press 整行单一反馈 展开箭头 独立点击 · 只改展开 临时锁定时 no-op 订阅源行 点击 = 选择具体源 右键编辑 / 取消订阅 当前源 父分类 临时锁定 SubscriptionCatalogService 共享权威目录 · 分区快照 · 失败保留缓存 侧边栏与时间线 feed mapping 同一份数据 静默订阅源分组 独立分组 · 点击只进入静默时间线 不因“被选中”自动展开 真实总高度滚动区（SingleChildScrollView + Column） 订阅管理写操作（添加/编辑/取消 · 可撤销） 订阅源数据支撑时间线过滤和展示。 当前行为： macOS 已提供第一轮订阅管理： 订阅源 section 标题右侧的 + 直接通过 RSS URL 添加普通订阅。该入口使用紧贴 18px 图标的 20px 点击区，静止时不绘制玻璃底板、边框或圆形轮廓，只在 hover/press 时显示轻量中性反馈，避免透明大点击框造成视觉错位；其右缘使用侧边栏普通行数量气泡的 24px 基准线，不改变 section 标题原有位置和信息密度。普通订阅源行右键可编辑或取消订阅；普通分类行右键可重命名或取消分组。Inbox 不是普通 RSS 订阅，不进入这些写操作。 添加与编辑共用同一套表单状态和校验。添加时 RSS URL 可编辑，编辑时 URL 只读；两种模式都可设置自定义标题、分类和内容类型（ Articles / Social Media ）。第一轮不做关键词发现、推荐、RSSHub 浏览、OPML、私密订阅或“从 Folo 总时间线隐藏”。 远端订阅元数据与 Fourier 本地偏好必须分层：自定义标题、分类和内容类型写入 Folo；静默、自动翻译、自动全文仍是本地设置，不得伪装成 Folo 订阅字段。“从总时间线隐藏”不引入本项目，现有静默机制继续承担对应的个人工作流。 FeedModel.title 是最终显示标题，优先使用订阅关系的自定义标题； sourceTitle 保留 RSS 源标题， customTitle 保留用户覆盖值。编辑表单清空自定义标题后必须恢复显示源标题。 订阅写操作集中在 SubscriptionManagementService ，HTTP 细节集中在 FeedHttp 。服务端变更成功后先更新共享目录并同步缓存，再通过 SubscriptionCatalogService 通知侧边栏和时间线；页面不得分别维护自己的订阅副本。 取消订阅需要确认，并作为自定义命令进入全局 50 项 Undo/Redo 历史。撤销会使用原 URL、标题、分类和内容类型重新订阅，重做再次取消；应用彻底关闭前应与其他已读/垃圾拦截动作共享同一条历史栈。 取消订阅只删除远端订阅关系及共享目录条目。不得删除历史文章、正文/图片缓存以及按 feed id 保存的静默、自动翻译和自动全文偏好；重新订阅同一 feed id 后这些本地偏好可以继续生效。 如果取消的是当前正在查看的具体订阅源，macOS 时间线立即回到“全部文章”，避免保留指向已不存在目录项的 scope。 订阅源会被缓存，但缓存不是永久并集。 SubscriptionCatalogService 是时间线 feed mapping 与侧边栏订阅树的共享目录；启动和手动刷新都先同步目录，再加载文章，两处不得各自维护独立请求和合并规则。 普通订阅和 Inbox 分区独立同步：某分区成功时，返回结果是该分区的权威快照，新订阅立即加入、已取消订阅立即移除；某分区失败时，只保留该分区旧缓存，不能因为另一分区成功而误删。成功的空列表同样表示该分区应清空。 目录同步具有本地修改代次。若远端请求在途时完成了本地添加、编辑或取消订阅，该请求可能代表操作前的旧状态，禁止直接发布；服务应自动重新同步后再替换共享目录。 共享目录只更新订阅元数据及侧边栏，不删除本地历史文章，也不删除按 feed id 保存的静默、自动翻译或自动全文设置。以后重新订阅同一 feed id 时，这些本地设置仍可继续生效。 订阅源/分类过滤应保持文章计数和 header 副标题准确。 静默订阅源设置会影响普通时间线计数和可见性。 macOS 侧边栏里，静默订阅源属于订阅源体系，不是主导航入口。普通订阅源树会排除静默源，静默源作为 订阅源 section 滚动内容末尾的特殊分组展示，避免重复。 macOS 静默订阅源分组的筛选与展开状态相互独立：点击分组行只切换到静默时间线，不应自动展开；只有用户点击展开/折叠按钮时才改变子列表可见性。 macOS 普通订阅源分类必须区分导航选择、用户手动展开和临时可见性。分类主体只切换分类筛选，箭头只改变手动展开状态，订阅源行只选择具体订阅源；不要让这些点击互相附带副作用。 分类行的 hover/press 必须是覆盖整行的单一视觉反馈。展开箭头仍保留独立点击语义和 tooltip，但自身 IconButton overlay 应透明，由外层行统一绘制反馈；箭头点击只展开/折叠，行主体点击只选择分类。临时锁定导致箭头不可折叠时，箭头区域仍应消费点击并保持 no-op，不能穿透成分类选择。 当前时间线正在查看某个具体订阅源时，其父分类临时锁定展开，保证当前项可见；该临时状态不能覆盖用户原来的展开偏好。切换到最近阅读、垃圾拦截或设置后解除锁定：原来手动展开的继续展开并可折叠，原来折叠的恢复折叠。 macOS 从文章元数据点击来源进入具体订阅源时，时间线保存一层临时返回上下文。目标订阅源中没有打开文章时按 Esc ，应恢复此前 scope、原文章、时间线滚动位置、正文滚动位置以及译文/摘要显隐；如果先打开了目标订阅源中的文章，第一次 Esc 仍只关闭该文章，第二次才返回。用户手动切到其他订阅源、分类或静默范围后返回上下文失效；同一订阅源内点击来源不建立返回点。 临时锁定期间，折叠箭头不应暗中写入折叠状态，tooltip 应说明当前订阅源位于该分组。将来若侧边栏加入搜索，搜索期间的临时展开也应遵循同一规则，清除搜索后恢复手动状态。 macOS 订阅源侧边栏使用独立 ScrollController 、单一显式 Scrollbar 和可一次得到真实总高度的 SingleChildScrollView + Column 。不要恢复成“一个 view/category 大组对应一个 ListView.builder item”的粗粒度懒加载：展开后的分组高度差异很大，Flutter 会在滑动到新组时反复修正 maxScrollExtent ，导致 scrollbar 拇指长短剧烈变化并前后跳跃。折叠分类仍只构建标题，只有展开分类才构建订阅源行。 Folo 官方来源类型展示名按英文保留： Articles 、 Social Media 、 Inbox 。不要再把 social 显示成“社交”，也不要使用 Social Inbox Feed 这类官方不存在的组合名。 相关服务： FeedT"
 },
 {
  "path": "features/timeline.html",
  "title": "时间线",
  "headings": [
   {
    "id": "最近阅读点击不再立即重排",
    "text": "最近阅读：点击不再立即重排"
   }
  ],
  "text": "时间线 相关文件： lib/pages/timeline/timeline_controller.dart lib/pages/timeline/timeline_page.dart lib/pages/widgets/article_card.dart lib/common/widgets/article_card_chrome.dart lib/common/widgets/article_length_label.dart lib/utils/article_length_estimator.dart lib/common/widgets/app_glass_sync_button.dart lib/common/widgets/app_glass_selection_button.dart lib/pages/widgets/article_actions_menu.dart lib/common/widgets/mac_split_article_list_coordinator.dart 当前行为： 模式：未读、全部、已读。 macOS 中间 header 的文章范围只暴露未读/全部，并使用与排序统一的圆形 morph 选择按钮，而不是完整 segment 或二态 switch。 Android 主时间线 header 与订阅源详情复用圆形文章范围按钮，点击后从玻璃底部面板选择 未读/全部 ；已读文章仍通过最近阅读等独立入口访问，不等于删除已读能力。 macOS 中间栏 header 不显示底部分隔线；当前视觉依赖卡片间距和轻填充区分层级。这个规则包括主时间线、订阅源详情、最近阅读和垃圾拦截，不要只在某个页面单独处理。 macOS 文章卡片普通态使用极轻中性色填充，统一由 ArticleCardChrome 控制；当前深色模式 alpha 为 0.018 ，浅色模式为 0.012 。时间线、最近阅读和垃圾拦截不要分别覆盖该值。 macOS 与 Android 的普通文章卡片、垃圾拦截审核卡片共用标题字号 14 和辅助正文 12 ，统一由 ArticleCardChrome.titleFontSize/bodyFontSize 提供，不要在页面中分别硬编码。 普通文章卡片在最下方订阅源行右侧显示预计内容高度；共享 ArticleLengthLabel 使用弱化 12px 文字，不增加卡片高度、胶囊、图标或平台分支。macOS 垃圾拦截虽然保留独立 _MacReviewRow ，也必须调用同一个标签组件。后台任务失败卡片不属于正常阅读列表，不显示长度。 macOS 主时间线和垃圾拦截列表共用 MacArticleListChrome 的两层下边距： viewportPadding 是滚动过程中始终存在的窗口下边界， contentPadding 是滚到列表末尾后出现的内容留白。不要只增加 ListView.padding.bottom 来替代视口边界，也不要在两个页面分别硬编码。 macOS 主时间线、垃圾拦截、最近阅读和订阅源详情通过 MacHeaderPane 共享固定 header/body 几何。内容和 scrollbar 自然从 header 下方开始；thumb 宽度及右侧 margin 继续由 MacGlassScrollbarStyle.articlePaneTheme 提供（ 8px 、 1px ）， MacArticleListChrome.contentPadding 另保留 2px 右侧内容间隔。 macOS 订阅源详情页的 header 筛选复用同一个文章范围 morph 组件；不要重新引入 仅已读 入口。 已读模式/页面仍在其他入口存在，不应删除。 过滤支持选中订阅源、分类和静默订阅源。 本地文章库支撑时间线状态。 已读/未读变化会更新本地状态并通知其他视图。 时间线和最近阅读列表合并本地已读状态时，使用 LocalArticleDbService.readOverrideOf(entryId) ，没有覆盖时保留 ArticleModel.isRead 。该规则同时支持本地标为已读和恢复未读，不要退回到只处理 readStatus == true 的旧逻辑。 本地标为已读后的 readStatus == true 是跨请求竞态保护，不能在 mark-read HTTP 成功时立即删除。未读请求可能比 mark-read 更早发出并返回旧快照；只在后续成功未读快照明确不再包含该文章时，才清除覆盖并以本地数据库中的已读状态继续。主时间线和订阅源详情必须遵循同一规则。 垃圾拦截/审核这类列表如果语义要求稳定追加，新文章应稳定附加。 macOS 静默订阅源批量导出： 批量入口只出现在“静默订阅源”汇总视图，不出现在单个静默订阅源中。进入批量模式时默认不选文章；卡片本体仍用于打开阅读，右上角独立的轻量标识负责切换勾选，不能复用当前文章的选中描边。 全选/全不选作用于当前筛选后的整个静默文章集合，不局限于当前视口。离开静默汇总 scope 时退出批量模式并清空勾选。 动作只有“复制 Markdown”“保存 Markdown”“复制并标为已读”“保存并标为已读”，不提供单独的批量标为已读。纯导出成功后保留批量模式和勾选；组合动作成功后退出批量模式并清空右侧详情。 批量导出入口与文章范围、排序入口共用锚定在右上角的液态玻璃 morph 展开组件；它是命令菜单，不显示持久选中项或勾号。批量模式下按 Esc 必须复用右上角关闭按钮的退出路径，同时清空本次勾选；处理中的批量动作仍禁止中途退出。 单篇复制和批量导出统一调用 ArticleMarkdownExportService ，页面不得自行维护 Markdown 转换器。批量保持当前列表顺序，文章之间只用 --- 分隔，不添加“静默订阅源导出”总标题或批次元数据。正文尚未缓存时仍输出标题、来源、链接，并写入 > 正文尚未缓存 ，不能为了导出临时联网拉正文。 组合动作必须先完成剪贴板写入或文件保存，之后才标为已读；文件保存取消、写入失败或复制失败都不能改变读状态。整批标为已读只占一个业务撤销项，撤销时整批恢复未读，重做时整批重新标为已读。 批量本地状态通过 TimelineController.setManyReadStatesLocal() 一次合并列表、计数和跨页面通知，不逐篇触发全量过滤或卡片动画。 BatchReadSyncService 逐篇追踪前向成功、补偿成功和最终仍改变的文章：部分请求失败后补偿已确认成功的请求；补偿全部成功时本地和历史都不变，补偿仍有失败时只把最终改变的子集写入本地并登记为可撤销批次。部分 Undo/Redo 同样拆分成功与未成功的子集，使两侧历史始终对应最终远端状态。 macOS 分栏选择与移除协调： MacSplitArticleListCoordinator 统一承载分栏文章列表中的稳定 item key、删除前后继项计算、删除期间选择保持、 onRemoveEnd 后详情切换、相对导航和 reveal 回调。页面继续负责已读、审核、数据库和网络等业务动作，不要把这些业务塞进协调器"
 },
 {
  "path": "features/translation-summary.html",
  "title": "翻译与摘要",
  "headings": [
   {
    "id": "摘要完成后的关系建立",
    "text": "摘要完成后的关系建立"
   },
   {
    "id": "翻译持久化时序",
    "text": "翻译持久化时序"
   }
  ],
  "text": "翻译与摘要 自动 AI 队列调度 正文持久化后经 onArticleContentAvailable 统一入队：只服务当时仍未读的文章，按订阅源开关决定翻译，Worker 并发执行并写入 Hive；手动操作不受限制。 正文已持久化 Readability / 详情页补抓 onArticleContentAvailable 唯一自动入队门卫 当时仍未读？ 已读则不排队 摘要队列 全部未读文章 翻译队列 按订阅源开关 入队后 不追已读 手动翻译/摘要 不受队列限制 AutoAiWorker 并发执行 · 原地重试 Hive 记录 translations / summaries 页面 立即可见 自动任务只在入队时检查文章的最新已读状态。已经是已读的文章不进入自动翻译和摘要队列；以未读状态入队后，后续即使标记为已读也不追踪取消，任务照常完成。这是经长期使用后确认的取舍：旧取消机制只能命中尚未被高并发 Worker 取入批次的少量任务，收益不足以支撑额外状态分支。手动翻译/摘要和垃圾拦截判定均不受影响。 新正文可用后的自动 AI 流转由 AutoAiQueueCoordinator.onArticleContentAvailable() 统一负责。后台 Readability、文章详情页直接补抓全文和 Inbox 详情补正文都必须在成功持久化正文后调用该入口；入口读取数据库中的最新已读状态，只给当时仍未读的文章排摘要，并按订阅源自动翻译开关排翻译。不要让详情页只更新显示和数据库而遗漏 AI 队列，也不要在 setReadState() 中重新加入队列取消副作用。 相关服务： lib/services/translation_service.dart lib/services/summary_service.dart lib/services/llm_config.dart lib/services/article_relation_service.dart lib/services/article_relation_worker.dart 存储： 翻译记录在 GStorage.translations 。 摘要记录在 GStorage.summaries 。 摘要启用后产生的关系节点/组在 GStorage.articleRelations ，批次与 token/cache 统计在 GStorage.relationBatches 。 LLM 默认取向： 翻译：flash、不思考、默认并发 32、低 temperature、大输出。 摘要：flash、thinking max、默认并发 32、紧凑输出。 过滤：flash、thinking max、默认并发 32；仓库默认只做保守、通用的内容质量审核，不表达特定用户的主题或来源偏好。用户保存/导入的自定义过滤 Prompt 优先于默认值。 关系判断：flash、thinking max、每批最多 128 篇新摘要，网络请求固定单飞。这里的 128 是批大小而不是并发数；历史阈值为 1024。 摘要完成后的关系建立 关系建立由跨平台设置 article_relation_enabled 控制，默认 false 。只有开关开启后完成的摘要才进入关系队列；关闭期间不积压，重新开启也不追溯。已有关系数据保留，以便用户停止 token 消耗后仍可查看此前结果。 现有质量过滤继续使用标题、来源和正文前 500 字，行为完全不变；关系判断只使用标题、来源、作者、发布时间和摘要，二者不得合并成一条 Prompt。 SummaryService 先等待 done 摘要写入 Hive，再通知关系服务。关系入队失败只能记录诊断，不能把已经成功的摘要改判为失败；启动恢复会扫描启用时间后的 done 摘要，补上摘要落盘与关系入队之间的崩溃窗口。 关系 Prompt 建立两种稀疏、无向关系： equivalent （近似重复）表示阅读任意一篇后其余内容基本可替代； same_event （同一事件）表示报道同一次明确发布、公告、事故或核心事实，但各自仍有不可替代的新增信息。仅主题、人物、产品或领域相近不算同一事件，后续独立评测、量化版本和生态适配也不自动归入原发布事件。 关系判断不参考已读状态、用户兴趣或质量。日报/周报/合集、纯图片和摘要不足的文章留在正常窗口中，但要求模型不要建立关系；关系缺失是可接受结果。旧版或旧自定义 Prompt 未输出 type 时按 equivalent 兼容，明确的未知类型则忽略。 默认关系 Prompt 接收稳定 articles 数组与末尾 new_ids ；文章 ID 来自账号级关系 sequence，不因批次身份变化。仓库已发布过的旧默认 Prompt 自动迁移，用户真正自定义的旧 Prompt 保留并继续使用旧 new/history + N/H 输入契约。 文章页只在存在关系时，于翻译/摘要工具栏下显示轻量相关文章横条，并用“近似重复”或灰蓝色“同一事件”标签明确语义。没有关系时不显示标题、占位或额外间距；直接关系与完整连通关系组分开呈现。同一事件组可跨批次按重叠成员合并，近似重复继续保留为更精确的独立子组。 macOS 分栏点击相关文章时只在右侧详情区压入一层文章，不切换整个应用页面；按 Esc 逐层返回，前一篇文章的滚动位置、译文和摘要显隐由仍挂载的详情页自然保留。Android 继续使用完整文章路由。垃圾拦截通过相关文章临时查看其他文章时，页面级 M/K/N 必须停用，避免动作错误作用于原审核文章。 重试： 翻译和摘要使用由 auto_retry_max_count 控制的原地重试。 重试期间 pending 状态应可见。 UI 注意点： macOS 翻译/摘要工具栏按钮是普通胶囊控件，不是重型 Liquid Glass。 灰色非激活按钮 hover 时不应闪烁；hover 只轻微改变边框。 从卡片右键菜单删除摘要后，文章详情必须立即更新。 SummaryService 记录删除后，不要回退到过期 controller summary text。 卡片右键操作会直接调用 service 方法；确保跨页面 UI 观察 service 状态或 notifier 状态。 文章在详情页打开后，后台译文仍可能稍后完成。 ArticleController 监听 TranslationService.recordsVersion ，只为当前文章解析最终译文并刷新 translatedChunks ；删除译文也必须清理详情页旧状态。不要重新把是否已有译文只固定在控制器初始化时判断。 文章列表里的长按/右键 AI 菜单由 lib/pages/widgets/article_actions_menu.dart 统一维护。 普通时间线卡片和垃圾拦截审核行都应通过 ArticleActionsMenu 提供翻译、删除翻译、生成摘要、删除摘要。这样新增或修复文章级 AI 动作时不需要同时改两套页面。 ArticleActionsMenu 只封装文章级动作和反馈，不拥有文章详情状态；删除翻译/摘要后的可见刷新仍依赖 service/notifier "
 },
 {
  "path": "features/undo-redo.html",
  "title": "撤销与重做",
  "headings": [
   {
    "id": "行为",
    "text": "行为"
   },
   {
    "id": "菜单与反馈",
    "text": "菜单与反馈"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "撤销与重做 macOS 的业务撤销/重做由 UndoService + BoundedHistory 提供，容量 50 项，覆盖标为已读、垃圾拦截保留/移除、误分类（ N ）和静默订阅源整批标为已读。 撤销重做流程 业务动作写入数据库后登记 UndoAction；Cmd+Z / Shift+Cmd+Z 串行执行撤销与重做，列表动画在数据变化前登记退场。 业务动作 标已读 / 保留 / 移除 / N 数据库写入 upsert / forceReplace 快照 登记 UndoAction BoundedHistory(50) 双栈 清空 redo 栈 Cmd+Z / Shift+Cmd+Z 串行执行，redo 准备先登记离场 输入框 文本历史 恢复 / 重做 本地列表增量更新 → 跨帧通知 → 后续选中 动画期间 Command-Z 取消待切换目标 行为 Cmd+Z 使用最多 50 项的业务历史连续撤销“标为已读、垃圾拦截保留、垃圾拦截移除、静默文章整批标为已读”； Shift+Cmd+Z 按相反顺序连续重做。新的业务动作会清空 redo 栈；导航、切换时间线范围、订阅源、分类或静默 scope 不清空历史。 业务栈在应用本次运行期间保持一致，只有进程彻底退出才自然消失，不持久化到下次启动。不要在 scope 切换时调用 UndoService.clear() 。 文本输入框继续使用 Flutter 自身的文本 Undo/Redo。原生“编辑”菜单与全局快捷键必须先检查当前焦点，不能让文章业务历史抢走输入框里的 Cmd+Z / Shift+Cmd+Z 。 全部过滤动作的撤销路径（ filterKeep / filterReject / misclassifyKeep / misclassifySpam ）都使用 upsertOne(forceReplace: true) 整条还原动作前快照；不能用普通 merge， item.userAction ?? existing?.userAction 会把动作标记留在已回滚的文章上。 误分类（ N ）是一条原子 UndoAction：撤销/重做同时恢复分类与已读状态。 N 撤销时可先将动作前的完整快照写回数据库，但时间线内存快照必须暂时保持已读，再由 markAsUnreadLocal 完成唯一一次未读插入。如果内存也提前恢复为未读，标准恢复路径会提前返回，后续数据库通知只能通过整表结构刷新重插卡片，并会取消进场动画。 静默订阅源整批标为已读只占一个业务撤销项；部分 Undo/Redo 会把已完成与未完成子集拆到 redo/undo 两侧，使两侧历史始终对应最终远端状态。 UndoService 使用 BoundedHistory 保存 undo/redo 双栈，并串行执行撤销/重做，避免快速连续按键造成网络回滚乱序。 UndoAction 可以承载单篇或不可拆分的一批文章；页面只通过 redo preparation 在数据变化前登记列表离场；数据变更集中复用单篇或批量本地状态入口，不能在重做路径复制数据库规则。 菜单与反馈 macOS 菜单栏由 MacOSAppMenu 的 PlatformMenuBar 管理，结构为 Fourier / 编辑 / 显示 / 文章 / 窗口 / 帮助 。系统 About、Services、隐藏、退出、全屏、最小化和缩放继续使用 PlatformProvidedMenuItem ；XIB 只为这些系统项提供本地化标题和 AppKit selector。 “编辑”菜单的业务动作名必须始终放在长标题之前，单篇格式为 撤销“动作” · 《截断标题…》 / 重做“动作” · 《截断标题…》 。整批静默文章使用 撤销“批量标为已读” · N 篇 ，不显示任意一篇文章标题。完整 50 项栈不暴露成菜单列表，只展示下一项。 UndoAction.actionName 是菜单动作名， description 用于反馈正文，不要再把完整句子整体截断。 相关页面 快捷键与焦点 ： Cmd+Z / Shift+Cmd+Z 与焦点、动画的关系。 垃圾拦截与审核 ：过滤动作撤销的 forceReplace 与动画时序。 时间线 ：单篇已读退场与批量标已读的撤销语义。 决策日志 ：有界双栈、误分类原子撤销等决策背景。"
 },
 {
  "path": "history/archive/README.html",
  "title": "历史主题归档",
  "headings": [],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史主题归档 这些页面保存旧交接时间线中的原始排查、实验、验证与发布过程。它们是证据库，不是当前操作手册；当前实现以 ../../status/current.md 、对应专题页和 ../decisions.md 为准。 项目基础与产品演进 ：25 个旧章节。 订阅源、缓存与同步 ：20 个旧章节。 翻译、摘要与 AI 过滤 ：17 个旧章节。 文章内容与 HTML 渲染 ：18 个旧章节。 图片、视频与媒体交互 ：12 个旧章节。 性能、滚动与进度 ：11 个旧章节。 时间线与导航 ：16 个旧章节。 列表动画与撤销 ：10 个旧章节。 macOS 桌面框架与快捷键 ：12 个旧章节。 macOS Liquid Glass 重构 ：7 个旧章节。 设置、身份与迁移 ：3 个旧章节。 Android 专项历史 ：3 个旧章节。 发布、Git、Worktree 与 CI ：14 个旧章节。 逐章查找请使用 历史时间索引 。 维护规则： 归档只保存旧证据，不追加当前工作日志；当前结论写入专题页或决策日志。 一个历史章节只保存在一个主主题，跨主题关系使用链接，不复制原文。 单个归档接近 1,000 行时按自然子主题继续拆分，不使用数字文件前缀或机械分卷。 旧章节使用稳定的 legacy-xxx 锚点；移动章节时必须同步更新 ../chronology.md 。"
 },
 {
  "path": "history/archive/ai-translation-and-filtering.html",
  "title": "历史归档：翻译、摘要与 AI 过滤",
  "headings": [
   {
    "id": "10-翻译功能实现v11-新增",
    "text": "10. 翻译功能实现（v1.1 新增）"
   },
   {
    "id": "101-需求确认",
    "text": "10.1 需求确认"
   },
   {
    "id": "102-实现细节",
    "text": "10.2 实现细节"
   },
   {
    "id": "103-工程集成要点",
    "text": "10.3 工程集成要点"
   },
   {
    "id": "104-新增修改文件清单",
    "text": "10.4 新增/修改文件清单"
   },
   {
    "id": "105-测试覆盖",
    "text": "10.5 测试覆盖"
   },
   {
    "id": "106-下一步扩展建议",
    "text": "10.6 下一步扩展建议"
   },
   {
    "id": "21-自动翻译文章拉取时自动处理",
    "text": "21. 自动翻译（文章拉取时自动处理）"
   },
   {
    "id": "211-架构",
    "text": "21.1 架构"
   },
   {
    "id": "212-核心代码",
    "text": "21.2 核心代码"
   },
   {
    "id": "213-集成点",
    "text": "21.3 集成点"
   },
   {
    "id": "214-ui-交互",
    "text": "21.4 UI 交互"
   },
   {
    "id": "215-存储与恢复",
    "text": "21.5 存储与恢复"
   },
   {
    "id": "216-已知限制与改进机会",
    "text": "21.6 已知限制与改进机会"
   },
   {
    "id": "27-翻译中状态提示增强2026-05-18",
    "text": "27. 翻译中状态提示增强（2026-05-18）"
   },
   {
    "id": "271-问题",
    "text": "27.1 问题"
   },
   {
    "id": "272-修复",
    "text": "27.2 修复"
   },
   {
    "id": "273-影响文件",
    "text": "27.3 影响文件"
   },
   {
    "id": "28-摘要长度调整2026-05-18",
    "text": "28. 摘要长度调整（2026-05-18）"
   },
   {
    "id": "281-调整内容",
    "text": "28.1 调整内容"
   },
   {
    "id": "282-影响文件",
    "text": "28.2 影响文件"
   },
   {
    "id": "33-ai-文章过滤系统2026-05-20",
    "text": "33. AI 文章过滤系统（2026-05-20）"
   },
   {
    "id": "331-功能概述",
    "text": "33.1 功能概述"
   },
   {
    "id": "332-影响文件",
    "text": "33.2 影响文件"
   },
   {
    "id": "333-数据流",
    "text": "33.3 数据流"
   },
   {
    "id": "334-关键设计决策",
    "text": "33.4 关键设计决策"
   },
   {
    "id": "34-llm-并发数配置2026-05-20",
    "text": "34. LLM 并发数配置（2026-05-20）"
   },
   {
    "id": "48-审核页重塑-实时状态药片2026-05-23",
    "text": "48. 审核页重塑 — 实时状态药片（2026-05-23）"
   },
   {
    "id": "vivo-originos-桌面角标适配待完成",
    "text": "Vivo / OriginOS 桌面角标适配（待完成）"
   },
   {
    "id": "51-审核界面直接预览-ai-摘要2026-05-23",
    "text": "51. 审核界面直接预览 AI 摘要（2026-05-23）"
   },
   {
    "id": "511-需求背景",
    "text": "51.1 需求背景"
   },
   {
    "id": "512-实现细节",
    "text": "51.2 实现细节"
   },
   {
    "id": "54-译文摘要内容传递修正2026-05-23",
    "text": "54. 译文/摘要内容传递修正（2026-05-23）"
   },
   {
    "id": "56-大文章分块翻译-邮件表格扁平化2026-05-23",
    "text": "56. 大文章分块翻译 + 邮件表格扁平化（2026-05-23）"
   },
   {
    "id": "561-正文规整优化",
    "text": "56.1 正文规整优化"
   },
   {
    "id": "562-分块翻译",
    "text": "56.2 分块翻译"
   },
   {
    "id": "563-pending-瞬态不落盘",
    "text": "56.3 pending 瞬态不落盘"
   },
   {
    "id": "564-未捕获异常兜底",
    "text": "56.4 未捕获异常兜底"
   },
   {
    "id": "100-撤销恢复未读操作丢失-ai-拦截状态修复-2026-06-06",
    "text": "100. 撤销/恢复未读操作丢失 AI 拦截状态修复 (2026-06-06)"
   },
   {
    "id": "1001-需求与问题背景",
    "text": "100.1 需求与问题背景"
   },
   {
    "id": "1002-问题产生原因",
    "text": "100.2 问题产生原因"
   },
   {
    "id": "1003-修复思路与讨论",
    "text": "100.3 修复思路与讨论"
   },
   {
    "id": "1004-副作用评估与平台一致性",
    "text": "100.4 副作用评估与平台一致性"
   },
   {
    "id": "103-审核垃圾拦截页面的即时已读同步修复-2026-06-07",
    "text": "103. 审核/垃圾拦截页面的即时已读同步修复 (2026-06-07)"
   },
   {
    "id": "1031-问题背景",
    "text": "103.1 问题背景"
   },
   {
    "id": "1032-问题根源",
    "text": "103.2 问题根源"
   },
   {
    "id": "1033-修复思路与讨论",
    "text": "103.3 修复思路与讨论"
   },
   {
    "id": "1034-具体实施",
    "text": "103.4 具体实施"
   },
   {
    "id": "105-垃圾拦截页快捷键与全局撤销重构-2026-06-07",
    "text": "105. 垃圾拦截页快捷键与全局撤销重构 (2026-06-07)"
   },
   {
    "id": "1051-需求背景与问题",
    "text": "105.1 需求背景与问题"
   },
   {
    "id": "1052-undoservice-重构",
    "text": "105.2 UndoService 重构"
   },
   {
    "id": "1053-拦截页快捷键注入",
    "text": "105.3 拦截页快捷键注入"
   },
   {
    "id": "1054-留给后续-agent-的防坑记录关于状态擦除的取舍",
    "text": "105.4 留给后续 Agent 的防坑记录：关于状态擦除的取舍"
   },
   {
    "id": "108-垃圾审核页与主时间线快捷键监听冲突修复-2026-06-07",
    "text": "108. 垃圾审核页与主时间线快捷键监听冲突修复 (2026-06-07)"
   },
   {
    "id": "1081-现象与问题诊断",
    "text": "108.1 现象与问题诊断"
   },
   {
    "id": "1082-修复方案讨论与决策",
    "text": "108.2 修复方案讨论与决策"
   },
   {
    "id": "1083-实现细节",
    "text": "108.3 实现细节"
   },
   {
    "id": "117-审核页-ui-按钮与快捷键行为不等效修复2026-06-08",
    "text": "117. 审核页 UI 按钮与快捷键行为不等效修复（2026-06-08）"
   },
   {
    "id": "1171-问题描述",
    "text": "117.1 问题描述"
   },
   {
    "id": "1172-根因分析",
    "text": "117.2 根因分析"
   },
   {
    "id": "1173-修复方案",
    "text": "117.3 修复方案"
   },
   {
    "id": "1174-行为变化对照",
    "text": "117.4 行为变化对照"
   },
   {
    "id": "1175-影响文件",
    "text": "117.5 影响文件"
   },
   {
    "id": "1176-验证",
    "text": "117.6 验证"
   },
   {
    "id": "123-垃圾拦截页移除后不跳转下一篇-焦点丢失修复2026-06-08",
    "text": "123. 垃圾拦截页\"移除\"后不跳转下一篇 & 焦点丢失修复（2026-06-08）"
   },
   {
    "id": "1231-问题现象",
    "text": "123.1 问题现象"
   },
   {
    "id": "1232-根因分析与第-111-节不同",
    "text": "123.2 根因分析（与第 111 节不同）"
   },
   {
    "id": "1233-修改内容",
    "text": "123.3 修改内容"
   },
   {
    "id": "1234-修复原理",
    "text": "123.4 修复原理"
   },
   {
    "id": "1235-影响文件",
    "text": "123.5 影响文件"
   },
   {
    "id": "1236-验收要点",
    "text": "123.6 验收要点"
   },
   {
    "id": "129-翻译与摘要的自动重试机制实现",
    "text": "129. 翻译与摘要的自动重试机制实现"
   },
   {
    "id": "1291-需求背景",
    "text": "129.1 需求背景"
   },
   {
    "id": "1292-架构选择与讨论",
    "text": "129.2 架构选择与讨论"
   },
   {
    "id": "1293-具体修改",
    "text": "129.3 具体修改"
   },
   {
    "id": "1294-注意事项",
    "text": "129.4 注意事项"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：翻译、摘要与 AI 过滤 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 10. 翻译功能实现（v1.1 新增） 10.1 需求确认 触发方式 ：文章卡片长按，弹出菜单选择\"翻译文章\" 翻译服务 ：DeepSeek API（flash 模型，无思考模式） 格式处理 ：全文发送，严格保留 HTML 标签与结构，仅翻译可见文本 目标语言 ：简体中文（默认），留余地支持扩展 已翻译标记 ：卡片上显示语言图标，详情页可切换原文/译文 可逆性 ：支持删除翻译，重新请求翻译 10.2 实现细节 新增文件 lib/services/translation_service.dart 核心翻译 API 调用层 方法： translateArticle(article, targetLang) — 调用 DeepSeek 并缓存结果 recordOf(entryId) / statusOf(entryId) — 读取翻译状态 displayTitleFor(article) — 返回优先使用译名的标题 translatedContentFor(entryId) — 读取已缓存译文 hasTranslation(entryId) — 检查是否已完成翻译 deleteTranslation(entryId) — 删除翻译缓存 setApiKey(key) / getApiKey() — API key 管理 内部处理： HTML 清洁（移除 <html> 包装） 使用 Dio 库，JSON 输出模式请求 DeepSeek flash 翻译结果存储在 GStorage.translations box（Hive） 记录 pending / done / error 状态，供列表卡片和详情页同步显示 存储扩展 lib/utils/storage.dart 新增 translations Box（Hive），压缩策略：30 条删除项触发压缩 存储结构： { 'status': 'done|pending|error', 'translatedTitle': ..., 'translatedContent': ..., 'errorMessage': ..., 'updatedAt': ms } 数据模型与控制器 lib/pages/article/article_page.dart (ArticleController) 新增属性： isTranslated — 是否已翻译（RxBool） translationContent — 翻译后的 HTML（RxString） isTranslating — 翻译进行中（RxBool） showTranslation — 是否显示译文（RxBool） 新增方法： translateArticle() — 触发翻译，包括加载状态管理和错误处理 toggleTranslationDisplay() — 切换原文/译文显示 初始化时检查是否有已缓存翻译，并改为从 TranslationService 的记录中读取译文 UI 增强 lib/pages/article/article_page.dart (ArticlePage) AppBar 增加 PopupMenuButton（已翻译状态下显示）： 切换原文/译文 删除翻译选项 详情页新增翻译控制面板： 未翻译：显示\"翻译文章\"按钮 + 加载进度（可打断） 已翻译：显示切换条、翻译/原文标记、操作菜单 正文部分用 Obx 响应 showTranslation 变化，动态显示原/译内容 lib/pages/widgets/article_card.dart 长按菜单直接调用 TranslationService.translateArticle() ，不再依赖父组件回调 卡片标题优先使用译名；翻译请求中显示旋转加载图标，避免看完后忘记是否已请求 已完成翻译时显示语言图标 长按菜单（BottomSheet）： \"翻译文章\" / \"重新翻译\"（根据翻译状态切换） 已翻译时额外显示\"删除翻译\" 列表与详情页都通过 RxMap 订阅翻译状态，能即时重绘 lib/pages/settings/settings_page.dart 新增\"翻译服务设置\"区块（在 Folo API 认证后） DeepSeek API Key 输入框 + 显示/隐藏切换 保存/清除按钮集成（与 Token 一起保存） Key 存储在 GStorage.setting['deepseek_api_key'] 10.3 工程集成要点 网络请求 Dio 实例化在 TranslationService 内部，避免全局依赖 API 基础 URL： https://api.deepseek.com 模型： deepseek-v4-flash （官方推荐用 flash 而非 pro，成本低） 错误处理 API 返回 200 但无 choices → 返回 null，UI 显示\"翻译失败\" API key 未配置 → 抛异常，SnackBar 提示配置 网络超时/异常 → 捕获后显示具体错误信息 性能考虑 翻译结果永久存储（Hive） 防止重复翻译： hasTranslation() 检查 列表卡片通过 RxMap 响应状态变化，避免轮询 已读状态回填 首页时间线与订阅源详情页已改为：未读列表全量拉取，已读列表后台按时间窗口静默补抓。 本地会用未读快照做收敛，避免只同步第一页已读列表导致旧文章长期停留在未读视图中。 已读补抓窗口可在设置里调整，默认 2 天。 品牌统一 应用名已统一为 autofolo 启动器图标源文件保存在 assets/branding/autofolo.jpg Android 启动器图标已更新为由该图片生成的 mipmap 资源 译文默认展示 已翻译文章进入详情页时默认进入译文视图 标题会优先显示翻译后的标题，正文直接展示翻译后的 HTML HTML 格式保证 TranslationService 接收的是已规范化的 HTML（ArticleContentUtils.normalizeHtml） API prompt 明确要求保留标签结构，仅翻译文本 响应后移除 <html> wrapper 10.4 新增/修改文件清单 新增 lib/services/translation_service.dart 修改 lib/utils/storage.dart — 添加 translations box lib/pages/article/article_page.dart — 添加翻译逻辑 + UI lib/pages/widgets/article_card.dart — 长按菜单 + 翻译标记 lib/pages/settings/settings_page.dart "
 },
 {
  "path": "history/archive/android.html",
  "title": "历史归档：Android 专项历史",
  "headings": [
   {
    "id": "82-android-安装签名冲突与-v113-修复2026-06-02",
    "text": "82. Android 安装签名冲突与 v1.1.3 修复（2026-06-02）"
   },
   {
    "id": "821-用户遇到的问题",
    "text": "82.1 用户遇到的问题"
   },
   {
    "id": "822-为什么之前会签名不同",
    "text": "82.2 为什么之前会签名不同"
   },
   {
    "id": "823-用户确认的修复策略",
    "text": "82.3 用户确认的修复策略"
   },
   {
    "id": "824-代码修复",
    "text": "82.4 代码修复"
   },
   {
    "id": "825-本地验证",
    "text": "82.5 本地验证"
   },
   {
    "id": "826-v113-发布预期",
    "text": "82.6 v1.1.3 发布预期"
   },
   {
    "id": "827-v113-远端发布结果",
    "text": "82.7 v1.1.3 远端发布结果"
   },
   {
    "id": "83-android-时间线灰屏修复与-v114-发布2026-06-02",
    "text": "83. Android 时间线灰屏修复与 v1.1.4 发布（2026-06-02）"
   },
   {
    "id": "831-用户反馈",
    "text": "83.1 用户反馈"
   },
   {
    "id": "832-排查结论",
    "text": "83.2 排查结论"
   },
   {
    "id": "833-修复内容",
    "text": "83.3 修复内容"
   },
   {
    "id": "834-版本策略",
    "text": "83.4 版本策略"
   },
   {
    "id": "835-本地验证",
    "text": "83.5 本地验证"
   },
   {
    "id": "836-github-actions-发布结果",
    "text": "83.6 GitHub Actions 发布结果"
   },
   {
    "id": "84-安卓端主时间线及垃圾拦截页灰屏彻底修复-2026-06-02",
    "text": "84. 安卓端主时间线及垃圾拦截页灰屏彻底修复 (2026-06-02)"
   },
   {
    "id": "841-问题复盘",
    "text": "84.1 问题复盘"
   },
   {
    "id": "842-根本原因分析",
    "text": "84.2 根本原因分析"
   },
   {
    "id": "843-修复方案与讨论过程",
    "text": "84.3 修复方案与讨论过程"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：Android 专项历史 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 82. Android 安装签名冲突与 v1.1.3 修复（2026-06-02） 82.1 用户遇到的问题 用户安装 v1.1.2 Android APK 时，系统提示： 应用未安装：软件包与现有软件包存在冲突 安装包的开发者签名有异常，建议清除同包名的数据或联系开发者 根本原因不是版本号不够高，而是 Android 覆盖安装要求： applicationId 相同：当前是 com.folo.folo_reader 签名证书也必须相同 versionCode 更高只在“包名相同且签名相同”时才决定是否可升级 如果包名相同但签名不同，Android 会直接拒绝覆盖安装。这是安全机制，防止任意 APK 用相同包名和更高版本号接管旧应用数据。 82.2 为什么之前会签名不同 检查 android/app/build.gradle.kts 后发现，本项目之前的 release 构建实际使用了 debug 签名： signingConfig = signingConfigs.getByName(\"debug\") debug keystore 通常与构建环境相关：本机构建和 GitHub Actions runner 可能使用不同证书。换机器、删掉本地调试 keystore、换 runner，都可能导致签名不同。 因此用户本机 flutter run 安装的包和 GitHub Actions 构建的 release APK 可能同包名但签名不同，从而无法覆盖安装。 82.3 用户确认的修复策略 用户基本只自用，并确认目前只通过“本机”和“GitHub Actions”两种方式安装/打包过。经过讨论后，采用固定 Android 内部测试签名材料，并通过 GitHub Secrets 提供给 CI；签名材料、别名、口令、证书指纹等敏感细节不得写入仓库文档。 GitHub Actions 使用的 Secrets 项目名保留在 workflow 中；本文档只记录策略，不记录 secret 值、key 指纹或本机 keystore 路径。 注意： GitHub Secrets 不进入 Git 仓库，不会被 git clone 、源码包、tag 或 Release 资产直接包含。 但 Actions 运行时可以使用这把 key 签 APK，因此它仍然是“把签名能力交给 GitHub Actions 环境”。 用户已明确同意将固定内部测试签名材料配置到 GitHub Secrets。 82.4 代码修复 修改文件： .gitignore 忽略 android/key.properties 忽略 android/app/*.jks 忽略 android/app/*.keystore android/app/build.gradle.kts 支持读取 android/key.properties 如果存在固定 keystore 配置，release build 使用 signingConfigs.release 如果本地没有 android/key.properties ，仍 fallback 到 debug signing，保证普通本地开发命令可运行 .github/workflows/internal-release.yml Android job 在 flutter build apk --release 前新增 Configure Android signing 从 GitHub Secrets 还原 android/app/upload-keystore.jks 生成 android/key.properties 若任一 secret 缺失，CI 直接失败，避免再次发布不稳定签名 APK 82.5 本地验证 已在本机生成被 .gitignore 忽略的签名配置文件： android/key.properties android/app/upload-keystore.jks 本地验证命令： dart analyze lib test flutter build apk --release --no-pub <android-sdk>/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk 验证结果： dart analyze lib test ：通过 flutter build apk --release --no-pub ：通过 apksigner verify --print-certs ：通过，并确认 APK 使用预期的固定内部测试签名证书。证书指纹不记录在仓库文档中。 82.6 v1.1.3 发布预期 版本计划： pubspec.yaml ： 1.1.3+5 X-App-Version ： 1.1.3 设置页关于版本： Auto Folo v1.1.3 tag： v1.1.3 安装预期： 如果手机当前安装包来自同一套固定内部测试签名，则 v1.1.3 GitHub APK 应该可以直接覆盖安装。 如果手机当前安装包来自旧 GitHub Actions runner 的 debug key，则仍会签名冲突，需要卸载一次。 一旦成功安装 v1.1.3 ，之后 GitHub Actions 发布的 APK 只要继续使用这套 secrets，就应能正常覆盖升级。 82.7 v1.1.3 远端发布结果 tag： v1.1.3 结果： Android APK 、 macOS App 、 Publish GitHub Release 全部通过。 Release URL： GitHub Release v1.1.3 Release assets： Auto-Folo-android-v1.1.3.apk 已下载到被 Git 忽略的临时目录并用 apksigner verify --print-certs 验证签名 确认 APK 使用预期的固定内部测试签名证书；证书指纹不记录在仓库文档中 Auto-Folo-macOS-arm64-v1.1.3.zip 结论： v1.1.3 GitHub Android APK 已确认使用固定内部测试签名。若用户手机上现有安装包来自同一签名，应可直接覆盖安装；若仍报签名冲突，说明手机上现有包来自另一把签名，需要卸载一次后再装。 83. Android 时间线灰屏修复与 v1.1.4 发布（2026-06-02） 2026-06-03 校准：本节记录的是第一次 Android 灰屏排查、缓存读取加固和 v1.1.4 发布过程；后续第 84 节进一步确认了“主时间线/垃圾拦截页灰屏”"
 },
 {
  "path": "history/archive/article-content-and-html.html",
  "title": "历史归档：文章内容与 HTML 渲染",
  "headings": [
   {
    "id": "19-html-渲染性能重构v15",
    "text": "19. HTML 渲染性能重构（v1.5）"
   },
   {
    "id": "191-问题诊断",
    "text": "19.1 问题诊断"
   },
   {
    "id": "192-重构方案六项策略",
    "text": "19.2 重构方案：六项策略"
   },
   {
    "id": "193-渲染组件",
    "text": "19.3 渲染组件"
   },
   {
    "id": "194-架构变化",
    "text": "19.4 架构变化"
   },
   {
    "id": "195-新增修改文件清单",
    "text": "19.5 新增/修改文件清单"
   },
   {
    "id": "31-html-渲染管线修复2026-05-19",
    "text": "31. HTML 渲染管线修复（2026-05-19）"
   },
   {
    "id": "311-bug-1-🔴标题内图片媒体被吞掉",
    "text": "31.1 BUG-1 🔴：标题内图片/媒体被吞掉"
   },
   {
    "id": "312-bug-2-🟡空标题产生多余空白间距",
    "text": "31.2 BUG-2 🟡：空标题产生多余空白间距"
   },
   {
    "id": "313-bug-3-🟡图片-css-百分比宽度误解析为-px",
    "text": "31.3 BUG-3 🟡：图片 CSS 百分比宽度误解析为 px"
   },
   {
    "id": "314-附带修复未知元素不再丢弃媒体",
    "text": "31.4 附带修复：未知元素不再丢弃媒体"
   },
   {
    "id": "315-影响文件",
    "text": "31.5 影响文件"
   },
   {
    "id": "316-图片渲染完善补充修复",
    "text": "31.6 图片渲染完善（补充修复）"
   },
   {
    "id": "53-正文加载-数据持久化2026-05-23",
    "text": "53. 正文加载 + 数据持久化（2026-05-23）"
   },
   {
    "id": "58-取消文章正文懒加载与重置列表增量刷新-2026-05-24",
    "text": "58. 取消文章正文懒加载与重置列表增量刷新 (2026-05-24)"
   },
   {
    "id": "581-文章阅读进度条精准度优先-取消懒加载",
    "text": "58.1 文章阅读进度条精准度优先 (取消懒加载)"
   },
   {
    "id": "582-feeddetail-已读-o1-增量优化回退",
    "text": "58.2 FeedDetail 已读 O(1) 增量优化回退"
   },
   {
    "id": "583-正文-dom-懒加载设置开关",
    "text": "58.3 正文 DOM 懒加载设置开关"
   },
   {
    "id": "60-深色模式-html-字体对比度动态调整-2026-05-25",
    "text": "60. 深色模式 HTML 字体对比度动态调整 (2026-05-25)"
   },
   {
    "id": "601-问题背景",
    "text": "60.1 问题背景"
   },
   {
    "id": "602-核心实现",
    "text": "60.2 核心实现"
   },
   {
    "id": "64-恢复消失的表格与通用图文排版重构2026-05-26",
    "text": "64. 恢复消失的表格与通用图文排版重构（2026-05-26）"
   },
   {
    "id": "641-修复背景与现象",
    "text": "64.1 修复背景与现象"
   },
   {
    "id": "642-诊断过程与核心思路",
    "text": "64.2 诊断过程与核心思路"
   },
   {
    "id": "643-变更细节",
    "text": "64.3 变更细节"
   },
   {
    "id": "65-修复-html-块内链接无法点击的问题2026-05-26",
    "text": "65. 修复 HTML 块内链接无法点击的问题（2026-05-26）"
   },
   {
    "id": "651-问题背景",
    "text": "65.1 问题背景"
   },
   {
    "id": "652-根因分析",
    "text": "65.2 根因分析"
   },
   {
    "id": "653-修复方案",
    "text": "65.3 修复方案"
   },
   {
    "id": "654-影响文件",
    "text": "65.4 影响文件"
   },
   {
    "id": "73-长文阅读页自适应虚拟渲染2026-05-31",
    "text": "73. 长文阅读页自适应虚拟渲染（2026-05-31）"
   },
   {
    "id": "731-背景",
    "text": "73.1 背景"
   },
   {
    "id": "732-本次决策",
    "text": "73.2 本次决策"
   },
   {
    "id": "733-进度条策略",
    "text": "73.3 进度条策略"
   },
   {
    "id": "734-影响文件",
    "text": "73.4 影响文件"
   },
   {
    "id": "735-验收要点",
    "text": "73.5 验收要点"
   },
   {
    "id": "87-行内代码排版与渲染重构-2026-06-05",
    "text": "87. 行内代码排版与渲染重构 (2026-06-05)"
   },
   {
    "id": "871-问题反馈",
    "text": "87.1 问题反馈"
   },
   {
    "id": "872-问题诊断",
    "text": "87.2 问题诊断"
   },
   {
    "id": "873-修复思路与实施",
    "text": "87.3 修复思路与实施"
   },
   {
    "id": "89-纯文本-url-的自动识别与可点击化-2026-06-05",
    "text": "89. 纯文本 URL 的自动识别与可点击化 (2026-06-05)"
   },
   {
    "id": "891-背景与问题",
    "text": "89.1 背景与问题"
   },
   {
    "id": "892-技术选型与权衡",
    "text": "89.2 技术选型与权衡"
   },
   {
    "id": "893-具体实现细节",
    "text": "89.3 具体实现细节"
   },
   {
    "id": "894-给后续接手-agent-的提醒",
    "text": "89.4 给后续接手 Agent 的提醒"
   },
   {
    "id": "102-优化文章行内代码样式-2026-06-07",
    "text": "102. 优化文章行内代码样式 (2026-06-07)"
   },
   {
    "id": "1021-问题描述",
    "text": "102.1 问题描述"
   },
   {
    "id": "1022-根本原因",
    "text": "102.2 根本原因"
   },
   {
    "id": "1023-修复思路与实现",
    "text": "102.3 修复思路与实现"
   },
   {
    "id": "107-行内代码文本基线向上浮动问题修复-2026-06-07",
    "text": "107. 行内代码文本基线向上浮动问题修复 (2026-06-07)"
   },
   {
    "id": "1071-问题描述",
    "text": "107.1 问题描述"
   },
   {
    "id": "1072-原因分析",
    "text": "107.2 原因分析"
   },
   {
    "id": "1073-修复方案与讨论",
    "text": "107.3 修复方案与讨论"
   },
   {
    "id": "121-行内代码文本基线对齐彻底修复-2026-06-08",
    "text": "121. 行内代码文本基线对齐彻底修复 (2026-06-08)"
   },
   {
    "id": "1211-问题背景",
    "text": "121.1 问题背景"
   },
   {
    "id": "1212-历史修复回顾",
    "text": "121.2 历史修复回顾"
   },
   {
    "id": "1213-根因分析",
    "text": "121.3 根因分析"
   },
   {
    "id": "1214-修复方案讨论",
    "text": "121.4 修复方案讨论"
   },
   {
    "id": "1215-性能评估",
    "text": "121.5 性能评估"
   },
   {
    "id": "1216-影响范围评估",
    "text": "121.6 影响范围评估"
   },
   {
    "id": "1217-实现细节",
    "text": "121.7 实现细节"
   },
   {
    "id": "1218-验证",
    "text": "121.8 验证"
   },
   {
    "id": "122-macos-文章正文超链接交互反馈悬停光标-底部-url-预览2026-06-08",
    "text": "122. macOS 文章正文超链接交互反馈（悬停光标 + 底部 URL 预览）(2026-06-08)"
   },
   {
    "id": "1221-需求背景",
    "text": "122.1 需求背景"
   },
   {
    "id": "1222-技术调研与方案讨论",
    "text": "122.2 技术调研与方案讨论"
   },
   {
    "id": "1223-实现细节",
    "text": "122.3 实现细节"
   },
   {
    "id": "1224-关键决策与边界说明",
    "text": "122.4 关键决策与边界说明"
   },
   {
    "id": "1225-验证",
    "text": "122.5 验证"
   },
   {
    "id": "130-文章内联链接-hover-样式优化-2026-06-10",
    "text": "130. 文章内联链接 Hover 样式优化 (2026-06-10)"
   },
   {
    "id": "1301-需求背景与原始诉求",
    "text": "130.1 需求背景与原始诉求"
   },
   {
    "id": "1302-技术方案探讨与取舍关键上下文",
    "text": "130.2 技术方案探讨与取舍（关键上下文）"
   },
   {
    "id": "1303-最终实现方案",
    "text": "130.3 最终实现方案"
   },
   {
    "id": "153-文章正文表格与空代码块保守修复2026-06-30",
    "text": "153. 文章正文表格与空代码块保守修复（2026-06-30）"
   },
   {
    "id": "161-macos-正文底部留白与纯文本-html-entity-解码2026-07-07",
    "text": "161. macOS 正文底部留白与纯文本 HTML entity 解码（2026-07-07）"
   },
   {
    "id": "1611-macos-文章详情底部留白",
    "text": "161.1 macOS 文章详情底部留白"
   },
   {
    "id": "1612-普通文本字段显示-amp-等-html-entity",
    "text": "161.2 普通文本字段显示 &amp; 等 HTML entity"
   },
   {
    "id": "163-文章详情状态与正文渲染细节修复2026-07-07",
    "text": "163. 文章详情状态与正文渲染细节修复（2026-07-07）"
   },
   {
    "id": "1631-摘要按钮-pending-状态修复",
    "text": "163.1 摘要按钮 pending 状态修复"
   },
   {
    "id": "1632-macos-图片-hover-行为调整",
    "text": "163.2 macOS 图片 hover 行为调整"
   },
   {
    "id": "1633-宽表格四角被裁剪修复",
    "text": "163.3 宽表格四角被裁剪修复"
   },
   {
    "id": "1634-验证结果与后续验证重点",
    "text": "163.4 验证结果与后续验证重点"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：文章内容与 HTML 渲染 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 19. HTML 渲染性能重构（v1.5） 19.1 问题诊断 文章详情页使用 SingleChildScrollView + 单个 flutter_html Html widget 渲染整篇 HTML，导致： Widget 树一次性构建数百个节点，首帧卡顿 滚动时整棵 widget 树重绘，帧率降至 30-40fps 图片异步加载完成触发 Reflow，布局抖动严重 <iframe> <video> 等 Platform View 在列表中引发崩溃 19.2 重构方案：六项策略 策略 1：DOM 拆块 + SliverList 懒加载（核心） 新增 lib/utils/html_chunk_parser.dart 使用 html 包解析 DOM，按块级元素切分为 List<HtmlChunk> 支持的块类型：标题 <h1>-<h6> 、段落 <p> 、图片 <img> 、代码块 <pre> 、引用 <blockquote> 、表格 <table> 、列表 <ul>/<ol> 、分割线 <hr> 、iframe/视频占位 相邻纯文本段落自动合并，减少 widget 数量 article_page.dart 改用 CustomScrollView + SliverList.builder ，仅构建视窗内可见 chunk 策略 2：预设图片尺寸防布局抖动 HtmlChunkParser._extractDimensions() 从 width / height 属性 + CSS style 中提取图片宽高 HtmlChunkCard 图片渲染使用 AspectRatio 占位，加载前显示静态颜色块，加载后不撑开父容器 无尺寸信息时默认 16:9 策略 3：RepaintBoundary 隔离 每个 HtmlChunkCard 外层包裹 RepaintBoundary 独立绘制图层，滚动时静态 DOM 节点不参与重绘 策略 4：iframe/Video 降级 <iframe> <video> <audio> 解析为 HtmlChunkType.iframeVideo 渲染为 \"静态封面 + 播放/浏览器图标\" 占位卡片 点击用 url_launcher 唤起外部浏览器 策略 5：Isolate 异步解析 HtmlChunkParser.parse() — HTML > 500KB 自动切 Isolate.run() 后台解析 小文本主线程同步解析（< 50ms） 同时提供 parseSync() 供需要同步结果的场景 策略 6：译文块独立解析 翻译完成后同步解析译文为 translatedChunks 切换原文/译文时 SliverList 无缝切换数据源 Obx 响应式驱动，无需重建整个页面 19.3 渲染组件 新增 lib/pages/article/widgets/html_chunk_card.dart ： 每种 HtmlChunkType 对应独立渲染方法 段落使用轻量 flutter_html （仅渲染内联标签 <a> <strong> <em> <code> ） 代码块：水平滚动 + 等宽字体 表格：水平滚动 + flutter_html 表格样式 列表：手动构建 Row + 序号/圆点 图片： AspectRatio + CachedNetworkImage （含 memCacheHeight 限制） 19.4 架构变化 Before (jank): SingleChildScrollView Column Html(data: ALL_HTML) ← 数百节点一次性构建 After (60fps): CustomScrollView SliverToBoxAdapter(title, metadata, buttons) SliverList.builder [HtmlChunkCard × N] ← 仅构建可见区域 ↳ RepaintBoundary ↳ 标题 | 段落 | 图片(AspectRatio) | 代码 | ... 19.5 新增/修改文件清单 lib/utils/html_chunk_parser.dart — 新建 lib/pages/article/widgets/html_chunk_card.dart — 新建 lib/pages/article/article_page.dart — 重写（SingleChildScrollView → CustomScrollView + SliverList） 31. HTML 渲染管线修复（2026-05-19） 经过对 13 篇真实 Folo 文章的管线实测，发现并修复了 3 个渲染 BUG。 31.1 BUG-1 🔴：标题内图片/媒体被吞掉 根因 ： _processElement 对 <h1>-<h6> 直接调 _stripInnerHtml 剥离所有 HTML 标签。 影响 ：实测中 6/13 篇文章丢失图片（新智元 86 张仅剩 33 张，少数派 7 张剩 5 张）。 修复 ： 新增 _hasMediaDescendant() — 递归检测是否有媒体子节点 新增 _headingTextOnly() — 从含媒体的标题中仅提取文本 新增 _emitMediaChildren() — 对标题仅发媒体块（文本已在标题中） 标题有媒体 → 先发标题文本块，再递归发媒体块 31.2 BUG-2 🟡：空标题产生多余空白间距 根因 ： <h3><span><br></span></h3> （微信公众号做分隔线）剥离后为空字符串，仍渲染为标题块。 影响 ：新智元文章出现 14 处无意义大间距。 修复 ：标题文本 trim 后为空 → return 跳过不发块。 31.3 BUG-3 🟡：图片 CSS 百分比宽度误解析为 px 根因 ： _extractDimensions 正则 width:\\s*(\\d+)\\s*(px|em|rem)? 不区分 % 单位， 100% → 100px。 影响 ：微信来源文章图片 style=\"width:100%\" 被当作 100px 处理，但实际无高度，仍无法确定比例。 修复 ：正则增加 %|vw|vh 单位匹配；百分比/视口单位 → 宽/高保持 null 交给渲染层 fallback（ AspectRatio ）。 31.4 附带修复：未知元素不再丢弃媒体 根因 ： <a><img></a> 等内联容器未被识别， _processElement 末尾只提取文本导致 <img> 丢失。 修复 ：未知元素改为递归子节点，而非仅提取文本。 31.5 影响文件 lib/utils/html_chunk_parser."
 },
 {
  "path": "history/archive/foundation-and-product.html",
  "title": "历史归档：项目基础与产品演进",
  "headings": [
   {
    "id": "原交接归档前言",
    "text": "原交接归档前言"
   },
   {
    "id": "项目速览",
    "text": "项目速览"
   },
   {
    "id": "关键约定",
    "text": "关键约定"
   },
   {
    "id": "1-用户要求原始上下文",
    "text": "1. 用户要求（原始上下文）"
   },
   {
    "id": "2-关键发现代码审查结论",
    "text": "2. 关键发现（代码审查结论）"
   },
   {
    "id": "21-原版本的主要短板",
    "text": "2.1 原版本的主要短板"
   },
   {
    "id": "22-参考方向piliplus",
    "text": "2.2 参考方向（PiliPlus）"
   },
   {
    "id": "3-已完成改动本轮",
    "text": "3. 已完成改动（本轮）"
   },
   {
    "id": "31-体验与功能增强",
    "text": "3.1 体验与功能增强"
   },
   {
    "id": "32-稳定性与工程质量提升",
    "text": "3.2 稳定性与工程质量提升"
   },
   {
    "id": "4-本轮新增修改文件清单",
    "text": "4. 本轮新增/修改文件清单"
   },
   {
    "id": "新增",
    "text": "新增"
   },
   {
    "id": "修改",
    "text": "修改"
   },
   {
    "id": "5-仍待继续对标完善的方向下一位-agent-可直接执行",
    "text": "5. 仍待继续对标完善的方向（下一位 agent 可直接执行）"
   },
   {
    "id": "6-接手建议最短路径",
    "text": "6. 接手建议（最短路径）"
   },
   {
    "id": "7-本轮追加优化2026-05-16-晚",
    "text": "7. 本轮追加优化（2026-05-16 晚）"
   },
   {
    "id": "8-本轮追加优化本地文章库",
    "text": "8. 本轮追加优化（本地文章库）"
   },
   {
    "id": "9-本轮追加优化图片加载稳定性",
    "text": "9. 本轮追加优化（图片加载稳定性）"
   },
   {
    "id": "13-对标参考工程的细节优化v13",
    "text": "13. 对标参考工程的细节优化（v1.3）"
   },
   {
    "id": "131-发现与改进",
    "text": "13.1 发现与改进"
   },
   {
    "id": "132-其他参考工程的细节暂不改",
    "text": "13.2 其他参考工程的细节（暂不改）"
   },
   {
    "id": "133-修改文件清单",
    "text": "13.3 修改文件清单"
   },
   {
    "id": "15-应用退出行为优化与桌面角标配置-v16",
    "text": "15. 应用退出行为优化与桌面角标配置 (v1.6)"
   },
   {
    "id": "151-需求",
    "text": "15.1 需求"
   },
   {
    "id": "152-实现",
    "text": "15.2 实现"
   },
   {
    "id": "153-注意事项",
    "text": "15.3 注意事项"
   },
   {
    "id": "18-轻量提示统一2026-05-17",
    "text": "18. 轻量提示统一（2026-05-17）"
   },
   {
    "id": "181-需求",
    "text": "18.1 需求"
   },
   {
    "id": "182-实现",
    "text": "18.2 实现"
   },
   {
    "id": "183-注意事项",
    "text": "18.3 注意事项"
   },
   {
    "id": "工程状态总结截至-2026-05-20",
    "text": "工程状态总结（截至 2026-05-20）"
   },
   {
    "id": "文件结构",
    "text": "文件结构"
   },
   {
    "id": "服务层清单",
    "text": "服务层清单"
   },
   {
    "id": "核心数据流",
    "text": "核心数据流"
   },
   {
    "id": "articlemodel-字段核心字段早期记录为-18-个",
    "text": "ArticleModel 字段（核心字段，早期记录为 18 个）"
   },
   {
    "id": "22-仓库完整性巡检与修复2026-05-18",
    "text": "22. 仓库完整性巡检与修复（2026-05-18）"
   },
   {
    "id": "221-巡检结论",
    "text": "22.1 巡检结论"
   },
   {
    "id": "222-本次已修复问题",
    "text": "22.2 本次已修复问题"
   },
   {
    "id": "223-当前建议执行命令",
    "text": "22.3 当前建议执行命令"
   },
   {
    "id": "23-主页面双标题修复2026-05-18",
    "text": "23. 主页面双标题修复（2026-05-18）"
   },
   {
    "id": "231-问题",
    "text": "23.1 问题"
   },
   {
    "id": "232-修复",
    "text": "23.2 修复"
   },
   {
    "id": "233-影响文件",
    "text": "23.3 影响文件"
   },
   {
    "id": "30-已知待修问题2026-05-19-全库审查",
    "text": "30. 已知待修问题（2026-05-19 全库审查）"
   },
   {
    "id": "1-🟡-loadmore-翻页只拉-feeds不追加-socialinbox",
    "text": "#1 🟡 loadMore() 翻页只拉 feeds，不追加 social/inbox"
   },
   {
    "id": "2-🟡-loaddata-feeds-拉取失败时静默返回",
    "text": "#2 🟡 loadData() feeds 拉取失败时静默返回"
   },
   {
    "id": "3-🟢-storagekeys-缺少-deepseek_api_key-常量",
    "text": "#3 🟢 StorageKeys 缺少 deepseek_api_key 常量"
   },
   {
    "id": "4-🟢-articlecard_istranslated-死代码",
    "text": "#4 🟢 ArticleCard._isTranslated 死代码"
   },
   {
    "id": "5-🟢-htmlchunkparser_extractsrc-双重-url-规范化",
    "text": "#5 🟢 HtmlChunkParser._extractSrc 双重 URL 规范化"
   },
   {
    "id": "37-其他杂项修复2026-05-20",
    "text": "37. 其他杂项修复（2026-05-20）"
   },
   {
    "id": "45-ui-全面美化2026-05-21手动修订",
    "text": "45. UI 全面美化（2026-05-21，手动修订）"
   },
   {
    "id": "配色体系重构",
    "text": "配色体系重构"
   },
   {
    "id": "时间线过滤入口重设计",
    "text": "时间线过滤入口重设计"
   },
   {
    "id": "文章详情页重构",
    "text": "文章详情页重构"
   },
   {
    "id": "文章卡片重设计",
    "text": "文章卡片重设计"
   },
   {
    "id": "图片组件打磨",
    "text": "图片组件打磨"
   },
   {
    "id": "订阅源页重构",
    "text": "订阅源页重构"
   },
   {
    "id": "feeddetail-页重构",
    "text": "FeedDetail 页重构"
   },
   {
    "id": "过滤审核页打磨",
    "text": "过滤审核页打磨"
   },
   {
    "id": "反馈系统重构",
    "text": "反馈系统重构"
   },
   {
    "id": "55-ui-细节打磨2026-05-23",
    "text": "55. UI 细节打磨（2026-05-23）"
   },
   {
    "id": "59-遗留问题与已知缺陷-2026-05-24",
    "text": "59. 遗留问题与已知缺陷 (2026-05-24)"
   },
   {
    "id": "591-特定长文复杂排版文章卡顿问题",
    "text": "59.1 特定长文/复杂排版文章卡顿问题"
   },
   {
    "id": "61-遗留问题与已知缺陷-2026-05-25",
    "text": "61. 遗留问题与已知缺陷 (2026-05-25)"
   },
   {
    "id": "611-审核列表快速刷新导致被拒文章复活问题",
    "text": "61.1 审核列表快速刷新导致被拒文章“复活”问题"
   },
   {
    "id": "72-未来功能规划-future-features",
    "text": "72. 未来功能规划 (Future Features)"
   },
   {
    "id": "721-后台静默刷新通知角标-background-badge-sync",
    "text": "72.1 后台静默刷新通知角标 (Background Badge Sync)"
   },
   {
    "id": "85-macos-桌面端-ui-细节精简与占位符统一补记于-2026-06-03",
    "text": "85. macOS 桌面端 UI 细节精简与占位符统一（补记于 2026-06-03）"
   },
   {
    "id": "851-需求与起因",
    "text": "85.1 需求与起因"
   },
   {
    "id": "852-排查与实现",
    "text": "85.2 排查与实现"
   },
   {
    "id": "853-后续建议",
    "text": "85.3 后续建议"
   },
   {
    "id": "86-ui-精简实验与设计理念记录补记于-2026-06-03",
    "text": "86. UI 精简实验与设计理念记录（补记于 2026-06-03）"
   },
   {
    "id": "861-遗留的体验问题待完善但不构成-bug",
    "text": "86.1 遗留的体验问题（待完善但不构成 Bug）"
   },
   {
    "id": "862-垃圾拦截与未读数设计理念防退化记录",
    "text": "86.2 垃圾拦截与未读数设计理念（防退化记录）"
   },
   {
    "id": "863-侧边栏折叠按钮的实验性隐藏",
    "text": "86.3 侧边栏折叠按钮的实验性隐藏"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：项目基础与产品演进 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 原交接归档前言 快速上手 ：Flutter 3.x + GetX + Hive + Dio 项目。入口 lib/main.dart ，路由 lib/router/app_pages.dart 。 当前产品名统一为 Auto Folo ；Dart package 名仍是 autofolo 。验证优先使用 flutter analyze 与 flutter test ，不要用裸 dart analyze lib/ 判断 Flutter 项目健康度。 当前应用标识已迁移为 io.github.xraygit.autofolo （Android applicationId/namespace、macOS bundle id、MethodChannel 命名空间）。历史章节中的 com.folo.* / com.autofolo 仅为旧记录，不能再作为当前实现依据。 常用构建： flutter build apk --debug 、 flutter build macos --debug 。内部发布走 tag 触发的 GitHub Actions，详见第 80 节；macOS 发布包必须保持 arm64。 项目速览 工程目标 ：构建高密度、低摩擦的 Folo RSS 阅读器，兼顾 Android 移动端与 macOS 分栏阅读体验。 维度 详情 框架 Flutter 3.x, Dart 3.11+ 状态管理 GetX (Obx, Rx, GetBuilder) 本地存储 Hive (articleDb, setting, localCache, readStatus, translations, summaries) 网络 Dio (Folo API + DeepSeek API) 路由 GetX (5 条: main, article, feed-detail, settings, filter-review) API api.folo.is (Cookie + X-Client-Id + X-Session-Id 认证) LLM api.deepseek.com (Bearer Token) 依赖 cached_network_image, share_plus, video_player, image_gallery_saver_plus, 等 关键约定 ArticleModel 的 isRejectedByAi / filterReason / filterReviewed 不可在 upsertMany 合并时丢失 Hive box 写入是同步的， box.get 立即读到最新值 图片加载过 Folo 代理： ArticleImageService.toProxiedUrl() 邮件 HTML 检测： tableCount > 5 && tableCount > divCount * 2 LlmConfig 三组独立：翻译(flash/T0.2/128K) 摘要(pro/think/T0.2/2K) 过滤(pro/T0.1/2K) 安全与隐私 ：临时测试脚本、抓取的真实 JSON/HTML 数据等，请务必放在 scratch/ 目录下（该目录包含一个 .gitkeep 占位符）。该目录已被 .gitignore 忽略，以防止含有真实 Token 或用户订阅数据的隐私信息被意外提交至版本库。 1. 用户要求（原始上下文） 当前版本“太简陋”，希望尽快修补。 优先参考 reference/PiliPlus （高成熟度范例）。 需要完整交接文档：让下一个不了解上下文的 agent 到项目目录后可立即接手。 后续澄清：这里的“漏洞”主要指 界面不完善、功能欠缺、体验粗糙 ，不是仅限安全漏洞。 最新要求：尽可能对标范例， 全方位提升用户体验与成熟度 。 2. 关键发现（代码审查结论） 2.1 原版本的主要短板 功能缺口 主页面搜索按钮是 TODO（无实际功能）。 分类详情页筛选依赖 subscriptionCategory ，但数据请求时未注入 feedMap ，导致分类筛选不准确。 已读状态只在本地零散处理，缺少可控的云端同步队列。 体验问题 登录前直接请求接口，用户看到的是网络/接口错误，而不是明确引导。 订阅列表缺少搜索能力，大量订阅时难用。 外链处理未做协议白名单，失败反馈弱。 工程完整度问题 默认 widget_test.dart 仍是模板测试（引用不存在的 MyApp ），测试体系不可用。 README 仍是 Flutter 模板文本，缺少当前项目信息（待后续补）。 2.2 参考方向（PiliPlus） 对标重点不是逐行抄实现，而是吸收成熟产品思路： 网络层要有更稳健的错误处理与返回结构兜底。 页面应避免“空功能入口”（例如按钮存在但无功能）。 交互上要有明确反馈（同步结果、输入校验、失败原因）。 3. 已完成改动（本轮） 3.1 体验与功能增强 时间线：已读同步能力补齐 新增 ReadSyncService （本地待同步队列管理）。 当前策略：仅在文章详情页点击悬浮“标为已读”按钮时，才标记并入队。 下拉刷新时执行“已读同步到云端”，并给出成功/失败数量提示。 分类详情页：筛选准确性修复 先拉取订阅映射，再请求 entries 时注入 feedMap ，确保 subscriptionCategory 可用。 本地已读状态在详情页也会正确合并显示。 进入详情页不会自动改已读；仍由详情页悬浮按钮手动触发。 订阅页：新增搜索 支持按分类名 / 订阅标题 / URL 过滤。 支持清空搜索词。 无结果时显示明确提示。 主页面搜索按钮：从 TODO 变为可用 新增 ArticleSearchDelegate 。 现支持在“时间线”页搜索已加载文章并直达详情。 设置页输入体验提升 三个认证字段支持显示/隐藏切换。 保存前增加输入规范校验，避免非法字符导致请求异常。 外链打开体验增强 新增 SecurityUtils.parseHttpUrl 。 文章正文链接点击与“打开原文”统一做 http/https 校验与失败提示。 3.2 稳定性与工程质量提升 网络层健壮化 FeedHttp 增加响应 Map 解析兜底，避免因返回结构异常导致崩溃。 统一 message 提取与 fallback。 登录前引导更明确 时间线 / 订阅页 / 详情页在未配置 Token 时会给出“请先去设置页配置”的明确提示，避免误判为网络故障。 测试修复 删除无效模板测试。 新增可运行的模型解析测试 test/article_model_test.dart 。 4. 本轮新增/修改文件清单 新增 lib/utils/security_utils.dart lib/ser"
 },
 {
  "path": "history/archive/images-video-and-media.html",
  "title": "历史归档：图片、视频与媒体交互",
  "headings": [
   {
    "id": "24-文章图片过大与无法全屏修复2026-05-18",
    "text": "24. 文章图片过大与无法全屏修复（2026-05-18）"
   },
   {
    "id": "241-问题",
    "text": "24.1 问题"
   },
   {
    "id": "242-修复",
    "text": "24.2 修复"
   },
   {
    "id": "243-影响文件",
    "text": "24.3 影响文件"
   },
   {
    "id": "32-视频播放支持2026-05-19",
    "text": "32. 视频播放支持（2026-05-19）"
   },
   {
    "id": "321-问题",
    "text": "32.1 问题"
   },
   {
    "id": "322-folo-官方方案",
    "text": "32.2 Folo 官方方案"
   },
   {
    "id": "323-实施",
    "text": "32.3 实施"
   },
   {
    "id": "324-影响文件",
    "text": "32.4 影响文件"
   },
   {
    "id": "325-预实验数据",
    "text": "32.5 预实验数据"
   },
   {
    "id": "326-验证结果",
    "text": "32.6 验证结果"
   },
   {
    "id": "35-图片画廊修复2026-05-20",
    "text": "35. 图片画廊修复（2026-05-20）"
   },
   {
    "id": "40-图片修复补充2026-05-20",
    "text": "40. 图片修复补充（2026-05-20）"
   },
   {
    "id": "95-macos-全屏图片-esc-键退出优化-2026-06-06",
    "text": "95. macOS 全屏图片 Esc 键退出优化 (2026-06-06)"
   },
   {
    "id": "951-需求背景与问题",
    "text": "95.1 需求背景与问题"
   },
   {
    "id": "952-问题产生原因",
    "text": "95.2 问题产生原因"
   },
   {
    "id": "953-修复方案与权衡",
    "text": "95.3 修复方案与权衡"
   },
   {
    "id": "954-给后续接手-agent-的提醒",
    "text": "95.4 给后续接手 Agent 的提醒"
   },
   {
    "id": "96-macos-物理播放键与空格键视频控制-2026-06-06",
    "text": "96. macOS 物理播放键与空格键视频控制 (2026-06-06)"
   },
   {
    "id": "961-背景与需求",
    "text": "96.1 背景与需求"
   },
   {
    "id": "962-实现细节",
    "text": "96.2 实现细节"
   },
   {
    "id": "963-注意事项",
    "text": "96.3 注意事项"
   },
   {
    "id": "99-重构-macos-视频播放器按键控制-2026-06-06",
    "text": "99. 重构 macOS 视频播放器按键控制 (2026-06-06)"
   },
   {
    "id": "991-需求与问题背景",
    "text": "99.1 需求与问题背景"
   },
   {
    "id": "992-实现思路与多视频冲突处理",
    "text": "99.2 实现思路与多视频冲突处理"
   },
   {
    "id": "993-关于-macos-原生媒体控制的遗留讨论",
    "text": "99.3 关于 macOS 原生媒体控制的遗留讨论"
   },
   {
    "id": "120-macos-图片右键复制功能-2026-06-08",
    "text": "120. macOS 图片右键复制功能 (2026-06-08)"
   },
   {
    "id": "1201-需求背景",
    "text": "120.1 需求背景"
   },
   {
    "id": "1202-讨论与决策",
    "text": "120.2 讨论与决策"
   },
   {
    "id": "1203-技术方案",
    "text": "120.3 技术方案"
   },
   {
    "id": "1204-修改文件清单",
    "text": "120.4 修改文件清单"
   },
   {
    "id": "1205-交互模式",
    "text": "120.5 交互模式"
   },
   {
    "id": "1206-验证结果",
    "text": "120.6 验证结果"
   },
   {
    "id": "133-修复极低高度分隔符图片被错误拉伸及过度占位问题-2026-06-10",
    "text": "133. 修复极低高度分隔符图片被错误拉伸及过度占位问题 (2026-06-10)"
   },
   {
    "id": "1331-问题现象与背景",
    "text": "133.1 问题现象与背景"
   },
   {
    "id": "1332-修复实施与效果",
    "text": "133.2 修复实施与效果"
   },
   {
    "id": "137-修复视频播放器总时长显示错误进位异常",
    "text": "137. 修复视频播放器总时长显示错误（进位异常）"
   },
   {
    "id": "1371-需求描述",
    "text": "137.1 需求描述"
   },
   {
    "id": "1372-根本原因定位",
    "text": "137.2 根本原因定位"
   },
   {
    "id": "1373-修复实现",
    "text": "137.3 修复实现"
   },
   {
    "id": "1374-修改文件清单",
    "text": "137.4 修改文件清单"
   },
   {
    "id": "141-macos-文章正文与图片宽度可配置2026-06-19",
    "text": "141. macOS 文章正文与图片宽度可配置（2026-06-19）"
   },
   {
    "id": "1411-背景",
    "text": "141.1 背景"
   },
   {
    "id": "1412-实现",
    "text": "141.2 实现"
   },
   {
    "id": "1413-验证",
    "text": "141.3 验证"
   },
   {
    "id": "1414-后续计划",
    "text": "141.4 后续计划"
   },
   {
    "id": "145-文章页目录摘要翻译操作与-android-打开过渡优化2026-06-26",
    "text": "145. 文章页目录、摘要/翻译操作与 Android 打开过渡优化（2026-06-26）"
   },
   {
    "id": "1451-本轮背景",
    "text": "145.1 本轮背景"
   },
   {
    "id": "1452-摘要翻译体验平行化",
    "text": "145.2 摘要/翻译体验平行化"
   },
   {
    "id": "1453-android-打开文章过渡优化",
    "text": "145.3 Android 打开文章过渡优化"
   },
   {
    "id": "1454-macos-目录功能改进",
    "text": "145.4 macOS 目录功能改进"
   },
   {
    "id": "1455-参考工程相关判断",
    "text": "145.5 参考工程相关判断"
   },
   {
    "id": "1456-验证",
    "text": "145.6 验证"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：图片、视频与媒体交互 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 24. 文章图片过大与无法全屏修复（2026-05-18） 24.1 问题 文章正文图片恢复为 flutter_html 默认渲染后，尺寸约束丢失，出现超大图片。 先前可点击图片进入全屏预览的交互被回退，正文图片无法点开。 24.2 修复 在 ArticlePage 的 Html 渲染中恢复 ImageExtension 自定义图片渲染： 使用 _ArticleInlineImage 控件统一渲染正文图片； 增加最大高度约束（ maxHeight: 320 ）和圆角容器，避免超大撑开布局。 恢复图片点击能力： 正文图片点击触发 controller.openImagePreview(imageUrl) ； 跳转到 ImageGalleryPage 全屏查看，支持缩放与多图切换。 保留图片加载稳态策略： 使用 CachedNetworkImage + 统一请求头（ ArticleImageService.httpHeaders ）； 失败态支持点击重试（retry stamp）。 24.3 影响文件 lib/pages/article/article_page.dart 32. 视频播放支持（2026-05-19） 32.1 问题 Social 条目（Twitter）中的 <video> 标签无法播放，显示静态占位符。两类格式： 直接 src ： <video src=\"...\" poster=\"...\" width=\"...\" height=\"...\"> <source> 子元素： <video poster=\"...\"><source src=\"...\"></video> 32.2 Folo 官方方案 Folo 桌面端用 HTML5 <video> 标签直接播放 mp4，移动端用 expo-video 包。不依赖第三方视频平台 SDK。 32.3 实施 Parser ( html_chunk_parser.dart ) <video> 含 <source> 子元素时从中提取 src 提取 poster 属性存入 HtmlChunk.posterSrc 字段 HtmlChunk 新增 posterSrc 字段 Renderer ( html_chunk_card.dart ) _buildMediaPlaceholder 改为 Stack 布局： 底层： CachedNetworkImage 加载 poster 缩略图（经过 Folo 图片代理） 中层：半透明黑色遮罩 顶层：圆形播放按钮（ Icons.play_arrow_rounded ） 点击 → url_launcher 打开 mp4 URL（系统播放器处理） 32.4 影响文件 lib/utils/html_chunk_parser.dart — HtmlChunk + posterSrc ， _processElement 视频分支 lib/pages/article/widgets/html_chunk_card.dart — _buildMediaPlaceholder 重写 32.5 预实验数据 样本 src poster dims social_video_12 (direct src) ✅ ✅ 1500×844 social_video_14 (direct src) ✅ ✅ 1920×1080 social_video_18 ( <source> ) ✅ ❌ null×null 32.6 验证结果 指标 修复前 修复后 新智元 86 图文章 33 张图片 80 张图片 (+142%) newsletter 17 图 13 张图片 16 张图片 (+23%) 新智元空标题 14 处间隙 0 处 解析性能 ~15ms ~15ms（持平） dart analyze 0 issues 0 issues 35. 图片画廊修复（2026-05-20） 双击放大 ：GestureDetector 从 InteractiveViewer 外层移到里层，避免手势冲突；缩放公式修正为 translate→scale→translate 捏合缩放 ：InteractiveViewer 移到最外层，不再被 GestureDetector 阻止 图片全灰 ：移除 AnimatedContainer + Opacity 包裹，直接使用 Scaffold 右下角\"点按查看\" ：删除 图片预加载 ：文章打开时隐藏 1px Stack 同时发出所有图片请求 画廊分母错误 ：审核页跳转文章时 sequence 改送审核列表自身，不再查全库 40. 图片修复补充（2026-05-20） i.qbitai.com 图片需 Referer: https://www.qbitai.com/ → 加代理规则走 img.folo.is 图片画廊双击缩放加 Matrix4Tween + AnimationController (300ms easeOut) normalizedContent / imageUrls 从 late final 改为普通字段，支持 inbox 异步补内容 95. macOS 全屏图片 Esc 键退出优化 (2026-06-06) 95.1 需求背景与问题 用户反馈：在 macOS 环境下阅读文章时，如果点击正文中的图片进入了沉浸式全屏浏览模式，此时按下 Esc 键，期望的行为是仅退出全屏图片，回到文章详情。但实际表现为不仅退出了图片全屏，连带着整篇文章也被关闭了。 95.2 问题产生原因 在 lib/pages/article/article_page.dart 中，为了支持 macOS 分栏模式（ isSplitView == true ）下文章视图的全局快捷键操作（如方向键滚动、快捷标记已读等）， ArticlePageView 注册了一个全局硬件键盘监听器 HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent) 。 该监听器由于是全局的，它在接收到 Esc 按键时，不论当前应用最顶层的 UI 是不是文章视图，都会强行拦截该按键并调用 _closeArticle() 。因此，当图片通过 HeroDialogRoute 被压入新路由全屏展示时，按下 Esc 依然触发了底层的 _closeArticle() 。 95.3 修复方案与权衡 由于这是由于底层的全局监听器“越权”拦截导致的问题，修复思路在于让 ArticlePageView 能够感知自身的路由层级。 我们在 _handleHardwareKeyEvent 的顶部追加了层级校验： if (!mounted) return false; final i"
 },
 {
  "path": "history/archive/list-animation-and-undo.html",
  "title": "历史归档：列表动画与撤销",
  "headings": [
   {
    "id": "93-macos-双击原文自动标已读与单步撤销2026-06-06",
    "text": "93. macOS 双击原文自动标已读与单步撤销（2026-06-06）"
   },
   {
    "id": "931-背景与交互判断",
    "text": "93.1 背景与交互判断"
   },
   {
    "id": "932-合入前审计发现的问题",
    "text": "93.2 合入前审计发现的问题"
   },
   {
    "id": "933-最终实现",
    "text": "93.3 最终实现"
   },
   {
    "id": "934-后续注意",
    "text": "93.4 后续注意"
   },
   {
    "id": "113-macos-时间线卡片双击动画掉帧修复2026-06-08",
    "text": "113. macOS 时间线卡片双击动画掉帧修复（2026-06-08）"
   },
   {
    "id": "1131-缺陷描述",
    "text": "113.1 缺陷描述"
   },
   {
    "id": "1132-根因分析",
    "text": "113.2 根因分析"
   },
   {
    "id": "1133-解决思路与实现",
    "text": "113.3 解决思路与实现"
   },
   {
    "id": "115-撤销聚焦与-macos-卡片进入退出动画重做2026-06-08",
    "text": "115. 撤销聚焦与 macOS 卡片进入/退出动画重做（2026-06-08）"
   },
   {
    "id": "1151-撤销后聚焦恢复文章",
    "text": "115.1 撤销后聚焦恢复文章"
   },
   {
    "id": "1152-macos-卡片进入退出动画",
    "text": "115.2 macOS 卡片进入/退出动画"
   },
   {
    "id": "116-cmdz-撤销已读状态不立即恢复的竞态条件修复2026-06-08",
    "text": "116. Cmd+Z 撤销已读状态不立即恢复的竞态条件修复（2026-06-08）"
   },
   {
    "id": "1161-问题报告",
    "text": "116.1 问题报告"
   },
   {
    "id": "1162-根因分析",
    "text": "116.2 根因分析"
   },
   {
    "id": "1163-设计讨论",
    "text": "116.3 设计讨论"
   },
   {
    "id": "1164-修复实现",
    "text": "116.4 修复实现"
   },
   {
    "id": "1165-行为变化对比",
    "text": "116.5 行为变化对比"
   },
   {
    "id": "1166-涉及文件",
    "text": "116.6 涉及文件"
   },
   {
    "id": "1167-后续注意事项",
    "text": "116.7 后续注意事项"
   },
   {
    "id": "118-macos-m-键快捷键偶尔失效修复2026-06-08",
    "text": "118. macOS M 键快捷键偶尔失效修复（2026-06-08）"
   },
   {
    "id": "1181-用户问题报告",
    "text": "118.1 用户问题报告"
   },
   {
    "id": "1182-完整代码审查与根因排查",
    "text": "118.2 完整代码审查与根因排查"
   },
   {
    "id": "1183-为什么双击总是有效",
    "text": "118.3 为什么双击总是有效"
   },
   {
    "id": "1184-修复方案",
    "text": "118.4 修复方案"
   },
   {
    "id": "1185-变更范围",
    "text": "118.5 变更范围"
   },
   {
    "id": "1186-受影响的手势路径总结",
    "text": "118.6 受影响的手势路径总结"
   },
   {
    "id": "1187-未修改的已知问题",
    "text": "118.7 未修改的已知问题"
   },
   {
    "id": "126-v1115-beta-验证失败后的滚动与垃圾拦截推进修复2026-06-08",
    "text": "126. v1.1.15 beta 验证失败后的滚动与垃圾拦截推进修复（2026-06-08）"
   },
   {
    "id": "1261-用户反馈",
    "text": "126.1 用户反馈"
   },
   {
    "id": "1262-滚动条与进度条根因",
    "text": "126.2 滚动条与进度条根因"
   },
   {
    "id": "1263-滚动修复",
    "text": "126.3 滚动修复"
   },
   {
    "id": "1264-垃圾拦截页推进失败根因",
    "text": "126.4 垃圾拦截页推进失败根因"
   },
   {
    "id": "1265-垃圾拦截页修复",
    "text": "126.5 垃圾拦截页修复"
   },
   {
    "id": "1266-验证",
    "text": "126.6 验证"
   },
   {
    "id": "本机-macos-native-build-仍受本机未安装-cocoapods-限制最终需通过-github-actions-release-包验证",
    "text": "本机 macOS native build 仍受本机未安装 CocoaPods 限制，最终需通过 GitHub Actions release 包验证。"
   },
   {
    "id": "131-卡片交互特效统一-2026-06-10",
    "text": "131. 卡片交互特效统一 (2026-06-10)"
   },
   {
    "id": "1311-需求背景",
    "text": "131.1 需求背景"
   },
   {
    "id": "1312-讨论过程",
    "text": "131.2 讨论过程"
   },
   {
    "id": "1313-实现细节",
    "text": "131.3 实现细节"
   },
   {
    "id": "1314-涉及的-ui-效果矩阵",
    "text": "131.4 涉及的 UI 效果矩阵"
   },
   {
    "id": "1315-修改文件清单",
    "text": "131.5 修改文件清单"
   },
   {
    "id": "1316-关键设计决策",
    "text": "131.6 关键设计决策"
   },
   {
    "id": "1317-后续优化建议",
    "text": "131.7 后续优化建议"
   },
   {
    "id": "136-修复-macos-卡片进出场动画闪现问题-2026-06-10",
    "text": "136. 修复 macOS 卡片进出场动画闪现问题 (2026-06-10)"
   },
   {
    "id": "1361-需求与问题描述",
    "text": "136.1 需求与问题描述"
   },
   {
    "id": "1362-问题定位与分析",
    "text": "136.2 问题定位与分析"
   },
   {
    "id": "1363-修复实现",
    "text": "136.3 修复实现"
   },
   {
    "id": "1364-补丁解决掉帧与m快捷键带来的冲突",
    "text": "136.4 补丁：解决掉帧与“M”快捷键带来的冲突"
   },
   {
    "id": "1365-补丁-2解决连续快速操作时的闭包变量捕获导致状态错乱与闪跳",
    "text": "136.5 补丁 2：解决连续快速操作时的“闭包变量捕获”导致状态错乱与闪跳"
   },
   {
    "id": "1366-修改文件清单",
    "text": "136.6 修改文件清单"
   },
   {
    "id": "139-macos-卡片进出场动画随机闪现的状态机修复2026-06-10",
    "text": "139. macOS 卡片进出场动画随机闪现的状态机修复（2026-06-10）"
   },
   {
    "id": "1391-背景",
    "text": "139.1 背景"
   },
   {
    "id": "1392-新发现的根因",
    "text": "139.2 新发现的根因"
   },
   {
    "id": "1393-修复实现",
    "text": "139.3 修复实现"
   },
   {
    "id": "1394-回归测试",
    "text": "139.4 回归测试"
   },
   {
    "id": "1395-已完成验证",
    "text": "139.5 已完成验证"
   },
   {
    "id": "1396-后续人工验证重点",
    "text": "139.6 后续人工验证重点"
   },
   {
    "id": "140-macos-时间线-m-键退场动画瞬间结束专项修复2026-06-10",
    "text": "140. macOS 时间线 M 键退场动画瞬间结束专项修复（2026-06-10）"
   },
   {
    "id": "1401-用户反馈",
    "text": "140.1 用户反馈"
   },
   {
    "id": "1402-新定位",
    "text": "140.2 新定位"
   },
   {
    "id": "1403-修复实现",
    "text": "140.3 修复实现"
   },
   {
    "id": "1404-后续验证重点",
    "text": "140.4 后续验证重点"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：列表动画与撤销 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 93. macOS 双击原文自动标已读与单步撤销（2026-06-06） 93.1 背景与交互判断 用户确认需要在 macOS 端双击文章卡片打开原文时自动将文章标记为已读。这里的产品判断是：单击只是进入右侧分栏预览，不应强行标已读；双击打开外部浏览器代表更明确的阅读/消费意图，可以自动标已读。 同时，误双击或误按 M 会让文章从“未读”列表里消失，用户再去“全部”里找回并恢复未读成本很高。因此本轮引入一个深度为 1 的全局撤销： Cmd-Z （macOS）/ Ctrl-Z （其他平台配置层面保留）撤销最近一次“未读 -> 已读”转换。 93.2 合入前审计发现的问题 super-galaxy-rolls-08h21 分支原始实现有价值，但不能原样合入： 双击时只有在对应 ArticleController 已注册时才会 markAsRead() ，而双击打开原文并不保证右侧详情 controller 一定存在，因此自动标已读不可靠。 ArticleController.markAsRead() 一进入就记录 undo；如果后续网络同步失败并恢复未读，会留下不真实的可撤销记录。 UndoService.undoLastRead() 在复用 ArticleController.markAsUnread() 时没有 await ，会过早显示“已撤销成功”。 文档章节没有沿用 AGENT_HANDOFF.md 的编号格式。 93.3 最终实现 本轮保留功能方向，但修正实现边界： 新增 lib/services/undo_service.dart ： 管理最近一次已读动作 _lastReadArticle 。 提供 markAsRead(article, showSuccess: false) ，用于双击外部打开时后台标已读。 如果 ArticleController 已存在，则复用 controller 的 markAsRead() ，保证右侧详情页按钮状态同步；否则直接更新本地 DB / TimelineController / ReadSyncService 并调用 Folo API。 网络失败时恢复未读并清理对应 undo 记录。 ArticleController.markAsRead() ： 改为在本地已读状态真正生效后记录 undo。 如果同步失败并恢复未读，调用 UndoService.clearForEntry() 清掉错误撤销记录。 增加 showSuccess 参数，允许双击自动标已读时静默同步。 TimelinePage 、 FeedDetailPage 、 RecentReadPage ： 双击仍先打开原文。 若文章未读，则 unawaited(UndoService.markAsRead(article, showSuccess: false)) 后台标已读。 main.dart ： 在 GetMaterialApp.builder 中通过 Shortcuts / Actions 注册全局撤销。 执行撤销前检查当前焦点 widget；如果焦点在 EditableText ，直接返回，避免抢占搜索框、设置页输入框、Prompt 编辑框里的文本撤销。 TimelineController ： 切换 view mode、feed、category 时清空 undo，避免跨上下文撤销造成隐藏列表的状态跳变。 93.4 后续注意 撤销仍是单步设计，不要扩展成多步栈，除非后续确实需要更复杂的历史管理。当前目标是降低误双击和误标已读的恢复成本，而不是实现完整编辑器式 undo 系统。 113. macOS 时间线卡片双击动画掉帧修复（2026-06-08） 113.1 缺陷描述 在 macOS 端应用中，点击时间线文章卡片时，左侧卡片会触发水波纹反馈动画（ InkWell ripple），同时右侧分栏会响应加载文章详情。当用户快速双击卡片以图快速打开外部浏览器并标记已读时，系统出现严重的视觉断裂和掉帧感。 113.2 根因分析 单双击设计权衡 ：为了避免原生 onDoubleTap 带来的 300ms 强制判断延迟，代码中去除了该回调，转而在 _handleMacArticleTap 中通过计算两次点击的时间差（ < 300ms ）手动判定双击。 第一击并发压力 ：无论是单击还是双击，第一击都会同步触发 controller.selectedArticle.value = article ，随即启动极其繁重的 ArticlePageView HTML 结构解析（包括 Isolate.run 以及返回后立即在主线程执行的前 5 个 HtmlChunkCard 的重度构建）。 视觉冲突与线程拥堵 ：双击行为发生在第一击之后的 150-300ms 之间，这正好与 ArticlePageView 首帧解析渲染的回调相撞。此时，第二击又并发触发了 launchUrl （唤起外部浏览器）和 UndoService.markAsRead 。而 markAsRead 会修改状态，导致包含该卡片的列表项从界面上迅速移除（销毁 ArticleCard widget），直接截断了刚刚开启的水波纹动画，造成强烈的撕裂和卡顿感。 113.3 解决思路与实现 核心原则是： 在保留双击响应速度（零人工 Delay）的前提下，实现重型操作的渲染错峰。 修改 lib/pages/timeline/timeline_page.dart ：在第 112 节已确定的“先选中下一篇”基础上，将双击后触发的浏览器启动及已读处理放入 WidgetsBinding.instance.addPostFrameCallback 中。让 Flutter 把当前正处于启动水波纹和准备布局变更阶段的那一帧顺畅渲染完（完成上屏），然后立即接管并执行其余沉重任务。 if (isDoubleTap) { _lastArticleTapEntryId = null; _lastArticleTapAt = null; _selectRelativeArticle(1); // Let the current frame paint the double-tap ripple before heavy work. WidgetsBinding.instance.addPostFrameCallback((_) { _openOriginalArticle(article); if (!article.isRead) { unawaited(UndoService.markAsRead(article, showSuccess: false)); } }); } 通过这种极其细粒度的帧调度，既消除"
 },
 {
  "path": "history/archive/macos-liquid-glass.html",
  "title": "历史归档：macOS Liquid Glass 重构",
  "headings": [
   {
    "id": "146-后续-macos-液态玻璃-ui-重构上下文2026-06-26",
    "text": "146. 后续 macOS 液态玻璃 UI 重构上下文（2026-06-26）"
   },
   {
    "id": "1461-用户意图与总体边界",
    "text": "146.1 用户意图与总体边界"
   },
   {
    "id": "1462-为什么本轮没有直接引入完整-shader-液态玻璃",
    "text": "146.2 为什么本轮没有直接引入完整 shader 液态玻璃"
   },
   {
    "id": "1463-推荐路线先-macos后-android",
    "text": "146.3 推荐路线：先 macOS，后 Android"
   },
   {
    "id": "1464-建议的技术组织方式",
    "text": "146.4 建议的技术组织方式"
   },
   {
    "id": "1465-工作流建议",
    "text": "146.5 工作流建议"
   },
   {
    "id": "1466-下一位-agent-进入重构线前应先做的事",
    "text": "146.6 下一位 agent 进入重构线前应先做的事"
   },
   {
    "id": "1467-不要遗漏的风险点",
    "text": "146.7 不要遗漏的风险点"
   },
   {
    "id": "147-macos-liquid-glass-重构分支阶段记录2026-06-26",
    "text": "147. macOS Liquid Glass 重构分支阶段记录（2026-06-26）"
   },
   {
    "id": "1471-分支状态与发布边界",
    "text": "147.1 分支状态与发布边界"
   },
   {
    "id": "1472-为什么这次改为完整引入参考实现的子集",
    "text": "147.2 为什么这次改为“完整引入参考实现的子集”"
   },
   {
    "id": "1473-目前新增的基础组件",
    "text": "147.3 目前新增的基础组件"
   },
   {
    "id": "1474-macos-主窗口外框与侧边栏改动",
    "text": "147.4 macOS 主窗口外框与侧边栏改动"
   },
   {
    "id": "1475-红绿灯按钮处理过程与当前方案",
    "text": "147.5 红绿灯按钮处理过程与当前方案"
   },
   {
    "id": "1476-高光边框与-continuous-corner-的讨论结果",
    "text": "147.6 高光、边框与 continuous corner 的讨论结果"
   },
   {
    "id": "1477-参考工程与许可自包含要求",
    "text": "147.7 参考工程与许可/自包含要求"
   },
   {
    "id": "1478-已验证事项",
    "text": "147.8 已验证事项"
   },
   {
    "id": "1479-后续继续本分支时不要遗漏",
    "text": "147.9 后续继续本分支时不要遗漏"
   },
   {
    "id": "14710-liquid-glass-使用边界校准2026-06-27",
    "text": "147.10 Liquid Glass 使用边界校准（2026-06-27）"
   },
   {
    "id": "14711-侧边栏真实背景取色边框实验结论2026-06-27",
    "text": "147.11 侧边栏真实背景取色边框实验结论（2026-06-27）"
   },
   {
    "id": "14712-macos-文章目录对标参考工程-popover-morph2026-06-27",
    "text": "147.12 macOS 文章目录对标参考工程 popover morph（2026-06-27）"
   },
   {
    "id": "148-macos-liquid-glass-控制层统一推进2026-06-28",
    "text": "148. macOS Liquid Glass 控制层统一推进（2026-06-28）"
   },
   {
    "id": "149-macos-liquid-glass-设置页与后台任务浮层整改2026-06-29",
    "text": "149. macOS Liquid Glass 设置页与后台任务浮层整改（2026-06-29）"
   },
   {
    "id": "150-macos-设置展开组件与文章页右上浮动控制2026-06-30",
    "text": "150. macOS 设置展开组件与文章页右上浮动控制（2026-06-30）"
   },
   {
    "id": "155-macos-全局滚动惯性上限与设置项2026-07-03",
    "text": "155. macOS 全局滚动惯性上限与设置项（2026-07-03）"
   },
   {
    "id": "162-软件内外观模式设置与圆角收敛调研2026-07-07",
    "text": "162. 软件内外观模式设置与圆角收敛调研（2026-07-07）"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：macOS Liquid Glass 重构 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 146. 后续 macOS 液态玻璃 UI 重构上下文（2026-06-26） 146.1 用户意图与总体边界 用户明确表达：后续有将整体 UI 重构为更接近 Apple / iOS 26 Liquid Glass 风格的想法，尤其是 macOS 端。当前只是讨论与准备上下文，尚未开始正式 UI 重构。 已确认边界： reference/liquid_glass_widgets 只作为参考工程。 不把参考工程作为 package、submodule、git 依赖或运行时外部路径。 当前仓库必须保持自包含：clone 到任何地方都应能独立构建和运行。 如果未来迁移/复制参考工程中的 MIT 代码或 shader，必须把需要的源码、shader、资源、许可与 attribution 一并纳入本仓库。 不允许要求运行环境额外存在 reference/liquid_glass_widgets 。 用户不希望做“先凑合、以后再改”的半成品。如果开始重构，应按目标形态认真设计与实现。 新问题当然可以继续向用户确认，但不要重复询问上述已经确认的原则。 146.2 为什么本轮没有直接引入完整 shader 液态玻璃 本轮阅读参考工程后确认： reference/liquid_glass_widgets 不只是毛玻璃样式库，而是有完整渲染体系： shaders/lightweight_glass.frag shaders/interactive_indicator.frag shaders/liquid_glass_geometry_blended.frag shaders/liquid_glass_final_render.frag LiquidGlassLayer LiquidGlassBlendGroup AdaptiveLiquidGlassLayer GlassMorphController LiquidMorphPhysics 参考工程的 GlassMenu 是“小按钮/小组件液态展开成大组件”的标准参考实现，使用： ghost trigger menu body J-curve / spring anchor blob 缩小 body 从触发器中心移动并扩张 SDF/metaball 形变 内容在容器接近成形后再淡入 但本轮只是文章页目录与阅读体验小版本修复，直接引入 shader/renderer 体系会把风险扩大到构建、性能、平台兼容和发布链路，因此没有混入 v1.1.22 。 146.3 推荐路线：先 macOS，后 Android 已经讨论并建议：下一阶段如果开始液态玻璃 UI 重构，应优先做 macOS，不建议 Android 同时全量重构。 理由： macOS 端的使用场景更适合液态玻璃：左侧列表、右侧阅读、悬浮目录、工具按钮、分栏布局都接近桌面 Apple 风格。 Android 刚处理过文章打开转场卡顿和进度条/滚动稳定性问题，大量 blur/shader/玻璃层更容易引入性能和视觉问题。 “逻辑统一”不等于“双端视觉同步上线”。更好的方式是抽象统一组件 API，然后按平台实现： macOS 使用液态玻璃实现。 Android 先保留轻量 Material / 轻毛玻璃实现。 这样调用层统一，平台差异集中在组件实现中，避免到处写零散 Platform.isMacOS 判断。 146.4 建议的技术组织方式 如果开始重构，建议先引入项目内自有设计系统层，而不是直接在业务页面里散写样式： AppGlassSurface AppGlassPanel AppGlassButton AppGlassIconButton AppGlassToolbar AppReaderShell AppSidebarSurface 这些名字只是建议，实际命名应服从代码库现有结构。 目标： 页面业务逻辑不直接依赖 shader 细节。 macOS/Android 差异集中在底层组件或少量 theme/adapter。 后续如果从毛玻璃 fallback 迁移到真实 shader Liquid Glass，不需要大范围改业务页面。 146.5 工作流建议 用户询问是否可以不等 v1.1.22 打包完成就开始新分支。结论： 可以不等打包完成，因为 v1.1.22 tag 已推送，GitHub Actions 会按 tag 独立跑。 不建议直接在当前 main 工作区 checkout 到大重构分支。 建议使用新的 worktree，保持当前目录在 main ，方便 release 如果失败可以随时热修。 推荐命令： git worktree add ../auto-folo-liquid-glass -b codex/macos-liquid-glass-ui main 原因： macOS UI 全面重构跨度大，容易产生多轮半成品。 新 worktree 可以让 main 始终保持可热修状态。 不需要频繁 stash/WIP commit 才能切回 main。 重构满意后再从分支 merge 回 main。 如果用户明确要求简单处理，也可以在当前位置 git checkout -b codex/macos-liquid-glass-ui ，但这不是推荐方案。 146.6 下一位 agent 进入重构线前应先做的事 进入新 worktree 后，建议先完成以下工作，而不是马上重写页面： 阅读本节和第 145 节，理解用户边界和本轮文章页目录已做的轻量 morph。 检查 reference/liquid_glass_widgets 的 license、shader 注册、renderer/fallback 结构。 盘点当前 macOS UI 结构： timeline / feed list / article split view article detail / toolbar / TOC overlay settings dialogs / menus / context actions 提出 macOS-first 的重构计划，明确哪些组件先抽象，哪些页面先改。 单独评估是否要迁移 shader 级实现，还是先构建自有组件 API + 毛玻璃 fallback。 如果迁移 MIT 代码，必须确认许可、归属说明、shader 路径、pubspec 注册和打包影响。 146.7 不要遗漏的风险点 Android 性能不要被 macOS 液态玻璃牵连。 不要重新引入文章滚动条/顶部进度条抖动。 不要破坏 macOS 文章页键盘焦点：左右键、上下键、M 键、Esc 之前多次修复过。 不要让图片 hover 再次造成正文布局移动；之"
 },
 {
  "path": "history/archive/macos-shell-and-shortcuts.html",
  "title": "历史归档：macOS 桌面框架与快捷键",
  "headings": [
   {
    "id": "75-macos-桌面端深度适配2026-05-31进行中",
    "text": "75. macOS 桌面端深度适配（2026-05-31，进行中）"
   },
   {
    "id": "751-核心需求与设计",
    "text": "75.1 核心需求与设计"
   },
   {
    "id": "752-当前实现要点",
    "text": "75.2 当前实现要点"
   },
   {
    "id": "753-关键设计讨论与决策留档",
    "text": "75.3 关键设计讨论与决策留档"
   },
   {
    "id": "76-macos-适配复盘与当前权威上下文2026-06-01",
    "text": "76. macOS 适配复盘与当前权威上下文（2026-06-01）"
   },
   {
    "id": "761-工作区与分支约束",
    "text": "76.1 工作区与分支约束"
   },
   {
    "id": "762-用户目标与设计参考",
    "text": "76.2 用户目标与设计参考"
   },
   {
    "id": "763-当前-macos-主布局",
    "text": "76.3 当前 macOS 主布局"
   },
   {
    "id": "764-左侧订阅栏与折叠逻辑",
    "text": "76.4 左侧订阅栏与折叠逻辑"
   },
   {
    "id": "765-审核页入口与桌面交互",
    "text": "76.5 审核页入口与桌面交互"
   },
   {
    "id": "766-macos-关闭行为与菜单",
    "text": "76.6 macOS 关闭行为与菜单"
   },
   {
    "id": "767-dock-角标与-appicon",
    "text": "76.7 Dock 角标与 AppIcon"
   },
   {
    "id": "768-macos-左栏毛玻璃问题未解决后续重点",
    "text": "76.8 macOS 左栏毛玻璃问题（未解决，后续重点）"
   },
   {
    "id": "769-macos-构建日志与-warning-处理",
    "text": "76.9 macOS 构建日志与 warning 处理"
   },
   {
    "id": "7610-当前验证记录",
    "text": "76.10 当前验证记录"
   },
   {
    "id": "7611-当前改动涉及的主要文件",
    "text": "76.11 当前改动涉及的主要文件"
   },
   {
    "id": "7612-后续接手建议",
    "text": "76.12 后续接手建议"
   },
   {
    "id": "77-macos-侧边栏与相关页面全面适配本轮对话完整记录",
    "text": "77. macOS 侧边栏与相关页面全面适配（本轮对话完整记录）"
   },
   {
    "id": "771-用户原始诉求按时间线",
    "text": "77.1 用户原始诉求（按时间线）"
   },
   {
    "id": "772-改动总览",
    "text": "77.2 改动总览"
   },
   {
    "id": "773-改动详情",
    "text": "77.3 改动详情"
   },
   {
    "id": "774-设计决策与讨论过程",
    "text": "77.4 设计决策与讨论过程"
   },
   {
    "id": "775-技术要点",
    "text": "77.5 技术要点"
   },
   {
    "id": "776-当前验证状态",
    "text": "77.6 当前验证状态"
   },
   {
    "id": "777-已回退的早期移动端订阅页尝试历史参考",
    "text": "77.7 已回退的早期移动端订阅页尝试（历史参考）"
   },
   {
    "id": "778-当时尝试的代码改动后续已回退libpagessubscriptionssubscriptions_pagedart",
    "text": "77.8 当时尝试的代码改动（后续已回退， lib/pages/subscriptions/subscriptions_page.dart ）"
   },
   {
    "id": "779-当时问题按钮在运行时不可见",
    "text": "77.9 当时问题：按钮在运行时不可见"
   },
   {
    "id": "7710-当时建议的调试步骤仅历史参考",
    "text": "77.10 当时建议的调试步骤（仅历史参考）"
   },
   {
    "id": "78-快捷键同步反馈品牌统一审核页已读同步2026-06-01",
    "text": "78. 快捷键、同步反馈、品牌统一、审核页已读同步（2026-06-01）"
   },
   {
    "id": "781-用户本次反馈的原始问题",
    "text": "78.1 用户本次反馈的原始问题"
   },
   {
    "id": "782-已做修改",
    "text": "78.2 已做修改"
   },
   {
    "id": "783-验证结果",
    "text": "78.3 验证结果"
   },
   {
    "id": "784-关于工程目录名的建议",
    "text": "78.4 关于工程目录名的建议"
   },
   {
    "id": "785-需要在-main-分支主工程侧同步的事项",
    "text": "78.5 需要在 main 分支/主工程侧同步的事项"
   },
   {
    "id": "79-macos-快捷键双重触发刷新动画与未读计数2026-06-01-追加修复",
    "text": "79. macOS 快捷键双重触发、刷新动画与未读计数（2026-06-01 追加修复）"
   },
   {
    "id": "本次反馈问题与修复总结",
    "text": "本次反馈问题与修复总结"
   },
   {
    "id": "94-macos-快捷键支持与设置页说明展示2026-06-06",
    "text": "94. macOS 快捷键支持与设置页说明展示（2026-06-06）"
   },
   {
    "id": "941-需求背景",
    "text": "94.1 需求背景"
   },
   {
    "id": "942-实现细节",
    "text": "94.2 实现细节"
   },
   {
    "id": "943-后续维护",
    "text": "94.3 后续维护"
   },
   {
    "id": "101-macos-设置快捷键行为等效化修复-2026-06-06",
    "text": "101. macOS 设置快捷键行为等效化修复 (2026-06-06)"
   },
   {
    "id": "1011-问题背景",
    "text": "101.1 问题背景"
   },
   {
    "id": "1012-问题根源",
    "text": "101.2 问题根源"
   },
   {
    "id": "1013-修复思路与重构方案",
    "text": "101.3 修复思路与重构方案"
   },
   {
    "id": "1014-留给后续-agent-的思考",
    "text": "101.4 留给后续 Agent 的思考"
   },
   {
    "id": "109-macos-分栏快捷键归属泛化与发布-notes-防错-2026-06-08",
    "text": "109. macOS 分栏快捷键归属泛化与发布 notes 防错 (2026-06-08)"
   },
   {
    "id": "1091-背景",
    "text": "109.1 背景"
   },
   {
    "id": "1092-本次修复",
    "text": "109.2 本次修复"
   },
   {
    "id": "1093-后续发布约束",
    "text": "109.3 后续发布约束"
   },
   {
    "id": "132-修复-macos-侧边栏选中项文本排版跳动",
    "text": "132. 修复 macOS 侧边栏选中项文本排版跳动"
   },
   {
    "id": "1321-问题描述",
    "text": "132.1 问题描述"
   },
   {
    "id": "1322-解决方案讨论与权衡",
    "text": "132.2 解决方案讨论与权衡"
   },
   {
    "id": "1323-实现细节",
    "text": "132.3 实现细节"
   },
   {
    "id": "134-macos-端卡片双重边界缺陷修复-2026-06-10",
    "text": "134. macOS 端卡片双重边界缺陷修复 (2026-06-10)"
   },
   {
    "id": "1341-缺陷描述",
    "text": "134.1 缺陷描述"
   },
   {
    "id": "1342-根本原因定位",
    "text": "134.2 根本原因定位"
   },
   {
    "id": "1343-修复思路与讨论过程",
    "text": "134.3 修复思路与讨论过程"
   },
   {
    "id": "1344-修改文件清单",
    "text": "134.4 修改文件清单"
   },
   {
    "id": "135-macos-端垃圾拦截卡片按钮点击失效修复",
    "text": "135. macOS 端垃圾拦截卡片按钮点击失效修复"
   },
   {
    "id": "1351-任务背景",
    "text": "135.1 任务背景"
   },
   {
    "id": "1352-问题定位与排查",
    "text": "135.2 问题定位与排查"
   },
   {
    "id": "1353-实施的修改方案",
    "text": "135.3 实施的修改方案"
   },
   {
    "id": "1354-关键设计决策与后续建议",
    "text": "135.4 关键设计决策与后续建议"
   },
   {
    "id": "144-迁移验证收口与-macos-图片-hover-微缩修复2026-06-22",
    "text": "144. 迁移验证收口与 macOS 图片 hover 微缩修复（2026-06-22）"
   },
   {
    "id": "1441-当前验证结论",
    "text": "144.1 当前验证结论"
   },
   {
    "id": "1442-暂时继续搁置的事项",
    "text": "144.2 暂时继续搁置的事项"
   },
   {
    "id": "1443-macos-图片-hover-微缩修复",
    "text": "144.3 macOS 图片 hover 微缩修复"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：macOS 桌面框架与快捷键 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 75. macOS 桌面端深度适配（2026-05-31，进行中） 75.1 核心需求与设计 在原有跨平台代码基础上，全面提升 macOS 端的原生交互体验，使其具备真正的桌面级应用质感。设计上严格对标原始 folo 桌面端的“三栏布局”，同时保留 Android 端的原有形态。 75.2 当前实现要点 三栏经典布局与毛玻璃侧边栏 ： 在 lib/pages/main/main_page.dart 中，移除了原有的移动端底导和基础侧边导航，彻底重构为 MacOSSidebar | VerticalDivider | 核心内容区 的三栏布局。 新增 lib/pages/main/widgets/macos_sidebar.dart ，使用 BackdropFilter(sigmaX: 20, sigmaY: 20) 实现 macOS 标志性的高强度毛玻璃（Vibrancy）效果。 订阅树（包含“全部文章”、“垃圾拦截”、各种分类与特定源）被直接展现在最左侧边栏中。 底层路由与状态联动 ： 左侧侧边栏通过 SubscriptionsController 渲染数据树，并将点击事件传递给 TimelineController 。 修改 TimelineController ，使其能够支持 selectedCategory 与 selectedFeedId 的响应式过滤更新。实现侧边栏点击后，中间时间线列表立刻精准切换内容的单页无缝体验。 原生快捷键补齐 ： 在 MainPage 外层增加 Focus 监听键盘事件。 实现 Cmd + W 隐藏当前窗口（调用 windowManager.hide() ）。 实现 Cmd + Q 彻底退出应用程序（调用 exit(0) ）。 macOS Dock 动态原生角标 ： 在 macos/Runner/AppDelegate.swift 中通过 MethodChannel(\"com.autofolo/badge\") 接管了原生层的 NSApp.dockTile.badgeLabel 渲染逻辑。 使得未读文章的数字可以实时且精准地以红底白字显示在 Mac 底部的 Dock 栏图标右上角。 独立的高清应用图标 ： 通过原生 sips 脚本对原始 Folo 高清图标进行自动重采样，生成了符合 macOS 标准的全尺寸 .appiconset 集合，完全替代了 Flutter 的默认模板图标。 75.3 关键设计讨论与决策留档 在本次迭代中，通过与用户的讨论，明确了以下几项关键的设计理念和未来规划： 摒弃侧边导航栏，回归三栏沉浸布局 ： 用户明确指出原始 folo 项目的界面设计非常优秀，因此决定放弃初版使用 NavigationRail （带 3 个按钮）的生硬方案。 最终确立了将“订阅源选择”直接做到最左侧的模式，当点击空白时不进行任何选择，最大程度复刻了桌面端原汁原味的体验。 关于“已读”行为的交互讨论 ： 用户不希望像原始 folo 工程那样“点击列表项就自动标为已读”，而是希望保留类似 Android 端那种“需要明确的确认步骤”。 已决定的方案 ：一方面在详情页保留明确的“已读”按钮，另一方面为 macOS 专门增加了快捷键（计划使用 M 键作为标为已读的快捷键，后续实现）。 状态刷新逻辑 ：讨论了阅读后文章是否立刻消失的问题。目前保持现状，后续可以结合状态管理平滑处理列表内的隐藏动画。 未来的键盘导航扩展 ： 用户提出未来可以通过设置其他快捷键（如左右方向键）来阅读上一篇/下一篇，以此来对标安卓端的左右滑动切页手势。该需求已记录，留待后续版本实现。 76. macOS 适配复盘与当前权威上下文（2026-06-01） 重要：第 75 节是早期记录，其中关于 Cmd+W/Cmd+Q 和毛玻璃的实现描述已经不完全准确。后续接手请以本节为准。 2026-06-03 校准：本节的“当前工作目录/当前分支/不要改 ~/dev 主工作区”等约束，是 2026-06-01 当时 macOS 适配辅助 worktree 的历史语境；当前主工作区请结合第 81 节 worktree 清理记录和后续发布记录判断，不要机械套用本节路径约束。 76.1 工作区与分支约束 当前工作目录： <historical-macos-worktree> 当前分支： migrate-software-macos-adaptation 用户明确要求：所有 macOS 适配、同步和实验都不要改动核心工作区 ~/dev 那边。 本轮操作均在当前 worktree 内完成，没有直接操作 ~/dev 工作区。 曾从另一个 worktree <historical-codex-worktree> 同步 7 个提交到当前分支顶部，避免 macOS 适配与 Android/通用功能更新长期分叉： 83f6b7a Fix read sync cleanup and readability queue dedupe a4b5777 Retry chunked translations without partial results ea8f494 Add adaptive virtual rendering for long articles 7e05db4 Add settings task center d5f67f3 Polish task center status UI ce869f3 Add AI failure detail retries 8e41518 Improve chunk translation failure details 同步前创建过备份 stash： stash@{0}: On migrate-software-macos-adaptation: pre-sync-macos-adaptation 。如确认当前工作无误，可后续手动清理；当前不要随意删除。 76.2 用户目标与设计参考 用户当前主线目标是 macOS 端精细化适配，方向是参考 reference/Folo 的桌面端视觉和交互，而不是照搬内部实现。核心要求： macOS 设计不要破坏现有移动端设计。 左侧订阅源的 category/folder 必须支持折叠；整条订阅栏是否可收起是附带能力。 关闭窗口应隐藏窗口但保留 app 运行； Cmd+Q 才是真正退出。 macOS 三栏设计参考 Folo 原生桌面工程：左侧订阅栏、中间列表、右侧阅读/详情。 Folo 左侧订阅栏的材质感、毛玻璃、视觉密度可以参考，但内部业务逻辑继续用本项目自己的 GetX/Hive/Folo API 逻辑。 审核页是高频入口，任务中心只是低频诊断入口，不能替代审核页。 7"
 },
 {
  "path": "history/archive/performance-and-scrolling.html",
  "title": "历史归档：性能、滚动与进度",
  "headings": [
   {
    "id": "14-图片渲染性能优化v14",
    "text": "14. 图片渲染性能优化（v1.4）"
   },
   {
    "id": "141-问题诊断",
    "text": "14.1 问题诊断"
   },
   {
    "id": "142-实施改进",
    "text": "14.2 实施改进"
   },
   {
    "id": "143-预期效果",
    "text": "14.3 预期效果"
   },
   {
    "id": "144-后续可选优化",
    "text": "14.4 后续可选优化"
   },
   {
    "id": "145-修改文件清单",
    "text": "14.5 修改文件清单"
   },
   {
    "id": "42-性能优化-卡顿修复2026-05-20",
    "text": "42. 性能优化 — 卡顿修复（2026-05-20）"
   },
   {
    "id": "62-性能优化2026-05-25",
    "text": "62. 性能优化（2026-05-25）"
   },
   {
    "id": "621-api-请求并行化",
    "text": "62.1 API 请求并行化"
   },
   {
    "id": "622-正则表达式编译缓存",
    "text": "62.2 正则表达式编译缓存"
   },
   {
    "id": "623-不必要的-articlemodel-全字段拷贝消除",
    "text": "62.3 不必要的 ArticleModel 全字段拷贝消除"
   },
   {
    "id": "624-searchsourcearticles-去拷贝",
    "text": "62.4 searchSourceArticles 去拷贝"
   },
   {
    "id": "625-骨架屏动画代码去重",
    "text": "62.5 骨架屏动画代码去重"
   },
   {
    "id": "626-hive-批量写入",
    "text": "62.6 Hive 批量写入"
   },
   {
    "id": "627-ai-过滤计数增量更新",
    "text": "62.7 AI 过滤计数增量更新"
   },
   {
    "id": "628-feeddetail-重复-upsertmany-移除",
    "text": "62.8 FeedDetail 重复 upsertMany 移除"
   },
   {
    "id": "629-readsyncservice-指数退避",
    "text": "62.9 ReadSyncService 指数退避"
   },
   {
    "id": "6210-审核列表复活修复-§611",
    "text": "62.10 审核列表复活修复 (§61.1)"
   },
   {
    "id": "6211-遗留问题部分接口网络失败导致未读文章闪烁",
    "text": "62.11 遗留问题：部分接口网络失败导致未读文章“闪烁”"
   },
   {
    "id": "66-优化文章滑动渲染性能2026-05-26",
    "text": "66. 优化文章滑动渲染性能（2026-05-26）"
   },
   {
    "id": "661-问题报告",
    "text": "66.1 问题报告"
   },
   {
    "id": "662-根因分析",
    "text": "66.2 根因分析"
   },
   {
    "id": "663-设计讨论与具体改动",
    "text": "66.3 设计讨论与具体改动"
   },
   {
    "id": "664-行为变化对照",
    "text": "66.4 行为变化对照"
   },
   {
    "id": "69-极致渲染优化完美进度条与流畅加载的平衡-2026-05-28",
    "text": "69. 极致渲染优化：完美进度条与流畅加载的平衡 (2026-05-28)"
   },
   {
    "id": "691-背景与痛点",
    "text": "69.1 背景与痛点"
   },
   {
    "id": "692-核心策略回归-column-大颗粒度打包",
    "text": "69.2 核心策略：回归 Column + 大颗粒度打包"
   },
   {
    "id": "693-终极补丁渐进式分帧注入-incremental-rendering",
    "text": "69.3 终极补丁：渐进式分帧注入 (Incremental Rendering)"
   },
   {
    "id": "694-视觉防抖优化-layout-shift-保护",
    "text": "69.4 视觉防抖优化 (Layout Shift 保护)"
   },
   {
    "id": "695-影响文件",
    "text": "69.5 影响文件"
   },
   {
    "id": "70-延迟-build-widget-缓存根治重度技术文章首次打开掉帧-2026-05-30",
    "text": "70. 延迟 build + widget 缓存：根治重度技术文章首次打开掉帧 (2026-05-30)"
   },
   {
    "id": "701-触发案例",
    "text": "70.1 触发案例"
   },
   {
    "id": "702-诊断过程",
    "text": "70.2 诊断过程"
   },
   {
    "id": "703-真正的根因不是图片加载",
    "text": "70.3 真正的根因（不是图片加载）"
   },
   {
    "id": "704-解决方案讨论",
    "text": "70.4 解决方案讨论"
   },
   {
    "id": "705-实施方案细节",
    "text": "70.5 实施方案细节"
   },
   {
    "id": "706-与现有机制的协同",
    "text": "70.6 与现有机制的协同"
   },
   {
    "id": "707-效果评估",
    "text": "70.7 效果评估"
   },
   {
    "id": "708-影响文件",
    "text": "70.8 影响文件"
   },
   {
    "id": "709-遗留讨论",
    "text": "70.9 遗留讨论"
   },
   {
    "id": "71-卡片转场动画防掉帧与预加载策略-2026-05-30",
    "text": "71. 卡片转场动画防掉帧与预加载策略 (2026-05-30)"
   },
   {
    "id": "711-痛点与现象描述",
    "text": "71.1 痛点与现象描述"
   },
   {
    "id": "712-根本原因分析",
    "text": "71.2 根本原因分析"
   },
   {
    "id": "713-渐进式渲染错峰挂载解决方案",
    "text": "71.3 渐进式渲染（错峰挂载）解决方案"
   },
   {
    "id": "714-概念澄清与架构约束交接备忘",
    "text": "71.4 概念澄清与架构约束（交接备忘）"
   },
   {
    "id": "106-阅读进度条视觉滞后问题修复-2026-06-07",
    "text": "106. 阅读进度条视觉滞后问题修复 (2026-06-07)"
   },
   {
    "id": "1061-问题描述",
    "text": "106.1 问题描述"
   },
   {
    "id": "1062-原因分析",
    "text": "106.2 原因分析"
   },
   {
    "id": "1063-讨论与决策",
    "text": "106.3 讨论与决策"
   },
   {
    "id": "1064-修复方案",
    "text": "106.4 修复方案"
   },
   {
    "id": "124-macos-右侧文章详情面板滚动条跳动修复2026-06-08",
    "text": "124. macOS 右侧文章详情面板滚动条跳动修复（2026-06-08）"
   },
   {
    "id": "1241-问题报告",
    "text": "124.1 问题报告"
   },
   {
    "id": "1242-根因分析",
    "text": "124.2 根因分析"
   },
   {
    "id": "1243-修复方案",
    "text": "124.3 修复方案"
   },
   {
    "id": "1244-行为变化对照",
    "text": "124.4 行为变化对照"
   },
   {
    "id": "1245-验证结果",
    "text": "124.5 验证结果"
   },
   {
    "id": "1246-修改文件清单",
    "text": "124.6 修改文件清单"
   },
   {
    "id": "1247-遗留风险与改进空间",
    "text": "124.7 遗留风险与改进空间"
   },
   {
    "id": "1248-讨论过程摘要",
    "text": "124.8 讨论过程摘要"
   },
   {
    "id": "156-macos-文章页滚动期无体验变化的小性能优化2026-07-03",
    "text": "156. macOS 文章页滚动期无体验变化的小性能优化（2026-07-03）"
   },
   {
    "id": "158-macos-文章正文与设置页滚动卡顿回归排查2026-07-04",
    "text": "158. macOS 文章正文与设置页滚动卡顿回归排查（2026-07-04）"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：性能、滚动与进度 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 14. 图片渲染性能优化（v1.4） 14.1 问题诊断 用户反馈： 有图片的文章帧率出现下降 。 根据代码审查，主要性能瓶颈： CachedNetworkImage 配置不完整 只限制了 memCacheWidth/maxWidthDiskCache（宽度） 缺少 memCacheHeight/maxHeightDiskCache（高度） 导致多图片文章时内存占用过高，触发 GC 频繁卡顿 占位符渲染开销 placeholder 中使用 CircularProgressIndicator 持续动画 多张图片加载时（10+ 张），10+ 个圈同时转，占用大量 GPU 资源 导致主线程帧率下降到 30fps 或以下 flutter_html 解析开销 HTML 字符串在 build() 中被完整解析 虽然已在 onInit 时规范化，但 flutter_html 仍会全量重新解析 TagExtension 对每个 <img> 都触发 builder 回调 14.2 实施改进 改进 1：添加 memCacheHeight 和 maxHeightDiskCache final cacheHeight = (300 * dpr).round(); // 限制高度为 300dp CachedNetworkImage( memCacheWidth: cacheWidth, memCacheHeight: cacheHeight, // 新增 maxWidthDiskCache: cacheWidth, maxHeightDiskCache: cacheHeight, // 新增 ) 收益 ： 减少 50-70% 的内存占用 降低 GC 频率和 GC 时长 帧率稳定度提升 改进 2：替换占位符为静态容器 前 ： placeholder: (context, url) => AspectRatio( child: Container( child: CircularProgressIndicator(...), // 持续动画，占用 GPU ), ), 后 ： placeholder: (context, url) => AspectRatio( child: Container( color: colorScheme.surfaceContainerHighest, // 静态颜色块 ), ), 收益 ： 消除 GPU 动画压力 帧率立刻提升到 60fps 用户体验明显改善 改进 3：错误态占位符（保留可点重试） errorWidget: (context, url, error) => AspectRatio( child: InkWell( onTap: () => setState(() => _retryCount++), child: Container(...), // 静态显示 ), ), 14.3 预期效果 主观体验 ：打开图片文章时不再感受到明显卡顿 帧率 ：从 30-40fps 稳定到 50-60fps 内存 ：多图片文章的峰值内存从 200+MB 降到 100-150MB 14.4 后续可选优化 为卡片图片也添加 cacheHeight （类似改造 ArticleCard） 实现图片加载优先级 （优先加载首屏可见图片） 考虑升级或更换 HTML 渲染库 （如果问题仍严重） 14.5 修改文件清单 lib/pages/article/article_page.dart — 修改 _ArticleInlineImageState.build() 添加 memCacheHeight/maxHeightDiskCache 替换占位符为静态容器 42. 性能优化 — 卡顿修复（2026-05-20） 静态 Dio 实例 ：翻译/摘要/过滤三个服务各用 static final _dio ，不再每条请求 new Dio(BaseOptions(...)) normalizeHtml 缓存 ： ArticleContentUtils.normalizeHtmlForEntry(entryId, html) 用 LinkedHashMap 做 200 条 LRU 缓存，翻译和摘要各调一次但共享结果，同篇长文章不再 DOM 解析两遍 审核页增量推送 ：过滤 Worker 完成一篇后通过 onRejected 回调直接推送单篇到审核列表（O(1)），替代 ever(doneCount) 每完成一篇扫全库 5000 篇（O(5000)） onRejected 回调仅在审核页可见时注册（ initState / deactivate / dispose ），后台不触发 62. 性能优化（2026-05-25） 不影响任何现有功能与体验， dart analyze 零新增 warning， flutter build apk --debug 通过。 62.1 API 请求并行化 TimelineController.loadData() 和 FeedDetailController.loadData() 中 3 个串行 await （feeds / social / inbox）改为 Future.wait 并行。 _refreshRecentReadWindow() 中 2 个串行 await （feeds read / social read）同样改为 Future.wait 。 62.2 正则表达式编译缓存 translation_service.dart 、 article_content_utils.dart 、 html_chunk_parser.dart 、 source_taxonomy.dart 共 9 处方法内 RegExp(...) 提升为 static final 常量。 62.3 不必要的 ArticleModel 全字段拷贝消除 _mergeLocalReadState() 增加守卫条件：只在本地 readState 与当前 isRead 不同时才创建新对象。 _updateReadStateInMemory() 从 .map() 全列表遍历改为 indexWhere 单点定位。 62.4 searchSourceArticles 去拷贝 TimelineController.searchSourceArticles 从 allArticles.toList() 改为直接返回 allArticles 引用。 62.5 骨架屏动画代码去重 新增 ShimmerFadeList （ lib/common/widgets/shimmer_card.dart ），三处独立动画控制器替换为统一组件。 62.6 Hive 批量写入 L"
 },
 {
  "path": "history/archive/release-git-and-ci.html",
  "title": "历史归档：发布、Git、Worktree 与 CI",
  "headings": [
   {
    "id": "历史版本标记",
    "text": "历史版本标记"
   },
   {
    "id": "49-最终打磨与-v100-beta1-发布2026-05-23",
    "text": "49. 最终打磨与 v1.0.0-beta1 发布（2026-05-23）"
   },
   {
    "id": "导航栏玻璃质感调优",
    "text": "导航栏玻璃质感调优"
   },
   {
    "id": "图片预加载性能修复",
    "text": "图片预加载性能修复"
   },
   {
    "id": "文章详情页微调",
    "text": "文章详情页微调"
   },
   {
    "id": "时间线过滤入口",
    "text": "时间线过滤入口"
   },
   {
    "id": "分批提交与-v100-beta1",
    "text": "分批提交与 v1.0.0-beta1"
   },
   {
    "id": "50-仓库管理规范2026-05-23",
    "text": "50. 仓库管理规范（2026-05-23）"
   },
   {
    "id": "一提交粒度",
    "text": "一、提交粒度"
   },
   {
    "id": "二tag-管理",
    "text": "二、Tag 管理"
   },
   {
    "id": "三文档同步",
    "text": "三、文档同步"
   },
   {
    "id": "四全局状态变更通知",
    "text": "四、全局状态变更通知"
   },
   {
    "id": "五flutter-代码规范",
    "text": "五、Flutter 代码规范"
   },
   {
    "id": "六当前已知问题非待修",
    "text": "六、当前已知问题（非待修）"
   },
   {
    "id": "57-v100-beta2-发布2026-05-23",
    "text": "57. v1.0.0-beta2 发布（2026-05-23）"
   },
   {
    "id": "80-android-macos-内部发布流程2026-06-01",
    "text": "80. Android + macOS 内部发布流程（2026-06-01）"
   },
   {
    "id": "801-本次发布命名与版本",
    "text": "80.1 本次发布命名与版本"
   },
   {
    "id": "802-github-actions-工作流",
    "text": "80.2 GitHub Actions 工作流"
   },
   {
    "id": "803-macos-arm64-约束",
    "text": "80.3 macOS arm64 约束"
   },
   {
    "id": "804-本次踩坑与修复",
    "text": "80.4 本次踩坑与修复"
   },
   {
    "id": "805-已验证结果",
    "text": "80.5 已验证结果"
   },
   {
    "id": "806-当前仓库状态注意",
    "text": "80.6 当前仓库状态注意"
   },
   {
    "id": "81-worktree-复核必要改动吸收与-v112-发布2026-06-02",
    "text": "81. worktree 复核、必要改动吸收与 v1.1.2 发布（2026-06-02）"
   },
   {
    "id": "811-用户要求与判断过程",
    "text": "81.1 用户要求与判断过程"
   },
   {
    "id": "812-已合入的代码提交",
    "text": "81.2 已合入的代码提交"
   },
   {
    "id": "813-验证结果",
    "text": "81.3 验证结果"
   },
   {
    "id": "814-v112-内部发布计划",
    "text": "81.4 v1.1.2 内部发布计划"
   },
   {
    "id": "815-后续-agent-注意事项",
    "text": "81.5 后续 agent 注意事项"
   },
   {
    "id": "816-v112-远端发布结果",
    "text": "81.6 v1.1.2 远端发布结果"
   },
   {
    "id": "91-四个-antigravity-worktree-的最终合入审计2026-06-06",
    "text": "91. 四个 antigravity worktree 的最终合入审计（2026-06-06）"
   },
   {
    "id": "911-背景",
    "text": "91.1 背景"
   },
   {
    "id": "912-合入时保留与修正的重点",
    "text": "91.2 合入时保留与修正的重点"
   },
   {
    "id": "913-验证结果",
    "text": "91.3 验证结果"
   },
   {
    "id": "914-git-状态提醒",
    "text": "91.4 Git 状态提醒"
   },
   {
    "id": "92-版本号统一与-v117-发布自动化2026-06-06",
    "text": "92. 版本号统一与 v1.1.7 发布自动化（2026-06-06）"
   },
   {
    "id": "921-背景",
    "text": "92.1 背景"
   },
   {
    "id": "922-本轮修改",
    "text": "92.2 本轮修改"
   },
   {
    "id": "923-本次发布版本",
    "text": "92.3 本次发布版本"
   },
   {
    "id": "924-后续发布约定",
    "text": "92.4 后续发布约定"
   },
   {
    "id": "110-v1112-release-job-的-annotated-tag-校验修复2026-06-08",
    "text": "110. v1.1.12 Release Job 的 annotated tag 校验修复（2026-06-08）"
   },
   {
    "id": "1101-失败现象",
    "text": "110.1 失败现象"
   },
   {
    "id": "1102-根因与修复",
    "text": "110.2 根因与修复"
   },
   {
    "id": "1103-发布处理",
    "text": "110.3 发布处理"
   },
   {
    "id": "114-worktree-安全合并检查点2026-06-08",
    "text": "114. Worktree 安全合并检查点（2026-06-08）"
   },
   {
    "id": "125-1115-beta-合并验证上下文2026-06-08",
    "text": "125. 1.1.15 beta 合并验证上下文（2026-06-08）"
   },
   {
    "id": "1251-背景",
    "text": "125.1 背景"
   },
   {
    "id": "1252-合入顺序",
    "text": "125.2 合入顺序"
   },
   {
    "id": "1253-关键冲突与手工合成",
    "text": "125.3 关键冲突与手工合成"
   },
   {
    "id": "1254-发布前验证",
    "text": "125.4 发布前验证"
   },
   {
    "id": "1255-发布计划",
    "text": "125.5 发布计划"
   },
   {
    "id": "127-readme-精简与图标美化",
    "text": "127. README 精简与图标美化"
   },
   {
    "id": "1271-背景与动机",
    "text": "127.1 背景与动机"
   },
   {
    "id": "1272-关键发现与讨论",
    "text": "127.2 关键发现与讨论"
   },
   {
    "id": "1273-最终实现",
    "text": "127.3 最终实现"
   },
   {
    "id": "1274-注意事项",
    "text": "127.4 注意事项"
   },
   {
    "id": "159-v1126-release-notes-换行格式修复2026-07-04",
    "text": "159. v1.1.26 Release Notes 换行格式修复（2026-07-04）"
   },
   {
    "id": "160-releasesh-对字面量-\\n-的策略改为-fail-fast2026-07-04",
    "text": "160. release.sh 对字面量 \\n 的策略改为 fail-fast（2026-07-04）"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：发布、Git、Worktree 与 CI 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 历史版本标记 49. 最终打磨与 v1.0.0-beta1 发布（2026-05-23） 导航栏玻璃质感调优 底栏背景从 surface(0.8) 降至 surface(0.40) ，瀑布流内容更多穿透 选中态指示器从 primary(0.15) 提至 primary(0.80) ，橙色标识更鲜明 顶栏 + 底栏均使用 BackdropFilter(blur: 16) 实现 iOS 风格毛玻璃 图片预加载性能修复 预加载隐藏 Stack 的 CachedNetworkImage 加上 memCacheWidth: 150 + maxWidthDiskCache: 300 原因：不加约束时每张图片以原始分辨率解码（>2000px），20 张同时解码打爆主线程 效果：预加载仅解码 150px 缩略图，CPU 开销降 ~90% 文章详情页微调 标题下方移除\"查看网页原文\"文字 + 图标，标题本身已可点击跳转 _SummaryCard 日间模式透明度从 0.25 降至 0.10 ，极淡底色改善可读性 FAB AnimatedScale 回退（效果太细微无法感知） 审核页 Dismissible 阈值调整： 0.3 → 0.5 （防误触） 时间线过滤入口 _buildFilterBar 移除 if (count <= 0) return 条件，入口始终可见 审核页\"AI 判定\"标签移除（卡片自带原因显示，防止重复） 分批提交与 v1.0.0-beta1 10 个 commit 按模块拆分： ColorScheme 手写体系 + 移除 DynamicColorBuilder _FadeIndexedStack 页面切换 + 底栏毛玻璃 过滤入口卡片重设计 + 骨架屏 审核页进度条 + 拒绝标签 + Dismissible 文章页 _ToolbarRow + _Chip + 摘要卡 + 预加载 fix 内联图片淡入 + 图片画廊手势 文章卡片布局 + 搜索栏 FeedDetail 控制器分离 + 骨架加载 订阅源三层缩进 + 动画打磨 设置页副标题 + FeedbackToast 重写 Tag: v1.0.0-beta1 — 功能完备（AI 过滤 + 翻译 + 摘要），橙色主题，全 UI 打磨。 50. 仓库管理规范（2026-05-23） 以下规则记录到文档中以便未来 AGENT 和协作者严格遵循。 一、提交粒度 一个 commit = 一个可独立回退的逻辑改动 禁止混合 \"修 bug + 顺带改 UI\"——示例反例： f9b06ad （物理引擎+图片画廊+导航三者合一） 不跨模块提交： Refactor: ArticlePage 不夹带 FilterReviewPage 的修改 二、Tag 管理 永不 force-update ：每次发版新建 tag，如 v1.0.0-beta2 、 v1.0.0-rc1 beta 阶段可密集发（按天/按功能），RC 之后减速 tag 注释写完整：日期 + 核心改动 + 对应的文档 § 编号 删除旧 tag 只在修复错打时使用，不使用 -f 覆盖 三、文档同步 commit message 引用对应 § 编号（格式： Refactor: xxx (§12) 或 Fix: xxx, see §8 ） 每个功能完成 → 立即更新文档，不打完 tag 才补文档 tag 打在文档和代码一起提交的 commit 上 § 编号应连续递增，不跳号、不重号 四、全局状态变更通知 任何涉及 ArticleStateNotifier.tick() 的改动，必须验证 6 个消费者页面全部正常： timeline_page · timeline_controller · filter_review_page · article_page · feed_detail_page · subscriptions_controller 新增消费者时在本文档登记 五、Flutter 代码规范 结构性重构（>30 行）使用 write_file 一次性写入，避免 edit_file 重复修改导致括号混乱 嵌套超过 3 层的 widget 提取为独立 StatelessWidget 或辅助方法 修改全局 ColorScheme 后抽查 3 个以上页面 六、当前已知问题（非待修） 项 说明 f9b06ad 提交粒度过大 混了物理引擎+图片画廊+导航，历史记录，不阻塞 硬编码色值 filter_review_page 绿色滑动、 timeline_page 琥珀过滤等为 语义色 ，刻意设计，不为违规 tag 被 force-update v1.0.0-beta1 覆盖 3 次，从下个版本严格递增 57. v1.0.0-beta2 发布（2026-05-23） 移除 flutter_app_badger 、 move_to_background 外部依赖，全部改为自写 MethodChannel Vivo/OriginOS 角标：ContentProvider 直写实现（待系统级验证） 自写 AppBadger 、 MoveToBackground 实用类 设置页新增「通知与角标」区块 翻译管线全链路稳定：启动自愈 → 表格扁平化 → 大文章分块并行 → 异常全面捕获 Tag: v1.0.0-beta2 80. Android + macOS 内部发布流程（2026-06-01） 80.1 本次发布命名与版本 推荐并采用 tag： v1.1.1 。 版本号同步： pubspec.yaml ： version: 1.1.1+3 lib/http/init.dart ： X-App-Version: 1.1.1 lib/pages/settings/settings_page.dart ：关于页显示 Auto Folo v1.1.1 CHANGELOG.md ：新增 1.1.1 - 2026-06-01 用户当前只自用，不考虑软件商城；发布策略按“内部测试版”处理，直接产出 APK 和 macOS zip。 80.2 GitHub Actions 工作流 文件： .github/workflows/internal-release.yml 触发方式： push tag，匹配 v* 。 workflow_dispatch 手动触发。 工作流结构： Android APK runner： ubuntu-latest Java：Temurin 17 Flutter： subosito/flutter-action@v2 ，固定 flutter-version: '3.41.6' 验证： flutter analyze --no-fatal"
 },
 {
  "path": "history/archive/settings-identity-and-migration.html",
  "title": "历史归档：设置、身份与迁移",
  "headings": [
   {
    "id": "74-设置页任务中心2026-05-31",
    "text": "74. 设置页任务中心（2026-05-31）"
   },
   {
    "id": "741-产品定位",
    "text": "74.1 产品定位"
   },
   {
    "id": "742-第一版范围",
    "text": "74.2 第一版范围"
   },
   {
    "id": "743-有意不做",
    "text": "74.3 有意不做"
   },
   {
    "id": "744-影响文件",
    "text": "74.4 影响文件"
   },
   {
    "id": "142-设置导入导出到剪贴板2026-06-19",
    "text": "142. 设置导入/导出到剪贴板（2026-06-19）"
   },
   {
    "id": "1421-背景",
    "text": "142.1 背景"
   },
   {
    "id": "1422-实现",
    "text": "142.2 实现"
   },
   {
    "id": "1423-验证",
    "text": "142.3 验证"
   },
   {
    "id": "1424-后续流程",
    "text": "142.4 后续流程"
   },
   {
    "id": "143-应用命名空间迁移与非官方声明2026-06-19",
    "text": "143. 应用命名空间迁移与非官方声明（2026-06-19）"
   },
   {
    "id": "1431-背景与边界",
    "text": "143.1 背景与边界"
   },
   {
    "id": "1432-当前标识",
    "text": "143.2 当前标识"
   },
   {
    "id": "1433-实现文件",
    "text": "143.3 实现文件"
   },
   {
    "id": "1434-安装与数据影响",
    "text": "143.4 安装与数据影响"
   },
   {
    "id": "1435-后续验证重点",
    "text": "143.5 后续验证重点"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：设置、身份与迁移 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 74. 设置页任务中心（2026-05-31） 74.1 产品定位 用户明确希望审核页的高频交互和入口保持不变，因此任务中心不承载逐篇审核流程。任务中心定位为设置页内的低频诊断入口，用于查看后台同步和 AI 队列是否正常。 74.2 第一版范围 入口： 设置页新增“后台任务与同步”卡片。 路由： Routes.taskCenter / /task-center 。 页面能力： 总览本地文章数、未读数、待人工审核数。 查看已读待同步数量和最近已读同步时间。 手动触发“同步已读”。 查看 AI 过滤、自动翻译、自动摘要的排队数、处理中数和失败数。 AI 过滤区只提供“去审核”跳转，不展示审核列表，不替代 FilterReviewPage 。 自动翻译/自动摘要失败时，可从任务中心进入失败文章列表，逐篇查看失败原因，并对单篇文章执行“打开”或“重试”。 74.3 有意不做 第一版不做暂停/继续、清空队列、批量重试、详细日志和批量审核。原因是这些操作会改变后台行为，容易引入误操作和更复杂的状态恢复；当前阶段只解决“用户能看懂后台是否在工作”的问题。 这里的“单篇重试”不是批量操作：用户明确希望能在 AI 任务下排查“是哪篇文章失败了”，并对具体文章手动处理。因此任务中心允许查看失败明细和单篇重试，但仍不提供“一键全部重试”。 74.4 影响文件 lib/pages/settings/task_center_page.dart — 新增任务中心页面。 lib/pages/settings/settings_page.dart — 设置页入口卡片。 lib/router/app_pages.dart — 新增任务中心路由。 lib/services/read_sync_service.dart — 记录最近已读同步时间。 lib/services/auto_translation_worker.dart / auto_summary_worker.dart — 暴露当前处理中数量。 lib/services/translation_service.dart / summary_service.dart — 提供按状态计数和失败记录查询，用于失败数量展示和失败明细页。 142. 设置导入/导出到剪贴板（2026-06-19） 142.1 背景 由于后续将整改 Android applicationId 和 macOS PRODUCT_BUNDLE_IDENTIFIER ，新安装包会使用新的应用身份和数据容器，旧设置不会自动共享。用户希望先发布一个临时版本，用旧包名安装后导出配置，再在改包名后的版本中导入。 讨论后决定： 使用纯 JSON 字典格式，不包额外前缀。 只导出“设置、偏好和密钥”，不导出文章内容、已读历史、摘要/翻译缓存。 手机端和电脑端共用同一套配置格式；平台不使用的配置可以保存但不生效。 导入时应覆盖当前已保存的受管理设置，形成接近快照恢复的效果。 142.2 实现 lib/services/settings_backup_service.dart ： 新增 SettingsBackupService 。 导出格式： { \"type\": \"auto_folo_settings\", \"version\": 1, \"exportedAt\": \"2026-06-19T00:00:00.000Z\", \"settings\": { \"session_token\": \"...\", \"client_id\": \"...\", \"session_id\": \"...\" } } 导出只收集 allowlist： 固定 key：Folo 凭据、DeepSeek API key、Prompt、自动重试、已读拉取窗口、角标策略、正文最大宽度。 LLM 前缀： llm_translate_ 、 llm_summary_ 、 llm_filter_ 。 订阅源偏好前缀： feed_auto_translate_ 、 feed_silent_ 、 feed_auto_readability_ 。 导入时校验 type 和 version 。 导入时只接受字符串、数字、布尔等 JSON primitive，并按 key 归一化类型： temperature 写入 double。 max_tokens / concurrency / 窗口天数 / 正文宽度 / 重试次数写入 int。 thinking 和订阅源偏好写入 bool。 导入时先删除所有受管理 key，再写入 JSON 内的设置，避免旧订阅源偏好残留。 导入后刷新 DeepSeek API key 的运行期缓存，并递增静默订阅源版本号以触发 UI 响应。 lib/pages/settings/settings_page.dart ： 新增“配置迁移”区块。 新增“导出到剪贴板”和“从剪贴板导入”按钮。 导出前提示 JSON 包含 Folo 登录凭据、DeepSeek API key、Prompt 和订阅源偏好。 导入前提示会覆盖当前设置，且不会导入文章缓存、已读历史、摘要和翻译结果。 导入成功后刷新设置页表单和 AccountService 登录状态。 lib/services/account_service.dart ： 新增 reload() ，供导入配置后重新计算登录状态。 142.3 验证 已执行： dart format lib/services/settings_backup_service.dart lib/services/account_service.dart lib/pages/settings/settings_page.dart dart analyze lib/services/settings_backup_service.dart lib/services/account_service.dart lib/pages/settings/settings_page.dart flutter analyze --no-fatal-infos lib test flutter test 结果均通过。 flutter analyze 和 flutter test 首次被 Flutter SDK cache 写入权限拦截，授权后重跑通过。 142.4 后续流程 本版本用于让用户在旧应用身份下导出配置。用户安装本临时版本并导出 JSON 后，再继续进行 com.folo.* 命名空间整改。整改后的新包将使用同一套导入逻辑恢复配置。 143. 应用命名空间迁移与非官方声明（2026-06-19） 143.1 背景与边界 用户确认：本项目不需要隐藏与 Folo 的关系，也不需要把 Auto Folo"
 },
 {
  "path": "history/archive/subscriptions-and-sync.html",
  "title": "历史归档：订阅源、缓存与同步",
  "headings": [
   {
    "id": "11-social-类别拉取修复v12-新增",
    "text": "11. Social 类别拉取修复（v1.2 新增）"
   },
   {
    "id": "111-问题描述",
    "text": "11.1 问题描述"
   },
   {
    "id": "112-根本原因",
    "text": "11.2 根本原因"
   },
   {
    "id": "113-修复实现",
    "text": "11.3 修复实现"
   },
   {
    "id": "114-修改文件清单",
    "text": "11.4 修改文件清单"
   },
   {
    "id": "115-预期效果",
    "text": "11.5 预期效果"
   },
   {
    "id": "116-验证方式",
    "text": "11.6 验证方式"
   },
   {
    "id": "12-inbox-拉取集成v12-扩展",
    "text": "12. Inbox 拉取集成（v1.2 扩展）"
   },
   {
    "id": "121-理解",
    "text": "12.1 理解"
   },
   {
    "id": "122-实现",
    "text": "12.2 实现"
   },
   {
    "id": "123-预期效果",
    "text": "12.3 预期效果"
   },
   {
    "id": "124-修改文件清单",
    "text": "12.4 修改文件清单"
   },
   {
    "id": "16-订阅源三级分组与视图标签2026-05-17",
    "text": "16. 订阅源三级分组与视图标签（2026-05-17）"
   },
   {
    "id": "161-需求",
    "text": "16.1 需求"
   },
   {
    "id": "162-实现",
    "text": "16.2 实现"
   },
   {
    "id": "163-注意事项",
    "text": "16.3 注意事项"
   },
   {
    "id": "17-文章来源跳转2026-05-17",
    "text": "17. 文章来源跳转（2026-05-17）"
   },
   {
    "id": "171-需求",
    "text": "17.1 需求"
   },
   {
    "id": "172-实现",
    "text": "17.2 实现"
   },
   {
    "id": "173-注意事项",
    "text": "17.3 注意事项"
   },
   {
    "id": "20-过滤页首屏复用全局缓存2026-05-17",
    "text": "20. 过滤页首屏复用全局缓存（2026-05-17）"
   },
   {
    "id": "201-需求",
    "text": "20.1 需求"
   },
   {
    "id": "202-实现",
    "text": "20.2 实现"
   },
   {
    "id": "203-注意事项",
    "text": "20.3 注意事项"
   },
   {
    "id": "26-已读失败重试队列2026-05-18",
    "text": "26. 已读失败重试队列（2026-05-18）"
   },
   {
    "id": "261-问题",
    "text": "26.1 问题"
   },
   {
    "id": "262-处理策略",
    "text": "26.2 处理策略"
   },
   {
    "id": "263-影响文件",
    "text": "26.3 影响文件"
   },
   {
    "id": "29-双击时间线底栏回顶部2026-05-18",
    "text": "29. 双击时间线底栏回顶部（2026-05-18）"
   },
   {
    "id": "291-调整内容",
    "text": "29.1 调整内容"
   },
   {
    "id": "292-影响文件",
    "text": "29.2 影响文件"
   },
   {
    "id": "36-inbox-空内容修复2026-05-20",
    "text": "36. Inbox 空内容修复（2026-05-20）"
   },
   {
    "id": "38-已读状态双向同步2026-05-20",
    "text": "38. 已读状态双向同步（2026-05-20）"
   },
   {
    "id": "39-订阅源未读计数2026-05-20",
    "text": "39. 订阅源未读计数（2026-05-20）"
   },
   {
    "id": "41-feeddetail-对齐2026-05-20",
    "text": "41. FeedDetail 对齐（2026-05-20）"
   },
   {
    "id": "43-articlestatenotifier-全局状态通知2026-05-20",
    "text": "43. ArticleStateNotifier 全局状态通知（2026-05-20）"
   },
   {
    "id": "44-feeddetail-已读筛选-tickentryid-增量2026-05-21",
    "text": "44. FeedDetail 已读筛选 + tick(entryId) 增量（2026-05-21）"
   },
   {
    "id": "46-主页时间线重大交互与逻辑重构2026-05-22",
    "text": "46. 主页时间线重大交互与逻辑重构（2026-05-22）"
   },
   {
    "id": "47-刷新圈反悔手势阻断优化2026-05-22",
    "text": "47. 刷新圈反悔手势阻断优化（2026-05-22）"
   },
   {
    "id": "52-通知角标-退后台2026-05-23",
    "text": "52. 通知角标 + 退后台（2026-05-23）"
   },
   {
    "id": "63-已读同步全面修复2026-05-25",
    "text": "63. 已读同步全面修复（2026-05-25）"
   },
   {
    "id": "631-问题报告",
    "text": "63.1 问题报告"
   },
   {
    "id": "632-实验过程",
    "text": "63.2 实验过程"
   },
   {
    "id": "633-三重根因",
    "text": "63.3 三重根因"
   },
   {
    "id": "634-设计讨论",
    "text": "63.4 设计讨论"
   },
   {
    "id": "635-具体改动",
    "text": "63.5 具体改动"
   },
   {
    "id": "636-行为变化对照",
    "text": "63.6 行为变化对照"
   },
   {
    "id": "637-未改动文件",
    "text": "63.7 未改动文件"
   },
   {
    "id": "638-遗留问题与安全分页方案研究pending-review-next-steps",
    "text": "63.8 遗留问题与安全分页方案研究（Pending Review & Next Steps）"
   },
   {
    "id": "67-解决全局状态变更导致的时间线-ui-失步问题2026-05-26",
    "text": "67. 解决全局状态变更导致的时间线 UI 失步问题（2026-05-26）"
   },
   {
    "id": "671-问题背景",
    "text": "67.1 问题背景"
   },
   {
    "id": "672-增量同步机制设计单点精确刷新",
    "text": "67.2 增量同步机制设计（单点精确刷新）"
   },
   {
    "id": "673-影响文件",
    "text": "67.3 影响文件"
   },
   {
    "id": "68-修复-inbox-旧文章不可见被-5000-条本地缓存限制误删的问题-2026-05-26",
    "text": "68. 修复 Inbox 旧文章不可见（被 5000 条本地缓存限制误删）的问题 (2026-05-26)"
   },
   {
    "id": "681-背景与现象",
    "text": "68.1 背景与现象"
   },
   {
    "id": "682-诊断过程",
    "text": "68.2 诊断过程"
   },
   {
    "id": "683-修复方案与逻辑简化",
    "text": "68.3 修复方案与逻辑简化"
   },
   {
    "id": "684-影响分析与架构哲学记录",
    "text": "68.4 影响分析与架构哲学记录"
   },
   {
    "id": "138-静默订阅源功能实现v119-本轮新增",
    "text": "138. 静默订阅源功能实现（v1.19 / 本轮新增）"
   },
   {
    "id": "1381-需求与背景",
    "text": "138.1 需求与背景"
   },
   {
    "id": "1382-核心实现思路",
    "text": "138.2 核心实现思路"
   },
   {
    "id": "1383-新增与修改细节",
    "text": "138.3 新增与修改细节"
   },
   {
    "id": "1384-遗留潜在待优化方向",
    "text": "138.4 遗留/潜在待优化方向"
   },
   {
    "id": "1385-补充更新ui-交互优化与状态绑定-bug-修复",
    "text": "138.5 补充更新（UI 交互优化与状态绑定 Bug 修复）"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：订阅源、缓存与同步 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 11. Social 类别拉取修复（v1.2 新增） 11.1 问题描述 首页只拉取了 Folo API 的 view=0 （feeds 未读）条目，忽略了 view=1 （social 未读）条目。根据实际调用结果： view=0 返回 68 篇未读文章 view=1 返回 30 篇未读文章 但首页只显示 ~49 篇（部分文章可能已读） 导致首页缺少约 30% 的内容。 11.2 根本原因 TimelineController 和 FeedDetailController 的 loadData() 与 _refreshRecentReadWindow() 都只调用了 FeedHttp.collectEntries(view: 0, ...) ，没有并行拉取 view=1 的条目。 11.3 修复实现 修改 ArticleModel.fromEntryJson() 添加 view 参数，自动设置 category 为 'feeds' 或 'social'： factory ArticleModel.fromEntryJson( Map<String, dynamic> item, { String? feedTitle, String? subscriptionCategory, int view = 0, }) { // ... 其他代码不变 final category = view == 1 ? 'social' : 'feeds'; return ArticleModel( // ... category: category, // ... ); } 修改 FeedHttp.getEntries() 在调用 fromEntryJson() 时传入 view 参数： return ArticleModel.fromEntryJson( json, feedTitle: f?.title, subscriptionCategory: f?.category, view: view, // 新增此行 ); 修改 TimelineController.loadData() 分别拉取 feeds 和 social 的未读，然后合并： final feedsResult = await FeedHttp.collectEntries( view: 0, withContent: true, feedMap: _feedMap, ); final socialResult = await FeedHttp.collectEntries( view: 1, withContent: true, feedMap: _feedMap, ); final unreadData = <ArticleModel>[]; if (feedsResult is Success<List<ArticleModel>>) { unreadData.addAll(feedsResult.response); } if (socialResult is Success<List<ArticleModel>>) { unreadData.addAll(socialResult.response); } 修改 TimelineController._refreshRecentReadWindow() 同样分别拉取 feeds 和 social 的已读条目，然后合并： final feedsReadResult = await FeedHttp.collectEntries( view: 0, read: true, withContent: true, publishedAfter: windowStart.toUtc().toIso8601String(), feedMap: _feedMap, maxPages: 5, ); final socialReadResult = await FeedHttp.collectEntries( view: 1, read: true, withContent: true, publishedAfter: windowStart.toUtc().toIso8601String(), feedMap: _feedMap, maxPages: 5, ); final readData = <ArticleModel>[]; if (feedsReadResult is Success<List<ArticleModel>>) { readData.addAll(feedsReadResult.response); } if (socialReadResult is Success<List<ArticleModel>>) { readData.addAll(socialReadResult.response); } 修改 FeedDetailController 在 loadData() 和 _refreshRecentReadWindow() 中应用相同的改动，确保按 feed 或 category 筛选时也能包含 social 条目。 11.4 修改文件清单 lib/models/article.dart — 修改 fromEntryJson() 添加 view 参数 lib/http/feed_http.dart — 修改 getEntries() 传入 view 参数 lib/pages/timeline/timeline_controller.dart — 修改 loadData() 和 _refreshRecentReadWindow() lib/pages/feed_detail/feed_detail_page.dart — 修改 loadData() 和 _refreshRecentReadWindow() 11.5 预期效果 首页现在应该能显示 ~98 篇未读文章（68 feeds + 30 social） 已读补抓也覆盖 social 条目，确保已读状态同步完整 时间线/分类详情都能混合展示 feeds 和 social 的文章 11.6 验证方式 登录后进入首页，观察未读数量是否接近 98 在设置里设置较小的已读补抓窗口（如 1 天），观察是否能补抓到 social 的已读文章 查看本地文章库中的 category 字段，确保 social 条目被正确标记为 'social' 12. Inbox 拉取集成（v1.2 扩展） 12.1 理解 参考工程中 inbox 不是独立页面，而是一种文章 category ，与 'feeds' 和 'social' 平级。在未读列表中，需要同时拉取： view=0 "
 },
 {
  "path": "history/archive/timeline-and-navigation.html",
  "title": "历史归档：时间线与导航",
  "headings": [
   {
    "id": "25-文章左右滑动切换2026-05-18",
    "text": "25. 文章左右滑动切换（2026-05-18）"
   },
   {
    "id": "251-需求",
    "text": "25.1 需求"
   },
   {
    "id": "252-实现",
    "text": "25.2 实现"
   },
   {
    "id": "253-影响文件",
    "text": "25.3 影响文件"
   },
   {
    "id": "88-macos-分屏模式下连续标记已读导致导航失效的修复补记于-2026-06-05",
    "text": "88. macOS 分屏模式下连续标记已读导致导航失效的修复（补记于 2026-06-05）"
   },
   {
    "id": "881-现象与问题诊断",
    "text": "88.1 现象与问题诊断"
   },
   {
    "id": "882-解决方案与实现",
    "text": "88.2 解决方案与实现"
   },
   {
    "id": "883-后续防退化设计说明",
    "text": "88.3 后续防退化设计说明"
   },
   {
    "id": "90-macos-端最近阅读功能实现与语义修正-2026-06-05",
    "text": "90. macOS 端“最近阅读”功能实现与语义修正 (2026-06-05)"
   },
   {
    "id": "901-需求背景与痛点",
    "text": "90.1 需求背景与痛点"
   },
   {
    "id": "902-技术选型与实现方案",
    "text": "90.2 技术选型与实现方案"
   },
   {
    "id": "903-本次合入前发现并修正的问题",
    "text": "90.3 本次合入前发现并修正的问题"
   },
   {
    "id": "904-关键注意事项与后续交接建议",
    "text": "90.4 关键注意事项与后续交接建议"
   },
   {
    "id": "97-键盘导航列表自动滚动定位-2026-06-06",
    "text": "97. 键盘导航列表自动滚动定位 (2026-06-06)"
   },
   {
    "id": "971-需求与问题背景",
    "text": "97.1 需求与问题背景"
   },
   {
    "id": "972-实现方案考量",
    "text": "97.2 实现方案考量"
   },
   {
    "id": "973-具体的修改",
    "text": "97.3 具体的修改"
   },
   {
    "id": "974-注意事项",
    "text": "97.4 注意事项"
   },
   {
    "id": "98-macos-列表双向自动跟随滚动体验优化-2026-06-06",
    "text": "98. macOS 列表双向自动跟随滚动体验优化 (2026-06-06)"
   },
   {
    "id": "981-需求与问题背景",
    "text": "98.1 需求与问题背景"
   },
   {
    "id": "982-问题产生原因",
    "text": "98.2 问题产生原因"
   },
   {
    "id": "983-修复方案与全局应用",
    "text": "98.3 修复方案与全局应用"
   },
   {
    "id": "104-macos-桌面端快捷键-m-按键逻辑升级-2026-06-07",
    "text": "104. macOS 桌面端快捷键 M 按键逻辑升级 (2026-06-07)"
   },
   {
    "id": "1041-需求背景与问题",
    "text": "104.1 需求背景与问题"
   },
   {
    "id": "1042-跨端体验差异讨论",
    "text": "104.2 跨端体验差异讨论"
   },
   {
    "id": "1043-具体的修改实现",
    "text": "104.3 具体的修改实现"
   },
   {
    "id": "1044-给后续接手-agent-的提醒",
    "text": "104.4 给后续接手 Agent 的提醒"
   },
   {
    "id": "111-统一-macos-端文章处理快捷键与-ui-按钮跳转逻辑-2026-06-08",
    "text": "111. 统一 macOS 端文章处理快捷键与 UI 按钮跳转逻辑 (2026-06-08)"
   },
   {
    "id": "1111-背景与问题发现",
    "text": "111.1 背景与问题发现"
   },
   {
    "id": "1112-逻辑溯源与缺陷分析",
    "text": "111.2 逻辑溯源与缺陷分析"
   },
   {
    "id": "1113-统一与修复方案",
    "text": "111.3 统一与修复方案"
   },
   {
    "id": "112-macos-端卡片双击跳转下一篇优化-2026-06-08",
    "text": "112. macOS 端卡片双击跳转下一篇优化 (2026-06-08)"
   },
   {
    "id": "1121-问题背景",
    "text": "112.1 问题背景"
   },
   {
    "id": "1122-修改方案讨论与决策",
    "text": "112.2 修改方案讨论与决策"
   },
   {
    "id": "1123-实现细节",
    "text": "112.3 实现细节"
   },
   {
    "id": "119-macos-cmdr-全局刷新快捷键2026-06-08",
    "text": "119. macOS Cmd+R 全局刷新快捷键（2026-06-08）"
   },
   {
    "id": "1191-需求背景",
    "text": "119.1 需求背景"
   },
   {
    "id": "1192-现状分析",
    "text": "119.2 现状分析"
   },
   {
    "id": "1193-方案选择与理由",
    "text": "119.3 方案选择与理由"
   },
   {
    "id": "1194-实现细节",
    "text": "119.4 实现细节"
   },
   {
    "id": "1195-与同步按钮的关系",
    "text": "119.5 与同步按钮的关系"
   },
   {
    "id": "1196-影响文件",
    "text": "119.6 影响文件"
   },
   {
    "id": "1197-验证结果",
    "text": "119.7 验证结果"
   },
   {
    "id": "128-2026-06-09-worktree-审查合并与图片高度策略修正",
    "text": "128. 2026-06-09 worktree 审查、合并与图片高度策略修正"
   },
   {
    "id": "1281-背景",
    "text": "128.1 背景"
   },
   {
    "id": "1282-审查结论",
    "text": "128.2 审查结论"
   },
   {
    "id": "1283-实际合并方式",
    "text": "128.3 实际合并方式"
   },
   {
    "id": "1284-hidden-wizard-修正后的图片高度策略",
    "text": "128.4 hidden-wizard 修正后的图片高度策略"
   },
   {
    "id": "1285-需要重点回归的功能",
    "text": "128.5 需要重点回归的功能"
   },
   {
    "id": "1286-已完成的本地检查",
    "text": "128.6 已完成的本地检查"
   },
   {
    "id": "151-macos-时间线同步按钮对齐2026-06-30",
    "text": "151. macOS 时间线同步按钮对齐（2026-06-30）"
   },
   {
    "id": "152-macos-列表阅读-header-统一与底部滚动视口内缩2026-06-30",
    "text": "152. macOS 列表/阅读 header 统一与底部滚动视口内缩（2026-06-30）"
   },
   {
    "id": "154-macos-中间栏-header-取消玻璃背景2026-07-01",
    "text": "154. macOS 中间栏 header 取消玻璃背景（2026-07-01）"
   },
   {
    "id": "157-macos-同步按钮旋转与图标方向统一为顺时针2026-07-03",
    "text": "157. macOS 同步按钮旋转与图标方向统一为顺时针（2026-07-03）"
   },
   {
    "id": "164-macos-时间线未读全部切换与系统红绿灯修复2026-07-07",
    "text": "164. macOS 时间线未读/全部切换与系统红绿灯修复（2026-07-07）"
   },
   {
    "id": "165-macos-时间线排序同步动画与调试日志收口2026-07-07",
    "text": "165. macOS 时间线排序、同步动画与调试日志收口（2026-07-07）"
   }
  ],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 历史归档：时间线与导航 本页保存从旧 history/timeline.md 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 history/decisions.md 为准。 25. 文章左右滑动切换（2026-05-18） 25.1 需求 在文章详情页支持左右滑动切换上一篇/下一篇 手指跟随时页面要同步横向移动 竖向滚动时避免误触发 临近切页时要有明确视觉提示 25.2 实现 文章详情页改为“单篇 / 序列”双模式： 单篇：保持原有 ArticlePageView 序列：使用 PageView.builder 承载多个 ArticlePageView 打开文章时从来源列表传入 sequence + index ： 时间线列表 订阅源详情列表 文章搜索结果 通过 PageView 自带横向拖动提供手势跟随和临近切页的预览效果。 AppBar 标题追加页码（如 文章详情 · 2/8 ）作为额外视觉提示。 25.3 影响文件 lib/pages/article/article_page.dart lib/pages/timeline/timeline_page.dart lib/pages/feed_detail/feed_detail_page.dart lib/pages/main/main_page.dart 88. macOS 分屏模式下连续标记已读导致导航失效的修复（补记于 2026-06-05） 88.1 现象与问题诊断 现象 ：在 macOS 的分屏模式（左侧文章列表，右侧正文阅读）下，当用户处于“未读”视图模式时，如果按下 m 键（标记为已读），接着按下“下一个（右方向键）”或“上一个（左方向键）”，导航列表会突然回到第一篇文章，而不是顺滑地跳到下一篇未读文章。这导致连续快速阅读（按 m -> 右 -> m -> 右）的操作流断裂。 原因分析 ： timeline_controller.dart 中，当前呈现的渲染列表（ controller.articles ）是动态过滤的（ TimelineViewMode.unread 模式下仅包含 !a.isRead 的文章）。 当按下 m 键标记已读时，底层数据立马更新，并触发 _applyFilter() ，导致该文章瞬间从 controller.articles 列表中被剔除。 当用户立刻按左右方向键触发 _selectRelativeArticle(delta) 导航时，系统会尝试在当前显示的列表 controller.articles 中使用 indexWhere 寻找当前文章所在的索引。 由于刚刚标记已读的文章已经被动态移除了， indexWhere 返回 -1 。 代码随后执行 (currentIndex + delta).clamp(0, list.length - 1) 计算下一个索引，由于 currentIndex 为 -1 ，其加减结果经 clamp 限制后总是 0 ，从而不可避免地跳回到第一篇文章。 注 ：移动端没有此问题，因为移动端的文章轮播页（ _ArticlePagerPage ）接收的是进入详情页那一刻的静态副本（ controller.articles.toList() ），不响应外部列表的实时元素删减。 88.2 解决方案与实现 不引入额外的历史堆栈或状态机，直接利用底层 未过滤的全量列表 controller.allArticles 作为绝对坐标参考系 。因为无论过滤条件怎么变，全集列表的文章顺序（基于发布时间的倒序排序）始终稳固。 具体逻辑 ( lib/pages/timeline/timeline_page.dart -> _selectRelativeArticle ) ： 第一优先级：仍在当前的过滤列表（ controller.articles ）中寻找。如果找到，按常理加减 delta 进行偏移（处理在“全部”模式下的场景）。 第二优先级：如果返回了 -1 （通常是因为被标记已读导致过滤），则去底层全量列表 controller.allArticles 中寻找该文章的绝对物理索引 allIndex 。 扫描寻找可用项：以该绝对物理索引为起点，依据按键方向（ delta > 0 向后或 delta < 0 向前），在全量列表中进行扫描。 在扫描过程中，找到 第一篇同时还存在于当前过滤列表 ( controller.articles ) 中的文章 ，选中该文章完成跳转。 性能优化 ： 考虑到列表最大可达 5000 条，嵌套的 list.contains 可能会引发 $O(N^2)$ 复杂度导致 UI 卡顿。因此，在第二优先级的扫描前，提前构造哈希集合 final listEntryIds = list.map((a) => a.entryId).toSet(); ，将查询从 $O(N)$ 降至 $O(1)$，确保查找瞬时完成。 88.3 后续防退化设计说明 未来修改 TimelineController 或处理导航相关的过滤逻辑时，必须注意： 任何涉及状态快速翻转引起的隐形列表重组问题，都应优先使用不受状态过滤影响的原始数据集作为坐标轴锚点，以防止游标丢失或索引崩塌。 另外，AI 拦截文章（ isRejectedByAi ）并没有被从列表中过滤，它们也会被正常的保留在列表中进行导航，仅呈现视觉标记，不可混淆此概念。 90. macOS 端“最近阅读”功能实现与语义修正 (2026-06-05) 90.1 需求背景与痛点 用户希望在侧边栏增加一个“最近阅读”页面，将所有已读文章严格按照 实际阅读时间倒序排列 。 由于后端的 Folo API 不提供单篇文章精确的“阅读时间戳”，导致本地如果依赖服务端数据，只能按照文章的默认“发布时间”降级排序，无法真实反映阅读历史。 此外，用户明确要求此功能 目前暂时仅在 macOS 端实现，不考虑安卓端 。 90.2 技术选型与实现方案 经过与用户的讨论，我们排除了依赖服务端修改的方案，采用了**“本地拦截+持久化”**的策略： 数据层 (Hive Box 记录时间戳) ：在 lib/utils/storage.dart 中新增了一个 readHistory Box。 状态层 (显式 Hook) ：新增 LocalArticleDbService.recordReadHistory(entryId) ，专门记录用户真实打开文章或主动处理文章的时间。 LocalArticleDbService.setReadState 保持状态写入语义，仅在显式传入 recordHistory: true 时才记录历史；后台静默同步推断已读不传该参数，因此不会污染最近阅读排序。 控制器层 ( RecentReadController ) ：负责从本地所有已读文章中读取数据，优先通过 readHistory 的时间戳进行降序；缺失时间戳的文章则回退到依 publishedAt 降序，并置于列表后方。"
 },
 {
  "path": "history/chronology.html",
  "title": "历史时间索引",
  "headings": [],
  "text": "历史时间索引 本页按旧交接时间线的原始出现顺序列出全部历史章节。编号只用于兼容旧引用，不表示当前开发计划或优先级。当前事实应查阅专题页和 决策日志 。 项目速览 旧第 1 节：用户要求（原始上下文） 旧第 2 节：关键发现（代码审查结论） 旧第 3 节：已完成改动（本轮） 旧第 4 节：本轮新增/修改文件清单 旧第 5 节：仍待继续对标完善的方向（下一位 agent 可直接执行） 旧第 6 节：接手建议（最短路径） 旧第 7 节：本轮追加优化（2026-05-16 晚） 旧第 8 节：本轮追加优化（本地文章库） 旧第 9 节：本轮追加优化（图片加载稳定性） 旧第 10 节：翻译功能实现（v1.1 新增） 旧第 11 节：Social 类别拉取修复（v1.2 新增） 旧第 12 节：Inbox 拉取集成（v1.2 扩展） 旧第 13 节：对标参考工程的细节优化（v1.3） 旧第 14 节：图片渲染性能优化（v1.4） 旧第 15 节：应用退出行为优化与桌面角标配置 (v1.6) 历史版本标记 旧第 16 节：订阅源三级分组与视图标签（2026-05-17） 旧第 17 节：文章来源跳转（2026-05-17） 旧第 18 节：轻量提示统一（2026-05-17） 旧第 19 节：HTML 渲染性能重构（v1.5） 旧第 20 节：过滤页首屏复用全局缓存（2026-05-17） 旧第 21 节：自动翻译（文章拉取时自动处理） 工程状态总结（截至 2026-05-20） 旧第 22 节：仓库完整性巡检与修复（2026-05-18） 旧第 23 节：主页面双标题修复（2026-05-18） 旧第 24 节：文章图片过大与无法全屏修复（2026-05-18） 旧第 25 节：文章左右滑动切换（2026-05-18） 旧第 26 节：已读失败重试队列（2026-05-18） 旧第 27 节：翻译中状态提示增强（2026-05-18） 旧第 28 节：摘要长度调整（2026-05-18） 旧第 29 节：双击时间线底栏回顶部（2026-05-18） 旧第 30 节：已知待修问题（2026-05-19 全库审查） 旧第 31 节：HTML 渲染管线修复（2026-05-19） 旧第 32 节：视频播放支持（2026-05-19） 旧第 33 节：AI 文章过滤系统（2026-05-20） 旧第 34 节：LLM 并发数配置（2026-05-20） 旧第 35 节：图片画廊修复（2026-05-20） 旧第 36 节：Inbox 空内容修复（2026-05-20） 旧第 37 节：其他杂项修复（2026-05-20） 旧第 38 节：已读状态双向同步（2026-05-20） 旧第 39 节：订阅源未读计数（2026-05-20） 旧第 40 节：图片修复补充（2026-05-20） 旧第 41 节：FeedDetail 对齐（2026-05-20） 旧第 42 节：性能优化 — 卡顿修复（2026-05-20） 旧第 43 节：ArticleStateNotifier 全局状态通知（2026-05-20） 旧第 44 节：FeedDetail 已读筛选 + tick(entryId) 增量（2026-05-21） 旧第 45 节：UI 全面美化（2026-05-21，手动修订） 旧第 46 节：主页时间线重大交互与逻辑重构（2026-05-22） 旧第 47 节：刷新圈反悔手势阻断优化（2026-05-22） 旧第 48 节：审核页重塑 — 实时状态药片（2026-05-23） 旧第 49 节：最终打磨与 v1.0.0-beta1 发布（2026-05-23） 旧第 50 节：仓库管理规范（2026-05-23） 旧第 51 节：审核界面直接预览 AI 摘要（2026-05-23） 旧第 52 节：通知角标 + 退后台（2026-05-23） 旧第 53 节：正文加载 + 数据持久化（2026-05-23） 旧第 54 节：译文/摘要内容传递修正（2026-05-23） 旧第 55 节：UI 细节打磨（2026-05-23） 旧第 56 节：大文章分块翻译 + 邮件表格扁平化（2026-05-23） 旧第 57 节：v1.0.0-beta2 发布（2026-05-23） 旧第 58 节：取消文章正文懒加载与重置列表增量刷新 (2026-05-24) 旧第 59 节：遗留问题与已知缺陷 (2026-05-24) 旧第 60 节：深色模式 HTML 字体对比度动态调整 (2026-05-25) 旧第 61 节：遗留问题与已知缺陷 (2026-05-25) 旧第 62 节：性能优化（2026-05-25） 旧第 63 节：已读同步全面修复（2026-05-25） 旧第 64 节：恢复消失的表格与通用图文排版重构（2026-05-26） 旧第 65 节：修复 HTML 块内链接无法点击的问题（2026-05-26） 旧第 66 节：优化文章滑动渲染性能（2026-05-26） 旧第 67 节：解决全局状态变更导致的时间线 UI 失步问题（2026-05-26） 旧第 68 节：修复 Inbox 旧文章不可见（被 5000 条本地缓存限制误删）的问题 (2026-05-26) 旧第 69 节：极致渲染优化：完美进度条与流畅加载的平衡 (2026-05-28) 旧第 70 节：延迟 build + widget 缓存：根治重度技术文章首次打开掉帧 (2026-05-30) 旧第 71 节：卡片转场动画防掉帧与预加载策略 (2026-05-30) 旧第 72 节：未来功能规划 (Future Features) 旧第 73 节：长文阅读页自适应虚拟渲染（2026-05-31） 旧第 74 节：设置页任务中心（2026-05-31） 旧第 75 节：macOS 桌面端深度适配（2026-05-31，进行中） 旧第 76 节：macOS 适配复盘与当前权威上下文（2026-06-01） 旧第 77 节：macOS 侧边栏与相关页面全面适配（本轮对话完整记录） 旧第 78 节：快捷键、同步反馈、品牌统一、审核页已读同步（2026-06-01） 旧第 79 节：macOS 快捷键双重触发、刷新动画与未读计数（2026-06-01 追加修复） 旧第 80 节：Android + macOS 内部发布流程（2026-06-01） 旧第 81 节：worktree 复核、必要改动吸收与 v1.1.2 发布（2026-06-02） 旧第 82 节：Android 安装签名冲突与 v1.1.3 修复（2026-06-02） 旧第 83 节：Android 时间线灰屏修复与 v1.1.4 发布（2026-06-02） 旧第 84 节：安卓端主时间线及垃圾拦截页灰屏彻底修复 (2026-06-02) 旧第 85 节：macOS 桌面端 UI 细节精简与占位符统一（补记于 2026-06-03） 旧第 86 节：UI 精简实验与设计理念记录（补记于 2026-06-03） 旧第 87 节：行内代码排版与渲染重构 (2026-06-05) 旧第"
 },
 {
  "path": "history/decisions.html",
  "title": "决策日志",
  "headings": [
   {
    "id": "应用整体迁移为-fourier",
    "text": "应用整体迁移为 Fourier"
   },
   {
    "id": "wiki-使用内嵌-markdown-的离线单页结构",
    "text": "Wiki 使用内嵌 Markdown 的离线单页结构"
   },
   {
    "id": "保留根目录-agent_handoffmd-作为入口",
    "text": "保留根目录 AGENT_HANDOFF.md 作为入口"
   },
   {
    "id": "完整历史按主题归档",
    "text": "完整历史按主题归档"
   },
   {
    "id": "不使用数字文件前缀",
    "text": "不使用数字文件前缀"
   },
   {
    "id": "文章正文保留-column",
    "text": "文章正文保留 Column"
   },
   {
    "id": "畸形文章修复保持保守",
    "text": "畸形文章修复保持保守"
   },
   {
    "id": "不裁剪宽表格-scroll-viewport",
    "text": "不裁剪宽表格 scroll viewport"
   },
   {
    "id": "无-th-的稳定网格仍属于数据表",
    "text": "无 <th> 的稳定网格仍属于数据表"
   },
   {
    "id": "避免会改变布局的图片-hover",
    "text": "避免会改变布局的图片 hover"
   },
   {
    "id": "选择性使用-liquid-glass",
    "text": "选择性使用 Liquid Glass"
   },
   {
    "id": "不在-flutter-中追求真实外部背景取色边框",
    "text": "不在 Flutter 中追求真实外部背景取色边框"
   },
   {
    "id": "macos-中间-header-保持轻量",
    "text": "macOS 中间 header 保持轻量"
   },
   {
    "id": "macos-圆角收敛按层级联动",
    "text": "macOS 圆角收敛按层级联动"
   },
   {
    "id": "玻璃按钮先集中颜色-token再统一角色规则",
    "text": "玻璃按钮先集中颜色 token，再统一角色规则"
   },
   {
    "id": "批量时间线变化保留列表实例读状态变化保留动画",
    "text": "批量时间线变化保留列表实例，读状态变化保留动画"
   },
   {
    "id": "本地已读覆盖保留到未读快照确认",
    "text": "本地已读覆盖保留到未读快照确认"
   },
   {
    "id": "时间线排序保持本地化",
    "text": "时间线排序保持本地化"
   },
   {
    "id": "macos-快速切换只暴露未读全部",
    "text": "macOS 快速切换只暴露未读/全部"
   },
   {
    "id": "macos-订阅源筛选-header-不重复侧边栏设置",
    "text": "macOS 订阅源筛选 header 不重复侧边栏设置"
   },
   {
    "id": "垃圾拦截页复用时间线级组件",
    "text": "垃圾拦截页复用时间线级组件"
   },
   {
    "id": "macos-debug-禁用-xcode-debug-dylib",
    "text": "macOS Debug 禁用 Xcode Debug Dylib"
   },
   {
    "id": "使用-appkit-系统红黄绿按钮",
    "text": "使用 AppKit 系统红黄绿按钮"
   },
   {
    "id": "android-内部安装签名保持对齐",
    "text": "Android 内部安装签名保持对齐"
   },
   {
    "id": "包命名空间迁移前先实现设置导出",
    "text": "包命名空间迁移前先实现设置导出"
   },
   {
    "id": "使用-iogithubxraygitautofolo-命名空间",
    "text": "使用 io.github.xraygit.autofolo 命名空间"
   },
   {
    "id": "release-notes-对字面量-\\n-fail-fast",
    "text": "Release notes 对字面量 \\n fail-fast"
   },
   {
    "id": "release-tag-必须是-annotated-tag",
    "text": "Release tag 必须是 annotated tag"
   },
   {
    "id": "用户要求时保留-worktree-分支历史",
    "text": "用户要求时保留 worktree 分支历史"
   },
   {
    "id": "历史证据不要作为当前操作手册",
    "text": "历史证据不要作为当前操作手册"
   },
   {
    "id": "macos-分栏列表共享选择与移除协调器",
    "text": "macOS 分栏列表共享选择与移除协调器"
   },
   {
    "id": "同步持久化与-macos-单项移除动画跨帧隔离",
    "text": "同步持久化与 macOS 单项移除动画跨帧隔离"
   },
   {
    "id": "macos-soft-scroll-edge-实验已撤销回到固定-header",
    "text": "macOS soft scroll edge 实验已撤销，回到固定 header"
   },
   {
    "id": "macos-固定-header-让-scrollbar-自然从正文区域开始",
    "text": "macOS 固定 header 让 scrollbar 自然从正文区域开始"
   },
   {
    "id": "macos-正文图片按文章预取并随已读状态回收",
    "text": "macOS 正文图片按文章预取并随已读状态回收"
   },
   {
    "id": "macos-红黄绿使用自绘控件并转发系统-action",
    "text": "macOS 红黄绿使用自绘控件并转发系统 action"
   },
   {
    "id": "macos-26-侧边栏使用局部原生-liquid-glass",
    "text": "macOS 26 侧边栏使用局部原生 Liquid Glass"
   },
   {
    "id": "macos-订阅源侧边栏分离选择展开与临时可见性",
    "text": "macOS 订阅源侧边栏分离选择、展开与临时可见性"
   },
   {
    "id": "macos-正文链接-hover-不再触发-html-重解析",
    "text": "macOS 正文链接 hover 不再触发 HTML 重解析"
   },
   {
    "id": "macos-tooltip-使用共享窗口碰撞布局",
    "text": "macOS tooltip 使用共享窗口碰撞布局"
   },
   {
    "id": "圆形工具按钮只用前景色表达橙色状态",
    "text": "圆形工具按钮只用前景色表达橙色状态"
   },
   {
    "id": "自动翻译和摘要只在入队时检查已读状态",
    "text": "自动翻译和摘要只在入队时检查已读状态"
   },
   {
    "id": "debug-网络请求保持系统证书校验",
    "text": "Debug 网络请求保持系统证书校验"
   },
   {
    "id": "macos-正文标题滚动后进入固定-header",
    "text": "macOS 正文标题滚动后进入固定 header"
   },
   {
    "id": "格式清洗只处理确定无效内容",
    "text": "格式清洗只处理确定无效内容"
   },
   {
    "id": "设置页按输入语义决定保存方式",
    "text": "设置页按输入语义决定保存方式"
   },
   {
    "id": "folo-认证收敛为-session-token",
    "text": "Folo 认证收敛为 Session Token"
   },
   {
    "id": "macos-单篇已读退场只在可见列表中增量更新",
    "text": "macOS 单篇已读退场只在可见列表中增量更新"
   },
   {
    "id": "macos-订阅源分类行使用单一交互反馈面",
    "text": "macOS 订阅源分类行使用单一交互反馈面"
   },
   {
    "id": "html-清洗删除格式包装空段但不合并正常段落",
    "text": "HTML 清洗删除格式包装空段但不合并正常段落"
   },
   {
    "id": "macos-文章范围与排序共用圆形-morph-选择器",
    "text": "macOS 文章范围与排序共用圆形 morph 选择器"
   },
   {
    "id": "macos-订阅源侧边栏优先稳定真实滚动范围",
    "text": "macOS 订阅源侧边栏优先稳定真实滚动范围"
   },
   {
    "id": "浮动玻璃面板使用中性遮罩保证文字对比",
    "text": "浮动玻璃面板使用中性遮罩保证文字对比"
   },
   {
    "id": "来源专属正文兼容集中管理hugging-face-作者区使用紧凑语义块",
    "text": "来源专属正文兼容集中管理，Hugging Face 作者区使用紧凑语义块"
   },
   {
    "id": "详情页补抓正文必须进入统一自动-ai-调度",
    "text": "详情页补抓正文必须进入统一自动 AI 调度"
   },
   {
    "id": "macos-阅读快捷键与空选择焦点归属",
    "text": "macOS 阅读快捷键与空选择焦点归属"
   },
   {
    "id": "macos-分屏正文暂以阅读进度条替代-scrollbar",
    "text": "macOS 分屏正文暂以阅读进度条替代 scrollbar"
   },
   {
    "id": "macos-业务撤销使用有界双栈并接入标准菜单",
    "text": "macOS 业务撤销使用有界双栈并接入标准菜单"
   },
   {
    "id": "静默订阅源批量导出以导出成功为读状态提交边界",
    "text": "静默订阅源批量导出以导出成功为读状态提交边界"
   },
   {
    "id": "android-复用文章级图片预取并限制批量范围",
    "text": "Android 复用文章级图片预取并限制批量范围"
   },
   {
    "id": "android-按能力边界类比-macos-设计语言",
    "text": "Android 按能力边界类比 macOS 设计语言"
   },
   {
    "id": "android-次级页面与目标设备圆角收敛",
    "text": "Android 次级页面与目标设备圆角收敛"
   },
   {
    "id": "android-文章范围使用圆形按钮并统一卡片字级",
    "text": "Android 文章范围使用圆形按钮并统一卡片字级"
   },
   {
    "id": "markdown-导出从文章页面提取为共享服务",
    "text": "Markdown 导出从文章页面提取为共享服务"
   },
   {
    "id": "发布只允许从-main-创建并迁移到-node-24-actions",
    "text": "发布只允许从 main 创建并迁移到 Node 24 Actions"
   },
   {
    "id": "android-审核横滑背景绕开-dismissible-的矩形裁剪",
    "text": "Android 审核横滑背景绕开 Dismissible 的矩形裁剪"
   },
   {
    "id": "flutter-3446-与-macos-纯-swiftpm-工具链",
    "text": "Flutter 3.44.6 与 macOS 纯 SwiftPM 工具链"
   },
   {
    "id": "android-垃圾拦截进入主导航并保留重叠计数",
    "text": "Android 垃圾拦截进入主导航并保留重叠计数"
   },
   {
    "id": "android-文章悬浮工具使用局部可变字重图标",
    "text": "Android 文章悬浮工具使用局部可变字重图标"
   },
   {
    "id": "来源上下文进入正文规范化窄兼容与通用渲染分层",
    "text": "来源上下文进入正文规范化，窄兼容与通用渲染分层"
   },
   {
    "id": "共享权威订阅目录与单层来源返回",
    "text": "共享权威订阅目录与单层来源返回"
   },
   {
    "id": "公开仓库使用中性的默认过滤-prompt",
    "text": "公开仓库使用中性的默认过滤 Prompt"
   },
   {
    "id": "公开仓库采用-agpl-30-only-并集中保留必要声明",
    "text": "公开仓库采用 AGPL-3.0-only 并集中保留必要声明"
   },
   {
    "id": "版本号从连续-patch-调整为阶段化语义",
    "text": "版本号从连续 Patch 调整为阶段化语义"
   },
   {
    "id": "android-导航选中态与未读角标分离",
    "text": "Android 导航选中态与未读角标分离"
   },
   {
    "id": "卡片与排序共用跨平台渲染高度估算",
    "text": "卡片与排序共用跨平台渲染高度估算"
   },
   {
    "id": "youtube-与-bilibili-共用自定义播放壳并保留官方回退",
    "text": "YouTube 与 Bilibili 共用自定义播放壳并保留官方回退"
   },
   {
    "id": "folo-登录采用官方浏览器交接与单一活动账号重建",
    "text": "Folo 登录采用官方浏览器交接与单一活动账号重建"
   },
   {
    "id": "带浮动标签的设置输入控件上方必须为裁切容器预留缓冲",
    "text": "带浮动标签的设置输入控件上方必须为裁切容器预留缓冲"
   },
   {
    "id": "图片加载失败的重试统一收敛到-articleimagecacheservice",
    "text": "图片加载失败的重试统一收敛到 ArticleImageCacheService"
   },
   {
    "id": "误分类n用-useraction-标记记录统计信号",
    "text": "误分类（N）用 userAction 标记记录统计信号"
   },
   {
    "id": "过滤动作撤销必须整条替换快照setreadstate-必须保留全部过滤字段",
    "text": "过滤动作撤销必须整条替换快照，setReadState 必须保留全部过滤字段"
   },
   {
    "id": "拦截页-kmn-由页面级键盘处理器执行hardwarekeyboard-不短路",
    "text": "拦截页 K/M/N 由页面级键盘处理器执行，HardwareKeyboard 不短路"
   },
   {
    "id": "obx-内所有提前-return-之前必须先读取-observable",
    "text": "Obx 内所有提前 return 之前必须先读取 observable"
   },
   {
    "id": "知识库采用编辑阅读的单文件-html-页面体系",
    "text": "知识库采用“编辑=阅读”的单文件 HTML 页面体系"
   },
   {
    "id": "首页兼具产品宣传页与-wiki-入口",
    "text": "首页兼具产品宣传页与 Wiki 入口"
   },
   {
    "id": "文档图形统一使用内联-svg不引入-mermaid",
    "text": "文档图形统一使用内联 SVG，不引入 Mermaid"
   },
   {
    "id": "发布足迹直接追加进-releaseshtml-的内嵌-markdown",
    "text": "发布足迹直接追加进 releases.html 的内嵌 Markdown"
   },
   {
    "id": "ai-队列改用滚动补位调度",
    "text": "AI 队列改用滚动补位调度"
   },
   {
    "id": "全文抓取成功标记语义",
    "text": "全文抓取成功标记语义"
   },
   {
    "id": "本地分析事件账本未来统计中心唯一数据源",
    "text": "本地分析事件账本（未来统计中心唯一数据源）"
   },
   {
    "id": "翻译完成态必须先持久化再上报",
    "text": "翻译完成态必须先持久化再上报"
   },
   {
    "id": "全屏图片成功写入统一缓存通知",
    "text": "全屏图片成功写入统一缓存通知"
   },
   {
    "id": "android-外链不再依赖-canlaunchurl-预检",
    "text": "Android 外链不再依赖 canLaunchUrl 预检"
   },
   {
    "id": "youtube-播放失败回退-mweb-ios-客户端",
    "text": "YouTube 播放失败回退 MWEB / IOS 客户端"
   },
   {
    "id": "普通视频区分签名过期与通用错误",
    "text": "普通视频区分签名过期与通用错误"
   },
   {
    "id": "最近阅读点击不立即重排",
    "text": "最近阅读点击不立即重排"
   },
   {
    "id": "android-目录面板用原生-backdrop骨架共用完整-appbar-inset",
    "text": "Android 目录面板用原生 backdrop，骨架共用完整 AppBar inset"
   },
   {
    "id": "android-集中式触觉反馈策略",
    "text": "Android 集中式触觉反馈策略"
   },
   {
    "id": "订阅抓取错误不误报-url-无效",
    "text": "订阅抓取错误不误报 URL 无效"
   },
   {
    "id": "文章链接-hover-使用生命周期安全回调",
    "text": "文章链接 hover 使用生命周期安全回调"
   },
   {
    "id": "账号切换隔离-worker-完成回调",
    "text": "账号切换隔离 Worker 完成回调"
   },
   {
    "id": "分析账本只记录真实状态变化",
    "text": "分析账本只记录真实状态变化"
   },
   {
    "id": "文章关系先观察后自动化独立于现有质量过滤2026-08-08",
    "text": "文章关系先观察后自动化，独立于现有质量过滤（2026-08-08）"
   },
   {
    "id": "关系窗口扩大至-1024-128输出预算改为-32k-64k2026-08-10",
    "text": "关系窗口扩大至 1024 + 128，输出预算改为 32K / 64K（2026-08-10）"
   },
   {
    "id": "关系建立改为默认关闭且不积压2026-08-12",
    "text": "关系建立改为默认关闭且不积压（2026-08-12）"
   },
   {
    "id": "关系语义拆分为近似重复与同一事件2026-08-12",
    "text": "关系语义拆分为近似重复与同一事件（2026-08-12）"
   },
   {
    "id": "关系请求改用稳定文章-id-保护前缀缓存2026-08-12",
    "text": "关系请求改用稳定文章 ID 保护前缀缓存（2026-08-12）"
   },
   {
    "id": "folo-接口以官方-sdk-契约为准并隔离认证域2026-08-09",
    "text": "Folo 接口以官方 SDK 契约为准并隔离认证域（2026-08-09）"
   },
   {
    "id": "历史审查建议必须按当前代码复核不做报告驱动的大重构2026-08-09",
    "text": "历史审查建议必须按当前代码复核，不做报告驱动的大重构（2026-08-09）"
   }
  ],
  "text": "决策日志 应用整体迁移为 Fourier 背景：旧名称 Auto Folo 容易把个人二次开发客户端与 Folo 官方品牌混在一起，且旧应用身份、图标和包名已经不适合作为长期公开工程标识。 决策：应用展示名、Dart package、Android application id、macOS bundle id、MethodChannel、构建产物和视觉素材统一迁移为 Fourier；旧配置导入与历史内容保留明确兼容。GitHub 仓库名称、远端 URL 和本地目录另行迁移，当前不伪造已经完成的状态。 后果：Fourier 会被 Android 和 macOS 视为新的应用身份。迁移前必须从旧版导出设置，安装后再导入；旧 Auto Folo 名称不得重新出现在当前产品文案或命名空间中。 Wiki 使用内嵌 Markdown 的离线单页结构 背景：目标要求克隆后直接双击 index.html 阅读，无服务、无构建步骤、无外部依赖，同时正文仍尽量保持 Markdown 编辑体验。浏览器在 file:// 下不能可靠地由入口页读取独立 .md 文件。 决策：每个专题使用自包含 .html ，正文写在 script[type=\"text/markdown\"] 中并由仓库内置 markdown-it 渲染； index.html 负责入口，搜索索引作为已提交静态数据。正文允许内嵌可信 HTML 和 SVG，不使用 Mermaid。 后果：编辑和阅读是同一个文件，双击即可使用；修改内容后只需运行索引和一致性检查。不得重新引入必须启动服务器、CDN、ES Module 或运行时 fetch() 的方案。 保留根目录 AGENT_HANDOFF.md 作为入口 背景：后续 agent 会预期根目录存在交接文件。 决策：保留 AGENT_HANDOFF.md 作为短入口，把详细知识迁移到 docs/agent_handoff/ 。 后果：agent 能快速起步，同时完整历史仍然可查。 完整历史按主题归档 背景：旧的单文件交接文档包含重要历史讨论，但 8,000 余行内容集中在一个文件中，不适合作为 wiki 证据库继续维护。 决策：完整历史按主题迁移到 history/archive/ ，每个旧编号章节只归入一个主主题； history/chronology.md 保留原始出现顺序和稳定 legacy-xxx 锚点。 history/timeline.md 只保留兼容入口。 后果：专题页可以保持简洁，历史仍可按主题或旧编号追溯，也不会继续形成新的巨型单文件。 不使用数字文件前缀 背景：开发顺序不遵循固定计划。 决策：使用语义化 wiki 路径，由 README 描述推荐阅读顺序。 后果：新增主题时无需重命名文件，也不会暗示优先级。 文章正文保留 Column 背景：Sliver 虚拟化可能提升性能，但会影响选择、目录锚点、图片生命周期和滚动行为。 决策：不要随意切换到 SliverList.builder 。 后果：除非进行专门重构，否则围绕当前结构优化。 不要回退 保留全文选择行为。 保留目录锚点准确性。 保留图片预览/光标/菜单行为。 保留当前滚动位置语义。 畸形文章修复保持保守 背景：少数真实文章出现异常空白、表格渲染、空代码块或交互组件文本问题。有些问题来自上游内容本身畸形。 决策：添加宽泛渲染启发式规则前，先检查真实源内容。优先做窄修复，或接受罕见上游边缘情况。 后果：渲染保持可预测，不为了少数坏文章牺牲常见正确文章。 不裁剪宽表格 scroll viewport 背景：在横向表格 scroll viewport 外包圆角 ClipRRect ，会在表格宽于文章栏时切掉矩形表格四角。 决策：不要仅为视觉一致性而给表格 viewport 加圆角裁剪。 后果：宽表格保持正确的直角边框，同时仍可横向滚动。 无 <th> 的稳定网格仍属于数据表 背景：阿里技术文章《为什么大模型的缓存命中率能到 90%？》包含 7×5 和 4×2 两个结构完整的数据表，但首行使用 <td> 而不是 <th> 。旧规范化规则把所有无 <th> 表格当成 Newsletter 布局容器，导致两张表在渲染前被摊平成正文。 决策：布局表格清理改用保守的结构判断。有 <th> 的表格直接保留；无 <th> 时，至少两行两列、列数稳定、无嵌套、文本单元格占主导且非媒体主导的网格也保留。其余明确像布局容器的表格继续扁平化。 后果：修复不依赖订阅源、文章标题或具体文本，正确的 td-only 数据表可以进入现有表格渲染器，Newsletter 单单元格/嵌套布局仍保持轻量。 未来方向：如果表格与其他富文本清洗需求继续分化，应把阅读渲染规范化和 LLM 输入清洗拆成独立管线与缓存；本轮不扩大到该架构重构。 避免会改变布局的图片 hover 背景：macOS 图片 hover 缩小/边框效果会移动后续文字，造成明显布局不稳定。 决策：macOS 图片 hover 不应改变图片布局尺寸；用光标表达可点击。 后果：文章文字保持稳定，同时图片仍有可点击提示。 选择性使用 Liquid Glass 背景：全局铺开 Liquid Glass 会造成可读性和 macOS 性能问题，尤其是在密集重复 UI 中。 决策：有意义的浮动控件/表面可以使用玻璃；密集设置、任务中心、未读标签和重复装饰使用轻量描边/静态样式。 后果：应用保留设计方向，同时避免重现 v1.1.25 风格的性能回归。 不在 Flutter 中追求真实外部背景取色边框 背景：用户希望边框高光颜色来自应用窗口后方真实内容。Flutter 绘制无法可靠采样这些像素；NSVisualEffectView/系统 compositor 才拥有这部分模糊。 决策：放弃 Flutter-only 的真实外部背景取色边框。未来如果要做，应作为 native/AppKit renderer 实验。 后果：当前玻璃边框使用实用的白色/高光样式，不假装采样不可得像素。 macOS 中间 header 保持轻量 背景：中间时间线/列表 header 的玻璃背景增加视觉重量，也可能影响性能。后续细线分隔也被取消。 决策：除非明确重新讨论，否则 macOS 中间栏 header 不使用玻璃背景。 后果：中间列表 chrome 保持安静且不显示底部分隔线；文章详情独立保留细分隔线和阅读进度。 macOS 圆角收敛按层级联动 背景：用户希望 macOS 整体圆角略微变小，同时文章卡片圆角略微增大。此前调研 Apple 官方资料后，没有找到普通 macOS app 的固定圆角数值规范；官方更强调圆角同心性、容器关系和系统控件自适应。 决策：第一阶段只收敛主几何层和大面板：窗口/Flutter 外框 24 ，红黄绿圆心 24 ，侧边栏面板 18 ， AppGlassSurface 默认 16 ， AppGlassPanel 默认 18 ，突出面板 20 ，macOS 文章卡片 10 。分屏文章右下角安全裁剪同步外框半径。 后果：红黄绿、外框、侧边栏和右下角文章裁剪必须联动维护。不要把“圆角收敛”扩展成全局搜索替换。 不要回退"
 },
 {
  "path": "history/historical-map.html",
  "title": "历史主题地图",
  "headings": [
   {
    "id": "产品与数据流",
    "text": "产品与数据流"
   },
   {
    "id": "ai-与内容处理",
    "text": "AI 与内容处理"
   },
   {
    "id": "媒体与性能",
    "text": "媒体与性能"
   },
   {
    "id": "时间线与桌面交互",
    "text": "时间线与桌面交互"
   },
   {
    "id": "设计与设置",
    "text": "设计与设置"
   },
   {
    "id": "android-与发布",
    "text": "Android 与发布"
   },
   {
    "id": "维护规则",
    "text": "维护规则"
   }
  ],
  "text": "历史主题地图 当专题页信息不足、需要追溯旧实现或讨论背景时，按主题进入归档。旧章节和当前专题冲突时，以专题页、状态页和决策日志为准。 按旧编号或原始出现顺序查找，请使用 历史时间索引 。 产品与数据流 项目基础与产品演进 订阅源、缓存与同步 当前维护页： 架构概览 、 订阅源 、 存储与缓存 AI 与内容处理 翻译、摘要与 AI 过滤 文章内容与 HTML 渲染 当前维护页： 翻译与摘要 、 垃圾拦截/审核 、 文章渲染 媒体与性能 图片、视频与媒体交互 性能、滚动与进度 当前维护页： 文章渲染 、 性能 时间线与桌面交互 时间线与导航 列表动画与撤销 macOS 桌面框架与快捷键 当前维护页： 时间线 、 macOS 、 快捷键 设计与设置 macOS Liquid Glass 重构 设置、身份与迁移 当前维护页： Liquid Glass 、 macOS UI 、 设置 、 迁移 Android 与发布 Android 专项历史 发布、Git、Worktree 与 CI 发布足迹 当前维护页： Android 、 发布与构建 、 Git worktree 维护规则 历史归档不追加当前事实；新结论写入对应专题页或 决策日志 。 引用旧章节时使用 chronology.md 中的稳定链接，不写只有“第 N 节”而没有链接的引用。 一个旧章节只保存在一个主归档页，跨主题关系通过链接表达，不复制原文。"
 },
 {
  "path": "history/migrations.html",
  "title": "迁移",
  "headings": [
   {
    "id": "fourier-品牌与应用身份迁移",
    "text": "Fourier 品牌与应用身份迁移"
   },
   {
    "id": "包与命名空间迁移",
    "text": "包与命名空间迁移"
   },
   {
    "id": "设置迁移",
    "text": "设置迁移"
   },
   {
    "id": "文章字段迁移",
    "text": "文章字段迁移"
   },
   {
    "id": "android-签名对齐",
    "text": "Android 签名对齐"
   },
   {
    "id": "git-历史隐私清理",
    "text": "Git 历史隐私清理"
   }
  ],
  "text": "迁移 Fourier 品牌与应用身份迁移 当前 app id 命名空间： Android namespace/applicationId： io.github.xraygit.fourier macOS bundle id： io.github.xraygit.fourier MethodChannel 命名空间： io.github.xraygit.fourier/... Android 登录回调： folo://fourier-auth 应用展示名、Dart package、构建产物和图标也统一为 Fourier 。旧 auto_folo_settings 备份类型继续允许导入，新导出使用 fourier_settings ；旧内部 HTML 作者标记继续只读兼容。由于应用标识发生变化，旧版与 Fourier 会被系统视为两个应用，正式迁移依赖用户已导出的设置 JSON。 应用身份迁移验证完成后，相关 worktree 和已合并临时分支已清理；GitHub 仓库、 origin 与本地 clone 目录随后统一迁移为大写品牌名 Fourier 。当前远端为 https://github.com/X-Ray-git/Fourier.git ，默认 clone 目录也是 Fourier ；旧 auto-folo URL 仅依赖 GitHub 的仓库重命名跳转，不再作为当前配置使用。 包与命名空间迁移 以下是 Fourier 之前的 Auto Folo 阶段记录，不再代表当前实现： Android namespace/applicationId： io.github.xraygit.autofolo macOS bundle id： io.github.xraygit.autofolo MethodChannel 命名空间： io.github.xraygit.autofolo/... 更早的 com.folo.* 和 com.autofolo 引用同样已经废弃。 原因： 避免暗示官方 Folo 命名空间所有权。 明确 Auto Folo 是 X-Ray 个人所有/个人使用的软件。 设置迁移 设置导入/导出使用剪贴板 JSON 和受控白名单。 当前重要新增设置： appearance_mode article_content_max_width macos_max_fling_velocity LLM 配置和 prompt key 已使用的迁移流程： 在改变 app identifier 前先加入导出/导入，因为旧包和新包无法自动共享平台存储。 用户从旧桌面/移动端 build 导出 JSON，安装迁移后的包，再导入设置。 缓存/内容数据刻意不属于设置备份。 文章字段迁移 ArticleModel.userAction （ 'k'/'m'/'n_keep'/'n_spam'/null ）为本地统计字段，Hive 无 schema，无需数据迁移，缺失时默认 null。 upsertMany 合并策略： item.userAction ?? existing?.userAction ，网络数据恒为 null，不覆盖本地动作标记。 旧版本二进制不认识该字段，任何旧版重写（同步、标已读、undo）都会把它从文章 JSON 中静默剥掉；这是二进制层面的不可修复行为，统计以\"有记录即真实信号\"为准，不做跨版本数量对齐。 Android 签名对齐 问题： GitHub 构建 APK 和本地 debug APK 最初使用不同签名 key，导致安装冲突。 解决： 用户同意通过 GitHub Secrets 使用本地 debug keystore 材料进行内部构建。 重要点： Secrets 不在仓库中。 单纯提高版本号不能解决签名不匹配。 Git 历史隐私清理 仓库是公开仓库。过去交接文档中的敏感内容被视为最终应从历史中清理，而不是只从最新文件删除。 重要概念： 从当前文件删除 secret，不等于从旧提交删除。 重写历史可以让敏感文本看起来从未提交过，但 commit hash 会变化。 用户没有协作者，不需要照顾旧 clone 兼容性。 执行这类工作时，优先采用只影响敏感文件的定向历史重写。"
 },
 {
  "path": "history/releases.html",
  "title": "发布记录",
  "headings": [
   {
    "id": "v1127",
    "text": "v1.1.27"
   },
   {
    "id": "v1128",
    "text": "v1.1.28"
   },
   {
    "id": "v120",
    "text": "v1.2.0"
   },
   {
    "id": "v121",
    "text": "v1.2.1"
   },
   {
    "id": "v200",
    "text": "v2.0.0"
   }
  ],
  "text": "发布记录 本页保存曾由发布流程追加到根 AGENT_HANDOFF.md 的发布足迹。当前发布方法以 发布与构建 为准，更完整的旧发布背景位于 发布、Git、Worktree 与 CI 归档 。 v1.1.27 ./scripts/release.sh 1.1.27 -m \"- feat: support inline YouTube playback and macOS system fullscreen\\n- fix: improve local video loading, aspect ratio, controls and keyboard behavior\\n- style: refine macOS timeline, article cards, scrollbars and compact glass controls\\n- fix: improve article metadata rendering, timeline interactions and macOS startup stability\" --push v1.1.28 ./scripts/release.sh 1.1.28 -m \"- feat: add swipe review actions and coordinated list transitions\\n- fix: stabilize macOS control interactions and timeline read animations\\n- style: refine compact timeline controls and article scrollbar spacing\" --push 这些命令只作为历史证据，不应直接复制执行。创建新版本前必须重新确认版本号、提交状态和 release notes。 v1.2.0 ./scripts/release.sh 1.2.0 -m $'- feat: add macOS subscription management with undoable changes\\n- feat: add unified YouTube and Bilibili playback with quality, subtitles and danmaku\\n- fix: align embedded video controls, shortcuts, scrolling and fullscreen across platforms' --push 首次 tag 触发时，Android 因 workflow 引用了不存在的 actions/setup-java@v6 而在 job 初始化阶段失败，未创建 GitHub Release。 确认没有正式发布产物后删除该 tag；workflow 改为使用 Node 24 的 actions/setup-java@v5 ，随后在保持 1.2.0+31 和原 release notes 不变的 前提下，于修复提交上重建 annotated v1.2.0 。 v1.2.1 ./scripts/release.sh 1.2.1 -m $'- feat: add cross-platform Folo browser login and account switching\\n- feat: add misclassification actions with atomic undo and review markers\\n- feat: retry failed article images with deterministic backoff\\n- fix: preserve undo animations and Android settings labels' --push v2.0.0 ./scripts/release.sh 2.0.0 -m $'- breaking: rebrand Auto Folo as Fourier with new app identifiers and icons; existing version 1 settings exports remain importable\\n- feat: add summary-based article relationship discovery, related-article review, queue monitoring, and local LLM usage/analysis ledgers\\n- docs: replace the legacy handoff with a self-contained offline Fourier Wiki and complete repository identity cleanup\\n- perf: use rolling-slot AI workers and harden translation, readability, image-cache, and account-bound task persistence\\n- fix: improve YouTube/Bilibili fallbacks, image recovery, external links, recent-reading stability, and Android haptics\\n- style: unify Android reading pages with transparent headers, shared edge fades, safe insets, and native-backdrop toolbar controls' --push 首次生成的 GitHub Release 正文原样采用了上述英文 tag annotation，因而缺少 此前版本使用的中文章节与完整变更链接。2026-08-09 已仅编辑公开 Release 正文， 未移动 tag、未替换附件、未重新触发构建。随后为 scripts/release.sh 增加标准 章节校验与 --notes-file 支持，避免普通发布再次依赖事后人工整理。"
 },
 {
  "path": "history/timeline.html",
  "title": "完整时间线已迁移",
  "headings": [],
  "text": "历史资料，当前事实以专题页为准 ：本页记录旧交接时间线中的原始排查、实验、验证与发布过程，仅作为证据库。当前实现以 当前状态 、对应专题页和 决策日志 为准。 完整时间线已迁移 原 timeline.md 的全部历史内容已按主题迁移到 archive/ ，逐章入口位于 chronology.md 。 本文件只保留为旧链接兼容入口，不再追加历史记录。当前事实请依次查阅： 当前状态 待办与搁置 决策日志 当前任务对应的专题页 旧章节编号只用于历史追溯，不表示计划顺序或优先级。"
 },
 {
  "path": "legal/third-party.html",
  "title": "第三方依赖、许可与致谢",
  "headings": [
   {
    "id": "第三方项目",
    "text": "第三方项目"
   },
   {
    "id": "依赖位置说明",
    "text": "依赖位置说明"
   },
   {
    "id": "维护规则",
    "text": "维护规则"
   }
  ],
  "text": "第三方依赖、许可与致谢 Fourier 项目整体采用 AGPL-3.0-only （见根目录 LICENSE ）。仓库实际包含来自多个开源项目的代码，各自的版权与许可证条款继续适用于对应部分；完整清单与许可证文本见根目录 THIRD_PARTY_NOTICES.md 与 third_party/licenses/ 。 第三方项目 Folo — AGPL-3.0，版权归 Folo contributors；Fourier 是围绕 Folo 使用场景构建的个人客户端，不暗示官方所有权。 PiliPlus — GPL-3.0，版权归 PiliPlus contributors。 Flutter — BSD 3-Clause，版权归 The Flutter Authors。 interactiveviewer_gallery — MIT，Copyright (c) 2020 Nell。 liquid_glass_widgets — MIT，Copyright (c) 2024 Sebastian Degenaar。 liquid_glass_renderer — MIT，Copyright 2025 Tim Lehmann for whynotmake.it。 YouTube.js （17.2.0）— MIT，Copyright (c) 2021 LuanRT。 googlevideo （4.0.4）— MIT，Copyright (c) 2024 LuanRT。 bgutils-js （3.2.0）— MIT，Copyright (c) 2024 LuanRT。 Shaka Player （4.16.2）— Apache-2.0，Copyright Shaka Player authors。 Protobuf-ES （2.8.0）— Apache-2.0 与 BSD-3-Clause，Copyright 2021-2025 Buf Technologies, Inc.；varint 实现 Copyright 2008 Google Inc.。 fflate （0.8.3）— MIT，Copyright (c) 2026 Arjun Barrett。 Meriyah （6.1.4）— ISC，Copyright (c) 2019 and later, KFlash and others。 markdown-it （15.0.0）— MIT，Copyright (c) 2014 Vitaly Puzrin、Alex Kocharin；用于本 Wiki 页面的客户端 Markdown 渲染，UMD 构建内置在 docs/agent_handoff/assets/vendor/ 。 markdown-it-anchor （9.2.1）— 公有领域（UNLICENSE），Copyright (c) 2014-2015 Vitaly Puzrin、Alex Kocharin，2016 Valeriu Paloş；为本 Wiki 生成标题锚点。 依赖位置说明 Flutter/Dart 依赖由 pubspec.lock 锁定，完整许可证声明位于 third_party/licenses/ 。 网页媒体运行时（YouTube.js、googlevideo、bgutils-js、Shaka、Protobuf-ES、fflate、Meriyah）固定在 tool/embed_video_player_runtime/ 的锁文件与构建源中，生产资产位于 assets/embed_video_player/ 。 本 Wiki 的 Markdown 解析器固定在 docs/agent_handoff/assets/vendor/ ，许可证文本见该目录内的 *.LICENSE.txt / *.UNLICENSE.txt 。 维护规则 新增第三方源码时必须同步补充许可证声明与 THIRD_PARTY_NOTICES.md 条目。 仅参考交互思路而未采用源码的项目不写入声明，避免错误归因。 许可证文件作为 Flutter asset 注册，Android 和 macOS 设置页的“关于”区域提供统一的“开源许可证”入口。"
 },
 {
  "path": "meta/design-guide.html",
  "title": "设计规范",
  "headings": [
   {
    "id": "设计判读五维",
    "text": "设计判读（五维）"
   },
   {
    "id": "设计令牌",
    "text": "设计令牌"
   },
   {
    "id": "色彩",
    "text": "色彩"
   },
   {
    "id": "字体与排印huashu-排印系统",
    "text": "字体与排印（huashu 排印系统）"
   },
   {
    "id": "间距与圆角",
    "text": "间距与圆角"
   },
   {
    "id": "阴影",
    "text": "阴影"
   },
   {
    "id": "动效令牌表移植自-huashu-design-easing-库",
    "text": "动效（令牌表，移植自 huashu-design Easing 库）"
   },
   {
    "id": "动画防坑清单huashu-animation-pitfalls",
    "text": "动画防坑清单（huashu animation-pitfalls）"
   },
   {
    "id": "组件协议",
    "text": "组件协议"
   },
   {
    "id": "反俗套检查清单",
    "text": "反俗套检查清单"
   },
   {
    "id": "可访问性自查结论2026-08",
    "text": "可访问性自查结论（2026-08）"
   },
   {
    "id": "来源与参考",
    "text": "来源与参考"
   }
  ],
  "text": "设计规范 本文档是 Fourier Wiki 的视觉与交互设计规范，供后续所有页面美化、新增组件与视觉调整遵循。设计方向参考了开源 agent 设计技能与转场参考工程（见文末来源），并结合本项目的\"离线、单文件、agent 可读\"约束做了取舍。 设计判读（五维） 当前站点在设计上的定位： 产品形态 ：产品身份入口 + 工程手册的离线混合站点。 视觉语言 ：以 Fourier 的中性深色和品牌橙为基础，强调真实产品画面、清晰层级和克制动效。 信息密度 ：高（8/10）——手册为主，允许紧凑列表与代码块。 动效强度 ：中（4/10）——只解释状态变化与引导注意，不干扰阅读。 资产依赖 ：低（3/10）——首页可使用仓库内真实产品截图，架构图继续使用内联 SVG。 品牌保真 ：中（6/10）——品牌橙为唯一强调色，其余色相不做点缀。 设计令牌 色彩 强调色：Fourier 橙 #ff7626 ，强强调 #ff5d00 ；大面积背景保持中性。 语义色：链接蓝 --link 、代码棕 --code-text 、危险/保留仅用于语义场景（按钮与横幅）。 中性色阶：浅色主题 9 级（ --bg 至 --text ），深色主题对应反转；全部用 CSS 变量，hex 在前作 fallback、oklch 在后覆盖。 分区横幅色：状态蓝 / 产品橙 / 架构靛 / 功能橙红 / 平台绿 / 设计紫 / 操作黄绿 / 历史棕 / 许可绿 / 关于灰——只用于横幅图标与底色，不用于正文。 反俗套：首页不使用装饰性光球、网格或纯概念 mockup，以真实产品截图承担视觉信息。 配色方向（2026-08 决策）：对标 Apple 展示页的高饱和克制风格， 不做印刷质感/压 chroma/奶油纸底 ；huashu-design 的\"印刷色质感\"协议（大面积 chroma 0.01–0.04 等）不适用于本站点，其 chroma 参考仅作为选色常识，不进入令牌。 字体与排印（huashu 排印系统） 正文：系统字体栈（PingFang SC / Microsoft YaHei / Noto Sans CJK 等）， 17px （中文建议值 17–18px），行高 1.75（可被阅读设置覆盖）。 等宽：SF Mono / Menlo / Consolas，用于代码与 kbd。 标题按 1.2 音阶 对齐：17 → h3 20 → h2 25 → h1 32；窄屏使用独立断点，不按 viewport 连续缩放。 行长：正文列 max-width: 36em 居中（中文最佳 28–32 字/行）；图形/表格可超出正文列（灯箱承担大图查看）。 text-wrap: pretty （正文）与 balance （标题）提升中文断行。 数字对齐：统计数字、阅读时长徽章等使用 font-variant-numeric: tabular-nums 。 间距与圆角 8pt 网格；正文段距 10px、章节间距 34px。 圆角分层：横幅 16 / 普通导航项与卡片不超过 8 / 胶囊与圆形控件 999 / 大型产品截图 14；不做全局搜索替换。 阴影 两档： --shadow-soft （悬浮反馈）与 --shadow （浮层）；浮层（面板/灯箱/命令面板）用更大的投影。 动效（令牌表，移植自 huashu-design Easing 库） 令牌 cubic-bezier 用途 --ease-expo-out (0.16, 1, 0.3, 1) 主缓动：区块渐显、卡片 hover、横幅和灯箱入场 --ease-overshoot (0.34, 1.56, 0.64, 1) 弹性弹出：主题图标切换、播放按钮、徽章 pop-in --ease-anticipation (0.3, -0.25, 0.6, 1) 蓄力：按钮按下、面板入场（当前未启用，预留） 时长：150–700ms（渐显类 500–600ms，微交互 150–250ms）。 触发：hover（边框或颜色反馈）、点击（主题切换、复制成功）、滚动（轻量区块渐显与进度条）、焦点（focus-visible 可见性）。 首页不钉住滚动，也不让标题随滚动缩放或消失；区块进入视口后只播放一次短渐显，子项可轻微错峰。 首页使用真实产品截图，不维护与实际 UI 容易分叉的纯 CSS mockup 动画。 所有动画必须受 prefers-reduced-motion 保护 ；阅读设置中\"动效关\"等价于全局 no-anim 。 View Transitions 只作渐进增强，不支持时静默降级。 动画防坑清单（huashu animation-pitfalls） 不用稀有 Unicode 字符做视觉元素（黑名单： ␣ ␀ ⌘ ⌥ ⇧ ↩ ⏎ 等）；用 CSS 构造语义盒子。 含 position: absolute 子元素的容器必须显式 position: relative 。 只动画 transform / opacity （含 filter 仅用于渐显类）；数据驱动的数量用 JS 注入。 动画中每个字符都必须在所选字体中存在；emoji 需要验证字体回退。 组件协议 横幅 ：运行时由 app.js 生成（图标 + 标题 + 首段摘要 + 专题标签 + 阅读时长徽章），使用低饱和静态分区底色和一次性轻量入场，不使用循环光泽动画。 图形 ： div.dg 包裹的内联 SVG，复用 dg-* 类与共享箭头 marker；点击打开灯箱（ <dialog> ）。 键帽 kbd ：快捷键一律用 kbd 呈现，样式由 theme.css 统一。 调用框 ：语义警示用 details.dg-callout （\"不要回退\"），默认展开。 交互反馈 ：复制按钮成功态对勾描画；搜索/命令面板 origin-aware 展开；导航当前页高亮 + aria-current 。 反俗套检查清单 新增视觉元素前逐项自查： [ ] 没有紫→粉→蓝渐变（品牌橙是唯一渐变色相） [ ] 不用 emoji 当图标；缺图标用占位或线条 SVG [ ] 不用系统字体当展示字做\"假品牌\"；字体保持系统栈 [ ] 卡片不加彩色左色条（语义警示框除外） [ ] 不堆砌阴影/玻璃；密集重复元素保持轻量 [ ] 不虚构数据、不添加占位截图 [ ] 色相数量 ≤ 4 族（品牌橙 + 中性 + 语义色） [ ] 动效有 reduced-motion 降级 可访问性自查结论（2026-08） 按 ai-friendly-web-design 要点检查： 语义结构：header/nav/main/article/footer 齐全；对话框（命令面板、阅读设置、灯箱）均带 aria-label ；导航当前项带 aria-current 。 键盘可达：复制按钮 hover 显隐但有 :focus-visible 兜底；对话框原生支持 Esc；命令面板支持方向键与 Enter； / ? n p t 全局快捷键在输入焦点与 IME 组合时跳过。 焦点管理：dialog 使用原生 showModal（焦点自动进入，关闭后归还）；灯箱关闭按钮可聚焦。 对比度：浅色/深"
 },
 {
  "path": "meta/migration-map.html",
  "title": "旧文档迁移映射",
  "headings": [
   {
    "id": "转换方式",
    "text": "转换方式"
   },
   {
    "id": "逐文件映射",
    "text": "逐文件映射"
   },
   {
    "id": "状态",
    "text": "状态"
   },
   {
    "id": "产品",
    "text": "产品"
   },
   {
    "id": "架构",
    "text": "架构"
   },
   {
    "id": "功能",
    "text": "功能"
   },
   {
    "id": "平台与设计",
    "text": "平台与设计"
   },
   {
    "id": "操作",
    "text": "操作"
   },
   {
    "id": "历史",
    "text": "历史"
   },
   {
    "id": "根目录与入口",
    "text": "根目录与入口"
   },
   {
    "id": "明确不动的文件",
    "text": "明确不动的文件"
   },
   {
    "id": "新增的-wiki-基础设施",
    "text": "新增的 Wiki 基础设施"
   },
   {
    "id": "敏感信息检查结论",
    "text": "敏感信息检查结论"
   },
   {
    "id": "本次重构的决策记录",
    "text": "本次重构的决策记录"
   }
  ],
  "text": "旧文档迁移映射 本页记录 Wiki 重构前后的完整映射，确保没有旧文档被静默遗漏。原则：内容仍然有效的进入对应专题页；长期设计取舍进入决策页；仅有历史价值的内容进入历史归档并标注“历史资料”；旧 .md 页面统一转换为同名 .html 单文件页面（正文仍为 Markdown，内嵌于 <script type=\"text/markdown\"> ）。 转换方式 转换 说明 .md → 同名 .html 正文以 Markdown 内嵌在页面中，编辑与阅读同一文件 内部链接 .md → .html 全部 265 处相对链接由转换器机械改写，锚点（如 legacy-xxx ）保留 根 index.html 旧营销页（590 行，含远程字体依赖）替换为 Wiki 入口 docs/agent_handoff/README.md 阅读顺序与知识地图并入根 index.html 首页，原文件删除 逐文件映射 状态 旧路径 新路径 处理 status/current.md status/current.html 转换 status/pending.md status/pending.html 转换 status/verification.md status/verification.html 转换 产品 旧路径 新路径 处理 product/principles.md product/principles.html 转换 product/terminology.md product/terminology.html 转换 product/privacy.md product/privacy.html 转换 —（新增） product/overview.html 从根 README.md 与 product/principles.md 提炼产品定位 架构 旧路径 新路径 处理 architecture/overview.md architecture/overview.html 转换 + 内嵌总体架构图 architecture/networking.md architecture/networking.html 转换 architecture/routing-state.md architecture/routing-state.html 转换 architecture/storage-and-cache.md architecture/storage-and-cache.html 转换 —（新增） architecture/sync-state.html 从 networking.md 、 storage-and-cache.md 、 current.md 与决策日志提炼数据同步与状态传播专题 功能 旧路径 新路径 处理 features/timeline.md features/timeline.html 转换 features/article-rendering.md features/article-rendering.html 转换 + 视频内容抽离至 media-playback + 内嵌处理流水线图 features/translation-summary.md features/translation-summary.html 转换 features/filter-review.md features/filter-review.html 转换 features/settings.md features/settings.html 转换 features/subscriptions.md features/subscriptions.html 转换 features/background-tasks.md features/background-tasks.html 转换 features/keyboard-shortcuts.md features/keyboard-shortcuts.html 转换 features/performance.md features/performance.html 转换 —（新增） features/media-playback.html 从 article-rendering.md 视频章节与 networking.md 播放器网络细节合并为媒体播放专题 —（新增） features/undo-redo.html 从 keyboard-shortcuts.md 、 filter-review.md 、决策日志提炼撤销/重做专题 平台与设计 旧路径 新路径 处理 platforms/macos.md platforms/macos.html 转换 platforms/android.md platforms/android.html 转换 design/liquid-glass.md design/liquid-glass.html 转换 design/macos-ui.md design/macos-ui.html 转换 design/interaction-patterns.md design/interaction-patterns.html 转换 操作 旧路径 新路径 处理 operations/release-build.md operations/release-build.html 转换 + 内嵌构建发布流程图 operations/git-worktrees.md operations/git-worktrees.html 转换 operations/testing.md operations/testing.html 转换 operations/troubleshooting.md operations/troubleshooting.html 转换 —（新增） operations/development.html 从根 README.md 、 testing.md 、 verification.md 提炼开发流程 历史 旧路径 新路径 处理 history/decisions.md history/decisions.html 转换 history/migrations.md history/migrations.html 转换 history/releases.md history/releases.html 转换为快照；机器追加日志改为由 scripts/release.sh 直接追加进 releases.html 的内嵌 Markdown（行为不变） history/chronology.md history/chronology.html 转换 history/historical-map.md history/historical-map.html 转换 history/timeline.md history/timeline.html 转换 + “历史资料”横幅（兼容入口） history/archive/README.md history/archive/README.html 转换 + “历史资料”横幅 histor"
 },
 {
  "path": "meta/site-guide.html",
  "title": "站点指南",
  "headings": [
   {
    "id": "核心约束",
    "text": "核心约束"
   },
   {
    "id": "页面结构",
    "text": "页面结构"
   },
   {
    "id": "编辑规则",
    "text": "编辑规则"
   },
   {
    "id": "图形",
    "text": "图形"
   },
   {
    "id": "页面呈现自动组件",
    "text": "页面呈现（自动组件）"
   },
   {
    "id": "首页",
    "text": "首页"
   },
   {
    "id": "导航与搜索",
    "text": "导航与搜索"
   },
   {
    "id": "命令",
    "text": "命令"
   },
   {
    "id": "历史页面",
    "text": "历史页面"
   },
   {
    "id": "品牌信息",
    "text": "品牌信息"
   }
  ],
  "text": "站点指南 本 Wiki 采用 单文件 HTML 页面体系 ：每个专题页是一个自包含的 .html 文件，正文以 Markdown 语法写在 <script type=\"text/markdown\" id=\"wiki-content\"> 中，阅读时由仓库内置的 markdown-it 在浏览器内渲染。克隆仓库后 双击根目录 index.html 即可使用，不需要安装依赖、不需要启动服务、不需要任何构建步骤。 核心约束 不使用 ES Module、Service Worker、动态 import、远程 CDN 或必须启动 HTTP 服务的功能。 禁止使用浏览器网络请求 API 读取本地文件（ file:// 下会被安全策略拦截）。 全部 JavaScript、CSS、字体与图形资源都保存在仓库内，路径均为相对路径。 编辑和阅读使用同一个页面文件；不维护独立的 Markdown 源与生成后的 HTML 副本。 页面结构 每个 .html 页面由转换器从统一模板生成，正文部分如下： <script type=\"text/markdown\" id=\"wiki-content\"> # 页面标题 正文使用 Markdown 编写… </script> <meta name=\"wiki-base\"> ：当前页面到 docs/agent_handoff/ 的相对前缀（根 index.html 为 docs/agent_handoff ）。 <meta name=\"repo-root\"> ：当前页面到仓库根目录的相对前缀。 <title> 与页面主标题由正文第一个 # 标题决定。 编辑规则 直接编辑 .html 中 wiki-content 脚本块里的 Markdown 正文。 内部链接使用相对路径的 .html 结尾： [设置](features/settings.html) 、 [决策日志](history/decisions.html#决策日志) 。 标题锚点由 markdown-it-anchor 自动生成：中文保留原文、空格转 - 、去除标点。跨页锚点链接目标与生成规则一致。 允许可信的 HTML：图表格、横幅、提示块等可以写在正文中（ html: true ）。 正文中不得出现字面量 </script ；确有需要时写成 \\</script （渲染时自动还原）。 图形使用内联 SVG（见下方），不要使用 Mermaid。 图形 每个图形是 div.dg 包裹的内联 <svg> （ div 包装确保 Markdown 解析器按原始 HTML 块透传）。 颜色、线型、节点与箭头样式统一由 assets/theme.css 的 dg-* 类与 CSS 变量提供，随明暗主题切换。 动画只用于解释状态变化（如箭头流动），通过 @media (prefers-reduced-motion: reduce) 全局禁用。 SVG 需要 viewBox 与 role=\"img\" + <title> / <desc> ，保证响应式缩放与可访问性。 页面呈现（自动组件） 以下组件由 assets/app.js 与 assets/theme.css 在阅读时自动生成，不需要在正文中手工编写： 页面横幅 ：每个专题页顶部自动生成静态分区色带（图标 + 标题 + 首段摘要 + 专题标签 + 阅读时长估算徽章），只播放一次轻量入场。首页不生成横幅。 阅读进度条 ：页面顶部细进度条，跟随滚动位置。 代码复制按钮 ：每个代码块右上角悬停出现“复制”，点击写入剪贴板。 标题锚点提示 ：悬停 h2/h3/h4 时左侧出现 # 链接标记。 键帽样式 ：正文中 `Cmd+Z` 、 `M` 这类快捷键行内代码可写成 `<kbd>Cmd+Z</kbd>` ，或直接使用反引号由转换规则生成键帽。 “不要回退”调用框 ：决策页中的 不要回退： 列表会被包装为可折叠的警示框（默认展开），格式为 <details class=\"dg-callout\" open> 。 命令面板 ： Cmd/Ctrl+K 打开（搜索页面 + 动作 + 快捷键帮助）， ? 直接查看帮助。 阅读设置 ：右下角 Aa 按钮调整字号 / 行距 / 正文宽度 / 动效开关（localStorage 持久化， file:// 下不可用时自动忽略）。 键盘导航 ： / 聚焦搜索、 n / p 上/下页、 t 返回顶部；输入框焦点与中文输入法组合键时全部跳过。 图形灯箱 ：点击任意示意图用原生 <dialog> 放大查看。 模糊搜索 ：内置 CJK 友好的轻量模糊匹配（标题 > 小标题 > 正文加权），无第三方依赖。 打印样式 ： @media print 输出干净的正文排版，可导出 PDF。 所有动画与过渡都受 prefers-reduced-motion 保护；视觉与交互规范见 设计规范 。 首页 根 index.html 是 Fourier 与工程 Wiki 的共同入口。首屏使用新品牌标识、简短定位、当前状态入口和真实产品截图；后续依次呈现核心能力、处理流水线和专题导航。首页不使用虚构统计数字，也不通过超长 sticky 场景制造额外滚动距离。 区块进入视口时使用轻量透明度与位移动画，子项短暂错峰；不对标题做滚动缩放，不使用模糊滤镜。全部动效受 prefers-reduced-motion 和阅读设置中的动效开关保护。落地页标记 wiki-full ，运行时隐藏侧栏与目录；其中链接使用 docs/agent_handoff/ 前缀（页面位于仓库根）。 导航与搜索 侧边栏导航清单： assets/data/nav.js 中的 window.WIKI_NAV （手维护）。新增/重命名页面后必须同步更新。 站内搜索索引： assets/data/search-index.js 中的 window.WIKI_SEARCH_INDEX 。修改内容后运行： ./scripts/docs.sh index 索引生成后随内容一起提交；阅读端始终使用已提交的索引，不需要再运行任何生成过程。 命令 ./scripts/docs.sh check # 链接/锚点/转义/敏感信息/索引新鲜度检查 ./scripts/docs.sh index # 重新生成搜索索引 ./scripts/docs.sh convert # （一次性）从 .md 工作态转换页面 历史页面 history/archive/ 与 history/timeline.html 属于历史资料：页面顶部有“历史资料，当前事实以专题页为准”横幅。归档不追加当前事实；新结论写入对应专题页或 history/decisions.html 。 品牌信息 页面外壳中的站点名会出现在全部专题 HTML，品牌色和页头标识由 assets/theme.css 维护，首页产品文案位于根 index.html 。变更品牌时必须同时更新页面外壳、当前专题正文、搜索索引和交接入口；历史归档正文保留当时名称作为证据。"
 },
 {
  "path": "operations/development.html",
  "title": "开发流程",
  "headings": [
   {
    "id": "快速开始",
    "text": "快速开始"
   },
   {
    "id": "常规检查",
    "text": "常规检查"
   },
   {
    "id": "不要依赖完整-dart-analyze",
    "text": "不要依赖完整 dart analyze"
   },
   {
    "id": "macos-本地-ui-验证",
    "text": "macOS 本地 UI 验证"
   },
   {
    "id": "动画诊断",
    "text": "动画诊断"
   },
   {
    "id": "文档维护",
    "text": "文档维护"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "开发流程 面向后续 agent 与开发者的日常开发入口。当前工具链对齐 Flutter 3.44.6 （项目最低约束 Flutter >=3.44.0 、Dart ^3.12.2 ）。 快速开始 flutter pub get flutter run -d macos # macOS flutter run -d <device-id> # Android 首次配置：应用内设置页填写 Folo Session Token （Folo Web 应用的 Cookie）与 DeepSeek API Key （翻译、摘要和垃圾拦截功能需要）。 常规检查 dart analyze lib test flutter analyze lib test flutter test flutter build macos --debug 迭代时可以使用更小范围的检查： dart analyze lib/pages/article/article_page.dart flutter test test/article_model_test.dart test/feed_model_test.dart test/html_entity_utils_test.dart 不要依赖完整 dart analyze dart analyze # 不要使用 原因：仓库的 reference/ 下有复制来的参考工程；完整 dart analyze 会把它们也扫进去，并产生无关错误。CI 使用 flutter analyze --no-fatal-infos lib test 。 macOS 本地 UI 验证 flutter run -d macos 或者： flutter build macos --debug open \"build/macos/Build/Products/Debug/Fourier.app\" 不要把本地 macOS release 构建作为主要 UI 验证目标。本地环境可能把 release 产物视为 ad-hoc 签名或未知证书链，从而造成启动/framework 加载问题；这不一定和当前代码有关。 如果 macOS Debug 出现“构建成功但等不到 debug connection”： flutter clean flutter pub get flutter run -d macos --no-pub 当前 Debug 配置依赖 ENABLE_DEBUG_DYLIB = NO 避免 Fourier.debug.dylib 被 macOS 系统策略拒载。验证时应看到 A Dart VM Service on macOS is available at: 。 动画诊断 复现 M/K 、审核横滑或主时间线双击偶发瞬移时，以 Debug 埋点运行： flutter run -d macos --no-pub \\ --dart-define=FOURIER_ANIMATION_PROBE=true \\ 2>&1 | tee /tmp/fourier-animation.log 按页面过滤 ReviewAnimProbe 、 TimelineAnimationProbe 、 TimelineTapProbe 、 TimelineListResetProbe 、 TimelineReadStateProbe 。埋点只输出文章 id 末 8 位、动作来源、列表数量、动画阶段和慢帧耗时，不输出标题、正文、凭据或完整文章 id。不要为了普通运行长期打开该开关。 文档维护 更新当前工作对应的专题页；长期有效的取舍写入 history/decisions.md 。 用 history/historical-map.md 定位旧上下文；历史归档不追加当前事实。 编辑 wiki 页面的方法见 站点指南 。 除非确实要保留原始时间线记录，否则不要继续向完整归档追加新工作。 相关页面 测试 ：测试命令与回归覆盖要求。 故障排查 ：常见问题速查。 Git worktree ：并行 agent 工作区规则。 发布与构建 ：版本号与发布流程。 验证记录 ：开放验证项与已确认结论。"
 },
 {
  "path": "operations/git-worktrees.html",
  "title": "Git Worktree",
  "headings": [],
  "text": "Git Worktree 用户经常并行使用多个 Codex agent 和 worktree。 规则： 清理或合并前先检查所有 worktree。 分支改动通常来自用户需求，但不代表实现一定正确。 用户要求保留 merge 行为时，功能 worktree 集成优先使用 merge commit。 未经用户确认，不要删除 worktree 或分支。 性能实验可能留下可清理的临时 worktree；清理前先检查。 main 内容可能已经由用户确认。用户要求检查 worktree 时，应谨慎评估其他分支；除非用户要求 review main，否则 main 只报告状态。 常用命令： git worktree list --porcelain git status --short --branch git log --oneline --decorate -12 git diff --stat main...branch-name 近期集成记录： 五个功能分支已通过 merge commit 合入 main ： macOS 时间线排序 macOS 时间线控件/系统红黄绿按钮 文章详情交互 应用内外观模式 HTML entity 解码 合并审查清单： 判断分支是否解决真实用户需求。 检查实现方式是否符合当前设计/性能约束。 关注过期状态、缺少即时 UI 刷新、hover/cursor 不一致、重复 scrollbar。 确认 macOS 专属 UI 工作没有意外影响 Android。 如果合并改变长期规则，更新对应专题页和决策日志。"
 },
 {
  "path": "operations/release-build.html",
  "title": "发布与构建",
  "headings": [
   {
    "id": "版本号规则",
    "text": "版本号规则"
   }
  ],
  "text": "发布与构建 除非用户明确要求，否则不要创建 release。 构建发布流程 pubspec 版本经 release.sh 在 main 分支创建 annotated tag，GitHub Actions 从 tag 构建并签名 Android APK 与 macOS arm64 产物，最后发布 GitHub Release。 pubspec.yaml X.Y.Z+N 唯一版本来源 scripts/release.sh 仅 main · 构建号 +1 annotated tag vX.Y.Z 发布足迹 releases.html 追加 GitHub Actions tag 触发 · Node 24 Actions Android APK 签名对齐 · versionCode macOS arm64 macos-26 runner · SwiftPM GitHub Release release notes 校验 当前发布流程： 使用 scripts/release.sh 。 脚本只允许在 main 分支运行；不要从功能分支直接创建发布 tag。 release tag 必须是 annotated tag。 GitHub Actions 会从 tag 构建 Android APK 和 macOS arm64 产物。 本地和 GitHub Actions 统一使用 Flutter 3.44.6 ；项目最低约束为 Flutter >=3.44.0 、Dart ^3.12.2 。升级 SDK 时必须同步检查 pubspec.yaml 、lockfile 和工作流中的两个 Flutter pin，不能只改本机。 macOS 发布包必须保持 arm64。 macOS job 固定使用 macos-26 ARM64 runner。原生侧边栏使用了 macOS 26 SDK 的 NSGlassEffectView ，不要改回默认仍可能选择 Xcode 16 的 macos-latest ，否则 CI 可能在 Swift 编译阶段失败。 macOS 原生插件已迁移为纯 Swift Package Manager。仓库不再保留 macos/Podfile 、 Podfile.lock 或 Xcode Pods 引用； screen_retriever 至少保持 0.2.2 ，该版本修复了其 macOS SwiftPM manifest。若构建再次输出 Running pod install ，应先排查是否误恢复 CocoaPods 集成。 每次发布的可复现命令由 scripts/release.sh 追加到 docs/agent_handoff/history/releases.html （内嵌 Markdown）；根 AGENT_HANDOFF.md 始终保持为短入口。 版本号规则 pubspec.yaml 的 version: X.Y.Z+N 是唯一版本来源： X.Y.Z 是用户可见版本，并对应 annotated tag vX.Y.Z 。 N 是单调递增的内部构建号；Android 使用它作为 versionCode ，macOS 使用它作为 CFBundleVersion 。 Major、Minor 或 Patch 变化时都不能重置构建号。 普通 commit 不修改版本号；只有真正创建发布时才由 scripts/release.sh 更新版本并把构建号加一。 不要手工同步 Android、macOS、设置页或请求头中的版本；这些位置应继续从 Flutter/pubspec 版本读取。 面向当前个人应用的版本语义： Major（ 2.0.0 ） ：产品定位根本变化，或配置、本地数据、安装身份和核心工作流出现无法平滑迁移的不兼容。单纯 UI 大改通常不升 Major。 Minor（ 1.2.0 ） ：新增明确功能或工作流，一批相关功能形成新阶段，或者完成重要但保持用户数据兼容的 UI/架构重构。 Patch（ 1.2.1 ） ：Bug 修复、性能优化、视觉微调和小范围行为完善，不引入新的主要工作流。 历史 v1.1.1 到 v1.1.28 长期把功能和重构也作为 Patch 发布，不重写这些历史。从下一次发布开始执行上述规则。 v1.1.28 之后已积累 Android 主导航与设计迁移、静默订阅源批量导出、macOS Undo/Redo、媒体与缓存能力、认证/设置收敛、SwiftPM 和许可证体系，因此观察稳定后应进入 v1.2.0 ；如果期间没有其他发布，对应 pubspec 为 1.2.0+31 。 当前脚本和 CI 只接受纯 X.Y.Z ，尚未支持 1.2.0-beta.1 。不要只改 tag 或 pubspec 来临时创建预发布版；若未来确实需要 Beta，必须先统一修改 release 脚本、pubspec/tag 校验、GitHub Actions 和 GitHub Release 的 prerelease 标记。 Release notes 规则： GitHub Release 正文默认必须保持统一结构： 本版重点 、至少一个内容章节（如 新功能 、 修复与改进 或 升级说明 ），以及 完整变更 对比链接。 较长说明优先写入临时 Markdown 文件并通过 --notes-file <path> 传入，避免 shell 多行引号破坏格式； -m 仍可直接传入完整 Markdown。 如果某次发布确实需要不同结构，必须显式使用 --allow-unstructured-notes ；不要把普通的简略 bullet list 当作正式正文。 scripts/release.sh 默认拒绝 -m 中的字面量 \\n 。 真实换行使用 ANSI-C quoting： ./scripts/release.sh 1.2.3 -m $'- fix: first item\\n- feat: second item' --push 上例仅说明真实换行的 shell 写法；正式 Release 仍需满足上述章节结构。 如果确实需要字面量 backslash-n，使用 --allow-literal-backslash-n 。 签名： Android 包名相同但签名 key 不同时会安装冲突。 项目已通过 GitHub Secrets 让 GitHub 内部构建签名与用户本地 debug keystore 对齐。 GitHub Secrets 不存放在仓库中。 本地构建命令： flutter build apk --debug flutter build macos --debug Flutter 3.44.6 迁移完成时，本机已通过 Android Debug、macOS Debug 和 macOS Release 构建，Release 主程序确认为 arm64。以后本地 release 失败仍应先区分签名/framework 环境问题与代码回归。"
 },
 {
  "path": "operations/testing.html",
  "title": "测试",
  "headings": [],
  "text": "测试 主要命令： dart analyze lib test flutter analyze lib test flutter test flutter build macos --debug 预期注意点： Flutter 命令可能需要权限更新 Flutter SDK cache。 完整 dart analyze 会很吵，因为 reference/ 包含外部复制来的参考工程。 Flutter 3.44.6 的分析器会对现有 renderer 和少量 helper 报 prefer_initializing_formals info；工具链迁移时共观察到 59 条，没有 warning/error。CI 使用 flutter analyze --no-fatal-infos lib test 。不要为了消除本次升级带来的 info 顺带机械重写液态玻璃 renderer；后续可作为独立无行为重构处理。 GitHub 的 Android job 在 Ubuntu runner 上执行 Dart/Flutter 测试， Platform.isAndroid 在测试进程中仍为 false 。测试受平台门控的 service 时必须使用该 service 明确提供的 test override，并在 tearDown 恢复；不能依赖开发机恰好是 macOS，也不能为迁就 CI 删除生产环境的平台边界。 当前测试： test/article_content_utils_test.dart test/html_chunk_parser_test.dart test/article_card_test.dart test/article_model_test.dart test/feed_model_test.dart test/html_entity_utils_test.dart test/implicitly_animated_list_test.dart test/widget_test.dart 正文来源兼容回归至少应覆盖：目标来源作者区被转换、作者姓名/账号/主页和头像地址保留、装饰头像空壳被清理、其他来源的圆形/头像式图片不被误删，以及内部作者标记只生成一个 authorList chunk。 修改单个功能时，先运行相关窄测试；推送前再运行完整项目测试套件。 macOS 列表动画诊断埋点默认关闭。普通 Debug/Release 不打印，也不会挂载动画监听器。复现 M/K 、审核横滑或主时间线双击偶发瞬移时，运行： flutter run -d macos --no-pub \\ --dart-define=FOURIER_ANIMATION_PROBE=true \\ 2>&1 | tee /tmp/fourier-animation.log 按页面过滤： grep ReviewAnimProbe /tmp/fourier-animation.log grep TimelineAnimationProbe /tmp/fourier-animation.log grep TimelineTapProbe /tmp/fourier-animation.log grep TimelineListResetProbe /tmp/fourier-animation.log grep TimelineReadStateProbe /tmp/fourier-animation.log TimelineAnimationProbe 同时覆盖主时间线的 M 、双击、退场动画进度和滚动 offset； TimelineTapProbe 记录原始点击与双击识别，用于区分手势未识别和动画未绘制； TimelineListResetProbe 记录零时长批量同步的明确原因，用于确认单篇读状态是否被错误归入批量路径； TimelineReadStateProbe 区分已读状态被未读快照降级与列表组件的纯视觉残影。正常单篇移除应依次出现动画 bucket 4→3→2→1→0 ，增量可见列表更新不应触发 list reset，外部浏览器只能在 remove.end 后打开。埋点只输出文章 id 的末 8 位、动作来源、列表数量、动画阶段和慢帧耗时，不输出标题、正文、凭据或完整文章 id。不要为了普通运行长期打开该开关；同步 debugPrintSynchronously 本身可能轻微干扰 Debug 性能测量。"
 },
 {
  "path": "operations/troubleshooting.html",
  "title": "故障排查",
  "headings": [],
  "text": "故障排查 flutter run -d macos 看起来卡住： 过大的 debug HTTP 日志曾导致 log reader 不稳定。 Dio body/header 日志现在已在 debug 下关闭。 如果 VM Service/DevTools URL 已出现，即使 foregrounding 报 warning，应用也可能已经在运行。 macOS release app 本地打不开： 本地 release 签名/framework 加载可能因为 ad-hoc 或未知证书链失败。 除非专门测试 release packaging，否则本地 UI 验证使用 debug build。 Android 安装冲突： 包名相同但签名 key 不同会造成安装冲突。 单纯提高版本号不能解决签名不匹配。 Analyzer 出现几千个错误： 很可能运行了完整 dart analyze ，扫描了 reference/ 。 使用 dart analyze lib test 。 macOS 文章滚动回归： 不要先猜，先和已知良好 tag 对比。用户认为 v1.1.20 明确流畅， v1.1.23 是有用的良好基线， v1.1.25 明显变差。 优先检查重型重复玻璃：未读标签、设置行、任务行、卡片装饰。 不要直接跳到 SliverList.builder ；那有已知行为风险。 触控板滚动太快： maxFlingVelocity / macos_max_fling_velocity 可以减少 fling 后的惯性位移。 它不会限制手指仍在触控板上时每一帧的原始滚动 delta。 原始事件拦截可行但侵入性强；除非用户明确接受风险，否则避免采用。 Release notes 出现字面量 \\n ： 必要时修正 release note body。 未来 release 应通过 scripts/release.sh ，该脚本会拒绝字面量 \\n ，除非显式允许。"
 },
 {
  "path": "platforms/android.html",
  "title": "Android 说明",
  "headings": [],
  "text": "Android 说明 Android 正在按现有 macOS 设计语言做类比迁移，但不是照搬 AppKit 实现。 平台边界： AppGlassSurface 、 AppMobileGlassSheet 等纯 Flutter 组件可以跨平台复用； NSGlassEffectView 、窗口后方取样和红黄绿等 AppKit 能力仍只属于 macOS。 少量固定浮动控件可以使用真实 Flutter 模糊玻璃；时间线卡片等密集重复元素继续使用轻量外壳，避免重演 macOS 列表玻璃造成的性能回退。 package id 已迁移到 io.github.xraygit.fourier 。安装签名 key 不同但包名相同的 APK 会和现有安装冲突；GitHub 内部构建使用已约定的签名设置。 Android 8+ launcher 使用自适应图标：橙色背景保持全幅，Fourier 前景标志按 2/3 围绕画布中心缩放到中央安全区域，使其相对底板的大小和视觉重心接近 macOS 图标。前景 432px 资源属于 drawable-xxxhdpi （即 108dp ），不得放回 drawable-nodpi ；所有修改应落在 assets/branding/fourier-android-foreground.svg 后运行 tool/generate_fourier_icons.sh ，避免手改生成 PNG。 截至 2026-07-19 已完成的迁移： 主时间线只在 header 暴露 36px 圆形文章范围按钮，点击后从共享玻璃底部面板选择 未读/全部 ；订阅源详情复用同一组件，不再维护旧 switch 的轨道、滑块和临时视觉状态。范围图标在“未读/全部”两种状态都使用主题中性前景色，不用橙色重复表达选中；底部面板内的当前选项仍保留橙色强调。 主 shell 左侧范围按钮与右侧搜索按钮共用 AppGlassIconButton 的 36px 圆形玻璃外壳和 19px 图标，分别距左右边界 12px 。搜索是普通工具动作，不设选中色。 底部主导航改为纯图标悬浮胶囊：水平和底部边距 12px 、高度 56px 、连续曲率半径 28px 。当前四个一级入口依次为时间线、垃圾拦截、订阅源和设置；时间线与垃圾拦截图标右上角显示未读/待处理数字角标，零值隐藏、超过 99 显示 99+ 。该组参数由已验证的底部面板 8px + 32px 反推约 40px 等效外圆角，并已在当前目标手机上通过视觉确认。外壳固定于 edge-to-edge 内容边界，不再由 SafeArea 动态抬高；按钮中心距底边约 40px 。选中项只把线框图标切换为橙色实心图标，不再铺橙色胶囊背景；未读角标固定使用 AppSemanticColors.unreadBadge 的 #DB4A3E 与白字，不加边框，也不随选中态变色。外阴影通过路径差集只绘制在导航外壳外侧。 垃圾拦截作为主导航常驻页面时使用 FilterReviewPage(embeddedInMainNavigation: true) ，复用主 shell 的 MobileBlurAppBar 和底部导航；独立命名路由仍保留，用于不处于主 shell 的兼容入口。主时间线不再显示重复的“AI 智能过滤”顶部卡片；后台任务的“去审核”返回主 shell 后切换到垃圾拦截页。 两个角标刻意保留既有文章口径：时间线角标使用非静默订阅源的全部未读数，垃圾拦截角标使用 isRejectedByAi && !isRead 的待审核数。被 AI 拒绝但尚未人工处理的文章仍留在普通时间线，因此可以同时计入两个角标；不要擅自改成互斥队列。 最近阅读从主导航移到订阅源页，并作为二级时间线进入。 文章页已使用圆形玻璃已读按钮；存在目录时在其上方显示目录按钮，目录使用共享移动端玻璃底部面板。正文底部空间按是否存在目录动态避让。 文章页右下角目录、标为已读和恢复未读图标使用 Rounded Material Symbols，统一为 24px 、字重 700 ，提高半透明玻璃按钮上的可见性。 AppGlassIconButton.iconWeight 默认仍为空，不能为了这组移动端悬浮按钮把其他平台或顶部工具按钮一起加粗。 订阅源详情改为紧凑 header，阅读状态筛选与主时间线一致；自动全文、翻译和静默设置进入共享玻璃底部面板。 AppMobileGlassSheet 是移动端玻璃底部面板的共享外壳，当前统一圆角 32px 、水平边距 8px 、底部 viewPadding + 8px 。不要在目录和订阅源设置中分别复制这些参数。 普通卡片、骨架、空态继续复用 ArticleCardChrome 的布局基线；本轮没有把密集卡片改成重型玻璃。 Android 与 macOS 的普通文章卡片、垃圾拦截审核卡片共用 14px 标题和 12px 辅助正文；这两个值由 ArticleCardChrome 集中管理。 Android 与 macOS 的文章卡片都在订阅源行右侧显示预计内容高度，例如 860 px 、 4.3k px 。数值来自同一个 ArticleLengthEstimator ，使用固定 340 logical px 阅读宽度并计入图片等渲染块，不读取设备尺寸或像素比；相同正文数据在两端应得到相同结果。 设置页已改为 Android 专用分组布局：页面水平边距 12px ，大设置面板使用 24px 连续圆角和轻量静态外壳；服务认证、阅读偏好、配置迁移、三组 LLM、Prompt 和关于信息按语义分组。正文宽度和 macOS 惯性上限等平台无关项不在 Android 显示。 Android 设置选择统一通过 MobileSettingsSelectField<T> ：收起态保持设置输入框外观，点击后打开 AppMobileGlassSheet ，当前项带勾选，选择即保存并关闭。外观、角标、重试、模型、思考模式、思考强度和 max_tokens 均使用该入口；不要重新引入 DropdownButtonFormField 的 Material overlay。 后台任务中心和 AI 失败记录保持二级页面，而非强行塞回设置列表；它们与设置页共享轻量面板、 12px 边距和移动端 header。任务实时状态与失败记录仍由原业务控制器负责。 MobileBlurAppBar 是普通 Android 页面共享 header：工具栏高度 48px 。设置、任务中心和失败记录仍使用背景 alpha 0.74 、blur sigma 18 的实体模糊 header；文章卡片列表、垃圾拦截、最近阅读、订阅源详情和文章正文则使用透明 header，并由 MobileEdgeFadeStack 让滚动内容在工具栏后方渐隐。不要再给这些页面各写一套 AppBar 或顶部占位。 Android 滚动阅读页的顶部渐隐以 AppBar 下边缘为坐标基准：从屏幕顶端到下边缘上方 24px 保持背景色 80% 不透明度，至下边缘下方 4px 线性降为 35% ，再至下方 32px 降为透明。列表顶部只额外留 2px ，与文章卡片自身"
 },
 {
  "path": "platforms/macos.html",
  "title": "macOS 说明",
  "headings": [],
  "text": "macOS 说明 macOS 窗口分层 AppKit 原生层与 Flutter 内容层分离：原生玻璃由 sidebarBackdropHost 裁剪，红黄绿自绘按钮转发系统 action，拖动只由 MacOSWindowDragArea 触发。 窗口外框 · 连续圆角 24 · full-size content view sidebarBackdropHost：只裁剪原生玻璃宿主的 24px AppKit 圆角 原生 backdrop 外扩 1px 堵住抗锯齿漏底细缝 AppKit 原生层 NSGlassEffectView(.regular) 侧边栏玻璃 自绘红黄绿 NSControl（转发系统 action） 窗口 isMovable=false · 启动隐藏到首帧 Flutter 内容层 页面 / 侧边栏内容 / 阴影与 0.5px 轮廓 MacOSLayoutMetrics 几何真值 → channel 同步 深浅主题与 NSApp.appearance 同步 拖动区 MacOSWindowDragArea 标题与空白区主动拖动 按钮/输入框不入子树 全屏视频：唯一临时隐藏红黄绿按钮的页面 冷启动：LiquidGlassWidgets.initialize() 在窗口隐藏期预热 shader macOS 是近期 UI 工作的主要验证目标。 当前 UI： 分栏：左侧应用侧边栏，中间时间线列表，右侧文章详情。 macOS 窗口使用透明/full-size content view。macOS 26 的侧边栏局部使用原生 NSGlassEffectView(.regular) ；旧系统回退到局部 NSVisualEffectView(.sidebar, .behindWindow) 。 局部原生侧边栏玻璃必须放在 sidebarBackdropHost 内，由该宿主使用与 Flutter 应用外框一致的 24px 连续圆角裁剪。不能把玻璃再次直接作为未裁剪的 contentView 子节点：Flutter 的外框 ClipPath 无法约束 AppKit 兄弟节点，窗口聚焦时会在最外侧左上、左下圆角产生透明穿透和不规则锯齿。宿主只负责原生玻璃的最外层裁剪，不能改成裁剪整个 contentView ，否则可能影响 Flutter、窗口按钮和阴影。 红黄绿按钮使用 AppKit NSControl 自绘容器，位置和命中范围匹配自定义窗口/侧边栏几何；系统标准按钮保持隐藏，自绘按钮通过它们现有的 target/action 转发关闭、最小化和绿色按钮行为。 全屏视频是唯一会临时隐藏红黄绿按钮的页面：视频会延伸到 full-size content view 的标题栏区域，保留按钮会遮挡画面。退出视频页面必须恢复按钮；普通文章、图片预览和其他页面仍遵循标准按钮定位。 YouTube 与 Bilibili 首选本地打包的 Shaka WKWebView 播放器，失败时自动 回退各自官方 iframe；网页视频全屏都是网页元素触发的 macOS 系统全屏， 不经过普通视频的 FullscreenVideoPage 。Runner 只对对应 WKWebView 开启 isElementFullscreenEnabled ，不要把这一配置误当成整个应用窗口的 全屏开关。 Bilibili 弹幕画在 Shaka 页面内部的 Canvas，而不是用 Flutter widget 覆盖 WKWebView。这样系统元素全屏仍保留弹幕，也避免 AppKit platform view 与 Flutter overlay 的层级、命中和性能问题。 两个平台的首选页面由应用内 127.0.0.1 服务提供，因此 Debug/Profile 与 Release 都需要 network server entitlement，ATS 只放行 local networking。服务不得监听 0.0.0.0 或局域网地址。 红色关闭应隐藏窗口，而不是退出应用。 侧边栏是悬浮圆角面板；它的间距和外侧圆角关系会影响其他 macOS 边缘间距决策。 软件内选择浅色/深色时，Flutter 主题、玻璃 renderer 读取的 MediaQuery.platformBrightness 、 NSApp.appearance 和主窗口 appearance 必须同步；否则系统模式与应用模式不同时，原生玻璃会使用错误明暗外观。 启动窗口策略： 冷启动时 AppKit 会先创建原生窗口，而 Flutter 首帧需要等待存储和版本信息初始化；如果立即显示原生窗口，会短暂看到带 Fourier 标题、红黄绿按钮和灰色 visual effect 背景的空壳窗口。 MainFlutterWindow.order(...) 必须调用 hiddenWindowAtLaunch() ，让 window_manager 在首次排序时隐藏原生窗口；仅调用 Dart 侧 waitUntilReadyToShow() 不足以保证 macOS 原生窗口不会提前出现。 Dart 侧应等待窗口配置完成，再运行 Flutter；首帧栅格化完成后才调用 windowManager.show() 。当前保留 5 秒超时回退，避免首帧异常时窗口永远不可见。 macOS 在配置窗口和 runApp 之前调用 LiquidGlassWidgets.initialize() ，让液态玻璃 shader 在窗口隐藏期间完成预热。不能只依赖各玻璃控件首次构建时异步加载：原生端 shader 就绪后不会保证立即重建控件，可能导致刷新、排序和未读切换在首次同步完成前只显示普通 fallback，随后才突然恢复玻璃效果。 XIB 初始尺寸和 Dart WindowOptions 默认尺寸均为 1000 x 750 ，避免原生窗口先按 800 x 600 创建、随后再跳到 Flutter 默认尺寸。 原生标题从窗口创建时就隐藏，避免首帧之前短暂显示 Fourier ；自绘红黄绿按钮在原生窗口中直接创建，不依赖 Flutter 首帧。 本轮没有新增“记住上次窗口尺寸”。红色关闭后的进程内重新打开仍保留当前窗口尺寸；完全退出后的冷启动仍使用 1000 x 750 。 近期 macOS 专属行为： 时间线 header 有 未读 / 全部 快速切换。 已读文章入口/页面仍然存在，但中间 header 快速切换不包含 已读 。 时间线排序按钮位于同步按钮左侧。 具体订阅源筛选下，中间时间线 header 不显示订阅源级自动拉取全文/自动翻译/静默设置，也不显示清除筛选；这些范围和设置由左侧侧边栏承担。 即使同步在 widget 订阅前已经开始，同步按钮也应开始旋转。 文章图片 hover 不再缩小图片，也不显示边框；可点击图片通过 native channel 使用 macOS zoom-in 光标。 中间时间线/列表 header 不再使用玻璃背景，也不保留底部分隔线。 文章详情使用固定 surface header，不做整块毛玻璃或顶部渐隐；底部始终显示细分隔线，阅读进度覆盖在其上。 ma"
 },
 {
  "path": "product/overview.html",
  "title": "产品定位",
  "headings": [
   {
    "id": "核心价值",
    "text": "核心价值"
   },
   {
    "id": "主要功能",
    "text": "主要功能"
   },
   {
    "id": "优先级",
    "text": "优先级"
   },
   {
    "id": "身份与命名空间",
    "text": "身份与命名空间"
   },
   {
    "id": "相关页面",
    "text": "相关页面"
   }
  ],
  "text": "产品定位 Fourier 是一个个人使用的高密度 RSS/Folo 聚合阅读客户端，基于 Flutter，支持 Android 与 macOS。它是 X-Ray 个人使用的软件，围绕 Folo 使用场景构建，但 不是 Folo、RSSNext 或其运营方的官方客户端，也不代表官方发布版本。 核心价值 同步 Folo 文章，按源筛选，逐块渲染长文，并基于 DeepSeek 完成可配置的翻译、摘要与垃圾拦截判定。 聚焦高密度信息流阅读：时间线、未读/全部/已读模式、长度排序、macOS 分栏阅读。 所有 AI 能力（翻译、摘要、垃圾拦截）都是辅助工具，最终决定始终由用户做出。 主要功能 时间线 — 未读/全部筛选、最近阅读、长度排序与 macOS 分栏阅读。 订阅源 — Articles / Social Media / Inbox 分组，分类与订阅源筛选、搜索、静默订阅源。 文章阅读 — HTML 拆块渲染、目录跳转、Markdown 复制、图片画廊与视频播放（普通视频、YouTube、Bilibili）。 垃圾拦截 — DeepSeek 判定后进入独立审核页，可保留或移除，不直接替用户做最终决定。 已读同步 — 本地 + Folo 云端双向同步。 AI 翻译 / 摘要 — 独立 LLM 配置与后台队列；自动任务只服务仍未读的文章。 配置迁移 — 设置可导出为 JSON 并通过剪贴板导入。 桌面体验 — macOS 原生分栏、克制的 Liquid Glass、右键菜单、快捷键与同步状态反馈。 优先级 快速、可重复的阅读工作流。 低摩擦的 macOS 分栏阅读体验。 稳定的 Android 行为。 同步、翻译、摘要、过滤任务要有清晰反馈。 避免 UI 看起来像 Folo 官方品牌，或暗示官方所有权。 身份与命名空间 产品名： Fourier ；Dart package 名： fourier 。 Android applicationId / macOS bundle id / MethodChannel 命名空间统一为 io.github.xraygit.fourier 。 历史 com.folo.* 与 com.autofolo 引用已经废弃，不得重新引入。 相关页面 设计原则 术语 隐私 当前状态"
 },
 {
  "path": "product/principles.html",
  "title": "产品原则",
  "headings": [],
  "text": "产品原则 Fourier 是一个个人使用的高密度 RSS/Folo 阅读工具。 优先级： 快速、可重复的阅读工作流。 低摩擦的 macOS 分栏阅读体验。 稳定的 Android 行为。 同步、翻译、摘要、过滤任务要有清晰反馈。 避免 UI 看起来像 Folo 官方品牌，或暗示官方所有权。 设计偏好： 构建真实可用的界面，不做营销页。 操作型 UI 应安静、紧凑、可读。 macOS 上选择性使用 Liquid Glass；不要把所有表面都变成重型玻璃。 当性能或可读性有风险时，优先使用轻量控件。"
 },
 {
  "path": "product/privacy.html",
  "title": "隐私",
  "headings": [],
  "text": "隐私 规则： 永远不要提交 token、cookie、session id、API key、私有文章原始数据或抓取的 API 响应。 临时脚本和抓取的真实文章 payload 应放在已忽略的 scratch/ 。 GitHub Secrets 不存放在仓库中。 历史敏感信息此前已经清理；不要重新引入到文档、提交、测试 fixture 或日志里。 不要把真实导出设置值粘贴到文档中，只泛化提到设置 key。 不要在 history/archive/ 、 history/chronology.md 或其他交接文档中保存真实文章 HTML/API payload；改为总结观察结果。 当前数据边界： Folo Session Token 与 DeepSeek API Key 保存在应用私有目录内的 Hive setting box；当前未使用 Keychain、Android Keystore 或 Hive 加密。这能隔离普通应用，但不能抵御已取得本机用户文件、设备备份、root 权限或恶意软件访问的攻击者。 配置导出是用户确认后触发的迁移功能，会按既定产品要求把 Folo 凭据、DeepSeek API Key、Prompt 与订阅源偏好写入系统剪贴板。界面必须明确警告敏感内容；不要在后台自动导出，也不要把导出值写入日志、文档或测试 fixture。 正文抓取使用不携带 Folo 凭据的独立 HTTP 客户端；认证客户端只允许访问精确的 https://api.folo.is API 边界。不要用认证客户端加载文章原文、图片、视频或任意外部 URL。 远程图片、视频和原文抓取会直接联系相应源站、CDN 或明确配置的代理，因此对方可能观察到用户 IP、请求时间与资源 URL。这是联网阅读的固有边界，不应在未评估信任和可用性取舍时统一改走第三方代理。 Android 浏览器登录回调可能短暂在原生进程内存中包含 Session Token；登录完成、取消或超时后必须同时清除 Dart handler 与原生 pending callback。 日志约束： HTTP 日志不得输出请求/响应 headers、body、cookie、Authorization 或回调 URI。 调试日志也不要输出文章标题、正文、Prompt、模型输出或用户身份信息；诊断优先使用无语义计数、状态名和错误类型。 发布产物： 旧 GitHub Release assets 可能包含历史签名/构建产物。用户表示可以在未来 release 后手动删除。 除非明确要求，否则不要轮换密钥或清理历史；这是另一个高影响操作。 历史重写上下文： 如果敏感文本存在于旧提交，仅从当前文件删除是不够的。 如果用户要求彻底清理，应使用有针对性的历史重写，并且只在用户确认备份和取舍后 force-push。"
 },
 {
  "path": "product/terminology.html",
  "title": "术语",
  "headings": [],
  "text": "术语 Fourier：本应用。 Folo：本应用使用的上游服务/软件生态。 时间线：本地文章列表，包含未读/全部/已读模式和过滤条件。 垃圾拦截/审核：用于审核 AI 拒绝文章的页面。 静默订阅源：默认从普通时间线计数/列表中隐藏，除非被显式选择。 Readability：拉取后的全文内容。 翻译：按文章缓存的翻译 HTML/标题。 摘要：按文章缓存的 LLM 生成摘要。 TOC：根据标题生成的文章目录。"
 },
 {
  "path": "status/current.html",
  "title": "当前状态",
  "headings": [],
  "text": "当前状态 截至 2026-08-12： main 是当前集成分支。 Fourier 品牌迁移与离线工程 Wiki 已通过独立 merge commit 合入 main 。应用展示名、Dart package、Android application id、macOS bundle id、MethodChannel、构建产物和图标均已迁移；旧 Auto Folo 名称只允许存在于历史证据、旧设置导入与明确的迁移兼容说明中。 GitHub 仓库、本地目录和 origin 已统一迁移为大写品牌名 Fourier ：远端是 X-Ray-git/Fourier ，本地 clone 目录名是 Fourier 。旧仓库 URL 只依赖 GitHub 重定向，不得再作为当前链接写入代码或文档。 Wiki 采用可离线双击的单文件 HTML 页面体系，正文以 Markdown 语法内嵌； index.html 是阅读入口，维护规则见 meta/site-guide.html 。 Android 设计迁移已通过 merge commit bd8c1b8 合入 main ；新代理应以 main 中的移动端实现为当前事实，不再等待旧 android 分支。 Android 时间线、垃圾拦截、最近阅读、订阅源详情和文章正文已统一为透明 header + 共享边缘渐隐；顶部圆形工具按钮使用真实局部背景模糊，安全距离和渐隐坐标由 MobileEdgeFadeStack 集中维护。文章列表保留底部渐隐，正文不使用底部渐隐。具体参数和回归边界见 platforms/android.html 。 本地 main 仍可能领先远端；提交/推送前必须先看 git status --short --branch 。 最近一批 worktree 功能已经用 merge commit 合入 main ，保留了分支历史。 除非用户明确要求，否则不要创建 release/tag。 AGENT_HANDOFF.md 现在只作为短入口。维护型交接知识库位于 docs/agent_handoff/ 。 旧单文件时间线已拆入 docs/agent_handoff/history/archive/ ； history/chronology.html 提供全部旧章节索引， history/timeline.html 仅保留兼容入口。当前事实不得写入历史归档。 macOS 已接入本地能耗诊断日志，用于定位无法稳定复现的“高耗电量”提示；当前空闲实测无持续 CPU 占用或电源断言，启动/刷新图片预取是首要待量化对象。日志边界与路径见 features/performance.html ，不得在没有证据时直接削弱用户明确选择的图片预取策略。 当前产品形态： Flutter 应用，使用 GetX、Hive、Dio 和本地缓存。 文章关系建立是默认关闭的可选实验功能。两端设置页可立即启停；关闭不积压、不追溯，已有关系保留。关系区分无向的“近似重复”和“同一事件”，当前仅记录、展示与统计，不自动拦截。默认请求已使用稳定 Axxxxxx ID、 articles 和 new_ids 保护 DeepSeek 前缀缓存。 产品名： Fourier 。 Dart package 名仍是 fourier 。 Android application id、macOS bundle id、MethodChannel 命名空间使用 io.github.xraygit.fourier 。 这是 X-Ray 个人使用的软件，围绕 Folo 使用场景构建，但不能暗示官方 Folo 所有权。 macOS 使用 Folo 官方网页 + loopback callback；Android 动态提供 Email、Google、GitHub 登录，其中社交方式使用 Better Auth Expo 同类的系统浏览器 + 精确 folo://fourier-auth 回调。手动长期 Session Token 与 version 1 配置导入继续兼容。当前是单一活动账号，本地退出/Token 变化会保留普通设置并重建全部账号内容，不执行 Folo 远端 sign-out。两端设置页使用本地缓存的 Folo 头像和用户名表达登录身份，旧 Token 会按需补全资料，登录入口等待 provider 时有明确加载动画。macOS 与 Android Google 基础链路已由用户确认；Android 多方式选择、GitHub、Email/TOTP 及新账号卡视觉仍待验证。 用户最近已验证： 大批 worktree 合入后的 macOS 视觉检查可接受。 macOS 文章工具栏 hover 闪烁已修复。 从卡片右键菜单删除摘要后，文章详情能立即更新。 工具链已对齐到本地与 GitHub Actions 均使用 Flutter 3.44.6 ，项目最低约束为 Flutter >=3.44.0 、Dart ^3.12.2 。macOS 插件完成纯 SwiftPM 迁移， screen_retriever 0.2.2 修复最后一个不兼容项；CocoaPods 工程引用、Podfile/lock 和旧并行签名补丁已删除。Android Debug、macOS Debug/Release 均已本地构建通过，Release 主程序确认为 arm64。 macOS 中间时间线在具体订阅源筛选状态下，header 不再显示重复的订阅源级按钮，也不再显示清除筛选按钮；用户验证该视觉调整符合预期。 垃圾拦截页开始复用普通时间线的同步按钮和文章 AI 右键菜单：刷新按钮位置已按时间线 header 对齐，文章审核行右键也有翻译/摘要相关动作。 flutter run -d macos --no-pub 的“构建成功但等不到 debug connection”问题已定位为 Xcode Debug Dylib 被 macOS 系统策略拒载，并通过 Debug 配置 ENABLE_DEBUG_DYLIB = NO 修复。 macOS 分屏文章详情右下角圆角安全区处理已由用户验证方向正确：正文 body 使用右下角 clip 避开窗口外框圆弧，避免内容贴到应用外框圆角。 最近阅读页文章进入详情后不应显示“标为已读”。根因是 ArticleController 只读 GStorage.readStatus ，忽略了传入文章自身的 isRead ；已修为 LocalArticleDbService.readOverrideOf(entryId) ?? article.isRead 。时间线和最近阅读列表的本地已读合并也同步改为 readOverrideOf() ，同时支持本地标已读和恢复未读。 macOS 中间栏 header 的底部分隔线已统一取消，覆盖最近阅读、订阅源详情和垃圾拦截。普通时间线此前已取消同类分隔线。 ArticleCardChrome 现在统一文章卡片外壳参数：外边距、内部 padding、圆角、普通态填充和边框。普通时间线 ArticleCard 与垃圾拦截 _MacReviewRow 都应从这里取值；垃圾拦截行只保留"
 },
 {
  "path": "status/pending.html",
  "title": "待办与搁置事项",
  "headings": [
   {
    "id": "操作事项",
    "text": "操作事项"
   },
   {
    "id": "已确认的功能缺口",
    "text": "已确认的功能缺口"
   },
   {
    "id": "已接受的源内容边界",
    "text": "已接受的源内容边界"
   },
   {
    "id": "条件触发的架构方向",
    "text": "条件触发的架构方向"
   },
   {
    "id": "维护规则",
    "text": "维护规则"
   }
  ],
  "text": "待办与搁置事项 这是当前有效的未来事项索引，但不是必须立刻执行的任务列表。 history/archive/ 中的旧“后续计划”只是历史证据；除非已经提炼到本页或当前专题页，否则不能据此直接开工。旧章节的时间顺序和位置通过 history/chronology.md 查询。 操作事项 发布：当前源码版本为 1.2.0+31 。除非用户明确要求，不提前改版本、打 tag 或触发 release；下一版本号应根据此后的实际改动规模按既有语义化规则决定。 Worktree 清理：本地可能仍有功能 worktree。删除前必须检查，并且只在用户确认后清理。 旧 GitHub Release assets：可能包含历史签名或构建产物；用户可以在未来 release 后手动删除。当前不主动轮换密钥或改写历史。 Android 多方式登录：Google 的精确深链、Session 落地和数据重建已真机确认；仍需验证方式选择 UI、取消、GitHub、Email 错误反馈、Email 正常登录及 TOTP（具备对应账号时）、账号切换确认和本地退出重登。当前 intent filter 只声明精确 host；若仍出现应用选择器或进入官方 Folo，必须停止并重新评估，不能扩大到整个 folo:// 。 Android 误分类按钮：macOS 已上线（ N /右上角旗帜按钮）；Android 是否安装待定。字段与统计语义已随共享模型落库，接入时复用 applyMisclassify / applyFilterReject / applyFilterKeep 与页面级/组件级快捷键模式，并补充本页 features/filter-review.md 的禁用规则。 已确认的功能缺口 旧图片缓存清理：新文章级缓存机制不会清理历史 v2_ 文件。后续如确有空间回收需求，应提供一次明确的旧缓存清理操作，不要把迁移隐式塞进普通刷新。 关系自动拦截：第一阶段只记录和展示关系。待真实数据确认关系数量与准确性后，再决定是否启用“任意近似重复组员已读时，把尚未人工 K/M/N 的未读组员移入垃圾拦截”。只有 equivalent （近似重复）可以参与自动化； same_event （同一事件）因允许明显新增信息，只用于发现和对比。启用前必须评估已有关系会移动多少文章；若会批量影响现有数据，应先确认，不能静默生效。K/M/N 文章永远不能作为连带操作目标，但已读的 K/M/N 仍可作为触发来源；K 不等于关系误判。质量过滤与关系原因必须结构化保存，未来同时命中时才机械展示 相关文章已阅读；质量理由 。 已接受的源内容边界 破损交互式 iframe：部分 Folo 内容已丢失 srcdoc 或脚本上下文，无法可靠还原。若未来支持，应重新抓取原网页并设计受限、懒加载 WebView；不要放宽当前“仅 YouTube/Bilibili 官方视频 iframe”白名单。 罕见畸形 HTML：继续遵循窄修复原则。除非同类失败明确反复出现，否则不要为了个例增加复杂通用启发式。 条件触发的架构方向 阅读渲染与 LLM 输入清洗拆分：只有表格、Newsletter 布局等规则继续分化时，才审计调用链并建立两套规范化管线与独立缓存键。 macOS 分栏文章列表协调器：垃圾拦截和主时间线已经接入；最近阅读尚未迁移。只有最近阅读继续出现选择、移除动画或 reveal 分叉问题时再接入，且恢复未读后的选择语义需要先确认。 文章正文虚拟化：正文 Column 是有意保留，用于保护全文选择、目录锚点、图片生命周期和稳定滚动。只有出现可复现且其他办法无法解决的长文性能问题时，才重新评估 SliverList.builder 。 macOS 滚动惯性：已有可配置 fling 上限；更深层触控板输入过滤因早期实验效果不佳且可能破坏平台手感、scrollbar、选择、嵌套滚动和可访问性而搁置。 完整 Liquid Glass UI：当前实现刻意克制。未来若做更大范围 macOS UI 重构，必须持续做性能验证，不能在密集重复元素上重新引入重型玻璃。 Android 视觉 fallback：这不是要求把 macOS Liquid Glass 完整移植到 Android。Android 应继续使用轻量实现，不继承 macOS 专属 renderer 和重复玻璃的性能成本。 真实窗口后方取色边框：Flutter-only 方案已放弃。若重新讨论，应作为独立 native/AppKit renderer 实验。 圆角/半径统一：macOS 主几何层第一阶段已完成。后续只在用户视觉验证驱动下微调，不全局替换图片、胶囊、小标签或 Android 圆角。 菜单视觉统一：文章动作、正文图片和图片查看器菜单已经迁移；普通筛选/下拉菜单只有在现有视觉确实产生问题时再决定是否迁移。 文章封面：当前没有独立封面机制。未来加入时必须使用 article-cover 缓存角色，不能复用正文五分钟清理键。 其他旧缓存数据迁移：除非用户明确要求，一般不做批量迁移；大多数兼容修复只作用于新拉取数据或读取时规范化。 维护规则 新增明确延期事项时更新本页，并在对应专题页保留实现边界；不要只写进历史时间线。 已完成、取消或被新决策覆盖的事项应从本页删除，历史证据继续留在 history/archive/ 、 history/chronology.md 和 history/decisions.md 。 继续维护专题页和决策页，不要重新形成单个巨大的交接文档。"
 },
 {
  "path": "status/verification.html",
  "title": "验证记录",
  "headings": [
   {
    "id": "2026-08-12-macos-能耗诊断",
    "text": "2026-08-12 macOS 能耗诊断"
   },
   {
    "id": "2026-08-04-误分类n标记与撤销",
    "text": "2026-08-04 误分类（N）标记与撤销"
   },
   {
    "id": "仍需持续观察",
    "text": "仍需持续观察"
   },
   {
    "id": "2026-07-25-android-角标与跨平台文章长度",
    "text": "2026-07-25 Android 角标与跨平台文章长度"
   },
   {
    "id": "2026-07-22-android-主导航与文章悬浮图标",
    "text": "2026-07-22 Android 主导航与文章悬浮图标"
   },
   {
    "id": "2026-07-18-android-设计迁移验证",
    "text": "2026-07-18 Android 设计迁移验证"
   },
   {
    "id": "2026-07-31-macos-folo-浏览器登录与账号重建",
    "text": "2026-07-31 macOS Folo 浏览器登录与账号重建"
   },
   {
    "id": "2026-08-01-android-folo-登录入口",
    "text": "2026-08-01 Android Folo 登录入口"
   },
   {
    "id": "2026-08-08-关系状态请求统计与全屏导航",
    "text": "2026-08-08 关系状态、请求统计与全屏导航"
   },
   {
    "id": "常规检查",
    "text": "常规检查"
   }
  ],
  "text": "验证记录 2026-08-12 macOS 能耗诊断 当前正式版在省电模式、无 LLM 请求且已运行约一天时，短时空闲采样约为 0.0%–0.1% CPU ； pmset 未发现 Fourier 持有防休眠或网络活跃断言。暂未证明存在空闲永久高负载。 新增本地轮转诊断，记录 CPU、内存、低电量/温度状态、帧耗时和各后台队列计数；不记录内容或凭据。后续需使用包含本改动的 macOS 构建正常使用，待系统再次提示高耗电后检查 energy.jsonl ，判断高峰是否与刷新图片预取、同步、AI 队列或 UI 慢帧重合。 隐藏 macOS 主页面已关闭 ticker，隐藏任务中心停止每秒刷新。定向测试、 dart analyze lib test （无新增 warning/error）及 macOS Debug 构建通过；构建中只保留 video_player_avfoundation 的既有弃用 warning。 2026-08-04 误分类（N）标记与撤销 已完成端到端验证： 四种动作标记写入正确：拦截页 K → k 、拦截页 M → m 、拦截页 N → n_keep 、时间线 N → n_spam ，状态组合（拒绝/已读/已审）与理由保留全部符合预期， tool/inspect_user_actions.dart 核对通过。 Cmd+Z 撤销回滚验证：时间线 N 后立即撤销，文章完整还原为 拒绝=false 已读=false 已审=false act=null （forceReplace 整条替换快照生效）。 撤销栈清空行为符合预期：跨应用实例的动作（如调试构建期间的受控测试标记）不在新实例的撤销栈内，无法撤销，属预期。 误分类功能相关的旧 bug 修复后确认：已读视图/最近阅读打开文章不再出现白色覆盖（GetX 误用修复）；拦截页未点开详情直接按 M/N 也能生效（页面级处理器）。 正式版已重建（ flutter build macos --release ），134 项 Flutter 测试通过、 dart analyze lib 无 error。 用户测试产生的标记与状态污染已用一次性脚本清理，数据库恢复为 0 标记残留。 仍需留意： Android 尚未加入误分类按钮（按计划待定）；字段随共享模型落库，后续接入即用。 调试构建期间曾发生两次无日志、无崩溃报告的静默退出（无退出码捕获前），未定位根因；正式版未复现。若正式版再次出现，需在带退出码捕获的启动方式下复现。 旧版本二进制混用会静默剥掉 userAction （已接受语义），统计结果应视为\"只有真的没有假的\"。 合并审查补充修复：页面级快捷键已放行 Alt/Control/Command；撤销同步失败会重建完整操作态；所有现有文章复制路径均保留 userAction ；时间线误分类不再用立即通知绕过退场动画。新增修饰键状态和操作态快照测试； flutter test --no-pub 共 136 项通过， dart analyze lib test tool 无 error/warning，仅保留 67 条既有 info。 统计范围经用户再次确认只需近期分析：记录随 articleDb 的 5000 篇缓存和账号清理生命周期存在，不承诺永久完整历史。 仍需持续观察 2026-07-31 图片加载失败重试机制已收敛到 ArticleImageCacheService （自动指数退避 1s/2s/4s 共 3 次、失败状态落盘、全局刷新 retryFailedPrefetches 串行重扫、成功后以图片级 successRevision 精确重建）。需在 macOS/Android 真机验证：打开含失败图片的文章，确认失败占位先显示“重新加载中…”、后台自动重试成功后占位自动变成图片（无需手动点）；自动重试耗尽后占位文案变为“图片加载失败，点击重试”，手动点击仅发起一条 service 下载链并可恢复；普通位图与独立块级 SVG 都需覆盖。切到时间线做一次全局刷新，确认之前失败的图片会在缓存清理完成后重新排查，进程重启后刷新仍能重扫落盘记录。HTML 行内图片扩展和图片画廊本次未纳入重试，属预期范围边界。决策与边界见 history/decisions.md “图片加载失败的重试统一收敛到 ArticleImageCacheService”。 2026-07-31 Android 设置页 _LlmConfigCard （翻译/摘要/过滤 LLM 参数卡片）展开后第一个下拉框“模型”的浮动 label 上半部分被裁切。根因是 ExpansionTile children padding 顶部为 0 ，浮动 label 向上越出 OutlineInputBorder 约 8.6px 的部分被 ExpansionTile 内部 ClipRect 和外层 MobileSettingsPanel 的 Clip.antiAlias 切掉；已把该 padding 顶部改为 10 。需在真机分别展开翻译、摘要、过滤三个 LLM 参数卡片，确认“模型”及其他首项浮动标签完整显示，且展开动画和卡片整体布局无异常。静态分析与排查结论见 history/decisions.md “带浮动标签的设置输入控件上方必须为裁切容器预留缓冲”。 2026-07-29 YouTube SABR 首选播放器尚待用户实机验证。macOS 与 Android 分别打开真实 YouTube 文章，检查首次点击有即时 loading、能够开始播放、 播放/暂停、拖动橙色进度条、清晰度/字幕/语言/倍速切换和系统全屏可用； 单击画面应只显隐控件，播放时 3 秒淡出、暂停时保持显示。macOS 触控板在 视频画面和控制栏上纵向滑动应继续滚动文章，打开分辨率/字幕菜单后菜单 自身仍可滚动；开始播放后点击文章其他位置， Space /媒体播放键仍应控制 当前视频，同篇切换另一视频后快捷键归属应随之转移。Android 触摸纵向 滑动不得被 WebView 锁死。切换文章不能残留上一篇控制器；SABR UMP 没有 媒体段时应先尝试同控件的普通自适应 DASH，只有两者都失败才在 35 秒内 切到官方 iframe，不得打开无关浏览器页面；官方 iframe 的内部滚轮不承诺 桥接。 macOS Release 还需确认 sandbox 下 loopback server 可以绑定；Android 需确认只放行 localhost 明文而外部 HTTPS 行为不变。 macOS 静默订阅源批量导出的入口、勾选、四类动作、morph 展开和 Esc 退出已完成用户运行确认。仍需在真实网络偶发部分成功时观察：本地列表、菜单篇数、刷新后的远端状态与 Undo/Redo 历史必须只反映最终确认改变的子集；保存取消或失败不能标为已读。 GitHub 发布 Actions 已迁移到 Node 24 对应的 checkout@v7 、 setup-java@v5 、 upload-artifact@v7 和 download-artifact@v8 ，Flutter pin 也从 3.41.6 "
 },
 {
  "path": "index.html",
  "title": "Fourier — 高密度信息流阅读客户端",
  "headings": [
   {
    "id": "推荐阅读顺序",
    "text": "推荐阅读顺序"
   },
   {
    "id": "硬性规则",
    "text": "硬性规则"
   },
   {
    "id": "维护规则",
    "text": "维护规则"
   }
  ],
  "text": "Fourier — 高密度信息流阅读客户端 Fourier · 非官方 Folo 客户端 把信息流变成 可以专注阅读的内容。 Fourier 将 Folo 时间线 、 长文阅读 与 可配置的 AI 工作流 放进同一个 Android 与 macOS 客户端。它负责拉取、整理和辅助判断，最终选择仍由用户完成。 开始阅读 Wiki 查看当前状态 macOS Android 个人非官方客户端 AGPL-3.0-only 离线 Wiki 非官方个人二次开发客户端，不隶属于 Folo、RSSNext 或其运营方，也不代表官方发布版本。 macOS 三栏阅读界面。真实产品截图，不使用概念性占位图。 核心能力 不止于阅读—— 从数据到决策的完整闭环。 从数据拉取到 AI 决策，每一层都经过精心设计。 高密度时间线 未读 / 全部 / 已读模式与长度排序，按分类、订阅源与静默订阅源筛选；macOS 原生分栏让列表与正文同步滚动。 AI 翻译与摘要 按订阅源自动翻译与生成摘要，保留 HTML 结构并支持原文 / 译文切换；模型、思考模式、temperature 与并发数独立配置，后台队列只服务仍未读的文章。 垃圾拦截审核 DeepSeek 逐篇给出保留 / 拒绝建议，被判定文章进入独立审核页：横滑、快捷键或右键菜单处理，最终决定由你做出。 长文与媒体阅读 HTML 拆块渲染、目录跳转、表格、代码块与 Markdown 复制；图片画廊与失败重试，普通视频、YouTube、Bilibili 内联播放并自动回退官方播放器。 订阅源管理 Articles / Social Media / Inbox 分组与静默订阅源，可撤销的添加 / 编辑 / 取消订阅，跨客户端同步的共享目录。 桌面体验与隐私 macOS 原生分栏、克制的 Liquid Glass、右键菜单与快捷键；凭据本地保存，配置可导出为 JSON 通过剪贴板迁移。 处理流水线 从 API 到你的屏幕， 每一步都可见。 01 拉取 从 Folo API 获取 feeds / social / inbox 三类未读文章。 02 本地合并 写入文章库并合并已读覆盖、订阅源与历史状态。 03 AI 判定 DeepSeek 给出保留 / 拒绝建议，被拒文章进入审核队列。 04 翻译与摘要 仍未读的文章按配置进入独立后台队列。 05 审核 横滑或操作菜单处理被拒文章，保留回时间线或移除。 06 同步 已读状态分批同步到 Folo，失败重试并保留待同步记录。 工程 Wiki 从当前状态开始， 按问题进入文档。 每个专题页正文都以 Markdown 语法内嵌在可直接阅读的 HTML 页面中； 克隆仓库后双击本页即可离线浏览，无需安装依赖或启动服务。 状态 → 当前状态 · 待办与搁置 · 验证记录 架构 → 概览 · 数据同步 · 网络 · 存储与缓存 功能 → 时间线 · 渲染 · 媒体 · 翻译 · 拦截 · 订阅 平台与设计 → macOS · Android · Liquid Glass · UI 交互 开发与操作 → 开发 · 测试 · 排障 · worktree · 发布 历史 → 决策日志 · 迁移 · 发布记录 · 主题归档 许可与致谢 → 第三方依赖 · 许可证声明 站点指南 → 如何编辑本 Wiki · 迁移映射 推荐阅读顺序 当前状态 — 最近的集成分支、产品形态与用户验证结论 待办与搁置事项 — 当前有效的未来事项索引 验证记录 — 仍需持续观察的开放验证项 开发流程 — 常用命令与检查方式 当前任务对应的专题页 需要历史证据时查 历史主题归档 ；按旧章节编号查找使用 历史时间索引 硬性规则 除非用户明确要求，否则不要创建 tag 或发布 release；发布只允许从 main 分支通过 scripts/release.sh 进行。 Flutter 项目健康检查优先使用 dart analyze lib test 、 flutter analyze lib test 和有针对性的 flutter test ；完整 dart analyze 会扫描 reference/ 并报告无关错误。 不要把密钥、API 响应、抓取的真实文章 HTML、临时脚本提交进 git。此类内容放进已忽略的 scratch/ 。 当前应用标识命名空间是 io.github.xraygit.fourier ；历史 io.github.xraygit.autofolo 、 com.folo.* 与 com.autofolo 仅用于迁移兼容或历史记录。 macOS 发布产物必须保持 arm64。 维护规则 这个知识库只保留当前仍有用的知识；专题页继续变大时按子专题拆分，不要无限追加。 原始历史证据按主题保存在 history/archive/ ；提炼总结时不要删除归档。 history/timeline.html 只用于兼容旧链接，不再追加内容。 记录决策时优先写入 history/decisions.html ，包含背景、决策、后果和“不要回退”的说明。 更新文档后运行 ./scripts/docs.sh index 重新生成搜索索引，并运行 ./scripts/docs.sh check 验证链接与一致性。"
 }
];
