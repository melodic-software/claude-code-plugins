#!/usr/bin/env bash
# test-scope: lib/org-standards.sh lib/org-standards-test-helpers.sh lib/fixtures/private-git-https/server.py lib/fixtures/private-git-https/redirect.py lib/fixtures/private-git-https/credential-helper.sh lib/fixtures/private-git-https/askpass.sh
set -uo pipefail

# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

handbook_v2
HANDBOOK2=$(head_of acme/handbook)

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/net-cache"
unset GIT_SSH_COMMAND GIT_ASKPASS
mkdir -p "$TEST_TMPDIR/netshim"
cat >"$TEST_TMPDIR/netshim/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" ls-remote "*|*" fetch "*|*" clone "*)
    printf '%s|%s|%s|%s|cfg=%s\n' "\${GIT_TERMINAL_PROMPT-}" "\${GIT_SSH_COMMAND-}" "\${GIT_ASKPASS-unset}" "\$*" \
      "\$(env | grep -E '^GIT_CONFIG_(KEY|VALUE)_[0-9]+=' | sort | paste -sd' ' -)" >>"$TEST_TMPDIR/net.log"
    [[ -z "\${SLOW_NET:-}" ]] || exec sleep 20
    [[ -z "\${BAD_LS:-}" || " \$* " != *" ls-remote "* ]] || { printf '../../escape\trefs/heads/main\n'; exit 0; } ;;
esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$TEST_TMPDIR/netshim/git"
net=$(target net "$OPTED")
user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: acme/handbook
  - repo: stranger/guide
    ref: $GUIDE
"
PATH="$TEST_TMPDIR/netshim:$PATH" run dir --root "$net" >/dev/null
PATH="$TEST_TMPDIR/netshim:$PATH" ORG_STANDARDS_TTL=0 run dir --root "$net" >/dev/null
PATH="$TEST_TMPDIR/netshim:$PATH" run subscriptions --root "$net" >/dev/null
assert_eq "every clone, fetch and ls-remote runs with prompts off, ssh in batch mode, no askpass, hooks and fsmonitor off and no redirect followed" "1|1|1|0" \
  "$(grep -cE '[| ]clone ' "$TEST_TMPDIR/net.log")|$(grep -cE -m1 '[| ]fetch ' "$TEST_TMPDIR/net.log")|$(grep -cE '[| ]ls-remote ' "$TEST_TMPDIR/net.log")|$(grep -vc '^0|ssh -o BatchMode=yes||-c core.hooksPath=/dev/null -c core.fsmonitor=false -c http.followRedirects=false ' "$TEST_TMPDIR/net.log")"

printf '[credential]\n\thelper = "!f() { echo password=SECRET-HELPER-TOKEN; }; f"\n' >"$TEST_TMPDIR/secret.gitconfig"
: >"$TEST_TMPDIR/net.log"
PATH="$TEST_TMPDIR/netshim:$PATH" GIT_CONFIG_GLOBAL="$TEST_TMPDIR/secret.gitconfig" ORG_STANDARDS_TTL=0 run dir --root "$net" >/dev/null
assert_eq "a credential setting reaches git through its environment, never its command line, which other users can list" "yes|0|yes" \
  "$([[ -s "$TEST_TMPDIR/net.log" ]] && echo yes || echo no)|$(awk -F'[|]cfg=' '$1 ~ /SECRET-HELPER-TOKEN/' "$TEST_TMPDIR/net.log" | wc -l)|$(awk -F'[|]cfg=' '$2 !~ /GIT_CONFIG_KEY_[0-9]+=credential.helper .*=!f\(\) \{ echo password=SECRET-HELPER-TOKEN; \}; f/ { bad = 1 } END { print bad ? "no" : "yes" }' "$TEST_TMPDIR/net.log")"

incl=$(target incl "$OPTED")
g init -q "$incl"
printf '[credential]\n\thelper = from-include\n' >"$TEST_TMPDIR/incl-plain.gitconfig"
printf '[credential]\n\thelper = from-this-repository\n' >"$TEST_TMPDIR/incl-here.gitconfig"
printf '[credential]\n\thelper = from-another-repository\n' >"$TEST_TMPDIR/incl-there.gitconfig"
printf '[include]\n\tpath = %s/incl-plain.gitconfig\n[includeIf "gitdir:%s/"]\n\tpath = %s/incl-here.gitconfig\n[includeIf "gitdir:%s/elsewhere/"]\n\tpath = %s/incl-there.gitconfig\n' \
  "$TEST_TMPDIR" "$incl" "$TEST_TMPDIR" "$TEST_TMPDIR" "$TEST_TMPDIR" >"$TEST_TMPDIR/incl.gitconfig"
