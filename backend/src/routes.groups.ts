import { Router } from "express";
import { z } from "zod";
import { db } from "./db.js";
import { AuthedRequest } from "./middleware.js";

const groupCreateSchema = z.object({ name: z.string().min(1).max(120) });
const groupUpdateSchema = z.object({ name: z.string().min(1).max(120).optional(), order: z.number().int().optional() });

export const groupsRouter = Router();

groupsRouter.get("/", async (req: AuthedRequest, res) => {
  const rows = await db.query("select * from groups where user_id=$1 order by \"order\" asc", [req.user!.userId]);
  return res.json(rows.rows);
});

groupsRouter.post("/", async (req: AuthedRequest, res) => {
  const parsed = groupCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const orderRes = await db.query("select coalesce(max(\"order\"), -1)+1 as next from groups where user_id=$1", [req.user!.userId]);
  const nextOrder = orderRes.rows[0].next;
  const inserted = await db.query(
    "insert into groups(user_id, name, \"order\") values($1, $2, $3) returning *",
    [req.user!.userId, parsed.data.name, nextOrder]
  );
  return res.status(201).json(inserted.rows[0]);
});

groupsRouter.patch("/:id", async (req: AuthedRequest, res) => {
  const parsed = groupUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const existing = await db.query("select * from groups where id=$1 and user_id=$2", [req.params.id, req.user!.userId]);
  if (!existing.rowCount) return res.status(404).json({ error: "Group not found" });
  const g = existing.rows[0];
  const updated = await db.query(
    "update groups set name=$1, \"order\"=$2 where id=$3 and user_id=$4 returning *",
    [parsed.data.name ?? g.name, parsed.data.order ?? g.order, req.params.id, req.user!.userId]
  );
  return res.json(updated.rows[0]);
});

groupsRouter.delete("/:id", async (req: AuthedRequest, res) => {
  await db.query("delete from groups where id=$1 and user_id=$2", [req.params.id, req.user!.userId]);
  return res.json({ success: true });
});

groupsRouter.post("/reorder", async (req: AuthedRequest, res) => {
  const parsed = z.object({ ids: z.array(z.string().uuid()) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const ids = parsed.data.ids;
  const client = await db.connect();
  try {
    await client.query("begin");
    for (let i = 0; i < ids.length; i++) {
      await client.query("update groups set \"order\"=$1 where id=$2 and user_id=$3", [i, ids[i], req.user!.userId]);
    }
    await client.query("commit");
    return res.json({ success: true });
  } catch (e) {
    await client.query("rollback");
    return res.status(500).json({ error: "Failed to reorder groups" });
  } finally {
    client.release();
  }
});
