# Native references — presence-gated phrasing for Claude Code's own surfaces

Owner doc for **how a component in this marketplace refers to a native Claude Code surface** — a
built-in CLI command, a bundled skill, a plugin-backed built-in, or a session-provided skill — when
that surface materially overlaps what the component does. One shape: a read-time presence gate that
routes, never an assertion that the native thing is there.

The problem this closes is specific. A marketplace skill and a native surface can do overlapping
work, and the model picks between them from descriptions alone. Silence produces duplication; a
static claim ("Claude Code ships `/doctor`, so use that") produces a false statement in every
session where the surface is gated off. Both failures are avoided by the same sentence shape.

## Boundary

This doc owns the phrasing of references **to native surfaces**. It does not own:

- **Cross-plugin references.** [`seam-phrasing`](../seam-phrasing/README.md) owns the
  gate + fallback + ownership-framing shape for optional references to *another plugin's* skill.
  Its three elements are the template this doc specializes; a native surface is not a plugin, which
  is why the specialization needs its own owner rather than a clause in that doc.
- **Whether a reference should exist at all.** That is a verdict, and verdicts live in the
  committed overlap store rendered into [`docs/NATIVE-SURFACES.md`](../../NATIVE-SURFACES.md).
  This doc governs the words once a verdict says a reference is warranted.
- **The stamp discipline on any upstream fact a reference restates.**
  [`upstream-drift`](../upstream-drift/README.md) owns the four-part record (claim, basis, as-of
  date, recheck trigger) and the observability bar its triggers must clear.
- **Instruction economy.** [`PLUGIN-PHILOSOPHY`](../../PLUGIN-PHILOSOPHY.md) owns the rule that
  every always-loaded description is a per-session tax. This doc keeps the phrase to one clause
  because of that rule; it does not restate it.

## Why a gate, and never an assertion

Native availability varies along at least four independent axes, so any static availability
sentence is wrong somewhere by construction:

| Axis | Mechanism |
|---|---|
| Settings / environment | `disableBundledSkills` and `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` remove bundled skills and workflows; `skillOverrides` maps a name to `on` / `name-only` / `user-invocable-only` / `off`; `DISABLE_DOCTOR_COMMAND` hides `/doctor` specifically |
| Plan | Some surfaces require a paid or specific plan tier |
| Platform / provider | Some surfaces are absent on some OSes, and several are unavailable on non-first-party model providers |
| Host surface | CLI, web/cloud, VS Code, and mobile expose different rosters; terminal-interface commands do not exist in a web session, and a cloud session carries session-provided skills a local CLI does not |

