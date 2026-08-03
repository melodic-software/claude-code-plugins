# Host per-model doctrine chapters at plugin level, outside any skill's private surface

- Status: accepted
- Date: 2026-08-03
- Supersedes: [ADR-0006](0006-scope-model-doctrine-per-version-behind-a-promotion-gate.md)

## Context

[ADR-0006](0006-scope-model-doctrine-per-version-behind-a-promotion-gate.md) established that
doctrine sourced from a single model's guide is model-scoped by default and reaches fleet-wide only
through a promotion gate. To make that scoping structural rather than advisory, it named the
playbooks seam's address: `plugins/playbooks/skills/fable-5/context/model-adaptation/<model-version>.md`.
That address is what this record changes, and it is the only thing this record changes.

Two forces make the address wrong, and both compound with every chapter and every consumer added.

**The host is named after a model that has no chapter in it.** The `fable-5` skill holds **zero**
Fable-5 files under `model-adaptation/`; the directory's entire contents are deltas for *other*
models (`opus-4-8.md`, `opus-5.md`). Fable-5 doctrine is the skill's twelve `context/` chapters —
the adaptation directory exists precisely for models that are *not* Fable 5. Every per-model chapter
added deepens a directory named after a model it will never describe.

**The address cannot be cited without violating a contract this repository ships to others.** The
`docs-hygiene:audit-encapsulation` skill defines a skill's private surface as any path into a
subdirectory under a skill other than `scripts/`, and the chapters sit inside exactly such a
subdirectory. A consumer that cites a chapter at that address commits a **fresh** violation — not an
inherited one — and the alternative to the violation is duplication, which this repository's own
documentation doctrine forbids. That price is paid **once per consumer**, by consumers who cannot fix
it, and four surfaces are queued to become exactly that. ADR-0006's own Decision section is the first
instance: its `:41-42` path cite reaches into the private surface.

Real alternatives shaped the outcome. **A sibling skill** (`plugins/playbooks/skills/model-adaptation/`)
fails on mechanism before cost: meta-rule 3 is mandatory *at arm time* and must therefore be a path
read, whereas routing through a skill is an invocation — it would make the playbook's one
unconditional instruction depend on a second skill firing, and path-reading a sibling skill's
`context/` is the same private-surface violation made structural instead of incidental. **A new
plugin** (`plugins/model-doctrine/`) buys model-neutrality at the price of a new marketplace entry, a
second version stream and CHANGELOG, and install friction for every consumer who already has
`playbooks`. **Keeping the current nesting** costs nothing today and accepts a price that rises
monotonically with each chapter and each consumer. The plugin-level `reference/` tree is precedented
inside this repository — `plugins/autonomy/reference/` and `plugins/architecture/reference/` — mints
no new skill, and so adds nothing to the shared skill-listing budget.

The new address is a cure rather than a relocation because of *where* it sits: a plugin-root
directory is not inside any skill, so the private-surface rule does not engage and a consumer citing
it commits no violation. The derivation is that the private-surface rule does not reach plugin-level
directories — **not** that the contract declares them public. Its public-surface matrix enumerates
Skill, Rule file, and Scheduled-automation prompt, and never mentions plugin-level directories at
all.

**Interpolation of `${CLAUDE_PLUGIN_ROOT}` inside a skill body is verified, not assumed.** Upstream
documents the substitution for hook commands, MCP and LSP server configuration, monitor commands, and
`allowed-tools` frontmatter — not for prose body text. Because meta-rule 3 is the one instruction that
fires unconditionally for every non-Fable model, a silent non-resolution there would be a no-read for
the entire population the chapters exist to serve, so the behavior was established empirically before
being written against. **Claim:** the harness substitutes `${CLAUDE_PLUGIN_ROOT}` in a `SKILL.md` body
before the model receives it. **Basis:** two headless `claude -p` probes on Claude Code 2.1.220. A
disposable plugin loaded with `--plugin-dir` returned the token expanded to its plugin root and read
the file at the expanded path successfully; an already-installed user-scope plugin
(`discipline` 0.10.1) returned a body line carrying both forms, with the `${CLAUDE_PLUGIN_ROOT}` token
expanded and a relative path on the same line left literal — which distinguishes harness substitution
from a model normalizing paths on its own. **As of:** 2026-08-03. **Recheck trigger:** any Claude Code
upgrade, since body-text substitution is not a documented contract. A relative-path form remains the
attested fallback if the behavior ever regresses.

## Decision

Per-version model-adaptation chapters live at
`plugins/playbooks/reference/model-adaptation/<model-version>.md`, at plugin level and outside every
skill's private surface. `fable-5`'s `SKILL.md` cites them as
`${CLAUDE_PLUGIN_ROOT}/reference/model-adaptation/<model-version>.md`, in meta-rule 3, in the
`full` argument's selected-chapter clause, in the chapter-routing table, and in the scope fence.

**ADR-0006's decision is preserved verbatim.** Doctrine sourced from a single model's guide or card
remains model-scoped by default; promotion to fleet-wide happens only through the gate — an
authoritative model-agnostic upstream document stating the claim, or multiple model guides converging
on it. Routing remains by model VERSION and never by family; a missing version file still routes to
the nearest prior version within the same family, whose preamble directs method-only application.
ADR-0006's audit-catalog clause (the `Model scope: <version>` annotation and its exact-match
semantics) and its ingestion-profile clause are untouched. **This record supersedes ADR-0006 on the
seam's address and on nothing else** — it is not a reopening of the scoping question.

The `fable-5` skill is not deprecated and its own doctrine does not move. Only `model-adaptation/`
relocates.

**Scope of the encapsulation cure, stated precisely.** ADR-0006 carries **three** live private-surface
cites. This record cures **one** — `:41-42`, into `fable-5`, which the rehost dissolves by moving the
target out of a skill. The other two survive untouched: `:48` into
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` and `:58` into
`plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md`. Both reach skills
unrelated to `fable-5`, neither is this decision's to fix, and any claim that this record cures "the"
encapsulation defect is falsifiable by grep. Their existence is evidence that ADR path-citing is a
repository-wide authoring habit rather than a symptom of the nesting.

## Consequences

The seam is now citable. DOC-2, DOC-3, DOC-4 and CG-1 — and every consumer behind them — can point at
a chapter without choosing between an encapsulation violation and a duplicate, which is the choice the
old address forced on each of them independently.

Adding a per-model chapter no longer deepens a directory named after an unrelated model, and the
naming stops degrading as the population grows. The rehost was cheapest at two chapters and two
consumers; it would have cost strictly more later.

Meta-rule 3's correctness now depends on a harness behavior that upstream does not document for skill
bodies. The verification record above carries the recheck trigger, and the relative-path fallback is
attested, so a regression is recoverable rather than silent — but the dependency is real and is the
price of the model-neutral host.

Chapter paths in `fable-5`'s `SKILL.md` are no longer uniform: twelve chapters resolve under
`context/` by bare filename while the adaptation chapters carry a full interpolated path. The routing
table's preamble states the exception rather than leaving a reader to infer it.

Prior release notes in `plugins/playbooks/CHANGELOG.md` continue to name the old address. They are
historical records of what shipped and are correct as written; they are not stale references to
repair.
