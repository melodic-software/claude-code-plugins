#!/usr/bin/env bash
# Exit codes:
#   0  success — worktree created, or an existing one this session may claim
#      reused (see "Reuse" below); path on stdout. A failed, skipped or timed-out
#      dependency install still exits 0 and names the failure on stderr
#   2  usage error — unknown/missing flag, or a --name git rejects as a branch
#   3  refuse — no usable external root, root inside a repository, or a
#      cross-drive root on Windows at any resolution rung including the
#      unconfigured plugin-data-dir default (guidance on stderr); nothing created
#   4  environment error: not a git repo, the target path or the branch is held
#      by another worktree or session, `git worktree add` failed, or the tree
#      was created and then left incomplete because a `.worktreeinclude` file
#      failed to copy. That last case shares exit 5's shape, a tree on disk that
#      is not what the caller asked for, so a caller treating 4 as "nothing was
#      created" is wrong for it
#   5  worktree created, but `git worktree lock` failed: the path is still the
#      sole stdout line and the tree exists, yet it carries no claim for a
#      cleanup sweep to read (a warning names it on stderr)

set -uo pipefail

HELPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || { echo "error: cannot resolve the helper's directory" >&2; exit 4; }

# shellcheck source=lib/worktree-facts.sh
source "$HELPER_DIR/lib/worktree-facts.sh" || { echo "error: cannot load lib/worktree-facts.sh" >&2; exit 4; }

PROG=${0##*/}

# shellcheck source=worktree-root-resolve.sh
source "$HELPER_DIR/worktree-root-resolve.sh" || { echo "error: cannot load worktree-root-resolve.sh" >&2; exit 4; }
# shellcheck source=../hooks/worktree-path-lib.sh
source "$HELPER_DIR/../hooks/worktree-path-lib.sh" || { echo "error: cannot load hooks/worktree-path-lib.sh" >&2; exit 4; }

windows_drive_letter() {
  local path="$1"
  if [[ "$path" =~ ^([A-Za-z]):(/|$) ]] || [[ "$path" =~ ^/cygdrive/([A-Za-z])(/|$) ]]; then
    printf '%s' "${BASH_REMATCH[1]^^}"
    return 0
  fi
  case "$(uname -s 2>/dev/null || true)" in
  MINGW* | MSYS* | CYGWIN*)
    if [[ "$path" =~ ^/([A-Za-z])(/|$) ]]; then
      printf '%s' "${BASH_REMATCH[1]^^}"
      return 0
    fi
    ;;
  *) ;;
  esac
  return 1
}

