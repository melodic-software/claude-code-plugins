# Configure the review council as a member catalog and ordered rules

- Status: accepted
- Date: 2026-11-09
- Refs: [#14714](https://github.com/melodic-software/claude-code-plugins/issues/14714)

## Context

`/review:council` runs a panel of reviewer members over one change and picks the panel per change
from what the change touches, its size and its merge risk. Each member names a provider, a model,
a brief and an effort, and the owner asked for all of it to be configurable and able to grow to
other providers and models.

The review plugin's settings live in `docs/conventions/review.yaml` (ADR 0064), checked by the
shared validator in `lib/setup-apply.mjs`. Until this change that validator checked scalars and
nested maps only and reported every list key as unchecked. The YAML subset it reads refuses flow
maps (`{...}`).

## Decision

1. **A member catalog, a fallback panel and ordered rules.** `council_members` is a map keyed by
   member id, each holding `provider` and optional `model`, `brief`, `effort`. `council_panel` is a
   list of ids run when no rule matches. `council_rules` is an ordered list; the first rule whose
   every term matches decides the members. Its terms are `paths` (globs), `size` (fanout's tier) and
   `risk` (merge-risk level, at or above), and it names members by id. `council_max_rounds` and
   `council_scores` are scalars.
2. **The lane switch is repository-only.** `council_lanes` has no user option, so a user setting
   cannot let unattended runs start the council in a repository.
3. **The user layer holds JSON text.** The three structured keys are also string userConfig options
   holding JSON in the same shape, checked against the same schema; the repository value wins per
   key, and an invalid option is dropped for its key.
4. **A change never configures its own review.** When the reviewed change edits
   `docs/conventions/review.yaml`, every council key is read from the base branch's committed copy.
5. **The shared validator checks lists.** `lib/setup-apply.mjs` validates a list key and its items
   from the parsed document (`validateData`), and keeps reporting a list that uses a keyword it does
   not implement as unchecked.

Rejected: rules as a map with an `order` field, which leaves the order for an author to keep unique
by hand; members written inline in each rule, which repeats a member in every rule that uses it; and
a separate `review-council.yaml`, a second configuration home against ADR 0064.

## Consequences

- Maps must be written in block style; a flow map is a parse error for the whole file.
- A review plugin release older than these keys drops the whole repository layer when the file holds
  a map or list key it does not know, so every other key in the file falls back as well.
  `plugins/review/reference/config.md` "Older releases" says to add a key only once users have
  updated.
- Adding a provider is an adapter record plus a runner inside the plugin. Selection and the keys
  above do not change, and the configuration never carries a command to run.
- Every plugin carrying a copy of the shared validator now checks its list keys.

## Revisit triggers

- A second plugin needs selection rules of the same shape, so the rule format should move to a
  shared contract.
- The YAML subset gains flow maps, or the review plugin stops reading `docs/conventions/review.yaml`.