: >"$TEST_TMPDIR/net.log"
(cd "$TEST_TMPDIR" && PATH="$TEST_TMPDIR/netshim:$PATH" GIT_CONFIG_GLOBAL="$TEST_TMPDIR/incl.gitconfig" ORG_STANDARDS_TTL=0 run dir --root "$incl" >/dev/null)
inc_cfg=$(awk -F'[|]cfg=' 'NR == 1 { print $2 }' "$TEST_TMPDIR/net.log")
assert_eq "credential helpers in the user's included config files reach git, an includeIf gitdir matched against the --root repository" "yes|yes|no" \
  "$([[ "$inc_cfg" == *=from-include* ]] && echo yes || echo no)|$([[ "$inc_cfg" == *=from-this-repository* ]] && echo yes || echo no)|$([[ "$inc_cfg" == *=from-another-repository* ]] && echo yes || echo no)"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/bad-ls-cache"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "a remote that answers main with something other than a commit SHA is not used as a cache key" "1|" \
  "$(PATH="$TEST_TMPDIR/netshim:$PATH" BAD_LS=1 errs subscriptions --root "$net" | grep -c 'cannot read acme/handbook; layer skipped')|$(find "$ORG_STANDARDS_CACHE" -name 'handbook@*')"

if command -v timeout >/dev/null 2>&1; then
  export ORG_STANDARDS_CACHE="$TEST_TMPDIR/slow-cache"
  user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
  start=$SECONDS
  slow=$(PATH="$TEST_TMPDIR/netshim:$PATH" SLOW_NET=1 ORG_STANDARDS_GIT_TIMEOUT=1 bash "$SCRIPT" subscriptions --root "$net" 2>&1)
  assert_eq "a stalled remote is given up after ORG_STANDARDS_GIT_TIMEOUT and the layer skipped" "1|yes" \
    "$(grep -c 'cannot read acme/handbook; layer skipped' <<<"$slow")|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")"
  start=$SECONDS
  assert_eq "a stalled org clone is given up after ORG_STANDARDS_GIT_TIMEOUT: exit 4" "4|yes" \
    "$(PATH="$TEST_TMPDIR/netshim:$PATH" SLOW_NET=1 ORG_STANDARDS_GIT_TIMEOUT=1 code dir --root "$net")|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")"
