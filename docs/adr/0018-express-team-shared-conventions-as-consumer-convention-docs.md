# Express team-shared plugin conventions as consumer convention docs bound by a pointer line, with manifest-driven retirement detection

- Status: accepted
- Date: 2026-09-01

## Context

Fleet inventory (2026-08-31, `.work/customization-consistency-inventory/INVENTORY.md`, memory
tier) found ~20 consumer-facing configuration surfaces across 51 setup skills, twelve verified
cross-plugin drift classes, and eight bespoke, mutually drifting implementations of "detect the
old convention and clean it up". Several surfaces are prose the model reads — a repo map, audit
targets, lane descriptions — carried in dedicated `.claude/<name>.md` files with a three-layer
cascade whose overlay channel nobody uses, while the consumer's own conventions already live as
natural-language docs the team maintains. The operator's stated goal: plugins should be able to
write succinctly to the consumer's instruction surface, the current setup is over-engineered for
many of them, and any change of format needs a story for detecting and cleaning the old
convention.

An interview (14 questions, register clean) rejected a machine-parsed one-liner grammar in
`CLAUDE.md` (`<plugin> <key>: <value>`) in favor of natural-language convention docs with
progressive disclosure. A blind three-validator tournament
(`docs/topics/customization-consistency/design/mechanism-validation.md`) ranked three retirement
mechanisms; candidate B — per-plugin `retirements.yaml` plus one shared deterministic helper —
won unanimously, with a hybrid of amendments. The plan
(`docs/topics/customization-consistency/PLAN.md`) was stress-tested twice; its findings are the
constraints below.

## Decision

1. **Two expression forms, chosen by content.** Team-shared prose configuration with no
   per-operator axis is expressed as a natural-language convention doc at the consumer's
   convention home, bound by a single pointer line in a marked machine-owned region of the root
   instruction file; the pointer line *is* the binding (no binding file). Per-operator-keyed
   surfaces, structured data, policy-floor surfaces, and all state stay dedicated files under the
   config-cascade layers. The criterion was amended at plan approval (per-operator-keyed stays a
   file), which removed `testing`'s e2e config from the migration set.
2. **Root-file shape is the downstream repository's call.** Recommended: AGENTS.md-canonical with
   a pure `@AGENTS.md` CLAUDE.md shim (the `instruction-placement` shape). Never forced.
3. **The resolution ladder gains a gated infer-and-persist rung**: convention doc → infer house
   style → ask → default, with discovery happening once and only on confirmation.
4. **Retirements are declared, not narrated.** A plugin that retires a consumer-facing convention
   appends an append-only record to its `retirements.yaml`; one shared deterministic helper
   (`lib/check-retirements.sh`, canonical in `claude-config`, synced byte-identical through the
   existing cross-plugin source registry) evaluates records; detection is a fixed step of setup
   `check`, cleanup is per-record and operator-gated in `apply`, migrate content stays with the
   model. Hybrid amendments adopted: one eval case per record (validator failure when missing), a
   runtime fleet-sweep lane in `claude-config` audit-pass over installed plugins' manifests, and a
   report-only demotion field for old records. A CI-aggregated fleet registry is deferred until
   orphan leftovers (uninstalled plugin) prove real.
5. **Dual-read deprecation window.** A migrated skill that finds the retired file present reads
   it as authority (at minimum inference evidence) and WARNs, every run, until cleaned. The window
   ends for a consumer when the record's cleanup runs, and for the fleet when the record is
   demoted to report-only. This is the one sanctioned dual-read; silent shims remain forbidden.
6. **Machine-scope exclusion.** The retirement schema is repository-scope only; there is no
   `scope` field. Machine-scope surfaces under `~/.claude/` (context-guard, rate-limit-guard,
   machine-health) keep their bespoke detection, with the twin drift between context-guard and
   rate-limit-guard fixed by the sync registry rather than by the schema.

## Alternatives considered

- **Machine-parsed one-liners in CLAUDE.md.** Rejected in the interview: it re-instantiates a
  parser contract the model does not need and turns the instruction file into a config file.
- **Candidate A — SKILL.md-embedded prose retirement entries.** Lost the tournament: prose
  semantics are ungradeable and re-create the drift the mechanism exists to kill.
- **Candidate C — CI-aggregated fleet registry.** Lost on machinery and coupling; its aggregator
  is the deferred item above, revived only if orphan leftovers appear.
- **Migrating every surface, including per-operator-keyed ones.** Rejected at plan approval: a
  convention doc has no overlay channel, so a surface with a legitimate personal axis would lose
  it.

## Consequences

- Three owner docs amend in one PR with this ADR: config-cascade (expression doctrine section,
  contract 1.2, Implementers-row expression note), the migration playbook (ladder amendment and the
  retired-conventions seam), and PLUGIN-PHILOSOPHY (ownership-table row, retirement-declaration
  requirement, the WARN-visible dual-read exception, and ratification of the no-no-op-`apply` rule
  the Phase 1b convergence applied).
- The mechanism ships next as its own PR (schema and validator fixtures, helper and tests and sync
  registration, owner doc `docs/conventions/retired-conventions/`, audit-pass sweep lane, the
  pointer-line resolver helper). Until it lands, no surface migrates.
- `plugin-quality`'s `.claude/plugin-quality.md` is the pilot surface, verified in a consumer repo
  with a populated pre-existing AGENTS.md, a pre-existing overlay file (must WARN), and an
  update-without-re-setup simulation (dual-read must carry the old values). Post-pilot surfaces
  migrate one PR each, each recording its keep/migrate call against the criterion.
- Hard to reverse: once consumers carry pointer lines and convention docs, moving back means a
  second retirement cycle. That cost is why the criterion is narrow and the pilot is gated on a
  real consumer-repo verification.
