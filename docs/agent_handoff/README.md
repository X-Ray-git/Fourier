# Auto Folo 交接知识库

这个目录是后续 agent 使用的维护型知识库。它把当前事实、专题知识、操作流程、设计规则和历史上下文拆开维护。

推荐阅读顺序：

1. [status/current.md](status/current.md)
2. [status/pending.md](status/pending.md)
3. [operations/testing.md](operations/testing.md)
4. 当前任务对应的专题页。
5. 只有需要完整时间线记录时再读 [history/timeline.md](history/timeline.md)。

知识地图：

- 状态：[当前状态](status/current.md)、[待办与搁置](status/pending.md)、[验证记录](status/verification.md)。
- 架构：[概览](architecture/overview.md)、[存储与缓存](architecture/storage-and-cache.md)、[网络](architecture/networking.md)、[路由与状态](architecture/routing-state.md)。
- 产品：[原则](product/principles.md)、[术语](product/terminology.md)、[隐私](product/privacy.md)。
- 平台：[macOS](platforms/macos.md)、[Android](platforms/android.md)。
- 功能：[时间线](features/timeline.md)、[文章渲染](features/article-rendering.md)、[性能](features/performance.md)、[翻译与摘要](features/translation-summary.md)、[垃圾拦截/审核](features/filter-review.md)、[设置](features/settings.md)、[后台任务](features/background-tasks.md)、[订阅源](features/subscriptions.md)、[快捷键](features/keyboard-shortcuts.md)。
- 操作：[发布与构建](operations/release-build.md)、[Git worktree](operations/git-worktrees.md)、[测试](operations/testing.md)、[故障排查](operations/troubleshooting.md)。
- 设计：[Liquid Glass](design/liquid-glass.md)、[macOS UI](design/macos-ui.md)、[交互模式](design/interaction-patterns.md)。
- 历史：[决策日志](history/decisions.md)、[迁移](history/migrations.md)、[历史索引](history/historical-map.md)、[完整时间线归档](history/timeline.md)。

维护规则：

- 这个知识库只保留当前仍有用的知识。
- 如果某个专题页继续变大，按子专题拆分，不要无限追加。
- 完整时间线保存在 `history/timeline.md`；提炼总结时不要删除归档。
- 记录决策时优先写入 `history/decisions.md`，包含背景、决策、后果和“不要回退”的说明。
