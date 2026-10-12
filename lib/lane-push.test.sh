#!/usr/bin/env bash
# Tests for lib/lane-push.sh, the one way an unattended lane pushes.
#
# A real local repository supplies the checkout and its local config, and the
# script's own config reads run the real git. PATH shims stand in for the two
# calls that would leave the host: `git ... push`, which records its argv and
# environment and replays the effective config it would run under, and gh,
# which answers the acting-login and pull-request reads from variables.
#
# Expected values come from the lane-push contract (the loop-lane convention,
# "Lane write identity"), not from the script: the URL is
# https://github.com/<owner>/<repo>.git, the refspec HEAD:refs/heads/<branch>,
# and the -c list is the one the convention names.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect the fixture's `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane-push.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}

REAL_GIT="$(type -P git)"
BASH_BIN="$(type -P bash)"
BIN="$TMP/bin"
LOG="$TMP/log"
mkdir -p "$BIN" "$LOG" "$TMP/home"

# The git shim: a push is recorded, never sent; everything else is real git.
cat >"$BIN/git" <<EOF
#!/usr/bin/env bash
is_push=0 cflags=()
for ((i = 1; i <= \$#; i++)); do
  [[ \${!i} == push ]] && is_push=1
  if [[ \${!i} == -c ]]; then j=\$((i + 1)); cflags+=(-c "\${!j}"); fi
done
[[ \$is_push == 1 ]] || exec "$REAL_GIT" "\$@"
printf '%s\n' "\$@" >"\$LP_LOG/push.argv"
env | LC_ALL=C sort >"\$LP_LOG/push.env"
printf 'protocol=https\nhost=github.com\n\n' |
  "$REAL_GIT" "\${cflags[@]}" credential fill >"\$LP_LOG/push.cred" 2>/dev/null
"$REAL_GIT" "\${cflags[@]}" config --get-all credential.helper >"\$LP_LOG/push.helpers"
"$REAL_GIT" "\${cflags[@]}" config --get-regexp '^(url|include|http)\.' >"\$LP_LOG/push.risky"
exit "\${LP_PUSH_EXIT:-0}"
EOF

# The gh shim: the acting-login, default-branch and pull-request head reads.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LP_LOG/gh.calls"
case "$1 $2" in
  "api --hostname")
    # The repository read: old-org/old-repo is a renamed example-org/example-repo;
    # any other repository is a fork of it unless LP_PARENT says otherwise.
    if [[ $4 == repos/* ]]; then
      [[ -z ${LP_DEFAULT_FAIL:-} ]] || exit 1
      r=${4#repos/}
      [[ ${r,,} == old-org/old-repo ]] && r=example-org/example-repo
      parent=""
      [[ ${r,,} == example-org/example-repo ]] || parent=${LP_PARENT-example-org/example-repo}
      if [[ $6 == .full_name ]]; then
        printf '%s\n' "$r"
      else
        printf '%s\n%s\n%s\n%s\n' "$r" "${LP_DEFAULT_BRANCH-trunk}" "$parent" "$parent"
      fi
      exit 0
    fi
    printf 'viewer HOME=%s\n' "$HOME" >>"$LP_LOG/gh.home"
    [[ -z ${LP_LOGIN_FAIL:-} ]] || exit 1
    printf '%s\n' "$LP_LOGIN"
    ;;
  "pr view") printf '%s\n%s\n' "$LP_HEAD_REPO" "$LP_HEAD_REF" ;;
  "auth git-credential")
    printf 'helper HOME=%s\n' "$HOME" >>"$LP_LOG/gh.home"
    printf 'username=x-access-token\npassword=gh-token\n'
    ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$BIN/git" "$BIN/gh"

export PATH="$BIN:$PATH" LP_LOG="$LOG" HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/home/.config"
export LP_LOGIN="example-lane[bot]"

# A hostile global config that GIT_CONFIG_GLOBAL=/dev/null must drop.
cat >"$HOME/.gitconfig" <<'EOF'
[credential]
    helper = store
[url "ssh://git@github.com/"]
    pushInsteadOf = https://github.com/
[http]
    extraHeader = Authorization: basic leaked
EOF

new_repo() {
  REPO_DIR="$TMP/repo-$1"
  "$REAL_GIT" init -q "$REPO_DIR"
  "$REAL_GIT" -C "$REPO_DIR" -c user.name=t -c user.email=t@example.invalid \
    commit -q --allow-empty -m init
}

# run <repo-dir> <args...>: run the script there, leaving RC, OUT, ERR.
run() {
  local dir=$1
  shift
  rm -f "$LOG"/*
  (cd "$dir" && "$BASH_BIN" "$SCRIPT" "$@" >/dev/null 2>"$TMP/err")
  RC=$?
  ERR="$(cat "$TMP/err")"
}
pushed() { [[ -f "$LOG/push.argv" ]]; }
gh_called() { [[ -f "$LOG/gh.calls" ]]; }

# expect_refused <name> <code>: exit 2, the code named, nothing pushed.
expect_refused() {
  if [[ $RC == 2 && $ERR == *"refused: $2"* ]] && ! pushed; then
    pass "$1"
  else
    fail "$1" "rc=$RC err=[$ERR] pushed=$(pushed && echo yes || echo no)"
  fi
}

HELPER="!'$BIN/gh' auth git-credential"
expected_argv() {
  printf '%s\n' \
    -c credential.helper= \
    -c "credential.helper=$HELPER" \
    -c core.sshCommand=false \
    -c core.askPass=false \
    -c core.hooksPath=/dev/null \
    -c protocol.allow=never \
    -c protocol.https.allow=always \
    -c http.extraHeader= \
    -c push.pushOption= \
    push --no-verify --no-signed --no-follow-tags --recurse-submodules=no \
    "$1" "$2"
}

new_repo main

# 1. A same-repository push: the constructed URL, refspec and -c options.
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch feat/x-1
assert_eq "case 1: exit 0" 0 "$RC"
assert_eq "case 1: argv is the constructed push" \
  "$(expected_argv https://github.com/example-org/example-repo.git HEAD:refs/heads/feat/x-1)" \
  "$(cat "$LOG/push.argv" 2>/dev/null)"

# 2. The scrubbed environment: no caller git variable reaches git, and the
# script's own four are set.
HOSTILE_VARS=(GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_SSH
  GIT_SSH_COMMAND GIT_ASKPASS SSH_ASKPASS GIT_PROXY_COMMAND GIT_TRACE GIT_TRACE_CURL
  GIT_ALLOW_PROTOCOL GIT_SSL_NO_VERIFY GIT_TERMINAL_PROMPT BASH_ENV)
export GIT_CONFIG_PARAMETERS="'url.ssh://git@github.com/.pushinsteadof'='https://github.com/'"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=store
export GIT_SSH=/bin/false GIT_SSH_COMMAND=/bin/false GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false
export GIT_PROXY_COMMAND=/bin/false GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_ALLOW_PROTOCOL=ssh
export GIT_SSL_NO_VERIFY=1 GIT_TERMINAL_PROMPT=1 BASH_ENV=/nonexistent
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
unset "${HOSTILE_VARS[@]}"
assert_eq "case 2: exit 0" 0 "$RC"
assert_eq "case 2: only the script's git variables reach git" \
  $'GIT_CONFIG_GLOBAL=/dev/null\nGIT_CONFIG_NOSYSTEM=1\nGIT_TERMINAL_PROMPT=0' \
  "$(grep -E '^GIT_' "$LOG/push.env")"
assert_eq "case 2: SSH_ASKPASS and BASH_ENV are unset" "" \
  "$(grep -E '^(SSH_ASKPASS|BASH_ENV|ENV)=' "$LOG/push.env")"
# Replayed through real git under the recorded -c list and environment: the
# helper list is the reset then gh, and no url, include or http key applies
# but the cleared header.
assert_eq "case 2: effective helpers are the reset and gh alone" \
  $'\n'"$HELPER" "$(cat "$LOG/push.helpers")"
assert_eq "case 2: no url or include key, only the cleared header" \
  "http.extraheader " "$(cat "$LOG/push.risky")"

# 3. A refusal for each local config key class that survives the global and
# system scrub.
n=0
for spec in \
  "url.ssh://git@github.com/.pushInsteadOf=https://github.com/|local-config-url" \
  "url.ssh://git@github.com/.insteadOf=https://github.com/|local-config-url" \
  "include.path=/tmp/x|local-config-include" \
  "includeIf.onbranch:main.path=/tmp/x|local-config-include" \
  "includeIf.gitdir:/tmp/.path=/tmp/x|local-config-include" \
  "credential.helper=store|local-config-credential" \
  "credential.https://github.com.username=someone|local-config-credential" \
  "http.extraHeader=Authorization: basic x|local-config-http" \
  "http.https://github.com/.extraheader=Authorization: basic x|local-config-http" \
  "http.sslVerify=false|local-config-http" \
  "remote.origin.vcs=fake|local-config-remote" \
  "remote.https://github.com/example-org/example-repo.git.pushurl=ssh://git@evil.example/x|local-config-remote"; do
  kv=${spec%|*} code=${spec##*|}
  key=${kv%%=*} value=${kv#*=}
  new_repo "k$((++n))"
  "$REAL_GIT" -C "$REPO_DIR" config "$key" "$value"
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
  expect_refused "case 3: local $key is refused" "$code"
done

# 4. Worktree config is read when the extension is on.
new_repo wt
"$REAL_GIT" -C "$REPO_DIR" config extensions.worktreeConfig true
"$REAL_GIT" -C "$REPO_DIR" config --worktree url.ssh://git@github.com/.pushInsteadOf https://github.com/
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 4: a worktree-scoped url key is refused" local-config-url

# 5. A gh pr checkout leaves the push target untouched: a remote and a branch
# push remote pointing over ssh elsewhere are not consulted.
new_repo checkout
"$REAL_GIT" -C "$REPO_DIR" remote add origin git@github.com:example-org/example-repo.git
"$REAL_GIT" -C "$REPO_DIR" remote add fork ssh://git@evil.example/x.git
"$REAL_GIT" -C "$REPO_DIR" config branch.main.pushRemote fork
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 5: remotes are ignored; the URL is constructed" \
  "https://github.com/example-org/example-repo.git" "$(tail -2 "$LOG/push.argv" 2>/dev/null | head -1)"

# 6. The acting login must be the identity.
REPO_DIR="$TMP/repo-main"
LP_LOGIN="operator-example" run "$REPO_DIR" --login "example-lane[bot]" --repo example-org/example-repo --branch main
expect_refused "case 6: a login mismatch is refused" login-mismatch
LP_LOGIN="EXAMPLE-LANE[bot]" run "$REPO_DIR" --login "example-lane[bot]" --repo example-org/example-repo --branch main
assert_eq "case 6: logins compare case-insensitively" 0 "$RC"
LP_LOGIN_FAIL=1 run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 6: an unreadable login is refused" login-unreadable
LP_LOGIN="" run "$REPO_DIR" --login "example-lane[bot]" --repo example-org/example-repo --branch main
expect_refused "case 6: an empty login is refused" login-unreadable

# 7. Owner, repository, branch, login and number outside the allowlist are
# refused before any gh call.
for spec in \
  "--repo|ex;ample/r|bad-repo" "--repo|-x/r|bad-repo" "--repo|o/..|bad-repo" "--repo|o/r/x|bad-repo" \
  "--repo|o/r x|bad-repo" "--repo|o|bad-repo" "--repo|o/\$(id)|bad-repo" \
  "--branch|a..b|bad-branch" "--branch|-x|bad-branch" "--branch|a b|bad-branch" \
  "--branch|x.lock|bad-branch" "--branch|a//b|bad-branch" "--branch|a@{1}|bad-branch" \
  "--branch|feat/|bad-branch" "--branch|\$(id)|bad-branch" "--branch||bad-branch" \
  "--login|a b|bad-login" "--login|-x[bot]|bad-login" "--login||bad-login" \
  "--pr|0|bad-pr" "--pr|1x|bad-pr"; do
  IFS='|' read -r flag value code <<<"$spec"
  args=(--login "$LP_LOGIN" --repo example-org/example-repo --branch main)
  case $flag in
    --repo) args[3]=$value ;;
    --branch) args[5]=$value ;;
    --login) args[1]=$value ;;
    *) args=(--login "$LP_LOGIN" --repo example-org/example-repo --pr "$value") ;;
  esac
  run "$REPO_DIR" "${args[@]}"
  expect_refused "case 7: $flag '$value' is refused" "$code"
  if gh_called; then fail "case 7: $flag '$value' made no gh call" "$(cat "$LOG/gh.calls")"; fi
done

# 8. A fork head: the target comes from the pull request's head repository.
LP_HEAD_REPO="someone/example-fork" LP_HEAD_REF="fix/y" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
assert_eq "case 8: fork head exit 0" 0 "$RC"
assert_eq "case 8: pushes the head repository and branch" \
  "$(expected_argv https://github.com/someone/example-fork.git HEAD:refs/heads/fix/y)" \
  "$(cat "$LOG/push.argv" 2>/dev/null)"
assert_eq "case 8: the head is read from the base repository's pull request" \
  "pr view 12 -R github.com/example-org/example-repo --json headRepository,headRefName --jq .headRepository.nameWithOwner, .headRefName" \
  "$(head -1 "$LOG/gh.calls")"
LP_HEAD_REPO="null" LP_HEAD_REF="fix/y" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
expect_refused "case 8: a deleted head repository is refused" bad-repo
LP_HEAD_REPO="someone/example-fork" LP_HEAD_REF="x..y" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
expect_refused "case 8: a head branch outside the allowlist is refused" bad-branch
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12 --branch main
expect_refused "case 8: --pr and --branch together are refused" usage

# 9. --check runs every refusal but the push.
run "$REPO_DIR" --login "$LP_LOGIN" --check
assert_eq "case 9: check passes" 0 "$RC"
if pushed; then fail "case 9: check pushes nothing" "pushed"; else pass "case 9: check pushes nothing"; fi
LP_LOGIN="operator-example" run "$REPO_DIR" --login "example-lane[bot]" --check
expect_refused "case 9: check refuses a login mismatch" login-mismatch

# 10. A missing gh is refused; a failed push exits 1.
mkdir -p "$TMP/nogh"
ln -s "$BIN/git" "$TMP/nogh/git"
ln -s "$BASH_BIN" "$TMP/nogh/bash"
rm -f "$LOG"/*
RC=0
ERR="$(cd "$REPO_DIR" && PATH="$TMP/nogh" "$BASH_BIN" "$SCRIPT" --login "$LP_LOGIN" \
  --repo example-org/example-repo --branch main 2>&1 >/dev/null)" || RC=$?
expect_refused "case 10: a missing gh is refused" gh-missing
LP_PUSH_EXIT=1 run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 10: a failed push exits 1" 1 "$RC"

# 11. --dir pushes another checkout's HEAD; a missing one is refused.
run "$TMP" --dir "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 11: --dir pushes from that checkout" 0 "$RC"
run "$TMP" --dir "$TMP/missing" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 11: a missing --dir is refused" bad-dir

# 12. Not a checkout: the config read fails closed.
mkdir -p "$TMP/plain"
run "$TMP/plain" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 12: outside a checkout is refused" config-unreadable

# 13. git runs with NETRC=/dev/null whatever the caller set, so libcurl reads
# no netrc file; HOME is the caller's, so gh, for the login read and as the
# helper, reads the same config and token.
REPO_DIR="$TMP/repo-main"
printf 'machine github.com login operator password leaked\n' >"$TMP/netrc-file"
NETRC="$TMP/netrc-file" run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 13: exit 0" 0 "$RC"
assert_eq "case 13: a caller's NETRC is replaced by /dev/null" "NETRC=/dev/null" "$(grep -E '^NETRC=' "$LOG/push.env")"
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 13: with no caller NETRC, git still gets /dev/null" "NETRC=/dev/null" "$(grep -E '^NETRC=' "$LOG/push.env")"
assert_eq "case 13: the helper answers with gh's credential" \
  $'protocol=https\nhost=github.com\nusername=x-access-token\npassword=gh-token' "$(cat "$LOG/push.cred")"
assert_eq "case 13: the login read and the helper both run gh under the caller's HOME" \
  "viewer HOME=$HOME"$'\n'"helper HOME=$HOME" "$(cat "$LOG/gh.home")"

# 14. git is resolved from PATH before --dir is entered, and only to an
# absolute path, so a relative PATH entry cannot pick up a git the checkout
# holds.
mkdir -p "$REPO_DIR/planted" "$TMP/cwd/planted"
for d in "$REPO_DIR/planted" "$TMP/cwd/planted"; do
  printf '#!/usr/bin/env bash\ntouch "%s/ran"\n' "$d" >"$d/git"
  chmod +x "$d/git"
done
PATH="planted:$PATH" run "$TMP" --dir "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
assert_eq "case 14: a git planted under --dir is not used" 0 "$RC"
if [[ -e $REPO_DIR/planted/ran ]]; then
  fail "case 14: the planted git never ran" "it ran"
else
  pass "case 14: the planted git never ran"
fi
PATH="planted:$PATH" run "$TMP/cwd" --dir "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 14: a git found through a relative PATH entry is refused" git-path-unsafe
if [[ -e $TMP/cwd/planted/ran ]]; then
  fail "case 14: the relative git never ran" "it ran"
else
  pass "case 14: the relative git never ran"
fi
rm -rf "$REPO_DIR/planted"

# 15. A lane never pushes the base repository's default branch, by --branch or
# by an in-repository pull request whose head is that branch. A fork's own
# default branch is a fork PR's head, so it pushes.
run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch trunk
expect_refused "case 15: --branch on the default branch is refused" default-branch
assert_eq "case 15: the default branch is read from the repository" \
  1 "$(grep -c "^api --hostname github.com repos/example-org/example-repo --jq " "$LOG/gh.calls" 2>/dev/null)"
LP_HEAD_REPO="example-org/example-repo" LP_HEAD_REF="trunk" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
expect_refused "case 15: an in-repository head on the default branch is refused" default-branch
LP_HEAD_REPO="Example-Org/Example-Repo" LP_HEAD_REF="trunk" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
expect_refused "case 15: the repository comparison ignores case" default-branch
LP_HEAD_REPO="someone/example-fork" LP_HEAD_REF="trunk" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
assert_eq "case 15: a fork head on the fork's default branch pushes" 0 "$RC"
LP_DEFAULT_FAIL=1 run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 15: an unreadable default branch is refused" default-branch-unreadable
LP_DEFAULT_BRANCH="" run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 15: an empty default branch is refused" default-branch-unreadable
LP_DEFAULT_BRANCH=$'main\r' run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --branch main
expect_refused "case 15: a default branch outside the branch allowlist is refused" default-branch-unreadable
# The base is compared by its canonical name, so a renamed repository's old
# name does not skip the refusal.
LP_HEAD_REPO="example-org/example-repo" LP_HEAD_REF="trunk" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo old-org/old-repo --pr 12
expect_refused "case 15: an in-repository default-branch head under the base's old name is refused" default-branch
# Only a fork of the base may be pushed on its own default branch: another
# repository's head (the base's upstream, when the base is itself a fork) is not.
LP_PARENT="" LP_HEAD_REPO="upstream-org/upstream" LP_HEAD_REF="trunk" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
expect_refused "case 15: a non-fork head repository's default branch is refused" default-branch
LP_HEAD_REPO="someone/example-fork" LP_HEAD_REF="fix/y" \
  run "$REPO_DIR" --login "$LP_LOGIN" --repo example-org/example-repo --pr 12
assert_eq "case 15: a fork head on another branch pushes" 0 "$RC"

if ((FAILED)); then
  printf '%d failure(s)\n' "$FAILED" >&2
  exit 1
fi
printf 'all passed\n'
