#!/usr/bin/env bash
# Seed a drafted reply whose answer sits at the bottom under history, a tangent and an unclear "it".
set -euo pipefail

mkdir -p drafts
cat >drafts/reply.md <<'MD'
# Reply to Dana

**Dana's question:** Can we drop Python 3.9 support in the v4.0 release?

## Draft reply

Back in 2021, when the project first adopted a support policy, the maintainers looked at several options, including following the NumPy NEP 29 schedule, matching the Ubuntu LTS cycle, and supporting every release that upstream still patches. After a long discussion on the mailing list, which also covered whether to move the build to a different packaging tool (we evaluated Poetry, Hatch and PDM, and Hatch had the nicest plugin story), they settled on supporting every CPython release that still gets security fixes. It has worked well since then, and it means it changes whenever that happens.

Python 3.9 reached end of life in October 2025, so it no longer receives security fixes. Our CI matrix still runs it, and dropping it would cut about four minutes from every pipeline.

So yes, we can drop 3.9 in v4.0, as long as we announce it in the v3.12 release notes first.
MD
