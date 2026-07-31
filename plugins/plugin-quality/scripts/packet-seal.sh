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
#   COVERED — every divergence after the seal: a formatter re-run triggered by a
#   subsequent edit (their own notices state the autocorrect "has no memory", so
#   a hand-repair is rewritten again on the next edit), truncation, or tampering.
#   VERIFY turns all of those from silent into reported.
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
# `<digest>  <name>` coreutils format, one line per non-manifest regular file at
# the top level of the packet. Its own name is outside the .md class, so neither
# known sibling formatter matches it (markdown-format filters to `*.md|*.mdc`;
# typos leaves a hex digest alone).
#
# Output (stdout, greppable): per-file `<verdict> <name>` lines for verify
# (MATCH / CHANGED / MISSING / UNSEALED), then a summary line.
#
# Exit 0 = recorded, or verified with every file matching.
# Exit 1 = verify found at least one CHANGED, MISSING, or UNSEALED file.
# Exit 2 = usage error, unusable packet directory, or no digest tool. FAIL
#          CLOSED: a packet this script cannot grade never reports as intact.

set -uo pipefail

MANIFEST_NAME="packet.sha256"

usage() {
  sed -n '/^# Tamper-evidence/,/^# Exit 2/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
  for file in "$packet"/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    [[ "$name" != "$MANIFEST_NAME" ]] || continue
    files+=("$file")
  done

  tmp="$manifest.tmp.$$"
  : >"$tmp" || {
    echo "error: cannot write the manifest in: $packet" >&2
    exit 2
  }
  for file in ${files[@]+"${files[@]}"}; do
    name="$(basename "$file")"
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
for file in "$packet"/*; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file")"
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
done

echo "matched=$matched changed=$changed missing=$missing unsealed=$unsealed"
if [[ $changed -gt 0 || $missing -gt 0 || $unsealed -gt 0 ]]; then
  echo "packet integrity: NOT INTACT — treat the differing files as altered evidence, not ground truth" >&2
  exit 1
fi
echo "packet integrity: intact"
exit 0
