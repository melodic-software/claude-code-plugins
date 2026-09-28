# eval-coverage: rebuild the emit scanner on a real shell parser

Recorded park for
[#4222](https://github.com/melodic-software/claude-code-plugins/issues/4222).

## Decision

**Parked, unpaid.** This repository does not replace
`scripts/check-detector-eval-coverage.sh`'s awk emit scanner with `shfmt
-tojson`. The hand-rolled scanner stays. Known silent-loss shapes stay in the
script header.

**Claim:** the gate is correct today because the one registered pair contains
none of the open shapes; it is not correct by construction. Patching awk
shapes does not converge. The rewrite is unpaid.
**Basis:** #4222 (follow-up promised in #4205; #4223 recorded remaining
shapes and corrected three header claims); scanner header "KNOWN to be
misread" list on origin/main, including `x="$(emit error P1)"`; triage
2026-09-23 (human-gated; issue scope note: nothing urgent). The 104-check
self-test in `scripts/check-detector-eval-coverage.test.sh` remains the
acceptance criterion for any replacement.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds the `shfmt -tojson` rewrite with that
self-test as acceptance and unparks #4222, or a newly registered detector
contains one of the header's silent-loss shapes.

## What stays

- The awk scanner and its header list of known silent losses.
- The 104-check self-test (arm-and-close, measured discrimination).
- The registered pair (`claude-config:audit-permission-grants`) as the only
  pair the gate governs today.

## What does not ship

- Extracting call sites from `shfmt -tojson`.
- Further awk shape patches as a substitute for the rewrite.

## Rationale

- Six adversarial rounds on #4205 found silent losses, including defects
  introduced by the previous round's fix. Round 6 (a different model family)
  found six more, including the quoted command-substitution form.
- Every remaining shape needs parser state a line-based scanner does not
  have. `shfmt` is already a CI lint dependency.
- The registered detector contains none of those shapes, so the gate is not
  currently false-green on production ids. Urgency is the difference between
  correct-today and correct-as-detectors-are-added.

## Revisit when

- A maintainer unparks #4222 and funds the parser rewrite, or
- Discovery flags a new detector-plus-evals pair whose emit sites include a
  known silent-loss shape.

## Prior requests

- #4222 (2026-09-28): promised rewrite after #4205; drain shipper parks it
  unpaid. #4223 already recorded the remaining shapes in the header and does
  not close this issue.
