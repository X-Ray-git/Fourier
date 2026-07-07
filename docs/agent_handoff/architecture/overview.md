# 架构概览

核心技术栈：

- Flutter 3.x / Dart 3.11+
- GetX 负责路由与响应式状态
- Hive 负责本地存储
- Dio 负责 Folo 和 DeepSeek HTTP 调用
- `cached_network_image`、`video_player`、`share_plus`、`image_gallery_saver_plus` 和平台插件

重要入口：

- 应用启动：`lib/main.dart`
- 路由：`lib/router/app_pages.dart`
- 主框架：`lib/pages/main/main_page.dart`
- 时间线：`lib/pages/timeline/`
- 文章详情：`lib/pages/article/`
- 设置：`lib/pages/settings/`

高层流程：

- Folo 凭据保存在 Hive settings 中。
- 时间线先加载订阅源，再加载 entries，然后合并本地已读/过滤状态。
- 文章详情会规范化 HTML、解析 chunk，并通过 chunk widget 渲染。
- 翻译与摘要服务把记录存入 Hive，并暴露响应式 map。

实现偏好：

- 除非任务明确要求更大重构，否则遵循现有 GetX/Hive 模式。
- macOS 专属 UI 行为要用平台判断保护。
- 修改 macOS 视觉时保持 Android 行为稳定。
