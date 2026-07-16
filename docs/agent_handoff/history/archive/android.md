# 历史归档：Android 专项历史

> 本页保存从旧 `history/timeline.md` 迁移来的原始历史证据。内容可能描述已经废弃的实现；当前事实以专题页和 `history/decisions.md` 为准。

<a id="legacy-082"></a>

## 82. Android 安装签名冲突与 v1.1.3 修复（2026-06-02）

### 82.1 用户遇到的问题

用户安装 `v1.1.2` Android APK 时，系统提示：

```text
应用未安装：软件包与现有软件包存在冲突
安装包的开发者签名有异常，建议清除同包名的数据或联系开发者
```

根本原因不是版本号不够高，而是 Android 覆盖安装要求：

- `applicationId` 相同：当前是 `com.folo.folo_reader`
- 签名证书也必须相同
- `versionCode` 更高只在“包名相同且签名相同”时才决定是否可升级

如果包名相同但签名不同，Android 会直接拒绝覆盖安装。这是安全机制，防止任意 APK 用相同包名和更高版本号接管旧应用数据。

### 82.2 为什么之前会签名不同

检查 `android/app/build.gradle.kts` 后发现，本项目之前的 release 构建实际使用了 debug 签名：

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

debug keystore 通常与构建环境相关：本机构建和 GitHub Actions runner 可能使用不同证书。换机器、删掉本地调试 keystore、换 runner，都可能导致签名不同。

因此用户本机 `flutter run` 安装的包和 GitHub Actions 构建的 release APK 可能同包名但签名不同，从而无法覆盖安装。

### 82.3 用户确认的修复策略

用户基本只自用，并确认目前只通过“本机”和“GitHub Actions”两种方式安装/打包过。经过讨论后，采用固定 Android 内部测试签名材料，并通过 GitHub Secrets 提供给 CI；签名材料、别名、口令、证书指纹等敏感细节不得写入仓库文档。

GitHub Actions 使用的 Secrets 项目名保留在 workflow 中；本文档只记录策略，不记录 secret 值、key 指纹或本机 keystore 路径。

注意：

- GitHub Secrets 不进入 Git 仓库，不会被 `git clone`、源码包、tag 或 Release 资产直接包含。
- 但 Actions 运行时可以使用这把 key 签 APK，因此它仍然是“把签名能力交给 GitHub Actions 环境”。
- 用户已明确同意将固定内部测试签名材料配置到 GitHub Secrets。

### 82.4 代码修复

修改文件：

1. `.gitignore`
   - 忽略 `android/key.properties`
   - 忽略 `android/app/*.jks`
   - 忽略 `android/app/*.keystore`

2. `android/app/build.gradle.kts`
   - 支持读取 `android/key.properties`
   - 如果存在固定 keystore 配置，release build 使用 `signingConfigs.release`
   - 如果本地没有 `android/key.properties`，仍 fallback 到 debug signing，保证普通本地开发命令可运行

3. `.github/workflows/internal-release.yml`
   - Android job 在 `flutter build apk --release` 前新增 `Configure Android signing`
   - 从 GitHub Secrets 还原 `android/app/upload-keystore.jks`
   - 生成 `android/key.properties`
   - 若任一 secret 缺失，CI 直接失败，避免再次发布不稳定签名 APK

### 82.5 本地验证

已在本机生成被 `.gitignore` 忽略的签名配置文件：

- `android/key.properties`
- `android/app/upload-keystore.jks`

本地验证命令：

