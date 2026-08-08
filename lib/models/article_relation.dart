class ArticleRelationNode {
  const ArticleRelationNode({
    required this.articleId,
    required this.sequence,
    required this.title,
    required this.feedId,
    required this.feedTitle,
    required this.url,
    required this.summary,
    required this.summaryDigest,
    required this.summaryUpdatedAt,
    this.feedImage,
    this.author,
    this.publishedAt = '',
    this.processedAt,
    this.lastBatchId,
  });

  final String articleId;
  final int sequence;
  final String title;
  final String feedId;
  final String feedTitle;
  final String? feedImage;
  final String url;
  final String? author;
  final String publishedAt;
  final String summary;
  final String summaryDigest;
  final int summaryUpdatedAt;
  final int? processedAt;
  final String? lastBatchId;

  ArticleRelationNode copyWith({
    int? sequence,
    String? title,
    String? feedId,
    String? feedTitle,
    String? feedImage,
    String? url,
    String? author,
    String? publishedAt,
    String? summary,
    String? summaryDigest,
    int? summaryUpdatedAt,
    int? processedAt,
    String? lastBatchId,
  }) {
    return ArticleRelationNode(
      articleId: articleId,
      sequence: sequence ?? this.sequence,
      title: title ?? this.title,
      feedId: feedId ?? this.feedId,
      feedTitle: feedTitle ?? this.feedTitle,
      feedImage: feedImage ?? this.feedImage,
      url: url ?? this.url,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      summary: summary ?? this.summary,
      summaryDigest: summaryDigest ?? this.summaryDigest,
      summaryUpdatedAt: summaryUpdatedAt ?? this.summaryUpdatedAt,
      processedAt: processedAt ?? this.processedAt,
      lastBatchId: lastBatchId ?? this.lastBatchId,
    );
  }

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'sequence': sequence,
    'title': title,
    'feedId': feedId,
    'feedTitle': feedTitle,
    'feedImage': feedImage,
    'url': url,
    'author': author,
    'publishedAt': publishedAt,
    'summary': summary,
    'summaryDigest': summaryDigest,
    'summaryUpdatedAt': summaryUpdatedAt,
    'processedAt': processedAt,
    'lastBatchId': lastBatchId,
  };

  factory ArticleRelationNode.fromJson(Map<dynamic, dynamic> json) {
    return ArticleRelationNode(
      articleId: json['articleId'] as String? ?? '',
      sequence: json['sequence'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      feedId: json['feedId'] as String? ?? '',
      feedTitle: json['feedTitle'] as String? ?? '',
      feedImage: json['feedImage'] as String?,
      url: json['url'] as String? ?? '',
      author: json['author'] as String?,
      publishedAt: json['publishedAt'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      summaryDigest: json['summaryDigest'] as String? ?? '',
      summaryUpdatedAt: json['summaryUpdatedAt'] as int? ?? 0,
      processedAt: json['processedAt'] as int?,
      lastBatchId: json['lastBatchId'] as String?,
    );
  }
}

class ArticleRelationGroup {
  const ArticleRelationGroup({
    required this.id,
    required this.batchId,
    required this.memberIds,
    required this.reason,
    required this.confidence,
    required this.createdAt,
    this.enabled = true,
  });

  final String id;
  final String batchId;
  final List<String> memberIds;
  final String reason;
  final double confidence;
  final int createdAt;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'memberIds': memberIds,
    'reason': reason,
    'confidence': confidence,
    'createdAt': createdAt,
    'enabled': enabled,
  };

  factory ArticleRelationGroup.fromJson(Map<dynamic, dynamic> json) {
    return ArticleRelationGroup(
      id: json['id'] as String? ?? '',
      batchId: json['batchId'] as String? ?? '',
      memberIds: (json['memberIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      reason: json['reason'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class ArticleRelationBatchRecord {
  const ArticleRelationBatchRecord({
    required this.id,
    required this.status,
    required this.newArticleIds,
    required this.historyArticleIds,
    required this.model,
    required this.promptVersion,
    required this.schemaVersion,
    required this.startedAt,
    this.completedAt,
    this.groupCount = 0,
    this.error,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheMissTokens = 0,
    this.totalTokens = 0,
    this.durationMs = 0,
  });

  final String id;
  final String status;
  final List<String> newArticleIds;
  final List<String> historyArticleIds;
  final String model;
  final String promptVersion;
  final int schemaVersion;
  final int startedAt;
  final int? completedAt;
  final int groupCount;
  final String? error;
  final int promptTokens;
  final int completionTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final int totalTokens;
  final int durationMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'newArticleIds': newArticleIds,
    'historyArticleIds': historyArticleIds,
    'model': model,
    'promptVersion': promptVersion,
    'schemaVersion': schemaVersion,
    'startedAt': startedAt,
    'completedAt': completedAt,
    'groupCount': groupCount,
    'error': error,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'cacheHitTokens': cacheHitTokens,
    'cacheMissTokens': cacheMissTokens,
    'totalTokens': totalTokens,
    'durationMs': durationMs,
  };

  factory ArticleRelationBatchRecord.fromJson(Map<dynamic, dynamic> json) {
    return ArticleRelationBatchRecord(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'failed',
      newArticleIds: (json['newArticleIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      historyArticleIds:
          (json['historyArticleIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      model: json['model'] as String? ?? '',
      promptVersion: json['promptVersion'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      startedAt: json['startedAt'] as int? ?? 0,
      completedAt: json['completedAt'] as int?,
      groupCount: json['groupCount'] as int? ?? 0,
      error: json['error'] as String?,
      promptTokens: json['promptTokens'] as int? ?? 0,
      completionTokens: json['completionTokens'] as int? ?? 0,
      cacheHitTokens: json['cacheHitTokens'] as int? ?? 0,
      cacheMissTokens: json['cacheMissTokens'] as int? ?? 0,
      totalTokens: json['totalTokens'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
    );
  }
}
