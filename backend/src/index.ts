import express from "express";
import cors from "cors";
import { config } from "./config.js";
import { db } from "./db.js";
import { authRouter } from "./routes.auth.js";
import { requireAuth } from "./middleware.js";
import { groupsRouter } from "./routes.groups.js";
import { tasksRouter } from "./routes.tasks.js";
import { syncRouter } from "./routes.sync.js";

const app = express();
app.use(cors({ origin: config.corsOrigin === "*" ? true : config.corsOrigin }));
app.use(express.json({ limit: "2mb" }));

app.get("/health", async (_req, res) => {
  await db.query("select 1");
  res.json({ ok: true });
});

app.use("/api/auth", authRouter);
app.use("/api/groups", requireAuth, groupsRouter);
app.use("/api/tasks", requireAuth, tasksRouter);
app.use("/api/sync", requireAuth, syncRouter);

app.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`API running on http://localhost:${config.port}`);
});
