/*
 * Auto Folo Wiki — 导航清单（经典 JS 数据文件）
 * path 相对于 docs/agent_handoff/；首页使用 home:true（相对仓库根解析）。
 * 新增/重命名页面后必须同步更新本文件。
 */
window.WIKI_NAV = [
  {
    group: '首页',
    items: [{ title: 'Wiki 首页', path: 'index.html', home: true }],
  },
  {
    group: '状态',
    items: [
      { title: '当前状态', path: 'status/current.html' },
      { title: '待办与搁置', path: 'status/pending.html' },
      { title: '验证记录', path: 'status/verification.html' },
    ],
  },
  {
    group: '产品',
    items: [
      { title: '产品定位', path: 'product/overview.html' },
      { title: '设计原则', path: 'product/principles.html' },
      { title: '术语', path: 'product/terminology.html' },
      { title: '隐私', path: 'product/privacy.html' },
    ],
  },
  {
    group: '架构',
    items: [
      { title: '架构概览', path: 'architecture/overview.html' },
      { title: '数据同步与状态传播', path: 'architecture/sync-state.html' },
      { title: '网络', path: 'architecture/networking.html' },
      { title: '路由与状态', path: 'architecture/routing-state.html' },
      { title: '存储与缓存', path: 'architecture/storage-and-cache.html' },
    ],
  },
  {
    group: '功能',
    items: [
      { title: '时间线', path: 'features/timeline.html' },
      { title: '文章渲染', path: 'features/article-rendering.html' },
      { title: '媒体播放', path: 'features/media-playback.html' },
      { title: '翻译与摘要', path: 'features/translation-summary.html' },
      { title: '垃圾拦截与审核', path: 'features/filter-review.html' },
      { title: '订阅源', path: 'features/subscriptions.html' },
      { title: '撤销与重做', path: 'features/undo-redo.html' },
      { title: '快捷键与焦点', path: 'features/keyboard-shortcuts.html' },
      { title: '后台任务', path: 'features/background-tasks.html' },
      { title: '设置', path: 'features/settings.html' },
      { title: '性能', path: 'features/performance.html' },
    ],
  },
  {
    group: '平台',
    items: [
      { title: 'macOS 说明', path: 'platforms/macos.html' },
      { title: 'Android 说明', path: 'platforms/android.html' },
    ],
  },
  {
    group: '设计',
    items: [
      { title: 'Liquid Glass', path: 'design/liquid-glass.html' },
      { title: 'macOS UI', path: 'design/macos-ui.html' },
      { title: '交互模式', path: 'design/interaction-patterns.html' },
    ],
  },
  {
    group: '操作',
    items: [
      { title: '开发流程', path: 'operations/development.html' },
      { title: '测试', path: 'operations/testing.html' },
      { title: '故障排查', path: 'operations/troubleshooting.html' },
      { title: 'Git Worktree', path: 'operations/git-worktrees.html' },
      { title: '发布与构建', path: 'operations/release-build.html' },
    ],
  },
  {
    group: '历史',
    items: [
      { title: '决策日志', path: 'history/decisions.html' },
      { title: '迁移记录', path: 'history/migrations.html' },
      { title: '发布记录', path: 'history/releases.html' },
      { title: '历史时间索引', path: 'history/chronology.html' },
      { title: '历史主题地图', path: 'history/historical-map.html' },
      { title: '完整时间线（兼容入口）', path: 'history/timeline.html' },
      { title: '历史主题归档', path: 'history/archive/README.html' },
    ],
  },
  {
    group: '历史归档（原始证据）',
    items: [
      { title: '项目基础与产品演进', path: 'history/archive/foundation-and-product.html' },
      { title: '订阅源、缓存与同步', path: 'history/archive/subscriptions-and-sync.html' },
      { title: '翻译、摘要与 AI 过滤', path: 'history/archive/ai-translation-and-filtering.html' },
      { title: '文章内容与 HTML 渲染', path: 'history/archive/article-content-and-html.html' },
      { title: '图片、视频与媒体交互', path: 'history/archive/images-video-and-media.html' },
      { title: '性能、滚动与进度', path: 'history/archive/performance-and-scrolling.html' },
      { title: '时间线与导航', path: 'history/archive/timeline-and-navigation.html' },
      { title: '列表动画与撤销', path: 'history/archive/list-animation-and-undo.html' },
      { title: 'macOS 桌面框架与快捷键', path: 'history/archive/macos-shell-and-shortcuts.html' },
      { title: 'macOS Liquid Glass 重构', path: 'history/archive/macos-liquid-glass.html' },
      { title: '设置、身份与迁移', path: 'history/archive/settings-identity-and-migration.html' },
      { title: 'Android 专项历史', path: 'history/archive/android.html' },
      { title: '发布、Git、Worktree 与 CI', path: 'history/archive/release-git-and-ci.html' },
    ],
  },
  {
    group: '其他',
    items: [
      { title: '第三方依赖、许可与致谢', path: 'legal/third-party.html' },
      { title: '设计规范', path: 'meta/design-guide.html' },
      { title: '站点指南', path: 'meta/site-guide.html' },
      { title: '旧文档迁移映射', path: 'meta/migration-map.html' },
    ],
  },
];
