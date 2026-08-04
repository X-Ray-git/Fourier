# 验证记录

## 2026-08-04 误分类（N）标记与撤销

已完成端到端验证：

- 四种动作标记写入正确：拦截页 `K`→`k`、拦截页 `M`→`m`、拦截页 `N`→`n_keep`、时间线 `N`→`n_spam`，状态组合（拒绝/已读/已审）与理由保留全部符合预期，`tool/inspect_user_actions.dart` 核对通过。
- `Cmd+Z` 撤销回滚验证：时间线 `N` 后立即撤销，文章完整还原为 `拒绝=false 已读=false 已审=false act=null`（forceReplace 整条替换快照生效）。
- 撤销栈清空行为符合预期：跨应用实例的动作（如调试构建期间的受控测试标记）不在新实例的撤销栈内，无法撤销，属预期。
- 误分类功能相关的旧 bug 修复后确认：已读视图/最近阅读打开文章不再出现白色覆盖（GetX 误用修复）；拦截页未点开详情直接按 `M/N` 也能生效（页面级处理器）。
- 正式版已重建（`flutter build macos --release`），134 项 Flutter 测试通过、`dart analyze lib` 无 error。
- 用户测试产生的标记与状态污染已用一次性脚本清理，数据库恢复为 0 标记残留。

仍需留意：

- Android 尚未加入误分类按钮（按计划待定）；字段随共享模型落库，后续接入即用。
- 调试构建期间曾发生两次无日志、无崩溃报告的静默退出（无退出码捕获前），未定位根因；正式版未复现。若正式版再次出现，需在带退出码捕获的启动方式下复现。
- 旧版本二进制混用会静默剥掉 `userAction`（已接受语义），统计结果应视为"只有真的没有假的"。
- 合并审查补充修复：页面级快捷键已放行 Alt/Control/Command；撤销同步失败会重建完整操作态；所有现有文章复制路径均保留 `userAction`；时间线误分类不再用立即通知绕过退场动画。新增修饰键状态和操作态快照测试；`flutter test --no-pub` 共 136 项通过，`dart analyze lib test tool` 无 error/warning，仅保留 67 条既有 info。
- 统计范围经用户再次确认只需近期分析：记录随 `articleDb` 的 5000 篇缓存和账号清理生命周期存在，不承诺永久完整历史。

## 仍需持续观察

- 2026-07-31 图片加载失败重试机制已收敛到 `ArticleImageCacheService`（自动指数退避 `1s/2s/4s` 共 3 次、失败状态落盘、全局刷新 `retryFailedPrefetches` 串行重扫、成功后以图片级 `successRevision` 精确重建）。需在 macOS/Android 真机验证：打开含失败图片的文章，确认失败占位先显示“重新加载中…”、后台自动重试成功后占位自动变成图片（无需手动点）；自动重试耗尽后占位文案变为“图片加载失败，点击重试”，手动点击仅发起一条 service 下载链并可恢复；普通位图与独立块级 SVG 都需覆盖。切到时间线做一次全局刷新，确认之前失败的图片会在缓存清理完成后重新排查，进程重启后刷新仍能重扫落盘记录。HTML 行内图片扩展和图片画廊本次未纳入重试，属预期范围边界。决策与边界见 `history/decisions.md`“图片加载失败的重试统一收敛到 ArticleImageCacheService”。
- 2026-07-31 Android 设置页 `_LlmConfigCard`（翻译/摘要/过滤 LLM 参数卡片）展开后第一个下拉框“模型”的浮动 label 上半部分被裁切。根因是 `ExpansionTile` children padding 顶部为 `0`，浮动 label 向上越出 `OutlineInputBorder` 约 `8.6px` 的部分被 `ExpansionTile` 内部 `ClipRect` 和外层 `MobileSettingsPanel` 的 `Clip.antiAlias` 切掉；已把该 padding 顶部改为 `10`。需在真机分别展开翻译、摘要、过滤三个 LLM 参数卡片，确认“模型”及其他首项浮动标签完整显示，且展开动画和卡片整体布局无异常。静态分析与排查结论见 `history/decisions.md`“带浮动标签的设置输入控件上方必须为裁切容器预留缓冲”。
- 2026-07-29 YouTube SABR 首选播放器尚待用户实机验证。macOS 与 Android
  分别打开真实 YouTube 文章，检查首次点击有即时 loading、能够开始播放、
  播放/暂停、拖动橙色进度条、清晰度/字幕/语言/倍速切换和系统全屏可用；
  单击画面应只显隐控件，播放时 3 秒淡出、暂停时保持显示。macOS 触控板在
  视频画面和控制栏上纵向滑动应继续滚动文章，打开分辨率/字幕菜单后菜单
  自身仍可滚动；开始播放后点击文章其他位置，`Space`/媒体播放键仍应控制
  当前视频，同篇切换另一视频后快捷键归属应随之转移。Android 触摸纵向
  滑动不得被 WebView 锁死。切换文章不能残留上一篇控制器；SABR UMP 没有
  媒体段时应先尝试同控件的普通自适应 DASH，只有两者都失败才在 35 秒内
  切到官方 iframe，不得打开无关浏览器页面；官方 iframe 的内部滚轮不承诺
  桥接。
  macOS Release 还需确认 sandbox 下 loopback server 可以绑定；Android
  需确认只放行 localhost 明文而外部 HTTPS 行为不变。
