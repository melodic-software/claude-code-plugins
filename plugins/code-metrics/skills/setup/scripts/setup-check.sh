#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
SCRIPTS="$PLUGIN_ROOT/scripts"

usage() {
  cat <<'EOF'
/code-metrics:setup check: inspect and verify, write nothing.

  setup-check.sh [--repo-root <dir>] [--home <dir>] [--user-file <f>]

--user-file takes the config_file userConfig option's value, the file that
holds the userConfig layer; empty or unsubstituted means unset.

Prints a PASS/FAIL/WARN/INFO table: the interpreter, each configuration
layer (present or absent; parseable in the YAML subset; the team file's
tracked-file guard), each old file the dual-read window still reads and its
new location, the resolved references with the layer that supplied each,
every collector adapter (a probe, then one measure run on a bundled fixture:
PASS with the version and the measure, FAIL when the probe passes and the
measure does not run, WARN when no fixture can exercise it, or `missing`
with its install hint), and any resolver warnings. Exit 0 when no row is
FAIL, 1 when one is; 2 on a usage or environment error. Nothing is installed
and nothing is written outside a temporary directory.
EOF
}

REPO_ROOT=""
HOME_DIR="${CODE_METRICS_HOME:-${HOME:-/}}"
USER_OPTION="${CODE_METRICS_USER_FILE:-}"
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
  --user-file)
    [[ $# -ge 2 ]] || {
      echo "setup-check.sh: --user-file needs a value" >&2
      exit 2
    }
    USER_OPTION="$2"
    shift 2
    ;;
  --help | -h)
    usage
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
  [[ "$1" == "FAIL" ]] && FAILS=$((FAILS + 1))
  printf '%-4s  %-28s  %s\n' "$1" "$2" "$3"
}

# shellcheck source=../../../scripts/python-resolve.sh
source "$SCRIPTS/python-resolve.sh"
if cm_resolve_python; then
  row PASS "python" "$("${PY[@]}" -I -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])') (floor $CM_PYTHON_FLOOR) via ${CM_PY_NATIVE[*]}"
else
  row FAIL "python" "no interpreter at or above ${CM_PYTHON_FLOOR} (tried python3, python, py -3); required for every skill"
  printf '\n%d FAIL\n' "$FAILS"
  exit 1
fi

check_layer() {
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
  case "$tracked" in
  yes | no) ;;
  *) return 0 ;;
  esac
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local rel ignore
  rel="${path#"$REPO_ROOT"/}"
  if [[ "$tracked" == "yes" ]]; then
    if ignore="$(git -C "$REPO_ROOT" check-ignore -v "$rel" 2>/dev/null)"; then
      row FAIL "layer $name tracked" "the team file is ignored by ${ignore%%:*}; a team layer must be committed to reach the team"
    elif git -C "$REPO_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      row PASS "layer $name tracked" "committed (git ls-files sees it)"
    else
      row WARN "layer $name tracked" "written but untracked: commit it to share with the team"
    fi
  elif git -C "$REPO_ROOT" check-ignore -q "$rel" 2>/dev/null; then
    row PASS "layer $name ignored" "the personal override is gitignored"
  else
    local line="docs/conventions/**/*.local.*"
    [[ "$rel" == .claude/* ]] && line=".claude/**/*.local.*"
    row WARN "layer $name ignored" "the personal override is NOT gitignored; recommended consumer .gitignore line: $line (the plugin never edits your .gitignore)"
  fi
}
parses() {
  "${PY[@]}" "$SCRIPTS/yaml_subset.py" "$1" >/dev/null 2>&1
}
dual_read_rows() {
  local name="$1" location="$2" what="$3" tracked="$4" old="$5" new="$6" where="$7"
  if [[ -f "$old" && -n "$new" && -f "$new" && ! "$old" -ef "$new" ]]; then
    if parses "$new"; then
      row WARN "$location" "$old is the old $what and is not read because $new exists; delete it once its keys are there"
      check_layer "$name" "$new" "$tracked"
    else
      row WARN "$location" "$old is the old $what, still read because $new is outside the YAML subset; fix $new, then delete the old file"
      check_layer "$name" "$old" "$tracked"
      check_layer "$name" "$new" "$tracked"
    fi
  elif [[ -f "$old" && ! "$old" -ef "$new" ]]; then
    row WARN "$location" "$old is the old $what, still read during the dual-read window; /code-metrics:setup apply --copy-old copies its keys to $where"
    check_layer "$name" "$old" "$tracked"
  elif [[ -n "$new" ]]; then
    check_layer "$name" "$new" "$tracked"
  fi
}
old_user="$HOME_DIR/.claude/code-metrics.yaml"
old_local="$REPO_ROOT/.claude/code-metrics.local.yaml"
personal_file="$REPO_ROOT/docs/conventions/code-metrics.local.yaml"
user_warn="$(mktemp)"
user_file="$("${PY[@]}" -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cm_resolve_config", sys.argv[1])
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)
warnings = []
print(resolver.user_file(sys.argv[2], sys.argv[3], warnings) or "")
for warning in warnings:
    print(warning, file=sys.stderr)
