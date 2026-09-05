#!/usr/bin/env bash
# Generate the hook event registry the claude-ops per-session event log is
# registered from, and the hooks.json rows that register it.
#
#   scripts/gen-hook-event-registry.sh --fetch        fetch the Hooks reference,
#                                                     rewrite the registry and
#                                                     the producer rows
#   scripts/gen-hook-event-registry.sh --from <file>  same, parsing a saved copy
#                                                     of the reference (tests)
#   scripts/gen-hook-event-registry.sh --check        OFFLINE: re-derive the
#                                                     producer rows from the
#                                                     committed registry and
#                                                     fail on drift (CI)
#
# Why generated, never hand-maintained: the event list is an upstream fact
# (https://code.claude.com/docs/en/hooks, the lifecycle table under "Hook
# lifecycle"), and a hardcoded list drifts silently as events are added or
# renamed. Every registry entry is a four-part record per
# docs/conventions/upstream-drift (claim, basis, as-of date, recheck trigger),
# and per docs/conventions/native-references it states what the reference
# documented on the as-of date, never that the running binary fires the event:
# a producer row on an event the binary does not fire costs nothing.
#
# Not every documented event is observable by a logging hook. Three are
# excluded with their reason stamped in the registry, because a registered
# hook on them changes behavior rather than observing it:
#   WorktreeCreate  configuring one REPLACES the default git worktree creation,
#                   and a hook that prints no path fails the worktree
#   MessageDisplay  Claude Code holds each streamed batch until the hook returns
#   FileChanged     the matcher builds the watch list; a matcherless row
#                   watches nothing
# An event this script does not know is excluded as `unclassified` with a
# warning, never registered by default: classify it here first.
#
# The parse refuses to write when the table yields fewer than 25 rows: a page
# whose shape changed would otherwise produce an empty registry and silently
# unregister the producer. The committed registry stays authoritative until a
# human re-runs --fetch. Recheck trigger for every entry: each
# `/claude-ops:changelog` ingest of a Claude Code release whose notes touch
# hooks re-runs `--fetch --check`; a read-time re-fetch finding the table
# changed also fires.
#
# Exit 0 = written / clean; 1 = drift (--check) or a usage error; 2 = the
# reference could not be fetched or parsed (nothing written).
set -euo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

MODE=""
FROM=""
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AS_OF=""
while (($# > 0)); do
  case "$1" in
  --fetch) MODE=fetch ;;
  --check) MODE=check ;;
  --from)
    MODE=from
    FROM="${2:?--from needs a file}"
    shift
    ;;
  --root)
    ROOT="${2:?--root needs a directory}"
    shift
    ;;
  --as-of)
    AS_OF="${2:?--as-of needs a date}"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "gen-hook-event-registry: unknown argument: $1" >&2
    exit 1
    ;;
  esac
  shift
done
[[ -n "$MODE" ]] || {
  echo "gen-hook-event-registry: one of --fetch, --from <file>, --check is required" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "gen-hook-event-registry: jq is required" >&2
  exit 2
}

URL="https://code.claude.com/docs/en/hooks.md"
BASIS="https://code.claude.com/docs/en/hooks#hook-lifecycle"
REGISTRY="$ROOT/plugins/claude-ops/hooks/hook-events.registry.json"
HOOKS_JSON="$ROOT/plugins/claude-ops/hooks/hooks.json"
# shellcheck disable=SC2016  # the literal hooks.json command text; Claude Code expands it, not this script
PRODUCER='"${CLAUDE_PLUGIN_ROOT}"/hooks/session-event-log.sh'
# shellcheck disable=SC2016
RETENTION='"${CLAUDE_PLUGIN_ROOT}"/hooks/session-retention.sh'
RECHECK="each /claude-ops:changelog ingest of a Claude Code release whose notes touch hooks re-runs scripts/gen-hook-event-registry.sh --fetch --check; a read-time re-fetch finding the lifecycle table changed also fires"
MIN_ROWS=25

# classify_to <cat-var> <producer-var> <event>: the category (the same table
# plugins/claude-ops/hooks/session-log-lib.sh carries, pinned by the test) and
# whether the producer may register on it.
classify_to() {
  local c p
  case "$3" in
  SessionStart | SessionEnd | Setup) c=session ;;
  UserPromptSubmit | UserPromptExpansion) c=prompt ;;
  PreToolUse | PostToolUse | PostToolUseFailure | PostToolBatch) c=tool ;;
  PermissionRequest | PermissionDenied) c=permission ;;
  SubagentStart | SubagentStop | TeammateIdle) c=agent ;;
  TaskCreated | TaskCompleted) c=task ;;
  Stop | StopFailure | Notification) c=turn ;;
  InstructionsLoaded | ConfigChange | CwdChanged | DirectoryAdded | FileChanged) c=config ;;
  WorktreeCreate | WorktreeRemove) c=worktree ;;
  PreCompact | PostCompact) c=compaction ;;
  PreModelSwitch | PostModelSwitch) c=model ;;
  Elicitation | ElicitationResult) c=mcp ;;
  MessageDisplay) c=display ;;
  *) c=other ;;
  esac
  p=observe
  case "$3" in
  WorktreeCreate) p="exclude: configuring a WorktreeCreate hook replaces the default git worktree creation, and a hook that prints no path fails the worktree" ;;
  MessageDisplay) p="exclude: Claude Code holds each streamed batch until the hook returns" ;;
  FileChanged) p="exclude: the matcher builds the watch list, so a matcherless row watches nothing" ;;
  *) [[ "$c" == other ]] && p="exclude: unclassified by scripts/gen-hook-event-registry.sh; classify it there before registering" ;;
  esac
  printf -v "$1" '%s' "$c"
  printf -v "$2" '%s' "$p"
}

