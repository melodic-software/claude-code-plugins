#!/usr/bin/env bash
# test-scope: plugins/session-flow/scripts/*.py plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/vendor/gitleaks/gitleaks-rules.json plugins/session-flow/lib/state-key.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/turns-to-complete.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/projects"

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

mkagent() {
  local name="$1" type="$2" day="$3" turns="$4" parallel="${5:-}" running="${6:-}"
  local dir="$ROOT/proj/sess/subagents"
  mkdir -p "$dir"
  printf '{"agentType":"%s"}\n' "$type" >"$dir/agent-$name.meta.json"
  python3 - "$dir/agent-$name.jsonl" "$day" "$turns" "$parallel" "$running" <<'PY'
import json, sys
path, day, turns, parallel, running = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
with open(path, "w") as fh:
    fh.write(json.dumps({"type": "user", "timestamp": f"{day}T01:00:00.000Z",
                         "message": {"role": "user", "content": "secret prompt"}}) + "\n")
    for i in range(turns):
        for kind in (["thinking", "text", "tool_use"] if parallel else ["tool_use"]):
            fh.write(json.dumps({"type": "assistant", "timestamp": f"{day}T01:00:01.000Z",
                                 "message": {"id": f"msg_{i}", "role": "assistant",
                                             "stop_reason": "end_turn" if i == turns - 1 and not running else "tool_use",
                                             "content": [{"type": kind}]}}) + "\n")
        fh.write(json.dumps({"type": "user", "timestamp": f"{day}T01:00:02.000Z",
                             "message": {"role": "user",
                                         "content": [{"type": "tool_result"}]}}) + "\n")
PY
}

expect() {
  local label="$1" want="$2" pattern="$3"
  shift 3
  local out got
  out="$(python3 "$SUT" "$@" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label: expected exit $want, got $got: $out"
  elif [[ -n "$pattern" ]] && ! grep -Eq -- "$pattern" <<<"$out"; then
    fail "$label: output lacks /$pattern/: $out"
  else
    pass "$label"
  fi
}

expect_absent() {
  local label="$1" pattern="$2"
  shift 2
  if grep -Eq -- "$pattern" < <(python3 "$SUT" "$@" 2>&1); then
    fail "$label: output unexpectedly matches /$pattern/"
  else
    pass "$label"
  fi
}

mkagent par discovery:researcher 2026-08-01 5 parallel
mkagent full discovery:explorer 2026-08-02 40
mkagent below discovery:explorer 2026-08-03 39
mkagent other general-purpose 2026-08-04 7
mkagent late discovery:researcher 2026-09-10 3
mkagent live discovery:researcher 2026-09-11 6 "" running
mkagent oldlive discovery:researcher 2026-08-06 6 "" running
mkdir -p "$ROOT/proj/sess/subagents"
: >"$ROOT/proj/sess/subagents/agent-nometa.jsonl"

expect "parallel records sharing a message.id count as one turn" 0 \
  '^\| 2026-08-01 \| discovery:researcher \| 5 \| no \| n/a \|' --root "$ROOT"
expect "a 40-turn dispatch is flagged at the ceiling" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \|' --root "$ROOT"
expect "a 39-turn dispatch is not flagged" 0 \
  '^\| 2026-08-03 \| discovery:explorer \| 39 \| no \|' --root "$ROOT"
expect "the summary counts dispatches at the ceiling" 0 \
  '^\| discovery:explorer \| 2 \| 39 \| 39 \| 40 \| 40 \| 1 \|' --root "$ROOT"
expect_absent "a non-discovery agentType is excluded by default" 'general-purpose' --root "$ROOT"
expect "--agent-type selects another type" 0 'general-purpose' \
  --root "$ROOT" --agent-type general-purpose
expect_absent "--since drops earlier dispatches" '2026-08-0' --root "$ROOT" --since 2026-09-01
expect "--since keeps later dispatches" 0 '2026-09-10' --root "$ROOT" --since 2026-09-01
expect "--json emits per-dispatch rows and a summary" 0 '"at_ceiling": 1' --root "$ROOT" --json
expect_absent "transcript content is never printed" 'secret prompt' --root "$ROOT" --json
expect_absent "a dispatch with no final stop_reason is excluded" '2026-09-11' --root "$ROOT"
expect "the unfinished note counts every unfinished dispatch" 0 '2 unfinished' --root "$ROOT"
expect "the unfinished note honors --since" 0 '1 unfinished' --root "$ROOT" --since 2026-09-01
expect "a missing root exits 2" 2 'cannot read root' --root "$WORK/absent"