- macOS 静默订阅源批量导出的入口、勾选、四类动作、morph 展开和 `Esc` 退出已完成用户运行确认。仍需在真实网络偶发部分成功时观察：本地列表、菜单篇数、刷新后的远端状态与 Undo/Redo 历史必须只反映最终确认改变的子集；保存取消或失败不能标为已读。
- GitHub 发布 Actions 已迁移到 Node 24 对应的 `checkout@v7`、`setup-java@v5`、`upload-artifact@v7` 和 `download-artifact@v8`，Flutter pin 也从 `3.41.6` 对齐为 `3.44.6`。`v1.2.0` 首次触发确认版本校验和 macOS arm64 全部成功，但 Android 因不存在的 `setup-java@v6` 在 job 初始化阶段失败，GitHub Release 因依赖关系被跳过；旧 tag 未产生 Release 后已删除，workflow 修正为实际使用 Node 24 的 `@v5`，等待重建同名 tag。重新触发后应确认 Android、macOS arm64 和 GitHub Release 三段均成功。
- macOS 圆形工具按钮和文章范围 morph 已完成用户视觉检查后进入提交：深色按钮应比旧版更通透；浅色按钮应通过冷白材质、左上高光和仅位于外部的双层阴影保持可见，内部不能因阴影发灰。文章范围在主时间线与订阅源详情都应只显示“未读/全部”，深色触发图标为白色、浅色为 `onSurface`，展开/收回和筛选结果应与排序共用的 morph 行为一致。后续如调整共享组件，要同时检查排序与两处范围入口。
- macOS 主时间线动画与滚动已完成日志和视觉验证：在约 `4799` 篇本地文章下，两次 `M`、四次双击都完整经过 `4→3→2→1→0`，没有列表 reset；用户确认实际动画正常。后续普通使用中仍应留意 `Command-Z`、同步刷新、排序和范围变化不能重新引入回顶或大规模列表动画，但不再把本次故障视为未验证修复。
- 已读文章偶发重新出现：并发旧快照竞态已修复，仍需在刷新与连续标记已读交叠时持续观察。正常日志中，旧未读快照不应触发重新出现；服务端快照不再包含文章时可见 `snapshot.confirms-local-read`。若再次出现，保留 `snapshot.missing-local-read-override`、`unread-list.reappeared` 及相邻动画日志。
- 自动 AI 队列：正文可用时已经是已读的文章不应进入自动翻译/摘要队列。以未读状态入队的文章后续被标记已读时，任务仍完成属于预期，不再验证等待数量因已读操作下降。
- 详情页正文补抓：打开一篇初始正文为空、成功补抓普通全文或 Inbox 正文的未读文章，应进入摘要队列；所属订阅源已开启自动翻译时也应进入翻译队列。后台译文在页面保持打开时完成，应直接出现译文状态和内容。文章已经标为已读或订阅源未开启自动翻译时不触发相应自动任务属于预期。
- macOS 空状态对齐：在没有文章的订阅源或筛选范围中，左侧列表空态勾图标与右侧文章空态图标应处于同一视觉高度。该项修复后没有留下明确的最终用户确认，因此继续保留观察。
- macOS 订阅源侧边栏 scrollbar：展开包含较多订阅源的分类，等待展开动画结束，再持续上下滚动经过多个分类/view；拇指长度应保持稳定并随滚动方向单调移动。展开/折叠的 `180ms` 内随内容高度平滑变化属于预期；同时确认没有双 scrollbar，订阅源点击、静默分组和多个分类同时展开时的滚动性能正常。
- Bilibili 自定义正文播放器尚待实机视觉验证：在少数派“本周看什么”分别
  用 macOS/Android 检查点击后有即时 loading、可播放、暂停、拖动进度条、
  音量、倍速、实际可用画质、字幕（源视频提供时）和系统全屏；单击显隐、
  控件 3 秒淡出、播放结束、空格/媒体键、macOS 视频区域触控板滚动和
  Android 纵向文章滚动应与 YouTube/普通视频一致。同篇多个 Bilibili 不得
  预加载；分 P 应选正确 `p/cid`。确认默认显示弹幕，控制栏“弹”可关闭和
  重新开启；暂停时弹幕冻结，拖动后不重放旧弹幕，倍速、窗口尺寸变化和
  系统全屏下仍与画面同步；滚动、顶部、底部及彩色弹幕可读，密集片段没有
  明显掉帧。匿名 API 或媒体失败时应自动进入官方 iframe；单段弹幕失败只
  缺少该段弹幕，不得留下永久 loading、打开无关网页或影响 YouTube。
  2026-07-29 已用真实匿名分段响应验证 Protobuf 解析，并通过运行时
  typecheck/build、117 项 Flutter 测试、macOS Debug 构建和 Android Debug
  APK 构建；以上自动验证不能替代实际弹幕密度、字号和控制栏位置的视觉检查。
