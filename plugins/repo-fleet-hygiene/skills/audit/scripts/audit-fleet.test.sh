#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-fleet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN" "$TMP/config" "$TMP/discovered-a" "$TMP/canonical-a" "$TMP/repo-b" "$TMP/old-repo" \
  "$TMP/bad-discovered" "$TMP/bad-canonical" "$TMP/wt-fail" \
  "$TMP/ref-fail" "$TMP/rref-fail" "$TMP/dup-a" "$TMP/new-clone" \
  "$TMP/root/acme/root-repo/.git" \
  "$TMP/emptyroot" \
  "$TMP/wt-a" "$TMP/wt-mismatch" \
  "$TMP/wt-status-fail" "$TMP/wt-regen" "$TMP/wt-ignored" \
  "$TMP/wt-old" \
  "$TMP/discovered-c" "$TMP/canonical-c" "$TMP/gone-repo" "$TMP/lost-repo" "$TMP/net-repo" \
  "$TMP/wt-root/aaa-linked" "$TMP/wt-root/bbb-linked" "$TMP/wt-root/zzz-canonical/.git" \
  "$TMP/wt-admin/sub-wt" "$TMP/wt-admin/sep-wt" \
  "$TMP/canonical-a/.claude/worktrees/nested" "$TMP/canonical-a/husk" \
  "$TMP/prefix-fail"
# Canonical-selection fixture: a LINKED worktree whose directory name sorts before its own main
# worktree under LC_ALL=C, so bounded discovery reaches it first. A linked worktree carries .git as
# a FILE, the main worktree as a DIRECTORY; both resolve to the same --git-common-dir, so whichever
# the glob reaches first wins the dedup. The canonical checkout must not be decided by that order.
: >"$TMP/wt-root/aaa-linked/.git"
: >"$TMP/wt-root/bbb-linked/.git"
# Admin-directory shapes. A submodule and a --separate-git-dir checkout both carry a .git FILE, so
# both reach the retarget path, which must refuse to adopt an administrative directory as canonical.
: >"$TMP/wt-admin/sub-wt/.git"
: >"$TMP/wt-admin/sep-wt/.git"
: >"$TMP/calls.log"

cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -u
[[ "${GIT_NO_LAZY_FETCH:-}" == "1" && "${GIT_OPTIONAL_LOCKS:-}" == "0" &&
  "${GIT_CONFIG_COUNT:-}" == "0" && "${GIT_TERMINAL_PROMPT:-}" == "0" ]] || exit 90
[[ -z "${GIT_CONFIG_PARAMETERS+x}" && -z "${GIT_DIR+x}" && -z "${GIT_WORK_TREE+x}" ]] || exit 91
printf 'git' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"

repo=""
if [[ "${1:-}" == "-C" ]]; then
  repo="$2"
  shift 2
fi
cmd="${1:-}"
shift || true

base="$(basename "$repo")"
case "$cmd" in
rev-parse)
  case "${1:-}" in
  --show-toplevel)
    case "$base" in
    discovered-a) printf '%s\n' "$TEST_ROOT/discovered-a" ;;
    canonical-a) printf '%s\n' "$TEST_ROOT/canonical-a" ;;
    repo-b) printf '%s\n' "$TEST_ROOT/repo-b" ;;
    old-repo) printf '%s\n' "$TEST_ROOT/old-repo" ;;
    wt-old) printf '%s\n' "$TEST_ROOT/wt-old" ;;
    bad-discovered) printf '%s\n' "$TEST_ROOT/bad-discovered" ;;
    bad-canonical) printf '%s\n' "$TEST_ROOT/bad-canonical" ;;
    wt-fail) printf '%s\n' "$TEST_ROOT/wt-fail" ;;
    ref-fail) printf '%s\n' "$TEST_ROOT/ref-fail" ;;
    rref-fail) printf '%s\n' "$TEST_ROOT/rref-fail" ;;
    dup-a) printf '%s\n' "$TEST_ROOT/dup-a" ;;
    new-clone) printf '%s\n' "$TEST_ROOT/new-clone" ;;
    root-repo) printf '%s\n' "$TEST_ROOT/root/acme/root-repo" ;;
    discovered-c | canonical-c) printf '%s\n' "$TEST_ROOT/canonical-c" ;;
    gone-repo) printf '%s\n' "$TEST_ROOT/gone-repo" ;;
    lost-repo) printf '%s\n' "$TEST_ROOT/lost-repo" ;;
    net-repo) printf '%s\n' "$TEST_ROOT/net-repo" ;;
    # Inside a linked worktree --show-toplevel returns the LINKED root, which is exactly the wrong
    # answer for a canonical checkout -- the defect this fixture pins.
    aaa-linked) printf '%s\n' "$TEST_ROOT/wt-root/aaa-linked" ;;
    bbb-linked) printf '%s\n' "$TEST_ROOT/wt-root/bbb-linked" ;;
    zzz-canonical) printf '%s\n' "$TEST_ROOT/wt-root/zzz-canonical" ;;
    # Admin-directory shapes. The porcelain's first record is not always a checkout, and all three
    # present a .git FILE so they reach the retarget. sub-admin re-resolves to sub-wt's own toplevel
    # (a submodule self-cancels); sep-gitdir and bare-gitdir are not working trees at all and fail
    # this probe, which is what keeps them from being adopted.
    sub-wt | sub-admin) printf '%s\n' "$TEST_ROOT/wt-admin/sub-wt" ;;
    sep-wt) printf '%s\n' "$TEST_ROOT/wt-admin/sep-wt" ;;
    nested) printf '%s\n' "$TEST_ROOT/canonical-a/.claude/worktrees/nested" ;;
    husk) printf '%s\n' "$TEST_ROOT/canonical-a" ;;
    prefix-fail) printf '%s\n' "$TEST_ROOT/prefix-fail" ;;
    wt-a) printf '%s\n' "$TEST_ROOT/wt-a" ;;
    wt-mismatch) printf '%s\n' "$TEST_ROOT/wt-mismatch" ;;
    wt-status-fail) printf '%s\n' "$TEST_ROOT/wt-status-fail" ;;
    wt-regen) printf '%s\n' "$TEST_ROOT/wt-regen" ;;
    wt-ignored) printf '%s\n' "$TEST_ROOT/wt-ignored" ;;
    *) exit 1 ;;
    esac
    ;;
  --show-prefix)
    # Empty at a work-tree ROOT; a path below the root reports its own relative prefix, which is
    # what separates a real worktree from a leftover directory that git -C still answers for.
    case "$base" in
    husk) printf '%s\n' 'husk/' ;;
    # The probe FAILING is a third state, distinct from empty and non-empty: root-ness is then
    # unproven rather than disproven. Without an arm that exits nonzero the collector's
    # unverifiable branch is dead code as far as this suite is concerned. Same shape as the
    # wt-fail fixture below, which does this for the worktree inventory.
    prefix-fail) exit 7 ;;
    *) printf '\n' ;;
    esac
    ;;
  --is-bare-repository)
    # Only the bare hub answers true; everything else is a working checkout.
    case "$base" in
    *) printf 'false\n' ;;
    esac
    ;;
  --path-format=absolute)
    case "$base" in
    discovered-a | canonical-a | wt-a) printf '%s\n' "$TEST_ROOT/canonical-a/.git" ;;
    wt-mismatch) printf '%s\n' "$TEST_ROOT/other-repository/.git" ;;
    repo-b) printf '%s\n' "$TEST_ROOT/repo-b/.git" ;;
    old-repo) printf '%s\n' "$TEST_ROOT/old-repo/.git" ;;
    wt-old) printf '%s\n' "$TEST_ROOT/old-repo/.git" ;;
    bad-discovered) printf '%s\n' "$TEST_ROOT/bad-discovered/.git" ;;
    bad-canonical) printf '%s\n' "$TEST_ROOT/bad-canonical/.git" ;;
    wt-fail) printf '%s\n' "$TEST_ROOT/wt-fail/.git" ;;
    ref-fail) printf '%s\n' "$TEST_ROOT/ref-fail/.git" ;;
    rref-fail) printf '%s\n' "$TEST_ROOT/rref-fail/.git" ;;
    dup-a) printf '%s\n' "$TEST_ROOT/dup-a/.git" ;;
    new-clone) printf '%s\n' "$TEST_ROOT/new-clone/.git" ;;
    root-repo) printf '%s\n' "$TEST_ROOT/root/acme/root-repo/.git" ;;
    discovered-c | canonical-c) printf '%s\n' "$TEST_ROOT/canonical-c/.git" ;;
    gone-repo) printf '%s\n' "$TEST_ROOT/gone-repo/.git" ;;
    lost-repo) printf '%s\n' "$TEST_ROOT/lost-repo/.git" ;;
    net-repo) printf '%s\n' "$TEST_ROOT/net-repo/.git" ;;
    nested) printf '%s\n' "$TEST_ROOT/canonical-a/.git" ;;
    prefix-fail) printf '%s\n' "$TEST_ROOT/canonical-a/.git" ;;
    wt-a | wt-mismatch | wt-status-fail | wt-regen | wt-ignored) printf '%s\n' "$TEST_ROOT/canonical-a/.git" ;;
    aaa-linked | bbb-linked | zzz-canonical) printf '%s\n' "$TEST_ROOT/wt-root/zzz-canonical/.git" ;;
    sub-wt) printf '%s\n' "$TEST_ROOT/wt-admin/sub-admin" ;;
    sep-wt) printf '%s\n' "$TEST_ROOT/wt-admin/sep-gitdir" ;;
    *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
  esac
  ;;
