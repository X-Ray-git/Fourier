# 决策日志

## 保留根目录 `AGENT_HANDOFF.md` 作为入口

背景：后续 agent 会预期根目录存在交接文件。

决策：保留 `AGENT_HANDOFF.md` 作为短入口，把详细知识迁移到 `docs/agent_handoff/`。

后果：agent 能快速起步，同时完整历史仍然可查。

## 保留完整时间线历史

背景：旧的单文件交接文档包含重要历史讨论。

决策：把旧全文复制到 `history/timeline.md`。

后果：专题页可以保持简洁，同时不丢失可追溯性。

## 不使用数字文件前缀

背景：开发顺序不遵循固定计划。

决策：使用语义化 wiki 路径，由 README 描述推荐阅读顺序。

后果：新增主题时无需重命名文件，也不会暗示优先级。

## 文章正文保留 `Column`

背景：Sliver 虚拟化可能提升性能，但会影响选择、目录锚点、图片生命周期和滚动行为。

决策：不要随意切换到 `SliverList.builder`。

后果：除非进行专门重构，否则围绕当前结构优化。

不要回退：

- 保留全文选择行为。
- 保留目录锚点准确性。
- 保留图片预览/光标/菜单行为。
- 保留当前滚动位置语义。

## 畸形文章修复保持保守

背景：少数真实文章出现异常空白、表格渲染、空代码块或交互组件文本问题。有些问题来自上游内容本身畸形。

决策：添加宽泛渲染启发式规则前，先检查真实源内容。优先做窄修复，或接受罕见上游边缘情况。

后果：渲染保持可预测，不为了少数坏文章牺牲常见正确文章。

## 不裁剪宽表格 scroll viewport

背景：在横向表格 scroll viewport 外包圆角 `ClipRRect`，会在表格宽于文章栏时切掉矩形表格四角。

决策：不要仅为视觉一致性而给表格 viewport 加圆角裁剪。

后果：宽表格保持正确的直角边框，同时仍可横向滚动。

## 无 `<th>` 的稳定网格仍属于数据表

背景：阿里技术文章《为什么大模型的缓存命中率能到 90%？》包含 `7×5` 和 `4×2` 两个结构完整的数据表，但首行使用 `<td>` 而不是 `<th>`。旧规范化规则把所有无 `<th>` 表格当成 Newsletter 布局容器，导致两张表在渲染前被摊平成正文。

决策：布局表格清理改用保守的结构判断。有 `<th>` 的表格直接保留；无 `<th>` 时，至少两行两列、列数稳定、无嵌套、文本单元格占主导且非媒体主导的网格也保留。其余明确像布局容器的表格继续扁平化。

后果：修复不依赖订阅源、文章标题或具体文本，正确的 td-only 数据表可以进入现有表格渲染器，Newsletter 单单元格/嵌套布局仍保持轻量。

未来方向：如果表格与其他富文本清洗需求继续分化，应把阅读渲染规范化和 LLM 输入清洗拆成独立管线与缓存；本轮不扩大到该架构重构。

## 避免会改变布局的图片 hover

背景：macOS 图片 hover 缩小/边框效果会移动后续文字，造成明显布局不稳定。

决策：macOS 图片 hover 不应改变图片布局尺寸；用光标表达可点击。

后果：文章文字保持稳定，同时图片仍有可点击提示。

## 选择性使用 Liquid Glass

背景：全局铺开 Liquid Glass 会造成可读性和 macOS 性能问题，尤其是在密集重复 UI 中。

决策：有意义的浮动控件/表面可以使用玻璃；密集设置、任务中心、未读标签和重复装饰使用轻量描边/静态样式。

后果：应用保留设计方向，同时避免重现 `v1.1.25` 风格的性能回归。

## 不在 Flutter 中追求真实外部背景取色边框

背景：用户希望边框高光颜色来自应用窗口后方真实内容。Flutter 绘制无法可靠采样这些像素；NSVisualEffectView/系统 compositor 才拥有这部分模糊。

决策：放弃 Flutter-only 的真实外部背景取色边框。未来如果要做，应作为 native/AppKit renderer 实验。

后果：当前玻璃边框使用实用的白色/高光样式，不假装采样不可得像素。

## macOS 中间 header 保持轻量

背景：中间时间线/列表 header 的玻璃背景增加视觉重量，也可能影响性能。后续细线分隔也被取消。

