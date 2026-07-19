# macOS 说明

macOS 是近期 UI 工作的主要验证目标。

当前 UI：

- 分栏：左侧应用侧边栏，中间时间线列表，右侧文章详情。
- macOS 窗口使用透明/full-size content view。macOS 26 的侧边栏局部使用原生 `NSGlassEffectView(.regular)`；旧系统回退到局部 `NSVisualEffectView(.sidebar, .behindWindow)`。
- 红黄绿按钮使用 AppKit `NSControl` 自绘容器，位置和命中范围匹配自定义窗口/侧边栏几何；系统标准按钮保持隐藏，自绘按钮通过它们现有的 target/action 转发关闭、最小化和绿色按钮行为。
- 全屏视频是唯一会临时隐藏红黄绿按钮的页面：视频会延伸到 full-size content view 的标题栏区域，保留按钮会遮挡画面。退出视频页面必须恢复按钮；普通文章、图片预览和其他页面仍遵循标准按钮定位。
- YouTube 使用 WKWebView 自带播放器；其全屏是网页元素触发的 macOS 系统全屏，不经过普通视频的 `FullscreenVideoPage`。Runner 只对对应 WKWebView 开启 `isElementFullscreenEnabled`，不要把这一配置误当成整个应用窗口的全屏开关。
- 红色关闭应隐藏窗口，而不是退出应用。
- 侧边栏是悬浮圆角面板；它的间距和外侧圆角关系会影响其他 macOS 边缘间距决策。
- 软件内选择浅色/深色时，Flutter 主题、玻璃 renderer 读取的 `MediaQuery.platformBrightness`、`NSApp.appearance` 和主窗口 appearance 必须同步；否则系统模式与应用模式不同时，原生玻璃会使用错误明暗外观。

启动窗口策略：

- 冷启动时 AppKit 会先创建原生窗口，而 Flutter 首帧需要等待存储和版本信息初始化；如果立即显示原生窗口，会短暂看到带 `Auto Folo` 标题、红黄绿按钮和灰色 visual effect 背景的空壳窗口。
- `MainFlutterWindow.order(...)` 必须调用 `hiddenWindowAtLaunch()`，让 `window_manager` 在首次排序时隐藏原生窗口；仅调用 Dart 侧 `waitUntilReadyToShow()` 不足以保证 macOS 原生窗口不会提前出现。
- Dart 侧应等待窗口配置完成，再运行 Flutter；首帧栅格化完成后才调用 `windowManager.show()`。当前保留 5 秒超时回退，避免首帧异常时窗口永远不可见。
- macOS 在配置窗口和 `runApp` 之前调用 `LiquidGlassWidgets.initialize()`，让液态玻璃 shader 在窗口隐藏期间完成预热。不能只依赖各玻璃控件首次构建时异步加载：原生端 shader 就绪后不会保证立即重建控件，可能导致刷新、排序和未读切换在首次同步完成前只显示普通 fallback，随后才突然恢复玻璃效果。
- XIB 初始尺寸和 Dart `WindowOptions` 默认尺寸均为 `1000 x 750`，避免原生窗口先按 `800 x 600` 创建、随后再跳到 Flutter 默认尺寸。
- 原生标题从窗口创建时就隐藏，避免首帧之前短暂显示 `Auto Folo`；自绘红黄绿按钮在原生窗口中直接创建，不依赖 Flutter 首帧。
- 本轮没有新增“记住上次窗口尺寸”。红色关闭后的进程内重新打开仍保留当前窗口尺寸；完全退出后的冷启动仍使用 `1000 x 750`。

近期 macOS 专属行为：

- 时间线 header 有 `未读 / 全部` 快速切换。
- 已读文章入口/页面仍然存在，但中间 header 快速切换不包含 `已读`。
- 时间线排序按钮位于同步按钮左侧。
- 具体订阅源筛选下，中间时间线 header 不显示订阅源级自动拉取全文/自动翻译/静默设置，也不显示清除筛选；这些范围和设置由左侧侧边栏承担。
- 即使同步在 widget 订阅前已经开始，同步按钮也应开始旋转。
- 文章图片 hover 不再缩小图片，也不显示边框；可点击图片通过 native channel 使用 macOS zoom-in 光标。
- 中间时间线/列表 header 不再使用玻璃背景，也不保留底部分隔线。
- 文章详情使用固定 `surface` header，不做整块毛玻璃或顶部渐隐；底部始终显示细分隔线，阅读进度覆盖在其上。
- macOS max fling velocity 是用户可配置项，并应全局应用于 macOS。
- 普通时间线和垃圾拦截页的同步按钮复用 `AppGlassSyncButton`；如果调整 macOS 同步按钮样式、旋转或 tooltip，应改共用组件。