remote)
  if [[ "${1:-}" == "get-url" && "${2:-}" == "origin" ]]; then
    case "$base" in
    discovered-a | canonical-a) printf '%s\n' 'https://github.com/acme/repo-a.git' ;;
    repo-b) printf '%s\n' 'git@github.com:acme/repo-b.git' ;;
    old-repo) printf '%s\n' 'https://github.com/old/repo.git' ;;
    bad-discovered) printf '%s\n' 'https://github.com/acme/bad.git' ;;
    bad-canonical) printf '%s\n' 'https://gitlab.com/other/unrelated.git' ;;
    wt-fail) printf '%s\n' 'https://github.com/acme/wt-fail.git' ;;
    ref-fail) printf '%s\n' 'https://github.com/acme/ref-fail.git' ;;
    rref-fail) printf '%s\n' 'https://github.com/acme/rref-fail.git' ;;
    dup-a) printf '%s\n' 'https://github.com/acme/repo-b.git' ;;
    new-clone) printf '%s\n' 'https://github.com/new/repo.git' ;;
    root-repo) printf '%s\n' 'https://github.com/acme/root-repo.git' ;;
    discovered-c | canonical-c) printf '%s\n' 'https://github.com/acme/repo-c.git' ;;
    gone-repo) printf '%s\n' 'https://github.com/gone/away.git' ;;
    lost-repo) printf '%s\n' 'https://github.com/lost/cause.git' ;;
    net-repo) printf '%s\n' 'https://github.com/gone/net.git' ;;
    aaa-linked | bbb-linked | zzz-canonical) printf '%s\n' 'https://github.com/acme/wt-canon.git' ;;
    sub-wt) printf '%s\n' 'https://github.com/acme/sub-mod.git' ;;
    sep-wt) printf '%s\n' 'https://github.com/acme/sep-mod.git' ;;
    *) exit 1 ;;
    esac
  else
    printf '%s\n' origin
  fi
  ;;
worktree)
  [[ "${1:-}" == "list" ]] || exit 97
  case "$base" in
  canonical-a)
    printf 'worktree %s\0HEAD main-a\0branch refs/heads/main\0\0' "$TEST_ROOT/canonical-a"
    printf 'worktree %s\0HEAD sha-a\0branch refs/heads/feature/shared\0\0' "$TEST_ROOT/wt-a"
    printf 'worktree %s\0HEAD mismatch\0branch refs/heads/feature/mismatch\0\0' "$TEST_ROOT/wt-mismatch"
    printf 'worktree %s\0HEAD evil\0prunable missing\0\0' "$EVIL_PATH"
    # Placement drift: a real work-tree ROOT (empty --show-prefix) sitting inside the canonical
    # checkout's own tree. Distinct from the husk below, which is not a work-tree root at all.
    printf 'worktree %s\0HEAD nested\0branch refs/heads/feature/nested\0\0' "$TEST_ROOT/canonical-a/.claude/worktrees/nested"
    # A registered path that exists but is a plain subdirectory: git -C answers it with the
    # CONTAINING repository's state at exit 0, indistinguishable from a healthy clean worktree.
    printf 'worktree %s\0HEAD husk\0branch refs/heads/feature/husk\0\0' "$TEST_ROOT/canonical-a/husk"
    # A registered path whose root-ness probe FAILS outright.
    printf 'worktree %s\0HEAD pfail\0branch refs/heads/feature/prefix-fail\0\0' "$TEST_ROOT/prefix-fail"
    # Linked worktrees for reclaimable-worktree: wt-a is clean with no ignored entries, wt-regen
    # is clean with regenerable ignored only, wt-ignored has non-regenerable ignored content,
    # wt-mismatch is dirty, wt-status-fail cannot answer status --porcelain --ignored.
    printf 'worktree %s\0HEAD status-fail\0branch refs/heads/feature/status-fail\0\0' "$TEST_ROOT/wt-status-fail"
    printf 'worktree %s\0HEAD regen\0branch refs/heads/feature/regen\0\0' "$TEST_ROOT/wt-regen"
    printf 'worktree %s\0HEAD ignored\0branch refs/heads/feature/ignored\0\0' "$TEST_ROOT/wt-ignored"
    ;;
  repo-b)
    printf 'worktree %s\0HEAD main-b\0branch refs/heads/main\0\0' "$TEST_ROOT/repo-b"
    ;;
  old-repo)
    # Moved-identity fixture (#2600): local branch/worktree inventory must still be classified
    # against the resolved GitHub identity (new/repo), not skipped after github-remote-moved.
    printf 'worktree %s\0HEAD old-main\0branch refs/heads/main\0\0' "$TEST_ROOT/old-repo"
    printf 'worktree %s\0HEAD moved-merged-tip\0branch refs/heads/feature/moved-merged\0\0' "$TEST_ROOT/wt-old"
    ;;
  wt-fail) exit 7 ;;
  ref-fail)
    printf 'worktree %s\0HEAD ref-main\0branch refs/heads/main\0\0' "$TEST_ROOT/ref-fail"
    ;;
  rref-fail)
    printf 'worktree %s\0HEAD rr-main\0branch refs/heads/main\0\0' "$TEST_ROOT/rref-fail"
    ;;
  dup-a)
    printf 'worktree %s\0HEAD dup-main\0branch refs/heads/main\0\0' "$TEST_ROOT/dup-a"
    ;;
  new-clone)
    printf 'worktree %s\0HEAD nc-main\0branch refs/heads/main\0\0' "$TEST_ROOT/new-clone"
    ;;
  root-repo)
    printf 'worktree %s\0HEAD root-main\0branch refs/heads/main\0\0' "$TEST_ROOT/root/acme/root-repo"
    ;;
  canonical-c)
    printf 'worktree %s\0HEAD main-c\0branch refs/heads/main\0\0' "$TEST_ROOT/canonical-c"
    ;;
  gone-repo)
    printf 'worktree %s\0HEAD gone-main\0branch refs/heads/main\0\0' "$TEST_ROOT/gone-repo"
    ;;
  lost-repo)
    printf 'worktree %s\0HEAD lost-main\0branch refs/heads/main\0\0' "$TEST_ROOT/lost-repo"
    ;;
  net-repo)
    printf 'worktree %s\0HEAD net-main\0branch refs/heads/main\0\0' "$TEST_ROOT/net-repo"
    ;;
  # git-worktree(1): the porcelain lists the MAIN worktree first regardless of which worktree the
  # command ran from. Both fixtures answer identically, so the main worktree is discoverable from
  # inside the linked one.
  aaa-linked | bbb-linked | zzz-canonical)
    printf 'worktree %s\0HEAD canon-main\0branch refs/heads/main\0\0' "$TEST_ROOT/wt-root/zzz-canonical"
    printf 'worktree %s\0HEAD canon-feat\0branch refs/heads/feature/linked\0\0' "$TEST_ROOT/wt-root/aaa-linked"
    printf 'worktree %s\0HEAD canon-feat2\0branch refs/heads/feature/linked-2\0\0' "$TEST_ROOT/wt-root/bbb-linked"
    ;;
  # First record is the superproject's .git/modules/<name> admin directory, exactly as real git
  # reports it from inside a submodule (verified on git 2.54).
  sub-wt)
    printf 'worktree %s\0HEAD sub-main\0branch refs/heads/main\0\0' "$TEST_ROOT/wt-admin/sub-admin"
    ;;
  # First record is the detached git directory, which is not a working tree at all.
  sep-wt)
    printf 'worktree %s\0HEAD sep-main\0branch refs/heads/main\0\0' "$TEST_ROOT/wt-admin/sep-gitdir"
    ;;
  esac
  ;;
