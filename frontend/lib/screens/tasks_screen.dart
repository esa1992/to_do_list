import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart";
import "package:provider/provider.dart";
import "../core/api_client.dart";
import "../core/auth_store.dart";
import "../core/local_db.dart";
import "../core/notification_service.dart";
import "../core/sync_service.dart";
import "../models/models.dart";
import "groups_screen.dart";
import "settings_screen.dart";

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with WidgetsBindingObserver {
  final localDb = LocalDb();
  final notifications = NotificationService();
  List<TaskItem> tasks = [];
  List<Map<String, dynamic>> groups = [];
  bool loading = false;
  bool groupsLoading = false;
  String? groupsError;
  String filter = "all";
  String query = "";
  String? defaultGroupId;
  SyncService? syncService;
  bool _bootstrapped = false;
  Timer? _autoRefreshTimer;
  bool _silentRefreshing = false;

  String get filterLabel {
    switch (filter) {
      case "active":
        return "Активные";
      case "completed":
        return "Выполненные";
      default:
        return "Все";
    }
  }

  Future<void> _bootstrapLoad() async {
    if (_bootstrapped) return;
    final auth = context.read<AuthStore>();
    if (kDebugMode) {
      debugPrint("[BOOT] _bootstrapLoad token=${auth.token != null}");
    }
    if (auth.token == null) return;
    _bootstrapped = true;
    syncService ??= SyncService(localDb: localDb, authStore: auth);
    try {
      await notifications.init();
      if (kDebugMode) debugPrint("[BOOT] notifications initialized");
    } catch (e) {
      // Не блокируем загрузку данных, если уведомления на платформе недоступны.
      if (kDebugMode) debugPrint("[BOOT] notifications init failed: $e");
    }
    if (kDebugMode) debugPrint("[BOOT] calling loadTasks()");
    await loadTasks();
    _startAutoRefresh();
  }

  void _onAuthChanged() {
    // Когда токен появляется после async init/refresh — подгружаем данные автоматически.
    if (kDebugMode) debugPrint("[BOOT] auth changed");
    _bootstrapLoad();
    _startAutoRefresh();
  }

  Future<T> _retryTransient<T>(Future<T> Function() action, {int maxAttempts = 4}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        final transient =
            msg.contains("HTTP 502") || msg.contains("HTTP 503") || msg.contains("HTTP 504");
        if (!transient || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt * attempt));
      }
    }
    throw lastError!;
  }

  Future<void> ensureDefaultGroup(ApiClient api, {bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        groupsLoading = true;
        groupsError = null;
      });
    }
    final g = await _retryTransient(() => api.getList("/api/groups"));
    final fetched = g.cast<Map<String, dynamic>>();
    if (fetched.isEmpty) {
      final created = await _retryTransient(() => api.post("/api/groups", {"name": "Общее"}));
      fetched.add(created);
    }

    // Если id выбранной группы устарел, переключаем на первую доступную.
    final fetchedIds = fetched.map((x) => x["id"] as String).toSet();
    final nextSelected = (defaultGroupId != null && fetchedIds.contains(defaultGroupId))
        ? defaultGroupId
        : fetched.first["id"] as String;

    if (!mounted) return;
    setState(() {
      groups = fetched;
      defaultGroupId = nextSelected;
      groupsLoading = silent ? groupsLoading : false;
      groupsError = null;
    });
  }

  Future<void> createGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Новая группа"),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "Название группы")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Создать")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final auth = context.read<AuthStore>();
    final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
    final created = await api.post("/api/groups", {"name": name});
    setState(() {
      groups = [...groups, created];
      defaultGroupId = created["id"] as String;
    });
    await loadTasks();
  }

  Future<void> renameGroup() async {
    if (defaultGroupId == null) return;
    final current = groups.firstWhere((g) => g["id"] == defaultGroupId, orElse: () => {"name": ""});
    final ctrl = TextEditingController(text: current["name"] as String? ?? "");
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Переименовать группу"),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Сохранить")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final auth = context.read<AuthStore>();
    final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
    await api.patch("/api/groups/$defaultGroupId", {"name": name});
    await loadTasks();
  }

  Future<void> deleteGroup() async {
    if (defaultGroupId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Подтверждение"),
        content: const Text("Удалить группу и все ее задачи?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Нет")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Да")),
        ],
      ),
    );
    if (confirm != true) return;
    final auth = context.read<AuthStore>();
    final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
    await api.delete("/api/groups/$defaultGroupId");
    defaultGroupId = null;
    await loadTasks();
  }

  Future<void> loadTasks() async {
    return loadTasksWithMode(silent: false);
  }

  Future<void> loadTasksWithMode({required bool silent}) async {
    final auth = context.read<AuthStore>();
    if (kDebugMode) {
      debugPrint("[BOOT] loadTasks token=${auth.token != null} syncService=${syncService != null}");
    }
    if (auth.token == null || syncService == null) return;
    if (!silent) {
      setState(() => loading = true);
    }
    if (silent && mounted) {
      setState(() => _silentRefreshing = true);
    }
    try {
      final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
      try {
        await ensureDefaultGroup(api, silent: silent);
      } catch (e) {
        if (mounted) {
          setState(() {
            groupsLoading = silent ? groupsLoading : false;
            groupsError = e.toString();
          });
          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Не удалось загрузить группы: $e"),
                backgroundColor: Colors.orange.shade800,
              ),
            );
          }
        }
      }
      try {
        await syncService!.syncNow();
      } catch (e) {
        if (mounted && !silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Синхронизация не удалась: $e"),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }
      final list = await localDb.listTasks(filter: filter, q: query);
      final filtered = defaultGroupId == null ? list : list.where((t) => t.groupId == defaultGroupId).toList();
      setState(() => tasks = filtered);
    } finally {
      if (silent && mounted) {
        setState(() => _silentRefreshing = false);
      }
      if (!silent) {
        setState(() => loading = false);
      }
      if (mounted && groups.isEmpty && !silent) {
        Future<void>.delayed(const Duration(seconds: 1), () {
          if (mounted && groups.isEmpty) {
            loadTasks();
          }
        });
      }
    }
  }

  Future<void> addTasksFromInput(String rawInput, {String? commonDescription}) async {
    if (rawInput.trim().isEmpty || syncService == null) return;
    try {
      if (defaultGroupId == null) {
        final auth = context.read<AuthStore>();
        final api = ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);
        await ensureDefaultGroup(api);
      }
      if (defaultGroupId == null) throw Exception("Не удалось создать группу по умолчанию");

      // Массовое создание: "Молоко.Фрукты.Овощи" -> 3 задачи.
      final titles = rawInput
          .split(".")
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
      if (titles.isEmpty) return;
      for (final title in titles) {
        await syncService!.addTaskOffline(
          groupId: defaultGroupId!,
          title: title,
          description: (commonDescription == null || commonDescription.trim().isEmpty)
              ? null
              : commonDescription.trim(),
        );
      }

      await loadTasksWithMode(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка добавления: $e")),
      );
    }
  }

  Future<void> openAddTaskDialog() async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final data = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Новая задача"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: "Название (можно несколько через точку)",
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: "Общее описание (опционально)"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, {
                "titleRaw": titleCtrl.text.trim(),
                "description": descriptionCtrl.text.trim(),
              });
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
    if (data == null) return;
    final titleRaw = data["titleRaw"] ?? "";
    if (titleRaw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Введите название задачи")),
      );
      return;
    }
    await addTasksFromInput(titleRaw, commonDescription: data["description"]);
  }

  Future<void> openSearchDialog() async {
    final ctrl = TextEditingController(text: query);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Поиск задач"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Введите текст"),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ""), child: const Text("Сбросить")),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Искать")),
        ],
      ),
    );
    if (value == null) return;
    setState(() => query = value);
    await loadTasks();
  }

  Future<void> toggle(TaskItem item) async {
    if (syncService == null) return;
    await syncService!.toggleOffline(item);
    await loadTasksWithMode(silent: true);
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
    await loadTasksWithMode(silent: true);
  }

  Future<void> editTask(TaskItem item) async {
    if (syncService == null) return;
    final titleCtrl = TextEditingController(text: item.title);
    final descriptionCtrl = TextEditingController(text: item.description ?? "");

    final formData = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Редактирование задачи"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: "Название"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: "Описание"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, {
                "title": titleCtrl.text.trim(),
                "description": descriptionCtrl.text.trim(),
              });
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
    if (formData == null) return;
    final newTitle = formData["title"] ?? "";
    final newDescription = formData["description"] ?? "";
    if (newTitle.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Название задачи не может быть пустым")),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Подтверждение"),
        content: const Text("Вы уверены? Изменения задачи будут сохранены."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Нет")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Да")),
        ],
      ),
    );
    if (confirm != true) return;

    await syncService!.updateOffline(
      item,
      title: newTitle,
      description: newDescription.isEmpty ? null : newDescription,
    );
    await loadTasksWithMode(silent: true);
  }

  Future<void> removeCompletedInCurrentGroup() async {
    if (syncService == null || defaultGroupId == null) return;

    final allLocal = await localDb.listTasks(filter: "all", q: "");
    final completedInGroup = allLocal
        .where((t) => t.groupId == defaultGroupId && t.isCompleted && t.deletedAt == null)
        .toList();

    if (completedInGroup.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("В этой группе нет выполненных задач")),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Подтверждение"),
        content: Text("Вы уверены? Будут удалены ${completedInGroup.length} выполненных задач(и)."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Нет")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Да")),
        ],
      ),
    );
    if (confirm != true) return;

    for (final task in completedInGroup) {
      await syncService!.deleteOffline(task);
    }
    await loadTasksWithMode(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Удалено задач: ${completedInGroup.length}")),
    );
  }

  Future<void> refreshNow() async {
    try {
      await loadTasksWithMode(silent: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Список обновлен")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка обновления: $e")),
      );
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || _silentRefreshing) return;
      final auth = context.read<AuthStore>();
      if (auth.token == null || syncService == null) return;
      if (kDebugMode) debugPrint("[AUTO] periodic refresh tick");
      await loadTasksWithMode(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // При возврате в приложение сразу подтягиваем актуальные изменения.
      loadTasksWithMode(silent: true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthStore>();
      auth.addListener(_onAuthChanged);
      await _bootstrapLoad();
      if (!_bootstrapped) {
        // Страховка на случай медленного восстановления сессии.
        Future<void>.delayed(const Duration(milliseconds: 500), _bootstrapLoad);
        Future<void>.delayed(const Duration(seconds: 1), _bootstrapLoad);
      }
    });
  }

  @override
  void dispose() {
    context.read<AuthStore>().removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("To-Do"),
        actions: [
          IconButton(
            tooltip: "Удалить выполненные в группе",
            onPressed: removeCompletedInCurrentGroup,
            icon: const Icon(Icons.delete_sweep),
          ),
          IconButton(
            tooltip: "Обновить",
            onPressed: refreshNow,
            icon: const Icon(Icons.refresh),
          ),
          if (_silentRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: "Группы",
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const GroupsScreen()),
              );
              if (context.mounted) await loadTasks();
            },
            icon: const Icon(Icons.folder_open),
          ),
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
                SizedBox(
                  width: 180,
                  child: groupsLoading
                      ? const InputDecorator(
                          decoration: InputDecoration(labelText: "Группа"),
                          child: SizedBox(
                            height: 24,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          key: ValueKey("group-dd-${groups.length}-$defaultGroupId"),
                          value: defaultGroupId,
                          decoration: InputDecoration(
                            labelText: "Группа",
                            helperText: groupsError != null
                                ? "Ошибка загрузки групп"
                                : (groups.isEmpty ? "Нет групп" : null),
                            helperStyle: TextStyle(
                              color: groupsError != null ? Colors.orange.shade400 : null,
                            ),
                          ),
                          hint: const Text("Нет групп"),
                          items: groups
                              .map((g) => DropdownMenuItem<String>(
                                    value: g["id"] as String,
                                    child: Text(g["name"] as String),
                                  ))
                              .toList(),
                          onChanged: groups.isEmpty
                              ? null
                              : (v) async {
                                  setState(() => defaultGroupId = v);
                                  await loadTasks();
                                },
                        ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: "Управление группой",
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == "create") await createGroup();
                    if (value == "rename") await renameGroup();
                    if (value == "delete") await deleteGroup();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: "create",
                      child: Text("Добавить группу"),
                    ),
                    PopupMenuItem<String>(
                      value: "rename",
                      enabled: defaultGroupId != null,
                      child: const Text("Переименовать группу"),
                    ),
                    PopupMenuItem<String>(
                      value: "delete",
                      enabled: defaultGroupId != null,
                      child: const Text("Удалить группу"),
                    ),
                  ],
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: "Фильтр задач",
                  icon: const Icon(Icons.filter_list),
                  onSelected: (value) async {
                    setState(() => filter = value);
                    await loadTasks();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(value: "all", child: Text("Все")),
                    const PopupMenuItem<String>(value: "active", child: Text("Активные")),
                    const PopupMenuItem<String>(value: "completed", child: Text("Выполненные")),
                  ],
                ),
                IconButton(
                  tooltip: query.isEmpty ? "Поиск" : "Поиск: $query",
                  onPressed: openSearchDialog,
                  icon: Icon(query.isEmpty ? Icons.search : Icons.manage_search),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                query.isEmpty ? "Фильтр: $filterLabel" : "Фильтр: $filterLabel  •  Поиск: $query",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
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
                      if (syncService == null) {
                        setState(() => tasks = reordered);
                        return;
                      }
                      final persisted = await syncService!.reorderOffline(reordered);
                      setState(() => tasks = persisted);
                    await loadTasksWithMode(silent: true);
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
                          subtitle: t.deadline != null ? Text("дедлайн: ${t.deadline}") : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: "Редактировать задачу",
                                onPressed: () => editTask(t),
                                icon: const Icon(Icons.edit),
                              ),
                              IconButton(
                                tooltip: "Удалить задачу",
                                onPressed: () => remove(t),
                                icon: const Icon(Icons.delete),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "Добавить задачу",
        onPressed: openAddTaskDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
