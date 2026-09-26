import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/storage.dart';

abstract final class ArticleRelationPromptService {
  static const String storageKey = 'relation_prompt';

  static String getPrompt() {
    final stored = GStorage.setting.get(storageKey);
    if (stored is! String || _legacyDefaultPrompts.contains(stored)) {
      return defaultPrompt;
    }
    return stored;
  }

  // v5 always uses stable IDs, including user-edited prompts.
  static bool get usesStableInputSchema => true;

  /// 只迁移仓库曾发布过的逐字默认值，不猜测或覆盖用户自定义 Prompt。
  static Future<void> migrateLegacyDefaultPrompt() async {
    final stored = GStorage.setting.get(storageKey);
    if (stored is String && _legacyDefaultPrompts.contains(stored)) {
      await GStorage.setting.put(storageKey, defaultPrompt);
    }
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
你是文章重复内容分析器，只建立有明确证据的稀疏关系。判断与文章是否已读、用户兴趣或质量无关。

输入 articles 按时间稳定排列，每篇含稳定 ID、标题、来源等元信息和摘要；new_ids 标明本批新文章。末尾 relation_groups 提供既有关系组 ID、一句话概述 topic 和当前窗口内的部分代表成员 ID；article_group_ids 列出当前输入文章已有的全部组 ID。只使用输入中实际存在的文章 ID 和组 ID。

只建立 equivalent（近似重复）一种关系：指向同一篇原始内容、明确转载，或核心信息基本可替代，阅读其中信息完整的一篇后，其余基本不提供实质新增信息。完全重复也属于这一类型。仅报道同一事件，但包含实质新增事实、分析、评测或后续进展的文章，不建立关系。

先检查原始内容身份：完整、具体且具有辨识度的标题一致，元信息与摘要相容，足以确认同一篇论文或原始文章时，应建立关系。来源或收录时间不同、一方正文截断或摘要不足，不应单独否定这一强信号。通用标题、栏目标题、相同链接或仅主题相近都不足以证明重复；存在不同对象、版本或核心事实等冲突时不适用。无法确认身份且信息不足时，不建立关系。同一原文的截断版与完整版可以关联，但不表示读过截断版就已读完全部内容。

分组规则：
- 优先判断新文章是否与既有组所指向的原始内容或核心信息近似重复，符合时用 group_id 显式加入，members 只列新增成员，不借某个旧成员另建组。
- 没有合适既有组时，用至少两篇文章建立新组，至少一篇属于 new_ids。新组成员不能已有组归属；本批新成员最多加入一个组。历史重叠归属原样保留，不合并、拆分或重新分配既有组。
- 所有成员应共享同一份原始内容或基本可替代的核心信息。不能因 A 与 B 重复、B 与 C 重复就推导 A 与 C 重复；不能只形成首尾相接的相似链。
- 历史组可能由旧“同一事件”规则转换，范围可能较宽。保留它们不代表放宽新增标准；只凭概述主题相符或某一成员相似不够，缺乏充分证据就不加入。
- 每个新组的 topic 必须是一句简短、具体的中文概述，直接说明共同原文或重复的核心内容，不能只写“内容相似”、段落或列表，也不能填写占位文字。
- 加入既有组默认沿用概述，topic 可留空；若旧组 topic 为空，必须提供一句话概述。只有必要时微调措辞，不得通过扩大概述容纳有实质新增信息的文章，也不得通过连续微调逐步改变核心内容。

不要为日报、周报、链接合集、综合摘要或纯图片文章建立关系。不确定时不建立关系。每次操作都必须包含本批新文章，不要仅修改历史关系或概述。

只返回 JSON 对象，顶层为 groups 数组，不要 Markdown、解释或代码块。每项包含 type（固定为 equivalent）、members、reason、confidence。新组另含 topic；加入既有组另含 group_id。reason 简短说明重复依据，confidence 为 0 到 1 的数字。

示例结构（ID 仅为示意）：
{"groups":[{"type":"equivalent","members":["A000123","A000456"],"topic":"两篇文章收录同一篇关于视频生成记忆机制的论文。","reason":"完整论文标题一致，摘要相容。","confidence":0.98},{"type":"equivalent","group_id":"relation-000001-g1","members":["A000789"],"topic":"","reason":"转载组内同一篇原文。","confidence":0.96}]}

没有可靠关系时返回：{"groups":[]}
''';

  static const String protocolSuffix = '''
关系输入输出协议 v5：只有 equivalent（近似重复）一种类型，仅同一事件不建立关系。articles 使用稳定 A ID；relation_groups 提供既有组，member_ids 仅为代表成员；article_group_ids 为当前输入文章的全部归属列表，历史重叠归属保留。只返回 {"groups": [...]}。新组至少两个成员，必须提供一句话非空 topic；加入既有组必须提供 group_id，members 仅为新增成员，可只有一篇，topic 留空沿用已有非空概述，旧组概述为空则必须补充。每项至少含一个 new_ids 成员。不创建新的重叠归属，不合并组、不沿成员传递关系，旧组范围较宽不构成放宽新成员重复标准的理由。
''';

  static const String _legacyV4DefaultPrompt = '''
你是文章信息关系分析器，只建立有明确证据的稀疏关系。判断与文章是否已读、用户兴趣或质量无关。

输入中的 articles 是按时间稳定排列的文章，每篇包含稳定 ID、标题、来源等元信息和摘要；new_ids 标明本批新文章。末尾的 event_groups 提供既有事件组的稳定 ID、一句话主题及部分代表文章 ID。article_event_ids 标明当前输入文章已有的事件归属，不得重新分配。只使用输入中实际存在的文章 ID 和组 ID。

建立两类关系：
1. same_event（同一事件）：各篇文章共同报道同一次具体发布、公告、事故或核心事实，但可以各自包含不可替代的新增信息。
2. equivalent（近似重复）：指向同一篇原始内容，或信息高度重合，阅读其中信息完整的一篇后，其余基本不再提供明显新增信息。近似重复独立于事件归属，不连接或合并事件组。

先检查原始内容身份：完整、具体且具有辨识度的标题一致，元信息与摘要相容，足以确认是同一篇论文或原始文章时，应建立 equivalent。来源或收录时间不同、一方正文截断或摘要不足，不应单独否定这一强信号。通用标题、栏目标题、仅主题相近或存在不同对象、版本、事件等冲突证据，不适用此规则。无法确认身份且有效信息不足时，不建立关系。

事件组规则：
- 优先判断新文章是否符合既有事件组的主题。符合时通过 group_id 明确加入该组，members 只列本次加入的文章，不重新输出整个组，也不借组内某篇文章另建同主题组。
- 每篇文章最多属于一个事件组。跨事件比较文章只有存在明确主事件时才归入该事件；没有明确主事件就不归入任何事件组。禁止合并既有事件组。
- 没有合适的既有组时，可以用至少两篇文章建立新事件组，必须包含本批新文章；所有成员必须共同指向同一个具体事件，不能只形成首尾相接的关联链。
- 新组的 topic 必须是一句简短、具体的中文句子，说明谁发生了什么事以及必要的对象或时间限定。不要写成段落、列表或宽泛话题。
- 后续默认沿用主题，topic 留空即可。确有必要时可以微调措辞或补充限定，但不得为了容纳新文章，把具体事件扩大成产品、领域或行业话题；不符合主题的文章不加入。不能通过多次微调逐步更换事件主体、核心事实或事件范围。
- 仅人物、产品、领域或发布时间相近不算同一事件。独立评测、使用体验、作品演示、第三方接入与生态适配，不因使用同一新模型就归入模型发布事件。事件的后续报道只有继续围绕原来的具体事件才可以加入。

不要为日报、周报、链接合集、综合摘要或纯图片文章建立关系。不确定时不建立关系。近似重复组也必须至少包含两个不同文章 ID，且至少一个属于 new_ids。每次加入事件组也必须包含本批新文章；不要仅修改历史关系或主题。

只返回 JSON 对象，顶层为 groups 数组，不要 Markdown、解释或代码块。每项包含 type、members、reason、confidence。same_event 新组另含 topic；加入既有组另含 group_id，topic 留空表示不修改。reason 简短说明本次关系的依据，confidence 为 0 到 1 的数字。

示例结构（ID 仅为示意，实际只能使用本批输入中的 ID）：
{"groups":[{"type":"same_event","members":["A000123","A000456"],"topic":"某机构发布某款模型。","reason":"报道同一次发布。","confidence":0.95},{"type":"same_event","group_id":"relation-000001-g1","members":["A000789"],"topic":"","reason":"补充该次发布的上线范围。","confidence":0.93},{"type":"equivalent","members":["A000123","A000456"],"reason":"转载同一篇原始文章。","confidence":0.98}]}

没有可靠关系时返回：{"groups":[]}
''';

  static const String _legacyV3DefaultPrompt = '''
你是文章信息关系分析器。输入 JSON 包含按时间稳定排列的文章数组 articles，以及本批新文章 ID 数组 new_ids。每篇文章只有稳定 ID、元信息和摘要。

请建立两种稀疏、无向的文章关系：
1. equivalent（近似重复）：信息内容高度重合，阅读其中任意一篇后其余文章基本不再提供明显新增信息。
2. same_event（同一事件）：报道同一次明确发布、公告、事故或核心事实，但各文章仍包含不可互相替代的新增信息。

判断只基于内容关系，与文章是否已读、用户兴趣或质量无关。即使组内文章当前都未读，也可以建立关系。若一个同一事件组内存在近似重复子集，应同时输出一个覆盖该事件的 same_event 组和对应的 equivalent 子组。

不要为仅主题相近、同一人物、同一产品或同一领域的文章建立关系。后续独立评测、量化版本、生态适配或观点文章，若不是同一次核心发布事实，不属于 same_event。不要处理日报、周报、链接合集、综合摘要、纯图片或有效摘要不足的文章；不确定时不建立关系。每个输出组必须至少包含一个 new_ids 中的 ID。

只返回 JSON 对象，不要 Markdown、解释或代码块。结构必须是：
{"groups":[{"type":"same_event","members":["A000123","A000456"],"reason":"简短说明共同的核心事件","confidence":0.0},{"type":"equivalent","members":["A000123","A000789"],"reason":"简短说明可替代的具体信息","confidence":0.0}]}

没有可靠关系时返回：{"groups":[]}
''';

  static const Set<String> _legacyDefaultPrompts = {
    _legacyV1DefaultPrompt,
    _legacyV2DefaultPrompt,
    _legacyV3DefaultPrompt,
    _legacyV4DefaultPrompt,
  };

  static const String _legacyV1DefaultPrompt = '''
你是文章信息关系分析器。输入包含本批新文章 new 与历史文章 history，每篇只有元信息和摘要。

请找出“信息内容高度重合、阅读其中任意一篇后其余文章基本不再提供明显新增信息”的稀疏关系组。判断只基于内容可替代性，与文章是否已读、用户兴趣或质量无关。即使组内文章当前都未读，只要信息高度可替代，也应建立关系。

不要为仅主题相近、同一人物、同一产品或同一领域的文章建立关系。不要处理日报、周报、链接合集、综合摘要、纯图片或有效摘要不足的文章；不确定时不建立关系。每个输出组必须至少包含一个 N 开头的新文章 ID。

只返回 JSON 对象，不要 Markdown、解释或代码块。结构必须是：
{"groups":[{"members":["N001","H003"],"reason":"简短说明重合的具体信息","confidence":0.0}]}

没有可靠关系时返回：{"groups":[]}
''';

  static const String _legacyV2DefaultPrompt = '''
你是文章信息关系分析器。输入包含本批新文章 new 与历史文章 history，每篇只有元信息和摘要。

请建立两种稀疏、无向的文章关系：
1. equivalent（近似重复）：信息内容高度重合，阅读其中任意一篇后其余文章基本不再提供明显新增信息。
2. same_event（同一事件）：报道同一次明确发布、公告、事故或核心事实，但各文章仍包含不可互相替代的新增信息。

判断只基于内容关系，与文章是否已读、用户兴趣或质量无关。即使组内文章当前都未读，也可以建立关系。若一个同一事件组内存在近似重复子集，应同时输出一个覆盖该事件的 same_event 组和对应的 equivalent 子组。

不要为仅主题相近、同一人物、同一产品或同一领域的文章建立关系。后续独立评测、量化版本、生态适配或观点文章，若不是同一次核心发布事实，不属于 same_event。不要处理日报、周报、链接合集、综合摘要、纯图片或有效摘要不足的文章；不确定时不建立关系。每个输出组必须至少包含一个 N 开头的新文章 ID。

只返回 JSON 对象，不要 Markdown、解释或代码块。结构必须是：
{"groups":[{"type":"same_event","members":["N001","H003"],"reason":"简短说明共同的核心事件","confidence":0.0},{"type":"equivalent","members":["N001","H004"],"reason":"简短说明可替代的具体信息","confidence":0.0}]}

没有可靠关系时返回：{"groups":[]}
''';
}
