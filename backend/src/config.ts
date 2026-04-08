import dotenv from "dotenv";

dotenv.config();

export const config = {
  port: Number(process.env.PORT ?? 8080),
  databaseUrl: process.env.DATABASE_URL ?? "",
  jwtSecret: process.env.JWT_SECRET ?? "",
  corsOrigin: process.env.CORS_ORIGIN ?? "*"
};

if (!config.databaseUrl) throw new Error("DATABASE_URL is required");
if (!config.jwtSecret) throw new Error("JWT_SECRET is required");