fi

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/lazy-cache"
FILTERED_WORK="$TEST_TMPDIR/work/stranger/filtered"
filtered_tree() { printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"; printf '# Testing\n' >"$1/docs/standards/testing.md"; }
publish_tree stranger/filtered filtered_tree
FILTERED=$(head_of stranger/filtered)
g -C "$FILTERED_WORK" checkout -q -b fork
printf '# Injected\n' >"$FILTERED_WORK/docs/standards/injected.md"
g -C "$FILTERED_WORK" add -A
g -C "$FILTERED_WORK" commit -q -m fork
FFORK=$(head_of stranger/filtered)
g -C "$FILTERED_WORK" push -q origin fork
g -C "$TEST_TMPDIR/git/stranger/filtered.git" update-ref -d refs/heads/fork
g -C "$FILTERED_WORK" checkout -q main
pin stranger/filtered "$FFORK"
lazy=$(GIT_TRACE="$TEST_TMPDIR/lazy-fork.trace" errs subscriptions --root "$tp")
assert_eq "a fork-only pin on a remote that honors blob filters is refused with no lazy fetch" "1|0" \
  "$(grep -c "$FFORK is not reachable from a branch or tag of stranger/filtered" <<<"$lazy")|$(grep -c 'fetch.negotiationAlgorithm=noop' "$TEST_TMPDIR/lazy-fork.trace")"
pin stranger/filtered "$FILTERED"
GIT_TRACE="$TEST_TMPDIR/lazy-ok.trace" run subscriptions --root "$tp" >/dev/null
assert_eq "an accepted pin on a remote that honors blob filters fetches its blobs lazily at checkout" "yes" \
  "$([[ $(grep -c 'fetch.negotiationAlgorithm=noop' "$TEST_TMPDIR/lazy-ok.trace") -ge 1 ]] && echo yes || echo no)"

if command -v timeout >/dev/null 2>&1; then
  export ORG_STANDARDS_CACHE="$TEST_TMPDIR/stall-cache"
  cat >"$TEST_TMPDIR/stall-hook.sh" <<EOF
#!/usr/bin/env bash
n=\$(cat "$TEST_TMPDIR/stall.count" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"$TEST_TMPDIR/stall.count"
[[ \$n -lt 2 ]] || sleep 30
exec "\$@"
EOF
  chmod +x "$TEST_TMPDIR/stall-hook.sh"
  real_exec=$(git --exec-path)
  mkdir -p "$TEST_TMPDIR/stall-exec"
  for f in "$real_exec"/*; do ln -s "$f" "$TEST_TMPDIR/stall-exec/${f##*/}"; done
  rm "$TEST_TMPDIR/stall-exec/git-upload-pack"
  # shellcheck disable=SC2016  # "$@" belongs to the written shim
  printf '#!/usr/bin/env bash\nexec "%s" "%s/git-upload-pack" "$@"\n' "$TEST_TMPDIR/stall-hook.sh" "$real_exec" >"$TEST_TMPDIR/stall-exec/git-upload-pack"
  chmod +x "$TEST_TMPDIR/stall-exec/git-upload-pack"
  pin stranger/filtered "$FILTERED"
  start=$SECONDS
  stall=$(GIT_EXEC_PATH="$TEST_TMPDIR/stall-exec" ORG_STANDARDS_GIT_TIMEOUT=2 errs subscriptions --root "$tp")
  assert_eq "a checkout whose lazy blob fetch stalls is given up after ORG_STANDARDS_GIT_TIMEOUT and the layer skipped" "1|2|yes" \
    "$(grep -c "cannot read stranger/filtered@${FILTERED:0:12}; layer skipped" <<<"$stall")|$(cat "$TEST_TMPDIR/stall.count")|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")"
fi

if command -v timeout >/dev/null 2>&1; then
  export ORG_STANDARDS_CACHE="$TEST_TMPDIR/filter-cache"
  printf "[filter \"lfs\"]\n\tprocess = \"sh -c 'touch %s/lfs-ran; sleep 30'\"\n\trequired = true\n[filter \"slow\"]\n\tsmudge = \"sh -c 'touch %s/slow-ran; sleep 30'\"\n" \
    "$TEST_TMPDIR" "$TEST_TMPDIR" >"$TEST_TMPDIR/filters.gitconfig"
  lfs_tree() {
    printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"
    printf '*.bin filter=lfs diff=lfs merge=lfs -text\n*.md filter=slow\n' >"$1/.gitattributes"
    printf '[lfs]\n\turl = http://127.0.0.1:9/lfs\n' >"$1/.lfsconfig"
    printf 'lfs pointer\n' >"$1/big.bin"
  }
  publish_tree acme/lfs lfs_tree
  tlfs=$(target lfs $'standards_repository: acme/lfs\n')
  start=$SECONDS
  lfsdir=$(GIT_CONFIG_GLOBAL="$TEST_TMPDIR/filters.gitconfig" ORG_STANDARDS_GIT_TIMEOUT=5 timeout 25 bash "$SCRIPT" dir --root "$tlfs" 2>/dev/null)
  assert_eq "org clone: no smudge or process filter runs, so the checkout holds the committed bytes" "lfs pointer|no|no" \
    "$(cat "$lfsdir/big.bin" 2>/dev/null)|$([[ -e "$TEST_TMPDIR/lfs-ran" ]] && echo yes || echo no)|$([[ -e "$TEST_TMPDIR/slow-ran" ]] && echo yes || echo no)"
  printf 'lfs pointer v2\n' >"$TEST_TMPDIR/work/acme/lfs/big.bin"
  push_main acme/lfs v2
  refreshed=$(GIT_CONFIG_GLOBAL="$TEST_TMPDIR/filters.gitconfig" ORG_STANDARDS_GIT_TIMEOUT=5 ORG_STANDARDS_TTL=0 timeout 25 bash "$SCRIPT" dir --root "$tlfs" 2>&1)
  assert_eq "org refresh: no smudge or process filter runs, so the refreshed checkout holds the committed bytes" "$lfsdir|lfs pointer v2|no|no" \
    "$refreshed|$(cat "$lfsdir/big.bin" 2>/dev/null)|$([[ -e "$TEST_TMPDIR/lfs-ran" ]] && echo yes || echo no)|$([[ -e "$TEST_TMPDIR/slow-ran" ]] && echo yes || echo no)"
  publish_tree stranger/lfs lfs_tree
  LFS=$(head_of stranger/lfs)
  pin stranger/lfs "$LFS"
  lfsline=$(GIT_CONFIG_GLOBAL="$TEST_TMPDIR/filters.gitconfig" ORG_STANDARDS_GIT_TIMEOUT=5 timeout 25 bash "$SCRIPT" subscriptions --root "$tp" 2>/dev/null)
  assert_eq "subscription: no smudge or process filter runs, so the checkout holds the committed bytes" "stranger/lfs@$LFS|lfs pointer|no|no" \
    "$(cut -f1 <<<"$lfsline")|$(cat "$(cut -f2 <<<"$lfsline")/big.bin" 2>/dev/null)|$([[ -e "$TEST_TMPDIR/lfs-ran" ]] && echo yes || echo no)|$([[ -e "$TEST_TMPDIR/slow-ran" ]] && echo yes || echo no)"
  assert_eq "filtered checkouts finish well inside the outer limit" "yes" "$([[ $((SECONDS - start)) -lt 20 ]] && echo yes || echo "no, $((SECONDS - start))s")"
