# 发布记录

本页保存曾由发布流程追加到根 `AGENT_HANDOFF.md` 的发布足迹。当前发布方法以 [发布与构建](../operations/release-build.md) 为准，更完整的旧发布背景位于 [发布、Git、Worktree 与 CI 归档](archive/release-git-and-ci.md)。

## v1.1.27

```bash
./scripts/release.sh 1.1.27 -m "- feat: support inline YouTube playback and macOS system fullscreen\n- fix: improve local video loading, aspect ratio, controls and keyboard behavior\n- style: refine macOS timeline, article cards, scrollbars and compact glass controls\n- fix: improve article metadata rendering, timeline interactions and macOS startup stability" --push
```

## v1.1.28

```bash
./scripts/release.sh 1.1.28 -m "- feat: add swipe review actions and coordinated list transitions\n- fix: stabilize macOS control interactions and timeline read animations\n- style: refine compact timeline controls and article scrollbar spacing" --push
```

这些命令只作为历史证据，不应直接复制执行。创建新版本前必须重新确认版本号、提交状态和 release notes。

## v1.2.0

```bash
./scripts/release.sh 1.2.0 -m $'- feat: add macOS subscription management with undoable changes\n- feat: add unified YouTube and Bilibili playback with quality, subtitles and danmaku\n- fix: align embedded video controls, shortcuts, scrolling and fullscreen across platforms' --push
```

首次 tag 触发时，Android 因 workflow 引用了不存在的
`actions/setup-java@v6` 而在 job 初始化阶段失败，未创建 GitHub Release。
确认没有正式发布产物后删除该 tag；workflow 改为使用 Node 24 的
`actions/setup-java@v5`，随后在保持 `1.2.0+31` 和原 release notes 不变的
前提下，于修复提交上重建 annotated `v1.2.0`。

## v1.2.1

```bash
./scripts/release.sh 1.2.1 -m $'- feat: add cross-platform Folo browser login and account switching\n- feat: add misclassification actions with atomic undo and review markers\n- feat: retry failed article images with deterministic backoff\n- fix: preserve undo animations and Android settings labels' --push
```
