#!/usr/bin/env bash
# worktree-create.sh — shared worktree-creation helper (Phase A).
#
# Single owner of worktree creation for this plugin: external-root path
# computation `<root>/<owner>-<repo>-<slug>`, slug sanitization, base-ref
# resolution (`worktree.baseRef` fresh|head), `git worktree add`, arming the
# `git worktree lock` liveness guard (#2257), and the `.worktreeinclude`
# local-file copy. The copy Claude Code performs for its
# native worktrees (EnterWorktree / --worktree) is bypassed when a worktree is
# created with `git worktree add` directly, so this helper reimplements it.
#
# Consumers:
#   - Phase A (now): the `/worktree create` skill routes through this helper,
#     then calls EnterWorktree(path:) on the printed path to enter the worktree.
#   - Phase B (gated on two upstream Claude Code behaviors still being verified):
#     the `WorktreeCreate` hook becomes a thin stdin adapter (parse `.name`) that
#     calls this same helper.
# The flag CLI is the stable seam both consumers share.
#
# Root-resolution contract: a configured root (--root/--root-file) wins; absent one,
# the plugin data directory supplied via --data-root-file yields <data-dir>/worktrees;
# absent both, the helper refuses (exit 3). It never falls back to Claude Code's
# in-repo `.claude/worktrees/`, whose nested placement is what the nesting
# invariant forbids. That claim is owned, measured and dated in exactly one place
# and is not restated here: skills/worktree/SKILL.md § "The nesting invariant,
# verified". The data dir is never read from the environment — see the resolution
# block.
#
# Output contract: on success the created worktree path is the SOLE stdout line
# (machine-parseable); all diagnostics go to stderr.
#
# Exit codes:
#   0  success — worktree created; path on stdout
#   2  usage error — unknown/missing flag, or a --name git rejects as a branch
#   3  refuse — no usable external root (guidance on stderr); nothing created
#   4  environment error — not a git repo, or `git worktree add` failed

set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — shared worktree-creation helper.

Usage:
  $PROG --name <name> (--root <dir> | --root-file <path>) [--data-root-file <path>]
        [--base-ref fresh|head] [--repo-dir <dir>]

Options:
  --name <name>       Branch/worktree name (e.g. feat/my-feature). Required.
                      Max 64 chars; each /-separated segment holds only letters,
                      digits, dots, underscores, and dashes. Also checked against
                      git's own branch-name grammar, so a name that satisfies the
                      character rules but is an illegal ref (feat/foo..bar,
                      foo.lock, HEAD) is refused (exit 2), not left to git later.
                      That grammar check runs after the repository is resolved,
                      so exits 3 and 4 can precede it.
  --root <dir>        External worktree root, passed directly as a process
                      argument (e.g. from a hook or CLI caller — no shell
                      re-quoting of the value happens on that path). An empty
                      value or an unexpanded \${user_config.*} token falls
                      through to --data-root-file — never to the in-repo
                      .claude/worktrees/ default, whose nested placement the
                      nesting invariant forbids (skills/worktree/SKILL.md).
                      Mutually exclusive with --root-file.
  --data-root-file <path>
                      Read the plugin's data directory from <path>, used as the
                      root ONLY when no --root/--root-file value is configured
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
                      \${user_config.worktree_root} into markdown, which is RAW
                      text substitution, not shell-escaped — write the value to
                      a temp file through a non-shell channel (the Write tool's
                      JSON content parameter), never a quoted literal or a
                      heredoc body: a value containing the heredoc delimiter
                      line ends the heredoc early and the remainder is parsed
                      as commands. The file's bytes ARE the root, verbatim and
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
                      default branch. With no resolvable remote, or an uncached
                      <remote>/HEAD, it warns and branches from local HEAD.
  --repo-dir <dir>    Source repository directory. Default: current directory.
  -h, --help          Show this help.

On success the created worktree path is printed as the sole stdout line, for the
caller to feed to EnterWorktree(path:).

Exit codes: 0 success · 2 usage · 3 refuse (no usable root) · 4 environment.
EOF
}

name=""
root=""
root_given=0
root_file=""
root_file_given=0
data_root_file=""
data_root_file_given=0
base_ref=""
repo_dir="."

