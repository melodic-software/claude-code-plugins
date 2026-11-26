#!/usr/bin/env bash
# Exit: 0 every consumer matches the source, 1 drift or a stale registration,
# 2 usage or a prerequisite this gate cannot verify around.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="${LOOP_LANE_FLOOR_ROOT:-$SCRIPT_DIR/..}"
cd "$ROOT" || {
  echo "check-loop-lane-floor-drift: cannot enter root: $ROOT" >&2
  exit 2
}

if ! command -v git >/dev/null 2>&1; then
  echo "check-loop-lane-floor-drift: git not found; the repo-wide scan for unregistered copies cannot run" >&2
  exit 2
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-loop-lane-floor-drift: $ROOT is not inside a git work tree; the repo-wide scan for unregistered copies cannot run" >&2
  exit 2
fi

SOURCE="plugins/rate-limits/reference/reader-contract.md"

CONSUMERS=(
  "exact plugins/work-items/skills/work-loop/SKILL.md"
  "exact plugins/work-items/skills/attend-queue/SKILL.md"
  "exact plugins/source-control/skills/babysit-loop/SKILL.md"
  "exact plugins/source-control/skills/pull-request/reference/watch-handoff.md"
  "exact plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md"
  "values prompts/loops/loop-lane-prompts.md"
)

DATA_CARRIERS=(
  "scripts/check-loop-lane-floor-drift.test.sh this gate's own fixtures: abridged stand-in floor text, deliberately not the real values"
)

BULLETS=(
  "**Snapshot file (fixed path):**"
  "**Pause threshold (fixed):**"
  "**Pause end:**"
  "**Staleness rule:**"
  "**Drain-then-pause:**"
  "**Account switch:**"
)

MARKER='- **Snapshot file (fixed path):**'

MODE=check
case "${1-}" in
"" | --check) ;;
--list) MODE=list ;;
*)
  echo "usage: check-loop-lane-floor-drift.sh [--check|--list]" >&2
  exit 2
  ;;
esac

extract_block() {
  awk '
    index($0, marker) == 1 || index($0, "> " marker) == 1 { inblock = 1 }
    inblock {
      line = $0
      sub(/^>[[:blank:]]?/, "", line)
      if (line ~ /^[[:blank:]]*$/) { exit }
      print line
    }
  ' marker="$MARKER" "$1"
}

count_markers() {
  awk '
    index($0, marker) == 1 || index($0, "> " marker) == 1 { n++ }
    END { print n + 0 }
  ' marker="$MARKER" "$1"
}

discover_carriers() {
  local file
  while IFS= read -r -d '' file; do
    [[ "$(count_markers "$file")" != 0 ]] || continue
    printf '%s\n' "$file"
  done < <(git grep -I --name-only -z --fixed-strings -e "$MARKER" -- . 2>/dev/null)
}

carrier_exemption() {
  local candidate="$1" entry
  for entry in "${DATA_CARRIERS[@]}"; do
    if [[ "${entry%% *}" == "$candidate" ]]; then
      printf '%s\n' "${entry#* }"
      return 0
    fi
  done
  return 1
}

