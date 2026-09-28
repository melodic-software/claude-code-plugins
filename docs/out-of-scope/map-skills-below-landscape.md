# map-* skills below the landscape rung

Recorded decline for
[#4639](https://github.com/melodic-software/claude-code-plugins/issues/4639)
and its children: a proposed architecture skill family below
`/architecture:map-landscape`.

## Decision

**Park. Do not build.** No `map-dependencies`, `map-components`, `map-context`,
`map-containers`, `map-flow`, `map-events`, `map-data`, `map-deployment`, or
`map-states` skill ships until a maintainer funds the epic.

- **Option A (taken):** decline the unpaid map-* skill family below landscape.
  `map-landscape` stays the only extractor. `/architecture:improve` and
  `/discovery:explore` stay the thin-result remedies.
- **Option B (declined):** implement the family, starting with map-dependencies
  and the dialect-key decision the epic left open.

**Claim:** the map-* skill family below landscape is unpaid product work; this
marketplace does not add those skills until a maintainer funds #4639 and records
the dialect-key decision in `plugins/architecture/reference/config.md`.
**Basis:** origin/main at this record (`29782b51b`): `plugins/architecture/skills/`
holds improve, map-landscape, record-decision, and setup only. Epic #4639
(`status: needs-decision`, `work-class: structural`) lists nine children and an
unrecorded dialect-key decision. Prior epic #3801 closed with container-level
and component-level C4 views out of scope. `map-landscape` SKILL.md "What this
skill does NOT do" already names those views as landscape-altitude only. PR
#4559 shipped the cheap cross-cutting slice (thin-result line, self-reference).
#4640 (layout refuse) is already closed. #4646 is a merged gaming PR, not a
child. #4554 is a leftover identity bug in existing map-landscape, not a new
skill; it has its own ledger.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds #4639, records the dialect-key decision in
`plugins/architecture/reference/config.md` (and in the authoring-formats
convention if those keys gain a consumer), and unparks the children in build
order.

## Children

| Issue | Skill | Role |
|---|---|---|
| #4641 | map-dependencies | shared extractor; hard prerequisite |
| #4642 | map-components | C4 component rung |
| #4643 | map-context | C4 system context |
| #4644 | map-containers | C4 containers |
| #4645 | map-flow | sequence from one entry |
| #4647 | map-events | async message topology |
| #4648 | map-data | offline ERD |
| #4649 | map-deployment | IaC topology |
| #4650 | map-states | optional last |

Short parks for each child point at this file.

#4554 (checkout identity from directory name) is a leftover of #4559 in the
existing skill. It is not declined here. See
[`map-landscape-checkout-identity.md`](map-landscape-checkout-identity.md).

## Rationale

- Nine skills plus a dialect-key contract change is a plugin vertical, not a
  drain-shipper slice.
- The epic itself is `status: needs-decision` on which dialect key each child
  reads. Shipping the first view child before that record would invent the
  contract.
- #3801 already closed the same altitude as out of scope. Reopening it needs
  funded design, not an implementer default.
- map-landscape already tells the reader that container and component views
  are not this skill. Thin results route to improve and explore.

## Revisit when

- A maintainer funds #4639 and records the dialect-key decision, or
- A named child is funded on its own with that decision already recorded.

## Prior requests

- #4639 (2026-09-28): epic; Option A recorded here.
- #4641, #4642, #4643, #4644, #4645, #4647, #4648, #4649, #4650 (2026-09-28):
  children; short parks point here.
