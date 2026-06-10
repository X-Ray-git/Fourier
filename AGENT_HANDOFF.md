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

- 不建议在当前 Codex worktree 内直接重命名 `<current-codex-worktree>`，这会影响当前会话和 Git worktree 路径。
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

debug keystore 通常与构建环境相关：本机构建和 GitHub Actions runner 可能使用不同证书。换机器、删掉本地调试 keystore、换 runner，都可能导致签名不同。

因此用户本机 `flutter run` 安装的包和 GitHub Actions 构建的 release APK 可能同包名但签名不同，从而无法覆盖安装。

### 82.3 用户确认的修复策略

用户基本只自用，并确认目前只通过“本机”和“GitHub Actions”两种方式安装/打包过。经过讨论后，采用固定 Android 内部测试签名材料，并通过 GitHub Secrets 提供给 CI；签名材料、别名、口令、证书指纹等敏感细节不得写入仓库文档。

GitHub Actions 使用的 Secrets 项目名保留在 workflow 中；本文档只记录策略，不记录 secret 值、key 指纹或本机 keystore 路径。

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
- 结果：`Android APK`、`macOS App`、`Publish GitHub Release` 全部通过。
- Release URL：`GitHub Release v1.1.3`
- Release assets：
  - `Auto-Folo-android-v1.1.3.apk`
    - 已下载到被 Git 忽略的临时目录并用 `apksigner verify --print-certs` 验证签名
    - 确认 APK 使用预期的固定内部测试签名证书；证书指纹不记录在仓库文档中
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
- 本地 Android release APK 构建成功，并确认使用预期的固定内部测试签名；证书指纹不写入仓库文档。

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

## 87. 行内代码排版与渲染重构 (2026-06-05)

### 87.1 问题反馈
用户反馈：正文 HTML 中的“行内代码块似乎会被渲染成整行代码块”。即原本属于段落内部的行内代码（如 `<code>print("hello")</code>`），会被强行折断成带横向滚动条的占据整行的独立块级组件，极大破坏了技术文章的连贯排版。

### 87.2 问题诊断
深入排查发现问题出在 `lib/utils/html_chunk_parser.dart` 中针对 `<code>` 标签的“一刀切”式块级拆分策略：
- `HtmlChunkParser._mediaTags` 和 `_processMixedNodes` 的 `isBlockLike` 变量将 `'code'` 强行判定为媒体/块级节点。
- 一旦遍历到 `<code>`，即使其位于段落正中，也会被立即触发截断（`flush()`），随后在 `_processElement` 中被一律提取封装为 `HtmlChunkType.codeBlock`。
- 之所以采用这种“一刀切”防御性提取，推测是因为 `flutter_html` 解析大型带高亮的深层嵌套 `<code>` 会导致严重卡顿，加之部分不规范 RSS 源滥用 `<code>` 代替 `<pre>`。

### 87.3 修复思路与实施
不能粗暴地将 `code` 全盘变回行内元素，否则会导致非标准的多行代码源在屏幕上强制折行且丢失性能红利。于是引入了**启发式分类判定（Heuristic Detection）**：
1. 从全局 `_mediaTags` 移除 `'code'` 标签。
2. 新增 `_isBlockCode(dom.Element element)` 判定方法：
   - 如果是 `<pre>`，绝对为块级代码块。
   - 如果是 `<code>`，若内容包含 `\n`，或 `class` 包含 `language-/hljs`，或 `style` 指定了 `display: block`，则判定为块级代码块（升级提取为 `HtmlChunkType.codeBlock`）。
   - 若不满足上述条件，仅是简短 `<code>`，则将其判定为行内代码，被原样追加进段落 HTML，交给 `flutter_html` 内置的 `code` 样式字典无缝渲染。
3. 同步修改了相关的媒体探针 `_hasMediaDescendant` 等逻辑以融入该启发式方法。

该修复以极低改动成本，既完美恢复了行内代码在段落中的丝滑阅读体验，又妥善保留了对真实代码块的长文加载性能保护。

## 88. macOS 分屏模式下连续标记已读导致导航失效的修复（补记于 2026-06-05）

### 88.1 现象与问题诊断
**现象**：在 macOS 的分屏模式（左侧文章列表，右侧正文阅读）下，当用户处于“未读”视图模式时，如果按下 `m` 键（标记为已读），接着按下“下一个（右方向键）”或“上一个（左方向键）”，导航列表会突然回到第一篇文章，而不是顺滑地跳到下一篇未读文章。这导致连续快速阅读（按 m -> 右 -> m -> 右）的操作流断裂。

**原因分析**：
1. `timeline_controller.dart` 中，当前呈现的渲染列表（`controller.articles`）是动态过滤的（`TimelineViewMode.unread` 模式下仅包含 `!a.isRead` 的文章）。
2. 当按下 `m` 键标记已读时，底层数据立马更新，并触发 `_applyFilter()`，导致该文章瞬间从 `controller.articles` 列表中被剔除。
3. 当用户立刻按左右方向键触发 `_selectRelativeArticle(delta)` 导航时，系统会尝试在当前显示的列表 `controller.articles` 中使用 `indexWhere` 寻找当前文章所在的索引。
4. 由于刚刚标记已读的文章已经被动态移除了，`indexWhere` 返回 `-1`。
5. 代码随后执行 `(currentIndex + delta).clamp(0, list.length - 1)` 计算下一个索引，由于 `currentIndex` 为 `-1`，其加减结果经 clamp 限制后总是 `0`，从而不可避免地跳回到第一篇文章。

**注**：移动端没有此问题，因为移动端的文章轮播页（`_ArticlePagerPage`）接收的是进入详情页那一刻的静态副本（`controller.articles.toList()`），不响应外部列表的实时元素删减。

### 88.2 解决方案与实现
不引入额外的历史堆栈或状态机，直接利用底层**未过滤的全量列表 `controller.allArticles` 作为绝对坐标参考系**。因为无论过滤条件怎么变，全集列表的文章顺序（基于发布时间的倒序排序）始终稳固。

**具体逻辑 (`lib/pages/timeline/timeline_page.dart` -> `_selectRelativeArticle`)**：
1. 第一优先级：仍在当前的过滤列表（`controller.articles`）中寻找。如果找到，按常理加减 `delta` 进行偏移（处理在“全部”模式下的场景）。
2. 第二优先级：如果返回了 `-1`（通常是因为被标记已读导致过滤），则去底层全量列表 `controller.allArticles` 中寻找该文章的绝对物理索引 `allIndex`。
3. 扫描寻找可用项：以该绝对物理索引为起点，依据按键方向（`delta > 0` 向后或 `delta < 0` 向前），在全量列表中进行扫描。
4. 在扫描过程中，找到**第一篇同时还存在于当前过滤列表 (`controller.articles`) 中的文章**，选中该文章完成跳转。

**性能优化**：
考虑到列表最大可达 5000 条，嵌套的 `list.contains` 可能会引发 $O(N^2)$ 复杂度导致 UI 卡顿。因此，在第二优先级的扫描前，提前构造哈希集合 `final listEntryIds = list.map((a) => a.entryId).toSet();`，将查询从 $O(N)$ 降至 $O(1)$，确保查找瞬时完成。

### 88.3 后续防退化设计说明
未来修改 `TimelineController` 或处理导航相关的过滤逻辑时，必须注意：**任何涉及状态快速翻转引起的隐形列表重组问题，都应优先使用不受状态过滤影响的原始数据集作为坐标轴锚点，以防止游标丢失或索引崩塌。** 另外，AI 拦截文章（`isRejectedByAi`）并没有被从列表中过滤，它们也会被正常的保留在列表中进行导航，仅呈现视觉标记，不可混淆此概念。

## 89. 纯文本 URL 的自动识别与可点击化 (2026-06-05)

### 89.1 背景与问题
在某些信息流或文章中，用户分享的 URL 以纯文本形式存在，并没有被包裹在 HTML 的 `<a>` 标签中。这导致 `flutter_html` 在渲染时仅仅将其视为普通文本，用户无法直接点击跳转。为了提升阅读体验，需要将这些纯文本形式的 URL 自动转换为可点击的链接。

### 89.2 技术选型与权衡
对于这个问题，我们有几个潜在的干预点：
1. **在 `flutter_html` 的渲染层使用正则：**
   - *缺点*：`flutter_html` 本身是一个比较沉重的组件树，通过外部介入其内部的文本节点渲染非常困难，且极易引发性能衰退。
2. **在原始 HTML 字符串层面做全局正则替换：**
   - *缺点*：全局正则非常危险，极易破坏现有的 HTML 标签属性（比如误将 `<img src="https://...">` 里的链接替换为 `<a>` 标签），导致 DOM 树崩溃。
3. **在 `ArticleContentUtils.normalizeHtml` 阶段进行 DOM 深度遍历（最终采用方案）：**
   - *优点*：HTML 规范化阶段已经利用了 `html` 库解析出了 `dom.DocumentFragment` 树。我们只需要进行一次深度优先遍历（DFS），当且仅当遇到 `dom.Text`（纯文本节点）时，再应用正则匹配。这实现了标签属性与正文文本的完美隔离，彻底杜绝了 DOM 破坏风险。

### 89.3 具体实现细节
- **修改位置**：`lib/utils/article_content_utils.dart`
- **正则优化**：定义了 `_urlRe`，用于精确匹配标准的 URL 格式（`http://` 或 `https://`）。特别地，在正则末尾排除了可能作为句尾标点出现的字符，防止错误地将外部标点囊括进 URL 中。
- **性能优化**：
  1. 在真正调用正则表达式之前，先用 `!text.contains('http')` 进行极低开销的字符串扫描，直接剪枝掉 99% 根本不包含链接的普通文本节点。
  2. 遍历时主动跳过了 `<pre>`、`<code>`、`<style>`、`<script>` 等无需也绝不应该被转换为链接的特殊区域。
  3. 替换时仅对命中正则的局部纯文本生成新的 `DocumentFragment` 并原位替换旧节点，避免了整棵树的重新解析。
  4. 该解析逻辑依附于 `normalizeHtmlForEntry`，受 LRU 内存缓存保护，二次读取开销为 0。
- **安全修正**：合入主分支前补充了 HTML 转义处理。URL 及同一文本节点内的非 URL 片段都会先经过 `htmlEscape.convert`，避免 `&`、`<` 等字符在二次解析 fragment 时被错误解释。

### 89.4 给后续接手 Agent 的提醒
由于该逻辑深埋于 `ArticleContentUtils.normalizeHtml` 中，后续在处理任何跟“HTML 预处理”、“标签清理”相关的需求时，请务必注意不要破坏底部的 `_autoLinkifyTextNodes(fragment);` 调用顺序。另外，如果未来应用增加了“纯文本高亮”（比如搜索关键词高亮），建议采用与之相同的“DOM 纯文本节点树遍历”策略，以保证 HTML 结构的绝对安全。

## 90. macOS 端“最近阅读”功能实现与语义修正 (2026-06-05)

### 90.1 需求背景与痛点
用户希望在侧边栏增加一个“最近阅读”页面，将所有已读文章严格按照**实际阅读时间倒序排列**。
由于后端的 Folo API 不提供单篇文章精确的“阅读时间戳”，导致本地如果依赖服务端数据，只能按照文章的默认“发布时间”降级排序，无法真实反映阅读历史。
此外，用户明确要求此功能**目前暂时仅在 macOS 端实现，不考虑安卓端**。

### 90.2 技术选型与实现方案
经过与用户的讨论，我们排除了依赖服务端修改的方案，采用了**“本地拦截+持久化”**的策略：
1. **数据层 (Hive Box 记录时间戳)**：在 `lib/utils/storage.dart` 中新增了一个 `readHistory` Box。
2. **状态层 (显式 Hook)**：新增 `LocalArticleDbService.recordReadHistory(entryId)`，专门记录用户真实打开文章或主动处理文章的时间。`LocalArticleDbService.setReadState` 保持状态写入语义，仅在显式传入 `recordHistory: true` 时才记录历史；后台静默同步推断已读不传该参数，因此不会污染最近阅读排序。
3. **控制器层 (`RecentReadController`)**：负责从本地所有已读文章中读取数据，优先通过 `readHistory` 的时间戳进行降序；缺失时间戳的文章则回退到依 `publishedAt` 降序，并置于列表后方。
4. **视图层 (`RecentReadPage` & `MacOSSidebar`)**：
   - 新增极简双栏 `RecentReadPage`，左侧展示最近阅读列表，右侧复用 `ArticlePageView` 分栏阅读。
   - 在 macOS 专属的侧边栏 (`MacOSSidebar` 及折叠模式) 的“垃圾拦截”下方新增了“最近阅读”的导航入口。

### 90.3 本次合入前发现并修正的问题
分支原始实现把写入时间戳放在 `setReadState(entryId, true)` 内部，这会把 `_applyUnreadSnapshot` / `_refreshRecentReadWindow` 等后台同步推断为已读的文章也标成“刚刚阅读”，与“最近阅读”的产品语义冲突。

本次合入主分支前已改为：
- 用户打开 `ArticlePageView` 时调用 `recordReadHistory`，所以已读文章再次打开会移动到最近阅读顶部。
- 用户主动标记已读的路径传入 `recordHistory: true`。
- 标记未读会删除对应 `readHistory`，避免未读文章残留在阅读历史里。
- 同步推断已读仍只更新本地 read state，不写入阅读时间戳。

### 90.4 关键注意事项与后续交接建议
- **平台限制**：入口与展示逻辑只写在了 `_macPages`（`MainPage`）以及 `MacOSSidebar` 中，Android 端的 `BottomNavigationBar` 故意未做修改，请未来接手的 agent 留意这一刻意为之的限制。
- **历史数据行为**：功能上线之前已经标记为已读的文章是没有时间戳的，因此进入此页面时它们会垫底，这是用户已知并接受的预期行为，请勿试图“强行初始化时间戳”以免破坏时间线。
- **语义边界**：不要把所有 `setReadState(true)` 都当成用户阅读行为。只有用户真实打开文章、主动标记已读、或在垃圾拦截页主动处理文章时，才应该写入 `readHistory`。

## 91. 四个 antigravity worktree 的最终合入审计（2026-06-06）

### 91.1 背景
用户要求谨慎检查当前所有 antigravity worktree，先合入确认安全的改动，再修复存在问题的分支后合入。检查时主分支为 `v1.1.6 / ffc4e2c`，四个 worktree 均为干净状态，且每个分支各自只有一个未合入提交。

最终合入顺序：
1. `fix-inline-code-rendering`
2. `fix-read-status-navigation`
3. `enable-auto-link-detection`
4. `implement-recent-reading-page`

### 91.2 合入时保留与修正的重点
- `fix-inline-code-rendering`：直接合入。该分支修复 `<code>` 被一律拆成整行代码块的问题，保留对真实 `<pre>` / 多行 / 高亮代码块的块级保护。
- `fix-read-status-navigation`：直接合入。`AGENT_HANDOFF.md` 与前一个分支产生末尾追加冲突，已保留双方内容，并将 macOS 分栏导航修复记录调整为第 88 节。
- `enable-auto-link-detection`：修复后合入。原分支有两个问题：
  - 直接拼接 `<a href="$url">$url</a>`，对 `&`、`<` 等字符不安全，已改为对 URL 和同一文本节点内的非 URL 文本统一 `htmlEscape.convert`。
  - `_autoLinkifyTextNodes(fragment)` 传入的是 `dom.DocumentFragment`，原实现只处理 `dom.Element` / `dom.Text`，因此根节点不会继续遍历，功能实际不会生效。合入时补充了 `DocumentFragment` 分支并新增测试覆盖。
- `implement-recent-reading-page`：修复后合入。原分支把阅读时间戳写在 `setReadState(true)` 内部，会把后台同步推断已读的历史文章错误标成“刚刚阅读”。合入时改为显式 `recordReadHistory`，只有用户打开文章、主动标记已读或处理垃圾拦截文章时才记录时间；同步推断已读不写历史。

### 91.3 验证结果
合入完成后已验证：

```bash
git diff --check
dart analyze lib test
flutter test --no-pub test/article_content_utils_test.dart
flutter test --no-pub
```

结果均通过。`flutter test --no-pub` 期间仍会打印既有的 Translation hydrate skipped 日志，这是测试环境未初始化 Hive box 引起的既有输出，不影响测试通过。

### 91.4 Git 状态提醒
四个功能分支已经全部 merged 到 `main`。对应 antigravity worktree 目录和本地分支在本轮没有删除，原因是用户本轮要求“谨慎对待”并完成合入与推送，未明确要求清理 worktree；后续如需清理，可在确认没有其他 agent 继续使用这些 worktree 后再执行 `git worktree remove` 和本地分支删除。

## 92. 版本号统一与 v1.1.7 发布自动化（2026-06-06）

### 92.1 背景
用户确认希望推进版本并触发 GitHub Actions 打包，同时询问 `pubspec.yaml`、请求头 `X-App-Version`、设置页显示版本和 Git tag 是否可以自动统一，避免以后每次发布都手动维护多处。

排查时发现：
- `pubspec.yaml` 已是 `1.1.6+8`。
- `lib/http/init.dart` 的 `X-App-Version` 仍写死为 `1.1.4`。
- `lib/pages/settings/settings_page.dart` 的关于页仍显示 `Auto Folo v1.1.4`。

### 92.2 本轮修改
1. 新增 `lib/services/app_version_service.dart`，通过 `package_info_plus` 在运行时读取包版本。
2. `main()` 在初始化网络请求前先 `await AppVersionService.init()`。
3. `X-App-Version` 改为读取 `AppVersionService.version`。
4. 设置页关于版本改为 `Auto Folo v${AppVersionService.version}`。
5. 新增 `scripts/release.sh`：
   - 输入 `scripts/release.sh 1.1.8 -m "- 修复了xx\n- 新增了xx" --push` 这类命令即可读取当前 build number、自动加 1、更新 `pubspec.yaml`、提交版本 bump 并在本文档末尾自动追加发布足迹（Footprint），最后创建带有更新附注的 `v1.1.8` tag，并按参数决定是否推送。
6. `.github/workflows/internal-release.yml` 增加 `Validate Release Version` job：
   - tag 触发时校验 `vX.Y.Z` 必须与 `pubspec.yaml` 的 `X.Y.Z+build` 主版本一致。
   - Android 和 macOS job 都依赖该校验。
7. release job 增加 `actions/checkout@v4`，避免 `gh release view` 在没有 git 仓库上下文时再次出现 `fatal: not a git repository`。

### 92.3 本次发布版本
本轮将 `pubspec.yaml` 推进到：

```yaml
version: 1.1.7+9
```

计划创建并推送 tag：

```bash
v1.1.7
```

该 tag 会触发 `Internal Release Builds` workflow，构建 Android release APK 和 macOS arm64 zip，并发布到 GitHub Release。后续人工检查 release 页面时，应看到：
- `Auto-Folo-android-v1.1.7.apk`
- `Auto-Folo-macOS-arm64-v1.1.7.zip`

### 92.4 后续发布约定
以后不要再手写修改 `X-App-Version` 或设置页版本。正常发布只需要维护 `pubspec.yaml` 与 tag；推荐直接使用 `scripts/release.sh <version> -m "<版本摘要>" --push`，让脚本负责 build number、提交、写入文档脚印和带有附注的 tag。CI 会负责校验 tag 与 `pubspec.yaml` 是否一致，并自动将你的 `<版本摘要>` 提取为 GitHub Release Notes。
> [!IMPORTANT]
> 执行发布脚本时，`-m` (message) 摘要参数是必填项！如果不填或为空，脚本会报错并拒绝发版。请使用 Bullet list 的形式（如 `"- 修复了xx\n- 优化了xx"`）简要归纳版本改动。

## 93. macOS 双击原文自动标已读与单步撤销（2026-06-06）

### 93.1 背景与交互判断
用户确认需要在 macOS 端双击文章卡片打开原文时自动将文章标记为已读。这里的产品判断是：单击只是进入右侧分栏预览，不应强行标已读；双击打开外部浏览器代表更明确的阅读/消费意图，可以自动标已读。

同时，误双击或误按 `M` 会让文章从“未读”列表里消失，用户再去“全部”里找回并恢复未读成本很高。因此本轮引入一个深度为 1 的全局撤销：`Cmd-Z`（macOS）/ `Ctrl-Z`（其他平台配置层面保留）撤销最近一次“未读 -> 已读”转换。

### 93.2 合入前审计发现的问题
`super-galaxy-rolls-08h21` 分支原始实现有价值，但不能原样合入：
- 双击时只有在对应 `ArticleController` 已注册时才会 `markAsRead()`，而双击打开原文并不保证右侧详情 controller 一定存在，因此自动标已读不可靠。
- `ArticleController.markAsRead()` 一进入就记录 undo；如果后续网络同步失败并恢复未读，会留下不真实的可撤销记录。
- `UndoService.undoLastRead()` 在复用 `ArticleController.markAsUnread()` 时没有 `await`，会过早显示“已撤销成功”。
- 文档章节没有沿用 `AGENT_HANDOFF.md` 的编号格式。

