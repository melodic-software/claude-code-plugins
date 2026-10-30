#!/usr/bin/env bash
# Tests for affected_features.py against throwaway repositories: the glob syntax (`*` stays in one
# path segment, `**` crosses `/`), a project control skill's feature and module matches, a plugin
# control skill's repository-root globs, the notes for no control skill and for nothing matched,
# and --trusted-root refusing a control skill outside it.
# Usage: affected_features.test.sh [script]   (default: the sibling affected_features.py)
# shellcheck disable=SC2016 # fixture Markdown holds backticks, single-quoted on purpose
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AFFECTED="${1:-$SCRIPT_DIR/affected_features.py}"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name fixture
git config --global user.email fixture@example.invalid
git config --global init.defaultBranch main

# commit_all <repo> <message>
commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}
# write <path> <text>: create parent folders and write the text.
write() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$2" >"$1"
}
# run <args...>: exit code in $rc, stderr in $err, affected.json under $T/out.
run() {
  rc=0
  rm -rf "$T/out"
  python3 -I "$AFFECTED" --out "$T/out" "$@" 2>"$T/stderr" >/dev/null || rc=$?
  err="$(cat "$T/stderr")"
}
# expect <name> <python expression over d, the parsed affected.json, and arg> <expected repr> [arg]
expect() {
  local got
  got="$(python3 -I -c 'import json, os, sys; d = json.load(open(sys.argv[1])); arg = sys.argv[3]; print(repr(eval(sys.argv[2])))' "$T/out/affected.json" "$2" "${4:-}" 2>&1)"
  if [[ "$rc" == 0 && "$got" == "$3" ]]; then pass "$1"; else fail "$1" "rc=$rc got=$got want=$3 $err"; fi
}

feature() {
  printf '# %s\n\n## Parts\n\n- one\n\n## Sub-features\n\n%s\n\n## Entry points\n\n%s\n\n## Reset\n\nnone\n\n## Drive\n\n- go\n\n## Gotchas\n\nnone\n' "$1" "$2" "$3"
}

# --- a project control skill: a feature, a module and a file nothing indexes ---------------------
P="$T/project"
S="$P/.claude/skills/control-shop"
write "$S/SKILL.md" '# control-shop

## Launch

`python3 shop/serve.py`

