# Fourier 交接入口

本文档只作为后续 agent 的短入口。完整知识库是 [Fourier 工程 Wiki](index.html)（克隆后双击 `index.html` 即可离线浏览；每个专题页是自包含的 `.html` 单文件，正文以 Markdown 内嵌，编辑与阅读同一个文件）。

接手时按这个顺序阅读：

1. 先读 Wiki 首页：[index.html](index.html)。
2. 再读[当前状态](docs/agent_handoff/status/current.html)。
3. 根据当前任务阅读对应专题页（导航见左侧边栏）。
4. 需要历史证据时，先查[历史主题归档](docs/agent_handoff/history/archive/README.html)；按旧章节编号追溯时使用[历史时间索引](docs/agent_handoff/history/chronology.html)。

当前硬性规则：

- 除非用户明确要求，否则不要打 tag 或发布 release；发布只允许从 `main` 分支通过 `scripts/release.sh` 进行。
- Flutter 项目健康检查优先使用 `dart analyze lib test`、`flutter analyze lib test` 和有针对性的 `flutter test`；完整 `dart analyze` 会扫描 `reference/` 并报告无关错误。
- 不要把密钥、API 响应、抓取的真实文章 HTML、临时脚本提交进 git。此类内容放进已忽略的 `scratch/`。
- 当前应用标识命名空间是 `io.github.xraygit.fourier`。历史 `io.github.xraygit.autofolo`、`com.folo.*` 与 `com.autofolo` 仅用于迁移兼容或历史记录，不得重新作为当前命名引入。
- macOS 发布产物必须保持 arm64。

Wiki 维护：

- 编辑 `.html` 页面中 `<script type="text/markdown" id="wiki-content">` 块内的 Markdown 正文；方法见[站点指南](docs/agent_handoff/meta/site-guide.html)。
- 修改内容后运行 `./scripts/docs.sh index` 重新生成搜索索引，再运行 `./scripts/docs.sh check` 验证。
- 旧 `.md` 页面已全部迁移为同名 `.html`；映射见[旧文档迁移映射](docs/agent_handoff/meta/migration-map.html)。

常用页面：

- [发布与构建](docs/agent_handoff/operations/release-build.html)
- [Git worktree](docs/agent_handoff/operations/git-worktrees.html)
- [macOS 平台说明](docs/agent_handoff/platforms/macos.html)
- [文章渲染](docs/agent_handoff/features/article-rendering.html)
- [媒体播放](docs/agent_handoff/features/media-playback.html)
- [时间线](docs/agent_handoff/features/timeline.html)
- [翻译与摘要](docs/agent_handoff/features/translation-summary.html)
- [Liquid Glass 设计](docs/agent_handoff/design/liquid-glass.html)
- [决策日志](docs/agent_handoff/history/decisions.html)