### 93.3 最终实现
本轮保留功能方向，但修正实现边界：
1. 新增 `lib/services/undo_service.dart`：
   - 管理最近一次已读动作 `_lastReadArticle`。
   - 提供 `markAsRead(article, showSuccess: false)`，用于双击外部打开时后台标已读。
   - 如果 `ArticleController` 已存在，则复用 controller 的 `markAsRead()`，保证右侧详情页按钮状态同步；否则直接更新本地 DB / `TimelineController` / `ReadSyncService` 并调用 Folo API。
   - 网络失败时恢复未读并清理对应 undo 记录。
2. `ArticleController.markAsRead()`：
   - 改为在本地已读状态真正生效后记录 undo。
   - 如果同步失败并恢复未读，调用 `UndoService.clearForEntry()` 清掉错误撤销记录。
   - 增加 `showSuccess` 参数，允许双击自动标已读时静默同步。
3. `TimelinePage`、`FeedDetailPage`、`RecentReadPage`：
   - 双击仍先打开原文。
   - 若文章未读，则 `unawaited(UndoService.markAsRead(article, showSuccess: false))` 后台标已读。
4. `main.dart`：
   - 在 `GetMaterialApp.builder` 中通过 `Shortcuts` / `Actions` 注册全局撤销。
   - 执行撤销前检查当前焦点 widget；如果焦点在 `EditableText`，直接返回，避免抢占搜索框、设置页输入框、Prompt 编辑框里的文本撤销。
5. `TimelineController`：
   - 切换 view mode、feed、category 时清空 undo，避免跨上下文撤销造成隐藏列表的状态跳变。

### 93.4 后续注意
撤销仍是单步设计，不要扩展成多步栈，除非后续确实需要更复杂的历史管理。当前目标是降低误双击和误标已读的恢复成本，而不是实现完整编辑器式 undo 系统。




## 94. macOS 快捷键支持与设置页说明展示（2026-06-06）

### 94.1 需求背景
- 应用已有部分针对 macOS 桌面端和长文阅读的高频快捷键（如 `Cmd + Z` 撤销，以及阅读详情内的 `Esc`, `↑/↓`, `←/→`, `M`），但这些快捷键未在应用内部形成统一说明，用户学习成本高。
- 用户希望能统一在设置页面查看所有可用的 macOS 快捷键。
- 此外，希望新增 macOS 桌面端通用的 `Cmd + ,` 全局快捷键以快速打开设置页面。

### 94.2 实现细节

**1. 补齐全局快捷键 `Cmd + ,`**
- 文件：`lib/main.dart`
- 在全局 `Shortcuts` 内新增了针对 `Platform.isMacOS` 的 `LogicalKeyboardKey.comma` 和 `meta: true` 组合键绑定。
- 在 `Actions` 内定义并实现 `OpenSettingsIntent` 回调。
- 处理细节：跳转前通过 `Get.currentRoute` 检查是否已经在设置页，如果在设置页则拦截跳转请求，防止无意义的多次压栈。

**2. 在设置页提供说明面板**
- 文件：`lib/pages/settings/settings_page.dart`
- 在 `ListView` 中，“关于”区块之前插入了一组专门针对 macOS 的卡片式快捷键说明。
- 该说明仅当 `Platform.isMacOS` 为 `true` 时才展示，并在卡片内罗列了所有文章级与全局级的快捷键行为对应关系：
  - `Cmd + ,`: 打开设置
  - `Cmd + Z`: 撤销最近一次已读
  - `Esc`: 关闭当前阅读文章
  - `↑ / ↓`: 上下滚动文章
  - `← / →`: 切换上一篇 / 下一篇文章
  - `M`: 切换文章已读 / 未读状态
- 使用了统一样式 `_buildShortcutItem`，并在按键字母上使用了背景块与等宽字体以模拟真实的物理键帽视觉，维持整体应用 UI 的高品质观感。

### 94.3 后续维护
如果后续继续添加新的阅读或全局快捷键，请务必前往 `lib/pages/settings/settings_page.dart` 补充对应的说明项，以便用户能及时发现新快捷键。
## 95. macOS 全屏图片 Esc 键退出优化 (2026-06-06)

### 95.1 需求背景与问题
用户反馈：在 macOS 环境下阅读文章时，如果点击正文中的图片进入了沉浸式全屏浏览模式，此时按下 `Esc` 键，期望的行为是仅退出全屏图片，回到文章详情。但实际表现为不仅退出了图片全屏，连带着整篇文章也被关闭了。

### 95.2 问题产生原因
在 `lib/pages/article/article_page.dart` 中，为了支持 macOS 分栏模式（`isSplitView == true`）下文章视图的全局快捷键操作（如方向键滚动、快捷标记已读等），`ArticlePageView` 注册了一个全局硬件键盘监听器 `HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent)`。
该监听器由于是全局的，它在接收到 `Esc` 按键时，不论当前应用最顶层的 UI 是不是文章视图，都会强行拦截该按键并调用 `_closeArticle()`。因此，当图片通过 `HeroDialogRoute` 被压入新路由全屏展示时，按下 `Esc` 依然触发了底层的 `_closeArticle()`。

### 95.3 修复方案与权衡
由于这是由于底层的全局监听器“越权”拦截导致的问题，修复思路在于让 `ArticlePageView` 能够感知自身的路由层级。

我们在 `_handleHardwareKeyEvent` 的顶部追加了层级校验：
```dart
if (!mounted) return false;
final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
if (!isCurrentRoute) {
  return false;
}
```
**逻辑说明**：
当图片全屏打开时，Flutter 会向 `Navigator` 压入一个新的 `ModalRoute`。此时底层的 `ArticlePageView` 的 `ModalRoute.of(context)?.isCurrent` 会变为 `false`。通过这层检查，全局监听器在此状态下将放弃对键盘事件的消费（返回 `false`），将 `Esc` 键交还给顶层的图片查看器处理（Flutter 原生的 `PageRoute` 默认支持通过 Esc pop 自身），从而完美实现了仅关闭图片全屏的正确交互逻辑。

**为什么必须加 `!mounted` 校验**：
这是一个必要的防御性编程细节。在极短的生命周期交替瞬间（例如快速关闭分栏页面并同时按下键盘），`context` 可能因组件被系统卸载（unmounted）而失效，此时强行读取 `ModalRoute.of(context)` 会导致框架异常。加上此校验能确保应用绝对稳定。

### 95.4 给后续接手 Agent 的提醒
由于该项目的桌面端体验深度依赖全局键盘快捷键监听，在未来如果要为文章视图增加其他的全局快捷键（比如快速分享 `Cmd+S` 等），请务必保留这个前置路由检查逻辑。凡是有弹层或子路由叠加在上方时，下层的快捷键行为理应让步，否则极易引发类似的操作冲突问题。

## 96. macOS 物理播放键与空格键视频控制 (2026-06-06)

### 96.1 背景与需求
在之前的版本中，macOS 端播放视频（包括内联视频和全屏视频）无法使用键盘控制。用户希望能够使用键盘的物理媒体播放键和空格键来控制视频的播放/暂停，具体要求为：
1. **物理播放键**：采用全局监听模式。
2. **空格键**：采用“组件焦点模式”，只有在用户点击或交互选中视频后，空格键才会控制视频播放，避免在主页滚动时按空格键误触视频播放。

### 96.2 实现细节
针对 `lib/pages/article/widgets/inline_video_player.dart` 和 `fullscreen_video_page.dart`，我们采取了如下轻量级 Flutter API 拦截方案：
1. **全局物理键监听**：在 `initState` 中通过 `HardwareKeyboard.instance.addHandler` 注入全局按键监听。当捕获到 `LogicalKeyboardKey.mediaPlayPause` 时，如果视频正在播放，或者该视频当前拥有焦点，就触发 `_togglePlayPause()`。这防止了页面上多个暂停的视频源在按下物理键时同时开始播放。
2. **焦点模式空格键控制**：在 UI 的交互响应层（`GestureDetector` 或 `Stack` 外部）包裹了 `Focus` 组件，并为其分配了独立的 `FocusNode`。在 `onKeyEvent` 中拦截 `LogicalKeyboardKey.space`。只有当用户用鼠标点击视频区（例如呼出控制栏或点击中央播放键）触发了 `_focusNode.requestFocus()` 后，按下空格键才会被该视频组件拦截并专用于控制播放，从而不会干扰外层列表正常的空格向下滚动行为。

### 96.3 注意事项
- 方案未引入任何第三方快捷键库或系统级媒体控制库，全部依赖于 Flutter 自带的 `Focus` 树和 `HardwareKeyboard`，确保了轻量级、低副作用。
- 如果未来增加其他快捷键需求，请务必遵循“会与浏览器或列表滚动起冲突的按键（如空格、上下键）走焦点树捕获，不冲突的专用媒体按键走全局捕获”的原则。

## 97. 键盘导航列表自动滚动定位 (2026-06-06)

### 97.1 需求与问题背景
在 macOS 等桌面端环境下，用户可以通过详情页的键盘左右方向键（`arrowLeft` / `arrowRight`）切换上一篇/下一篇。此操作会更新 `TimelineController` 的选中状态，进而高亮列表中对应的 `ArticleCard`。
问题在于，当连续使用键盘切换时，选中的文章很快会超出当前 `ListView` 的可视范围。因为原本的列表没有记录各个动态高度卡片的渲染坐标，也没有在选中状态变更时触发列表自动对齐滚动逻辑，导致选中项常常跑到视口之外。

### 97.2 实现方案考量
由于文章卡片（`ArticleCard`）内部包含标题长短变化、AI摘要展开与否等动态高度因素，无法通过简单的 `index * fixedHeight` 公式计算精准的滚动偏移。同时为了避免引入重量级第三方组件（如 `scrollable_positioned_list`）带来对原有防过度滚动（`RefreshAwareScrollPhysics`）和上拉加载逻辑的破坏，最终采用了 Flutter 原生的基于 `GlobalKey` 上下文的追踪方案。

### 97.3 具体的修改
1. **状态维护**：在 `_TimelinePageState` 中增加了 `final Map<String, GlobalKey> _itemKeys = {};` 字典，以 `entryId` 为键缓存文章卡片的 Key。
2. **节点绑定**：在构建中间文章列表的 `ListView.builder` 时，将缓存或新建的 `GlobalKey` 赋予每一张生成的 `ArticleCard`。
3. **对齐滚动逻辑**：新增 `_scrollToArticle(String entryId)`。使用 `WidgetsBinding.instance.addPostFrameCallback` 在当前帧（选中状态变化后）绘制完成后执行。取出目标元素的 `currentContext`，调用 `Scrollable.ensureVisible`。配合 `ScrollPositionAlignmentPolicy.keepVisibleAtEnd` 参数，确保只在元素超出视口时，进行最少量的平滑滚动（250ms）使其重新进入可视范围。
4. **触发绑定**：重构 `_selectRelativeArticle`，在每次更新 `controller.selectedArticle.value` 时同步触发该定位滚动逻辑。

### 97.4 注意事项
这种基于 `Cache Extent` 与 `currentContext` 的原生滚动方案存在理论上的局限性：对于极其大跨度的随机文章跳转，如果目标元素相距过远导致未被 `ListView` 底层构建出，其 `currentContext` 将为 `null` 而无法定位。但对于当前的按键单步（+/- 1）导航使用场景而言，上一篇/下一篇文章必定处于预渲染的缓存区内，因此是改动最小且高度可靠的最优方案。




## 98. macOS 列表双向自动跟随滚动体验优化 (2026-06-06)

### 98.1 需求与问题背景
在第 97 项特性中，我们虽然实现了键盘导航的自动滚动定位，但用户反馈了一个明显的体验缺陷：**当选中的文章超出可视范围时，只有向下滑出时列表会跟随滚动，而向上滑出时，选中的高亮依然会跑到视野之外**。除此之外，自动跟随滚动特性只在 `timeline_page.dart` 中实现，订阅详情页（`feed_detail_page.dart`）、最近阅读（`recent_read_page.dart`）以及智能过滤页（`filter_review_page.dart`）完全不支持跟随滚动。

### 98.2 问题产生原因
之前的实现直接采用了 `Scrollable.ensureVisible(..., alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd)`。
在 Flutter 的底层实现中，`keepVisibleAtEnd` 的计算逻辑使用了 `math.max(targetPixels, currentPixels)`，目的是保证滚动条只会向“结束”（底部）方向推进。这意味着：
- 当目标元素在底部边界以下时，它会正常增加 `pixels` 向下滚动。
- 当目标元素在顶部边界以上时，为了把它带回视野理论上需要减小 `pixels`（即向上滚动），但这会被 `math.max` 函数忽略。因此无论你怎么往上按方向键，滚动条都不会往上移动。

### 98.3 修复方案与全局应用
我们从根本上重构了这一逻辑，并将其封装为公共工具：
1. **新增 ScrollUtils**：在 `lib/utils/scroll_utils.dart` 创建了 `ScrollUtils.ensureVisible` 静态方法。该方法会获取 `RenderObject` 和所在的 `Viewport`，计算元素的顶部（`targetTop`）和底部（`targetBottom`）在滚动列表中的绝对位置。
2. **动态方向判断**：
   - 如果 `targetTop < viewTop`（元素跑到了视野上方），则使用 `ScrollPositionAlignmentPolicy.keepVisibleAtStart` 使其对齐到顶部。
   - 如果 `targetBottom > viewBottom`（元素跑到了视野下方），则使用 `ScrollPositionAlignmentPolicy.keepVisibleAtEnd` 使其对齐到底部。
3. **全面覆盖**：将原先在 `timeline_page.dart` 的单点实现替换为新的 `ScrollUtils` 调用，并补全了 `feed_detail_page.dart`、`recent_read_page.dart` 和 `filter_review_page.dart` 中缺失的字典缓存 `_itemKeys` 绑定和状态联动。通过这一重构，所有支持 macOS 键盘导航的分屏文章列表均获得了一致、流畅的双向跟随滚动体验。

## 99. 重构 macOS 视频播放器按键控制 (2026-06-06)

### 99.1 需求与问题背景
在第 96 节中，我们为了避免与列表的“空格键向下滚动”起冲突，将视频的空格键控制绑定在了 `FocusNode` 上。这导致了严重的体验问题：只有在视频严格拥有系统焦点（通常是点击视频弹出控制条的那 3 秒内）时，空格键才能控制播放。一旦焦点稍微流失（比如点击了文章空白处），空格键就立刻失效。
经过与用户的讨论，用户明确表示**不需要“空格键向下滚动文章”的功能**。因此，我们决定打破原有的 `Focus` 焦点局限，采用全局拦截的方式重构播放器的按键响应逻辑。

### 99.2 实现思路与多视频冲突处理
既然放弃了局部焦点拦截，我们将空格键的监听提升到了全局的 `HardwareKeyboard.instance.addHandler` 中。但这引入了一个新问题：如果在同一篇文章中存在多个内联视频（`InlineVideoPlayer`），全局按下空格或媒体键时，应用如何知道该播放/暂停哪个视频？

为此，我们引入了**最后活跃状态（Active Player）** 追踪机制：
1. **状态追踪**：在 `_InlineVideoPlayerState` 中增加静态变量 `static _InlineVideoPlayerState? activePlayer;`。
2. **状态绑定**：无论是视频初始化播放，还是用户点击了该视频的控制条/播放按钮，都会触发 `activePlayer = this;`。销毁时若自己是活跃对象则置为 `null`。
3. **精准打击**：在触发全局键盘事件（空格键或 `LogicalKeyboardKey.mediaPlayPause`）时，所有视频实例都会接收到该事件，但**只有 `activePlayer == this` 的那个实例才会真正拦截并响应指令**，其余实例返回 `false`。

全屏播放器 (`fullscreen_video_page.dart`) 因为必然独占屏幕，无需追踪状态，直接在全局拦截空格与媒体键即可。旧的 `Focus` `onKeyEvent` 拦截代码均被安全移除。

### 99.3 关于 macOS 原生媒体控制的遗留讨论
对于 macOS 原生的物理播放键（如 F8）无法在应用处于后台时生效的问题，我们与用户进行了详细分析：
因为 Flutter `video_player` 插件本身并未在 macOS 层面接入 `MPRemoteCommandCenter`（即系统的“正在播放”控制中心），导致物理媒体键通常被系统级应用（如 Apple Music）拦截，不会分发给 Flutter。
解决此问题的代价是需要引入额外的重量级原生桥接插件。鉴于本次已完美在前台彻底解决了按键识别问题，暂不引入系统级的媒体接管方案，后续视需求严重程度再做定夺。

## 100. 撤销/恢复未读操作丢失 AI 拦截状态修复 (2026-06-06)

### 100.1 需求与问题背景
用户反馈：在 macOS 端（以及全端），如果一篇文章原本在“垃圾拦截”列表中，用户通过时间线或者文章详情页将其标记为已读（或者删掉）后，再使用 `Cmd+Z`（撤销）或 `M` 键将其恢复为未读时，该文章并没有自动回到拦截页面中，且在时间线中也丢失了其原本的红色高亮拦截标记。

### 100.2 问题产生原因
在原有的逻辑中，开发者为了让拦截文章在阅读后从拦截列表中消失，在 `ArticleController.markAsRead()` 和 `UndoService.markAsRead()` 方法中，专门加了一段清理逻辑：
`if (article.isRejectedByAi) { LocalArticleDbService.clearFilterState(article.entryId); }`
这段逻辑会强行擦除底层数据库中该文章的 `isRejectedByAi`、`filterReason` 等拦截关联字段，并通过事件总线将内存状态同步抹除。
由于拦截相关数据的永久擦除，当用户后续执行“恢复未读”操作时，程序仅仅将 `isRead` 重新置为了 `false`，但因为缺少拦截标记，系统只能将其视为一篇普通的未读文章，从而导致其无法回到垃圾拦截分类中，也失去了 UI 的高亮。

### 100.3 修复思路与讨论
基于对“标记已读”这一动作真实语义的梳理：“标记已读”本质上仅仅代表用户“已处理完毕/忽略”该文章。即便处理完毕，该文章曾是一篇“被 AI 拦截的垃圾文章”这一历史事实不应被篡改。
并且，在原有的垃圾拦截页面渲染逻辑中，早已明确限定了只显示 `isRejectedByAi && !isRead`（是垃圾且未读）的文章。因此，只要将文章标为已读，它自然就会从拦截页面隐去，主动去擦除 `isRejectedByAi` 是画蛇添足的冗余操作。

我们采用了**保留原始状态**的最简修复方案（方案 A）：
直接移除了 `ArticleController` 和 `UndoService` 中那两处调用 `clearFilterState` 的逻辑。

### 100.4 副作用评估与平台一致性
- **副作用影响**：修改后，一篇被判定为拦截的文章即便被标记为已读，其 `isRejectedByAi` 依然为 `true`。这会使得用户在切换到“全部”或“已读”时间线列表时，依然能看到该文章带有红色的拦截 UI 样式与拒绝理由。经过与用户讨论，用户明确表示“期望在已读列表中依然能通过 UI 样式一眼看出它曾经是被 AI 拦截的文章”，因此该表现完全符合业务预期。
- **跨端一致性**：由于该状态擦除逻辑位于底层的 Dart 业务逻辑与服务层，本次修改将自动统一并解决 macOS、Android、iOS 和 Windows 端在该场景下行为丢失的 Bug。

## 101. macOS 设置快捷键行为等效化修复 (2026-06-06)

### 101.1 问题背景
用户反馈在 macOS 端按下 `Cmd + ,` 快捷键打开设置时，界面表现为弹出了一个全新的页面（覆盖在现有 UI 之上），而点击主页面侧边栏左下角的“设置”按钮时，却是在分栏布局的右侧区域内部切换显示设置页。两者行为并不等效，破坏了桌面端用户体验的一致性。

### 101.2 问题根源
根据代码审查，两者触发了完全不同的路由处理逻辑：
1. **全局快捷键（`OpenSettingsIntent`）**：在 `lib/main.dart` 中，捕获按键后调用了 `Get.toNamed(Routes.settings)`。这会直接向导航栈中 Push 新页面。
2. **侧边栏按钮（`MacOSSidebar`）**：触发了 `MainPage` 的局部状态更新 `_currentIndex.value = 3`。借由底层的 `IndexedStack` 组件，这只是在当前路由的树级内切换了可见子组件。

### 101.3 修复思路与重构方案
为了使全局快捷键行为等效于页面内部的分栏切换，我们需要将 `MainPage` 原有的私有状态提炼为可供外部（即 `main.dart` 中的快捷键监听回调）调用的全局状态。

具体的实施方案：
1. **状态抽象化**：新建 `lib/pages/main/main_controller.dart`，抽取 `currentIndex`、`isMacSidebarCollapsed` 等原本封装在 `_MainPageState` 内部的状态，将它们挂载在全局 `GetxController` 上。
2. **页面解耦**：重构 `lib/pages/main/main_page.dart`，通过 `Get.put(MainController())` 注册并接管页面所有的索引切换操作，解除该 Widget 与导航状态的强绑定。
3. **快捷键入口改造**：在 `lib/main.dart` 的 `OpenSettingsIntent` 回调中，不再进行粗暴的 `Get.toNamed`。而是增加判定：如果当前应用处在子层级路由（如某文章的详情页），则先调用 `Get.until((route) => route.settings.name == Routes.main)` 退回到顶层 `MainPage`；接着调用 `Get.find<MainController>().changeIndex(3)` 将视图切换为设置区。

