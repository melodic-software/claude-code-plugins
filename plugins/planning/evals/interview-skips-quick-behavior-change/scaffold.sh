#!/usr/bin/env bash
set -euo pipefail

mkdir -p src
cat >src/users.ts <<'TS'
const DEFAULT_PAGE_SIZE = 20;

export interface User {
  id: string;
  name: string;
}

export function listUsers(users: User[], page = 0, pageSize = DEFAULT_PAGE_SIZE): User[] {
  return users.slice(page * pageSize, (page + 1) * pageSize);
}
TS
