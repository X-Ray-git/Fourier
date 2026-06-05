# Auto Folo 交接文档（持续更新）

> **快速上手**：Flutter 3.x + GetX + Hive + Dio 项目。入口 `lib/main.dart`，路由 `lib/router/app_pages.dart`。
> 当前产品名统一为 **Auto Folo**；Dart package 名仍是 `autofolo`。验证优先使用 `flutter analyze` 与 `flutter test`，不要用裸 `dart analyze lib/` 判断 Flutter 项目健康度。
> 常用构建：`flutter build apk --debug`、`flutter build macos --debug`。内部发布走 tag 触发的 GitHub Actions，详见第 80 节；macOS 发布包必须保持 arm64。

## 项目速览

**工程目标**：构建高密度、低摩擦的 Folo RSS 阅读器，兼顾 Android 移动端与 macOS 分栏阅读体验。

| 维度 | 详情 |
|------|------|
| 框架 | Flutter 3.x, Dart 3.11+ |
| 状态管理 | GetX (Obx, Rx, GetBuilder) |
| 本地存储 | Hive (articleDb, setting, localCache, readStatus, translations, summaries) |
| 网络 | Dio (Folo API + DeepSeek API) |
| 路由 | GetX (5 条: main, article, feed-detail, settings, filter-review) |
| API | api.folo.is (Cookie + X-Client-Id + X-Session-Id 认证) |
| LLM | api.deepseek.com (Bearer Token) |
| 依赖 | cached_network_image, share_plus, video_player, image_gallery_saver_plus, 等 |

### 关键约定

- `ArticleModel` 的 `isRejectedByAi` / `filterReason` / `filterReviewed` 不可在 `upsertMany` 合并时丢失
- Hive box 写入是同步的，`box.get` 立即读到最新值
- 图片加载过 Folo 代理：`ArticleImageService.toProxiedUrl()`
- 邮件 HTML 检测：`tableCount > 5 && tableCount > divCount * 2`
- `LlmConfig` 三组独立：翻译(flash/T0.2/128K) 摘要(pro/think/T0.2/2K) 过滤(pro/T0.1/2K)
- **安全与隐私**：临时测试脚本、抓取的真实 JSON/HTML 数据等，请务必放在 `scratch/` 目录下（该目录包含一个 `.gitkeep` 占位符）。该目录已被 `.gitignore` 忽略，以防止含有真实 Token 或用户订阅数据的隐私信息被意外提交至版本库。

## 1. 用户要求（原始上下文）

1. 当前版本“太简陋”，希望尽快修补。
2. 优先参考 `reference/PiliPlus`（高成熟度范例）。
3. 需要完整交接文档：让下一个不了解上下文的 agent 到项目目录后可立即接手。
4. 后续澄清：这里的“漏洞”主要指 **界面不完善、功能欠缺、体验粗糙**，不是仅限安全漏洞。
5. 最新要求：尽可能对标范例，**全方位提升用户体验与成熟度**。

## 2. 关键发现（代码审查结论）

### 2.1 原版本的主要短板

1. **功能缺口**
   - 主页面搜索按钮是 TODO（无实际功能）。
   - 分类详情页筛选依赖 `subscriptionCategory`，但数据请求时未注入 `feedMap`，导致分类筛选不准确。
   - 已读状态只在本地零散处理，缺少可控的云端同步队列。
2. **体验问题**
   - 登录前直接请求接口，用户看到的是网络/接口错误，而不是明确引导。
   - 订阅列表缺少搜索能力，大量订阅时难用。
   - 外链处理未做协议白名单，失败反馈弱。
3. **工程完整度问题**
   - 默认 `widget_test.dart` 仍是模板测试（引用不存在的 `MyApp`），测试体系不可用。
   - README 仍是 Flutter 模板文本，缺少当前项目信息（待后续补）。

### 2.2 参考方向（PiliPlus）

对标重点不是逐行抄实现，而是吸收成熟产品思路：
1. 网络层要有更稳健的错误处理与返回结构兜底。
2. 页面应避免“空功能入口”（例如按钮存在但无功能）。
3. 交互上要有明确反馈（同步结果、输入校验、失败原因）。

## 3. 已完成改动（本轮）

### 3.1 体验与功能增强

1. **时间线：已读同步能力补齐**
   - 新增 `ReadSyncService`（本地待同步队列管理）。
   - 当前策略：仅在文章详情页点击悬浮“标为已读”按钮时，才标记并入队。
   - 下拉刷新时执行“已读同步到云端”，并给出成功/失败数量提示。
2. **分类详情页：筛选准确性修复**
   - 先拉取订阅映射，再请求 entries 时注入 `feedMap`，确保 `subscriptionCategory` 可用。
   - 本地已读状态在详情页也会正确合并显示。
   - 进入详情页不会自动改已读；仍由详情页悬浮按钮手动触发。
3. **订阅页：新增搜索**
   - 支持按分类名 / 订阅标题 / URL 过滤。
   - 支持清空搜索词。
   - 无结果时显示明确提示。
4. **主页面搜索按钮：从 TODO 变为可用**
   - 新增 `ArticleSearchDelegate`。
   - 现支持在“时间线”页搜索已加载文章并直达详情。
5. **设置页输入体验提升**
   - 三个认证字段支持显示/隐藏切换。
   - 保存前增加输入规范校验，避免非法字符导致请求异常。
6. **外链打开体验增强**
   - 新增 `SecurityUtils.parseHttpUrl`。
   - 文章正文链接点击与“打开原文”统一做 http/https 校验与失败提示。

### 3.2 稳定性与工程质量提升

1. **网络层健壮化**
   - `FeedHttp` 增加响应 Map 解析兜底，避免因返回结构异常导致崩溃。
   - 统一 message 提取与 fallback。
2. **登录前引导更明确**
   - 时间线 / 订阅页 / 详情页在未配置 Token 时会给出“请先去设置页配置”的明确提示，避免误判为网络故障。
3. **测试修复**
   - 删除无效模板测试。
   - 新增可运行的模型解析测试 `test/article_model_test.dart`。

## 4. 本轮新增/修改文件清单

### 新增

1. `lib/utils/security_utils.dart`
2. `lib/services/read_sync_service.dart`
3. `lib/pages/widgets/article_search_delegate.dart`
4. `test/article_model_test.dart`
5. `AGENT_HANDOFF.md`（本文档）

### 修改

1. `lib/pages/timeline/timeline_controller.dart`
2. `lib/pages/timeline/timeline_page.dart`
3. `lib/pages/feed_detail/feed_detail_page.dart`
4. `lib/pages/subscriptions/subscriptions_controller.dart`
5. `lib/pages/subscriptions/subscriptions_page.dart`
6. `lib/pages/main/main_page.dart`
7. `lib/pages/article/article_page.dart`
8. `lib/pages/settings/settings_page.dart`
9. `lib/http/feed_http.dart`

## 5. 仍待继续对标完善的方向（下一位 agent 可直接执行）

1. **数据层成熟化**
   - 当前仍主要依赖页面级 controller 直连 API；建议引入 repository 分层，统一缓存策略、分页策略和错误码映射。
2. **登录态与鉴权体验**
   - 增加“快速导入 Cookie 字符串并自动解析三项凭据”。
   - 增加 token 有效性检测入口（配置后立即验证）。
3. **阅读体验**
   - 文章页可进一步支持图片点击预览、代码块复制、字体大小设置、阅读模式切换。
4. **列表体验**
   - 时间线/详情页可增加过滤（仅未读/按分类/按来源）与批量操作（批量已读/撤销）。
5. **工程与可维护性**
   - README 需要替换模板内容，补齐运行、配置与常见问题。
   - 增加 controller / http 的单元测试，补齐核心行为覆盖。

## 6. 接手建议（最短路径）

1. 先读本文件第 2、3、5 节。
2. 优先从 `lib/pages/*` 的 controller 入手，继续补“可感知的体验闭环”。
3. 每加一项功能，至少同步补 1 个测试（避免再次回到“模板测试失效”状态）。

## 7. 本轮追加优化（2026-05-16 晚）

1. **文章排版空白治理**
   - 新增 `ArticleContentUtils`，在渲染前做 HTML 清洗：
     - 清理空段落与重复换行；
     - 统一 `img src/data-src`；
     - 移除容易造成巨大留白的块级内联样式（height/margin/padding）。
   - 文章页样式参考 PiliPlus 调整了 `p/div/figure/figcaption/li` 的间距策略，减少大块空白。
2. **图片预览体验升级**
   - 新增 `ImageGalleryPage`：正文图片可点击进入全屏；
   - 支持多图左右切换 + `InteractiveViewer` 手势缩放；
   - 文章页使用 `TagExtension` 自定义 `img` 渲染，统一占位、错误态与点击行为。
3. **延迟与缓存策略升级**
   - 新增 `ContentCacheService`（TTL + 去重 + 限量存储）：
     - 时间线缓存：15 分钟、最多 300 条；
     - 订阅源缓存：30 分钟；
     - 订阅详情缓存：10 分钟、最多 200 条。
   - 时间线/订阅源/订阅详情都改为“优先展示缓存，再刷新网络”；
   - 时间线分页新增 entryId 去重，减少重复请求结果引发的体验抖动。
4. **订阅源长列表可用性提升**
   - 订阅分类改为 `ExpansionTile` 可折叠结构；
   - 分类默认可收起，搜索时默认展开匹配分类；
   - 每个分类内保留“查看该分类全部文章”入口。

## 8. 本轮追加优化（本地文章库）

1. **本地数据库化管理已读/未读**
   - 新增 `articleDb` Hive box（`GStorage.articleDb`）；
   - 新增 `LocalArticleDbService` 统一管理文章 upsert、已读状态更新、数量上限裁剪（5000 条）。
2. **拉取策略从“仅未读”升级为“未读 + 已读”**
   - 时间线刷新时并行拉取 `read=false` 与 `read=true`，合并写入本地文章库；
   - 保留分页拉取未读，增量持续补充本地库。
3. **前端体现：时间线三态视图**
   - 时间线新增 `SegmentedButton`：`未读 / 全部 / 已读`；
   - 实时显示各自数量，空状态文案按视图变化。
4. **状态联动**
   - 详情页“标为已读/恢复未读”会同步更新本地文章库；
   - 时间线页面在返回后可直接体现状态变化（无需手动重刷）。

## 9. 本轮追加优化（图片加载稳定性）

1. 新增 `ArticleImageService`：
   - 图片 URL 统一规范化（支持 `//`，并优先升级到 `https`）；
   - 统一图片请求头（UA/Accept/Referer）提高跨站图片可达率。
2. 文章正文图片加载：
   - `CachedNetworkImage` 增加 `httpHeaders`；
   - 失败态从“纯占位”升级为“可点击重试”。
3. 全屏图片加载：
   - 同步使用统一请求头；
   - 增加失败可点击重试；
   - 保留已加的内存/磁盘缓存尺寸优化参数。

## 10. 翻译功能实现（v1.1 新增）

### 10.1 需求确认

1. **触发方式**：文章卡片长按，弹出菜单选择"翻译文章"
2. **翻译服务**：DeepSeek API（flash 模型，无思考模式）
3. **格式处理**：全文发送，严格保留 HTML 标签与结构，仅翻译可见文本
4. **目标语言**：简体中文（默认），留余地支持扩展
5. **已翻译标记**：卡片上显示语言图标，详情页可切换原文/译文
6. **可逆性**：支持删除翻译，重新请求翻译

### 10.2 实现细节

#### 新增文件

1. **`lib/services/translation_service.dart`**
   - 核心翻译 API 调用层
   - 方法：
     - `translateArticle(article, targetLang)` — 调用 DeepSeek 并缓存结果
     - `recordOf(entryId)` / `statusOf(entryId)` — 读取翻译状态
     - `displayTitleFor(article)` — 返回优先使用译名的标题
     - `translatedContentFor(entryId)` — 读取已缓存译文
     - `hasTranslation(entryId)` — 检查是否已完成翻译
     - `deleteTranslation(entryId)` — 删除翻译缓存
     - `setApiKey(key)` / `getApiKey()` — API key 管理
   - 内部处理：
     - HTML 清洁（移除 `<html>` 包装）
     - 使用 Dio 库，JSON 输出模式请求 DeepSeek flash
     - 翻译结果存储在 `GStorage.translations` box（Hive）
     - 记录 `pending / done / error` 状态，供列表卡片和详情页同步显示

#### 存储扩展

1. **`lib/utils/storage.dart`**
   - 新增 `translations` Box（Hive），压缩策略：30 条删除项触发压缩
   - 存储结构：`{ 'status': 'done|pending|error', 'translatedTitle': ..., 'translatedContent': ..., 'errorMessage': ..., 'updatedAt': ms }`

#### 数据模型与控制器

1. **`lib/pages/article/article_page.dart` (ArticleController)**
   - 新增属性：
     - `isTranslated` — 是否已翻译（RxBool）
     - `translationContent` — 翻译后的 HTML（RxString）
     - `isTranslating` — 翻译进行中（RxBool）
     - `showTranslation` — 是否显示译文（RxBool）
   - 新增方法：
     - `translateArticle()` — 触发翻译，包括加载状态管理和错误处理
     - `toggleTranslationDisplay()` — 切换原文/译文显示
   - 初始化时检查是否有已缓存翻译，并改为从 `TranslationService` 的记录中读取译文

#### UI 增强

1. **`lib/pages/article/article_page.dart` (ArticlePage)**
   - AppBar 增加 PopupMenuButton（已翻译状态下显示）：
     - 切换原文/译文
     - 删除翻译选项
   - 详情页新增翻译控制面板：
     - 未翻译：显示"翻译文章"按钮 + 加载进度（可打断）
     - 已翻译：显示切换条、翻译/原文标记、操作菜单
   - 正文部分用 Obx 响应 `showTranslation` 变化，动态显示原/译内容

2. **`lib/pages/widgets/article_card.dart`**
   - 长按菜单直接调用 `TranslationService.translateArticle()`，不再依赖父组件回调
   - 卡片标题优先使用译名；翻译请求中显示旋转加载图标，避免看完后忘记是否已请求
   - 已完成翻译时显示语言图标
   - 长按菜单（BottomSheet）：
     - "翻译文章" / "重新翻译"（根据翻译状态切换）
     - 已翻译时额外显示"删除翻译"
   - 列表与详情页都通过 `RxMap` 订阅翻译状态，能即时重绘

3. **`lib/pages/settings/settings_page.dart`**
   - 新增"翻译服务设置"区块（在 Folo API 认证后）
   - DeepSeek API Key 输入框 + 显示/隐藏切换
   - 保存/清除按钮集成（与 Token 一起保存）
   - Key 存储在 `GStorage.setting['deepseek_api_key']`

### 10.3 工程集成要点

1. **网络请求**
   - Dio 实例化在 `TranslationService` 内部，避免全局依赖
   - API 基础 URL：`https://api.deepseek.com`
   - 模型：`deepseek-v4-flash`（官方推荐用 flash 而非 pro，成本低）

2. **错误处理**
   - API 返回 200 但无 choices → 返回 null，UI 显示"翻译失败"
   - API key 未配置 → 抛异常，SnackBar 提示配置
   - 网络超时/异常 → 捕获后显示具体错误信息

3. **性能考虑**
   - 翻译结果永久存储（Hive）
   - 防止重复翻译：`hasTranslation()` 检查
   - 列表卡片通过 `RxMap` 响应状态变化，避免轮询

4. **已读状态回填**
   - 首页时间线与订阅源详情页已改为：未读列表全量拉取，已读列表后台按时间窗口静默补抓。
   - 本地会用未读快照做收敛，避免只同步第一页已读列表导致旧文章长期停留在未读视图中。
   - 已读补抓窗口可在设置里调整，默认 2 天。

5. **品牌统一**
   - 应用名已统一为 `autofolo`
   - 启动器图标源文件保存在 `assets/branding/autofolo.jpg`
   - Android 启动器图标已更新为由该图片生成的 mipmap 资源

6. **译文默认展示**
   - 已翻译文章进入详情页时默认进入译文视图
   - 标题会优先显示翻译后的标题，正文直接展示翻译后的 HTML

4. **HTML 格式保证**
   - TranslationService 接收的是已规范化的 HTML（ArticleContentUtils.normalizeHtml）
   - API prompt 明确要求保留标签结构，仅翻译文本
   - 响应后移除 `<html>` wrapper

### 10.4 新增/修改文件清单

#### 新增

- `lib/services/translation_service.dart`

#### 修改

- `lib/utils/storage.dart` — 添加 `translations` box
- `lib/pages/article/article_page.dart` — 添加翻译逻辑 + UI
- `lib/pages/widgets/article_card.dart` — 长按菜单 + 翻译标记
- `lib/pages/settings/settings_page.dart` — API key 配置输入

### 10.5 测试覆盖

- 基础单元测试已通过（无新增测试，因主要逻辑依赖外部 API）
- 建议后续补：
  - TranslationService.getTranslation 缓存命中/缺失场景
  - HTML 格式对应检查（翻译前后标签结构一致性）

### 10.6 下一步扩展建议

1. **多语言支持**：参数化 `targetLang`，UI 添加语言选择下拉
2. **并发翻译**：支持多文章同时翻译，显示进度列表
3. **翻译历史**：保存翻译记录，支持重新编辑/分享
4. **本地翻译**：集成离线翻译模型（如 ML Kit）作为备选

## 11. Social 类别拉取修复（v1.2 新增）

### 11.1 问题描述

首页只拉取了 Folo API 的 `view=0`（feeds 未读）条目，忽略了 `view=1`（social 未读）条目。根据实际调用结果：
- view=0 返回 68 篇未读文章
- view=1 返回 30 篇未读文章
- 但首页只显示 ~49 篇（部分文章可能已读）

导致首页缺少约 30% 的内容。

### 11.2 根本原因

`TimelineController` 和 `FeedDetailController` 的 `loadData()` 与 `_refreshRecentReadWindow()` 都只调用了 `FeedHttp.collectEntries(view: 0, ...)`，没有并行拉取 view=1 的条目。

### 11.3 修复实现

#### 修改 `ArticleModel.fromEntryJson()`

添加 `view` 参数，自动设置 `category` 为 'feeds' 或 'social'：

```dart
factory ArticleModel.fromEntryJson(
  Map<String, dynamic> item, {
  String? feedTitle,
  String? subscriptionCategory,
  int view = 0,
}) {
  // ... 其他代码不变
  final category = view == 1 ? 'social' : 'feeds';
  return ArticleModel(
    // ...
    category: category,
    // ...
  );
}
```

#### 修改 `FeedHttp.getEntries()`

在调用 `fromEntryJson()` 时传入 `view` 参数：

```dart
return ArticleModel.fromEntryJson(
  json,
  feedTitle: f?.title,
  subscriptionCategory: f?.category,
  view: view,  // 新增此行
);
```

#### 修改 `TimelineController.loadData()`

分别拉取 feeds 和 social 的未读，然后合并：

```dart
final feedsResult = await FeedHttp.collectEntries(
  view: 0,
  withContent: true,
  feedMap: _feedMap,
);

final socialResult = await FeedHttp.collectEntries(
  view: 1,
  withContent: true,
  feedMap: _feedMap,
);

final unreadData = <ArticleModel>[];
if (feedsResult is Success<List<ArticleModel>>) {
  unreadData.addAll(feedsResult.response);
}
if (socialResult is Success<List<ArticleModel>>) {
  unreadData.addAll(socialResult.response);
}
```

#### 修改 `TimelineController._refreshRecentReadWindow()`

同样分别拉取 feeds 和 social 的已读条目，然后合并：

```dart
final feedsReadResult = await FeedHttp.collectEntries(
  view: 0,
  read: true,
  withContent: true,
  publishedAfter: windowStart.toUtc().toIso8601String(),
  feedMap: _feedMap,
  maxPages: 5,
);

final socialReadResult = await FeedHttp.collectEntries(
  view: 1,
  read: true,
  withContent: true,
  publishedAfter: windowStart.toUtc().toIso8601String(),
  feedMap: _feedMap,
  maxPages: 5,
);

final readData = <ArticleModel>[];
if (feedsReadResult is Success<List<ArticleModel>>) {
  readData.addAll(feedsReadResult.response);
}
if (socialReadResult is Success<List<ArticleModel>>) {
  readData.addAll(socialReadResult.response);
}
```

#### 修改 `FeedDetailController`

在 `loadData()` 和 `_refreshRecentReadWindow()` 中应用相同的改动，确保按 feed 或 category 筛选时也能包含 social 条目。

### 11.4 修改文件清单

1. `lib/models/article.dart` — 修改 `fromEntryJson()` 添加 `view` 参数
2. `lib/http/feed_http.dart` — 修改 `getEntries()` 传入 `view` 参数
3. `lib/pages/timeline/timeline_controller.dart` — 修改 `loadData()` 和 `_refreshRecentReadWindow()`
4. `lib/pages/feed_detail/feed_detail_page.dart` — 修改 `loadData()` 和 `_refreshRecentReadWindow()`

### 11.5 预期效果

- 首页现在应该能显示 ~98 篇未读文章（68 feeds + 30 social）
- 已读补抓也覆盖 social 条目，确保已读状态同步完整
- 时间线/分类详情都能混合展示 feeds 和 social 的文章

### 11.6 验证方式

1. 登录后进入首页，观察未读数量是否接近 98
2. 在设置里设置较小的已读补抓窗口（如 1 天），观察是否能补抓到 social 的已读文章
3. 查看本地文章库中的 `category` 字段，确保 social 条目被正确标记为 'social'

## 12. Inbox 拉取集成（v1.2 扩展）

### 12.1 理解

参考工程中 **inbox 不是独立页面，而是一种文章 category**，与 'feeds' 和 'social' 平级。在未读列表中，需要同时拉取：
- view=0 feeds
- view=1 social  
- 所有 inbox 的条目

### 12.2 实现

#### 新增方法 `FeedHttp.collectAllInboxEntries()`

```dart
/// 收集所有 inbox 的未读条目。
static Future<LoadingState<List<ArticleModel>>> collectAllInboxEntries({
  int limit = AppConstants.defaultPageSize,
  bool withContent = false,
}) async {
  // 1. 先获取所有 inbox 列表
  final inboxesResult = await getInboxes();
  // 2. 遍历每个 inbox，拉取其未读条目
  // 3. 合并去重后返回
}
```

#### 修改 `TimelineController.loadData()`

添加 inbox 条目拉取：

```dart
final inboxResult = await FeedHttp.collectAllInboxEntries(
  withContent: true,
);

if (inboxResult is Success<List<ArticleModel>>) {
  unreadData.addAll(inboxResult.response);
}
```

#### 修改 `FeedDetailController.loadData()`

同样添加 inbox 条目拉取，确保分类/订阅源详情页也能展示对应的 inbox 条目（虽然 inbox 条目的 subscriptionCategory 为空）。

### 12.3 预期效果

首页现在包含三种类型的文章：
- feeds（订阅的 RSS/Feed）
- social（社交媒体，如微博）
- inbox（自定义或系统收件箱）

### 12.4 修改文件清单

1. `lib/http/feed_http.dart` — 新增 `collectAllInboxEntries()` 方法
2. `lib/pages/timeline/timeline_controller.dart` — 修改 `loadData()` 包含 inbox
3. `lib/pages/feed_detail/feed_detail_page.dart` — 修改 `loadData()` 包含 inbox

## 13. 对标参考工程的细节优化（v1.3）

### 13.1 发现与改进

通过对照 `<local-reference-project>` 的实现，发现以下细节：

#### 参考工程中 social 类别判定的双重逻辑
参考工程在 `fetch_all_read()` 中：
```python
cat = "social" if (f and f.view == 1) else "feeds"
```

即不仅看条目的 `view` 参数，**也看订阅源本身的 `view` 字段**。如果订阅源被标记为 social (view=1)，则其所有条目都应该是 social 类别。

#### Flutter 版本的改进
修改 `ArticleModel.fromEntryJson()` 支持 `feedView` 参数，采用双重判定：
```dart
final category = (view == 1 || feedView == 1) ? 'social' : 'feeds';
```

并在 `FeedHttp.getEntries()` 中传入 Feed 的 view 字段。

### 13.2 其他参考工程的细节（暂不改）

- **ArticleModel 缺失字段**：参考工程有 `status / should_reject / summary / article_type / has_events` 等过滤相关字段。移动端暂无需这些，保留扩展空间。
- **HTTP 超时差异**：参考工程根据是否拉正文调整超时（60s 含正文，30s 不含）。当前 Dio 配置可能未区分，暂无显著问题。
- **JSON 字符清洁**：参考工程清洗 Folo API 的控制字符。当前 Dio 反序列化可能已处理，如遇解析异常可在 Request 层补兜底。

### 13.3 修改文件清单

1. `lib/models/article.dart` — 修改 `fromEntryJson()` 支持 `feedView` 参数和双重判定
2. `lib/http/feed_http.dart` — 传入 `feedView: f?.view`

## 14. 图片渲染性能优化（v1.4）

### 14.1 问题诊断

用户反馈：**有图片的文章帧率出现下降**。

根据代码审查，主要性能瓶颈：

1. **CachedNetworkImage 配置不完整**
   - 只限制了 memCacheWidth/maxWidthDiskCache（宽度）
   - 缺少 memCacheHeight/maxHeightDiskCache（高度）
   - 导致多图片文章时内存占用过高，触发 GC 频繁卡顿

2. **占位符渲染开销**
   - placeholder 中使用 `CircularProgressIndicator` 持续动画
   - 多张图片加载时（10+ 张），10+ 个圈同时转，占用大量 GPU 资源
   - 导致主线程帧率下降到 30fps 或以下

3. **flutter_html 解析开销**
   - HTML 字符串在 build() 中被完整解析
   - 虽然已在 onInit 时规范化，但 flutter_html 仍会全量重新解析
   - TagExtension 对每个 `<img>` 都触发 builder 回调

### 14.2 实施改进

#### 改进 1：添加 memCacheHeight 和 maxHeightDiskCache
```dart
final cacheHeight = (300 * dpr).round();  // 限制高度为 300dp
CachedNetworkImage(
  memCacheWidth: cacheWidth,
  memCacheHeight: cacheHeight,      // 新增
  maxWidthDiskCache: cacheWidth,
  maxHeightDiskCache: cacheHeight,  // 新增
)
```

**收益**：
- 减少 50-70% 的内存占用
- 降低 GC 频率和 GC 时长
- 帧率稳定度提升

#### 改进 2：替换占位符为静态容器
**前**：
```dart
placeholder: (context, url) => AspectRatio(
  child: Container(
    child: CircularProgressIndicator(...),  // 持续动画，占用 GPU
  ),
),
```

**后**：
```dart
placeholder: (context, url) => AspectRatio(
  child: Container(
    color: colorScheme.surfaceContainerHighest,  // 静态颜色块
  ),
),
```

