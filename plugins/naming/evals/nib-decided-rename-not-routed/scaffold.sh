#!/usr/bin/env bash
# Seed a repo where fetchUser was renamed to loadUser at its definition but three files still use the old name.
set -euo pipefail

mkdir -p src/users src/pages src/components
cat >src/users/api.js <<'JS'
export async function loadUser(id) {
  const res = await fetch(`/api/users/${id}`);
  return res.json();
}
JS
cat >src/pages/profile.js <<'JS'
import { fetchUser } from "../users/api.js";

export async function renderProfile(id) {
  const user = await fetchUser(id);
  return `<h1>${user.name}</h1>`;
}
JS
cat >src/components/header.js <<'JS'
import { fetchUser } from "../users/api.js";

export async function headerGreeting(id) {
  return `Hi, ${(await fetchUser(id)).firstName}`;
}
JS
cat >README.md <<'MD'
# Accounts web

Call `fetchUser(id)` from src/users/api.js to get a user record.
MD
