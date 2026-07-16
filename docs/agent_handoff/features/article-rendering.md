# 文章渲染

相关文件：

- `lib/pages/article/article_page.dart`
- `lib/pages/article/widgets/html_chunk_card.dart`
- `lib/utils/article_content_utils.dart`
- `lib/utils/html_chunk_parser.dart`

当前设计：

- HTML 在渲染前会先规范化。
- 解析后的 chunk 在文章 scroll 内通过 `Column` 渲染。
- 不要随意把文章正文切换到 `SliverList.builder`：此前讨论后保留 `Column`，原因是选择、目录锚点 key、图片生命周期和滚动稳定性。
- 渲染器刻意拆分 HTML 规范化、chunk 解析、widget 渲染。修复应尽量放在问题所属阶段。
- `ArticleController` 初始化右上角已读/未读按钮时，必须使用 `LocalArticleDbService.readOverrideOf(article.entryId) ?? article.isRead`。不要只读 `GStorage.readStatus`，因为最近阅读页传入的文章本身已经是已读，而同步成功后本地覆盖状态可能不存在。

超链接：

- macOS 正文链接保留主题色、手型光标、点击打开和底部 URL 预览，但 hover 时不再动态增加下划线。
- 底部 URL 预览继续由文章页共享的 `_hoveredUrl` 驱动；它是 `Stack` 中的局部覆盖层，不改变正文布局。
- `HtmlChunkCard` 不得监听共享 `_hoveredUrl` 并把 URL 变化作为 HTML widget 缓存失效条件。旧实现会在鼠标进入/离开任意链接时通知所有 chunk，导致全篇 `flutter_html` 重新解析和文本布局，滚动经过链接时产生瞬时卡顿。
- 如果未来重新设计 hover 视觉反馈，必须保证不重新解析全篇或整个复杂 HTML chunk；手型光标和 URL 预览是当前稳定的交互反馈基线。

图片：

- 使用 `ArticleImageService` 处理代理/请求头。
- macOS 与 Android 正文图片都使用 `ArticleImageCacheService` 的文章级缓存键。`HtmlChunkCard` 和 `ImageGalleryPage` 必须携带 `entryId`，确保正常阅读、后台预取、图片查看器和已读后清理命中同一套缓存；历史 `v2_` 缓存暂不迁移。
- macOS 刷新完成后预取全部本地未读文章的正文静态图片：按文章顺序、每篇最多 8 张、总调度并发 16；当前文章前 4 张提升到队首。
- Android 使用保守参数：刷新时预取前 50 篇本地未读文章、每篇最多 4 张、总调度并发 4；当前文章前 2 张提升到队首。当前不区分 Wi-Fi 与移动网络。不要加入 hover 触发，也不要把预取改成批量 `precacheImage()` 常驻内存。
- 宽度尽量尊重文章内容最大宽度和源图片尺寸。
- macOS hover 不再缩小图片，也不绘制边框。
- 可点击图片在 macOS 通过 `MacOSZoomInCursor` 使用 zoom-in 光标。
- 避免会改变图片布局尺寸的 hover 效果；哪怕很小的尺寸变化也会移动后续文字，在桌面端显得不稳定。
- 很小的分隔符类图片不应被拉伸成大占位。

视频：

