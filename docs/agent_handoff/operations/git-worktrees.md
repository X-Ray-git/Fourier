# Git Worktree

用户经常并行使用多个 Codex agent 和 worktree。

规则：

- 清理或合并前先检查所有 worktree。
- 分支改动通常来自用户需求，但不代表实现一定正确。
- 用户要求保留 merge 行为时，功能 worktree 集成优先使用 merge commit。
- 未经用户确认，不要删除 worktree 或分支。
- 性能实验可能留下可清理的临时 worktree；清理前先检查。
- `main` 内容可能已经由用户确认。用户要求检查 worktree 时，应谨慎评估其他分支；除非用户要求 review main，否则 main 只报告状态。

常用命令：

```bash
git worktree list --porcelain
git status --short --branch
git log --oneline --decorate -12
git diff --stat main...branch-name
```

近期集成记录：

- 五个功能分支已通过 merge commit 合入 `main`：
  - macOS 时间线排序
  - macOS 时间线控件/系统红黄绿按钮
  - 文章详情交互
  - 应用内外观模式
  - HTML entity 解码

合并审查清单：

- 判断分支是否解决真实用户需求。
- 检查实现方式是否符合当前设计/性能约束。
- 关注过期状态、缺少即时 UI 刷新、hover/cursor 不一致、重复 scrollbar。
- 确认 macOS 专属 UI 工作没有意外影响 Android。
- 如果合并改变长期规则，更新对应专题页和决策日志。
