# Agent-run artifact attestation

## Decision

**Out of scope.** This marketplace does not sign agent-produced changes
(what instructions, review prompts, workflows, and runs produced a commit).

- **Option 1 (taken):** CI/CD supply-chain tooling, not agent tooling. Close #4703.
- **Option 2 (declined):** a new plugin, only if someone wants the predicate designed.
- **Option 3 (declined):** a leaf under `autonomy`. Return accounting attests human
  effort and counterfactual, not a Sigstore signature.

**Claim:** signed SLSA / in-toto / Sigstore attestation of an agent run is not in
this marketplace.
**Basis:** #4703 body (three options; no home after `provenance` renamed to
`attribution`). Fetched 2026-09-29: the
[in-toto vetted predicate list](https://github.com/in-toto/attestation/blob/main/spec/predicates/README.md)
names no AI-agent-run predicate;
[`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance)
(from v4 a wrapper on `actions/attest`) binds a SLSA build provenance predicate, while
[`actions/attest`](https://github.com/actions/attest) takes a custom `predicate-type` and
`predicate`, so a prompt or instruction digest is expressible only as a custom predicate
with no vetted type. `plugins/autonomy/reference/return-accounting.md` "Agent-run artifact
attestation is out of scope".
**As of:** 2026-09-29.
**Recheck:** a maintainer names a predicate URI they will own, or GitHub/in-toto
publishes an agent-run predicate this marketplace is asked to emit.

## Rationale

- Three senses of "provenance" were conflated: prose (owned by `attribution`),
  claim provenance (discovery joint-inference), and artifact provenance (this
  issue). None of the first two is a signed build predicate.
- Defining a custom `actions/attest` predicate means owning verification
  (`gh attestation verify --predicate-type`) and a re-hash step. That is
  supply-chain product work, not a docs patch.

## Revisit when

- A maintainer funds an agent-run predicate design, or
- An upstream predicate for AI-agent runs lands on the vetted in-toto list.

## Prior requests

- #4703 (2026-09-28): wayfind design item; Option 1 recorded here.
