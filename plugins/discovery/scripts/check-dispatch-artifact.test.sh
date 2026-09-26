#!/usr/bin/env bash
# Black-box contract test for check-dispatch-artifact.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer is invisible. A slice
# holding no artifact, a stub index, or an index naming files nobody wrote must
# never read as "usable" — that reading is the whole failure this gate exists to
# refuse, because the caller's next move on a pass is to proceed to planning.
#
# The shape suite runs ONCE PER ARTIFACT FAMILY, because the gate serves
# `/discovery:explore`, `/discovery:research` and `/discovery:trace-intent` and
# the only difference between them is `--index-name`. Running it for EXPLORE.md
# alone would let a RESEARCH.md or INTENT.md regression through on the strength
# of an explore-shaped pass, which is the same class of false evidence the gate
# itself refuses.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-dispatch-artifact.sh"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# run_raw <expected-exit> <label> [args...] — argv exactly as given, for the
# cases about the argument vector itself.
run_raw() {
  local expected="$1" label="$2"
  shift 2
  local out actual
  out="$(bash "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label — expected exit $expected, got $actual: $out"
  fi
}

# stdout_raw <expected-exit> <expected-substring> <label> [args...] — the stdout
# line is what a parent greps, so its shape is part of the contract, not debug
# output.
#
# The exit status is asserted here too: a caller branches on the status and then reads
# the line. `$?` is captured right after the substitution; anything between overwrites it.
#
# The two halves are reported INDEPENDENTLY rather than as a short-circuiting
# chain: when both drift at once, an `elif` would hide the exit-status failure
# behind the substring one and cost a second run to discover it.
stdout_raw() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  local out actual ok=1
  out="$(bash "$SUT" "$@" 2>/dev/null)"
  actual=$?
  if [[ "$out" != *"$needle"* ]]; then
    fail "$label — stdout lacked '$needle': $out"
    ok=0
  fi
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$label — exit was $actual, expected $expected"
    ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    pass "$label"
  fi
}

# Set per suite; the wrappers below PREPEND --index-name so a case that ends in
# a value-less flag still fails for the reason it names rather than swallowing
# the injected flag as its value.
# stderr_raw <expected-exit> <expected-substring> <label> [args...]: the reason
# a parent reports back is on stderr, so a case about WHICH reason fired reads it.
stderr_raw() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  local err actual ok=1
  err="$(bash "$SUT" "$@" 2>&1 >/dev/null)"
  actual=$?
  if [[ "$err" != *"$needle"* ]]; then
    fail "$label: stderr lacked '$needle': $err"
    ok=0
  fi
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$label: exit was $actual, expected $expected"
    ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    pass "$label"
  fi
}

INDEX_NAME=""
PREFIX=""
WORK=""

run() {
  local expected="$1" label="$2"
  shift 2
  run_raw "$expected" "$label [$INDEX_NAME]" --index-name "$INDEX_NAME" "$@"
}

stdout_has() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  stdout_raw "$expected" "$needle" "$label [$INDEX_NAME]" --index-name "$INDEX_NAME" "$@"
}

stderr_has() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  stderr_raw "$expected" "$needle" "$label [$INDEX_NAME]" --index-name "$INDEX_NAME" "$@"
}

# slice <name> — make an empty slice directory and echo its path.
slice() {
  local path="$WORK/$1"
  mkdir -p "$path"
  printf '%s' "$path"
}

sidecar() {
  local dir="$1" name="$2"
  shift 2
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/$name"
}

# index <slice-dir> <body...> — write the family's index into a directory.
index() {
  local dir="$1"
  shift
  sidecar "$dir" "$INDEX_NAME" "$@"
}

