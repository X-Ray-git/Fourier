# 订阅源

订阅源数据支撑时间线过滤和展示。

当前行为：

- 订阅源会被缓存。
- 需要时，时间线会先加载 feed mapping，再加载文章。
- 订阅源/分类过滤应保持文章计数和 header 副标题准确。
- 静默订阅源设置会影响普通时间线计数和可见性。
- macOS 侧边栏里，静默订阅源属于订阅源体系，不是主导航入口。普通订阅源树会排除静默源，静默源作为 `订阅源` section 滚动内容末尾的特殊分组展示，避免重复。
- Folo 官方来源类型展示名按英文保留：`Articles`、`Social Media`、`Inbox`。不要再把 `social` 显示成“社交”，也不要使用 `Social Inbox Feed` 这类官方不存在的组合名。

相关服务：

- `FeedTranslationSettingsService`
- `FeedReadabilitySettingsService`
- `FeedSilentSettingsService`

UI 注意点：

- macOS 订阅源专属 header 可以显示自动翻译和自动全文开关。
- `FeedDetailPage` 仍是有效入口：订阅源页中点击某个 view/category 的“全部”会进入它。不要把该页面当作废弃代码删除。
- macOS `FeedDetailPage` header 的阅读状态筛选必须和主时间线保持一致：只暴露紧凑二态 `未读/全部` switch，不再显示旧的 `仅未读/全部/仅已读` 三项 PopupMenu。
- 移动端 `FeedDetailPage` AppBar 目前仍保留三项菜单，这是移动端路径的既有行为；本轮只统一 macOS。
- 清除选中订阅源时，适当情况下也应清除选中分类。
- macOS 订阅源/侧边栏相关按钮应避免遗留 Flutter 默认 tooltip。订阅源分类展开箭头、订阅源搜索清空按钮等入口应使用 `AppGlassTooltip` 或 `AppGlassIconButton`。
- 订阅源分类展开/折叠箭头仍保留原本紧凑尺寸和旋转动画，只把 tooltip 从默认系统样式迁移到玻璃样式；不要借 tooltip 迁移扩大行高或改变侧边栏信息密度。
