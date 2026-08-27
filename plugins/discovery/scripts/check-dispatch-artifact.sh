#!/usr/bin/env bash
# Deterministic acceptance gate for a dispatched /discovery:explore or
# /discovery:research run.
#
# The dispatched agent's return payload is a CLAIM about a run; this gate reads
# the run's actual output off disk instead. It takes the memory-slice path the
# PARENT resolved before dispatching — never a path read out of the payload —
# because the failure it exists to catch is a payload that arrives malformed,
# carrying no artifact pointer at all. A check that sources its own input from
# the suspect payload cannot see that failure.
#
# One gate serves both skills because they share one on-disk shape: an index
# plus section-keyed sidecars beside it, the same one-level sub-slice rule, and
# the same two placement rules (`skills/research/context/artifact-shape.md`).
# The part that differs between them is the sidecar YAML header — tiers and
# publishing pools for research, `verified: read | grep | inferred` for
# exploration — and this gate never reads a header. `--index-name` is therefore
# the whole difference, and it is REQUIRED rather than defaulted: a gate that
# fails closed everywhere else must not silently grade the wrong artifact
# family because a caller omitted a flag.
#
# Usage:
#   bash check-dispatch-artifact.sh <memory-slice-path> \
#     --index-name <EXPLORE.md|RESEARCH.md> \
#     [--newer-than <pre-dispatch baseline file>] \
#     [--expect-index <the payload's artifact: value>] \
#     [--expect-sidecars <the payload's sidecars: count>]
#   bash check-dispatch-artifact.sh --help
#
# What it checks, in order:
#   1. Exactly one <index-name> exists — at the slice root, or one level below
#      it in a sub-slice (the sanctioned collision path). Two is ambiguous: the
#      gate cannot tell which run this dispatch produced. For research that
#      ambiguity is also a REACHABLE END STATE — a parent fanning out over N
#      topics synthesizes a slice-root index from the sub-slice ones — so grade
#      each fan-out run against its own assigned sub-slice, before synthesis.
#   2. That index is non-empty.
#   3. It names at least one `<PREFIX>-<section>.md` sidecar, and every sidecar
#      it names exists beside it and is non-empty. A mid-stream stub passes a
#      bare non-empty test; it does not pass this one.
#   4. With --newer-than, the index is strictly newer than a file the parent
#      touched immediately BEFORE dispatching. Existence alone cannot tell this
#      run's artifact from one an earlier run left in the same slice, so without
#      a baseline a dispatch that wrote nothing can be accepted on stale
#      evidence and planning proceeds against an outdated snapshot.
#   5. With --expect-index, the pointer the payload returned resolves to the
#      same file this gate graded. A payload naming some OTHER path is not
#      corroborating this artifact, and its verification_request.target would
#      send the verifier at the wrong file.
#   6. With --expect-sidecars, the count the payload reported matches the count
#      the index actually names. Secondary: the payload is the suspect party.
#
# Checks 4-6 are opt-in, so each reports `unchecked` in the output line rather
# than passing silently — a skipped check that looks like a passed one is the
# same failure class this gate exists to refuse.
#
# Exit 0 = a usable artifact set is on disk (status=usable)
# Exit 1 = the slice is readable but its artifact set is NOT usable — no index,
#          an empty index, an index naming no sidecars, a named sidecar that is
#          missing or empty, an index no newer than the baseline, a payload
#          pointer naming a different file, or a sidecar-count mismatch
#          (status=unusable). The parent discards the run; it does not proceed.
# Exit 2 = the gate cannot grade — the slice path is missing, is not a
#          directory, holds more than one candidate index, or names a baseline
#          file that does not exist — plus usage errors, including a missing or
#          malformed `--index-name`. FAIL CLOSED: a slice this gate cannot read
#          is never reported as usable.
#
# What it deliberately does NOT check: the coverage ledger a bounded-corpus
# research run writes. `research-checklist.md` has its own gate
# (`check-coverage-complete.sh`), which grades the marks in its table rather
# than the presence of a file, and the research skill composes the two. Folding
# a ledger flag in here would put one caller's file into the shape-agnostic
# half of the pair.
#
# Output (stdout, greppable):
#   `index=<path> sidecars=<n> missing=<m> freshness=<newer|stale|unchecked>
#    pointer=<matches|mismatch|unchecked> status=<usable|unusable>`
#   (one line; wrapped here only for the comment width)
# On a failure the specific reason is named on stderr.

set -uo pipefail