# parse_table: markdown on stdin -> `name<TAB>when` per row of the lifecycle
# table (the rows after the `| Event | When it fires |` header, up to the first
# blank line; the name is the first backticked cell, the description the second
# cell, trimmed).
parse_table() {
  awk '
    /^\| *Event *\| *When it fires *\|/ { inside = 1; next }
    inside && /^\| *:?-+/ { next }
    inside && /^[[:space:]]*$/ { exit }
    inside && /^\| *`[A-Za-z]+` *\|/ {
      line = $0
      sub(/^\| *`/, "", line)
      name = line; sub(/`.*/, "", name)
      when = line; sub(/^[^`]*` *\| */, "", when); sub(/ *\|[[:space:]]*$/, "", when)
      gsub(/\t/, " ", when)
      print name "\t" when
    }'
}

# build_registry <rows-tsv> <as-of> -> registry JSON on stdout
build_registry() {
  local rows="$1" as_of="$2" name when cat prod tmp
  tmp=$(mktemp)
  while IFS=$'\t' read -r name when; do
    [[ -n "$name" ]] || continue
    classify_to cat prod "$name"
    [[ "$prod" == "exclude: unclassified"* ]] &&
      echo "gen-hook-event-registry: WARN unknown event '$name' excluded; classify it in classify_to" >&2
    printf '%s\t%s\t%s\t%s\n' "$name" "$when" "$cat" "$prod" >>"$tmp"
  done <"$rows"
  jq -Rn --arg as_of "$as_of" --arg basis "$BASIS" --arg recheck "$RECHECK" '
    [inputs | split("\t") | {
      name: .[0], when: .[1], category: .[2], producer: .[3],
      claim: ("hook event " + .[0] + " is documented in the Hooks reference lifecycle table"),
      basis: ($basis + " (raw markdown of hooks.md, fetched with curl -sS -L)"),
      as_of: $as_of, recheck: $recheck }]
    | sort_by(.name)' <"$tmp"
  rm -f "$tmp"
}

# regen_rows <registry-json-file> <hooks-json-file> -> hooks.json on stdout with
# the producer rows re-derived: every row naming the producer or the retention
# hook is stripped, then one producer row per observable event and one
# retention row on SessionEnd are appended; the existing handlers and their
# order are untouched.
regen_rows() {
  jq --indent 2 --arg prod "$PRODUCER" --arg ret "$RETENTION" --slurpfile reg "$1" '
    def strip: map(select(any(.hooks[]?; .command == $prod or .command == $ret) | not));
    .hooks |= (with_entries(.value |= strip) | with_entries(select(.value | length > 0)))
    | reduce ($reg[0][] | select(.producer == "observe")) as $e (.;
        .hooks[$e.name] = ((.hooks[$e.name] // []) + [{hooks: [{type: "command", command: $prod, timeout: 5,
          statusMessage: ("Logging the " + $e.name + " event...")}]}]))
    | .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [{hooks: [{type: "command", command: $ret,
        statusMessage: "Pruning the session event log..."}]}])
  ' "$2"
}

case "$MODE" in
fetch | from)
  rows=$(mktemp)
  trap 'rm -f "$rows"' EXIT
  if [[ "$MODE" == fetch ]]; then
    page=$(mktemp)
    trap 'rm -f "$rows" "$page"' EXIT
    if ! curl -sS -L --max-time 30 "$URL" >"$page"; then
      echo "gen-hook-event-registry: fetch of $URL failed" >&2
      exit 2
    fi
    parse_table <"$page" >"$rows"
  else
    parse_table <"$FROM" >"$rows"
  fi
  [[ -n "$AS_OF" ]] || AS_OF=$(date -u +%Y-%m-%d)
  n=$(wc -l <"$rows" | tr -d ' ')
  if ((n < MIN_ROWS)); then
    echo "gen-hook-event-registry: parsed only $n lifecycle rows (need $MIN_ROWS); the page shape may have changed. Nothing written." >&2
    exit 2
  fi
  build_registry "$rows" "$AS_OF" >"$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  regen_rows "$REGISTRY" "$HOOKS_JSON" >"$HOOKS_JSON.tmp"
  mv "$HOOKS_JSON.tmp" "$HOOKS_JSON"
  observed=$(jq '[.[] | select(.producer == "observe")] | length' "$REGISTRY")
  echo "gen-hook-event-registry: $n events in the registry ($observed observable), as of $AS_OF; producer rows rewritten in $HOOKS_JSON"
  ;;
check)
  [[ -f "$REGISTRY" ]] || {
    echo "gen-hook-event-registry: no registry at $REGISTRY" >&2
    exit 1
  }
  bad=$(jq '[.[] | select((has("name") and has("when") and has("category") and has("producer") and has("claim") and has("basis") and has("as_of") and has("recheck")) | not)] | length' "$REGISTRY")
  if [[ "$bad" != 0 ]]; then
    echo "gen-hook-event-registry: $bad registry entries lack one of the required parts (name, when, category, producer, claim, basis, as_of, recheck)" >&2
    exit 1
  fi
  expected=$(regen_rows "$REGISTRY" "$HOOKS_JSON" | jq -S .)
  actual=$(jq -S . "$HOOKS_JSON")
  if [[ "$expected" != "$actual" ]]; then
    echo "gen-hook-event-registry: hooks.json producer rows drift from the registry; re-run --fetch (or --from) to regenerate:" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
  fi
  echo "gen-hook-event-registry: hooks.json producer rows match the registry ($(jq length "$REGISTRY") events)"
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
