# Auto Folo 交接入口

本文档现在只作为后续 agent 的短入口。详细交接内容已经迁移到 `docs/agent_handoff/` 下的 wiki 式知识库。

接手时按这个顺序阅读：

1. 先读 [docs/agent_handoff/README.md](docs/agent_handoff/README.md)。
2. 再读 [docs/agent_handoff/status/current.md](docs/agent_handoff/status/current.md)。
3. 根据当前任务阅读对应专题页。
4. 只有需要完整时间线证据时，再查 [docs/agent_handoff/history/timeline.md](docs/agent_handoff/history/timeline.md)。

当前硬性规则：

- 除非用户明确要求，否则不要打 tag 或发布 release。
- Flutter 项目健康检查优先使用 `dart analyze lib test`、`flutter analyze lib test` 和有针对性的 `flutter test`；完整 `dart analyze` 会扫描 `reference/` 并报告无关错误。
- 不要把密钥、API 响应、抓取的真实文章 HTML、临时脚本提交进 git。此类内容放进已忽略的 `scratch/`。
- 当前应用标识命名空间是 `io.github.xraygit.autofolo`。历史 `com.folo.*` / `com.autofolo` 引用已经废弃。
- macOS 发布产物必须保持 arm64。

常用页面：

- [发布与构建](docs/agent_handoff/operations/release-build.md)
- [Git worktree](docs/agent_handoff/operations/git-worktrees.md)
- [macOS 平台说明](docs/agent_handoff/platforms/macos.md)
- [文章渲染](docs/agent_handoff/features/article-rendering.md)
- [时间线](docs/agent_handoff/features/timeline.md)
- [翻译与摘要](docs/agent_handoff/features/translation-summary.md)
- [Liquid Glass 设计](docs/agent_handoff/design/liquid-glass.md)
- [决策日志](docs/agent_handoff/history/decisions.md)

---
*🤖 Automated Release Footprint:*
*执行指令: `./scripts/release.sh 1.1.27 -m "- feat: support inline YouTube playback and macOS system fullscreen\n- fix: improve local video loading, aspect ratio, controls and keyboard behavior\n- style: refine macOS timeline, article cards, scrollbars and compact glass controls\n- fix: improve article metadata rendering, timeline interactions and macOS startup stability" --push`*
