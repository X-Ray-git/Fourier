import '../utils/source_taxonomy.dart';
import '../utils/html_entity_utils.dart';

const Object _articleFieldUnset = Object();

class ArticleModel {
  final String entryId;
  final String feedId;
  final String feedTitle;
  final String? feedImage;
  final String title;
  final String url;
  final String? content;
  final String publishedAt;
  final bool isRead;
  final String category;
  final String subscriptionCategory;
  final String? author;
  final String? imageUrl;
  static const String userActionKeep = 'k';
  static const String userActionReject = 'm';
  static const String userActionMisclassifyKeep = 'n_keep';
  static const String userActionMisclassifySpam = 'n_spam';

  final bool isRejectedByAi;
  final String? filterReason;
  final bool filterReviewed; // 用户已审核过，不再重判
  final int? filteredAt; // 拦截判定完成的时间戳（毫秒）
  final String? userAction; // 用户动作标记，事后统计误分类用

  ArticleModel({
    required this.entryId,
    required this.feedId,
    required this.feedTitle,
    this.feedImage,
    required this.title,
    required this.url,
    this.content,
    this.publishedAt = '',
    this.isRead = false,
    this.category = 'feeds',
    this.subscriptionCategory = '',
    this.author,
    this.imageUrl,
    this.isRejectedByAi = false,
    this.filterReason,
    this.filterReviewed = false,
    this.filteredAt,
    this.userAction,
  });

  ArticleModel copyWith({
    String? entryId,
    String? feedId,
    String? feedTitle,
    Object? feedImage = _articleFieldUnset,
    String? title,
    String? url,
    Object? content = _articleFieldUnset,
    String? publishedAt,
    bool? isRead,
    String? category,
    String? subscriptionCategory,
    Object? author = _articleFieldUnset,
    Object? imageUrl = _articleFieldUnset,
    bool? isRejectedByAi,
    Object? filterReason = _articleFieldUnset,
    bool? filterReviewed,
    Object? filteredAt = _articleFieldUnset,
    Object? userAction = _articleFieldUnset,
  }) {
    return ArticleModel(
      entryId: entryId ?? this.entryId,
      feedId: feedId ?? this.feedId,
      feedTitle: feedTitle ?? this.feedTitle,
      feedImage: identical(feedImage, _articleFieldUnset)
          ? this.feedImage
          : feedImage as String?,
      title: title ?? this.title,
      url: url ?? this.url,
      content: identical(content, _articleFieldUnset)
          ? this.content
          : content as String?,
      publishedAt: publishedAt ?? this.publishedAt,
      isRead: isRead ?? this.isRead,
      category: category ?? this.category,
      subscriptionCategory: subscriptionCategory ?? this.subscriptionCategory,
      author: identical(author, _articleFieldUnset)
          ? this.author
          : author as String?,
      imageUrl: identical(imageUrl, _articleFieldUnset)
          ? this.imageUrl
          : imageUrl as String?,
      isRejectedByAi: isRejectedByAi ?? this.isRejectedByAi,
      filterReason: identical(filterReason, _articleFieldUnset)
          ? this.filterReason
          : filterReason as String?,
      filterReviewed: filterReviewed ?? this.filterReviewed,
      filteredAt: identical(filteredAt, _articleFieldUnset)
          ? this.filteredAt
          : filteredAt as int?,
      userAction: identical(userAction, _articleFieldUnset)
          ? this.userAction
          : userAction as String?,
    );
  }

