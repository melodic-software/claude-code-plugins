#!/usr/bin/env bash
# Self-contained tests for setup.sh: each case builds a git repository and an
# empty home beside it, so no real layer is read or written.
#
# SC2016 is disabled file-wide: the single-quoted backticks are literal Markdown
# fences written into fixtures, never shell expansions.
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
run() { # run <case> <action> <args...>
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

# A bound convention home moves the team YAML apply writes.
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

# The legacy docs block seeds the YAML and is left as it was.
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
assert_contains "check names the retired .claude file and the migration" "$out" "WARN team: $T/claudefile/repo/.claude/multi-agent.yaml is no longer read; apply --migrate moves its keys into $T/claudefile/repo/docs/conventions/multi-agent.yaml and deletes it"
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

# A symlinked legacy file is not read as a seed.
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

# A symlinked docs file beside a regular .claude file: apply refuses the docs
# file, block or no block, so check must not promise a seed from the .claude file.
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
assert_contains "the .claude file gets the migration row" "$out" "WARN team: $T/mdbeside/repo/.claude/multi-agent.yaml is no longer read; apply --migrate moves its keys into $T/mdbeside/repo/docs/conventions/multi-agent.yaml and deletes it"

# A regular .claude file in a symlinked .claude directory: apply refuses it.
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

fixture mig
mkdir -p "$T/mig/home/.claude" "$T/mig/repo/.claude"
printf 'schema: 1\nroles:\n  worker:\n    effort: high\n' >"$T/mig/home/.claude/multi-agent.yaml"
printf 'schema: 1\nroles:\n  worker:\n    model: sonnet\n' >"$T/mig/repo/.claude/multi-agent.local.yaml"
out="$(run mig check session=opus)"
assert_contains "check: the old user file row names the option" "$out" "WARN user-config: $T/mig/home/.claude/multi-agent.yaml is an old path; set the role_map_file option in /config"
assert_contains "check: the old personal file row names the new path" "$out" "WARN personal-override: $T/mig/repo/.claude/multi-agent.local.yaml is an old path; apply --migrate moves its keys into $T/mig/repo/docs/conventions/multi-agent.local.yaml and deletes it"
assert_contains "check: the dual-read warning names the setup command" "$(cat "$T/mig.err")" '/multi-agent:setup apply --migrate'
run mig apply --layer local --write roles.worker.effort=low >/dev/null
assert_eq "local apply beside the old personal file is refused" 2 "$?"
assert_contains "the refusal names the migration" "$(cat "$T/mig.err")" 'run apply --migrate first'
run mig apply --layer user --write --user-file "$T/mig/role-map.yaml" roles.worker.effort=low >/dev/null
assert_eq "user apply beside the old user file is refused" 2 "$?"
out="$(run mig apply --migrate)"
assert_contains "migrate without the option skips the user file" "$out" "skip: $T/mig/home/.claude/multi-agent.yaml stays until the user layer has a new home"
assert_contains "migrate previews the personal move" "$out" "would move: $T/mig/repo/.claude/multi-agent.local.yaml into $T/mig/repo/docs/conventions/multi-agent.local.yaml (local layer)"
assert_contains "migrate preview shows the keys" "$out" '+    model: sonnet'
state=absent
[[ -e "$T/mig/repo/docs/conventions/multi-agent.local.yaml" ]] && state=present
assert_eq "migrate preview writes nothing" absent "$state"
out="$(run mig apply --migrate --write --user-file "$T/mig/role-map.yaml")"
assert_eq "migrate write exits 0" 0 "$?"
assert_contains "migrate moves the user file" "$out" "moved: $T/mig/home/.claude/multi-agent.yaml into $T/mig/role-map.yaml (user layer)"
assert_contains "migrate moves the personal file" "$out" "moved: $T/mig/repo/.claude/multi-agent.local.yaml into $T/mig/repo/docs/conventions/multi-agent.local.yaml (local layer)"
assert_eq "the user file holds the old keys" $'schema: 1\nroles:\n  worker:\n    effort: high' "$(cat "$T/mig/role-map.yaml")"
state=absent
[[ -e "$T/mig/home/.claude/multi-agent.yaml" || -e "$T/mig/repo/.claude/multi-agent.local.yaml" ]] && state=present
assert_eq "migrate deletes the old files" absent "$state"
out="$(run mig check session=opus --user-file "$T/mig/role-map.yaml")"
assert_contains "after migrate: the same values from the new layers" "$out" '"single":{"model":"sonnet","omit_model":false,"effort":"high","guarded":false},"fanout":{"model":"sonnet","omit_model":false,"effort":"high","guarded":false},"source":{"model":"personal-override","effort":"user-config"}'
assert_lacks "after migrate: no old-path row" "$out" 'old path'
out="$(run mig apply --migrate --user-file "$T/mig/role-map.yaml")"
assert_eq "migrate with no old file says so" "nothing to migrate: no old file found" "$out"

fixture migboth
mkdir -p "$T/migboth/repo/.claude" "$T/migboth/repo/docs/conventions"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n    model: sonnet\n' >"$T/migboth/repo/.claude/multi-agent.local.yaml"
printf 'schema: 1\nroles:\n  worker:\n    effort: high\n' >"$T/migboth/repo/docs/conventions/multi-agent.local.yaml"
out="$(run migboth apply --migrate --write)"
assert_contains "both: the kept key is named" "$out" "kept: roles.worker.effort: high from $T/migboth/repo/docs/conventions/multi-agent.local.yaml (the old file says low)"
assert_eq "both: the old key the new file lacks is added" $'schema: 1\nroles:\n  worker:\n    effort: high\n    model: sonnet' \
  "$(cat "$T/migboth/repo/docs/conventions/multi-agent.local.yaml")"
state=absent
[[ -e "$T/migboth/repo/.claude/multi-agent.local.yaml" ]] && state=present
assert_eq "both: the old file is deleted" absent "$state"

fixture migteam
mkdir -p "$T/migteam/repo/.claude"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/migteam/repo/.claude/multi-agent.yaml"
out="$(run migteam apply --migrate --write)"
assert_contains "team: the retired file moves into the YAML" "$out" "moved: $T/migteam/repo/.claude/multi-agent.yaml into $T/migteam/repo/docs/conventions/multi-agent.yaml (team layer)"
assert_eq "team: the YAML holds its keys" $'schema: 1\nroles:\n  worker:\n    effort: low' "$(cat "$T/migteam/repo/docs/conventions/multi-agent.yaml")"
state=absent
[[ -e "$T/migteam/repo/.claude/multi-agent.yaml" ]] && state=present
assert_eq "team: the retired file is deleted" absent "$state"

mkdir -p "$T/homeroot"
git -C "$T/homeroot" init -q
"$SUT" apply --root "$T/homeroot" --home "$T/homeroot" --layer local roles.worker.effort=low >/dev/null 2>"$T/homeroot.err"
assert_eq "local layer refused at a home root" 2 "$?"
assert_contains "the refusal names the root class" "$(cat "$T/homeroot.err")" 'not applicable at a home root'

"$SUT" apply --root "$T/user/repo" --home "$T/user/home" --layer team >/dev/null 2>&1
assert_eq "apply without a pair is a usage error" 2 "$?"

printf '\n%d cases, %d failed\n' "$CASES" "$FAILED"
((FAILED == 0))