# need_value <flag> — guard against a value-taking flag given as the last token
# with no argument. Without this, `shift 2` on a single remaining positional
# fails and leaves $# unchanged, spinning the loop forever.
need_value() {
  if [[ $# -lt 2 ]]; then
    printf '%s: %s requires a value\n' "$PROG" "$1" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) need_value "$@"; name="$2"; shift 2 ;;
    --root) need_value "$@"; root="$2"; root_given=1; shift 2 ;;
    --root-file) need_value "$@"; root_file="$2"; root_file_given=1; shift 2 ;;
    --data-root-file) need_value "$@"; data_root_file="$2"; data_root_file_given=1; shift 2 ;;
    --base-ref) need_value "$@"; base_ref="$2"; shift 2 ;;
    --repo-dir) need_value "$@"; repo_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$name" ]]; then
  printf '%s: --name is required\n' "$PROG" >&2
  exit 2
fi

# Mutual exclusion keys off whether each flag APPEARED, not whether its value is
# non-empty: `--root '' --root-file f` is still a caller naming two sources, and
# treating the empty one as absent would silently pick the other.
if (( root_given && root_file_given )); then
  printf '%s: --root and --root-file are mutually exclusive\n' "$PROG" >&2
  exit 2
fi

# --root-file: read the root from the file rather than a process argument. This
# is the out-of-band handoff a skill uses when it cannot place the
# raw-substituted ${user_config.worktree_root} value in shell source safely (see
# the --root-file usage text above) — the file's bytes ARE the root (or, when
# unset, the literal unexpanded ${user_config...} token), placed there through a
# non-shell channel so no expansion, quote-processing, or heredoc-delimiter
# matching touches it before it lands here.
#
# The whole file is the value, byte for byte: a single quote, `$`, or a backtick
# passes through unchanged, and no line terminator is assumed or stripped. A
# newline anywhere — trailing included — is therefore a rejection, not a trim.
# Reading a "first line" instead would silently proceed with a root the caller
# never asked for, and a trailing newline is indistinguishable from a root whose
# own last byte is a newline, so neither can be forgiven without guessing.
# read_path_file <flag-name> <path> — read a path a caller handed over out-of-band
# through a file, with every byte intact, into the global PATH_FILE_VALUE. Shared
# by --root-file and --data-root-file so the second channel cannot drift from the
# first's guards. Exits 2 on anything that is not a usable single-line path.
#
# Assigns to a global rather than echoing: the guards below must terminate the
# SCRIPT, and an `exit` inside a `$( )` capture kills only the subshell — the
# caller would sail on with an empty root. Verified, not assumed.
read_path_file() {
  local flag="$1" file="$2" value
  PATH_FILE_VALUE=""
  if [[ ! -f "$file" ]]; then
    printf '%s: %s not found: %s\n' "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  # A NUL byte has to be caught BEFORE the value reaches a shell variable: command
  # substitution drops NULs (with a warning on stderr the caller may never see),
  # which would turn `/root-<NUL>suffix` into `/root-suffix` and create a worktree
  # at a path nobody supplied. Compare the byte count with and without NULs rather
  # than matching on one, since the variable can never hold it.
  if (( $(wc -c < "$file") != $(tr -d '\000' < "$file" | wc -c) )); then
    printf '%s: %s %s contains a NUL byte; the file holds the path verbatim and no pathname can contain NUL\n' \
      "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  value=$(cat "$file"; printf x)   # printf x defends the value's own trailing bytes from $( ) stripping
  value=${value%x}
  if [[ "$value" == *$'\n'* ]]; then
    printf '%s: %s %s contains a newline byte; the file holds the path verbatim and a path with a newline in it is malformed configuration, not a value to trim\n' \
      "$PROG" "$flag" "$file" >&2
    exit 2
  fi
  PATH_FILE_VALUE="$value"
}

if (( root_file_given )); then
  read_path_file --root-file "$root_file"
  root="$PATH_FILE_VALUE"
fi

