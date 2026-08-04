import 'package:autofolo/services/mac_article_shortcut_service.dart';
import 'package:autofolo/common/widgets/mac_empty_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects a boundary only for an active unselected list', (
    tester,
  ) async {
    final owner = Object();
    var active = true;
    var selected = false;
    int? direction;
    addTearDown(() => MacArticleShortcutService.instance.unregister(owner));
    MacArticleShortcutService.instance.register(
      owner,
      isActive: () => active,
      hasSelection: () => selected,
      selectBoundary: (value) {
        direction = value;
        return true;
      },
    );

    expect(MacArticleShortcutService.instance.canSelectBoundary, isTrue);
    expect(MacArticleShortcutService.instance.selectBoundary(-1), isTrue);
    expect(direction, -1);

    selected = true;
    expect(MacArticleShortcutService.instance.canSelectBoundary, isFalse);

    selected = false;
    active = false;
    expect(MacArticleShortcutService.instance.canSelectBoundary, isFalse);
  });

  testWidgets('does not steal arrow keys from editable text', (tester) async {
    final owner = Object();
    addTearDown(() => MacArticleShortcutService.instance.unregister(owner));
    MacArticleShortcutService.instance.register(
      owner,
      isActive: () => true,
      hasSelection: () => false,
      selectBoundary: (_) => true,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TextField(autofocus: true))),
    );
    await tester.pump();

    expect(MacArticleShortcutService.instance.canSelectBoundary, isFalse);
  });

  testWidgets('empty detail placeholder accepts a neutral focus target', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(home: MacSplitDetailEmptyPlaceholder(focusNode: focusNode)),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('recognizes modifiers that must bypass article shortcuts', (
    tester,
  ) async {
    expect(MacArticleShortcutService.hasNonShiftModifier, isFalse);

    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await tester.sendKeyDownEvent(key);
      expect(MacArticleShortcutService.hasNonShiftModifier, isTrue);
      await tester.sendKeyUpEvent(key);
      expect(MacArticleShortcutService.hasNonShiftModifier, isFalse);
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(MacArticleShortcutService.hasNonShiftModifier, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });
}