- inline player 和全屏 player 都支持空格播放/暂停，但同一时刻只能由当前可见播放器处理全局按键。
- 进入全屏前，inline player 如果是 `activePlayer`，应暂时释放该身份；全屏页在首帧后请求焦点并接管空格。退出全屏后，inline player 再恢复 `activePlayer` 和焦点。
- 不要让 inline 与全屏页面同时响应同一次空格事件，否则可能发生连续切换两次、视觉上像“空格无效”。也不要在全屏 widget 尚未挂载完成前同步请求焦点。
- 视频不自动循环。controller 初始化后显式 `setLooping(false)`；播放自然结束时停在最后一帧，只有用户再次主动播放才 seek 到开头后继续。这一规则同时适用于 inline 和全屏，因为二者复用同一个 controller。
- macOS 全屏视频不显示顶部返回、旋转按钮和顶部渐变条：返回按钮与红黄绿位置冲突，旋转对桌面没有意义，底部已有退出全屏入口。Android 仍保留移动端顶部返回和横竖屏控制，不要误删为全平台统一行为。
- macOS 进入全屏视频时通过 `MacOSWindowControls`/`window_controls` 原生通道临时隐藏 AppKit 红黄绿按钮，退出页面时必须恢复。`MainFlutterWindow` 保存显隐状态，窗口重新布局时不得强制把按钮提前显示出来。
- 全屏视频键盘：`Space`/媒体键播放暂停，`Left` 后退 5 秒，`Right` 前进 5 秒，`Esc` 退出。seek 必须 clamp 到 `0..duration`；只处理首次 `KeyDownEvent`，不把系统按键重复当作连续快进。
- 文章内普通视频视口固定为 `16:9`，不再用 feed HTML 的 width/height 改变正文布局。poster 和真实视频都在黑色视口内按自身比例 `contain`，允许黑边但禁止裁切、拉伸和加载后重排正文。全屏仍按视频真实比例显示。
- 普通视频和 YouTube 播放前共用 `MediaPlayButton`：macOS hover 使用手指光标；点击后按钮保持 `64x64`，只把图标替换为转圈。初始化状态必须立即 `setState`，避免网络较慢时用户误以为没有点击成功。
- `AnimatedOpacity` 不会自动停止命中测试。inline 与全屏视频控制栏隐藏时必须同时 `IgnorePointer`，否则不可见的全屏/退出按钮仍会拦截角落点击。
- inline 与全屏普通视频的 `VideoProgressIndicator` 均已启用 `allowScrubbing: true`。`video_player` 内部支持点击定位和水平拖拽：拖动开始时暂时暂停，拖动中连续 seek，结束后按拖动前状态恢复。两处进度条都用 `MouseRegion(SystemMouseCursors.click)` 提示可交互；这只适用于本地 `video_player`，YouTube 进度条由 WebView/YouTube 自己管理。

YouTube：

- Folo/Newtype 等源会返回 `youtube.com` 或 `youtube-nocookie.com/embed/...` iframe。它不是媒体文件，不能交给 `video_player`；当前使用 Flutter 官方 `webview_flutter`，Android 与 macOS 平台实现作为直接依赖。
- `YouTubeEmbedInfo` 只识别明确的 YouTube embed/watch/shorts/live/youtu.be URL，并统一生成隐私增强 `youtube-nocookie.com` 地址。非 YouTube iframe 继续保持静态占位并用外部浏览器打开，不要宽泛内嵌任意网页。
- YouTube WebView 必须懒加载：文章初始只显示固定 `16:9` 缩略图和共用播放按钮，用户点击后才创建原生 WebView，避免长文章一次创建多个 platform view。播放后遵循 YouTube 自带控制栏、字幕、清晰度和结束行为，不强行伪装成本地 `video_player`。
- YouTube 错误 `153` 表示 embed 请求缺少 HTTP Referer/客户端身份。不要直接把 embed URL 当作 WebView 顶层请求；当前通过受控本地 HTML iframe、`YouTubeEmbedInfo.clientBaseUrl`（公开仓库地址）、`strict-origin-when-cross-origin` 和 `allowfullscreen` 提供合法身份与全屏权限。导航代理需精确放行该 client document URL，否则会误把初始化 base URL 打开到默认浏览器并留下白屏转圈。
- readability 仅保留能被 `YouTubeEmbedInfo` 识别的 iframe，仍删除其他 iframe。这个白名单是安全与复杂度边界，不要为了支持更多站点直接取消 iframe 清理。
- macOS 网页元素系统全屏需要 `WKPreferences.isElementFullscreenEnabled`（macOS 12.3+）。当前 Dart 通过 `WebKitWebViewController.webViewIdentifier` 和 `MacOSWebViewControls` 通道，Runner 再用插件官方 `FWFWebViewFlutterWKWebViewExternalAPI` 找回原生 WKWebView 并启用该属性；不要修改 pub cache 或 fork 插件。用户已验证 YouTube 内联播放、按钮操作和系统全屏可用，细节优化留待后续需求。

