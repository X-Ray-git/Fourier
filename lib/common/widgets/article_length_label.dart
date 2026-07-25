import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../utils/article_length_estimator.dart';

class ArticleLengthLabel extends StatelessWidget {
  const ArticleLengthLabel({super.key, required this.article});

  final ArticleModel article;

  @override
  Widget build(BuildContext context) {
    final label = ArticleLengthEstimator.formatReadingHeight(article);
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Semantics(
      label: '预计内容高度 $label',
      child: ExcludeSemantics(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ),
    );
  }
}