决策：除非明确重新讨论，否则 macOS 中间栏 header 不使用玻璃背景。

后果：中间列表 chrome 保持安静且不显示底部分隔线；文章详情独立保留细分隔线和阅读进度。

## macOS 圆角收敛按层级联动

背景：用户希望 macOS 整体圆角略微变小，同时文章卡片圆角略微增大。此前调研 Apple 官方资料后，没有找到普通 macOS app 的固定圆角数值规范；官方更强调圆角同心性、容器关系和系统控件自适应。

决策：第一阶段只收敛主几何层和大面板：窗口/Flutter 外框 `24`，红黄绿圆心 `24`，侧边栏面板 `18`，`AppGlassSurface` 默认 `16`，`AppGlassPanel` 默认 `18`，突出面板 `20`，macOS 文章卡片 `10`。分屏文章右下角安全裁剪同步外框半径。

后果：红黄绿、外框、侧边栏和右下角文章裁剪必须联动维护。不要把“圆角收敛”扩展成全局搜索替换。

不要回退：

- 不要单独改 `MainFlutterWindow.swift` 的 `windowRadius` 而不同步 Flutter 外框、红黄绿圆心和文章右下角裁剪。
- 不要把 `999` 胶囊、圆形按钮、图片、代码块、表格、小标签或 Android 端纳入这一轮 macOS 主几何收敛。
- 不要为了统一而给宽表格 scroll viewport 加圆角裁剪。

## 玻璃按钮先集中颜色 token，再统一角色规则

背景：用户希望进一步规划液态玻璃按钮的背景颜色规则，并评估哪些控件未来可以贴图/预绘制以改善性能。当前项目里右上角文章按钮、目录按钮、时间线排序/同步按钮、摘要/翻译 pill、设置页 segmented/select 等控件虽然都带有玻璃语言，但选中态、默认态、hover、橙色使用范围仍存在分叉。

决策：第一阶段只新增 `AppGlassControlPalette`，把散落的 hover、pressed、active、border、disabled 色值集中管理，并保持视觉体感基本不变。第二阶段再讨论和实现“按钮角色规则”，决定哪些状态允许橙色背景、哪些只改变图标色、哪些保持中性背景。贴图/预绘制应排在角色规则稳定之后。

后果：不要因为已经有 palette 就认为按钮设计语言已经统一。后续如果改右上角文章按钮、目录按钮、时间线排序按钮、同步按钮或 pill 控件，应优先接入同一套角色规则，而不是继续在各自页面手写颜色公式。

不要回退：

- 不要重新在页面局部复制 `cs.primary.withValues(...)`、`cs.onSurface.withValues(...)` 等玻璃控制状态公式。
- 不要在角色规则未稳定前批量做贴图化，否则会把临时视觉状态固化成资产。
- 不要为了统一而把密集重复控件改回重型玻璃；性能约束仍然优先。

## 批量时间线变化重建，读状态变化保留动画

背景：切换未读/全部、从具体订阅源回到全部文章、排序、同步回填等操作会产生大量插入/删除/重排序 diff，并阻塞 UI isolate。用户明确希望列表动画只在“标为已读/恢复未读”时应用，其余批量变化不要动画，以节省性能。

决策：macOS 时间线列表 key 包含 selected mode、scope key 和 `TimelineController.timelineListResetVersion`。批量变化递增 reset version，使 `ImplicitlyAnimatedList` 整体重建；`markAsReadLocal` / `markAsUnreadLocal` 不递增 reset version，保留单篇移除/恢复动画。

后果：批量变化避免全局动画卡顿，同时普通单卡片标已读/恢复未读动画保留。

不要回退：

- 不要让排序、筛选范围切换、同步回填、加载更多重新触发大规模列表 diff 动画。
- 不要在侧边栏直接连续设置 `isSilentSelected`、`selectedFeedId`、`selectedCategory`；应使用 `setTimelineScope()` 合并为一次过滤。
- 不要为了禁用批量动画而移除已读/未读的局部动画，除非用户重新明确要求。

## 时间线排序保持本地化

背景：用户请求的长文/短文排序只针对当前已加载本地文章，不要求远端全历史排序。

决策：只排序本地已加载集合，并避免 UI 文案暗示远端/全局排序。

后果：排序保持快速、边界明确，不需要新增 API 或全历史抓取。

## macOS 快速切换只暴露未读/全部