Claim, basis, and trigger for that table, per [`upstream-drift`](../upstream-drift/README.md):
the four axes are documented on `https://code.claude.com/docs/en/settings-reference.md`
(`disableBundledSkills`, `skillOverrides`), `https://code.claude.com/docs/en/env-vars.md`,
`https://code.claude.com/docs/en/commands.md` ("Not every command appears for every user.
Availability depends on your platform, plan, and environment."), and
`https://code.claude.com/docs/en/cloud-environments.md`; verified 2026-08-23; **recheck trigger** —
a Claude Code release note or docs change adds, removes, or renames a gating axis, or a
`skillOverrides` state leaves the four-value set.

The consequence is the rule: **a component never states that a native surface is present, absent,
enabled, or unavailable.** It states what to do *if the surface resolves in the session*, and the
model reads its own listing to decide.

## The description phrase

The routing-effective surface is the frontmatter `description`, because descriptions load into
model context by default while bodies load only on invocation. One clause, front-loaded, matching
this grammar:

```text
When the <class> <name> <surface-noun> resolves in your session, prefer it for <native's job>;
this skill for <ours>.
```

Four required parts:

1. **The gate** — `resolves in your session` (or `resolves in this session`). This is the
   canonical, greppable token. It is a read-time condition on the model's own listing, not a claim
   about the machine. `if installed`, `always available`, `Claude Code ships`, and `is built in`
   are all wrong here: the first is the cross-plugin gate, the rest are assertions.
2. **The provenance class** — `bundled`, `built-in`, `plugin-backed built-in`, or
   `session-provided`, named in the sentence. The classes behave differently (different disable
   switches, different rosters per host), and a reader who cannot tell which one they are looking
   at cannot check the gate.
3. **The routing split** — what the native surface is preferred *for*, and what this component is
   preferred *for*. A gate with no split tells the model a thing exists without telling it when to
   pick which, which is the duplication the reference exists to stop.
4. **Self-containment** — the phrase carries its own meaning with no external lookup.

Worked example, in the shipped shape:

```text
When the bundled doctor skill resolves in your session, prefer it for the quick native
health-and-fix pass; this skill for the deep read-only install-tree inventory.
```

**Absent is not a fallback state.** Unlike a cross-plugin seam, there is nothing to degrade to: the
component's own job is the fallback, and the split sentence already says what that job is. Do not
write "otherwise this skill" — it is noise the shared budget pays for.

### Budget caveat

Descriptions are subject to two limits, and a baked phrase is the best available routing surface,
not a guaranteed one:

- the combined `description` + `when_to_use` text is truncated at **1,536 characters** in the
  listing by default (`skillListingMaxDescChars`); and
- the listing as a whole is capped at a **share of the context window**
  (`skillListingBudgetFraction`, default 1%). On overflow the listing keeps every skill *name* and
  drops whole descriptions, starting with the least-invoked skills.

Basis: `https://code.claude.com/docs/en/skills.md` (Frontmatter reference; Troubleshooting →
"Skill descriptions are cut short") and `https://code.claude.com/docs/en/settings-reference.md`;
verified 2026-08-23. **Recheck trigger** — a release or docs change moves the 1,536 default, the
1% default, or the drop-order rule.

Two obligations follow. Keep the phrase to one clause, since it spends shared budget every session
for every consumer. And where a fleet's listing plausibly overflows, the overlap store records a
per-row *phrase may be budget-dropped* caveat, so nobody later reads a baked phrase as a guarantee
that the model saw it.

### Open consideration — the bundled keep-set

A single-source, unconfirmed read of a shipped build suggests bundled entries may be exempt from
budget dropping, which would make native/marketplace routing asymmetric under pressure. It is
recorded here as an open consideration and **nothing in this convention builds on it**: no phrase,
no verdict, and no registry row may cite it until a live probe confirms it. **Recheck trigger** —
a live in-session probe confirms or refutes the exemption, or upstream documents the drop order at
the source level.

## The Boundary section

Where a description clause is too small for the real distinction, the component's **body** carries a
fuller section, modeled on the `review` plugin's organic pattern
(`plugins/review/skills/quality-gate/context/pr.md`, `plugins/review/skills/fanout/SKILL.md`):

```markdown
## Boundary — <the native surfaces this skill overlaps>

<One sentence naming the surfaces and why they are conflated.>

- **<name> (<provenance class>)** — what it does, what it mutates, how it is invoked.
- **<name> (<provenance class>)** — same.

**Routing:** <when to prefer each>.

**Mutation gate:** <which invocations mutate, and the explicit opt-in they require>.
```

Five properties the section keeps:

1. **Surfaces named by provenance class**, exactly as in the description phrase.
2. **A mutation gate per surface that mutates.** Naming an overlap without naming what it writes
   invites an unrequested mutation.
3. **One owning description, pointers elsewhere.** Where two components in the *same plugin* both
   overlap the surface, one carries the description and the other points at it with a same-plugin
   relative link and adds only what is specific to itself. Cross-plugin pointers are forbidden.
4. **Presence-gated language throughout** — the body inherits the description's gate; it never
   promotes a surface to available because the body is longer.
5. **Upstream specifics carry their basis and date**, per
   [`upstream-drift`](../upstream-drift/README.md).

## Self-containment — shipped plugins never cite the registry

The overlap store and [`docs/NATIVE-SURFACES.md`](../../NATIVE-SURFACES.md) live in this
repository. A plugin installed from the marketplace does **not** have them: a citation would be a
broken reference at install time, and the reader would be routed to a file that does not exist.

So: baked text repeats what it needs and cites nothing outside its own plugin. The registry is a
maintainer surface — it records the verdict, the evidence, and the trigger that would change them;
the component carries the conclusion. This is the same direction the parity check enforces
mechanically: every baked line traces back to a store row, while a store row without a baked line
is legal pending-sweep state.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A baked native reference traces to a store row | **Deterministic** — built, as the overlap self-check's store↔baked-line parity pass |
| Every store row carries a recheck trigger and a class-tagged observation record | **Deterministic** — built, in the same self-check |
| The phrase uses the presence gate rather than an availability assertion | **Detect-then-judge** — the `resolves in your session` token is greppable, but deciding whether a *different* sentence asserts availability is a judgment about meaning. Candidate check named, not built: flag a component description naming a bundled or built-in surface with no gate token. Build trigger: a second assertion-shaped native reference reaches `main` after this doc |
| The routing split is the right one | **Reasoning-only** — it is the verdict, and verdicts are human-gated by design |

## Adopters

| Surface | What it carries |
|---|---|
| `plugins/claude-ops/skills/audit-install-state/SKILL.md` | Description phrase + `## Boundary` section for the bundled `doctor` skill (verdict `complementary`) |
| `plugins/review/skills/quality-gate/context/pr.md`, `plugins/review/skills/fanout/SKILL.md` | The organic Boundary pattern this doc generalizes; adopts the phrasing rules on next touch |

Fleet-wide application is a reserved, separately gated sweep: one plugin per unit — apply, verify,
PR, close — never a single fleet-wide edit.

## Versioning

Changing a required part of the description phrase, the canonical gate token, or an enforceability
verdict is a major change to this contract; additive guidance is minor; clarification is a patch.
This doc is README-only today; a `CHANGELOG.md` lands here the first time a versioned change is
made, per the convention-registry shape.

## External authority

- `https://code.claude.com/docs/en/skills.md` — description loading, the per-entry cap, and the
  listing budget's drop behavior.
- `https://code.claude.com/docs/en/settings-reference.md`,
  `https://code.claude.com/docs/en/env-vars.md` — `disableBundledSkills`, `skillOverrides`,
  `skillListingMaxDescChars`, `skillListingBudgetFraction`, and the env twins.
- `https://code.claude.com/docs/en/commands.md`,
  `https://code.claude.com/docs/en/cloud-environments.md` — plan/platform gating and per-host
  roster differences.

Upstream publishes no convention for deferring to its own surfaces (absence checked 2026-08-23
against the pages listed above and `https://code.claude.com/docs/llms.txt`), which is why this
repository owns one.
