import 'package:flutter/widgets.dart';

typedef MacShortcutPredicate = bool Function();
typedef MacBoundarySelection = bool Function(int direction);

class MacArticleShortcutService {
  MacArticleShortcutService._();

  static final instance = MacArticleShortcutService._();

  final Map<Object, _MacArticleShortcutTarget> _targets = {};

  void register(
    Object owner, {
    required MacShortcutPredicate isActive,
    required MacShortcutPredicate hasSelection,
    required MacBoundarySelection selectBoundary,
  }) {
    _targets[owner] = _MacArticleShortcutTarget(
      isActive: isActive,
      hasSelection: hasSelection,
      selectBoundary: selectBoundary,
    );
  }

  void unregister(Object owner) {
    _targets.remove(owner);
  }

  bool get canSelectBoundary {
    final target = _activeTarget;
    if (target == null || target.hasSelection()) return false;

    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return false;
    }
    return true;
  }

  bool selectBoundary(int direction) {
    final target = _activeTarget;
    if (target == null || target.hasSelection() || !canSelectBoundary) {
      return false;
    }

    // A sidebar InkWell may still own keyboard focus after closing an article.
    // Release it before mounting the next detail view so its focus highlight
    // cannot remain visible alongside the newly selected card.
    FocusManager.instance.primaryFocus?.unfocus();
    return target.selectBoundary(direction);
  }

  _MacArticleShortcutTarget? get _activeTarget {
    for (final target in _targets.values.toList().reversed) {
      if (target.isActive()) return target;
    }
    return null;
  }
}

class _MacArticleShortcutTarget {
  const _MacArticleShortcutTarget({
    required this.isActive,
    required this.hasSelection,
    required this.selectBoundary,
  });

  final MacShortcutPredicate isActive;
  final MacShortcutPredicate hasSelection;
  final MacBoundarySelection selectBoundary;
}
