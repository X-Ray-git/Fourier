# Liquid Glass

当前立场：

- 选择性使用 Liquid Glass。
- 避免把每个表面都做成重型玻璃。
- 当玻璃影响性能或可读性时，密集设置/任务中心 UI 优先使用轻量描边面板。
- 苹果式玻璃应在能澄清层级或形成有意义浮动控件的位置使用，不应作为整页泛用装饰。

参考工程：

- 用户已把参考材料复制到 `reference/`。
- 参考代码不是运行时依赖；需要的效果必须复制或重新实现在本仓库内。

已知限制：

- Flutter shader 代码不能直接采样应用窗口后方的真实像素。
- AppKit/系统 compositor 负责真实的窗口后方玻璃。macOS 26 侧边栏使用 `NSGlassEffectView`；旧系统才回退到 `NSVisualEffectView`。
- 尝试从真实外部背景提取鲜艳边框色的方案已经放弃；当前可行方案是白色/高光样式或内部玻璃组件。
- 中间模糊可以是真实系统材质，但 Flutter 绘制的边框仍不能可靠采样同一批窗口后方像素。
- 如果未来需要真实窗口后方取色边框，需要 native/AppKit 参与，并应作为专门 renderer 实验处理。

macOS 原生侧边栏玻璃：

- 早期 Runner 在整个透明窗口下方铺设 `.sidebar + .behindWindow` 的 `NSVisualEffectView`，Flutter 侧边栏再叠加模糊和低透明冷白色。强制浅色模式时，这套组合仍容易受系统灰色 sidebar 材质和窗口后方内容影响，表现为侧边栏偏深、文字反而显淡。
- 当前 macOS 26 使用只覆盖侧边栏面板的 `NSGlassEffectView(style: .regular)`，不设置 `tintColor`，Flutter 不再为侧边栏叠加白色或二次模糊。浅色和深色共用同一原生组件，由同步后的 `.aqua/.darkAqua` 外观驱动。macOS 10.15～15 保留 `.sidebar + .behindWindow` 的 `NSVisualEffectView` 回退。
- `NSGlassEffectView` 公开可调项主要是 `style`（`regular/clear`）、`tintColor`、`cornerRadius` 和原生几何；它没有模糊半径、折射、饱和度、高光、阴影或边框强度参数。侧边栏应保持 `.regular`；`.clear` 更适合媒体背景并常需额外 dimming，不适合当前导航侧边栏。
- 侧边栏 Flutter 开口使用连续曲率，而 AppKit 玻璃使用系统轮廓。为避免两套抗锯齿边缘不完全重合而露出未处理背景，原生 backdrop 在 Flutter 遮罩后方向四周扩展 `1px`；最终可见轮廓仍由 Flutter 的 `8px` margin、`18px` 连续曲率裁剪决定。
- 原生玻璃是 Flutter 视图下方的 AppKit 兄弟节点，Flutter 最外层 `ClipPath` 无法裁剪它。玻璃直接挂在透明窗口下方时，窗口获得焦点后增强的折射和高光会越过应用外框，在左上、左下圆角表现为透明穿透或不规则锯齿。Runner 现在用覆盖整个内容区的透明 `sidebarBackdropHost` 承载玻璃，并以 `24px` AppKit 连续圆角做最终外框裁剪；只裁剪这个原生宿主，不裁剪整个 `contentView`、Flutter 页面或红黄绿按钮。侧边栏自身的 `1px` bleed 继续保留，用途与外框裁剪不同。
- 原生组件没有可调 border。当前 Flutter 在最终轮廓上补 `0.5px` 环境描边：浅色为黑色 `12%`，深色为白色 `12%`；浅色另有克制的外侧主阴影和接触阴影，深色不额外加阴影。描边只用于白色/深色背景下的边界识别，不应重新演变为厚重模拟玻璃。
- 不要为了“略微增加模糊”给侧边栏重新叠 `BackdropFilter`。用户了解原生 API 不支持调模糊半径后，明确选择保持系统模糊。

性能：

- 大量时间线卡片上的重型玻璃曾造成 macOS 性能回归。
- 侧边栏未读标签、设置页、任务中心已经简化，以降低渲染成本。

