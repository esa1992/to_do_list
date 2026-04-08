import "package:path/path.dart";
import "package:sqflite/sqflite.dart";
import "../models/models.dart";

class LocalDb {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), "todo_local.db");
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, _) async {
        await d.execute("""
        create table tasks (
          id text primary key,
          group_id text not null,
          title text not null,
          description text null,
          is_completed integer not null,
          priority text not null,
          "order" integer not null,
          updated_at text not null,
          deleted_at text null,
          deadline text null
        );
        """);
        await d.execute("""
        create table pending_ops (
          id integer primary key autoincrement,
          op_type text not null,
          payload text not null,
          created_at text not null
        );
        """);
      },
    );
    return _db!;
  }

  Future<void> upsertTask(TaskItem task) async {
    final d = await db;
    await d.insert("tasks", task.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TaskItem>> listTasks({required String filter, required String q}) async {
    final d = await db;
    var where = "deleted_at is null";
    final args = <Object?>[];
    if (filter == "active") where += " and is_completed = 0";
    if (filter == "completed") where += " and is_completed = 1";
    if (q.isNotEmpty) {
      where += " and (title like ? or coalesce(description, '') like ?)";
      args.add("%$q%");
      args.add("%$q%");
    }
    final rows = await d.query("tasks", where: where, whereArgs: args, orderBy: "\"order\" asc");
    return rows.map((r) => TaskItem.fromJson(r)).toList();
  }

  Future<void> enqueue(String opType, String payload) async {
    final d = await db;
    await d.insert("pending_ops", {
      "op_type": opType,
      "payload": payload,
      "created_at": DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> listOps() async {
    final d = await db;
    return d.query("pending_ops", orderBy: "id asc");
  }

  Future<void> deleteOp(int id) async {
    final d = await db;
    await d.delete("pending_ops", where: "id = ?", whereArgs: [id]);
  }
}