fi

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/net-cache"
printf '[core]\n\tsshCommand = ssh -i /keys/id\n' >"$TEST_TMPDIR/ssh.gitconfig"
: >"$TEST_TMPDIR/net.log"
PATH="$TEST_TMPDIR/netshim:$PATH" GIT_CONFIG_GLOBAL="$TEST_TMPDIR/ssh.gitconfig" ORG_STANDARDS_TTL=0 run dir --root "$net" >/dev/null
assert_eq "a fetch keeps the user's core.sshCommand and adds batch mode" "ssh -i /keys/id -o BatchMode=yes" \
  "$(cut -d'|' -f2 "$TEST_TMPDIR/net.log" | sort -u)"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/hostile-cache"
HOSTILE="$TEST_TMPDIR/hostile"
mkdir -p "$HOSTILE/hooks"
for h in reference-transaction post-checkout; do
  printf '#!/bin/sh\necho "hook %s" >>"%s/marker"\nexit 0\n' "$h" "$HOSTILE" >"$HOSTILE/hooks/$h"
  chmod +x "$HOSTILE/hooks/$h"
done
printf '#!/bin/sh\necho fsmonitor >>"%s/marker"\nexit 1\n' "$HOSTILE" >"$HOSTILE/fsmonitor.sh"
chmod +x "$HOSTILE/fsmonitor.sh"
printf "[core]\n\thooksPath = %s/hooks\n\tfsmonitor = %s/fsmonitor.sh\n[filter \"mark\"]\n\tsmudge = \"sh -c 'echo filter >>%s/marker; cat'\"\n[http]\n\tproxy = http://127.0.0.1:9\n" \
  "$HOSTILE" "$HOSTILE" "$HOSTILE" >"$HOSTILE/gitconfig"
hostile_tree() {
  printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"
  printf '# Testing\n' >"$1/docs/standards/testing.md"
  printf '*.md filter=mark\n' >"$1/.gitattributes"
}
publish_tree acme/hostile hostile_tree
publish_tree stranger/hostile hostile_tree
thost=$(target hostile $'standards_repository: acme/hostile\n')
GIT_CONFIG_GLOBAL="$HOSTILE/gitconfig" run dir --root "$thost" >/dev/null
printf '# Testing v2\n' >"$TEST_TMPDIR/work/acme/hostile/docs/standards/testing.md"
push_main acme/hostile v2
GIT_CONFIG_GLOBAL="$HOSTILE/gitconfig" ORG_STANDARDS_TTL=0 run dir --root "$thost" >/dev/null
user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: acme/hostile
  - repo: stranger/hostile
    ref: $(head_of stranger/hostile)
"
hostile_subs=$(GIT_CONFIG_GLOBAL="$HOSTILE/gitconfig" run subscriptions --root "$tp" | wc -l)
assert_eq "a hostile global git config runs no hook, fsmonitor or filter during clone, fetch and checkout" \
  "# Testing v2|2|" "$(cat "$ORG_STANDARDS_CACHE/acme/hostile/docs/standards/testing.md")|$((hostile_subs))|$(cat "$HOSTILE/marker" 2>/dev/null)"