' "$SCRIPTS/resolve-config.py" "$USER_OPTION" "$HOME_DIR" 2>"$user_warn")"
user_where="$user_file"
if [[ -s "$user_warn" ]]; then
  row WARN "layer userConfig" "$(tr '\n' ' ' <"$user_warn")"
elif [[ -z "$user_file" ]]; then
  row INFO "layer userConfig" "unset: the config_file option names no file; set it in /config to keep your own settings for every repository"
fi
rm -f "$user_warn"
[[ -n "$user_where" ]] || user_where="the file the config_file userConfig option names (set it in /config)"
dual_read_rows userConfig "layer user-global location" "user-global file" n/a "$old_user" "$user_file" "$user_where"
team_file="$REPO_ROOT/docs/conventions/code-metrics.yaml"
retired_file="$REPO_ROOT/.claude/code-metrics.yaml"
if [[ -f "$retired_file" && ! "$retired_file" -ef "$old_user" ]]; then
  if [[ -f "$team_file" ]]; then
    row WARN "layer team location" "$retired_file is the retired team file and is not read; delete it"
  else
    row WARN "layer team location" "$retired_file is the retired team file and is not read; /code-metrics:setup apply moves its keys to $team_file"
  fi
fi
check_layer "team" "$team_file" yes
dual_read_rows local "layer local location" "personal override" no "$old_local" "$personal_file" "$personal_file"

# The resolver reads an ecosystem record only for a lane in the resolved
# `lanes` mapping whose id matches its LANE_ID pattern, so the configuration
# resolves before the ecosystem rows. The pattern is imported from the
# resolver, never copied, so the rows cannot drift from what it reads.
RESOLVED="$(mktemp)"
LIVE="$(mktemp -d)"
trap 'rm -rf "$RESOLVED" "$RESOLVED.err" "$LIVE"' EXIT
resolved_ok=0
"${PY[@]}" "$SCRIPTS/resolve-config.py" --ladder "$SCRIPTS/collector-ladder.tsv" --home "$HOME_DIR" --repo-root "$REPO_ROOT" --user-file "$USER_OPTION" >"$RESOLVED" 2>"$RESOLVED.err" && resolved_ok=1

ecos=()
lanes=()
for eco in "$REPO_ROOT"/docs/conventions/ecosystems/*.yaml "$REPO_ROOT"/.claude/ecosystems/*.yaml; do
  [[ -f "$eco" ]] || continue
  if [[ "$eco" == "$REPO_ROOT/.claude/ecosystems/"* && -f "$REPO_ROOT/docs/conventions/ecosystems/${eco##*/}" ]]; then
    row WARN "ecosystem .claude/ecosystems/${eco##*/}" "is not read: docs/conventions/ecosystems/${eco##*/} takes its place; delete it"
    continue
  fi
  lane="${eco##*/}"
  lane="${lane%.yaml}"
  lane="${lane%.local}"
  ecos+=("$eco")
  lanes+=("$lane")
done
statuses=()
if [[ ${#ecos[@]} -gt 0 ]]; then
  resolved_doc=""
  [[ $resolved_ok -eq 1 ]] && resolved_doc="$RESOLVED"
  mapfile -t statuses < <("${PY[@]}" -I -c '
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("cm_resolve_config", sys.argv[1])
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)
lanes = (json.load(open(sys.argv[2])).get("lanes") or {}) if sys.argv[2] else None
for lane in sys.argv[3:]:
    if not resolver.LANE_ID.fullmatch(lane):
        print("invalid")
    elif lanes is None:
        print("unknown")
    else:
        print("listed" if lane in lanes else "unlisted")
' "$SCRIPTS/resolve-config.py" "$resolved_doc" "${lanes[@]}")
fi

for i in "${!ecos[@]}"; do
  eco="${ecos[$i]}"
  lane="${lanes[$i]}"
  if ! err="$("${PY[@]}" "$SCRIPTS/yaml_subset.py" "$eco" 2>&1 >/dev/null)"; then
    row FAIL "ecosystem ${eco##*/}" "outside the YAML subset: ${err#*: }"
    continue
  fi
  case "${statuses[$i]:-unknown}" in
  invalid)
    row WARN "ecosystem ${eco##*/}" "parses, but its file name gives lane id $lane, which is not lowercase kebab-case, so no lane can read it; rename the file to a lowercase kebab-case lane id to use it"
    ;;
  listed)
    row PASS "ecosystem ${eco##*/}" "parses; its globs and enabled key are honored for lane detection"
    ;;
  unlisted)
    row WARN "ecosystem ${eco##*/}" "parses, but no layer lists lane $lane under lanes, so it is not used for lane detection; add a lanes.$lane entry to a layer to use it"
    ;;
  *)
    row WARN "ecosystem ${eco##*/}" "parses; whether lane $lane reads it is unknown because the configuration did not resolve (see the config row)"
    ;;
  esac