# ============================================================================
# The shape suite — identical for every family, run once per family.
# ============================================================================
suite() {
  INDEX_NAME="$1"
  PREFIX="${INDEX_NAME%.md}"
  WORK="$WORKROOT/$PREFIX"
  mkdir -p "$WORK"

  # --- usable ---------------------------------------------------------------

  local good multi sub dupes blank stub placeholder orphan hollow
  local notdir occupied two_sub deep old_baseline future_baseline

  good="$(slice good)"
  index "$good" "# $PREFIX — payments rounding" '| Section | File |' \
    "| codebase | [$PREFIX-codebase.md]($PREFIX-codebase.md#codebase) |"
  sidecar "$good" "$PREFIX-codebase.md" '---' 'section: codebase' '---'
  run 0 "index plus its one named sidecar is usable" "$good"
  stdout_has 0 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' \
    "usable run reports its counts" "$good"

  # A trailing slash is what a parent's own path variable usually carries.
  run 0 "a trailing slash on the slice path is accepted" "$good/"

  # The same sidecar named in both the abstract list and the section table is
  # ONE sidecar. Counting references rather than distinct files would inflate
  # the count and then disagree with the payload's own honest number.
  dupes="$(slice dupes)"
  index "$dupes" "abstract for $PREFIX-tests.md" "table row for $PREFIX-tests.md"
  sidecar "$dupes" "$PREFIX-tests.md" 'content'
  stdout_has 0 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' \
    "a sidecar named twice counts once" "$dupes"

  multi="$(slice multi)"
  index "$multi" "$PREFIX-codebase.md" "$PREFIX-tests.md" "$PREFIX-config.md"
  sidecar "$multi" "$PREFIX-codebase.md" 'a'
  sidecar "$multi" "$PREFIX-tests.md" 'b'
  sidecar "$multi" "$PREFIX-config.md" 'c'
  run 0 "three named sidecars all present is usable" "$multi"
  run 0 "a matching --expect-sidecars passes" "$multi" --expect-sidecars 3

  # The sanctioned collision path: the PARENT assigned a sub-slice pre-dispatch
  # and passes exactly that path here. On the research side this is also the
  # fan-out placement a parent assigns.
  sub="$(slice sub)"
  index "$sub/rounding-scope" "$PREFIX-codebase.md"
  sidecar "$sub/rounding-scope" "$PREFIX-codebase.md" 'a'
  run 0 "a parent-assigned sub-slice path is graded directly" "$sub/rounding-scope"
  stdout_has 0 "rounding-scope/$INDEX_NAME" "the graded index is the one at the given path" "$sub/rounding-scope"

  # No scan: an index one level BELOW the given path is NOT found. The gate
  # grades exactly the path the parent assigned; an index it did not assign is
  # not a candidate, however close by it sits.
  run 1 "an index one level below the given path is not found" "$sub"

  # Root and sub-slice indexes coexisting confuse nothing — for research this
  # is what a completed, synthesized fan-out looks like. Each invocation names
  # which artifact it is asking about, and grades that one only.
  occupied="$(slice occupied)"
  index "$occupied" "$PREFIX-codebase.md"
  sidecar "$occupied" "$PREFIX-codebase.md" 'a'
  index "$occupied/other-scope" "$PREFIX-codebase.md"
  sidecar "$occupied/other-scope" "$PREFIX-codebase.md" 'b'
  run 0 "the root path is graded even when a sub-slice index coexists" "$occupied"
  stdout_has 0 "occupied/$INDEX_NAME" "the root invocation reports the root index" "$occupied"
  run 0 "a sub-slice path is graded even when the root is occupied" "$occupied/other-scope"
  stdout_has 0 "other-scope/$INDEX_NAME" "the sub-slice invocation reports the sub-slice index" "$occupied/other-scope"

  # A fan-out before synthesis: each run is graded against the sub-slice IT was
  # assigned, and the un-synthesized root holds no index of its own.
  two_sub="$(slice two-sub)"
  index "$two_sub/scope-a" "$PREFIX-codebase.md"
  sidecar "$two_sub/scope-a" "$PREFIX-codebase.md" 'a'
  index "$two_sub/scope-b" "$PREFIX-codebase.md"
  sidecar "$two_sub/scope-b" "$PREFIX-codebase.md" 'b'
  run 0 "the first fan-out sub-slice is graded against its own path" "$two_sub/scope-a"
  run 0 "the second fan-out sub-slice is graded against its own path" "$two_sub/scope-b"
  run 1 "the un-synthesized root of a fan-out is unusable" "$two_sub"

  # --- unusable -------------------------------------------------------------
  # Every case below is a slice the parent must NOT proceed from.

  run 1 "an empty slice with no index is unusable" "$(slice empty-slice)"

  blank="$(slice blank-index)"
  : >"$blank/$INDEX_NAME"
  run 1 "an empty index is unusable" "$blank"

  # The observed production failure's on-disk shape: something got written, but
  # it is a stub, not an index. A bare `test -s` passes this; this gate must not.
  stub="$(slice stub)"
  index "$stub" 'Reading src/payments/rounding.ts ...'
  run 1 "an index naming no sidecar is unusable" "$stub"
  # The no-sidecar branch reports through the same verdict line as every other
  # failure — a parent greps one shape, not one shape per failure path.
  stdout_has 1 'sidecars=0 missing=0 freshness=unchecked pointer=unchecked status=unusable' \
    "the no-sidecar branch reports the full verdict line" "$stub"

  # The angle-bracketed placeholder is not a filename.
  placeholder="$(slice placeholder)"
  index "$placeholder" "sidecars are named $PREFIX-<section>.md"
  run 1 "the literal <section> placeholder does not count as a sidecar" "$placeholder"

  # The truncation shape dispatch.md describes: an index naming files the run
  # died before writing.
  orphan="$(slice orphan)"
  index "$orphan" "$PREFIX-codebase.md" "$PREFIX-tests.md"
  sidecar "$orphan" "$PREFIX-codebase.md" 'a'
  run 1 "an index naming a sidecar that was never written is unusable" "$orphan"
  stdout_has 1 'sidecars=2 missing=1 freshness=unchecked pointer=unchecked status=unusable' \
    "the missing count is reported" "$orphan"

  hollow="$(slice hollow)"
  index "$hollow" "$PREFIX-codebase.md"
  : >"$hollow/$PREFIX-codebase.md"
  run 1 "an index naming an empty sidecar is unusable" "$hollow"

  # The payload cross-check: the index and the payload disagree about how much
  # was written, so one of them is wrong and the parent cannot tell which.
  run 1 "a --expect-sidecars mismatch is unusable" "$multi" --expect-sidecars 5
  run 1 "--expect-sidecars 0 against a real index is unusable" "$multi" --expect-sidecars 0

  # --- fail closed ----------------------------------------------------------
  # Everything below is a slice or an invocation the gate cannot honestly grade.
  # Each must exit 2 — never 0.

  run 2 "no slice path is a usage error" ""
  run 2 "a nonexistent slice path is ungradeable" "$WORK/does-not-exist"

  notdir="$WORK/a-file"
  printf 'x\n' >"$notdir"
  run 2 "a slice path that is a file is ungradeable" "$notdir"

  run 2 "an unknown flag is a usage error" "$good" --nope
  run 2 "a second positional path is a usage error" "$good" "$multi"
  run 2 "--expect-sidecars with no value is a usage error" "$good" --expect-sidecars
  run 2 "--expect-sidecars with a non-integer is a usage error" "$good" --expect-sidecars two
  run 2 "--expect-sidecars with a negative value is a usage error" "$good" --expect-sidecars -1

  # An index below the given path is never reached, at any depth — the gate
  # grades the assigned path only, so the slice reads as holding no artifact
  # rather than silently reaching for one.
  deep="$(slice deep)"
  index "$deep/a/b" "$PREFIX-codebase.md"
  sidecar "$deep/a/b" "$PREFIX-codebase.md" 'a'
  run 1 "an index two levels below the slice is not reached" "$deep"

  # --- freshness (--newer-than) ---------------------------------------------
  # Existence proves an artifact is there, not that THIS dispatch put it there.
  # Every fixture below is a slice that passes every other check.

  # Baselines are stamped with `touch -t` rather than written in sequence, so
  # the ordering does not depend on the filesystem's mtime granularity.
  old_baseline="$WORK/old-baseline"
  : >"$old_baseline"
  touch -t 200001010000 "$old_baseline"

  future_baseline="$WORK/future-baseline"
  : >"$future_baseline"
  touch -t 203001010000 "$future_baseline"

  run 0 "an index newer than the baseline is usable" "$good" --newer-than "$old_baseline"
  stdout_has 0 'freshness=newer' "a checked-and-fresh index reports freshness=newer" "$good" --newer-than "$old_baseline"

  # The finding this check exists for: a slice already holding a complete
  # artifact set from an EARLIER run, graded after a dispatch that wrote nothing.
  run 1 "an index no newer than the baseline is unusable" "$good" --newer-than "$future_baseline"
  stdout_has 1 'freshness=stale' "a stale index reports freshness=stale" "$good" --newer-than "$future_baseline"

  # An opt-in check that did not run must say so rather than reading as passed.
  stdout_has 0 'freshness=unchecked pointer=unchecked' "omitted checks report unchecked" "$good"

  # A baseline that is not there makes freshness ungradeable, and the caller
  # asked for it — downgrading to `unchecked` would hand back a check that only
  # appeared to run.
  run 2 "--newer-than naming a missing baseline is ungradeable" "$good" --newer-than "$WORK/no-such-baseline"
  run 2 "--newer-than with no value is a usage error" "$good" --newer-than

  # --- pointer agreement (--expect-index) -----------------------------------

  run 0 "a payload pointer naming the graded index is usable" "$good" --expect-index "$good/$INDEX_NAME"
  stdout_has 0 'pointer=matches' "an agreeing pointer reports pointer=matches" "$good" --expect-index "$good/$INDEX_NAME"

  # Two spellings of one file are one file. Comparing raw strings would report a
  # mismatch here and halt a run whose artifact is fine.
  run 0 "a differently-spelled path to the same index still matches" "$good" --expect-index "$good/./$INDEX_NAME"

  # The finding: the payload's pointer — and so its verification_request.target
  # — names a file this gate never graded.
  run 1 "a payload pointer naming another file is unusable" "$good" --expect-index "$multi/$INDEX_NAME"
  stdout_has 1 'pointer=mismatch' "a disagreeing pointer reports pointer=mismatch" "$good" --expect-index "$multi/$INDEX_NAME"

  run 1 "a payload pointer into a directory that does not exist is unusable" "$good" --expect-index "$WORKROOT/nowhere/$INDEX_NAME"
  run 2 "--expect-index with no value is a usage error" "$good" --expect-index

  # --- the by-value recovery rung -------------------------------------------
  # A worker that finished its work and whose every write was refused leaves the
  # slice holding nothing but the parent's own pre-dispatch baseline. The ladder
  # routes that case to `persistence: by-value`: the PARENT writes the slice from
  # the payload's verbatim artifact bodies and re-runs this same gate.
  #
  # Both halves are asserted, and the pair is the point. The first proves the
  # exception is needed — the by-value end state really does exit 1, so it is not
  # a rung invented for a failure the gate never produces. The second proves the
  # exception routes THROUGH the gate rather than around it: the recovered slice
  # earns its exit 0 from the same command, with the same freshness and pointer
  # checks, as any run that wrote its own artifact. If a future change ever let
  # `persistence: by-value` be believed without a passing gate, the second half
  # stops being the thing that licenses proceeding and this pair stops meaning
  # what it says.

  local byvalue byvalue_baseline
  byvalue="$(slice by-value)"
  byvalue_baseline="$byvalue/.dispatch-baseline"
  : >"$byvalue_baseline"
  touch -t 200001010000 "$byvalue_baseline"

  # Before: work complete, nothing persisted. The baseline is all that is there.
  run 1 "a slice holding only the dispatch baseline is unusable" "$byvalue" \
    --newer-than "$byvalue_baseline"
  stdout_has 1 'index=<none> sidecars=0 missing=0' \
    "the by-value end state reports no index at all" "$byvalue" --newer-than "$byvalue_baseline"

  # After: the parent wrote the slice from the payload's bodies. Nothing about
  # the gate changed — only who did the writing.
  index "$byvalue" "# $PREFIX — recovered by value" \
    "| codebase | [$PREFIX-codebase.md]($PREFIX-codebase.md#codebase) |"
  sidecar "$byvalue" "$PREFIX-codebase.md" '---' 'section: codebase' '---'
  run 0 "the same slice is usable once the parent writes it from the payload" "$byvalue" \
    --newer-than "$byvalue_baseline" --expect-index "$byvalue/$INDEX_NAME" --expect-sidecars 1
  stdout_has 0 'sidecars=1 missing=0 freshness=newer pointer=matches status=usable' \
    "a parent-written slice passes every check a self-written one does" "$byvalue" \
    --newer-than "$byvalue_baseline" --expect-index "$byvalue/$INDEX_NAME" --expect-sidecars 1

  # The parent writes AFTER its own pre-dispatch touch, so freshness is earned
  # rather than waived. A recovered slice whose index predates the baseline is
  # still stale — the rung does not smuggle in an artifact from an older run.
  run 1 "a recovered slice no newer than the baseline is still stale" "$byvalue" \
    --newer-than "$future_baseline"

  # The opt-in checks compose, and a single verdict line carries all of them.
  run 0 "all three opt-in checks together pass on a good slice" "$good" \
    --newer-than "$old_baseline" --expect-index "$good/$INDEX_NAME" --expect-sidecars 1
  stdout_has 0 'freshness=newer pointer=matches status=usable' "a fully-checked pass reports every field" "$good" \
    --newer-than "$old_baseline" --expect-index "$good/$INDEX_NAME" --expect-sidecars 1

  # --- the in-progress marker -----------------------------------------------
  # A dispatched agent writes its index skeleton early with the line
  # `Run status: in progress` and replaces it with `Run status: complete` only in
  # its final write. An index still carrying the marker is a run that stopped
  # before that write, however complete its sidecars look.

  local inprog inprog_crlf complete nostatus lookalike trailing skeleton byvalue_inprog

  inprog="$(slice in-progress)"
  index "$inprog" "# $PREFIX" 'Run status: in progress' "$PREFIX-codebase.md"
  sidecar "$inprog" "$PREFIX-codebase.md" 'a'
  run 1 "an index still marked Run status: in progress is unusable" "$inprog"
  stdout_has 1 'status=unusable' "an in-progress index reports status=unusable" "$inprog"
  stderr_has 1 'still marked Run status: in progress' \
    "an in-progress index names the marker reason on stderr" "$inprog"

  inprog_crlf="$(slice in-progress-crlf)"
  printf '# %s\r\nRun status: in progress\r\n%s-codebase.md\r\n' "$PREFIX" "$PREFIX" \
    >"$inprog_crlf/$INDEX_NAME"
  sidecar "$inprog_crlf" "$PREFIX-codebase.md" 'a'
  run 1 "an in-progress marker with CRLF line endings is unusable" "$inprog_crlf"

  # Trailing whitespace an editor leaves behind does not hide the marker.
  local inprog_ws
  inprog_ws="$(slice in-progress-trailing-ws)"
  printf '# %s\nRun status: in progress \t\r\n%s-codebase.md\n' "$PREFIX" "$PREFIX" \
    >"$inprog_ws/$INDEX_NAME"
  sidecar "$inprog_ws" "$PREFIX-codebase.md" 'a'
  run 1 "an in-progress marker with trailing whitespace is unusable" "$inprog_ws"

  complete="$(slice complete)"
  index "$complete" "# $PREFIX" 'Run status: complete' "$PREFIX-codebase.md"
  sidecar "$complete" "$PREFIX-codebase.md" 'a'
  run 0 "an index marked Run status: complete is usable" "$complete"

  # The marker slot is the first non-blank line after the `# ` title. A
  # finished index whose restated task or quoted source text later carries the
  # marker's literal line is still finished.
  local quoted_later inprog_then_text
  quoted_later="$(slice complete-then-quoted)"
  index "$quoted_later" "# $PREFIX" 'Run status: complete' 'The agent writes:' \
    'Run status: in progress' "$PREFIX-codebase.md"
  sidecar "$quoted_later" "$PREFIX-codebase.md" 'a'
  run 0 "a quoted in-progress line after the complete marker does not trigger" "$quoted_later"

  inprog_then_text="$(slice in-progress-then-complete-text)"
  index "$inprog_then_text" "# $PREFIX" 'Run status: in progress' 'The final write sets:' \
    'Run status: complete' "$PREFIX-codebase.md"
  sidecar "$inprog_then_text" "$PREFIX-codebase.md" 'a'
  run 1 "an in-progress marker followed by later complete text is unusable" "$inprog_then_text"

  # An index with no status line at all is a legacy or inline artifact and
  # grades exactly as before; `$good` carries none.
  nostatus="$(slice no-status)"
  index "$nostatus" "# $PREFIX" "$PREFIX-codebase.md"
  sidecar "$nostatus" "$PREFIX-codebase.md" 'a'
  run 0 "an index with no status line is usable" "$nostatus"

  # The marker is a plain line. A bolded copy or a line that merely starts with
  # the words is prose about the marker, not the marker.
  lookalike="$(slice lookalike)"
  index "$lookalike" "# $PREFIX" '**Run status: in progress**' "$PREFIX-codebase.md"
  sidecar "$lookalike" "$PREFIX-codebase.md" 'a'
  run 0 "a bolded look-alike of the marker does not trigger" "$lookalike"

  trailing="$(slice trailing)"
  index "$trailing" "# $PREFIX" 'Run status: in progress later' "$PREFIX-codebase.md"
  sidecar "$trailing" "$PREFIX-codebase.md" 'a'
  run 0 "a marker line with trailing words does not trigger" "$trailing"

  local until_done
  until_done="$(slice until-done)"
  index "$until_done" "# $PREFIX" 'Run status: in progress until done' "$PREFIX-codebase.md"
  sidecar "$until_done" "$PREFIX-codebase.md" 'a'
  run 0 "a slot line with words after the marker does not trigger" "$until_done"

  # slotted <expected-exit> <label> <slice-name> <printf-format>: write the
  # index from a printf format (so a case can carry a BOM, a tab or a CR), give
  # it one sidecar, and grade it. `%s` in the format is the family prefix.
  # `--` keeps a format that opens with `---` from being read as an option,
  # which would write an empty index. A refuse case also asserts the marker
  # reason, so an exit 1 for any other cause (an empty index, no sidecar)
  # cannot pass for a slot read.
  slotted() {
    local expected="$1" label="$2" dir
    dir="$(slice "$3")"
    # shellcheck disable=SC2059
    printf -- "$4" "$PREFIX" "$PREFIX" >"$dir/$INDEX_NAME"
    sidecar "$dir" "$PREFIX-codebase.md" 'a'
    run "$expected" "$label" "$dir"
    if [[ "$expected" -eq 1 ]]; then
      stderr_has 1 'still marked Run status: in progress' "$label, for the marker reason" "$dir"
    fi
  }

  # Only the slot is read. With no marker, the literal line elsewhere is text.
  slotted 0 "no marker, the in-progress line quoted in the restated task, is usable" \
    quoted-no-marker '# %s\n\nTask: the agent writes\nRun status: in progress\n%s-codebase.md\n'
  # shellcheck disable=SC2016
  slotted 0 "no marker, the in-progress line inside a fence, is usable" \
    fenced-no-marker '# %s\n\n```text\nRun status: in progress\n```\n%s-codebase.md\n'
  # A `# ` line inside a fence is a shell comment, not the title, so the line
  # after it is not the slot.
  # shellcheck disable=SC2016
  slotted 0 "a hash line inside a backtick fence is not the title" \
    fenced-hash-backtick '```sh\n# %s\nRun status: in progress\n```\n%s-codebase.md\n'
  slotted 0 "a hash line inside a tilde fence is not the title" \
    fenced-hash-tilde '~~~sh\n# %s\nRun status: in progress\n~~~\n%s-codebase.md\n'
  slotted 0 "complete in the slot with a later in-progress quote is usable" \
    complete-slot-quoted '# %s\nRun status: complete\n\nRun status: in progress\n%s-codebase.md\n'

  # The slot survives the shapes a real index takes.
  slotted 1 "front matter, then the title, then the marker, is unusable" \
    frontmatter-marker '---\nabstract: one line\n---\n# %s\nRun status: in progress\n%s-codebase.md\n'
  slotted 1 "a BOM before the title, then the marker, is unusable" \
    bom-marker '\357\273\277# %s\nRun status: in progress\n%s-codebase.md\n'
  slotted 1 "a blank line between the title and the marker is unusable" \
    blank-then-marker '# %s\n\n   \nRun status: in progress\n%s-codebase.md\n'
  slotted 1 "a CRLF title and marker are unusable" \
    crlf-slot '# %s\r\n\r\nRun status: in progress\r\n%s-codebase.md\r\n'

  # Spelling drift in the marker still reads as the marker.
  slotted 1 "the marker in other case is unusable" \
    drift-case '# %s\nrun status: IN PROGRESS\n%s-codebase.md\n'
  slotted 1 "the marker with doubled spaces is unusable" \
    drift-spaces '# %s\nRun  status:  in progress\n%s-codebase.md\n'
  slotted 1 "the marker with a tab after the colon is unusable" \
    drift-tab '# %s\nRun status:\tin progress\n%s-codebase.md\n'
  slotted 1 "the marker spelled in-progress is unusable" \
    drift-hyphen '# %s\nRun status: in-progress\n%s-codebase.md\n'
  slotted 1 "the marker spelled in_progress is unusable" \
    drift-underscore '# %s\nRun status: in_progress\n%s-codebase.md\n'

  # A closing fence uses the opening fence's character and is at least as
  # long (CommonMark). A tilde line inside a backtick fence closes nothing.
  # shellcheck disable=SC2016
  slotted 1 "a tilde line does not close a backtick fence" \
    fence-mixed-close '```\n~~~\n```\n# %s\nRun status: in progress\n%s-codebase.md\n'
  # shellcheck disable=SC2016
  slotted 1 "a shorter backtick line does not close a longer fence" \
    fence-short-close '````\n```\n# not a title\n````\n# %s\nRun status: in progress\n%s-codebase.md\n'

  # Line 1 `---` opens front matter only when a `---` or `...` closer exists
  # and every line between is YAML-shaped. Otherwise it is a horizontal rule
  # and the slot is read from line 1.
  slotted 1 "an unclosed front-matter opener is a rule, and the marker counts" \
    fm-unclosed '---\n# %s\nRun status: in progress\n%s-codebase.md\n'
  slotted 1 "an unclosed opener with a key line is a rule, and the marker counts" \
    fm-unclosed-title '---\ntitle: x\n# %s\nRun status: in progress\n%s-codebase.md\n'
  slotted 1 "front matter closed with dots, then the marker, is unusable" \
    fm-dots-close '---\ntitle: x\n...\n# %s\nRun status: in progress\n%s-codebase.md\n'
  slotted 0 "a rule-bounded block holding a non-YAML line is not front matter" \
    hr-false '---\n# %s\nRun status: complete\n%s-codebase.md\n\n---\n# Appendix\nRun status: in progress\n'
  slotted 0 "a hash line inside real front matter is a YAML comment, not the title" \
    fm-title-inside '---\n# %s\nRun status: in progress\n---\n# Title\nRun status: complete\n%s-codebase.md\n'
  slotted 1 "front matter with a comment line, then the title and the marker, is unusable" \
    fm-title-inside-ip '---\ntitle: x\n# not a title\n---\n# %s\nRun status: in progress\n%s-codebase.md\n'

  # A bare skeleton: the run wrote its marker and stopped before planning any
  # sidecar. The marker reason is the one reported, not the no-sidecar one.
  skeleton="$(slice skeleton)"
  index "$skeleton" "# $PREFIX" 'Run status: in progress'
  run 1 "a bare in-progress skeleton is unusable" "$skeleton"
  stderr_has 1 'still marked Run status: in progress' \
    "a bare skeleton reports the in-progress reason" "$skeleton"

  # A by-value body still marked in progress is a partial run however it
  # reached the disk.
  byvalue_inprog="$(slice by-value-in-progress)"
  index "$byvalue_inprog" "# $PREFIX: recovered by value" 'Run status: in progress' \
    "| codebase | [$PREFIX-codebase.md]($PREFIX-codebase.md#codebase) |"
  sidecar "$byvalue_inprog" "$PREFIX-codebase.md" '---' 'section: codebase' '---'
  run 1 "a by-value body still marked in progress is unusable" "$byvalue_inprog" \
    --newer-than "$old_baseline" --expect-index "$byvalue_inprog/$INDEX_NAME" --expect-sidecars 1
}