```bash
dart analyze lib test
flutter build apk --release --no-pub
<android-sdk>/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

验证结果：

- `dart analyze lib test`：通过
- `flutter build apk --release --no-pub`：通过
- `apksigner verify --print-certs`：通过，并确认 APK 使用预期的固定内部测试签名证书。证书指纹不记录在仓库文档中。

### 82.6 v1.1.3 发布预期

版本计划：

- `pubspec.yaml`：`1.1.3+5`
- `X-App-Version`：`1.1.3`
- 设置页关于版本：`Auto Folo v1.1.3`
- tag：`v1.1.3`

安装预期：

- 如果手机当前安装包来自同一套固定内部测试签名，则 `v1.1.3` GitHub APK 应该可以直接覆盖安装。
- 如果手机当前安装包来自旧 GitHub Actions runner 的 debug key，则仍会签名冲突，需要卸载一次。
- 一旦成功安装 `v1.1.3`，之后 GitHub Actions 发布的 APK 只要继续使用这套 secrets，就应能正常覆盖升级。

### 82.7 v1.1.3 远端发布结果

- tag：`v1.1.3`
- 结果：`Android APK`、`macOS App`、`Publish GitHub Release` 全部通过。
- Release URL：`GitHub Release v1.1.3`
- Release assets：
  - `Auto-Folo-android-v1.1.3.apk`
    - 已下载到被 Git 忽略的临时目录并用 `apksigner verify --print-certs` 验证签名
    - 确认 APK 使用预期的固定内部测试签名证书；证书指纹不记录在仓库文档中
  - `Auto-Folo-macOS-arm64-v1.1.3.zip`

结论：`v1.1.3` GitHub Android APK 已确认使用固定内部测试签名。若用户手机上现有安装包来自同一签名，应可直接覆盖安装；若仍报签名冲突，说明手机上现有包来自另一把签名，需要卸载一次后再装。

<a id="legacy-083"></a>

## 83. Android 时间线灰屏修复与 v1.1.4 发布（2026-06-02）

> 2026-06-03 校准：本节记录的是第一次 Android 灰屏排查、缓存读取加固和 v1.1.4 发布过程；后续第 84 节进一步确认了“主时间线/垃圾拦截页灰屏”的真正根因是 GetX `Obx` 短路读取和卡片布局问题。诊断同类灰屏时，应以第 84 节为最终根因记录，同时保留本节作为发布与防御性修复历史。

### 83.1 用户反馈

用户成功安装 `v1.1.3` 后反馈：Android 端时间线主页面中间是一整片灰色，什么都看不见。用户进一步澄清：不是灰色占位卡片，而是彻底的一整片灰色。

本机环境没有连接 Android 设备或模拟器：

```bash
flutter devices
# 仅发现 macOS 和 Chrome
```

因此本轮无法直接截图复现 Android 页面，只能从 Flutter release 灰盒常见原因和时间线渲染路径排查。

### 83.2 排查结论

初始猜测是时间线停在骨架屏，但用户澄清不是占位卡片。因此排查转向 Flutter release 灰盒：

- Flutter debug 下 widget 异常常表现为红屏/错误文本。
- Flutter release 下某些 build/layout 异常可能表现为灰色错误块或整块灰色区域。

时间线卡片 `ArticleCard` 在 build/initState 阶段会读取：

- `TranslationService.hasTranslation`
- `TranslationService.recordOf`
- `TranslationService.displayTitleFor`
- 摘要块开启时的 `SummaryService.recordOf`

临时 widget test 复现出一个问题：如果本地 AI 缓存 box 尚未 hydration，`ArticleCard` 会因为 `GStorage.translations` 未初始化抛 `LateInitializationError`。真实 App 正常会先 `GStorage.init()`，但 release 中这类缓存读取不应能把整个时间线渲染链路打挂。

另一个独立风险来自 `FeedHttp.collectEntries()`：

- 它依赖 `publishedAfter = batch.last.publishedAt` 继续分页。
- 如果服务端重复返回同一页，或最后一篇时间戳不前进，就可能长时间停留在加载态。
- 这不会解释用户澄清后的“整片灰色”全部现象，但会造成主页面一直显示空表面/加载表面，因此一起修复。

### 83.3 修复内容

1. `lib/services/translation_service.dart`
   - `recordOf()` 对 `ensureHydrated()` 增加 try/catch。
   - 如果缓存 box 未就绪，记录调试日志后继续读取 `_records[entryId]`；这样既不会抛出 hydration 异常，也会保留 `Obx` 所需的 observable 读取。

2. `lib/services/summary_service.dart`
   - `recordOf()` 对 `ensureHydrated()` 增加 try/catch。
   - 如果缓存 box 未就绪，记录调试日志后继续读取 `_records[entryId]`；摘要块按 idle/未生成状态处理，不抛异常。

3. `lib/http/feed_http.dart`
   - `collectEntries()` 增加 `seenIds` 去重。
   - 如果某一页没有任何新 entryId，停止分页，避免重复页无限循环。
   - 如果下一页 cursor 为空或与上一页相同，停止分页。
   - 增加可选 `maxPages` 参数，保留未来调用方限制分页上限的能力。

4. `test/article_card_test.dart`
   - 新增 widget test：本地 AI cache 未 hydration 时，`ArticleCard` 必须能渲染且不抛异常。

### 83.4 版本策略

用户原话是“重新打包成 1.1.3”。但 `v1.1.3` 已经是已推送并成功发布的 tag，不应该移动或覆盖重打。为了避免历史混淆，本轮使用新 patch 版本：

- `pubspec.yaml`：`1.1.4+6`
- `X-App-Version`：`1.1.4`
- 设置页关于版本：`Auto Folo v1.1.4`
- tag：`v1.1.4`

Android 签名继续使用第 82 节配置的固定内部测试签名材料，因此应保持与 `v1.1.3` 可覆盖升级。

### 83.5 本地验证

本轮修复提交前已完成：

```bash
dart format lib/http/feed_http.dart lib/services/translation_service.dart lib/services/summary_service.dart lib/http/init.dart lib/pages/settings/settings_page.dart test/article_card_test.dart
git diff --check
dart analyze lib test
flutter test --no-pub
flutter build apk --release --no-pub
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

结果：

- `dart analyze lib test` 通过。
- `flutter test --no-pub` 通过，包含新增 `ArticleCard renders when local AI caches are not hydrated`。
- 本地 Android release APK 构建成功。
- 本地 Android release APK 构建成功，并确认使用预期的固定内部测试签名；证书指纹不写入仓库文档。

