# Changelog

All notable changes to the `naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Added

- **`name-it-better tournament`: the scoring criteria are settled before the candidates return.**
  Absorbed from an upstream skill this marketplace decided not to ship
  (`docs/upstream/cursor-pstack.md`, the `arena` row). Upstream's version of this idea is a *secret*
  rubric, which was rejected outright: this skill's criteria are deliberately the consuming
  project's own declared standards, which are public by construction, so withholding them would
  fight that design rather than improve it. What was taken is the anti-retrofit property without the
  secrecy — the mode now fixes *when* the rubric is settled, not who may see it. Which resolved
  criteria decide a given name, and how they rank against each other, is a judgement made in this
  skill, and it must be made and written down while the pool is still unknown. Criteria fixed after
  the candidates land get shaped by the candidates, and a rubric that already fits the pool cannot
  eliminate anything — the independent judges then score against a standard the pool itself
  authored. The existing "does not copy or invent criteria" rule is unchanged and explicitly
  reasserted for the mid-bracket case: a criterion discovered missing still routes upstream to the
  source of truth, and adding it means re-scoring the round it changes rather than applying it from
  that point on.

## [0.4.1]

### Changed

- **Explicit `disable-model-invocation` on `name-it-better` (#2968).** The skill now states the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.4.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.3.0]

### Added

- **Four tournament lessons from the running-retro naming round** folded into
  `name-it-better`:
  - a **terms-of-art brief field** — the field's established names for the act,
    with researched (not recalled) meanings, so generators neither borrow a
    divergent term blindly nor miss the honest established one;
  - **blocklist provenance** — every word-level blocklist entry records
    user-stated vs agent-inferred origin; agent-inferred entries are proposals
    to confirm, never silently hard constraints;
  - the **sentence-form test** as an early merge filter for utterance names
    (skills, commands): the imperative you would actually say, cold-readable;
  - a **temporal-neutrality constraint** for skills loadable as primed context:
    the name must read valid before any work exists.

## [0.2.0]

### Changed

- **Structured context brief.** The loose "distill a brief" step is now a
  brief with named fields — responsibility, firing/usage context, scope
  boundaries (what it is NOT), collision vocabulary, and word-level
  blocklist (with reasons) — mirroring the replicated concept → word →
  structure naming model. The generators receive this brief, and only this
  brief; rejected incumbent NAMES stay on the main-thread reject list and
  never enter it.
- **Declared criteria priority.** The fallback general criteria are now
  research-ordered — semantic accuracy (anti-misleading) > scope fit >
  comprehensibility > trigger/evocative utility — and this ordering governs
  scoring and judging. A consuming project's declared conventions still
  override it.

### Added

- **Rejection-reason iteration protocol.** A rejected candidate's REASON is
  captured as an explicit new brief constraint (a word-level blocklist
  entry, a scope-boundary correction, or a criteria reweight) and fed into
  the next blind round; rejected names and words never re-enter.
- **Modality layer.** Criteria split into a universal semantic layer and a
  modality/vendor-specific syntactic layer; documented style conflicts
  (abbreviation policy, acronym casing, casing style) route to the
  consuming ecosystem's own style guide rather than a house verdict. For
  Claude Code skills, the description — not the name — drives discovery, so
  the name optimises for human semantic accuracy.
- **Strengthened domain-concept pointer.** When the target is a domain
  concept, route to a domain-modelling capability to settle what it IS
  before naming it (pointer only).
- **Research grounding.** `context/sources.md` adds the primary empirical
  sources behind the criteria priority (Feitelson TSE 2022, Alpern 2024
  reproduction, Avidan & Feitelson 2017, Hofmeister 2017) and the modality
  layer (clig.dev, Claude Code skills docs, the conflicting style guides),
  and honestly marks paywalled book sources as Tier-2-for-verification.

## [0.1.0]

### Added

- **Initial release.** `/naming:name-it-better` — generate fresh name
  candidates by fanning out blind, fresh-context generators from distinct lenses
  (responsibility-literal, moment-of-use, domain-lore), score a shortlist against
  the consuming org's naming criteria, and recommend — the human always picks,
  never an auto-locked name. Optional `tournament` action adds elimination rounds
  with independent judges for high-stakes, hard-to-refactor names.
- Repo-agnostic: scores against the consuming project's declared naming
  conventions when present, degrading to the general criteria grounded in the
  skill's `context/sources.md` when none is declared.
