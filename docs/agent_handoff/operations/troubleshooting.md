# 故障排查

`flutter run -d macos` 看起来卡住：

- 过大的 debug HTTP 日志曾导致 log reader 不稳定。
- Dio body/header 日志现在已在 debug 下关闭。
- 如果 VM Service/DevTools URL 已出现，即使 foregrounding 报 warning，应用也可能已经在运行。

macOS release app 本地打不开：

- 本地 release 签名/framework 加载可能因为 ad-hoc 或未知证书链失败。
- 除非专门测试 release packaging，否则本地 UI 验证使用 debug build。

Android 安装冲突：

- 包名相同但签名 key 不同会造成安装冲突。
- 单纯提高版本号不能解决签名不匹配。

Analyzer 出现几千个错误：

- 很可能运行了完整 `dart analyze`，扫描了 `reference/`。
- 使用 `dart analyze lib test`。

macOS 文章滚动回归：

- 不要先猜，先和已知良好 tag 对比。用户认为 `v1.1.20` 明确流畅，`v1.1.23` 是有用的良好基线，`v1.1.25` 明显变差。
- 优先检查重型重复玻璃：未读标签、设置行、任务行、卡片装饰。
- 不要直接跳到 `SliverList.builder`；那有已知行为风险。

触控板滚动太快：

- `maxFlingVelocity` / `macos_max_fling_velocity` 可以减少 fling 后的惯性位移。
- 它不会限制手指仍在触控板上时每一帧的原始滚动 delta。
- 原始事件拦截可行但侵入性强；除非用户明确接受风险，否则避免采用。

Release notes 出现字面量 `\n`：

- 必要时修正 release note body。
- 未来 release 应通过 `scripts/release.sh`，该脚本会拒绝字面量 `\n`，除非显式允许。