suite EXPLORE.md
suite RESEARCH.md
suite INTENT.md

# ============================================================================
# --index-name itself — the one parameter the two families differ by.
# ============================================================================

INDEX_NAME="RESEARCH.md"
WORK="$WORKROOT/flag"
mkdir -p "$WORK"

flagged="$(slice flagged)"
index "$flagged" 'RESEARCH-tiers.md'
sidecar "$flagged" RESEARCH-tiers.md 'a'

# No default. A gate that guessed EXPLORE.md here would report a research run
# that succeeded as unusable — or, in a slice an earlier exploration also wrote
# to, report one that wrote nothing as usable.
run_raw 2 "a missing --index-name is a usage error" "$flagged"
run_raw 2 "--index-name with no value is a usage error" "$flagged" --index-name
run_raw 2 "--index-name without a .md suffix is rejected" "$flagged" --index-name RESEARCH
run_raw 2 "--index-name with a non-markdown suffix is rejected" "$flagged" --index-name RESEARCH.txt

# The stem is interpolated into an ERE for the sidecar scan, so a stem carrying
# regex metacharacters is refused rather than silently widening what counts as
# a sidecar.
run_raw 2 "--index-name with a dotted stem is rejected" "$flagged" --index-name RE.SEARCH.md
run_raw 2 "--index-name with a glob metacharacter is rejected" "$flagged" --index-name 'RE*.md'
run_raw 2 "--index-name with a path separator is rejected" "$flagged" --index-name 'sub/RESEARCH.md'

