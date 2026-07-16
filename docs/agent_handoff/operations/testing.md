# 测试

主要命令：

```bash
dart analyze lib test
flutter analyze lib test
flutter test
flutter build macos --debug
```

预期注意点：

- Flutter 命令可能需要权限更新 Flutter SDK cache。
- 完整 `dart analyze` 会很吵，因为 `reference/` 包含外部复制来的参考工程。

当前测试：

- `test/article_content_utils_test.dart`
- `test/article_card_test.dart`
- `test/article_model_test.dart`
- `test/feed_model_test.dart`
- `test/html_entity_utils_test.dart`
- `test/implicitly_animated_list_test.dart`
- `test/widget_test.dart`

修改单个功能时，先运行相关窄测试；推送前再运行完整项目测试套件。

macOS 列表动画诊断埋点默认关闭。普通 Debug/Release 不打印，也不会挂载动画监听器。复现 `M/K`、审核横滑或主时间线双击偶发瞬移时，运行：

```bash
flutter run -d macos --no-pub \
  --dart-define=AUTO_FOLO_ANIMATION_PROBE=true \
  2>&1 | tee /tmp/auto-folo-animation.log
```

按页面过滤：

```bash
grep ReviewAnimProbe /tmp/auto-folo-animation.log
grep TimelineAnimationProbe /tmp/auto-folo-animation.log
grep TimelineListResetProbe /tmp/auto-folo-animation.log
grep TimelineReadStateProbe /tmp/auto-folo-animation.log
```

`TimelineAnimationProbe` 同时覆盖主时间线的 `M`、双击、退场动画进度和滚动 offset；`TimelineListResetProbe` 记录零时长批量同步的明确原因，用于确认单篇读状态是否被错误归入批量路径；`TimelineReadStateProbe` 区分已读状态被未读快照降级与列表组件的纯视觉残影。埋点只输出文章 id 的末 8 位、动作来源、列表数量、动画阶段和慢帧耗时，不输出标题、正文、凭据或完整文章 id。不要为了普通运行长期打开该开关；同步 `debugPrintSynchronously` 本身可能轻微干扰 Debug 性能测量。
