import 'dart:io';

import 'package:hive/hive.dart';

/// 检查 articleDb 中文章的动作标记（userAction）是否按预期落库。
///
/// 用法：
///   dart run tool/inspect_user_actions.dart [hive目录]
///
/// 默认读取 macOS 沙盒目录
///   ~/Library/Containers/io.github.xraygit.fourier/Data/Documents/hive
///
/// 会把 articledb.hive 复制到临时目录后只读检查，应用运行中也可使用；
/// 复制瞬间之后的最新一条写入可能尚未反映到快照，如需精确结果请稍后再跑一次。
Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '';
  final path = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/io.github.xraygit.fourier'
            '/Data/Documents/hive';

  final sourceFile = File('$path/articledb.hive');
  if (!sourceFile.existsSync()) {
    stderr.writeln('Hive 文件不存在: ${sourceFile.path}');
    exit(1);
  }

  final tmpDir = Directory.systemTemp.createTempSync('fourier_inspect');
  try {
    sourceFile.copySync('${tmpDir.path}/articledb.hive');
    Hive.init(tmpDir.path);
    final box = await Hive.openBox<dynamic>('articleDb');

    final articles = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is Map) {
        articles.add(Map<String, dynamic>.from(value));
      }
    }

    final marked = articles
        .where((a) => a['userAction'] != null)
        .toList(growable: false);
    final flagged = articles
        .where((a) => a['isRejectedByAi'] == true)
        .toList(growable: false);

    print('文章总数: ${articles.length}');
    print('带 userAction 标记: ${marked.length}');
    print('isRejectedByAi=true: ${flagged.length}');
    print('');

    if (marked.isEmpty) {
      print('未发现任何动作标记。');
    } else {
      final counts = <String, int>{};
      for (final a in marked) {
        final action = a['userAction'] as String;
        counts[action] = (counts[action] ?? 0) + 1;
      }
      const labels = <String, String>{
        'k': '保留',
        'm': '确认拒绝',
        'n_keep': '误分类-保留+已读',
        'n_spam': '误分类-拒绝+已读',
      };
      for (final entry in counts.entries) {
        print(
          '  ${entry.key.padRight(6)} (${labels[entry.key] ?? '未知'})'
          ': ${entry.value}',
        );
      }
      print('');

      marked.sort((a, b) {
        final tA = (a['filteredAt'] as int?) ?? 0;
        final tB = (b['filteredAt'] as int?) ?? 0;
        return tB.compareTo(tA);
      });

      for (final a in marked) {
        final action = a['userAction'] as String;
        final rejected = a['isRejectedByAi'] == true;
        final isRead = a['isRead'] == true;
        final reviewed = a['filterReviewed'] == true;
        final reason = (a['filterReason'] as String?) ?? '';
        final title = (a['title'] as String?) ?? '?';
        final entryId = (a['entryId'] as String?) ?? '?';
        final shortId = entryId.length > 12
            ? '${entryId.substring(0, 4)}…${entryId.substring(entryId.length - 8)}'
            : entryId;
        print(
          '[${action.padRight(6)}] 拒绝=${rejected ? 'Y' : 'N'}'
          ' 已读=${isRead ? 'Y' : 'N'} 已审=${reviewed ? 'Y' : 'N'}'
          '${reason.isNotEmpty ? ' 理由="$reason"' : ''}'
          '  $title ($shortId)',
        );
      }
    }

    await box.close();
  } finally {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
