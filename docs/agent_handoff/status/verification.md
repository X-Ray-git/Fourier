# 验证记录

## 仍需持续观察

- macOS 圆形工具按钮和文章范围 morph 已完成用户视觉检查后进入提交：深色按钮应比旧版更通透；浅色按钮应通过冷白材质、左上高光和仅位于外部的双层阴影保持可见，内部不能因阴影发灰。文章范围在主时间线与订阅源详情都应只显示“未读/全部”，深色触发图标为白色、浅色为 `onSurface`，展开/收回和筛选结果应与排序共用的 morph 行为一致。后续如调整共享组件，要同时检查排序与两处范围入口。
- macOS 主时间线动画与滚动已完成日志和视觉验证：在约 `4799` 篇本地文章下，两次 `M`、四次双击都完整经过 `4→3→2→1→0`，没有列表 reset；用户确认实际动画正常。后续普通使用中仍应留意 `Command-Z`、同步刷新、排序和范围变化不能重新引入回顶或大规模列表动画，但不再把本次故障视为未验证修复。
- 已读文章偶发重新出现：并发旧快照竞态已修复，仍需在刷新与连续标记已读交叠时持续观察。正常日志中，旧未读快照不应触发重新出现；服务端快照不再包含文章时可见 `snapshot.confirms-local-read`。若再次出现，保留 `snapshot.missing-local-read-override`、`unread-list.reappeared` 及相邻动画日志。
- 自动 AI 队列：刷新后快速把等待翻译/摘要的文章标为已读，后台等待数量应下降，文章不应长期停留在“翻译中”。已经进入处理批次的任务继续完成属于预期。
- 详情页正文补抓：打开一篇初始正文为空、成功补抓普通全文或 Inbox 正文的未读文章，应进入摘要队列；所属订阅源已开启自动翻译时也应进入翻译队列。后台译文在页面保持打开时完成，应直接出现译文状态和内容。文章已经标为已读或订阅源未开启自动翻译时不触发相应自动任务属于预期。
- macOS 空状态对齐：在没有文章的订阅源或筛选范围中，左侧列表空态勾图标与右侧文章空态图标应处于同一视觉高度。该项修复后没有留下明确的最终用户确认，因此继续保留观察。
- macOS 订阅源侧边栏 scrollbar：展开包含较多订阅源的分类，等待展开动画结束，再持续上下滚动经过多个分类/view；拇指长度应保持稳定并随滚动方向单调移动。展开/折叠的 `180ms` 内随内容高度平滑变化属于预期；同时确认没有双 scrollbar，订阅源点击、静默分组和多个分类同时展开时的滚动性能正常。
- Bilibili 正文视频：严格 URL 解析、readability 白名单、懒加载 widget 与完整 Flutter 测试均已通过，用户已允许提交；对话中尚未留下 macOS/Android 实际播放、控制栏和系统全屏的明确逐项反馈。发布前应至少在一篇“本周看什么”中验证点击播放、同篇多视频不预加载、全屏退出，并回归一个 YouTube 视频。
- macOS 阅读快捷键：分别在主时间线、垃圾拦截和最近阅读验证 `B`、`Shift+B`、`Esc` 与无选择时的 `Left/Right`；确认 `Shift+B` 保留退场动画和撤销语义，垃圾拦截按“移除并打开”处理。验证 `Cmd+1/2/0` 切换全部文章、垃圾拦截和静默订阅源，连续按键不应让时间线回顶；输入框和隐藏的 `IndexedStack` 页面不能抢裸方向键。

其余曾列在 `status/current.md` 的 macOS 视觉、列表动画、横滑、tooltip、复制、卡片和侧边栏检查均已在后续使用或提交前验证中通过，不再作为开放验证项重复维护。

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
