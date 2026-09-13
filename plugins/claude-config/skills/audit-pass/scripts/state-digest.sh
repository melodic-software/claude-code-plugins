#!/usr/bin/env bash
# state-digest.sh — `state-digest/v1` and `input-digest/v1` for audit-pass.
#
# WHY THIS EXISTS. The state digest is the FIRST comparability input, so P1 is
# only as falsifiable as this derivation is exact. It shipped as one sentence
# ("sha256 over the inventoried surfaces in sorted order, each paired with the
# content hash of its current bytes") with no pinned ordering, no separator, and
# no statement of which sha256 over what. Two implementations following that
# sentence produce different digests over one tree, so two runs compare unequal
# and P1 asserts nothing anyone can check. A run in this state computed its own
# digest with a scratch script, which is the defect rather than a workaround.
#
# THE DERIVATION, pinned here and in `reference/determinism-tiers.md` §6:
#
#   entry       = <surface> 0x1F <content-hash>
#   digest-body = entry 0x1E entry 0x1E ...        (no trailing separator)
#   digest      = lowercase hex sha256(digest-body), all 64 characters
#
#   - entries are DEDUPLICATED on the surface token, then sorted ascending by
#     BYTE ORDER under LC_ALL=C. A locale collation reorders the same set on a
#     different machine and changes the digest with no change to the tree.
#   - the content hash is sha256 over the file's RAW BYTES, 64 lowercase hex.
#     One algorithm across all three scopes: user scope and managed policy sit
#     outside any worktree, so a git object id is not uniformly available there,
#     and a digest that switched algorithms by scope would make the two halves of
#     one comparison incomparable. Git supplies the dirty path SET, never a hash.
#   - a path that does not exist pairs with the literal token `deleted`; one that
#     cannot be read pairs with `unreadable`. Neither is 64 lowercase hex, so
#     neither can be mistaken for a content hash. `unreadable` is a value rather
#     than a failure because a permission-denied user-scope file is an ordinary
#     state and failing there would take the whole gate down with it.
#   - a digest over NO entries is sha256 of the empty byte string.
#
# `input-digest/v1` is the SAME construction over a lane's file list plus its
# detection configuration, which enters as reserved `cfg:` pseudo-surface entries
# sorted in with the files rather than appended after them (the ordering rule
# admits no exceptions). Reusing the construction is deliberate: two digests
# specified separately drift apart on the next edit to either, and a resume
# comparing one against the other re-runs every lane forever or carries every
# lane forward wrongly.
#
# SCOPE OF WRITES: none. This script reads files the caller names and prints a
# hex string. It never writes anywhere, which is what lets the skill call it
# under a bare read-only invocation.
#
# PORTABILITY. coreutils plus one of `sha256sum` / `shasum`, and `git` only for
# the `dirty` subcommand. No jq, no GNU-only flags.
#
# Usage:
#   state-digest.sh digest       --list <file> [--exclude <surface>]...
#   state-digest.sh input-digest --list <file> [--config <token>=<value>]...
#                                [--exclude <surface>]...
#   state-digest.sh dirty        --target <repo-root>
#   state-digest.sh hash-file    --path <file>
#
# `--list <file>` holds one entry per line, `<surface-token>\t<path>`, where the
# surface token is §1's `surface` form and the path is where those bytes live on
# this machine. `-` reads the list from stdin. `dirty` emits exactly that shape
# for a target's dirty set, so the two compose:
#
#   { cat inventory.tsv; state-digest.sh dirty --target "$ROOT"; } \
#     | state-digest.sh digest --list -
#
# `--config <token>=<value>` adds one `cfg:` entry whose content hash is sha256
# of <value>. The token must start with `cfg:`; it cannot collide with a surface
# token, whose forms are a repo-relative POSIX path or a scope prefix.
#
# Exit codes:
#   0  the digest (or the dirty listing) is on stdout
#   2  usage error, rejected argument, a missing prerequisite, or a `git status`
#      that did not succeed. An empty dirty set means a clean tree and nothing
#      else, so a failing `git status` is refused rather than reported as clean.

set -uo pipefail

PROG="state-digest.sh"

# The two sentinels. Chosen to be unrepresentable as a content hash, which is
# exactly 64 lowercase hex characters.
SENTINEL_MISSING="deleted"
SENTINEL_UNREADABLE="unreadable"

# 0x1F between an entry's two fields, 0x1E between entries. Two distinct
# separators, so a surface token carrying a separator-shaped substring cannot
# restructure the body.
US=$'\x1f'
RS=$'\x1e'

# Every temp file this script creates is registered here and removed on exit,
# however the script leaves. `die` is the reason: it is called from eight places
# that hold a live temp file, and a per-site `rm` before each one is a rule that
# has to be re-obeyed every time a `die` is added. One trap is obeyed by
# construction. Explicit removals elsewhere stay, because freeing a large entry
# file at the end of a long run beats holding it until exit; `rm -f` twice on one
# path is harmless.
TEMP_FILES=()
cleanup_temps() {
  [[ "${#TEMP_FILES[@]}" -gt 0 ]] && rm -f "${TEMP_FILES[@]}"
  return 0
}
trap cleanup_temps EXIT