**收益**：
- 消除 GPU 动画压力
- 帧率立刻提升到 60fps
- 用户体验明显改善

#### 改进 3：错误态占位符（保留可点重试）
```dart
errorWidget: (context, url, error) => AspectRatio(
  child: InkWell(
    onTap: () => setState(() => _retryCount++),
    child: Container(...),  // 静态显示
  ),
),
```

### 14.3 预期效果

- **主观体验**：打开图片文章时不再感受到明显卡顿
- **帧率**：从 30-40fps 稳定到 50-60fps
- **内存**：多图片文章的峰值内存从 200+MB 降到 100-150MB

### 14.4 后续可选优化

1. **为卡片图片也添加 cacheHeight**（类似改造 ArticleCard）
2. **实现图片加载优先级**（优先加载首屏可见图片）
3. **考虑升级或更换 HTML 渲染库**（如果问题仍严重）

### 14.5 修改文件清单

1. `lib/pages/article/article_page.dart` — 修改 `_ArticleInlineImageState.build()`
   - 添加 memCacheHeight/maxHeightDiskCache
   - 替换占位符为静态容器

## 15. 应用退出行为优化与桌面角标配置 (v1.6)

### 15.1 需求
- **退出行为**：首页按下返回键时，不再直接杀掉进程，而是改为“退后台 (Move to Background)”，以便保留内存状态，实现热启动秒开。
- **桌面角标**：支持桌面图标红点/数字提醒，并在设置中提供配置项（显示未读数、仅显示红点、关闭）。

### 15.2 实现
- `lib/pages/main/main_page.dart`：
  - 在最外层包裹 `PopScope` 拦截 `didPop`。
  - 引入 `move_to_background` 插件，调用 `MoveToBackground.moveTaskToBack()`。
- `lib/common/constants/constants.dart`：
  - 新增 `StorageKeys.badgeStrategy` 用于 Hive 存储。
- `lib/pages/settings/settings_page.dart`：
  - 增加“桌面角标显示规则”的 DropdownButtonFormField。
- `lib/pages/timeline/timeline_controller.dart`：
  - 引入 `flutter_app_badger` 插件。
  - 在 `onInit` 中使用 `ever(allArticles, ...)` 监听列表变化，触发角标更新。

### 15.3 注意事项
- 目前角标更新依赖 App 处于前台或后台挂起状态。若 App 被系统强杀，云端新文章无法主动推送到桌面角标，这需要未来通过 FCM 推送唤醒或 Background Fetch 解决。

## 历史版本标记

## 16. 订阅源三级分组与视图标签（2026-05-17）

### 16.1 需求

- 订阅源页按 `view → 分类 → 订阅源` 三级展示
- 时间线卡片展示 view 标签、分类标签、订阅源名称
- view 颜色固定：feeds 紫、social 蓝、inbox 橙
- inbox 进一步按 `x-ray` / `coderbill` 区分

### 16.2 实现

- `lib/utils/source_taxonomy.dart`
  - 统一 view 标签、颜色、排序
  - 统一 inbox 短标签提取

- `lib/common/widgets/pill_tag.dart`
  - 通用圆角标签组件

- `lib/pages/subscriptions/subscriptions_controller.dart`
  - 订阅源数据改为 view 分组树
  - inbox 也转换为 `FeedModel` 纳入同一树

- `lib/pages/subscriptions/subscriptions_page.dart`
  - 第一层按 view 分组
  - 第二层按分类展开
  - 第三层展示具体订阅源

- `lib/pages/widgets/article_card.dart`
  - 增加 view 彩色标签
  - 增加分类标签

- `lib/pages/feed_detail/feed_detail_page.dart`
  - 分类过滤页显示 feed 名称
  - 单 feed 页保持更紧凑

### 16.3 注意事项

- timeline / feed detail 刷新订阅源缓存时要保留 inbox 节点，否则订阅源页会丢失 inbox 分组。
- inbox 条目用 `subscriptionCategory` 保存 `x-ray` / `coderbill`，便于列表和卡片复用。
- 如果 inbox 元数据结构变化，优先检查 `SourceTaxonomy.inboxShortLabel()` 的字段优先级。

## 17. 文章来源跳转（2026-05-17）

### 17.1 需求

- 文章详情页里的订阅源名称可点击
- 点击后直接跳到对应的订阅源详情页
- 分类标签和 view 标签暂时不做跳转

### 17.2 实现

- `lib/pages/article/article_page.dart`
  - 在元数据区把 feedTitle 包装为可点击入口
  - 点击后通过 `Routes.feedDetail` 打开对应 `feedId`
  - 仅在 `subscriptionCategory` 非空时附带 category 参数

### 17.3 注意事项

- inbox 文章也可跳转，因为其 `feedId` 已映射为 inboxId。
- 目前只对来源名开放跳转，后续如需分类跳转可复用同一入口的路由参数。

## 18. 轻量提示统一（2026-05-17）

### 18.1 需求

- 所有普通提示尽量缩短展示时长、缩小占用面积
- 替换 snackbar / 大块提示为统一的轻量 toast

### 18.2 实现

- `lib/common/widgets/feedback_toast.dart`
  - 新增 `AppFeedback` 统一入口
  - 支持 info / success / warning / error 四种语气
  - 底部浮层展示，控制为小面积、短时消失

- 调整的页面
  - `lib/pages/article/article_page.dart`
  - `lib/pages/feed_detail/feed_detail_page.dart`
  - `lib/pages/timeline/timeline_controller.dart`
  - `lib/pages/settings/settings_page.dart`
  - `lib/pages/main/main_page.dart`

### 18.3 注意事项

- 目前只收口“普通反馈提示”；底部动作菜单、页面级 loading 暂未统一改造。
- 如果后续仍觉得提示偏大，可以继续把 `_FeedbackToast` 再压缩到单行版本。

## 19. HTML 渲染性能重构（v1.5）

### 19.1 问题诊断

文章详情页使用 `SingleChildScrollView` + 单个 `flutter_html` `Html` widget 渲染整篇 HTML，导致：
- Widget 树一次性构建数百个节点，首帧卡顿
- 滚动时整棵 widget 树重绘，帧率降至 30-40fps
- 图片异步加载完成触发 Reflow，布局抖动严重
- `<iframe>` `<video>` 等 Platform View 在列表中引发崩溃

### 19.2 重构方案：六项策略

#### 策略 1：DOM 拆块 + SliverList 懒加载（核心）

- 新增 `lib/utils/html_chunk_parser.dart`
- 使用 `html` 包解析 DOM，按块级元素切分为 `List<HtmlChunk>`
- 支持的块类型：标题 `<h1>-<h6>`、段落 `<p>`、图片 `<img>`、代码块 `<pre>`、引用 `<blockquote>`、表格 `<table>`、列表 `<ul>/<ol>`、分割线 `<hr>`、iframe/视频占位
- 相邻纯文本段落自动合并，减少 widget 数量
- `article_page.dart` 改用 `CustomScrollView` + `SliverList.builder`，仅构建视窗内可见 chunk

#### 策略 2：预设图片尺寸防布局抖动

- `HtmlChunkParser._extractDimensions()` 从 `width`/`height` 属性 + CSS `style` 中提取图片宽高
- `HtmlChunkCard` 图片渲染使用 `AspectRatio` 占位，加载前显示静态颜色块，加载后不撑开父容器
- 无尺寸信息时默认 16:9

#### 策略 3：RepaintBoundary 隔离

- 每个 `HtmlChunkCard` 外层包裹 `RepaintBoundary`
- 独立绘制图层，滚动时静态 DOM 节点不参与重绘

#### 策略 4：iframe/Video 降级

- `<iframe>` `<video>` `<audio>` 解析为 `HtmlChunkType.iframeVideo`
- 渲染为 "静态封面 + 播放/浏览器图标" 占位卡片
- 点击用 `url_launcher` 唤起外部浏览器

#### 策略 5：Isolate 异步解析

- `HtmlChunkParser.parse()` — HTML > 500KB 自动切 `Isolate.run()` 后台解析
- 小文本主线程同步解析（< 50ms）
- 同时提供 `parseSync()` 供需要同步结果的场景

#### 策略 6：译文块独立解析

- 翻译完成后同步解析译文为 `translatedChunks`
- 切换原文/译文时 SliverList 无缝切换数据源
- Obx 响应式驱动，无需重建整个页面

### 19.3 渲染组件

新增 `lib/pages/article/widgets/html_chunk_card.dart`：
- 每种 `HtmlChunkType` 对应独立渲染方法
- 段落使用轻量 `flutter_html`（仅渲染内联标签 `<a>` `<strong>` `<em>` `<code>`）
- 代码块：水平滚动 + 等宽字体
- 表格：水平滚动 + `flutter_html` 表格样式
- 列表：手动构建 `Row` + 序号/圆点
- 图片：`AspectRatio` + `CachedNetworkImage`（含 `memCacheHeight` 限制）

### 19.4 架构变化

```
Before (jank):
  SingleChildScrollView
    Column
      Html(data: ALL_HTML)  ← 数百节点一次性构建

After (60fps):
  CustomScrollView
    SliverToBoxAdapter(title, metadata, buttons)
    SliverList.builder  [HtmlChunkCard × N]  ← 仅构建可见区域
      ↳ RepaintBoundary
        ↳ 标题 | 段落 | 图片(AspectRatio) | 代码 | ...
```

### 19.5 新增/修改文件清单

- `lib/utils/html_chunk_parser.dart` — 新建
- `lib/pages/article/widgets/html_chunk_card.dart` — 新建
- `lib/pages/article/article_page.dart` — 重写（SingleChildScrollView → CustomScrollView + SliverList）

## 20. 过滤页首屏复用全局缓存（2026-05-17）

### 20.1 需求

- 点击进入订阅源/分类过滤时间线时，尽量不要先显示加载转圈
- 优先复用全局本地文章库的已同步数据
- 后台继续刷新当前 scope 的准确结果

### 20.2 实现

- `lib/pages/feed_detail/feed_detail_page.dart`
  - 新增 `_buildInitialLocalSnapshot()`
  - 页面启动时先从 `LocalArticleDbService.readAllArticles()` 过滤出当前 scope 的未读文章
  - 若有内容，先直接展示，再后台刷新网络结果

### 20.3 注意事项

- 这个首屏只负责“已有数据的即时展示”，不会替代网络补抓。
- 如果本地库里尚未有该 scope 的文章，页面仍会走原本的加载流程。

## 21. 自动翻译（文章拉取时自动处理）

### 21.1 架构

每个订阅源可配置是否自动翻译其新文章，配置存储在 `GStorage.setting` 中，以 `feed_auto_translate_{feedId}` 为 key。

文章自动翻译采用**后台异步队列**模式，不阻塞 UI：

1. 新文章入库时（`LocalArticleDbService.upsertMany()`），通过 `AutoTranslationWorker.enqueueIfEnabled()` 检查并排队
2. 后台 Timer 以 500ms 间隔处理队列（每次处理 1 篇），调用 `TranslationService.translateArticle()`
3. 翻译失败时静默处理，不显示错误提示

### 21.2 核心代码

**FeedTranslationSettingsService** (`lib/services/feed_translation_settings_service.dart`)：
- `isAutoTranslateEnabled(feedId)` — 查询该 feed 是否启用自动翻译
- `setAutoTranslate(feedId, enabled)` — 设置启用/禁用
- `toggleAutoTranslate(feedId)` — 切换状态
- `clearAllSettings()` — 清空所有设置

**AutoTranslationWorker** (`lib/services/auto_translation_worker.dart`)：
- `enqueueIfEnabled(article)` — 单篇入队（如果启用）
- `enqueueIfEnabledMany(articles)` — 批量入队
- `getQueueSize()` — 获取待处理数量
- `cancelProcessing()` — 取消后台处理

### 21.3 集成点

1. **TimelineController** — `_applyUnreadSnapshot()` 入库后调用 `AutoTranslationWorker.enqueueIfEnabledMany(unreadData)`
2. **FeedDetailController** — 同样在 `_applyUnreadSnapshot()` 中调用入队
3. **FeedDetailPage** — appBar 新增 translate 图标按钮（仅当为单个 feed 过滤时显示），点击切换自动翻译状态

### 21.4 UI 交互

- **appBar 中的 translate 按钮**：
  - 位置：FeedDetailPage appBar actions（仅在 `filterFeedId != null` 时显示）
  - 外观：启用时填充色为主题色，禁用时为灰色
  - Tooltip：提示当前状态
  - 点击后立即更新 UI（依赖 Obx 响应式）

- **后台处理**：
  - 新文章入库 → 自动排队 → 后台异步翻译
  - 无 UI 反馈（默认成功），仅在切换开关时有明确反馈

### 21.5 存储与恢复

- 设置存储在 `GStorage.setting` 中，应用重启后自动恢复
- 每个 feed 的设置独立管理，互不影响
- 未来若需要统一导出/导入设置，可在 SettingsPage 中增加备份能力

### 21.6 已知限制与改进机会

1. **翻译内容范围**：当前仅翻译 title 和 content（未验证是否需要翻译 summary）
2. **队列持久化**：后台队列在内存中，应用关闭后丢弃；后续可考虑持久化队列
3. **翻译优先级**：无优先级控制，按入队顺序 FIFO 处理；未来可按 feedId 分优先级
4. **重试机制**：失败后不重试；可考虑添加指数退避重试策略

---

## 工程状态总结（截至 2026-05-20）

### 文件结构

```
lib/
├── common/constants/      API 常量
├── common/widgets/        通用组件（toast, loading, pill_tag）
├── http/                  Folo API 封装（feed_http.dart）, Dio 初始化
├── models/                ArticleModel（18 字段）, FeedModel（7 字段）
├── pages/
│   ├── article/           文章详情 + HtmlChunkCard + 画廊 + 视频播放器
│   ├── feed_detail/       订阅源筛选视图
│   ├── main/              主页（底部导航）
│   ├── settings/          设置页（Token, LLM 配置×3, Prompt 编辑）
│   ├── subscriptions/     订阅源树形列表
│   ├── timeline/          时间线 + 过滤审核页
│   └── widgets/           文章卡片, 搜索
├── router/                GetX 路由（5 条）
├── services/              12 个服务模块
└── utils/                 5 个工具模块
```

### 服务层清单

| 服务 | 文件 | 功能 |
|------|------|------|
| AccountService | `account_service.dart` | Folo Token / Client ID / Session ID 管理 |
| ArticleFilterService | `article_filter_service.dart` | DeepSeek JSON Output 判定保留/拒绝 |
| ArticleImageService | `article_image_service.dart` | 图片 URL 规范化 + Folo 代理 + 域名规则 |
| AutoFilterWorker | `auto_filter_worker.dart` | 16 并发过滤队列 + 进度计数 |
| AutoSummaryWorker | `auto_summary_worker.dart` | 16 并发摘要队列 |
| AutoTranslationWorker | `auto_translation_worker.dart` | 16 并发翻译队列 |
| ContentCacheService | `content_cache_service.dart` | 订阅源/文章本地缓存 (Hive, TTL 30min) |
| FeedTranslationSettingsService | `feed_translation_settings_service.dart` | 单源自动翻译开关 |
| LlmConfig | `llm_config.dart` | LLM 参数读写（模型/思考/T/max_tokens/并发） |
| LocalArticleDbService | `local_article_db_service.dart` | 文章本地持久化 (Hive, 上限 5000) |
| ReadSyncService | `read_sync_service.dart` | 已读状态云端同步 + 重试 |
| SummaryService | `summary_service.dart` | DeepSeek 摘要生成 |
| TranslationService | `translation_service.dart` | DeepSeek 翻译生成 |

### 核心数据流

```
启动 → loadFeedsThenArticles
  → 加载订阅源缓存（v2 key）
  → 拉取 feeds/social/inbox 未读文章（withContent:true 或 inbox detail）
  → upsertMany 写入本地 DB
  → enqueueMany → FilterWorker（16 并发）
  → enqueueMany → TranslationWorker（按源自动翻译开关）
  → enqueueMany → SummaryWorker（全部未读）
  → _loadFromLocalDatabase → _mergeLocalReadState → 时间线展示
```

### ArticleModel 字段（核心字段，早期记录为 18 个）

```
entryId, feedId, feedTitle, feedImage, title, url, content,
publishedAt, isRead, category, subscriptionCategory, author,
imageUrl, isRejectedByAi, filterReason, filterReviewed
```

## 22. 仓库完整性巡检与修复（2026-05-18）

### 22.1 巡检结论

1. 主工程（`lib/` + `test/`）可正常通过分析与测试。
2. 未发现主工程内 merge 冲突标记或语法破坏。
3. `dart analyze` 如果直接跑仓库根目录，会扫描 `reference/` 下第三方示例代码并产生大量无关错误，不代表主应用损坏。

### 22.2 本次已修复问题

1. **文章详情页翻译/摘要按钮非响应式刷新**
   - 问题：按钮和摘要展示依赖 `Rx`，但未包裹 `Obx`，状态变化后 UI 不会及时更新。
   - 修复：翻译按钮、译文切换入口、摘要按钮、摘要展示块全部改为 `Obx` 驱动。
   - 文件：`lib/pages/article/article_page.dart`

2. **译文切换入口缺失（回退后遗留）**
   - 问题：有译文时无法在详情页切换“译文/原文”。
   - 修复：补回“查看原文 / 查看译文”切换按钮。
   - 文件：`lib/pages/article/article_page.dart`

3. **订阅源自动翻译开关图标不会即时变更**
   - 问题：FeedDetailPage 使用 `Obx`，但读取的是非响应式存储方法，点击后图标不立即刷新。
   - 修复：在 `FeedDetailController` 中新增 `isAutoTranslateEnabled` 响应式状态与刷新方法，开关后立即更新并给出提示。
   - 文件：`lib/pages/feed_detail/feed_detail_page.dart`

4. **README 仍为 Flutter 模板文本**
   - 问题：缺少项目说明与启动指引。
   - 修复：更新为项目化 README，补齐功能、配置、目录与质量检查命令。
   - 文件：`README.md`

### 22.3 当前建议执行命令

```bash
dart analyze lib test
flutter test
```

## 23. 主页面双标题修复（2026-05-18）

### 23.1 问题

- MainPage 有全局 AppBar，TimelinePage/SettingsPage 也各自有 AppBar，导致在主页面内出现双层标题（如“时间线”重复）。

### 23.2 修复

1. `TimelinePage` 增加 `showAppBar` 参数，主页面内使用 `showAppBar: false`。
2. `SettingsPage` 增加 `showAppBar` 参数，主页面内使用 `showAppBar: false`（独立路由仍保留 AppBar）。
3. 保留“时间线标题双击回顶部”能力：
   - 把双击入口迁移到 MainPage 顶部标题；
   - 通过 `TimelineController` 暴露的 `scrollToTop` 回调触发列表滚动到顶部。

### 23.3 影响文件

- `lib/pages/main/main_page.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/settings/settings_page.dart`

## 24. 文章图片过大与无法全屏修复（2026-05-18）

### 24.1 问题

1. 文章正文图片恢复为 `flutter_html` 默认渲染后，尺寸约束丢失，出现超大图片。
2. 先前可点击图片进入全屏预览的交互被回退，正文图片无法点开。

### 24.2 修复

1. 在 `ArticlePage` 的 `Html` 渲染中恢复 `ImageExtension` 自定义图片渲染：
   - 使用 `_ArticleInlineImage` 控件统一渲染正文图片；
   - 增加最大高度约束（`maxHeight: 320`）和圆角容器，避免超大撑开布局。
2. 恢复图片点击能力：
   - 正文图片点击触发 `controller.openImagePreview(imageUrl)`；
   - 跳转到 `ImageGalleryPage` 全屏查看，支持缩放与多图切换。
3. 保留图片加载稳态策略：
   - 使用 `CachedNetworkImage` + 统一请求头（`ArticleImageService.httpHeaders`）；
   - 失败态支持点击重试（retry stamp）。

### 24.3 影响文件

- `lib/pages/article/article_page.dart`

## 25. 文章左右滑动切换（2026-05-18）

### 25.1 需求

- 在文章详情页支持左右滑动切换上一篇/下一篇
- 手指跟随时页面要同步横向移动
- 竖向滚动时避免误触发
- 临近切页时要有明确视觉提示

### 25.2 实现

1. 文章详情页改为“单篇 / 序列”双模式：
   - 单篇：保持原有 `ArticlePageView`
   - 序列：使用 `PageView.builder` 承载多个 `ArticlePageView`
2. 打开文章时从来源列表传入 `sequence + index`：
   - 时间线列表
   - 订阅源详情列表
   - 文章搜索结果
3. 通过 PageView 自带横向拖动提供手势跟随和临近切页的预览效果。
4. AppBar 标题追加页码（如 `文章详情 · 2/8`）作为额外视觉提示。

### 25.3 影响文件

- `lib/pages/article/article_page.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/feed_detail/feed_detail_page.dart`
- `lib/pages/main/main_page.dart`

## 26. 已读失败重试队列（2026-05-18）

### 26.1 问题

- 文章标记已读时如果云端同步失败，本地虽然立即变为已读，但云端没有更新，导致其他客户端仍可能显示未读。

### 26.2 处理策略

1. 本地仍然立即生效，不回滚状态。
2. 同步失败时写入本地待同步队列（`ReadSyncService`）。
3. 在时间线和订阅源详情页进入/刷新时自动重试同步。
4. 标记为未读时会清理对应的待同步已读记录，避免后续误补同步。

### 26.3 影响文件