- macOS 阅读快捷键：分别在主时间线、垃圾拦截和最近阅读验证 `B`、`Shift+B`、`Esc` 与无选择时的 `Left/Right`；确认 `Shift+B` 保留退场动画和撤销语义，垃圾拦截按“移除并打开”处理。验证 `Cmd+1/2/0` 切换全部文章、垃圾拦截和静默订阅源，连续按键不应让时间线回顶；输入框和隐藏的 `IndexedStack` 页面不能抢裸方向键。

其余曾列在 `status/current.md` 的 macOS 视觉、列表动画、横滑、tooltip、复制、卡片和侧边栏检查均已在后续使用或提交前验证中通过，不再作为开放验证项重复维护。

macOS 显式窗口拖动已完成用户运行确认：侧边栏顶部空白和各桌面标题区域可以拖动，双击标题可以最大化/还原；标题栏按钮内部按下并轻微移动不会拖动窗口，设置页面板、输入框和普通正文也不再被隐式当作拖动区。静态分析无错误或警告，100 项 Flutter 测试和 macOS Debug 构建均通过。

## 2026-07-25 Android 角标与跨平台文章长度

- 用户确认 Android 底部导航只使用橙色实心图标表达选中、不再绘制橙色底板后，和 `#DB4A3E` 红色无边框数字角标的视觉关系合理。
- 用户确认 Android 与 macOS 卡片在订阅源行右侧显示预计内容高度的布局符合预期。普通卡片与 macOS 垃圾拦截独立审核行共用同一估算和标签组件。
- `ArticleLengthEstimator` 使用固定 `340 logical px` 基准，格式化、图片计入和缓存稳定性有定向测试；完整 `flutter test --no-pub` 共 `103` 项通过。`dart analyze lib test` 无 error/warning，仍只有仓库既有 `prefer_initializing_formals` info。

## 2026-07-22 Android 主导航与文章悬浮图标

- 用户确认垃圾拦截作为第四个主导航入口后，嵌入页面顶部避让修复正确，审核卡片不再进入主 AppBar。
- 时间线和垃圾拦截角标使用现有重叠计数属于明确产品决定，不需要后续改为互斥队列。
- 文章页右下角目录、标为已读和恢复未读已统一改为 `24px` Rounded Material Symbols、字重 `700`；共享按钮字重传递有定向 widget 测试，Android Debug APK 已构建通过。