symbolic-ref)
  printf '%s\n' refs/remotes/origin/main
  ;;
branch)
  case "$base" in
  canonical-a) printf '%s\n' main ;;
  repo-b | old-repo | root-repo | wt-fail | ref-fail | rref-fail | dup-a | new-clone | canonical-c | gone-repo | lost-repo | net-repo) printf '%s\n' main ;;
  aaa-linked | bbb-linked | zzz-canonical) printf '%s\n' main ;;
  sub-wt | sep-wt) printf '%s\n' main ;;
  esac
  ;;
for-each-ref)
  # refs/remotes/<remote>/ scans (case-branch below) prove a local-only branch never becomes a
  # --head argument to gh: canonical-a's remote mirror deliberately omits feature/mismatch.
  # repo-b deliberately matches NO case here (empty output, exit 0): it is the empty-remote-
  # inventory regression fixture for #1119 -- its non-default feature/shared branch has no PR-batch
  # row, so the exact-fallback gate loop must run over an empty REMOTE_BRANCH_NAMES without
  # aborting the fleet (unguarded expansion is fatal under set -u on bash <= 4.3) and must report
  # the skipped lookup as a visible privacy gap.
  if [[ "${3:-}" == refs/remotes/*/ ]]; then
    case "$base" in
    canonical-a)
      printf 'origin\thead-a\0\norigin/main\tmain-a\0\norigin/feature/shared\tsha-a\0\norigin/stale/changed\tdrift-tip\0\n'
      ;;
    # Moved-identity checkout (#2600): remote still advertises the feature head, so the privacy
    # gate must not block the exact-OID merge match against the resolved identity.
    old-repo) printf 'origin/main\told-main\0\norigin/feature/moved-merged\tmoved-merged-tip\0\norigin/feature/moved-local\tmoved-local-tip\0\n' ;;
    rref-fail) exit 9 ;;
    aaa-linked | bbb-linked | zzz-canonical) printf 'origin/main\tcanon-main\0\n' ;;
    sub-wt) printf 'origin/main\tsub-main\0\n' ;;
    sep-wt) printf 'origin/main\tsep-main\0\n' ;;
    esac
    exit 0
  fi
  case "$base" in
  canonical-a)
    # stale/gone: merged-PR batch row exists at a different OID (drift) but the branch has no
    # remote-tracking ref -- the drift finding must state tip/headRefOid differ without claiming
    # the commits were never pushed (they may still be on the remote).
    printf 'main\tmain-a\0\nfeature/shared\tsha-a\0\nstale/changed\tdrift-tip\0\nfeature/mismatch\tmismatch\0\nstale/gone\tgone-tip\0\n'
    ;;
  repo-b)
    printf 'main\tmain-b\0\nfeature/shared\tsha-b\0\n'
    ;;
  old-repo) printf 'main\told-main\0\nfeature/moved-merged\tmoved-merged-tip\0\nfeature/moved-local\tmoved-local-tip\0\n' ;;
  wt-fail) printf 'main\twt-main\0\nfeature/fail\tfail-tip\0\n' ;;
  ref-fail) printf 'main\tref-main\0\nfeature/partial\tpartial-tip\0'; exit 9 ;;
  rref-fail) printf 'main\trr-main\0\nfeature/gated\trr-tip\0\n' ;;
  dup-a) printf 'main\tdup-main\0\n' ;;
  new-clone) printf 'main\tnc-main\0\n' ;;
  root-repo) printf 'main\troot-main\0\n' ;;
  canonical-c) printf 'main\tmain-c\0\n' ;;
  gone-repo) printf 'main\tgone-main\0\n' ;;
  lost-repo) printf 'main\tlost-main\0\n' ;;
  net-repo) printf 'main\tnet-main\0\n' ;;
  aaa-linked | bbb-linked | zzz-canonical) printf 'main\tcanon-main\0\nfeature/linked\tcanon-feat\0\n' ;;
  sub-wt) printf 'main\tsub-main\0\n' ;;
  sep-wt) printf 'main\tsep-main\0\n' ;;
  esac
  ;;
merge-base) exit 1 ;;
status)
  [[ "${1:-}" == "--porcelain" && "${2:-}" == "--ignored" && "${3:-}" == "--untracked-files=normal" ]] || exit 96
  case "$base" in
  wt-a) printf '' ;;
  wt-regen) printf '!! node_modules/\n' ;;
  wt-ignored) printf '!! .work/handoffs/\n!! node_modules/\n' ;;
  wt-mismatch) printf ' M file.txt\n' ;;
  wt-status-fail) exit 7 ;;
  wt-old) printf '' ;;
  *) printf '' ;;
  esac
  ;;
stash)
  [[ "${1:-}" == "list" ]] || exit 96
  # Once-per-repository collection: answer only for canonical checkouts. A per-worktree call
  # would be a collector bug; leave linked worktree bases failing closed so the suite notices.
  case "$base" in
  canonical-a) printf '' ;;
  repo-b | old-repo | root-repo | wt-fail | ref-fail | rref-fail | dup-a | new-clone | canonical-c | \
    gone-repo | lost-repo | net-repo | zzz-canonical | sub-wt | sep-wt)
    printf ''
    ;;
  *) exit 7 ;;
  esac
  ;;
log)
  [[ "${1:-}" == "-1" && "${2:-}" == "--format=%ct" && "${3:-}" == "HEAD" ]] || exit 96
  case "$base" in
  wt-a | wt-old) printf '1700000000\n' ;;
  *) printf '1\n' ;;
  esac
  ;;
config) "$REAL_GIT" config "$@" ;;
*) exit 96 ;;
esac
EOF

cat >"$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -u
[[ "${GH_HOST:-}" == "github.com" && "${GH_PROMPT_DISABLED:-}" == "1" &&
  "${GH_TELEMETRY:-}" == "false" && "${GH_NO_UPDATE_NOTIFIER:-}" == "1" &&
  "${GH_NO_EXTENSION_UPDATE_NOTIFIER:-}" == "1" && "${GH_SPINNER_DISABLED:-}" == "1" ]] || exit 92
[[ -z "${GH_REPO+x}" && -z "${GH_DEBUG+x}" ]] || exit 93
printf 'gh' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"

case "${1:-}" in
auth)
  [[ "${MOCK_GH_AUTH_FAIL:-}" == "1" ]] && exit 1
  exit 0
  ;;
api)
  endpoint="${2:-}"
  case "$endpoint" in
  user)
    [[ "${MOCK_GH_USER_FAIL:-}" == "1" ]] && exit 1
    printf 'test-login'
    ;;
  repos/acme/repo-a) printf 'acme/repo-a\tmain' ;;
  repos/acme/repo-b) printf 'acme/repo-b\tmain' ;;
  repos/acme/root-repo) printf 'acme/root-repo\tmain' ;;
  repos/acme/bad) printf 'acme/bad\tmain' ;;
  repos/acme/wt-fail) printf 'acme/wt-fail\tmain' ;;
  repos/acme/ref-fail) printf 'acme/ref-fail\tmain' ;;
  repos/acme/rref-fail) printf 'acme/rref-fail\tmain' ;;
  repos/old/repo) printf 'new/repo\tmain' ;;
  repos/new/repo) printf 'new/repo\tmain' ;;
  repos/acme/repo-c) printf 'acme/repo-c\tmain' ;;
  repos/acme/wt-canon) printf 'acme/wt-canon\tmain' ;;
  repos/acme/sub-mod) printf 'acme/sub-mod\tmain' ;;
  repos/acme/sep-mod) printf 'acme/sep-mod\tmain' ;;
  repos/gone/net) printf 'gh: connection reset by peer\n' >&2; exit 1 ;;
  *) printf 'gh: Not Found (HTTP 404)\n' >&2; exit 1 ;;
  esac
  ;;
pr)
  repo=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--repo" ]]; then repo="$2"; shift 2; else shift; fi
  done
  case "$repo" in
  github.com/acme/repo-a)
    printf '18\tfeature/shared\tsha-a\t2026-07-01T00:00:00Z\thttps://github.com/acme/repo-a/pull/18\n'
    printf '42\tstale/changed\tmerged-tip\t2026-07-02T00:00:00Z\thttps://github.com/acme/repo-a/pull/42\n'
    printf '43\tstale/gone\tother-tip\t2026-07-03T00:00:00Z\thttps://github.com/acme/repo-a/pull/43\n'
    ;;
  github.com/acme/repo-b | github.com/acme/root-repo | github.com/acme/repo-c) ;;
  # Resolved identity for the moved-remote fixture: merge evidence must be queried here, not under
  # the stale configured remote (old/repo). Exact-OID rows prove branch/worktree analysis continued.
  github.com/new/repo)
    printf '7\tfeature/moved-merged\tmoved-merged-tip\t2026-07-04T00:00:00Z\thttps://github.com/new/repo/pull/7\n'
    printf '8\tfeature/moved-local\tmoved-local-tip\t2026-07-05T00:00:00Z\thttps://github.com/new/repo/pull/8\n'
    ;;
  # A FULL merged-PR window: gh returns at most --limit rows, so 200 rows means older merged PRs
  # were silently dropped. Every row is a branch this repository does not have locally, so the
  # truncation disclosure is the only thing this fixture can produce.
  github.com/acme/sub-mod | github.com/acme/sep-mod) ;;
  github.com/acme/wt-canon)
    i=1
    while [[ "$i" -le 1000 ]]; do
      printf '%s\tarchived/branch-%s\toid-%s\t2026-07-01T00:00:00Z\thttps://github.com/acme/wt-canon/pull/%s\n' "$i" "$i" "$i" "$i"
      i=$((i + 1))
    done
    ;;
  github.com/acme/rref-fail) ;;
  github.com/acme/wt-fail)
    printf '88\tfeature/fail\tfail-tip\t2026-07-03T00:00:00Z\thttps://github.com/acme/wt-fail/pull/88\n'
    ;;
  github.com/acme/ref-fail) ;;
  *) exit 1 ;;
  esac
  ;;
*) exit 95 ;;
esac
EOF

chmod +x "$MOCK_BIN/git" "$MOCK_BIN/gh"
REAL_GIT="$(command -v git)"
export REAL_GIT
export PATH="$MOCK_BIN:$PATH"
export CALL_LOG="$TMP/calls.log"
export TEST_ROOT="$TMP"
EVIL_PATH="$TMP/evil"$'\nFinding: forged\nConfidence: CRITICAL\nHandoff: injected-control\033[31m'
export EVIL_PATH

cat >"$TMP/config/repo-fleet-hygiene.conf" <<'EOF'
[fleet]
    root = ../root
    root = ../emptyroot
    repo = ../discovered-a
    repo = ../repo-b
    repo = ../old-repo
    repo = ../bad-discovered
    repo = ../wt-fail
    repo = ../ref-fail
    repo = ../rref-fail
    repo = ../dup-a
    repo = ../new-clone
    repo = ../deleted-repo
    root = ../gone-root
    repo = ../discovered-c
    repo = ../gone-repo
    repo = ../lost-repo
    repo = ../net-repo
    maxDepth = 5
    ackUnavailable = github.com/Gone/Away
    ackUnavailable = github.com/gone/net
[canonical "github.com/acme/repo-a"]
    path = ../canonical-a
[canonical "github.com/acme/bad"]
    path = ../bad-canonical
[canonical "github.com/Acme/Repo-C"]
    path = ../canonical-c
EOF

output="$TMP/output.txt"
REPO_FLEET_TEST_FAST_TIMEOUTS=1 bash "$SCRIPT" --config "$TMP/config/repo-fleet-hygiene.conf" >"$output"

failures=0
assert_contains() {
  local label="$1" pattern="$2"
  if ! grep -Fq -- "$pattern" "$output"; then
    printf 'FAIL: %s (missing %s)\n' "$label" "$pattern" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_not_contains() {
  local label="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$output"; then
    printf 'FAIL: %s (unexpected %s)\n' "$label" "$pattern" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_contains "canonical override used" "Canonical: $TMP/canonical-a"
assert_contains "mixed-case canonical config section honored" "Canonical: $TMP/canonical-c"
assert_contains "bounded root discovery used" "Repo: $TMP/root/acme/root-repo"
assert_contains "same-name branch scoped to repo A" "Target: $TMP/canonical-a :: feature/shared"
assert_contains "merged worktree evidence" "Finding: merged-worktree"
assert_contains "tip drift manual review" "Finding: merged-pr-tip-drift"
assert_contains "worktree common-dir mismatch" "Finding: worktree-admin-mismatch"
assert_contains "clean linked worktree is reclaimable" "Finding: reclaimable-worktree"
assert_contains "reclaimable evidence names absence of ignored entries" \
  "no tracked/untracked changes and no ignored entries"
assert_contains "failed status probe is disposability-unverifiable" \
  "Finding: worktree-disposability-unverifiable"
assert_contains "non-regenerable ignored content is reported" "Finding: worktree-ignored-content"
assert_contains "ignored-content evidence names the destroyable path" ".work/handoffs/"
assert_contains "stash state is collected once per repository" \
  "Stashes: none (repository-global refs/stash; unaffected by worktree removal)"
assert_contains "worktree nested in its own repository is reported" "Finding: worktree-nested-in-repository"
assert_contains "nested finding names the containing checkout" \
  "registered worktree root is inside the canonical checkout's own working tree ($TMP/canonical-a)"
assert_contains "a registered path that is not a work-tree root is reported" "Finding: worktree-not-a-root"
assert_contains "a failed root-ness probe is UNKNOWN, not a silent pass" \
  "Finding: worktree-root-unverifiable"
assert_contains "and it says root-ness is unproven rather than disproven" \
  "git rev-parse --show-prefix failed at the registered path"
assert_contains "not-a-root finding says why the probe reads clean" \
  "probing it reports the containing repository's state at exit 0"
# The two are distinct conditions, not one collapsed into the other: the nested worktree IS a real
# work-tree root, so it must not also be reported as not-a-root, and the husk stops before the
# placement test because a path that is not a worktree has no placement to judge. Asserted on the
# Target lines WITHIN each finding block — a whole-file match would be satisfied by the other
# finding's block and prove nothing.
assert_kind_targets() {
  local label="$1" kind="$2" wanted="$3" forbidden="$4" targets
  targets="$(grep -A2 -F "Finding: $kind" "$output" | grep -F 'Target: ')"
  if [[ "$targets" == *"$wanted"* && "$targets" != *"$forbidden"* ]]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s (targets for %s: %s)\n' "$label" "$kind" "$targets" >&2
    failures=$((failures + 1))
  fi
}
assert_kind_targets "not-a-root names the husk and not the nested worktree" \
  worktree-not-a-root "canonical-a/husk" "worktrees/nested"
assert_kind_targets "nested names the nested worktree and not the husk" \
  worktree-nested-in-repository "worktrees/nested" "canonical-a/husk"
assert_kind_targets "reclaimable names wt-a and not dirty or status-fail siblings" \
  reclaimable-worktree "wt-a" "wt-mismatch"
assert_kind_targets "reclaimable does not include status-fail sibling" \
  reclaimable-worktree "wt-a" "wt-status-fail"
assert_kind_targets "reclaimable includes regenerable-ignored worktree" \
  reclaimable-worktree "wt-regen" "wt-ignored"
assert_kind_targets "ignored-content names non-regenerable worktree and not regenerable sibling" \
  worktree-ignored-content "wt-ignored" "wt-regen"
assert_kind_targets "ignored-content does not include clean wt-a" \
  worktree-ignored-content "wt-ignored" "wt-a"
# Regenerable-only evidence must appear on a reclaimable finding (not only in ignored-content).
if grep -A5 -F "Finding: reclaimable-worktree" "$output" | grep -Fq "ignored entries are regenerable only: node_modules/"; then
  printf 'PASS: regenerable ignored entries are named on reclaimable-worktree\n'
else
  printf 'FAIL: regenerable ignored entries are named on reclaimable-worktree\n' >&2
  failures=$((failures + 1))
fi
assert_contains "moved repository detected" "Target: origin (old/repo -> new/repo)"
assert_contains "moved-remote finding states analysis continues" \
  "branch and worktree analysis continues against that resolved identity"
# #2600: github-remote-moved must not silent-skip local classification. The resolved identity
# (new/repo) supplies merge evidence for both an attached worktree branch and an unattached local.
assert_kind_targets "moved-remote still emits merged-worktree on resolved identity" \
  merged-worktree "old-repo :: feature/moved-merged" "new-clone"
assert_kind_targets "moved-remote still emits merged-local-branch on resolved identity" \
  merged-local-branch "old-repo :: feature/moved-local" "new-clone"
assert_contains "moved-remote worktree disposability still classified" "Target: $TMP/wt-old"
assert_contains "non-GitHub canonical override fails closed" "canonical override has a missing, ambiguous, credential-only, or non-github.com remote"
assert_contains "worktree inventory failure is unknown" "Finding: worktree-inventory-unavailable"
assert_contains "branch inventory failure is unknown" "Finding: branch-inventory-unavailable"
assert_contains "control-bearing path was encoded" '\nFinding: forged\nConfidence: CRITICAL\nHandoff: injected-control'
assert_contains "report states the enforcing read-only mechanism, not a tallied constant" "Mutations: none possible"
assert_not_contains "no hardcoded mutation tally" "Mutation count: 0"
assert_not_contains "repo B branch did not inherit repo A merge" "Target: $TMP/repo-b :: feature/shared"
assert_not_contains "invalid canonical state was not combined" "Target: $TMP/bad-canonical ::"
assert_not_contains "failed worktree inventory suppressed branch candidate" "Target: $TMP/wt-fail :: feature/fail"
assert_not_contains "partial branch inventory suppressed branch candidate" "Target: $TMP/ref-fail :: feature/partial"
assert_contains "failed repositories not counted successful" "Summary: repositories_audited=11"

# Duplicate detection keys on the CANONICALIZED identity: old-repo (remote still says old/repo,
# resolved to new/repo) must pair with new-clone (cloned from new/repo directly).
if grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -F "Evidence:" | grep -Fq "$TMP/old-repo" &&
  grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -F "Evidence:" | grep -Fq "$TMP/new-clone"; then
  printf 'PASS: moved-remote checkout pairs with fresh clone via canonical identity\n'
else
  printf 'FAIL: moved-remote checkout pairs with fresh clone via canonical identity\n' >&2
  failures=$((failures + 1))
fi

# Stale CONFIG-sourced entries degrade per-entry (deleted-repo, gone-root) and the run continues;
# a CLI-supplied bad path must still hard-fail (checked in a separate run below).
assert_contains "stale config repo degrades per-entry" "Finding: stale-config-entry"
# The script may canonicalize CONFIG_DIR (e.g. /tmp -> its symlink target on Git Bash), so match
# the stable config-relative suffix rather than the $TMP prefix.
assert_contains "stale config repo names the path" "config/../deleted-repo"
assert_contains "stale config root names the path" "config/../gone-root"
assert_contains "stale root reason names fleet.root" "configured fleet.root path is not a directory"

# Duplicate checkouts of one identity (repo-b + dup-a) get ONE LOW informational finding listing
# both paths; a single-checkout identity gets none.
if grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -Fq "Confidence: LOW"; then
  printf 'PASS: duplicate-checkout stays LOW\n'
else
  printf 'FAIL: duplicate-checkout stays LOW\n' >&2
  failures=$((failures + 1))
fi
if grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -F "Evidence:" | grep -Fq "$TMP/repo-b" &&
  grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -F "Evidence:" | grep -Fq "$TMP/dup-a"; then
  printf 'PASS: duplicate-checkout lists both checkout paths\n'
else
  printf 'FAIL: duplicate-checkout lists both checkout paths\n' >&2
  failures=$((failures + 1))
fi
if grep -A3 -F "Finding: duplicate-checkout" "$output" | grep -Fq "Target: github.com/acme/repo-a"; then
  printf 'FAIL: single-checkout identity wrongly reported as duplicate\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: single-checkout identity not reported as duplicate\n'
fi
assert_contains "per-root discovered count for a contributing root" "../root: 1 repositories"
assert_contains "zero-contribution root stays visible in the header" "../emptyroot: 0 repositories"

# Empty remote-ref inventory (repo-b: refs/remotes scan returns nothing with exit 0) must reach
# and survive the exact-fallback gate loop -- on bash <= 4.3 an unguarded empty-array expansion
# under set -u aborts the whole fleet -- and the privacy-gated skip must be visible, never silent.
if grep -A3 -F "Finding: merge-evidence-privacy-gated" "$output" | grep -Fq "Target: $TMP/repo-b"; then
  printf 'PASS: empty remote inventory survives gate loop and reports privacy gap\n'
else
  printf 'FAIL: empty remote inventory survives gate loop and reports privacy gap\n' >&2
  failures=$((failures + 1))
fi
assert_contains "local-only branch named in aggregate privacy gap" \
  "absent from the local remote-tracking inventory: feature/mismatch"
# A FAILED remote-ref scan (rref-fail) already reports remote-branch-inventory-unavailable
# repo-wide; the per-repo privacy-gap aggregate must stay quiet there, not double-report.
assert_contains "failed remote-ref scan reported repo-wide" "Finding: remote-branch-inventory-unavailable"
if grep -A3 -F "Finding: merge-evidence-privacy-gated" "$output" | grep -Fq "Target: $TMP/rref-fail"; then
  printf 'FAIL: failed remote inventory double-reported as privacy gap\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: failed remote inventory not double-reported as privacy gap\n'
fi
assert_not_contains "privacy-gated handoff does not suggest re-fetch" \
  "re-fetch the branch to restore remote evidence"
assert_contains "privacy-gated handoff names PR lookup for auto-deleted heads" \
  "gh pr list --repo github.com/"
assert_contains "privacy-gated handoff distinguishes never-pushed locals" \
  "Never-pushed locals: push to publish the branch name, then rerun"

# Drift push-state evidence: stale/changed has a same-named remote-tracking ref at the SAME OID
# (pushed as of last fetch); stale/gone has a drift-batch row but NO remote-tracking ref — that
# absence must not be framed as "never pushed" (#2603).
assert_contains "pushed drift named in evidence" \
  "current local tip is drift-tip; local tip matches the last-fetched remote-tracking ref (pushed as of the last fetch; verify current remote state before relying on recoverability)"
assert_contains "absent remote-tracking tip named without unpushed claim" \
  "current local tip is gone-tip; local tip not on the last-fetched remote-tracking ref (tip differs from merged PR headRefOid; commits may still be on the remote)"
assert_not_contains "tip-drift evidence never claims unpushed without proof" \
  "may never have been pushed"

# Header names the authenticated gh account; a failed login probe degrades to the plain line.
assert_contains "header names gh account" "GitHub evidence: available (account: test-login)"

# Clean repos say so explicitly instead of ending the section without a marker.
if grep -A6 -F "Repo: $TMP/root/acme/root-repo" "$output" | grep -Fq "Findings: none"; then
  printf 'PASS: clean repo emits explicit Findings: none marker\n'
else
  printf 'FAIL: clean repo emits explicit Findings: none marker\n' >&2
  failures=$((failures + 1))
fi
if grep -A6 -F "Repo: $TMP/discovered-a" "$output" | grep -Fq "Findings: none"; then
  printf 'FAIL: finding-bearing repo wrongly emitted Findings: none\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: finding-bearing repo does not emit Findings: none\n'
fi

# fleet.ackUnavailable: 404 on an acked identity (mixed-case config entry) is
# demoted to ACKNOWLEDGED; an unacked 404 stays UNKNOWN; a non-404 failure on
# an acked identity stays UNKNOWN with its real reason.
if grep -B2 -F "Target: github.com/gone/away" "$output" | grep -Fq "Confidence: ACKNOWLEDGED"; then
  printf 'PASS: acked 404 demoted to ACKNOWLEDGED\n'
else
  printf 'FAIL: acked 404 demoted to ACKNOWLEDGED\n' >&2
  failures=$((failures + 1))
fi
assert_contains "acked finding names its ack source" "acknowledged known-inaccessible via fleet.ackUnavailable"
if grep -B2 -F "Target: github.com/lost/cause" "$output" | grep -Fq "Confidence: UNKNOWN"; then
  printf 'PASS: unacked 404 stays UNKNOWN\n'
else
  printf 'FAIL: unacked 404 stays UNKNOWN\n' >&2
  failures=$((failures + 1))
fi
if grep -B2 -F "Target: github.com/gone/net" "$output" | grep -Fq "Confidence: UNKNOWN"; then
  printf 'PASS: non-404 failure on acked identity stays UNKNOWN\n'
else
  printf 'FAIL: non-404 failure on acked identity stays UNKNOWN\n' >&2
  failures=$((failures + 1))
fi
assert_contains "summary counts acknowledged separately" "acknowledged=1"

if grep -Fq -- '--head feature/mismatch' "$CALL_LOG"; then
  printf 'FAIL: local-only branch name was sent to GitHub via --head\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: local-only branch name never sent to GitHub\n'
fi
if grep -Fq -- '--head stale/changed' "$CALL_LOG"; then
  printf 'PASS: remote-known branch still queried via exact-fallback\n'
else
  printf 'FAIL: remote-known branch was not queried via exact-fallback\n' >&2
  failures=$((failures + 1))
fi

if grep -Fxq 'Handoff: injected-control' "$output" || LC_ALL=C grep -q $'\033' "$output"; then
  printf 'FAIL: control-bearing path injected report lines or terminal controls\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: control-bearing path stayed within one encoded field\n'
fi

# Config resolution ladder: explicit --config > project-scoped > user-global > none,
# with the consumed source named in the report header.
assert_contains "explicit config named in header" "(explicit --config)"

mkdir -p "$TMP/proj/.claude" "$TMP/noconf" "$TMP/homeg/.claude" "$TMP/nohome"
cat >"$TMP/proj/.claude/repo-fleet-hygiene.conf" <<'LADDER'
[fleet]
    repo = ../../discovered-a
LADDER
cp "$TMP/proj/.claude/repo-fleet-hygiene.conf" "$TMP/homeg/.claude/repo-fleet-hygiene.conf"
ladder_out="$TMP/ladder.txt"

REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/proj" HOME="$TMP/nohome" \
  bash "$SCRIPT" >"$ladder_out"
if grep -Fq -- "repo-fleet-hygiene.conf (project)" "$ladder_out"; then
  printf 'PASS: project config auto-probed and named\n'
else
  printf 'FAIL: project config auto-probed and named\n' >&2
  failures=$((failures + 1))
fi

REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/noconf" HOME="$TMP/homeg" \
  bash "$SCRIPT" >"$ladder_out"
if grep -Fq -- "repo-fleet-hygiene.conf (user-global)" "$ladder_out"; then
  printf 'PASS: user-global config fallback consumed and named\n'
else
  printf 'FAIL: user-global config fallback consumed and named\n' >&2
  failures=$((failures + 1))
fi

REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/discovered-a" HOME="$TMP/nohome" \
  bash "$SCRIPT" >"$ladder_out"
if grep -Fq -- "Config: none" "$ladder_out"; then
  printf 'PASS: no-config run states none was consumed\n'
else
  printf 'FAIL: no-config run states none was consumed\n' >&2
  failures=$((failures + 1))
fi

# An ALL-stale config must still complete and render its stale-config-entry findings -- the
# remediation detail matters most exactly when every entry is gone.
cat >"$TMP/stale-only.conf" <<'STALEONLY'
[fleet]
    repo = ./no-such-dir-anywhere
STALEONLY
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 bash "$SCRIPT" --config "$TMP/stale-only.conf" >"$ladder_out" 2>&1 &&
  grep -Fq "Finding: stale-config-entry" "$ladder_out" &&
  grep -Fq "Repositories discovered (audit targets after deduplication): 0" "$ladder_out"; then
  printf 'PASS: all-stale config completes with stale findings instead of hard-failing\n'
else
  printf 'FAIL: all-stale config completes with stale findings instead of hard-failing\n' >&2
  failures=$((failures + 1))
fi

# The implicit current-project default (no CLI paths, no config) is CLI-equivalent: running the
# zero-configuration audit from a non-Git directory must still hard-fail, never degrade to a
# stale-config-entry with an empty source.
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/noconf" HOME="$TMP/nohome" \
  bash "$SCRIPT" >"$ladder_out" 2>&1; then
  printf 'FAIL: zero-config non-Git project dir did not hard-fail\n' >&2
  failures=$((failures + 1))
elif grep -Fq "not a Git working tree" "$ladder_out" && ! grep -Fq "stale-config-entry" "$ladder_out"; then
  printf 'PASS: zero-config non-Git project dir hard-fails without stale-config degradation\n'
else
  printf 'FAIL: zero-config non-Git project dir hard-fails without stale-config degradation (wrong output)\n' >&2
  failures=$((failures + 1))
fi

# ...and it must name the remedy. The operator never chose the implicit path, so a bare rejection
# leaves the very first invocation on a machine whose fleet lives elsewhere with no way forward.
if grep -Fq -- "--root <dir>" "$ladder_out" && grep -Fq -- "--repo <dir>" "$ladder_out" &&
  grep -Fq -- "--config <file>" "$ladder_out" && grep -Fq "repo-fleet-hygiene:setup apply" "$ladder_out"; then
  printf 'PASS: zero-config rejection names --root, --repo, --config, and the setup skill\n'
else
  printf 'FAIL: zero-config rejection does not name the scope remedies\n' >&2
  failures=$((failures + 1))
fi

# A consumed config without any fleet.root/fleet.repo (e.g. only maxDepth) still falls back to the
# implicit project-dir target, but the rejection must not claim --config was omitted -- the remedy
# is adding scope to the config that was already consumed.
cat >"$TMP/scopeless.conf" <<'SCOPELESS'
[fleet]
    maxDepth = 5
SCOPELESS
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/noconf" HOME="$TMP/nohome" \
  bash "$SCRIPT" --config "$TMP/scopeless.conf" >"$ladder_out" 2>&1; then
  printf 'FAIL: scope-less config with non-Git project dir did not hard-fail\n' >&2
  failures=$((failures + 1))
elif grep -Fq "scopeless.conf" "$ladder_out" && grep -Fq -- "--add fleet.root" "$ladder_out"; then
  if grep -Fq "No --root, --repo, or --config was given" "$ladder_out"; then
    printf 'FAIL: scope-less config rejection claims --config was omitted\n' >&2
    failures=$((failures + 1))
  else
    printf 'PASS: scope-less config rejection names the consumed config and directs scope into it\n'
  fi
else
  printf 'FAIL: scope-less config rejection does not direct scope into the consumed config\n' >&2
  failures=$((failures + 1))
fi

# The guidance belongs to the IMPLICIT default only: an explicitly supplied bad path is a typo, and
# the operator already knows how to pass a scope -- they just did.
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 bash "$SCRIPT" --repo "$TMP/noconf" >"$ladder_out" 2>&1; then
  printf 'FAIL: explicit --repo on a non-Git dir did not hard-fail\n' >&2
  failures=$((failures + 1))
elif grep -Fq "not a Git working tree" "$ladder_out" && ! grep -Fq -- "--config <file>" "$ladder_out"; then
  printf 'PASS: explicit --repo rejection stays terse (no scope guidance)\n'
else
  printf 'FAIL: explicit --repo rejection leaked the implicit-default scope guidance\n' >&2
  failures=$((failures + 1))
fi

# A CLI-supplied bad path is a typo, not config drift: the run must still hard-fail.
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 bash "$SCRIPT" --repo "$TMP/never-existed" >"$ladder_out" 2>&1; then
  printf 'FAIL: CLI-supplied missing repo did not hard-fail\n' >&2
  failures=$((failures + 1))
elif grep -Fq "repository directory not found" "$ladder_out"; then
  printf 'PASS: CLI-supplied missing repo hard-fails\n'
else
  printf 'FAIL: CLI-supplied missing repo hard-fails (wrong error)\n' >&2
  failures=$((failures + 1))
fi

# A failed authenticated-login probe must degrade the header to the plain line, never block.
REPO_FLEET_TEST_FAST_TIMEOUTS=1 MOCK_GH_USER_FAIL=1 CLAUDE_PROJECT_DIR="$TMP/discovered-a" HOME="$TMP/nohome" \
  bash "$SCRIPT" >"$ladder_out"
if grep -Fq -- "GitHub evidence: available" "$ladder_out" && ! grep -Fq -- "(account:" "$ladder_out"; then
  printf 'PASS: failed account probe degrades to plain header line\n'
else
  printf 'FAIL: failed account probe degrades to plain header line\n' >&2
  failures=$((failures + 1))
fi

# Canonical selection must not be decided by discovery order. wt-root holds a linked worktree
# (aaa-linked) that sorts before its own main worktree (zzz-canonical) under LC_ALL=C, so the glob
# reaches the linked one first and both map to the same --git-common-dir dedup key. Every emitted
# handoff carries the canonical path, so picking the worktree would aim per-repository cleanup at a
# checkout that is not the repository of record.
REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/discovered-a" HOME="$TMP/nohome" \
  bash "$SCRIPT" --root "$TMP/wt-root" >"$ladder_out" 2>&1
if grep -Fq "Canonical: $TMP/wt-root/zzz-canonical" "$ladder_out"; then
  printf 'PASS: main worktree wins canonical selection over an earlier-sorting linked sibling\n'
else
  printf 'FAIL: main worktree wins canonical selection over an earlier-sorting linked sibling\n' >&2
  failures=$((failures + 1))
fi
if grep -Fq "Canonical: $TMP/wt-root/aaa-linked" "$ladder_out"; then
  printf 'FAIL: a linked worktree was reported as the canonical checkout\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: no linked worktree reported as a canonical checkout\n'
fi
# The two directories are one repository: dedup by common dir must still collapse them to a single
# discovered target, so the fix cannot be a duplicate-target regression in disguise.
if grep -Fq "Repositories discovered (audit targets after deduplication): 1" "$ladder_out"; then
  printf 'PASS: linked worktree and main worktree collapse to one discovered repository\n'
else
  printf 'FAIL: linked worktree and main worktree collapse to one discovered repository\n' >&2
  failures=$((failures + 1))
fi
# Scope provenance is computed, not asserted: this run's scope came from a CLI --root, so the header
# must say so rather than printing the old fixed "current-project scope" literal that contradicted
# the run's own inputs two lines later.
if grep -Fq "Scope: command line (1 --root/--repo argument(s))" "$ladder_out"; then
  printf 'PASS: header attributes scope to the command line when --root supplied it\n'
else
  printf 'FAIL: header attributes scope to the command line when --root supplied it\n' >&2
  failures=$((failures + 1))
fi
assert_not_contains_file() {
  local label="$1" pattern="$2" file="$3"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'FAIL: %s (unexpected %s)\n' "$label" "$pattern" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}
assert_not_contains_file "no false current-project scope claim" "current-project scope" "$ladder_out"
# Retargeting a supplied/discovered path to the repository of record is a substitution the operator
# did not ask for, so it must be stated rather than silently applied. wt-root holds TWO linked
# worktrees of one repository: the disclosure must be ONE line naming both sources, because a line
# per retargeted path would read as two repositories against the "discovered: 1" count above.
if grep -Fq "Resolved to main worktree: $TMP/wt-root/zzz-canonical (reached via $TMP/wt-root/aaa-linked, $TMP/wt-root/bbb-linked)" "$ladder_out"; then
  printf 'PASS: retarget is disclosed once per repository, naming every source path\n'
else
  printf 'FAIL: retarget is disclosed once per repository, naming every source path\n' >&2
  failures=$((failures + 1))
fi
if [[ "$(grep -c "^Resolved to main worktree:" "$ladder_out")" -eq 1 ]]; then
  printf 'PASS: one retarget line for one discovered repository\n'
else
  printf 'FAIL: one retarget line for one discovered repository\n' >&2
  failures=$((failures + 1))
fi

# The porcelain's first record is NOT always a checkout. A submodule reports the superproject's
# .git/modules/<name>, and --separate-git-dir reports the detached git directory; both carry a .git
# FILE, so both reach the retarget. Adopting either would aim every handoff INSIDE another
# repository's administrative directory -- the harm the retarget exists to prevent, reintroduced by
# the retarget itself. Each must keep its own working tree and emit no retarget line.
admin_out="$TMP/wt-admin-out.txt"
REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/discovered-a" HOME="$TMP/nohome" \
  bash "$SCRIPT" --root "$TMP/wt-admin" >"$admin_out" 2>&1
for admin_case in "sub-wt:sub-admin:submodule" "sep-wt:sep-gitdir:separate-git-dir"; do
  admin_wt="${admin_case%%:*}"
  admin_rest="${admin_case#*:}"
  admin_dir="${admin_rest%%:*}"
  admin_label="${admin_rest#*:}"
  if grep -Fq "Repo: $TMP/wt-admin/$admin_wt" "$admin_out"; then
    printf 'PASS: %s keeps its own working tree as the audited repository\n' "$admin_label"
  else
    printf 'FAIL: %s keeps its own working tree as the audited repository\n' "$admin_label" >&2
    failures=$((failures + 1))
  fi
  # The administrative directory legitimately appears as a registered-worktree FINDING -- the
  # porcelain really does register it, and reporting registrations is the collector's job. What must
  # never happen is it becoming the audited repository or a handoff destination, because that is what
  # sends a cleanup tool inside another repository's .git.
  if grep -Eq "^(Repo|Canonical): $(printf '%s' "$TMP/wt-admin/$admin_dir" | sed 's/[][\\.*^$/]/\\&/g')$" "$admin_out" ||
    grep -Fq "in $TMP/wt-admin/$admin_dir" "$admin_out"; then
    printf 'FAIL: %s administrative directory became a canonical path or handoff target\n' "$admin_label" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s administrative directory is never a canonical path or handoff target\n' "$admin_label"
  fi
done
assert_not_contains_file "no retarget claimed for an administrative directory" \
  "Resolved to main worktree:" "$admin_out"

# --project-dir is the primary #1798 fix path: CLAUDE_PROJECT_DIR is NOT in the Bash tool's
# environment, so the argument is the only rung that works in the real invocation. Every other
# ladder assertion supplies it as an env var, which would stay green if the argument were deleted.
projarg_out="$TMP/projarg.txt"
REPO_FLEET_TEST_FAST_TIMEOUTS=1 HOME="$TMP/nohome" \
  env -u CLAUDE_PROJECT_DIR bash "$SCRIPT" --project-dir "$TMP/proj" >"$projarg_out" 2>&1
if grep -Fq -- "repo-fleet-hygiene.conf (project)" "$projarg_out"; then
  printf 'PASS: --project-dir argument reaches the project config rung with no env var set\n'
else
  printf 'FAIL: --project-dir argument reaches the project config rung with no env var set\n' >&2
  failures=$((failures + 1))
fi
# The argument is what the skill body substitutes, so it must win over a stale inherited env value.
REPO_FLEET_TEST_FAST_TIMEOUTS=1 CLAUDE_PROJECT_DIR="$TMP/noconf" HOME="$TMP/nohome" \
  bash "$SCRIPT" --project-dir "$TMP/proj" >"$projarg_out" 2>&1
if grep -Fq -- "repo-fleet-hygiene.conf (project)" "$projarg_out"; then
  printf 'PASS: --project-dir argument overrides an inherited CLAUDE_PROJECT_DIR\n'
else
  printf 'FAIL: --project-dir argument overrides an inherited CLAUDE_PROJECT_DIR\n' >&2
  failures=$((failures + 1))
fi

# An empty CLI scope value is skipped by the discovery loops, so accepting it would let the header's
# computed scope count claim an argument that contributed nothing. It must stop the run instead.
# Its own output file: the surrounding assertions all read $ladder_out from the wt-root run above,
# and reusing it here would silently invalidate whichever of them follows.
scope_out="$TMP/scope-arg.txt"
if REPO_FLEET_TEST_FAST_TIMEOUTS=1 bash "$SCRIPT" --root "" --root "$TMP/wt-root" >"$scope_out" 2>&1; then
  printf 'FAIL: an empty --root value did not hard-fail\n' >&2
  failures=$((failures + 1))
elif grep -Fq -- "--root requires a directory" "$scope_out"; then
  printf 'PASS: an empty --root value hard-fails instead of inflating the scope count\n'
else
  printf 'FAIL: an empty --root value hard-fails (wrong error)\n' >&2
  failures=$((failures + 1))
fi
# A full merged-PR window silently drops older history, which reads in the report exactly like a
# branch that was never merged. The truncation must be disclosed, never inferred by the reader.
if grep -Fq "Finding: merged-pr-window-truncated" "$ladder_out" &&
  grep -Fq "equal to its 1000-PR window" "$ladder_out"; then
  printf 'PASS: a full merged-PR window is disclosed as truncated\n'
else
  printf 'FAIL: a full merged-PR window is disclosed as truncated\n' >&2
  failures=$((failures + 1))
fi

# gh unavailable/unauthenticated: the skill promises the audit continues with GitHub evidence marked
# UNKNOWN rather than aborting or inferring a negative. Never exercised before, though it is the
# degradation a machine without gh hits on its very first run.
REPO_FLEET_TEST_FAST_TIMEOUTS=1 MOCK_GH_AUTH_FAIL=1 CLAUDE_PROJECT_DIR="$TMP/discovered-a" HOME="$TMP/nohome" \
  bash "$SCRIPT" --root "$TMP/wt-root" >"$ladder_out" 2>&1
if grep -Fq "GitHub evidence: unavailable" "$ladder_out" &&
  grep -Fq "Canonical: $TMP/wt-root/zzz-canonical" "$ladder_out"; then
  printf 'PASS: unauthenticated gh degrades to UNKNOWN GitHub evidence and still audits locally\n'
else
  printf 'FAIL: unauthenticated gh degrades to UNKNOWN GitHub evidence and still audits locally\n' >&2
  failures=$((failures + 1))
fi
assert_not_contains_file "no merged claim without GitHub evidence" "Finding: merged-local-branch" "$ladder_out"

# The tier table is the contract a consumer tiers decisions on, and it silently fell to covering
# half the emitted kinds. Assert set equality in BOTH directions instead: a new emit_finding kind
# with no documented disposition fails here, and so does a table row for a kind the collector no
# longer emits. Both sides are extracted mechanically -- comparing two hand-maintained lists would
# reproduce the drift this replaces.
MODEL_DOC="$SCRIPT_DIR/../reference/confidence-model.md"
emitted_kinds="$TMP/emitted-kinds.txt"
documented_kinds="$TMP/documented-kinds.txt"
# Skip comment lines: prose in this script names finding kinds while explaining them, and counting
# those would let a kind be "documented" by a comment that emits nothing.
grep -vE "^[[:space:]]*#" "$SCRIPT" | grep -oE "emit_finding [A-Z]+ [a-z-]+" | awk '{print $3}' | sort -u >"$emitted_kinds"
# Table rows only: a kind is the first backticked cell of a row, so prose mentions elsewhere in the
# document cannot satisfy the contract. The delimiter is built with printf rather than written
# literally, so no quoting style has to carry a bare backtick through grep and sed.
bt="$(printf '\140')"
grep -E "^\| ${bt}[a-z-]+${bt} \|" "$MODEL_DOC" | sed -e "s/^| ${bt}//" -e "s/${bt} |.*//" | sort -u >"$documented_kinds"
emitted_count="$(grep -c . "$emitted_kinds" || true)"
documented_count="$(grep -c . "$documented_kinds" || true)"
# Guard against an extraction that silently matches nothing and compares two empty sets.
if [[ "$emitted_count" -lt 20 || "$documented_count" -lt 20 ]]; then
  printf 'FAIL: finding-kind extraction returned too few kinds (emitted=%s documented=%s); the extraction, not the docs, is broken\n' \
    "$emitted_count" "$documented_count" >&2
  failures=$((failures + 1))
elif kind_diff="$(diff "$emitted_kinds" "$documented_kinds")"; then
  printf 'PASS: tier table documents exactly the finding kinds the collector emits (%s)\n' "$emitted_count"
else
  printf 'FAIL: tier table and collector finding kinds have drifted (< emitted only, > documented only)\n%s\n' \
    "$kind_diff" >&2
  failures=$((failures + 1))
fi

# Exercise the collector's own fail-closed command gate, rather than relying on a denylist that can
# miss a new mutation spelling. None of these forbidden vectors may reach the fake executables.
calls_before="$(wc -l <"$CALL_LOG")"
# shellcheck source=audit-fleet.sh
source "$SCRIPT"
forbidden_rejected=true
run_git_probe fetch origin >/dev/null 2>&1 && forbidden_rejected=false
run_git_probe -c alias.remote='!touch /tmp/pwned' remote >/dev/null 2>&1 && forbidden_rejected=false
run_git_probe -C "$TMP/repo-b" branch -D main >/dev/null 2>&1 && forbidden_rejected=false
run_git_probe -C "$TMP/repo-b" remote set-url origin https://example.invalid >/dev/null 2>&1 &&
  forbidden_rejected=false
run_git_probe config --file "$TMP/config/repo-fleet-hygiene.conf" --get-regexp -z '.*' >/dev/null 2>&1 &&
  forbidden_rejected=false
run_bounded_gh api repos/acme/repo-b --hostname github.com --method POST --template x >/dev/null 2>&1 &&
  forbidden_rejected=false
run_bounded_gh pr merge --repo github.com/acme/repo-b >/dev/null 2>&1 && forbidden_rejected=false
run_bounded_gh alias set pr '!touch /tmp/pwned' >/dev/null 2>&1 && forbidden_rejected=false
calls_after="$(wc -l <"$CALL_LOG")"
allowed_status=true
run_git_probe -C "$TMP/wt-a" status --porcelain --ignored --untracked-files=normal >/dev/null 2>&1 || allowed_status=false
allowed_stash=true
run_git_probe -C "$TMP/canonical-a" stash list >/dev/null 2>&1 || allowed_stash=false
allowed_log=true
run_git_probe -C "$TMP/wt-a" log -1 --format=%ct HEAD >/dev/null 2>&1 || allowed_log=false
if [[ "$forbidden_rejected" != "true" || "$calls_before" != "$calls_after" ]]; then
  printf 'FAIL: exact command allowlist admitted a forbidden Git/gh vector\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: exact command allowlist rejected Git/gh mutation and config-injection vectors\n'
fi
if [[ "$allowed_status" != "true" || "$allowed_log" != "true" || "$allowed_stash" != "true" ]]; then
  printf 'FAIL: status/log/stash probes were not admitted by the Git allowlist\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: status --ignored --untracked-files=normal, stash list, and log probes are admitted by the Git allowlist\n'
fi
# Plain status --porcelain (without --ignored) must no longer be admitted — reclaimability depends
# on the ignored-aware probe (#2601).
plain_status_rejected=true
run_git_probe -C "$TMP/wt-a" status --porcelain >/dev/null 2>&1 && plain_status_rejected=false
if [[ "$plain_status_rejected" != "true" ]]; then
  printf 'FAIL: plain status --porcelain was admitted after the --ignored require\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: plain status --porcelain is rejected; --ignored is required\n'
fi
ignored_only_rejected=true
run_git_probe -C "$TMP/wt-a" status --porcelain --ignored >/dev/null 2>&1 && ignored_only_rejected=false
if [[ "$ignored_only_rejected" != "true" ]]; then
  printf 'FAIL: status --ignored without --untracked-files=normal was admitted\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: status --ignored requires --untracked-files=normal\n'
fi
# Stash must not be callable from a linked worktree path in this suite's mock (collector uses the
# canonical once). The allowlist itself still admits stash list under -C; the once-per-repo
# contract is the collector's, asserted via a single Stashes field above.
stash_per_wt_calls_before="$(grep -c ' stash list$' "$CALL_LOG" || true)"
run_git_probe -C "$TMP/canonical-a" stash list >/dev/null 2>&1 || true
stash_per_wt_calls_after="$(grep -c ' stash list$' "$CALL_LOG" || true)"
if [[ "$stash_per_wt_calls_after" -le "$stash_per_wt_calls_before" ]]; then
  printf 'FAIL: allowlisted stash list did not reach the mock from the canonical path\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: stash list reaches the mock from the canonical path\n'
fi

# Force the portable watchdog and prove a TERM-ignoring gh cannot outlive the finite KILL grace.
HANG_BIN="$TMP/hang-bin"
mkdir -p "$HANG_BIN"
cat >"$HANG_BIN/gh" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
while :; do sleep 1; done
EOF
chmod +x "$HANG_BIN/gh"
SECONDS=0
if REPO_FLEET_FORCE_BASH_TIMEOUT=1 REPO_FLEET_TEST_FAST_TIMEOUTS=1 \
  PATH="$HANG_BIN:$PATH" SCRIPT="$SCRIPT" bash -c \
  'source "$SCRIPT"; run_bounded_gh auth status --hostname github.com' >/dev/null 2>&1; then
  printf 'FAIL: TERM-ignoring gh unexpectedly succeeded\n' >&2
  failures=$((failures + 1))
elif [[ "$SECONDS" -gt 4 ]]; then
  printf 'FAIL: portable watchdog exceeded its finite TERM-to-KILL bound (%ss)\n' "$SECONDS" >&2
  failures=$((failures + 1))
else
  printf 'PASS: portable watchdog killed a TERM-ignoring gh within the finite bound\n'
fi

if [[ "$failures" -ne 0 ]]; then
  printf '\nCollector output:\n' >&2
  cat "$output" >&2
  exit 1
fi

printf 'All repo-fleet-hygiene collector tests passed.\n'