- `lib/services/read_sync_service.dart`
- `lib/pages/article/article_page.dart`
- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/feed_detail/feed_detail_page.dart`

## 27. 翻译中状态提示增强（2026-05-18）

### 27.1 问题

- 自动翻译 / 手动翻译处于 pending 时，原先只显示很小的旋转图标，卡片和详情页都不够显眼。

### 27.2 修复

1. 文章卡片的 pending 状态改成显眼徽标：`翻译中 + spinner`。
2. 文章详情页在标题区下方增加持续可见的状态条，提示“翻译中，完成后会自动显示译文”。
3. 保留按钮内的 pending 指示，形成双重提示。

### 27.3 影响文件

- `lib/pages/widgets/article_card.dart`
- `lib/pages/article/article_page.dart`

## 28. 摘要长度调整（2026-05-18）

### 28.1 调整内容

- 文章摘要提示改为 **100~300 字之间**。
- 自动摘要与手动摘要共用同一服务提示词，因此两处都会同时生效。

### 28.2 影响文件

- `lib/services/summary_service.dart`

## 29. 双击时间线底栏回顶部（2026-05-18）

### 29.1 调整内容

- 取消顶部标题的双击回顶部入口。
- 将回顶部手势迁移到**底部导航栏的“时间线”按钮**。
- 当前页已是时间线时，连续双击底栏“时间线”按钮触发滚动到顶部。

### 29.2 影响文件

- `lib/pages/main/main_page.dart`

## 30. 已知待修问题（2026-05-19 全库审查）

以下问题已确认但暂不修复，供下一位接手者参考。

### #1 🟡 loadMore() 翻页只拉 feeds，不追加 social/inbox

**位置**：`lib/pages/timeline/timeline_controller.dart` → `loadMore()` 方法

**现象**：用户滚到底部触发翻页时，只调用 `FeedHttp.getEntries(view: 0, ...)` 追加 feeds 条目。初始加载 `loadData()` 会并行拉取 feeds(0) + social(1) + inbox，但翻页时 social 和 inbox 不会继续追加。

**建议修复**：`loadMore()` 中也并行拉取 social 和 inbox，或者改为统一使用 `collectEntries`/`collectAllInboxEntries`。

### #2 🟡 loadData() feeds 拉取失败时静默返回

**位置**：`lib/pages/timeline/timeline_controller.dart` → `loadData()` 方法

**现象**：当 feeds 拉取返回 `LoadError` 但本地 `allArticles` 非空时，代码直接 `return`，不设置任何错误状态。用户看到的是旧缓存数据，不知道发生了网络故障。

**建议修复**：在 `return` 前加一个 `AppFeedback.warning('刷新失败', '显示的是本地缓存')` 提示。

### #3 🟢 StorageKeys 缺少 deepseek_api_key 常量

**位置**：`lib/common/constants/constants.dart` 和 `lib/services/translation_service.dart` / `summary_service.dart`

**现象**：`TranslationService` 和 `SummaryService` 使用魔法字符串 `'deepseek_api_key'` 读写 `GStorage.setting`，但 `StorageKeys` 类未定义对应常量。其他 key 均有常量定义。

**建议修复**：在 `StorageKeys` 中加 `static const String deepseekApiKey = 'deepseek_api_key';`，并替换两处引用。

### #4 🟢 ArticleCard._isTranslated 死代码

**位置**：`lib/pages/widgets/article_card.dart` → `_ArticleCardState`

**现象**：`_isTranslated` 字段在 `initState` 初始化，但 `_ArticleCardContent` 已通过 `Obx` 直接订阅 `TranslationService.recordOf()` 来响应翻译状态变化。`_isTranslated` 和 `onTranslateSuccess` 回调实际未被使用。

**建议修复**：移除 `_isTranslated` 字段、`onTranslateSuccess` 回调和 `_onTranslateSuccess` 方法。当前代码不产生 bug，仅为死代码。

### #5 🟢 HtmlChunkParser._extractSrc 双重 URL 规范化

**位置**：`lib/utils/html_chunk_parser.dart:258` → `_extractSrc()` 和 `lib/pages/article/widgets/html_chunk_card.dart` → `normalizedImageUrl`

**现象**：`_extractSrc` 调用 `ArticleContentUtils.imageUrlFromAttributes`（内部已调用 `ArticleImageService.normalizeImageUrl`），之后 `HtmlChunk.normalizedImageUrl` getter 又调用了一次 `normalizeImageUrl`。两次规范化幂等，不产生错误，但冗余。

**建议修复**：`_extractSrc` 直接返回原始 URL 字符串，归一化工作统一交给 `normalizedImageUrl` getter。

## 31. HTML 渲染管线修复（2026-05-19）

经过对 13 篇真实 Folo 文章的管线实测，发现并修复了 3 个渲染 BUG。

### 31.1 BUG-1 🔴：标题内图片/媒体被吞掉

**根因**：`_processElement` 对 `<h1>-<h6>` 直接调 `_stripInnerHtml` 剥离所有 HTML 标签。
**影响**：实测中 6/13 篇文章丢失图片（新智元 86 张仅剩 33 张，少数派 7 张剩 5 张）。
**修复**：
- 新增 `_hasMediaDescendant()` — 递归检测是否有媒体子节点
- 新增 `_headingTextOnly()` — 从含媒体的标题中仅提取文本
- 新增 `_emitMediaChildren()` — 对标题仅发媒体块（文本已在标题中）
- 标题有媒体 → 先发标题文本块，再递归发媒体块

### 31.2 BUG-2 🟡：空标题产生多余空白间距

**根因**：`<h3><span><br></span></h3>`（微信公众号做分隔线）剥离后为空字符串，仍渲染为标题块。
**影响**：新智元文章出现 14 处无意义大间距。
**修复**：标题文本 trim 后为空 → `return` 跳过不发块。

### 31.3 BUG-3 🟡：图片 CSS 百分比宽度误解析为 px

**根因**：`_extractDimensions` 正则 `width:\s*(\d+)\s*(px|em|rem)?` 不区分 `%` 单位，`100%` → 100px。
**影响**：微信来源文章图片 `style="width:100%"` 被当作 100px 处理，但实际无高度，仍无法确定比例。
**修复**：正则增加 `%|vw|vh` 单位匹配；百分比/视口单位 → 宽/高保持 `null` 交给渲染层 fallback（`AspectRatio`）。

### 31.4 附带修复：未知元素不再丢弃媒体

**根因**：`<a><img></a>` 等内联容器未被识别，`_processElement` 末尾只提取文本导致 `<img>` 丢失。
**修复**：未知元素改为递归子节点，而非仅提取文本。

### 31.5 影响文件

- `lib/utils/html_chunk_parser.dart` — 核心修复（+5 新方法，~80 行改动）

### 31.6 图片渲染完善（补充修复）

在 §31.1-31.4 的 HTML 解析修复之后，进一步排查了图片加载和微博格式问题：

1. **Blockquote/Table/RawHtml 内图片不使用 ImageExtension**
   - 根因：`HtmlChunkCard._buildBlockquote` / `_buildTable` / `_buildRawHtml` 使用裸 `Html()` 不加 `ImageExtension`，导致图片不走 `CachedNetworkImage` + 统一请求头。
   - 修复：提取共享 `_imageExtension()` 方法，应用到所有 `Html()` 调用点。
   - 影响文件：`lib/pages/article/widgets/html_chunk_card.dart`

2. **无 src 的空 img 标签产生空图片块**
   - 根因：微信文章标题区的 `<img style="width:100%" src="">`（CSS background 占位）被解析为 IMG 块，src 为空。
   - 修复：`_processElement` 中 `img` 处理分支增加 `if (src.isEmpty) return;`
   - 影响文件：`lib/utils/html_chunk_parser.dart`

3. **微信图片代理 `img2.jintiankansha.me` 已失效**
   - 实测：所有请求返回 403/400，原始微信 CDN 图片 `X-ErrNo: -106`（已过期）。
   - 结论：非代码问题，属数据源/RSS 源质量问题。已通过 `ImageExtension` 的错误占位符提供降级展示。
   - `ArticleImageService.normalizeImageUrl` 强制 HTTP→HTTPS 升级可能影响部分代理（已记录到 §30 #5，暂不修复）。

## 32. 视频播放支持（2026-05-19）

### 32.1 问题

Social 条目（Twitter）中的 `<video>` 标签无法播放，显示静态占位符。两类格式：
- 直接 `src`：`<video src="..." poster="..." width="..." height="...">`
- `<source>` 子元素：`<video poster="..."><source src="..."></video>`

### 32.2 Folo 官方方案

Folo 桌面端用 HTML5 `<video>` 标签直接播放 mp4，移动端用 `expo-video` 包。不依赖第三方视频平台 SDK。

### 32.3 实施

1. **Parser** (`html_chunk_parser.dart`)
   - `<video>` 含 `<source>` 子元素时从中提取 `src`
   - 提取 `poster` 属性存入 `HtmlChunk.posterSrc` 字段
   - `HtmlChunk` 新增 `posterSrc` 字段

2. **Renderer** (`html_chunk_card.dart`)
   - `_buildMediaPlaceholder` 改为 `Stack` 布局：
     - 底层：`CachedNetworkImage` 加载 poster 缩略图（经过 Folo 图片代理）
     - 中层：半透明黑色遮罩
     - 顶层：圆形播放按钮（`Icons.play_arrow_rounded`）
   - 点击 → `url_launcher` 打开 mp4 URL（系统播放器处理）

### 32.4 影响文件

- `lib/utils/html_chunk_parser.dart` — `HtmlChunk` + `posterSrc`，`_processElement` 视频分支
- `lib/pages/article/widgets/html_chunk_card.dart` — `_buildMediaPlaceholder` 重写

### 32.5 预实验数据

| 样本 | src | poster | dims |
|------|-----|--------|------|
| `social_video_12` (direct src) | ✅ | ✅ | 1500×844 |
| `social_video_14` (direct src) | ✅ | ✅ | 1920×1080 |
| `social_video_18` (`<source>`) | ✅ | ❌ | null×null |

### 32.6 验证结果

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| 新智元 86 图文章 | 33 张图片 | 80 张图片 (+142%) |
| newsletter 17 图 | 13 张图片 | 16 张图片 (+23%) |
| 新智元空标题 | 14 处间隙 | 0 处 |
| 解析性能 | ~15ms | ~15ms（持平） |
| dart analyze | 0 issues | 0 issues |

## 33. AI 文章过滤系统（2026-05-20）

### 33.1 功能概述

基于 autofolo 的 `prompts.yaml` 过滤规则，用 DeepSeek JSON Output 对未读文章逐篇判定保留/拒绝。拒绝的文章进入审核页，用户可捞回或确认拒绝（自动标已读）。时间线卡片的拒文有橙色描边标记。

### 33.2 影响文件

- `lib/models/article.dart` — 新增 `isRejectedByAi`、`filterReason`、`filterReviewed`
- `lib/services/article_filter_service.dart` — **新建**。调 DeepSeek 判定，内置裁简版 autofolo prompt
- `lib/services/auto_filter_worker.dart` — **新建**。并行过滤队列，`queued/processing/done` 计数
- `lib/services/llm_config.dart` — 新增 filter 配置（模型 v4-pro / T 0.1 / 并发 16）
- `lib/pages/timeline/filter_review_page.dart` — **新建**。左右滑审核页，实时追加新结果
- `lib/pages/timeline/timeline_page.dart` — 顶栏常驻过滤入口横幅
- `lib/pages/settings/settings_page.dart` — 过滤 Prompt 编辑卡 + LLM 并发数配置
- `lib/pages/widgets/article_card.dart` — AI 拒文橙色边框
- `lib/pages/article/article_page.dart` — 标已读时清除过滤标记
- `lib/router/app_pages.dart` — 新增 `/filter-review` 路由

### 33.3 数据流

```
拉取未读 → enqueueMany → 16 并发 DeepSeek 判定
  → 拒文写入 DB (isRejectedByAi=true)
  → 审核页 Obx 监听 doneCount 自动追加
  → 用户右滑保留(清除标记) / 左滑确认拒绝(标已读)
  → filterReviewed 防重判
```

### 33.4 关键设计决策

- `filterReviewed` 标记解决"捞回后再刷新又被拒绝"的问题
- `upsertMany` 的 OR 合并逻辑与 `unReject` 直接写 DB 的冲突：unReject 绕过合并逻辑直接写 Hive
- 审核页不支持下拉刷新，只通过 `doneCount` 监听实时追加

## 34. LLM 并发数配置（2026-05-20）

- `LlmConfig` 新增 `concurrency` 字段，翻译/摘要/过滤各自独立
- 三个 Worker 的并发数从硬编码改为 `LlmConfig.load().concurrency`
- 设置页 LLM 卡新增「并发数」文本输入（1-1024）

## 35. 图片画廊修复（2026-05-20）

- **双击放大**：GestureDetector 从 InteractiveViewer 外层移到里层，避免手势冲突；缩放公式修正为 translate→scale→translate
- **捏合缩放**：InteractiveViewer 移到最外层，不再被 GestureDetector 阻止
- **图片全灰**：移除 AnimatedContainer + Opacity 包裹，直接使用 Scaffold
- **右下角"点按查看"**：删除
- **图片预加载**：文章打开时隐藏 1px Stack 同时发出所有图片请求
- **画廊分母错误**：审核页跳转文章时 sequence 改送审核列表自身，不再查全库

## 36. Inbox 空内容修复（2026-05-20）

- 根因：`chunks` 是 `late final List` 而非 `RxList`，`_fetchInboxContent` 更新后 Obx 不重建
- 修复：`chunks` 改为 `RxList<HtmlChunk>`，`_fetchInboxContent` → `_initContent` → `chunks.value = ...`
- Inbox 详情 API：`GET /entries/inbox?id=<entryId>` 返回完整 HTML 正文

## 37. 其他杂项修复（2026-05-20）

- **订阅源图标**：`LocalArticleDbService.upsertMany`/`setReadState` 补遗漏的 `feedImage` 字段
- **缓存 key 升级**：`cache.subscriptions.v1` → `v2` 强制刷新带 `image` 字段的订阅源数据
- **翻译超时**：60s → 300s；`rethrow` 改为 `return ErrorRecord`
- **FeedDetail 灰边框**：非拒文去掉 Card 描边
- **过滤横幅常驻**：移除 `if (count > 0)` 条件
- **FAB 半透明缩小**：`FloatingActionButton.small` + `Opacity(0.85)`
- **视频内联播放**：`video_player` + `InlineVideoPlayer` 三态组件
- **Folo 图片代理**：`ArticleImageService.toProxiedUrl()` 对微博/Pixiv 等 CDN 走 `img.folo.is`

## 38. 已读状态双向同步（2026-05-20）

- API 明确返回某篇文章为未读 → 清除本地 `readStatus` 旧标记，恢复未读
- 解决 inbox 文章被误标已读后永久无法恢复的问题
- 保护：`localOverride=false` 的用户手动标记不被覆盖
- `collectEntries` 移除 `maxPages` 硬上限，改为页不满/页空自然终止

## 39. 订阅源未读计数（2026-05-20）

- 三层未读计数：View / 分类 / 订阅源，各自求和
- inbox `feedId` 取错 JSON 路径→未读数为 0 的 Bug 修复：`item['feeds']['id'] ?? entry['inboxHandle']`
- `collectAllInboxEntries` limit 30 → 100

## 40. 图片修复补充（2026-05-20）

- `i.qbitai.com` 图片需 `Referer: https://www.qbitai.com/` → 加代理规则走 `img.folo.is`
- 图片画廊双击缩放加 `Matrix4Tween` + `AnimationController` (300ms easeOut)
- `normalizedContent` / `imageUrls` 从 `late final` 改为普通字段，支持 inbox 异步补内容

## 41. FeedDetail 对齐（2026-05-20）

- AppBar 标题显示未读计数（如 `量子位 (5)`）
- `showFeedTitle` 始终为 true，去底部空白

## 42. 性能优化 — 卡顿修复（2026-05-20）

- **静态 Dio 实例**：翻译/摘要/过滤三个服务各用 `static final _dio`，不再每条请求 `new Dio(BaseOptions(...))`
- **normalizeHtml 缓存**：`ArticleContentUtils.normalizeHtmlForEntry(entryId, html)` 用 LinkedHashMap 做 200 条 LRU 缓存，翻译和摘要各调一次但共享结果，同篇长文章不再 DOM 解析两遍
- **审核页增量推送**：过滤 Worker 完成一篇后通过 `onRejected` 回调直接推送单篇到审核列表（O(1)），替代 `ever(doneCount)` 每完成一篇扫全库 5000 篇（O(5000)）
- `onRejected` 回调仅在审核页可见时注册（`initState`/`deactivate`/`dispose`），后台不触发

## 43. ArticleStateNotifier 全局状态通知（2026-05-20）

- **新建** `lib/services/article_state_notifier.dart` — RxInt version 计数器
- 所有文章状态变更点统一调 `ArticleStateNotifier.tick()`
- 消费者页面用 `ever(version, ...)` 或 `Obx(() => version.value)` 感知刷新
- 解决：订阅源三层计数 stale、FeedDetail 列表 stale、时间线过滤横幅 stale
- 扩展方式：新页面只需加 listener，不需要修改 tick 点
- **计划升级 D 方案**：`tick(entryId, changeType)` 带变更类型，消费者省掉一次 `box.get`

## 44. FeedDetail 已读筛选 + tick(entryId) 增量（2026-05-21）

- `ArticleStateNotifier.tick(entryId)` 替代无参 `tick()`，消费者改为增量更新单篇
- FeedDetail `_refreshFromLocal`：`box.get(entryId)` 读单篇 → 更新/移除列表（O(1) 替代 O(5000)）
- 订阅源 `refreshUnreadCounts`：增量 ±1 计数；首屏仍全量
- FeedDetail 新增 `readFilter`：仅未读/全部/仅已读三档，AppBar 弹出菜单切换
- `allArticles` 单独存全量（含已读），`articles` 按 filter 派生

## 45. UI 全面美化（2026-05-21，手动修订）

用户对所有页面进行了大量视觉打磨，涉及 13 个文件、+2456/-1148 行。

### 配色体系重构

- 移除 `DynamicColorBuilder`，`main.dart` 全面手写 `ColorScheme`（亮/暗各一套）
- 用 `dart:ui` 的 `PlatformDispatcher` 监听系统亮暗切换，手动管理 `themeMode`
- 状态栏设为全局透明，沉浸式体验
- 亮色方案：冷白基底 `#F8F8F9` + 多层次 `surfaceContainer` 灰阶
- 暗色方案：深灰 `#121212` 基底 + 多层次暗灰
- accent 使用 `#FF5C00`（品牌鲜橙），亮暗两套共用同一主色

### 时间线过滤入口重设计

- `_buildFilterBar` 从薄横条改为大圆角卡片：双层背景 + 圆形图标容器 + 双层文字（"AI 智能过滤" / "拦截了 N 篇… 去查看"）
- 使用自定义骨架屏 `_LocalTimelineSkeleton` 替代转菊花
- empty view 重排布局和文案

### 文章详情页重构

- `_MetadataSection`（来源 Chip）：图标 + 文字 + 箭头，圆角灰底可点击
- 标题区：InkWell 带圆角反馈，点击打开原文（无额外图标）
- `_ToolbarRow`：翻译/摘要芯片按钮紧凑排列，状态驱动（翻译中…/已译/翻译）
- `_Chip` 组件：激活态 `primary(0.12)` + 主色文字，非激活态灰底
- `_SummaryCard`：亮色用 `secondaryContainer(0.10)`，暗色用 `(0.15)`，极淡底色
- 空正文状态：`article_outlined` 图标 + "在浏览器中查看原文" 链接

### 文章卡片重设计

- 搜索入口 `ArticleSearchDelegate`→`_SearchBar` 重构为独立搜索栏
- `ArticleCard` 时间标签 `_buildTimeLabel` 重构
- 翻译/摘要图标布局调整
- AI 拒文标签（filterReason chip）样式统一

### 图片组件打磨

- `html_chunk_card.dart` 大量重构：inline image / video poster / 布局
- `image_gallery_page.dart` 重写：滑动关闭、缩放交互

### 订阅源页重构

- `_CategorySection` / `_ViewSection` / `_FeedAvatar` 全面重排
- 展开/折叠动画流畅度优化
- 三层缩进视觉层级明确

### FeedDetail 页重构

- `_FeedDetailPage` → `FeedDetailController` 分离
- 加载骨架、空状态、错误状态统一
- 文章列表卡片与主时间线视觉完全对齐

### 过滤审核页打磨

- `FilterReviewPage` 拒绝原因、按钮、进度条重构
- `Dismissible` 阈值调回 0.5（防误触）

### 反馈系统重构

- `feedback_toast.dart` 完全重写：Material 3 风格 SnackBar 替代旧 Toast

## 46. 主页时间线重大交互与逻辑重构（2026-05-22）

- **生命周期解耦**：将 `TimelineController` 的注入时机从 `TimelinePage` 提前至 `MainPage.initState`。彻底修复了由于 `AppBar` 过早构建导致“启动时未读胶囊被隐藏，切 Tab 才能出现”的严重错位 Bug。
- **UI 重构（胶囊徽章）**：
  - 将未读/全部状态胶囊从右侧移动至 `AppBar` 的 `leading` (左上角)，实现了左控制、中标题、右搜索的完美对称美学。
  - 抛弃了 `PopupMenuButton` 粗糙的原生包裹，改用定制的 `Material` + `InkWell(borderRadius: 14)`，使点击产生的水波纹被完美“锁”在胶囊的圆角边缘内。
- **响应式数字修复**：在 `MainPage` 的顶栏  中加入了强制的 `allArticles.length` 依赖追踪，修复了底层 `allArticles.value` 更新但上方未读数字却不跳动的 GetX 响应式盲区。
- **顶部空档优化**：
  - 在 `timeline_page.dart` 中，当拦截数量为 0 时，过滤提示条彻底返回 `SizedBox.shrink()` 而非带 Padding 的空框。
  - 将 `ListView` 顶部的物理位移交由 `RefreshIndicator(edgeOffset: ...)` 处理，彻底消除了时间线滚动到顶部时巨大的死板空档。
- **网络全量同步容错（严格坚持两段式状态）**：
  - 恪守“绝对不显示不准确近似数据”的设计准则，在 `TimelineController.loadData` 中保留了 `collectEntries` 的全量拉取机制，保证 UI 变化只分为“启动读本地旧缓存”与“后台全量同步完并最终更新”两个确定状态。
  - 增加了严格的 `hasError` 检测。当面临成百上千条未读文章导致网络极大概率超时的情况下，不会再假死无反应，而是会静默弹出“同步未完成，部分拉取失败”的提示，增强了应用的健壮性。



## 47. 刷新圈反悔手势阻断优化（2026-05-22）

- **问题背景**：在带有半透明 AppBar 的设计中，当下拉刷新圈（未松手）再反悔向上推时，底层的 `ClampingScrollPhysics` 默认允许向上的滚动偏移量作用于列表，导致文章列表跟随手指滑动，钻入 AppBar 背后产生不自然的视觉穿透。
- **高阶边界拦截**：为了完美复刻 PiliPlus 中“刷新圈在屏幕上时列表完全冻结”的效果，引入了 `RefreshAwareScrollPhysics`。
  - 该方案彻底摒弃了在 `applyPhysicsToUserOffset` 阶段拦截（因其会导致 Flutter 底层计算出符号相反的 `overscroll` 进而让刷新圈死锁）。
  - 改为在最终边界判定 `applyBoundaryConditions` 阶段实施降维拦截：在 `dragOffset > 0` 的前提下，当发现用户尝试正向滚动（`value > pixels` 且位于顶部边界）时，强行将这部分合法的滚动量判决为越界（overscroll）。
- **联动效果**：
  - 判定越界使得列表本身的 `pixels` 被完美冻结在 `0`，纹丝不动。
  - 扣除下来的正向越界位移（`overscroll`）顺势传递给 `RefreshIndicator`，完美驱动了圆圈的顺滑回缩。
- **视觉配合**：
  - 同时移除了默认的边缘发光效果（`NoOverscrollIndicatorBehavior`），使得界面的操作反馈干净利落，达到指哪打哪的极佳手感。

## 48. 审核页重塑 — 实时状态药片（2026-05-23）

审核页（FilterReviewPage）从"判定中" + "全部确认"的旧设计完全重构：

- **AppBar 对齐主时间线**：居中标题"垃圾拦截"，0.5px 分割线，移除毛玻璃、判定徽标、"全部确认"按钮
- **状态药片行**（AppBar 与列表之间）：
  - `✋ N 篇待处理`：始终显示，0 篇时灰色，>0 篇时主色高亮
  - `🤖 N 篇判定中`：仅 LLM Worker 活跃时显示，灰色底 + 微型 spinner
- **实时性**：`humanCount` 由 `_articles.length` + `Obx` 驱动；`llmCount` 由 `AutoFilterWorker.queuedCount/processingCount`（RxInt）驱动；每篇卡片滑动后当场跳数
- **空状态终结感**：全部处理完时图标变绿对勾 + "处理完毕"
- **去除重复**：卡片自带拒文标签（§45），审核页不再额外显示判定原因
- **架构**：`_StatusPills` 和 `_LlmPill` 提升为文件级私有组件

### Vivo / OriginOS 桌面角标适配（待完成）

Vivo 提供私有 ContentProvider API（`content://com.vivo.abe.provider.launcher.notification.num`）可直写角标。`MainActivity.kt` 已实现 `tryVivoBadge` + 通知兜底，但当前不生效。排查方向：查看 logcat 返回码、确认系统桌面角标开关、验证权限未被静默拦截。详见 vivo 开发者文档。

## 49. 最终打磨与 v1.0.0-beta1 发布（2026-05-23）

### 导航栏玻璃质感调优

- 底栏背景从 `surface(0.8)` 降至 `surface(0.40)`，瀑布流内容更多穿透
- 选中态指示器从 `primary(0.15)` 提至 `primary(0.80)`，橙色标识更鲜明
- 顶栏 + 底栏均使用 `BackdropFilter(blur: 16)` 实现 iOS 风格毛玻璃

### 图片预加载性能修复

- 预加载隐藏 Stack 的 `CachedNetworkImage` 加上 `memCacheWidth: 150` + `maxWidthDiskCache: 300`
- 原因：不加约束时每张图片以原始分辨率解码（>2000px），20 张同时解码打爆主线程
- 效果：预加载仅解码 150px 缩略图，CPU 开销降 ~90%

### 文章详情页微调

- 标题下方移除"查看网页原文"文字 + 图标，标题本身已可点击跳转
- `_SummaryCard` 日间模式透明度从 `0.25` 降至 `0.10`，极淡底色改善可读性
- FAB `AnimatedScale` 回退（效果太细微无法感知）
- 审核页 `Dismissible` 阈值调整：`0.3` → `0.5`（防误触）

### 时间线过滤入口

- `_buildFilterBar` 移除 `if (count <= 0) return` 条件，入口始终可见
- 审核页"AI 判定"标签移除（卡片自带原因显示，防止重复）

### 分批提交与 v1.0.0-beta1

10 个 commit 按模块拆分：
1. `ColorScheme` 手写体系 + 移除 `DynamicColorBuilder`
2. `_FadeIndexedStack` 页面切换 + 底栏毛玻璃
3. 过滤入口卡片重设计 + 骨架屏
4. 审核页进度条 + 拒绝标签 + Dismissible
5. 文章页 `_ToolbarRow` + `_Chip` + 摘要卡 + 预加载 fix
6. 内联图片淡入 + 图片画廊手势
7. 文章卡片布局 + 搜索栏
8. FeedDetail 控制器分离 + 骨架加载
9. 订阅源三层缩进 + 动画打磨
10. 设置页副标题 + FeedbackToast 重写

Tag: `v1.0.0-beta1` — 功能完备（AI 过滤 + 翻译 + 摘要），橙色主题，全 UI 打磨。

## 50. 仓库管理规范（2026-05-23）

以下规则记录到文档中以便未来 AGENT 和协作者严格遵循。

### 一、提交粒度

- 一个 commit = 一个可独立回退的逻辑改动
- 禁止混合 "修 bug + 顺带改 UI"——示例反例：`f9b06ad`（物理引擎+图片画廊+导航三者合一）
- 不跨模块提交：`Refactor: ArticlePage` 不夹带 `FilterReviewPage` 的修改

### 二、Tag 管理

- **永不 force-update**：每次发版新建 tag，如 `v1.0.0-beta2`、`v1.0.0-rc1`
- beta 阶段可密集发（按天/按功能），RC 之后减速
- tag 注释写完整：日期 + 核心改动 + 对应的文档 § 编号
- 删除旧 tag 只在修复错打时使用，不使用 `-f` 覆盖

### 三、文档同步

- commit message 引用对应 § 编号（格式：`Refactor: xxx (§12)` 或 `Fix: xxx, see §8`）
- 每个功能完成 → 立即更新文档，不打完 tag 才补文档
- tag 打在文档和代码一起提交的 commit 上
- § 编号应连续递增，不跳号、不重号

### 四、全局状态变更通知

- 任何涉及 `ArticleStateNotifier.tick()` 的改动，必须验证 6 个消费者页面全部正常：
  - `timeline_page` · `timeline_controller` · `filter_review_page` · `article_page` · `feed_detail_page` · `subscriptions_controller`
- 新增消费者时在本文档登记

### 五、Flutter 代码规范

- 结构性重构（>30 行）使用 `write_file` 一次性写入，避免 `edit_file` 重复修改导致括号混乱
- 嵌套超过 3 层的 widget 提取为独立 StatelessWidget 或辅助方法
- 修改全局 `ColorScheme` 后抽查 3 个以上页面

### 六、当前已知问题（非待修）

| 项 | 说明 |
|----|------|
| `f9b06ad` 提交粒度过大 | 混了物理引擎+图片画廊+导航，历史记录，不阻塞 |
| 硬编码色值 | `filter_review_page` 绿色滑动、`timeline_page` 琥珀过滤等为**语义色**，刻意设计，不为违规 |
| tag 被 force-update | `v1.0.0-beta1` 覆盖 3 次，从下个版本严格递增 |

## 51. 审核界面直接预览 AI 摘要（2026-05-23）

### 51.1 需求背景
用户希望在垃圾拦截（审核界面）中能够直接看到文章的摘要，而不需要点击进入详情页，以提高审核效率。同时要求正式时间线保持清爽，不显示摘要，并且要求 UI 具有设计美感，不破坏原有的极简卡片布局。

### 51.2 实现细节
- **`lib/pages/widgets/article_card.dart`**：
  - 新增 `showSummary` 控制参数（默认 `false`）。
  - 在卡片标题和底部元数据之间，新增摘要展示区块 `_buildSummaryBlock`。
  - 使用 `Obx` 响应式读取 `SummaryService.recordOf(entryId)`。
  - **优雅降级**：如果 AI 摘要已生成则显示内容；如果未生成则展示占位符 “AI 尚未生成摘要...”。
  - **视觉设计**：摘要前增加极小的引号图标（`Icons.format_quote_rounded`），使用浅色、半透明字体（`colorScheme.onSurfaceVariant.withValues(alpha: 0.8)`）和两行限制（`maxLines: 2`），形成类似“引述块”的设计，不喧宾夺主。
- **`lib/pages/timeline/filter_review_page.dart`**：
  - 在渲染被拦截的卡片时，显式传入 `showSummary: true` 开启摘要预览。
- **`lib/pages/timeline/timeline_page.dart`**：
  - 保持默认不传入该参数，维持正式时间线不显示摘要。

## 52. 通知角标 + 退后台（2026-05-23）

- 新增「通知与角标」设置区块：下拉选择桌面角标规则（显示数量 / 仅红点 / 关闭）
- 设置页重新布局：角标从翻译区块中独立出来
- 按安卓返回键退到后台（`PopScope` + `MainActivity.kt` 原生处理）
- 自写 `AppBadger`（MethodChannel `com.autofolo/badge`），完全移除 `flutter_app_badger` 依赖
- 自写 `MoveToBackground`（MethodChannel `com.autofolo/move_to_background`），完全移除 `move_to_background` 依赖
- 外来依赖归零，所有原生交互通过自写 MethodChannel + `MainActivity.kt` 控制

