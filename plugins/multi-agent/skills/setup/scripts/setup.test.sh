#!/usr/bin/env bash
# SC2016 is disabled file-wide: the single-quoted backticks are literal Markdown fences written into fixtures.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

fixture() {
  mkdir -p "$T/$1/repo" "$T/$1/home"
  git -C "$T/$1/repo" init -q
}
run() {
  local c="$1" a="$2"
  shift 2
  "$SUT" "$a" --root "$T/$c/repo" --home "$T/$c/home" "$@" 2>"$T/$c.err"
}

fixture dry
out="$(run dry apply --layer local roles.worker.effort=high)"
assert_contains "dry run names the personal override path" "$out" "would write: $T/dry/repo/docs/conventions/multi-agent.local.yaml"
assert_contains "dry run shows the new key in a diff" "$out" '+    effort: high'
state=absent
[[ -e "$T/dry/repo/docs/conventions/multi-agent.local.yaml" ]] && state=present
assert_eq "dry run writes nothing" absent "$state"

fixture local
out="$(run local apply --layer local --write roles.worker.effort=high fanout.frontier_guard=false)"
assert_contains "write reports the path" "$out" "wrote: $T/local/repo/docs/conventions/multi-agent.local.yaml (local layer)"
assert_contains "write reads the stored value back" "$out" '  fanout.frontier_guard: false'
assert_eq "written file is the rendered subset" "$(cat "$T/local/repo/docs/conventions/multi-agent.local.yaml")" \
  $'schema: 1\nfanout:\n  frontier_guard: false\nroles:\n  worker:\n    effort: high'
out="$(run local check session=fable)"
assert_contains "check shows the personal override as the source" "$out" '"source":{"model":"bundled","effort":"personal-override"}'
assert_contains "check shows the guard off: fan-out inherits under fable" "$out" '"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false}'
assert_contains "check warns when the personal override is not ignored" "$out" 'WARN personal-override'
out="$(run local apply --layer local --write roles.worker.effort=high)"
assert_eq "rerun with the same value is unchanged" "unchanged: $T/local/repo/docs/conventions/multi-agent.local.yaml" "$out"
run local apply --layer local --write fanout.frontier_guard= >/dev/null
assert_lacks "an empty value removes the key" "$(cat "$T/local/repo/docs/conventions/multi-agent.local.yaml")" 'frontier_guard'

fixture reject
run reject apply --layer local --write roles.worker.model=claude-opus-5-5 >/dev/null
assert_eq "a value the resolver rejects exits 1" 1 "$?"
assert_contains "the rejection is relayed" "$(cat "$T/reject.err")" "roles.worker.model rejected"
state=absent
[[ -e "$T/reject/repo/docs/conventions/multi-agent.local.yaml" ]] && state=present
assert_eq "a rejected candidate writes nothing" absent "$state"
run reject apply --layer local --write roles.judge.model=opus >/dev/null
assert_eq "an unknown role exits 1" 1 "$?"

fixture team
out="$(run team apply --layer team --write roles.verifier.effort=xhigh)"
assert_contains "team with no file creates the concern YAML" "$out" "wrote: $T/team/repo/docs/conventions/multi-agent.yaml"
out="$(run team check session=opus)"
assert_contains "the new YAML is the team layer" "$out" '"layer":"team","path":"'"$T/team/repo/docs/conventions/multi-agent.yaml"'","state":"read"'
out="$(run team apply --layer team --write verification=standard)"
assert_contains "team apply writes the verification level" "$(cat "$T/team/repo/docs/conventions/multi-agent.yaml")" 'verification: standard'
run team apply --layer local --write verification=light >/dev/null
assert_eq "local apply of the verification level is a usage error" 2 "$?"
assert_contains "the refusal names the team layer" "$(cat "$T/team.err")" "verification is read from the team layer only"
out="$(run team apply --layer team --write verification_skills.audit-defaults=strict)"
assert_contains "team apply writes a per-skill level" "$(cat "$T/team/repo/docs/conventions/multi-agent.yaml")" 'audit-defaults: strict'
before="$(cat "$T/team/repo/docs/conventions/multi-agent.yaml")"
for bad in verification=Standard verification=lite verification_skills.x=bad; do
  run team apply --layer team --write "$bad" >/dev/null
  assert_eq "$bad is refused as a usage error" 2 "$?"
  assert_contains "$bad: the refusal names the key and value" "$(cat "$T/team.err")" "${bad%%=*}: '${bad#*=}' is not off, light, standard or strict"
  assert_eq "$bad leaves the team file unchanged" "$before" "$(cat "$T/team/repo/docs/conventions/multi-agent.yaml")"
done

