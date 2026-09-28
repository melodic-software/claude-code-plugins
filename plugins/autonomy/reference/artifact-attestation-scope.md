# Agent-run artifact attestation — out of scope (#4703)

**Decision (2026-09-28):** Signed, verifiable attestation of what instructions, review prompts,
workflows, and agent runs produced a commit (SLSA-style artifact provenance for AI sessions) is
**not in scope** for the `autonomy` plugin or this marketplace in the current generation.

## What we already cover

| Sense of "provenance" | Home |
|---|---|
| Prose provenance of claims and sources | `attribution` plugin (formerly named `provenance`) |
| Claim provenance traveling with a number | `discovery:research` joint-inference criteria |
| CI build attestations from the runner | Upstream `actions/attest-build-provenance` / consumer repos |

None of these slots bind **prompt digests, model id, skill set, and instruction-file hashes** to a
commit in a way a third party can verify offline.

## Why not now

- GitHub's `actions/attest` can carry a custom predicate, but verification requires a defined
  predicate type and a workflow that re-hashes inputs; nothing in the fleet defines an AI-agent-run
  predicate on the vetted in-toto list.
- A signature proves which workflow emitted JSON, not that digests inside match the commit without an
  explicit re-hash step (#4703 evidence).
- `autonomy` today binds **security and emission posture** for scheduled runs; extending it into
  supply-chain attestations would be a new product surface, not a small skill patch.

## Revisit when

- A consumer repo needs merge gates on attested agent runs and owns the predicate URI + verification
  tooling; or
- GitHub documents a first-class AI-run attestation predicate the fleet can adopt without inventing
  schema.

Until then, file follow-ups under `docs/out-of-scope/` if a concept is rejected for the marketplace
as a whole; per-repo experiments stay in consumer CI, not bundled plugins.
