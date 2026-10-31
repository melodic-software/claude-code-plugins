#!/usr/bin/env bash
# Commits src/db.ts on main, adds an uncommitted src/users.ts holding an exported doc comment, a step comment, a constraint comment and a narrating comment, and writes the lines file naming all 23 of its lines.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >src/db.ts <<'EOF'
export const db = {
  users: {
    find: (id: string) => ({ id }),
    insert: (_user: { id: string; name: string }) => {},
  },
};
EOF
git add src/db.ts
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add db stub"
cat >src/users.ts <<'EOF'
import { db } from "./db";

/**
 * Loads a user.
 * @param userId - the ID of the user
 */
export async function loadUser(userId: string) {
  return db.users.find(userId);
}

export function importUsers(raw: string) {
  // Step 1: parse input
  const records = raw
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line) => line.split(","));
  // NOT thread-safe; callers serialize imports
  records.sort((a, b) => a[0].localeCompare(b[0]));
  // loop over the records
  for (const record of records) {
    db.users.insert({ id: record[0], name: record[1] });
  }
}
EOF
printf '1\t23\tsrc/users.ts\n' >changed-lines.tsv
