import type { Job } from "./job";
import { withRetry } from "./retry";
import { db } from "../lib/db";

export const cleanupSessions: Job = {
  name: "cleanup-sessions",
  schedule: "0 3 * * *",
  run: withRetry(async () => {
    await db.none("delete from sessions where expires_at < now()");
  }),
};
