#!/usr/bin/env bash
# Tamper-evidence for evidence-packet files.
#
# Packet files are written with the Write tool, and any sibling plugin that
# registers a `PostToolUse` hook on the `Write|Edit` matcher post-processes
# every one of them: PostToolUse runs after a tool call succeeds and may rewrite
# content (https://code.claude.com/docs/en/hooks, fetched 2026-08-10), and the
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
#   ACKNOWLEDGED DIVERGENCE — `record --acknowledge-divergence` never replaces
#   `packet.sha256`: verify keeps reporting the original divergence as CHANGED
#   (exit 1). It writes `packet.sha256.<N>` (N starts at 2), a manifest of the
#   bytes as they are now, so notes added afterwards can be sealed. verify reads
#   `packet.sha256` exactly as before and also every entry of the LATEST
#   generation (highest N by numeric value), labeled GEN-MATCH / GEN-CHANGED /
#   GEN-MISSING, so a second edit of an already-diverged file is still caught.
#   A file in neither manifest is UNSEALED. Once a generation exists an ordinary
#   `record` is refused (it would launder the acknowledged divergence), and
#   `record --acknowledge-divergence` writes the next generation, also after the
#   altered file was restored. It names (GEN-MISSING) any file the previous
#   generation sealed that is now gone, because the next generation stops
#   listing it.
#
#   With a generation, verify prints `ACKNOWLEDGED generation=<N>` on every run,
#   including when a restore made every digest match and the exit is 0: verify
#   reports what the bytes are, and the visible line, not a permanent nonzero
#   exit, keeps the incident in front of a reader.
#
#   NOT COVERED — the FIRST in-place rewrite. PostToolUse runs after the write
#   succeeds, so by the time any subsequent tool call can hash the file, the
#   formatter has already run; the digest necessarily covers the post-hook bytes.
#   The writer's read-back (see the skill's write-once rule) is what catches
#   that one, not this script.
#
# Usage:
#   bash packet-seal.sh record <packet-dir>
#   bash packet-seal.sh record --acknowledge-divergence <packet-dir>
#   bash packet-seal.sh verify <packet-dir>
#   bash packet-seal.sh --help
#
# The manifest is `packet.sha256` inside the packet directory: a first line
# `# sealed-at <UTC ISO-8601>`, then `<digest>  <name>` lines (the coreutils
# format), one per non-manifest regular file anywhere under the packet, named by
# its path RELATIVE to the packet. Coverage is recursive on purpose: a packet
# holds raw artifacts as well as the markdown files, and content the manifest
# silently said nothing about is exactly the content a reader would trust on the
# strength of a manifest that never covered it. The manifest's own name is
# outside the .md class, so neither known sibling formatter matches it
# (markdown-format filters to `*.md|*.mdc`; typos leaves a hex digest alone).
#
# SEAL MOMENT — `record` writes the `# sealed-at` line, and so does each
# generation manifest, so a later reader can tell how old a seal is. The value
# is SELF-ATTESTED: this script wrote it from the local clock, it is unsigned,
# and anyone who can write the manifest can edit it. It says when the packet
# claims to have been sealed, not proof of when it was. Every reader of a
# manifest here skips lines starting with `#`; a real entry starts with a hex
# digest, so the two cannot clash. A manifest written before the header existed
# has no seal moment and verifies as before, reporting `unknown`. The reverse
# fails closed: a verify from a version of this script older than the header
# reads that line as a sealed name, reports it MISSING, and exits 1. That is
# loud, not silent, and acceptable.
#
# Output (stdout, greppable): per-file `<verdict> <name>` lines for verify
# (MATCH / CHANGED / MISSING, then GEN-MATCH / GEN-CHANGED / GEN-MISSING for the
# latest generation, then UNSEALED), `ACKNOWLEDGED generation=<N>` when a
# generation exists, `sealed-at=<value>` (`unknown` without a header) and, when
# a generation exists, `gen-sealed-at=<value>` for the latest generation, then a
# summary line that gains gen-matched / gen-changed / gen-missing counters only
# when a generation exists. The seal moment never changes an exit code.
#
# Exit 0 = recorded, or verified with every manifest entry (and every entry of
#          the latest generation) matching and nothing unsealed. NOT a claim the content is pristine — only that nothing
#          changed since the seal; a rewrite before the first seal is invisible
#          to any digest and is the read-back's job, not this script's.
# Exit 1 = verify found at least one CHANGED, MISSING, GEN-CHANGED or GEN-MISSING
#          file (altered evidence), or `record` refused to reseal over an
#          already-divergent file or once a generation exists.
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
# symlinks are adjudicated per entry where the manifest is built.
packet_files() {
  local root="$1"
  (cd "$root" && find . ! -type d 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
}

# GNU coreutils ships sha256sum; macOS ships shasum. Probed once: the answer
# cannot change mid-run, and the refusal below reads the same probe.
if command -v sha256sum >/dev/null 2>&1; then
  digest_tool=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  digest_tool=shasum
else
  digest_tool=""
fi

# Emits the bare hex digest. Fails closed when no digest tool was found.
digest_of() {
  case "$digest_tool" in
  sha256sum) sha256sum -- "$1" 2>/dev/null | awk '{print $1}' ;;
  shasum) shasum -a 256 -- "$1" 2>/dev/null | awk '{print $1}' ;;
  *) return 2 ;;
  esac
}