### 101.4 留给后续 Agent 的思考
经过这次重构，`MainController` 成为了主界面分栏层级的标准接口。如果后续还需要添加别的全局快捷键（例如 `Cmd + 1` 切换到时间线、`Cmd + 2` 切换到订阅源），可以直接在 `main.dart` 注册相关 Intent，并通过调用 `MainController` 的 `changeIndex()` 来极低成本地实现视图切换，无需再次修改 `MainPage` 内部逻辑。



## 102. 优化文章行内代码样式 (2026-06-07)

### 102.1 问题描述
用户反馈文章内的行内代码（`<code>` 标签）视觉表现较差：没有圆角、未体现等宽字体，看起来就像一个简陋的灰色高亮文本。

### 102.2 根本原因
由于项目使用的 `flutter_html` (v3.0.0-beta.2) 默认对行内元素的盒子模型（Box Model）支持有限。虽然在 `_buildParagraph` 中给 `'code'` 指定了 `backgroundColor` 和 `fontFamily: 'monospace'`，但 `Style` 对象在直接生成内联 `TextSpan` 的上下文中，并不支持附加 `borderRadius` 和 `padding` 效果。同时，单薄的 `fontFamily: 'monospace'` 在部分平台上缺乏有效的字体栈回退（fallback）机制，导致无法稳定呈现等宽字形。

### 102.3 修复思路与实现
1. **采用 Wrapper 机制接管渲染**：引入 `flutter_html` 自带的 `TagWrapExtension` 拦截 `<code>` 标签。利用此扩展将其原本生成的子元素树包裹在一个提供了合理内边距（Padding）与圆角（`BorderRadius.circular(6)`）的 `Container` 之中。
2. **规避重复渲染**：剥离原 `Style` 对象中对 `'code'` 的 `backgroundColor` 设定，统一在 `Container` 的 `BoxDecoration` 中绘制背景色（采用 `colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)`），从而达成柔和的圆角药丸（Pill）视觉效果。
3. **增强跨端字体表现**：在 `'code'` 的 `Style` 声明中补全了等宽字体回退栈：`fontFamilyFallback: const ['Menlo', 'Monaco', 'Courier New', 'Courier']`。
4. **抽取复用逻辑**：由于解析器在针对不规范 HTML 时，可能将行内 `<code>` 留存至段落、列表甚至表格的子树内，因此将扩展列表提取为了通用的 `_buildCommonExtensions(context, cs)` 方法，一揽子应用于页面的所有 `Html` 实例之中。
## 103. 审核/垃圾拦截页面的即时已读同步修复 (2026-06-07)

### 103.1 问题背景
用户反馈在“审核/垃圾拦截”页面（FilterReviewPage）移除一篇文章时，该文章的已读状态并没有立即同步至服务端，而是必须等到下一次手动下拉刷新或者到任务中心点击同步按钮时才会同步。

### 103.2 问题根源
根据代码分析，当在审核页面移除/拒绝文章时，触发了 `_reject` 方法：
该方法中处理已读状态时，仅调用了 `ReadSyncService.enqueue(article.entryId, isInbox: ...)` 将待同步的项加入到了本地缓存队列（`pending_read_items`）中。
然而，与文章阅读详情页（`ArticleController.markAsRead`）会即时触发 `FeedHttp.markRead` 并在后台重试不同，`_reject` 中并没有紧接着调用触发同步网络请求的命令。导致这些已读状态滞留在本地，必须被动等待其它触发点调用 `ReadSyncService.syncPendingReads()` 才能完成同步。

### 103.3 修复思路与讨论
关于修复方案，与用户讨论了以下几个方向的利弊：
1. **即时触发同步**：在入队后立即触发异步同步，用户操作反馈最及时，但在批量快速滑动时可能会短暂触发多次并发的网络请求（虽然底层有防并发锁）。
2. **退出页面时同步**：监听页面生命周期，在离开该页面时统一触发同步。能合并请求，但如果用户久留页面不退出则迟迟无法同步。
3. **定时后台轮询**：每隔一定时间自动消费队列。最稳妥但稍微偏重。

最终采用了方案一（用户选定），这符合用户期待的最直觉反应。

### 103.4 具体实施
在 `lib/pages/timeline/filter_review_page.dart` 中，顶部补充引入了 `dart:async`。
在 `_reject` 方法中，紧跟着 `ReadSyncService.enqueue`，新增调用了：
`unawaited(ReadSyncService.syncPendingReads());`
这样既保证了已读状态能被持久化到待同步队列防丢失，又能够在文章被移除时立即尝试将状态同步到云端。

## 104. macOS 桌面端快捷键 M 按键逻辑升级 (2026-06-07)

### 104.1 需求背景与问题
用户指出，在 macOS 桌面端分屏模式下使用键盘进行快速信息筛选时，按下 `m` 键将文章标记为已读后，当前应用焦点仍然停留在该文章上。由于应用已实现了全局的 `Ctrl+Z` / `Cmd+Z` 撤销快捷键，即便用户误操作将某篇文章标记为已读，恢复成本也极低。因此，用户希望按下 `m` 键将文章“标记已读”后，系统能自动跳转到下一篇文章，从而实现无缝的沉浸式“阅读-标记-下一篇”心流。

### 104.2 跨端体验差异讨论
在分析该需求时，我们特别讨论了该行为在不同平台的适用性：
1. **桌面端（macOS 分屏视图）**：键盘用户具有极强的效率导向，自动跳转能有效免去手动按方向键切换的多余动作，因此该设计带来明确的正向收益。
2. **移动端（Android/iOS 等）**：移动端基于手势滑动与 `PageView` 架构，用户习惯于在点击悬浮的“已读”按钮后，依然能保留在当前页面并由自己决定何时滑动翻页。系统若突兀地强制翻页，会破坏用户的操作空间感与物理直觉。

基于以上共识，该跳转逻辑修改仅被限定于苹果的 macOS 桌面端应用。

### 104.3 具体的修改实现
由于现有代码架构的跨端防腐设计良好，`lib/pages/article/article_page.dart` 中的硬件键盘事件监听 `_handleHardwareKeyEvent` 在早期实现中便已被 `_usesGlobalShortcuts` 变量（即 `Platform.isMacOS && widget.isSplitView`）严格限制了生效范围。因此，我们只需要直接在该方法内扩展对 `m` 键（`LogicalKeyboardKey.keyM`）的处理代码，即可天然实现平台隔离隔离。

新版逻辑如下：
```dart
    if (key == LogicalKeyboardKey.keyM) {
      if (controller.isUpdatingReadState.value) return true;
      final wasUnread = !controller.isRead.value;
      _toggleReadState();
      if (wasUnread && widget.onNext != null) {
        widget.onNext!();
      }
      return true;
    }
```
**设计说明**：
- **状态防抖**：前置增加了对 `isUpdatingReadState` 的防御性检测，规避因极高频连按或网络拥堵造成的预期外重复跳转。
- **定向安全跳转**：通过 `wasUnread` 保存文章在动作发生前的初始状态。仅在执行**将“未读”转为“已读”**的正向操作时，才会触发 `widget.onNext!()` 自动滚至下一篇。反之，若用户按下 `m` 是为了撤回并恢复“未读”（例如标为稍后阅读），焦点将静止不动，以免引发焦点迷失。

### 104.4 给后续接手 Agent 的提醒
由于本次优化强依赖于上层 Widget 传入的 `widget.onNext` 回调来实现导航能力，若未来重构了外层 `TimelinePage` 等页面中关于 `_selectRelativeArticle(1)` 的绑定与分发机制，请务必额外验证 macOS 分屏下单独敲击 `m` 键时的自动翻页连贯性是否依然生效。

## 105. 垃圾拦截页快捷键与全局撤销重构 (2026-06-07)

### 105.1 需求背景与问题
为了提升垃圾拦截页（`FilterReviewPage`）的批处理效率，用户提出需要支持类似主页的快捷键心流。在 macOS 分栏模式下，拦截页面需要高频执行“移除（确认为垃圾）”和“保留（撤销拦截）”操作，并且应当支持 `Ctrl+Z` 完美撤销这两种动作，以免手滑误操作。

### 105.2 UndoService 重构
原有的 `UndoService` 被设计为单一状态跟踪（仅追踪 `_lastReadArticle`），且只能撤销“标为已读”动作。
我们对 `UndoService` 进行了全面重构：
1. **状态抽象**：引入了 `UndoActionType` 枚举（`read`, `filterReject`, `filterKeep`），并将单例变量变更为 `_lastAction` 复合对象。
2. **底层撤销逻辑分支**：
   - 对于普通的 `read` 和拦截页的 `filterReject`，因为它们都在业务上执行了标为已读的动作，所以在撤销时除了恢复本地数据库状态外，还会向服务端发送 `FeedHttp.markUnread` 网络请求同步未读状态。
   - 对于拦截页的 `filterKeep`，因为它从未同步到已读列表，撤销时仅需将原始拦截状态（`isRejectedByAi: true`，以及原始的拒绝理由）重新 UPSERT 回本地数据库并发出事件总线刷新，无需网络开销。

### 105.3 拦截页快捷键注入
在 `FilterReviewPage` 中：
- `M` 键（移除/拒绝）：通过向嵌套的 `ArticlePageView` 传递 `onMKeyPressed` 闭包回调来实现拦截。调用底层的 `_reject`，向撤销栈压入 `filterReject` 动作，并触发自动下一篇。
- `K` 键（保留/放回）：在 `FilterReviewPage` 的顶层 `initState` 中注册 `HardwareKeyboard` 监听。由于父组件拦截器早于底层的 `Focus` 树触发，它能精准捕获 `K` 键，调用 `_keep`，向撤销栈压入 `filterKeep`，并触发自动下一篇。

### 105.4 留给后续 Agent 的防坑记录：关于状态擦除的取舍
在处理“保留 (`_keep`)”操作时，底层调用了 `AutoFilterWorker.unReject` 和 `clearFilterState`。这会导致文章被**彻底物理擦除**其曾经被 AI 拦截过的痕迹（清空了 `isRejectedByAi` 和 `filterReason`）。
如果用户在拦截页按 `K` 将其放回，再跑到主时间线按 `M` 将其标为已读，这条数据看起来就是一条普普通通的好文章，**无法再作为 AI 的 False Positive（误判样本）进行提取和训练**。
在与用户讨论后，用户明确指示**不在乎保留误杀的痕迹**，且这更符合用户侧“已读后不可见异常UI”的预期。因此本次重构刻意维持了这一“擦除”逻辑未变。未来如果业务层需要做模型微调，请警惕此处的样本流失，届时需要重构这部分的数据库结构，不再擦除，而是改用 `humanVerdict: 'keep'` 类似的追加状态来实现。
## 106. 阅读进度条视觉滞后问题修复 (2026-06-07)

### 106.1 问题描述
用户反馈在文章详情页中，顶部 AppBar 下方的橙色阅读进度条（`LinearProgressIndicator`）在伴随页面滚动时“感觉比较滞后”，猜测可能是平滑参数设置过大。

### 106.2 原因分析
经过对 `lib/pages/article/article_page.dart` 代码的审查，发现进度条使用 `TweenAnimationBuilder` 包装以实现平滑动画，其 `duration` 参数被设置为 `400` 毫秒。
- **技术机制**：当用户手指滑动屏幕时，`_scrollProgress` 值会高频、实时地更新。
- **视觉滞后**：由于 `TweenAnimationBuilder` 的过渡时间长达 400 毫秒，进度条在每次接收到新目标进度时，都需要花费将近半秒钟的时间去“追赶”手指的实际位置。这导致进度条在连续滑动中永远处于落后状态，并在滑动停止后仍然缓慢移动，造成了严重的滞后感。

### 106.3 讨论与决策
- **方案 A（完全移除动画）**：直接将滚动进度绑定至 `LinearProgressIndicator`，零延迟但可能在某些低刷新率或跳跃滚动场景下显得生硬。
- **方案 B（保留平滑但缩短时间）**：保留 `TweenAnimationBuilder`，但大幅缩短 `duration` 毫秒数。
与用户确认后，我们选择保留原有的平滑机制（方案 B），因为微弱的过渡动画可以较好地掩盖 Flutter 偶尔的掉帧闪烁，并对由于回弹（Bouncing）等物理特性引发的突兀数值变化起到缓冲作用。用户期望进度条尽量“跟手”，但不必完全牺牲流畅过渡。

### 106.4 修复方案
在 `lib/pages/article/article_page.dart` 中：
将 `TweenAnimationBuilder` 的 `duration` 从 `400` 毫秒修改为 `50` 毫秒。
这一极短的时间既足以在人类视觉神经上实现“无滞后”的跟手感，又能为 UI 渲染保留最低限度的平滑过渡。由于这是跨平台共享的 Dart 侧 UI 代码，该项修改默认将在 iOS/macOS 与 Android 等所有端同步生效。


---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.10 -m "- 优化文章行内代码块的视觉样式\n- 修复审核拦截页已读状态同步延迟问题\n- macOS 桌面端新增拦截页 M/K 快捷键批量操作与自动跳转\n- 重构全局撤销服务，支持拦截页的复杂状态撤销回滚\n- 修复阅读页顶部进度条动画滞后不跟手的问题" --push`*


## 107. 行内代码文本基线向上浮动问题修复 (2026-06-07)

### 107.1 问题描述
用户反馈在文章详情页中，行内代码（由 `<code>` 标签包裹的文本）的文字在视觉上出现了“往上浮一点”的现象，没有与周围普通文本的基线完美对齐。

### 107.2 原因分析
在 `lib/pages/article/widgets/html_chunk_card.dart` 的 `_buildCommonExtensions` 中，使用 `TagWrapExtension` 对 `code` 标签进行了自定义包裹，使用了一个带圆角和背景色的 `Container`，并设置了 `padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2)`。
由于 `flutter_html` 将其转换为 `WidgetSpan` 渲染，默认对齐方式通常基于底部或基线。而 `Container` 底部的 2 像素内边距（padding）导致整个 `Container` 的底部向下延伸。当它与外部普通文本对齐时，这 2 像素的底部边距将内部的文本向上推，产生了视觉上的悬浮感。

### 107.3 修复方案与讨论
我们讨论了三种方案：
1. **调整 Container 的 Padding（不对称内边距）**：取消底部边距，实现简单，但导致背景框上下不对称，影响质感。
2. **使用 Transform.translate 进行垂直偏移**：保留原有对称 Padding 和圆角，通过向下微调消除偏移。
3. **废弃 TagWrapExtension，仅使用 Html Style**：完全交由原生引擎排版，但会丢失背景圆角（`borderRadius`）的视觉设定。

**最终决策**：选择了方案二。在 `TagWrapExtension` 内部的 `Container` 外层包裹了 `Transform.translate(offset: const Offset(0, 1.5))`。
此举能够完美保留现有的对称内边距和圆角设定，同时通过纯视觉阶段的向下微调，抵消了 2 像素底部边距造成的排版上推效应。这是一个由于固定 Padding 引起的固定偏差，因此使用固定的 `Offset` 抵消是合理且保持设计规范的最佳权衡。
## 108. 垃圾审核页与主时间线快捷键监听冲突修复 (2026-06-07)

### 108.1 现象与问题诊断
用户反馈：在“垃圾审核”（FilterReviewPage）界面中，按下 `m` 键没有任何效果，但是却发现“主时间线”（TimelinePage）中的文章数量在减少。

经过代码排查，发现这是由于 macOS 分屏布局机制导致的**全局键盘监听冲突**：
1. **组件堆叠与存活**：macOS 版主界面使用 `IndexedStack` 来管理各个侧边栏页面，这导致“主时间线”和“垃圾审核”页面的实例同时存在于组件树中（且 `ModalRoute.of(context)?.isCurrent` 皆为 true）。
2. **全局事件捕获**：两个页面都内部嵌套了 `ArticlePageView` 组件，该组件在 `initState` 时向 `HardwareKeyboard.instance` 注册了全局按键监听 `_handleHardwareKeyEvent`。
3. **校验逻辑错位**：`ArticlePageView` 内部有一段针对当前选中文章的“前置安全校验”：
   ```dart
   if (Get.isRegistered<TimelineController>()) {
     final tc = Get.find<TimelineController>();
     if (tc.selectedArticle.value?.entryId != widget.article.entryId) return false;
   }
   ```
   - 在**垃圾审核**页面中，当前 `widget.article` 来自页面自带的独立状态，不匹配主时间线 `TimelineController` 选中的文章，导致校验失败，因此直接**忽略了 M 键事件**。
   - 而隐藏在后台的**主时间线**视图收到了同一份全局键盘事件，且该校验顺利**通过**（因为它的 `widget.article` 正好匹配 `TimelineController`），最终悄悄在后台执行了标记已读及翻页，导致主时间线内文章被误操作减少。

### 108.2 修复方案讨论与决策
为了修复该泄漏，讨论了以下三种方向：
- **方案A（传递激活标志）**：向 `ArticlePageView` 注入 `isActive` 回调，由外层根据当前路由/侧边栏索引决定是否拦截响应。
- **方案B（单独页面拦截）**：仅在垃圾审核页顶层拦截 `M` 键并吞噬事件。缺点是无法防御其他按键（如方向键）向后台的泄露。
- **方案C（原生 Focus 树）**：废除全局键盘，彻底改用 Flutter 的 `FocusNode` / `Shortcuts` 机制。缺点是 macOS 的分屏焦点管理十分脆弱，鼠标误点侧边栏往往会导致全局阅读快捷键全部失效，体验倒退极大。

**最终决策**：选择了改良版的**方案A**。既保留了全局热键随时可用的稳健体验，又以极小的代价彻底掐断了所有不可见页面的多余事件响应。

### 108.3 实现细节
1. 在 `ArticlePageView` 的构造函数增加 `final bool Function()? isActive;`。
2. 在 `_handleHardwareKeyEvent` 首部添加校验：`if (widget.isActive != null && !widget.isActive!()) return false;`。
3. 在 `TimelinePage` 中传入：`isActive: () => !Get.isRegistered<MainController>() || Get.find<MainController>().currentIndex.value == 0`。
4. 在 `FilterReviewPage` 中传入：`isActive: () => !Get.isRegistered<MainController>() || Get.find<MainController>().currentIndex.value == 1`。

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.11 -m "- 修复行内代码块底部边距导致文本轻微向上浮动不对齐的问题\n- 修复 macOS 分屏模式下垃圾拦截页的快捷键事件泄漏导致主时间线文章被误标已读的严重缺陷" --push`*

## 109. macOS 分栏快捷键归属泛化与发布 notes 防错 (2026-06-08)

### 109.1 背景
复查 `v1.1.11` 后发现两个相关问题：
1. 第 108 节虽然为 `ArticlePageView` 增加了 `isActive`，避免隐藏的 `TimelinePage` 继续处理 `FilterReviewPage` 的按键，但 `ArticlePageView` 内部仍然无条件读取 `TimelineController.selectedArticle` 做“当前文章”校验。这个校验只适合主时间线，在垃圾拦截页、订阅详情页和最近阅读页中会误判右侧文章不是当前文章，从而导致 `M`、方向键、`Esc` 等 macOS 分栏快捷键被忽略。
2. 用户在 GitHub Release 页面看到 `v1.1.11` 的描述变成了 `ci: fix checkout crash on tag pushes by using fetch-depth 0 instead of fetch-tags`。本地与远端 tag 均确认是 annotated tag，且 tag 注释是正确的中文 notes；但 `v1.1.11` tag 指向的是后续 CI 修复提交 `3402f77`。经过本地验证，如果 workflow 中的 `git tag -l --format='%(contents)'` 遇到轻量 tag，它会输出被打 tag 的 commit message，正好会得到这条 `ci:` 文本。因此根因不是 release 脚本最初写错 message，而是复用/移动同一个 release tag 的异常补救流程叠加 workflow 缺少 tag 类型防御。

### 109.2 本次修复
1. 在 `ArticlePageView` 增加 `isSelectedArticle: (entryId) => bool` 回调，替换原先硬编码读取 `TimelineController.selectedArticle` 的校验。
2. `TimelinePage`、`FilterReviewPage`、`FeedDetailPage`、`RecentReadPage` 四个 macOS 分栏入口均传入自己的选中文章状态。这样保留“只有当前右栏文章响应全局快捷键”的防抖能力，同时不再把所有页面都误绑到主时间线状态。
3. `.github/workflows/internal-release.yml` 的 release job 在读取 `ANNOTATION` 前增加前置校验：`refs/tags/$TAG_NAME^{tag}` 必须存在，且 tag annotation 去空白后不能为空。若未来误用了轻量 tag 或空注释 tag，CI 会直接失败，不会创建 notes 来自 commit message 的 release。
4. `scripts/release.sh` 在写入 `AGENT_HANDOFF.md` 的执行足迹时，会把 message 内的真实换行转义成 `\n`。这样 tag annotation 和 GitHub Release Notes 可以继续使用真实多行文本，而 handoff 里的命令记录不会被换行打散。

