import 'package:flutter/material.dart';

import '../utils/html_entity_utils.dart';
import '../utils/source_taxonomy.dart';

class FeedModel {
  final String feedId;
  final String title;
  final String sourceTitle;
  final String? customTitle;
  final String? category;
  final int? view;
  final String? url;
  final String? image;

  FeedModel({
    required this.feedId,
    required this.title,
    String? sourceTitle,
    this.customTitle,
    this.category,
    this.view,
    this.url,
    this.image,
  }) : sourceTitle = sourceTitle ?? title;

  factory FeedModel.fromJson(Map<String, dynamic> json) {
    final feeds = json['feeds'] as Map<String, dynamic>? ?? {};
    final sourceTitle = HtmlEntityUtils.decodeText(
      feeds['title'] as String? ?? '?',
    );
    final customTitle = HtmlEntityUtils.decodeNullableText(
      json['title'] as String?,
    );
    return FeedModel(
      feedId: json['feedId'] as String? ?? '',
      title: customTitle?.trim().isNotEmpty == true
          ? customTitle!
          : sourceTitle,
      sourceTitle: sourceTitle,
      customTitle: customTitle,
      category: HtmlEntityUtils.decodeNullableText(json['category'] as String?),
      view: json['view'] as int?,
      url: feeds['url'] as String?,
      image: feeds['image'] as String?,
    );
  }

  factory FeedModel.fromSubscriptionMutation(
    Map<String, dynamic> feed, {
    required String? customTitle,
    required String? category,
    required int view,
    String? fallbackUrl,
  }) {
    final sourceTitle = HtmlEntityUtils.decodeText(
      feed['title'] as String? ?? customTitle ?? '?',
    );
    final decodedCustomTitle = HtmlEntityUtils.decodeNullableText(customTitle);
    return FeedModel(
      feedId: feed['id'] as String? ?? feed['feedId'] as String? ?? '',
      title: decodedCustomTitle?.trim().isNotEmpty == true
          ? decodedCustomTitle!
          : sourceTitle,
      sourceTitle: sourceTitle,
      customTitle: decodedCustomTitle,
      category: HtmlEntityUtils.decodeNullableText(category),
      view: view,
      url: feed['url'] as String? ?? fallbackUrl,
      image: feed['image'] as String?,
    );
  }

  factory FeedModel.fromInboxJson(Map<String, dynamic> json) {
    return FeedModel(
      feedId: (json['id'] as String?) ?? (json['inboxId'] as String? ?? ''),
      title: HtmlEntityUtils.decodeText(SourceTaxonomy.inboxDisplayTitle(json)),
      category: HtmlEntityUtils.decodeText(
        SourceTaxonomy.inboxShortLabel(json),
      ),
      view: 2,
      url: json['url'] as String?,
      image: json['image'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'feedId': feedId,
    'title': title,
    'sourceTitle': sourceTitle,
    'customTitle': customTitle,
    'category': category,
    'view': view,
    'url': url,
    'image': image,
  };

  factory FeedModel.fromCache(Map<String, dynamic> json) {
    final title = HtmlEntityUtils.decodeText(json['title'] as String? ?? '?');
    return FeedModel(
      feedId: json['feedId'] as String? ?? '',
      title: title,
      sourceTitle: HtmlEntityUtils.decodeText(
        json['sourceTitle'] as String? ?? title,
      ),
      customTitle: HtmlEntityUtils.decodeNullableText(
        json['customTitle'] as String?,
      ),
      category: HtmlEntityUtils.decodeNullableText(json['category'] as String?),
      view: json['view'] as int?,
      url: json['url'] as String?,
      image: json['image'] as String?,
    );
  }

  FeedModel copyWith({
    String? feedId,
    String? title,
    String? sourceTitle,
    String? customTitle,
    bool clearCustomTitle = false,
    String? category,
    bool clearCategory = false,
    int? view,
    String? url,
    String? image,
  }) {
    final nextCustomTitle = clearCustomTitle
        ? null
        : (customTitle ?? this.customTitle);
    final nextSourceTitle = sourceTitle ?? this.sourceTitle;
    return FeedModel(
      feedId: feedId ?? this.feedId,
      title:
          title ??
          (nextCustomTitle?.trim().isNotEmpty == true
              ? nextCustomTitle!
              : nextSourceTitle),
      sourceTitle: nextSourceTitle,
      customTitle: nextCustomTitle,
      category: clearCategory ? null : (category ?? this.category),
      view: view ?? this.view,
      url: url ?? this.url,
      image: image ?? this.image,
    );
  }

  String get displayCategory => category ?? '未分类';
  String get viewLabel => SourceTaxonomy.viewLabelFromInt(view);
  String get viewKey => SourceTaxonomy.viewKeyFromInt(view);
  Color get viewColor => SourceTaxonomy.viewColorFromInt(view);
  int get viewOrder => SourceTaxonomy.viewOrderFromInt(view);
  bool get isInbox => view == 2;
}