check_same_drive() {
  local repo_path="$1" wt_path="$2" repo_drive wt_drive
  repo_drive=$(windows_drive_letter "$repo_path") || return 0
  wt_drive=$(windows_drive_letter "$wt_path") || return 0
  [[ "$repo_drive" == "$wt_drive" ]] && return 0

  cat >&2 <<EOF
$PROG: set \`worktreeroot.path\` (or the plugin's \`worktree_root\` option) to a directory on drive ${repo_drive}: — refusing a cross-drive root.

  repository: $repo_path  (drive ${repo_drive}:)
  worktree:   $wt_path  (drive ${wt_drive}:)

git worktree move uses rename(), which cannot cross volumes on Windows
(EXDEV / Improper link). The includeIf-capable \`worktreeroot.path\` key
is the per-repository remedy:

  git config worktreeroot.path <same-drive-root>
EOF
  return 3
}

run_capped() {
  local cap="$1" pid ticks=0
  shift
  set -m
  "$@" &
  pid=$!
  set +m
  while kill -0 "$pid" 2>/dev/null; do
    if ((ticks >= cap * 10)); then
      kill -- -"$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

usage() {
  cat >&2 <<EOF
$PROG — shared worktree-creation helper.

Usage:
  $PROG --name <name> [--root <dir> | --root-file <path>]
        [--fallback-root <dir> | --fallback-root-file <path>]
        [--data-root-file <path>] [--base-ref fresh|head] [--repo-dir <dir>]
        [--session-id <id>] [--remove-input-files]

Root resolution, most specific first:
  --root/--root-file (explicit, per invocation), then worktreeroot.path
  read from the target repository (includes on, --type=path, last value
  wins — includeIf supplies per-identity/per-repo answers), then
  --fallback-root/--fallback-root-file (the machine-global plugin option), then
  --data-root-file (<data-dir>/worktrees). Absent all: refuse (exit 3).

Options:
  --name <name>       Branch/worktree name (e.g. feat/my-feature). Required.
                      Max 64 chars; each /-separated segment holds only letters,
                      digits, dots, underscores, and dashes. Also checked against
                      git's own branch-name grammar, so a name that satisfies the
                      character rules but is an illegal ref (feat/foo..bar,
                      foo.lock, HEAD) is refused (exit 2), not left to git later.
                      That grammar check runs after the repository is resolved,
                      so exits 3 and 4 can precede it. The branch is the name
                      unless the repository's tracked
                      docs/conventions/source-control.yaml sets
                      worktree_branch_naming: conventional-commits, which
                      derives <type>/<description> from it (the stderr note
                      names the branch); the grammar check then applies to the
                      derived branch. The directory slug always comes from the
                      name.
  --root <dir>        External worktree root, passed directly as a process
                      argument (e.g. from a hook or CLI caller — no shell
                      re-quoting of the value happens on that path). Wins over
                      every configured source: an explicit per-invocation choice
                      outranks per-repo config. An empty value or an unexpanded
                      \${user_config.*} token falls through to the config key /
                      fallback / data-root rungs — never to the in-repo
                      .claude/worktrees/ default, whose nested placement the
                      nesting invariant forbids (skills/worktree/reference/nesting-invariant.md).
                      Mutually exclusive with --root-file.
  --fallback-root <dir>
                      The machine-global worktree_root plugin option, consulted
                      only when neither an explicit --root/--root-file nor
                      worktreeroot.path yields
                      a value. Ranks
                      below the key deliberately: the key is per-repo/per-identity
                      capable and readable by every consumer, while the plugin
                      option is machine-wide and plugin-only (#2612). Same
                      unset/empty/unexpanded-token handling as --root. Mutually
                      exclusive with --fallback-root-file.
  --fallback-root-file <path>
                      Read the fallback root from <path> — the same byte-verbatim
                      file channel as --root-file, for a caller that cannot place
                      the raw-substituted \${user_config.worktree_root} value in
                      shell source safely. Mutually exclusive with --fallback-root.
  --data-root-file <path>
                      Read the plugin's data directory from <path>, used as the
                      root only when no --root/--root-file value is configured
                      (the resolved root is then <data-dir>/worktrees). Same
                      byte-verbatim file channel as --root-file, and combinable
                      with it: a configured root always wins. The caller obtains
                      the value by substituting \${CLAUDE_PLUGIN_DATA} into its
                      own SKILL.md body — never from the environment, which is
                      not per-plugin in a Bash-tool subprocess. A file still
                      holding the literal token is treated as absent.
  --root-file <path>  Read the external worktree root from <path> instead of a
                      --root argument. For a caller that cannot place the value
                      in shell source safely — e.g. a skill rendering
                      \${user_config.worktree_root} into markdown, which is raw
                      text substitution, not shell-escaped — write the value to
                      a temp file through a non-shell channel (the Write tool's
                      JSON content parameter), never a quoted literal or a
                      heredoc body: a value containing the heredoc delimiter
                      line ends the heredoc early and the remainder is parsed
                      as commands. The file's bytes are the root, verbatim and
                      unterminated — a newline anywhere in it, trailing
                      included, is a usage error (exit 2), never trimmed, and so
                      is a NUL byte. The same unset/empty/unexpanded-token
                      refuse (exit 3) applies to the file's content. Mutually
                      exclusive with --root: supplying both is a usage error
                      even when one of the two values is empty.
  --base-ref <ref>    fresh (default) branches from the default remote's default
                      branch; head branches from the repo's current HEAD. Omitted
                      defaults to fresh; the caller passes the effective Claude
                      worktree.baseRef setting (a settings.json key, not git config).
                      fresh picks the remote generically — the current branch's
                      configured remote, else origin, else the sole remote — so a
                      clone made with 'git clone -o upstream' resolves upstream's
                      default branch. fresh first fetches that branch on every
                      run (capped at 5s, prompts off); a failed or timed-out
                      fetch warns, keeps the cached ref, and reports the base
                      as <remote>/<branch>@<sha>, not refreshed. With no
                      resolvable remote, or an uncached <remote>/HEAD, it
                      warns and branches from local HEAD.
  --repo-dir <dir>    Source repository directory. Default: current directory.
  --session-id <id>   Session id recorded in the git worktree lock reason as
                      \`session <id> since\`, the token worktree-claim.sh
                      check-enter matches (exit 0 for this id, exit 4 for any
                      other). The id must match ^[A-Za-z0-9._:-]{1,128}$; any
                      other value is a usage error (exit 2) and creates nothing.
                      Omitted or empty: the reason names the helper, host, and
                      start time only and carries no session token, so
                      check-enter reports a foreign claim for every session id.
                      This flag is the only session source. An omitted id is
                      never filled in from the host name or the environment, and
                      is not reported as any session's claim.
  --remove-input-files
                      On exit, whatever the exit code, delete the files handed
                      to --root-file, --fallback-root-file and --data-root-file,
                      then rmdir each one's directory (left in place when it is
                      not empty). Armed when the flag is parsed: a usage error
                      before it, or a missing library, leaves the files. For a
                      caller that wrote those files into a temp directory and
                      would otherwise need its own rm.
  -h, --help          Show this help.

Dependencies: the helper runs the provisioning step, provision-prerequisites.sh,
which installs the lockfiles the tree's ecosystem records declare with an
install object on a requires entry, by npm ci --ignore-scripts --no-audit
--no-fund in each lockfile's directory. When no record declares any lockfile,
it installs the root npm-shrinkwrap.json or package-lock.json the same way and
prints a notice to declare it; that fallback ends at the ecosystem-commands
contract's next major version. It installs once per distinct install
into <root>/.npm-seed/<key>, makes the seed's files read-only, and hard-links
that node_modules into the worktree (cp -al), so worktrees on one install share
one copy on disk. It installs in place instead without flock, node or a working
cp -al, when package.json declares workspaces, an install lifecycle script or a
file:/link: dependency, or when the seed install fails.
Seeds unused for WORKTREE_CREATE_NPM_SEED_DAYS (default 14) are removed; with
WORKTREE_CREATE_NPM_SEED=0 no seed is used. Waiting for the seed lock and
installing share one cap, WORKTREE_CREATE_DEPS_CAP_SECONDS (default 45); npm
output goes to stderr. A missing npm, a failed install or the cap only warns on
stderr; the exit code is unchanged.

Git LFS: when a .gitattributes file in the commit being checked out routes
paths through filter=lfs, the checkout runs with GIT_LFS_SKIP_SMUDGE=1, so
those paths arrive as LFS pointer files and nothing is copied out of the LFS
store. One stderr line names git lfs pull, and git lfs pull --include <paths>
for part of the content.

Reuse: a worktree already at the target path, on the branch this run would use,
is printed as it is (no copy, no provisioning) when its lock names --session-id, when
it is unlocked (claimed first), or when worktree-claim.sh stale proves its
session's claim stale (handed over). Anything else there, a live or
session-less claim, or no --session-id, exits 4. An existing branch checked out
nowhere is checked out without -b and --base-ref does not apply; one checked out
in another worktree exits 4, naming it.

On success the worktree path is printed as the sole stdout line, for the
caller to feed to EnterWorktree(path:).

Exit codes: 0 success · 2 usage · 3 refuse (no usable root) · 4 environment ·
5 created but not locked.
EOF
}

name=""
root=""
root_given=0
root_file=""
root_file_given=0
fallback_root=""
fallback_root_given=0
fallback_root_file=""
fallback_root_file_given=0
data_root_file=""
data_root_file_given=0
base_ref=""
existing_branch=0
repo_dir="."
session_id=""

remove_input_files_on_exit() {
  local file
  for file in "$root_file" "$fallback_root_file" "$data_root_file"; do
    [[ -n "$file" ]] || continue
    rm -f -- "$file"
    rmdir -- "$(dirname -- "$file")" 2>/dev/null || true
  done
}

need_value() {
  if [[ $# -lt 2 ]]; then
    printf '%s: %s requires a value\n' "$PROG" "$1" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --name)
    need_value "$@"
    name="$2"
    shift 2
    ;;
  --root)
    need_value "$@"
    root="$2"
    root_given=1
    shift 2
    ;;
  --root-file)
    need_value "$@"
    root_file="$2"
    root_file_given=1
    shift 2
    ;;
  --fallback-root)
    need_value "$@"
    fallback_root="$2"
    fallback_root_given=1
    shift 2
    ;;
  --fallback-root-file)
    need_value "$@"
    fallback_root_file="$2"
    fallback_root_file_given=1
    shift 2
    ;;
  --data-root-file)
    need_value "$@"
    data_root_file="$2"
    data_root_file_given=1
    shift 2
    ;;
  --base-ref)
    need_value "$@"
    base_ref="$2"
    shift 2
    ;;
  --existing-branch)
    existing_branch=1
    shift
    ;;
  --repo-dir)
    need_value "$@"
    repo_dir="$2"
    shift 2
    ;;
  --session-id)
    need_value "$@"
    session_id="$2"
    shift 2
    ;;
  --remove-input-files)
    trap remove_input_files_on_exit EXIT
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
    usage
    exit 2
    ;;
  esac
done

if [[ -z "$name" ]]; then
  printf '%s: --name is required\n' "$PROG" >&2
  exit 2
fi

if ((root_given && root_file_given)); then
  printf '%s: --root and --root-file are mutually exclusive\n' "$PROG" >&2
  exit 2
fi
if ((fallback_root_given && fallback_root_file_given)); then
  printf '%s: --fallback-root and --fallback-root-file are mutually exclusive\n' "$PROG" >&2
  exit 2
fi

read_path_file() {
  local flag="$1" file="$2" value
  PATH_FILE_VALUE=""
  if [[ ! -f "$file" ]]; then
    printf '%s: %s not found: %s\n' "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  if (($(wc -c <"$file") != $(tr -d '\000' <"$file" | wc -c))); then
    printf '%s: %s %s contains a NUL byte; the file holds the path verbatim and no pathname can contain NUL\n' \
      "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  value=$(
    cat "$file"
    printf x
  ) # printf x defends the value's own trailing bytes from $( ) stripping
  value=${value%x}
  if [[ "$value" == *$'\n'* ]]; then
    printf '%s: %s %s contains a newline byte; the file holds the path verbatim and a path with a newline in it is malformed configuration, not a value to trim\n' \
      "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  PATH_FILE_VALUE="$value"
}

if ((root_file_given)); then
  read_path_file --root-file "$root_file"
  root="$PATH_FILE_VALUE"
fi
if ((fallback_root_file_given)); then
  read_path_file --fallback-root-file "$fallback_root_file"
  fallback_root="$PATH_FILE_VALUE"
fi

if ((${#name} > 64)); then
  printf '%s: --name %q exceeds 64 characters\n' "$PROG" "$name" >&2
  exit 2
fi
if [[ ! "$name" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
  printf '%s: --name %q is not a valid worktree/branch name (each /-separated segment: letters, digits, dots, underscores, dashes only)\n' "$PROG" "$name" >&2
  exit 2
fi

if [[ -n "$session_id" ]] && [[ ! "$session_id" =~ ^[A-Za-z0-9._:-]{1,128}$ ]]; then
  printf '%s: --session-id must match ^[A-Za-z0-9._:-]{1,128}$\n' "$PROG" >&2
  exit 2
fi

# The ${user_config token is matched literally: the unexpanded placeholder is what is detected.
# shellcheck disable=SC2016
root_is_unset() {
  [[ -z "$1" || "$1" == *'${user_config'* ]]
}

canonicalize_root() {
  local value="$1" source="$2"
  if [[ "$value" == *\\* && ("$OSTYPE" == msys || "$OSTYPE" == cygwin) ]]; then
    local bslash="\\" fwd="/"
    value="${value//"$bslash"/"$fwd"}"
  fi
  if [[ "$value" =~ ^[A-Za-z]:[^/] ]]; then
    printf '%s: %s %q is drive-relative; use an absolute path (e.g. C:/worktrees)\n' \
      "$PROG" "$source" "$value" >&2
    exit 2
  fi
  CANONICAL_ROOT="$value"
}

root_unset=0
if root_is_unset "$root"; then
  root_unset=1
else
  canonicalize_root "$root" --root
  root="$CANONICAL_ROOT"
fi

if ! toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
  printf '%s: run this from inside a git repository, or pass --repo-dir pointing at one; for a Claude Code background session at a non-repository directory, set worktree.bgIsolation to "none" in settings so it edits in place; --worktree and subagent isolation need a repository\n' "$PROG" >&2
  printf '%s:   --repo-dir is not inside a git repository: %s\n' "$PROG" "$repo_dir" >&2
  exit 4
fi

# No scope flag: git-config(1) turns includes off when a specific file is given:
# https://git-scm.com/docs/git-config
if ((root_unset)); then
  worktree_root_resolve "$toplevel" || true
  if [[ -n "${WORKTREE_ROOT_VALUE:-}" ]]; then
    canonicalize_root "$WORKTREE_ROOT_VALUE" "$WORKTREE_ROOT_KEY_USED"
    root="$CANONICAL_ROOT"
    root_unset=0
    printf '%s: worktree root resolved from the %s git config key\n' \
      "$PROG" "$WORKTREE_ROOT_KEY_USED" >&2
  fi
fi

if ((root_unset)) && ! root_is_unset "$fallback_root"; then
  canonicalize_root "$fallback_root" --fallback-root
  root="$CANONICAL_ROOT"
  root_unset=0
fi

if ((root_unset)); then
  data_root=""
  if ((data_root_file_given)); then
    read_path_file --data-root-file "$data_root_file"
    data_root="$PATH_FILE_VALUE"
    # A caller whose substitution did not fire hands over this literal token, matched as text.
    # shellcheck disable=SC2016
    [[ "$data_root" == *'${CLAUDE_PLUGIN_DATA'* ]] && data_root=""
  fi

  if [[ -z "$data_root" ]]; then
    cat >&2 <<EOF
$PROG: no worktree root available — refusing to create a worktree.

Set the \`worktreeroot.path\` git config key to an external root (a path
OUTSIDE every repository), then retry:

  git config --global worktreeroot.path <root>

Any tool that can run \`git config --get\` can honor that key; the
source-control plugin's \`worktree_root\` option (via \`/plugin\`) also works but
only this plugin can read it. Convention and per-identity layering:
reference/worktree-root-convention.md.

Not falling back to the in-repo .claude/worktrees/ default: a worktree nested
inside a checkout can pick up that checkout's path-scoped rules as well as its
own. Measurement, disputed arms and expiry:
skills/worktree/reference/nesting-invariant.md "The nesting invariant, dated measurement".
EOF
    exit 3
  fi

  root="${data_root%/}/worktrees"
  printf '%s: worktree_root is not configured; defaulting to %s\n' "$PROG" "$root" >&2
  # The backticks are literal markdown in guidance text, not a command substitution.
  # shellcheck disable=SC2016
  printf '%s: set the plugin'\''s `worktree_root` directory key to place worktrees elsewhere.\n' "$PROG" >&2
fi

CONVENTION_YAML_REL="docs/conventions/source-control.yaml"
branch_naming="verbatim"
branch_default_type="chore"
branch_extra_prefixes=()

branch_type_is_valid() { [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; }

read_branch_naming() {
  local records key value naming="" default_type=""
  [[ -f "$toplevel/$CONVENTION_YAML_REL" ]] || return 0
  # shellcheck source=../lib/convention-key.sh
  source "$HELPER_DIR/../lib/convention-key.sh" || {
    printf '%s: cannot load lib/convention-key.sh; keeping the branch name verbatim\n' "$PROG" >&2
    return 0
  }
  convention_key_tracked "$toplevel" "$CONVENTION_YAML_REL" || return 0
  if ! records="$(convention_key_records "$toplevel")"; then
    printf '%s: the YAML parser rejected %s; keeping the branch name verbatim\n' "$PROG" "$CONVENTION_YAML_REL" >&2
    return 0
  fi
  while IFS=$'\t' read -r key value; do
    case "$key" in
    worktree_branch_naming) naming="$value" ;;
    worktree_branch_default_type) default_type="$value" ;;
    worktree_branch_extra_prefixes.[0-9]*)
      if branch_type_is_valid "$value"; then
        branch_extra_prefixes+=("$value")
      else
        printf '%s: worktree_branch_extra_prefixes entry %q is not one lowercase segment; skipping it\n' "$PROG" "$value" >&2
      fi
      ;;
    *) ;;
    esac
  done <<<"$records"
  case "$naming" in
  "" | verbatim) ;;
  conventional-commits) branch_naming="$naming" ;;
  *) printf '%s: worktree_branch_naming %q in %s is not verbatim or conventional-commits; keeping the branch name verbatim\n' \
    "$PROG" "$naming" "$CONVENTION_YAML_REL" >&2 ;;
  esac
  if [[ -n "$default_type" ]]; then
    if branch_type_is_valid "$default_type"; then
      branch_default_type="$default_type"
    else
      printf '%s: worktree_branch_default_type %q in %s is not one lowercase segment; using chore\n' \
        "$PROG" "$default_type" "$CONVENTION_YAML_REL" >&2
    fi
  fi
}

branch_ref_segment() {
  local s="${1//[^A-Za-z0-9._-]/-}"
  while [[ "$s" == *..* ]]; do s="${s//../.}"; done
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  while [[ "$s" == [-._]* ]]; do s="${s#?}"; done
  while [[ "$s" == *[-._] ]]; do s="${s%?}"; done
  BRANCH_SEGMENT="${s%.lock}"
}

derive_conventional_branch() {
  local name="$1" type canonical="" prefix
  if [[ "$name" == */* ]]; then
    type="${name%%/*}"
    type="${type,,}"
    case "$type" in
    feat | feature) canonical="feat" ;;
    fix | bugfix | hotfix) canonical="fix" ;;
    docs | documentation | doc) canonical="docs" ;;
    test | tests) canonical="test" ;;
    perf | performance) canonical="perf" ;;
    build | chore | ci | refactor | revert | style) canonical="$type" ;;
    *)
      for prefix in ${branch_extra_prefixes[@]+"${branch_extra_prefixes[@]}"}; do
        if [[ "$type" == "$prefix" ]]; then
          canonical="$prefix"
          break
        fi
      done
      ;;
    esac
    if [[ -n "$canonical" ]]; then
      branch_ref_segment "${name#*/}"
      if [[ -n "$BRANCH_SEGMENT" ]]; then
        branch="$canonical/$BRANCH_SEGMENT"
        return 0
      fi
      printf '%s: name %q has type %s but no description; using %s/ (pass %s/<description> to keep the type)\n' \
        "$PROG" "$name" "$canonical" "$branch_default_type" "$canonical" >&2
    fi
  fi
  branch_ref_segment "$name"
  if [[ -z "$BRANCH_SEGMENT" ]]; then
    printf '%s: name %q sanitizes to an empty description; keeping the branch name verbatim\n' "$PROG" "$name" >&2
    branch="$name"
    return 0
  fi
  branch="$branch_default_type/$BRANCH_SEGMENT"
}

branch="$name"
if ((!existing_branch)); then
  read_branch_naming
  if [[ "$branch_naming" == conventional-commits ]]; then
    derive_conventional_branch "$name"
    printf '%s: branch %s derived from name %s (worktree_branch_naming: conventional-commits)\n' \
      "$PROG" "$branch" "$name" >&2
  fi
fi

if ! git -C "$toplevel" check-ref-format --branch "$branch" >/dev/null 2>&1; then
  if [[ "$branch" == "$name" ]]; then
    printf '%s: --name %q is not a valid git branch name (see: git help check-ref-format)\n' "$PROG" "$name" >&2
  else
    printf '%s: branch %q derived from --name %q is not a valid git branch name (see: git help check-ref-format)\n' \
      "$PROG" "$branch" "$name" >&2
  fi
  exit 2
fi

parse_owner_repo() {
  local url="$1" path
  owner=""
  repo=""
  path="$url"
  if [[ "$path" == *"://"* ]]; then
    path="${path#*://}" # strip scheme://
    path="${path#*/}"   # strip host[:port] up to the first '/'
  elif [[ "$path" == *:* ]]; then
    path="${path#*:}" # scp-like git@host:owner/repo -> owner/repo
  fi
  path="${path%.git}"
  path="${path%/}"

  local -a seg=() parts
  IFS='/' read -r -a parts <<<"$path"
  local p
  for p in "${parts[@]}"; do
    [[ -z "$p" || "$p" == "_git" || "$p" == "v3" ]] && continue
    seg+=("$p")
  done

  local n=${#seg[@]}
  if ((n >= 2)); then
    repo="${seg[n - 1]}"
    owner="${seg[n - 2]}"
  elif ((n == 1)); then
    repo="${seg[0]}"
  fi
}

owner=""
repo=""
if origin_url=$(git -C "$toplevel" remote get-url origin 2>/dev/null); then
  parse_owner_repo "$origin_url"
fi
[[ -n "$repo" ]] || repo="${toplevel##*/}"

slug="$name"
slug="${slug//[^A-Za-z0-9._-]/-}"
while [[ "$slug" == *--* ]]; do slug="${slug//--/-}"; done
slug="${slug#-}"
slug="${slug%-}"
if [[ -z "$slug" ]]; then
  printf '%s: --name %q sanitizes to an empty slug\n' "$PROG" "$name" >&2
  exit 2
fi

if [[ -n "$owner" ]]; then
  dirname="${owner}-${repo}-${slug}"
else
  dirname="${repo}-${slug}"
fi
worktree_path="${root%/}/${dirname}"

[[ "$worktree_path" != /* && ! "$worktree_path" =~ ^[A-Za-z]:/ ]] && worktree_path="$toplevel/$worktree_path"

worktree_path=$(worktree_path_normalize "$worktree_path")

probe="${worktree_path%/*}"
while [[ ! -e "$probe" ]]; do
  parent="${probe%/*}"
  [[ "$parent" == "$probe" ]] && break
  probe="$parent"
done
if [[ -e "$probe" ]]; then
  location=""
  detail=""
  if target_top=$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null) && [[ -n "$target_top" ]]; then
    if [[ "$target_top" == "$toplevel" ]]; then
      location="inside the repository"
    else
      location="inside another git working tree"
    fi
    detail="  checkout: $target_top"
  elif [[ "$(git -C "$probe" rev-parse --is-inside-git-dir 2>/dev/null)" == "true" ]]; then
    location="inside a git directory"
    detail="  git dir:  $(git -C "$probe" rev-parse --absolute-git-dir 2>/dev/null)"
  fi
  if [[ -n "$location" ]]; then
    cat >&2 <<EOF
$PROG: worktree target is $location — refusing to create a worktree.

  target:   $worktree_path
$detail

Point the \`worktreeroot.path\` git config key (or the plugin's
\`worktree_root\` option) at an external root — a path OUTSIDE every repository,
on the same drive as the repo on Windows — then retry.

Not creating inside a checkout or a git directory: from there a worktree can
pick up the enclosing checkout's path-scoped rules as well as its own, and a
git-directory placement mixes the worktree into git metadata. Measurement and
expiry: skills/worktree/reference/nesting-invariant.md "The nesting invariant, dated measurement".
EOF
    exit 3
  fi
fi

check_same_drive "$toplevel" "$worktree_path" || exit $?

worktree_facts_read=0
read_worktree_facts() {
  ((worktree_facts_read)) && return 0
  worktree_facts_read=1
  worktree_facts_parse_z <(git -C "$toplevel" worktree list --porcelain -z 2>/dev/null)
}

reuse_refuse() {
  local line
  for line in "$@"; do printf '%s: %s\n' "$PROG" "$line" >&2; done
  exit 4
}

reuse_existing_target() {
  local top i idx=-1 reason held_branch old_sid claim="$HELPER_DIR/worktree-claim.sh"
  top="$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -n "$top" ]]; then
    read_worktree_facts
    for i in "${!WT_FACT_PATH[@]}"; do
      [[ "${WT_FACT_PATH[i]}" == "$top" ]] && idx=$i && break
    done
  fi
  ((idx >= 0)) || reuse_refuse "target path already exists and is not a worktree of this repository: $worktree_path" \
    "move it aside or choose another name"
  [[ "${WT_FACT_LINKED[idx]}" == yes ]] || reuse_refuse "target path is the repository's main worktree: $worktree_path"
  held_branch="${WT_FACT_BRANCH[idx]}"
  [[ "$held_branch" == "$branch" ]] || reuse_refuse \
    "the worktree at $worktree_path holds branch ${held_branch:-(none)}, not $branch; choose another name"
  [[ -n "$session_id" ]] || reuse_refuse \
    "a worktree already exists at $worktree_path; pass --session-id so the helper can prove this session may reuse it"
  reason="${WT_FACT_LOCKED[idx]}"
  if [[ "${WT_FACT_IS_LOCKED[idx]}" == no ]]; then
    git -C "$toplevel" worktree lock --reason "$(worktree_lock_reason worktree-create.sh "$session_id")" "$top" >&2 ||
      reuse_refuse "could not claim the unlocked worktree at $worktree_path; another process may have claimed it first"
    printf '%s: claimed the unlocked worktree at %s for session %s\n' "$PROG" "$worktree_path" "$session_id" >&2
  elif worktree_reason_is_ours "$reason" "$session_id"; then
    :
  elif [[ -z "$reason" ]]; then
    reuse_refuse "the worktree at $worktree_path is locked with no reason, so it names no session; unlock it by hand if it is free"
  elif ! worktree_reason_lane "$reason" >/dev/null; then
    reuse_refuse "the worktree at $worktree_path is locked by a claim that names no session: $reason" \
      "unlock it by hand (git worktree unlock) if no session is working there"
  else
    old_sid="${BASH_REMATCH[2]}"
    if ! bash "$claim" stale "$top" --repo-dir "$toplevel" >&2; then
      reuse_refuse "another session holds a live claim on the worktree at $worktree_path: $reason" \
        "finish in that session, or hand it over: worktree-claim.sh handover $worktree_path --session-id $old_sid --to $session_id"
    fi
    bash "$claim" handover "$top" --repo-dir "$toplevel" --session-id "$old_sid" --to "$session_id" >&2 ||
      reuse_refuse "could not hand the stale claim on $worktree_path over to session $session_id"
    printf '%s: took over the stale claim of session %s on %s\n' "$PROG" "$old_sid" "$worktree_path" >&2
  fi
  printf '%s: reusing the existing worktree at %s (branch %s)\n' "$PROG" "$worktree_path" "$branch" >&2
  printf '%s\n' "$worktree_path"
  exit 0
}

[[ -e "$worktree_path" ]] && reuse_existing_target

branch_exists=0
if git -C "$toplevel" show-ref --verify --quiet "refs/heads/$branch"; then
  branch_exists=1
  read_worktree_facts
  for i in "${!WT_FACT_PATH[@]}"; do
    [[ "${WT_FACT_BRANCH[i]}" == "$branch" ]] &&
      reuse_refuse "branch $branch is already checked out in the worktree at ${WT_FACT_PATH[i]}" \
        "work there, or choose a name that does not resolve to $branch"
  done
fi

resolve_default_remote() {
  local repo_top="$1" branch cfg r
  local -a remotes=()

  branch=$(git -C "$repo_top" symbolic-ref --quiet --short HEAD 2>/dev/null | tr -d '\r')
  if [[ -n "$branch" ]]; then
    cfg=$(git -C "$repo_top" config --get "branch.$branch.remote" 2>/dev/null | tr -d '\r')
    if [[ -n "$cfg" && "$cfg" != "." ]] && git -C "$repo_top" remote get-url -- "$cfg" >/dev/null 2>&1; then
      printf '%s' "$cfg"
      return 0
    fi
  fi

  if git -C "$repo_top" remote get-url origin >/dev/null 2>&1; then
    printf 'origin'
    return 0
  fi

  while IFS= read -r r; do
    r=${r%$'\r'}
    [[ -n "$r" ]] && remotes+=("$r")
  done < <(git -C "$repo_top" remote 2>/dev/null)
  if ((${#remotes[@]} == 1)); then
    printf '%s' "${remotes[0]}"
    return 0
  fi

  return 1
}

FETCH_CAP_SECONDS=5

refresh_remote_branch() {
  local repo_top="$1" remote="$2" branch="$3"
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never run_capped "$FETCH_CAP_SECONDS" \
    git -C "$repo_top" fetch --quiet --no-tags -- "$remote" "$branch" </dev/null >/dev/null 2>&1
}

if ((existing_branch)); then
  if [[ -n "$base_ref" ]]; then
    printf '%s: --existing-branch cannot be combined with --base-ref\n' "$PROG" >&2
    exit 2
  fi
  if ((!branch_exists)); then
    printf '%s: --existing-branch requires a local branch named %q\n' "$PROG" "$name" >&2
    exit 2
  fi
elif ((branch_exists)); then
  if [[ -n "$base_ref" ]]; then
    printf '%s: branch %s already exists, so --base-ref %s does not apply; checking it out as it is\n' \
      "$PROG" "$branch" "$base_ref" >&2
  fi
else
  [[ -z "$base_ref" ]] && base_ref="fresh"
  base_label="$base_ref"
  case "$base_ref" in
  head)
    base_commit="HEAD"
    ;;
  fresh)
    default_remote=$(resolve_default_remote "$toplevel") || default_remote=""
    head_ref=""
    if [[ -n "$default_remote" ]]; then
      head_ref=$(git -C "$toplevel" symbolic-ref -q "refs/remotes/$default_remote/HEAD" 2>/dev/null | tr -d '\r')
    fi
    if [[ -n "$head_ref" ]]; then
      if ! refresh_remote_branch "$toplevel" "$default_remote" "${head_ref#"refs/remotes/$default_remote/"}"; then
        printf '%s: warning: --base-ref fresh could not refresh %s within %ss (fetch failed or timed out); basing on the cached ref, which may be behind the remote.\n' \
          "$PROG" "${head_ref#refs/remotes/}" "$FETCH_CAP_SECONDS" >&2
        base_label="${head_ref#refs/remotes/}@$(git -C "$toplevel" rev-parse --short "$head_ref" 2>/dev/null | tr -d '\r'), not refreshed"
      fi
      base_commit="$head_ref"
    else
      base_commit="HEAD"
      if [[ -n "$default_remote" ]]; then
        printf '%s: warning: --base-ref fresh could not resolve the remote default branch (%s/HEAD not set); branching from local HEAD instead. Run: git remote set-head %s --auto  to cache it.\n' \
          "$PROG" "$default_remote" "$default_remote" >&2
      else
        printf '%s: warning: --base-ref fresh could not resolve the remote default branch (no default remote: the repository has no remotes, or has several with neither a branch-configured remote nor an origin); branching from local HEAD instead.\n' \
          "$PROG" >&2
      fi
    fi
    ;;
  *)
    printf '%s: --base-ref must be fresh or head, got: %q\n' "$PROG" "$base_ref" >&2
    exit 2
    ;;
  esac
fi

checkout_rev="${base_commit:-}"
((branch_exists)) && checkout_rev="refs/heads/$branch"
checkout_env=()
lfs_skipped=0
if git -C "$toplevel" grep -q -E -e '^[^#]*[[:space:]]filter=lfs([[:space:]]|$)' "$checkout_rev" -- ':(glob)**/.gitattributes' 2>/dev/null; then
  checkout_env=(GIT_LFS_SKIP_SMUDGE=1)
  lfs_skipped=1
fi

if ((branch_exists)); then
  env ${checkout_env[@]+"${checkout_env[@]}"} git -C "$toplevel" worktree add "$worktree_path" "$branch" >&2
elif [[ "$base_ref" == fresh ]]; then
  env ${checkout_env[@]+"${checkout_env[@]}"} git -C "$toplevel" worktree add --no-track -b "$branch" "$worktree_path" "$base_commit" >&2
else
  env ${checkout_env[@]+"${checkout_env[@]}"} git -C "$toplevel" worktree add -b "$branch" "$worktree_path" "$base_commit" >&2
fi || {
  if [[ -e "$worktree_path" ]]; then
    printf '%s: another process created %s while this one was creating it; rerun to reuse it if this session may claim it\n' \
      "$PROG" "$worktree_path" >&2
  else
    printf '%s: git worktree add failed for branch %q (git'\''s error is above)\n' "$PROG" "$branch" >&2
  fi
  exit 4
}
if ((lfs_skipped)); then
  printf '%s: LFS content was not checked out; Git LFS paths are pointer files. Fetch it with git lfs pull, or git lfs pull --include <paths> for part of it, run in %s\n' \
    "$PROG" "$worktree_path" >&2
fi

lock_reason="$(worktree_lock_reason worktree-create.sh "$session_id")"
lock_failed=0
if ! git -C "$toplevel" worktree lock --reason "$lock_reason" "$worktree_path" >&2; then
  lock_failed=1
  printf '%s: warning: could not lock the new worktree — cleanup sweeps will not see it as claimed\n' "$PROG" >&2
  printf '%s: lock_failed=1\n' "$PROG" >&2
fi

include_file="$toplevel/.worktreeinclude"
copied=0
copy_failed=0
if [[ -f "$include_file" ]]; then
  while IFS= read -r -d '' rel; do
    [[ -z "$rel" ]] && continue
    git -C "$toplevel" check-ignore -q -- "$rel" || continue
    src="$toplevel/$rel"
    [[ -f "$src" ]] || continue
    dest="$worktree_path/$rel"
    if mkdir -p "$(dirname "$dest")" && cp -p "$src" "$dest"; then
      copied=$((copied + 1))
    else
      copy_failed=$((copy_failed + 1))
      printf '%s: warning: failed to copy .worktreeinclude file: %s\n' "$PROG" "$rel" >&2
    fi
  done < <(git -C "$toplevel" ls-files -o -i -z --exclude-from="$include_file")
  printf '%s: copied %d .worktreeinclude file(s) into the worktree\n' "$PROG" "$copied" >&2
  if ((copy_failed > 0)); then
    printf '%s: %d .worktreeinclude file(s) failed to copy — the worktree at %s exists but is missing expected local files\n' \
      "$PROG" "$copy_failed" "$worktree_path" >&2
    exit 4
  fi
fi

common_dir="$(git -C "$toplevel" rev-parse --git-common-dir)"
if [[ "$common_dir" != /* ]]; then
  common_dir="$toplevel/$common_dir"
fi
main_worktree="$(dirname "$common_dir")"
settings_src="$main_worktree/.claude/settings.local.json"
if [[ -f "$settings_src" ]]; then
  settings_dest="$worktree_path/.claude/settings.local.json"
  if mkdir -p "$(dirname "$settings_dest")" && cp -p "$settings_src" "$settings_dest"; then
    printf '%s: copied settings.local.json into the worktree\n' "$PROG" >&2
  else
    printf '%s: warning: failed to copy settings.local.json into the worktree\n' "$PROG" >&2
  fi
fi

bash "$HELPER_DIR/provision-prerequisites.sh" --cap "${WORKTREE_CREATE_DEPS_CAP_SECONDS:-45}" \
  --seed-root "$(dirname "$worktree_path")/.npm-seed" "$worktree_path" </dev/null >&2

if ((branch_exists)); then
  printf '%s: created worktree on existing branch %q\n' "$PROG" "$branch" >&2
else
  printf '%s: created worktree on branch %q (base %s)\n' "$PROG" "$branch" "$base_label" >&2
fi
printf '%s\n' "$worktree_path"
if ((lock_failed)); then
  exit 5
fi
