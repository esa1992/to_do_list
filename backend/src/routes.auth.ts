import { Router } from "express";
import bcrypt from "bcryptjs";
import crypto from "node:crypto";
import { z } from "zod";
import { db } from "./db.js";
import { signJwt } from "./auth.js";

const registerSchema = z.object({
  login: z.string().min(3).max(64),
  password: z.string().min(6).max(128)
});

export const authRouter = Router();

async function issueRefreshToken(userId: string): Promise<string> {
  const raw = crypto.randomBytes(48).toString("hex");
  const tokenHash = await bcrypt.hash(raw, 10);
  const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
  await db.query(
    "insert into refresh_tokens(user_id, token_hash, expires_at) values($1, $2, $3)",
    [userId, tokenHash, expiresAt.toISOString()]
  );
  return raw;
}

authRouter.post("/register", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { login, password } = parsed.data;
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const result = await db.query(
      "insert into users(login, password_hash) values($1, $2) returning id, login",
      [login, passwordHash]
    );
    const user = result.rows[0];
    const token = signJwt({ userId: user.id, login: user.login });
    const refreshToken = await issueRefreshToken(user.id);
    return res.json({ token, refreshToken, user });
  } catch {
    return res.status(409).json({ error: "Login already exists" });
  }
});

authRouter.post("/login", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { login, password } = parsed.data;
  const result = await db.query("select id, login, password_hash from users where login = $1", [login]);
  if (!result.rowCount) return res.status(401).json({ error: "Invalid credentials" });
  const user = result.rows[0];
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return res.status(401).json({ error: "Invalid credentials" });
  const token = signJwt({ userId: user.id, login: user.login });
  const refreshToken = await issueRefreshToken(user.id);
  return res.json({ token, refreshToken, user: { id: user.id, login: user.login } });
});

authRouter.post("/refresh", async (req, res) => {
  const parsed = z.object({ login: z.string(), refreshToken: z.string().min(20) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const userQ = await db.query("select id, login from users where login=$1", [parsed.data.login]);
  if (!userQ.rowCount) return res.status(401).json({ error: "Unauthorized" });
  const user = userQ.rows[0];
  const tokensQ = await db.query(
    "select id, token_hash, expires_at from refresh_tokens where user_id=$1 and revoked_at is null order by created_at desc limit 10",
    [user.id]
  );
  let matchedTokenId: string | null = null;
  for (const rt of tokensQ.rows) {
    if (new Date(rt.expires_at).getTime() < Date.now()) continue;
    // small list, safe for hash compare
    if (await bcrypt.compare(parsed.data.refreshToken, rt.token_hash)) {
      matchedTokenId = rt.id;
      break;
    }
  }
  if (!matchedTokenId) return res.status(401).json({ error: "Invalid refresh token" });
  await db.query("update refresh_tokens set revoked_at=now() where id=$1", [matchedTokenId]);
  const token = signJwt({ userId: user.id, login: user.login });
  const refreshToken = await issueRefreshToken(user.id);
  return res.json({ token, refreshToken });
});

authRouter.post("/logout", async (req, res) => {
  const parsed = z.object({ login: z.string().optional() }).safeParse(req.body ?? {});
  if (parsed.success && parsed.data.login) {
    const userQ = await db.query("select id from users where login=$1", [parsed.data.login]);
    if (userQ.rowCount) {
      await db.query("update refresh_tokens set revoked_at=now() where user_id=$1 and revoked_at is null", [userQ.rows[0].id]);
    }
  }
  return res.json({ success: true });
});
