---
bump: minor
---

### Added

- `prove-check.sh --fixture <dir>` proves a check over an agent action or turn: it must fail on the fixture's `with-mistake` input and pass on its `without-mistake` input, outside any git repository.
- `/corrections:codify` proposals follow `reference/proposal-template.md`, every section filled or `none`, and the proof modes are in `reference/proof.md`.

### Changed

- The enforcement ladder copy is 3.5.0: a classify step opens the guardrail criterion, `action-guard` covers a check when the agent's turn ends, a model-judged hook is the blocking form of `automated-review`, and a loaded and ignored rule with no rung above is strengthened in place.
- `/corrections:codify` classifies a mistake first and picks a rung for each part, strengthens a rule its scope already states instead of adding a duplicate, and its report names the `## Next` route for each rung it passed over.
- Links from the codify skill to the untrusted-content contract are absolute, so they resolve in an installed copy.
