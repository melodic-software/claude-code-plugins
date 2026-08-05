#!/usr/bin/env bash
# Tamper-evidence for evidence-packet files.
#
# Packet files are written with the Write tool, and any sibling plugin that
# registers a `PostToolUse` hook on the `Write|Edit` matcher post-processes
# every one of them: PostToolUse runs after a tool call succeeds and may rewrite
# content (https://code.claude.com/docs/en/hooks, fetched 2026-07-31), and the
# matcher keys on the TOOL NAME, so nothing about the destination directory
# excludes a packet. Observed in this fleet: `typos-format` and
# `markdown-format` both register that matcher unconditionally and both rewrite
# in place, damaging exactly what a packet exists to preserve — verbatim
# quotations and code-span identifiers.
#
# The rewrite is silent WITH RESPECT TO THE ARTIFACT: it is announced only in
# the session, which is the context the packet exists to outlive. This script
# makes divergence visible to a later reader instead.
#
# What the digest does and does not cover (stated honestly, because a mechanism
# that overclaims is worse than none):
#
#   COVERED — every divergence after the LAST seal: a formatter re-run triggered
#   by a subsequent edit (their own notices state the autocorrect "has no
#   memory", so a hand-repair is rewritten again on the next edit), truncation,
#   or tampering. VERIFY turns all of those from silent into reported. "Last"
#   rather than "first" is exact, and `record` enforces the difference: it
#   refuses to reseal over an already-divergent file, because doing so would
#   replace the evidence of a rewrite with a digest of the rewritten bytes.
#
#   NOT COVERED — the FIRST in-place rewrite. PostToolUse runs after the write
#   succeeds, so by the time any subsequent tool call can hash the file, the
#   formatter has already run; the digest necessarily covers the post-hook bytes.
#   The writer's read-back (see the skill's write-once rule) is what catches
#   that one, not this script.
#
# Usage:
#   bash packet-seal.sh record <packet-dir>
#   bash packet-seal.sh verify <packet-dir>
#   bash packet-seal.sh --help
#
# The manifest is `packet.sha256` inside the packet directory, in the standard
# `<digest>  <name>` coreutils format, one line per non-manifest regular file
# anywhere under the packet, named by its path RELATIVE to the packet. Coverage
# is recursive on purpose: a packet holds raw artifacts as well as the markdown
# files, and content the manifest silently said nothing about is exactly the
# content a reader would trust on the strength of a manifest that never covered
# it. The manifest's own name is outside the .md class, so neither known sibling
# formatter matches it (markdown-format filters to `*.md|*.mdc`; typos leaves a
# hex digest alone).
#
# Output (stdout, greppable): per-file `<verdict> <name>` lines for verify
# (MATCH / CHANGED / MISSING / UNSEALED), then a summary line.
#
# Exit 0 = recorded, or verified with every manifest entry matching and nothing
#          unsealed. NOT a claim the content is pristine — only that nothing
#          changed since the seal; a rewrite before the first seal is invisible
#          to any digest and is the read-back's job, not this script's.
# Exit 1 = verify found at least one CHANGED or MISSING file (altered evidence),
#          or `record` refused to reseal over an already-divergent file.
# Exit 2 = usage error, unusable packet directory, no digest tool, or a packet
#          entry that is a symlink (never permitted). FAIL CLOSED: a packet this
#          script cannot grade never reports as intact.
# Exit 3 = verify found every sealed file matching but some file UNSEALED. A
#          distinct code on purpose: files legitimately arrive after the last
#          seal (`contract.md` at step 4, `item.md` at step 6), so this is
#          "integrity unknown for these", never "evidence was altered".

set -uo pipefail

MANIFEST_NAME="packet.sha256"

usage() {
  sed -n '/^# Tamper-evidence/,/^# Exit 3/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Every regular file under the packet, as a path relative to it, one per line,
# in a stable order. Recursive so raw artifacts in subdirectories are covered
# rather than silently outside the manifest.
# `! -type d` rather than `-type f`: a symlink is not a regular file, so a
# `-type f` walk cannot see one — an all-symlink packet enumerated as EMPTY and
# then verified as "intact", which is the worst possible answer from an
# integrity tool. Everything that is not a directory is now enumerated, and
# symlinks are adjudicated per entry by is_symlink below.
packet_files() {
  local root="$1"
  (cd "$root" && find . ! -type d 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
}

# True when <name> is a symlink. A packet entry is never allowed to be one.
#
# The rule is "no symlinks", not "no symlinks that escape", deliberately. An
# evidence packet is written by Write-tool calls and never legitimately contains
# a link, so the permissive case buys nothing — while resolving a link's real
# target portably needs `readlink -f`, which is GNU-only and silently absent on
# BSD userland, exactly where a resolution bug would go unnoticed. Refusing the
# whole class is simpler, portable, and fails closed: a link's bytes are not the
# packet's, they can change with nothing in the packet changing, and digesting
# one would let a link inside an evidence directory make an arbitrary file on
# the machine read as sealed packet content.
is_symlink() {
  [[ -L "$1/$2" ]]
}

# GNU coreutils ships sha256sum; macOS ships shasum. Emits `<digest>  <name>`.
digest_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$file" 2>/dev/null | awk '{print $1}'
  else
    return 2
  fi
}

command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || {
  case "${1:-}" in
  --help | -h) ;;
  *)
    echo "error: neither sha256sum nor shasum is available — cannot seal or verify" >&2
    exit 2
    ;;
  esac
}

action="${1:-}"
case "$action" in
--help | -h | "")
  usage
  exit 0
  ;;
record | verify) ;;
*)
  echo "error: unknown action: $action (expected 'record' or 'verify')" >&2
  exit 2
  ;;
esac

