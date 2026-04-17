import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../core/api_client.dart";
import "../core/auth_store.dart";

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> groups = [];
  bool loading = true;
  String? error;

  ApiClient _api(AuthStore auth) =>
      ApiClient(baseUrl: auth.baseUrl, token: auth.token, proxySettings: auth.proxy);

  Future<void> load() async {
    final auth = context.read<AuthStore>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await _api(auth).getList("/api/groups");
      setState(() => groups = list.cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persistOrder() async {
    final auth = context.read<AuthStore>();
    final ids = groups.map((g) => g["id"] as String).toList();
    try {
      await _api(auth).post("/api/groups/reorder", {"ids": ids});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Не удалось сохранить порядок: $e")),
      );
      await load();
    }
  }

  Future<void> createGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Новая группа"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Название"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Создать")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final auth = context.read<AuthStore>();
    try {
      final created = await _api(auth).post("/api/groups", {"name": name});
      setState(() => groups = [...groups, created]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> renameGroup(Map<String, dynamic> g) async {
    final ctrl = TextEditingController(text: g["name"] as String? ?? "");
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Переименовать"),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Сохранить")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final auth = context.read<AuthStore>();
    try {
      await _api(auth).patch("/api/groups/${g["id"]}", {"name": name});
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> deleteGroup(Map<String, dynamic> g) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Подтверждение"),
        content: const Text("Удалить группу и все её задачи?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Нет")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Да")),
        ],
      ),
    );
    if (confirm != true) return;
    final auth = context.read<AuthStore>();
    try {
      await _api(auth).delete("/api/groups/${g["id"]}");
      setState(() => groups = groups.where((x) => x["id"] != g["id"]).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Группы"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: loading ? null : createGroup,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(error!, textAlign: TextAlign.center)))
              : groups.isEmpty
                  ? const Center(child: Text("Нет групп. Нажмите + чтобы создать."))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: groups.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (oldIndex < newIndex) newIndex -= 1;
                        final next = [...groups];
                        final item = next.removeAt(oldIndex);
                        next.insert(newIndex, item);
                        setState(() => groups = next);
                        await persistOrder();
                      },
                      itemBuilder: (context, index) {
                        final g = groups[index];
                        final id = g["id"] as String;
                        final name = g["name"] as String? ?? "";
                        return ListTile(
                          key: ValueKey(id),
                          leading: const Icon(Icons.drag_handle),
                          title: Text(name),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == "rename") renameGroup(g);
                              if (v == "delete") deleteGroup(g);
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: "rename", child: Text("Переименовать")),
                              PopupMenuItem(value: "delete", child: Text("Удалить")),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
