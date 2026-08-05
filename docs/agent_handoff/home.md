# Auto Folo — 高密度信息流阅读客户端

<div class="landing">

<section class="hero">
  <div class="hero-inner">
    <div class="hero-logo">
      <span class="hero-orb" aria-hidden="true"></span>
      Auto Folo · 基于 Folo API 与 DeepSeek 驱动
    </div>
    <h2>让 AI 替你<br>筛选信息洪流</h2>
    <p class="hero-sub">
      Auto Folo 把 <strong>Folo 时间线</strong>、<strong>长文阅读</strong>与<strong>可配置的 AI 工作流</strong>
      放进同一个客户端：后台翻译与摘要帮助快速浏览，垃圾拦截判定进入独立审核页，
      最终保留或移除仍由你决定。
    </p>
    <div class="hero-cta">
      <a class="cta-primary" href="#wiki-entry">开始阅读 Wiki</a>
      <a class="cta-ghost" href="docs/agent_handoff/status/current.html">查看当前状态</a>
    </div>
    <div class="hero-badges">
      <span>macOS</span>
      <span>Android</span>
      <span>个人非官方客户端</span>
      <span>AGPL-3.0</span>
      <span>离线工程 Wiki</span>
    </div>
    <p class="hero-note">
      非官方个人二次开发客户端，不隶属于 Folo、RSSNext 或其运营方，也不代表官方发布版本。
    </p>
  </div>
</section>

<section class="landing-section">
  <h2>核心能力</h2>
  <p class="section-lead">不止于阅读——从数据拉取到 AI 决策，形成完整的智能信息处理闭环。</p>
  <div class="feature-grid">

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="3.5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="3.5" cy="18" r="1.4" fill="currentColor" stroke="none"/></svg>
      </div>
      <h3>高密度时间线</h3>
      <p>未读 / 全部 / 已读模式与长度排序，按分类、订阅源与静默订阅源筛选；macOS 原生分栏让列表与正文同步滚动。</p>
    </div>

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l2.2 5.6L20 11l-5.8 2.4L12 19l-2.2-5.6L4 11l5.8-2.4z"/><path d="M19 16.5l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z"/></svg>
      </div>
      <h3>AI 翻译与摘要</h3>
      <p>按订阅源自动翻译与生成摘要，保留 HTML 结构并支持原文 / 译文切换；模型、思考模式、temperature 与并发数独立配置，后台队列只服务仍未读的文章。</p>
    </div>

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l7 3v5c0 4.5-3 8.2-7 10-4-1.8-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4.5"/></svg>
      </div>
      <h3>垃圾拦截审核</h3>
      <p>DeepSeek 逐篇给出保留 / 拒绝建议，被判定文章进入独立审核页：横滑、快捷键或右键菜单处理，最终决定由你做出。</p>
    </div>

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>
      </div>
      <h3>长文与媒体阅读</h3>
      <p>HTML 拆块渲染、目录跳转、表格、代码块与 Markdown 复制；图片画廊与失败重试，普通视频、YouTube、Bilibili 内联播放并自动回退官方播放器。</p>
    </div>

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/><path d="M3 17l9 5 9-5"/></svg>
      </div>
      <h3>订阅源管理</h3>
      <p>Articles / Social Media / Inbox 分组与静默订阅源，可撤销的添加 / 编辑 / 取消订阅，跨客户端同步的共享目录。</p>
    </div>

    <div class="feature-card">
      <div class="feature-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>
      </div>
      <h3>桌面体验与隐私</h3>
      <p>macOS 原生分栏、克制的 Liquid Glass、右键菜单与快捷键；凭据本地保存，配置可导出为 JSON 通过剪贴板迁移，同步、AI 与后台任务全程可见。</p>
    </div>

  </div>
</section>

</div>

<div class="landing">

<section class="landing-section" id="wiki-entry">
  <h2>工程 Wiki — 技术手册</h2>
  <p class="section-lead">
    这是一个“编辑 = 阅读”的单文件 HTML 知识库：每个专题页正文以 Markdown 内嵌在页面中，
    克隆仓库后双击本页即可离线浏览全部专题，无需安装任何依赖或启动服务。
  </p>
  <div class="entry-grid">

    <a class="entry-card" href="docs/agent_handoff/status/current.html">
      <div class="entry-title">状态 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">当前状态 · 待办与搁置 · 验证记录</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/architecture/overview.html">
      <div class="entry-title">架构 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">概览 · 数据同步 · 网络 · 存储与缓存</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/features/timeline.html">
      <div class="entry-title">功能 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">时间线 · 渲染 · 媒体 · 翻译 · 拦截 · 订阅</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/platforms/macos.html">
      <div class="entry-title">平台与设计 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">macOS · Android · Liquid Glass · UI 交互</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/operations/development.html">
      <div class="entry-title">开发与操作 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">开发 · 测试 · 排障 · worktree · 发布</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/history/decisions.html">
      <div class="entry-title">历史 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">决策日志 · 迁移 · 发布记录 · 主题归档</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/legal/third-party.html">
      <div class="entry-title">许可与致谢 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">第三方依赖 · 许可证声明</div>
    </a>
    <a class="entry-card" href="docs/agent_handoff/meta/site-guide.html">
      <div class="entry-title">站点指南 <span class="entry-arrow">→</span></div>
      <div class="entry-desc">如何编辑本 Wiki · 迁移映射</div>
    </a>

  </div>
</section>

</div>

## 推荐阅读顺序

1. [当前状态](status/current.html) — 最近的集成分支、产品形态与用户验证结论
2. [待办与搁置事项](status/pending.html) — 当前有效的未来事项索引
3. [验证记录](status/verification.html) — 仍需持续观察的开放验证项
4. [开发流程](operations/development.html) — 常用命令与检查方式
5. 当前任务对应的专题页
6. 需要历史证据时查[历史主题归档](history/archive/README.html)；按旧章节编号查找使用[历史时间索引](history/chronology.html)

## 硬性规则

- 除非用户明确要求，否则不要创建 tag 或发布 release；发布只允许从 `main` 分支通过 `scripts/release.sh` 进行。
- Flutter 项目健康检查优先使用 `dart analyze lib test`、`flutter analyze lib test` 和有针对性的 `flutter test`；完整 `dart analyze` 会扫描 `reference/` 并报告无关错误。
- 不要把密钥、API 响应、抓取的真实文章 HTML、临时脚本提交进 git。此类内容放进已忽略的 `scratch/`。
- 当前应用标识命名空间是 `io.github.xraygit.autofolo`；历史 `com.folo.*` / `com.autofolo` 引用已经废弃。
- macOS 发布产物必须保持 arm64。

## 维护规则

- 这个知识库只保留当前仍有用的知识；专题页继续变大时按子专题拆分，不要无限追加。
- 原始历史证据按主题保存在 `history/archive/`；提炼总结时不要删除归档。`history/timeline.html` 只用于兼容旧链接，不再追加内容。
- 记录决策时优先写入 `history/decisions.html`，包含背景、决策、后果和“不要回退”的说明。
- 更新文档后运行 `./scripts/docs.sh index` 重新生成搜索索引，并运行 `./scripts/docs.sh check` 验证链接与一致性。