## 2026-07-18 Android 设计迁移验证

用户已在真机 Debug/Release 路径完成视觉检查：

- 主时间线与订阅源详情的圆形文章范围按钮、`未读/全部` 玻璃选择面板和 `12px` 卡片对齐正确；两处筛选结果必须一致。
- Android 普通时间线与垃圾拦截卡片的标题均为 `14px`、辅助正文为 `12px`；需要在真实手机上确认可读性和信息密度。
- Android 垃圾拦截横滑圆角已在真机 Debug 中确认：保留/移除背景完整填充卡片真实让出的区域，最外侧保持 `16px` 圆角，彩色背景与移动卡片交界处也不再出现直角。根因与不可回退结构见[垃圾拦截与审核](../features/filter-review.md)。
- 最近阅读入口、文章圆形已读按钮、目录面板和订阅源设置面板可用。
- 底部悬浮导航选中反馈、页面淡入淡出和仅向外扩散的阴影符合预期；导航后续已扩展为四项。
- Inbox 展开不再出现 Debug 红色 GetX 错误或 Release 灰色色块。
- 底部面板统一 `32px` 圆角后未发现屏幕边缘溢出。
- 设置页、后台任务中心、失败记录、移动端菜单和其余次级页面迁移后功能与视觉符合预期。
- 底部导航按目标设备反推为 `12px` 边距、`56px` 高、`28px` 半径后，用户确认圆角视觉可接受；系统手势未反馈冲突。
- 设置选择面板的玻璃背景、动画和选择即保存可用；外层误裁剪浮动标签的问题修复后，用户确认显示正常。
- 普通移动端 AppBar 从 `56px` 收敛为 `48px`，相关正文顶部避让同步调整，用户确认高度合适。

2026-07-19 真机视觉复查后，文章范围触发图标已改为“未读/全部”都使用中性前景色，避免未读态误显橙色。主 shell 右侧搜索也已改为与左侧范围入口一致的 `36px` 圆形玻璃按钮，左右各保持 `12px` 边距；用户确认后允许提交。

后续只需在明显不同屏幕圆角、底部安全区或三键导航设备上复查底栏位置；当前参数不是通用物理屏幕圆角真值。

推荐 Android 检查：

```bash
dart analyze lib test
flutter test --no-pub
flutter build apk --debug --no-pub
flutter run -d <device-id> --no-pub
```

## 2026-07-31 macOS Folo 浏览器登录与账号重建

- `dart analyze lib test`：无 error/warning；仍只有仓库既有的 `prefer_initializing_formals` info。
- `flutter test --no-pub`：125 项全部通过，新增账号切换隔离、官方登录 URL、候选账号显示名和 version 1 配置解析兼容测试。
- `flutter build macos --debug --no-pub`：构建成功；只有 `video_player_avfoundation 2.9.6` 的既有 `AVKeyValueStatus` 弃用警告。
- 仍需用户真实运行验证：未登录浏览器时的官方登录页；已登录浏览器的快速回调；等待页取消；同一账号退出后重新登录并重建；手动 Token；旧配置导入；Prompt/DeepSeek/外观等普通设置在退出与重建后保持不变。

## 2026-08-01 Android Folo 登录入口

