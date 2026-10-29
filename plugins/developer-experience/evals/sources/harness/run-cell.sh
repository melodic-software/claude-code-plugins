#!/usr/bin/env bash
# Run one eval cell run: one (scenario, arm, model, run index) in a fresh fixture copy.
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS_DIR="$(dirname "$HARNESS_DIR")"
WORKTREE="$(cd "$EVALS_DIR/../../../.." && pwd)"
# shellcheck source=scenarios.sh
source "$HARNESS_DIR/scenarios.sh"

usage() {
  cat <<'EOF'
run-cell.sh: run one eval run in a fresh, isolated fixture copy.

Usage:
  run-cell.sh --scenario ID --arm A0|A1|A2 --model opus|sonnet|haiku --run N
              --budget CAP [--timeout SECONDS] [--replace] [--dry-run]
  run-cell.sh --help

  --scenario  one of the ids in scenarios.sh (S1 ... NM-script, SENT-tarnquill, SENT-brackenfold)
  --arm       A0 no plugin (bare), A1 no plugin (conventions-only), A2 plugin (converged)
  --budget    value passed to claude --max-budget-usd for each turn (a ceiling, required)
  --timeout   per-turn wall-clock limit in seconds (default 2700)
  --replace   delete an existing result and workspace for this run first
  --dry-run   build the workspace and print the claude commands; run nothing

Environment: EVAL_RUNS_DIR (required) is the scratch root for workspaces, outside the repository;
EVAL_RESULTS_DIR overrides the results root (default results/ beside harness/).

Writes results/<scenario>/<arm>/<model>/run-<n>/:
  turn1.jsonl [turn2.jsonl]  stream-json (cost fields removed), turnN.err stderr
  init.json                  the system/init event of turn 1
  meta.json                  versions, model id, turns, tokens, duration, validity
  workspace.diff             final diff against the scaffold commit
  tree-turn1.txt             workspace tree hash after turn 1 (two-turn scenarios)
  sentinel.txt               the planted token (sentinel scenarios)

Exit: 0 valid run; 1 invalid run (isolation check, claude failure, home files
changed, sentinel missing); 2 usage; 3 refused (result exists, CLAUDE.md in a
parent of the workspace); 4 internal error.
EOF
}

die() {
  printf 'run-cell: %s\n' "$2" >&2
  exit "$1"
}

SCENARIO="" ARM="" MODEL="" RUN="" BUDGET="" TIMEOUT=2700 REPLACE=0 DRY_RUN=0
while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --scenario | --arm | --model | --run | --budget | --timeout)
      (($# >= 2)) || die 2 "$1 needs a value"
      case "$1" in
        --scenario) SCENARIO="$2" ;;
        --arm) ARM="$2" ;;
        --model) MODEL="$2" ;;
        --run) RUN="$2" ;;
        --budget) BUDGET="$2" ;;
        *) TIMEOUT="$2" ;;
      esac
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *) die 2 "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$SCENARIO" && -n "$ARM" && -n "$MODEL" && -n "$RUN" && -n "$BUDGET" ]] ||
  die 2 "--scenario, --arm, --model, --run and --budget are required (see --help)"
[[ "$ARM" =~ ^A[012]$ ]] || die 2 "--arm must be A0, A1 or A2"
[[ "$MODEL" =~ ^(opus|sonnet|haiku)$ ]] || die 2 "--model must be opus, sonnet or haiku"
[[ "$RUN" =~ ^[1-9][0-9]*$ ]] || die 2 "--run must be a positive integer"
[[ "$BUDGET" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die 2 "--budget must be a number"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die 2 "--timeout must be a positive integer"
scenario_load "$SCENARIO" "$ARM"
case $? in
  0) ;;
  1) die 2 "unknown scenario: $SCENARIO" ;;
  *) die 2 "scenario $SCENARIO is not run in arm $ARM" ;;
esac
for tool in claude git jq sha256sum timeout; do
  command -v "$tool" >/dev/null || die 4 "required tool not found: $tool"
done