红黄绿按钮当前规则：

- 三颗按钮直径 `14px`，第一个圆心距窗口左上均为 `24px`，圆心间距 `23px`。
- 每颗按钮只有自身 `14 x 14px` 区域触发 hover 和点击；按钮之间的空隙不触发 hover。
- hover 任意一颗时三颗同步显示符号，窗口失焦时统一灰化，按住移出后松开不执行动作。
- 自绘控件的 `mouseDownCanMoveWindow` 为 `false`，按钮操作不能被窗口拖动接管。
- 全屏视频通过既有 MethodChannel 隐藏整个自绘容器，退出时恢复。

验证清单：

- 红黄绿按钮：位置、hover 符号、非激活灰色状态、关闭/最小化/缩放行为。
- 时间线：未读/全部切换、排序菜单、同步旋转。
- 文章详情：工具栏 hover、图片光标、表格渲染、目录行为。
- 全屏视频：顶部无桌面冗余按钮，红黄绿进入时隐藏/退出时恢复，`Space`、左右 5 秒和 `Esc` 正确，播放结束停在最后一帧。
- YouTube：缩略图与加载反馈、内联播放、右下角系统全屏和 `Esc` 返回文章均可用；用户已完成本轮验证，未决视觉细节以后按具体反馈处理。
- 设置/任务中心：滚动行为、轻量面板、没有重复 scrollbar。
- 冷启动：完全退出进程后双击应用，确认不会先出现灰色空壳、标题或尺寸连续跳变，首个可见画面应已经是 Flutter 正式界面。
- 冷启动同步：刷新按钮旋转期间，刷新、排序和 `未读 / 全部` 三个控件应从首次可见画面起就具有玻璃材质，刷新完成时不应发生材质突变。

已知坑：

- 不要重新采用“直接移动 `standardWindowButton`”方案。系统按钮的可见 frame 可以移动，但 AppKit 私有的整组 hover tracking 仍停留在默认位置，造成方向相关的提前 hover/消失；手工复制 tracking area 会丢失首次 hover 状态，移动 `NSTitlebarView` 又会破坏 hit test。当前自绘 AppKit 控件已经补齐整组 hover、非激活灰态和系统 action 转发。
- 项目从 Flutter `3.44.6` 起使用纯 Swift Package Manager 管理 macOS 插件。`screen_retriever` 已升级到 `0.2.2`，全部插件进入生成的 `FlutterGeneratedPluginSwiftPackage`；CocoaPods 已 deintegrate，仓库不再保留 Podfile/lock、Pods xcconfig include 或 workspace Pods 引用。
- 迁移时本地 Android Debug、macOS Debug 和 macOS Release 均已构建成功，Release 主程序确认为 arm64；UI 调试仍优先使用 debug build。
- 如果 `flutter run -d macos` 看似卡住，先检查 debug 日志量或 foregrounding 问题，不要直接归因于应用启动失败。
- AppKit 窗口几何变化可能被仍在运行的应用缓存。验证红黄绿按钮位置前应完全退出应用。
- macOS/Xcode 26 环境下曾在 CocoaPods 的 `[CP] Embed Pods Frameworks` 阶段出现 `Killed: 9`；该路径已随纯 SwiftPM 迁移删除。不要恢复旧的 `COCOAPODS_PARALLEL_CODE_SIGN=false` 补丁。`DebugProfile.entitlements` 中的 library validation 例外仍保留，用于本地 debug framework。
- 2026-07-08 又出现一种不同的 `flutter run -d macos --no-pub` 失败：Xcode 构建成功，Flutter 随后报 `Error waiting for a debug connection: The log reader stopped unexpectedly, or never started.`。系统日志显示 `Auto Folo -> Auto Folo.debug.dylib` 被拒载：`library load denied by system policy`。
- 这个问题不是 Dart 业务崩溃，也不是 `[CP] Embed Pods Frameworks` 被 kill。直接 `open build/macos/Build/Products/Debug/Auto Folo.app` 可以启动应用，但 Flutter 等不到 VM Service，因为 debug dylib 没加载成功。
- 已验证修复：Debug 配置设置 `ENABLE_DEBUG_DYLIB = NO`，避免 Xcode 把 Debug 代码拆到 `Auto Folo.debug.dylib`。修改后需要 `flutter clean && flutter pub get` 让 Xcode 重新生成产物，再运行 `flutter run -d macos --no-pub`。
- 不要优先尝试普通 Runner build phase 清理 `com.apple.provenance` xattr。实测这种脚本时机不够晚，最终 CodeSign/构建步骤仍会让产物带上 provenance，并不能稳定解决 debug dylib 被系统拒载。
