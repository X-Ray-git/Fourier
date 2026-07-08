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

图片：

- 使用 `ArticleImageService` 处理代理/请求头。
- 宽度尽量尊重文章内容最大宽度和源图片尺寸。
- macOS hover 不再缩小图片，也不绘制边框。
- 可点击图片在 macOS 通过 `MacOSZoomInCursor` 使用 zoom-in 光标。
- 避免会改变图片布局尺寸的 hover 效果；哪怕很小的尺寸变化也会移动后续文字，在桌面端显得不稳定。
- 很小的分隔符类图片不应被拉伸成大占位。

表格：

- `_buildTable()` 刻意不在横向 scroll viewport 外包 `ClipRRect`。
- 原因：圆角裁剪会在横向滚动宽表格时切掉直角矩形表格的四角。
- 表格修复应保守。一些 feed 会输出畸形 table-like 内容；避免可能破坏正确表格的宽泛启发式规则。
- 坏源 HTML 可能出现空代码块。可以隐藏真正空的代码块，但不要重写有意义代码。

底部间距：

- macOS 文章底部 padding 较小。
- 移动端保留更大底部 padding，以避开浮动控件。
- macOS 分屏文章详情使用 `_MacSplitArticleCornerClipper` 对文章 body 做右下角圆角安全裁剪。背景原因是窗口外层圆角会向内收，普通矩形 padding 在右下角不能保持“正文到应用外框”的视觉距离。
- 该 clip 只应用于 `Platform.isMacOS && isSplitView`，且只包裹文章 body，不包裹 AppBar、进度条、右上工具按钮或 hover 链接状态栏。用户已验证这是正确问题位置。
- 当前参数：外层窗口半径 `28`，安全 inset `8`，内侧右下角半径 `20`。如果后续窗口圆角或外框间距改动，需要同步评估这些值。

HTML entity 解码：

- API/LLM 的纯文本字段在新拉取时解码。
- 正文 HTML、URL、图片 URL 不全局按纯文本解码。

目录：

- 目录跳转精度依赖稳定的标题锚点和滚动 offset。
- 除非重做目录逻辑，否则不要把标题虚拟化掉。
- 目录面板动画已调整为从固定右上角锚点展开；避免按钮先跳动再展开的动画。

复制原文：

- macOS 文章详情右上角有“复制原文全文”按钮，位置在已读/未读按钮附近。
- 复制对象是正文区当前已经加载并解析出的原文 `controller.chunks`，不是译文、摘要、目录或 UI 文案。
- 点击复制不应触发网络请求，也不应临时拉取 readability/full content；如果正文尚未加载完成，只提示暂无可复制正文。
- 输出格式为 Markdown。开头包含标题、来源、作者、发布时间、原文链接；正文保留基础结构：标题、段落、链接、图片链接、代码块、引用、列表和表格。
- 脱水规则保持轻量，不做复杂广告识别。当前目标是稳定、可读、便于粘贴到笔记或 LLM，而不是完全还原网页。
- 如果正文第一块标题和文章标题重复，导出时跳过该正文标题，避免复制结果开头重复标题。

文章格式 bug：

- 用户报告特定文章格式问题时，先抓取/检查真实源内容，再添加渲染启发式规则。
- 如果上游文章内容本身畸形，或包含自定义交互组件，优先做窄修复，或接受该边缘情况。
- 除非失败模式明确反复出现，否则不要为了罕见畸形文章加入复杂通用解析规则。