mkagent resumed discovery:researcher 2026-08-05 40
printf '%s\n' '{"type":"user","timestamp":"2026-08-05T02:00:00.000Z","message":{"role":"user","content":"continue"}}' \
  >>"$ROOT/proj/sess/subagents/agent-resumed.jsonl"
expect "a user record after the ceiling marks the dispatch resumed" 0 \
  '^\| 2026-08-05 \| discovery:researcher \| 40 \| yes \| yes \|' --root "$ROOT"
expect "a ceiling stop with no later user record reports unknown" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \| unknown \|' --root "$ROOT"

HOME_B="/""home/user-b"
LEAK="host-b $HOME_B ops-b@example.org"
printf '{"schema":"transcript-sources/v1","sources":[%s,%s]}\n' \
  "{\"name\":\"host-a-wsl\",\"host\":\"host-a\",\"platform\":\"wsl\",\"config_dir\":\"$WORK\"}" \
  '{"name":"host-b-wsl","host":"host-b","platform":"wsl","config_dir":"/srv/user-b/.claude","via":["ssh","host-b"]}' \
  >"$WORK/sources.json"
mkagent leak "$LEAK" 2026-08-07 4
expect "the markdown names the host and email by placeholders" 0 \
  '^\| 2026-08-07 \| <host-2> ~ <email> \| 4 \| no \| n/a \|' \
  --root "$ROOT" --agent-type "$LEAK" --sources-file "$WORK/sources.json"
for leaked in host-b "$HOME_B" example.org; do
  expect_absent "the markdown carries no $leaked" "$leaked" \
    --root "$ROOT" --agent-type "$LEAK" --sources-file "$WORK/sources.json"
done
expect "a missing sources file publishes nothing" 2 'nothing published: the sources file was not found' \
  --root "$ROOT" --agent-type "$LEAK" --sources-file "$WORK/absent-sources.json"
expect_absent "a missing sources file prints no table" '^\| date' \
  --root "$ROOT" --agent-type "$LEAK" --sources-file "$WORK/absent-sources.json"
AWS_KEY="AKIA""IOSFODNN7""EXAMPLE"
SECRET_TYPE="$AWS_KEY project-zeta"
mkagent secret "$SECRET_TYPE" 2026-08-08 3
expect "a detected secret and a --redact-identifiers entry leave as placeholders" 0 \
  '^\| 2026-08-08 \| <redacted:aws-access-token> <identifier> \| 3 \|' \
  --root "$ROOT" --agent-type "$SECRET_TYPE" --sources-file "$WORK/sources.json" --redact-identifiers project-zeta
expect_absent "the secret is not published" "$AWS_KEY" \
  --root "$ROOT" --agent-type "$SECRET_TYPE" --sources-file "$WORK/sources.json" --redact-identifiers project-zeta

CLAUDE_CONFIG_DIR="$WORK" expect "without --root the local configuration directory's projects are read" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \|'
CLAUDE_CONFIG_DIR="$WORK" expect "without session-flow installed the header says local sources were read" 0 \
  '^- Source: local sources \(session-flow not installed\)$'
CLAUDE_CONFIG_DIR="$WORK" expect "without --root each local source of the sources file is read" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \|' --sources-file "$WORK/sources.json"

CLAUDE_CONFIG_DIR="$WORK" expect "--json names each source this skill does not read" 0 \
  '"Not read by this skill: host-b-wsl \(remote; this skill reads this host.s sources only\)"' \
  --sources-file "$WORK/sources.json" --json
CLAUDE_CONFIG_DIR="$WORK" expect "the markdown header names the unread remote source by placeholder" 0 \
  '^- Not read by this skill: <host-2:wsl> \(remote; this skill reads this host.s sources only\)$' \
  --sources-file "$WORK/sources.json"
CLAUDE_CONFIG_DIR="$WORK" expect_absent "with only local sources no unread source is named" 'Not read by this skill' --json

BLOCKED="$WORK/blocked"
mkdir -p "$BLOCKED"
printf 'not a directory\n' >"$BLOCKED/projects"
printf '{"schema":"transcript-sources/v1","sources":[%s,%s]}\n' \
  "{\"name\":\"host-a-wsl\",\"host\":\"host-a\",\"platform\":\"wsl\",\"config_dir\":\"$WORK\"}" \
  "{\"name\":\"host-a-windows\",\"host\":\"host-a\",\"platform\":\"windows\",\"config_dir\":\"$BLOCKED\"}" \
  >"$WORK/gap-sources.json"
CLAUDE_CONFIG_DIR="$WORK" expect "the header names an unlistable projects directory as a gap with its retry" 0 \
  '^- Gap: <host-1:windows> unreadable: its projects directory could not be listed \(NotADirectoryError\)\. Retry: python3 ' \
  --sources-file "$WORK/gap-sources.json"
