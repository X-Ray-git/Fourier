abstract final class ApiConstants {
  static const String baseUrl = 'https://api.folo.is';
  static const String subscriptions = '/subscriptions';
  static const String entries = '/entries';
  static const String entriesInbox = '/entries/inbox';
  static const String entriesInboxDetail = '/entries/inbox'; // GET ?id=
  static const String inboxesList = '/inboxes/list';
  static const String reads = '/reads';
  static const String categories = '/categories';
}

abstract final class AppConstants {
  static const String appName = 'Fourier';
  static const int defaultPageSize = 50;
  static const int defaultTimeout = 30000;
  static const int defaultReadSyncWindowDays = 2;
  static const int defaultArticleContentMaxWidth = 720;
  static const int defaultMacosMaxFlingVelocity = 4500;
  static const String defaultAppearanceMode = 'system';
}

abstract final class StorageKeys {
  static const String sessionToken = 'session_token';
  static const String foloAccountProfile = 'folo_account_profile';
  static const String foloClientId = 'folo_client_id_v1';
  // Legacy backup/storage keys. Folo authentication only requires the token.
  static const String clientId = 'client_id';
  static const String sessionId = 'session_id';
  static const String localCache = 'localCache';
  static const String setting = 'setting';
  static const String readStatus = 'readStatus';
  static const String readSyncWindowDays = 'read_sync_window_days';
  static const String badgeStrategy = 'badge_strategy';
  static const String articleInitialChunkBuildCount =
      'article_initial_chunk_build_count';
  static const String articleContentMaxWidth = 'article_content_max_width';
  static const String macosMaxFlingVelocity = 'macos_max_fling_velocity';
  static const String appearanceMode = 'appearance_mode';
  static const String articleRelationEnabled = 'article_relation_enabled';
  static const String readabilityFetchedPrefix = 'readability_fetched_';
  static const String readabilityFetchStatePrefix = 'readability_fetch_state_';
  static const String inboxDetailFetchedPrefix = 'inbox_detail_fetched_';

  static String readabilityFetched(String entryId) =>
      '$readabilityFetchedPrefix$entryId';
  static String readabilityFetchState(String entryId) =>
      '$readabilityFetchStatePrefix$entryId';
  static String inboxDetailFetched(String entryId) =>
      '$inboxDetailFetchedPrefix$entryId';
}
