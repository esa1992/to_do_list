import { Pool } from "pg";
import { config } from "./config.js";

export const db = new Pool({
  connectionString: config.databaseUrl,
  ssl: config.databaseUrl.includes("localhost") ? false : { rejectUnauthorized: false }
});
