#!/usr/bin/env bash
# Seed a repo whose read-through cache class is misleadingly named UserStore.
set -euo pipefail

mkdir -p src/cache src/routes
cat >src/cache/user-store.ts <<'TS'
import { UsersApi, User } from "../users-api";

// Read-through cache in front of the users API. It never owns the data: a miss calls the API,
// and entries expire after ttlMs.
export class UserStore {
  private entries = new Map<string, { user: User; at: number }>();

  constructor(private readonly api: UsersApi, private readonly ttlMs: number) {}

  async get(id: string): Promise<User> {
    const hit = this.entries.get(id);
    if (hit && Date.now() - hit.at < this.ttlMs) return hit.user;
    const user = await this.api.getUser(id);
    this.entries.set(id, { user, at: Date.now() });
    return user;
  }
}
TS
cat >src/users-api.ts <<'TS'
export interface User { id: string; name: string }
export interface UsersApi { getUser(id: string): Promise<User> }
TS
cat >src/routes/me.ts <<'TS'
import { UserStore } from "../cache/user-store";

export function meHandler(store: UserStore) {
  return (id: string) => store.get(id);
}
TS
