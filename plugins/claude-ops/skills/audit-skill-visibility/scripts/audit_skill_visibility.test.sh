#!/usr/bin/env bash
# Cross-platform contract wrapper for the skill-starvation engine test suite.
set -euo pipefail

# ISOLATION (#2840). The churn tests build throwaway git repositories, and the
# Python subprocess inherits this environment. An exported absolute GIT_DIR
# outranks `git -C` and overrides repository DISCOVERY, so a fixture's
# `git config` would write its throwaway identity into the CALLER's .git/config
# — shared by every worktree of the clone — instead of into the fixture. Cleared
# unconditionally here, before anything spawns git.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the engine. Parse it rather
# than restating the number here.
ENGINE="$SCRIPT_DIR/audit_skill_visibility.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(p) for p in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}

(cd "$SCRIPT_DIR" && "$PYTHON" -m unittest -v test_audit_skill_visibility)

# Contract check: the shipped fixture must resolve every row to not-observable.
# A fresh install is exactly where a naive report libels the fleet as unused, so
# this asserts the honesty floor end-to-end, not just in the unit seam.
FIXTURE="$SCRIPT_DIR/../tests/fixtures/fleet-basic.json"
OUT="$("$PYTHON" "$ENGINE" --fixture "$FIXTURE" --render json)"
TOTAL="$(printf '%s' "$OUT" | "$PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)["skills"]))')"
UNOBS="$(printf '%s' "$OUT" | "$PYTHON" -c 'import json,sys; m=json.load(sys.stdin); print(sum(1 for s in m["skills"] if s["observation"]["value"]=="not-observable"))')"
if [[ "$TOTAL" != "$UNOBS" ]]; then
  echo "FAIL: fresh-install fixture resolved $UNOBS/$TOTAL rows not-observable; expected all" >&2
  exit 1
fi
echo "ok: fresh-install fixture withheld every cold verdict ($UNOBS/$TOTAL)"

# Contract check: --installed resolves ONE entry per plugin, not one per install
# scope. A manifest listing the same plugin at two scopes must not double the
# fleet -- the fleet is the denominator the listing budget is measured against,
# so a doubled fleet roughly doubles the reported overflow.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/plugins/alpha/skills/one" "$WORK/repo/.claude-plugin" "$WORK/cfg"

# A path this fixture EMBEDS -- in the two JSON files and in CLAUDE_PROJECT_DIR
# -- is read verbatim by the engine, while the `--installed` ARGUMENT is
# rewritten to the host's native form on the way in (Git Bash rewrites a POSIX
# argument for a native interpreter; an environment variable and a file's
# contents it leaves alone). Embedding `/tmp/...` therefore hands a native
# Python a path it cannot open, so the marketplace catalog reads empty and the
# fleet resolves to nothing. `cygpath -m` produces the same forward-slash
# spelling the argument arrives in, and is absent (so this is the identity) on
# a host that needs no rewrite.
host_path() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
REPO="$(host_path "$WORK/repo")"

printf -- '---\nname: one\ndescription: "does a thing"\n---\n' \
  >"$WORK/repo/plugins/alpha/skills/one/SKILL.md"
printf '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}\n' \
  >"$WORK/repo/.claude-plugin/marketplace.json"
printf '{"mkt":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
  "$REPO" "$REPO" >"$WORK/cfg/known_marketplaces.json"
printf '{"version":2,"plugins":{"alpha@mkt":[{"scope":"project","version":"1.0.0","installPath":"/nowhere","projectPath":"%s"},{"scope":"user","version":"2.0.0","installPath":"/nowhere-else"}]}}\n' \
  "$REPO" >"$WORK/cfg/installed_plugins.json"

# `projectPath` and CLAUDE_PROJECT_DIR are compared to each other, so both use
# the one spelling; converting only one turns the project-scope record
# not-applicable and changes what the assertion below measures.
INST="$(CLAUDE_PROJECT_DIR="$REPO" "$PYTHON" "$ENGINE" --installed "$WORK/cfg" --render json)"
read -r ENTRIES PLUGINS SKILLS <<EOF
$(printf '%s' "$INST" | "$PYTHON" -c 'import json,sys; m=json.load(sys.stdin); f=m["fleet"]; print(f["manifest_entries"], f["plugins_resolved"], len(m["skills"]))')
EOF
if [[ "$ENTRIES" != "2" || "$PLUGINS" != "1" || "$SKILLS" != "1" ]]; then
  echo "FAIL: --installed gave entries=$ENTRIES plugins=$PLUGINS skills=$SKILLS; expected 2/1/1" >&2
  exit 1
fi
echo "ok: --installed collapsed $ENTRIES install records to $PLUGINS plugin ($SKILLS skill)"
