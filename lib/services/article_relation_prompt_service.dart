import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/storage.dart';

abstract final class ArticleRelationPromptService {
  static const String storageKey = 'relation_prompt';

  static String getPrompt() {
    return GStorage.setting.get(storageKey, defaultValue: defaultPrompt)
        as String;
  }

  static Future<void> setPrompt(String prompt) async {
    await GStorage.setting.put(storageKey, prompt);
  }

  static void resetPrompt() {
    GStorage.setting.delete(storageKey);
  }

  static String get promptFingerprint =>
      sha256.convert(utf8.encode(getPrompt())).toString().substring(0, 12);

  static const String defaultPrompt = '''
你是文章信息关系分析器。输入包含本批新文章 new 与历史文章 history，每篇只有元信息和摘要。

请找出“信息内容高度重合、阅读其中任意一篇后其余文章基本不再提供明显新增信息”的稀疏关系组。判断只基于内容可替代性，与文章是否已读、用户兴趣或质量无关。即使组内文章当前都未读，只要信息高度可替代，也应建立关系。

不要为仅主题相近、同一人物、同一产品或同一领域的文章建立关系。不要处理日报、周报、链接合集、综合摘要、纯图片或有效摘要不足的文章；不确定时不建立关系。每个输出组必须至少包含一个 N 开头的新文章 ID。

只返回 JSON 对象，不要 Markdown、解释或代码块。结构必须是：
{"groups":[{"members":["N001","H003"],"reason":"简短说明重合的具体信息","confidence":0.0}]}

没有可靠关系时返回：{"groups":[]}
''';
}
