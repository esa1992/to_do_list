import { Router } from "express";
import { z } from "zod";
import { db } from "./db.js";
import { AuthedRequest } from "./middleware.js";

const taskSchema = z.object({
  groupId: z.string().uuid(),
  title: z.string().min(1).max(300),
  description: z.string().max(5000).optional(),
  priority: z.enum(["low", "medium", "high"]).default("low"),
  deadline: z.string().datetime().optional()
});

const updateTaskSchema = z.object({
  title: z.string().min(1).max(300).optional(),
  description: z.string().max(5000).nullable().optional(),
  isCompleted: z.boolean().optional(),
  priority: z.enum(["low", "medium", "high"]).optional(),
  deadline: z.string().datetime().nullable().optional(),
  order: z.number().int().optional()
});

export const tasksRouter = Router();

async function logTaskHistory(taskId: string, action: string, oldValue: unknown, newValue: unknown, userId: string) {
  await db.query(
    "insert into task_history(task_id, action_type, old_value, new_value, changed_by) values($1, $2, $3, $4, $5)",
    [taskId, action, oldValue ? JSON.stringify(oldValue) : null, newValue ? JSON.stringify(newValue) : null, userId]
  );
}

tasksRouter.get("/", async (req: AuthedRequest, res) => {
  const groupId = req.query.groupId as string | undefined;
  const q = (req.query.q as string | undefined) ?? "";
  const filter = (req.query.filter as string | undefined) ?? "all";
  const values: unknown[] = [req.user!.userId];
  let where = "g.user_id = $1 and t.deleted_at is null";
  if (groupId) {
    values.push(groupId);
    where += ` and t.group_id = $${values.length}`;
  }
  if (q) {
    values.push(`%${q}%`);
    where += ` and (t.title ilike $${values.length} or coalesce(t.description,'') ilike $${values.length})`;
  }
  if (filter === "active") where += " and t.is_completed=false";
  if (filter === "completed") where += " and t.is_completed=true";

  const rows = await db.query(
    `select t.* from tasks t join groups g on g.id=t.group_id where ${where} order by t."order" asc`,
    values
  );
  return res.json(rows.rows);
});

tasksRouter.post("/", async (req: AuthedRequest, res) => {
  const parsed = taskSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const groupCheck = await db.query("select id from groups where id=$1 and user_id=$2", [parsed.data.groupId, req.user!.userId]);
  if (!groupCheck.rowCount) return res.status(404).json({ error: "Group not found" });
  const orderRes = await db.query("select coalesce(max(\"order\"), -1)+1 as next from tasks where group_id=$1 and deleted_at is null", [parsed.data.groupId]);
  const inserted = await db.query(
    "insert into tasks(group_id,title,description,priority,deadline,\"order\") values($1,$2,$3,$4,$5,$6) returning *",
    [parsed.data.groupId, parsed.data.title, parsed.data.description ?? null, parsed.data.priority, parsed.data.deadline ?? null, orderRes.rows[0].next]
  );
  await logTaskHistory(inserted.rows[0].id, "create", null, inserted.rows[0], req.user!.userId);
  return res.status(201).json(inserted.rows[0]);
});

