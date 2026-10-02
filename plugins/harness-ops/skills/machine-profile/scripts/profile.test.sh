#!/usr/bin/env bash
# The machine profile discovers read-only, refuses records without an observation,
# diffs both sides, and applies nothing without a confirm. Every case runs against a
# scratch HOME fixture.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/profile.sh"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; }
expect_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
expect_has() { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
expect_lacks() { if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no $2" "$3"; fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is not installed"; exit 0; }
# The byte-identical hash needs both; without them it would hash empty input and pass vacuously.
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: sha256sum is not installed"; exit 0; }
find . -maxdepth 0 -printf '' >/dev/null 2>&1 || { echo "SKIP: find -printf is not available"; exit 0; }

# FIX is the fixture HOME and repository. OUT holds everything a probe could
# write (data directory, npm cache and logs) so the fixture hash stays meaningful.
FIX="$(mktemp -d)"
OUT="$(mktemp -d)"
trap 'chmod -R u+w "$FIX" 2>/dev/null; rm -rf "$FIX" "$OUT"' EXIT
export HOME="$FIX/home"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export npm_config_cache="$OUT/npm-cache"
export npm_config_logs_dir="$OUT/npm-logs"
export NO_UPDATE_NOTIFIER=1
DATA="$OUT/data"
STORE="$DATA/machine-profile/profile.json"

mkdir -p "$HOME/work" "$HOME/oss" "$HOME/lab" "$FIX/repo" "$DATA"
cat >"$HOME/.gitconfig" <<'EOF'
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
[includeIf "gitdir/i:~/oss/"]
    path = .gitconfig-oss
[includeIf "gitdir:~/lab/**"]
    path = ~/.gitconfig-lab
EOF
printf '[user]\n\temail = work@example.invalid\n' >"$HOME/.gitconfig-work"
printf '[user]\n\temail = oss@example.invalid\n' >"$HOME/.gitconfig-oss"
# shellcheck disable=SC2016  # the fixture .envrc holds the literal text
printf 'export GH_CONFIG_DIR="$HOME/.config/gh-work"\n' >"$HOME/work/.envrc"
# shellcheck disable=SC2016  # the fixture .envrc holds the literal text
printf 'export GH_CONFIG_DIR="$(pwd)/.gh"\n' >"$HOME/lab/.envrc"
printf 'tool\tplugin\tstatus\tcheck\tinstall\nfixture-present\tplug-a\tpresent\t/plug-a:check\tinstall a\nfixture-missing\tplug-b\tmissing\t/plug-b:setup check\t\nmissing=1 present=1\n' >"$FIX/prereq.tsv"
git -C "$FIX/repo" init -q
git -C "$FIX/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -q -m init
git -C "$FIX/repo" config 'includeIf.gitdir:~/scratch/.path' "$HOME/.gitconfig-oss"
printf '[includeIf "gitdir:~/decoy/"]\n\tpath = ~/.gitconfig-oss\n' >"$FIX/decoy"
chmod 444 "$HOME/.gitconfig-work"

tree_hash() {
  (cd "$1" && {
    find . -printf '%P %y %m %s %T@\n' | LC_ALL=C sort
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  }) | sha256sum
}
state_hash() { printf '%s %s %s\n' "$(tree_hash "$FIX")" "$(tree_hash "$DATA")" "$(tree_hash "$OUT")"; }

run() { (cd "$FIX/repo" && bash "$SCRIPT" "$@"); }

# 1. Read-only discovery and the unchanged-machine rerun.
before="$(tree_hash "$FIX")"
first="$(run discover --prerequisites "$FIX/prereq.tsv" </dev/null)"
rc=$?
second="$(run discover --prerequisites "$FIX/prereq.tsv" </dev/null)"
expect_eq "discover exits 0" 0 "$rc"
expect_eq "discover prints only a JSON document, with no prompt" "true" "$(jq -e 'type == "object"' <<<"$first" >/dev/null 2>&1 && echo true || echo false)"
expect_eq "two discoveries of an unchanged fixture match" "$first" "$second"
expect_eq "discover leaves the fixture HOME and repository byte-identical" "$before" "$(tree_hash "$FIX")"
from_home="$(cd "$HOME" && bash "$SCRIPT" discover --prerequisites "$FIX/prereq.tsv" </dev/null)"
with_decoy="$(GIT_CONFIG="$FIX/decoy" run discover --prerequisites "$FIX/prereq.tsv" </dev/null)"
expect_eq "discovery gives the same document from another directory" "$first" "$from_home"
expect_eq "discovery gives the same document under an exported GIT_CONFIG" "$first" "$with_decoy"
expect_lacks "a repository-local includeIf is not a machine domain" "scratch" "$first"

expect_eq "one domain per includeIf tree" "$HOME/lab $HOME/oss $HOME/work" "$(jq -r '.domains | keys | join(" ")' <<<"$first")"
expect_eq "git_include resolves relative to the including file" "$HOME/.gitconfig-oss" "$(jq -r --arg d "$HOME/oss" '.domains[$d].identity.git_include.value' <<<"$first")"
expect_eq "gh_config_dir is read from the tree's own .envrc" "$HOME/.config/gh-work" "$(jq -r --arg d "$HOME/work" '.domains[$d].identity.gh_config_dir.value' <<<"$first")"
expect_eq "a tree with no .envrc is default-unexamined" "default-unexamined" "$(jq -r --arg d "$HOME/oss" '.domains[$d].identity.gh_config_dir.verdict' <<<"$first")"
expect_eq "an unexamined gh_config_dir carries skipped_because and no observed_by" "true false" "$(jq -r --arg d "$HOME/oss" '.domains[$d].identity.gh_config_dir | "\(.skipped_because != null) \(has("observed_by"))"' <<<"$first")"
expect_has "a computed GH_CONFIG_DIR is not read statically" "computes GH_CONFIG_DIR" "$(jq -r --arg d "$HOME/lab" '.domains[$d].identity.gh_config_dir.skipped_because' <<<"$first")"
expect_eq "the machine's gh directory is not copied to a tree" "false" "$(GH_CONFIG_DIR="$FIX/machine-gh" run discover | jq -r --arg d "$HOME/oss" '.domains[$d].identity.gh_config_dir | has("value")')"
expect_eq "a binary on the table is present" "present" "$(jq -r '.machine.facts[] | select(.key == "binary.fixture-present") | .value' <<<"$first")"
expect_eq "a missing binary is default-verified with an observation" "default-verified" "$(jq -r '.machine.facts[] | select(.key == "binary.fixture-missing") | .verdict' <<<"$first")"
expect_eq "a :setup check row is labeled reproduced" "reproduced" "$(jq -r '.machine.facts[] | select(.key == "binary.fixture-missing") | .mode' <<<"$first")"
expect_eq "a :check row is labeled observed" "observed" "$(jq -r '.machine.facts[] | select(.key == "binary.fixture-present") | .mode' <<<"$first")"
no_table="$(run discover)"
expect_eq "without a table, binaries is default-unexamined" "default-unexamined" "$(jq -r '.machine.facts[] | select(.key == "binaries") | .verdict' <<<"$no_table")"
if [[ "$(id -u)" -ne 0 ]]; then
  expect_eq "a read-only include file is blocked with the operator command" "blocked" "$(jq -r --arg d "$HOME/work" '.domains[$d].facts[] | select(.key | startswith("git_include_file:")) | .verdict' <<<"$first")"
  expect_has "the blocked guard names the operator command" "chmod u+w" "$(jq -r --arg d "$HOME/work" '.domains[$d].facts[] | select(.verdict == "blocked") | .guard' <<<"$first")"
fi

# 1b. A credential word in a key discovery derives (an include path, a binary
# name) does not abort discover, and the document survives record, diff and explain.
CRED="$OUT/credpath"
mkdir -p "$CRED/home/secret-dir" "$CRED/home/Token_dir"
printf '[includeIf "gitdir:~/sx/"]\n\tpath = ~/secret-dir/gitconfig\n[includeIf "gitdir:~/tx/"]\n\tpath = ~/Token_dir/gitconfig\n' >"$CRED/gitconfig"
printf '[user]\n\temail = x@example.invalid\n' >"$CRED/home/secret-dir/gitconfig"
cred="$(HOME="$CRED/home" GIT_CONFIG_GLOBAL="$CRED/gitconfig" run discover </dev/null)"
rc=$?
expect_eq "an include path naming secret or token still discovers" 0 "$rc"
expect_eq "both include trees are recorded" 2 "$(jq '.domains | length' <<<"$cred")"
expect_eq "an include path with a credential word keeps its fact" "writable" "$(jq -r '.domains[] | .facts[] | select(.key | startswith("git_include_file:")) | .value' <<<"$cred" | head -n 1)"
expect_eq "no include-path fact key matches the credential pattern" "0" "$(jq '[.domains[].facts[].key | select(test("token|secret|password|credential"; "i"))] | length' <<<"$cred")"
expect_has "the include path stays readable in its key" "[T]oken_dir/gitconfig" "$(jq -r '.domains[].facts[].key' <<<"$cred")"

printf 'tool\tplugin\tstatus\tcheck\tinstall\nsecret-tool\tplug-a\tpresent\t/plug-a:check\tx\ngit-credential-manager\tplug-a\tmissing\t/plug-a:check\tx\ndocker-credential-pass\tplug-b\tpresent\t/plug-b:check\t\nsecretoken\tplug-b\tpresent\t/plug-b:check\t\n' >"$OUT/credbin.tsv"
CREDDATA="$OUT/creddata"
credbin="$(run discover --prerequisites "$OUT/credbin.tsv" </dev/null)"
rc=$?
expect_eq "a declared binary named for a credential tool still discovers" 0 "$rc"
expect_eq "each credential word in a binary key is bracketed, overlaps included" "binary.[s]ecre[t]oken binary.[s]ecret-tool binary.docker-[c]redential-pass binary.git-[c]redential-manager" "$(jq -r '[.machine.facts[].key | select(startswith("binary."))] | sort | join(" ")' <<<"$credbin")" # spellchecker:disable-line
expect_eq "a credential-named binary keeps its observed value" "present" "$(jq -r '.machine.facts[] | select(.key == "binary.[s]ecret-tool") | .value' <<<"$credbin")" # spellchecker:disable-line
expect_eq "no discovered key matches the credential pattern" "0" "$(jq '[.machine.facts[].key | select(test("token|secret|password|credential"; "i"))] | length' <<<"$credbin")"
run record --data-dir "$CREDDATA" --confirm - <<<"$credbin" >/dev/null 2>&1
expect_eq "record accepts the discovered document" 0 "$?"
out="$(run diff --data-dir "$CREDDATA" --prerequisites "$OUT/credbin.tsv" </dev/null 2>&1)"
rc=$?
expect_eq "diff of the stored credential-named keys exits 0" 0 "$rc"
expect_eq "diff of the stored credential-named keys prints nothing" "" "$out"
expect_has "explain resolves a bracketed key" '"verdict":"set"' "$(run explain --data-dir "$CREDDATA" 'binary.[s]ecret-tool' 2>&1)" # spellchecker:disable-line

# 1c. A drive-letter origin resolves a relative include against the including file,
# and a tree reached through two origins keeps both observations.
REAL_GIT="$(command -v git)"
STUB="$OUT/stub"
mkdir -p "$STUB"
cat >"$STUB/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "config --list --show-origin" ]]; then
  printf 'file:C:/cfg/.gitconfig\tincludeif.gitdir:~/w/.path=.gitconfig-work\n'
  printf 'file:/etc/gitconfig\tincludeif.gitdir:~/w/.path=/etc/gitconfig-corp\n'
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB/git"
multi="$(PATH="$STUB:$PATH" run discover </dev/null)"
expect_has "a drive-letter origin resolves a relative include against its file" 'git_include_file:C:/cfg/.gitconfig-work' "$(jq -r '.domains[].facts[].key' <<<"$multi")"
expect_eq "a drive-letter include is not resolved against the repository" "0" "$(jq '[.domains[].facts[].key | select(contains("repo/"))] | length' <<<"$multi")"
expect_eq "a tree reached through two origins names both in observed_by" "2" "$(jq '.domains[].identity.git_include.observed_by | split("; ") | length' <<<"$multi")"

# 2. Store, then diff an unchanged fixture: an empty diff and no prompt.
dry="$(run record --data-dir "$DATA" - <<<"$first")"
expect_has "record without --confirm says nothing was written" "dry run, nothing written" "$dry"
expect_eq "record without --confirm writes no document" "absent" "$([[ -e "$STORE" ]] && echo present || echo absent)"
wrote="$(run record --data-dir "$DATA" --confirm - <<<"$first")"
expect_has "record --confirm writes the document" "wrote $STORE" "$wrote"
out="$(run diff --data-dir "$DATA" --prerequisites "$FIX/prereq.tsv")"
rc=$?
expect_eq "diff of an unchanged fixture exits 0" 0 "$rc"
expect_eq "diff of an unchanged fixture prints nothing" "" "$out"

# 3. A changed value reports both values and both observed_by entries.
# shellcheck disable=SC2016  # the fixture .envrc holds the literal text
printf 'export GH_CONFIG_DIR="$HOME/.config/gh-work-two"\n' >"$HOME/work/.envrc"
out="$(run diff --data-dir "$DATA" --prerequisites "$FIX/prereq.tsv")"
rc=$?
expect_eq "diff exits 4 when a value differs" 4 "$rc"
expect_has "diff names the changed path" "changed domains.$HOME/work.identity.gh_config_dir" "$out"
expect_has "diff shows the stored value" "stored: $HOME/.config/gh-work [set]" "$out"
expect_has "diff shows the fresh value" "fresh:  $HOME/.config/gh-work-two [set]" "$out"
expect_has "diff shows both observed_by entries" "observed_by: grep 'export GH_CONFIG_DIR' $HOME/work/.envrc" "$out"
rm -rf "$HOME/lab"
out="$(run diff --data-dir "$DATA" --prerequisites "$FIX/prereq.tsv")"
expect_has "diff reports a vanished tree as a changed fact" "changed domains.$HOME/lab.facts.tree_present" "$out"
# shellcheck disable=SC2016  # the fixture .envrc holds the literal text
printf 'export GH_CONFIG_DIR="$HOME/.config/gh-work"\n' >"$HOME/work/.envrc"
mkdir -p "$HOME/lab"

# explain shows the observation behind one value.
out="$(run explain --data-dir "$DATA" cores)"
expect_has "explain prints the record behind a key" '"observed_by"' "$out"
run explain --data-dir "$DATA" no-such-key >/dev/null 2>&1
expect_eq "explain refuses an unknown key" 1 "$?"

# 4. The writer refuses records without an observation.
before_store="$(cat "$STORE")"
doc_with() { jq -nc --argjson r "$1" '{machine: {facts: [$r]}, domains: {}}'; }
refuse() { # NAME RECORD
  local msg rc
  msg="$(run record --data-dir "$DATA" --confirm - <<<"$(doc_with "$2")" 2>&1)"
  rc=$?
  expect_eq "$1: exit 1" 1 "$rc"
  expect_eq "$1: the stored document is unchanged" "$before_store" "$(cat "$STORE")"
  REFUSAL="$msg"
}
accept() { # NAME RECORD
  local rc
  run record --data-dir "$DATA" --confirm - <<<"$(doc_with "$2")" >/dev/null 2>&1
  rc=$?
  expect_eq "$1: exit 0" 0 "$rc"
  run record --data-dir "$DATA" --confirm - <<<"$before_store" >/dev/null 2>&1
}
refuse "an empty observed_by is refused" '{"key":"k","value":"v","verdict":"set","observed_by":"","mode":"observed","supplied_by":"host"}'
expect_has "the refusal names the missing observed_by" "has no observed_by" "$REFUSAL"
refuse "an absent observed_by is refused" '{"key":"k","value":"v","verdict":"set","mode":"observed","supplied_by":"host"}'
refuse "an empty record is refused" '{}'
refuse "default-verified without an observation is refused" '{"key":"k","value":"","verdict":"default-verified","observed_by":"ls /x","mode":"observed"}'
expect_has "the refusal names the missing observation" "default-verified requires an observation" "$REFUSAL"
refuse "default-verified with an empty observed_by is refused" '{"key":"k","value":"","verdict":"default-verified","observed_by":"","observation":"found nothing","mode":"observed"}'
refuse "default-unexamined without skipped_because is refused" '{"key":"k","verdict":"default-unexamined"}'
expect_has "the refusal names the missing skipped_because" "requires skipped_because" "$REFUSAL"
refuse "default-unexamined that claims an observation is refused" '{"key":"k","verdict":"default-unexamined","skipped_because":"not looked at","observed_by":"ls /x"}'
refuse "a bare keep verdict is refused" '{"key":"k","value":"v","verdict":"keep","observed_by":"ls","mode":"observed"}'
refuse "an unknown mode is refused" '{"key":"k","value":"v","verdict":"set","observed_by":"ls","mode":"guessed","supplied_by":"host"}'
refuse "blocked without a guard is refused" '{"key":"k","value":"v","verdict":"blocked","observed_by":"ls","mode":"observed"}'
refuse "set without supplied_by is refused" '{"key":"k","value":"v","verdict":"set","observed_by":"ls","mode":"observed"}'
refuse "a credential value is refused" '{"key":"k","value":"ghp_abcdefghijklmnopqrstuvwxyz0123","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a new-format GitHub App token value is refused" '{"key":"k","value":"ghs'"_1234567_FAKEheader.FAKEpayload.FAKEsignature"'","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a credential key is refused" '{"key":"api_token","value":"x","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a sensitive userConfig key is refused" '{"key":"dometrain-mcp.dometrain_api_key","value":"x","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "an AWS access key value is refused" '{"key":"k","value":"AKIA'"IOSFODNN7EXAMPLE"'","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a Slack token value is refused" '{"key":"k","value":"xoxb-123456789012-abcdefghij","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a URL with an embedded password is refused" '{"key":"k","value":"postgres://admin:Sup3rPassw0rd@host/db","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
refuse "a private key block is refused" '{"key":"k","value":"-----BEGIN RSA PRIVATE KEY-----","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
accept "a path with sk- inside a word is accepted" '{"key":"k","value":"/work/task-management-system-notes-dir","verdict":"set","observed_by":"ls","mode":"observed","supplied_by":"host"}'
dup_opts="$(jq -c '{machine: {facts: [], options: [{key:"o",value:"a",verdict:"set",observed_by:"ls",mode:"observed",supplied_by:"host"},{key:"o",value:"b",verdict:"set",observed_by:"ls",mode:"observed",supplied_by:"host"}]}, domains: {}}' <<<'{}')"
msg="$(run record --data-dir "$DATA" --confirm - <<<"$dup_opts" 2>&1)"
expect_eq "duplicate option keys are refused: exit 1" 1 "$?"
expect_has "the refusal names the duplicate option key" "machine.options: duplicate key o" "$msg"
accept "default-unexamined with skipped_because is accepted" '{"key":"k","verdict":"default-unexamined","skipped_because":"no discovery source is defined for it"}'
accept "default-verified with an observation is accepted" '{"key":"k","value":"","verdict":"default-verified","observed_by":"ls /x","mode":"observed","observation":"directory not found"}'

# 5. A missing document reads as no profile, with no fallback.
empty="$OUT/empty"
mkdir -p "$empty"
out="$(run diff --data-dir "$empty" 2>&1)"
rc=$?
expect_eq "a missing document exits 3" 3 "$rc"
expect_has "a missing document reads as no profile" "no profile for this machine" "$out"
expect_eq "a missing document is not created by reading" "" "$(find "$empty" -mindepth 1)"
# shellcheck disable=SC2016  # the unresolved token, literally
run diff --data-dir '${CLAUDE_PLUGIN_DATA}' >/dev/null 2>&1
expect_eq "an unresolved data directory is a usage error" 2 "$?"

# 6. apply writes nothing without a confirm, and never applies a per-domain identity.
opts="$(jq -c --arg d "$HOME/work" '
  .machine.options = [{key: "plug-a.registry_dir", value: "reports", verdict: "set", observed_by: "cat user settings", mode: "observed", supplied_by: "user-global"},
                      {key: "plug-a.unset_option", verdict: "default-unexamined", skipped_because: "not looked at"}]
  | .domains[$d].options = [{key: "plug-b.profile", value: "work", verdict: "set", observed_by: "cat include", mode: "observed", supplied_by: "git include"}]' <<<"$first")"
run record --data-dir "$DATA" --confirm - <<<"$opts" >/dev/null
before="$(state_hash)"
out="$(run apply --data-dir "$DATA" --option plug-a.registry_dir --option plug-b.profile)"
expect_eq "apply without --confirm writes nothing" "$before" "$(state_hash)"
expect_has "apply without --confirm prints the plan" "plan plug-a.registry_dir" "$out"
expect_lacks "apply without --confirm hands nothing off" "handoff" "$out"
expect_has "apply without --confirm says so" "not confirmed" "$out"
out="$(run apply --data-dir "$DATA" --option plug-a.registry_dir --option plug-b.profile --option plug-a.unset_option --confirm)"
expect_eq "apply --confirm writes nothing itself" "$before" "$(state_hash)"
expect_has "apply --confirm hands the machine option to its setup" "handoff plug-a.registry_dir" "$out"
expect_has "apply stops for a per-domain identity option" "conflict plug-b.profile" "$out"
expect_lacks "apply never hands off a per-domain identity" "handoff plug-b.profile" "$out"
expect_has "apply skips an option with no non-default value" "skipped plug-a.unset_option" "$out"
run apply --data-dir "$DATA" --option plug-a.missing >/dev/null
expect_eq "apply refuses an unknown option" 1 "$?"
run apply --data-dir "$DATA" >/dev/null 2>&1
expect_eq "apply without a selected option is a usage error" 2 "$?"

# 7. None of the read paths changed the fixture.
run discover --prerequisites "$FIX/prereq.tsv" >/dev/null
run diff --data-dir "$DATA" --prerequisites "$FIX/prereq.tsv" >/dev/null
run explain --data-dir "$DATA" cores >/dev/null
expect_eq "no read path changed the fixture HOME or repository" "$before" "$(state_hash)"

if [[ "$FAILED" -ne 0 ]]; then
  printf '%s case(s) failed\n' "$FAILED" >&2
  exit 1
fi
echo "all cases passed"
