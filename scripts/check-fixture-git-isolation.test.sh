#!/usr/bin/env bash
# Self-test for scripts/check-fixture-git-isolation.sh.
#
# Every LOGIC case runs the gate inside a synthetic fixture repository holding a
# copy of the script, so those assertions cannot drift with whatever the live
# corpus happens to contain today. The final case is deliberately different: it
# is a canary that runs the gate against the REAL tree, so the shipped baseline
# and the shipped corpus are asserted to agree.
set -uo pipefail

# This suite builds git fixtures itself, so it clears the inherited git
# environment for the same reason the gate exists (#2840): under an exported
# ABSOLUTE GIT_DIR, `git init` and `git config` follow repository discovery
# rather than `-C` or the working directory, and the fixture identity lands in
# the caller's repository. GIT_CONFIG is cleared as a distinct path — it
# replaces the file `git config` itself reads and writes.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-fixture-git-isolation.sh"
BASELINE_NAME="fixture-git-isolation-baseline.txt"
failures=0

ok() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

seq_n=0
REPO=""
# new_repo — a fresh fixture repo carrying a copy of the gate under scripts/.
# Sets REPO rather than echoing a path: command substitution would run this in a
# SUBSHELL, so the sequence counter would never advance in the caller and every
# case would silently reuse — and accumulate into — the first repo.
new_repo() {
  seq_n=$((seq_n + 1))
  REPO="$TMP/r$seq_n"
  mkdir -p "$REPO/scripts"
  cp "$SCRIPT" "$REPO/scripts/check-fixture-git-isolation.sh"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name test
  git -C "$REPO" config commit.gpgsign false
}

commit_all() { git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" commit -qm fixture >/dev/null 2>&1; }

run_gate() {
  local repo="$1"
  shift
  (cd "$repo" && bash scripts/check-fixture-git-isolation.sh "$@" 2>&1)
}

# --- usage -------------------------------------------------------------------
new_repo
r="$REPO"
commit_all "$r"
out="$(run_gate "$r" --bogus)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"usage:"* ]]; then
  ok "unknown flag exits 2 with usage"
else
  fail "unknown flag: rc=$rc out='$out'"
fi

# --- a fixture-building suite with no isolation is a VIOLATION ---------------
new_repo
r="$REPO"
cat >"$r/leaky.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"leaky.test.sh"* ]]; then
  ok "unisolated fixture suite is a violation (exit 1, names the file)"
else
  fail "unisolated suite: rc=$rc out='$out'"
fi

# --- the same suite clearing the environment itself PASSES -------------------
new_repo
r="$REPO"
cat >"$r/clean.test.sh" <<'SH'
#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "suite that unsets GIT_DIR/GIT_WORK_TREE passes"
else
  fail "self-clearing suite: rc=$rc out='$out'"
fi

# --- clearing only GIT_DIR is NOT enough -------------------------------------
new_repo
r="$REPO"
cat >"$r/half.test.sh" <<'SH'
#!/usr/bin/env bash
unset GIT_DIR
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"half.test.sh"* ]]; then
  ok "unsetting GIT_DIR alone is still a violation"
else
  fail "half-clearing suite: rc=$rc out='$out'"
fi

# --- sourcing a harness that clears the environment PASSES -------------------
new_repo
r="$REPO"
mkdir -p "$r/lib"
cat >"$r/lib/harness.sh" <<'SH'
# shellcheck shell=bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
SH
cat >"$r/sourced.test.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/lib/harness.sh"
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "sourcing a harness that clears the environment passes"
else
  fail "harness-sourcing suite: rc=$rc out='$out'"
fi

# --- a harness that STOPS clearing re-exposes every suite that sources it ----
new_repo
r="$REPO"
mkdir -p "$r/lib"
# shellcheck disable=SC2016  # literal fixture text, not an expansion
printf '# shellcheck shell=bash\n: "${PASS:=0}"\n' >"$r/lib/harness.sh"
cat >"$r/sourced.test.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/lib/harness.sh"
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"sourced.test.sh"* ]]; then
  ok "a harness that stops clearing re-exposes its sourcing suites"
else
  fail "regressed harness: rc=$rc out='$out'"
