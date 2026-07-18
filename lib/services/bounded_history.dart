class BoundedHistory<T> {
  BoundedHistory({required this.limit}) : assert(limit > 0);

  final int limit;
  final List<T> _undo = <T>[];
  final List<T> _redo = <T>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  T? get nextUndo => _undo.isEmpty ? null : _undo.last;
  T? get nextRedo => _redo.isEmpty ? null : _redo.last;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  void push(T value) {
    _undo.add(value);
    if (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  T? takeUndo() {
    if (_undo.isEmpty) return null;
    final value = _undo.removeLast();
    _redo.add(value);
    return value;
  }

  T? takeRedo() {
    if (_redo.isEmpty) return null;
    final value = _redo.removeLast();
    _undo.add(value);
    return value;
  }

  bool rollbackUndo(T value) {
    if (_redo.isEmpty || !identical(_redo.last, value)) return false;
    _redo.removeLast();
    _undo.add(value);
    return true;
  }

  bool rollbackRedo(T value) {
    if (_undo.isEmpty || !identical(_undo.last, value)) return false;
    _undo.removeLast();
    _redo.add(value);
    return true;
  }

  void removeWhere(bool Function(T value) predicate) {
    _undo.removeWhere(predicate);
    _redo.removeWhere(predicate);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