done

if [[ $resolved_ok -eq 1 ]]; then
  while IFS=$'\t' read -r measure reference provenance layer; do
    row INFO "reference $measure" "$reference (layer: $layer) $provenance"
  done < <("${PY[@]}" -I -c '
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

FIXTURES="$SCRIPTS/fixtures/sources"
PROJECT_BOUND=" eslint-complexity sonarjs type-coverage "

fixture_files() {
  if [[ "$2" == duplication ]]; then
    [[ "$1" == bash ]] && echo "cluster/alpha/shared/shared-utils.sh cluster/beta/shared/shared-utils.sh"
    return 0
  fi
  case "$1" in
  typescript) echo cm-sample.ts ;;
  python) echo cm_sample.py ;;
  bash) echo cm-sample.sh ;;
  go) echo cm-sample.go ;;
  dotnet) echo CmSample.cs ;;
  other) echo cm-notes.md ;;
  *) ;;
  esac
}

check_collector() {
  local name="$1" adapter="$2" version="$3" lane measure files="" first_lane="" first_measure=""
  while IFS=$'\t' read -r lane measure; do
    [[ -n "$first_lane" ]] || {
      first_lane="$lane"
      first_measure="$measure"
    }
    files="$(fixture_files "$lane" "$measure")"
    [[ -n "$files" ]] && break
  done < <(awk -F'\t' -v t="$name" '!/^#/ && $3 == t { print $1 "\t" $2 }' "$SCRIPTS/collector-ladder.tsv")
  if [[ -z "$first_lane" ]]; then
    row PASS "collector $name" "$version"
    return
  fi
  if [[ "$PROJECT_BOUND" == *" $name "* ]]; then
    row WARN "collector $name" "$version; probe only: resolves from the project's node_modules and needs its configuration, which a bundled fixture cannot supply"
    return
  fi
  if [[ -z "$files" ]]; then
    row WARN "collector $name" "$version; probe only: no bundled fixture for $first_lane/$first_measure"
    return
  fi
  local -a fx
  read -ra fx <<<"$files"
  local work="$LIVE/$name" proj="$PWD" f rc rows err on="${fx[0]}"
  [[ ${#fx[@]} -gt 1 ]] && on+=" +$((${#fx[@]} - 1))"
  mkdir -p "$work"
  for f in "${fx[@]}"; do
    mkdir -p "$work/$(dirname "$f")"
    cp "$FIXTURES/$f" "$work/$f"
  done
  (cd "$work" && PATH="$proj/node_modules/.bin:$PATH" "${PY[@]}" "$adapter" collect "$lane" "$measure" "${fx[@]}" >"$LIVE/$name.out" 2>"$LIVE/$name.err")
  rc=$?
  rows="$(grep -c '^{' "$LIVE/$name.out" || true)"
  err="$(head -n 1 "$LIVE/$name.err" | tr -d '\r')"
  if [[ $rc -eq 4 ]]; then
    row WARN "collector $name" "$version; probe only: ${err:-the tool cannot run on a lone fixture}"
  elif [[ $rc -eq 0 && "$rows" -gt 0 ]]; then
    row PASS "collector $name" "$version; measured $measure on $on"
  elif [[ $rc -eq 0 ]]; then
    row FAIL "collector $name" "$version; probe passed but collect $lane $measure on $on returned no rows${err:+: $err}"
  else
    row FAIL "collector $name" "$version; probe passed but collect $lane $measure on $on failed (exit $rc)${err:+: $err}"
  fi
}

for adapter in "$SCRIPTS"/collectors/*.py; do
  name="${adapter##*/}"
  name="${name%.py}"
  [[ "$name" == test_* || "$name" == adapter_paths ]] && continue
  if version="$("${PY[@]}" "$adapter" probe 2>/dev/null)"; then
    check_collector "$name" "$adapter" "$version"
  else
    hint="$("${PY[@]}" "$adapter" install_hint 2>/dev/null || true)"
    row INFO "collector $name" "missing; ${hint:-no install hint} (optional: the lane reports unavailable without it)"
  fi
done

printf '\n%d FAIL\n' "$FAILS"
[[ $FAILS -eq 0 ]]