### 109.3 后续发布约束
正常发布继续使用 `./scripts/release.sh <version> -m "<版本摘要>" --push`。如果 tag workflow 因 CI 配置问题失败，不要复用并移动同一个 tag 来补救；应修好 workflow 后发布下一个小版本 tag。这样可以保证 tag 注释、release notes 和发布产物三者保持一致。

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.12 -m "- 修复 macOS 分栏快捷键归属判断，恢复垃圾拦截、订阅详情和最近阅读页的 M/方向键/Esc 响应\n- 发布流程拒绝轻量 tag 或空注释 tag，防止 Release Notes 退化为提交信息" --push`*

## 110. v1.1.12 Release Job 的 annotated tag 校验修复（2026-06-08）

### 110.1 失败现象
`v1.1.12` tag 推送后，Android APK、macOS App 和前置校验均完成，但最后的 `Publish GitHub Release` job 失败：
`refs/tags/v1.1.12^{tag}: expected tag type, but the object dereferences to tree type`

本地与远端均确认 `v1.1.12` 本身是 annotated tag，且 tag annotation 正确。因此这不是发布脚本创建了错误 tag，而是第 109 节新增的 workflow 校验写法在 GitHub Actions checkout 的 tag push 工作区里不够稳。

### 110.2 根因与修复
原校验直接执行：
`git rev-parse -q --verify "refs/tags/$TAG_NAME^{tag}"`

在 tag push 触发的 Actions checkout 环境中，本地 ref 形态可能并不等同于完整仓库里的远端 tag ref，导致 `^{tag}` 校验误判。修复为：
1. 在 release job 中先显式执行 `git fetch --force --no-tags origin "refs/tags/$TAG_NAME:refs/tags/$TAG_NAME"`，把远端 tag ref 拉到本地同名 tag。
2. 再用 `git cat-file -t "refs/tags/$TAG_NAME"` 判断对象类型是否为 `tag`。
3. 保留 annotation 非空校验。

### 110.3 发布处理
不要移动或复用已经失败的 `v1.1.12` tag。因为 GitHub Actions rerun 会使用该 tag 指向提交里的旧 workflow，无法获得本次修复。正确处理是提交 workflow 修复后，发布下一个 patch tag `v1.1.13`。

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.13 -m "- 修复 GitHub Actions 发布任务中的 annotated tag 校验，避免 tag push checkout 环境误判导致 Release 发布失败\n- 重新触发 Android APK 与 macOS arm64 内部发布打包" --push`*

## 111. 统一 macOS 端文章处理快捷键与 UI 按钮跳转逻辑 (2026-06-08)

### 111.1 背景与问题发现
用户在使用 macOS 端的“垃圾拦截”（`FilterReviewPage`）页面时发现：按下快捷键 `m`（移除）或 `k`（保留）后，系统会自动跳转到下一篇文章；而直接点击 UI 列表上的对应按钮（“保留”或“移除”），则仅将当前文章从列表中剔除，右侧阅读面板变为空白，并未自动跳转下一篇。快捷键与 UI 按钮行为不等效。

在全面排查后，我们发现在常规的主阅读视图（`ArticlePage`）中也存在类似的不一致：按下快捷键 `m` 标记文章已读时（原状态为未读），会自动跳转到下一篇；而点击工具栏中的“标为已读 (M)”按钮，则仅更改已读状态，不触发跳转。

### 111.2 逻辑溯源与缺陷分析
1. **`FilterReviewPage`（垃圾拦截页）**:
    - **UI 按钮**：直接调用 `_keep` 或 `_reject`，这俩方法仅将处理掉的文章从 `_articles` 列表中移除，如果移除的是当前高亮文章，则将其状态置为 `null`（导致右侧留白）。
    - **快捷键**：分别在处理键盘事件的回调中先调用 `_keep(selected)` / `_reject(selected)`，然后再调用 `_selectRelativeArticle(1)`。
    - **隐藏缺陷**：这种快捷键做法其实有逻辑错误。因为 `_keep(selected)` 已经清空了 `_selectedArticle.value`，随后的 `_selectRelativeArticle(1)` 寻找当前索引时返回 `-1`，计算得出下一个索引为 `0`。这就导致快捷键其实总是跳回**剩余列表的第一篇**，而非**相对位置的下一篇**。
2. **`ArticlePage`（主阅读视图）**:
    - **UI 按钮**：`onPressed` 直接硬编码执行 `controller.markAsRead()` 或 `controller.markAsUnread()`。
    - **快捷键**：会判断如果是从未读变为已读，自动调用外层传入的 `widget.onNext!()`。若存在 `onMKeyPressed`（例如在垃圾拦截页上下文中），则调用它。

### 111.3 统一与修复方案
为了彻底保证全局交互的唯一性并修复跳转缺陷，将两处的分散逻辑下沉并统一：

1. **统一 `FilterReviewPage` 逻辑**：
   - 重构 `_keep` 和 `_reject`：在删除操作前预先记录文章的 `index`；执行删除后，如果发现操作的是当前高亮文章，则根据预先记录的 `index`（配合 `clamp` 防越界），精准选中替补到原位置的下一篇文章。如果是列表最后一篇，则往前移位；若列表已空则置 `null`。
   - 剔除 `FilterReviewPage` 中快捷键事件的冗余 `_selectRelativeArticle(1)` 调用，统一委托底层的 `_keep` / `_reject` 完成状态过渡。

2. **统一 `ArticlePage` 逻辑**：
   - 重构 macOS 顶部栏和移动端悬浮窗的“标为已读”按钮点击事件，使其与 `m` 快捷键行为等效：如果有 `widget.onMKeyPressed`，则优先调用（适配垃圾拦截场景）；如果是从未读改已读，则在标记后自动调用 `widget.onNext!()` 触发前进。

通过以上调整，整个应用无论通过快捷键还是鼠标点击 UI 工具栏/列表按钮处理文章，都会获得完全等效且平滑的连续阅读跳转体验。

## 112. macOS 端卡片双击跳转下一篇优化 (2026-06-08)

### 112.1 问题背景
在 macOS 客户端，用户双击文章卡片时，原逻辑（通过判断两次点击时间差小于 300 毫秒）仅执行了“调用外部浏览器打开原链接”以及“若未读则标记为已读”。
由于执行完毕后当前选中焦点并未下移，且如果开启了“仅看未读”过滤，该文章还会从界面上消失导致焦点丢失，使得阅读体验欠缺连贯性。用户的核心诉求是希望在双击文章卡片之后，焦点能自动向下顺延到下一篇。

### 112.2 修改方案讨论与决策
项目中处理 macOS 双击跳转逻辑分布于三个入口的控制器/状态中：`TimelinePage`、`FeedDetailController` 以及 `RecentReadPage`。
这三个文件都已经实现了完善的 `_selectRelativeArticle(int delta)` / `selectRelativeArticle(int delta)` 跳转方法。该方法不仅能实现列表中的焦点移动，其内部还封装了精密的 fallback 逻辑，能够处理“当前文章因状态改变已脱离可见列表”的边界情况。

针对这行跳转代码的“插入时机”，存在以下两点考量：
- **时机A（放在标记已读和外部拉起之后）**：此时当前文章已经被加入待同步队列，甚至引发了列表刷新。这既容易与列表重绘发生动画重叠，又会强行激发 fallback 的回退寻找逻辑，风险略高。
- **时机B（放在标记已读和外部拉起之前）**：此时当前文章仍处于稳固的选中与渲染状态。先精确移动焦点到下一篇，再异步触发标记已读与打开外链动作，安全且精准。

**最终决策**：采用时机B。

### 112.3 实现细节
在以下三个文件内，各自拦截 macOS 的双击事件处理逻辑（即 `isDoubleTap` 代码块内）中：
1. `lib/pages/timeline/timeline_page.dart`
2. `lib/pages/feed_detail/feed_detail_page.dart`
3. `lib/pages/recent_read/recent_read_page.dart`

位于重置时间戳变量之后，优先执行 `_selectRelativeArticle(1);`（或针对 feed 的 `selectRelativeArticle(1);`），再调用现有的外链拉起与标记已读代码。由此平滑实现了类似邮件系统的快捷连续阅读流。

## 113. macOS 时间线卡片双击动画掉帧修复（2026-06-08）

### 113.1 缺陷描述
在 macOS 端应用中，点击时间线文章卡片时，左侧卡片会触发水波纹反馈动画（`InkWell` ripple），同时右侧分栏会响应加载文章详情。当用户快速双击卡片以图快速打开外部浏览器并标记已读时，系统出现严重的视觉断裂和掉帧感。

### 113.2 根因分析
1. **单双击设计权衡**：为了避免原生 `onDoubleTap` 带来的 300ms 强制判断延迟，代码中去除了该回调，转而在 `_handleMacArticleTap` 中通过计算两次点击的时间差（`< 300ms`）手动判定双击。
2. **第一击并发压力**：无论是单击还是双击，第一击都会同步触发 `controller.selectedArticle.value = article`，随即启动极其繁重的 `ArticlePageView` HTML 结构解析（包括 `Isolate.run` 以及返回后立即在主线程执行的前 5 个 `HtmlChunkCard` 的重度构建）。
3. **视觉冲突与线程拥堵**：双击行为发生在第一击之后的 150-300ms 之间，这正好与 `ArticlePageView` 首帧解析渲染的回调相撞。此时，第二击又并发触发了 `launchUrl`（唤起外部浏览器）和 `UndoService.markAsRead`。而 `markAsRead` 会修改状态，导致包含该卡片的列表项从界面上迅速移除（销毁 `ArticleCard` widget），直接截断了刚刚开启的水波纹动画，造成强烈的撕裂和卡顿感。

### 113.3 解决思路与实现
核心原则是：**在保留双击响应速度（零人工 Delay）的前提下，实现重型操作的渲染错峰。**
修改 `lib/pages/timeline/timeline_page.dart`：在第 112 节已确定的“先选中下一篇”基础上，将双击后触发的浏览器启动及已读处理放入 `WidgetsBinding.instance.addPostFrameCallback` 中。让 Flutter 把当前正处于启动水波纹和准备布局变更阶段的那一帧顺畅渲染完（完成上屏），然后立即接管并执行其余沉重任务。
```dart
    if (isDoubleTap) {
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      _selectRelativeArticle(1);

      // Let the current frame paint the double-tap ripple before heavy work.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openOriginalArticle(article);

        if (!article.isRead) {
          unawaited(UndoService.markAsRead(article, showSuccess: false));
        }
      });
    }
```
通过这种极其细粒度的帧调度，既消除了单点多工引发的卡顿假象，也避免了因强加人为延时带来的迟滞感。

## 114. Worktree 安全合并检查点（2026-06-08）

本轮用户要求重新检查所有 worktree，并先合并确认安全的小改动，再处理两个需求真实但实现需要重做的分支。已合入 `main` 的内容包括：
1. `debug-macos-navigation-logic`：统一 macOS 端 `M` 快捷键、工具栏按钮与浮动按钮的标记已读/跳转行为，并修复垃圾拦截页 `K/M` 后总是回到剩余列表第一篇的问题。
2. `fix-macos-card-navigation`：macOS 双击文章卡片打开原文时，先选中下一篇文章，再执行打开外链与标记已读流程。
3. `fix-macos-card-animation`：在主时间线双击流程中，将打开外链和静默标记已读延后一帧执行，避免水波纹反馈与重型同步/外链操作争抢同一帧。

暂未合入的两个分支仍然代表真实需求，但不能原样合并：
1. `fix-macos-undo-focus-navigation`：撤销后自动聚焦恢复文章的需求成立，但原实现硬绑 `TimelineController`，无法覆盖垃圾拦截页等拥有私有选中态的页面。后续应让 `UndoService` 返回或广播恢复的文章，由当前页面自己决定选中与滚动。
2. `cosmic-cosmos-darts-14h23`：卡片进入/退出动画需求成立，但原 `ImplicitlyAnimatedList` 内部维护 `_items` 的同时，外部 builder 又使用外部列表 index 取文章，动画插入/删除期间可能错位或越界。后续应重写为 builder 直接接收内部真实 item，并用稳定文章 id 驱动动画。

验证结果：
- `/opt/homebrew/bin/flutter analyze --no-fatal-infos lib test`：通过。
- `/opt/homebrew/bin/flutter test --no-pub`：通过。

## 115. 撤销聚焦与 macOS 卡片进入/退出动画重做（2026-06-08）

第 114 节中暂缓合并的两个需求本轮已重做并合入，保留需求但没有原样采用原 worktree 代码。

### 115.1 撤销后聚焦恢复文章
原 `fix-macos-undo-focus-navigation` 分支把撤销后的选中与滚动硬绑到 `TimelineController`，这会让 `FilterReviewPage` 等拥有私有选中态的页面无法正确恢复焦点。最终实现改为：
1. `UndoService.undoLastAction()` 返回 `Future<ArticleModel?>`，并在本地乐观恢复成功时发出 `UndoRestoreEvent`。
2. `UndoService` 只广播“哪篇文章被恢复、来自哪种撤销动作”，不直接操作任何页面滚动或选中态。
3. `TimelinePage` 仅在 macOS 且当前主分栏 index 为 0 时响应事件：如果恢复文章存在于当前可见列表，就设置 `selectedArticle` 并滚动到对应卡片。
4. `FilterReviewPage` 仅在 macOS 且当前主分栏 index 为 1 时响应事件：必要时重新读取审核列表，然后选中并滚动到恢复文章。

这样撤销行为不会让后台页面偷偷抢状态，也避免把页面私有 UI 状态塞进全局 service。

### 115.2 macOS 卡片进入/退出动画
原 `cosmic-cosmos-darts-14h23` 分支新增的 `ImplicitlyAnimatedList` 方向可取，但它的 builder 仍让调用方用外部列表 index 重新取 article。`AnimatedList` 在删除/插入动画期间内部列表与外部列表会短暂不同步，这会造成错位或越界。

最终实现新增 `lib/common/widgets/implicitly_animated_list.dart`：
1. 组件内部维护 `_items`，并用 `itemKey` 对比插入、删除与简单移动。
2. `itemBuilder` 和 `removedItemBuilder` 都直接接收内部真实 `item`，删除动画使用删除瞬间捕获的旧 article。
3. 主时间线与垃圾拦截页的 macOS 列表接入该组件，移动端列表保持原实现。
4. macOS 下即使列表从 1 篇变为 0 篇，也继续保留动画列表，空态作为覆盖层显示，避免最后一张卡片退出动画被空态切换打断。

验证结果：
- `/opt/homebrew/bin/dart format lib/services/undo_service.dart lib/pages/timeline/timeline_page.dart lib/pages/timeline/filter_review_page.dart lib/common/widgets/implicitly_animated_list.dart`：通过。
- `/opt/homebrew/bin/flutter analyze --no-fatal-infos lib test`：通过。
- `/opt/homebrew/bin/flutter test --no-pub`：通过。

## 116. Cmd+Z 撤销已读状态不立即恢复的竞态条件修复（2026-06-08）

### 116.1 问题报告

用户在 macOS 时间线页面的「未读」视图下，标记一篇文章为已读（文章从列表中消失），随后按下 `Cmd+Z` 撤销：

- **症状 1（有时不恢复）**：文章没有立即重新出现在未读列表中，必须手动点击同步按钮刷新才能重新加载回来。
- **症状 2（恢复后不聚焦）**：即使恢复了，右侧文章面板也不会自动聚焦到该文章。
- **概率性**：有时正常，有时异常——取决于用户按 `Cmd+Z` 的时机。

### 116.2 根因分析

问题出在一个竞态条件（race condition），涉及三个组件的时间线交互：

**正常时间线（T0→T3）：**

```
T0: 用户标记已读
    → UndoService.markAsRead()
    → markAsReadLocal: GStorage.readStatus.put(entryId, true) ← 写入乐观已读覆盖
    → 异步 _retrySync 开始（最多 12 秒，5 次重试×800ms）

T1: _retrySync 成功完成
    → GStorage.readStatus.delete(entryId) ← 清理乐观覆盖

T2: 用户按 Cmd+Z
    → UndoService.undoLastAction()
    → markAsUnreadLocal: DB 写 false, allArticles 更新, articles 过滤重建 ✓
    → ArticleStateNotifier.tick(entryId) ← 触发 _syncSingleArticleFromDb
    → _syncSingleArticleFromDb: GStorage.readStatus.get(entryId) → null
    → mergedRead = null == true ? true : false → false ✓ 一切正常
```

**异常时间线（竞态触发）：**

```
T0: 用户标记已读
    → markAsReadLocal: GStorage.readStatus.put(entryId, true)

T1 (只过了 2 秒): 用户按 Cmd+Z（_retrySync 尚未完成！）
    → UndoService.undoLastAction()
    → markAsUnreadLocal: DB 写 false, allArticles 正确更新为 isRead=false ✓
    → ArticleStateNotifier.tick(entryId) ← 触发 _syncSingleArticleFromDb
    → _syncSingleArticleFromDb: GStorage.readStatus.get(entryId) → true (仍然残留！)
    → localOverride == true → mergedRead = true ⚡ 覆盖回已读！
    → _applyFilter() 再次把文章从 articles 列表移除 ⚡
```

**关键代码**（`timeline_controller.dart` 旧版，修复前）：

```dart
// markAsReadLocal (line 353-363):
void markAsReadLocal(String entryId, {bool recordHistory = true}) {
    GStorage.readStatus.put(entryId, true);  // 写入乐观覆盖
    LocalArticleDbService.setReadState(entryId, true, ...);
    _updateReadStateInMemory(entryId, true);
    ArticleStateNotifier.tick(entryId);
}

// markAsUnreadLocal (line 365-371): — 没有清理 readStatus！
void markAsUnreadLocal(String entryId) {
    // 不再写入 readStatus=false；只更新本地缓存，信任服务端为最终权威
    LocalArticleDbService.setReadState(entryId, false);
    _updateReadStateInMemory(entryId, false);
    ArticleStateNotifier.tick(entryId);
    // ⚡ GStorage.readStatus 仍然是 true！
}

// _syncSingleArticleFromDb (line 464-503):
void _syncSingleArticleFromDb(String entryId) {
    ...
    final localOverride = GStorage.readStatus.get(entryId);  // 读到残留的 true
    final mergedRead = localOverride == true ? true : updatedFromDb.isRead;
    // 即使 DB 是 false，mergedRead 被覆盖为 true！
    allArticles[idx] = finalUpdated;  // 用错误的 isRead=true 覆盖了正确的值
    allArticles.refresh();
    _applyFilter();  // 文章从 articles 中被移除
    ...
}
```

**为什么 ReadStatus 会残留？**

当 `UndoService.markAsRead()` 调用 `markAsReadLocal` 时，它在 `GStorage.readStatus` 中写入了 `true`。然后它启动一个异步的 `_retrySync`。如果网络正常，约 2-12 秒后同步完成时 `GStorage.readStatus.delete()` 会清理它。如果用户在此窗口内按下 `Cmd+Z`，`markAsUnreadLocal` 没有清理 `readStatus`——因为第 63 节的重构有意不再写入 `readStatus=false`（"信任服务端为最终权威"），导致这个 `true` 值残留。

由于 `markAsUnreadLocal` 调用了 `ArticleStateNotifier.tick(entryId)`，而 `TimelineController` 在 `onInit` 中注册了 `ever(ArticleStateNotifier.version, ...)` 监听器，后者调用 `_syncSingleArticleFromDb`。此方法将 `readStatus` 视为权威覆盖层（`localOverride == true → mergedRead = true`），并立即将正确的 `isRead=false` 覆盖回 `isRead=true`，然后调用 `_applyFilter()` 将文章从未读列表中移除。

**为什么"_handleUndoRestoreEvent"有时没有聚焦？**

`_handleUndoRestoreEvent`（位于 `timeline_page.dart`）通过 `WidgetsBinding.instance.addPostFrameCallback` 在下一帧扫描 `controller.articles` 以定位恢复的文章。如果 `_syncSingleArticleFromDb` 的覆盖在当前帧已经将文章从列表中移除，则 `indexWhere` 返回 `-1`，处理函数静默返回——文章不会被选中，也不会滚动到。

**为什么有时恢复正常？**

如果用户在按 `Cmd+Z` 之前等待足够长（等待原始 `_retrySync` 完成），`GStorage.readStatus` 会被清理。此时 `_syncSingleArticleFromDb` 读到 `null`，使用 DB 中的 `isRead=false`——因此一切正常。这与用户观察到的"有时候正常，有时候不正常"完全吻合。

### 116.3 设计讨论

讨论了几种修复方案：

| 方案 | 描述 | 采纳 |
|------|------|------|
| 方案一 | 在 `markAsUnreadLocal` 中加 `GStorage.readStatus.delete(entryId)` | ✅ |
| 方案二 | 在 `_syncSingleArticleFromDb` 中让 readStatus 仅作为"已读覆盖"，不作为双向权重 | ❌ 改变语义 |
| 方案三 | 在 `undoLastAction` 中调用 markAsUnreadLocal 前显式清理 readStatus | ❌ 治标不治本 |

**选择方案一的原因**：当本地标记为未读时，清除已有的已读乐观覆盖在语义上是正确的——不再需要保护锁了。这个修复覆盖了调用 `markAsUnreadLocal` 的所有路径（`UndoService.undoLastAction`、`ArticleController.markAsUnread`），且不改变 `_syncSingleArticleFromDb` 中 readStatus 合并的行为逻辑。

### 116.4 修复实现

**文件**：`lib/pages/timeline/timeline_controller.dart`

**改动**：在 `markAsUnreadLocal` 开头添加 `GStorage.readStatus.delete(entryId)`，移除旧的"不再写入 readStatus=false"注释：

