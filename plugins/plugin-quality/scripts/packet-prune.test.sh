#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/packet-prune.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
test_helpers::contract_lane

OLD="19990101T000000Z"
NEW="$(date -u +%Y%m%dT%H%M%SZ)"

fresh_tree() {
  local root="$WORK/data/evidence"
  rm -rf "$WORK/data"
  mkdir -p "$root/sess-1/plugin-a-skill/$OLD" \
    "$root/sess-1/plugin-a-skill/$NEW" \
    "$root/sess-1/plugin-b-hook/$OLD" \
    "$root/sess-2/plugin-c/not-a-nonce"
  : >"$root/sess-1/plugin-a-skill/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-a-skill/$NEW/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/item.md"
  : >"$root/sess-2/plugin-c/not-a-nonce/audit-notes.md"
  printf '%s' "$root"
}

verdict_is() {
  local nonce="$1" expected="$2" label="$3" line actual=""
  while IFS= read -r line; do
    [[ "${line#* }" == *"/$nonce" ]] || continue
    actual="${line%% *}"
    break
  done <<<"$last_out"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label — expected $expected for $nonce, got '${actual:-<no line>}'"
  fi
}

root="$(fresh_tree)"
run 0 "bare invocation runs" --root "$root"
has "WOULD-DELETE" "old packet is reported as a would-delete"
has "(dry run" "dry run is announced"
if [[ -e "$root/sess-1/plugin-a-skill/$OLD/audit-notes.md" ]]; then
  pass "dry run deleted nothing"
else
  fail "dry run DELETED a packet — the default must never mutate"
fi

root="$(fresh_tree)"
run 0 "apply runs" --root "$root" --apply
has "RETAIN-ITEM" "a packet holding item.md is reported as retained"
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "an OLD packet holding item.md survives --apply"
else
  fail "--apply DELETED an unemitted item.md — the one thing retention must never destroy"
fi
if [[ ! -e "$root/sess-1/plugin-a-skill/$OLD" ]]; then
  pass "an old packet without item.md is deleted under --apply"
else
  fail "--apply did not delete an expired packet"
fi
if [[ -e "$root/sess-1/plugin-a-skill/$NEW/audit-notes.md" ]]; then
  pass "a packet inside the window survives --apply"
else
  fail "--apply deleted a packet inside the retention window"
fi

if [[ -e "$root/sess-2/plugin-c/not-a-nonce/audit-notes.md" ]]; then
  pass "a directory whose name is not a nonce is never deleted"
else
  fail "--apply deleted a directory it could not grade the age of"
fi
has "UNPARSABLE" "an ungradable directory is reported, not silently kept"

shaped="$WORK/shaped-not-real/evidence"
rm -rf "$WORK/shaped-not-real"
mkdir -p "$shaped/s/g/00000000T000000Z" "$shaped/s/g/20260231T000000Z" "$shaped/s/g/$OLD"
: >"$shaped/s/g/00000000T000000Z/audit-notes.md"
: >"$shaped/s/g/20260231T000000Z/audit-notes.md"
: >"$shaped/s/g/$OLD/audit-notes.md"
run 0 "apply runs over nonce-shaped non-dates" --root "$shaped" --apply
if [[ -e "$shaped/s/g/00000000T000000Z/audit-notes.md" ]]; then
  pass "an all-zero nonce survives --apply"
else
  fail "--apply DESTROYED 00000000T000000Z — a nonce-shaped non-date was graded as an ancient timestamp"
fi
if [[ -e "$shaped/s/g/20260231T000000Z/audit-notes.md" ]]; then
  pass "an impossible calendar day (Feb 31) survives --apply"
else
  fail "--apply DESTROYED 20260231T000000Z — a normalizing date parse graded a non-existent day"
fi
verdict_is "00000000T000000Z" UNPARSABLE "the all-zero nonce is reported UNPARSABLE, not DELETE"
verdict_is "20260231T000000Z" UNPARSABLE "the Feb-31 nonce is reported UNPARSABLE, not DELETE"
verdict_is "$OLD" DELETE "a real expired nonce is still reported DELETE"

shaped_dry="$WORK/shaped-dry/evidence"
rm -rf "$WORK/shaped-dry"
mkdir -p "$shaped_dry/s/g/00000000T000000Z"
: >"$shaped_dry/s/g/00000000T000000Z/audit-notes.md"
run 0 "dry run over a nonce-shaped non-date" --root "$shaped_dry"
verdict_is "00000000T000000Z" UNPARSABLE "a dry run grades the non-date UNPARSABLE, not WOULD-DELETE"

real="$WORK/real-nonces/evidence"
rm -rf "$WORK/real-nonces"
mkdir -p "$real/s/g/20240229T000000Z" "$real/s/g/19700101T000000Z" "$real/s/g/20991231T235959Z"
run 0 "dry run over legitimate calendar values" --root "$real"
verdict_is "20240229T000000Z" WOULD-DELETE "a leap day is graded as a real nonce"
verdict_is "19700101T000000Z" WOULD-DELETE "the epoch is graded as a real nonce"
verdict_is "20991231T235959Z" KEEP "a far-future nonce is graded as a real nonce"

stubdir="$WORK/stub-bin"
rm -rf "$stubdir"
mkdir -p "$stubdir"
cat >"$stubdir/date" <<'STUB'
#!/usr/bin/env bash
# Round-trip parses use `-d <YYYY-MM-DD HH:MM:SS>`; the probe and cutoff use
# relative forms ("N days ago"). Fail only the former.
for a in "$@"; do
  [[ "$a" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\  ]] && exit 7
