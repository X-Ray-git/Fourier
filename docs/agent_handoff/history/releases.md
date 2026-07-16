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