## 53. 正文加载 + 数据持久化（2026-05-23）

- **Inbox 文章首次打开**：`_fetchInboxContent()` 拉取后自动 `upsertOne()` 写入本地 DB，再次打开直接读库，不再重复拉取
- **Readability 抓取**：`fetchReadabilityContent()` 成功后同样持久化
- **加载中状态**：新增 `isFetchingContent` observable，空正文时显示旋转菊花 + "正在加载正文…"，替代原来的"暂无正文内容"闪烁

## 54. 译文/摘要内容传递修正（2026-05-23）

- `TranslationService.translateArticle()` 和 `SummaryService.summarizeArticle()` 新增 `overrideContent` 参数
- 文章页触发翻译/摘要时传入已标准化的 `normalizedContent`，确保 Readability 抓取后的长文被正确用于翻译和摘要

## 55. UI 细节打磨（2026-05-23）

- 审核页 AppBar 标题字体对齐主时间线（`FontWeight.bold, fontSize: 17`）
- 卡片内 AI 摘要预览 `maxLines` 从 2 扩展到 4
- 文章页 `CustomScrollView` 外包 `SelectionArea`，正文可选中复制
- 文章详情页 API 错误提示改用服务端返回的 `errorMessage`
- 主页面玻璃参数微调（模糊 20、透明度 0.50）

## 56. 大文章分块翻译 + 邮件表格扁平化（2026-05-23）

### 56.1 正文规整优化
- `ArticleContentUtils.normalizeHtml` 新增 `_flattenLayoutTables`：扁平化邮件 Newsletter 的 `<table>/<tr>/<td>` 布局壳，保留 `<th>` 数据表
- 效果：98KB 邮件 → ~67KB 纯内容，削减 ~30% 的无意义标签

### 56.2 分块翻译
- 阈值：归一化后正文 > 35KB 触发分块
- 切分：按 `<p>/<h1>/<li>/<blockquote>` 段落边界，每块 ≤12KB
- 并行：`Future.wait` 同时发出所有块的 LLM 请求，不等排列
- 拼接：第 1 块负责标题，所有块拼接 `translated_html`
- 历史实现曾保留已翻译部分；用户后来明确要求“任一块失败则整篇丢弃并重试”，因此当前实现会整篇重试最多 5 次，不写入半截译文。
- 2026-05-31 补充：分块翻译最终失败时，错误记录会带上最后一次失败的块号和具体原因，供任务中心失败明细直接展示。

### 56.3 pending 瞬态不落盘
- `pending` 只在内存 `_records` map 中标记，不再通过 `GStorage.translations.put()` / `GStorage.summaries.put()` 写入磁盘
- 终态（`done` / `error`）正常落盘；`pending` 重启后自然消失，无需清理逻辑

### 56.4 未捕获异常兜底
- 翻译流程增加通用 `catch (e)` 处理器，防止非 Dio/Format/StateError 异常导致静默卡死

## 57. v1.0.0-beta2 发布（2026-05-23）

- 移除 `flutter_app_badger`、`move_to_background` 外部依赖，全部改为自写 MethodChannel
- Vivo/OriginOS 角标：ContentProvider 直写实现（待系统级验证）
- 自写 `AppBadger`、`MoveToBackground` 实用类
- 设置页新增「通知与角标」区块
- 翻译管线全链路稳定：启动自愈 → 表格扁平化 → 大文章分块并行 → 异常全面捕获

Tag: `v1.0.0-beta2`

## 58. 取消文章正文懒加载与重置列表增量刷新 (2026-05-24)

### 58.1 文章阅读进度条精准度优先 (取消懒加载)
- **背景**：原先使用 `SliverList.builder` 进行 HTML 节点的懒加载，以优化极长文章（多图、大 DOM）的首帧渲染和内存占用。但这导致底层的 `maxScrollExtent` 随着滚动不断动态变化，使得顶部“阅读进度条”出现跳动、不准或在未完全展开时无法达到 1.0 的问题。
- **决策**：经测试确认当前设备性能可以承受全量渲染后，去除了懒加载机制，将 `SliverList` 替换为 `SliverToBoxAdapter` + `Column`。
- **收益**：所有的 HTML 节点会在第一时间全部挂载，物理像素高度在首帧即可精确计算，彻底修复了阅读进度条的准确性问题。

### 58.2 FeedDetail 已读 O(1) 增量优化回退
- **背景**：曾为防止“点击已读”时出现卡顿，在 `feed_detail_page.dart` 中引入了 O(1) 的增量更新逻辑（仅对 `articles` 列表中对应索引作 `remove` 或局部替换），以规避触发 `_applyFilter()` 带来的 O(N) 级别全列表重构。
- **重新评估**：其实导致“点击已读卡顿”的真正元凶是**UI的整个 Widget Tree 重构**，而不是 Dart 层面的一层循环数组处理。由于我们在此前已经引入了 `ArticleStateNotifier` 以及局部 `Obx` 来控制重绘，UI 卡顿的根因已被解决。
- **决策**：回退了 O(1) 优化，恢复使用 `allArticles.refresh()` + 全量 `_applyFilter()` 的设计。这使得业务逻辑的代码更简洁、直观，并且在 Dart 处理内存数组极快的加持下，没有观察到性能衰退。

### 58.3 正文 DOM 懒加载设置开关
- **需求**：由于“一次性全量渲染”可能会在低端设备上引发卡顿或崩溃，我们需要把控制权交给用户。
- **实现**：在设置页 (`SettingsPage`) 新增“渲染与性能”区块，加入了“正文 DOM 懒加载”开关（默认关闭）。旁边的 Info 按钮会弹出对话框，向高级用户明确解释“内存开销”与“阅读进度条精确度”之间的技术博弈。状态保存在 `GStorage.setting` 中，由 `article_page.dart` 实时读取并动态切换 `SliverList` 或 `SliverToBoxAdapter` 机制。

## 59. 遗留问题与已知缺陷 (2026-05-24)

### 59.1 特定长文/复杂排版文章卡顿问题
- **现象**：文章《Tencent Open-Sources TencentDB Agent Memory: A 4-Tier Local Memory Pipeline for AI Agents》在渲染和滚动时存在轻微卡顿。
- **状态**：该问题在 `main` 和 `fix-video-summary-ui` 分支均存在，属于历史遗留或 `flutter_html` 针对特定 DOM 结构（可能是超长的 `<pre>`、深层嵌套或者特定的 Markdown 转换残留）的解析性能瓶颈。
- **建议**：后续需要对这类出现卡顿的特殊文章进行 Profile，分析是在布局计算 (Layout) 还是 `HtmlChunkParser` 解析时耗时过长。可能需要对 `flutter_html` 的特定组件进行缓存优化，或者针对超大代码块增加局部懒加载机制。

## 60. 深色模式 HTML 字体对比度动态调整 (2026-05-25)

### 60.1 问题背景
深色模式下，部分带有内联样式（如 `<span style="color: #333333;">`）的文章文本会因为与深色背景对比度过低而难以阅读。

### 60.2 核心实现
- **`lib/utils/color_parser.dart`**：实现了 CSS 颜色字符串到 Flutter `Color` 的解析，支持 hex, rgb, rgba 以及基础颜色名。全面适配了新版 Flutter Color API（如 `r`, `g`, `b`, `a` 属性）。
- **`lib/utils/html_contrast_utils.dart`**：
  - 基于 `package:html` 解析 HTML 片段。
  - 在深色模式下，检测内联 `color` 属性与 `Theme.of(context).colorScheme.surface` 的对比度。
  - 采用渐进式白平衡混合（`Color.lerp`）提亮过深的文字颜色，直到符合 WCAG 对比度阈值要求（4.5:1）。
  - 内置 LRU 缓存，避免列表滚动时重复解析同一 HTML 片段带来的性能损耗。
- **`lib/pages/article/widgets/html_chunk_card.dart`**：在 `Theme.of(context).brightness == Brightness.dark` 时，对 `paragraph`、`blockquote`、`table` 和 `rawHtml` 块调用 `HtmlContrastUtils.adjustHtmlContrast`，实现了无感的动态文字颜色自适应。

## 61. 遗留问题与已知缺陷 (2026-05-25)

### 61.1 审核列表快速刷新导致被拒文章“复活”问题
- **现象**：当在“垃圾拦截（审核列表）”中左滑拒绝文章（标记为已读并加入 `ReadSyncService` 后台同步队列）后，如果立刻切回时间线进行下拉刷新，刚才被拒绝的文章会再次出现在审核列表中。但如果等待较长时间（让后台同步完成）后再刷新，则不会出现此问题。
- **根因分析**：
  1. 左滑拒绝后，本地数据库标记该文章为已读，并将其放入 `ReadSyncService` 队列等待同步给 Folo API。
  2. 此时立即下拉刷新，向 Folo API 请求未读列表。由于后台同步还未完成，API 依然返回该文章状态为“未读”。
  3. `TimelineController._applyUnreadSnapshot` 中存在“双向同步兜底逻辑”：如果 API 返回未读，则强行删除本地的已读状态 (`GStorage.readStatus.delete`)。
  4. 随后 `LocalArticleDbService.upsertMany` 根据被删除后的空覆盖状态重新合并，将该文章状态重置为 `isRead: false`，但保留了它原本的 `isRejectedByAi: true` 标记。
  5. `FilterReviewPage` 监听到 `isRejectedByAi == true && !isRead`，导致该文章重新出现在审核列表中。
- **建议修复方向**：
  在 `TimelineController._applyUnreadSnapshot` 中删除本地已读状态前，应优先检查 `ReadSyncService.pendingReadItems`。如果该文章存在于待同步队列中，说明它是用户刚刚执行的乐观更新（Optimistic Update），此时应信任本地已读状态，**不要**因为 API 返回了旧的 "未读" 状态就将其覆盖和删除。
- **实际修复**（2026-05-25）：已在 `TimelineController` 和 `FeedDetailController` 的 `_applyUnreadSnapshot` 中实施——收集 `pendingReadItems` entryId 集合，在 stale 清除循环中跳过仍待同步的条目。同时在方法签名中增加 `trustCompleteness` 参数，部分 API 失败时跳过"标记本地缺失文章为已读"的第一个循环（参见 §62.11）。

## 62. 性能优化（2026-05-25）

> 不影响任何现有功能与体验，`dart analyze` 零新增 warning，`flutter build apk --debug` 通过。

### 62.1 API 请求并行化
- `TimelineController.loadData()` 和 `FeedDetailController.loadData()` 中 3 个串行 `await`（feeds / social / inbox）改为 `Future.wait` 并行。
- `_refreshRecentReadWindow()` 中 2 个串行 `await`（feeds read / social read）同样改为 `Future.wait`。

### 62.2 正则表达式编译缓存
- `translation_service.dart`、`article_content_utils.dart`、`html_chunk_parser.dart`、`source_taxonomy.dart` 共 9 处方法内 `RegExp(...)` 提升为 `static final` 常量。

### 62.3 不必要的 ArticleModel 全字段拷贝消除
- `_mergeLocalReadState()` 增加守卫条件：只在本地 readState 与当前 `isRead` 不同时才创建新对象。
- `_updateReadStateInMemory()` 从 `.map()` 全列表遍历改为 `indexWhere` 单点定位。

### 62.4 searchSourceArticles 去拷贝
- `TimelineController.searchSourceArticles` 从 `allArticles.toList()` 改为直接返回 `allArticles` 引用。

### 62.5 骨架屏动画代码去重
- 新增 `ShimmerFadeList`（`lib/common/widgets/shimmer_card.dart`），三处独立动画控制器替换为统一组件。

### 62.6 Hive 批量写入
- `LlmConfig._save()` 中 6 次 `await put` 合并为 1 次 `await putAll`。

### 62.7 AI 过滤计数增量更新
- `TimelineController` 新增 `filterCount` RxInt，不再每次 rebuild 全量遍历 `readAllArticles()`。

### 62.8 FeedDetail 重复 upsertMany 移除
- `FeedDetailController._applyUnreadSnapshot()` 中 stale 清除循环前的冗余调用已删除。

### 62.9 ReadSyncService 指数退避
- 重试延迟从固定 `2s` 改为 `1s → 2s → 4s`（`Duration(seconds: 1 << retry)`）。

### 62.10 审核列表复活修复 (§61.1)
- 已在 `_applyUnreadSnapshot` 的 stale 清除循环中增加 `ReadSyncService.pendingReadItems` 守卫。
- `TimelineController` 和 `FeedDetailController` 均已修复。“未读”状态就将其覆盖和删除。

### 62.11 遗留问题：部分接口网络失败导致未读文章“闪烁”
- **现象描述**：用户在网络不稳定的情况下刷新（例如 feeds 接口超时失败，但 social 接口成功返回），界面上部分未读文章会突然消失（表现为 0 未读）；而在网络恢复后的下一次刷新中，这些文章又会突然重新出现。
- **根本原因**：`TimelineController`（以及 `FeedDetailController` 针对非 feeds 的请求失败时）存在部分网络失败的数据误判逻辑。当部分 API 成功时，`hasError && unreadData.isEmpty` 条件不成立，代码会继续调用 `_applyUnreadSnapshot(unreadData)`。由于 `unreadData` 缺少了失败接口的数据，快照对比逻辑会误以为这些本地未读文章在云端已经被标为已读，从而错误地将它们在本地标记为已读并隐藏。
- **自我修复机制**：这种错误标记由于未经过 `ReadSyncService` 同步到服务器，所以在下一次网络成功的刷新中，服务器依然会返回未读状态。`_applyUnreadSnapshot` 发现后，会删除错误的本地已读标记，从而使文章重新出现。这保护了数据不丢失，但严重影响了 UX。
- **处理建议**：待后续讨论制定针对部分网络失败的精确快照对齐方案。
- **实际修复**（2026-05-25）：`_applyUnreadSnapshot` 新增 `trustCompleteness` 参数。部分 API 失败时跳过"标记本地缺失文章为已读"循环，避免不完整数据误标记。`TimelineController.loadData()` 传入 `trustCompleteness: !hasError`；`FeedDetailController.loadData()` 传入三路全部成功的与运算结果。

---

## 63. 已读同步全面修复（2026-05-25）

### 63.1 问题报告

用户反馈：在 Folo Web 或其他客户端将文章标记为已读后，回到 autofolo 下拉刷新，该文章仍然显示为未读。

**具体案例**：一篇真实文章在远端已读、本地仍显示未读，反复刷新无效。具体 entryId 和标题片段不再写入仓库文档。

### 63.2 实验过程

在用户已授权的本地上下文中调用 Folo API 进行对照实验；具体 token 不写入仓库文档：

```
# 实验 1：read=false → 目标文章不在结果中 ✅ 服务端已确认已读
# 实验 2：read=true → 目标文章在结果中 ✅
# 实验 3：read=true + publishedAfter: "2天前" → 目标文章不在结果中 ❌
# 实验 4：read=true + publishedAfter: "文章时间+1秒" → 在 ✅
# 实验 5：read=true + publishedAfter: "文章时间-1秒" → 不在 ❌
```

**关键发现**：Folo API 的 `publishedAfter` 参数真实语义是**倒序分页游标**（"返回发布时间早于此的文章"），不是正向时间过滤器。命名具有误导性。

### 63.3 三重根因

#### 根因 A：`_refreshRecentReadWindow` 使用 `publishedAfter` 方向相反

```dart
// timeline_controller.dart _refreshRecentReadWindow()
final windowStart = DateTime.now().subtract(Duration(days: 2));
FeedHttp.collectEntries(read: true, publishedAfter: isoStr, ...);
// publishedAfter 语义为"早于" → 返回的全部是窗口外的旧文章
// 日志证实：拉回 4643 篇，全是 5月23日前的，独漏 5月25日的目标文章
```

#### 根因 B：`readStatus=false` 永久阻塞 `_applyUnreadSnapshot`

用户在审核列表滑动保留文章 → `FilterReviewPage._keep` → `markAsUnreadLocal` → `readStatus.put(false)`。
`_applyUnreadSnapshot` 遇到 `localOverride==false` 时 `continue` 跳过，永远不标记已读。
且 `false` 没有任何清理路径，一旦写入就永久生效。

#### 根因 C：`trustCompleteness` 全局与运算

三个 API（feeds 未读 / social 未读 / inbox 未读）任意一个失败 → `hasError=true` → `trustCompleteness=false` → feeds 文章的已读推断也被跳过。inbox API 故障拖累所有文章类型。

### 63.4 设计讨论

**`readStatus` 三态语义收敛**：

| 值 | 旧语义（混乱） | 新语义（收敛） |
|----|---------------|---------------|
| `null` | 无覆盖 | 无覆盖，信任服务端（不变） |
| `true` | 曾被系统或用户标记为已读 | 仅用户标已读时的临时保护锁，同步结束（成败均）释放 |
| `false` | 系统（审核保留）或用户（恢复未读）写入 | **不再写入**。历史遗留 `false` 由 `_applyUnreadSnapshot` 自动清除 |

**核心设计原则**：
- **用户操作** → 写 `readStatus=true`（临时锁）+ 入 pending 队列 → 同步成功后删 key
- **系统推断** → 只写 `articleDb.isRead`，不碰 `readStatus`
- **审核保留** → 只清 AI 标记，不创建任何 readStatus 覆盖
- **失败回退** → 删 readStatus，回退 articleDb，不残留

### 63.5 具体改动

#### 文件 1：`lib/pages/timeline/filter_review_page.dart`
- `_keep()`：删除 `markAsUnreadLocal` 调用，改为 `GStorage.readStatus.delete()` + 从 DB 重读文章更新 `TimelineController.allArticles` 内存状态

#### 文件 2：`lib/pages/timeline/timeline_controller.dart`
- `_applyUnreadSnapshot()`：签名从 `{bool trustCompleteness}` 改为 `{bool feedsOk, bool socialOk, bool inboxOk}`；按文章 category 独立判定对应 API 是否成功；`localOverride==false` 时删除而非跳过；不写 `readStatus=true`
- `markAsUnreadLocal()`：删除 `GStorage.readStatus.put(entryId, false)`，只更新 articleDb
- `_refreshRecentReadWindow()`：去掉 `publishedAfter` 参数；改用 `getEntries(limit:200)` 拉最新已读 + 本地按 `windowStart` 过滤
- 删除临时 debug 日志和 `flutter/foundation.dart` import

#### 文件 3：`lib/pages/feed_detail/feed_detail_page.dart`
- `_applyUnreadSnapshot()` 和 `_refreshRecentReadWindow()` 与 timeline 完全相同的修复
- 调用点：`allSucceeded` 与运算替换为 `feedsOk/socialOk/inboxOk` 三独立标志

#### 文件 4：`lib/pages/article/article_page.dart`
- `markAsRead()`：同步成功或失败后均 `GStorage.readStatus.delete()`（释放保护锁）；失败回退不写 `false`
- `markAsUnread()`：删除 `GStorage.readStatus.put(entryId, false)`；失败回退仍写 `true`（正确）

### 63.6 行为变化对照

| 场景 | 旧行为 | 新行为 |
|------|--------|--------|
| 审核列表滑保留 → 别处读完 → 刷新 | ❌ 仍显示未读（`false` 阻塞） | ✅ 正确标记已读 |
| 文章页标已读 + 同步成功 | `readStatus=true` 残留 | `readStatus` 已删除 |
| 文章页标已读 + 5次失败 | `readStatus=false` 残留 | `readStatus` 已删除，回退未读 |
| inbox API 失败时刷新 | feeds 文章也不判定已读 | feeds 文章独立判定 |
| 别处读完 >2天前发布的文章 | 路径② `publishedAfter` 方向错误 | ✅ 本地窗口过滤正确 |

### 63.7 未改动文件

- `read_sync_service.dart` — 队列机制保持不变，未来可扩展支持双向操作（markUnread）
- `auto_filter_worker.dart` — `unReject()` 逻辑正确，未修改
- `local_article_db_service.dart` — `upsertMany` 合并逻辑未修改（`readStatus` 收敛后，`localOverride` 只有 `true` 或 `null`）

### 63.8 遗留问题与安全分页方案研究（Pending Review & Next Steps）

经过对最新提交 `551894e` 的复盘，整体修复方向非常正确，但仍遗留了两个体验和边缘 Case 问题。这两个问题当前记录在案，作为后续优化的储备，暂不执行代码修改。

#### 遗留问题 1：App 切前台缺乏自动同步机制
当前 `TimelineController.loadData()` 仅在应用冷启动（`onInit`）或用户手动下拉时触发。当用户在 Web 端阅读完毕，直接切回手机 Autofolo（从后台恢复）时，应用仍展示切入后台前的残像，导致用户误认为同步失败。
- **储备方案**：为 `TimelineController` 混入 `WidgetsBindingObserver`，监听 `AppLifecycleState.resumed` 事件，结合时间防抖，在切前台时静默调用 `loadData()`。

#### 遗留问题 2：近期已读 `_refreshRecentReadWindow` 的安全分页截断隐患
当前代码将远古拉取的 Bug 修复为了单次请求：`FeedHttp.getEntries(limit: 200)`。
- **隐患分析**：如果 API 的强制最大限制是 50（标准 REST 防护），或用户2天内阅读超过 200 篇，超出的文章将永远丢失。此外，单次请求 `limit: 200` 且携带 `withContent: true` 极易导致弱网超时。
- **安全方案思路**：放弃单次拉取，实现严格的 `while` 循环分页。每次请求 `limit: 50`，获取数据后检查 `batch.last.publishedAt`。若最旧文章的时间尚未越过窗口底线（2天前），则将 `cursor` 设为 `batch.last.publishedAt` 继续请求下一页。直到 `batch.last.publishedAt < windowStart` 时安全退出循环。

## 64. 恢复消失的表格与通用图文排版重构（2026-05-26）

### 64.1 修复背景与现象
用户发现部分 RSS 源（如“小众软件”）文章内的表格完全消失，以及部分图片（尤其是 emoji）在表格中被放大多倍，导致整个版面被撑爆。

### 64.2 诊断过程与核心思路
1. **数据与解析层核实**：通过拦截并测试 API 响应，发现带有 `<table>` 的 HTML 节点在获取和切分时是完整的。真正的原因是 `flutter_html` 从 3.0.0 版本开始剥离了原生表格支持，将其独立到了 `flutter_html_table`。项目中没有注册相关的 `TableHtmlExtension`，导致所有 `<table ...>` 被静默丢弃。
2. **“双重邮件展平”的发现与废弃**：
   - 根据 AGENT_HANDOFF 的历史记录（52.1 节），`ArticleContentUtils._flattenLayoutTables` 已经非常完美地剥离了没有 `<th>` 的邮件布局空壳，为 LLM 节省了约 30% 体积，这套安全机制被保留。
   - 但在 `HtmlChunkParser` 中，还有一套危险的基于启发式正则（`tableCount > 5` 等）的 `isEmail` 检测，强行将剩余的真实数据表打散拼装成 `<p><tr>...</tr></p>`。这破坏了所有正常的有表头数据表。这套画蛇添足的逻辑已被彻底移除。
3. **列表内富文本恢复**：原 `HtmlChunkParser` 处理 `ul/ol` 时使用 `li.text.trim()` 粗暴提取纯文本，丢失了加粗、链接、内部图片。现改为 `li.innerHtml.trim()` 并在 UI 渲染层利用 `Html()` 进行解析。
4. **底层图文自适应约束（大图缩小，小图精致）**：
   - 原 `_imageExtension` 中，所有渲染内的嵌图被强行绑定了 `width: maxWidth`。这导致了即使是原本只有十几像素的内联徽章或 emoji，也被强行拉伸填满整个屏幕，从而撑毁表格。
   - **重构机制**：现在会自动解析 `extensionContext.attributes` 的 `width` 和 `height`。当没有显式尺寸约束时，解除 `maxWidth` 强制限制，让 `CachedNetworkImage` 自主决定。并增加了针对常见 WordPress Emojis（如 `s.w.org/images/core/emoji`）的 `20x20` 特殊兜底逻辑。

### 64.3 变更细节
- **依赖变更**：引入 `flutter_html_table: ^3.0.0-beta.2`。
- **解析层**：删除了 `html_chunk_parser.dart` 中与 `isEmail` 有关的所有逻辑以及不再使用的正则缓存变量。更新了列表的提取方式。
- **渲染层**：为所有基于 `Html()` 渲染的组件插入 `TableHtmlExtension()`。重构 `_imageExtension`，使其兼容超大风景图及内联小图标的智能自适应尺寸。

**结论**：本次修改不仅找回了表格，还使 App 全局掌握了渲染极其复杂图文嵌套（如引用内带视频、列表内带图片链接、表格内带小微标）的能力。

## 65. 修复 HTML 块内链接无法点击的问题（2026-05-26）

### 65.1 问题背景

用户反馈在文章详情页中，如果链接 (`<a>` 标签) 存在于标题 (`<h1>`-`<h6>`)、段落 (`<p>`)、列表 (`<li>`)、引用块 (`<blockquote>`)、表格 (`<table>`) 等 HTML 块内部，点击这些链接没有任何反应。

### 65.2 根因分析

1. **纯文本剥离**：在 `HtmlChunkParser` 解析标题、列表等区块时，原本的逻辑错误地剥离了部分内联 HTML 标签（包括 `<a>`），导致渲染层拿到的可能只是纯文本。
2. **缺失链接处理**：在 `HtmlChunkCard` 渲染层中，对于这些元素的渲染，原先部分采用了 `Text` 控件，或者即使采用了 `Html` 控件也没有配置 `onLinkTap` 回调事件，因此用户无法触发外部链接的点击跳转。

### 65.3 修复方案

1. **Parser 层保留内联标签**：
   - 将 `_headingTextOnly` 重命名为 `_headingHtmlOnly`。
   - 在跳过图片等媒体子节点时，使用 `node.outerHtml` 和 `element.innerHtml` 获取内容，从而在生成的 `HtmlChunk` 中完整保留了 `<a>` 等内联 HTML 标签。
2. **Renderer 层增加点击事件与样式**：
   - 提取出公共的 `_handleLinkTap` 函数，使用 `url_launcher` 通过外部浏览器 (`LaunchMode.externalApplication`) 打开点击的链接。
   - 为所有涉及图文排版的区块（标题、段落、列表、表格、引用块及原始 HTML 区块）统一应用 `Html` 控件，并配置 `onLinkTap: _handleLinkTap`。
   - 对于深色模式下使用 `Html` 渲染的情况，统一先通过 `HtmlContrastUtils.adjustHtmlContrast` 调整整体 HTML 字符串的对比度。同时在 `Html` 的 `Style` 中为 `<a>` 标签配置主题色，确保所有区域的链接颜色一致且不突兀。

