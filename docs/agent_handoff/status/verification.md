# 验证记录

## 仍需持续观察

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
