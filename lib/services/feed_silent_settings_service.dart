import 'dart:convert';

import 'package:get/get.dart';

import '../utils/storage.dart';

class SilentFeedGroup {
  const SilentFeedGroup({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};
}

/// 管理与 Folo 分类相互独立的本地静默维度。
abstract final class FeedSilentSettingsService {
  static const String silentKeyPrefix = 'feed_silent_';
  static const String groupsKey = 'feed_silent_groups_v1';
  static const String assignmentKeyPrefix = 'feed_silent_group_assignment_';
  static const String ungroupedId = '__ungrouped__';
  static const Set<String> reservedGroupNames = {'全部静默', '未分组'};

  /// 用于通知 UI 层（如侧边栏分类树）配置已变更
  static final RxInt version = 0.obs;
  static String? _cachedGroupsJson;
  static List<SilentFeedGroup> _cachedGroups = const [];

  static bool isSilent(String feedId) {
    if (feedId.isEmpty) return false;
    final stored = GStorage.setting.get('$silentKeyPrefix$feedId');
    return stored is bool ? stored : false;
  }

  static List<SilentFeedGroup> get groups {
    final raw = GStorage.setting.get(groupsKey);
    if (raw is! String || raw.isEmpty) return const [];
    if (raw == _cachedGroupsJson) return _cachedGroups;
    try {
      _cachedGroupsJson = raw;
      _cachedGroups = parseGroupsJson(raw);
      return _cachedGroups;
    } catch (_) {
      _cachedGroups = const [];
      return const [];
    }
  }

  static List<SilentFeedGroup> parseGroupsJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('静默分组必须是数组');
    final result = <SilentFeedGroup>[];
    final ids = <String>{};
    final names = <String>{};
    for (final item in decoded) {
      if (item is! Map || item['id'] is! String || item['name'] is! String) {
        throw const FormatException('静默分组格式不正确');
      }
      final id = item['id'] as String;
      final name = (item['name'] as String).trim();
      if (id.isEmpty || id == ungroupedId || !_isValidGroupName(name)) {
        throw const FormatException('静默分组包含无效名称或标识');
      }
      if (!ids.add(id) || !names.add(name)) {
        throw const FormatException('静默分组标识或名称重复');
      }
      result.add(SilentFeedGroup(id: id, name: name));
    }
    return List.unmodifiable(result);
  }

  static SilentFeedGroup? groupById(String? groupId) {
    if (groupId == null) return null;
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  static String? groupIdFor(String feedId) {
    if (!isSilent(feedId)) return null;
    final value = GStorage.setting.get('$assignmentKeyPrefix$feedId');
    if (value is! String || groupById(value) == null) return null;
    return value;
  }

  static Future<void> setSilent(
    String feedId,
    bool silent, {
    String? groupId,
  }) async {
    if (feedId.isEmpty) return;
    if (silent && groupId != null && groupById(groupId) == null) {
      throw ArgumentError.value(groupId, 'groupId', 'Unknown silent group');
    }
    await GStorage.setting.put('$silentKeyPrefix$feedId', silent);
    if (silent && groupId != null) {
      await GStorage.setting.put('$assignmentKeyPrefix$feedId', groupId);
    } else {
      await GStorage.setting.delete('$assignmentKeyPrefix$feedId');
    }
    version.value++;
  }

  static Future<void> moveToGroup(String feedId, String? groupId) async {
    await setSilent(feedId, true, groupId: groupId);
  }

  static Future<SilentFeedGroup> createGroup(String name) async {
    final normalized = _validateNewName(name);
    final current = groups;
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var suffix = 0;
    while (current.any((group) => group.id == id)) {
      id =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${suffix++}';
    }
    final group = SilentFeedGroup(id: id, name: normalized);
    await _writeGroups([...current, group]);
    version.value++;
    return group;
  }

  static Future<void> renameGroup(String groupId, String name) async {
    final normalized = _validateNewName(name, excludingId: groupId);
    final current = groups;
    if (!current.any((group) => group.id == groupId)) {
      throw ArgumentError.value(groupId, 'groupId', 'Unknown silent group');
    }
    await _writeGroups([
      for (final group in current)
        group.id == groupId
            ? SilentFeedGroup(id: group.id, name: normalized)
            : group,
    ]);
    version.value++;
  }

  static Future<void> moveGroup(String groupId, int offset) async {
    if (offset == 0) return;
    final current = groups.toList();
    final oldIndex = current.indexWhere((group) => group.id == groupId);
    if (oldIndex < 0) return;
    final newIndex = (oldIndex + offset).clamp(0, current.length - 1);
    if (newIndex == oldIndex) return;
    final group = current.removeAt(oldIndex);
    current.insert(newIndex, group);
    await _writeGroups(current);
    version.value++;
  }

  /// 删除分组只清除归属，其中的订阅源继续静默并落入“未分组”。
  static Future<void> deleteGroup(String groupId) async {
    final current = groups;
    final remaining = current.where((group) => group.id != groupId).toList();
    if (remaining.length == current.length) return;
    final keysToDelete = <String>[];
    for (final rawKey in GStorage.setting.keys) {
      if (rawKey is String && rawKey.startsWith(assignmentKeyPrefix)) {
        if (GStorage.setting.get(rawKey) == groupId) keysToDelete.add(rawKey);
      }
    }
    await _writeGroups(remaining);
    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
    version.value++;
  }

  static int feedCountForGroup(String? groupId) {
    var count = 0;
    for (final rawKey in GStorage.setting.keys) {
      if (rawKey is! String || !rawKey.startsWith(silentKeyPrefix)) continue;
      if (rawKey == groupsKey || rawKey.startsWith(assignmentKeyPrefix)) {
        continue;
      }
      final feedId = rawKey.substring(silentKeyPrefix.length);
      if (isSilent(feedId) && groupIdFor(feedId) == groupId) count++;
    }
    return count;
  }

  static Future<void> clearAllSettings() async {
    final keysToDelete = <String>[];
    for (final key in GStorage.setting.keys) {
      if (key is String && key.startsWith(silentKeyPrefix)) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
    if (keysToDelete.isNotEmpty) {
      version.value++;
    }
  }

  static String _validateNewName(String name, {String? excludingId}) {
    final normalized = name.trim();
    if (!_isValidGroupName(normalized)) {
      throw const FormatException('分组名称须为 1–40 个字符，且不能使用保留名称');
    }
    if (groups.any(
      (group) => group.id != excludingId && group.name == normalized,
    )) {
      throw const FormatException('静默分组名称不能重复');
    }
    return normalized;
  }

  static bool _isValidGroupName(String name) =>
      name.isNotEmpty &&
      name.length <= 40 &&
      !reservedGroupNames.contains(name);

  static Future<void> _writeGroups(List<SilentFeedGroup> value) {
    final encoded = jsonEncode(value.map((group) => group.toJson()).toList());
    _cachedGroupsJson = encoded;
    _cachedGroups = List.unmodifiable(value);
    return GStorage.setting.put(groupsKey, encoded);
  }
}
