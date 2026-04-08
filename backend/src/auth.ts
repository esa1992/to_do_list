import jwt from "jsonwebtoken";
import { config } from "./config.js";

export type JwtPayload = { userId: string; login: string };

export function signJwt(payload: JwtPayload): string {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: "30d" });
}

export function verifyJwt(token: string): JwtPayload {
  return jwt.verify(token, config.jwtSecret) as JwtPayload;
}