SRC="$EVALS_DIR/fixtures/$FIXTURE/$STATE"
[[ -d "$SRC" ]] || die 4 "fixture state missing: $SRC (run build-fixtures.py)"
RUNS_ROOT="${EVAL_RUNS_DIR:?set EVAL_RUNS_DIR to a scratch directory outside the repository}"
# The parent walk below and the worktree check need an absolute path; a relative one never reaches /.
[[ "$RUNS_ROOT" == /* ]] || die 2 "EVAL_RUNS_DIR must be an absolute path: $RUNS_ROOT"
RUN_DIR="$RUNS_ROOT/$SCENARIO/$ARM/$MODEL/run-$RUN"
WS="$RUN_DIR/ws"
OUT="${EVAL_RESULTS_DIR:-$EVALS_DIR/results}/$SCENARIO/$ARM/$MODEL/run-$RUN"

if [[ "$RUN_DIR" == "$WORKTREE"/* ]]; then die 3 "workspace would sit inside the worktree: $RUN_DIR"; fi
if ((DRY_RUN)); then OUT="$RUN_DIR/dry-run-results"; fi
if [[ -e "$OUT" || -e "$RUN_DIR" ]]; then
  ((REPLACE)) || die 3 "run exists (use --replace): $OUT"
  rm -rf "${OUT:?}" "${RUN_DIR:?}"
fi

# A CLAUDE.md in the workspace's parents would replace the fixture's AGENTS.md.
dir="$RUNS_ROOT"
mkdir -p "$dir" || die 4 "cannot create $dir"
while [[ "$dir" != / ]]; do
  for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md; do
    [[ -e "$dir/$f" ]] && die 3 "instruction file in a workspace parent: $dir/$f"
  done
  dir="$(dirname "$dir")"
done

mkdir -p "$RUN_DIR" "$OUT" || die 4 "cannot create run directories"
cp -a "$SRC" "$WS" || die 4 "copy failed"
if ((SENTINEL)); then
  TOKEN="SENTINEL-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  # shellcheck disable=SC2016
  printf '\n- Verification token for this repository: `%s`.\n' "$TOKEN" >>"$WS/AGENTS.md"
  printf '%s\n' "$TOKEN" >"$OUT/sentinel.txt"
fi
GIT=(git -C "$WS" -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false)
if ! { "${GIT[@]}" init -q -b main && "${GIT[@]}" add -A && "${GIT[@]}" commit -q -m scaffold; }; then
  die 4 "git init of the workspace failed"
fi
SCAFFOLD_TREE="$("${GIT[@]}" rev-parse 'HEAD^{tree}')"

PLUGIN_ARGS=()
if [[ "$ARM" == A2 ]]; then
  cp -a "$WORKTREE/plugins/developer-experience" "$RUN_DIR/developer-experience" ||
    die 4 "plugin copy failed"
  PLUGIN_ARGS=(--plugin-dir "$RUN_DIR/developer-experience")
  # A2-only (DEVIATIONS 2026-10-09): setup's helper, by its plugin-copy path; nothing else.
  # Both spellings of that one path: unquoted, and quoted as the skill body writes it.
  HELPER="$RUN_DIR/developer-experience/skills/setup/scripts/pointer-line.sh"
  TOOLS+=("Bash(bash $HELPER:*)" "Bash(bash \"$HELPER\":*)")
fi
DISALLOW_ARGS=()
if ((SENTINEL)); then
  DISALLOW_ARGS=(--disallowedTools Read Glob Grep Bash Write Edit Skill Task Agent WebFetch WebSearch)
fi

home_state() {
  local claude_md="$HOME/.claude/CLAUDE.md" dx_dir="$HOME/.config/developer-experience"
  if [[ -e "$claude_md" ]]; then sha256sum "$claude_md" | cut -d' ' -f1; else echo absent; fi
  if [[ -e "$dx_dir" ]]; then find "$dx_dir" -type f -exec sha256sum {} + | sort | sha256sum | cut -d' ' -f1; else echo absent; fi
}

# Parent-session variables (session ids, sockets, effort, plugin data) never reach the run.
UNSET=()
while IFS= read -r name; do UNSET+=(-u "$name"); done < <(compgen -e | grep -E '^(CLAUDE|ANTHROPIC|OTEL_)')
CLAUDE_ENV=(env "${UNSET[@]}" CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 DISABLE_AUTOUPDATER=1)
COMMON=(--setting-sources project --strict-mcp-config --permission-mode dontAsk
  --model "$MODEL" --output-format stream-json --verbose --max-budget-usd "$BUDGET"
  "${PLUGIN_ARGS[@]}" "${DISALLOW_ARGS[@]}" --allowedTools "${TOOLS[@]}")

if ((DRY_RUN)); then
  printf 'workspace: %s\nresults: %s\n' "$WS" "$OUT"
  printf 'turn 1: (cd %q &&' "$WS"
  printf ' %q' "${CLAUDE_ENV[@]}" claude -p "$PROMPT" "${COMMON[@]}"
  printf ')\n'
  [[ -n "$TURN2" ]] && printf 'turn 2: claude -p --resume <session_id> %q (same flags)\n' "$TURN2"
  exit 0
fi

SCRUB='(fromjson? | del(.. | .total_cost_usd?, .costUSD?)) // .'
run_turn() {
  local n="$1"
  shift
  (cd "$WS" && timeout "$TIMEOUT" "${CLAUDE_ENV[@]}" claude -p "$@" "${COMMON[@]}" </dev/null) \
    2>"$OUT/turn$n.err" | jq -cR "$SCRUB" >"$OUT/turn$n.jsonl"
  local rc=("${PIPESTATUS[@]}")
  return "${rc[0]}"
}

HOME_BEFORE="$(home_state)"
CLI_VERSION="$("${CLAUDE_ENV[@]}" claude --version 2>&1 | head -1)"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROBLEMS=()

run_turn 1 "$PROMPT"
RC1=$?
((RC1 == 0)) || PROBLEMS+=("turn 1 exited $RC1")
jq -c 'select(.type == "system" and .subtype == "init")' "$OUT/turn1.jsonl" | head -1 >"$OUT/init.json"
SESSION_ID="$(jq -r '.session_id // empty' "$OUT/init.json")"

RC2=""
if [[ -n "$TURN2" ]]; then
  GIT_INDEX_FILE="$RUN_DIR/turn1.index" "${GIT[@]}" add -A &&
    GIT_INDEX_FILE="$RUN_DIR/turn1.index" "${GIT[@]}" write-tree >"$OUT/tree-turn1.txt"
  if [[ -n "$SESSION_ID" && $RC1 -eq 0 ]]; then
    run_turn 2 --resume "$SESSION_ID" "$TURN2"
    RC2=$?
    ((RC2 == 0)) || PROBLEMS+=("turn 2 exited $RC2")
  else
    PROBLEMS+=("turn 2 not sent: no session id or turn 1 failed")
  fi
fi

# Isolation: only built-in cc-plugin-* plugins, plus developer-experience in A2.
if [[ ! -s "$OUT/init.json" ]]; then
  PROBLEMS+=("no system/init event")
  PLUGINS="[]"
else
  PLUGINS="$(jq -c '[.plugins[]? | if type == "object" then .name else . end]' "$OUT/init.json")"
  EXTRA="$(jq -r --arg arm "$ARM" '.[] | select(test("^cc-plugin-") | not)
    | select(($arm == "A2" and (. == "developer-experience" or startswith("developer-experience@"))) | not)' <<<"$PLUGINS")"
  [[ -z "$EXTRA" ]] || PROBLEMS+=("unexpected plugin(s): $(tr '\n' ' ' <<<"$EXTRA")")
  if [[ "$ARM" == A2 ]] && ! jq -e 'any(.[]; . == "developer-experience" or startswith("developer-experience@"))' <<<"$PLUGINS" >/dev/null; then
    PROBLEMS+=("developer-experience plugin not loaded")
  fi
  MCP="$(jq -r '[.mcp_servers[]? | .name // .] | join(" ")' "$OUT/init.json")"
  [[ -z "$MCP" ]] || PROBLEMS+=("MCP server(s) loaded: $MCP")
fi

for n in 1 2; do
  [[ -f "$OUT/turn$n.jsonl" ]] || continue
  subtype="$(jq -r 'select(.type == "result") | .subtype' "$OUT/turn$n.jsonl" | tail -1)"
  [[ "$subtype" == success ]] || PROBLEMS+=("turn $n result subtype: ${subtype:-none}")
done

if ((SENTINEL)); then
  final="$(jq -r 'select(.type == "result") | .result // ""' "$OUT/turn1.jsonl" | tail -1)"
  tool_uses="$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")] | length' "$OUT/turn1.jsonl")"
  grep -qF "$TOKEN" <<<"$final" || PROBLEMS+=("sentinel token not in the final answer")
  [[ "$tool_uses" == 0 ]] || PROBLEMS+=("sentinel run used $tool_uses tool call(s)")
fi

HOME_AFTER="$(home_state)"
[[ "$HOME_BEFORE" == "$HOME_AFTER" ]] || PROBLEMS+=("home files changed during the run")

GIT_INDEX_FILE="$RUN_DIR/final.index" "${GIT[@]}" add -A &&
  GIT_INDEX_FILE="$RUN_DIR/final.index" "${GIT[@]}" diff --cached --binary "$SCAFFOLD_TREE" >"$OUT/workspace.diff"
FINAL_TREE="$(GIT_INDEX_FILE="$RUN_DIR/final.index" "${GIT[@]}" write-tree)"

VALID=true
((${#PROBLEMS[@]} == 0)) || VALID=false
jq -n \
  --arg scenario "$SCENARIO" --arg arm "$ARM" --arg model_alias "$MODEL" --argjson run "$RUN" \
  --arg fixture "$FIXTURE" --arg state "$STATE" --arg workspace "$WS" --arg started "$STARTED" \
  --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cli_version "$CLI_VERSION" \
  --arg budget_flag "$BUDGET" --arg session_id "$SESSION_ID" --arg scaffold_tree "$SCAFFOLD_TREE" \
  --arg final_tree "$FINAL_TREE" --arg home_before "$HOME_BEFORE" --arg home_after "$HOME_AFTER" \
  --argjson plugins "$PLUGINS" --argjson valid "$VALID" \
  --argjson problems "$(printf '%s\n' "${PROBLEMS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --argjson tools "$(printf '%s\n' "${TOOLS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --slurpfile init "$OUT/init.json" \
  --argjson turns "$(for n in 1 2; do
    [[ -f "$OUT/turn$n.jsonl" ]] && jq -c --argjson n "$n" 'select(.type == "result")
      | {turn: $n, subtype, num_turns, duration_ms, duration_api_ms, usage}' "$OUT/turn$n.jsonl" | tail -1
  done | jq -sc '.')" \
  '{scenario: $scenario, arm: $arm, model_alias: $model_alias, run: $run, fixture: $fixture,
    state: $state, workspace: $workspace, started: $started, finished: $finished,
    cli_version: $cli_version, model_id: ($init[0].model // null), max_budget_usd_flag: $budget_flag,
    session_id: $session_id, plugins: $plugins, allowed_tools: $tools,
    scaffold_tree: $scaffold_tree, final_tree: $final_tree,
    home_state_before: $home_before, home_state_after: $home_after,
    turns: $turns,
    totals: {num_turns: ($turns | map(.num_turns // 0) | add),
      duration_ms: ($turns | map(.duration_ms // 0) | add),
      input_tokens: ($turns | map(.usage.input_tokens // 0) | add),
      cache_creation_input_tokens: ($turns | map(.usage.cache_creation_input_tokens // 0) | add),
      cache_read_input_tokens: ($turns | map(.usage.cache_read_input_tokens // 0) | add),
      output_tokens: ($turns | map(.usage.output_tokens // 0) | add)},
    valid: $valid, problems: $problems}' >"$OUT/meta.json" || die 4 "could not write meta.json"

if [[ "$VALID" == true ]]; then
  printf 'VALID %s\n' "$OUT"
  exit 0
fi
printf 'INVALID %s\n' "$OUT" >&2
printf '  %s\n' "${PROBLEMS[@]}" >&2
exit 1
