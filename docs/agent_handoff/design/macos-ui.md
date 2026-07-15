# macOS UI

当前设计语言：

- 高密度分栏视图。
- 半透明材质的悬浮圆角侧边栏。
- 系统红黄绿按钮被定位到自定义窗口几何中。
- macOS 侧边栏当前只保留展开态。旧折叠 rail 入口已经废弃并清理，不要再新增折叠侧边栏专属按钮或状态分支。
- macOS 主几何层第一阶段圆角已收敛：窗口/Flutter 外框 `24`，红黄绿圆心 `24`，侧边栏面板 `18`，`AppGlassSurface` 默认 `16`，`AppGlassPanel` 默认 `18`，突出面板 `20`。这些值应联动维护，不要单独改其中一个。
- 侧边栏槽位外围和右侧时间线共用 `colorScheme.surface`。macOS 主布局使用分层 `Stack`：底层保留 `290px` 透明侧边栏槽位并布局右侧内容，侧边栏玻璃面板最后绘制且允许越界，让外部阴影自然衰减到时间线左缘。不要改回按顺序绘制的单层 `Row`，否则右侧 `ColoredBox` 会盖住越界阴影，在槽位边界形成断层和“独立底板”错觉。
- macOS 26 侧边栏面板是 Runner 中的原生 `NSGlassEffectView(.regular)`，仅覆盖 `290px` 槽位内扣 `8px` 后的面板，不再在整个窗口下方铺原生 sidebar 材质。Flutter `_MacOSGlassPane` 只负责连续曲率裁剪、内容和轻量边界，不得重新叠白色 tint 或整块二次模糊。旧 macOS 使用同尺寸 `NSVisualEffectView(.sidebar, .behindWindow)` 回退。
- 侧边栏宽度、margin 和圆角的真值统一放在 `MacOSLayoutMetrics`。Flutter 启动后通过 `MacOSWindowControls.setSidebarGlassGeometry()` 同步给 Runner；Swift 中的 `290/8/18` 只是在 channel 生效前避免首帧错位的兜底值。调整几何时修改 Dart 常量，不要分别改 Flutter 和 Swift。
- 原生 backdrop 比 Flutter 最终开口向外多 `1px`，用于覆盖 AppKit 系统圆角与 Flutter 连续曲率抗锯齿不完全重合产生的漏底细缝；不要误删为“尺寸不一致”。最终可见半径仍是 `18`。
- 侧边栏浅色轮廓使用 `0.5px / 12% black`，深色使用 `0.5px / 12% white`；只有浅色增加低强度外侧阴影。原生 `NSGlassEffectView` 没有可调 border 参数，这层线由 Flutter 按最终连续曲率绘制。
- 当前侧边栏阴影以连续融合为目标，不要求肉眼明确看见。用户已验证断层消失、外围底板消失，且玻璃透视、布局和点击行为没有回归；不要为了强调阴影而主动加深或加宽。
- Header 分隔线应克制；中间时间线 header 不再使用大面积玻璃。
- macOS 中间栏 header 的底部分隔线已取消。这个规则包括主时间线、订阅源详情、最近阅读和垃圾拦截；列表层级主要依赖卡片轻填充、间距和右侧分栏结构。
- macOS 中间栏和文章详情使用固定 `surface` header，滚动内容从 header 下方开始，不再进入 header，也不再使用顶部渐隐。此前参考 `.scrollEdgeEffectStyle(.soft)` 的透明 header 实验已因长期观感不理想而撤销。
- header 不使用整块 `BackdropFilter`；文章 header 曾因此采样到相邻时间线按钮的高光。玻璃仍只属于 header 内的交互控件。
- 中间栏 header 不显示底部分隔线。文章 header 是例外：底部始终保留 `1px`、`outlineVariant`、alpha `0.30` 的细线，橙色阅读进度在其上按比例覆盖。

控件：