# The original manifest, or a generation manifest `packet.sha256.<digits>`.
is_manifest_name() {
  [[ "$1" == "$MANIFEST_NAME" || "$1" =~ ^packet\.sha256\.[0-9]+$ ]]
}

# The first line of every manifest this script writes: the self-attested seal
# moment (see the header comment). `date -u` with this format is the same on
# GNU and BSD.
seal_header() {
  printf '# sealed-at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# The seal moment a manifest states, or `unknown` when its first line is not a
# `# sealed-at` header (a manifest written before the header existed).
seal_moment() {
  local moment
  moment="$(sed -n '1s/^# sealed-at \([^ ]*\).*/\1/p' "$1")"
  printf '%s' "${moment:-unknown}"
}

# The highest generation number in the packet, compared numerically (10 sorts
# after 9), or empty when there is none. `10#` keeps a leading zero from being
# read as octal.
latest_generation() {
  local f n latest=""
  for f in "$1"/packet.sha256.*; do
    n="${f##*/packet.sha256.}"
    [[ "$n" =~ ^[0-9]+$ && -f "$f" ]] || continue
    if [[ -z "$latest" ]] || ((10#$n > 10#$latest)); then
      latest="$n"
    fi
  done
  printf '%s' "$latest"
}

# note_divergence <manifest> <label> [<missing-label>]: prints `<label> <name>`
# for each entry whose file still exists with different bytes, and adds each to
# `relaundered`. A missing file is skipped unless <missing-label> is given: the
# original manifest reports it as MISSING on every verify, but a new generation
# stops listing it, so acknowledging one is the last time it is named.
note_divergence() {
  local line prev_digest prev_name now_digest
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != "#"* ]] || continue
    prev_digest="${line%% *}"
    prev_name="${line#* }"
    prev_name="${prev_name# }"
    if [[ ! -e "$packet/$prev_name" ]]; then
      if [[ -n "${3:-}" ]]; then
        echo "$3 $prev_name"
        relaundered=$((relaundered + 1))
      fi
      continue
    fi
    now_digest="$(digest_of "$packet/$prev_name")" || continue
    if [[ "$now_digest" != "$prev_digest" ]]; then
      echo "$2 $prev_name"
      relaundered=$((relaundered + 1))
    fi
  done <"$1"
}

[[ -n "$digest_tool" ]] || {
  case "${1:-}" in
  --help | -h) ;;
  *)
    echo "error: neither sha256sum nor shasum is available — cannot seal or verify" >&2
    exit 2
    ;;
  esac
}

action="${1:-}"
acknowledge=0
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

