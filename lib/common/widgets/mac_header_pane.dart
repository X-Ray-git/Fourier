import 'package:flutter/material.dart';

/// Shared fixed header layout for macOS split-view list panes.
class MacHeaderPane extends StatelessWidget {
  final double headerHeight;
  final Widget header;
  final Widget body;

  const MacHeaderPane({
    super.key,
    required this.headerHeight,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: headerHeight, child: header),
        Expanded(child: body),
      ],
    );
  }
}
