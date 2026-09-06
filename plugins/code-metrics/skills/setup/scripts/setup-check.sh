#!/usr/bin/env bash
# /code-metrics:setup check: inspect and verify, write nothing.
#
#   setup-check.sh [--repo-root <dir>] [--home <dir>]
#
# Prints a PASS/FAIL/WARN/INFO table: the interpreter, each configuration
# layer (present or absent; parseable in the YAML subset; the team file's
# tracked-file guard), the resolved references with the layer that supplied
# each, every collector adapter's probe (a version, or `missing` with its
# install hint), and any resolver warnings. Exit 0 when no row is FAIL, 1
# when one is; 2 on a usage or environment error. Nothing is installed and
# nothing is written.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
SCRIPTS="$PLUGIN_ROOT/scripts"

REPO_ROOT=""
HOME_DIR="${CODE_METRICS_HOME:-${HOME:-/}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo-root)
    [[ $# -ge 2 ]] || {
      echo "setup-check.sh: --repo-root needs a value" >&2
      exit 2
    }
    REPO_ROOT="$2"
    shift 2
    ;;
  --home)
    [[ $# -ge 2 ]] || {
      echo "setup-check.sh: --home needs a value" >&2
      exit 2
    }
    HOME_DIR="$2"
    shift 2
    ;;
  --help | -h)
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 0
    ;;
  *)
    echo "setup-check.sh: unknown argument $1" >&2
    exit 2
    ;;
  esac
done
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || pwd)"
fi

FAILS=0
row() {
  # row <status> <subject> <detail>
  [[ "$1" == "FAIL" ]] && FAILS=$((FAILS + 1))
  printf '%-4s  %-28s  %s\n' "$1" "$2" "$3"
}

# shellcheck source=../../../scripts/python-resolve.sh
source "$SCRIPTS/python-resolve.sh"
if cm_resolve_python; then
  row PASS "python" "$("${PY[@]}" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])') (floor $CM_PYTHON_FLOOR) via ${PY[*]}"
else
  row FAIL "python" "no interpreter at or above ${CM_PYTHON_FLOOR} (tried python3, python, py -3); required for every skill"
  printf '\n%d FAIL\n' "$FAILS"
  exit 1
fi

# ---- layers ------------------------------------------------------------------
check_layer() {
  # check_layer <name> <path> <expect-tracked: yes|no|n/a>
  local name="$1" path="$2" tracked="$3" err
  if [[ ! -f "$path" ]]; then
    row INFO "layer $name" "absent ($path); the plugin runs on the layers that exist, or the bundled defaults"
    return
  fi
  if err="$("${PY[@]}" "$SCRIPTS/yaml_subset.py" "$path" 2>&1 >/dev/null)"; then
    row PASS "layer $name" "$path parses in the YAML subset"
  else
    row FAIL "layer $name" "$path is outside the YAML subset: ${err#*: }"
    return
  fi
  if [[ "$tracked" == "yes" ]] && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local rel ignore
    rel="${path#"$REPO_ROOT"/}"
    if ignore="$(git -C "$REPO_ROOT" check-ignore -v "$rel" 2>/dev/null)"; then
      row FAIL "layer $name tracked" "the team file is ignored by ${ignore%%:*}; a team layer must be committed to reach the team"
    elif git -C "$REPO_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      row PASS "layer $name tracked" "committed (git ls-files sees it)"
    else
      row WARN "layer $name tracked" "written but untracked: commit it to share with the team"
    fi
  elif [[ "$tracked" == "no" ]] && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local rel
    rel="${path#"$REPO_ROOT"/}"
    if git -C "$REPO_ROOT" check-ignore -q "$rel" 2>/dev/null; then
      row PASS "layer $name ignored" "the local overlay is gitignored"
    else
      row WARN "layer $name ignored" "the local overlay is NOT gitignored; recommended consumer .gitignore line: .claude/**/*.local.* (the plugin never edits your .gitignore)"
    fi
  fi
}
check_layer "user-global" "$HOME_DIR/.claude/code-metrics.yaml" n/a
check_layer "team" "$REPO_ROOT/.claude/code-metrics.yaml" yes
check_layer "local" "$REPO_ROOT/.claude/code-metrics.local.yaml" no
for eco in "$REPO_ROOT"/.claude/ecosystems/*.yaml; do
  [[ -f "$eco" ]] || continue
  if err="$("${PY[@]}" "$SCRIPTS/yaml_subset.py" "$eco" 2>&1 >/dev/null)"; then
    row PASS "ecosystem ${eco##*/}" "parses; its globs and enabled key are honoured for lane detection"
  else
    row FAIL "ecosystem ${eco##*/}" "outside the YAML subset: ${err#*: }"
  fi
done

# ---- resolved references -----------------------------------------------------
RESOLVED="$(mktemp)"
trap 'rm -f "$RESOLVED" "$RESOLVED.err"' EXIT
if "${PY[@]}" "$SCRIPTS/resolve-config.py" --ladder "$SCRIPTS/collector-ladder.tsv" --home "$HOME_DIR" --repo-root "$REPO_ROOT" >"$RESOLVED" 2>"$RESOLVED.err"; then
  while IFS=$'\t' read -r measure reference provenance layer; do
    row INFO "reference $measure" "$reference (layer: $layer) $provenance"
  done < <("${PY[@]}" -c '
import json, sys
d = json.load(open(sys.argv[1]))
for t in d["thresholds"]:
    p = d["_provenance"].get(t["config_key"], {})
    v = p.get("value")
    print("\t".join([t["measure"], "null" if v is None else str(v), t.get("provenance", ""), p.get("layer", "bundled default")]))
' "$RESOLVED")
  while IFS= read -r warning; do
    [[ -n "$warning" ]] && row WARN "config" "${warning#resolve-config.py: warning: }"
  done <"$RESOLVED.err"
else
  row FAIL "config" "$(tr '\n' ' ' <"$RESOLVED.err")"
fi
rm -f "$RESOLVED.err"

# ---- collectors --------------------------------------------------------------
for adapter in "$SCRIPTS"/collectors/*.py; do
  name="${adapter##*/}"
  name="${name%.py}"
  [[ "$name" == test_* ]] && continue
  if version="$("${PY[@]}" "$adapter" probe 2>/dev/null)"; then
    row PASS "collector $name" "$version"
  else
    hint="$("${PY[@]}" "$adapter" install_hint 2>/dev/null || true)"
    row INFO "collector $name" "missing; ${hint:-no install hint} (optional: the lane reports unavailable without it)"
  fi
done

printf '\n%d FAIL\n' "$FAILS"
[[ $FAILS -eq 0 ]]
