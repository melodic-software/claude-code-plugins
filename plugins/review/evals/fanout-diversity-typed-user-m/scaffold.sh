#!/usr/bin/env bash
# Decoy fixture typed-user, with docs/conventions/review.yaml committed on main so the run reads
# fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch narrows displayName to a SignedInUser and drops its null check. The change is correct:
# headerLabel, the only caller, returns "Sign in" before it calls displayName, and strict
# TypeScript rejects a null argument.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "strict": true,
    "noEmit": true
  },
  "include": ["src"]
}
JSON

cat >src/types.ts <<'TS'
export interface Profile {
  nickname?: string;
  fullName: string;
}

export interface SignedInUser {
  id: string;
  profile: Profile;
}

export interface Session {
  user: SignedInUser | null;
}
TS

cat >src/display-name.ts <<'TS'
import type { SignedInUser } from "./types.js";

export function displayName(user: SignedInUser | null): string {
  if (!user) {
    return "Guest";
  }
  return user.profile.nickname || user.profile.fullName;
}
TS

cat >src/header.ts <<'TS'
import { displayName } from "./display-name.js";
import type { Session } from "./types.js";

export function headerLabel(session: Session): string {
  if (!session.user) {
    return "Sign in";
  }
  return `Hi, ${displayName(session.user)}`;
}
TS

cat >package.json <<'JSON'
{
  "name": "storefront-header",
  "type": "module",
  "private": true,
  "scripts": { "typecheck": "tsc -p ." },
  "devDependencies": { "typescript": "^5.6.0" }
}
JSON

git add .
git commit -q -m "feat: header greets the signed-in visitor by name"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/display-name-type
cat >src/display-name.ts <<'TS'
import type { SignedInUser } from "./types.js";

export function displayName(user: SignedInUser): string {
  return user.profile.nickname || user.profile.fullName;
}
TS
git commit -q -am "refactor: narrow displayName to a signed-in user

headerLabel, the only caller, returns \"Sign in\" before it calls displayName,
and tsconfig.json's strict mode makes the compiler reject a null argument,
so the Guest branch could never run."