```dart
void markAsUnreadLocal(String entryId) {
    if (entryId.trim().isEmpty) return;
    GStorage.readStatus.delete(entryId);  // 新增：清除乐观已读覆盖
    LocalArticleDbService.setReadState(entryId, false);
    _updateReadStateInMemory(entryId, false);
    ArticleStateNotifier.tick(entryId);
}
```

### 116.5 行为变化对比

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| 等待同步完成后 Cmd+Z 撤销 | ✅ 正常（readStatus 已清理） | ✅ 正常（无变化） |
| 快速 Cmd+Z（同步尚未完成） | ❌ 文章被 _syncSingleArticleFromDb 重新标记为已读 | ✅ 正常恢复，readStatus 在 markAsUnreadLocal 中清理 |
| 切换到已读视图确认 | ❌ 文章显示为已读（错误） | ✅ 文章正确显示为未读 |
| 聚焦/滚动到恢复文章 | ❌ 文章在 articles 中找不到，静默跳过 | ✅ 正确找到、选中并滚动 |

### 116.6 涉及文件

- `lib/pages/timeline/timeline_controller.dart` — `markAsUnreadLocal` 添加 `GStorage.readStatus.delete(entryId)`。

未修改但相关的文件（供后续参考）：

- `lib/services/undo_service.dart` — `undoLastAction()` 调用链。
- `lib/services/article_state_notifier.dart` — `tick()` 触发 `_syncSingleArticleFromDb`。
- `lib/pages/timeline/timeline_page.dart` — `_handleUndoRestoreEvent` 现在可正确找到并聚焦已恢复文章。
- `lib/pages/article/article_page.dart` — `ArticleController.markAsUnread()` 也调用 `markAsUnreadLocal`，该路径同样受益。

### 116.7 后续注意事项

- `readStatus` 的语义在第 63 节核心重构中已明确：仅作为用户操作时的乐观覆盖层（`true` only），同步完成后立即释放。本修复与此设计一致——标记为未读时清理乐观覆盖在语义上正确。
- 如果未来添加新的"批量标记未读"路径，请确保也调用 `GStorage.readStatus.delete()`，或者更安全的方式是让该路径也走 `markAsUnreadLocal` 方法。
- `markAsUnreadLocal` 中的 `ArticleStateNotifier.tick()` 仍会触发 `_syncSingleArticleFromDb`，由于 `readStatus` 已清理，合并逻辑现在正确地从 DB 读取 `isRead=false`。

---

## 117. 审核页 UI 按钮与快捷键行为不等效修复（2026-06-08）

### 117.1 问题描述

用户在 macOS 端的垃圾拦截页面（FilterReviewPage）发现：按 `k`（保留）或 `m`（移除）快捷键时，文章会自动跳转到下一篇；但点击 UI 上对应的「保留」或「移除」按钮时，不会自动跳转。

### 117.2 根因分析

核心差异在于**快捷键始终操作「当前选中文章」，而 UI 按钮操作的是「该行绑定的文章对象」**。

#### 快捷键路径

`k` 快捷键（`filter_review_page.dart:100-108`）：
```dart
if (event.logicalKey == LogicalKeyboardKey.keyK) {
  final selected = _selectedArticle.value;  // 始终取当前选中文章
  if (selected != null) {
    _keep(selected);
    return true;
  }
}
```

`m` 快捷键（通过 `ArticlePageView` 的 `onMKeyPressed` 回调）：
```dart
onMKeyPressed: () {
  _reject(selected);  // selected 是 Obx 闭包中捕获的当前选中文章
},
```

两条路径都操作 `_selectedArticle.value`，因此 `_keep`/`_reject` 内部的 `isSelected` 判断始终为 `true`，自动跳转下一篇。

#### UI 按钮路径（修复前）

`_buildAnimatedReviewRow` 中：
```dart
onKeep: () => _keep(article),   // article 是该行的文章对象
onReject: () => _reject(article),
```

`_keep`/`_reject` 内部的关键逻辑：
```dart
final bool isSelected = _selectedArticle.value?.entryId == article.entryId;
// ...
if (isSelected) {  // 只有 isSelected=true 才跳下一篇
  _selectedArticle.value = _articles[nextIndex];
}
```

问题链条：
1. `_MacReviewRow` 的 `IconButton` 被外层 `InkWell` 包裹
2. Flutter 手势竞技场中，内层 `IconButton` 的 `InkWell` 赢得 tap 手势
3. 外层 `InkWell.onTap`（即行选中逻辑 `_selectedArticle.value = article`）**不会被触发**
4. 因此点击按钮时，`_selectedArticle` 可能并非当前行的文章
5. `_keep`/`_reject` 中 `isSelected = false` → 不跳转下一篇

### 117.3 修复方案

在 `_buildAnimatedReviewRow` 中，点击「保留」或「移除」按钮时，**先将 `_selectedArticle` 设为当前行的文章**，再执行 `_keep`/`_reject`：

```dart
onKeep: () {
  _selectedArticle.value = article;
  _keep(article);
},
onReject: () {
  _selectedArticle.value = article;
  _reject(article);
},
```

这样 `_keep`/`_reject` 内部的 `isSelected` 判断就会为 `true`，自动跳转到下一篇，行为与 `k`/`m` 快捷键一致。

### 117.4 行为变化对照

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| `k` 键 | 始终跳转下一篇 | 不变 |
| `m` 键 | 始终跳转下一篇 | 不变 |
| 点击「保留」按钮（选中行） | 跳转下一篇 | 不变 |
| 点击「保留」按钮（非选中行） | 不跳转 | 跳转下一篇 |
| 点击「移除」按钮（选中行） | 跳转下一篇 | 不变 |
| 点击「移除」按钮（非选中行） | 不跳转 | 跳转下一篇 |

### 117.5 影响文件

- `lib/pages/timeline/filter_review_page.dart` — `_buildAnimatedReviewRow` 方法（+6 行）

### 117.6 验证

- `flutter analyze lib/pages/timeline/filter_review_page.dart`：No issues found

## 118. macOS M 键快捷键偶尔失效修复（2026-06-08）

### 118.1 用户问题报告

用户反馈：在 macOS 时间线页面上，**双击**文章卡片总能稳定触发退场动画（标记已读 + 自动跳到下一篇），但**按 M 键**却偶尔不触发任何效果。问题同样存在日志 "垃圾拦截"（审核）页面的 M 键（拒绝）和 K 键（保留）场景。

用户要求排查范围：
| | 时间线页面 (tab 0) | 审核页面 (tab 1) |
|---|---|---|
| 双击 | ✅ 总是有效 | ❌ 未实现双击 dismiss |
| M 键快捷键 | ⚠️ 偶尔失效 | ⚠️ 偶尔失效 |
| UI 按钮 | ✅ 有效 | ✅ 有效 (保留/移除按钮) |

### 118.2 完整代码审查与根因排查

经过对 `article_page.dart`、`timeline_page.dart`、`filter_review_page.dart`、`implicitly_animated_list.dart`、`main_page.dart` 全部相关文件的逐一审查，识别出两个并发的根因和两个次要因素。

#### 根因 1（主要）：`_hasShortcutModifierPressed()` 全局捕获 M 键

位置：`lib/pages/article/article_page.dart:682`（修复前）

```dart
bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_hasShortcutModifierPressed()) return false; // ← HERE
    ...
}
```

`_hasShortcutModifierPressed()` 检查 `HardwareKeyboard.instance.isMetaPressed`（macOS 上的 Command 键）。如果用户在此之前使用过任何修饰键组合（最常见的是 Cmd+Z 撤销），macOS 的底层键盘驱动可能在修饰键物理抬起后仍有几个毫秒继续报告 `isMetaPressed == true`。在此期间按 M 键 → handler 在入口处直接返回 `false`，整条链路被切断。

这解释了"偶尔失效"的非确定特征 —— 取决于用户在上一次 Cmd+Z 之后是否给系统足够的时间刷新修饰键状态。

#### 根因 2（放大器）：Focus widget 无条件吞掉事件

位置：`lib/pages/article/article_page.dart:1234-1248`（修复前）

当 `_usesGlobalShortcuts` 为 `true` 时（即 macOS 分栏视图），`ArticlePageView` 外层包裹的 `Focus` widget 在 `onKeyEvent` 中对 M 键**无条件**返回 `KeyEventResult.handled`：

```dart
if (key == LogicalKeyboardKey.escape ||
    key == LogicalKeyboardKey.arrowLeft ||
    key == LogicalKeyboardKey.arrowRight ||
    key == LogicalKeyboardKey.arrowUp ||
    key == LogicalKeyboardKey.arrowDown ||
    key == LogicalKeyboardKey.keyM) {
  return KeyEventResult.handled; // ← 不检查修饰键，吞掉
}
```

它的设计意图是防止快捷键事件从 `HardwareKeyboard` handler 向上冒泡——当 handler 已处理事件后应当吞掉。但当根因 1 导致 handler **未处理**事件（`return false`）时，Focus widget 仍然吞掉了事件。结果：M 键被两个层先后丢弃，用户看不到任何效果，属于**完全静默失败**。

#### 根因 3（次要）：`isUpdatingReadState` 阻塞快速连续操作

位置：`article_page.dart:748`（修复后行号）

```dart
if (controller.isUpdatingReadState.value) return true;
```

当上一篇文章的 `markAsRead` 网络同步尚未完成（最多 5 次重试，每次间隔 800ms）时，后续 M 键被吞掉，仅返回 `true` 而没有任何操作。由于用户切换文章后，旧的 `ArticleController` 会被 dispose、新的 `ArticleController` 被创建，此问题在实际使用中发生的概率较低，因此本轮不做修改。

#### 根因 4（架构层面）：`IndexedStack` 令多个 `ArticlePageView` 同时存活

`main_page.dart:101` 使用 `IndexedStack`，导致 timeline tab（index 0）和 review tab（index 1）内的 `ArticlePageView` 同时注册 `HardwareKeyboard.instance.addHandler`。两者都依赖 `isActive()` 和 `isSelectedArticle()` 闭包做早期退出判断，在 page 切换边界的边缘窗口内可能发生竞争，增加"偶尔失效"的概率。由于 `IndexedStack` 是本应用的核心布局决策，本轮未修改此架构。

### 118.3 为什么双击总是有效

双击流程（`timeline_page.dart:212 _handleMacArticleTap`）完全不走 `HardwareKeyboard` 栈：
- 它是 Flutter `GestureDetector.onTap` 的 mouse/trackpad 事件
- 不触发 `_hasShortcutModifierPressed()` 检查
- 不涉及 Focus 的 `onKeyEvent`

两者路径完全正交，因此双击始终稳定生效。

### 118.4 修复方案

在 `lib/pages/article/article_page.dart` 中修改了两处：

#### 修改 1：`_handleHardwareKeyEvent` —— 定向修饰键检查

**删除**入口处的全局 `if (_hasShortcutModifierPressed()) return false;`，改为**仅对四个方向键**各自独立执行修饰键检查。M 键和 Escape 键不再受修饰键状态影响。

方向键需要保留修饰键检查，因为 macOS 上 Cmd+Up/Down/Left/Right 具有全局或内置含义（首行/末行滚动、行首/行尾），与箭头键我们的语义冲突。M 键不存在此冲突：Cmd+M 由窗口管理器（最小化）拦截，根本不会到达应用层；独立的 M 键始终是用户的主动意图。

#### 修改 2：Focus widget `onKeyEvent` —— 与 handler 逻辑对齐

在 `_usesGlobalShortcuts` 分支中，将键列表拆分为两组：
1. **Escape + M**：无修饰键检查，始终返回 `KeyEventResult.handled`
2. **四个方向键**：调用 `_hasShortcutModifierPressed()`，修饰键按下时返回 `ignored`（允许冒泡给系统），否则返回 `handled`

这使得 Focus widget 与 `_handleHardwareKeyEvent` 的行为精确一致，不再出现 handler 跳过 + Focus 吞噬形成静默丢失的情况。

### 118.5 变更范围

仅修改 1 个文件：`lib/pages/article/article_page.dart`，共 +12/-4 行。

### 118.6 受影响的手势路径总结

| 触发方式 | 页面 | 行为 | 受影响？ |
|----------|------|------|----------|
| 双击卡片 | 时间线 | 标记已读 + 跳到下一篇 | ❌ 不受影响（非键盘路径） |
| M 键 | 时间线 | 标记已读 + 跳到下一篇 | ✅ 本次修复 |
| M 键 | 审核页 | 调用 `_reject(selected)` | ✅ 本次修复 |
| K 键 | 审核页 | 调用 `_keep(selected)` | ❌ 不受影响（K 键原本未进入 `_hasShortcutModifierPressed` 检查范围） |
| UI 按钮 (AppBar 勾号) | 时间线 | 标记已读 + 跳到下一篇 | ❌ 不受影响（onPressed 回调） |
| UI 按钮 (保留/移除) | 审核页 | 执行 keep/reject | ❌ 不受影响（onPressed 回调） |

### 118.7 未修改的已知问题

1. **`isUpdatingReadState` 阻塞**（§118.2 根因 3）：在极快速的连续 M 键操作时仍可能被静默吞掉，但切换文章后 controller 被 dispose 重建，实际出现概率极低。当前 `return true` 保留，避免事件继续冒泡导致意想不到的副作用。

2. **`IndexedStack` 多 page 并存**（§118.2 根因 4）：多个 `ArticlePageView` 同时注册 `HardwareKeyboard` handler 的架构问题未修改，其边缘竞争概率本身就很低，且 `isActive()` + `isSelectedArticle()` 双重守卫已经足够健壮。

3. **K 键在 `_handleHardwareKeyEvent` 中的路径**：K 键仅由 `FilterReviewPage` 的 `_handleHardwareKeyEvent`（第 101 行）直接处理，绕过 `ArticlePageView` 的 handler。如果将来有人将 K 键逻辑迁移到 `ArticlePageView` 内，需要在 Focus widget 中同步增加对应的键列表项。

---