CLAUDE_CONFIG_DIR="$WORK" expect "the other local source is still read" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \|' --sources-file "$WORK/gap-sources.json"
CLAUDE_CONFIG_DIR="$WORK" expect "--json carries the gap verbatim in its header" 0 \
  "\"Gap: host-a-windows unreadable: .*Retry: python3 $SUT --sources-file $WORK/gap-sources.json --json --diagnostics-dir $WORK/diag\"" \
  --sources-file "$WORK/gap-sources.json" --json --diagnostics-dir "$WORK/diag"
if compgen -G "$WORK/diag/*.json" >/dev/null && grep -q '"kind": "lookup"' "$WORK"/diag/*.json; then
  pass "--diagnostics-dir writes the gap as a lookup record"
else
  fail "--diagnostics-dir wrote no lookup record"
fi
printf '{"schema":"transcript-sources/v1"}\n' >"$WORK/bad-sources.json"
CLAUDE_CONFIG_DIR="$WORK" expect "a malformed sources file exits 2" 2 'error: .*bad-sources.json' --sources-file "$WORK/bad-sources.json" --json

SF_ROOT="$(cd "$SCRIPT_DIR/../../session-flow" && pwd)"
FLEET="$WORK/fleet"
HOST_A="$FLEET/host-a"
HOST_B="$FLEET/host-b"
mkdir -p "$HOST_A/projects/proj-a/sess-a/subagents" "$HOST_B/projects/proj-b/sess-b/subagents" \
  "$HOST_A/plugins/data/session-flow-test-mp"
python3 - "$HOST_A/projects/proj-a" "sess-a" "a1" "discovery:researcher" "2026-09-01" 12 <<'PY'
import json, pathlib, sys
proj, sid, name, atype, day, turns = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6])
(proj / f"{sid}.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u0", "timestamp": f"{day}T01:00:00Z", "promptSource": "typed", "message": {"role": "user", "content": "hi"}}) + "\n" +
    json.dumps({"type": "assistant", "uuid": "a0", "timestamp": f"{day}T01:00:05Z", "message": {"id": "main_0", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn", "content": [{"type": "text", "text": "ok"}]}}) + "\n",
    encoding="utf-8",
)
sub = proj / sid / "subagents"
(sub / f"agent-{name}.meta.json").write_text(json.dumps({"agentType": atype}) + "\n", encoding="utf-8")
lines = [json.dumps({"type": "user", "timestamp": f"{day}T01:00:00Z", "message": {"role": "user", "content": "go"}})]
for i in range(turns):
    lines.append(json.dumps({"type": "assistant", "timestamp": f"{day}T01:00:01Z", "message": {"id": f"m_{i}", "role": "assistant", "stop_reason": "end_turn" if i == turns - 1 else "tool_use", "content": [{"type": "tool_use"}]}}))
    lines.append(json.dumps({"type": "user", "timestamp": f"{day}T01:00:02Z", "message": {"role": "user", "content": [{"type": "tool_result"}]}}))
(sub / f"agent-{name}.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
python3 - "$HOST_B/projects/proj-b" "sess-b" "b1" "discovery:explorer" "2026-09-02" 25 <<'PY'
import json, pathlib, sys
proj, sid, name, atype, day, turns = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6])
(proj / f"{sid}.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u0", "timestamp": f"{day}T01:00:00Z", "promptSource": "typed", "message": {"role": "user", "content": "hi"}}) + "\n" +
    json.dumps({"type": "assistant", "uuid": "a0", "timestamp": f"{day}T01:00:05Z", "message": {"id": "main_0", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn", "content": [{"type": "text", "text": "ok"}]}}) + "\n",
    encoding="utf-8",
)
sub = proj / sid / "subagents"
(sub / f"agent-{name}.meta.json").write_text(json.dumps({"agentType": atype}) + "\n", encoding="utf-8")
lines = [json.dumps({"type": "user", "timestamp": f"{day}T01:00:00Z", "message": {"role": "user", "content": "go"}})]
for i in range(turns):
    lines.append(json.dumps({"type": "assistant", "timestamp": f"{day}T01:00:01Z", "message": {"id": f"m_{i}", "role": "assistant", "stop_reason": "end_turn" if i == turns - 1 else "tool_use", "content": [{"type": "tool_use"}]}}))
    lines.append(json.dumps({"type": "user", "timestamp": f"{day}T01:00:02Z", "message": {"role": "user", "content": [{"type": "tool_result"}]}}))
(sub / f"agent-{name}.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

FLEET_SOURCES="$FLEET/sources.json"
printf '{"schema":"transcript-sources/v1","sources":[%s,%s]}\n' \
  "{\"name\":\"host-a-wsl\",\"host\":\"host-a\",\"platform\":\"wsl\",\"config_dir\":\"$HOST_A\"}" \
  "{\"name\":\"host-b-wsl\",\"host\":\"host-b\",\"platform\":\"wsl\",\"config_dir\":\"$HOST_B\",\"via\":[\"sh\",\"-c\"]}" \
  >"$FLEET_SOURCES"

printf '{"version":2,"plugins":{"session-flow@test-mp":[{"scope":"user","installPath":"%s"}]}}\n' "$SF_ROOT" \
  >"$HOST_A/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"session-flow@test-mp":true}}\n' >"$HOST_A/settings.json"

CLAUDE_CONFIG_DIR="$HOST_A" expect "without a store yet falls back to local sources and says why" 0 \
  '^- Source: local sources \(no session-flow store yet; run /session-flow:audit-sessions to collect\)$' \
  --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect "fallback before collect names the unread remote host" 0 \
  '^- Not read by this skill: <host-2:wsl> ' \
  --sources-file "$FLEET_SOURCES"

SF_DATA="$HOST_A/plugins/data/session-flow-test-mp"
if ! python3 "$SF_ROOT/scripts/collect.py" collect --lock-name "test-ttc-$$" \
  --data-dir "$SF_DATA" --sources-file "$FLEET_SOURCES" >/dev/null 2>&1; then
  fail "collect.py failed to populate fleet store"
fi

CLAUDE_CONFIG_DIR="$HOST_A" expect "with session-flow store reads local host dispatch" 0 \
  '^\| 2026-09-01 \| discovery:researcher \| 12 \| no \| n/a \|' \
  --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect "with session-flow store reads remote host dispatch too" 0 \
  '^\| 2026-09-02 \| discovery:explorer \| 25 \| no \| n/a \|' \
  --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect "with session-flow store header says session-flow store" 0 \
  '^- Source: session-flow store$' \
  --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect_absent "with every host collected the header names no unread source" \
  'Not read by this skill' --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect_absent "with every host collected --json header names no unread source" \
  'Not read by this skill' --sources-file "$FLEET_SOURCES" --json

printf '{"enabledPlugins":{"session-flow@test-mp":false}}\n' >"$HOST_A/settings.json"
CLAUDE_CONFIG_DIR="$HOST_A" expect "disabled session-flow falls back to local sources" 0 \
  '^- Source: local sources \(session-flow not installed\)$' \
  --sources-file "$FLEET_SOURCES"
CLAUDE_CONFIG_DIR="$HOST_A" expect_absent "disabled session-flow does not read remote host" \
  '2026-09-02' --sources-file "$FLEET_SOURCES"
printf '{"enabledPlugins":{"session-flow@test-mp":true}}\n' >"$HOST_A/settings.json"

CLAUDE_CONFIG_DIR="$WORK" expect "explicit session-flow flags read the fleet store" 0 \
  '^\| 2026-09-02 \| discovery:explorer \| 25 \| no \| n/a \|' \
  --sources-file "$FLEET_SOURCES" \
  --session-flow-script "$SF_ROOT/scripts/dispatches.py" \
  --session-flow-data-dir "$SF_DATA"

python3 - "$SF_DATA" <<'PY'
import json, pathlib, sys
data_dir = pathlib.Path(sys.argv[1])
rec_path = next((data_dir / "audit-sessions" / "store" / "v2" / "host-b-wsl").glob("p-*/sess-b.json"))
legacy = json.loads(rec_path.read_text(encoding="utf-8"))
legacy["session_id"] = "sess-b-legacy"
legacy["subagents"].pop("dispatches")
(rec_path.parent / "sess-b-legacy.json").write_text(json.dumps(legacy), encoding="utf-8")
PY
CLAUDE_CONFIG_DIR="$HOST_A" expect "older store record lacking dispatches is named by placeholder in markdown header" 0 \
  '^- Not read by this skill: <host-2:wsl> \(1 stored session record\(s\) lack per-dispatch rows' \
  --sources-file "$FLEET_SOURCES"

mkdir -p "$SF_DATA/audit-sessions/store/v2/host-a-wsl/p-000000000000"
printf '{"schema":"session-record/v0"}\n' >"$SF_DATA/audit-sessions/store/v2/host-a-wsl/p-000000000000/bad.json"
CLAUDE_CONFIG_DIR="$HOST_A" expect "corrupted session-flow store exits 2" 2 \
  'error: session-flow store reader failed:' --sources-file "$FLEET_SOURCES"

if [[ "$fails" -ne 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo "all passed"