fi

# --- a baselined violation is grandfathered ----------------------------------
new_repo
r="$REPO"
cat >"$r/leaky.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
printf '# grandfathered\nleaky.test.sh\n' >"$r/scripts/$BASELINE_NAME"
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a baselined violation is grandfathered"
else
  fail "baselined violation: rc=$rc out='$out'"
fi

# --- a STALE baseline entry fails --------------------------------------------
new_repo
r="$REPO"
cat >"$r/fixed.test.sh" <<'SH'
#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
printf 'fixed.test.sh\n' >"$r/scripts/$BASELINE_NAME"
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"STALE BASELINE"* && "$out" == *"fixed.test.sh"* ]]; then
  ok "a stale baseline entry fails (a line cannot outlive its debt)"
else
  fail "stale baseline: rc=$rc out='$out'"
fi

# --- a suite that builds no fixture is ignored -------------------------------
new_repo
r="$REPO"
cat >"$r/pure.test.sh" <<'SH'
#!/usr/bin/env bash
[[ "$(printf 'a')" == "a" ]] || exit 1
git status --short >/dev/null 2>&1
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a suite that builds no fixture is not conscripted"
else
  fail "non-fixture suite: rc=$rc out='$out'"
fi

# --- prose about `git init` in a comment does not conscript a suite ----------
new_repo
r="$REPO"
cat >"$r/prose.test.sh" <<'SH'
#!/usr/bin/env bash
# This suite explains why `git init` and `config user.email` leak, but runs
# neither of them.
printf 'ok\n'
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a comment mentioning git init does not conscript a suite"
else
  fail "prose-only suite: rc=$rc out='$out'"
fi

# --- --list reports a verdict per suite without failing ----------------------
new_repo
r="$REPO"
cat >"$r/leaky.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r" --list)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"VIOLATION"*"leaky.test.sh"* ]]; then
  ok "--list reports verdicts and exits 0"
else
  fail "--list: rc=$rc out='$out'"
fi

# --- an identity write via `config --local` is caught --------------------------
# The narrower earlier form required `config` immediately followed by `user.`,
# so this spelling escaped. A suite whose ONLY fixture work is a --local
# identity write is the case that used to slip through entirely.
new_repo
r="$REPO"
cat >"$r/local-ident.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -C "$d" config --local user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"local-ident.test.sh"* ]]; then
  ok "an identity write via 'config --local' is a violation"
else
  fail "config --local write: rc=$rc out='$out'"
fi

# --- an identity READ does NOT conscript a suite -----------------------------
# The counterpart to the case above, and the reason the intent excludes the
# --get spellings rather than matching every `config … user.*`. A read cannot
# poison anything.
new_repo
r="$REPO"
cat >"$r/read-ident.test.sh" <<'SH'
#!/usr/bin/env bash
git config --get-all user.name >/dev/null 2>&1
git config --get user.email >/dev/null 2>&1
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "an identity read alone does not conscript a suite"
else
  fail "identity read: rc=$rc out='$out'"
fi

# --- a read and a write on the SAME line: the write still wins ---------------
# Guards the fail-OPEN a line-wide read exclusion would create: one `--get` on
# the line must not suppress a real identity write sharing it.
new_repo
r="$REPO"
cat >"$r/mixed-ident.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -C "$d" config user.email test@example.com && git config --get user.name
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"mixed-ident.test.sh"* ]]; then
  ok "a read sharing a line does not suppress an identity write"
else
  fail "mixed read/write line: rc=$rc out='$out'"
fi

# --- `--local --get` is still a read -----------------------------------------
# The read exclusion must survive an option word BEFORE the --get.
new_repo
r="$REPO"
cat >"$r/local-read.test.sh" <<'SH'
#!/usr/bin/env bash
git config --local --get user.email >/dev/null 2>&1
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "'config --local --get user.email' is a read, not a fixture write"
else
  fail "local read: rc=$rc out='$out'"
fi