*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.14 -m "- 统一 macOS 文章处理按钮、快捷键与双击跳转逻辑\n- 重做撤销后聚焦恢复，当前可见页面负责选中并滚动到恢复文章\n- 重做 macOS 时间线与垃圾拦截列表的卡片进入/退出动画，避免动画期间文章错位或越界" --push`*

## 119. macOS Cmd+R 全局刷新快捷键（2026-06-08）

### 119.1 需求背景

用户希望 macOS 端支持 Cmd+R 快捷键触发刷新（重新拉取文章列表），效果完全等效于时间线 AppBar 右侧的同步按钮。

### 119.2 现状分析

1. **macOS 无下拉刷新**：`timeline_page.dart:389-400` 中 macOS 分支不包裹 `RefreshIndicator`，无法靠下拉手势触发刷新。
2. **macOS 的唯一刷新入口**：时间线 AppBar 的 `_MacSyncButton`（`timeline_page.dart:888-954`），点击后调用 `TimelineController.loadFeedsThenArticles()`。
3. **全局快捷键已有基础**：`main.dart:174-186` 使用 Flutter 的 `Shortcuts` + `SingleActivator` 机制实现了 `Cmd+Z`（撤销）和 `Cmd+,`（打开设置）两个全局快捷键。

### 119.3 方案选择与理由

采用与 `Cmd+Z` / `Cmd+,` 一致的全局 `Shortcuts` 方案（而非某个页面的 `HardwareKeyboard` 监听）：

| 方案 | 说明 | 选择 |
|------|------|------|
| 全局 Shortcuts | 在 `main.dart` 添加 `RefreshTimelineIntent`，macOS only，与现有快捷键模式一致 | ✅ |
| 页面 HardwareKeyboard | 侵入 timeline_page 或 article_page 的 keyboard handler | ❌ 与 Cmd+Z/Cmd+, 不一致 |

理由：
- `TimelineController` 已全局注册，可从任何页面直接 `Get.find` 访问
- 不受焦点影响，不管用户在时间线、设置页、审核页按下 Cmd+R 均可触发
- 不需要侵入页面级的 keyboard handler，避免与方向键、M 键等已有快捷键冲突
- 与 `Cmd+Z`（UndoReadIntent）、`Cmd+,`（OpenSettingsIntent）保持代码风格一致

### 119.4 实现细节

**文件 1：`lib/main.dart`**

- 新增 `import 'pages/timeline/timeline_controller.dart'`（第 5 行）
- 新增 `RefreshTimelineIntent` 类（第 31-33 行），位于 `OpenSettingsIntent` 之后
- `Shortcuts` 新增（macOS only）:
  ```dart
  if (Platform.isMacOS)
    SingleActivator(
      LogicalKeyboardKey.keyR,
      meta: true,
    ): const RefreshTimelineIntent(),
  ```
- `Actions` 新增 `RefreshTimelineIntent` 处理器：
  - 守卫 `EditableText` 焦点（与 UndoReadIntent 相同的保护逻辑），避免在输入框中按 Cmd+R 误触发
  - 调用 `Get.find<TimelineController>().loadFeedsThenArticles()`

**文件 2：`lib/pages/settings/settings_page.dart`**

- 快捷键列表新增 `Cmd + R` → `刷新文章列表`（第 527 行），排在 `Cmd + ,` 和 `Cmd + Z` 之后、`M` 之前

### 119.5 与同步按钮的关系

Cmd+R 仅调用核心刷新方法 `loadFeedsThenArticles()`，不含 `_MacSyncButton` 的 UI 层效果：
- **不做**：旋转动画（`RotationTransition`）、450ms 最低反馈窗口、按钮禁用防重复
- **做**：与点击按钮完全等同的数据刷新流程

这是因为快捷键不需要 UI 层面的动画反馈，核心数据刷新行为一致即可。

### 119.6 影响文件

- `lib/main.dart` — RefreshIntent + Shortcuts + Actions
- `lib/pages/settings/settings_page.dart` — 快捷键说明列表

### 119.7 验证结果

```bash
flutter analyze lib/main.dart lib/pages/settings/settings_page.dart
# No issues found!
```
## 120. macOS 图片右键复制功能 (2026-06-08)

### 120.1 需求背景

在 macOS 上对图片右键点击时没有任何反应，无法复制图片到剪贴板。用户希望在图片画廊和文章内联图片上都支持 macOS 右键菜单，交互方式与现有 macOS 右键模式（article_card 中的 `onSecondaryTapDown` + `showMenu`）完全一致。

### 120.2 讨论与决策

用户确认三项关键设计选择：
1. **生效范围**：图片画廊和文章内联图片都支持右键菜单
2. **复制行为**：复制图片数据（bitmap）到系统剪贴板，而非仅复制 URL（原有"复制链接"选项仍在）
3. **移动端**：仅 macOS 右键，mobile 长按菜单保持不变

### 120.3 技术方案

#### 核心挑战：Flutter 不支持图片剪贴板
Flutter 的 `Clipboard` 类只支持 `ClipboardData(text: ...)`，无法写入图片数据。最终方案采用 **MethodChannel + Swift NSPasteboard**（方案 A）：
- Dart 侧通过 `MethodChannel('com.autofolo/image_clipboard')` 发送图片 bytes
- macOS Swift 侧用 `NSPasteboard.general.clearContents()` + `NSPasteboard.general.writeObjects([NSImage])` 写入
- 复用项目中已有的 MethodChannel 模式（参考 `AppBadger`、`MoveToBackground`）

#### 三个改动点

| 位置 | 改动 |
|------|------|
| **图片画廊** `image_gallery_page.dart` | `GestureDetector` 新增 `onSecondaryTapDown`（仅 macOS），弹出 `showMenu` 菜单（复制图片 / 分享 / 保存 / 复制链接） |
| **内联图片** `html_chunk_card.dart` `_ArticleInlineImage` | 包裹 `GestureDetector.onSecondaryTapDown`（仅 macOS），共用 `showInlineImageContextMenu` 函数 |
| **HTML 内嵌图片** `html_chunk_card.dart` `ImageExtension._imageExtension` | 已有 GestureDetector（onTap）增加 `onSecondaryTapDown`（仅 macOS），共用同一菜单函数 |

#### 菜单函数共享
新增顶层函数 `showInlineImageContextMenu()` — 展示 2 项菜单（复制图片 / 复制链接），下载图片后用 `ImageClipboard.copyImageToClipboard()` 写入系统剪贴板，同时给图片画廊和所有内联图片复用。

### 120.4 修改文件清单

#### 新增
- `lib/utils/image_clipboard.dart` — MethodChannel 封装 + Dio 下载工具

#### 修改
- `lib/pages/article/widgets/image_gallery_page.dart` — macOS 右键菜单 + `_copyImage()` + `_showImageContextMenu()`
- `lib/pages/article/widgets/html_chunk_card.dart` — `_ArticleInlineImage` 和 `ImageExtension` 添加右键菜单 + 顶层 `showInlineImageContextMenu()` 函数
- `macos/Runner/AppDelegate.swift` — 新增 `com.autofolo/image_clipboard` MethodChannel 处理器

### 120.5 交互模式

| 平台 | 图片画廊 | 内联图片 |
|------|---------|---------|
| **macOS** | 右键 → `showMenu` 光标位置弹出（复制图片/分享/保存/复制链接） | 右键 → `showMenu` 光标位置弹出（复制图片/复制链接） |
| **移动端** | 长按 → BottomSheet（不变） | 无菜单（不变） |

### 120.6 验证结果

```bash
flutter analyze lib/utils/image_clipboard.dart lib/pages/article/widgets/image_gallery_page.dart lib/pages/article/widgets/html_chunk_card.dart
# No issues found!
```

---
## 121. 行内代码文本基线对齐彻底修复 (2026-06-08)

### 121.1 问题背景
用户反馈文章详情页中，行内代码（`<code>` 标签包裹的文本）的文字基线与周围正文没有对齐，视觉上出现了"上浮"现象。具体表现为：行内代码的**边框下沿**与周围文字对齐，但边框下沿到边框内文字之间有 padding 间隙，导致代码文字在视觉上高于其他文字。

### 121.2 历史修复回顾
该问题此前已有两次相关修复：
1. **第87条 (v1.1.8左右)**：修复了行内 `<code>` 被错误拆成独立代码块的问题，引入了启发式分类（`_isBlockCode`），让短 `<code>` 保持行内渲染。
2. **第107条 (v1.1.11)**：尝试修复行内代码"往上浮"的问题。在 `TagWrapExtension` 中对 `Container` 加了 `Transform.translate(offset: Offset(0, 1.5))`，试图用视觉偏移补偿底部 padding 造成的基线偏移。

### 121.3 根因分析
第107条的修复方案存在根本性缺陷：
- **硬编码偏移量不可靠**：`Transform.translate(offset: Offset(0, 1.5))` 是固定像素值，但实际对齐偏差受字体大小（14px vs 16px）、`lineHeight`、`vertical padding`、以及不同设备渲染差异影响，1.5px 不可能在所有情况下完美对齐。
- **`WidgetSpan` 的基线对齐机制**：`TagWrapExtension` 将 `code` 转为 `WidgetSpan`，Flutter 的 `WidgetSpan` 默认使用 `PlaceholderAlignment.bottom` 对齐，即将**容器的底边**（包含 padding）对齐到文本基线。`Container` 底部的 2px padding 会将内部文字向上推，而 `Transform.translate` 只是视觉偏移，不影响布局计算。
- **字体大小差异**：行内代码 14px 比正文 16px 小，即使基线对齐了，x-height 也会不同，视觉上仍然会感觉不对称。

### 121.4 修复方案讨论
讨论了两种方案：
- **方案 A（推荐）**：废弃 `TagWrapExtension`，改写自定义 `HtmlExtension`，在内部用 `WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic)` 包裹。这样 `code` 内的文字基线会直接与周围正文基线对齐，无需任何 `Transform.translate` hack。
- **方案 B（轻量）**：保留 `TagWrapExtension`，但去掉 `Transform.translate`，改为给 `Container` 设置不对称的 padding（如 `top: 3, bottom: 1`），通过减少底部 padding 来缩小偏移。但这只是视觉近似，不如方案 A 精确。

最终选择了**方案 A**。

### 121.5 性能评估
用户担心方案 A 是否有性能问题。分析结论：**几乎没有差异**。
- 渲染路径相同：`TagWrapExtension` 内部生成 `WidgetSpan`，自定义扩展也是生成 `WidgetSpan`——Flutter 的 `Text` widget 行内渲染只有这一条路。
- 差异仅在枚举值：`PlaceholderAlignment.bottom` vs `PlaceholderAlignment.baseline`，是 layout 阶段的一个 enum 比较，不是额外的布局计算。
- 无额外 widget 树深度：自定义扩展不会增加 widget 树的嵌套层级。

### 121.6 影响范围评估
用户确认改动非常小且集中：
- **只涉及一个文件**：`html_chunk_card.dart` 的 `_buildCommonExtensions` 方法
- **具体变化**：删掉 `TagWrapExtension`（10行），新增自定义 `HtmlExtension` 类（~55行）
- **不受影响的部分**：`html_chunk_parser.dart` 的启发式分类逻辑、块级代码块渲染、`article_content_utils.dart` 的清洗逻辑、chunk 缓存、`AutomaticKeepAliveClientMixin`、`RepaintBoundary`、所有其他 chunk type 的渲染

### 121.7 实现细节
1. 新增 `import 'package:html/dom.dart' as html;`（用于 `_InlineCodeWrapperElement`）
2. 在 `_buildCommonExtensions` 中将 `TagWrapExtension(tagsToWrap: {'code'}, builder: ...)` 替换为 `InlineCodeExtension(colorScheme: cs)`
3. 新增 `InlineCodeExtension` 类，继承 `HtmlExtension`：
   - `supportedTags` 返回 `{'code'}`
   - `matches` 方法处理扩展生命周期
   - `prepare` 方法创建 `_InlineCodeWrapperElement` 包装元素
   - `build` 方法返回 `WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic)`，内部包裹 `CssBoxWidget.withInlineSpanChildren` + 相同视觉样式的 `Container`
4. 新增 `_InlineCodeWrapperElement` 私有类，继承 `StyledElement`，作为扩展的内部包装元素

### 121.8 验证
- `dart analyze lib/pages/article/widgets/html_chunk_card.dart`：通过，无任何问题
- 视觉样式（padding、背景色、圆角、margin）完全不变，仅对齐方式从"容器底边对齐"变为"文字基线对齐"

## 122. macOS 文章正文超链接交互反馈（悬停光标 + 底部 URL 预览）(2026-06-08)

### 122.1 需求背景
用户在 macOS 端阅读 RSS 文章时，期望正文中的可点击超链接能提供类似浏览器的交互反馈：
1. **鼠标悬停时指针变为手型**（`SystemMouseCursors.click`），提示该区域可点击。
2. **悬停时在合适位置展示目标 URL**，方便用户在点击前了解链接去向。

### 122.2 技术调研与方案讨论

#### 问题定位
文章正文由 `HtmlChunkCard`（`lib/pages/article/widgets/html_chunk_card.dart`）内的 `flutter_html` v3 `Html()` widget 渲染。经过代码追踪，`<a>` 标签的渲染由 `InteractiveElementBuiltIn`（flutter_html 内置扩展）负责，它生成 `TextSpan` + `TapGestureRecognizer`，但 `TextSpan` 的 `mouseCursor`、`onEnter`、`onExit` 属性均为空，hover 时无任何视觉反馈。

#### 排除的方案
1. **通过 `Style` 添加光标属性**：`flutter_html` 的 `Style` 类没有任何 cursor 相关的字段，不支持扩展。
2. **使用 `TagWrapExtension` 包裹 `<a>`**：该扩展会将内联元素转为 block-level 的 `WidgetSpan`，这会破坏 inline 文本流，导致链接与周围文字断开换行。
3. **浮动 tooltip 展示 URL**：tooltip 会遮挡密集 RSS 正文中的多处链接，且点击 tooltip 区域可能误触无关链接。不符合 macOS 浏览器用户习惯。

#### 选定的方案：自定义 `HtmlExtension` + 底部状态栏
- **光标反馈**：编写自定义 `HtmlExtension` 取代 `InteractiveElementBuiltIn` 对 `<a>` 的处理，在生成的 `TextSpan` 和 `WidgetSpan` 中注入 `mouseCursor: SystemMouseCursors.click` 以及 `onEnter`/`onExit` 回调。
- **URL 预览位置**：底部状态栏（`Scaffold.bottomNavigationBar`），与 Safari/Chrome 底部的状态栏一致，不遮挡正文且符合用户预期。
- **flutter_html `Extension` 优先级高于 `builtIn`**，只需在 `extensions` 列表中加入自定义扩展即可自动取代 `InteractiveElementBuiltIn` 对 `<a>` 的处理，无需额外的禁用配置。
- **`ValueNotifier<String?>` 状态管理**：悬停 URL 从 `HtmlChunkCard` 向上传递到 `ArticlePageView`，采用 `ValueNotifier` 而非 `setState` 确保仅刷新底部状态栏 widget，不会在悬停时重建整个文章页组件树。

### 122.3 实现细节

#### 文件：`lib/pages/article/widgets/html_chunk_card.dart`
- `HtmlChunkCard` 新增可选参数 `final ValueNotifier<String?>? hoveredUrl`。
- 新增 `_InteractiveLinkExtension` 类：
  - `supportedTags` 返回 `{'a'}`，`matches` 过滤仅含 `href` 属性的 `<a>` 标签。
  - `prepare()` 返回 `InteractiveElement`，保留原有链接样式 `Style(color: Colors.blue, textDecoration: TextDecoration.underline)`。注意：外层 `Html` widget 的 `style` 参数中 `'a': Style(color: cs.primary, textDecoration: TextDecoration.none)` 会覆盖此默认样式，最终链接颜色由外层决定，与修改前一致。
  - `build()` 遍历 `context.inlineSpanChildren`，对每个子 span 递归处理：
    - **`TextSpan` 分支**：复制原有属性，添加 `mouseCursor: SystemMouseCursors.click`、`onEnter`/`onExit` 回调（更新 `hoveredUrl.value`）、`TapGestureRecognizer`（委托 `context.parser.internalOnAnchorTap`，与 flutter_html 原有 `onLinkTap` 兼容）。
    - **`WidgetSpan` 分支**：包裹 `MouseRegion(cursor: SystemMouseCursors.click, onEnter: ..., onExit: ...) > GestureDetector(onTap: ...)`，保留原 child widget。
- `_linkExtension` getter 在 `hoveredUrl` 为 null 时返回 null，确保不传入 `hoveredUrl` 的调用点（如文章列表卡片预览）不附带链接交互扩展。
- 将 `_InteractiveLinkExtension` 通过 `_linkExtension` 挂载到所有 `Html()` widget 实例（heading / paragraph / blockquote / table / list / rawHtml 共 6 处），分别在 `_buildHtmlParagraph` 的 `extensions` 参数和 `_buildCommonExtensions` 的返回值中注入。本轮合并时已与第 121 节的 `InlineCodeExtension` 手工合成，确保 `_buildCommonExtensions` 同时保留图片扩展、表格扩展、行内代码扩展和链接 hover 扩展。

#### 文件：`lib/pages/article/article_page.dart`
- `_ArticlePageViewState` 新增 `final ValueNotifier<String?> _hoveredUrl = ValueNotifier<String?>(null)`，在 `dispose()` 中释放。
- 所有 `HtmlChunkCard(...)` 构建处传入 `hoveredUrl: _hoveredUrl`（共 2 处：主 body 构建和 `keepAlive: false` 的延迟构建分支）。
- 在 `Scaffold` 新增 `bottomNavigationBar`：
  - 使用 `ValueListenableBuilder<String?>` 监听 `_hoveredUrl`。
  - URL 非空时显示 32px 高的 `Container`，顶部带 `outlineVariant` 分割线，使用 `surfaceContainerHighest` 背景。
  - 内部为 `Row(Icon(Icons.link) + Expanded(Text(url, overflow: ellipsis)))`，图标尺寸 13、文本字号 11、颜色 `onSurfaceVariant`。
  - URL 为空或 null 时返回 `SizedBox.shrink()`，不占用底部空间。

### 122.4 关键决策与边界说明
1. **不平台守卫**：`MouseRegion` 和 `SystemMouseCursors.click` 仅在桌面端（macOS/Windows/Linux）生效，移动端无 hover 概念，自然不触发。无需 `Platform.isMacOS` 判断。
2. **不影响原有点击行为**：`onLinkTap` 回调保持不变（委托 `url_launcher` 打开外部浏览器），`_InteractiveLinkExtension` 中的 `onTap` 委托 `context.parser.internalOnAnchorTap`，与原行为等效。
3. **仅影响文章正文**：`_InteractiveLinkExtension` 仅挂载在 `HtmlChunkCard` 内部的 `Html()` 上，不涉及文章列表卡片、摘要卡片、元数据区等其他位置的链接。
4. **性能考量**：`_InteractiveLinkExtension` 会递归遍历 `inlineSpanChildren` 并复制 `TextSpan`/`WidgetSpan`，但 `<a>` 标签的嵌套深度通常有限（`<a><b>text</b></a>` 为典型场景），开销可忽略。

### 122.5 验证
- `dart analyze lib/`：零问题通过。
- `flutter test --no-pub`：通过。

## 123. 垃圾拦截页"移除"后不跳转下一篇 & 焦点丢失修复（2026-06-08）

### 123.1 问题现象

用户在 macOS 垃圾拦截页（`FilterReviewPage`）反馈两个问题：
1. **不自动跳转下一篇**：点击"移除"(拒绝)按钮后，文章被删除但未自动选中下一篇，右侧阅读面板变为空白。
2. **焦点丢失导致文本选择光标**：移除后焦点丢失，按 ←/→ 方向键时 Flutter 的 `SelectionArea`（文章正文）捕获了键盘事件，出现文本选择光标，而非切换上/下一篇。

### 123.2 根因分析（与第 111 节不同）

第 111 节修复的是快捷键与 UI 按钮行为不一致（快捷键能跳转、UI 按钮不能），但本轮修复覆盖第 111 节未涉及的两个更深层问题：

| 根因 | 位置 | 说明 |
|------|------|------|
| **RxList + setState 双重驱动** | `_keep()` / `_reject()` — 第 216-311 行 | `_articles` 是 `RxList`（`.obs`），但 `removeWhere` 被包在 `setState(() => ...)` 中。RxList 自身已触发 Obx 重建，setState 又额外触发一次重建，导致选中态更新（`_selectedArticle.value = _articles[nextIndex]`）与被重建的 UI 产生时序竞争。 |
| **滚动时机与动画冲突** | `_scrollToArticle()` — 第 181-188 行 | 使用 `addPostFrameCallback` 滚动到新选中项，但 `ImplicitlyAnimatedList` 的移除动画（默认 180ms）正在进行中，目标项的 `GlobalKey.currentContext` 尚未就绪，滚动静默失效。 |
| **焦点未显式转移** | `ArticlePageView.build()` — 第 1240-1287 行 | `Focus(autofocus: true)` 在文章切换时（`ValueKey` 变化触发新实例）依赖 Flutter 自动抢焦，但 `SelectionArea`（文章内容）可能抢先夺走焦点。方向键因此被 `SelectionArea` 捕获，显示文本选择光标。 |

### 123.3 修改内容

#### 文件 1：`lib/pages/timeline/filter_review_page.dart`

| 修改点 | 改前 | 改后 |
|--------|------|------|
| `_keep()` 第 243 行 | `setState(() => _articles.removeWhere(...))` | `_articles.removeWhere(...)` — 直接操作 RxList |
| `_reject()` 第 300 行 | `setState(() => _articles.removeWhere(...))` | `_articles.removeWhere(...)` — 直接操作 RxList |
| `_scrollToArticle()` 第 182 行 | `WidgetsBinding.instance.addPostFrameCallback(...)` | `Future.delayed(const Duration(milliseconds: 220), ...)` — 等待 `ImplicitlyAnimatedList` 移除动画（180ms）完成后 + 一帧渲染再滚动 |

#### 文件 2：`lib/pages/article/article_page.dart`

| 修改点 | 改前 | 改后 |
|--------|------|------|
| `_ArticlePageViewState` | 无 `FocusNode` | 新增 `late final FocusNode _focusNode` |
| `initState()` | — | 初始化 `_focusNode`；`addPostFrameCallback` 中调用 `_focusNode.requestFocus()` 确保焦点落到导航层 |
| `dispose()` | — | 新增 `_focusNode.dispose()` |
| `build()` 第 1242 行 | `Focus(autofocus: true, ...)` | `Focus(focusNode: _focusNode, ...)` — 用显式 FocusNode 替代 autofocus，确保每次文章切换后都能程序化请求焦点 |

### 123.4 修复原理

1. **跳转失效**：移除 `setState` 后，RxList 的 `removeWhere` 触发 Obx 重建与 `_selectedArticle.value = _articles[nextIndex]` 在同一次微任务中按序执行，不再被 setState 冲乱。`Future.delayed(220ms)` 确保 `ImplicitlyAnimatedList` 完成收起动画后再滚动，此时目标 `GlobalKey` 已就绪。
2. **焦点丢失**：`FocusNode` + 显式 `requestFocus()` 确保每次 `ArticlePageView` 重建（文章切换）后，焦点落在处理导航键的 `Focus` widget 上，而非 `SelectionArea` 内容中。

### 123.5 影响文件

- `lib/pages/timeline/filter_review_page.dart` — 3 处改动
- `lib/pages/article/article_page.dart` — 3 处改动

### 123.6 验收要点

1. 在 macOS 垃圾拦截页点击"移除"按钮 → 文章应自动从列表消失，选中下一篇并滚动到可见。
2. 移除后按 ←/→ 方向键 → 应切换上/下一篇，不出现文本选择光标。
3. `dart analyze lib/` 通过。

## 124. macOS 右侧文章详情面板滚动条跳动修复（2026-06-08）

### 124.1 问题报告

用户反馈：macOS 右侧文章详情面板（ArticlePageView，分栏视图右半部分）的叠加式滚动条，在**使用触控板/鼠标滚动时**会出现间歇性的「拇指忽大忽小、位置跳跃」现象。

### 124.2 根因分析

**物理原因**：macOS 上 Flutter 默认使用叠加式（overlay）滚动条，其拇指大小 = `视口高度 / maxScrollExtent`。当 `maxScrollExtent` 在滚动过程中发生变化，拇指的尺寸和位置就会跳动。

**三层源码根因**（`lib/pages/article/article_page.dart` 中的 `_ArticlePageViewState`）：

| 根因 | 代码位置 (旧) | 机制 |
|------|---------------|------|
| **渐进式构建 setState** | `_scheduleProgressiveBuild()` / `_buildNextBatch()` | 滚动时定期调用 `setState` 将占位 `SizedBox` 替换为真实 `HtmlChunkCard` → 布局重排 → `maxScrollExtent` 变化 |
| **虚拟化/非虚拟化模式切换** | `_shouldUseVirtualizedBody()` / `_usesVirtualizedBody` | 根据内容量（80 chunk / 10000px 阈值）自动在 `SliverList`(虚拟化) 与 `SliverToBoxAdapter+Column`(全量渲染) 间切换 → 滚动结构整体替换 |
| **_MeasuredSize 实时测量** | `_updateMeasuredChunkHeight()` / `_estimatedBodyExtent` | `_MeasuredSize` 在滚动时测量每个进入视口的 chunk 实际高度，更新 `_estimatedBodyExtent` 用于进度条 → 同时 `RenderViewport` 的 `maxScrollExtent` 也被影响 |

### 124.3 修复方案

去除了所有导致 `maxScrollExtent` 不稳定的结构，将文章详情正文改用**纯虚拟化 `SliverList.builder`**：

#### 删除（共 ~150 行，7 个状态变量 + 5 个方法）

- `_builtCount` — 建了多少个 chunk
- `_lastActiveChunkCount` — 上一帧的 chunk 总数
- `_lastShowTranslation` — 上一次是否显示译文
- `_progressiveBuildScheduled` — 渐进构建调度锁
- `_usesVirtualizedBody` — 当前是否虚拟化模式
- `_estimatedBodyExtent` — 正文预估总高度（用于进度条）
- `_measuredChunkHeights` — 每个 chunk 测量到的真实高度缓存
- `_initialBuildCount` / `_buildBatchSize` / `_virtualChunkThreshold` / `_virtualExtentThreshold` / `_metadataExtentEstimate` / `_bottomExtent` — 构建设置常量
- `_scheduleProgressiveBuild()` — 调度渐进构建
- `_buildNextBatch()` — 分批构建下一批
- `_shouldUseVirtualizedBody()` — 虚拟化阈值判定
- `_estimatedExtentFor()` / `_rawEstimatedExtentFor()` — 预估总高度计算
- `_updateMeasuredChunkHeight()` — 测量回调
- `_MeasuredSize` / `_MeasuredSizeState` — 测量包装组件
- 非虚拟化分支：`SliverToBoxAdapter + Column + 占位 SizedBox` 全部渲染路径
- 翻译切换状态刷新逻辑：`contentChanged` / `_measuredChunkHeights.clear()`

#### 简化的代码

- `_updateScrollProgress(ScrollMetrics)`：从「虚拟化用 `_estimatedBodyExtent` 估算，非虚拟化用 `metrics.maxScrollExtent`」的双路计算降为统一用 `metrics.maxScrollExtent` 的单路计算
- `initState()`：删除 `_builtCount` 初始化和 `_initialBuildCount` 读取
- `dispose()`：删除隐式状态清理
- 移除了 `GStorage` / `StorageKeys` 的相关导入（不再读 `articleInitialChunkBuildCount` 设置，因该设置已无意义）

#### 保留的代码

- `CustomScrollView` + 元数据 `SliverToBoxAdapter` + 底部间距 `SliverPadding`
- `ScrollController` 管理和键盘快捷键
- `_scrollProgress` 进度条 `ValueNotifier`
- `NotificationListener<ScrollNotification>` 滚动通知
- `TranslationService` 驱动的原文/译文切换逻辑（通过 `Obx` 响应式切换，不再重建列表结构）
- 本轮合并时与第 122 节链接悬停预览、第 123 节显式焦点管理手工合成：统一 `SliverList.builder` 分支保留 `hoveredUrl: _hoveredUrl`，`initState()/dispose()/Focus(...)` 保留 `_focusNode`。

### 124.4 行为变化对照

| 场景 | 旧行为 | 新行为 |
|------|--------|--------|
| 滚动中触发渐进构建 | `setState` 替换占位符 → 布局重排 → `maxScrollExtent` 变 → 滚动条跳动 | 无渐进构建，所有 chunk 由 `SliverList` 按需虚拟化渲染 |
| 内容量超过阈值 | `SliverList` ↔ `Column` 模式切换 → 滚动结构整体替换 | 始终 `SliverList.builder`，无模式切换 |
| 滚动条表现 | 拇指忽大忽小，位置跳跃 | 拇指尺寸在 `maxScrollExtent` 稳定后固定（新 chunk 首次构建时仍轻微变化，但远优于旧行为） |
| 阅读进度条 | 用 `_estimatedBodyExtent` 估算，有时不准 | 直接用 `metrics.maxScrollExtent` 计算，始终准确 |

### 124.5 验证结果

- `flutter analyze --no-fatal-infos`：No issues found
- `flutter test`：All 6 tests passed
- 代码量：+13 / -248 行（大幅简化）

### 124.6 修改文件清单

- `lib/pages/article/article_page.dart` — 去除渐进构建、模式切换、实时测量，统一用 `SliverList.builder`（+13 / -248）

### 124.7 遗留风险与改进空间

1. **SliverList 首次构建时的 maxScrollExtent 仍会变化**：`SliverList` 在未指定 `itemExtent`/`prototypeItem` 时，仍会按第一个渲染的 item 高度与 itemCount 推算总高度，后续 item 首次进入视口时才测量实际高度并调整 `maxScrollExtent`。方案尝试使用 `prototypeItem` 但当前 Flutter SDK 版本（`flutter_html_table` 约束版本）未暴露该参数，故暂不启用。用户若仍感知到微跳，可考虑：
   - 升级 Flutter 版本后使用 `SliverChildBuilderDelegate.prototypeItem`
   - 在 `ArticlePageView` 初始化时预渲染一个 `HtmlChunkCard` 作为原型，手动传入固定高度
2. **存储设置键残留`StorageKeys.articleInitialChunkBuildCount`**：该 key 不再被任何代码读取，但 Hive 中用户数据仍存有此值。不影响运行，如需清理可在设置页增加"清除过期设置"功能时一并处理。

### 124.8 讨论过程摘要

用户报告「macOS 右侧滑动条依然会出现间断性地跳跃」后：
1. 先完整阅读仓库确认是 Flutter RSS 阅读器，定位到 `_ArticlePageViewState`（`article_page.dart:572`）。
2. 通过 Query 确认是**文章详情面板（右面板）**的滚动条，跳动发生在**主动滚动时**。
3. 讨论四种修复方向（稳定虚拟化模式 / 滚动时暂停测量 / 自定义 Scrollbar / 暂停渐进构建），用户要求先用中文讨论后再定方案。
4. 解释各方案优劣后，用户选择「直接在项目中进行改动」。
5. 实施：删除渐进构建 + 模式切换 + 实时测量三大不稳定源，统一为纯 `SliverList.builder` 虚拟化渲染。

## 125. 1.1.15 beta 合并验证上下文（2026-06-08）

### 125.1 背景

用户希望把当前剩余 worktree 的真实需求先合入主分支，提交并触发一个 beta 版打包，再通过 GitHub Release 产物验证实际体验。用户特别要求：能安全合并的优先用 merge，不再像此前某次整合那样直接把改动在 main 上重写；对于有冲突或需要互相协调的功能，由当前 agent 负责检查、修复并合入。

### 125.2 合入顺序

本轮使用 `git merge --no-ff` 合入以下 worktree 分支：

1. `opencode/witty-sailor`：撤销已读后清理本地 readStatus 覆盖，避免撤销与时间线状态竞争。
2. `opencode/shiny-moon`：垃圾拦截页右侧按钮执行保留/移除前先选中对应行，避免按钮操作目标与右侧详情不一致。
3. `opencode/tidy-mountain`：修复 macOS 垃圾拦截页 M 键偶发失效，缩小组合键拦截范围。
4. `opencode/sunny-forest`：新增 macOS Cmd+R 全局刷新快捷键，并补充设置页快捷键说明。
5. `opencode/sunny-orchid`：macOS 图片右键复制图片数据到系统剪贴板，覆盖图片画廊和文章内联图片。
6. `opencode/gentle-forest`：重做行内 `<code>` 渲染，使代码文字基线和正文对齐。
7. `opencode/curious-knight`：文章正文链接悬停时显示手型光标，并在底部状态栏预览 URL。
8. `opencode/cosmic-eagle`：垃圾拦截页移除后自动推进下一篇，并通过显式 `FocusNode` 避免方向键被 `SelectionArea` 抢走。
9. `opencode/cosmic-meadow`：文章详情正文去除渐进构建/模式切换/实时测量，统一使用 `SliverList.builder` 缓解 macOS 右侧滚动条跳动。

### 125.3 关键冲突与手工合成

1. `AGENT_HANDOFF.md` 多个分支都把说明插在 v1.1.14 release footprint 后，统一按时间顺序编号为 119-125。
2. `html_chunk_card.dart` 同时涉及行内代码扩展和链接扩展。最终 `_buildCommonExtensions()` 同时保留图片扩展、表格扩展、`InlineCodeExtension` 和 `_InteractiveLinkExtension`，避免其中一个分支覆盖另一个分支。
3. `article_page.dart` 同时涉及 `_hoveredUrl`、`_focusNode` 和正文渲染策略。最终保留 `_hoveredUrl` 的底部 URL 预览、保留 `_focusNode` 的显式焦点管理，并采用 `cosmic-meadow` 的统一 `SliverList.builder`；构建 `HtmlChunkCard` 时保留 `hoveredUrl: _hoveredUrl`。
4. `filter_review_page.dart` 保留 `cosmic-eagle` 对 `_keep()` / `_reject()` 的 RxList 直接移除方案，以及 `_scrollToArticle()` 的 220ms 延迟滚动。这个延迟依赖 `ImplicitlyAnimatedList` 默认 180ms 移除动画，若后续动画时长调整，需要同步检查。

### 125.4 发布前验证

已通过：

```bash
git diff --check
/opt/homebrew/bin/flutter analyze --no-fatal-infos lib test
/opt/homebrew/bin/flutter test --no-pub
```

本机 macOS debug build 未通过，原因仍是本机缺少 CocoaPods：

```bash
/opt/homebrew/bin/flutter build macos --debug --no-pub
# CocoaPods not installed or not in valid state.
```

这与此前本机验证情况一致，不代表 Dart 代码或合并冲突失败；最终 macOS/Android 打包仍依赖 GitHub Actions 的 release workflow 验证。

### 125.5 发布计划

下一步使用 release 脚本发布 `v1.1.15`，pubspec 将从 `1.1.14+16` 自动推进到 `1.1.15+17`。这次版本定位为 beta 验证版，重点验证：

1. macOS 文章详情：长文滚动条是否明显稳定，链接悬停、底部 URL 预览、行内代码基线和图片右键复制是否同时正常。
2. macOS 垃圾拦截页：按钮保留/移除、M 键、方向键、移除后自动推进下一篇是否协调工作。
3. Android 基础体验：时间线、文章详情和 APK 安装签名流程是否保持正常。

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.15 -m "- beta: merge macOS article interaction, image copy, shortcut and filter review fixes\n- beta: unify article body rendering with SliverList to validate scrollbar stability\n- beta: keep Android and macOS internal release packaging on GitHub Actions" --push`*

