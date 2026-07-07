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

HTML entity 解码：

- API/LLM 的纯文本字段在新拉取时解码。
- 正文 HTML、URL、图片 URL 不全局按纯文本解码。

目录：

- 目录跳转精度依赖稳定的标题锚点和滚动 offset。
- 除非重做目录逻辑，否则不要把标题虚拟化掉。
- 目录面板动画已调整为从固定右上角锚点展开；避免按钮先跳动再展开的动画。

文章格式 bug：

- 用户报告特定文章格式问题时，先抓取/检查真实源内容，再添加渲染启发式规则。
- 如果上游文章内容本身畸形，或包含自定义交互组件，优先做窄修复，或接受该边缘情况。
- 除非失败模式明确反复出现，否则不要为了罕见畸形文章加入复杂通用解析规则。