tasksRouter.post("/bulk", async (req: AuthedRequest, res) => {
  const parsed = z.object({ groupId: z.string().uuid(), titlesRaw: z.string().min(1), description: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const titles = parsed.data.titlesRaw.split(".").map((x) => x.trim()).filter(Boolean);
  const created: unknown[] = [];
  for (const title of titles) {
    const orderRes = await db.query("select coalesce(max(\"order\"), -1)+1 as next from tasks where group_id=$1 and deleted_at is null", [parsed.data.groupId]);
    const inserted = await db.query(
      "insert into tasks(group_id,title,description,priority,\"order\") values($1,$2,$3,'low',$4) returning *",
      [parsed.data.groupId, title, parsed.data.description ?? null, orderRes.rows[0].next]
    );
    await logTaskHistory(inserted.rows[0].id, "create", null, inserted.rows[0], req.user!.userId);
    created.push(inserted.rows[0]);
  }
  return res.status(201).json(created);
});

tasksRouter.patch("/:id", async (req: AuthedRequest, res) => {
  const parsed = updateTaskSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const existingQ = await db.query(
    "select t.* from tasks t join groups g on g.id=t.group_id where t.id=$1 and g.user_id=$2 and t.deleted_at is null",
    [req.params.id, req.user!.userId]
  );
  if (!existingQ.rowCount) return res.status(404).json({ error: "Task not found" });
  const oldTask = existingQ.rows[0];
  const newTask = {
    title: parsed.data.title ?? oldTask.title,
    description: parsed.data.description === undefined ? oldTask.description : parsed.data.description,
    is_completed: parsed.data.isCompleted ?? oldTask.is_completed,
    priority: parsed.data.priority ?? oldTask.priority,
    deadline: parsed.data.deadline === undefined ? oldTask.deadline : parsed.data.deadline,
    order: parsed.data.order ?? oldTask.order
  };
  const updated = await db.query(
    "update tasks set title=$1, description=$2, is_completed=$3, priority=$4, deadline=$5, \"order\"=$6, updated_at=now() where id=$7 returning *",
    [newTask.title, newTask.description, newTask.is_completed, newTask.priority, newTask.deadline, newTask.order, req.params.id]
  );
  const action = parsed.data.isCompleted !== undefined ? "complete" : (parsed.data.order !== undefined ? "reorder" : "update");
  await logTaskHistory(req.params.id, action, oldTask, updated.rows[0], req.user!.userId);
  return res.json(updated.rows[0]);
});

tasksRouter.delete("/:id", async (req: AuthedRequest, res) => {
  const existingQ = await db.query(
    "select t.* from tasks t join groups g on g.id=t.group_id where t.id=$1 and g.user_id=$2 and t.deleted_at is null",
    [req.params.id, req.user!.userId]
  );
  if (!existingQ.rowCount) return res.status(404).json({ error: "Task not found" });
  await db.query("update tasks set deleted_at=now(), updated_at=now() where id=$1", [req.params.id]);
  await logTaskHistory(req.params.id, "delete", existingQ.rows[0], null, req.user!.userId);
  return res.json({ success: true });
});

tasksRouter.post("/reorder", async (req: AuthedRequest, res) => {
  const parsed = z.object({ ids: z.array(z.string().uuid()) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const client = await db.connect();
  try {
    await client.query("begin");
    for (let i = 0; i < parsed.data.ids.length; i++) {
      await client.query(
        "update tasks set \"order\"=$1, updated_at=now() where id=$2 and group_id in (select id from groups where user_id=$3)",
        [i, parsed.data.ids[i], req.user!.userId]
      );
      await client.query(
        "insert into task_history(task_id, action_type, old_value, new_value, changed_by) values($1,'reorder',null,jsonb_build_object('order',$2),$3)",
        [parsed.data.ids[i], i, req.user!.userId]
      );
    }
    await client.query("commit");
    return res.json({ success: true });
  } catch {
    await client.query("rollback");
    return res.status(500).json({ error: "Reorder failed" });
  } finally {
    client.release();
  }
});

tasksRouter.get("/:id/history", async (req: AuthedRequest, res) => {
  const rows = await db.query(
    "select h.* from task_history h join tasks t on t.id=h.task_id join groups g on g.id=t.group_id where h.task_id=$1 and g.user_id=$2 order by h.changed_at desc",
    [req.params.id, req.user!.userId]
  );
  return res.json(rows.rows);
});

tasksRouter.post("/:id/rollback", async (req: AuthedRequest, res) => {
  const parsed = z.object({ historyId: z.string().uuid() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const history = await db.query(
    "select * from task_history where id=$1 and task_id=$2 order by changed_at desc limit 1",
    [parsed.data.historyId, req.params.id]
  );
  if (!history.rowCount) return res.status(404).json({ error: "History event not found" });
  const oldValue = history.rows[0].old_value;
  if (!oldValue) return res.status(400).json({ error: "Rollback unavailable for this event" });
  const updated = await db.query(
    "update tasks set title=$1, description=$2, is_completed=$3, priority=$4, \"order\"=$5, updated_at=now() where id=$6 returning *",
    [oldValue.title, oldValue.description, oldValue.is_completed, oldValue.priority, oldValue.order, req.params.id]
  );
  await logTaskHistory(req.params.id, "update", null, updated.rows[0], req.user!.userId);
  return res.json(updated.rows[0]);
});