参考工程使用方式：

- `reference/` 下代码是设计与实现参考，不是运行时依赖。
- 如果采用某个效果，应把必要代码复制或重新实现到本仓库。
- 对依赖协同 shader/renderer 栈的效果，不要假设局部模仿就足够。

当前实用模式：

- 侧边栏和少数浮动控件可以使用玻璃/材质语言。
- 覆盖任意文章内容的浮动玻璃面板不能只依赖主题 `onSurface` 与背景模糊保证可读性。正文下方可能是纯白图片、表格或代码区域，深色模式的浅色文字会因此失去对比。此类面板应在玻璃内部叠主题相关的中性可读性遮罩，而不是全局提高 `AppGlassTone.control` 不透明度。
- 当前 `appGlassFloatingPanelScrim()` 约定深色模式使用黑色 `32%`、浅色模式使用白色 `18%`。文章目录只在圆形按钮形变为面板的后半段以 `easeInOutCubic` 渐入遮罩，并确保目录文字出现前遮罩基本到位；关闭静止态按钮仍使用普通圆形 control 材质。后续菜单或同类浮层可以复用该语义规则，但应先单独视觉验证，不要机械套到按钮、tooltip 或大面积页面。
- 密集列表、设置行、任务行、未读标签、重复卡片装饰应保持轻量，除非重新验证性能。
- 边框/高光应细腻稳定。用户只期待高光线时，避免边缘效果把整个内部区域变亮。
- Tooltip 属于低频浮层，适合统一使用玻璃样式；但触发 tooltip 的按钮本体不一定要变成玻璃按钮。
- 垃圾拦截审核行的“保留/移除”按钮数量很多，且用户明确担心重玻璃造成性能问题，因此当前保持圆形轻量按钮，只使用玻璃 tooltip。
- macOS header 的 soft edge/透明渐隐曾按参考工程思路完整实验，但用户长时间使用后认为观感不理想，现已撤销。当前中间栏和文章详情均使用固定 `surface` header，内容从其下方开始；不要把 soft edge 当作当前设计语言重新接入。

玻璃控制色：