- 第一版系统浏览器实现已在真机确认失败：Folo 会根据 Android 移动 UA 在到达 SSR 登录页前将请求 `302` 至 `https://folo.is/`。桌面 UA 请求同一 URL 则返回 `200`。
- 第二版全屏应用内 WebView + 桌面 UA 能加载 Folo 页面，但 Google 在真机明确提示“不安全的浏览器或应用”，因此该实现已撤销。
- 第三版系统浏览器 + Chrome“桌面版网站”也已真机确认失败：设置发生在重定向后的 `folo.is`，重新打开原始 `app.folo.is` 登录 URL 时仍会按移动 UA 再次跳转。
- 当前第四版改为官方移动端 Better Auth Expo 同类流程：`sign-in/social` → `expo-authorization-proxy` → Chrome Google 登录 → `folo://autofolo-auth?cookie=...` → `/get-session` 验证。服务端探针已确认 `folo://autofolo-auth` callbackURL 被接受，authorization proxy 能正确写入 OAuth state 并 302 至 Google。
- 第四版首次真机授权后仍落到 `folo.is`：原因是实现错误地把初始响应中的普通 `better-auth.state` 作为 Expo `oauthState` 传给 proxy。官方 Expo 客户端只转发独立的 `oauth_state`；当前响应没有该 cookie，因此正确行为是省略参数，让 proxy 从 authorization URL 取 raw state 并自行签名。服务端探针已确认省略参数时返回正确的 `__Secure-better-auth.state`。
- `flutter test --no-pub test/folo_auth_service_test.dart`：5 项通过，覆盖 CLI URL、provider 响应解析、Expo authorization proxy URL、Session Cookie 提取和账号显示名。
- `dart analyze lib test`：无 error/warning；仅有 59 条已存在的 liquid-glass `prefer_initializing_formals` info。
- `flutter build apk --debug --no-pub`：构建成功；`apkanalyzer` 确认最终 manifest 只声明 `folo://autofolo-auth` 精确 host。
- Google 真机流程已确认：浏览器授权返回 Auto Folo，MethodChannel 收到回调，`/get-session` 验证通过，等待窗口关闭，Session Token 持久化，文章数据库与缓存开始重建。此前“闪烁后仍等待”是 Flutter 默认深链与 MethodChannel 双重处理同一 URI，现由 `MainActivity.shouldHandleDeeplinking() = false` 修复。
- 多方式实现后，`flutter build apk --debug --no-pub` 成功；无效 Email 探针得到 Folo 结构化 `401 INVALID_EMAIL_OR_PASSWORD`，确认接口和移动 fallback header 可被服务端处理。真实 Email/TOTP 和 GitHub 仍需对应账号真机验证。
- 登录入口新增 provider 等待动画；账号状态改为 macOS `48px`、Android `52px` 的无内描边头像与用户名，图片按约三倍显示尺寸解码，失败时回退首字符。资料编解码、头像字段解析与既有认证测试共 8 项通过，相关文件静态分析无问题。仍需两端视觉确认：旧 Token 启动后能自动补全名字/头像、重新启动无需再次查询、退出后旧资料消失、配置导入后资料正确恢复。
- macOS 安全日志确认登录 URL 含 `cli_callback`、系统浏览器打开成功、localhost 收到 `GET /callback` 且带一次性 Token。此前必须把焦点切回 Auto Folo 才完成登录，是 Android 共用的生命周期门禁误用于 macOS；现已拆分为 macOS 收到并验证回调后立即后台完成，Android 仍等待应用恢复前台。Folo 官网回调生成期间显示的“打开 Folo”会唤起官方客户端，属于上游通用页面行为；Auto Folo 等待框已明确提示无需点击。保留只记录 host/path/布尔状态而不记录 Token 的 `FoloAuthProbe` 检查点继续观察。

## 常规检查

推荐检查：

```bash
dart analyze lib test
flutter analyze lib test
flutter test
flutter build macos --debug
```

迭代时可以使用更小范围的检查：

```bash
dart analyze lib/pages/article/article_page.dart
flutter test test/article_model_test.dart test/feed_model_test.dart test/html_entity_utils_test.dart
```

不要依赖：

```bash
dart analyze
```

原因：仓库的 `reference/` 下有复制来的参考工程；完整 `dart analyze` 会把它们也扫进去，并产生无关错误。

macOS 本地 UI 验证：

```bash
flutter run -d macos
```

或者：

```bash
flutter build macos --debug
open "build/macos/Build/Products/Debug/Auto Folo.app"
```

不要把本地 macOS release 构建作为主要 UI 验证目标。本地环境可能把 release 产物视为 ad-hoc 签名或未知证书链，从而造成启动/framework 加载问题；这不一定和当前代码有关。

如果 macOS Debug 出现“构建成功但等不到 debug connection”：

```bash
flutter clean
flutter pub get
flutter run -d macos --no-pub
```

当前 Debug 配置依赖 `ENABLE_DEBUG_DYLIB = NO` 避免 `Auto Folo.debug.dylib` 被 macOS 系统策略拒载。验证时应看到 `A Dart VM Service on macOS is available at:`。
