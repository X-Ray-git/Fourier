# 路由与状态

路由：

- 路由定义位于 `lib/router/app_pages.dart`。
- 主路由通过 `MainController` 承载类似 tab 的各个区域。

状态：

- GetX 响应式值（`Rx`、`Obx`）是主要模式。
- Service 经常暴露静态方法，并在内部维护响应式 map。
- `ArticleStateNotifier` 用于跨页面刷新文章状态。

重要体验规则：

- 当 service 记录被删除时，避免继续回退到过期 controller 缓存。近期 bug：从卡片右键菜单删除摘要后，`SummaryService` 记录已删除，但文章详情仍显示缓存的 `controller.summaryText`。修复后的行为是：可见摘要状态应信任 service 记录。