背景：用户澄清：中间栏快速过滤器不需要 `已读`，但已读文章页面/入口仍需要保留。

决策：macOS 时间线 header 快速切换只暴露 `未读 / 全部`。

后果：不要删除已读页面能力；只是在这个局部快速过滤器中省略 `已读`。

## macOS 订阅源筛选 header 不重复侧边栏设置

背景：在左侧侧边栏点开某个分类并选择具体订阅源后，中间时间线 header 曾同时出现刷新、清除筛选、自动拉取全文、自动翻译等按钮。用户认为这些订阅源级设置已经可以在左侧侧边栏中处理，中间栏重复出现会拥挤且职责不清。

决策：macOS 中间时间线处于具体订阅源筛选状态时，不显示自动拉取全文、自动翻译、静默等订阅源级设置，也不显示清除筛选。header 保留时间线级操作，例如排序和同步。

后果：切换范围和订阅源级设置由左侧侧边栏承担；中间栏保持轻量，避免按钮拥挤。

不要回退：

- 不要为了“方便”把订阅源级设置重新塞回中间 header。
- 不要在中间 header 添加清除筛选按钮，除非用户重新明确要求。
- 如果以后需要更多订阅源级操作，优先扩展左侧侧边栏或订阅源上下文菜单。

## 垃圾拦截页复用时间线级组件

背景：垃圾拦截页长期和普通时间线分叉，导致刷新按钮、文章右键菜单等功能需要单独维护。用户注意到刷新按钮位置不一致，右键菜单也缺少重新生成摘要等文章级动作。

决策：把可共享的时间线级 UI 和文章级 AI 动作抽成共用组件。同步按钮由 `AppGlassSyncButton` 维护；文章翻译/摘要菜单由 `ArticleActionsMenu` 维护。垃圾拦截页复用这些组件，但保留自己的审核业务布局和已拒绝文章处理逻辑。

后果：后续改同步按钮样式或文章 AI 菜单时，普通时间线和垃圾拦截页可以一起受益；审核页的保留/移除、拒绝理由、下一篇选择等特殊逻辑仍然独立。

不要回退：

- 不要重新在 `ArticleCard` 和垃圾拦截审核行复制翻译/摘要菜单代码。
- 不要为了“统一”把垃圾拦截页的审核操作塞进普通 `ArticleCard`，除非重新设计整个审核流。
- 已读/未读快速切换属于普通时间线，不需要同步到垃圾拦截页。

## macOS Debug 禁用 Xcode Debug Dylib

背景：在 macOS 26 / Xcode 17 环境中，`flutter run -d macos --no-pub` 可能出现 Xcode 构建成功但 Flutter 等不到 debug connection。系统日志显示主程序加载 `Auto Folo.debug.dylib` 被拒绝：`library load denied by system policy`。

决策：Debug 配置设置 `ENABLE_DEBUG_DYLIB = NO`，避免 Xcode 生成并加载 `Auto Folo.debug.dylib`。

后果：`flutter run` 可以正常启动 Dart VM Service。修改后如果仍使用旧构建产物，需要先执行 `flutter clean && flutter pub get`。

不要回退：

- 不要只看 Flutter 的 `log reader stopped` 表象就判断为 Dart 代码崩溃。
- 不要优先尝试普通 build phase 清理 xattr；实测时机不稳定，最终产物仍可能带 provenance。
- 如果本机有真实开发者证书，未来可以重新评估签名方案，但当前用户机器没有有效 codesigning identity。

## 使用 AppKit 系统红黄绿按钮

背景：自定义红黄绿按钮只能近似外观，无法正确匹配系统 hover、非激活、zoom 语义。

决策：使用标准 `NSWindow` 按钮并重新定位。

后果：AppKit 负责符号、非激活状态和 zoom/fullscreen 行为。

不要回退：

- Hover 任意红黄绿按钮时应显示系统 hover 符号。
- 非激活窗口应显示系统灰色状态。
- 绿色按钮应保留 AppKit zoom/fullscreen 语义。
- 红色关闭应保留“隐藏窗口而非退出应用”的行为。

## Android 内部安装签名保持对齐

背景：GitHub 构建 APK 和本地 debug APK 签名 key 不同时会互相安装冲突。

决策：通过 GitHub Secrets 使用用户本地 debug keystore 材料进行内部构建签名。

