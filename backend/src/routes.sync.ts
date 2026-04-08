import { Router } from "express";
import { z } from "zod";
import { db } from "./db.js";
import { AuthedRequest } from "./middleware.js";

export const syncRouter = Router();

syncRouter.get("/pull", async (req: AuthedRequest, res) => {
  const since = req.query.since ? new Date(String(req.query.since)) : new Date(0);
  const groups = await db.query(
    "select * from groups where user_id=$1 and id in (select group_id from tasks where updated_at >= $2 or deleted_at >= $2) order by \"order\" asc",
    [req.user!.userId, since.toISOString()]
  );
  const tasks = await db.query(
    "select t.* from tasks t join groups g on g.id=t.group_id where g.user_id=$1 and (t.updated_at >= $2 or t.deleted_at >= $2)",
    [req.user!.userId, since.toISOString()]
  );
  return res.json({ serverTime: new Date().toISOString(), groups: groups.rows, tasks: tasks.rows });
});

syncRouter.post("/push", async (req: AuthedRequest, res) => {
  const parsed = z.object({
    tasks: z.array(
      z.object({
        id: z.string().uuid(),
        group_id: z.string().uuid(),
        title: z.string(),
        description: z.string().nullable().optional(),
        is_completed: z.boolean(),
        priority: z.enum(["low", "medium", "high"]),
        order: z.number().int(),
        updated_at: z.string().datetime(),
        deleted_at: z.string().datetime().nullable().optional()
      })
    )
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  for (const t of parsed.data.tasks) {
    const existing = await db.query(
      "select tasks.* from tasks join groups g on g.id=tasks.group_id where tasks.id=$1 and g.user_id=$2",
      [t.id, req.user!.userId]
    );
    if (!existing.rowCount) {
      await db.query(
        "insert into tasks(id,group_id,title,description,is_completed,priority,\"order\",updated_at,deleted_at) values($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [t.id, t.group_id, t.title, t.description ?? null, t.is_completed, t.priority, t.order, t.updated_at, t.deleted_at ?? null]
      );
      continue;
    }
    const serverUpdatedAt = new Date(existing.rows[0].updated_at).getTime();
    const clientUpdatedAt = new Date(t.updated_at).getTime();
    if (clientUpdatedAt > serverUpdatedAt) {
      await db.query(
        "update tasks set title=$1, description=$2, is_completed=$3, priority=$4, \"order\"=$5, updated_at=$6, deleted_at=$7 where id=$8",
        [t.title, t.description ?? null, t.is_completed, t.priority, t.order, t.updated_at, t.deleted_at ?? null, t.id]
      );
    }
  }
  return res.json({ success: true, strategy: "last-write-wins" });
});