已确认但暂不修复的源内容边界：

- OpenAI News 的 `Improving health intelligence in ChatGPT`：Folo 条目只有短摘要，没有 media、attachments、video 或 iframe。全文 readability 会从 OpenAI 动态页面留下一个无 `src`/`source` 的 `<audio preload="none">`；它原本属于依赖网页 JavaScript 后续注入资源的“朗读文章”控件，不是视频。不要尝试猜测 OpenAI 的动态音频地址，也不要静默删除该节点；当前把它显示为明确的“音频不可用”状态。
- MarkTechPost 的 `Mira Murati’s Thinking Machines Lab Makes The Technical Case For Human-Centered AI Built On Customizable Model Weights`：对应内容不是视频，而是 `500x500` 的交互式 explainer。原网页用 `iframe srcdoc` 承载完整 HTML/CSS/JavaScript，但 Folo 返回内容已丢失 `srcdoc` 属性名和开头，剩余代码被实体转义后塞入无 `src` iframe，无法可靠还原。当前继续省略/降级比执行残缺任意脚本更安全；若未来支持完整 srcdoc，应从原网页重新抓取，并使用受限、懒加载 WebView 单独设计，不能放宽现有“仅 YouTube iframe”白名单。
- 无有效 `src/source` 的 audio、video、iframe 不得静默删除，也不得继续伪装成可播放的空播放器。当前保留媒体 chunk，并明确显示“源内容未提供可用的媒体地址”；文章有原始链接时提供“打开原文”。这既暴露源内容/解析问题，又避免误导用户。

表格：

- `_buildTable()` 刻意不在横向 scroll viewport 外包 `ClipRRect`。
- 原因：圆角裁剪会在横向滚动宽表格时切掉直角矩形表格的四角。
- 表格修复应保守。一些 feed 会输出畸形 table-like 内容；避免可能破坏正确表格的宽泛启发式规则。
- `ArticleContentUtils` 不能再用“没有 `<th>`”直接判定布局表格。真实数据表常用第一行 `<td>` 充当表头；当前按结构保留至少两行两列、列数稳定、无嵌套且以文本为主的网格，单行/单列、嵌套、媒体主导或结构混乱的表格仍可扁平化。
- 更彻底但暂缓的架构方向：拆分“忠实阅读渲染规范化”和“翻译/摘要等 LLM 输入清洗”两条管线。前者尽量保留源 HTML 语义，后者可以更积极地扁平化 Newsletter 布局、压缩噪声。实施前需要盘点 `normalizeHtmlForEntry` 缓存、翻译、摘要、readability 和复制正文的调用边界，并为两套输出建立独立缓存键；不要在没有完成调用链审计时直接复制两套规则。
- HTML 规范化只应删除数值确实为 `0` 的 inline `opacity`；`0.8`、`0.46` 等半透明内容仍是可见正文。顶层文本和布局表格拆平后移到顶层的文本必须重新 HTML 转义，不能让 `&lt;b&gt;` 一类字面内容变成真实标签。
- 翻译/摘要共用的规范化缓存不能只凭 `entryId` 命中，还必须确认传入的原始正文一致；同一文章补全文或更新正文后必须重新规范化。
- 坏源 HTML 可能出现空代码块。可以隐藏真正空的代码块，但不要重写有意义代码。

底部间距：