norm() {
  tr -d '`*' | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

if [[ ! -r "$SOURCE" ]]; then
  echo "check-loop-lane-floor-drift: source not readable: $SOURCE" >&2
  exit 2
fi

src_markers="$(count_markers "$SOURCE")"
if [[ "$src_markers" != 1 ]]; then
  echo "check-loop-lane-floor-drift: source $SOURCE opens the floor block $src_markers time(s); expected exactly 1" >&2
  exit 2
fi

SRC_BLOCK="$(extract_block "$SOURCE")"
if [[ -z "$SRC_BLOCK" ]]; then
  echo "check-loop-lane-floor-drift: extracted no floor block from $SOURCE; the marker no longer matches" >&2
  exit 2
fi
for bullet in "${BULLETS[@]}"; do
  if [[ "$SRC_BLOCK" != *"$bullet"* ]]; then
    echo "check-loop-lane-floor-drift: source block from $SOURCE is missing the '$bullet' bullet; refusing to compare against a block this gate did not recognize" >&2
    exit 2
  fi
done
SRC_NORM="$(printf '%s\n' "$SRC_BLOCK" | norm)"

CARRIERS="$(discover_carriers)"
if ! grep -Fxq "$SOURCE" <<<"$CARRIERS"; then
  echo "check-loop-lane-floor-drift: the repo-wide scan did not find $SOURCE, which carries the floor by definition; the scan is not working and its result cannot be believed" >&2
  exit 2
fi

is_registered() {
  local candidate="$1" entry
  for entry in "${CONSUMERS[@]}"; do
    [[ "${entry#* }" == "$candidate" ]] && return 0
  done
  return 1
}

if [[ "$MODE" == list ]]; then
  printf 'source  %s (%s lines)\n' "$SOURCE" "$(printf '%s\n' "$SRC_BLOCK" | wc -l | tr -d ' ')"
  for entry in "${CONSUMERS[@]}"; do
    printf 'consumer %-6s %s\n' "${entry%% *}" "${entry#* }"
  done
  carrier_count=0
  while IFS= read -r carrier; do
    [[ -n "$carrier" ]] || continue
    [[ "$carrier" != "$SOURCE" ]] || continue
    carrier_count=$((carrier_count + 1))
    if is_registered "$carrier"; then
      printf 'carrier registered   %s\n' "$carrier"
    elif reason="$(carrier_exemption "$carrier")"; then
      printf 'carrier exempt       %s (%s)\n' "$carrier" "${reason:-NO REASON GIVEN}"
    else
      printf 'carrier UNREGISTERED %s\n' "$carrier"
    fi
  done <<<"$CARRIERS"
  printf 'check-loop-lane-floor-drift: 1 source, %s registered consumer(s), %s tracked carrier(s) found by the repo-wide scan.\n' \
    "${#CONSUMERS[@]}" "$carrier_count"
  exit 0
fi

while IFS= read -r carrier; do
  [[ -n "$carrier" ]] || continue
  [[ "$carrier" != "$SOURCE" ]] || continue

  if reason="$(carrier_exemption "$carrier")"; then
    if is_registered "$carrier"; then
      report "CONTRADICTORY LISTING: $carrier is in CONSUMERS and in DATA_CARRIERS ($reason). A file is compared or excused, never both; drop one entry."
    fi
    continue
  fi

  is_registered "$carrier" ||
    report "UNREGISTERED COPY: $carrier inlines the operable floor but is not in this gate's registry. Add it to CONSUMERS in $(basename "$0") with its comparison mode (exact, or values for a re-wrapped blockquote); add it to DATA_CARRIERS there, with a reason, if it carries the marker as data; or remove the inlined block. A copy nothing watches is a copy the next contract change strands. Nothing written INSIDE the file exempts it: the exception list lives in the gate so a copy cannot quiet the gate itself."
done <<<"$CARRIERS"

for entry in "${DATA_CARRIERS[@]}"; do
  dc_path="${entry%% *}"
  if [[ ! -r "$dc_path" ]]; then
    report "STALE DATA CARRIER: $dc_path is listed in DATA_CARRIERS but is not readable. Remove the entry; an exemption must not outlive what it excuses."
  elif [[ "$(count_markers "$dc_path")" == 0 ]]; then
    report "STALE DATA CARRIER: $dc_path is listed in DATA_CARRIERS but no longer carries the floor marker. Remove the entry."
  fi
done

checked=0
for entry in "${CONSUMERS[@]}"; do
  mode="${entry%% *}"
  path="${entry#* }"

  if [[ ! -r "$path" ]]; then
    report "STALE REGISTRATION: $path is registered as a floor consumer but is not readable. Repoint or remove the entry; a registration matching no file enforces nothing."
    continue
  fi

  markers="$(count_markers "$path")"
  if [[ "$markers" == 0 ]]; then
    report "MISSING FLOOR: $path is registered as a floor consumer but no longer inlines the block. Restore the inlined floor, or drop the registration in the same change."
    continue
  fi
  if [[ "$markers" != 1 ]]; then
    report "AMBIGUOUS FLOOR: $path opens the floor block $markers times; this gate compares exactly one block per consumer."
    continue
  fi

  block="$(extract_block "$path")"
  if [[ -z "$block" ]]; then
    report "EMPTY FLOOR: $path matched the floor marker but yielded no block."
    continue
  fi

  checked=$((checked + 1))

  if [[ "$mode" == exact ]]; then
    if [[ "$block" == "$SRC_BLOCK" ]]; then
      continue
    fi
    report "DRIFT (exact): $path does not match the floor block in $SOURCE."
    diff -u <(printf '%s\n' "$SRC_BLOCK") <(printf '%s\n' "$block") |
      sed "s|^--- .*|--- $SOURCE|; s|^+++ .*|+++ $path|" >&2 || true
    continue
  fi

  if [[ "$(printf '%s\n' "$block" | norm)" == "$SRC_NORM" ]]; then
    continue
  fi
  report "DRIFT (values): $path does not match the floor block in $SOURCE after normalization."
  diff -u <(printf '%s\n' "$SRC_NORM" | tr ' ' '\n') \
    <(printf '%s\n' "$block" | norm | tr ' ' '\n') |
    sed "s|^--- .*|--- $SOURCE (normalized)|; s|^+++ .*|+++ $path (normalized)|" >&2 || true
done

if ((errors != 0)); then
  cat >&2 <<EOF

The rate-limits operable floor is inlined on purpose: an installed
plugin cannot read a sibling plugin's files at runtime, so every consumer
carries its own copy (docs/contracts/loop-lane/README.md section 6). The
values are DECIDED in one place only:

  $SOURCE

Every copy above has to move with it in the same change. Reconcile the copies
to the source, or change the source and every copy together. Do not hoist the
block into a shared file: the copies exist to survive plugin isolation.
EOF
  echo "check-loop-lane-floor-drift: $errors drifted or unresolvable consumer(s)" >&2
  exit 1
fi

carriers_found="$(printf '%s\n' "$CARRIERS" | grep -c . || true)"

for entry in "${DATA_CARRIERS[@]}"; do
  printf 'check-loop-lane-floor-drift: NOT COMPARED (data carrier): %s — %s\n' \
    "${entry%% *}" "${entry#* }"
done

printf 'check-loop-lane-floor-drift: %s consumer(s) match the operable floor in %s; the repo-wide scan found %s tracked carrier(s), %s excused as data carrier(s) above, and no unregistered copy.\n' \
  "$checked" "$SOURCE" "$((carriers_found - 1))" "${#DATA_CARRIERS[@]}"
exit 0