fixture bound
mkdir -p "$T/bound/repo/team-docs"
printf '<!-- BEGIN GENERATED: convention-home -->\nConventions live in `team-docs`.\n<!-- END GENERATED: convention-home -->\n' >"$T/bound/repo/AGENTS.md"
out="$(run bound apply --layer team --write roles.verifier.effort=xhigh)"
assert_contains "bound home: team writes the YAML under the home" "$out" "wrote: $T/bound/repo/team-docs/multi-agent.yaml"
state=absent
[[ -e "$T/bound/repo/docs/conventions/multi-agent.yaml" ]] && state=present
assert_eq "bound home: nothing is written under docs/conventions" absent "$state"
out="$(run bound check session=opus)"
assert_contains "bound home: the written YAML is the team layer" "$out" '"layer":"team","path":"'"$T/bound/repo/team-docs/multi-agent.yaml"'","state":"read"'

fixture docs
mkdir -p "$T/docs/repo/docs/conventions"
printf '# Ours\n\nProse.\n\n```yaml config\nschema: 1\nroles:\n  worker:\n    effort: low\n```\n\nTrailer.\n' \
  >"$T/docs/repo/docs/conventions/multi-agent.md"
cp "$T/docs/repo/docs/conventions/multi-agent.md" "$T/docs/legacy.md"
run docs apply --layer team --write roles.verifier.effort=high >/dev/null
assert_eq "docs block: seeded keys and new keys are in the YAML" \
  $'schema: 1\nroles:\n  verifier:\n    effort: high\n  worker:\n    effort: low' \
  "$(cat "$T/docs/repo/docs/conventions/multi-agent.yaml")"
assert_eq "docs block: the legacy file is untouched" "$(cat "$T/docs/legacy.md")" "$(cat "$T/docs/repo/docs/conventions/multi-agent.md")"

fixture claudefile
mkdir -p "$T/claudefile/repo/.claude"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/claudefile/repo/.claude/multi-agent.yaml"
out="$(run claudefile apply --layer team roles.verifier.effort=high)"
assert_contains "team targets the concern YAML, not the .claude file" "$out" "would write: $T/claudefile/repo/docs/conventions/multi-agent.yaml"
assert_contains "the .claude file seeds the preview" "$out" '+    effort: low'
out="$(run claudefile check session=opus)"
assert_contains "check names the retired .claude file and the seed step" "$out" "WARN team: $T/claudefile/repo/.claude/multi-agent.yaml is no longer read; the first apply --layer team copies its keys into $T/claudefile/repo/docs/conventions/multi-agent.yaml, then delete it"
assert_contains "the resolver does not read the retired .claude file" "$out" '"layer":"team","path":"'"$T/claudefile/repo/docs/conventions/multi-agent.yaml"'","state":"absent"'

fixture existing
mkdir -p "$T/existing/repo/docs/conventions"
printf 'schema: 1\nroles:\n  worker:\n    effort: max\n' >"$T/existing/repo/docs/conventions/multi-agent.yaml"
printf '```yaml config\nschema: 1\nroles:\n  worker:\n    effort: low\n```\n' >"$T/existing/repo/docs/conventions/multi-agent.md"
run existing apply --layer team --write roles.verifier.effort=high >/dev/null
assert_eq "an existing YAML is merged, the legacy block is not read" \
  $'schema: 1\nroles:\n  verifier:\n    effort: high\n  worker:\n    effort: max' \
  "$(cat "$T/existing/repo/docs/conventions/multi-agent.yaml")"
out="$(run existing check session=opus)"
assert_contains "check names the retired block beside the YAML" "$out" "WARN team: the config block in $T/existing/repo/docs/conventions/multi-agent.md is no longer read; copy any key still wanted into $T/existing/repo/docs/conventions/multi-agent.yaml, then delete it"
out="$(run team check session=opus)"
assert_lacks "no retired file: no team WARN row" "$out" 'WARN team'

fixture broken
mkdir -p "$T/broken/repo/docs/conventions"
printf 'schema: 1\nroles:\n\tworker:\n' >"$T/broken/repo/docs/conventions/multi-agent.local.yaml"
run broken apply --layer local --write roles.worker.effort=low >/dev/null
assert_eq "an unparsable layer is not overwritten" 1 "$?"
assert_contains "the parse error names the line" "$(cat "$T/broken.err")" 'line 3: tab indentation'

fixture symlink
mkdir -p "$T/symlink/repo/docs/conventions"
printf 'outside\n' >"$T/symlink/victim"
ln -s "$T/symlink/victim" "$T/symlink/repo/docs/conventions/multi-agent.yaml"
run symlink apply --layer team --write roles.worker.effort=low >/dev/null
assert_eq "a symlinked team file is refused" 2 "$?"
assert_eq "the symlink target is untouched" outside "$(cat "$T/symlink/victim")"
assert_contains "the refusal names the symlink" "$(cat "$T/symlink.err")" 'is a symlink'

