---
outcome: sequenced-into-plan
tier: A
date: 2026-07-24
---

# Design resolution

**Tier A — design-significant.** The work introduces new checks across four plugins, a sweep skill
that dispatches them, and a versioned criteria catalog consumed by more than one plugin. New
contract, cross-plugin integration, new component surface: every Tier A signal fires.

**Resolution: design is sequenced as Phases 2–6 of the plan, behind a gate before implementation**,
with a proportionality gate at Phase 2.5 that decides which detectors survive before the catalog and
the homing map are built against them.
The design questions are already enumerated as tasks (#33 homing map, #34 anchored catalog, #35
re-run contract, #28 sweep design, plus D1–D7's own shapes). Running a separate `/planning:design`
pass would re-derive the same list from the same four inputs. Implementation phases do not lock
until Phases 2–6 land and the gate is re-evaluated.

## The constraint that forces Phase 2 to exist

`docs/PLUGIN-PHILOSOPHY.md`, "Design boundary": a plugin "never imports files from a sibling plugin
or discovers another plugin's installation directory. Cooperation uses a documented public seam: an
artifact contract, an explicit invocation argument, or an optional namespaced skill invocation."

This breaks the obvious design. A shared criteria catalog living in
`claude-config/skills/audit-instructions/reference/criteria.md` cannot be read by a check inside
`docs-hygiene` or `skill-quality`. Four shapes survive the boundary, and picking between them is
Phase 2:

1. **Catalog as an artifact contract in the consumer project** — each plugin reads a documented file
   in the target repo. Decoupled, but every consumer must adopt the file, and the catalog stops
   being marketplace-owned knowledge.
2. **Catalog stays in one plugin; siblings receive it as an invocation argument** — the sweep loads
   it and passes the relevant slice to each check it invokes. Preserves single ownership; makes
   every check dependent on being called by the sweep rather than standing alone.
3. **Each plugin owns the checks whose criteria it already holds; the sweep only sequences** — no
   shared catalog at all. Cleanest boundary; risks the drift the anchoring was meant to prevent.
4. **Canonical repo-level source, materialized per carrying plugin by a sync script** — the catalog
   lives at a repo-owned path under `docs/conventions/`, and `scripts/sync-<catalog>.sh` copies it
   into `plugins/<name>/reference/<catalog>.md` for each plugin that opts in. Every plugin reads
   only its own `${CLAUDE_PLUGIN_ROOT}/reference/`, so there is no runtime cross-plugin reach and no
   consumer adoption burden; CI holds the copies byte-identical.

### Shape 4 is the repo's own established mechanism

The boundary rule forbids a *runtime* reach into a sibling's installation directory. A build-time
materialization ends with each plugin owning a file under its own root, so the rule is satisfied
without weakening it. The repo already runs this pattern three times, and the convention registry
names two of them as owner-doc rows:

- `docs/conventions/standards/README.md` → `plugins/*/reference/standards-contract.md`, synced by
  `scripts/sync-standards-contract.sh`, whose `--check-bump` mode additionally fails when the
  contract changed without a carrying plugin's manifest version bump, without a frontmatter semver
  bump, and without a new CHANGELOG entry.
- `lib/hook-utils.sh` → `plugins/*/hooks/hook-utils.sh`, synced by `scripts/sync-hook-utils.sh`.
- `reference/artifact-protocol.md`, checked by `scripts/validate-plugin-contracts.mjs`.

`scripts/check-cross-plugin-source-drift.sh --check` clusters by path-within-plugin and fails when a
registered cluster drifts **or an unregistered cluster is now fully identical** — its skip list is
`SKILL.md`, `plugin.json`, `README.md`, `CHANGELOG.md`, `evals.json`, `hooks.json`, `.gitignore`, so
`reference/criteria.md` is in scope. A byte-identical catalog copy landing in a second plugin
therefore trips that check, and registering the cluster behind a dedicated sync script is the
repository's sanctioned resolution rather than an invention.

**How Shape 4 scores against the other three, on the criteria this document already uses.** It
preserves single ownership (Shape 1 does not), keeps every check standalone-useful because the
criteria are present without the sweep supplying them (Shape 2 does not), and removes the drift
Shape 3 accepts by making drift a CI failure. It also avoids Shape 1's consequence that
`claude-memory` and `docs-hygiene` each gain a consumer-project configuration surface and therefore
a mandatory new `setup` skill.

**The price, stated.** One catalog bump bumps every carrying plugin together — `--check-bump` makes
that release coupling mandatory rather than optional. The catalog gains a semver frontmatter field
and a CHANGELOG of its own. And moving the live `criteria.md` (currently v1.0.0, inside
`audit-instructions/reference/`) to a canonical location is a migration of a contract surface, so
Shape 4 *requires* Phase 3's pre-flight consumer check rather than excusing it.

Shape 4 also satisfies Phase 2's encapsulation sanity check by construction. The plan notes that a
catalog path inside another skill's `reference/` directory is a private surface, and that reaching
it from outside is what `docs-hygiene:audit-encapsulation` exists to detect — that is Shape 2's
problem. Under Shape 4 no plugin reads another's `reference/`; each reads its own copy.

## The second constraint, on naming and posture

`docs/PLUGIN-PHILOSOPHY.md`, "Naming": verb meanings are fixed. `audit` and `scan` mean a read-only
findings report, with "mutation only behind an explicit user override such as an autofix argument,
never on bare invocation." `clean`, `tidy`, and `fix` mutate.

The Brief settles on fix-capable. Under this convention that means either a mutating verb, or an
`audit` that mutates only behind an explicit override. The convention already sanctions the second,
and it preserves the safer bare invocation. Resolved in Phase 6 alongside naming.

## Gate before implementation

Phase 8 does not begin until: the seam shape is chosen and written down, every surviving check has a
named owning plugin, the re-run contract has testable criteria, and the sweep's dispatch order is
fixed. If Phase 2 lands on shape 1 or 3, re-evaluate whether a separate `/planning:design` pass is
now warranted for the catalog's own contract — shape 4 does not need one, because the sync-cluster
contract already has an owner and a CI gate.

The Tier A classification above is itself contingent on Phase 2.5. It rests on "new checks across
four plugins" and "a versioned criteria catalog consumed by more than one plugin". If the
proportionality gate leaves one detector and a set of calibration inputs, neither signal fires as
stated, and the tier is re-derived along with the deliverable's shape.
