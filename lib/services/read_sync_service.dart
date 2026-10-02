import '../http/feed_http.dart';
import '../http/init.dart';
import '../utils/storage.dart';
import 'account_session_guard.dart';
import 'analysis_event_ledger.dart';

class PendingReadSyncItem {
  final String entryId;
  final bool isInbox;
  final int updatedAt;
  final int revision;

  const PendingReadSyncItem({
    required this.entryId,
    required this.isInbox,
    required this.updatedAt,
    this.revision = 0,
  });

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'isInbox': isInbox,
    'updatedAt': updatedAt,
    'revision': revision,
  };

  factory PendingReadSyncItem.fromJson(Map<dynamic, dynamic> json) {
    return PendingReadSyncItem(
      entryId: json['entryId'] as String? ?? '',
      isInbox: json['isInbox'] as bool? ?? false,
      updatedAt: json['updatedAt'] as int? ?? 0,
      revision: json['revision'] as int? ?? 0,
    );
  }
}

/// 管理本地待同步的已读队列
abstract final class ReadSyncService {
  static const String _pendingReadIdsKey = 'pending_read_items';
  static const String _lastReadSyncAtKey = 'last_read_sync_at';
  static const String _revisionKey = 'pending_read_revision';
  static Future<void>? _syncInFlight;
  static int? _syncAccountRevision;

  static List<PendingReadSyncItem> get pendingReadItems {
    final raw = GStorage.localCache.get(_pendingReadIdsKey);
    if (raw is! List) return <PendingReadSyncItem>[];

    return raw
        .whereType<Object?>()
        .map((e) {
          if (e is Map) {
            return PendingReadSyncItem.fromJson(Map<dynamic, dynamic>.from(e));
          }
          final id = e?.toString() ?? '';
          if (id.isEmpty) {
            return null;
          }
          return PendingReadSyncItem(entryId: id, isInbox: false, updatedAt: 0);
        })
        .whereType<PendingReadSyncItem>()
        .toList();
  }

  static PendingReadSyncItem enqueue(String entryId, {required bool isInbox}) {
    final normalized = entryId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(entryId, 'entryId');

    final items = <String, PendingReadSyncItem>{
      for (final item in pendingReadItems) item.entryId: item,
    };
    final revision = (GStorage.localCache.get(_revisionKey) as int? ?? 0) + 1;
    GStorage.localCache.put(_revisionKey, revision);
    final task = PendingReadSyncItem(
      entryId: normalized,
      isInbox: isInbox,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: revision,
    );
    items[normalized] = task;
    GStorage.localCache.put(
      _pendingReadIdsKey,
      items.values.map((item) => item.toJson()).toList()..sort((a, b) {
        final left = a['updatedAt'] as int? ?? 0;
        final right = b['updatedAt'] as int? ?? 0;
        return left.compareTo(right);
      }),
    );
    return task;
  }

  static bool isCurrent(PendingReadSyncItem task) =>
      pendingReadItems.any((item) => _sameTask(item, task));

  static bool _sameTask(PendingReadSyncItem a, PendingReadSyncItem b) =>
      a.entryId == b.entryId &&
      a.isInbox == b.isInbox &&
      a.updatedAt == b.updatedAt &&
      a.revision == b.revision;

  /// A completed old request must not remove a newer task for the same ID.
  static void removeMatching(Iterable<PendingReadSyncItem> completed) {
    final tasks = completed.toList();
    if (tasks.isEmpty) return;
    final previous = pendingReadItems;
    final remaining = previous
        .where((item) => !tasks.any((task) => _sameTask(item, task)))
        .toList();
    if (remaining.length == previous.length) return;
    _save(remaining);
  }

  static void _save(List<PendingReadSyncItem> items) {
    if (items.isEmpty) {
      GStorage.localCache.delete(_pendingReadIdsKey);
    } else {
      GStorage.localCache.put(
        _pendingReadIdsKey,
        items.map((item) => item.toJson()).toList(),
      );
    }
  }

  static void removeMany(Iterable<String> entryIds) {
    final removeSet = entryIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (removeSet.isEmpty) return;

    final previous = pendingReadItems;
    final items = previous
        .where((item) => !removeSet.contains(item.entryId))
        .toList();
    if (items.length == previous.length) return;
    _save(items);
  }

  static Future<void> syncPendingReads() {
    final accountRevision = AccountSessionGuard.revision;
    if (_syncInFlight != null && _syncAccountRevision == accountRevision) {
      return _syncInFlight!;
    }
    final future = _syncPendingReadsInternal();
    _syncInFlight = future;
    _syncAccountRevision = accountRevision;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) _syncInFlight = null;
    });
  }

  static void clear() {
    // Do not forget an active drain when its persistent queue becomes empty.
    GStorage.localCache.delete(_pendingReadIdsKey);
  }

  static int? get lastReadSyncAt {
    final raw = GStorage.localCache.get(_lastReadSyncAtKey);
    return raw is int ? raw : null;
  }

  static Future<void> _syncPendingReadsInternal() async {
    final accountRevision = AccountSessionGuard.revision;
    final visited = <(String, int, int)>{};
    while (AccountSessionGuard.isCurrent(accountRevision)) {
      final candidates = pendingReadItems
          .where(
            (item) => !visited.contains((
              item.entryId,
              item.revision,
              item.updatedAt,
            )),
          )
          .toList();
      if (candidates.isEmpty) break;
      final isInbox = candidates.first.isInbox;
      final chunk = candidates
          .where((item) => item.isInbox == isInbox)
          .take(50)
          .toList();
      for (final item in chunk) {
        visited.add((item.entryId, item.revision, item.updatedAt));
      }
      List<PendingReadSyncItem> current() => chunk
          .where(
            (item) =>
                isCurrent(item) &&
                GStorage.readStatus.get(item.entryId) != false,
          )
          .toList();
      // Migrate an old, explicitly cancelled item without sending it.
      removeMatching(
        chunk.where((item) => GStorage.readStatus.get(item.entryId) == false),
      );
      for (var retry = 0; retry < 3; retry++) {
        if (!AccountSessionGuard.isCurrent(accountRevision)) return;
        final active = current();
        if (active.isEmpty) break;
        final result = await FeedHttp.markRead(
          entryIds: active.map((item) => item.entryId).toList(),
          isInbox: isInbox,
          auditSource: RemoteReadRequestSource.pendingQueue,
          currentEntryIds: () => current().map((item) => item.entryId).toList(),
          queuedAtByEntryId: {
            for (final item in active) item.entryId: item.updatedAt,
          },
        );
        if (!AccountSessionGuard.isCurrent(accountRevision)) return;
        if (result is Success<void>) {
          removeMatching(active);
          break;
        }
        if (retry < 2 && current().isNotEmpty) {
          await Future.delayed(Duration(seconds: 1 << retry));
        }
      }
    }
    if (!AccountSessionGuard.isCurrent(accountRevision)) return;
    GStorage.localCache.put(
      _lastReadSyncAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
