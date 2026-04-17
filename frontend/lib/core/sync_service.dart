import "dart:convert";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";
import "../models/models.dart";
import "api_client.dart";
import "auth_store.dart";
import "local_db.dart";

class SyncService {
  final LocalDb localDb;
  final AuthStore authStore;
  static const _checkpointKey = "sync_checkpoint_v1";
  static const _uuid = Uuid();

  SyncService({required this.localDb, required this.authStore});

  Future<String> _checkpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_checkpointKey) ?? DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();
  }

  Future<void> _saveCheckpoint(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checkpointKey, value);
  }

  ApiClient _api() => ApiClient(
        baseUrl: authStore.baseUrl,
        token: authStore.token,
        proxySettings: authStore.proxy,
      );

  /// Render и другие хостинги часто отдают 502/503 при пробуждении или перегрузке шлюза.
  Future<T> _retryTransient<T>(Future<T> Function() action, {int maxAttempts = 4}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        final transient = msg.contains("502") ||
            msg.contains("503") ||
            msg.contains("504") ||
            msg.contains("Connection reset") ||
            msg.contains("HandshakeException");
        if (!transient || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
      }
    }
    throw lastError!;
  }

  Future<void> addTaskOffline({
    required String groupId,
    required String title,
    String? description,
    String priority = "low",
  }) async {
    final now = DateTime.now();
    final local = TaskItem(
      id: _uuid.v4(),
      groupId: groupId,
      title: title,
      description: description,
      isCompleted: false,
      priority: priority,
      order: now.millisecondsSinceEpoch,
      updatedAt: now,
      deletedAt: null,
      deadline: null,
    );
    await localDb.upsertTask(local);
    await localDb.enqueue("upsert_task", jsonEncode(local.toSyncJson()));
  }

  Future<void> toggleOffline(TaskItem task) async {
    final updated = TaskItem(
      id: task.id,
      groupId: task.groupId,
      title: task.title,
      description: task.description,
      isCompleted: !task.isCompleted,
      priority: task.priority,
      order: task.order,
      updatedAt: DateTime.now(),
      deletedAt: null,
      deadline: task.deadline,
    );
    await localDb.upsertTask(updated);
    await localDb.enqueue("upsert_task", jsonEncode(updated.toSyncJson()));
  }

  Future<void> deleteOffline(TaskItem task) async {
    final updated = TaskItem(
      id: task.id,
      groupId: task.groupId,
      title: task.title,
      description: task.description,
      isCompleted: task.isCompleted,
      priority: task.priority,
      order: task.order,
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      deadline: task.deadline,
    );
    await localDb.upsertTask(updated);
    await localDb.enqueue("upsert_task", jsonEncode(updated.toSyncJson()));
  }

  Future<void> updateOffline(
    TaskItem task, {
    required String title,
    String? description,
  }) async {
    final updated = TaskItem(
      id: task.id,
      groupId: task.groupId,
      title: title,
      description: description,
      isCompleted: task.isCompleted,
      priority: task.priority,
      order: task.order,
      updatedAt: DateTime.now(),
      deletedAt: null,
      deadline: task.deadline,
    );
    await localDb.upsertTask(updated);
    await localDb.enqueue("upsert_task", jsonEncode(updated.toSyncJson()));
  }

  Future<List<TaskItem>> reorderOffline(List<TaskItem> orderedTasks) async {
    final baseTime = DateTime.now();
    final updatedTasks = <TaskItem>[];
    for (var i = 0; i < orderedTasks.length; i++) {
      final task = orderedTasks[i];
      final updated = TaskItem(
        id: task.id,
        groupId: task.groupId,
        title: task.title,
        description: task.description,
        isCompleted: task.isCompleted,
        priority: task.priority,
        order: i,
        updatedAt: baseTime.add(Duration(milliseconds: i)),
        deletedAt: task.deletedAt,
        deadline: task.deadline,
      );
      await localDb.upsertTask(updated);
      await localDb.enqueue("upsert_task", jsonEncode(updated.toSyncJson()));
      updatedTasks.add(updated);
    }
    return updatedTasks;
  }

  Future<void> syncNow() async {
    final ops = await localDb.listOps();
    final upsertOps = ops.where((o) => o["op_type"] == "upsert_task").toList();
    if (upsertOps.isNotEmpty) {
      final tasks = upsertOps
          .map((o) => jsonDecode(o["payload"] as String) as Map<String, dynamic>)
          .toList();
      await _retryTransient(() => _api().post("/api/sync/push", {"tasks": tasks}));
      for (final o in upsertOps) {
        await localDb.deleteOp(o["id"] as int);
      }
    }

    final checkpoint = await _checkpoint();
    final pull = await _retryTransient(() => _api().getMap("/api/sync/pull?since=$checkpoint"));
    final serverTasks = (pull["tasks"] as List<dynamic>? ?? [])
        .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // LWW: принимаем запись с более новым updatedAt
    final localAll = await localDb.listTasks(filter: "all", q: "");
    final localMap = {for (final t in localAll) t.id: t};
    for (final st in serverTasks) {
      final lt = localMap[st.id];
      if (lt == null || st.updatedAt.isAfter(lt.updatedAt)) {
        await localDb.upsertTask(st);
      }
    }
    await _saveCheckpoint((pull["serverTime"] as String?) ?? DateTime.now().toIso8601String());
  }
}