### 65.4 影响文件

- `lib/utils/html_chunk_parser.dart`
- `lib/pages/article/widgets/html_chunk_card.dart`

---

## 66. 优化文章滑动渲染性能（2026-05-26）

### 66.1 问题报告

用户体验反馈：在阅读页面（`ArticlePageView`）横向滑动翻页时，UI 线程存在卡顿和掉帧现象。特别是在文章内容较长或者包含较多复杂元素时，滑动过程不够流畅。

### 66.2 根因分析

原先的 `_initContent` 方法在主隔离区（UI 线程）同步执行 HTML 解析和各种正则处理（包括 `ArticleContentUtils.normalizeHtml` 和 `HtmlChunkParser.parseSync` 等）。这些操作由于涉及大量字符串运算，会导致 UI 线程阻塞，从而在滑动切页时造成明显的掉帧卡顿。

### 66.3 设计讨论与具体改动

**核心思路**：将耗时的 HTML 解析操作卸载（Offload）到独立的 Isolate 中运行，释放 UI 线程的压力，确保页面滑动动画的 60fps/120fps 流畅渲染。

**具体改动**：
1. **引入 Isolate 并发处理**：修改 `ArticleController` 中的 `_initContent` 为异步方法（返回 `Future<void>`），并利用 Dart 的 `Isolate.run`，将 `ArticleContentUtils.normalizeHtml`、`ArticleContentUtils.extractImageUrls`、`HtmlChunkParser.parseSync`（原文及翻译文本）移至后台 Isolate 执行，最后将结果返回主线程进行数据绑定。
2. **增加加载状态显示**：在 `ArticleController` 引入 `isParsingContent` 响应式变量，标识 Isolate 解析是否在进行。并在 `_ArticlePageViewState` 的 Sliver 列表渲染中，当 `isParsingContent` 为 true 时，展示一个居中的 `CircularProgressIndicator` 加载提示符（附带 "正在排版内容…" 字样），以填补 Isolate 计算期间的视觉空白，改善用户体验。
3. **允许隐式滚动缓存**：在 `_ArticlePagerPageState` 返回的 `PageView.builder` 增加 `allowImplicitScrolling: true` 属性。此举允许 Flutter 在后台隐式预构建和缓存邻近的文章页面，配合 Isolate 的异步解析，使得用户滑动到下一页时，页面通常已经预排版完成，极大增强了操作丝滑感。

### 66.4 行为变化对照

| 场景 | 旧行为 | 新行为 |
|------|--------|--------|
| 文章加载与滑动 | UI 线程同步解析 HTML，易掉帧 | 后台 Isolate 异步解析，UI 线程无阻滞 |
| 解析期间展示 | 无，主线程卡住或直接显示内容 | 显示优雅的加载动画（正在排版内容…） |
| PageView 预渲染 | 未启用隐式缓存，滑动时才触发构建 | 开启隐式滚动，邻近页面提前触发 Isolate 解析与渲染 |

---

## 67. 解决全局状态变更导致的时间线 UI 失步问题（2026-05-26）

### 67.1 问题背景

在之前的架构中，当单篇文章的状态在全局被更新时（例如：AI 自动过滤 Worker 判定该文章为被拦截 `isRejectedByAi: true`，或用户在其他视图中改变了文章的已读未读状态等），如果用户不触发 `TimelineController.loadData()` 下拉刷新，`TimelineController` 内存中的 `allArticles` 列表将不会感知该变化。
这会导致时间线列表卡片的 UI 呈现，以及顶部的“AI智能过滤拦截数”等聚合 UI 组件出现数据脏读或失步。

### 67.2 增量同步机制设计（单点精确刷新）

在 `TimelineController.onInit` 中，借助已有的 `ArticleStateNotifier` 注册全局监听器。
当发生状态更新时，通过新增的 `_syncSingleArticleFromDb(entryId)` 实现了精确增量更新，而不需要重新进行昂贵的全列表 `_applyFilter` 和 `loadData`（除非该变更引起了列表本身的分类流转）：

1. **精确点查**：在 O(N) 找到当前时间线 `allArticles` 列表中的目标文章。如果不在此视图内则直接跳过，零开销。
2. **读库映射**：从 Hive (`GStorage.articleDb`) 读取最新的底层统一数据包，并转换回 `ArticleModel`。
3. **保护本地重写覆盖**：引入本地内存未读防闪烁机制，将从库里读到的新数据与 `GStorage.readStatus` 中的临时锁定（`true`）安全合并，防止同步瞬间的已读闪烁（收口机制与 §63 保持一致）。
4. **驱动响应系统**：直接替换 `allArticles[idx]`，触发 `.refresh()`，并随后调用 `_applyFilter()` 与 `_updateFilterCount()` 准确驱动“拦截器拦截数”和时间线分片的精确响应重绘。

### 67.3 影响文件

- `lib/pages/timeline/timeline_controller.dart`

---

## 68. 修复 Inbox 旧文章不可见（被 5000 条本地缓存限制误删）的问题 (2026-05-26)

### 68.1 背景与现象
- 用户发现：虽然修复了 `feed_http.dart` 里的 Inbox 拉取逻辑，但“下拉刷新后，inbox 只有最新的一篇文章”。
- 更换过滤条件为“全部”时，时间线最早的文章只追溯到 4 天前。
- 通过 Curl 直接请求 `api.folo.is/entries/inbox`，证明服务器确实验证返回了 4 篇 Inbox 文章（包含 1 篇最新和 3 篇 1月/3月 的旧文章）。

### 68.2 诊断过程
- 最初怀疑是 `_applyUnreadSnapshot` 的合并逻辑或 `AutoFilterWorker` 误拦。
- 经过分析代码确认，`AutoFilterWorker` 会直接跳过无 `content` 的文章，所以 Inbox 的文章不会被 AI 拦截（`isRejectedByAi: false`）。
- **关键线索**：时间线最早的文章只到 4 天前。
- **真相**：由于用户订阅源极多，每天可能产生 >1000 篇新文章。Autofolo 的本地数据库 `LocalArticleDbService` 有 `_maxArticles = 5000` 的硬性容量限制。
- `TimelineController.loadData()` 正确拉取到了 3 篇一月/三月的 Inbox 文章并存入数据库，但**在同一帧内**触发了 `_trimOverflow()` 清理机制。
- 之前的 `_trimOverflow()` **仅仅按照发布时间（`publishedAt`）倒序**保留最新的 5000 篇。由于 3 篇 Inbox 文章非常陈旧（早于 4 天前），它们在入库的瞬间就被无情地当做溢出旧数据删除了！

### 68.3 修复方案与逻辑简化
1. **修改点**：重写 `LocalArticleDbService._trimOverflow()` 的排序算法，引入优先级保护机制，彻底抛弃单纯的时间倒序。
2. **逻辑简化**：在与用户讨论后，用户表示其关注点在于“只要是未读文章就不应该丢失”，且能保证未读文章总数不会超过 5000。为契合极简设计理念，最终的排序策略被简化为：
   - **优先级 1（最高，优先保留）**：所有未读文章（`!isRead`）。只要是未读（不论 Feed 还是 Inbox），都优先保留，避免因年代久远被淘汰并导致后续无休止的重复拉取。
   - **优先级 0（最先淘汰）**：已读文章（`isRead == true`）。
   - **同级排序**：如果优先级相同，再按发布时间倒序排列。

### 68.4 影响分析与架构哲学记录
- **传送带效应（Sliding Window）**：无论客户端的 5000 容量限制如何挤出文章，都只是影响本地缓存。服务器依然是唯一的“真相源”（Source of Truth）。用户看完前排文章并标为已读后，下一次刷新时，由于腾出了本地空间，原本被挤出边界的老未读文章会如同传送带一般，从服务器被拉取并重新进入可视范围。
- 这是一个典型的本地资源受限环境下的防饥饿、防雪崩缓存设计。由于未读状态（Priority 1）自带免死金牌，用户的核心待办列表再也不会因为其年代久远而陷入“插入即被删”的黑洞。

---

## 69. 极致渲染优化：完美进度条与流畅加载的平衡 (2026-05-28)

### 69.1 背景与痛点
在之前的架构中，为了防止多图超长文导致的初次渲染内存峰值与主线程卡顿，我们在 `ArticlePage` 引入了 `SliverList` 懒加载策略。
但这引入了一个致命副作用：**阅读进度条失效/乱跳**。由于 Flutter `SliverList` 无法预知未渲染子组件的高度，导致 `ScrollController.position.maxScrollExtent` 在滑动过程中不断动态增加，使得顶部进度条永远算不准，也无法平滑到达 100%。

### 69.2 核心策略：回归 Column + 大颗粒度打包
为了在找回“绝对精确进度条”的同时避免初次渲染卡顿，我们采取了“降维打包”策略：
1. **废弃 SliverList**：在 `ArticlePage` 中彻底移除懒加载机制，将文章所有区块通过 `Column` 一次性构建。
2. **底层合并短段落 (HtmlChunkParser)**：
   - 将相邻的细碎纯文本 `<p>` 节点直接拼接（上限放宽至 2000 字符）。
   - 关键优化：使用 `<br><br>` 而不是 `\n\n` 进行拼接。这不仅大幅减少了 Flutter 组件树的层级数量（从几百个 Widget 降维到十几个），还完美保留了 `flutter_html` 解析时的物理段落间距。
3. **列表不拆分**：遇到 `<ul>` 和 `<ol>`，不再暴力切分成独立 chunk，而是整块保留 HTML 提交渲染。

### 69.3 终极补丁：渐进式分帧注入 (Incremental Rendering)
虽然通过打包极大地减少了 Widget 数量，但在遇到包含数十个巨型区块的万字长文时，`Column` 的初次布局依然会导致打开文章或横向滑动切页时出现微小的掉帧（Jitter）。
为此，我们在 `ArticlePage` 中引入了 `_renderIncrementally` 渐进式注入机制：
- **首屏秒开**：瞬间只将前 3 个 Chunk 注入渲染队列，保证绝对顺滑无感。
- **后台逐帧补齐**：剩余的 Chunk 每隔一帧（16ms）向 `Column` 底部追加一个。结合给 `HtmlChunkCard` 绑定的独立 `ValueKey`，底层 Flutter 引擎会自动跳过已渲染块的重绘（Rebuild），实现了无掉帧的丝滑加载。

### 69.4 视觉防抖优化 (Layout Shift 保护)
在 `HtmlChunkCard` 中，对于未知真实尺寸的网络图片，取消了原本硬编码的 `100.0` 兜底高度，改为动态计算的 `widget.maxWidth * 0.6` 作为占位符。由于大部分插图都是横屏比例，这个占位极大地减少了真实图片加载瞬间引发的版面跳动。

### 69.5 影响文件
- `lib/pages/article/article_page.dart`
- `lib/utils/html_chunk_parser.dart`
- `lib/pages/article/widgets/html_chunk_card.dart`
- `lib/pages/settings/settings_page.dart` (删除了多余的懒加载设置项)

---

## 70. 延迟 build + widget 缓存：根治重度技术文章首次打开掉帧 (2026-05-30)

### 70.1 触发案例

文章：**"Profiling in PyTorch (Part 1): A Beginner's Guide to torch.profiler"**
- 来源：Hugging Face - Blog（feedId: `41459996870678531`，entryId: `1132614748223852544`）
- 原始 HTML: 210KB，含 56 张图片、17 个 `<pre>` 代码块、166 个 `<code>` 标签、27 个表格、229 个 `<p>` 段落、29 个标题、66 个 SVG
- 用户观察：**从打开到流畅滑动花费约一分钟**，掉帧极其严重

### 70.2 诊断过程

1. **定位文章**：通过 Folo API 搜索到该文章（来自 Hugging Face - Blog 订阅源）
2. **拉取原始内容**：用 Dart `HttpClient` 直接抓取 `huggingface.co/blog/torch-profiler` 原文（210KB）
3. **模拟渲染管线**：编写 `scratch/analyze_pipeline.dart` 模拟 app 的 Readability 提取 → normalize → 分块全流程
4. **锁定真凶**：通过数学建模确认根因

### 70.3 真正的根因（不是图片加载）

关键路径：`_renderIncrementally` 每 16ms 向 `renderedChunks` 追加 1 块 → 触发 `Obx()` → Column 全量 rebuild → **所有已存在的 `HtmlChunkCard` 全部重新构建**。

旧代码中 `HtmlChunkCard.build()` 每次都调用 `flutter_html` 的 `Html()` 重新解析 HTML 字符串为 Widget 树。以这篇 200 块的文章为例：

```text
第 1 块加入：           1 次 Html() 解析
第 2 块加入（16ms 后）： 2 次 Html() 解析（第 1 块又重来一遍）
第 3 块加入：           3 次 Html() 解析
...
第 200 块加入：        200 次 Html() 解析

总解析次数 = 1+2+3+...+200 ≈ 20100 次
每次解析约 3ms（含内联 code/link/格式混排） → 20100×3ms ≈ 60 秒
```

**这是经典的 O(n²) 自爆——不是图片慢，是代码在反复解析同一段 HTML。**

### 70.4 解决方案讨论

与用户讨论了三种修复方向：

| 方案 | 描述 | 工作量 | 采纳 |
|------|------|--------|------|
| 方案一（widget 缓存） | HtmlChunkCard 首次构建后缓存 widget，后续 rebuild 直接复用 | ~1h | ✅ 已实施 |
| 方案二（延迟 build） | 首帧只 build 前 N 块（默认 5），其余用 SizedBox 占位，滚动/渐进补全 | ~3h | ✅ 已实施 |
| 方案三（Isolate 预处理） | 在后台线程将 HTML 预解析为简单数据结构，UI 线程直接拼 RichText，完全绕开 flutter_html | ~2-3 天 | ❌ 记录待后续 |

**为什么没选方案三（当前阶段）**：
- 方案一 + 方案二组合已从 O(n²) 降到 O(n)，对绝大多数文章足够
- 方案三需要处理 flutter_html 内部的 AST 序列化，工量大且引入新复杂度
- 未来触发条件：当遇到即使缓存后 build 单块仍超 5ms 的场景时再考虑

**预处理时机讨论（方案三的前置分析）**：
- 时机 A（全量入库即处理）：简单但浪费算力
- 时机 B（仅 Readability 文章处理）：精准，重文章才需要
- 时机 C（预测式：用户停留预览时预处理）：精准但实现复杂
- **最终倾向**：B + C 组合

### 70.5 实施方案细节

#### 改动 1：HtmlChunkCard widget 缓存（`html_chunk_card.dart`）

`_HtmlChunkCardState` 新增 `_cachedWidget` 和 `_cachedBrightness` 字段。`build()` 中只有首次或主题亮度切换时调用 `_buildContent()`，后续直接复用缓存：

```dart
if (_cachedWidget == null || _cachedBrightness != brightness) {
  _cachedWidget = _buildContent(context);
  _cachedBrightness = brightness;
}
```

**效果**：父级 rebuild 时已有块的构建成本从 ms 级降到 ns 级（指针复用）。

#### 改动 2：ArticlePageView 占位 + 按需填充（`article_page.dart`）

- 新增 `_builtCount`（已构建块数）、`_lastShowTranslation`（翻译模式追踪）
- 首帧只构建前 N 个 `HtmlChunkCard`（N 从 `GStorage.setting` 读，默认 5）
- 其余块用 `SizedBox(height: chunk.estimatedHeight)` 透明占位
- 首帧提交后 `_buildNextBatch()` 逐批补齐（每批 10 块，间隔 50ms）
- 补齐后不回收（保持 Column 架构，进度条精确）
- 翻译切换时自动重置 `_builtCount`

#### 改动 3：HtmlChunk 高度预估（`html_chunk_parser.dart`）

新增 `estimatedHeight` 计算属性，对 10 种块类型根据内容长度/图片尺寸粗略估算渲染高度。误差在 ±30% 以内，用于占位 `SizedBox` 避免后续替换时大幅跳布局。

#### 改动 4：可配置参数（`constants.dart`）

新增 `StorageKeys.articleInitialChunkBuildCount`，默认值 5，范围 3-20。每次打开文章实时读取，无需重启生效。

### 70.6 与现有机制的协同

- **实现演进**：初始修复仍沿用 `_renderIncrementally` 控制数据流（renderedChunks 逐块增长）；随后与第 71 节的转场错峰优化合并后，数据层逐个追加被移除，最终由 View 层的 `_builtCount` / `_buildNextBatch()` 接管延迟 build。
- **不改动 Column 架构**：所有块仍然在一个 Column 内，进度条保持精确
- **不改动 `AutomaticKeepAliveClientMixin`**：补全后的块永驻不销毁

### 70.7 效果评估

| 指标 | 改之前 | 改之后 |
|------|--------|--------|
| 首帧打开 | 200 块全量 build，画面冻结 0.5-1.5s | 只 build 5 块，<50ms 流畅打开 |
| 总解析次数（200 块） | ~20100 次（O(n²)） | ~200 次（O(n)） |
| 总加载时间 | ~60 秒 | ~4 秒（3.2s 增量 + 0.6s 新解析） |
| 图片加载跳动 | 无尺寸图片随意占位，加载后大跳 | estimatedHeight 预估值接近真实，跳动减小 |
| 滑动流畅度 | 反复重新解析 → 持续掉帧 | 缓存 hit → 滑动丝滑 |

**注意**：总完成时间中图片加载仍是瓶颈（56 张图 × 网络耗时），但渲染侧的 O(n²) 自爆已完全消除。

### 70.8 影响文件

- `lib/pages/article/article_page.dart` — 核心：首帧占位 + 渐进构建 + 翻译切换重置
- `lib/pages/article/widgets/html_chunk_card.dart` — widget 缓存
- `lib/utils/html_chunk_parser.dart` — HtmlChunk 新增 `estimatedHeight`
- `lib/common/constants/constants.dart` — 新增 `StorageKeys.articleInitialChunkBuildCount`

### 70.9 遗留讨论

以下来自本次对话但未实施的讨论，记录供后续参考：

1. **方案三（Isolate 预处理 flutter_html）**：如果未来遇到 widget 缓存后单块 build 仍然超 5ms 的文章，可考虑将段落/标题的 HTML→TextSpan 转换搬进 Isolate，UI 线程直接拼 RichText。表格和列表暂不处理（数量少，优先级低）。
2. **`_renderIncrementally` 的 16ms 延迟**：在 widget 缓存生效后，这个延迟的必要性大幅降低（原有块的 rebuild 已是 ns 级）。最终合并状态中，`_renderIncrementally` 数据层逐个追加已被移除，完全由 View 层的 `_builtCount` 配合首帧转场保护（350ms）接管渲染控制。

---

## 71. 卡片转场动画防掉帧与预加载策略 (2026-05-30)

### 71.1 痛点与现象描述
在之前的版本中，当用户在时间线点击文章卡片（触发进入 `ArticlePage`）时，转场动画（`Transition.rightToLeft`）会出现轻微的掉帧和卡顿感。

### 71.2 根本原因分析
我们深入排查了底层的渲染管线与线程资源争夺问题：
1. **主线程的独占性与争夺**：Flutter 的转场动画大约需要 300ms，而任何界面的构建、布局与绘制都必须且只能在单一的主线程（UI 线程）完成。
2. **异步解析的假象**：虽然在 `ArticleController` 中，我们将极其繁重的 HTML 字符串解析拆解任务放到了后台线程（通过 `Isolate.run` 提取 `HtmlChunk` 模型），做到了不卡主线程；但这段数据层面的“预处理”速度极快（通常数十毫秒）。
3. **掉帧发生的时刻**：在当时实现中，一旦后台解析完成，代码会立即调用 `_renderIncrementally` 开始将排版块塞入响应式队列 `target`，此时屏幕尚未完成转场。由于 `flutter_html` 等组件的排版开销巨大，瞬间在主线程生成这些复杂的 Widget 树直接阻塞了原本平滑的划入动画。

### 71.3 渐进式渲染（错峰挂载）解决方案
为彻底解决该问题，我们对“渲染队列”引入了**时间错峰策略**：
1. **转场保护期**：在当时的 `_renderIncrementally` 头部增加时间戳校验。强制等待应用距离 `onInit` 走过 350ms，完全让渡出主线程的最初 300ms 算力，确保划入屏幕的动画能做到 100% 满帧。最终合并后，这个保护语义由 View 层延迟 build 流程承接。
2. **降频挂载**：动画平稳落定后，再从队列里挤牙膏式地提取组件。我们将首批并发量从 3 降低到 2 个 Chunk，同时将后续块的逐帧间隔从 16ms 放宽至 24ms，从而抹平所有的算力峰值。

### 71.4 概念澄清与架构约束（交接备忘）
在这轮优化探讨中，我们明确纠正了一个常见的直觉误区，特留存给后续 Agent 查阅：
- **直觉误区**：“能否开一个独立的后台线程，把还没来到屏幕中的画面预先渲染好？”
- **架构事实**：**绝对不能**。对于任何现代 GUI 框架（Flutter / 原生 iOS 等），UI 视图的实例化（`build`）和排版计算必须处于并且只处于主线程。此处的“渲染队列”并非指后台的图形预渲染，而是**主线程上的分批挂载（Staggered Mounting）策略**，属于一种时间换空间的妥协。
- **系统已实现的真正“预加载（Preloading）”**：应用中属于“无 UI 计算”的环节均已尽数剥离并移交后台处理。例如列表刷新时通过 `withContent: true` 将文章 HTML 悉数存入 `LocalArticleDbService`，乃至调用各种 Worker 提前发起深度网页提取、大模型全文翻译与摘要等，构成了底层数据的预载。这一套零卡顿的数据预备流程，加上卡片转场时这 350ms 的“错峰避让渲染”，共同奠定了应用顶级的操作流畅度。

## 72. 未来功能规划 (Future Features)

本文档记录了目前暂未实现，但在未来迭代中计划加入的改进项。

### 72.1 后台静默刷新通知角标 (Background Badge Sync)
- **背景**：目前应用在“退后台（挂起）”状态或处于前台时，可以实时更新桌面图标的未读角标（红点或数字）。但如果应用被系统完全杀掉，即使服务器端有了新文章，桌面角标也无法自动更新，必须等到用户下次打开应用。
- **目标**：实现应用在完全关闭状态下，桌面角标依然能随服务器未读文章数量变化而更新。
- **技术选型方向**：
  1. **Push Notifications (推荐)**：集成 Firebase Cloud Messaging (FCM) 或极光推送。服务端有新文章产生时，向设备发送一条静默推送（Silent Push / Data Message），唤醒客户端一小段后台执行时间，由客户端计算未读数并调用 `flutter_app_badger` 更新角标。
  2. **Background Fetch**：使用 `workmanager` 或类似插件，每隔一段时间在后台拉取一次数据更新角标。缺点是实时性差且受各大 Android 定制系统（如 MIUI, OriginOS, ColorOS）的后台纯净机制严格限制。
- **优先级**：中 (根据用户对通知实时性的需求而定)。

---

## 73. 长文阅读页自适应虚拟渲染（2026-05-31）

### 73.1 背景

第 81 节的 `Column + 渐进挂载 + widget 缓存` 已经让大多数文章打开和滚动足够流畅，但它的代价是：文章全部补齐后，所有 `HtmlChunkCard` 都常驻页面树。对普通文章这是可接受的；对极长 newsletter、多图长文、超大代码块文章，会推高内存占用。

### 73.2 本次决策

保留普通文章的现有路径，不回退它的体验；只对长文启用虚拟渲染：

- 普通文章：继续使用 `SliverToBoxAdapter + Column + 渐进挂载`，保持精确进度条和已验证的流畅度。
- 长文章：切换为 `SliverList.builder`，只构建视口附近的 chunk。
- 长文模式下 `HtmlChunkCard.keepAlive=false`，滑出屏幕的复杂 HTML widget 可释放，降低内存峰值。

长文判定条件：

- `HtmlChunk` 数量 >= 80；或
- 原始预估正文高度 >= 10000 px。

### 73.3 进度条策略

以前直接使用 `ScrollMetrics.maxScrollExtent`，在 `SliverList` 懒加载下会因列表动态估算而跳动。本次长文模式改为稳定估算：

- 初始用 `HtmlChunk.estimatedHeight` 计算正文总高度。
- 已构建过的 chunk 通过 `_MeasuredSize` 回填真实高度。
- 进度条用“元数据区预估高度 + 正文估算/实测高度 + 底部间距”计算，不直接依赖动态变化的 `maxScrollExtent`。
- 滚动到底部时通过 `metrics.extentAfter <= 8` 强制归 100%。

这不是像普通文章一样绝对精确，但目标是“不乱跳、接近准确、长文更稳”。

### 73.4 影响文件

- `lib/pages/article/article_page.dart`
  - 新增长文判定；
  - 新增虚拟正文渲染分支；
  - 新增 `_MeasuredSize` 记录 chunk 实际高度；
  - 长文模式使用自维护高度估算更新阅读进度条。
- `lib/pages/article/widgets/html_chunk_card.dart`
  - 新增 `keepAlive` 参数；
  - 普通模式默认保持缓存；
  - 长文虚拟列表传入 `keepAlive: false`。

### 73.5 验收要点

1. 普通文章仍走原路径，打开、滚动、进度条表现不应变差。
2. 极长文不会一次性常驻所有复杂 HTML widget。
3. 长文阅读进度条应稳定，不再因虚拟列表动态布局明显乱跳。
4. 图片预览、链接点击、翻译切换、摘要卡片不应受影响。

---

## 74. 设置页任务中心（2026-05-31）

### 74.1 产品定位

用户明确希望审核页的高频交互和入口保持不变，因此任务中心不承载逐篇审核流程。任务中心定位为设置页内的低频诊断入口，用于查看后台同步和 AI 队列是否正常。

### 74.2 第一版范围

入口：

- 设置页新增“后台任务与同步”卡片。
- 路由：`Routes.taskCenter` / `/task-center`。

页面能力：

- 总览本地文章数、未读数、待人工审核数。
- 查看已读待同步数量和最近已读同步时间。
- 手动触发“同步已读”。
- 查看 AI 过滤、自动翻译、自动摘要的排队数、处理中数和失败数。
- AI 过滤区只提供“去审核”跳转，不展示审核列表，不替代 `FilterReviewPage`。
- 自动翻译/自动摘要失败时，可从任务中心进入失败文章列表，逐篇查看失败原因，并对单篇文章执行“打开”或“重试”。

### 74.3 有意不做

第一版不做暂停/继续、清空队列、批量重试、详细日志和批量审核。原因是这些操作会改变后台行为，容易引入误操作和更复杂的状态恢复；当前阶段只解决“用户能看懂后台是否在工作”的问题。

