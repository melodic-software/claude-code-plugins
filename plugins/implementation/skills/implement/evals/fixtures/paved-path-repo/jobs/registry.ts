import type { Job } from "./job";
import { cleanupSessions } from "./cleanup-sessions";

export const jobs: Job[] = [cleanupSessions];