fixture seedlink
mkdir -p "$T/seedlink/repo/.claude"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/seedlink/victim"
ln -s "$T/seedlink/victim" "$T/seedlink/repo/.claude/multi-agent.yaml"
out="$(run seedlink apply --layer team roles.verifier.effort=high)"
assert_eq "a symlinked .claude seed is refused" 2 "$?"
assert_lacks "the symlinked seed is not in the preview" "$out" 'effort: low'
assert_contains "the seed refusal names the symlink" "$(cat "$T/seedlink.err")" 'is a symlink'

fixture mdlink
mkdir -p "$T/mdlink/repo/docs/conventions"
printf '```yaml config\nschema: 1\nroles:\n  worker:\n    effort: low\n```\n' >"$T/mdlink/victim"
ln -s "$T/mdlink/victim" "$T/mdlink/repo/docs/conventions/multi-agent.md"
out="$(run mdlink apply --layer team roles.verifier.effort=high)"
assert_eq "a symlinked docs seed is refused" 2 "$?"
assert_lacks "the symlinked docs seed is not in the preview" "$out" 'effort: low'
out="$(run mdlink check session=opus)"
assert_contains "check names the symlinked docs file apply refuses" "$out" "WARN team: apply --layer team refuses $T/mdlink/repo/docs/conventions/multi-agent.md while $T/mdlink/repo/docs/conventions/multi-agent.yaml is absent, since $T/mdlink/repo/docs/conventions/multi-agent.md is a symlink; replace or delete the symlink"

fixture mdbeside
mkdir -p "$T/mdbeside/repo/docs/conventions" "$T/mdbeside/repo/.claude"
printf '# Prose only\n' >"$T/mdbeside/victim"
ln -s "$T/mdbeside/victim" "$T/mdbeside/repo/docs/conventions/multi-agent.md"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/mdbeside/repo/.claude/multi-agent.yaml"
run mdbeside apply --layer team roles.verifier.effort=high >/dev/null
assert_eq "a symlinked docs file beside a .claude file is refused" 2 "$?"
out="$(run mdbeside check session=opus)"
assert_contains "check names the symlinked docs file beside a .claude file" "$out" "WARN team: apply --layer team refuses $T/mdbeside/repo/docs/conventions/multi-agent.md while"
assert_lacks "check promises no seed apply would refuse" "$out" 'the first apply --layer team copies'
assert_contains "the .claude file gets the retired team row" "$out" "WARN team: $T/mdbeside/repo/.claude/multi-agent.yaml is no longer read; copy any key still wanted into $T/mdbeside/repo/docs/conventions/multi-agent.yaml, then delete it"

fixture claudedir
mkdir -p "$T/claudedir/outside"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/claudedir/outside/multi-agent.yaml"
ln -s "$T/claudedir/outside" "$T/claudedir/repo/.claude"
run claudedir apply --layer team roles.verifier.effort=high >/dev/null
assert_eq "a .claude file in a symlinked directory is refused" 2 "$?"
out="$(run claudedir check session=opus)"
assert_contains "check names the symlinked .claude directory" "$out" "WARN team: $T/claudedir/repo/.claude/multi-agent.yaml is no longer read, and apply --layer team refuses it while $T/claudedir/repo/docs/conventions/multi-agent.yaml is absent, since $T/claudedir/repo/.claude is a symlink"
assert_lacks "check promises no seed from a symlinked directory" "$out" 'the first apply --layer team copies'

fixture user
run user apply --layer user --write fanout.model=sonnet >/dev/null
assert_eq "user layer with the option unset is refused" 2 "$?"
assert_contains "the refusal names the option" "$(cat "$T/user.err")" 'role_map_file option'
run user apply --layer user --write --user-file '${user_config.role_map_file}' fanout.model=sonnet >/dev/null
assert_eq "an unsubstituted option is unset" 2 "$?"
out="$(run user apply --layer user --write --user-file "$T/user/role-map.yaml" fanout.model=sonnet)"
assert_contains "user layer goes to the option's file" "$out" "wrote: $T/user/role-map.yaml (user layer)"
state=absent
[[ -e "$T/user/home/.claude/multi-agent.yaml" ]] && state=present
assert_eq "nothing is written under ~/.claude" absent "$state"
out="$(run user apply --layer user --write --user-file \~/role-map.yaml fanout.model=sonnet)"
assert_contains "a leading ~/ expands against the home" "$out" "wrote: $T/user/home/role-map.yaml (user layer)"
run user apply --layer user --write --user-file role-map.yaml fanout.model=sonnet >/dev/null
assert_eq "a relative option is refused" 2 "$?"
assert_contains "the refusal asks for an absolute path in /config" "$(cat "$T/user.err")" 'set an absolute path in /config'

