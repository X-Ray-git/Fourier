# macOS 说明

macOS 是近期 UI 工作的主要验证目标。

当前 UI：

- 分栏：左侧应用侧边栏，中间时间线列表，右侧文章详情。
- macOS 窗口使用透明/full-size content view 和原生 visual effect 背景。
- 红黄绿按钮是 AppKit 标准窗口按钮，只是重新定位以匹配自定义窗口/侧边栏几何。
- 全屏视频是唯一会临时隐藏红黄绿按钮的页面：视频会延伸到 full-size content view 的标题栏区域，保留按钮会遮挡画面。退出视频页面必须恢复按钮；普通文章、图片预览和其他页面仍遵循标准按钮定位。
- 红色关闭应隐藏窗口，而不是退出应用。
- 侧边栏是悬浮圆角面板；它的间距和外侧圆角关系会影响其他 macOS 边缘间距决策。

启动窗口策略：

- 冷启动时 AppKit 会先创建原生窗口，而 Flutter 首帧需要等待存储和版本信息初始化；如果立即显示原生窗口，会短暂看到带 `Auto Folo` 标题、红黄绿按钮和灰色 visual effect 背景的空壳窗口。
- `MainFlutterWindow.order(...)` 必须调用 `hiddenWindowAtLaunch()`，让 `window_manager` 在首次排序时隐藏原生窗口；仅调用 Dart 侧 `waitUntilReadyToShow()` 不足以保证 macOS 原生窗口不会提前出现。
- Dart 侧应等待窗口配置完成，再运行 Flutter；首帧栅格化完成后才调用 `windowManager.show()`。当前保留 5 秒超时回退，避免首帧异常时窗口永远不可见。
- macOS 在配置窗口和 `runApp` 之前调用 `LiquidGlassWidgets.initialize()`，让液态玻璃 shader 在窗口隐藏期间完成预热。不能只依赖各玻璃控件首次构建时异步加载：原生端 shader 就绪后不会保证立即重建控件，可能导致刷新、排序和未读切换在首次同步完成前只显示普通 fallback，随后才突然恢复玻璃效果。
- XIB 初始尺寸和 Dart `WindowOptions` 默认尺寸均为 `1000 x 750`，避免原生窗口先按 `800 x 600` 创建、随后再跳到 Flutter 默认尺寸。
- 原生标题从窗口创建时就隐藏，避免首帧之前短暂显示 `Auto Folo`；红黄绿按钮仍是系统按钮，Flutter 正式界面显示后继续按既有规则定位。
- 本轮没有新增“记住上次窗口尺寸”。红色关闭后的进程内重新打开仍保留当前窗口尺寸；完全退出后的冷启动仍使用 `1000 x 750`。

近期 macOS 专属行为：

- 时间线 header 有 `未读 / 全部` 快速切换。
- 已读文章入口/页面仍然存在，但中间 header 快速切换不包含 `已读`。
- 时间线排序按钮位于同步按钮左侧。
- 具体订阅源筛选下，中间时间线 header 不显示订阅源级自动拉取全文/自动翻译/静默设置，也不显示清除筛选；这些范围和设置由左侧侧边栏承担。
- 即使同步在 widget 订阅前已经开始，同步按钮也应开始旋转。
- 文章图片 hover 不再缩小图片，也不显示边框；可点击图片通过 native channel 使用 macOS zoom-in 光标。
- 中间时间线/列表 header 不再使用玻璃背景；保留分隔线。
- 文章详情 header 暂时保留当前处理，除非用户要求再次调整。
- macOS max fling velocity 是用户可配置项，并应全局应用于 macOS。
- 普通时间线和垃圾拦截页的同步按钮复用 `AppGlassSyncButton`；如果调整 macOS 同步按钮样式、旋转或 tooltip，应改共用组件。

验证清单：

- 红黄绿按钮：位置、hover 符号、非激活灰色状态、关闭/最小化/缩放行为。
- 时间线：未读/全部切换、排序菜单、同步旋转。
- 文章详情：工具栏 hover、图片光标、表格渲染、目录行为。
- 全屏视频：顶部无桌面冗余按钮，红黄绿进入时隐藏/退出时恢复，`Space`、左右 5 秒和 `Esc` 正确，播放结束停在最后一帧。
- 设置/任务中心：滚动行为、轻量面板、没有重复 scrollbar。
- 冷启动：完全退出进程后双击应用，确认不会先出现灰色空壳、标题或尺寸连续跳变，首个可见画面应已经是 Flutter 正式界面。
- 冷启动同步：刷新按钮旋转期间，刷新、排序和 `未读 / 全部` 三个控件应从首次可见画面起就具有玻璃材质，刷新完成时不应发生材质突变。

已知坑：

- 除非有强理由，否则不要用自绘 Flutter/AppKit 按钮替代系统红黄绿按钮；自绘版本曾无法正确处理 hover/非激活/zoom 语义。
- 本地 macOS release 构建可能因为签名/framework 原因失败；本地 UI 验证使用 debug build。
- 如果 `flutter run -d macos` 看似卡住，先检查 debug 日志量或 foregrounding 问题，不要直接归因于应用启动失败。
- AppKit 窗口几何变化可能被仍在运行的应用缓存。验证红黄绿按钮位置前应完全退出应用。
- macOS/Xcode 26 环境下，`flutter run -d macos --no-pub` 曾在 `[CP] Embed Pods Frameworks` 阶段出现 `Killed: 9 "${PODS_ROOT}/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"`。
- 当前处理是：Debug 配置覆盖 `COCOAPODS_PARALLEL_CODE_SIGN=false`，并在 `DebugProfile.entitlements` 添加 `com.apple.security.cs.disable-library-validation`。前者避免 CocoaPods 并行 ad-hoc signing 被系统无诊断杀掉，后者允许 debug app 加载本地 ad-hoc framework。
- 如果用户机器再次遇到类似问题，先用 `flutter build macos --debug --no-pub -v` 看 Xcode 实际环境中 `COCOAPODS_PARALLEL_CODE_SIGN` 是否为 `false`，再考虑 `rm -rf build/macos` 重建。
- 2026-07-08 又出现一种不同的 `flutter run -d macos --no-pub` 失败：Xcode 构建成功，Flutter 随后报 `Error waiting for a debug connection: The log reader stopped unexpectedly, or never started.`。系统日志显示 `Auto Folo -> Auto Folo.debug.dylib` 被拒载：`library load denied by system policy`。
- 这个问题不是 Dart 业务崩溃，也不是 `[CP] Embed Pods Frameworks` 被 kill。直接 `open build/macos/Build/Products/Debug/Auto Folo.app` 可以启动应用，但 Flutter 等不到 VM Service，因为 debug dylib 没加载成功。
- 已验证修复：Debug 配置设置 `ENABLE_DEBUG_DYLIB = NO`，避免 Xcode 把 Debug 代码拆到 `Auto Folo.debug.dylib`。修改后需要 `flutter clean && flutter pub get` 让 Xcode 重新生成产物，再运行 `flutter run -d macos --no-pub`。
- 不要优先尝试普通 Runner build phase 清理 `com.apple.provenance` xattr。实测这种脚本时机不够晚，最终 CodeSign/构建步骤仍会让产物带上 provenance，并不能稳定解决 debug dylib 被系统拒载。