# Validate the name up front against the EnterWorktree schema: max 64 chars, and
# each '/'-separated segment contains only letters, digits, dots, underscores,
# and dashes. Reject invalid names loudly (exit 2) here rather than let
# `git worktree add` fail opaquely downstream. The branch is used verbatim; only
# the directory slug transforms it.
if (( ${#name} > 64 )); then
  printf '%s: --name %q exceeds 64 characters\n' "$PROG" "$name" >&2
  exit 2
fi
if [[ ! "$name" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
  printf '%s: --name %q is not a valid worktree/branch name (each /-separated segment: letters, digits, dots, underscores, dashes only)\n' "$PROG" "$name" >&2
  exit 2
fi

# The remaining name check — git's own ref grammar — needs a healthy repository
# to run in, so it waits until $toplevel is resolved below.

# Unconfigured root: detected here, resolved after the repository is known below.
# Treat an empty value or an unexpanded ${user_config.*} token (what Claude Code
# leaves when the key is unset) as unset.
#
# SC2016: the single-quoted ${user_config token is matched literally on purpose —
# we are detecting the UNexpanded placeholder, so expansion here would be a bug.
root_unset=0
# shellcheck disable=SC2016
if [[ -z "$root" || "$root" == *'${user_config'* ]]; then
  root_unset=1
fi

# Canonicalize a Windows backslash root to the forward-slash grammar git emits.
# On a Windows shell `\` is a path separator `git worktree add` resolves, but the
# containment guard below cannot: the ancestor walk splits on `/`, so an
# all-backslash `${probe%/*}` never changes (parent == probe), the loop breaks on
# its first iteration, and the whole guard block is skipped — a backslash root
# then sails through and git lands the checkout inside the repo/.git. Swapping
# `\`→`/` up front routes a backslash root through the SAME anchor + normalize_path
# + walk as a forward-slash root (one code path, not a parallel one). Gated to
# Windows shells via $OSTYPE — off-Windows `\` is a legal filename byte and must
# be left untouched. (cygpath is intentionally avoided: it resolves relative paths
# against the CWD, not $toplevel, and rewrites MSYS `/tmp` paths — both diverge
# from this helper's contract; a pure separator swap defers all resolution to the
# existing machinery.)
if [[ "$root" == *\\* && ("$OSTYPE" == msys || "$OSTYPE" == cygwin) ]]; then
  bslash="\\"
  fwd="/"
  root="${root//"$bslash"/"$fwd"}"
fi

# Reject drive-relative roots (`C:foo` with no separator after the colon). Git for
# Windows resolves them against the drive's per-directory CWD, which bypasses the
# containment ancestor walk (#962).
if [[ "$root" =~ ^[A-Za-z]:[^/] ]]; then
  printf '%s: --root %q is drive-relative; pass an absolute path (e.g. C:/worktrees)\n' "$PROG" "$root" >&2
  exit 2
fi

# Resolve the source repository top level.
if ! toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
  # Remedy first: this line is surfaced verbatim to a user whose worktree
  # creation just failed, and a bare diagnosis leaves them nothing to do. There
  # is no worktree to create outside a repository, so the actionable answer is
  # the harness-side stand-down, not a flag of this script's.
  printf '%s: run this from inside a git repository, or pass --repo-dir pointing at one; for a Claude Code session at a non-repository directory, set worktree.bgIsolation to "none" in settings so it edits in place instead of isolating\n' "$PROG" >&2
  printf '%s:   --repo-dir is not inside a git repository: %s\n' "$PROG" "$repo_dir" >&2
  exit 4
fi

# Resolve the unconfigured-root fallback: the plugin's own data directory,
# delivered by the caller through --data-root-file.
#
# The value cannot be read from the environment here. In a general Bash-tool
# subprocess — which is what every caller of this helper runs in — CLAUDE_PLUGIN_DATA
# is not scoped to the invoking plugin; the repository's probe recorded it naming an
# unrelated installed plugin's data directory (docs/extensibility-contract-smoke-tests.md,
# Test B). It IS reliable inside a plugin's own declared command, so a future
# WorktreeCreate hook passes it as a --root process argument instead.
#
# What the skill CAN do is substitute ${CLAUDE_PLUGIN_DATA} into its own SKILL.md
# body, where it renders per-plugin (same probe, Test D), and hand the rendered
# value over through the existing non-shell file channel. That is this flag.
#
# A repository-derived default was considered and rejected: a sibling of the
# checkout lands inside a repository-discovery tree under a layout like
# <root>/github.com/<owner>/<repo>, where `ghq list` then enumerates each worktree
# as a repository of its own (a leading dot does not hide it) — the very pollution
# the worktree skill tells users to keep their configured root clear of.
#
# Fail-closed by construction: if substitution ever regresses, the file carries the
# literal token, which is detected below and refused rather than turned into a
# relative path inside the repository. The containment guard further down still
# validates whatever root wins.
if (( root_unset )); then
  data_root=""
  if (( data_root_file_given )); then
    read_path_file --data-root-file "$data_root_file"
    data_root="$PATH_FILE_VALUE"
    # A caller whose substitution did not fire hands over the literal token. That
    # is not a directory, and treating it as one would create `${CLAUDE_PLUGIN_DATA}`
    # as a relative path in the repository — the nesting this helper exists to
    # prevent. Detect it and fall through to the refusal below.
    # shellcheck disable=SC2016
    [[ "$data_root" == *'${CLAUDE_PLUGIN_DATA'* ]] && data_root=""
  fi

  if [[ -z "$data_root" ]]; then
    cat >&2 <<EOF
$PROG: no worktree root available — refusing to create a worktree.

Set the source-control plugin's \`worktree_root\` directory key to an external
root (a path OUTSIDE every repository), then retry. Run the worktree setup
skill, or configure it via \`/plugin\`.

Not falling back to the in-repo .claude/worktrees/ default: a worktree nested
inside a checkout can pick up that checkout's path-scoped rules as well as its
own. Measurement, disputed arms and expiry:
skills/worktree/SKILL.md "The nesting invariant, verified".
EOF
    exit 3
  fi

  root="${data_root%/}/worktrees"
  printf '%s: worktree_root is not configured; defaulting to %s\n' "$PROG" "$root" >&2
  # SC2016: the backticks are literal markdown in guidance text, not a command
  # substitution — expansion is exactly what must NOT happen here.
  # shellcheck disable=SC2016
  printf '%s: set the plugin'\''s `worktree_root` directory key to place worktrees elsewhere.\n' "$PROG" >&2
fi

# Second half of name validation: the character class checked above is NOT a
# subset of git's ref grammar, so it alone cannot uphold the exit-2-for-an-
# invalid-name contract. `feat/foo..bar` (`..`), `.foo` and `feat/.` (component
# starting/ending with `.`), `foo.lock` (reserved suffix), `HEAD`, and `-lead`
# all sit inside the class yet are illegal refs, and would otherwise fail inside
# `git worktree add` as environment exit 4 — which a caller cannot tell from a
# genuinely broken environment. Ask git rather than reimplementing its rules.
#
# Runs HERE, not beside the character check, and scoped with `-C "$toplevel"`:
# `--branch` takes a branchname-shorthand and so performs repository discovery,
# which fails outright when the process's CWD is a stale checkout (a `.git` file
# naming a gitdir that no longer exists — precisely what this plugin's own
# worktree cleanup deals with). Inheriting that CWD turned a perfectly valid name
# into a false exit 2, and the documented invocation omits `--repo-dir`, so the
# CWD is the default. Deferring past the exit-4 repository probe guarantees a
# healthy repo to run in and makes a non-zero exit mean the NAME, nothing else.
# Both streams are discarded: on success `--branch` echoes the name to stdout,
# which would corrupt the sole-stdout-line output contract, and on failure git's
# message is superseded by ours. An option-shaped name is read as a ref because
# git parses no further options after `--branch`.
if ! git -C "$toplevel" check-ref-format --branch "$name" >/dev/null 2>&1; then
  printf '%s: --name %q is not a valid git branch name (see: git help check-ref-format)\n' "$PROG" "$name" >&2
  exit 2
fi

# parse_owner_repo <url> — derive an `owner<TAB>repo` pair from a remote URL for
# the directory name. Sets globals `owner` and `repo`. Handles the shapes we see:
#   git@host:owner/repo.git · https://host/owner/repo.git · ssh://git@host/owner/repo
#   GitLab subgroups (group/subgroup/repo → owner=subgroup)
#   Azure DevOps (…/org/project/_git/repo and v3/org/project/repo → owner=project)
# It never fails: with fewer than two usable path segments, owner is left empty
# and the caller falls back to the repo-dir name.
parse_owner_repo() {
  local url="$1" path
  owner=""; repo=""
  # Reduce to the path portion. Scheme URLs (scheme://host/path) and scp syntax
  # (git@host:path) delimit the host differently, so branch on which is present.
  path="$url"
  if [[ "$path" == *"://"* ]]; then
    path="${path#*://}"        # strip scheme://
    path="${path#*/}"          # strip host[:port] up to the first '/'
  elif [[ "$path" == *:* ]]; then
    path="${path#*:}"          # scp-like git@host:owner/repo -> owner/repo
  fi
  path="${path%.git}"
  path="${path%/}"

  # Split into non-empty segments, dropping Azure's `_git` marker and a leading
  # `v3` (Azure SSH) so the meaningful org/project/repo tail remains.
  local -a seg=() parts
  IFS='/' read -r -a parts <<<"$path"
  local p
  for p in "${parts[@]}"; do
    [[ -z "$p" || "$p" == "_git" || "$p" == "v3" ]] && continue
    seg+=("$p")
  done

  local n=${#seg[@]}
  if (( n >= 2 )); then
    repo="${seg[n-1]}"
    owner="${seg[n-2]}"
  elif (( n == 1 )); then
    repo="${seg[0]}"
  fi
}

# normalize_path <abs-path> — lexically collapse `.` and `..` (and redundant
# slashes) in an ABSOLUTE path, echoing the result. Pure string work: it does
# NOT touch the filesystem, so it resolves `..` even when leading components do
# not exist yet — the case `git worktree add` handles by creating the missing
# dirs and letting the OS resolve `..`. `realpath -m` would do this too but is a
# GNU extension absent on BSD/macOS (the repo's realpath/readlink -f idiom needs
# every-but-last component to exist, so it cannot resolve a nonexistent-prefix
# `..`). A path with no `.`/`..`/`//` segment re-splits and re-joins identically,
# so this is a no-op for ordinary roots. Symlink resolution of existing
# components is left to git's own realpath at creation (see the containment note).
normalize_path() {
  local input="$1" root rest seg
  if [[ "$input" == /* ]]; then
    root="/"
    rest="${input#/}"
  elif [[ "$input" =~ ^[A-Za-z]:/ ]]; then
    root="${input:0:2}/"
    rest="${input:3}"
  else
    root=""
    rest="$input"
  fi
  local -a segs=() out=()
  IFS='/' read -r -a segs <<<"$rest"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    if [[ "$seg" == ".." ]]; then
      # Pop the last kept segment; a `..` at the root is a no-op (clamped).
      ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}")
      continue
    fi
    out+=("$seg")
  done
  local IFS='/'
  printf '%s%s' "$root" "${out[*]}"
}

# owner/repo from the origin remote when present; otherwise fall back to the
# repository directory name (owner omitted).
owner=""
repo=""
if origin_url=$(git -C "$toplevel" remote get-url origin 2>/dev/null); then
  parse_owner_repo "$origin_url"
fi
if [[ -z "$repo" ]]; then
  repo="${toplevel##*/}"
  owner=""
fi

# Sanitize the name into a filesystem-safe slug: '/' and any character outside
# [A-Za-z0-9._-] become '-', runs of '-' collapse, leading/trailing '-' trim.
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

# `git -C "$toplevel" worktree add` resolves a relative target against the repo
# top level, so a relative root (e.g. `worktrees`) always lands inside the repo.
# Anchor it to $toplevel up front so the containment check below sees the real
# target rather than an unrooted string whose ancestor walk never reaches the repo.
# A drive-letter path counts as absolute only when the colon is followed by a
# separator (`C:/foo`); `C:foo` is drive-relative and is refused above (#962).
[[ "$worktree_path" != /* && ! "$worktree_path" =~ ^[A-Za-z]:/ ]] && worktree_path="$toplevel/$worktree_path"

# Collapse `.`/`..` before the containment walk. A root with `..` after a
# nonexistent component (e.g. `<root>/missing/../<repo>/.claude/worktrees`) would
# otherwise defeat the walk: it stops at the nonexistent `missing` string and
# never probes the real `<repo>` ancestor, so the guard passes and `git worktree
# add` creates `missing`, resolves `..`, and lands the checkout inside the repo.
# Normalizing first makes the walk see the true landing path.
worktree_path=$(normalize_path "$worktree_path")

# Reject placement inside any git repository — a working tree, a normal repo's
# .git directory, or a bare clone. Keeping worktrees OUT of every repository is
# the helper's core purpose — see skills/worktree/SKILL.md § "The nesting
# invariant, verified" for the measured claim, and note that a worktree dropped
# inside a .git or bare directory additionally mixes the checkout into git
# metadata, which is a separate and undisputed reason to refuse. The root resolution above does not catch a root explicitly
# pointed inside a repository (e.g. the old .claude/worktrees/ path, a root under
# a sibling clone, or a path beneath a .git directory), so ask git about the
# target's location: walk up from the target's parent to the nearest existing
# ancestor. Probing the parent, never the target itself, keeps an already-created
# worktree at $worktree_path from matching its own top level — that case is the
# "already exists" error below. `--show-toplevel` catches work-tree ancestors (and
# by top-level equality tells the source repo from a foreign clone);
# `--is-inside-git-dir` catches .git and bare-repo ancestors, which have no work
# tree and so report no top level. Both come from `rev-parse`, so the check is
# immune to path-format differences (drive-letter spelling, symlinks) that defeat
# a raw string prefix test.
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

Set the source-control plugin's \`worktree_root\` directory key to an external
root (a path OUTSIDE every repository, on the same drive as the repo on Windows),
then retry.

Not creating inside a checkout or a git directory: from there a worktree can
pick up the enclosing checkout's path-scoped rules as well as its own, and a
git-directory placement mixes the worktree into git metadata. Measurement and
expiry: skills/worktree/SKILL.md "The nesting invariant, verified".
EOF
    exit 3
  fi
fi

if [[ -e "$worktree_path" ]]; then
  printf '%s: target path already exists: %s\n' "$PROG" "$worktree_path" >&2
  exit 4
fi

# Base-ref resolution. The caller owns policy: pass --base-ref (fresh|head),
# defaulting to fresh when omitted. Claude Code's `worktree.baseRef` lives in
# settings.json (not git config), so the helper does not probe it — the skill
# reads the effective setting and passes it through this flag.
[[ -z "$base_ref" ]] && base_ref="fresh"

# resolve_default_remote <repo-toplevel> — echo the repository's effective
# default remote name, or return non-zero when none can be resolved. `origin` is
# only a convention, not a guarantee: `git clone -o upstream` produces a repo
# with no `origin` at all, so probing that one name mistakes a healthy repo for a
# remoteless one. Rungs, highest priority first:
#   1. the current branch's configured remote (`branch.<name>.remote`)
#   2. `origin`, when it exists
#   3. the sole remote, when the repository has exactly one
# Every rung is a NAME lookup only — the caller probes the resolved remote's
# cached HEAD symref, so nothing here hardcodes a default branch.
resolve_default_remote() {
  local repo_top="$1" branch cfg r
  local -a remotes=()

  # Rung 1. A detached HEAD has no branch, so symbolic-ref yields nothing and
  # this rung is skipped. Two values must not be accepted: `.` is git's sentinel
  # for "tracks a local branch" rather than a remote name (`refs/remotes/./HEAD`
  # is nonsense), and a name whose remote no longer exists is stale config that
  # must not shadow a healthy `origin` below — so require it to resolve.
  #
  # The `--` before the name is load-bearing: `git remote get-url` takes options
  # (`[--push] [--all] <name>`) and a remote name may legally begin with `-`
  # (`git clone -o -foo <url>` creates exactly that, and writes it straight into
  # `branch.<name>.remote`). Without the terminator git reads `-foo` as switches,
  # this rung fails on a remote that is perfectly healthy, and resolution falls
  # silently through to `origin` — the one outcome "fresh" must never produce.
  #
  # Every git read here is piped through `tr -d '\r'`: under git.exe on an MSYS
  # or Cygwin shell the output carries CRLF, and an untrimmed `upstream\r` makes
  # every downstream lookup miss while looking correct in an error message.
  branch=$(git -C "$repo_top" symbolic-ref --quiet --short HEAD 2>/dev/null | tr -d '\r')
  if [[ -n "$branch" ]]; then
    cfg=$(git -C "$repo_top" config --get "branch.$branch.remote" 2>/dev/null | tr -d '\r')
    if [[ -n "$cfg" && "$cfg" != "." ]] && git -C "$repo_top" remote get-url -- "$cfg" >/dev/null 2>&1; then
      printf '%s' "$cfg"
      return 0
    fi
  fi

  # Rung 2.
  if git -C "$repo_top" remote get-url origin >/dev/null 2>&1; then
    printf 'origin'
    return 0
  fi

  # Rung 3. Exactly one remote makes the choice unambiguous whatever it is
  # named; two or more with neither a branch-configured nor an `origin` default
  # is a genuine ambiguity, and guessing one would be worse than the caller-
  # visible HEAD fallback. (`checkout.defaultRemote` settles exactly that
  # ambiguity for git's own branch-name disambiguation and is a candidate rung
  # here; it is deliberately not consulted yet, because it would widen the
  # resolution order beyond the one this helper's callers were specified against.)
  while IFS= read -r r; do
    r=${r%$'\r'}
    [[ -n "$r" ]] && remotes+=("$r")
  done < <(git -C "$repo_top" remote 2>/dev/null)
  if (( ${#remotes[@]} == 1 )); then
    printf '%s' "${remotes[0]}"
    return 0
  fi

  return 1
}

case "$base_ref" in
  head)
    base_commit="HEAD"
    ;;
  fresh)
    # Resolve the default REMOTE first, then that remote's default BRANCH
    # symbolically (never hardcode origin/main — the portability lint forbids
    # it). When the symref is not cached locally, fall back to local HEAD
    # (matching Claude Code's documented behavior, which is itself origin-centric:
    # https://code.claude.com/docs/en/worktrees) but warn loudly: "fresh"
    # promises the remote default branch, so a silent fall-through to HEAD could
    # carry unpushed local commits the caller did not want.
    #
    # The HEAD probe deliberately does NOT cascade back down the remote rungs.
    # "fresh" means the EFFECTIVE remote's default branch; quietly substituting a
    # different remote's default branch is a worse failure than the HEAD
    # fallback, because the caller cannot see it happen.
    default_remote=$(resolve_default_remote "$toplevel") || default_remote=""
    head_ref=""
    if [[ -n "$default_remote" ]]; then
      head_ref=$(git -C "$toplevel" symbolic-ref -q "refs/remotes/$default_remote/HEAD" 2>/dev/null | tr -d '\r')
    fi
    if [[ -n "$head_ref" ]]; then
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

if ! git -C "$toplevel" worktree add -b "$name" "$worktree_path" "$base_commit" >&2; then
  printf '%s: git worktree add failed (branch %q may already exist)\n' "$PROG" "$name" >&2
  exit 4
fi

# Arm the removal guard the moment the worktree exists: a locked worktree makes
# `git worktree remove` refuse (a single --force included) and its record
# survives `git worktree prune`, so another session's cleanup sweep cannot
# delete a lane's worktree mid-operation. `git status --porcelain` cannot carry
# this signal — an interactive rebase paused at a `break` leaves it completely
# empty — and before this helper armed it, no lane ever ran `git worktree lock`,
# so the `locked` flag the cleanup skill already honors was structurally always
# absent (#2257). The owning lane (or cleanup, after explicit confirmation)
# disarms with `git worktree unlock <path>`.
lock_reason="worktree-create.sh: lane active on ${HOSTNAME:-$(hostname 2>/dev/null || printf 'unknown-host')} since $(date -u +%Y-%m-%dT%H:%M:%SZ); unlock when the owning lane is done"
lock_failed=0
if ! git -C "$toplevel" worktree lock --reason "$lock_reason" "$worktree_path" >&2; then
  lock_failed=1
  printf '%s: warning: could not lock the new worktree — cleanup sweeps will not see it as claimed\n' "$PROG" >&2
  printf '%s: lock_failed=1\n' "$PROG" >&2
fi

# Reimplement Claude Code's .worktreeinclude copy: files that match a
# .worktreeinclude pattern AND are also gitignored are copied one-way into the
# new worktree. `ls-files -o -i --exclude-from` yields untracked files matching
# the include patterns; `check-ignore -q` filters that down to the ones the
# real .gitignore also ignores (the documented intersection). NUL-delimited
# (`-z` / `read -d ''`) so paths with spaces, newlines, or quote-triggering
# characters are not dropped or mangled.
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
  if (( copy_failed > 0 )); then
    printf '%s: %d .worktreeinclude file(s) failed to copy — the worktree at %s exists but is missing expected local files\n' \
      "$PROG" "$copy_failed" "$worktree_path" >&2
    exit 4
  fi
fi

printf '%s: created worktree on branch %q (base %s)\n' "$PROG" "$name" "$base_ref" >&2
printf '%s\n' "$worktree_path"
if ((lock_failed)); then
  exit 5
fi
