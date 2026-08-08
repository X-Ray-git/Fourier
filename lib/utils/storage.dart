import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

abstract final class GStorage {
  // 非 final：测试中每个用例在独立临时目录重新 init（关闭旧 box 后重开）。
  static late Box<dynamic> setting;
  static late Box<dynamic> localCache;
  static late Box<dynamic> readStatus;
  static late Box<dynamic> articleDb;
  static late Box<dynamic> translations;
  static late Box<dynamic> summaries;
  static late Box<dynamic> readHistory;
  static late Box<dynamic> analysisEvents;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter('${appDir.path}/hive');

    setting = await Hive.openBox('setting');
    localCache = await Hive.openBox('localCache');
    readStatus = await Hive.openBox(
      'readStatus',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 10,
    );
    articleDb = await Hive.openBox(
      'articleDb',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 50,
    );
    translations = await Hive.openBox(
      'translations',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 30,
    );
    summaries = await Hive.openBox(
      'summaries',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 30,
    );
    readHistory = await Hive.openBox(
      'readHistory',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 50,
    );
    // 本地分析事件账本：版本化、追加式，账号退出时随账号数据清理。
    analysisEvents = await Hive.openBox('analysisEvents');
  }

  static Future<void> close() async {
    await Future.wait([
      setting.close(),
      localCache.close(),
      readStatus.close(),
      articleDb.close(),
      translations.close(),
      summaries.close(),
      readHistory.close(),
      analysisEvents.close(),
    ]);
  }
}