# Sets MK_TEMP rather than printing it. A command substitution would put both the
# registration and the `die` inside a subshell, where the registry never reaches
# this shell and the exit never reaches this script.
MK_TEMP=""
mk_temp() {
  MK_TEMP=$(mktemp) || die "could not create a temporary file"
  TEMP_FILES+=("$MK_TEMP")
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
state-digest.sh — state-digest/v1 and input-digest/v1 for audit-pass.

  state-digest.sh digest       --list <file|-> [--exclude <surface>]...
  state-digest.sh input-digest --list <file|-> [--config <cfg:token>=<value>]...
                               [--exclude <surface>]...
  state-digest.sh dirty        --target <repo-root>
  state-digest.sh hash-file    --path <file>

--list holds one `<surface-token>\t<path>` entry per line; `-` reads stdin.
Entries are deduplicated on the surface token, sorted by byte order under
LC_ALL=C, joined `surface 0x1F hash` / `0x1E`, and hashed with sha256.
A missing path hashes to `deleted`, an unreadable one to `unreadable`.
EOF
}

# sha256 of stdin, lowercase hex, no filename suffix. `sha256sum` on GNU,
# `shasum -a 256` on BSD userland; a host with neither cannot compute the digest
# at all and says so rather than printing something that looks like one.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    die "no sha256 implementation found (need sha256sum or shasum)"
  fi
}

sha256_string() {
  printf '%s' "$1" | sha256_stdin
}

# Content hash of one path, or a sentinel. Readability is tested with -r AND by
# the read itself: a path can pass -r and still fail to read (a directory, a
# dangling mount), and a sentinel is the honest answer to both.
hash_path() {
  local p="$1" out=""
  if [[ ! -e "$p" ]]; then
    printf '%s' "$SENTINEL_MISSING"
    return 0
  fi
  if [[ -d "$p" || ! -r "$p" ]]; then
    printf '%s' "$SENTINEL_UNREADABLE"
    return 0
  fi
  out=$(sha256_stdin <"$p" 2>/dev/null) || out=""
  if [[ -z "$out" ]]; then
    printf '%s' "$SENTINEL_UNREADABLE"
    return 0
  fi
  printf '%s' "$out"
}

# Read `<surface>\t<path>` lines, drop excluded surfaces, dedup on the surface
# token keeping the first occurrence, hash each path, and print `<surface>\t<hash>`
# lines. Deduplication happens BEFORE sorting and before hashing: a surface that
# is both inventoried and dirty must contribute exactly one entry, and hashing it
# twice would also double the cost on the largest files.
collect_entries() {
  local list="$1"
  shift
  local excludes=("$@")
  local line surface path seen_file hashed ex skip

  mk_temp
  seen_file="$MK_TEMP"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    surface="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    if [[ "$surface" == "$line" ]]; then
      die "list entry is not <surface>\\t<path>: $line"
    fi
    [[ -z "$surface" ]] && die "list entry has an empty surface token: $line"

    skip=0
    for ex in ${excludes[0]+"${excludes[@]}"}; do
      if [[ "$surface" == "$ex" ]]; then
        skip=1
        break
      fi
    done
    [[ "$skip" -eq 1 ]] && continue

    if grep -qxF -- "$surface" "$seen_file" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$surface" >>"$seen_file"

    hashed=$(hash_path "$path")
    printf '%s\t%s\n' "$surface" "$hashed"
  done <"$list"

  rm -f "$seen_file"
}

# Sort by byte order, join into the pinned body, hash it. The body is built by
# streaming rather than accumulated in a variable, because a large inventory's
# body exceeds what is comfortable to hold in one shell string.
digest_from_entries() {
  local entries="$1" body first=1 line surface hashed
  body=$(mktemp) || die "could not create a temporary file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    surface="${line%%$'\t'*}"
    hashed="${line#*$'\t'}"
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf '%s' "$RS" >>"$body"
    fi
    printf '%s%s%s' "$surface" "$US" "$hashed" >>"$body"
  done < <(LC_ALL=C sort "$entries")

  sha256_stdin <"$body"
  rm -f "$body"
}

read_list_to_temp() {
  local list="$1" tmp
  # This function runs inside a command substitution, so the caller's registry
  # and trap are in a different shell: the temp is removed here, by hand, on the
  # one path that abandons it. The caller registers the path it receives.
  tmp=$(mktemp) || die "could not create a temporary file"
  if [[ "$list" == "-" ]]; then
    cat >"$tmp"
  else
    [[ -r "$list" ]] || {
      rm -f "$tmp"
      die "--list is not readable: $list"
    }
    cat "$list" >"$tmp"
  fi
  printf '%s' "$tmp"
}

