# shellcheck shell=bash
identity="${1:?the agent identity}" budget="${2:?the merge-group wait budget}"
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
rows() { printf '%s\n' "${1:-[]}"; }
discussion() {
  [[ "$(grep -cE '/(comments|reviews)\?' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
}
case "$*" in
"api graphql "*lastEditedAt*)
  unedited='{"data":{"node":{"lastEditedAt":null}}}'
  printf '%s\n' "${STUB_EDITED:-$unedited}"
  ;;
"api graphql "*)
  echo '{"data":{}}'
  ;;
*/contents/*) exit 1 ;;
*/pulls/*/files\?*)
  jq -c '[.[] | {filename: .[0], previous_filename: .[1], status: (.[2] // (if .[1] then "renamed" else "modified" end))}]' <<<"$STUB_FILES" | jq -r "${*: -1}"
  ;;
*/issues/*/comments\?*) [[ -z "${STUB_COMMENTS_FAIL:-}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }; discussion; rows "${STUB_ISSUE:-}" ;;
*/pulls/*/reviews\?*) discussion; rows "${STUB_REVIEWS:-}" ;;
*/pulls/*/comments\?*) discussion; rows "${STUB_INLINE:-}" ;;
*/actions/artifacts\?name=*)
  all="$*" name=${all##*actions/artifacts?name=}
  name=${name%%&*}
  # The step's own --jq filter, the last argument, runs over a listing that
  # also holds an expired artifact of that name and an unexpired one whose
  # name only starts with it, both of run 11, which neither may count.
  jq -c --arg name "$name" '{artifacts: ([.[$name][]? | {name: $name, id: (. * 10), expired: false, workflow_run: {id: .}}]
    + [{name: $name, id: 110, expired: true, workflow_run: {id: 11}}, {name: ($name + "-i1"), id: 110, expired: false, workflow_run: {id: 11}}])}' \
    <<<"${STUB_ARTIFACTS:-{\}}" | jq -r "${*: -1}"
  ;;