fixture oldignored
mkdir -p "$T/oldignored/home/.claude" "$T/oldignored/repo/.claude"
printf 'schema: 1\nroles:\n  worker:\n    effort: high\n' >"$T/oldignored/home/.claude/multi-agent.yaml"
printf 'schema: 1\nroles:\n  worker:\n    model: sonnet\n' >"$T/oldignored/repo/.claude/multi-agent.local.yaml"
out="$(run oldignored check session=opus)"
assert_contains "check: old files are not read and bundled defaults apply" "$out" '"source":{"model":"bundled","effort":"bundled"}'
assert_lacks "check: no old-path warning row" "$out" 'old path'
assert_eq "check: no stderr warning for old files" "" "$(cat "$T/oldignored.err")"
out="$(run oldignored apply --layer local --write roles.worker.effort=low)"
assert_eq "local apply succeeds even when an old personal file exists" 0 "$?"
assert_contains "local apply writes the canonical path" "$out" "wrote: $T/oldignored/repo/docs/conventions/multi-agent.local.yaml (local layer)"
out="$(run oldignored apply --layer user --write --user-file "$T/oldignored/role-map.yaml" roles.worker.effort=low)"
assert_eq "user apply succeeds even when an old user file exists" 0 "$?"
assert_contains "user apply writes the option file" "$out" "wrote: $T/oldignored/role-map.yaml (user layer)"
run oldignored apply --migrate >/dev/null
assert_eq "--migrate is no longer accepted" 2 "$?"

mkdir -p "$T/homeroot"
git -C "$T/homeroot" init -q
"$SUT" apply --root "$T/homeroot" --home "$T/homeroot" --layer local roles.worker.effort=low >/dev/null 2>"$T/homeroot.err"
assert_eq "local layer refused at a home root" 2 "$?"
assert_contains "the refusal names the root class" "$(cat "$T/homeroot.err")" 'not applicable at a home root'

"$SUT" apply --root "$T/user/repo" --home "$T/user/home" --layer team >/dev/null 2>&1
assert_eq "apply without a pair is a usage error" 2 "$?"

fixture vendors
run vendors apply --layer local --write vendors.trials_fail=1 >/dev/null
assert_eq "vendors.trials_fail=1 is refused" 1 "$?"
assert_contains "vendors.trials_fail=1 refusal names the key" "$(cat "$T/vendors.err")" "vendors.trials_fail rejected: '1'"
state=absent
[[ -e "$T/vendors/repo/docs/conventions/multi-agent.local.yaml" ]] && state=present
assert_eq "refused vendors.trials_fail=1 writes nothing" absent "$state"

out="$(run vendors apply --layer local --write vendors.routing=false vendors.trials_prove=3 vendors.trials_fail=2 vendors.codex.in_use=true vendors.codex.rank=1 vendors.sources.terminal-bench.enabled=false)"
assert_eq "valid vendors keys write cleanly" 0 "$?"
out="$(run vendors check session=opus)"
assert_contains "check resolves written vendors keys" "$out" '"routing":false'

fixture tbupgrade
mkdir -p "$T/tbupgrade/repo/docs/conventions"
printf 'schema: 1\nvendors:\n  tiebreak:\n    - fewest-tokens\n    - vendor-order\n  trials_fail: 2\n' >"$T/tbupgrade/repo/docs/conventions/multi-agent.local.yaml"
run tbupgrade apply --layer local --write vendors.routing=false >/dev/null
assert_eq "an unrelated apply over a retired tiebreak list succeeds" 0 "$?"
assert_eq "the apply drops the retired tiebreak list and keeps the rest" $'schema: 1\nvendors:\n  routing: false\n  trials_fail: 2' "$(cat "$T/tbupgrade/repo/docs/conventions/multi-agent.local.yaml")"

fixture tbclear
mkdir -p "$T/tbclear/repo/docs/conventions"
printf 'schema: 1\nvendors:\n  tiebreak: [most-usage-left, vendor-order]\n  trials_fail: 2\n' >"$T/tbclear/repo/docs/conventions/multi-agent.local.yaml"
run tbclear apply --layer local --write vendors.tiebreak= >/dev/null
assert_eq "vendors.tiebreak= over a retired list succeeds" 0 "$?"
assert_eq "vendors.tiebreak= removes every child of the list" $'schema: 1\nvendors:\n  trials_fail: 2' "$(cat "$T/tbclear/repo/docs/conventions/multi-agent.local.yaml")"

printf '\n%d cases, %d failed\n' "$CASES" "$FAILED"
((FAILED == 0))