### 83.6 GitHub Actions 发布结果

提交：

- Commit：`e017bff447392ebdbff5ac40d18aada86a42edf3`
- Commit message：`fix(timeline): prevent Android release gray screen`
- Tag：`v1.1.4`

GitHub Actions：

- Run ID：已通过，具体 run id 不写入仓库文档
- Run URL：`GitHub Actions run`
- 结果：成功。
- Jobs：
  - `macOS App`：通过，用时约 `6m30s`；包含 `Verify arm64 runner`，因此本次 macOS 仍为 arm64 构建。
  - `Android APK`：通过，用时约 `9m50s`；`Configure Android signing`、`Build APK`、`Upload APK artifact` 均通过。
  - `Publish GitHub Release`：通过，用时约 `12s`。
- Release URL：`GitHub Release v1.1.4`
- 预期 release assets（由 workflow 产物命名规则生成）：
  - `Auto-Folo-android-v1.1.4.apk`
  - `Auto-Folo-macOS-arm64-v1.1.4.zip`

注意：本轮在 workflow 成功后，新的 `gh run view`/release 查询被 Codex 系统用量限制拒绝，因此没有继续下载 GitHub release asset 做远端 hash 和远端 APK 签名复验。可确认的信息来自已完成的 workflow 监控输出和本地 release APK 签名验证。

<a id="legacy-084"></a>

## 84. 安卓端主时间线及垃圾拦截页灰屏彻底修复 (2026-06-02)

### 84.1 问题复盘
用户反馈：在安卓端，只要有文章被 AI 拦截（左上角/顶部出现数字），主时间线中间就会变成一片灰色，什么都看不见；点击进入垃圾拦截页面，里面同样是一片灰色。但从具体的订阅源点进去则显示正常。
此外，用户提出被拦截的文章“应该在主时间线显示，按本身日期排序，同时在拦截页面按审核完成时间排序”。

### 84.2 根本原因分析
排查后发现，灰屏是由两个独立但相互叠加的错误造成的：

1. **GetX `Obx` 的短路求值引发的运行时崩溃（导致灰屏的元凶）**
   在 `timeline_page.dart` 和 `filter_review_page.dart` 中，为了判断文章卡片在 macOS 端是否被选中，代码写成了：
   `isSelected: Platform.isMacOS && controller.selectedArticle.value?.entryId == article.entryId`
   在安卓端，由于 `Platform.isMacOS` 为 `false`，Dart 的短路求值特性导致后半段的响应式变量 `controller.selectedArticle.value` 从未被读取。
   GetX 的安全机制强制要求在 `Obx` 闭包内至少读取一次 Observable，否则会直接在 `build` 阶段抛出 `the improper use of a GetX has been detected` 异常。在 Release 模式下，这个异常导致整个列表的卡片渲染失败，呈现为大面积灰屏。

2. **卡片内 `Row` 与 `Flexible` 的布局约束死锁（潜在的 Debug 崩溃）**
   在 `ArticleCard` 渲染 AI 拒文理由时，原代码使用了一个 `mainAxisSize: MainAxisSize.min` 的 `Row`，里面嵌套了一个 `Flexible` 组件。
   在 Flutter 中，试图让父组件紧缩（min）的同时让子组件扩展（flex）会触发严格的布局约束冲突断言。虽然在 Release 模式下这个 `assert` 会被跳过从而不会引发灰屏，但如果在 Debug 模式下运行，必定会触发红屏报错（Red Screen of Death）。

### 84.3 修复方案与讨论过程
1. **彻底修复 `ArticleCard` 布局冲突**：
   移除了带有 `Flexible` 的 `Row`，改为使用原生且安全的 `Text.rich` 搭配 `WidgetSpan` 来渲染图文混排的拦截理由。这不仅彻底排除了 Debug 模式下的“红屏炸弹”，也提升了长文本截断的可靠性。
2. **修复 GetX `Obx` 崩溃逻辑**：
   在 `timeline_page.dart` 和 `filter_review_page.dart` 中的 `Obx` 闭包内，提前将 `selectedArticle.value?.entryId` 赋值给一个局部变量，强制其在所有平台上都被读取一次。这样既绕过了短路求值的陷阱，又保证了状态的正确注册。
3. **澄清并恢复时间线的过滤逻辑**：
   由于我最初误解了用户“新分析完的文章应该在垃圾拦截页面”的需求，曾一度在 `timeline_controller.dart` 中把被拦截文章从主时间线剔除了。用户澄清后确认：**被拦截的文章既要留在主时间线（按发布时间排序），也要出现在审核页面（按审核完成时间排序）**。这正符合旧有代码的双线并行排序逻辑，因此我立即撤销了那段错误剔除代码，恢复了原有设定。

经过这些修改，安卓端的灰屏现象彻底消失，应用恢复正常运行与逻辑流转。
