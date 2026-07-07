# 测试

主要命令：

```bash
dart analyze lib test
flutter analyze lib test
flutter test
flutter build macos --debug
```

预期注意点：

- Flutter 命令可能需要权限更新 Flutter SDK cache。
- 完整 `dart analyze` 会很吵，因为 `reference/` 包含外部复制来的参考工程。

当前测试：

- `test/article_content_utils_test.dart`
- `test/article_card_test.dart`
- `test/article_model_test.dart`
- `test/feed_model_test.dart`
- `test/html_entity_utils_test.dart`
- `test/implicitly_animated_list_test.dart`
- `test/widget_test.dart`

修改单个功能时，先运行相关窄测试；推送前再运行完整项目测试套件。