packet="${2:-}"
[[ -n "$packet" ]] || {
  echo "error: $action needs a packet directory" >&2
  exit 2
}
[[ -d "$packet" ]] || {
  echo "error: not a directory: $packet" >&2
  exit 2
}
[[ $# -le 2 ]] || {
  echo "error: unexpected extra argument: $3" >&2
  exit 2
}

manifest="$packet/$MANIFEST_NAME"

if [[ "$action" == record ]]; then
  count=0
  # Enumerate BEFORE creating the temp manifest: a temp file inside the packet
  # is itself a packet file, and a glob that walks it would seal the manifest
  # into itself under a name that vanishes on `mv`.
  files=()
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" != "$MANIFEST_NAME" ]] || continue
    files+=("$name")
  done < <(packet_files "$packet")

  # Re-sealing must not LAUNDER divergence. Overwriting the manifest blindly
  # would replace the digest of an already-altered file with a digest of its
  # altered bytes, converting a detectable rewrite into a clean bill of health —
  # the one outcome that makes this tool worse than useless. So an existing
  # manifest is verified first, and a changed entry stops the reseal.
  if [[ -f "$manifest" ]]; then
    relaundered=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      prev_digest="${line%% *}"
      prev_name="${line#* }"
      prev_name="${prev_name# }"
      [[ -e "$packet/$prev_name" ]] || continue
      now_digest="$(digest_of "$packet/$prev_name")" || continue
      if [[ "$now_digest" != "$prev_digest" ]]; then
        echo "CHANGED $prev_name"
        relaundered=$((relaundered + 1))
      fi
    done <"$manifest"
    if [[ "$relaundered" -gt 0 ]]; then
      echo "error: $relaundered already-sealed file(s) differ from the existing manifest — refusing to reseal" >&2
      echo "       resealing would overwrite the evidence of that divergence with a digest of the altered bytes." >&2
      echo "       Treat the named files as altered evidence; record the divergence in a NEW packet file." >&2
      exit 1
    fi
  fi

  tmp="$manifest.tmp.$$"
  : >"$tmp" || {
    echo "error: cannot write the manifest in: $packet" >&2
    exit 2
  }
  for name in ${files[@]+"${files[@]}"}; do
    file="$packet/$name"
    if is_symlink "$packet" "$name"; then
      rm -f -- "$tmp"
      echo "error: packet entry is a symlink: $name" >&2
      echo "       An evidence packet holds its own bytes; sealing a link would certify a file it does not own." >&2
      exit 2
    fi
    d="$(digest_of "$file")" || {
      rm -f -- "$tmp"
      echo "error: cannot digest: $file" >&2
      exit 2
    }
    printf '%s  %s\n' "$d" "$name" >>"$tmp"
    count=$((count + 1))
  done
  mv -f -- "$tmp" "$manifest" || {
    rm -f -- "$tmp"
    echo "error: cannot install the manifest: $manifest" >&2
    exit 2
  }
  echo "sealed=$count manifest=$manifest"
  exit 0
fi

# verify
[[ -f "$manifest" ]] || {
  echo "error: no $MANIFEST_NAME in $packet — nothing was sealed, so nothing can be verified" >&2
  exit 2
}

matched=0
changed=0
missing=0
unsealed=0
sealed_names=()

# A sealed name that no longer matches, or is gone entirely.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  expected="${line%% *}"
  name="${line#* }"
  name="${name# }"
  sealed_names+=("$name")
  file="$packet/$name"
  if [[ ! -f "$file" ]]; then
    echo "MISSING $name"
    missing=$((missing + 1))
    continue
  fi
  actual="$(digest_of "$file")" || {
    echo "error: cannot digest: $file" >&2
    exit 2
  }
  if [[ "$actual" == "$expected" ]]; then
    echo "MATCH $name"
    matched=$((matched + 1))
  else
    echo "CHANGED $name"
    changed=$((changed + 1))
  fi
done <"$manifest"

# A packet file that the manifest never covered. Reported, never ignored: an
# unsealed file is content a reader would otherwise trust on the strength of a
# manifest that says nothing about it.
#
# Compared as exact strings, never by grepping the name into a pattern: a
# filename is not a regex, and `audit-notes.md` as a pattern would also match
# `audit-notesXmd` — a false negative that reports unsealed content as covered,
# which is the one direction this check must never fail in.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  [[ "$name" != "$MANIFEST_NAME" ]] || continue
  found=0
  for sealed in ${sealed_names[@]+"${sealed_names[@]}"}; do
    if [[ "$sealed" == "$name" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "UNSEALED $name"
    unsealed=$((unsealed + 1))
  fi
done < <(packet_files "$packet")

echo "matched=$matched changed=$changed missing=$missing unsealed=$unsealed"

# CHANGED/MISSING and UNSEALED are different facts and must not share an exit
# code. A packet routinely acquires files after its last seal — `contract.md` at
# step 4, `item.md` at step 6 — so collapsing them would make the ordinary
# interrupted-run packet, the exact case resume exists for, report as tampered
# evidence and get discarded.
if [[ $changed -gt 0 || $missing -gt 0 ]]; then
  echo "packet integrity: NOT INTACT — treat the differing files as altered evidence, not ground truth" >&2
  [[ $unsealed -eq 0 ]] || echo "packet integrity: additionally, $unsealed file(s) are outside the manifest" >&2
  exit 1
fi
if [[ $unsealed -gt 0 ]]; then
  echo "packet integrity: INCOMPLETE — every sealed file matches, but $unsealed file(s) were never sealed" >&2
  echo "       Unsealed is not altered: files added after the last seal land here. Their integrity is simply unknown." >&2
  exit 3
fi
echo "packet integrity: sealed files intact (a rewrite BEFORE the first seal is outside what this can detect)"
exit 0