usage() {
  # Sentinel range (not fixed line numbers) so the printed usage never silently
  # truncates when the header grows or shrinks on a future edit.
  sed -n '/^# Deterministic acceptance gate/,/^# Output/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

slice=""
index_name=""
expect_sidecars=""
newer_than=""
expect_index=""

# Resolve a path to its canonical directory plus its basename, so that two
# spellings of one file compare equal. Deliberately not `realpath`, which is not
# everywhere, and deliberately NOT resolving the basename itself — the question
# is which file the payload named, not what a symlink points at. A path whose
# directory does not exist is returned unchanged, which cannot match a real
# index, and mismatch is the correct verdict for a pointer into nowhere.
canonical() {
  local path="$1" dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s' "$(cd "$dir" && pwd -P)" "$base"
  else
    printf '%s' "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --index-name)
    if [[ $# -lt 2 ]]; then
      echo "error: --index-name requires an index filename (EXPLORE.md or RESEARCH.md)" >&2
      exit 2
    fi
    # The name is not just echoed — its stem becomes the sidecar-matching
    # pattern below, so it is constrained to characters that carry no meaning in
    # an ERE. A name with a `.` or a `*` in its stem would silently widen that
    # pattern and start counting files the run never wrote as sidecars.
    if [[ ! "$2" =~ ^[A-Za-z0-9_-]+\.md$ ]]; then
      echo "error: --index-name must be <NAME>.md with NAME in [A-Za-z0-9_-], got: $2" >&2
      exit 2
    fi
    index_name="$2"
    shift 2
    ;;
  --newer-than)
    if [[ $# -lt 2 ]]; then
      echo "error: --newer-than requires a baseline file path" >&2
      exit 2
    fi
    newer_than="$2"
    shift 2
    ;;
  --expect-index)
    if [[ $# -lt 2 ]]; then
      echo "error: --expect-index requires the payload's artifact: path" >&2
      exit 2
    fi
    expect_index="$2"
    shift 2
    ;;
  --expect-sidecars)
    if [[ $# -lt 2 ]]; then
      echo "error: --expect-sidecars requires a count" >&2
      exit 2
    fi
    if [[ ! "$2" =~ ^[0-9]+$ ]]; then
      echo "error: --expect-sidecars takes a non-negative integer, got: $2" >&2
      exit 2
    fi
    expect_sidecars="$2"
    shift 2
    ;;
  -*)
    echo "error: unknown argument: $1" >&2
    exit 2
    ;;
  *)
    if [[ -n "$slice" ]]; then
      echo "error: expected exactly one memory-slice path, got a second: $1" >&2
      exit 2
    fi
    slice="$1"
    shift
    ;;
  esac
done

if [[ -z "$slice" ]]; then
  echo "error: a memory-slice path is required" >&2
  exit 2
fi

# No default. The two artifact families this gate serves differ only in this
# name, so guessing one would grade a research slice against EXPLORE.md, find
# nothing, and report `unusable` for a run that in fact succeeded — or, worse,
# find an unrelated EXPLORE.md a prior exploration left in the same slice and
# report a research dispatch that wrote nothing as usable.
if [[ -z "$index_name" ]]; then
  echo "error: --index-name is required (EXPLORE.md or RESEARCH.md)" >&2
  exit 2
fi
sidecar_prefix="${index_name%.md}"

# A trailing slash would turn `$slice/$index_name` into a double-slashed path in
# every message this gate prints, and the printed path is what the parent acts
# on. Strip it, while leaving a bare `/` intact.
while [[ "$slice" == */ && "$slice" != "/" ]]; do
  slice="${slice%/}"
done

if [[ ! -d "$slice" ]]; then
  echo "error: memory slice not found or not a directory: $slice" >&2
  exit 2
fi

# A baseline that is not there makes freshness ungradeable, and the parent asked
# for it — so this is an envelope error (2), never a quiet downgrade to
# `freshness=unchecked`. Downgrading would turn the check the caller requested
# into one it only appeared to get.
if [[ -n "$newer_than" && ! -e "$newer_than" ]]; then
  echo "error: --newer-than baseline does not exist: $newer_than" >&2
  exit 2
fi

# Reported in every verdict line, so an opt-in check that did not run says so
# rather than looking like one that passed.
freshness="unchecked"
pointer="unchecked"

# verdict <index> <sidecars> <missing> <status>
verdict() {
  printf 'index=%s sidecars=%s missing=%s freshness=%s pointer=%s status=%s\n' \
    "$1" "$2" "$3" "$freshness" "$pointer" "$4"
}

# Candidate indexes: the slice root, plus exactly one level below it. One level
# is the whole sub-slice rule — an index deeper than that is not a placement
# this workflow sanctions, and globbing for it would start matching unrelated
# artifacts that happen to live under the slice.
#
# Each candidate is existence-tested rather than left to the glob. `nullglob`
# drops a PATTERN that matches nothing; it does nothing to a literal path with
# no wildcard in it, so `"$slice/$index_name"` would survive into the array as a
# path to a file that is not there — and a slice holding only a sub-slice index
# would then read as ambiguous.
candidates=()
if [[ -f "$slice/$index_name" ]]; then
  candidates+=("$slice/$index_name")
fi
shopt -s nullglob
for candidate in "$slice"/*/"$index_name"; do
  if [[ -f "$candidate" ]]; then
    candidates+=("$candidate")
  fi
done
shopt -u nullglob

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "unusable: no $index_name in $slice or in a sub-slice one level below it" >&2
  verdict "<none>" 0 0 unusable
  exit 1
fi

if [[ ${#candidates[@]} -gt 1 ]]; then
  # Ungradeable rather than unusable: one of these may well be a fine artifact,
  # but the gate cannot tell which one THIS dispatch wrote, and guessing is how
  # a prior run's artifact gets accepted as evidence that a failed run
  # succeeded. The parent assigns sub-slices, so it can disambiguate and re-run
  # this gate against the specific one.
  #
  # On the research side this is also what a COMPLETED fan-out looks like from
  # the slice root: the parent synthesizes a slice-root index from N sub-slice
  # ones, so root-plus-sub-slices is a sanctioned end state there rather than a
  # defect. It is still not a gradeable input — the fix is the same, grade each
  # run against the sub-slice it was assigned, and do it before synthesis.
  echo "error: ${#candidates[@]} candidate indexes under $slice — cannot tell which run wrote which:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  exit 2
fi

index="${candidates[0]}"
index_dir="$(dirname "$index")"

if [[ ! -s "$index" ]]; then
  echo "unusable: index is empty: $index" >&2
  verdict "$index" 0 0 unusable
  exit 1
fi

# Sidecar references are harvested by filename pattern rather than by parsing
# the index's section -> file table. The table's markdown shape is free to
# change; the sidecar filename contract (`<PREFIX>-<section>.md`, a sibling of
# the index) is the part the artifact-shape spoke pins down, so keying on it
# keeps this gate from breaking on a formatting edit. The angle-bracketed
# placeholder itself does not match, so an index that only ever wrote
# `<PREFIX>-<section>.md` reads as naming no sidecar — which it does not.
#
# The prefix is interpolated into an ERE, which is safe because `--index-name`
# already refused every character that would mean anything in one.
#
# Read with a while loop rather than `mapfile`, which is bash 4+ only; this
# gate has to run wherever a consuming project's shell does.
referenced=()
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  referenced+=("$name")
done < <(grep -oE "${sidecar_prefix}-[A-Za-z0-9._-]+\.md" "$index" | sort -u)

if [[ ${#referenced[@]} -eq 0 ]]; then
  echo "unusable: index names no ${sidecar_prefix}-<section>.md sidecar: $index" >&2
  # Through `verdict`, not a hand-rolled printf, so this failure path emits
  # the `freshness=`/`pointer=` fields the header documents and a parent
  # grepping the verdict line for them finds them here too.
  verdict "$index" 0 0 unusable
  exit 1
fi

missing=0
for name in "${referenced[@]}"; do
  sidecar="$index_dir/$name"
  if [[ ! -f "$sidecar" ]]; then
    echo "unusable: index names a sidecar that was never written: $sidecar" >&2
    missing=$((missing + 1))
  elif [[ ! -s "$sidecar" ]]; then
    echo "unusable: index names an empty sidecar: $sidecar" >&2
    missing=$((missing + 1))
  fi
done

count=${#referenced[@]}
unusable=$((missing > 0 ? 1 : 0))

# Freshness. Existence proves an artifact is there, not that THIS dispatch put
# it there — a slice that already held a complete set from an earlier
# exploration satisfies every check above even when the run just failed without
# writing a byte, and the sidecar count would match too, because both runs write
# the same sections. Planning then proceeds against a stale snapshot with the
# gate reporting success. So the parent touches a baseline file immediately
# before dispatching, and the index has to be strictly newer than it.
#
# `-nt` compares mtimes without `stat`, whose flags differ across platforms. It
# is strict, so an index written inside the filesystem's mtime granularity of
# the baseline reads as stale — a false halt, which is the safe direction, and
# not a realistic one for a run that reads a codebase first.
if [[ -n "$newer_than" ]]; then
  if [[ "$index" -nt "$newer_than" ]]; then
    freshness="newer"
  else
    freshness="stale"
    echo "unusable: index is not newer than the pre-dispatch baseline — this run may have written nothing: $index" >&2
    unusable=1
  fi
fi

# Pointer agreement. The gate finds the index from the parent's own slice path,
# so a payload whose `artifact:` names some OTHER file is not corroborating what
# was graded — and its `verification_request.target` would aim the sibling
# verifier at a file this gate never looked at. Disagreement is a defect in the
# payload, not a naming preference to reconcile silently.
if [[ -n "$expect_index" ]]; then
  if [[ "$(canonical "$expect_index")" == "$(canonical "$index")" ]]; then
    pointer="matches"
  else
    pointer="mismatch"
    echo "unusable: payload pointer names $expect_index; this gate graded $index" >&2
    unusable=1
  fi
fi

if [[ -n "$expect_sidecars" && "$expect_sidecars" -ne "$count" ]]; then
  echo "unusable: payload reported $expect_sidecars sidecar(s); the index names $count" >&2
  unusable=1
fi

if [[ "$unusable" -ne 0 ]]; then
  verdict "$index" "$count" "$missing" unusable
  exit 1
fi

verdict "$index" "$count" "$missing" usable
exit 0