# --- `git -c <k>=<v> init` is caught -----------------------------------------
# Anchoring the option run on `-C` alone missed this, and the form is live in
# this corpus.
new_repo
r="$REPO"
cat >"$r/dashc-init.test.sh" <<'SH'
#!/usr/bin/env bash
d="$(mktemp -d)"
git -c init.defaultBranch=main init -q "$d"
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"dashc-init.test.sh"* ]]; then
  ok "'git -c <k>=<v> init' is a violation"
else
  fail "git -c init: rc=$rc out='$out'"
fi

# --- PYTHON: a fixture-building suite with no isolation is a VIOLATION -------
# The file that caused the #2827 incident is Python, so Python coverage is the
# load-bearing half of this gate rather than an extension of it. The argv here
# is the exact shape of that incident: a list-literal `git -C <dir> config
# user.email`, which no shell-word pattern matches.
new_repo
r="$REPO"
cat >"$r/test_leaky.py" <<'PY'
import subprocess, tempfile
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_leaky.py"* ]]; then
  ok "python: unisolated fixture suite is a violation"
else
  fail "python unisolated: rc=$rc out='$out'"
fi

# --- PYTHON: popping both variables from os.environ PASSES -------------------
# Asserted through the multi-line tuple idiom the real suites use, because a
# line-scoped check would miss it — that is why the Python arm is file-scoped.
new_repo
r="$REPO"
cat >"$r/test_clean.py" <<'PY'
import os, subprocess
for _v in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
    os.environ.pop(_v, None)
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "python: popping GIT_DIR and GIT_WORK_TREE passes"
else
  fail "python cleared: rc=$rc out='$out'"
fi

# --- PYTHON: popping only GIT_DIR is NOT enough ------------------------------
new_repo
r="$REPO"
cat >"$r/test_half.py" <<'PY'
import os, subprocess
os.environ.pop("GIT_DIR", None)
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_half.py"* ]]; then
  ok "python: popping GIT_DIR alone is still a violation"
else
  fail "python half-cleared: rc=$rc out='$out'"
fi

# --- PYTHON: naming the variables without popping anything is NOT enough -----
# Guards the fail-OPEN direction: a file that only mentions GIT_DIR in a comment
# must not be credited with clearing it.
new_repo
r="$REPO"
cat >"$r/test_prose.py" <<'PY'
import subprocess
# We should probably clear GIT_DIR and GIT_WORK_TREE here one day.
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_prose.py"* ]]; then
  ok "python: naming the variables without popping is still a violation"
else
  fail "python prose-only: rc=$rc out='$out'"
fi

# --- PYTHON: a formatter-wrapped argv is still SEEN --------------------------
# A per-line scan never has `git` and `init` on one physical line here, so the
# suite does not merely get the wrong verdict, it is invisible to the gate: it never
# enters the violation/baseline classification at all. That is the failure this
# gate's own header calls disqualifying — a gate that cannot see the file that
# fired is not a gate.
new_repo
r="$REPO"
cat >"$r/test_wrapped.py" <<'PY'
import subprocess
def make(d):
    subprocess.run(
        [
            "git",
            "-C",
            str(d),
            "init",
        ],
        check=True,
    )
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_wrapped.py"* ]]; then
  ok "python: a formatter-wrapped git argv is still detected as a fixture"
else
  fail "python wrapped argv: rc=$rc out='$out'"
fi

# --- PYTHON: a wrapped argv WITH a wrapped clear PASSES ----------------------
# The other half of the same joining rule: the real suites in this repo spell
# their clear as a tuple the formatter has already wrapped, so recall on the
# fixture side must not cost recognition on the clear side.
new_repo
r="$REPO"
cat >"$r/test_wrapped_clean.py" <<'PY'
import os
import subprocess

for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
):
    os.environ.pop(_leaked_git_var, None)

def make(d):
    subprocess.run(
        [
            "git",
            "-C",
            str(d),
            "config",
            "user.email",
            "test@example.com",
        ],
        check=True,
    )
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "python: a wrapped clear still credits a wrapped fixture suite"
else
  fail "python wrapped clear: rc=$rc out='$out'"
fi

