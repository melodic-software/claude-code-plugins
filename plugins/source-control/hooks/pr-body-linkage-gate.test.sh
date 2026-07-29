#!/usr/bin/env bash
# Black-box contract test for pr-body-linkage-gate.sh.
#
# Asserts the hook's OWN behavior against expectations transcribed by hand from
# a reading of the ci-workflows pr-issue-linkage validator — deliberately not a
# claim that the two agree, because nothing here executes the validator. A real
# mirroring proof needs the validator itself as an oracle, which would mean
# vendoring a copy of upstream JavaScript into this repo; see the PR that added
# this file for why that is a separate decision. What these cases DO cover is
# every shape a hand port gets wrong: comment stripping (terminated and
# unterminated), a `## Related` section whose content is a deeper subsection,
# the JavaScript word boundaries that make `#12abc` and `unclosed #5`
# non-matches, the locale-dependence of `[[:space:]]`, and that every
# undeterminable body ALLOWS.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures and
# invokes the hook as a subprocess from an UNRELATED cwd, so any reliance on the
# caller's working directory would surface (the hook is anchored on the payload's
# own `cwd`).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-body-linkage-gate.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-body-linkage-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# new_repo <dir> <yml|yaml|plain> — a throwaway repo, optionally carrying the
# gate workflow under either spelling the hook accepts.
new_repo() {
  local r="$1" gated="$2"
  mkdir -p "$r"
  git -C "$r" init -q 2>/dev/null
  case "$gated" in
  yml | yaml)
    mkdir -p "$r/.github/workflows"
    printf 'name: pr-issue-linkage\n' >"$r/.github/workflows/pr-issue-linkage.$gated"
    ;;
  *) ;;
  esac
}

GATED="$WORK/gated"
UNGATED="$WORK/ungated"
GATED_YAML="$WORK/gated-yaml"
OTHER="$WORK/other"
new_repo "$GATED" yml
new_repo "$UNGATED" plain
new_repo "$GATED_YAML" yaml
new_repo "$OTHER" yml

