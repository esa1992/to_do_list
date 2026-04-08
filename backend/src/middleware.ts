import { NextFunction, Request, Response } from "express";
import { verifyJwt } from "./auth.js";

export type AuthedRequest = Request & { user?: { userId: string; login: string } };

export function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });
  const token = authHeader.replace("Bearer ", "");
  try {
    req.user = verifyJwt(token);
    next();
  } catch {
    return res.status(401).json({ error: "Invalid token" });
  }
}
