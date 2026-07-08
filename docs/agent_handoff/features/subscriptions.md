# 订阅源

订阅源数据支撑时间线过滤和展示。

当前行为：

- 订阅源会被缓存。
- 需要时，时间线会先加载 feed mapping，再加载文章。
- 订阅源/分类过滤应保持文章计数和 header 副标题准确。
- 静默订阅源设置会影响普通时间线计数和可见性。

相关服务：

- `FeedTranslationSettingsService`
- `FeedReadabilitySettingsService`
- `FeedSilentSettingsService`

UI 注意点：

- macOS 订阅源专属 header 可以显示自动翻译和自动全文开关。
- 清除选中订阅源时，适当情况下也应清除选中分类。
- macOS 订阅源/侧边栏相关按钮应避免遗留 Flutter 默认 tooltip。侧边栏折叠 rail、订阅源分类展开箭头、订阅源搜索清空按钮等入口应使用 `AppGlassTooltip` 或 `AppGlassIconButton`。
- 订阅源分类展开/折叠箭头仍保留原本紧凑尺寸和旋转动画，只把 tooltip 从默认系统样式迁移到玻璃样式；不要借 tooltip 迁移扩大行高或改变侧边栏信息密度。