- macOS 文章底部 padding 较小。
- 移动端保留更大底部 padding，以避开浮动控件。
- macOS 分屏文章详情使用 `_MacSplitArticleCornerClipper` 对文章 body 做右下角圆角安全裁剪。背景原因是窗口外层圆角会向内收，普通矩形 padding 在右下角不能保持“正文到应用外框”的视觉距离。
- 该 clip 只应用于 `Platform.isMacOS && isSplitView`，且只包裹文章 body，不包裹 AppBar、进度条、右上工具按钮或 hover 链接状态栏。用户已验证这是正确问题位置。
- 当前参数：外层窗口半径 `24`，安全 inset `8`，内侧右下角半径 `16`。如果后续窗口圆角或外框间距改动，需要同步评估这些值。
- `_MacSplitArticleCornerClipper` 会裁掉正文整个右边缘的 `8px`；如果依赖 Flutter 自动 scrollbar，thumb 也会位于 clip 内并几乎被完全裁掉，只剩抗锯齿细线。当前 macOS 分屏正文关闭自动 scrollbar，改用同一 `_scrollController` 的显式 `Scrollbar` 包在 clip 外层；不要把 scrollbar 再移回安全裁剪内部，也不要为修 scrollbar 删除正文圆角安全裁剪。
- 分屏正文使用固定 `surface` header，正文从 header 下方开始。整块 header 不使用 `BackdropFilter`，避免左侧采样到相邻时间线按钮光效；右上角交互按钮仍保留各自玻璃材质。顶部状态不显示“文章详情”、分隔线和阅读进度；正文大标题接近完全滚出后，文章标题以单行省略形式进入 header，分隔线和进度条同步渐显。实现通过真实标题高度和滚动 offset 驱动局部 `ValueNotifier`，不使用 `SliverAppBar`，不要为该效果改动正文 sliver、scrollbar 或目录锚点结构。
- 分屏正文 `Scrollbar` 使用 `MacGlassScrollbarStyle.theme`：宽 `8px`、距离右边界 `2px`，仍可拖动；正文基础左右 padding 为 `11px`，最大正文宽度设置仍独立生效。
- macOS 阅读进度条位于文章 header 下边缘；正文大标题尚未离开时，`1px` 细分隔线和橙色进度都隐藏；header 标题折叠出现时，两者同步渐显，橙色进度覆盖在细线上。Android 保留原 appbar 底部行为。

HTML entity 解码：

- API/LLM 的纯文本字段在新拉取时解码。
- 本地缓存恢复时也要重新解码文章标题、来源、订阅分类、作者、垃圾拦截原因、订阅源标题/分类和历史翻译标题等纯文本字段，以兼容修复前已经缓存的实体字样；这只是内存读取规范化，不需要批量迁移数据库。
- 常见实体走内置快速映射；其他格式明确为 `&name;` 的实体通过现有 `html` 包的公开 `HtmlParser` 解码并缓存结果，避免以后每遇到一种实体就扩充白名单。只有解析器没有报告错误时才接受结果，因此未知实体和 HTML5 宽松前缀匹配都保持原文。
- `&ensp;`、`&emsp;`、`&thinsp;` 与 `&nbsp;` 在 UI 纯文本中统一规范化为普通空格。
- 正文 HTML、URL、图片 URL 不全局按纯文本解码。

目录：

- 目录跳转精度依赖稳定的标题锚点和滚动 offset。
- 除非重做目录逻辑，否则不要把标题虚拟化掉。
- 目录面板动画已调整为从固定右上角锚点展开；避免按钮先跳动再展开的动画。

复制原文：

- macOS 文章详情右上角有“复制原文全文”按钮，位置在已读/未读按钮附近；无修饰键 `C` 与按钮调用同一复制逻辑。`Command-C` 仍交给系统处理正文选区复制，不得被全局快捷键吞掉。
- 复制对象是正文区当前已经加载并解析出的原文 `controller.chunks`，不是译文、摘要、目录或 UI 文案。
- 点击复制不应触发网络请求，也不应临时拉取 readability/full content；如果正文尚未加载完成，只提示暂无可复制正文。
- 输出格式为 Markdown。开头包含标题、来源、作者、发布时间、原文链接；正文保留基础结构：标题、段落、链接、图片链接、代码块、引用、列表和表格。
- 脱水规则保持轻量，不做复杂广告识别。当前目标是稳定、可读、便于粘贴到笔记或 LLM，而不是完全还原网页。
- 如果正文第一块标题和文章标题重复，导出时跳过该正文标题，避免复制结果开头重复标题。

文章格式 bug：

- 用户报告特定文章格式问题时，先抓取/检查真实源内容，再添加渲染启发式规则。
- 如果上游文章内容本身畸形，或包含自定义交互组件，优先做窄修复，或接受该边缘情况。
- 除非失败模式明确反复出现，否则不要为了罕见畸形文章加入复杂通用解析规则。