后果：包名相同时，内部 APK 可以覆盖本地 debug 构建。单纯提高版本号不能解决签名不匹配。

## 包命名空间迁移前先实现设置导出

背景：改变 Android application id / macOS bundle id 会创建新的应用身份，平台存储不会自动迁移。

决策：正式命名空间迁移前，先加入剪贴板 JSON 设置导入/导出。

后果：用户可以手动迁移凭据/设置；缓存和文章内容刻意不备份。

## 使用 `io.github.xraygit.autofolo` 命名空间

背景：`com.folo.*` 看起来像官方 Folo 命名空间所有权，用户希望避免这种暗示。

决策：当前应用标识命名空间为 `io.github.xraygit.autofolo`；产品仍是 X-Ray 个人使用的 Auto Folo。

后果：历史 `com.folo.*` 和 `com.autofolo` 引用已经废弃。

## Release notes 对字面量 `\n` fail-fast

背景：release message 里的字面量 `\n` 曾造成格式错误的 release notes。

决策：默认拒绝字面量 `\n`，确实需要时必须显式传 `--allow-literal-backslash-n`。

后果：release 脚本不猜测用户意图。

## Release tag 必须是 annotated tag

背景：release job 曾因 tag object 不是 annotated tag 失败。

决策：release tag 必须是 annotated tag，并通过 `scripts/release.sh` 创建。

后果：GitHub Actions 可以验证 tag metadata 并发布预期 release notes。

## 用户要求时保留 worktree 分支历史

背景：用户注意到早期有直接在 main 上改动的情况，明确偏好 worktree 功能集成使用 merge commit。

决策：已接受的 worktree 分支优先使用 `git merge --no-ff`，除非有具体理由不用。

后果：并行 agent 分支上下文在 git history 中可见。

## 保留旧交接全文为归档，但不要以它作为操作手册

背景：旧交接文档有完整时间顺序，但过大，不适合作为日常操作手册。

决策：完整保存在 `history/timeline.md`；当前事实维护在专题页和本决策日志。

后果：未来 agent 应在旧时间线内容变成长期知识时，把结论更新到专题页。

## macOS 分栏列表共享选择与移除协调器

背景：主时间线、垃圾拦截和最近阅读分别演进出了选择、后继项、移除动画、撤销恢复和确保可见逻辑。垃圾拦截还会在 `ArticleStateNotifier` 同步通知中提前 prune selection，使首次构建下一篇详情与卡片退出动画并发，表现为偶发瞬移；撤销后缓存已预热，第二次通常正常。

决策：提取 `MacSplitArticleListCoordinator`，共享稳定 key、删除前登记、删除期间选择保持、真实 `onRemoveEnd` 后切换详情和 reveal。页面只保留业务动作及各自的滚动策略，不创建覆盖所有时间线结构的大型通用 Widget。

后果：垃圾拦截先行迁移并独立验证；主时间线和最近阅读分阶段接入。主时间线的虚拟列表定位、最近阅读的恢复未读语义仍作为页面差异保留。

## 同步持久化与 macOS 单项移除动画跨帧隔离

背景：用户长期观察到垃圾拦截 `M/K` 和主时间线双击偶发没有动画。定向日志证明这不是固定时长或曲线问题：正常移除约 180ms，异常会从动画值 `1.0` 在 30–80ms 内直接跳到接近 `0`。垃圾拦截中，`ArticleStateNotifier` 会在页面显式删除前同步删掉列表项；主时间线双击则在 post-frame callback 中执行约 100ms 的同步数据库写入，消耗了动画首帧。原文浏览器还曾在动画中途抢走前台。

决策：垃圾拦截用 pending action 屏蔽本次状态广播和 reload 对可视列表的提前修改，持久化完成后在帧边界只提交一次删除。主时间线双击允许 `markAsReadLocal` 先持久化，再在下一帧边界更新内存列表；会删除卡片时，浏览器在真实 `onRemoveEnd` 后再跨一帧打开。其他已读调用方保持默认同步视觉更新。

后果：不改变既有 180ms 动画曲线，也不把平台特殊时序扩散到 Android。用户验证 `M/K` 和双击恢复稳定。诊断埋点保留为 Debug 显式开关 `AUTO_FOLO_ANIMATION_PROBE`，普通运行和 Release 没有监听/日志成本。

不要回退：

