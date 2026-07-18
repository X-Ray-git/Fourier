# 设置

设置页有 macOS 和移动端布局。

重要设置：

- 服务认证：Folo Session Token，以及 DeepSeek API Key。
- LLM 模型/配置值。
- Prompt 模板。
- 已读同步窗口。
- 角标策略。
- 文章内容最大宽度。
- macOS max fling velocity。
- 外观模式：`system`、`light`、`dark`。
- 任何会改变持久用户偏好的设置，都应考虑是否加入备份导出。

导入/导出：

- 使用剪贴板 JSON。
- 由 `SettingsBackupService` 白名单管理。
- 如果新增持久设置需要跨设备迁移，应加入导出/导入。
- 导出内容可能包含敏感值；UI 应提醒用户。

macOS UI：

- 设置/任务中心已经从重型玻璃面板转向轻量描边面板，以改善性能/可读性。
- Scrollbar 不应和内容重叠，也不应出现重复条。
- 设置顶部 chrome 已简化：不再保留大块冗余标题/说明/版本号区域。
- 设置底部/右侧 padding 应尽量保持和 macOS frame/侧边栏一致的边缘节奏。
- Segmented 控件应使用当前 hover/cursor 行为，中性控件避免橙色 hover。
- macOS 设置页 segmented 保留自身极弱主色 tint 和主色文字。时间线 `未读/全部` 已迁移为圆形 morph 选择按钮，不再和设置 segmented 共用 switch 视觉参数；不要为了机械统一把 header 选择器重新改回 segmented/switch。
- macOS 自定义下拉菜单使用 `_MacGlassSelectField`。下拉 overlay 不能完全透明：菜单面板需要局部静态底色遮住背后内容，且底色圆角必须和外框圆角对齐。
- 下拉 overlay 的可读性修复是局部处理，不应通过全局提高 `AppGlassSurface` 不透明度解决，否则会影响其他已经验证过的玻璃控件。
- 三选一的外观 segmented 高度和普通下拉/文本输入结构不同，应在“阅读与后台偏好”中独占完整一行；不要为了机械配对压缩其已验证的动画和玻璃规格。其余普通设置再进入响应式两列网格，窄窗口回落为单列。
- macOS 的 Folo 与 DeepSeek 凭据位于同一个“服务认证”容器，底部右侧共用紧凑的“测试连接 + 保存认证”按钮行；Prompt 保存/重置仍位于各自容器底部右侧。不要把保存按钮挤在输入框右侧或横向撑满卡片。

Android UI：

- Android 设置页使用独立的移动端分组布局，但继续复用相同保存语义与业务组件。页面水平边距为 `12px`，大面板使用 `MobileSettingsPanel` 的 `24px` 连续圆角和轻量静态材质；不要把 macOS 双栏设置布局压缩后直接搬到手机。
- 离散选择统一使用 `MobileSettingsSelectField<T>`。字段本身不裁剪 `InputDecorator` 的浮动标签；点击后打开 `AppMobileGlassSheet`，选中项显示勾选，选择后立即关闭并保存。不要恢复透明的 Material dropdown overlay。
- 移动端服务认证、LLM 自动提交数字输入和 Prompt 行为仍与 macOS 共享语义。正文最大宽度、macOS fling 上限等桌面专属项不得出现在 Android 设置页。
- 后台任务中心是独立二级页面，入口位于设置页。该页面有实时队列和失败记录导航，保持独立路由比把全部状态展开在设置列表中更清晰。

保存语义：

- 选择型控件应选择即保存，包括 dropdown、segmented、switch/checkbox 等。
- 单值数字输入不应边输边写盘；按 Enter 或失去焦点时校验并静默保存，无效值或写入失败应提示并恢复上一次有效值。
- 凭据、API Key 和 Prompt 等敏感、组合或大段文本输入保留明确保存按钮。
- Folo Session Token 与 DeepSeek API Key 共用一次保存操作：先完成所有格式校验，再写入本地；Folo Token 必填，DeepSeek Key 可以留空，留空保存表示清除已有 Key。
- 旧设置备份中的 `client_id`、`session_id` 继续允许导入但会被忽略并清理，保证旧 JSON 可迁移；新导出不再包含这两个字段。
- “测试连接”读取输入框当前值但不保存：Folo 使用只读 `/subscriptions` 并校验业务 `code == 0`；DeepSeek 使用需 Bearer 认证的只读 `/models`，不发起推理、不产生推理 token。两项独立测试并分别反馈，单项失败不能阻止另一项完成；DeepSeek Key 留空时显示“未配置，已跳过”，不把可选配置计为失败。
- LLM 参数卡片中，模型、思考模式、思考强度和 `max_tokens` 选择后立即保存；Temperature 和并发数按 Enter/失焦保存，编辑中的草稿不得阻塞或污染其他选项。重置默认立即落盘。
- Prompt 保留卡片内保存/重置操作；不要重新引入设置页全局“保存全部”按钮。
- macOS 与移动端的无按钮数字输入复用 `_AutoSavedSettingsTextField`；两端服务认证共用 `_CredentialActions`，避免按钮语义、加载态和提交时机分叉。
- 自动保存写入必须串行，并以最后一次用户选择为准；正常选择不弹成功提示，失败时恢复上一次持久值并提示。单行文本按 Enter 与点击保存等价。
