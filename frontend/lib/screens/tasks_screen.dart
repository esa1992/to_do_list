import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../core/api_client.dart";
import "../core/auth_store.dart";
import "../core/local_db.dart";
import "../core/notification_service.dart";
import "../core/sync_service.dart";
import "../models/models.dart";
import "settings_screen.dart";

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final taskCtrl = TextEditingController();
  final localDb = LocalDb();
  final notifications = NotificationService();
  List<TaskItem> tasks = [];
  bool loading = false;
  String filter = "all";
  String query = "";
  String? defaultGroupId;
  SyncService? syncService;

  Future<void> loadTasks() async {
    final auth = context.read<AuthStore>();
    if (auth.token == null || syncService == null) return;
    setState(() => loading = true);
    try {
      final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
      final groups = await api.getList("/api/groups");
      if (groups.isNotEmpty) {
        defaultGroupId = (groups.first as Map<String, dynamic>)["id"] as String;
      }
      try {
        await syncService!.syncNow();
      } catch (_) {
        // сеть недоступна: работаем из локального кэша
      }
      final list = await localDb.listTasks(filter: filter, q: query);
      setState(() => tasks = list);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> addTask() async {
    if (taskCtrl.text.trim().isEmpty || defaultGroupId == null || syncService == null) return;
    await syncService!.addTaskOffline(groupId: defaultGroupId!, title: taskCtrl.text.trim());
    taskCtrl.clear();
    await loadTasks();
  }

  Future<void> toggle(TaskItem item) async {
    if (syncService == null) return;
    await syncService!.toggleOffline(item);
    await loadTasks();
  }

  Future<void> remove(TaskItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Подтверждение"),
        content: const Text("Вы уверены? Задача будет удалена."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Нет")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Да")),
        ],
      ),
    );
    if (confirm != true) return;
    if (syncService == null) return;
    await syncService!.deleteOffline(item);
    await loadTasks();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthStore>();
      syncService = SyncService(localDb: localDb, authStore: auth);
      await notifications.init();
      await loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("To-Do"),
        actions: [
          IconButton(
            onPressed: () => showDialog(context: context, builder: (_) => const SettingsScreen()),
            icon: const Icon(Icons.settings),
          ),
          IconButton(onPressed: auth.logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: taskCtrl,
                    decoration: const InputDecoration(hintText: "Быстрое добавление задачи"),
                    onSubmitted: (_) => addTask(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: addTask, child: const Text("Добавить")),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: filter,
                  items: const [
                    DropdownMenuItem(value: "all", child: Text("Все")),
                    DropdownMenuItem(value: "active", child: Text("Активные")),
                    DropdownMenuItem(value: "completed", child: Text("Выполненные")),
                  ],
                  onChanged: (v) async {
                    setState(() => filter = v ?? "all");
                    await loadTasks();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: "Поиск"),
                    onChanged: (v) => query = v,
                    onSubmitted: (_) => loadTasks(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView(
                    onReorder: (oldIndex, newIndex) async {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final reordered = [...tasks];
                      final item = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, item);
                      setState(() => tasks = reordered);
                    },
                    children: [
                      for (final t in tasks)
                        ListTile(
                          key: ValueKey(t.id),
                          leading: Checkbox(value: t.isCompleted, onChanged: (_) => toggle(t)),
                          title: Text(
                            t.title,
                            style: TextStyle(
                              color: t.isCompleted ? Colors.grey : null,
                              decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          subtitle: Text("${t.priority}${t.deadline != null ? " • дедлайн: ${t.deadline}" : ""}"),
                          trailing: IconButton(onPressed: () => remove(t), icon: const Icon(Icons.delete)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
