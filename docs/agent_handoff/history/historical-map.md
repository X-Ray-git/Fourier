# 历史索引

当专题页信息不够，需要回到 `history/timeline.md` 查原始时间线背景时，使用本页。

如果旧章节和专题页冲突，不要把旧章节当作当前事实。专题页和决策日志才是维护中的当前视图。

## 早期产品基础

- 第 1-15 节：原始应用加固、本地文章库、图片加载、翻译、social/inbox 拉取、通知角标、早期性能工作。
- 第 16-29 节：订阅源分组、文章来源跳转、toast 清理、HTML renderer 性能、自动翻译、左右滑动和已读同步细节。
- 第 30-45 节：已知缺陷、HTML pipeline 修复、视频支持、AI 过滤、LLM 并发、图片画廊、状态通知、UI 美化。

## 阅读、渲染与性能

- 第 56、58、62、64-73 节：大文章分块翻译、表格扁平化、正文懒加载回滚、文章渲染性能、进度条平滑、延迟 build/cache 策略、转场动画。
- 第 141、153、156、158 节：文章宽度可配置、表格/代码块保守修复、滚动期小优化、macOS 正文/设置滚动性能回归。
- 当前维护页：`features/article-rendering.md`、`features/performance.md`、`features/timeline.md`。

## macOS 桌面端适配

- 第 75-79 节：第一次 macOS 分栏适配、快捷键、同步反馈、未读计数。
- 第 88-124 节：导航、快捷键归属、M/Cmd+R/Cmd+Z 行为、图片/链接交互、审核页焦点、scrollbar/progress 不稳定。
- 第 145-152 节：目录、Android 过渡、Liquid Glass 分支、设置/任务中心、浮动控件、header 对齐。
- 第 154-165 节：中间 header 取消玻璃、滚动惯性设置、同步旋转、性能回退、release note 防线、外观模式、系统红黄绿、时间线排序。
- 当前维护页：`platforms/macos.md`、`design/liquid-glass.md`、`design/macos-ui.md`、`features/keyboard-shortcuts.md`。

## 发布、版本与仓库操作

- 第 49-50 节：早期 beta release 和仓库管理规范。
- 第 80-84 节：Android + macOS 内部发布流程、签名冲突、Android 灰屏发布。
- 第 91-92 节：worktree 审计和版本自动化。
- 第 109-110、159-160 节：release notes、annotated tag、字面量 `\n` fail-fast 行为。
- 当前维护页：`operations/release-build.md`、`operations/git-worktrees.md`、`history/decisions.md`。

## 身份、隐私与迁移

- 第 127、142-144 节：README/图标清理、设置剪贴板备份、包命名空间迁移、迁移验证。
- 当前维护页：`product/privacy.md`、`product/terminology.md`、`history/migrations.md`、`platforms/android.md`。

## 功能区域

- 时间线与过滤：第 8、20、38-44、46-48、68、90、138、164-165 节。
- 翻译与摘要：第 10、21、27-28、54、56、129、145、163 节。
- 垃圾拦截/审核：第 33、48、51、100、103、105、108、117、123 节。
- 设置与后台任务：第 34、74、94、142、149-150、155、162 节。

## 维护规则

未来修改如果依赖某个旧章节，请把长期有效结论复制到对应专题页或 `history/decisions.md`。让 `timeline.md` 作为证据来源，而不是主要操作手册。
