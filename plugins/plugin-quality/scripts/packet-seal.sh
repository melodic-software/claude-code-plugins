#!/usr/bin/env bash
# Exit 0 = recorded, or verified with every manifest entry (and every entry of
#          the latest generation) matching and nothing unsealed. NOT a claim
#          the content is pristine, only that nothing changed since the seal;
#          a rewrite before the first seal is invisible to any digest and is
#          the read-back's job, not this script's.
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
  cat <<'EOF'
Tamper-evidence for evidence-packet files: seal a packet's files in packet.sha256, then verify them against it.

Usage:
  bash packet-seal.sh record <packet-dir>
  bash packet-seal.sh record --acknowledge-divergence <packet-dir>
  bash packet-seal.sh verify <packet-dir>
  bash packet-seal.sh --help

  record                    write packet.sha256; refused over a divergent file or once a generation exists
  --acknowledge-divergence  write the next generation manifest packet.sha256.<N> instead
  verify                    report MATCH / CHANGED / MISSING / GEN-* / UNSEALED per file
  --help                    print this help

Exit 0 = recorded, or every sealed file matches; 1 = a sealed file changed or is missing, or
record refused; 2 = usage error, unusable packet, no digest tool, or a symlink entry;
3 = every sealed file matches but some file is UNSEALED.
EOF
}

packet_files() {
  local root="$1"
  (cd "$root" && find . ! -type d 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
}

if command -v sha256sum >/dev/null 2>&1; then
  digest_tool=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  digest_tool=shasum
else
  digest_tool=""
fi

digest_of() {
  case "$digest_tool" in
  sha256sum) sha256sum -- "$1" 2>/dev/null | awk '{print $1}' ;;
  shasum) shasum -a 256 -- "$1" 2>/dev/null | awk '{print $1}' ;;
  *) return 2 ;;
  esac
}

is_manifest_name() {
  [[ "$1" == "$MANIFEST_NAME" || "$1" =~ ^packet\.sha256\.[0-9]+$ ]]
}

seal_header() {
  printf '# sealed-at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

seal_moment() {
  local moment
  moment="$(sed -n '1s/^# sealed-at \([^ ]*\).*/\1/p' "$1")"
  printf '%s' "${moment:-unknown}"
}

latest_generation() {
  local f n latest=""
  for f in "$1"/packet.sha256.*; do
    n="${f##*/packet.sha256.}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if [[ -L "$f" ]]; then
      echo "error: generation manifest is a symlink: packet.sha256.$n" >&2
      return 2
    fi
    [[ -f "$f" ]] || continue
    if [[ "$n" =~ ^0*[1-9][0-9]{18,}$ ]]; then
      echo "error: generation number is too large to read: packet.sha256.$n" >&2
      return 2
    fi
    if [[ -z "$latest" ]] || ((10#$n > 10#$latest)); then
      latest="$n"
    fi
  done
  printf '%s' "$latest"
}

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

write_manifest() {
  local dest="$1" kind="$2" tmp="$1.tmp.$$" name file d
  seal_header >"$tmp" || {
    echo "error: cannot write the $kind in: $packet" >&2
    exit 2
  }
  for name in ${files[@]+"${files[@]}"}; do
    [[ "$kind" == manifest ]] || ! is_manifest_name "$name" || continue
    file="$packet/$name"
    if [[ -L "$file" ]]; then
      rm -f -- "$tmp"
      echo "error: packet entry is a symlink: $name" >&2
      [[ "$kind" != manifest ]] || echo "       An evidence packet holds its own bytes; sealing a link would certify a file it does not own." >&2
      exit 2
    fi
    d="$(digest_of "$file")" || {
      rm -f -- "$tmp"
      echo "error: cannot digest: $file" >&2
      exit 2
    }
    printf '%s  %s\n' "$d" "$name" >>"$tmp"
  done
  mv -f -- "$tmp" "$dest" || {
    rm -f -- "$tmp"
    echo "error: cannot install the $kind: $dest" >&2
    exit 2
  }
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
  files=()
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" != "$MANIFEST_NAME" ]] || continue
    files+=("$name")
  done < <(packet_files "$packet")

  latest="$(latest_generation "$packet")" || exit 2
  if [[ "$acknowledge" -eq 0 && -n "$latest" ]]; then
    echo "error: this packet has an acknowledged divergence (packet.sha256.$latest exists) — refusing to reseal packet.sha256" >&2
    echo "       later notes are sealed into a generation: record --acknowledge-divergence writes the next one, and verify reads the latest." >&2
    exit 1
  fi
  if [[ -f "$manifest" ]]; then
    relaundered=0
    note_divergence "$manifest" CHANGED
    [[ -z "$latest" ]] || note_divergence "$packet/packet.sha256.$latest" GEN-CHANGED GEN-MISSING
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
      generation=$((10#${latest:-1} + 1))
      while [[ -e "$packet/packet.sha256.$generation" ]]; do
        generation=$((generation + 1))
      done
      gen_manifest="$packet/packet.sha256.$generation"
      write_manifest "$gen_manifest" "generation manifest"
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

  write_manifest "$manifest" manifest
  echo "sealed=${#files[@]} manifest=$manifest"
  exit 0
fi

[[ -f "$manifest" ]] || {
  echo "error: no $MANIFEST_NAME in $packet — nothing was sealed, so nothing can be verified" >&2
  exit 2
}

unsealed=0
sealed_names=()

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

verify_manifest "$manifest" ""
matched=$v_matched
changed=$v_changed
missing=$v_missing

latest="$(latest_generation "$packet")" || exit 2
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
