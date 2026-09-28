# Target-set resolution stays spread in `detect.sh`

Recorded park for
[#3420](https://github.com/melodic-software/claude-code-plugins/issues/3420),
a deepening candidate that would hoist "resolve targets to a scannable file
list" into one module.

## Decision

**Park. Do not hoist.** Target resolution stays spread across the existing
sites in `detect.sh`.

- **Option A (taken):** no unpaid hoist. The arg loop, `--paths-file` reader,
  `list_repo_markdown` (no-args default), `normalize_dir_target`,
  `expand_dir_target`, and the scan-loop `[[ -f ]]` skip keep their own
  listing discipline. Sibling detectors stay out of scope. #3407 is already
  closed at the no-args path; this park does not reopen it.
- **Option B (declined):** one target-resolution module that every entry form
  routes through (no args, explicit files, directory, `--paths-file`,
  `--offset` / `--limit`), holding quotePath, error surfacing, and offset
  windowing once.

**Claim:** `detect.sh` has no owning target-resolution interface. Listing
defects still have more than one home. A resolver module is unpaid.
**Basis:** origin/main as of this record, plus the #3419 park this branch
stacks on. `list_repo_markdown` now lists with `core.quotePath=false` and
surfaces git-absent / non-work-tree / `ls-files` failure on stderr (#3407
closed 2026-09-02). `expand_dir_target` is still a separate `ls-files` with
its own quotePath and fallback walk. `--paths-file` and the arg loop do not
go through either helper. The scan loop still skips a non-file. Sibling
`plugins/instruction-placement/scripts/detect.sh` still has a silent `find .`
fallback; that adoption is out of scope.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds one resolver every entry form routes through,
with a suite that asserts identical lists per form, including a non-ASCII
tracked filename, a directory outside a checkout, and a git-absent host.

## Rationale

- The live #3407 defect (bare-invocation quotePath drop) is already fixed at
  `list_repo_markdown`. The remaining spread is a deepening candidate, not an
  open correctness hole this record is paid to close.
- Directory expansion and bare-repo listing share git-listing hazards but
  differ in anchors (`-C <dir>` vs repo root) and fallback walks. Forcing one
  function is the unpaid design.
- The issue is `work-class: structural` and `needs-human`.

## Revisit when

- A maintainer funds the resolver and names the first entry form to migrate,
  or
- a new listing defect has to be patched at more than one site again.

## Prior requests

- #3420 (2026-09-28): deepening candidate; Option A recorded here. Stacked
  after #3419 (cascade-reader park) so the `ai-slop` version bump serializes.