cmd_digest() {
  local list="" excludes=() configs=() arg key value
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --list)
      [[ $# -ge 2 ]] || die "--list needs a value"
      list="$2"
      shift 2
      ;;
    --exclude)
      [[ $# -ge 2 ]] || die "--exclude needs a value"
      excludes+=("$2")
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die "--config needs a value"
      configs+=("$2")
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$list" ]] || die "--list is required"
  # Validated HERE, not inside read_list_to_temp: that runs in a command
  # substitution, where a `die` exits the subshell and the caller carries on
  # with an empty path. A refusal that does not reach the exit code is not one.
  if [[ "$list" != "-" && ! -r "$list" ]]; then
    die "--list is not readable: $list"
  fi

  local src entries
  src=$(read_list_to_temp "$list")
  TEMP_FILES+=("$src")
  mk_temp
  entries="$MK_TEMP"

  collect_entries "$src" ${excludes[0]+"${excludes[@]}"} >"$entries"

  # Config entries are appended to the entry set and then sorted IN with the
  # file entries, never after them: the ordering rule is over the whole set.
  local cfg
  for cfg in ${configs[0]+"${configs[@]}"}; do
    key="${cfg%%=*}"
    value="${cfg#*=}"
    if [[ "$key" == "$cfg" ]]; then
      die "--config must be <cfg:token>=<value>: $cfg"
    fi
    case "$key" in
    cfg:?*) : ;;
    *) die "--config token must start with 'cfg:': $key" ;;
    esac
    printf '%s\t%s\n' "$key" "$(sha256_string "$value")" >>"$entries"
  done

  digest_from_entries "$entries"
  rm -f "$src" "$entries"
}

# The dirty path set, as `<surface>\t<path>` lines the digest can consume.
# `--untracked-files=all` is required, not a preference: bare porcelain collapses
# an untracked directory to one `?? dir/` entry, so the ordinary worktree state of
# having one untracked directory would make the digest uncomputable. `-z` emits
# NUL-delimited, unquoted paths, which sidesteps porcelain's quoting of unusual
# bytes entirely. A rename entry emits the new path followed by the original as a
# separate NUL-terminated field; both are hashed, the original normally as
# `deleted`.
cmd_dirty() {
  local target="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --target)
      [[ $# -ge 2 ]] || die "--target needs a value"
      target="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$target" ]] || die "--target is required"
  [[ -d "$target" ]] || die "--target is not a directory: $target"
  command -v git >/dev/null 2>&1 || die "git is required for the dirty path set"

  # The output is captured and the STATUS CHECKED BEFORE anything parses it.
  # Consumed through a process substitution instead, a failing `git status` is
  # indistinguishable from a clean tree: the loop reads nothing, completes, and
  # the caller computes baseline and endpoint digests that omit every worktree
  # change, with the comparability gate then evaluating against incomplete input
  # instead of failing. A bare repo and an unreadable index both take that path.
  local raw err rc=0
  raw=$(mktemp) || die "could not create a temporary file"
  # `$raw` already exists, so a failure here has to clean it up: a `die` that
  # leaves its own temp file behind turns one failure into litter in TMPDIR.
  err=$(mktemp) || {
    rm -f "$raw"
    die "could not create a temporary file"
  }
  git -C "$target" status --porcelain -z --untracked-files=all >"$raw" 2>"$err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    local detail
    detail=$(tr '\n' ' ' <"$err")
    rm -f "$raw" "$err"
    die "git status failed in $target (exit $rc): ${detail% }"
  fi
  rm -f "$err"

  local field status path expect_rename_src=0
  while IFS= read -r -d '' field; do
    if [[ "$expect_rename_src" -eq 1 ]]; then
      expect_rename_src=0
      printf '%s\t%s\n' "$field" "$target/$field"
      continue
    fi
    # `XY path` — two status characters, a space, then the path.
    status="${field:0:2}"
    path="${field:3}"
    [[ -z "$path" ]] && continue
    printf '%s\t%s\n' "$path" "$target/$path"
    case "$status" in
    R* | C* | *R | *C) expect_rename_src=1 ;;
    *) : ;;
    esac
  done <"$raw"
  rm -f "$raw"
}

cmd_hash_file() {
  local path="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --path)
      [[ $# -ge 2 ]] || die "--path needs a value"
      path="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$path" ]] || die "--path is required"
  hash_path "$path"
  printf '\n'
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 2
  }
  local cmd="$1"
  shift
  # Checked once, up front. Every other call site is inside a command
  # substitution, where a `die` exits only the subshell and the run would carry
  # on with an empty hash that looks like a value.
  case "$cmd" in
  digest | input-digest | hash-file)
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
      die "no sha256 implementation found (need sha256sum or shasum)"
    fi
    ;;
  *) : ;;
  esac
  case "$cmd" in
  digest | input-digest) cmd_digest "$@" ;;
  dirty) cmd_dirty "$@" ;;
  hash-file) cmd_hash_file "$@" ;;
  --help | -h | help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