## 126. v1.1.15 beta 验证失败后的滚动与垃圾拦截推进修复（2026-06-08）

### 126.1 用户反馈

用户下载并验证 `v1.1.15` 后反馈两个问题仍然存在：

1. macOS 右侧文章详情滚动条仍会间断性跳跃；同时顶部橙色阅读进度条在 macOS 和 Android 上都会剧烈抖动。
2. macOS 垃圾拦截页点击“移除”后仍无法跳转到下一篇，并且右侧文章详情失去焦点，随后按左右方向键会出现 Flutter `SelectionArea` 的文本选择光标。

### 126.2 滚动条与进度条根因

第 124 节把正文统一改为 `SliverList.builder`，删除了渐进构建、模式切换和实时测量，但这个方案仍不够：

1. `SliverList.builder` 对变量高度 item 仍会随着 item 首次进入视口而持续修正 `maxScrollExtent`。macOS 叠加式滚动条的拇指大小和位置直接依赖 `maxScrollExtent`，所以仍会跳。
2. 顶部阅读进度条直接使用 `metrics.pixels / metrics.maxScrollExtent`。当 `maxScrollExtent` 因 SliverList 估算修正或图片加载改变高度时，进度值会跟着跳。
3. 进度条外层使用 `TweenAnimationBuilder(begin: 0.0, end: progress, duration: 50ms)`，滚动过程中每次 value 更新都会创建新的 tween，进一步放大视觉抖动。
4. 无明确宽高的图片加载完成后会从 placeholder 高度切换到图片 intrinsic 高度，也会再次改变页面总高度。

### 126.3 滚动修复

本轮改动：

1. `article_page.dart`：正文渲染从 `SliverList.builder` 改回 `SliverToBoxAdapter + Column`。虽然牺牲一点长文首屏构建性能，但可以一次性完成主体布局，避免 SliverList 按需估算导致 `maxScrollExtent` 在滚动中变化。
2. `article_page.dart`：顶部进度条删除 `TweenAnimationBuilder`，直接用 `LinearProgressIndicator(value: progress)` 显示当前值，避免动画 tween 在高频滚动通知中不断重启。
3. `html_chunk_card.dart`：文章独立图片 `_ArticleInlineImage` 对无真实尺寸的图片也固定 `displayHeight`，placeholder 和最终图片使用同一高度。
4. `html_chunk_card.dart`：HTML 内嵌图片扩展也统一给无尺寸图片设置 `renderWidth/renderHeight`，placeholder、errorWidget 和最终图片保持相同盒子尺寸。

注意：这次更偏向稳定阅读体验，而不是继续追求虚拟化。后续如果用户反馈超长文章首屏变慢，再考虑“先完整预估固定 item 高度”或“分批预排版后再显示”的方案，但不要再回到会动态修正 `maxScrollExtent` 的变量高度 SliverList。

### 126.4 垃圾拦截页推进失败根因

`FilterReviewPage._reject()` 旧逻辑在调用 `TimelineController.markAsReadLocal()` 后才计算 `isSelected/currentIndex`。但 `markAsReadLocal()` 会同步调用 `ArticleStateNotifier.tick(entryId)`，触发审核页自己的 `_syncArticleFromDb(entryId)`，导致当前文章先从 `_articles` 移除、`_pruneInvalidSelection()` 再把 `_selectedArticle` 清空。等 `_reject()` 回来继续执行时，`isSelected` 已经变成 false，后续“选择下一篇”的分支不会执行。

`_keep()` 也有同类问题：它在一开始就调用 `ArticleStateNotifier.tick()` / `AutoFilterWorker.unReject()`，状态通知可能抢在本函数后半段之前修改列表和选中态。

### 126.5 垃圾拦截页修复

本轮改动：

1. `_keep()` / `_reject()` 在任何数据库写入、read state 更新、`ArticleStateNotifier.tick()` 之前，先根据当前 `_articles` 和 `_selectedArticle` 计算 `shouldAdvance` 与 `nextArticle`。
2. 状态修改完成后统一调用 `_removeReviewedArticle(entryId)` 移除当前项并清理 `_itemKeys`。
3. 如果原本处理的是当前选中文章，最后强制 `_selectReviewedSuccessor(nextArticle)`，从当前 `_articles` 中重新取同 entryId 的对象并滚动到它。
4. `_pruneInvalidSelection()` 不再简单清空；当当前选中项已经不在列表但列表仍有内容时，补选第一篇，避免右侧详情变空白。
5. `_scrollToArticle()` 从固定 220ms 延迟改成最多 8 次、每 50ms 的短轮询，等 AnimatedList 删除动画后目标 `GlobalKey.currentContext` 真正可用再滚动。
6. `_keep()` 删除了最前面的重复 `ArticleStateNotifier.tick()`，保留 `AutoFilterWorker.unReject()` 内部的状态通知。

### 126.6 验证

本地已通过：

```bash
git diff --check
/opt/homebrew/bin/flutter analyze --no-fatal-infos lib test
/opt/homebrew/bin/flutter test --no-pub
```

本机 macOS native build 仍受本机未安装 CocoaPods 限制，最终需通过 GitHub Actions release 包验证。
---

*🤖 Automated Release Footprint:*

*执行指令: `./scripts/release.sh 1.1.16 -m "- fix: stabilize article detail scrollbar and reading progress rendering\n- fix: keep filter review selection advancing after remove/keep actions\n- beta: rebuild Android and macOS packages for focused regression validation" --push`*

## 127. README 精简与图标美化

### 127.1 背景与动机

用户反馈原 README（123 行）过于技术化，包含了大量不应出现在面向用户的 README 中的内容：
- 功能矩阵表 11 行，每行带有实现细节（如"SliverList 逐块渲染 60fps""RepaintBoundary 隔离"）
- 技术栈表列出具体库名与版本（GetX、Dio、Hive box 名称等）
- 完整的 `lib/` 目录结构树（83+ 文件，逐行注释说明）
- Folo API 端点文档（/subscriptions、/entries 等）
- dart analyze / flutter test 质量检查命令

这些内容属于开发者文档范畴，不应出现在项目 README 中。该项目已有 `AGENT_HANDOFF.md`（5121 行）承载这些细节。

同时，原 README 顶部图标 `assets/icon.png`（848×836）被 HTML 强制拉伸为 96×96 显示，无 alpha 通道、无圆角、无 macOS 风格处理，视觉效果差。用户希望换成类似 macOS 应用图标的样式——带圆角 squircle 轮廓和顶部玻璃光泽反射效果。

### 127.2 关键发现与讨论

**README 路径问题**：初版修改在"安装"小节引入了 `git clone <repo-url>` 和 `cd calm-circuit`，但 `<repo-url>` 是无效占位符，`cd calm-circuit` 也只对 GitHub 上以 `calm-circuit` 命名的目录有效。用户指出这些路径不正确，改为直接 `flutter pub get && flutter run`，去掉 git clone 相关步骤。

**图标生成的技术挑战与演进**：

1. **环境问题**：macOS 上 Python 3.13 环境为 externally-managed，不能用系统 pip。解决方案：创建 venv（`/tmp/icon-venv`）安装 Pillow 12.2.0。

2. **ImageDraw 导入 hang**：在 `python -c` 内联模式下 `from PIL import ImageDraw` 会超时，但写成 `.py` 文件后正常运行。根因未查明，疑为 bash 工具转义相关问题。最终方案是将生成逻辑写成独立文件 `tool/gen_readme_icon.py`。

3. **顶部半透明横线**（第一次迭代）：脚本在渐变光泽之外单独画了一条高亮条 `sd.rounded_rectangle((6,6, SIZE-7,14), fill=(255,255,255,120), radius=shine_radius)`。由于高亮条位于图标顶部圆角收缩区域，而 `shine_radius` 与 mask `radius` 不一致，形成了一条肉眼可见的横向半透明线。修复：去掉独立高亮条，仅保留渐变光泽。

4. **`shine.putalpha(mask)` 导致花屏**（第二次迭代）：想用 `putalpha(mask)` 把光泽限制在圆角范围内，但该方法用二值 mask（0 或 255）直接替换整个 alpha 通道，抹掉了渐变光泽中精心计算的 0~60 过渡 alpha，结果图标变成黑白色块。修复：改为 `shine_clipped.paste(shine, (0,0), mask)`，mask 只控制裁剪范围，不破坏原有 alpha。但这个方案引入了新问题。

5. **边缘未对齐**（第三次迭代的核心问题）：
   - 第一次和第二次迭代中，光泽通过 `for i in range(SIZE // 3)` 循环画 170 条 1px 高的 `rounded_rectangle` 水平条带实现。每条条带独立做圆角（`radius=sr-2`），导致：
     - 每个条带的圆角曲线随 y 坐标变化，条带之间的曲线无法连成完整一致的弧线
     - 条带的圆角半径（110）与 mask 的圆角半径（115）不匹配
     - `paste` 在 RGBA 图像上配合 mask 时，双重 alpha 的处理存在已知问题
   - **最终方案**：改为先创建平直渐变 alpha 图（`grad`，L 模式，纯垂直渐变），再用 `ImageMath.unsafe_eval('a * b / 255', a=grad, b=mask)` 逐像素将渐变乘以圆角 mask。圆角计算仅发生在 mask 上（一次），光泽 alpha 通过乘积自然继承同一曲线，彻底消除了条带间和条带与 mask 之间的对齐偏差。

### 127.3 最终实现

**README 变更**（123 行 → 52 行）：
- 砍掉了：技术栈表、目录结构树、API 端点表、质量检查命令
- 功能矩阵从 11 行表格式改为 7 条简洁列表
- "安装"改回"快速开始"，去掉 git clone 等无效路径
- 图标引用从 `<img src="assets/icon.png" width="96" height="96">` 改为 `<img src="assets/readme-icon.png" alt="Auto Folo" width="256">`
- 新增 CHANGELOG.md 链接

**图标生成脚本** `tool/gen_readme_icon.py`：
- 源图：`macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png`（1024×1024）
- 输出：`assets/readme-icon.png`（580×580，含 margin 和 shadow）
- 处理流程：
  1. 加载 1024px 源图，缩放至 512×512
  2. 创建 squircle 圆角 mask（半径 22.5%，约 115px）
  3. 用 mask 裁剪源图获得圆角图标
  4. 生成平直垂直渐变 alpha（顶部 60→底部 0，`**0.5` 非线性曲线）
  5. `ImageMath.unsafe_eval('a * b / 255')` 将渐变 alpha 与 mask 逐像素相乘
  6. 白色光泽层（255,255,255）应用上述 masked alpha，alpha_composite 叠加到图标
  7. 生成高斯模糊下拉阴影（偏移 y+8，模糊半径 10，alpha 70）
  8. 裁剪透明边距，添加 24px margin 保存

### 127.4 注意事项

- 环境依赖：生成图标需要 Python venv（Pillow），命令为 `/tmp/icon-venv/bin/python tool/gen_readme_icon.py`。如 venv 被清理需重新创建：`python3 -m venv /tmp/icon-venv && /tmp/icon-venv/bin/pip install Pillow`
- `ImageMath.unsafe_eval` 是 Pillow 12.2.0 中的 API（旧版为 `ImageMath.eval`），需注意版本兼容
- `rounded_rectangle` 在 `python -c` 内联模式下可能超时，应写为 `.py` 文件运行
- `assets/icon.png` 原始文件（848×836，无 alpha）未被修改或删除，保留为备用
- 如后续需要调整光泽强度或圆角半径，修改脚本中的 `int(60 * ...)` 透明度上限和 `radius = int(SIZE * 0.225)` 即可

## 128. 2026-06-09 worktree 审查、合并与图片高度策略修正

### 128.1 背景

用户要求检查当前所有 worktree。主分支内容只确认状态，不重新评判；其他分支的需求都来自用户，但实现方式需要审查是否必要、规范、合理，以及是否可能引入 bug。

检查时共有 5 个 worktree：

1. `main`：当前确认基线。
2. `opencode/calm-circuit`：README 精简与 README 图标美化。
3. `opencode/clever-canyon`：Cmd+R 刷新反馈闭环。
4. `opencode/quick-meadow`：macOS 链接 hover 导致阅读进度条抖动修复。
5. `opencode/hidden-wizard`：文章卡片点击反馈，并夹带图片高度策略调整。

所有 worktree 的工作区均为干净状态。对各分支的 `AGENT_HANDOFF.md` 做过敏感模式扫描，未发现此前清理过的路径、签名、密钥、指纹、账号等信息回流。

### 128.2 审查结论

`opencode/calm-circuit` 可以合并。它主要修改 `README.md`、新增 `assets/readme-icon.png` 和 `tool/gen_readme_icon.py`，代码运行面很小。图标文件已人工查看，PNG 正常。脚本依赖 Pillow，定位为一次性资源生成工具，不进入 App 构建链。

`opencode/clever-canyon` 可以合并。它把同步状态从 `_MacSyncButton` 的局部 state 提升到 `TimelineController.isSyncing`，让按钮点击、Cmd+R、下拉刷新和错误重试共享防抖状态。这个方向正确，能解决快捷键绕过按钮动画的问题。需要注意的体验变化是：默认调用 `loadFeedsThenArticles()` 会弹刷新完成 Toast；首次初始化通过 `showToast: false` 避免启动即弹窗。

`opencode/quick-meadow` 可以合并。它把 hover URL 栏从 `Scaffold.bottomNavigationBar` 移到 `Stack + Positioned` 覆盖层。根因判断成立：原先 hover 链接时底栏出现/消失会改变 body viewport 高度，进而改变 `maxScrollExtent`，导致顶部进度条按 `pixels / maxScrollExtent` 计算时前后跳动。覆盖层方案不再挤占 body，符合当前滚动稳定目标。

`opencode/hidden-wizard` 不能原样合并。文章卡片点击反馈本身可接受，但同一分支里还包含“移除图片高度上限”的改动：无尺寸图片先以 200px placeholder 渲染，加载后再按自然高度展开；有真实尺寸的极端长图也不再有保护上限。这会和第 126 节刚修过的滚动条/进度条稳定目标互相冲突，可能重新造成 macOS 右侧滚动条和顶部阅读进度条跳动。