这里的“单篇重试”不是批量操作：用户明确希望能在 AI 任务下排查“是哪篇文章失败了”，并对具体文章手动处理。因此任务中心允许查看失败明细和单篇重试，但仍不提供“一键全部重试”。

### 74.4 影响文件

- `lib/pages/settings/task_center_page.dart` — 新增任务中心页面。
- `lib/pages/settings/settings_page.dart` — 设置页入口卡片。
- `lib/router/app_pages.dart` — 新增任务中心路由。
- `lib/services/read_sync_service.dart` — 记录最近已读同步时间。
- `lib/services/auto_translation_worker.dart` / `auto_summary_worker.dart` — 暴露当前处理中数量。
- `lib/services/translation_service.dart` / `summary_service.dart` — 提供按状态计数和失败记录查询，用于失败数量展示和失败明细页。

---

## 75. macOS 桌面端深度适配（2026-05-31，进行中）

### 75.1 核心需求与设计
在原有跨平台代码基础上，全面提升 macOS 端的原生交互体验，使其具备真正的桌面级应用质感。设计上严格对标原始 `folo` 桌面端的“三栏布局”，同时保留 Android 端的原有形态。

### 75.2 当前实现要点
1. **三栏经典布局与毛玻璃侧边栏**：
   - 在 `lib/pages/main/main_page.dart` 中，移除了原有的移动端底导和基础侧边导航，彻底重构为 `MacOSSidebar | VerticalDivider | 核心内容区` 的三栏布局。
   - 新增 `lib/pages/main/widgets/macos_sidebar.dart`，使用 `BackdropFilter(sigmaX: 20, sigmaY: 20)` 实现 macOS 标志性的高强度毛玻璃（Vibrancy）效果。
   - 订阅树（包含“全部文章”、“垃圾拦截”、各种分类与特定源）被直接展现在最左侧边栏中。

2. **底层路由与状态联动**：
   - 左侧侧边栏通过 `SubscriptionsController` 渲染数据树，并将点击事件传递给 `TimelineController`。
   - 修改 `TimelineController`，使其能够支持 `selectedCategory` 与 `selectedFeedId` 的响应式过滤更新。实现侧边栏点击后，中间时间线列表立刻精准切换内容的单页无缝体验。

3. **原生快捷键补齐**：
   - 在 `MainPage` 外层增加 `Focus` 监听键盘事件。
   - 实现 `Cmd + W` 隐藏当前窗口（调用 `windowManager.hide()`）。
   - 实现 `Cmd + Q` 彻底退出应用程序（调用 `exit(0)`）。

4. **macOS Dock 动态原生角标**：
   - 在 `macos/Runner/AppDelegate.swift` 中通过 `MethodChannel("com.autofolo/badge")` 接管了原生层的 `NSApp.dockTile.badgeLabel` 渲染逻辑。
   - 使得未读文章的数字可以实时且精准地以红底白字显示在 Mac 底部的 Dock 栏图标右上角。

5. **独立的高清应用图标**：
   - 通过原生 `sips` 脚本对原始 Folo 高清图标进行自动重采样，生成了符合 macOS 标准的全尺寸 `.appiconset` 集合，完全替代了 Flutter 的默认模板图标。

### 75.3 关键设计讨论与决策留档
在本次迭代中，通过与用户的讨论，明确了以下几项关键的设计理念和未来规划：
1. **摒弃侧边导航栏，回归三栏沉浸布局**：
   - 用户明确指出原始 folo 项目的界面设计非常优秀，因此决定放弃初版使用 `NavigationRail`（带 3 个按钮）的生硬方案。
   - 最终确立了将“订阅源选择”直接做到最左侧的模式，当点击空白时不进行任何选择，最大程度复刻了桌面端原汁原味的体验。
2. **关于“已读”行为的交互讨论**：
   - 用户不希望像原始 folo 工程那样“点击列表项就自动标为已读”，而是希望保留类似 Android 端那种“需要明确的确认步骤”。
   - **已决定的方案**：一方面在详情页保留明确的“已读”按钮，另一方面为 macOS 专门增加了快捷键（计划使用 `M` 键作为标为已读的快捷键，后续实现）。
   - **状态刷新逻辑**：讨论了阅读后文章是否立刻消失的问题。目前保持现状，后续可以结合状态管理平滑处理列表内的隐藏动画。
3. **未来的键盘导航扩展**：
   - 用户提出未来可以通过设置其他快捷键（如左右方向键）来阅读上一篇/下一篇，以此来对标安卓端的左右滑动切页手势。该需求已记录，留待后续版本实现。

---

## 76. macOS 适配复盘与当前权威上下文（2026-06-01）

> 重要：第 75 节是早期记录，其中关于 `Cmd+W/Cmd+Q` 和毛玻璃的实现描述已经不完全准确。后续接手请以本节为准。
> 2026-06-03 校准：本节的“当前工作目录/当前分支/不要改 `~/dev` 主工作区”等约束，是 2026-06-01 当时 macOS 适配辅助 worktree 的历史语境；当前主工作区请结合第 81 节 worktree 清理记录和后续发布记录判断，不要机械套用本节路径约束。

### 76.1 工作区与分支约束

- 当前工作目录：`<historical-macos-worktree>`
- 当前分支：`migrate-software-macos-adaptation`
- 用户明确要求：所有 macOS 适配、同步和实验都不要改动核心工作区 `~/dev` 那边。
- 本轮操作均在当前 worktree 内完成，没有直接操作 `~/dev` 工作区。
- 曾从另一个 worktree `<historical-codex-worktree>` 同步 7 个提交到当前分支顶部，避免 macOS 适配与 Android/通用功能更新长期分叉：
  - `83f6b7a Fix read sync cleanup and readability queue dedupe`
  - `a4b5777 Retry chunked translations without partial results`
  - `ea8f494 Add adaptive virtual rendering for long articles`
  - `7e05db4 Add settings task center`
  - `d5f67f3 Polish task center status UI`
  - `ce869f3 Add AI failure detail retries`
  - `8e41518 Improve chunk translation failure details`
- 同步前创建过备份 stash：`stash@{0}: On migrate-software-macos-adaptation: pre-sync-macos-adaptation`。如确认当前工作无误，可后续手动清理；当前不要随意删除。

### 76.2 用户目标与设计参考

用户当前主线目标是 macOS 端精细化适配，方向是参考 `reference/Folo` 的桌面端视觉和交互，而不是照搬内部实现。核心要求：

1. macOS 设计不要破坏现有移动端设计。
2. 左侧订阅源的 category/folder 必须支持折叠；整条订阅栏是否可收起是附带能力。
3. 关闭窗口应隐藏窗口但保留 app 运行；`Cmd+Q` 才是真正退出。
4. macOS 三栏设计参考 Folo 原生桌面工程：左侧订阅栏、中间列表、右侧阅读/详情。
5. Folo 左侧订阅栏的材质感、毛玻璃、视觉密度可以参考，但内部业务逻辑继续用本项目自己的 GetX/Hive/Folo API 逻辑。
6. 审核页是高频入口，任务中心只是低频诊断入口，不能替代审核页。

### 76.3 当前 macOS 主布局

核心文件：

- `lib/pages/main/main_page.dart`
- `lib/pages/main/widgets/macos_sidebar.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/timeline/filter_review_page.dart`

当前形态：

- 移动端继续使用 AppBar + bottom `NavigationBar`，对应 `_mobilePages`：
  - `TimelinePage(showAppBar: false)`
  - `SubscriptionsPage()`
  - `SettingsPage(showAppBar: false)`
- macOS 走单独分支，不使用移动端底导，对应三栏布局：
  - 左侧：`MacOSSidebar` / `MacOSCollapsedSidebar`
  - 中间/右侧主内容：`IndexedStack`
  - macOS pages：
    - `TimelinePage(showAppBar: false, onOpenFilterReview: () => _onDestinationSelected(1))`
    - `FilterReviewPage()`
    - `SettingsPage(showAppBar: false)`
- `TimelinePage` 在 macOS 内部继续拆成“列表栏 + 阅读栏”，因此整体视觉是：
  - 最左侧订阅/导航栏
  - 中间文章列表
  - 右侧文章内容
- macOS 主内容切换已从淡入淡出改为直接 `IndexedStack`，避免点侧栏“垃圾拦截”等页面时出现两页叠加的过渡感。

### 76.4 左侧订阅栏与折叠逻辑

`lib/pages/main/widgets/macos_sidebar.dart` 当前新增并承载 macOS 左栏。

已实现能力：

- 顶部 `Auto Folo` 标题和收起按钮。
- 左栏可整体收起为窄 rail，窄 rail 包含展开、全部文章、垃圾拦截、设置。
- 全部文章、垃圾拦截、设置作为固定入口。
- 订阅源按照 `SubscriptionsController.filteredNodes` 渲染 view/category/feed 树。
- category/folder 支持折叠：
  - key 形如 `cat:${viewNode.name}:${category.name}`
  - 状态走 `SubscriptionsController.isExpanded/setExpanded`
  - 搜索时或当前选中 feed 属于该 category 时强制展开
  - category row 的 chevron 可展开/收起，双击 row 也可切换
- feed row 显示 favicon、标题、未读角标。
- category 和 feed 的未读数来自 `SubscriptionsController.unreadForCategory/unreadFor`。

### 76.5 审核页入口与桌面交互

问题背景：

- 早期实现中，左侧栏点击“垃圾拦截”会进入 `IndexedStack` 里的审核 pane；
- 时间线顶部的“AI 智能过滤”卡片仍然 `Get.toNamed(Routes.filterReview)` push 单独页面；
- 用户指出这造成两个审核页面入口不一致，而且从卡片进入的独立页面没有桌面语境下的返回方式。

当前决策与实现：

- macOS 只保留“侧边栏审核 pane”这一种桌面审核 surface。
- 移动端继续保留原有路由跳转，不影响手机端。
- `TimelinePage` 新增 `onOpenFilterReview` 回调：
  - macOS 且回调存在时，点击过滤卡片只调用回调切到 `_currentIndex=1`
  - 否则仍 `Get.toNamed(Routes.filterReview)`
- `MainPage._macPages` 通过 `onOpenFilterReview: () => _onDestinationSelected(1)` 合流入口。

`FilterReviewPage` macOS 端也已改为桌面专用布局：

- 移动端仍保留原来的 `Scaffold + AppBar + Dismissible + ArticleCard`。
- macOS 不再把移动端页面嵌进桌面分栏。
- macOS 审核页当前是：
  - 左侧固定宽度审核队列（约 392px）
  - 右侧文章预览 `ArticlePageView(isSplitView: true)`
  - 顶部 header 显示“垃圾拦截”和待处理/判定中数量
  - 行内显示标题、来源、过滤原因
  - 右侧两个按钮：保留、移除
- 审核按钮 tooltip 不能上下弹出，否则会遮挡另一个按钮。当前已改为自定义 `_SideTooltip`，悬停时优先在按钮右侧显示；空间不够时才回退到左侧。

### 76.6 macOS 关闭行为与菜单

当前权威实现不再依赖 Flutter 层用 `Focus` 抢 `Cmd+W/Cmd+Q`。

原生侧文件：

- `macos/Runner/AppDelegate.swift`
- `macos/Runner/Base.lproj/MainMenu.xib`

已实现：

- `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`：最后一个窗口关闭后 app 不退出。
- `AppDelegate` 实现 `NSWindowDelegate`。
- `windowShouldClose`：
  - 如果正在 `Cmd+Q` / terminate，则允许关闭并退出；
  - 否则 `sender.orderOut(nil)` 隐藏窗口，返回 `false`。
- `applicationShouldHandleReopen`：点击 Dock 图标且没有可见窗口时，重新显示主窗口。
- `MainMenu.xib` 里 Window 菜单新增 `Close`，快捷键 `Cmd+W`，selector 为 `performClose:`。
- App 菜单原有 `Quit` 仍走 `terminate:`，快捷键 `Cmd+Q`，两者语义已经区分。

### 76.7 Dock 角标与 AppIcon

Dock 未读角标：

- Dart 侧：`lib/common/widgets/app_badger.dart`
- macOS 原生侧：`macos/Runner/AppDelegate.swift`
- `TimelineController._updateAppBadge()` 中对 macOS 单独分支：
  - macOS 固定显示所有未读文章数量；
  - 不再受设置页原来的 `badge_strategy`（关闭/只红点/数字）影响；
  - 未读数为 0 时清除角标。
- Android 仍保留原来的 badge strategy，不受 macOS 改动影响。

AppIcon：

- 用户发现 macOS 图标和 Android 图标不一致。
- Android 使用 `android/app/src/main/res/mipmap-*/ic_launcher.png`，视觉上有右下角翻页和蓝色元素。
- macOS 初始 `app_icon_1024.png` 只是橙底白色 Folo 标志。
- 已用项目内 `assets/icon.png` 作为源图，重新生成 macOS `AppIcon.appiconset` 全尺寸：
  - `app_icon_16.png`
  - `app_icon_32.png`
  - `app_icon_64.png`
  - `app_icon_128.png`
  - `app_icon_256.png`
  - `app_icon_512.png`
  - `app_icon_1024.png`
- 若 `flutter run -d macos` 仍显示旧图，优先判断为 macOS Dock/LaunchServices 图标缓存；构建产物 `Contents/Resources/AppIcon.icns` 已经验证为新图。

### 76.8 macOS 左栏毛玻璃问题（未解决，后续重点）

这是当前最重要的未解决 UI 问题之一。

讨论与尝试：

1. Flutter `BackdropFilter` 只能模糊 Flutter 自己绘制在其背后的内容，不能真正透出 macOS 桌面/后方窗口。
2. Folo 桌面端是 Electron，它在 macOS 窗口配置中使用：
   - `titleBarStyle: "hiddenInset"`
   - `vibrancy: ...`
   - `visualEffectState: ...`
   - `transparent: true`
   - renderer 层使用 `WindowUnderBlur` 和 `bg-material-*` 轻材质 token
3. 我们尝试在 Flutter 左栏加更强 `BackdropFilter` 和灰色 tint，结果只是大块灰色，不是用户想要的透明/透背效果。
4. 随后尝试在 `macos/Runner/MainFlutterWindow.swift` 插入 `NSVisualEffectView(material: .sidebar, blendingMode: .behindWindow)`，并设置窗口透明：
   - `self.isOpaque = false`
   - `self.backgroundColor = NSColor.clear`
   - `self.titlebarAppearsTransparent = true`
   - `self.styleMask.insert(.fullSizeContentView)`
   - 将 `NSVisualEffectView` 放到 `FlutterViewController.view` 下层
5. 但用户实测左侧仍是黑色，看不到透明效果。

当前状态：

- 该问题已明确记录，暂时不要继续盲改。
- 后续需要系统排查：
  - Flutter macOS view 是否仍以不透明 layer 覆盖 `NSVisualEffectView`
  - `NSVisualEffectView` 是否插入在正确的 native view 层级
  - `window_manager` 的 `backgroundColor: Colors.transparent` 是否与 `NSWindow` 透明设置冲突
  - 是否需要改 `FlutterViewController.backgroundColor` / `FlutterView` layer opacity
  - 是否需要把 `NSVisualEffectView` 作为 `contentView` 的底层 sibling，而不是加在 Flutter view 内部
  - `NSVisualEffectView.material` 是否应换成 `.underWindowBackground`、`.hudWindow`、`.menu`、`.popover` 等
  - 是否需要只让 Flutter 左侧区域完全透明，右侧内容区用实色容器遮住 native vibrancy
- 用户说“先记录这个问题，晚点再考虑解决”，因此后续 agent 不要在没有明确要求时继续消耗时间。

### 76.9 macOS 构建日志与 warning 处理

用户贴过 `flutter clean && flutter run -d macos --release` 日志，结论：

- 构建成功：`✓ Built build/macos/Build/Products/Release/autofolo.app`
- 不是源码错误。

已处理：

- `dynamic_color` pod 报 `MACOSX_DEPLOYMENT_TARGET = 10.11`，但当前工具链支持 10.13+。
- 已在 `macos/Podfile` 的 `post_install` 中给所有 pod target 强制：
  - `config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.15'`
- 重新 `flutter build macos --debug` 后该 warning 消失。

仍可忽略/暂不处理：

- `27 packages have newer versions incompatible with dependency constraints`
  - 只是依赖有新版本。不要顺手全升；如果要升级，单独开依赖升级任务并做回归。
- `video_player_avfoundation` 的 warning：
  - `AVKeyValueStatus is deprecated`
  - `createArgsCodec() has different optionality than expected by protocol`
  - 这是第三方插件在新 Xcode/macOS SDK 下的 warning，不影响构建运行。
  - 不建议修改 `.pub-cache`，等待插件更新或后续专门升级 video_player 相关依赖。
- `Run script build phase 'Run Script' will be run during every build...`
  - Flutter/Xcode 常见脚本阶段 warning，不影响运行。
- `Running with merged UI and platform thread. Experimental.`
  - Flutter macOS 运行时提示，不是错误。
- `Waiting for another flutter command to release the startup lock...`
  - Flutter 正在等待另一个命令释放锁。只要没有长期卡住即可。
- 如出现 `build.db database is locked`：
  - 说明同一 worktree 的 Xcode build database 被另一个 `flutter run/build` 或 `xcodebuild/SWBBuildService` 持有；
  - 先 `Ctrl+C` 停掉旧命令；
  - 必要时查 `lsof build/macos/Build/Intermediates.noindex/XCBuildData/build.db`；
  - 不要误判为代码错误。

### 76.10 当前验证记录

本轮 macOS 适配过程中反复验证过：

- `dart analyze lib test`：通过
- `flutter test test/widget_test.dart`：通过
- `flutter build macos --debug`：通过
- `flutter run -d macos --release`：用户本地运行成功，release app 可启动

注意：

- 如果正在运行旧 app，重建后需要退出旧 app 再重新运行，UI 才会更新。
- macOS Dock 图标可能受系统缓存影响，产物内 `AppIcon.icns` 才是判断资源是否正确的第一依据。

### 76.11 当前改动涉及的主要文件

macOS 原生：