- `AppGlassControlPalette` 是当前玻璃按钮/控件颜色状态的集中入口。
- 第一阶段只把散落的 hover、pressed、active、border、disabled 色值收敛到 palette，刻意保持原视觉体感基本不变。
- `AppGlassRoundControlChrome` 是固定 `34px` 圆形工具按钮的共享外壳。文章右上角普通按钮、时间线范围/排序按钮和同步按钮应复用它，而不是各自手写 `AppGlassSurface`。
- `AppGlassMorphSelectionButton<T>` 是低选项数量 header 选择器的共享实现：闭合时复用圆形 control chrome，展开时保持右上角锚点并使用统一的弹性 morph、选项 hover/press、关闭按钮和点击外部收回。当前排序和文章范围共用它；选项很多或需要滚动时仍使用常规菜单，不要无限扩展该组件。
- 主时间线与 macOS 订阅源详情的文章范围只暴露“未读/全部”，使用 `filter_alt_rounded` / `filter_alt_off_rounded`。触发图标不使用橙色选中态：深色固定白色，浅色使用 `onSurface`；展开菜单中的当前项仍按通用 option palette 表达选择。
- 旧 `AppGlassCompactSwitch` 已删除。此前 `58px` 轨道、`42px` 滑块、`1px` rim、空余轨道 `5%` 和 overshoot 裁切规则只属于已废弃视觉实验，不得作为当前实现恢复；设置页 segmented 仍有自己的组件和参数。
- 圆形/header 工具按钮统一使用中性玻璃背景和中性 hover/press。除文章范围这个明确例外外，选中、主动作或状态提示通常只让图标变橙，背景不得叠橙色。红色危险操作、绿色保留操作等语义按钮不属于这一规则。
- 深色模式下圆形工具按钮使用按钮专属玻璃设置，control tint alpha 为普通 control 的 `0.52`，有效白色 tint 约 `12%`；不要通过全局降低 `AppGlassTone.control` 实现，否则 tooltip、菜单和面板会被误伤。
- 浅色圆形工具按钮对齐参考工程的静态材质：冷白 `Color.fromRGBO(210,220,240,0.12)`、厚度 `12`、blur `5`、`135°` 左上光、light intensity `0.85`、ambient `0.15`、refractive index/saturation `1.2`、chromatic aberration `0.02`。为提高本应用浅色可见性，外部主阴影使用黑 `9%`/blur `8`/y `2`，接触阴影使用黑约 `3.5%`/blur `2`/y `1`，强度高于参考默认但仍通过 `PathOperation.difference` 反向裁切，绝不能渗入按钮内部使玻璃发灰。
- 目录按钮仍使用 morph 玻璃实现，但关闭态材质已调到更接近普通圆形 control；不要重新调回明显更深的独立玻璃按钮。
- 目录关闭静止态现在直接复用 `AppGlassIconButton/AppGlassRoundControlChrome`；只有展开和收回期间使用 morph layer，收回越过零点后才交回普通按钮。这样目录、复制、排序、刷新在关闭态使用同一材质路径，同时保留既有完整形变动画。
- 目录展开态的中性遮罩解决的是“任意正文底色上的文字对比”，不属于按钮角色色。不要用动态背景像素采样、逐行切换文字颜色或明显文字描边替代：这些方案会增加渲染复杂度、可能闪烁，且容易产生字幕式观感。
- 浅色模式下，应用设置与原生 AppKit appearance 必须同步；同时用当前主题覆盖玻璃 renderer 读取的 `MediaQuery.platformBrightness`，避免软件强制浅色而系统仍为深色时出现原生侧边栏、目录和普通控件各读一套明暗状态。
- 浅色和深色的选中圆形按钮都沿用普通按钮的中性玻璃基底，不增加主色 tint。文章复制/已读按钮不关闭 own layer，否则它们在浅色背景下会比排序/刷新缺少边界层次。参考工程的实时背景亮度采样等高成本能力没有为这些固定 header 按钮新增；当前只使用静态、可复制且性能稳定的材质参数。
- 真正的贴图/预绘制优化应放在角色规则稳定之后。优先候选是固定尺寸圆形按钮、固定高度 pill、badge；不要先对大面板或密集内容区做贴图化。

Android 复用边界：

- 纯 Flutter 玻璃 renderer 和控制色规则是共享设计资产，不应因为最初在 macOS 上建立就复制一套 Android 版本；AppKit 原生玻璃仍保持平台隔离。
- Android 主时间线和订阅源详情使用共享圆形文章范围按钮，点击后由 `AppMobileGlassSheet` 展示“未读/全部”。不要恢复旧紧凑 switch 的轨道、滑块、rim 或临时视觉状态。
- Android 固定浮动导航使用单个真实玻璃表面；选中态只把图标切换为橙色实心形态，不铺额外橙色底板。未读数字角标使用集中语义色 `#DB4A3E`、白字和无边框外形，不套玻璃或随选中态换色。当前几何为边距 `12px`、高度 `56px`、半径 `28px`；外阴影路径必须复用同一半径并裁掉组件内部，只向外扩散。不要用不透明底板或轮廓线补浅色模式可见性。
- 移动底部面板统一通过 `AppMobileGlassSheet`：当前圆角 `32px`、水平边距 `8px`、底部避让 `viewPadding + 8px`。目录与订阅源设置都使用这一几何来源。
- Android 设置选择面板同样复用 `AppMobileGlassSheet`，但收起字段由轻量 `InputDecorator` 表达，不在列表中常驻模糊。浮动标签必须允许越过输入框上边缘绘制，不能在外层使用 `Clip.antiAlias` 将其裁掉。
- 普通 Android header 复用 `MobileBlurAppBar`，只保留一个低数量的 `48px` 模糊表面。双行订阅源详情、文章进度 header 和全屏媒体属于专用结构，不为形式统一强行压缩。
- 固定、低数量控件可以使用模糊玻璃；文章卡片、骨架和密集列表行继续走轻量 `ArticleCardChrome`。这是性能边界，不是视觉迁移遗漏。
