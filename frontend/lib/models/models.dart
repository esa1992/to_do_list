int _jsonInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.parse(v.toString());
}

class TaskItem {
  final String id;
  final String groupId;
  final String title;
  final String? description;
  final bool isCompleted;
  final String priority;
  final int order;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deadline;

  TaskItem({
    required this.id,
    required this.groupId,
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.priority,
    required this.order,
    required this.updatedAt,
    required this.deletedAt,
    required this.deadline,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json["id"] as String,
        groupId: json["group_id"] as String,
        title: json["title"] as String,
        description: json["description"] as String?,
        isCompleted: json["is_completed"] is bool ? json["is_completed"] as bool : (json["is_completed"] as int) == 1,
        priority: json["priority"] as String,
        order: _jsonInt(json["order"]),
        updatedAt: DateTime.parse((json["updated_at"] ?? DateTime.now().toIso8601String()) as String),
        deletedAt: json["deleted_at"] == null ? null : DateTime.parse(json["deleted_at"] as String),
        deadline: json["deadline"] == null ? null : DateTime.parse(json["deadline"] as String),
      );

  /// Для SQLite локального кэша (0/1).
  Map<String, dynamic> toJson() => {
        "id": id,
        "group_id": groupId,
        "title": title,
        "description": description,
        "is_completed": isCompleted ? 1 : 0,
        "priority": priority,
        "order": order,
        "updated_at": updatedAt.toIso8601String(),
        "deleted_at": deletedAt?.toIso8601String(),
        "deadline": deadline?.toIso8601String(),
      };

  /// Для REST/sync API (boolean, как ожидает backend).
  Map<String, dynamic> toSyncJson() => {
        "id": id,
        "group_id": groupId,
        "title": title,
        "description": description,
        "is_completed": isCompleted,
        "priority": priority,
        "order": order,
        "updated_at": updatedAt.toUtc().toIso8601String(),
        "deleted_at": deletedAt?.toUtc().toIso8601String(),
      };
}