# Cross-family isolation, both directions: an index of the OTHER family is not
# this family's artifact, and must not be graded as one.
explore_only="$(slice explore-only)"
sidecar "$explore_only" EXPLORE.md 'EXPLORE-codebase.md'
sidecar "$explore_only" EXPLORE-codebase.md 'a'
run_raw 1 "a slice holding only EXPLORE.md is unusable under --index-name RESEARCH.md" \
  "$explore_only" --index-name RESEARCH.md
run_raw 0 "the same slice is usable under --index-name EXPLORE.md" \
  "$explore_only" --index-name EXPLORE.md

# The research coverage ledger is a sibling of the index, lowercase, and is NOT
# a sidecar. Counting it would inflate the count and disagree with the payload's
# honest number; grading its contents belongs to check-coverage-complete.sh.
#
# The fixture puts the ledger in BOTH places a wrong implementation could reach
# it from, because the gate harvests sidecar names out of the index TEXT and a
# ledger the index never mentions is unreachable by construction — an assertion
# no implementation of that design could fail is not coverage:
#
#   - NAMED IN THE INDEX. `artifact-shape.md` does not put the ledger in the
#     index's section table, but nothing stops a run mentioning it in the
#     restatement or the handoff, and real ones do. A harvest that dropped the
#     `RESEARCH-` anchor for a bare `[A-Za-z0-9._-]+\.md`, or that matched
#     case-insensitively (`research-checklist.md` matches `RESEARCH-…` under
#     `grep -oiE`), counts it and reports sidecars=2.
#   - ON DISK BESIDE THE INDEX, which keeps the fixture realistic but is NOT
#     what this case discriminates on. A directory-glob rewrite does not fail
#     here: bash matches a glob against the DIRENT STRING, so `RESEARCH-*.md`
#     never picks up `research-checklist.md` regardless of how the filesystem
#     compares names for lookup. Probed on this platform — `shopt -s nullglob;
#     echo RESEARCH-*.md` yields only `RESEARCH-tiers.md` while
#     `test -f RESEARCH-checklist.md` succeeds. A glob rewrite is caught
#     instead by the named-but-missing sidecar cases, which it cannot satisfy.
#
# So the anchor and the case-fold inflate the count and fail the assertion
# below, which is the point of having it.
ledgered="$(slice ledgered)"
index "$ledgered" 'RESEARCH-tiers.md' \
  'Corpus coverage is tracked in research-checklist.md beside this index.'
sidecar "$ledgered" RESEARCH-tiers.md 'a'
sidecar "$ledgered" research-checklist.md '| # | Corpus item | Depth criterion | Done |'
stdout_raw 0 'sidecars=1 missing=0' "research-checklist.md is not counted as a sidecar" \
  "$ledgered" --index-name RESEARCH.md

# --- help -------------------------------------------------------------------
# --help answers before the required-argument check, so it works with no flags.

run_raw 0 "--help exits 0" --help
stdout_raw 0 'Deterministic acceptance gate' "--help prints the header" --help
stdout_raw 0 '--index-name' "--help documents the required index name" --help

# ----------------------------------------------------------------------------

if [[ "$fails" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall tests passed\n'