- 不要让垃圾拦截在 pending action 期间响应同一 entry id 的增量状态通知并提前删项。
- 不要把同步数据库写入和 `ImplicitlyAnimatedList` 列表变更重新放进同一个 post-frame callback。
- 不要用固定短延迟在移除动画中途打开外部浏览器；应依赖真实移除生命周期。
- 不要默认开启同步诊断日志；需要排查时用 dart-define 临时启用。

## macOS soft scroll edge 实验已撤销，回到固定 header

背景：用户希望正文和各类时间线滚入 header 时没有硬分界，同时发现文章 header 左侧会出现疑似相邻刷新按钮投射的白光。参考工程的 `GlassScrollEdgeEffect` 并不是让模糊半径随位置增加，而是在滚动内容上覆盖页面背景纹理/底色并渐变 alpha。

实验：曾让主时间线、垃圾拦截、最近阅读、订阅源详情共用 `MacHeaderScrollEdge`，文章详情使用同源 `GlassScrollEdgeEffect`；内容滚入透明 header 后通过分段采样的 alpha 渐隐。阅读进度条也曾移到面板最顶端。

最终决策：用户长时间使用后认为渐隐灰色不够自然，撤销整套 header 渐隐设计。主时间线、垃圾拦截、最近阅读、订阅源详情现在通过轻量 `MacHeaderPane` 使用固定 `surface` header，列表从 header 下方开始；文章详情同样恢复固定 `surface` header，但不恢复整块 `BackdropFilter`。玻璃只保留在交互控件。中间栏 header 仍不显示底部分隔线；文章 header 底部始终显示 `1px`、`outlineVariant`、alpha `0.30` 的细线，橙色阅读进度覆盖在该细线上。

不要回退：

- 不要恢复文章 header 的整块 `BackdropFilter`，否则可能重新采样相邻分栏控件的高光。
- 不要未经重新讨论恢复 `MacHeaderScrollEdge`、透明 header 或内容滚入 header 的渐隐方案。
- 不要把文章进度条重新移到面板最顶端；当前位于文章 header 下边缘，并与常驻细分隔线叠层。

## macOS 固定 header 让 scrollbar 自然从正文区域开始

背景：透明 header 允许卡片滚入其下方，但 scrollbar 应从 header 下缘开始。早期用实色色块盖住顶部 thumb，会同时切掉卡片右上角；改为 `MediaQuery.padding` 的间接方案又没有稳定约束自动 scrollbar。主时间线和最近阅读内部遗留的局部 `ScrollConfiguration` 还会覆盖共享行为，重新生成从窗口顶端开始的 scrollbar。

最终决策：撤销透明 header 后，不再需要 `MacHeaderScrollbar` 的顶部轨道 inset。`MacHeaderPane` 用固定高度 header 与 `Expanded` body 分栏，列表及 scrollbar 都自然从 header 下缘开始。右侧正文使用普通显式 `Scrollbar`，继续放在正文圆角安全 clip 外部。

后果：thumb 从 header 下缘开始且一开始可见，内容不会进入 header。中间栏和右侧正文保留各自的 `crossAxisMargin`。

不要回退：

- 不要用矩形色块遮住从窗口顶端绘制的 scrollbar。
- 不要把 scrollbar 放回正文右下角安全 clip 内部。

## macOS 正文图片按文章预取并随已读状态回收

背景：正文图片此前只在打开文章后由 `CachedNetworkImage` 开始下载。用户希望刷新后提前下载全部未读文章图片，并接受较激进的 macOS 参数，但要求通过已读后及时清理控制缓存增长。Android 等 macOS 验证后再用更保守参数移植。

决策：macOS 使用一套共享 cache manager 和文章级缓存命名空间，而不是每篇文章独立创建 manager。全部本地未读文章按时间线顺序进入图片任务队列，每篇最多 8 张，总并发 16；当前文章前 4 张拥有弹性优先级，空闲槽位可由后台借用。不使用 hover 预测，不批量预解码到内存。`readHistory` 作为最近阅读/标记时间：保持已读 5 分钟且文章不再显示后，串行删除该文章登记的原图与尺寸变体；运行中 timer 及时处理，刷新补扫遗漏。

后果：同一 URL 跨文章允许重复缓存，换取整篇可靠清理。旧 `v2_` 历史缓存不在本轮迁移或清理；验证稳定后再单独设计明确的旧缓存清理入口。未来封面必须使用独立缓存角色，不能复用正文清理键。
