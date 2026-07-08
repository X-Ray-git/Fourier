# 设置

设置页有 macOS 和移动端布局。

重要设置：

- Folo 凭据：session token、client id、session id。
- DeepSeek API key。
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
- macOS 设置页 segmented 与时间线 `未读/全部` switch 共用同一类紧凑玻璃语言：外层轨道低存在感、选中滑块使用中性 `AppGlassSurface` control 材质、只保留极弱主色 tint 和主色文字。不要把设置页 segmented 重新改成明显橙色块或旧式普通分段控件。
- macOS 自定义下拉菜单使用 `_MacGlassSelectField`。下拉 overlay 不能完全透明：菜单面板需要局部静态底色遮住背后内容，且底色圆角必须和外框圆角对齐。
- 下拉 overlay 的可读性修复是局部处理，不应通过全局提高 `AppGlassSurface` 不透明度解决，否则会影响其他已经验证过的玻璃控件。

已知产品张力：

- 有些设置立即保存，有些仍依赖保存按钮。这是可接受的阶段性状态，不是硬 bug，但未来应统一保存模型。
- “保存设置”和各子项旁“保存/重置默认”的功能划分长期需要更清晰。