*/actions/artifacts\?per_page=100*)
  # The whole listing, as two pages of STUB_TOTAL's total_count holding
  # STUB_LISTED_FAILS FAILs between them, a pass and a name that only starts like a
  # FAIL, through the step's own --jq filter.
  [[ -n "${STUB_TOTAL-x}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
  jq -nc --argjson total "${STUB_TOTAL:-7522}" --argjson fails "${STUB_LISTED_FAILS:-264}" '
    def fail: {name: "pr-verify-\(.)-0123456789abcdef0123456789abcdef01234567-fail-i\(.)"};
    {total_count: $total, artifacts: ([range(0; $fails / 2 | floor) | fail] + [{name: "pr-verify-7-0123456789abcdef0123456789abcdef01234567-pass"}])},
    {total_count: $total, artifacts: ([range($fails / 2 | floor; $fails) | fail] + [{name: "pr-verify-7-0123456789abcdef-fail"}])}' |
    jq -r "${*: -1}"
  ;;
*/actions/runs/*)
  all="$*" id=${all##*actions/runs/}
  jq -ce --arg id "$id" '.[$id] // error' <<<"${STUB_RUNS:-{\}}" 2>/dev/null || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  ;;
*/pulls/*) printf '%s\n' "$STUB_PULL" ;;
*/rules/branches/*)
  [[ -n "${STUB_RULES-x}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
  jq -nc --argjson n "${STUB_RULES:-1}" '[{type: "pull_request"}, {type: "merge_queue", parameters: {max_entries_to_build: $n, grouping_strategy: "ALLGREEN"}}]'
  ;;
*rate_limit*)
  [[ -n "${STUB_RATE:-}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
  printf '%s\n' "$STUB_RATE"
  ;;
*) exit 1 ;;
esac
EOF
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$STUB_LOG"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

cat >"$TMP_ROOT/reader.py" <<'EOF'
import json, os, sys
with open(os.environ["STUB_LOG"], "a") as log:
    log.write("reader " + " ".join(sys.argv[1:]) + "\n")
    log.write("reader-env floor-wait=" + os.environ.get("BABYSIT_READ_FLOOR_WAIT_SECONDS", "") + "\n")
if os.environ.get("STUB_READER_RC"):
    sys.exit(int(os.environ["STUB_READER_RC"]))
if not os.environ.get("STUB_NO_LISTING"):
    listing = []
    for name, runs in json.loads(os.environ.get("STUB_ARTIFACTS") or "{}").items():
        listing += [{"name": name, "id": run * 10, "expired": False, "workflow_run": {"id": run}} for run in runs]
        listing += [{"name": name, "id": 110, "expired": True, "workflow_run": {"id": 11}},
                    {"name": name + "-i1", "id": 110, "expired": False, "workflow_run": {"id": 11}}]
    with open(os.environ["BABYSIT_VERIFY_LISTING"], "w") as out:
        json.dump({"fetchedAt": "2026-10-25T10:00:00+00:00", "artifacts": listing}, out)
evidence = os.environ.get("STUB_EVIDENCE") or json.dumps({"refusal": None, "head": sys.argv[-1], "detail": None})
if "--pass-out" in sys.argv and os.environ.get("STUB_PASS_OUT") != "none":
    import copy, subprocess
    def sample(name):
        with open(os.path.join(os.environ["STUB_SAMPLES"], name)) as f:
            return json.load(f)
    def jq(doc, program):
        return subprocess.run(["jq", "-rc", program], input=json.dumps(doc), capture_output=True, text=True, check=True).stdout
    head = sys.argv[-1]
    try:
        allowed = json.loads(evidence.splitlines()[-1])
    except (ValueError, IndexError):
        allowed = None
    sent = sample("refusal.json") | {"head": head}
    if isinstance(allowed, dict) and allowed.get("refusal") is None and allowed.get("head") == head:
        base, notes = sample("allow-pass.json"), sample("allow-pass-and-pass-notes.json")
        order = [v["verdict"] for v in notes["verdicts"]]
        kinds = {v["verdict"]: v for v in notes["verdicts"] + base["verdicts"]}
        runs = json.loads(os.environ.get("STUB_RUNS") or "{}")
        prefix = f"pr-verify-7-{head}-"
        sent = base | {"head": head, "verdicts": []}
        for name, ids in json.loads(os.environ.get("STUB_ARTIFACTS") or "{}").items():
            kind = name[len(prefix):] if name.startswith(prefix) else None
            for run in ids if kind in kinds else ():
                read = runs.get(str(run))
                ran = None if read is None else {k: read.get(k, v) for k, v in kinds[kind]["run"].items()}
                sent["verdicts"].append(kinds[kind] | {"name": name, "runId": run, "artifact": run * 10, "run": ran})
        sent["verdicts"].sort(key=lambda v: order.index(v["verdict"]))
        record = copy.deepcopy(base["record"]) | {"pr": 7, "head_sha": head}
        for issue in record["linked_issues"]:
            issue["number"] = 1
        sent["record"] = None if not sent["verdicts"] or os.environ.get("STUB_NO_RECORD") else json.loads(jq(record, os.environ.get("STUB_RECORD") or "."))
        node = base["closing"]["nodes"][0]
        closing = [node | {"number": n, "repository": {"nameWithOwner": "o/r"}} for n in json.loads(os.environ.get("STUB_CLOSING") or "[1]")]
        sent["closing"] = {"totalCount": len(closing), "nodes": closing}
    with open(sys.argv[sys.argv.index("--pass-out") + 1], "w") as out:
        out.write(jq(sent, os.environ.get("STUB_PASS_OUT") or "."))
print(evidence)
EOF
mkdir -p "$TMP_ROOT/pr-merge"
cat >"$TMP_ROOT/pr-merge/head-ref-map.mjs" <<'EOF'
import { appendFileSync } from "node:fs";
import process from "node:process";
appendFileSync(process.env.STUB_LOG, `head-ref-map ${process.argv.slice(2).join(" ")}\n`);
process.exitCode = process.env.STUB_MAP_FAILS ? 1 : 0;
EOF

SHA=0123456789abcdef0123456789abcdef01234567
BASE=89abcdef0123456789abcdef0123456789abcdef
LANES='{"id":337595936,"login":"melodic-automation-lanes[bot]","type":"Bot"}'
pull() { jq -nc --argjson user "${2:-$LANES}" --arg body "$1" --arg ref "${STUB_BASE_REF:-main}" --arg sha "${STUB_BASE_SHA:-$BASE}" \
  --argjson changed "${STUB_CHANGED:-1}" '{number: 7, node_id: "PR_7", user: $user, body: $body, head: {sha: "'"$SHA"'", ref: "work-resolve-issue/issue-1"}, base: {ref: $ref, sha: $sha}, changed_files: $changed,
    auto_merge: (if env.STUB_ARMED then {merge_method: "squash"} else null end)}'; }
comment() { jq -nc --arg login "$1" --arg type "${2:-User}" --arg assoc "$3" --arg at "$4" --arg body "$5" \
  '{user: {login: $login, type: $type}, author_association: $assoc, created_at: $at, body: $body}'; }
approval() { jq -nc --arg login "$1" --argjson id "$2" --arg state "$3" --arg at "$4" --arg commit "$5" \
  '{user: {login: $login, id: $id, type: "User"}, author_association: "OWNER", state: $state, submitted_at: $at, commit_id: $commit, body: ""}'; }
review() { jq -nc --arg login "$1" --arg assoc "$2" --arg at "$3" --arg body "$4" \
  '{user: {login: $login, type: "User"}, author_association: $assoc, submitted_at: $at, body: $body}'; }

base_config() {
  local dir="$TMP_ROOT/base-config"
  rm -rf "$dir"
  mkdir -p "$dir/docs/conventions" "$dir/.github/scripts/pr-merge"
  [[ -n "${STUB_NO_CONFIG:-}" ]] ||
    IDENTITY="$identity" yq '.merge."agent-identity" = strenv(IDENTITY)' <<<"$STUB_CONFIG" >"$dir/docs/conventions/pr-pipeline.yaml"
  [[ -n "${STUB_NO_MODULE:-}" ]] || cp "${STUB_MODULE:-$MODULE}" "$dir/.github/scripts/pr-merge/merge-holds.mjs"
}
standards_stub() {
  rm -rf "$TMP_ROOT/standards"
  mkdir -p "$TMP_ROOT/standards/components/trusted-actors"
  [[ -n "${STUB_NO_ACTORS:-}" ]] || cp "$STUB_ACTORS" "$TMP_ROOT/standards/components/trusted-actors/trusted-actors.json"
}

WARM_CARRIED='{"carried-run-record":{"o/r|1":{"at":"2026-10-25T10:00:00Z","value":{}}},"carried-fail-head-ref":{},"carried-on-branch":{}}'
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  rm -rf "$TMP_ROOT/verify-listing.json" "$TMP_ROOT/pr-files.json"
  [[ -n "${STUB_BASE_CONFIG+x}" ]] || base_config
  standards_stub
  [[ -n "${STUB_KEEP_READS:-}" ]] || rm -rf "$TMP_ROOT/pr-reads"
  [[ -z "${STUB_PR_FILES:-}" ]] || printf '%s\n' "$STUB_PR_FILES" >"$TMP_ROOT/pr-files.json"
  local author_id='' author_type='' head_sha=''
  if [[ "${EVENT:-pull_request}" == pull_request ]]; then
    head_sha="${STUB_HEAD-$SHA}"
    author_id="${STUB_AUTHOR_ID-$(jq -r '.user.id // ""' <<<"$STUB_PULL")}"
    author_type="${STUB_AUTHOR_TYPE-$(jq -r '.user.type // ""' <<<"$STUB_PULL")}"
  fi
  if [[ -n "${STUB_COLD:-}" ]]; then
    rm -f "$TMP_ROOT/babysit-run-cache.json"
  else
    printf '%s\n' "${STUB_CARRIED:-$WARM_CARRIED}" >"$TMP_ROOT/babysit-run-cache.json"
  fi
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" \
    GITHUB_EVENT_NAME="${EVENT:-pull_request}" GITHUB_REF="${REF:-refs/pull/7/merge}" PR_NUMBER="${PR_NUMBER-7}" PR_AUTHOR_ID="$author_id" PR_AUTHOR_TYPE="$author_type" PR_HEAD_SHA="$head_sha" \
    GITHUB_REPOSITORY=o/r GITHUB_API_URL="${STUB_API:-http://127.0.0.1:9}" RUNNER_TEMP="$TMP_ROOT" GROUP_BASE_SHA="${GROUP_BASE_SHA-}" GROUP_BASE_REF="${GROUP_BASE_REF-refs/heads/main}" \
    VERIFY_EVIDENCE_SCRIPT="$TMP_ROOT/reader.py" BABYSIT_VERIFY_LEGACY_FAILS="$TMP_ROOT/base/.github/verify-legacy-fails.json" PR_MERGE_SCRIPTS="$TMP_ROOT/pr-merge" BABYSIT_VERIFY_LISTING="$TMP_ROOT/verify-listing.json" \
    BABYSIT_RUN_CACHE="$TMP_ROOT/babysit-run-cache.json" API_BUDGET_READ_FLOOR=0.1 MERGE_GROUP_WAIT_SECONDS="$budget" QUEUED_PR_WAITED="${STUB_WAITED-0}" BASE_CONFIG="${STUB_BASE_CONFIG-$TMP_ROOT/base-config}" STANDARDS_DIR="${STUB_STANDARDS-$TMP_ROOT/standards}" LANES_APP_ID="${STUB_APP_ID-$LANES_APP_ID}" LANES_DISABLED="${KILL-false}" LANES_REPO_DISABLED="${REPO_KILL-false}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -cE '/(comments|reviews)\?' "$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls discussion call(s) got $calls: '$(sort -u "$TMP_ROOT/log")'"
  elif grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the hold config was read through the contents API, not the base_config checkout: '$(grep '/contents/' "$TMP_ROOT/log")'"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then
    fail "$label: output lacks '$4': '$out'"
  else
    ok "$label"
  fi
}