: >"$TEST_TMPDIR/net.log"
PATH="$TEST_TMPDIR/netshim:$PATH" GIT_CONFIG_GLOBAL="$HOSTILE/gitconfig" ORG_STANDARDS_TTL=0 run dir --root "$thost" >/dev/null
assert_eq "a fetch passes the user's proxy setting through its environment and no other global setting" "1|0|0" \
  "$(grep -c '|cfg=GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0=http://127.0.0.1:9$' "$TEST_TMPDIR/net.log")|$(grep -c -- 'http.proxy.*|cfg=' "$TEST_TMPDIR/net.log")|$(grep -c -- "$HOSTILE/" "$TEST_TMPDIR/net.log")"

EXT="$TEST_TMPDIR/ext"
mkdir -p "$EXT"
printf '#!/bin/sh\necho "ext ran: $*" >>"%s/marker"\nexit 1\n' "$EXT" >"$EXT/helper.sh"
chmod +x "$EXT/helper.sh"
ext_config() { g -C "$1" config protocol.ext.allow always; g -C "$1" config "url.ext::$EXT/helper.sh %S .insteadOf" "file://$TEST_TMPDIR/git/"; }
ext_ran() { [[ -e "$EXT/marker" ]] && echo "ext ran" || echo "no ext"; rm -f "$EXT/marker"; }
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/cwd-cache"
tcwd=$(target cwd "$OPTED")
g init -q "$tcwd"
ext_config "$tcwd"
cwd_out=$(cd "$tcwd" && bash "$SCRIPT" dir 2>/dev/null; bash "$SCRIPT" subscriptions 2>/dev/null | cut -f1)
assert_eq "the current directory's repository config reaches no clone or ls-remote: its insteadOf and protocol.ext.allow are not read" \
  "$ORG_STANDARDS_CACHE/acme/standards|acme/handbook@$HANDBOOK2|no ext" "$(paste -sd'|' - <<<"$cwd_out")|$(ext_ran)"

ENCLOSING="$TEST_TMPDIR/enclosing"
g init -q "$ENCLOSING"
ext_config "$ENCLOSING"
export ORG_STANDARDS_CACHE="$ENCLOSING/cache"
assert_eq "a cache directory inside another repository reads none of that repository's config" \
  "$ORG_STANDARDS_CACHE/acme/standards|acme/handbook@$HANDBOOK2|no ext" "$(run dir --root "$tcwd")|$(run subscriptions --root "$tcwd" | cut -f1)|$(ext_ran)"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/protocol-cache"
assert_eq "no transport outside https, ssh, git and file runs, even when the environment's git config allows it" "4|no ext" \
  "$(GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=protocol.ext.allow GIT_CONFIG_VALUE_0=always GIT_CONFIG_KEY_1="url.ext::$EXT/helper.sh %S .insteadOf" GIT_CONFIG_VALUE_1="file://$TEST_TMPDIR/git/" code dir --root "$tcwd")|$(ext_ran)"

kind() { if [[ -L "$1" ]]; then echo 'symbolic link'; elif [[ -d "$1" ]]; then echo directory; else echo other; fi; }
export ORG_STANDARDS_CACHE="$TEST_TMPDIR/owner-link-cache"
mkdir -p "$ORG_STANDARDS_CACHE" "$TEST_TMPDIR/owner-out"
ln -s "$TEST_TMPDIR/owner-out" "$ORG_STANDARDS_CACHE/acme"
ln -s "$TEST_TMPDIR/owner-out" "$ORG_STANDARDS_CACHE/stranger"
pin stranger/guide "$GUIDE"
owner_dir=$(run dir --root "$tcwd")
owner_sub=$(run subscriptions --root "$tp" | cut -f2)
assert_eq "a symbolic link at an owner directory of the cache is replaced, so no clone lands outside the cache" \
  "$ORG_STANDARDS_CACHE/acme/standards|$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE|directory|directory|" \
  "$owner_dir|$owner_sub|$(kind "$ORG_STANDARDS_CACHE/acme")|$(kind "$ORG_STANDARDS_CACHE/stranger")|$(find "$TEST_TMPDIR/owner-out" -mindepth 1)"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/entry-link-cache"
