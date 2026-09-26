import 'package:flutter/material.dart';

import '../../models/article_relation.dart';

/// Historical overlapping groups retain their own overview; never silently
/// select only one group's topic for the combined related-article list.
class ArticleRelationTopics extends StatelessWidget {
  const ArticleRelationTopics({super.key, required this.groups});

  final List<ArticleRelationGroup> groups;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topics = groups.map((g) => g.displayTopic).toSet().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < topics.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Text(
            topics[i],
            style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface),
          ),
        ],
      ],
    );
  }
}