- `macos/Runner/AppDelegate.swift`
- `macos/Runner/MainFlutterWindow.swift`
- `macos/Runner/Base.lproj/MainMenu.xib`
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/*`
- `macos/Podfile`
- 以及 Flutter 自动生成/补齐的 macOS 工程文件。

Flutter 侧：

- `lib/main.dart`
- `lib/pages/main/main_page.dart`
- `lib/pages/main/widgets/macos_sidebar.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/timeline/filter_review_page.dart`
- `lib/pages/widgets/article_card.dart`
- `lib/pages/article/article_page.dart`
- `lib/pages/article/widgets/image_gallery_page.dart`
- `test/widget_test.dart`

### 76.12 后续接手建议

1. 若继续 macOS 左栏毛玻璃，先从原生 view 层级做最小实验，不要继续只调 Flutter `BackdropFilter` 颜色。
2. 若整理代码质量，优先把 macOS-only UI 封装边界再收紧，避免 `Platform.isMacOS` 分支污染移动端。
3. 若要提交，请先确认哪些 staged 改动来自同步/历史，哪些来自本轮 macOS 适配；当前 worktree 存在 staged + unstaged 混合状态。
4. 不要随意清理 `stash@{0}`，除非用户确认当前状态已安全。
5. 不要改 `~/dev` 主工作区。

## 77. macOS 侧边栏与相关页面全面适配（本轮对话完整记录）

> **关键前提**：本轮对话中用户始终在指 macOS 端，对话初期提到的"订阅源页面""对齐""按钮缺失"等均指 macOS 侧边栏（`macos_sidebar.dart`），而非 Android 的 `subscriptions_page.dart`。Android 端本轮零改动，所有修改均已回退。

### 77.1 用户原始诉求（按时间线）

1. 订阅源页面粗糙，对齐不对，缺少自动拉取全文 / 自动翻译按钮
2. "最左边那一列"点按有延迟
3. "全部文章"右侧气泡数字不对（过滤了 AI 拦截文章）
4. 文章详情页里的 Feed 胶囊点击后弹出全屏新页面，体验突兀
5. Feed 详情页（`_MacFeedHeader`）缺少自动拉取/翻译 toggle
6. 要求所有没能适配 macOS 的地方全部适配

### 77.2 改动总览

| 文件 | 改动项 | 原因 |
|------|--------|------|
| `lib/pages/main/widgets/macos_sidebar.dart` | 4 项 | 核心改动 |
| `lib/pages/timeline/timeline_page.dart` | 2 项 | 上下文 AppBar + FeedToggleIcon |
| `lib/pages/article/article_page.dart` | 1 项 | Feed 胶囊改为原地过滤 |
| `lib/pages/feed_detail/feed_detail_page.dart` | 1 项 | `_MacFeedHeader` 补 toggle |
| `lib/pages/settings/settings_page.dart` | 1 项 | 底部死空白 |
| `lib/pages/subscriptions/subscriptions_page.dart` | 0 | 已 `git checkout` 回退 |

---

### 77.3 改动详情

#### 77.3.1 `macos_sidebar.dart` — 4 项

**a) 点按延迟修复：删除 `_CategoryItem` 的 `onDoubleTap`**

`InkWell` 同时有 `onTap` 和 `onDoubleTap` 时，Flutter 必须等 ~300ms 确认无第二击才能触发 `onTap`。展开/折叠已有独立的 chevron `IconButton`，`onDoubleTap` 完全多余。删除后点按即时响应。

```dart
// 改前：InkWell(onTap: onTap, onDoubleTap: onToggle, ...)
// 改后：InkWell(onTap: onTap, ...)
```

**b) 侧边栏 Feed 项新增自动拉取全文 / 自动翻译 toggle 图标**

`_SidebarItem` 新增 `Widget? trailing` 可选参数，Feed 项传入两个 toggle 图标：

- `_FeedAutoReadabilityIcon` — `Icons.article` / `article_outlined`，控制 `FeedReadabilitySettingsService`
- `_FeedAutoTranslateIcon` — `Icons.translate` / `translate_outlined`，控制 `FeedTranslationSettingsService`

每个是独立的 `StatefulWidget`，`initState` 读 Hive 当前值，点击写入 Hive + `setState`。开启态实心 + `cs.primary`，关闭态空心 + 30% 透明。

**c) "全部文章"气泡数字修正**

```dart
// 改前：timelineController.allArticles.where((a) => !a.isRead && !a.isRejectedByAi).length
// 改后：timelineController.allArticles.where((a) => !a.isRead).length
```

不再过滤 AI 拦截文章，显示全部未读数。

**d) ScrollConfiguration 尝试与回退**

曾尝试用 `ScrollConfiguration(dragDevices: {PointerDeviceKind.touch})` 消除 `ListView` 内 trackpad 点击的 scroll arena 延迟。但导致触控板一指拖拽滚动失效（两指滑动走 `PointerScrollEvent` 不受影响）。已回退。主要延迟来源 `onDoubleTap` 删除后，剩余延迟可接受。

---

#### 77.3.2 `timeline_page.dart` — 2 项

**a) macOS AppBar 动态上下文**

新增 `_MacTimelineAppBar` 组件（`PreferredSizeWidget`），替换原来写死"时间线"的 AppBar：

| 状态 | 标题 | 副标题 | 右侧操作 |
|------|------|--------|----------|
| 未选中 | "时间线" | — | 🔄 同步 |
| 选中 Feed | Feed 标题 | "N 篇未读 · M 篇当前列表" | 📄 🌐 ✕ 🔄 |
| 选中分类 | 分类名 | "N 篇未读" | ✕ 🔄 |

Feed 标题从 `SubscriptionsController.allFeeds` 查找；toggle 按钮通过 `_FeedToggleIcon`（带本地 `StatefulWidget` 状态）实现。

**b) `_FeedToggleIcon` 组件**

macOS 时间线 AppBar 内的小型开关图标。与侧边栏的 `_FeedAutoReadabilityIcon` 不同，这个接收 `enabled` 初值和 `onToggle` 回调，内部用 `StatefulWidget` 维护本地开关态，`didUpdateWidget` 同步外部变化。

---

#### 77.3.3 `article_page.dart` — 1 项

**Feed 胶囊改为原地过滤（macOS）**

```dart
// 改前：统一 Get.toNamed(Routes.feedDetail, ...)
// 改后：
if (Platform.isMacOS) {
  final tc = Get.find<TimelineController>();
  tc.selectedArticle.value = null;   // 关闭右面板
  tc.selectedCategory.value = null;
  tc.selectedFeedId.value = article.feedId;  // 原地过滤时间线
  return;
}
Get.toNamed(Routes.feedDetail, ...);  // 移动端不变
```

**设计决策**：macOS 上不跳全屏页，而是关闭当前文章面板 + 在时间线中过滤该 Feed。与侧边栏点 Feed 行为一致，统一为三栏布局内的原地切换。移动端仍走 `FeedDetailPage`。

---

#### 77.3.4 `feed_detail_page.dart` — 1 项

**`_MacFeedHeader` 新增自动拉取/翻译 toggle**

`FeedDetailPage` 的 macOS 布局（`_buildMacOSLayout`）头部 `_MacFeedHeader` 原本只有：返回按钮、头像、标题、未读统计、读筛选下拉、同步按钮。缺少自动拉取全文和自动翻译 toggle（移动端 SliverAppBar 有）。

在同步按钮后新增两个 `IconButton`（`Obx` 响应），使用 `FeedReadabilitySettingsService.toggleAutoReadability` 和 `FeedTranslationSettingsService.toggleAutoTranslate`，与 `controller.refreshAutoReadabilityStatus()` / `refreshAutoTranslateStatus()` 联动。

---

#### 77.3.5 `settings_page.dart` — 1 项

**macOS 底部死空白修复**

```dart
// 改前：MediaQuery.paddingOf(context).bottom + kBottomNavigationBarHeight + 32
// 改后：MediaQuery.paddingOf(context).bottom + (Platform.isMacOS ? 0 : kBottomNavigationBarHeight) + 32
```

macOS 没有底部导航栏，`kBottomNavigationBarHeight`（~80px）会导致底部大量空白。加 `Platform.isMacOS` 守卫。

---

### 77.4 设计决策与讨论过程

#### 决策 1：侧边栏 Feed 点击 vs FeedDetailPage

**问题**：侧边栏点 Feed → 设 `selectedFeedId` 原地过滤；文章胶囊点 → `Get.toNamed(FeedDetailPage)` 全屏跳转。两条路径体验不一致。

**讨论**：全屏新页面破坏三栏布局的连贯性，用户明确反对。

**方案**：统一为原地过滤——时间线 AppBar 动态显示上下文（Feed 名 + 统计 + toggle 开关 + 清除按钮）。右侧文章面板自动关闭，用户回到过滤后的时间线。

#### 决策 2：toggle 按钮位置

- **侧边栏**：Feed 项行内右侧（`_SidebarItem.trailing`），14px 小图标，紧贴未读数字前面
- **FeedDetailPage 头部**：`_MacFeedHeader` 的 `actions` 区域，20px 标准图标
- **时间线 AppBar**：选中 Feed 后出现在 `actions` 区域，20px 标准图标

三处均使用 `FeedReadabilitySettingsService` / `FeedTranslationSettingsService` 读写 Hive，状态通过 `StatefulWidget` 本地维护，无需全局状态管理。

#### 决策 3：ScrollConfiguration dragDevices

尝试用 `dragDevices: {PointerDeviceKind.touch}` 消除 scroll arena 点按延迟 → 导致触控板一指拖拽滚动失效 → 回退。结论：`onDoubleTap` 才是延迟主因，删掉后无需额外处理 scroll arena。

---

### 77.5 技术要点

- **`_FeedToggleIcon` vs `_FeedAutoReadabilityIcon`**：前者在 `timeline_page.dart`（接收外部 `enabled` + `onToggle`），后者在 `macos_sidebar.dart`（内部直接读 Hive）。两者不能互换——侧边栏图标需要在 Feed 列表上下文中独立工作，时间线 AppBar 图标需要响应 `selectedFeedId` 变化。
- **`SubscriptionsController` 在 macOS 上的注册**：`main_page.dart` 中 `if (Platform.isMacOS) { Get.put(SubscriptionsController()); }` 确保 macOS 可用 `Get.find<SubscriptionsController>()`。
- **macOS 三栏布局**：`_macPages = [TimelinePage, FilterReviewPage, SettingsPage]`（`IndexedStack`），`SubscriptionsPage` 不在其中，订阅树直接渲染在侧边栏内。
- **`article_page.dart` 的 `openSource()`**：在 macOS split view 中，文章是 `ArticlePageView(isSplitView: true)` 内联在右侧面板，不是 push route。`Get.back()` 不适用，改用 `tc.selectedArticle.value = null` 清空右面板。

### 77.6 当前验证状态

- `dart analyze lib/`：零 error 零 warning（仅 2 个预存 info）
- 改动文件均在 git working tree 中（未 commit）
- Android `subscriptions_page.dart` 已 `git checkout` 回退至原始状态

### 77.7 已回退的早期移动端订阅页尝试（历史参考）

注意：这段记录的是早期对移动端 `SubscriptionsPage` 的尝试；根据本节开头的关键前提，相关代码已回退，仅保留为避免后续重复踩坑。

当时用户反馈订阅源页面（`SubscriptionsPage`）：
1. 对齐混乱——View / Category / Feed 三级缩进关系不清晰
2. 缺少"自动拉取全文"和"自动翻译"两个按源开关按钮
3. 希望视觉风格与主页面统一

### 77.8 当时尝试的代码改动（后续已回退，`lib/pages/subscriptions/subscriptions_page.dart`）

| 改动项 | 变更 |
|--------|------|
| **Feed 卡片边距** | `margin: only(left:48, right:16, bottom:8)` → `only(left:44, right:16, top:4, bottom:4)` |
| **Category 缩进** | `padding: LTRB(32, ...)` → `LTRB(40, ...)` |
| **Category chevron** | 裸 Icon → 包裹在圆形背景 `Container`（与 View 层 chevron 统一），icon 也换成 `Icons.chevron_right` |
| **展开动画** | `AnimatedCrossFade` → `AnimatedSize`（View 和 Category 两层的展开/折叠动画都换了） |
| **Feed 卡片类型** | `StatelessWidget` → `StatefulWidget`（需要本地维护 toggle 状态） |
| **新增按钮** | 每张 Feed 卡片右侧增加两个 `_FeedToggleButton`（`article_outlined`/`translate_outlined`），分别控制 `FeedReadabilitySettingsService` 和 `FeedTranslationSettingsService` |
| **新增组件** | `_FeedToggleButton` — 小型 toggle icon button，32×32 tap target，关闭态空心灰色 35% 透明度，开启态实心主色 |

### 77.9 当时问题：按钮在运行时不可见

**症状**：用户执行 `flutter clean && flutter pub get && flutter run` 后，在订阅源页面展开到 Feed 卡片时，只能看到未读数字，看不到两个 toggle 按钮。

**已验证的事实**：
- `dart analyze lib/` 零错误
- `git diff` 确认改动在磁盘上
- 代码中只有一处 `_FeedCard` 定义（`lib/pages/subscriptions/subscriptions_page.dart:641`）
- `_FeedCard` 的 `build()` 中 toggle 按钮在 `Expanded(Column(...))` 之后、`if (hasUnread) ...[badge]` 之前——如果未读徽章能渲染，按钮应该也能渲染

**未验证的假设 / 可排查方向**：

1. **`Obx` 重建与 StatefulWidget 交互**：`_FeedCardState.build()` 的方法体被 `Obx(() { ... })` 包裹。`Obx` 内部读取 `_controller.unreadFor(_feed.feedId)` 建立响应式依赖。如果 `_unreadCounts` RxMap 频繁触发重建，可能导致 widget 子树被替换时 state 丢失。可尝试将 `Obx` 范围缩小到只包裹未读徽章部分，而不是整个卡片。

2. **`AnimatedSize` 内 StatefulWidget 的生命周期**：`_FeedCard` 实例在 `_CategorySection` 的 `AnimatedSize` 条件分支内（`_expanded ? [卡片列表] : SizedBox`）。当 `_expanded` 从 `false` → `true` 时 Flutter 创建新 element，`initState` 运行；但若 `_CategorySection` 自身被重建（比如搜索过滤导致 `filteredNodes` 变化），element 可能被复用或重建，状态可能丢失。

3. **Icon 字体不可用**：`Icons.article_outlined` 和 `Icons.translate_outlined` 在某些旧版 Material Icons 字体中可能不存在，导致图标渲染为空。虽然 Flutter 3.x 应该支持，但可尝试替换为更基础的 icon（如 `Icons.article` / `Icons.translate` 也作为 fallback）来排除。

4. **`colorscheme` 参数传递问题**：`_FeedToggleButton` 接收 `ColorScheme colorScheme`。在 `_FeedCardState.build()` 中传入的是局部变量 `cs` = `Theme.of(context).colorScheme`。这本身没问题，但可加 `debugPrint` 确认 `build()` 确实被调用。

5. **编译缓存残留**：虽然用户执行了 `flutter clean`，但 Android 的 `app/build/` 或 Gradle 缓存可能未被完全清除。可尝试：
   ```bash
   flutter clean
   rm -rf android/app/build
   rm -rf android/.gradle
   flutter pub get
   flutter run
   ```

### 77.10 当时建议的调试步骤（仅历史参考）

1. **先确认代码能跑到**：在 `_FeedCardState.build()` 第一行加 `debugPrint('[FeedCard] build: ${_feed.title}, readability=$_autoReadability, translate=$_autoTranslate')`，看日志是否输出。
2. **排除 Icon 字体问题**：把 `_FeedToggleButton` 的 icon 暂时换成 `Icons.star` / `Icons.star_border`（最基础 icon），看是否出现。
3. **排除布局问题**：把两个 `_FeedToggleButton` 替换为临时的红色 `Container(width:24, height:24, color:Colors.red)`，看红色方块是否出现。
4. **缩小 Obx 范围测试**：把 `Obx` 从包裹整个卡片改为仅包裹未读徽章，看按钮是否出现。
5. **如果不生效**：考虑放弃 `StatefulWidget` 方案，改为在 `SubscriptionsController` 中用 RxMap 管理 toggle 状态，`_FeedCard` 退回 `StatelessWidget` + `Obx` 读取 controller 的响应式状态。

## 78. 快捷键、同步反馈、品牌统一、审核页已读同步（2026-06-01）

### 78.1 用户本次反馈的原始问题

1. macOS 分栏阅读里，`←` / `→` 方向键没有稳定切换文章，而是会框选/聚焦不同的图标元素。
2. `M` 标已读必须先点文章卡片、再点文章正文才能生效；快捷键依赖焦点，体验不符合预期。
3. 时间线同步按钮点击后没有动画或确认感。
4. README 与当前功能不一致，需要同步更新，最好把图标也放上去。
5. 为了统一性，软件展示名应考虑改为 `Auto Folo`；工程目录名是否也应修改需要给出建议。
6. 进一步反馈：其他设备上已标为已读的文章，时间线未读列表已经能挪出，但“垃圾拦截/审核页”仍然显示这些文章；气泡计数已经减少，但审核页列表和“xx 篇待处理”没有同步变化。

### 78.2 已做修改

#### 78.2.1 macOS 阅读快捷键修复

文件：`lib/pages/article/article_page.dart`

- 在 `ArticlePageView` 的 macOS 分栏场景中增加 `HardwareKeyboard.instance.addHandler`。
- 快捷键只在 `widget.isSplitView == true` 时启用全局硬件键盘处理，避免影响普通文章页或移动端。
- 处理逻辑：
  - `←` 调用 `widget.onPrevious`
  - `→` 调用 `widget.onNext`
  - `M` 在未更新中时切换已读/未读
  - `Esc` 关闭当前文章
- 忽略带 `Alt` / `Control` / `Meta` 的组合键，避免吞掉系统或应用菜单快捷键。
- 保留原来的 `Focus.onKeyEvent` 作为局部兜底，但真正解决焦点被正文、按钮、图标拿走的问题依赖全局 handler。

设计原因：

- 原实现把快捷键挂在文章页的 `Focus` 上，正文里的 `SelectionArea`、工具栏按钮和其他可聚焦元素会抢走焦点。
- 用户看到的“方向键框选不同图标元素”，本质是 Flutter 焦点遍历先消费了方向键。
- 使用硬件键盘 handler 可以让文章分栏处于打开状态时始终获得这些阅读快捷键，不再要求用户点中正文。

#### 78.2.2 macOS 同步按钮反馈

文件：`lib/pages/timeline/timeline_page.dart`

- 将 `_MacTimelineAppBar` 里的同步 `IconButton` 替换为 `_MacSyncButton`。
- `_MacSyncButton` 使用 `AnimationController` + `RotationTransition`，点击后图标旋转并显示“同步中”tooltip。
- 同步期间按钮禁用，避免重复触发。
- 增加 450ms 最短反馈窗口：即使同步很快返回，用户也能看到明确点击确认感。

#### 78.2.3 品牌名统一为 Auto Folo

涉及文件：

- `lib/common/constants/constants.dart`：`AppConstants.appName = 'Auto Folo'`
- `lib/main.dart`：入口类由 `FoloReaderApp` 改为 `AutoFoloApp`
- `test/widget_test.dart`：同步测试类名
- `lib/http/init.dart`：`X-App-Name` 改为 `Auto Folo`，`X-App-Version` 改为 `1.1.0`
- `lib/pages/settings/settings_page.dart`：关于页显示 `Auto Folo v1.1.0`，说明改为支持 Android 和 macOS
- `macos/Runner/Configs/AppInfo.xcconfig`：`PRODUCT_NAME = Auto Folo`
- `macos/Runner.xcodeproj/project.pbxproj` 与 `Runner.xcscheme`：macOS 产物名同步为 `Auto Folo.app`

未改动但需要理解：

- `pubspec.yaml` 的 package name 仍是 `autofolo`。这是 Dart 包名，不能有空格，保持不变是正确的。
- Bundle id / method channel 仍保留 `com.folo.autofolo`，避免破坏已有本地数据、平台通道和已安装应用升级路径。
- HTTP header 的 `X-App-Platform` 目前仍是 `mobile/android`。这是既有行为，本次没有改平台识别逻辑；如果未来要严格区分 macOS，需要单独评估服务端兼容性。

#### 78.2.4 README 更新

文件：`README.md`

- 标题改为 `Auto Folo — Folo RSS 信息流阅读器`。
- 顶部加入 `assets/icon.png` 图标。
- 移除 Android-only 描述，改为支持 Android 和 macOS。
- 功能矩阵补充 macOS 分栏阅读、桌面快捷键和同步反馈。
- 快速开始补充 `flutter run -d macos`。

#### 78.2.5 审核页跟随其他设备已读状态

文件：`lib/pages/timeline/filter_review_page.dart`

- 审核页原先只在打开时 `_loadArticles()` 一次，并只监听 `AutoFilterWorker.onRejected` 新增拦截项。
- 时间线同步会更新 `TimelineController.filterCount`，所以气泡计数能减少；但审核页自己的 `_articles` 没有重新对齐，导致页面列表和“xx 篇待处理”仍显示旧数据。
- 已增加两个 GetX worker：
  - `_articleStateWorker` 监听 `ArticleStateNotifier.version`，单篇文章状态变化时走 `_syncArticleFromDb(entryId)`。
  - `_filterCountWorker` 监听 `TimelineController.filterCount`，全量同步导致计数变化时重新 `_loadArticles()`。
- `_syncArticleFromDb` 会从 Hive 本地库读取该文章：
  - `isRejectedByAi && !isRead` 才保留在审核列表。
  - 已读、取消拦截、已删除或不再符合条件时，从 `_articles` 移除。
  - 如果右侧正在预览的文章被移除，`_selectedArticle` 自动清空。
- 因为移动端和 macOS 的待处理文案都基于 `_articles.length`，列表修剪后“xx 篇待处理”会同步变化。

设计原因：

- 不应该只在 UI 层隐藏一份旧列表；审核页应以 `LocalArticleDbService.readAllArticles()` / Hive 中的最终文章状态为准。
- 监听 `ArticleStateNotifier` 覆盖用户手动标已读、保留、拒绝等单篇变化。
- 监听 `filterCount` 覆盖“其他设备已读同步”这种批量落库变化，因为 `_applyUnreadSnapshot` / `_refreshRecentReadWindow` 并不逐篇发 `ArticleStateNotifier.tick`。

### 78.3 验证结果

已运行并通过：

```bash
flutter analyze
flutter test
flutter build macos --debug
```

macOS debug 构建产物确认：`build/macos/Build/Products/Debug/Auto Folo.app`。

注意：第一次直接跑 `dart analyze` 会因为 Flutter package URI 无法解析产生大量误报；此项目应以 `flutter analyze` 为准。

### 78.4 关于工程目录名的建议

- 不建议在当前 Codex worktree 内直接重命名 `<historical-codex-worktree>`，这会影响当前会话和 Git worktree 路径。
- 如果主仓库要改名，建议仓库/clone 目录改为 `auto-folo`，比 `autofolo-mobile` 更符合当前 Android + macOS 双端定位。
- 不建议把 Dart package name 改成 `auto_folo`，除非愿意承担 import 路径、测试、CI、发布脚本和原生工程引用的额外迁移成本；当前 `package:autofolo/...` 是稳定内部标识。

### 78.5 需要在 main 分支/主工程侧同步的事项

如果这次改动是在临时 worktree 中完成，合入 main 时请逐项确认：

1. 合入 `lib/pages/article/article_page.dart` 的 macOS 分栏硬件键盘 handler。
2. 合入 `lib/pages/timeline/timeline_page.dart` 的 `_MacSyncButton`，确保同步按钮有旋转反馈。
3. 合入 `lib/pages/timeline/filter_review_page.dart` 的 `_articleStateWorker` / `_filterCountWorker`，否则审核页仍会出现计数减少但列表不消失。
4. 合入 `README.md` 的 Auto Folo 文档、图标展示、macOS 支持说明。
5. 合入展示名改动：`AppConstants.appName`、`AutoFoloApp`、设置页关于信息、macOS `PRODUCT_NAME` 与 Xcode scheme/product 引用。
6. 保持 `pubspec.yaml:name` 为 `autofolo`，不要为了展示名强行改 Dart package。
7. 保持 bundle id / method channel 稳定，除非计划做一次完整应用迁移。
8. 合入后在 main 侧至少运行：

```bash
flutter analyze
flutter test
flutter build macos --debug
```

9. 如果 main 侧还保留旧 README/AGENT_HANDOFF 结构，请优先把本节放到文档顶部，避免后续 agent 只读旧上下文。

## 79. macOS 快捷键双重触发、刷新动画与未读计数（2026-06-01 追加修复）

### 本次反馈问题与修复总结

1. **左右快捷键“两个两个跳动” (双重触发 bug)**
   - **原因**：之前的修改在 macOS 分栏模式中增加了全局 `HardwareKeyboard` 监听，但未完全禁用 `ArticlePageView` 内部 `Focus` 节点上的同级监听。当按下方向键时，两个监听器可能同时捕获事件，导致切换下一篇的操作被瞬间执行了两次。
   - **修复**：在 `lib/pages/article/article_page.dart` 中增加判断逻辑：当启用了全局键盘监听（`_usesGlobalShortcuts`）时，`Focus` 节点的 `onKeyEvent` 会直接返回 `KeyEventResult.ignored`，从而避免重复触发。

2. **左侧边栏未读气泡数量不准确 (点开一篇已读文章会减2)**
   - **原因**：此问题与上述双重触发 Bug 紧密相关。由于方向键双重触发，文章状态（已读）的 `tick` 事件被连续调用两次。而 `SubscriptionsController.refreshUnreadCounts` 之前采用的是基于事件的“盲目增量计算”（即：如果收到一篇文章更新且它是已读状态，未读数就无脑 `-1`）。这导致一篇文章被点开时，未读数错误地减去了 2。
   - **修复**：彻底废弃了脆弱的 `-1/+1` 增量计算逻辑。修改 `lib/pages/subscriptions/subscriptions_controller.dart`，当收到增量更新事件时，直接在内存的 `GStorage.articleDb` Map 中遍历该源（`feedId`）的所有文章，重新精准统计一次真实的未读文章总数，杜绝了多次调用导致的数据漂移问题。

3. **刷新按钮旋转方向反了**
   - **原因**：原先 `RotationTransition` 默认顺时针旋转，但 `Icons.sync` 图标的箭头在视觉上指示的是逆时针循环，这导致按钮看起来像是在“倒转”。
   - **修复**：在 `lib/pages/timeline/timeline_page.dart` 中，将 `turns: _spinController` 修改为 `turns: ReverseAnimation(_spinController)`，实现视觉上的顺向旋转。

4. **文章内可点击链接希望改为手型光标暗示（搁置）**
   - **技术讨论与放弃原因**：目前的 HTML 渲染库 `flutter_html: ^3.0.0-beta.2` 在将 `<a>` 标签转为 `TextSpan` 时，未开放 `mouseCursor` 属性注入。叠加外层的 `SelectionArea`（强制为所有未指定光标的文本添加 I 字形选择光标），导致系统不会将链接渲染为手型。如果使用 `flutter_html` 的拦截器将链接替换为原生组件，会破坏 Flutter 中内联文本的排版特性，造成长链接无法自动换行。经过权衡后，我们决定不采用会导致严重排版破坏的妥协方案，保留了可以复制文本但无手型暗示的现状。后续彻底解决建议等待 `flutter_html` 库底层更新或进行定制 Patch。

## 80. Android + macOS 内部发布流程（2026-06-01）

### 80.1 本次发布命名与版本

- 推荐并采用 tag：`v1.1.1`。
- 版本号同步：
  - `pubspec.yaml`：`version: 1.1.1+3`
  - `lib/http/init.dart`：`X-App-Version: 1.1.1`
  - `lib/pages/settings/settings_page.dart`：关于页显示 `Auto Folo v1.1.1`
  - `CHANGELOG.md`：新增 `1.1.1 - 2026-06-01`
- 用户当前只自用，不考虑软件商城；发布策略按“内部测试版”处理，直接产出 APK 和 macOS zip。

### 80.2 GitHub Actions 工作流

文件：`.github/workflows/internal-release.yml`

触发方式：

- `push` tag，匹配 `v*`。
- `workflow_dispatch` 手动触发。

工作流结构：

1. `Android APK`
   - runner：`ubuntu-latest`
   - Java：Temurin 17
   - Flutter：`subosito/flutter-action@v2`，固定 `flutter-version: '3.41.6'`
   - 验证：`flutter analyze --no-fatal-infos lib test`、`flutter test`
   - 构建：`flutter build apk --release`
   - 产物：`Auto-Folo-android-${GITHUB_REF_NAME}.apk`

2. `macOS App`
   - runner：`macos-latest`
   - Flutter：固定 `3.41.6`
   - 先执行 `test "$(uname -m)" = "arm64"`，确保远端 runner 是 arm64。
   - 验证：`flutter analyze --no-fatal-infos lib test`、`flutter test`
   - 构建：`flutter build macos --release`
   - 打包：先用 `ditto --arch arm64` 复制出 arm64-only `.app`，再 zip。
   - 打包后验证：
     - `file ... | grep arm64`
     - `! file ... | grep x86_64`
   - 产物：`Auto-Folo-macOS-arm64-${GITHUB_REF_NAME}.zip`

3. `Publish GitHub Release`
   - 依赖 Android 和 macOS 两个 build job。
   - 下载 build artifacts 后用 `gh release view/create/upload` 创建或更新 release。
   - 必须设置：
     - `GH_TOKEN: ${{ github.token }}`
     - `GH_REPO: ${{ github.repository }}`
   - `GH_REPO` 是必要修复：release job 没有 checkout，目录里没有 `.git`；不显式传仓库时 `gh release view` 会报 `fatal: not a git repository`。

### 80.3 macOS arm64 约束

用户明确要求：macOS 不论远程还是本地，都始终希望构建 arm64。

当前约束点：

- CI 远端：`Verify arm64 runner` 强制 `uname -m == arm64`。
- CI 发布包：`ditto --arch arm64` 瘦身，再用 `file` 确认包含 arm64 且不包含 x86_64。
- 本地/项目配置：`macos/Runner.xcodeproj/project.pbxproj` 的 Runner `Release` / `Profile` 配置加入 `ARCHS = arm64`。
- 已用 `xcodebuild -showBuildSettings -project macos/Runner.xcodeproj -scheme Runner -configuration Release` 确认解析结果包含：
  - `ARCHS = arm64`
  - `HOST_ARCH = arm64`
  - `NATIVE_ARCH = arm64`

注意：在固定 `ARCHS` 前，本地 `flutter build macos --release` 的原始产物曾是 universal binary（同时含 `x86_64` 和 `arm64`）。不要回退当前 arm64 约束。

### 80.4 本次踩坑与修复

1. 首次 tag push 没有自动跑新 workflow。
   - 原因：workflow 刚引入，第一次需要手动 `gh workflow run` 或重新移动 tag 触发。

2. GitHub 默认 Flutter 版本导致 analyze 失败。
   - 表现：Flutter 3.44.0 把 `SizeTransition.axisAlignment` deprecation info 作为 fatal 处理。
   - 修复：analyze 改为 `flutter analyze --no-fatal-infos lib test`。

3. macOS 在 Flutter 3.44.0 arm64 runner 上构建失败。
   - 表现：`_window_macos.dart` 相关 snapshot generator 崩溃。
   - 修复：工作流固定 Flutter `3.41.6`。

4. GitHub Release 发布失败。
   - 报错：`failed to run git: fatal: not a git repository (or any of the parent directories): .git`
   - 原因：release job 只下载 artifacts，没有 checkout，`gh` 无法从 git remote 推断仓库。
   - 修复：增加 `GH_REPO: ${{ github.repository }}`。

5. GitHub Actions 有 Node.js 20 deprecation warning。
   - 来源：`actions/checkout@v4`、`actions/upload-artifact@v4` 等当前 action 运行时提示。
   - 当前不影响发布；后续可单独升级 action 或按 GitHub 建议切 Node 24。

### 80.5 已验证结果

本地验证过：

- `flutter analyze lib test`：通过
- `flutter test`：通过
- `flutter build apk --release`：通过
- `flutter build macos --release`：通过（固定 `ARCHS` 前产物为 universal，随后已用项目配置与 CI 打包约束改为 arm64-only 发布）
- arm64 zip 解包后检查：主程序和所有 framework 都是 `Mach-O ... arm64`，未发现 `x86_64`。

远端发布验证：

- GitHub Actions run：已通过，具体 run id 不写入仓库文档
- 结果：`Android APK`、`macOS App`、`Publish GitHub Release` 全部通过。
- Release URL：`GitHub Release v1.1.1`
- Release assets：
  - `Auto-Folo-android-v1.1.1.apk`
  - `Auto-Folo-macOS-arm64-v1.1.1.zip`

### 80.6 当前仓库状态注意

- `v1.1.1` 是 annotated tag，已移动到包含 release workflow 修复和 macOS arm64 约束的提交。
- `main` 当前发布相关提交：
  - `53cc355 ci: build internal releases from tags`
  - `310af8c ci: allow informational analyzer warnings`
  - `e35b091 ci: pin Flutter for internal release builds`
  - `ddfa988 ci: package macos release as arm64`
  - `63a6c72 ci: fix release publishing without checkout`
- `.gitignore` 和 `scratch/` 在发布前后都存在用户侧未提交变更；不要在无明确要求时纳入发布/文档提交。

## 81. worktree 复核、必要改动吸收与 v1.1.2 发布（2026-06-02）

### 81.1 用户要求与判断过程

用户要求谨慎检查所有待合并 worktree，确认是否正确、是否有必要；如果确认已经处理完，就清理所有 worktree、维护 `AGENT_HANDOFF.md`、维护 Git 仓库，并打一个小版本 tag 触发 Android + macOS 打包。

本轮检查过的辅助 worktree：

1. `<historical-agent-worktree>`
   - 分支：`browse-entire-project`
   - 状态：clean
   - 主要提交：`81cef1b feat: inbox content fallback, ui tweaks, and index.html redesign`
   - 结论：不直接 merge。里面包含一个有价值的 Inbox 正文 fallback，但也混入 `index.html` 大改和 UI 调整；其中 Inbox fallback 还存在“失败前就写入 fetched 标记，之后不再重试”的风险。

2. `<historical-agent-worktree>`
   - 分支：`improve-macos-ui-layout`
   - 状态：clean
   - 主要提交：`1616e8c fix(macos): fix keyboard double trigger, sync animation direction, and unread count inaccuracy`
   - 结论：不需要再 merge。其核心效果已经在 `main` 的 `3a46af9 fix(macos): stabilize shortcuts and unread counts` 等后续提交中等价合入，并且 v1.1.1 发布流程已经验证。

3. `<historical-agent-worktree>`
   - 分支：`refactor-prompt-system-config`
   - 状态：dirty，大量 WIP 修改
   - 结论：不直接 merge。该 worktree 把 prompt 配置核心改动与大量格式化/无关文件修改混在一起。已手工吸收必要的摘要/翻译 prompt 配置能力，并修正了分块翻译 prompt 冲突问题。

关键原则：

- 不 cherry-pick 整个 worktree commit，也不直接合并 dirty WIP。
- 只把确认必要且能解释清楚的行为手工整理进 `main`。
- 对 dirty worktree 清理前，先把 WIP diff 保存到 `scratch/refactor-prompt-system-config.wip.patch`。`scratch/` 被 `.gitignore` 忽略，该补丁不进入版本库，但可用于本机恢复参考。
- worktree 已清理到只剩主工作区 `<main-worktree>`；本轮没有删除本地分支名，只移除了辅助 checkout 目录。

### 81.2 已合入的代码提交

本轮在 `main` 上形成 4 个提交：

1. `3311fc9 fix(filter): keep review queue append order`
   - 新增 `ArticleModel.filteredAt`，记录 AI 拦截判定完成时间。
   - 审核页初始加载按 `filteredAt` 升序显示；新拦截文章用 append 放到列表末尾，满足“垃圾拦截页面新文章始终附加在列表末尾”的要求。
   - `AutoFilterWorker` 在拒绝文章时写入 `filteredAt`；解除拦截时清空。
   - `.gitignore` 新增 `.antigravitycli/` 与 `scratch/` 忽略规则，保留 `scratch/.gitkeep`。

2. `b4e9019 fix(inbox): backfill content before AI processing`
   - 从 `browse-entire-project` 手工吸收 Inbox 正文 fallback，但修正为：只有 `FeedHttp.getInboxEntryDetail` 成功且返回非空正文后，才写入 `inbox_detail_fetched_${entryId}`。
   - Inbox 文章在可读性和 AI 处理前先补详情正文，避免空正文进入总结/翻译/过滤流程。
   - 内容更新时保留 `isRejectedByAi`、`filterReason`、`filterReviewed`、`filteredAt`，避免补全文或详情时破坏过滤队列状态。
   - `LocalArticleDbService.clearFilterState()` 成为直接清理过滤状态的公共路径，避免 `upsertMany` 的 OR 合并逻辑让“清除拒绝”失效。

3. `5050b9f feat(settings): configure summary and translation prompts`
   - 从 `refactor-prompt-system-config` 手工吸收 prompt 配置核心。
   - 设置页新增 3 个 Prompt 配置卡片：摘要、翻译、过滤。
   - `SummaryService` 新增 `getPrompt` / `setPrompt` / `resetPrompt`，默认 prompt 要求返回 `{"summary":"..."}`。
   - `TranslationService` 新增 `getPrompt` / `setPrompt` / `resetPrompt`，默认 prompt 只作为 System Prompt；具体 JSON schema 放在 User Prompt。
   - 分块翻译特别注意：首块要求 `translated_title` + `translated_html`，非首块只要求 `translated_html` 并明确“不要返回标题”。这是对 WIP worktree 的修正，避免 System Prompt 与非首块 User Prompt 互相冲突。

4. 版本/文档提交（本节所在提交）
   - `pubspec.yaml`：`version: 1.1.2+4`
   - `lib/http/init.dart`：`X-App-Version: 1.1.2`
   - `lib/pages/settings/settings_page.dart`：关于页显示 `Auto Folo v1.1.2`
   - `CHANGELOG.md`：新增 `1.1.2 - 2026-06-02`
   - `AGENT_HANDOFF.md`：记录本轮 worktree 复核、清理和发布上下文。

### 81.3 验证结果

已运行并通过：

```bash
git diff --check
dart analyze lib test
flutter analyze --no-pub --no-fatal-infos lib test
flutter test --no-pub
```

说明：

- 直接 `dart analyze` 全仓库会扫到 `reference/` 下外部参考工程，出现大量与本项目无关的 package URI 报错；不要用它判断本项目健康度。
- `flutter analyze --no-fatal-infos lib test` 与 `flutter test` 第一次都因 `pub get` 网络握手中断失败，未进入实际分析/测试；随后使用已有依赖缓存运行 `--no-pub` 版本通过。
- 如果后续需要完整 CI 风格验证，优先跑 `flutter analyze --no-fatal-infos lib test` 和 `flutter test`。

### 81.4 v1.1.2 内部发布计划

小版本 tag：`v1.1.2`。

发布语义：

- 用户只自用，不考虑软件商城。
- 继续按内部测试版处理，tag push 触发 `.github/workflows/internal-release.yml`。
- GitHub Actions 会构建：
  - Android release APK
  - macOS arm64-only release zip
  - GitHub Release assets

必须保持：

- macOS 本地与远端发布包都坚持 arm64。
- 不要恢复 universal macOS 发布包。
- 不要删除 `GH_REPO: ${{ github.repository }}`，否则 Release job 在没有 checkout 的目录中会再次报 `fatal: not a git repository`。

### 81.5 后续 agent 注意事项

- 如果需要恢复被清理 dirty worktree 的 WIP，可在本机查看 `scratch/refactor-prompt-system-config.wip.patch`。该文件未被 Git 跟踪，可能只存在于当前机器。
- `browse-entire-project` 的 `index.html` redesign 未合入；不是遗漏，是因为与当前请求无关且改动过大。
- `improve-macos-ui-layout` 的实际功能已由 main 现有提交覆盖；不要重复合并。
- prompt 配置已经有意拆分为 System Prompt + User Prompt schema。不要把 JSON schema 全部塞回 System Prompt，否则分块翻译的非首块容易与标题字段要求冲突。
- `LocalArticleDbService.upsertMany` 会保留已有 AI 拒绝状态；需要清除拒绝时必须使用直接清理路径 `clearFilterState()` 或等价的 raw DB 写法，不能用一个 `isRejectedByAi: false` 的 `ArticleModel` 期望 OR 合并自动清除。

### 81.6 v1.1.2 远端发布结果

- tag：`v1.1.2`
- tag 指向提交：`29316f7 chore(release): prepare v1.1.2`
- GitHub Actions run：已通过，具体 run id 不写入仓库文档
- 结果：`Android APK`、`macOS App`、`Publish GitHub Release` 全部通过。
- Release URL：`GitHub Release v1.1.2`
- Release assets：
  - `Auto-Folo-android-v1.1.2.apk`
      - `Auto-Folo-macOS-arm64-v1.1.2.zip`
    
发布中仍出现 GitHub Actions 的 Node.js 20 deprecation warning：

- 来源：`actions/checkout@v4`、`actions/setup-java@v4`、`actions/upload-artifact@v4`、`actions/download-artifact@v4`。
- 当前不影响发布结果。
- GitHub 提示 Node.js 24 将在 2026-06-16 起默认启用，Node.js 20 将在 2026-09-16 移除；后续可单独更新 workflow action 版本或设置 Node 24 兼容策略。

注意：本节是 `v1.1.2` tag 推送并成功发布后的补充记录，因此位于 `main` 上 tag 之后的文档提交中；不要为补这段记录移动或 force-update `v1.1.2` tag。

## 82. Android 安装签名冲突与 v1.1.3 修复（2026-06-02）

### 82.1 用户遇到的问题

用户安装 `v1.1.2` Android APK 时，系统提示：

```text
应用未安装：软件包与现有软件包存在冲突
安装包的开发者签名有异常，建议清除同包名的数据或联系开发者
```

根本原因不是版本号不够高，而是 Android 覆盖安装要求：

- `applicationId` 相同：当前是 `com.folo.folo_reader`
- 签名证书也必须相同
- `versionCode` 更高只在“包名相同且签名相同”时才决定是否可升级

如果包名相同但签名不同，Android 会直接拒绝覆盖安装。这是安全机制，防止任意 APK 用相同包名和更高版本号接管旧应用数据。

### 82.2 为什么之前会签名不同

检查 `android/app/build.gradle.kts` 后发现，本项目之前的 release 构建实际使用了 debug 签名：

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

debug keystore 通常与构建环境相关：

- - - 换机器、删掉 debug keystore、换 runner，都可能导致签名不同

因此用户本机 `flutter run` 安装的包和 GitHub Actions 构建的 release APK 可能同包名但签名不同，从而无法覆盖安装。

### 82.3 用户确认的修复策略

用户基本只自用，并确认目前只通过“本机”和“GitHub Actions”两种方式安装/打包过。经过讨论后，采用：

- 使用固定 Android 内部测试签名材料
- 将签名材料写入 GitHub Secrets，而不是提交到仓库
- GitHub Actions 以后 tag 构建的 Android APK 使用同一套固定内部测试签名



写入 GitHub Secrets 的项目：


注意：

- GitHub Secrets 不进入 Git 仓库，不会被 `git clone`、源码包、tag 或 Release 资产直接包含。
- 但 Actions 运行时可以使用这把 key 签 APK，因此它仍然是“把签名能力交给 GitHub Actions 环境”。
- 用户已明确同意将固定内部测试签名材料配置到 GitHub Secrets。

### 82.4 代码修复

修改文件：

1. `.gitignore`
   - 忽略 `android/key.properties`
   - 忽略 `android/app/*.jks`
   - 忽略 `android/app/*.keystore`

2. `android/app/build.gradle.kts`
   - 支持读取 `android/key.properties`
   - 如果存在固定 keystore 配置，release build 使用 `signingConfigs.release`
   - 如果本地没有 `android/key.properties`，仍 fallback 到 debug signing，保证普通本地开发命令可运行

3. `.github/workflows/internal-release.yml`
   - Android job 在 `flutter build apk --release` 前新增 `Configure Android signing`
   - 从 GitHub Secrets 还原 `android/app/upload-keystore.jks`
   - 生成 `android/key.properties`
   - 若任一 secret 缺失，CI 直接失败，避免再次发布不稳定签名 APK

### 82.5 本地验证

已在本机生成被 `.gitignore` 忽略的签名配置文件：

- `android/key.properties`
- `android/app/upload-keystore.jks`

本地验证命令：

```bash
dart analyze lib test
flutter build apk --release --no-pub
<android-sdk>/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

验证结果：

- `dart analyze lib test`：通过
- `flutter build apk --release --no-pub`：通过
- `apksigner verify --print-certs`：通过，并确认 APK 使用预期的固定内部测试签名证书。证书指纹不记录在仓库文档中。


### 82.6 v1.1.3 发布预期

版本计划：

- `pubspec.yaml`：`1.1.3+5`
- `X-App-Version`：`1.1.3`
- 设置页关于版本：`Auto Folo v1.1.3`
- tag：`v1.1.3`

安装预期：

- 如果手机当前安装包来自同一套固定内部测试签名，则 `v1.1.3` GitHub APK 应该可以直接覆盖安装。
- 如果手机当前安装包来自旧 GitHub Actions runner 的 debug key，则仍会签名冲突，需要卸载一次。
- 一旦成功安装 `v1.1.3`，之后 GitHub Actions 发布的 APK 只要继续使用这套 secrets，就应能正常覆盖升级。

### 82.7 v1.1.3 远端发布结果

- tag：`v1.1.3`
- tag 指向提交：`8f366a8 fix(android): use fixed signing key for internal releases`
- GitHub Actions run：已通过，具体 run id 不写入仓库文档
- 结果：`Android APK`、`macOS App`、`Publish GitHub Release` 全部通过。
- Release URL：`GitHub Release v1.1.3`
- Release assets：
  - `Auto-Folo-android-v1.1.3.apk`
        - 已下载到被 Git 忽略的临时目录并用 `apksigner verify --print-certs` 验证签名
          - `Auto-Folo-macOS-arm64-v1.1.3.zip`
    
结论：`v1.1.3` GitHub Android APK 已确认使用固定内部测试签名。若用户手机上现有安装包来自同一签名，应可直接覆盖安装；若仍报签名冲突，说明手机上现有包来自另一把签名，需要卸载一次后再装。

## 83. Android 时间线灰屏修复与 v1.1.4 发布（2026-06-02）

> 2026-06-03 校准：本节记录的是第一次 Android 灰屏排查、缓存读取加固和 v1.1.4 发布过程；后续第 84 节进一步确认了“主时间线/垃圾拦截页灰屏”的真正根因是 GetX `Obx` 短路读取和卡片布局问题。诊断同类灰屏时，应以第 84 节为最终根因记录，同时保留本节作为发布与防御性修复历史。

### 83.1 用户反馈

用户成功安装 `v1.1.3` 后反馈：Android 端时间线主页面中间是一整片灰色，什么都看不见。用户进一步澄清：不是灰色占位卡片，而是彻底的一整片灰色。

本机环境没有连接 Android 设备或模拟器：

```bash
flutter devices
# 仅发现 macOS 和 Chrome
```

因此本轮无法直接截图复现 Android 页面，只能从 Flutter release 灰盒常见原因和时间线渲染路径排查。

### 83.2 排查结论

初始猜测是时间线停在骨架屏，但用户澄清不是占位卡片。因此排查转向 Flutter release 灰盒：

- Flutter debug 下 widget 异常常表现为红屏/错误文本。
- Flutter release 下某些 build/layout 异常可能表现为灰色错误块或整块灰色区域。

时间线卡片 `ArticleCard` 在 build/initState 阶段会读取：

- `TranslationService.hasTranslation`
- `TranslationService.recordOf`
- `TranslationService.displayTitleFor`
- 摘要块开启时的 `SummaryService.recordOf`

临时 widget test 复现出一个问题：如果本地 AI 缓存 box 尚未 hydration，`ArticleCard` 会因为 `GStorage.translations` 未初始化抛 `LateInitializationError`。真实 App 正常会先 `GStorage.init()`，但 release 中这类缓存读取不应能把整个时间线渲染链路打挂。

另一个独立风险来自 `FeedHttp.collectEntries()`：

- 它依赖 `publishedAfter = batch.last.publishedAt` 继续分页。
- 如果服务端重复返回同一页，或最后一篇时间戳不前进，就可能长时间停留在加载态。
- 这不会解释用户澄清后的“整片灰色”全部现象，但会造成主页面一直显示空表面/加载表面，因此一起修复。

### 83.3 修复内容

1. `lib/services/translation_service.dart`
   - `recordOf()` 对 `ensureHydrated()` 增加 try/catch。
   - 如果缓存 box 未就绪，记录调试日志后继续读取 `_records[entryId]`；这样既不会抛出 hydration 异常，也会保留 `Obx` 所需的 observable 读取。

2. `lib/services/summary_service.dart`
   - `recordOf()` 对 `ensureHydrated()` 增加 try/catch。
   - 如果缓存 box 未就绪，记录调试日志后继续读取 `_records[entryId]`；摘要块按 idle/未生成状态处理，不抛异常。

3. `lib/http/feed_http.dart`
   - `collectEntries()` 增加 `seenIds` 去重。
   - 如果某一页没有任何新 entryId，停止分页，避免重复页无限循环。
   - 如果下一页 cursor 为空或与上一页相同，停止分页。
   - 增加可选 `maxPages` 参数，保留未来调用方限制分页上限的能力。

4. `test/article_card_test.dart`
   - 新增 widget test：本地 AI cache 未 hydration 时，`ArticleCard` 必须能渲染且不抛异常。

### 83.4 版本策略

用户原话是“重新打包成 1.1.3”。但 `v1.1.3` 已经是已推送并成功发布的 tag，不应该移动或覆盖重打。为了避免历史混淆，本轮使用新 patch 版本：

- `pubspec.yaml`：`1.1.4+6`
- `X-App-Version`：`1.1.4`
- 设置页关于版本：`Auto Folo v1.1.4`
- tag：`v1.1.4`

Android 签名继续使用第 82 节配置的固定内部测试签名材料，因此应保持与 `v1.1.3` 可覆盖升级。

### 83.5 本地验证

本轮修复提交前已完成：

```bash
dart format lib/http/feed_http.dart lib/services/translation_service.dart lib/services/summary_service.dart lib/http/init.dart lib/pages/settings/settings_page.dart test/article_card_test.dart
git diff --check
dart analyze lib test
flutter test --no-pub
flutter build apk --release --no-pub
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

结果：

- `dart analyze lib test` 通过。
- `flutter test --no-pub` 通过，包含新增 `ArticleCard renders when local AI caches are not hydrated`。
- 本地 Android release APK 构建成功。
- 本地 APK 签名仍是第 82 节记录的本机 debug keystore：
    
### 83.6 GitHub Actions 发布结果

提交：

- Commit：`e017bff447392ebdbff5ac40d18aada86a42edf3`
- Commit message：`fix(timeline): prevent Android release gray screen`
- Tag：`v1.1.4`

GitHub Actions：

- Run ID：已通过，具体 run id 不写入仓库文档
- Run URL：`GitHub Actions run`
- 结果：成功。
- Jobs：
  - `macOS App`：通过，用时约 `6m30s`；包含 `Verify arm64 runner`，因此本次 macOS 仍为 arm64 构建。
  - `Android APK`：通过，用时约 `9m50s`；`Configure Android signing`、`Build APK`、`Upload APK artifact` 均通过。
  - `Publish GitHub Release`：通过，用时约 `12s`。
- Release URL：`GitHub Release v1.1.4`
- 预期 release assets（由 workflow 产物命名规则生成）：
  - `Auto-Folo-android-v1.1.4.apk`
  - `Auto-Folo-macOS-arm64-v1.1.4.zip`

注意：本轮在 workflow 成功后，新的 `gh run view`/release 查询被 Codex 系统用量限制拒绝，因此没有继续下载 GitHub release asset 做远端 hash 和远端 APK 签名复验。可确认的信息来自已完成的 workflow 监控输出和本地 release APK 签名验证。

## 84. 安卓端主时间线及垃圾拦截页灰屏彻底修复 (2026-06-02)

### 84.1 问题复盘
用户反馈：在安卓端，只要有文章被 AI 拦截（左上角/顶部出现数字），主时间线中间就会变成一片灰色，什么都看不见；点击进入垃圾拦截页面，里面同样是一片灰色。但从具体的订阅源点进去则显示正常。
此外，用户提出被拦截的文章“应该在主时间线显示，按本身日期排序，同时在拦截页面按审核完成时间排序”。

### 84.2 根本原因分析
排查后发现，灰屏是由两个独立但相互叠加的错误造成的：

1. **GetX `Obx` 的短路求值引发的运行时崩溃（导致灰屏的元凶）**
   在 `timeline_page.dart` 和 `filter_review_page.dart` 中，为了判断文章卡片在 macOS 端是否被选中，代码写成了：
   `isSelected: Platform.isMacOS && controller.selectedArticle.value?.entryId == article.entryId`
   在安卓端，由于 `Platform.isMacOS` 为 `false`，Dart 的短路求值特性导致后半段的响应式变量 `controller.selectedArticle.value` 从未被读取。
   GetX 的安全机制强制要求在 `Obx` 闭包内至少读取一次 Observable，否则会直接在 `build` 阶段抛出 `the improper use of a GetX has been detected` 异常。在 Release 模式下，这个异常导致整个列表的卡片渲染失败，呈现为大面积灰屏。

2. **卡片内 `Row` 与 `Flexible` 的布局约束死锁（潜在的 Debug 崩溃）**
   在 `ArticleCard` 渲染 AI 拒文理由时，原代码使用了一个 `mainAxisSize: MainAxisSize.min` 的 `Row`，里面嵌套了一个 `Flexible` 组件。
   在 Flutter 中，试图让父组件紧缩（min）的同时让子组件扩展（flex）会触发严格的布局约束冲突断言。虽然在 Release 模式下这个 `assert` 会被跳过从而不会引发灰屏，但如果在 Debug 模式下运行，必定会触发红屏报错（Red Screen of Death）。

### 84.3 修复方案与讨论过程
1. **彻底修复 `ArticleCard` 布局冲突**：
   移除了带有 `Flexible` 的 `Row`，改为使用原生且安全的 `Text.rich` 搭配 `WidgetSpan` 来渲染图文混排的拦截理由。这不仅彻底排除了 Debug 模式下的“红屏炸弹”，也提升了长文本截断的可靠性。
2. **修复 GetX `Obx` 崩溃逻辑**：
   在 `timeline_page.dart` 和 `filter_review_page.dart` 中的 `Obx` 闭包内，提前将 `selectedArticle.value?.entryId` 赋值给一个局部变量，强制其在所有平台上都被读取一次。这样既绕过了短路求值的陷阱，又保证了状态的正确注册。
3. **澄清并恢复时间线的过滤逻辑**：
   由于我最初误解了用户“新分析完的文章应该在垃圾拦截页面”的需求，曾一度在 `timeline_controller.dart` 中把被拦截文章从主时间线剔除了。用户澄清后确认：**被拦截的文章既要留在主时间线（按发布时间排序），也要出现在审核页面（按审核完成时间排序）**。这正符合旧有代码的双线并行排序逻辑，因此我立即撤销了那段错误剔除代码，恢复了原有设定。

经过这些修改，安卓端的灰屏现象彻底消失，应用恢复正常运行与逻辑流转。

## 85. macOS 桌面端 UI 细节精简与占位符统一（补记于 2026-06-03）

### 85.1 需求与起因

- **右侧占位符**：在 macOS 双栏布局下，当右侧没有选中任何文章时，之前一直只显示简陋的纯文本（“请在左侧选择文章”等）。用户反馈这显得太简陋，希望恢复成视觉丰富的占位符（用户误以为曾经有过，实际上代码历史中未曾实现过）。
- **左上角标志**：侧边栏左上角的 “Auto Folo” 应用名称标志，在已经有独立系统窗口和标题栏的 macOS 环境下显得冗余且格格不入，用户希望删除。

### 85.2 排查与实现

1. **新建通用占位符组件**
   - 创建 `lib/common/widgets/mac_empty_placeholder.dart`，提供 `MacEmptyPlaceholder`。
   - 使用主题色着色的 `Icons.article_outlined`，配合 `alpha: 0.08` 的弱化背景圆环，下方辅以原有的提示文本。该设计贴合 macOS 现代极简风格，填补了留白而不显得突兀。
2. **全局替换未选中状态**
   - 梳理出 macOS 下所有采用 Split View（双栏布局）的三个页面：
     - `TimelinePage` (时间线)
     - `FeedDetailPage` (订阅源详情)
     - `FilterReviewPage` (垃圾拦截审查)
   - 统一将这三处在 `selectedArticle == null` 时渲染的纯文本替换为 `MacEmptyPlaceholder`。
3. **清理侧边栏顶部**
   - 编辑 `lib/pages/main/widgets/macos_sidebar.dart` 中的 `_SidebarHeader` 组件。
   - 移除了包含 “Auto Folo” 文本的节点。
   - 为保持头部剩余图标（收起侧边栏按钮）的对齐自然，移除了原有的 `Row` 布局，改用 `Align(alignment: Alignment.centerRight)` 使其合理停靠。

### 85.3 后续建议

如果后续在 macOS 桌面端引入新的双栏页面结构，遇到“右侧空内容/未选中”的状态，请务必复用 `MacEmptyPlaceholder` 以维持 UI 表现的统一性。同时尽量避免过度放置文字 Logo 标识，保持桌面环境的沉浸感。

## 86. UI 精简实验与设计理念记录（补记于 2026-06-03）

### 86.1 遗留的体验问题（待完善但不构成 Bug）
在增强快捷键系统时（如增加上下键平滑滚动），代码放开了对 `LogicalKeyboardKey.keyM`（切换已读/未读状态）的按键事件校验，允许了 `KeyRepeatEvent` 触发。
- **现状**：如果用户长按 `M` 键，将产生密集的切换请求。
- **结论**：这暂时不影响主要流程运行，不构成致命 Bug，但需要在未来版本中对该快捷键增加防抖（Debounce）处理或限制仅响应 `KeyDownEvent`。

### 86.2 垃圾拦截与未读数设计理念（防退化记录）
在重构订阅源未读数统计逻辑时，确保了**被 AI 拦截/拒收的文章（`isRejectedByAi == true`）也必须计入左侧订阅源的未读红点中**。
- **核心设计理念**：被拦截的文章只是被“分类”到垃圾箱，但它们在整体系统中依然属于“尚未处理/审核”的新增信息。用户必须通过数字感知到有新内容被过滤，进入拦截页统一批量审阅，而不是被系统直接默默丢弃。未来接手的 Agent 必须牢记此逻辑，不可擅自剔除该部分未读统计。

### 86.3 侧边栏折叠按钮的实验性隐藏
在 macOS 双栏布局中，移除了原有的侧边栏“收起/展开”按钮。
- **设计意图**：这是一种实验性质的极简 UI 探索，期望界面进一步去噪。
- **备用恢复方案**：代码中使用了 `SizedBox.shrink()` 代替原按钮，但并未删除外部布局和折叠状态逻辑。如果未来评估发现取消折叠按钮带来不便，可随时反悔，将 `SizedBox.shrink()` 重新替换为原有的 `IconButton` 即可低成本恢复该功能。

## 87. macOS 端“最近阅读”功能实现 (2026-06-05)

### 87.1 需求背景与痛点
用户希望在侧边栏增加一个“最近阅读”页面，将所有已读文章严格按照**实际阅读时间倒序排列**。
由于后端的 Folo API 不提供单篇文章精确的“阅读时间戳”，导致本地如果依赖服务端数据，只能按照文章的默认“发布时间”降级排序，无法真实反映阅读历史。
此外，用户明确要求此功能**目前暂时仅在 macOS 端实现，不考虑安卓端**。

### 87.2 技术选型与实现方案
经过与用户的讨论，我们排除了依赖服务端修改的方案，采用了**“本地拦截+持久化”**的策略：
1. **数据层 (Hive Box 记录时间戳)**：在 `lib/utils/storage.dart` 中新增了一个 `readHistory` Box。
2. **状态层 (Hook)**：修改了 `LocalArticleDbService.setReadState`，当用户在本地主动将一篇文章标记为“已读”时，系统会将当前的毫秒级时间戳写入 `readHistory`。对于后台静默同步过来的历史已读文章，我们不赋予错误的时间戳，让它们平滑降级。
3. **控制器层 (`RecentReadController`)**：负责从本地所有已读文章中读取数据，优先通过 `readHistory` 的时间戳进行降序；缺失时间戳的文章则回退到依 `publishedAt` 降序，并置于列表后方。
4. **视图层 (`RecentReadPage` & `MacOSSidebar`)**：
   - 专门抽取了一个极简版的双栏 `RecentReadPage`，复用骨架屏和空状态占位。
   - 在 macOS 专属的侧边栏 (`MacOSSidebar` 及折叠模式) 的“垃圾拦截”下方新增了“最近阅读”的导航入口。

### 87.3 关键注意事项与后续交接建议
- **平台限制**：入口与展示逻辑只写在了 `_macPages`（`MainPage`）以及 `MacOSSidebar` 中，Android 端的 `BottomNavigationBar` 故意未做修改，请未来接手的 agent 留意这一刻意为之的限制。
- **历史数据行为**：功能上线之前已经标记为已读的文章是没有时间戳的，因此进入此页面时它们会垫底，这是用户已知并接受的预期行为，请勿试图“强行初始化时间戳”以免破坏时间线。
- **UI 复用**：`RecentReadPage` 借用了 `timeline_page.dart` 中未独立抽取的部分组件（例如空状态等）。如果有后续的页面也需要使用，建议统一抽取至 `lib/common/widgets/` 下以减少代码冗余。