  factory ArticleModel.fromEntryJson(
    Map<String, dynamic> item, {
    String? feedTitle,
    String? feedImage,
    String? subscriptionCategory,
    int view = 0,
    int? feedView,
  }) {
    final entry = item['entries'] as Map<String, dynamic>? ?? {};
    final feed = item['feeds'] as Map<String, dynamic>? ?? {};
    final media = entry['media'] as List<dynamic>?;
    String? imageUrl;
    if (media != null && media.isNotEmpty) {
      final m = media.first as Map<String, dynamic>?;
      imageUrl = m?['url'] as String?;
    }

    final category = (view == 1 || feedView == 1) ? 'social' : 'feeds';

    return ArticleModel(
      entryId: entry['id'] as String? ?? '',
      feedId: feed['id'] as String? ?? '',
      feedTitle: HtmlEntityUtils.decodeText(
        feedTitle ?? feed['title'] as String? ?? '?',
      ),
      feedImage: feedImage ?? feed['image'] as String?,
      title: HtmlEntityUtils.decodeText(entry['title'] as String? ?? '?'),
      url: entry['url'] as String? ?? '',
      content: entry['content'] as String?,
      publishedAt: entry['publishedAt'] as String? ?? '',
      isRead: item['read'] as bool? ?? false,
      category: category,
      subscriptionCategory: HtmlEntityUtils.decodeText(
        subscriptionCategory ?? '',
      ),
      author: HtmlEntityUtils.decodeNullableText(entry['author'] as String?),
      imageUrl: imageUrl,
      isRejectedByAi: false,
      filterReviewed: false,
      filteredAt: null,
    );
  }

  factory ArticleModel.fromInboxJson(
    Map<String, dynamic> item, {
    String? feedTitle,
    String? feedImage,
    String? subscriptionCategory,
  }) {
    final entry = item['entries'] as Map<String, dynamic>? ?? {};
    final sourceTitle = HtmlEntityUtils.decodeText(
      feedTitle ?? SourceTaxonomy.inboxDisplayTitle(item),
    );
    return ArticleModel(
      entryId: entry['id'] as String? ?? '',
      feedId:
          (item['feeds'] as Map<String, dynamic>?)?['id'] as String? ??
          entry['inboxHandle'] as String? ??
          '',
      feedTitle: sourceTitle,
      feedImage: feedImage ?? item['image'] as String?,
      title: HtmlEntityUtils.decodeText(entry['title'] as String? ?? '?'),
      url: entry['url'] as String? ?? '',
      content: entry['content'] as String?,
      publishedAt: entry['publishedAt'] as String? ?? '',
      isRead: item['read'] as bool? ?? false,
      category: 'inbox',
      subscriptionCategory: HtmlEntityUtils.decodeText(
        subscriptionCategory ?? SourceTaxonomy.inboxShortLabel(item),
      ),
      isRejectedByAi: false,
      filterReviewed: false,
      filteredAt: null,
    );
  }

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'feedId': feedId,
    'feedTitle': feedTitle,
    'feedImage': feedImage,
    'title': title,
    'url': url,
    'content': content,
    'publishedAt': publishedAt,
    'isRead': isRead,
    'category': category,
    'subscriptionCategory': subscriptionCategory,
    'author': author,
    'imageUrl': imageUrl,
    'isRejectedByAi': isRejectedByAi,
    'filterReason': filterReason,
    'filterReviewed': filterReviewed,
    'filteredAt': filteredAt,
    'userAction': userAction,
  };

  factory ArticleModel.fromCache(Map<String, dynamic> json) => ArticleModel(
    entryId: json['entryId'] as String? ?? '',
    feedId: json['feedId'] as String? ?? '',
    feedTitle: HtmlEntityUtils.decodeText(json['feedTitle'] as String? ?? '?'),
    feedImage: json['feedImage'] as String?,
    title: HtmlEntityUtils.decodeText(json['title'] as String? ?? '?'),
    url: json['url'] as String? ?? '',
    content: json['content'] as String?,
    publishedAt: json['publishedAt'] as String? ?? '',
    isRead: json['isRead'] as bool? ?? false,
    category: json['category'] as String? ?? 'feeds',
    subscriptionCategory: HtmlEntityUtils.decodeText(
      json['subscriptionCategory'] as String? ?? '',
    ),
    author: HtmlEntityUtils.decodeNullableText(json['author'] as String?),
    imageUrl: json['imageUrl'] as String?,
    isRejectedByAi: json['isRejectedByAi'] as bool? ?? false,
    filterReason: HtmlEntityUtils.decodeNullableText(
      json['filterReason'] as String?,
    ),
    filterReviewed: json['filterReviewed'] as bool? ?? false,
    filteredAt: json['filteredAt'] as int?,
    userAction: json['userAction'] as String?,
  );

  String get displayCategory =>
      subscriptionCategory.isNotEmpty ? subscriptionCategory : '未分类';
}