if [[ "${2:-}" == "--acknowledge-divergence" ]]; then
  if [[ "$action" != record ]]; then
    echo "error: --acknowledge-divergence is only valid with record" >&2
    exit 2
  fi
  acknowledge=1
  packet="${3:-}"
  [[ $# -le 3 ]] || {
    echo "error: unexpected extra argument: $4" >&2
    exit 2
  }
else
  packet="${2:-}"
  [[ $# -le 2 ]] || {
    echo "error: unexpected extra argument: $3" >&2
    exit 2
  }
fi
[[ -n "$packet" ]] || {
  echo "error: $action needs a packet directory" >&2
  exit 2
}
[[ -d "$packet" ]] || {
  echo "error: not a directory: $packet" >&2
  exit 2
}

manifest="$packet/$MANIFEST_NAME"

if [[ "$action" == record ]]; then
  # Enumerate BEFORE creating the temp manifest: a temp file inside the packet
  # is itself a packet file, and a walk that sees it would seal the manifest
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
  # An acknowledged divergence is permanent: once a generation manifest exists,
  # an ordinary reseal is refused even if the altered bytes were restored.
  # Later notes are sealed into the next generation instead.
  latest="$(latest_generation "$packet")"
  if [[ "$acknowledge" -eq 0 && -n "$latest" ]]; then
    echo "error: this packet has an acknowledged divergence (packet.sha256.$latest exists) — refusing to reseal packet.sha256" >&2
    echo "       later notes are sealed into a generation: record --acknowledge-divergence writes the next one, and verify reads the latest." >&2
    exit 1
  fi
  if [[ -f "$manifest" ]]; then
    relaundered=0
    note_divergence "$manifest" CHANGED
    [[ -z "$latest" ]] || note_divergence "$packet/packet.sha256.$latest" GEN-CHANGED GEN-MISSING
    # With a generation in place nothing has to differ: restoring the altered
    # bytes and then adding notes leaves only notes to seal, and they belong in
    # the next generation. Without one, acknowledging needs a divergence.
    if [[ "$relaundered" -gt 0 || -n "$latest" ]]; then
      if [[ "$acknowledge" -eq 0 ]]; then
        echo "error: $relaundered already-sealed file(s) differ from the existing manifest — refusing to reseal" >&2
        echo "       resealing would overwrite the evidence of that divergence with a digest of the altered bytes." >&2
        echo "       The original manifest is left in place and verify keeps reporting CHANGED against it." >&2
        echo "       Treat the named files as altered evidence; record the divergence in a NEW packet file." >&2
        echo "       record --acknowledge-divergence writes packet.sha256.N and does not overwrite packet.sha256:" >&2
        echo "       later notes are sealed into that generation, and verify reads the latest one." >&2
        exit 1
      fi
      # A generation manifest seals the bytes as they are now. packet.sha256
      # stays the record of the divergence. Generation files are not themselves
      # packet content: verify of the original still reports CHANGED, and a
      # generation is not a clean bill of health for the first seal.
      generation=$((10#${latest:-1} + 1))
      while [[ -e "$packet/packet.sha256.$generation" ]]; do
        generation=$((generation + 1))
      done
      gen_manifest="$packet/packet.sha256.$generation"
      gen_tmp="$gen_manifest.tmp.$$"
      seal_header >"$gen_tmp" || {
        echo "error: cannot write the generation manifest in: $packet" >&2
        exit 2
      }
      for name in ${files[@]+"${files[@]}"}; do
        ! is_manifest_name "$name" || continue
        file="$packet/$name"
        if [[ -L "$file" ]]; then
          rm -f -- "$gen_tmp"
          echo "error: packet entry is a symlink: $name" >&2
          exit 2
        fi
        d="$(digest_of "$file")" || {
          rm -f -- "$gen_tmp"
          echo "error: cannot digest: $file" >&2
          exit 2
        }
        printf '%s  %s\n' "$d" "$name" >>"$gen_tmp"
      done
      mv -f -- "$gen_tmp" "$gen_manifest" || {
        rm -f -- "$gen_tmp"
        echo "error: cannot install the generation manifest: $gen_manifest" >&2
        exit 2
      }
      echo "acknowledged=$relaundered generation=$generation manifest=$gen_manifest original-preserved=$manifest"
      exit 0
    fi
  fi
  if [[ "$acknowledge" -eq 1 ]]; then
    if [[ ! -f "$manifest" ]]; then
      echo "error: --acknowledge-divergence needs an existing packet.sha256" >&2
    else
      echo "error: no divergence to acknowledge; packet.sha256 already matches the packet" >&2
    fi
    exit 2
  fi

  tmp="$manifest.tmp.$$"
  seal_header >"$tmp" || {
    echo "error: cannot write the manifest in: $packet" >&2
    exit 2
  }
  # A packet entry is never allowed to be a symlink. The rule is "no symlinks",
  # not "no symlinks that escape", deliberately. An evidence packet is written by
  # Write-tool calls and never legitimately contains a link, so the permissive
  # case buys nothing — while resolving a link's real target portably needs
  # `readlink -f`, which is GNU-only and silently absent on BSD userland, exactly
  # where a resolution bug would go unnoticed. Refusing the whole class is
  # simpler, portable, and fails closed: a link's bytes are not the packet's,
  # they can change with nothing in the packet changing, and digesting one would
  # let a link inside an evidence directory make an arbitrary file on the machine
  # read as sealed packet content.
  for name in ${files[@]+"${files[@]}"}; do
    file="$packet/$name"
    if [[ -L "$file" ]]; then
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
  done
  mv -f -- "$tmp" "$manifest" || {
    rm -f -- "$tmp"
    echo "error: cannot install the manifest: $manifest" >&2
    exit 2
  }
  echo "sealed=${#files[@]} manifest=$manifest"
  exit 0
fi

# verify
[[ -f "$manifest" ]] || {
  echo "error: no $MANIFEST_NAME in $packet — nothing was sealed, so nothing can be verified" >&2
  exit 2
}

unsealed=0
sealed_names=()

# verify_manifest <manifest> <label-prefix>: a sealed name that no longer
# matches, or is gone entirely. Every name read joins sealed_names, and the
# tallies land in v_matched / v_changed / v_missing.
verify_manifest() {
  local line expected name file actual
  v_matched=0
  v_changed=0
  v_missing=0
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != "#"* ]] || continue
    expected="${line%% *}"
    name="${line#* }"
    name="${name# }"
    sealed_names+=("$name")
    file="$packet/$name"
    if [[ ! -f "$file" ]]; then
      echo "$2MISSING $name"
      v_missing=$((v_missing + 1))
      continue
    fi
    actual="$(digest_of "$file")" || {
      echo "error: cannot digest: $file" >&2
      exit 2
    }
    if [[ "$actual" == "$expected" ]]; then
      echo "$2MATCH $name"
      v_matched=$((v_matched + 1))
    else
      echo "$2CHANGED $name"
      v_changed=$((v_changed + 1))
    fi
  done <"$1"
}

# packet.sha256 is graded exactly as before. The latest generation, if any, is
# graded on top of it and never in place of it.
verify_manifest "$manifest" ""
matched=$v_matched
changed=$v_changed
missing=$v_missing

latest="$(latest_generation "$packet")"
if [[ -n "$latest" ]]; then
  echo "ACKNOWLEDGED generation=$latest"
  verify_manifest "$packet/packet.sha256.$latest" "GEN-"
  gen_matched=$v_matched
  gen_changed=$v_changed
  gen_missing=$v_missing
else
  gen_changed=0
  gen_missing=0
fi

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
  ! is_manifest_name "$name" || continue
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

echo "sealed-at=$(seal_moment "$manifest")"
[[ -z "$latest" ]] || echo "gen-sealed-at=$(seal_moment "$packet/packet.sha256.$latest")"

summary="matched=$matched changed=$changed missing=$missing unsealed=$unsealed"
if [[ -n "$latest" ]]; then
  summary="$summary gen-matched=$gen_matched gen-changed=$gen_changed gen-missing=$gen_missing"
fi
echo "$summary"

# CHANGED/MISSING and UNSEALED are different facts and must not share an exit
# code. A packet routinely acquires files after its last seal — `contract.md` at
# step 4, `item.md` at step 6 — so collapsing them would make the ordinary
# interrupted-run packet, the exact case resume exists for, report as tampered
# evidence and get discarded. The GEN- verdicts count the same way: a generation
# entry that differs was altered after it was acknowledged.
if [[ $changed -gt 0 || $missing -gt 0 || $gen_changed -gt 0 || $gen_missing -gt 0 ]]; then
  echo "packet integrity: NOT INTACT — treat the differing files as altered evidence, not ground truth" >&2
  [[ $unsealed -eq 0 ]] || echo "packet integrity: additionally, $unsealed file(s) are outside the manifest" >&2
  exit 1
fi
if [[ $unsealed -gt 0 ]]; then
  echo "packet integrity: INCOMPLETE — every sealed file matches, but $unsealed file(s) were never sealed" >&2
  echo "       Unsealed is not altered: files added after the last seal land here. Their integrity is simply unknown." >&2
  exit 3
fi
if [[ -n "$latest" ]]; then
  echo "packet integrity: every digest matches, but generation $latest acknowledges a divergence — matching bytes do not undo it"
  exit 0
fi
echo "packet integrity: sealed files intact (a rewrite BEFORE the first seal is outside what this can detect)"
exit 0
