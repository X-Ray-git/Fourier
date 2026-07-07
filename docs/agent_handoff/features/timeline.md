# 时间线

相关文件：

- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/widgets/article_card.dart`

当前行为：

- 模式：未读、全部、已读。
- macOS 中间 header 快速切换只暴露未读/全部。
- 已读模式/页面仍在其他入口存在，不应删除。
- 过滤支持选中订阅源、分类和静默订阅源。
- 本地文章库支撑时间线状态。
- 已读/未读变化会更新本地状态并通知其他视图。
- 垃圾拦截/审核这类列表如果语义要求稳定追加，新文章应稳定附加。

排序：

- `TimelineSortMode.newest`：默认，最新优先。
- `TimelineSortMode.longest`：估算长文优先。
- `TimelineSortMode.shortest`：估算短文优先。
- 排序只作用于当前本地/已加载文章集合，不是远端全历史。
- 长度估算使用 `ArticleLengthEstimator`、规范化 HTML、解析后的 chunk 和缓存签名。
- 排序刻意保持本地化。UI 文案不能让用户误以为是远端/全历史排序。

性能决策：

- macOS 切换未读/全部时，列表按 selected mode 设置 key，避免几千个 AnimatedList 项逐个动画。
- 普通标记已读时，单项移除动画仍保留。
- 首次长文/短文排序可能需要一次估算；用户验证时未观察到不可接受的成本。
- 避免批量重排或模式切换触发大型列表动画；这曾经让文章 loading spinner 等无关动画也卡住。

状态与交互：

- 卡片右键菜单操作如果影响当前选中文章，必须立即刷新可见详情状态。
- backing service 记录被删除后，不要回退到过期 controller 字段。
- 即使同步在按钮订阅 controller 前已经开始，同步按钮也必须开始旋转。
- macOS 刷新/排序/操作按钮在用户明确要求时，应对齐文章卡片边界。
- macOS 中间时间线处于具体订阅源筛选时，header 只保留时间线级操作，例如排序和同步。
- 不要在该 header 重复放置订阅源级设置按钮，例如自动拉取全文、自动翻译、静默等；这些入口属于左侧侧边栏订阅源项。
- 该 header 也不显示“清除筛选”。用户通过左侧侧边栏切换范围或回到全部文章。
- 这个取舍来自一次拥挤问题：进入某个分类下的具体订阅源后，刷新、清除筛选、拉取全文、自动翻译等按钮挤在同一行，视觉负担过重且功能重复。

当前文章保持可见：

- macOS 上切换文章时，如果目标卡片已经构建，继续使用 `ScrollUtils.ensureVisible` 做短距离校正。
- 如果目标卡片因为列表虚拟化尚未构建，先根据当前已构建卡片和估算 item 高度 `jumpTo` 到附近，再做短距离 `ensureVisible` 校正。
- 不要用长距离 `animateTo` 粗定位；它会和右侧文章切换同时竞争 UI isolate，用户曾观察到明显掉帧。
