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

  Future<void> addTaskOffline({
    required String groupId,
    required String title,
    String priority = "low",
  }) async {
    final now = DateTime.now();
    final local = TaskItem(
      id: _uuid.v4(),
      groupId: groupId,
      title: title,
      description: null,
      isCompleted: false,
      priority: priority,
      order: now.millisecondsSinceEpoch,
      updatedAt: now,
      deletedAt: null,
      deadline: null,
    );
    await localDb.upsertTask(local);
    await localDb.enqueue("upsert_task", jsonEncode(local.toJson()));
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
    await localDb.enqueue("upsert_task", jsonEncode(updated.toJson()));
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
    await localDb.enqueue("upsert_task", jsonEncode(updated.toJson()));
  }

  Future<void> syncNow() async {
    final ops = await localDb.listOps();
    if (ops.isNotEmpty) {
      final tasks = ops
          .where((o) => o["op_type"] == "upsert_task")
          .map((o) => jsonDecode(o["payload"] as String) as Map<String, dynamic>)
          .toList();
      if (tasks.isNotEmpty) {
        await _api().post("/api/sync/push", {"tasks": tasks});
      }
      for (final o in ops) {
        await localDb.deleteOp(o["id"] as int);
      }
    }

    final checkpoint = await _checkpoint();
    final pull = await _api().getMap("/api/sync/pull?since=$checkpoint");
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
