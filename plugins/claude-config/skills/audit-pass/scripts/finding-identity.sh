#!/usr/bin/env bash
# finding-identity.sh — §1's derivations, plus the emitter guard every record
# passes before `run-state.sh partial append` writes it.
#
# WHY THIS EXISTS. `reference/finding-identity.md` pins `anchor/v1`
# normalization, the duplicate discriminator, and `finding_id` in full, and then
# left every one of them to be performed by the model on each run. An
# underspecified derivation is a different anchor per implementation; a fully
# specified one performed by hand is a different anchor per RUN, which is the
# same defect with a longer fuse. A pass in that state emitted a record typed as
# a finding carrying `"identity": null` and no `finding_id/v1` — a hard error
# under assertion 1.3 that a validating emitter would have refused at the append.
#
# WHAT IT COMPUTES.
#
#   anchor/v1   e:<sha256(normalized excerpt) truncated to 12 hex>:<n>
#               s:                                (whole-surface, content-free)
#   <n>         sha256(normalized heading path) truncated to 8 hex, or the
#               sentinel 0x00 where the surface has no heading above the excerpt
#   finding_id  sha256(check 0x1F claim 0x1F surface 0x1F anchor [0x1F ...])
#               truncated to 16 hex, sites in canonical sorted order
#   group/v1    "g:" + sha256(check 0x1F claim) truncated to 16 hex
#
# `group` is derived from check and claim ALONE, never from the sites. That is
# the property that makes it useful: it survives fixing, adding, or removing any
# one site, so a report can keep one claim's split occurrences together across
# runs without the grouping renaming itself on every partial fix.
#
# THE EMITTER GUARD refuses, rather than repairs:
#   - a finding record with `identity` absent or null;
#   - an empty `sites` array, or THREE OR MORE sites (past two there is no
#     relation the pairwise exemption could be about, only independently
#     correctable occurrences the lane was supposed to split);
#   - two sites without a `pairwise: true` declaration on the claim;
#   - an `s:` anchor in a two-site finding (assertion 1.6);
#   - a `claim` that is free prose rather than a claim id;
#   - a stored `finding_id/v1` that disagrees with its own constituents.
# Splitting a multi-site return, binding a claim id, and choosing the
# granularity are the lane's work. A guard that silently fixed them would hide
# the delegate that needs the fix.
#
# SCOPE OF WRITES: none. Every subcommand reads its arguments and prints to
# stdout.
#
# PORTABILITY. coreutils plus one of `sha256sum` / `shasum`. `validate-record`
# additionally needs `python3` for a definitive JSON parse, and says so rather
# than guessing with a regex: a record that a regex passed and a parser would
# have rejected is permanent in an append-only artifact.
#
# Usage:
#   finding-identity.sh normalize       --excerpt <text> [--in-fence]
#   finding-identity.sh anchor          --excerpt <text> [--heading-path <text>]
#                                       [--in-fence]
#   finding-identity.sh anchor          --whole
#   finding-identity.sh finding-id      --check <id> --claim <id>
#                                       --site <surface>=<anchor> [--site ...]
#   finding-identity.sh group-id        --check <id> --claim <id>
#   finding-identity.sh validate-record --record <json-line>
#
# Exit codes:
#   0  the derivation is on stdout, or the record passed the guard
#   2  usage error, rejected argument, or a missing prerequisite
#   4  `validate-record` only — the record VIOLATES §1 and must not be appended.
#      Distinct from 2 so a caller can tell "you called me wrong" from "the
#      record is bad", which are different failures with different remedies.

set -uo pipefail

PROG="finding-identity.sh"
EXIT_INVALID_RECORD=4

US=$'\x1f'

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
finding-identity.sh — anchor/v1, finding_id/v1, group/v1, and the emitter guard.

  finding-identity.sh normalize       --excerpt <text> [--in-fence]
  finding-identity.sh anchor          --excerpt <text> [--heading-path <text>] [--in-fence]
  finding-identity.sh anchor          --whole
  finding-identity.sh finding-id      --check <id> --claim <id> --site <surface>=<anchor> ...
  finding-identity.sh group-id        --check <id> --claim <id>
  finding-identity.sh validate-record --record <json-line>