# --- PYTHON: a clear that exists only in a COMMENT does not credit -----------
# Prose describing the idiom is not the idiom. This shape is the one that
# tripped the gate on its own header text: a comment holding both variable
# names and pop-like syntax must not satisfy the check.
new_repo
r="$REPO"
cat >"$r/test_commented.py" <<'PY'
import subprocess
# The idiom every suite here should use is:
#     for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE"):
#         os.environ.pop(_leaked_git_var, None)
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_commented.py"* ]]; then
  ok "python: a clear written only inside a comment does not credit the file"
else
  fail "python commented clear: rc=$rc out='$out'"
fi

# --- PYTHON: an UNRELATED pop plus a separate mention does not credit --------
# The pop and the names must be tied to each other. A pop of some other
# variable, plus a comment that happens to name the git ones, is the shape that
# passed while nothing was ever cleared.
new_repo
r="$REPO"
cat >"$r/test_unrelated_pop.py" <<'PY'
import os
import subprocess

os.environ.pop("SOME_UNRELATED_FLAG", None)

# Someday: handle GIT_DIR / GIT_WORK_TREE leaking into fixtures.
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_unrelated_pop.py"* ]]; then
  ok "python: popping an unrelated variable does not credit the git ones"
else
  fail "python unrelated pop: rc=$rc out='$out'"
fi

# --- PYTHON: a loop over UNRELATED names does not credit the git ones --------
# The loop-variable tie, exercised from the other side: the pop is real and the
# loop is real, but the iterable never named a git variable.
new_repo
r="$REPO"
cat >"$r/test_unrelated_loop.py" <<'PY'
import os
import subprocess

for _v in ("HOME", "USERPROFILE"):
    os.environ.pop(_v, None)

# Someday: GIT_DIR and GIT_WORK_TREE belong in that tuple too.
def make(d):
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "test@example.com"], check=True)
PY
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"test_unrelated_loop.py"* ]]; then
  ok "python: a loop popping unrelated names does not credit the git ones"
else
  fail "python unrelated loop: rc=$rc out='$out'"
fi

# --- SHELL: a commented-out unset does not credit ----------------------------
# The shell arm strips comments and matches the names inside the `unset`
# STATEMENT, so neither a commented-out clear nor an unrelated later command on
# the same line can grant it.
new_repo
r="$REPO"
cat >"$r/commented.test.sh" <<'SH'
#!/usr/bin/env bash
# unset GIT_DIR GIT_WORK_TREE
unset SOME_OTHER_VAR   # GIT_DIR GIT_WORK_TREE belong here too
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"commented.test.sh"* ]]; then
  ok "shell: a commented-out unset does not credit the suite"
else
  fail "shell commented unset: rc=$rc out='$out'"
fi

# --- SCOPE: a declared counter-fixture is exempt -----------------------------
new_repo
r="$REPO"
cat >"$r/counter.test.sh" <<'SH'
#!/usr/bin/env bash
# fixture-isolation-scope: exports GIT_DIR on purpose to prove the harness.
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r" --list)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"declared"*"counter.test.sh"* ]]; then
  ok "a declared fixture-isolation scope exempts the suite"
else
  fail "declared scope: rc=$rc out='$out'"
fi

# --- SCOPE: a mere MENTION of the token does not exempt ----------------------
# The anchoring rule, mirroring `portability-scope:` in
# scripts/check-shell-portability.sh. Without it, this gate's own documentation
# and its own detector string would silently exempt whatever file held them.
new_repo
r="$REPO"
cat >"$r/mention.test.sh" <<'SH'
#!/usr/bin/env bash
# See the docs for how fixture-isolation-scope: declarations work.
d="$(mktemp -d)"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
SH
commit_all "$r"
out="$(run_gate "$r")"
rc=$?
if [[ $rc -eq 1 && "$out" == *"mention.test.sh"* ]]; then
  ok "a mid-line mention of the scope token does not exempt"
else
  fail "scope mention: rc=$rc out='$out'"
fi

# --- the LIVE corpus is clean against its own baseline ------------------------
out="$(cd "$ROOT" && bash scripts/check-fixture-git-isolation.sh 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "live corpus passes against scripts/$BASELINE_NAME"
else
  fail "live corpus: rc=$rc out='$out'"
fi

if ((failures > 0)); then
  printf '\n%d case(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nALL PASS\n'