- 图标按钮在适当位置使用现有 glass/tooltip 组件。
- macOS 上仍能看到的旧 `IconButton(tooltip: ...)` 应优先迁移为 `AppGlassIconButton` 或外包 `AppGlassTooltip`；如果底层控件必须保留，例如 `PopupMenuButton` 或尺寸很小的展开箭头，应把原生 `tooltip` 置空，避免同时出现两套 tooltip。
- `AppGlassTooltip` 当前支持底部和右侧两种首选位置。默认底部用于普通工具栏按钮；垃圾拦截审核行这种靠右的垂直小按钮沿用右侧。共享布局会按气泡真实尺寸保留窗口四周 `8px` 安全边距：水平越界时向内收，底部空间不足时翻到上方，右侧空间不足时翻到左侧。不要再为靠边按钮逐个手调 tooltip offset。
- 二态且空间紧张的 header 筛选不要默认使用完整 segment。时间线“未读/全部”采用类似 switch 的紧凑滑块，只显示当前态文字；完整 segment 更适合三态以上或需要同时展示所有选项的设置项。
- 翻译/摘要文字胶囊是轻量普通胶囊。
- Hover 应微妙且稳定；避免闪烁或布局变化。
- 密集、重复出现的列表按钮不应为了追求玻璃效果而全部改为重型 glass surface；优先使用轻量 hover/描边，并只把 tooltip 统一到玻璃语言。
- 密集文章列表卡片不使用普通边框作为默认态。用户验证后认为细线边框不够理想，当前取舍是 macOS 普通态极高透明度白/黑中性色填充，浅色模式反向使用黑/灰透明填充。
- full-size content view 的 header 可拖动窗口，但可点击控件不能把轻微指针位移传给 AppKit。共享圆形玻璃按钮、紧凑 switch 和目录 morph 入口使用 `MacOSWindowDragGuard`；按下期间通过原生 channel 临时设置 `NSWindow.isMovable = false`，最后一个指针释放/取消/组件销毁后恢复。不要把整个 header 禁止拖动，空白区仍是窗口拖动入口。

间距：

- 边缘应尽量和侧边栏/窗口 margin 视觉对齐。
- Scrollbar 不应占用不对称布局宽度，也不应覆盖正文内容。固定 `MacHeaderPane` 让中间栏列表及 scrollbar 自然从 header 下缘开始，不需要顶部遮罩或轨道 inset。
- `MacGlassScrollbarStyle` 是 macOS scrollbar 颜色、圆角和尺寸的共享入口。中间文章列表使用 `articlePaneTheme`（`8px` thumb、右侧 `1px` margin）；右侧文章正文同样是 `8px` thumb，但局部使用 `crossAxisMargin: 2`。设置页和任务中心的 `MacGlassScrollArea` 仍默认使用更轻的 `5px`，不要盲目全局统一宽度或 margin。
- 主时间线、垃圾拦截、最近阅读、订阅源详情共用 `MacHeaderPane` 的固定 header/body 几何，不要各自恢复透明叠层。
- scrollbar 与内容裁剪要按语义分层：右侧文章正文的 scrollbar 必须显式放在圆角安全 clip 之外。
- 文章卡片之间保留比旧版略大的间距，避免轻填充卡片粘连。
- 文章列表卡片的外边距、内部 padding、圆角和普通态外壳由 `ArticleCardChrome` 统一控制。普通时间线、最近阅读和垃圾拦截审核行应共用这些参数，而不是分别复制数值。macOS 卡片圆角当前为 `10`，是用户要求相对旧 `8` 略微增大的取舍。
- macOS 分屏文章详情右下角需要额外处理圆角安全区：矩形 padding 只能保证到直线边的距离，不能沿窗口右下圆弧保持等距。当前通过文章 body 的右下角 clip 避开外框圆弧，不要用全局加大 padding 代替，否则会改变直线区域间距。
- 不要把圆角收敛误读为全局搜索替换：`999` 胶囊/圆形按钮、图片、代码块、表格、小标签和 Android 端不属于本轮 macOS 主几何层收敛范围。
