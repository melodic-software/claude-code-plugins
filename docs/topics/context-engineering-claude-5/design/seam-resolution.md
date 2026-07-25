---
outcome: seam-resolved
tier: A
date: 2026-07-24
---

# Phase 2 — the cross-plugin criteria seam, resolved

**Chosen shape: no shared criteria artifact. Each plugin owns its own criteria outright;
cross-plugin cooperation is a presence-gated namespaced skill invocation with a documented
standalone fallback.**

This is Shape 3 from [design-resolution.md](design-resolution.md) — "each plugin owns the checks
whose criteria it already holds" — reached for reasons that document did not have. Shape 4, the
sync-script materialization, was its starting position; it is **rejected** below on evidence
gathered after it was written.

The decision is smaller than the phase anticipated, because [proportionality-gate.md](proportionality-gate.md)
ran first and removed most of what the seam was for. What remained was one question: does the D4
stopping-condition carve-out need to be shared across plugins? It does not. **Nothing crosses a
plugin boundary in this design except an invocation.**

## The constraint

`docs/PLUGIN-PHILOSOPHY.md` "Design boundary", verbatim:

> - It never imports files from a sibling plugin or discovers another plugin's installation
>   directory.
> - Cooperation uses a documented public seam: an artifact contract, an explicit invocation
>   argument, or an optional namespaced skill invocation.

The chosen shape uses the third listed seam. It is the one the repository already runs between these
exact two plugins in both directions.

## Why nothing needs sharing

Two findings, each verified against the live tree, removed the seam's subject matter.

**All surviving rules land in two plugins, and neither reads the other's files.** The homing map in
[proportionality-gate.md](proportionality-gate.md) assigns every surviving rule to
`claude-config:audit-instructions` or `claude-memory:audit`. Both already ship their own versioned
`reference/criteria.md`. Neither needs a line of the other's.

**The one candidate for sharing has exactly one consumer.** D4's carve-out was expected to be
consulted by trimming rules across three plugins. Reading those plugins' bodies shows otherwise:
every `docs-hygiene` trimmer already owns a stopping condition shaped to its own content model —
semantic-loss revert in `compress`, always-admitted categories in `audit-noise`, fact ownership in
`audit-derivability`, reasoning-stays-inline in `extract-ssot` — and `skill-quality`'s skills do not
remove content at all. The gap is confined to `claude-config`'s I6 and I8, which are the only
trimming rules in either family with no a-priori bound. A shared artifact with one consumer is not a
seam; it is a file with extra steps.

## The seam that already exists, and is reused

`claude-config` and `claude-memory` already cooperate through reciprocal presence-gated invocation,
and it is the pattern this design extends rather than replaces.

- `audit-instructions/SKILL.md` routes memory-layer hygiene to `claude-memory`'s `audit` skill when
  that plugin is installed, and emits a one-line pointer to the official guidance when it is not —
  "this skill still does not perform it."
- `audit/SKILL.md` routes the reciprocal case back, keeping such findings as criteria-free
  observations when `claude-config` is absent — "never a checklist finding, never silently dropped."

Both sides carry a documented standalone fallback, which is what `docs/conventions/seam-phrasing/`
requires and what keeps each plugin independently useful.

## Why each other shape is rejected

**Shape 1 — catalog as an artifact contract in the consumer project: rejected.** It moves
marketplace-owned knowledge into every consumer repository, requires each consumer to adopt a file
before any check works, and — per the consequence PLAN.md already recorded — hands `claude-memory`
and `docs-hygiene` a consumer-project configuration surface, making a conforming `setup` skill
mandatory for both. It buys decoupling this design does not need, because nothing is coupled.

**Shape 2 — one plugin owns the catalog, siblings receive slices as an invocation argument:
rejected**, and it is the shape the repository's own tooling exists to catch. A catalog inside
`audit-instructions/reference/` is private surface: `docs-hygiene:audit-encapsulation` defines the
public surface as "frontmatter + documented actions + args/flags + `/skill-name` slash invocation +
the `scripts/` entry surface", with every other subdirectory private — and `reference/` is another
subdirectory. Shape 2 also makes each check dependent on being called by the sweep, breaking "every
plugin remains useful alone".

**Shape 4 — canonical repo-level source materialized per plugin by a sync script: rejected**, and
this is the reversal, since it was the starting position. Four findings, all verified at
`cbf27e88a9`:

1. **Its cited CI guarantee does not fire for this artifact.**
   `scripts/check-cross-plugin-source-drift.sh` clusters on the **full path-within-plugin**, and a
   criteria catalog lives at `skills/<skill-name>/reference/criteria.md` where the skill name
   differs by construction. Four `criteria.md` files exist today at four distinct paths and form
   **zero clusters**; `--check` exits 0. `design-resolution.md`'s claim that a byte-identical copy
   would trip the check as an unregistered cluster is false — the skip-list argument was necessary
   but not sufficient. Drift would be invisible, not caught.
2. **Relocation breaks a currently-green gate.** All three parse paths are bare skill-relative
   markdown links in `audit-instructions/SKILL.md`, and `plugins/skill-quality/scripts/check-skill.sh`
   existence-checks every skill-internal ref. Moving the file emits `broken skill-internal ref:
   reference/criteria.md`. Worse: after the move the natural `](../../reference/criteria.md)` form
   escapes that extractor entirely, so CI goes green whether or not the ref resolves.
3. **Adoption is six to seven registration points**, not one: per-plugin copies, a dedicated sync
   script, a `lib/<name>.test.sh`, a CI job in the `--check` / test / `--check-bump` shape *with*
   `fetch-depth: 0`, that job's name added to the `ci-status` aggregate or the gate never blocks, a
   registry entry that is unreachable here because no cluster can form, and a Convention registry
   row. Two operational costs follow: byte-identity forbids relative markdown links in the canonical
   source, and every content edit becomes a fleet-wide version event — a manifest bump in *every*
   carrying plugin plus a changelog entry whose heading matches the new version string.
4. **The catalog has no frontmatter to bump.** `Version: 1.0.0` is body prose on line 3 under an H1,
   and the `sync-standards-contract.sh` precedent reads a YAML frontmatter key. Adopting that shape
   starts by restructuring a live contract surface.

## What this design accepts

**Drift risk, stated rather than engineered away.** Two plugins will hold rules derived from the same
source doctrine, and no CI check compares independently-worded derivatives. Three requirements bound
it, and they are recorded in [proportionality-gate.md](proportionality-gate.md): every rule cites its
source URL and carries the same recheck triggers, so one staleness event fires all of them; a host
with no staleness surface receives no rule; and the rules are named as a family in one place so a
recheck enumerates its dependents.

That is a weaker guarantee than a byte-identity check — and it is the *same* guarantee the
repository already lives with for these two plugins, whose criteria files have always been
independently authored against shared official sources.

## Sanity checks

- **`rg -c "rejected" design/seam-resolution.md` ≥ 3** — three shapes are rejected by name above,
  each with its reason.
- **Encapsulation.** The chosen seam introduces no cross-plugin file read at all, so there is no
  surface for `docs-hygiene:audit-encapsulation` to flag. Verified by inspection as well as by
  construction: no skill in `claude-config`, `claude-memory`, `docs-hygiene`, or `skill-quality`
  reads another plugin's `reference/criteria.md` today, and every criteria reference in the corpus
  is same-plugin and relative. Running the skill against the implemented result remains a Phase 8
  gate.