# run <repo> <command> -> sets RC and ERR from one hook invocation.
RC=0
ERR=""
run() {
  local repo="$1" cmd="$2" payload
  payload=$(jq -n --arg cwd "$repo" --arg cmd "$cmd" \
    '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
  ERR=$(cd "$UNRELATED" && printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
}

# assert_allow / assert_block <label> <repo> <command>
assert_allow() {
  run "$2" "$3"
  if ((RC == 0)); then ok "$1"; else fail "$1: expected allow, got rc=$RC ($ERR)"; fi
}
assert_block() {
  run "$2" "$3"
  if ((RC == 2)); then ok "$1"; else fail "$1: expected block(2), got rc=$RC ($ERR)"; fi
}

# gh_body <body> -> a `gh pr create` command carrying <body> as a single-quoted
# literal. Bodies in this suite never contain a single quote.
gh_body() {
  printf "gh pr create --title 'T' --body '%s'" "$1"
}

GOOD=$'Closes #5\n\n## Related\n\n- refs #9'
NO_RELATED=$'Closes #5\n\nJust a summary.'
NO_KEYWORD=$'Some summary.\n\n## Related\n\n- refs #9'

# --- Scope guard -------------------------------------------------------------

assert_allow "ungated repo: bad body allowed" "$UNGATED" "$(gh_body "$NO_RELATED")"
assert_allow "non-gh command allowed" "$GATED" "git commit -m 'x'"
assert_allow "gh command that is not pr create/edit allowed" "$GATED" "gh pr view 5"

# --- The two halves ----------------------------------------------------------

assert_allow "compliant body allowed" "$GATED" "$(gh_body "$GOOD")"
assert_block "missing ## Related blocks" "$GATED" "$(gh_body "$NO_RELATED")"
assert_block "missing closing keyword blocks" "$GATED" "$(gh_body "$NO_KEYWORD")"
assert_block "empty ## Related blocks" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n\n## Test plan\n\n- ran it')"

run "$GATED" "$(gh_body "$NO_RELATED")"
if [[ "$ERR" == *'Missing a "## Related" section.'* && "$ERR" == *"## Related"* && "$ERR" == *"Closes #<issue>"* ]]; then
  ok "block message names the missing half and the line to add"
else
  fail "block message lacks the missing half or the template: $ERR"
fi

# --- Closing-keyword shapes --------------------------------------------------

for kw in Closes closes Closed Fixes fix fixed Resolves resolve resolved; do
  assert_allow "keyword '$kw' accepted" "$GATED" \
    "$(gh_body "$kw #5"$'\n\n## Related\n\n- x')"
done
assert_allow "colon form accepted" "$GATED" \
  "$(gh_body $'Closes: #5\n\n## Related\n\n- x')"
assert_allow "owner/repo#N form accepted" "$GATED" \
  "$(gh_body $'Closes melodic-software/standards#5\n\n## Related\n\n- x')"
assert_allow "No linked issue marker accepted" "$GATED" \
  "$(gh_body $'No linked issue\n\n## Related\n\n- x')"
assert_allow "No related issue: marker accepted" "$GATED" \
  "$(gh_body $'No related issue: drift sweep\n\n## Related\n\n- x')"

# Word boundaries: JavaScript's \b makes both of these non-matches, so a body
# carrying only one of them must still block.
assert_block "trailing word char after #N is not a match" "$GATED" \
  "$(gh_body $'Closes #12abc\n\n## Related\n\n- x')"
assert_block "keyword glued to a preceding word is not a match" "$GATED" \
  "$(gh_body $'unclosed #5\n\n## Related\n\n- x')"

# --- HTML comments -----------------------------------------------------------

assert_block "markers only inside a terminated comment do not count" "$GATED" \
  "$(gh_body $'<!-- Closes #5 and a ## Related section -->\n\nSummary.')"
assert_block "an unterminated comment swallows the rest of the body" "$GATED" \
  "$(gh_body $'Summary.\n<!-- oops\nCloses #5\n\n## Related\n\n- x')"
assert_allow "content around a comment still counts" "$GATED" \
  "$(gh_body $'Closes #5 <!-- issue --> \n\n## Related\n<!-- list below -->\n- x')"

# --- Section boundaries ------------------------------------------------------

assert_allow "a deeper subsection is Related's content, not its terminator" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n\n### Prior art\n\n- x\n\n## Test plan\n\n- ran it')"
assert_block "a same-level heading terminates Related, leaving it empty" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n## Summary\n\n- x')"
assert_allow "Related is matched case-insensitively" "$GATED" \
  "$(gh_body $'Closes #5\n\n##   RELATED\n\n- x')"
assert_block "a Related heading with trailing text is not the section" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related work\n\n- x')"

# --- Body sources ------------------------------------------------------------

printf '%s\n' "$NO_RELATED" >"$GATED/body.md"
assert_block "--body-file reads the file" "$GATED" "gh pr create -t T --body-file body.md"
printf '%s\n' "$GOOD" >"$GATED/good.md"
assert_allow "--body-file with a compliant file allowed" "$GATED" "gh pr create -t T -F good.md"
assert_allow "--body-file naming a missing file allowed" "$GATED" "gh pr create -t T -F absent.md"

assert_block "--body-file - reads the sole heredoc" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$NO_RELATED")"
assert_allow "--body-file - with a compliant heredoc allowed" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$GOOD")"
assert_block "--body \$(cat <<EOF) substitution is read" "$GATED" \
  "$(printf "gh pr create -t T --body \"\$(cat <<'EOF'\n%s\nEOF\n)\"\n" "$NO_RELATED")"
assert_allow "two heredocs are undeterminable" "$GATED" \
  "$(printf "cat <<'A' >x\njunk\nA\ngh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$NO_RELATED")"
assert_allow "an unterminated heredoc is undeterminable" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\n" "$NO_RELATED")"
# shellcheck disable=SC2016  # the literal, unexpanded $BODY is the fixture under test
assert_allow "a variable body is undeterminable" "$GATED" 'gh pr create -t T --body "$BODY"'
assert_allow "--fill carries no body flag" "$GATED" "gh pr create -t T --fill"
assert_allow "interactive create carries no body flag" "$GATED" "gh pr create"
assert_block "attached short-flag value is read" "$GATED" "$(printf "gh pr create -t T -b'%s'" "$NO_RELATED")"
assert_block "--body=VALUE form is read" "$GATED" "$(printf "gh pr create -t T --body='%s'" "$NO_RELATED")"
assert_block "an empty literal body blocks" "$GATED" "gh pr create -t T --body ''"
assert_allow "a trailing --body with no value is malformed, not empty" "$GATED" "gh pr create -t T --body"
assert_allow "a trailing --body-file with no value is malformed" "$GATED" "gh pr create -t T --body-file"
assert_allow "everything after -- is positional" "$GATED" "gh pr create -t T -- --body bad"
assert_allow "a body-file naming a directory is unreadable" "$GATED" "gh pr create -t T --body-file ."

# A body-shaped string sitting in another flag's value is not the body.
assert_allow "a label value spelled --body is not the body" "$GATED" \
  "gh pr create -t T -l --body --fill"

# --- gh pr edit --------------------------------------------------------------

assert_block "gh pr edit --body is gated" "$GATED" "$(printf "gh pr edit 5 --body '%s'" "$NO_RELATED")"
assert_block "gh pr edit --body-file is gated" "$GATED" "gh pr edit 5 --body-file body.md"
assert_allow "gh pr edit changing no body allowed" "$GATED" "gh pr edit 5 --add-label ready"
assert_allow "gh pr new alias with a compliant body allowed" "$GATED" \
  "$(printf "gh pr new -t T --body '%s'" "$GOOD")"

# --- Wrappers and out-of-scope targets ---------------------------------------

assert_block "env-assignment wrapper is unwrapped" "$GATED" \
  "$(printf "GH_TOKEN=x gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "env(1) wrapper is unwrapped" "$GATED" \
  "$(printf "env GH_TOKEN=x gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sh -c operand is re-parsed" "$GATED" \
  "$(printf "bash -c \"gh pr create -t T --body '%s'\"" "$NO_RELATED")"
assert_allow "--repo targets a repo whose gate is unknown" "$GATED" \
  "$(printf "gh pr create -R other/repo -t T --body '%s'" "$NO_RELATED")"
assert_allow "-R attached form is out of scope too" "$GATED" \
  "$(printf "gh pr create -Rother/repo -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo wrapper is unwrapped" "$GATED" \
  "$(printf "sudo gh pr create -t T --body '%s'" "$NO_RELATED")"
# A wrapper option's SEPARATED value sits where the command name is expected;
# skipping the flag alone leaves the gate looking at the value.
assert_block "sudo -u root consumes its value" "$GATED" \
  "$(printf "sudo -u root gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -uroot attaches its value" "$GATED" \
  "$(printf "sudo -uroot gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo --user=root attaches its value" "$GATED" \
  "$(printf "sudo --user=root gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -- ends its own options" "$GATED" \
  "$(printf "sudo -- gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "env -u VAR consumes its value" "$GATED" \
  "$(printf "env -u GH_TOKEN gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -r role consumes its SELinux value" "$GATED" \
  "$(printf "sudo -r staff_r gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -t type consumes its SELinux value" "$GATED" \
  "$(printf "sudo -t sysadm_t gh pr create -t T --body '%s'" "$NO_RELATED")"

# A wrapper that moves the working directory or the root is the `cd` case
# wearing a flag: the gate file and a relative body path resolve elsewhere.
assert_allow "env -C moves the directory" "$GATED" \
  "$(printf "env -C %s gh pr create -t T --body '%s'" "$UNGATED" "$NO_RELATED")"
assert_allow "env --chdir= moves the directory" "$GATED" \
  "$(printf "env --chdir=%s gh pr create -t T --body '%s'" "$UNGATED" "$NO_RELATED")"
assert_allow "sudo -D moves the directory" "$GATED" \
  "$(printf "sudo -D %s gh pr create -t T --body '%s'" "$UNGATED" "$NO_RELATED")"
assert_allow "sudo -R moves the filesystem root" "$GATED" \
  "$(printf "sudo -R %s gh pr create -t T --body '%s'" "$UNGATED" "$NO_RELATED")"

# `env -S` carries an entire command line in one operand; it is a command to
# re-parse, not a value to step over.
assert_block "env -S operand is re-parsed" "$GATED" \
  "$(printf "env -S \"gh pr create -t T --body '%s'\"" "$NO_RELATED")"
assert_block "env --split-string= operand is re-parsed" "$GATED" \
  "$(printf "env --split-string=\"gh pr create -t T --body '%s'\"" "$NO_RELATED")"
assert_allow "env -S carrying a compliant body allowed" "$GATED" \
  "$(printf "env -S \"gh pr create -t T --body '%s'\"" "$GOOD")"

# A short wrapper word is a CLUSTER, not one flag: `sudo -Eu root` is valid, and
# reading it as a single unknown flag leaves `root` where the command belongs.
assert_block "sudo -Eu root is a cluster ending in a value" "$GATED" \
  "$(printf "sudo -Eu root gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -Euroot attaches the clustered value" "$GATED" \
  "$(printf "sudo -Euroot gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "env -iu VAR is a cluster ending in a value" "$GATED" \
  "$(printf "env -iu GH_TOKEN gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_allow "a chdir letter inside a cluster still moves the directory" "$GATED" \
  "$(printf "env -iC %s gh pr create -t T --body '%s'" "$UNGATED" "$NO_RELATED")"

# sudo login mode runs from the target user's home; shell mode does not move.
assert_allow "sudo -i is login mode" "$GATED" \
  "$(printf "sudo -i gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_allow "sudo --login is login mode" "$GATED" \
  "$(printf "sudo --login gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sudo -s keeps the current directory" "$GATED" \
  "$(printf "sudo -s gh pr create -t T --body '%s'" "$NO_RELATED")"

# --- How `gh` is spelled -----------------------------------------------------
# The wrapper loop above already reads basenames; matching the binary any other
# way lets a path-qualified or Windows-suffixed call walk straight past.

for spelling in "gh.exe" "/usr/bin/gh" "./gh" "/c/Program Files/GitHub CLI/gh.exe"; do
  assert_block "'$spelling' is the same call" "$GATED" \
    "$(printf "'%s' pr create -t T --body '%s'" "$spelling" "$NO_RELATED")"
done
assert_allow "a command merely containing gh is not gh" "$GATED" \
  "npm run lighthouse-prod --body bad"

# --- Directory changes -------------------------------------------------------
# A cd/pushd earlier in the line moves the directory gh runs in, which is the
# directory the gate file and any relative --body-file resolved against.

printf '%s\n' "$GOOD" >"$OTHER/bad.md"
assert_allow "cd retargets a relative --body-file" "$GATED" \
  "cd $OTHER && gh pr create -t T --body-file bad.md"
assert_allow "cd into an ungated repo is not gated" "$GATED" \
  "cd $UNGATED && $(gh_body "$NO_RELATED")"
assert_allow "pushd counts as a directory change" "$GATED" \
  "pushd $UNGATED && $(gh_body "$NO_RELATED")"
assert_allow "a cd inside sh -c still counts" "$GATED" \
  "bash -c \"cd $UNGATED && gh pr create -t T --body 'bad'\""
assert_block "a cd AFTER the gh call does not excuse it" "$GATED" \
  "$(gh_body "$NO_RELATED") && cd $UNGATED"

# --- pflag grouped shorthand -------------------------------------------------
# `-db BODY`, `-dbBODY`, `-dF file`, `-dFfile` are all valid gh and all carry a
# body a plain `-b`/`-F` match never sees.

assert_block "-db takes the next word as the body" "$GATED" \
  "$(printf "gh pr create -db '%s'" "$NO_RELATED")"
assert_block "-dbVALUE takes the rest of the word" "$GATED" "gh pr create -dbBAD_BODY_NO_RELATED"
assert_block "-dF takes the next word as the body file" "$GATED" "gh pr create -dF body.md"
assert_block "-dFVALUE takes the rest of the word" "$GATED" "gh pr create -dFbody.md"
assert_allow "-dF with a compliant file allowed" "$GATED" "gh pr create -dF good.md"
assert_allow "-dR retargets the repo" "$GATED" \
  "$(printf "gh pr create -dR other/repo -t T --body '%s'" "$NO_RELATED")"
assert_allow "a value-taking shorthand before b consumes the body word" "$GATED" \
  "gh pr create -tb T"
assert_allow "an unknown shorthand letter is not guessed at" "$GATED" \
  "$(printf "gh pr create -zb '%s'" "$NO_RELATED")"
assert_allow "a trailing value-taking cluster has nothing to take" "$GATED" "gh pr create -t T -db"

# --- Attached and absolute body-file forms -----------------------------------

assert_block "--body-file=X attached form" "$GATED" "gh pr create -t T --body-file=body.md"
assert_block "-FX attached form" "$GATED" "gh pr create -t T -Fbody.md"
assert_block "an absolute body-file path is read" "$GATED" "gh pr create -t T --body-file $GATED/body.md"
assert_allow "an absolute path to a compliant body allowed" "$GATED" \
  "gh pr create -t T --body-file $GATED/good.md"

# --- .yaml gate spelling -----------------------------------------------------

printf '%s\n' "$NO_RELATED" >"$GATED_YAML/body.md"
assert_block "a .yaml gate workflow enforces too" "$GATED_YAML" "gh pr create -t T --body-file body.md"

# --- Locale independence -----------------------------------------------------
# `[[:space:]]` is locale-defined; JavaScript's `\s` is not. Each body below
# uses a non-ASCII `\s` member (NBSP, em space, ideographic space) where the
# validator accepts whitespace, so both locales must ALLOW.

locale_case() {
  local label="$1" body="$2" payload utf c
  printf '%s' "$body" >"$GATED/u.md"
  payload=$(jq -n --arg cwd "$GATED" --arg cmd "gh pr create -t T --body-file u.md" \
    '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
  printf '%s' "$payload" | LC_ALL=en_US.UTF-8 bash "$HOOK" >/dev/null 2>&1
  utf=$?
  printf '%s' "$payload" | LC_ALL=C bash "$HOOK" >/dev/null 2>&1
  c=$?
  if ((utf == 0 && c == 0)); then
    ok "$label (locale-independent)"
  else
    fail "$label: utf8 rc=$utf, C rc=$c (both should allow)"
  fi
}

locale_case "NBSP between keyword and issue" $'Closes:\xc2\xa0#5\n\n## Related\n\n- x'
locale_case "em space between keyword and issue" $'Closes\xe2\x80\x83#5\n\n## Related\n\n- x'
locale_case "ideographic space in the heading" $'Closes #5\n\n##\xe3\x80\x80Related\n\n- x'
locale_case "BOM ahead of the heading" $'Closes #5\n\n\xef\xbb\xbf## Related\n\n- x'

# --- CRLF --------------------------------------------------------------------

printf 'Closes #5\r\n\r\n## Related\r\n\r\n- x\r\n' >"$GATED/crlf-good.md"
printf 'Closes #5\r\n\r\nno related\r\n' >"$GATED/crlf-bad.md"
assert_allow "a CRLF body validates" "$GATED" "gh pr create -t T --body-file crlf-good.md"
assert_block "a CRLF body still fails when it should" "$GATED" "gh pr create -t T --body-file crlf-bad.md"

# --- Large bodies stay inside the declared hook timeout ----------------------
# One fork per body line put a 1000-line body past the 15 s hooks.json timeout,
# where a cancelled hook silently stops gating. The bound below is deliberately
# loose so a slow CI runner does not flake; the defect it guards was 18 s.

{
  printf 'Closes #5\n\n'
  perf_i=0
  while ((perf_i < 1000)); do
    printf 'filler line %d with several words on it\n' "$perf_i"
    perf_i=$((perf_i + 1))
  done
  printf '\n## Related\n\n- x\n'
} >"$GATED/big.md"
perf_start=${EPOCHREALTIME:-}
run "$GATED" "gh pr create -t T --body-file big.md"
perf_end=${EPOCHREALTIME:-}
if [[ -z "$perf_start" || -z "$perf_end" ]]; then
  echo "SKIP: EPOCHREALTIME unavailable -- large-body timing not measured"
elif ((RC != 0)); then
  fail "1000-line compliant body should allow, got rc=$RC"
else
  perf_ms=$(awk -v s="${perf_start/,/.}" -v e="${perf_end/,/.}" 'BEGIN{printf "%d", (e-s)*1000}')
  if ((perf_ms < 8000)); then
    ok "1000-line body judged in ${perf_ms}ms (hooks.json timeout is 15s)"
  else
    fail "1000-line body took ${perf_ms}ms -- too close to the 15s hook timeout"
  fi
fi

# --- Missing jq fails open ---------------------------------------------------
# The hook cannot parse its payload without jq, and a policy gate that cannot
# read its input must not refuse the command.

STUB="$WORK/stub-bin"
mkdir -p "$STUB"
jq_stub_ok=1
# bash is invoked by absolute path: a PATH with no bash in it would fail the
# invocation itself rather than exercising the hook's own missing-jq branch.
BASH_ABS="${BASH:-$(command -v bash)}"
for tool in dirname tr; do
  if tool_path="$(command -v "$tool" 2>/dev/null)" && [[ -n "$tool_path" ]]; then
    cp "$tool_path" "$STUB/" 2>/dev/null || jq_stub_ok=0
  else
    jq_stub_ok=0
  fi
done
if ((jq_stub_ok)) && [[ -x "$BASH_ABS" ]] && ! PATH="$STUB" command -v jq >/dev/null 2>&1; then
  payload=$(jq -n --arg cwd "$GATED" --arg cmd "$(gh_body "$NO_RELATED")" \
    '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
  if (printf '%s' "$payload" | PATH="$STUB" "$BASH_ABS" "$HOOK" >/dev/null 2>&1); then
    ok "a missing jq fails open"
  else
    fail "a missing jq did not fail open"
  fi
else
  echo "SKIP: could not build a jq-free PATH -- missing-jq fail-open not measured"
fi

# --- Kill switch -------------------------------------------------------------

payload=$(jq -n --arg cwd "$GATED" --arg cmd "$(gh_body "$NO_RELATED")" \
  '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
if (cd "$UNRELATED" && printf '%s' "$payload" |
  CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED=false bash "$HOOK" >/dev/null 2>&1); then
  ok "kill switch disables the gate"
else
  fail "kill switch did not disable the gate"
fi

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0)) || exit 1