done
exec /usr/bin/env -i PATH=/usr/bin:/bin date "$@"
STUB
chmod +x "$stubdir/date"
stub_root="$WORK/stub-tree/evidence"
rm -rf "$WORK/stub-tree"
mkdir -p "$stub_root/s/g/$OLD"
: >"$stub_root/s/g/$OLD/audit-notes.md"
last_out="$(PATH="$stubdir:$PATH" bash "$SUT" --root "$stub_root" --apply 2>&1)"
stub_rc=$?
if [[ "$stub_rc" -eq 2 ]]; then
  pass "a date that cannot round-trip is refused with exit 2 (stub exit $stub_rc)"
else
  fail "a broken date round-trip exited $stub_rc, not 2 — retention would silently no-op: $last_out"
fi
if [[ "$last_out" == *"cannot round-trip a known-good nonce"* ]]; then
  pass "the refusal names the real cause"
else
  fail "the broken-round-trip refusal did not name its cause — output: $last_out"
fi
if [[ -e "$stub_root/s/g/$OLD/audit-notes.md" ]]; then
  pass "nothing was deleted when age could not be graded"
else
  fail "a packet was deleted despite an ungradable date implementation"
fi
if [[ ! -e "$shaped/s/g/$OLD" ]]; then
  pass "a genuinely old nonce is still deleted under --apply"
else
  fail "the calendar check broke retention — a real expired packet was not deleted"
fi

sym_root="$WORK/symlink-case"
rm -rf "$sym_root"
mkdir -p "$sym_root/data/evidence" "$sym_root/outside/slug/$OLD"
: >"$sym_root/outside/slug/$OLD/evidence.md"
if ln -s "$sym_root/outside" "$sym_root/data/evidence/sess-link" 2>/dev/null &&
  [[ -L "$sym_root/data/evidence/sess-link" ]]; then
  run 0 "apply runs over a symlinked session directory" --root "$sym_root/data/evidence" --apply
  has "ESCAPED" "a candidate resolving outside the root is reported as escaped"
  if [[ -e "$sym_root/outside/slug/$OLD/evidence.md" ]]; then
    pass "nothing outside the evidence root was deleted"
  else
    fail "--apply DELETED a directory outside the evidence root via a symlink"
  fi
else
  echo "SKIP - symlink containment case (cannot create symlinks here; set MSYS=winsymlinks:nativestrict on Git Bash)"
fi

alias_root="$WORK/alias-item/evidence"
rm -rf "$WORK/alias-item"
mkdir -p "$alias_root/s/g/$OLD"
printf 'findings for the other plugin\n' >"$alias_root/s/g/$OLD/item-plugin-quality.md"
run 0 "apply runs with item-plugin-quality.md and no item.md" --root "$alias_root" --apply
has "RETAIN-ITEM" "a second-owner item file retains the packet"
if [[ -e "$alias_root/s/g/$OLD/item-plugin-quality.md" ]]; then
  pass "item-plugin-quality.md survives --apply"
else
  fail "--apply DELETED item-plugin-quality.md"
fi

nested="$WORK/nested-item/evidence"
rm -rf "$WORK/nested-item"
mkdir -p "$nested/s/g/$OLD/raw"
: >"$nested/s/g/$OLD/raw/item.md"
run 0 "apply runs with a nested item.md" --root "$nested" --apply
has "RETAIN-ITEM" "a deliverable one directory down still retains the packet"
if [[ -e "$nested/s/g/$OLD/raw/item.md" ]]; then
  pass "an item.md in a subdirectory survives --apply"
else
  fail "--apply DELETED a nested item.md — the deliverable guard must not be depth-limited"
fi

root="$(fresh_tree)"
run 0 "dry run for the summary check" --root "$root"
has "would-delete=" "a dry run reports would-delete="
if [[ "$last_out" != *"deleted="* ]]; then
  pass "a dry run never prints deleted="
else
  fail "a dry run printed deleted=, which a log reader cannot distinguish from a real delete"
fi

run 2 "an out-of-range --days is refused" --root "$(fresh_tree)" --days 999999999999
if [[ "$last_out" == *"did not yield a usable cutoff"* ]]; then
  pass "the overflow names the real cause"
else
  fail "the overflow was misdiagnosed — output: $last_out"
fi

mkdir -p "$WORK/not-evidence/sess/slug/$OLD"
run 2 "a root not named 'evidence' is refused" --root "$WORK/not-evidence"
has "refusing to prune" "the refusal names its reason"
if [[ -e "$WORK/not-evidence/sess/slug/$OLD" ]]; then
  pass "the refused root was not walked"
else
  fail "a refused root was still pruned"
fi

run 2 "a missing root is a usage error" --root "$WORK/no-such-dir"
run 2 "--root is required" --days 5
run 2 "a non-numeric --days is refused" --root "$(fresh_tree)" --days thirty
run 2 "an unknown argument is refused" --root "$(fresh_tree)" --wipe
run 0 "--help exits clean" --help

root="$(fresh_tree)"
run 0 "--days 0 runs" --root "$root" --days 0 --apply
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "item.md survives even at --days 0"
else
  fail "--days 0 destroyed an unemitted item.md"
fi

contract_report packet-prune.sh