- Cart | features/cart/README.md | entry points: 2 | sources: shop/cart/**
- Billing | features/billing/README.md | entry points: 1 | sources: shop/billing/**

```text
- Fenced | features/fenced/README.md | entry points: 1 | sources: shop/**
```
'
write "$S/features/cart/README.md" "$(feature Cart none '- the cart page: driven
- `POST /api/cart`: not driven: needs a seeded basket')"
write "$S/features/billing/README.md" "$(feature Billing '- Export | features/billing/export/README.md | entry points: 1 | sources: shop/billing/export.py' '- the export button: driven')"
write "$S/features/billing/export/README.md" "$(feature Export none '- the export button: driven')"
write "$P/shop/cart/basket.py" 'x = 1
'
write "$P/shop/billing/export.py" 'x = 1
'
write "$P/shop/billing/tax.py" 'x = 1
'
write "$P/README.md" 'shop
'
git init -q "$P"
commit_all "$P" base
BASE="$(git -C "$P" rev-parse HEAD)"
write "$P/shop/cart/basket.py" 'x = 2
'
write "$P/shop/billing/export.py" 'x = 2
'
write "$P/shop/billing/tax.py" 'x = 2
'
write "$P/README.md" 'shop, edited
'
git -C "$P" mv shop/cart/basket.py shop/cart/bag.py
commit_all "$P" change

PROJECT=(--repo "$P" --base "$BASE" --app shop --hub "$S/SKILL.md" --source project
  --control-skill 'control-shop (project: .claude/skills/control-shop/SKILL.md)')
run "${PROJECT[@]}"
expect "a project control skill maps files to its features" \
  '[(f["id"], f["matched_files"]) for f in d["features"]]' \
  "[('cart', ['shop/cart/bag.py', 'shop/cart/basket.py']), ('billing/export', ['shop/billing/export.py'])]"
expect "a matched module line maps to the sub-feature, never the module" \
  '[f["id"] for f in d["features"] if f["id"] == "billing"]' "[]"
expect "a file a module matches but no sub-feature does is unmatched" \
  'd["unmatched_files"]' "['README.md', 'shop/billing/tax.py']"
expect "entry points carry their driven marker and reason" \
  'd["features"][0]["entry_points"]' \
  "[{'text': 'the cart page', 'driven': True, 'reason': None}, {'text': '\`POST /api/cart\`', 'driven': False, 'reason': 'needs a seeded basket'}]"
expect "the source, note and trusted root" '(d["source"], d["note"], d["trusted_root"])' \
  "('project', None, None)"

run "${PROJECT[@]}" --head "$BASE"
expect "a control skill present that matched nothing says so" \
  '(d["features"], d["note"])' "([], 'control skill present, 0 files unmatched')"

# --- no control skill -----------------------------------------------------------------------
run --repo "$P" --base "$BASE" --app shop
expect "no control skill writes empty features with a note" \
  '(d["control_skill"], d["source"], d["features"], len(d["unmatched_files"]), d["note"])' \
  "(None, 'none', [], 5, 'No control skill: nothing matched')"

# --- a plugin control skill: globs from the repository root ------------------------------------
R="$T/repo"
write "$R/plugins/a/SKILL.md" 'a
'
write "$R/plugins/a/b/SKILL.md" 'b
'
write "$R/plugins/x" 'x
'
write "$R/plugins/a/b/x" 'x
'
git init -q "$R"
commit_all "$R" base
RBASE="$(git -C "$R" rev-parse HEAD)"
for f in plugins/a/SKILL.md plugins/a/b/SKILL.md plugins/x plugins/a/b/x; do
  printf 'changed\n' >>"$R/$f"
done
commit_all "$R" change
PL="$T/plugin-cache/repo-tools/skills/control-repo"
write "$PL/SKILL.md" '# control-repo

- Skills | features/skills/README.md | entry points: 1 | sources: plugins/*/SKILL.md
- Xs | features/xs/README.md | entry points: 1 | sources: plugins/**/x
'
write "$PL/features/skills/README.md" "$(feature Skills none '- a skill: driven')"
write "$PL/features/xs/README.md" "$(feature Xs none '- an x: driven')"
PLUGIN=(--repo "$R" --base "$RBASE" --app repo --hub "$PL/SKILL.md" --source plugin
  --control-skill 'repo-tools:control-repo (plugin: skills/control-repo/SKILL.md)')
run "${PLUGIN[@]}"
expect "plugins/*/SKILL.md does not match plugins/a/b/SKILL.md" \
  '[f["matched_files"] for f in d["features"] if f["id"] == "skills"]' "[['plugins/a/SKILL.md']]"
expect "plugins/**/x matches nested paths and zero folders" \
  '[f["matched_files"] for f in d["features"] if f["id"] == "xs"]' "[['plugins/a/b/x', 'plugins/x']]"
expect "the nested SKILL.md is unmatched" 'd["unmatched_files"]' "['plugins/a/b/SKILL.md']"

# --- --trusted-root ---------------------------------------------------------------------------
run "${PLUGIN[@]}" --trusted-root "$R"
if [[ "$rc" == 1 && "$err" == *"outside --trusted-root"* && ! -e "$T/out/affected.json" ]]; then
  pass "a control skill outside --trusted-root is refused"
else
  fail "a control skill outside --trusted-root is refused" "rc=$rc: $err"
fi

run "${PROJECT[@]}" --trusted-root "$P"
expect "a control skill inside --trusted-root is used and the root recorded" \
  '(len(d["features"]), d["trusted_root"] == os.path.realpath(arg))' "(2, True)" "$P"

# --- --project-dir: globs resolve against the project folder -----------------------------------
run "${PROJECT[@]}" --project-dir "$P/shop"
expect "globs resolve against --project-dir, not the repository root" \
  '([f["id"] for f in d["features"]], d["note"])' "([], 'control skill present, 5 files unmatched')"

if ((FAILED)); then
  printf '%d failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all passed\n'