Exit 2 is a usage error. Exit 4 is validate-record's verdict that the record
violates §1 and must not be appended.
EOF
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    printf 'MISSING-SHA256'
  fi
}

sha256_string() { printf '%s' "$1" | sha256_stdin; }

require_sha256() {
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    die "no sha256 implementation found (need sha256sum or shasum)"
  fi
}

# Normalization, v1. Case is PRESERVED, because these surfaces carry code and
# identifiers.
#
#   1. strip trailing whitespace; collapse internal whitespace runs to one space
#   2. strip surrounding markdown emphasis markers
#   3. PRESERVE backticks and the text they delimit — stripping them would
#      normalize `@README` to @README, so literal text quoted AS AN EXAMPLE of
#      an import would hash identically to a real import
#   4. strip block-level HTML comments OUTSIDE a fenced code block; inside a
#      fence they are content and are kept, which is what --in-fence declares
normalize_v1() {
  local text="$1" in_fence="$2"

  if [[ "$in_fence" -eq 0 ]]; then
    # Non-greedy removal of every <!-- ... --> span, including one spanning
    # newlines. Done before whitespace collapsing so a comment's own spacing
    # cannot survive as a gap.
    while [[ "$text" == *"<!--"*"-->"* ]]; do
      local head tail
      head="${text%%<!--*}"
      tail="${text#*<!--}"
      tail="${tail#*-->}"
      text="${head}${tail}"
    done
  fi

  # Collapse every whitespace run (spaces, tabs, newlines) to one space, then
  # trim the ends.
  text="$(printf '%s' "$text" | tr '\n\t' '  ' | tr -s ' ')"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"

  # Strip SURROUNDING emphasis markers only, longest first, repeatedly: `***x***`
  # reduces through `**x**` to `x`. An emphasis marker in the middle of the
  # excerpt is content and stays.
  local changed=1
  while [[ "$changed" -eq 1 ]]; do
    changed=0
    local marker
    for marker in '***' '___' '**' '__' '*' '_'; do
      local n=${#marker}
      if [[ ${#text} -gt $((2 * n)) && "${text:0:n}" == "$marker" && "${text: -n}" == "$marker" ]]; then
        text="${text:n:${#text}-2*n}"
        changed=1
        break
      fi
    done
  done

  printf '%s' "$text"
}

cmd_normalize() {
  local excerpt="" in_fence=0 have=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --excerpt)
      [[ $# -ge 2 ]] || die "--excerpt needs a value"
      excerpt="$2"
      have=1
      shift 2
      ;;
    --in-fence)
      in_fence=1
      shift
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ "$have" -eq 1 ]] || die "--excerpt is required"
  normalize_v1 "$excerpt" "$in_fence"
  printf '\n'
}

cmd_anchor() {
  local excerpt="" heading="" whole=0 in_fence=0 have=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --excerpt)
      [[ $# -ge 2 ]] || die "--excerpt needs a value"
      excerpt="$2"
      have=1
      shift 2
      ;;
    --heading-path)
      [[ $# -ge 2 ]] || die "--heading-path needs a value"
      heading="$2"
      shift 2
      ;;
    --whole)
      whole=1
      shift
      ;;
    --in-fence)
      in_fence=1
      shift
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done

  if [[ "$whole" -eq 1 ]]; then
    [[ "$have" -eq 0 ]] || die "--whole takes no --excerpt: a whole-surface anchor is content-free"
    # Bare `s:`, no digest. A finding about a file AS A WHOLE must not be
    # retired by editing a line inside it.
    printf 's:\n'
    return 0
  fi

  [[ "$have" -eq 1 ]] || die "--excerpt is required unless --whole"
  require_sha256

  local normalized excerpt_hash disc
  normalized="$(normalize_v1 "$excerpt" "$in_fence")"
  excerpt_hash="$(sha256_string "$normalized")"
  excerpt_hash="${excerpt_hash:0:12}"

  if [[ -z "$heading" ]]; then
    # The fixed sentinel for a surface with no heading structure above the
    # excerpt, or no heading concept at all (a prompt-type hook in JSON).
    # Piped, never command-substituted: a shell drops a NUL byte out of `$( )`,
    # which would silently turn the sentinel into the hash of an EMPTY string
    # and collide with an excerpt under an empty heading path.
    disc="$(printf '\x00' | sha256_stdin)"
  else
    disc="$(sha256_string "$(normalize_v1 "$heading" 0)")"
  fi
  disc="${disc:0:8}"

  printf 'e:%s:%s\n' "$excerpt_hash" "$disc"
}

# `sites` is a SET, canonically sorted by the byte ordering of
# `surface 0x1F anchor`, because an ordered pair hashes X-versus-Y differently
# from Y-versus-X and the same conflict would then be reported twice.
sorted_site_fields() {
  local site surface anchor
  for site in "$@"; do
    surface="${site%%=*}"
    anchor="${site#*=}"
    if [[ "$surface" == "$site" ]]; then
      die "--site must be <surface>=<anchor>: $site"
    fi
    [[ -n "$surface" ]] || die "--site has an empty surface: $site"
    [[ -n "$anchor" ]] || die "--site has an empty anchor: $site"
    printf '%s%s%s\n' "$surface" "$US" "$anchor"
  done | LC_ALL=C sort
}

cmd_finding_id() {
  local check="" claim="" sites=() arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --check)
      [[ $# -ge 2 ]] || die "--check needs a value"
      check="$2"
      shift 2
      ;;
    --claim)
      [[ $# -ge 2 ]] || die "--claim needs a value"
      claim="$2"
      shift 2
      ;;
    --site)
      [[ $# -ge 2 ]] || die "--site needs a value"
      sites+=("$2")
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$check" ]] || die "--check is required"
  [[ -n "$claim" ]] || die "--claim is required"
  [[ ${#sites[@]} -ge 1 ]] || die "at least one --site is required"
  require_sha256

  # Validated HERE rather than inside sorted_site_fields: that runs in a
  # pipeline and a process substitution, where a `die` exits only the subshell
  # and this function would hash a body built from nothing. A refusal that does
  # not reach the exit code is not one.
  local site surface anchor
  for site in "${sites[@]}"; do
    surface="${site%%=*}"
    anchor="${site#*=}"
    [[ "$surface" != "$site" ]] || die "--site must be <surface>=<anchor>: $site"
    [[ -n "$surface" ]] || die "--site has an empty surface: $site"
    [[ -n "$anchor" ]] || die "--site has an empty anchor: $site"
  done

  local body line
  body="${check}${US}${claim}"
  while IFS= read -r line; do
    body="${body}${US}${line}"
  done < <(sorted_site_fields "${sites[@]}")

  local full
  full="$(sha256_string "$body")"
  printf '%s\n' "${full:0:16}"
}

cmd_group_id() {
  local check="" claim="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --check)
      [[ $# -ge 2 ]] || die "--check needs a value"
      check="$2"
      shift 2
      ;;
    --claim)
      [[ $# -ge 2 ]] || die "--claim needs a value"
      claim="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$check" ]] || die "--check is required"
  [[ -n "$claim" ]] || die "--claim is required"
  require_sha256

  local full
  full="$(sha256_string "${check}${US}${claim}")"
  printf 'g:%s\n' "${full:0:16}"
}

# The emitter guard. Refusals print one line naming the violated rule, so the
# lane that produced the record can be fixed rather than the record patched.
cmd_validate_record() {
  local record="" have=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --record)
      [[ $# -ge 2 ]] || die "--record needs a value"
      record="$2"
      have=1
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ "$have" -eq 1 ]] || die "--record is required"
  command -v python3 >/dev/null 2>&1 ||
    die "validate-record needs python3 for a definitive JSON parse"
  require_sha256

  local out rc=0
  # The record reaches python through the environment rather than through the
  # command line, so a record containing a quote, a backtick, or a `$(` is data
  # in both hops and never text a shell re-parses.
  out=$(
    FI_RECORD="$record" python3 - <<'PY'
import hashlib
import json
import os
import sys

US = "\x1f"
raw = os.environ["FI_RECORD"]


def reject(msg):
    print("invalid: " + msg)
    sys.exit(4)


if "\n" in raw.strip("\n"):
    reject("a record must be a single line")
try:
    rec = json.loads(raw)
except Exception as exc:  # a parse failure is the record's defect, not ours
    reject("not well-formed JSON: %s" % exc)
if not isinstance(rec, dict):
    reject("a record must be a JSON object")

kind = rec.get("record")
if kind != "finding":
    # Notes, start records, terminators and supersession records are validated
    # against their own shapes elsewhere. A note in particular carries a
    # `note_id` and NO identity block, and giving it one would put a tier that
    # is excluded from D(R) into the shape identity sets are built from.
    if kind == "note":
        if "identity" in rec:
            reject("a note carries no identity block")
        if not rec.get("note_id"):
            reject("a note requires a note_id")
    print("ok")
    sys.exit(0)

if "identity" not in rec or rec["identity"] is None:
    reject("a finding record requires an identity block; identity was absent or null")
identity = rec["identity"]
if not isinstance(identity, dict):
    reject("identity must be an object")

check = identity.get("check")
claim = identity.get("claim")
if not isinstance(check, str) or not check.strip():
    reject("identity.check is required")
if not isinstance(claim, str) or not claim.strip():
    reject("identity.claim is required")
# A claim is the check's canonical claim id plus bound parameters, never free
# prose. Prose is a rendering of the claim, never the claim itself.
if " " in claim.strip() or len(claim) > 200:
    reject("identity.claim looks like free prose rather than a claim id: %r" % claim)

sites = identity.get("sites")
if not isinstance(sites, list) or not sites:
    reject("identity.sites must be a non-empty array")
if len(sites) > 2:
    reject(
        "a finding carries one site, or two for a pairwise claim; %d sites means the "
        "lane did not split independently correctable occurrences" % len(sites)
    )

pairwise = bool(identity.get("pairwise", False))
if len(sites) == 2 and not pairwise:
    reject("two sites require identity.pairwise true; otherwise split them per site")
if len(sites) == 1 and pairwise:
    reject("identity.pairwise asserts a relation between two sites, but one site was given")

pairs = []
for site in sites:
    if not isinstance(site, dict):
        reject("each site must be an object with surface and anchor")
    surface = site.get("surface")
    anchor = site.get("anchor")
    if not isinstance(surface, str) or not surface:
        reject("each site requires a surface")
    if not isinstance(anchor, str) or not anchor:
        reject("each site requires an anchor")
    if anchor.startswith("s:") and len(sites) == 2:
        reject("an s: anchor in a two-site finding is a hard error (1.6)")
    if not (anchor == "s:" or anchor.startswith("e:")):
        reject("an anchor is `s:` or `e:<12hex>:<8hex>`: %r" % anchor)
    pairs.append(surface + US + anchor)

body = US.join([check, claim] + sorted(pairs))
derived = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]

stored = rec.get("finding_id/v1")
if not stored:
    reject("a finding record requires finding_id/v1")
if stored != derived:
    reject(
        "finding_id/v1 disagrees with its own constituents: stored %s, derived %s"
        % (stored, derived)
    )

group = rec.get("group")
if group is not None:
    gbody = check + US + claim
    gderived = "g:" + hashlib.sha256(gbody.encode("utf-8")).hexdigest()[:16]
    if group != gderived:
        reject("group disagrees with group/v1 over check and claim: %s vs %s" % (group, gderived))

print("ok")
PY
  ) || rc=$?

  if [[ "$rc" -eq 4 ]]; then
    printf '%s: %s\n' "$PROG" "$out" >&2
    exit "$EXIT_INVALID_RECORD"
  fi
  if [[ "$rc" -ne 0 ]]; then
    die "validate-record failed to run: $out"
  fi
  printf '%s\n' "$out"
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 2
  }
  local cmd="$1"
  shift
  case "$cmd" in
  normalize) cmd_normalize "$@" ;;
  anchor) cmd_anchor "$@" ;;
  finding-id) cmd_finding_id "$@" ;;
  group-id) cmd_group_id "$@" ;;
  validate-record) cmd_validate_record "$@" ;;
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