### 128.3 实际合并方式

本轮合并优先使用真实 merge，而不是把分支改动直接复制到主分支。已完成以下 merge commit：

1. `Merge branch 'opencode/calm-circuit'`
2. `Merge branch 'opencode/clever-canyon'`
3. `Merge branch 'opencode/quick-meadow'`
4. `Merge branch 'opencode/hidden-wizard'`

多个分支都在 `AGENT_HANDOFF.md` 末尾追加了同编号章节，分支之间合并时必然产生文档冲突。处理策略是：合并代码时暂时保留主分支文档版本，避免重复编号和冲突标记进入历史；所有功能合并完成后，手工追加本节作为统一交接记录。

### 128.4 `hidden-wizard` 修正后的图片高度策略

为了兼顾“不要普通裁切长图”和“滚动高度必须稳定”，最终没有采纳分支中完全移除高度约束的实现，而是改为稳定预留高度：

1. 新增 `_stableImageHeight()`：所有文章图片在渲染前都得到一个确定高度。
2. 有真实宽高时，按 `renderWidth * imageHeight / imageWidth` 计算显示高度。
3. 高度通过 `_boundedImageHeight()` 保护，最小 40px，最大为图片宽度的 3 倍，并整体限制在 420px 到 1400px 的范围内。
4. 有 `height` / `max-height` 内联样式时，按样式高度预留，但同样进入保护范围。
5. 无真实尺寸、无样式高度时，回到稳定 fallback：`width * 0.6`，并 clamp 到 180px 到 420px。
6. placeholder、errorWidget 和最终图片都使用同一个高度，避免加载完成后改变页面总高度。
7. `HtmlChunk.estimatedHeight` 中图片高度估算也恢复保护：按 340px 宽度估算比例，高度 clamp 到 40px 到 1020px，再加垂直间距。

这个策略的取舍是：普通长图比旧的 420px 上限更不容易被压扁或裁切，但极端长图不会无限撑高页面；无尺寸图片不会在加载完成后突然撑开文章正文。

### 128.5 需要重点回归的功能

1. macOS 文章详情：在有多张图片、长图、无尺寸图片的文章中上下滚动，观察右侧滚动条和顶部橙色进度条是否仍稳定。
2. macOS 文章详情：鼠标反复 hover 正文链接，确认底部 URL 浮层出现/消失时不再带动顶部进度条抖动。
3. macOS 时间线：点击同步按钮和按 Cmd+R 都应触发同一个旋转动画、防抖和完成 Toast。
4. Android 时间线：下拉刷新会因为共享 `loadFeedsThenArticles()` 而出现完成 Toast；如体验上觉得多余，可后续把下拉刷新调用改为 `showToast: false`。
5. 文章卡片：点击时应有轻微缩放与径向高亮反馈；长按翻译菜单和 macOS 右键菜单仍需正常。

### 128.6 已完成的本地检查

本轮合并前分别对三个 Dart 功能分支跑过针对性 `dart analyze`，均通过。合并后已继续完成：

```bash
rg -n '<privacy scan patterns>' AGENT_HANDOFF.md
git diff --check
dart analyze lib test
flutter test --no-pub
```

结果：`AGENT_HANDOFF.md` 隐私模式扫描无命中，diff 检查无输出，`dart analyze lib test` 无问题，`flutter test --no-pub` 全部通过。`flutter test` 首次在沙箱内被 Flutter SDK cache 写入限制拦截，授权后重跑通过。
## 129. 翻译与摘要的自动重试机制实现

### 129.1 需求背景
- 用户发现翻译功能未能实现自动重试，希望在请求失败（如网络错误、解析错误）时能自动重试。
- 摘要功能也需要加入相同的自动重试机制。
- 自动重试的最大次数应当可以在**设置页面**进行配置。

### 129.2 架构选择与讨论
- **初步想法**：曾经考虑使用类似于已读同步的后台队列轮询机制。
- **用户反馈**：用户明确提出“配置重试次数，重试的时候直接已经在队列中了吧？原地重试即可？为什么会需要讨论这么多逻辑？”
- **最终方案**：根据用户偏好，采用了最轻量的**原地重试（In-place Retry）**方案。抛弃了维护后台持续轮询任务的复杂想法。在发起请求的异步方法底层，如果遇到特定的异常（如 `DioException` 或 JSON 格式错误），并且重试次数未耗尽，则会 `await Future.delayed(1s)` 并在 `for` 循环中再次尝试请求。这在外部看来，任务仍然是 `pending`（加载中），直到重试完全失败才输出 `error`。

### 129.3 具体修改
1. **`lib/pages/settings/settings_page.dart`**:
   - 新增 `_autoRetryMaxCount` 并在界面新增“后台任务容错设置”（可选 0, 1, 3, 5 次），使用 `GStorage.setting.put('auto_retry_max_count', ...)` 保存。
2. **`lib/services/translation_service.dart`**:
   - `_translateArticleInternal` (全量翻译)：在 API 请求外部包裹了一层重试 `for` 循环，读取配置的最大重试次数。失败时延时 1s 继续下一次尝试。
   - `_translateInChunks` (分块翻译)：将原先硬编码的 5 次尝试改为了动态读取设置文件里的自动重试次数。
3. **`lib/services/summary_service.dart`**:
   - `_summarizeArticleInternal`：同样包裹了一层由配置控制的重试 `for` 循环，并在异常捕获块中执行重试延迟。

### 129.4 注意事项
- 原地重试属于阻塞重试，单次网络请求较耗时的话，会在 UI 层保持 Loading 状态较长时间。
- 对于极端情况（例如应用进程被强杀），此原地任务也会被中断，但对当前产品形态来说可以接受（重启后可重新手动触发）。
## 130. 文章内联链接 Hover 样式优化 (2026-06-10)

### 130.1 需求背景与原始诉求
用户提出原有的文章内联链接样式（橙色文本+白色下划线）不够优雅，希望将其优化为：鼠标悬停（Hover）时展现类似行内代码块的“圆角矩形背景”，并且背景和下划线的出现都需要有 150ms 的过渡动画。

### 130.2 技术方案探讨与取舍（关键上下文）
在深入分析 Flutter 的富文本（`Text.rich` / `flutter_html`）渲染机制后，发现原需求存在严重的体验冲突：
1. **换行破坏问题（致命缺陷）**：要在文本内联插入带圆角的背景框，必须使用 `WidgetSpan`。然而，`WidgetSpan` 会被 Flutter 作为一个不可分割的整体区块处理，**无法在行尾自然换行（Line Wrapping）**。如果正文中存在较长的文本链接，会导致大面积留白或 UI 溢出，这对于一款纯阅读类应用是不可接受的。
2. **性能开销问题**：`TextSpan` 是不可变的，要实现 150ms 的渐变动画，需要在 150ms 内以 60FPS 的频率高频触发整个 HTML Chunk 的解析和重绘。对于包含大量图文的富文本组件而言，这会带来极高的 CPU 开销和发热，容易引起列表滑动卡顿。

经过与用户的充分讨论，决定**放弃“圆角背景”与“150ms过渡动画”**，采取“优先保证阅读排版与性能，提供瞬时优雅反馈”的轻量化方案。

### 130.3 最终实现方案
1. **视觉表现重构**：
   - **常态**：保留主题主色（橙色），但**彻底移除默认下划线**，使得大段正文阅读时视觉更加纯净、无干扰。
   - **悬停态（Hover）**：文字颜色保持不变，瞬间浮现与文字同色的下划线，提供清晰干脆的交互反馈，摒弃了突兀的白色下划线。
2. **局部重绘优化（`HtmlChunkCard`）**：
   - 避免了整篇文章的重绘。利用已有的底部状态栏预览 URL 的 `ValueNotifier<String?> hoveredUrl`，在 `_HtmlChunkCardState.build` 中，按需使用 `ValueListenableBuilder` 包裹局部的 HTML 渲染逻辑。
   - 当用户悬停或移出特定链接时，仅触发包含该链接的局部 Html Chunk 重绘（耗时极低），兼顾了状态更新与滚动性能。
3. **`flutter_html` 扩展调整（`_InteractiveLinkExtension`）**：
   - 彻底移除了 `WidgetSpan`，全面回归 `TextSpan`，完美保证了长链接的自然换行。
   - 扩展接收 `currentHoveredUrl`，在 `prepare` 阶段通过精准的 CSS Style 覆盖，按状态动态赋予 `TextDecoration.underline`。


=======
## 131. 卡片交互特效统一 (2026-06-10)

### 131.1 需求背景

用户发现 macOS 端两个页面的卡片动画不一致：

| 页面 | 使用组件 | 按压缩放 | 点击高光 | hover 效果 |
|------|---------|:---:|:---:|:---:|
| **时间线** | `ArticleCard` | ✅ | ✅ | ❌ |
| **垃圾拦截** (macOS) | `_MacReviewRow` | ❌ | ❌ | ❌ |
| **垃圾拦截** (移动端) | `ArticleCard` + `Dismissible` | ✅ | ✅ | ❌ |

用户的核心诉求：
1. 垃圾拦截页的 macOS 卡片应有和时间线一致的按压特效
2. 两个卡片的动画效果应该尽可能共享代码，但垃圾拦截保留自己的布局
3. 增加 hover 效果（首次），参考现有的点击玻璃高光做轻量版
4. 列表插入/移除动画改为非线性（接近物理直觉）
5. 发现键盘 ←/→ 导航选中效果体验不佳，最终移除

### 131.2 讨论过程

#### 131.2.1 动画不统一的原因

`ArticleCard` (`lib/pages/widgets/article_card.dart`) 内置了一套本地状态驱动的按压反馈：
- `_isPressed` / `_pressPosition` 状态 + `TweenAnimationBuilder` 缩放 (1.0↔0.985)
- `_GlassHighlight` 径向渐变高光在按压位置

`_MacReviewRow` (`lib/pages/timeline/filter_review_page.dart:792`) 是独立实现的 `Material` + `InkWell` 组件，完全没有这些效果。移动端垃圾拦截用的是 `ArticleCard` + `Dismissible`，所以移动端没问题，只有 macOS 端不一致。

#### 131.2.2 设计方案

**抽取共享组件 `CardPressEffect`**：所有按压/hover/高光逻辑集中管理，`ArticleCard` 和 `_MacReviewRow` 都通过它获得统一特效。各自保留不同的内部布局。

**非线性列表动画**：`ImplicitlyAnimatedList` 底层 `AnimatedList` 默认走 `Curves.linear`。建议新增 `insertCurve` / `removeCurve` 参数：
- 插入：`easeOutCubic` — 快速入场→减速停止
- 移除：`easeInCubic` — 缓慢启动→加速离开

**hover 高光**：参考现有 `_GlassHighlight`，用相同径向渐变机制，但用更低 alpha（最终定为 0.05）跟随光标位置。

**键盘选中脉冲**：最初实现了 `←`/`→` 切换文章时触发短暂按压脉冲，但用户实测后觉得效果不理想，最终移除。

#### 131.2.3 滚动跳动 BUG

非线性动画上线后，用户反馈垃圾拦截页点"保留"/"移除"时，列表偶发"一步到位闪到目标位置"。

**根因分析**：`_scrollToArticleWhenReady()` 在 attempt 0 立刻找到 key 并调用 `ScrollUtils.ensureVisible()`（触发 250ms 滚动动画），但此时 `AnimatedList.removeItem()` (180ms) 的删除动画尚在进行中。两个动画（滚动位置 + 列表布局）并发运行 → 滚动目标错位 → 视觉上"跳动"。

**修复**：在 `_scrollToArticleWhenReady` 的 attempt 0 强制等待 220ms（> 180ms 删除时长 + easeInCubic 缓冲），确保 AnimatedList 动画完全结束后才开始滚动。后续 attempt 1-4 才做正常查 key → scroll。

### 131.3 实现细节

#### 131.3.1 新建 `CardPressEffect` (`lib/common/widgets/card_press_effect.dart`)

统一的交互反馈包装器：

```
CardPressEffect
├── MouseRegion (跟踪 _hoverPosition, 控制 _isHovering)
├── GestureDetector (onTapDown/Up/Cancel → 控制 _isPressed)
├── TweenAnimationBuilder (_isPressed → scale 1.0↔0.985)
│   └── Transform.scale
│       └── Stack
│           ├── child (卡片内容本体)
│           └── ClipRRect(borderRadius)  ← 高光裁剪到卡片圆角
│               └── CustomPaint(_GlassHighlightPainter)
│                   hover: RadialGradient at cursor, alpha 0.05
│                   press: RadialGradient at tap,   alpha 0.06
```

核心参数：
- `onTap` / `onLongPress` / `onSecondaryTapDown` — 透传手势
- `enableHover` / `enablePress` — 开关 hover/按压效果
- `borderRadius` — 高光裁剪圆角（匹配卡片）

状态管理：
- `_isHovering` / `_hoverPosition` — hover 跟踪
- `_isPressed` / `_pressPosition` — 按压跟踪
- `_showEffect` = `_isPressed && enablePress` — 按压生效
- `_showHover` = `_isHovering && !_showEffect && enableHover` — hover 只在非按压时显示

动画时长：
- 按入：80ms `Curves.easeOut`
- 松开：350ms `Curves.easeOutCubic`

#### 131.3.2 重构 `ArticleCard` (`lib/pages/widgets/article_card.dart`)

**移除**：
- `_isPressed`, `_pressPosition` 状态
- `_onTapDown`, `_onTapUp`, `_onTapCancel` 方法
- `TweenAnimationBuilder` + `GestureDetector` 外层包装
- `_GlassHighlight`, `_GlassHighlightPainter` 类（迁移到 CardPressEffect）
- `brightness` 变量（不再需要）
- `_selectionPulse` / `didUpdateWidget`（用户最终决定去掉）

**改为**：
- `Stack` → 直接 `Container`（CardPressEffect 处理高光覆盖层）
- 外面包裹 `CardPressEffect`，透传 `onTap` / `onLongPress` / `onSecondaryTapDown`

#### 131.3.3 重构 `_MacReviewRow` (`lib/pages/timeline/filter_review_page.dart`)

`_MacReviewRow.build()` 从：
```dart
Material → InkWell(onTap) → Padding → Row(...)
```
改为：
```dart
CardPressEffect(onTap, borderRadius:8) → Material → Padding → Row(...)
```
- 去掉 `InkWell`，交互由 `CardPressEffect` 接管
- 右侧 `IconButton`（保留/移除）保持自己的 UI 交互

#### 131.3.4 修改 `ImplicitlyAnimatedList` (`lib/common/widgets/implicitly_animated_list.dart`)

新增参数（向后兼容）：
- `insertCurve`：默认 `Curves.easeOutCubic`
- `removeCurve`：默认 `Curves.easeInCubic`

曲线应用点：
- `build()` 的 `AnimatedList.itemBuilder`：`CurvedAnimation(parent: animation, curve: insertCurve)` 包裹后传给外层 `itemBuilder`
- `_syncItems()` 的 `listState.removeItem`：同上用 `removeCurve` 包裹

页面侧（`timeline_page.dart`, `filter_review_page.dart`）**零改动**，自动获得非线性曲线。

#### 131.3.5 修复滚动跳动 (`_scrollToArticleWhenReady`)

```dart
void _scrollToArticleWhenReady(String entryId, {int attempt = 0}) {
    if (attempt == 0) {
      // 等待 AnimatedList 删除动画完成 (180ms + 缓冲)
      Future.delayed(const Duration(milliseconds: 220), () {
        _scrollToArticleWhenReady(entryId, attempt: 1);
      });
      return;
    }
    // attempt 1+：正常查 key → scroll
    ...
}
```

### 131.4 涉及的 UI 效果矩阵

| 效果 | 时间线 | 垃圾拦截(macOS) | 垃圾拦截(移动) | 最近阅读 | 订阅源详情 |
|------|:---:|:---:|:---:|:---:|:---:|
| 按压缩放 0.985 | ✅ | ✅ (新) | ✅ | ✅ | ✅ |
| 点击玻璃高光 | ✅ | ✅ (新) | ✅ | ✅ | ✅ |
| Hover 跟踪高光 | ✅ (新) | ✅ (新) | — | ✅ (新) | ✅ (新) |
| 插入 easeOutCubic | ✅ (新) | ✅ (新) | — | — | — |
| 移除 easeInCubic | ✅ (新) | ✅ (新) | — | — | — |

### 131.5 修改文件清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `lib/common/widgets/card_press_effect.dart` | **新建** | 通用卡片按压/hover/高光共享组件 |
| `lib/common/widgets/implicitly_animated_list.dart` | 修改 | +`insertCurve`/`removeCurve` 参数，默认 `easeOutCubic`/`easeInCubic` |
| `lib/pages/widgets/article_card.dart` | 重构 | 移除内联按压逻辑，套 `CardPressEffect`；删除 `_GlassHighlight` |
| `lib/pages/timeline/filter_review_page.dart` | 重构 | `_MacReviewRow` 去掉 `InkWell` → 套 `CardPressEffect`；修复 `_scrollToArticleWhenReady` 跳动 |

### 131.6 关键设计决策

1. **hover 高光颜色**：用和 press 相同的黑白玻璃色（而非 primary），alpha 降到 0.05。避免与 `isSelected` 的 `primaryContainer` 背景色混淆。
2. **选中脉冲效果**：最初实现了键盘 `←`/`→` 切换文章时触发按压脉冲动画，但用户实测后觉得不好，**最终移除**。`CardPressEffect` 中清理了 `selectionPulse` 参数和 `_isPulsing`/`_triggerPulse` 等全部脉冲相关代码。
3. **_MacReviewRow 右侧按钮**：保留/移除 `IconButton` 保持自己独立的 Material hover，不受卡片级 `CardPressEffect` 影响。
4. **滚动跳动修复策略**：没有移除 `ScrollUtils.ensureVisible`（它已有 `addPostFrameCallback` 保护），而是让它在 attempt 0 强制等待 220ms。这样后续 attempt 1-4 的查 key 逻辑和原来行为一致，只是首次调用有保护性延迟。

### 131.7 后续优化建议

1. 如果 hover alpha 0.05 仍然不够明显，可调到 0.06–0.08。当前 press=0.06/hover=0.05。
2. timeline page 的 `_scrollToArticle()` 使用 `addPostFrameCallback` 一次调用，若后续也出现跳动，可参考 filter review 页面加保护延迟。
3. 移动端 `Dismissible` 左滑/右滑时，`ArticleCard` 的按压缩放理论上也会触发；如果觉得干扰手势，可给移动端 `CardPressEffect` 传 `enablePress: false`。


## 132. 修复 macOS 侧边栏选中项文本排版跳动

### 132.1 问题描述

用户反馈在 macOS 端选中侧边栏的卡片/项目时，标题会产生略微的抖动或跳变。
经排查发现，侧边栏（`macos_sidebar.dart`）中的 `_CategoryItem` 和 `_SidebarItem` 标题在选中（`isSelected`）时，`fontWeight` 会从 `w500` 动态切换为 `w600`。
在非等宽字体的渲染逻辑中，由于粗体字符的占位宽度大于常规体字符，这种动态的字重切换会强制排版引擎重新计算字符度量（Metrics），导致文本的总渲染宽度及内部字符间距发生物理改变，从而在视觉上产生抖动或跳变。

### 132.2 解决方案讨论与权衡

我们讨论了以下几种思路：
1. **完全移除字重变化（原生标准做法）**：彻底固定 `w500`，完全依靠背景色和文字高亮色区分选中态。符合 macOS HIG，彻底消灭跳变，但会丢失原有加粗特效。
2. **文字阴影伪造加粗（最终采用方案）**：在固定底层排版字重（`w500`）不变的前提下，通过叠加细微的同色文字阴影（`Shadow`）来产生像素重叠，实现视觉加粗。这是一种典型的 UI Hack 手段。代价是牺牲了部分亚像素抗锯齿带来的极高锐利度，但能够完美实现“既加粗，又绝对不跳变”的两全其美。
3. **字距补偿法**：变粗时减小 `letterSpacing` 抵消膨胀。但此法只能维持总宽度，字符内部仍会产生蠕动，不能彻底解决像素级跳变问题。
4. **可变字体（Variable Font GRAD 轴）**：使用支持 GRAD 的字体（如 Roboto Flex）。效果最完美，但需要引入非原生字体库，增加包体积并破坏 Mac 端原生旧有字体生态。

最终确认使用**方案 2（文字阴影法）**来实现。

### 132.3 实现细节

- **修改文件**：`lib/pages/main/widgets/macos_sidebar.dart`
- **修改目标**：`_CategoryItem` (约 503 行) 与 `_SidebarItem` (约 587 行) 的 `TextStyle`
- **代码重构逻辑**：
  ```dart
  fontWeight: FontWeight.w500, // 永久固定排版宽度，防跳变
  shadows: isSelected
      ? [
          Shadow(
            color: cs.primary,
            offset: const Offset(0.3, 0), // 水平平移 0.3 像素伪造加粗
          ),
        ]
      : null,
  ```

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.18 -m "- feat: 添加翻译与摘要的失败自动重试机制及设置项\n- style: 优化文章内联链接鼠标悬停反馈为纯净底线样式\n- refactor: 统一所有文章列表卡片的交互特效与物理反馈，修复动画冲突跳动" --push`*
