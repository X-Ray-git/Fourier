import '../common/constants/constants.dart';
import '../utils/article_content_utils.dart';
import '../utils/article_length_estimator.dart';
import '../utils/storage.dart';
import 'account_session_guard.dart';
import 'analysis_event_ledger.dart';
import 'article_image_cache_service.dart';
import 'article_relation_service.dart';
import 'article_relation_worker.dart';
import 'article_state_notifier.dart';
import 'auto_filter_worker.dart';
import 'auto_readability_worker.dart';
import 'auto_summary_worker.dart';
import 'auto_translation_worker.dart';
import 'local_article_db_service.dart';
import 'read_sync_service.dart';
import 'subscription_catalog_service.dart';
import 'summary_service.dart';
import 'translation_service.dart';
import 'undo_service.dart';

/// Clears data owned by the active Folo account while preserving preferences.
abstract final class AccountDataService {
  static void beginAccountChange() {
    AccountSessionGuard.beginAccountChange();
    AutoFilterWorker.cancelProcessing();
    AutoReadabilityWorker.cancelProcessing();
    ArticleRelationWorker.cancelProcessing();
    AutoSummaryWorker.cancelProcessing();
    AutoTranslationWorker.cancelProcessing();
    ReadSyncService.clear();
  }

  static Future<void> clearForAccountChange() async {
    await ArticleImageCacheService.resetForAccountChange();
    await AnalysisEventLedger.clear();
    await Future.wait([
      GStorage.localCache.clear(),
      GStorage.readStatus.clear(),
      GStorage.articleDb.clear(),
      GStorage.translations.clear(),
      GStorage.summaries.clear(),
      GStorage.readHistory.clear(),
      GStorage.articleRelations.clear(),
      GStorage.relationBatches.clear(),
    ]);

    final transientSettingKeys = GStorage.setting.keys
        .whereType<String>()
        .where(
          (key) =>
              key.startsWith(StorageKeys.readabilityFetchedPrefix) ||
              key.startsWith(StorageKeys.readabilityFetchStatePrefix) ||
              key.startsWith(StorageKeys.inboxDetailFetchedPrefix),
        )
        .toList(growable: false);
    await GStorage.setting.deleteAll(transientSettingKeys);

    LocalArticleDbService.invalidateCache();
    SummaryService.resetForAccountChange();
    ArticleRelationService.resetForAccountChange();
    TranslationService.resetForAccountChange();
    SubscriptionCatalogService.reset();
    ArticleContentUtils.clearCache();
    ArticleLengthEstimator.clearCache();
    UndoService.clear();
    ArticleStateNotifier.tickAll();
  }
}
