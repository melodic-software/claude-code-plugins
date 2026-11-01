#!/usr/bin/env bash
# Scaffold of guard-removal-null-user, with docs/conventions/review.yaml committed on main so the
# run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# main returns "Guest" for a missing user or profile; the branch removes that check on the
# commit message's claim that every caller passes a signed-in user, which renderHeader contradicts.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >src/display-name.js <<'JS'
export function displayName(user) {
  if (!user || !user.profile) {
    return "Guest";
  }
  return user.profile.nickname || user.profile.fullName;
}
JS

cat >src/header.js <<'JS'
import { displayName } from "./display-name.js";

// session.user stays null until the visitor signs in.
export function renderHeader(session) {
  return `<span class="who">${displayName(session.user)}</span>`;
}
JS

cat >package.json <<'JSON'
{ "name": "storefront-header", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: header shows the visitor's display name"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/display-name
cat >src/display-name.js <<'JS'
export function displayName(user) {
  return user.profile.nickname || user.profile.fullName;
}
JS
git commit -q -am "refactor: drop defensive check in displayName

Every caller passes a signed-in user, so the branch was dead code."