VICTIM="$TEST_TMPDIR/entry-victim"
g clone -q "file://$TEST_TMPDIR/git/stranger/guide.git" "$VICTIM"
printf 'KEEP\n' >"$VICTIM/keep.txt"
mkdir -p "$ORG_STANDARDS_CACHE/stranger"
ln -s "$VICTIM" "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE"
entry=$(run subscriptions --root "$tp" | cut -f2)
assert_eq "a symbolic link planted at a subscription's cache entry is replaced by a checkout built inside the cache, and its target is left alone" \
  "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE|directory|KEEP" \
  "$entry|$(kind "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE")|$(cat "$VICTIM/keep.txt")"

PRIV_FIXTURE="$SCRIPT_DIR/fixtures/private-git-https"
if command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  PRIV="$TEST_TMPDIR/private"
  mkdir -p "$PRIV/root"
  cp -R "$TEST_TMPDIR/git/acme" "$PRIV/root/"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=127.0.0.1 \
    -addext 'subjectAltName=IP:127.0.0.1,DNS:localhost' -keyout "$PRIV/key.pem" -out "$PRIV/cert.pem" 2>/dev/null
  python3 "$PRIV_FIXTURE/server.py" "$PRIV/root" "$PRIV/cert.pem" "$PRIV/key.pem" "$PRIV/port" reader fixture-token 2>"$PRIV/server.log" &
  PRIV_PID=$!
  trap 'kill "$PRIV_PID" 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT
  for _ in $(seq 50); do [[ -s "$PRIV/port" ]] && break; sleep 0.2; done
  PRIV_HOST="127.0.0.1:$(cat "$PRIV/port")"
  export CRED_LOG="$PRIV/cred.log"
  priv_config() { printf '[http]\n\tsslCAInfo = %s\n%s' "$PRIV/cert.pem" "$2" >"$PRIV/$1.gitconfig"; printf '%s\n' "$PRIV/$1.gitconfig"; }
  priv() { local cfg=$1; shift; rm -rf "$TEST_TMPDIR/priv-cache"; : >"$CRED_LOG"; GIT_CONFIG_GLOBAL="$cfg" ORG_STANDARDS_CACHE="$TEST_TMPDIR/priv-cache" ORG_STANDARDS_GIT_BASE="https://$PRIV_HOST" "$@"; }
  other_hosts() { grep -cv " https://$PRIV_HOST\(/\|$\)" "$CRED_LOG"; }
  tpriv=$(target private "$OPTED")
  HELPER=$(priv_config helper "$(printf '[credential]\n\thelper = %s\n' "$PRIV_FIXTURE/credential-helper.sh")")
  SCOPED=$(priv_config scoped "$(printf '[credential "https://%s"]\n\thelper = %s\n\tusername = reader\n\tuseHttpPath = true\n' "$PRIV_HOST" "$PRIV_FIXTURE/credential-helper.sh")")
  BARE=$(priv_config bare "$(printf '[core]\n\taskPass = %s\n' "$PRIV_FIXTURE/askpass.sh")")

  priv_dir=$(priv "$HELPER" run dir --root "$tpriv")
  assert_eq "a private org repository over https is cloned with the user's global credential helper, which is asked about the configured host only" \
    "$TEST_TMPDIR/priv-cache/acme/standards|$(g -C "$PRIV/root/acme/standards.git" show main:REVIEW.md | head -n 1)|1|1|0" \
    "$priv_dir|$(head -n 1 "$priv_dir/REVIEW.md" 2>/dev/null)|$(grep -c "^get https://$PRIV_HOST$" "$CRED_LOG")|$(grep -c "^store https://$PRIV_HOST$" "$CRED_LOG")|$(other_hosts)"

  user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
  priv_sub=$(priv "$SCOPED" run subscriptions --root "$tpriv" | cut -f1)
  assert_eq "a private subscription is read with a URL-scoped credential helper, and its useHttpPath setting reaches the helper" \
    "acme/handbook@$HANDBOOK2|yes|0" \
    "$priv_sub|$(grep -q "^get https://$PRIV_HOST/acme/handbook.git$" "$CRED_LOG" && echo yes || echo no)|$(other_hosts)"

  user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: evil.example/handbook\n  - repo: https://evil.example/acme/handbook\n  - repo: acme@evil.example/handbook\n  - repo: acme/handbook\n'
  priv_err=$(priv "$HELPER" errs subscriptions --root "$tpriv" | grep -c 'is not <owner>/<repo>')
  priv_sub=$(priv "$HELPER" run subscriptions --root "$tpriv" | cut -f1)
  assert_eq "subscriptions naming another host are skipped as malformed, and the helper is asked about no host but the configured one" \
    "3|acme/handbook@$HANDBOOK2|0" "$priv_err|$priv_sub|$(other_hosts)"

  REWRITE=$(priv_config rewrite "$(printf '[credential]\n\thelper = %s\n[url "https://localhost:%s/"]\n\tinsteadOf = https://%s/\n' "$PRIV_FIXTURE/credential-helper.sh" "${PRIV_HOST#*:}" "$PRIV_HOST")")
  priv_dir=$(priv "$REWRITE" run dir --root "$tpriv")
  assert_eq "an insteadOf rewrite in the user's own global config is followed, so the helper is asked about the host the user rewrote to" \
    "$TEST_TMPDIR/priv-cache/acme/standards|1|0" \
    "$priv_dir|$(grep -c "^get https://localhost:${PRIV_HOST#*:}$" "$CRED_LOG")|$(grep -c "$PRIV_HOST" "$CRED_LOG")"

  python3 "$PRIV_FIXTURE/redirect.py" "$PRIV/cert.pem" "$PRIV/key.pem" "$PRIV/rport" "localhost:${PRIV_HOST#*:}" 2>"$PRIV/redirect.log" &
  REDIR_PID=$!
  trap 'kill "$PRIV_PID" "$REDIR_PID" 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT
  for _ in $(seq 50); do [[ -s "$PRIV/rport" ]] && break; sleep 0.2; done
  REDIR_BASE="https://127.0.0.1:$(cat "$PRIV/rport")"
  served=$(wc -l <"$PRIV/server.log")
  redir_out=$(priv "$HELPER" env ORG_STANDARDS_GIT_BASE="$REDIR_BASE" bash "$SCRIPT" dir --root "$tpriv" 2>&1; echo "exit=$?")
  assert_eq "a configured host that redirects is not followed: no credential is asked for, the target host is never reached, and the reader says to name the new location" \
    "yes|0|0|1|1" \
    "$([[ -s "$PRIV/redirect.log" ]] && echo yes || echo no)|$(wc -l <"$CRED_LOG")|$(($(wc -l <"$PRIV/server.log") - served))|$(grep -cxF 'org-standards: acme/standards answered with a redirect (for example, it was renamed or moved), which is not followed; set standards_repository to its new location' <<<"$redir_out")|$(grep -cx 'exit=4' <<<"$redir_out")"
  user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
  redir_sub=$(priv "$HELPER" env ORG_STANDARDS_GIT_BASE="$REDIR_BASE" bash "$SCRIPT" subscriptions --root "$tpriv" 2>&1)
  assert_eq "a subscription whose host redirects is not followed, and the reader says to name its new location" "0|1" \
    "$(wc -l <"$CRED_LOG")|$(grep -cxF "org-standards: $USER_INDEX:6: acme/handbook answered with a redirect (for example, it was renamed or moved), which is not followed; set the subscription's repo to its new location" <<<"$redir_sub")"
  kill "$REDIR_PID" 2>/dev/null

  start=$SECONDS
  hung=$(CRED_HANG=1 ORG_STANDARDS_GIT_TIMEOUT=2 priv "$HELPER" code dir --root "$tpriv")
  assert_eq "a credential helper that hangs is stopped by ORG_STANDARDS_GIT_TIMEOUT: exit 4" "4|yes|1" \
    "$hung|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")|$(grep -c "^get https://$PRIV_HOST$" "$CRED_LOG")"

  start=$SECONDS
  bare_code=$(SSH_ASKPASS="$PRIV_FIXTURE/askpass.sh" ORG_STANDARDS_GIT_TIMEOUT=30 priv "$BARE" code dir --root "$tpriv" </dev/null)
  assert_eq "with no credential helper a private clone fails fast and asks nothing: no terminal prompt, no core.askPass, no SSH_ASKPASS" \
    "4|yes|" "$bare_code|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")|$(cat "$CRED_LOG")"

  kill "$PRIV_PID" 2>/dev/null
else
  printf 'SKIP: private https remote cases need python3, openssl and timeout\n'
fi

finish
