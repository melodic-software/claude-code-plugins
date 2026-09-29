# Native references: presence-gated phrasing for Claude Code's own surfaces

Owner doc for **how a component in this marketplace refers to a native Claude Code surface**,
whether a built-in CLI command, a bundled skill, a plugin-backed built-in, a built-in subagent or
tool, or a session-provided skill, when that surface materially overlaps what the component does. One shape: a read-time
presence gate that routes, never an assertion that the native thing is there.

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
  committed overlap store rendered into [`docs/native-surfaces.md`](../../native-surfaces.md).
  This doc governs the words once a verdict says a reference is warranted.
- **The stamp discipline on any upstream fact a reference restates.**
  [`upstream-drift`](../upstream-drift/README.md) owns the four-part record (claim, basis, as-of
  date, recheck trigger) and the observability bar its triggers must clear.
- **Instruction economy.** [`plugin-philosophy`](../../plugin-philosophy.md) owns the rule that
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
`https://code.claude.com/docs/en/cloud-environments.md`; verified 2026-08-23; **recheck trigger**:
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
When the <class> <name> <surface-noun> resolves in this session, prefer it for <native's job>;
this skill for <ours>.
```

Four required parts:

1. **The gate**: `resolves in this session` (the retired spelling `resolves in your session` is
   no longer accepted). This is the canonical, greppable token. It is a read-time condition on the model's own listing, not a claim
   about the machine. `if installed`, `always available`, `Claude Code ships`, and `is built in`
   are all wrong here: the first is the cross-plugin gate, the rest are assertions.
2. **The provenance class**: `bundled`, `built-in`, `plugin-backed built-in`, or
   `session-provided`, named in the sentence. The classes behave differently (different disable
   switches, different rosters per host), and a reader who cannot tell which one they are looking
   at cannot check the gate.
3. **The routing split**: what the native surface is preferred *for*, and what this component is
   preferred *for*. A gate with no split tells the model a thing exists without telling it when to
   pick which, which is the duplication the reference exists to stop.
4. **Self-containment**: the phrase carries its own meaning with no external lookup.

Worked example, in the shipped shape:

```text
When the bundled doctor skill resolves in this session, prefer it for the quick native
health-and-fix pass; this skill for the deep read-only install-tree inventory.
```

**Absent is not a fallback state.** Unlike a cross-plugin seam, there is nothing to degrade to: the
component's own job is the fallback, and the split sentence already says what that job is. Do not
write "otherwise this skill", which is noise the shared budget pays for.

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
verified 2026-08-23. **Recheck trigger**: a release or docs change moves the 1,536 default, the
1% default, or the drop-order rule.

Two obligations follow. Keep the phrase to one clause, since it spends shared budget every session
for every consumer. And where a fleet's listing plausibly overflows, the overlap store records a
per-row *phrase may be budget-dropped* caveat, so nobody later reads a baked phrase as a guarantee
that the model saw it.

### Open consideration: the bundled keep-set

A single-source, unconfirmed read of a shipped build suggests bundled entries may be exempt from
budget dropping, which would make native/marketplace routing asymmetric under pressure. It is
recorded here as an open consideration and **nothing in this convention builds on it**: no phrase,
no verdict, and no registry row may cite it until a live probe confirms it. **Recheck trigger**:
a live in-session probe confirms or refutes the exemption, or upstream documents the drop order at
the source level.

## The Boundary section

The Boundary section is the surface a verdict lands on. **A store row whose verdict is not `defer`
and whose observation is extraction-evidence lands together with its `## Boundary` section in the
component's body, in the same change.** A verdict that lives only in the store changes nothing the
model reads: the registry is a maintainer surface and shipped plugins never carry it, so until the
body says how the two surfaces relate, the overlap the row records is still silent at runtime.
The section costs nothing the description phrase costs. Bodies load only on invocation, so a
Boundary section spends no shared listing budget and changes no routing; the gate the phrase
earns (below) has no reason to hold the section back.

The section carries the conclusion: the surfaces by provenance class, the routing split, and the
mutation gate. The four-part records behind it (the basis each upstream specific rests on, its
as-of date, its recheck trigger, the extraction or docs evidence) live in a **reference file inside
the same skill**, linked from the section with a same-plugin relative path, so the body stays short
and the detail stays reachable. Modeled on the `review` plugin's organic pattern (`/review:quality-gate`
and `/review:fanout` each carry one):

```markdown
## Boundary, the bundled `<name>` skill

<One sentence naming the surfaces and why they are conflated.>

- **`<name>` (<provenance class>)**: what it does, what it mutates, how it is invoked.
- **`<name>` (<provenance class>)**: same.

**Routing:** <when to prefer each>.

**Mutation gate:** <which invocations mutate, and the explicit opt-in they require>.
```

Six properties the section keeps:

1. **Every overlapped surface named in the section, as a code span.** `## Boundary` on its own is
   a heading any prose satisfies, and several components carry one for a surface this convention
   has no verdict on. The heading naming the surface is the preferred shape and is what the
   template above shows; a generic `## Boundary` heading is still accepted when the section text
   names the surface, which is how one section covers a component that overlaps several. Either
   way the name is a code span, so a surface whose name is also an ordinary English word (`run`,
   `design`) is never satisfied by a sentence that happens to use the word.
2. **Surfaces named by provenance class**, exactly as in the description phrase.
3. **A mutation gate per surface that mutates.** Naming an overlap without naming what it writes
   invites an unrequested mutation.
4. **One owning description, pointers elsewhere.** Where two components in the *same plugin* both
   overlap the surface, one carries the description phrase and the other points at it with a
   same-plugin relative link and adds only what is specific to itself. The rule governs
   description phrases only: a second skill may carry a Native step or a suggest sentence for
   the same surface, with a same-plugin pointer to the owner's Boundary, and never a second
   phrase. Cross-plugin pointers are forbidden.
5. **Presence-gated language throughout**: the body inherits the description's gate; it never
   promotes a surface to available because the body is longer.
6. **Upstream specifics carry their basis and date**, per
   [`upstream-drift`](../upstream-drift/README.md).

## Self-containment: shipped plugins never cite the registry

The overlap store and [`docs/native-surfaces.md`](../../native-surfaces.md) live in this
repository. A plugin installed from the marketplace does **not** have them: a citation would be a
broken reference at install time, and the reader would be routed to a file that does not exist.

So: baked text repeats what it needs and cites nothing outside its own plugin. The registry is a
maintainer surface: it records the verdict, the evidence, and the trigger that would change them;
the component carries the conclusion. The parity check enforces the forward direction
mechanically: every baked line traces back to a store row, and a claimed Boundary section must name
that row's surface rather than merely carry the heading. In the other direction the two baked
surfaces differ. A row without its Boundary section is a defect the self-check fails on, because
the section costs nothing and can always land in the change that adds the row; a row without a
description phrase is legal pending state, because the phrase is the budget-priced,
routing-affecting half and earns its separate gate.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A baked native reference traces to a store row | **Deterministic**: built, as the overlap self-check's store↔baked-line parity pass |
| Every non-`defer` extraction-evidence row has its Boundary section (`baked.boundary_section` true, and a `## Boundary` section in the component naming that row's surface as a code span) | **Deterministic**: built, in the same self-check, as a blocking problem (exit 1). The tier carries no advisory grade: advisory belongs to detect-then-judge, where a tool narrows a set a human then rules on, and nothing here needs a ruling. A consumer gate passes a degraded run because degraded reports what this repository cannot fix by editing its own files; a missing section is fixable in the change that adds the row |
| Every store row carries a recheck trigger and a class-tagged observation record | **Deterministic**: built, in the same self-check |
| The phrase uses the presence gate rather than an availability assertion | **Deterministic**: built. The overlap self-check flags a description that names a bundled or built-in surface behind a presence condition with no gate token. Deciding whether some other sentence asserts availability remains a judgment about meaning; the built check is the greppable candidate, and it blocks as an advisory (exit 3), not as a store defect |
| A `wrap` row's Native step and a `suggest` row's sentence trace to the store | **Deterministic**: built, in the same self-check. Forward parity looks for the heading `## Native step: <name> (<class>)` and for the sentence shape `If /<name> is available in your session (`. Reverse parity scans bodies for that sentence shape only, never the bare phrase |
| The routing split is the right one | **Reasoning-only**: it is the verdict, and verdicts are human-gated by design |

## Adopters

| Surface | What it carries |
|---|---|
| `/claude-ops:audit-install-state` | Description phrase + `## Boundary` section for the bundled `doctor` skill (verdict `complementary`) |
| `/review:quality-gate`, `/review:fanout` | The organic Boundary pattern this doc generalizes; adopts the phrasing rules on next touch |

| `/claude-config:audit-instructions` | `## Boundary` section for the bundled `claude-api` skill's `prompt-audit` subcommand (verdict `complementary`, composite posture), four-part detail in the skill's own reference file; no description phrase |
| `/evals:methodology` | `## Boundary` section for the bundled `claude-api` skill's `hillclimb` and `build-eval` subcommands (verdict `complementary`); detail in the skill's eval-design reference |
| `/playbooks:fable-5` | `## Boundary` section for the bundled `claude-api` skill as the live-facts and cost-audit surface its chapters defer to (verdict `complementary`); detail in the pack's prompt-caching reference chapter |
| `/review:code-review`, `/review:security-review` | Description phrase + `## Boundary` section for the bundled `code-review` skill and the plugin-backed built-in `security-review` command (verdict `complementary`, CI lane versus session pass); four-part detail in each skill's `reference/` file |
| `/code-tidying:tidy`, `/code-tidying:batch-simplify` | `## Boundary` sections for the bundled `simplify` skill (verdict `complementary`, diff-anchored versus lane- and sweep-anchored); detail in each skill's reference or context file; no description phrase |
| `/testing:run-e2e` | description phrase, `## Boundary` section and `## Native step` for the bundled `run` skill (verdict `complementary`, integration `wrap`; a look versus evidenced verification); detail in the skill's context file |
| `/claude-ops:audit-performance`, `/claude-ops:audit-skill-visibility` | `## Boundary` sections for the bundled `doctor` skill (and `/skill-doctor` for the second), verdict `complementary`; the second also carries the description phrase; detail in each skill's `reference/` file |
| `/visualization:visualize` | Description phrase + `## Boundary` section for the bundled `design` skill (verdict `complementary`, user-run canvas versus a chosen form and medium); detail in the catalog spoke |
| `/prototype:explore-directions` | Description phrase + `## Boundary` section for the bundled `design` skill (verdict `complementary`, user-run canvas versus throwaway mockup); detail in the skill's `reference/` file |

Applying **description phrases** fleet-wide is a reserved, separately gated sweep: one plugin per
unit, each running apply, verify, PR, close, never a single fleet-wide edit, because each phrase
and spends shared budget. **Boundary sections** are not routing-affecting and spend no budget, so
Boundary-only baking may land across several plugins in one change; the unit rule does not apply
to it.

## Runtime relationship

`verdict` says whether the surfaces overlap. `integration` says what a component does about it
at runtime. Every store row carries one of `route`, `wrap`, or `suggest`.

| Class | Values |
|---|---|
| `builtin-command` | `route` or `suggest`. Never `wrap`: a built-in command is not invoked by the Skill tool |
| `bundled-skill` | `route` or `wrap` |
| `bundled-skill` carrying `model-invocation-disabled` | `suggest` only. The model never lists the surface, so a route phrase is dead text. The marker is set from the registration the row's evidence names, never from the bare name |
| `bundled-workflow` | `route` or `suggest`. Never `wrap`: the Native step invokes through the Skill tool, and a workflow is not a skill |
| `plugin-backed-builtin` | `route` or `wrap` |
| `marketplace-plugin` | `route` or `wrap`. The wrap grammar for this class is seam-phrasing's, not the Native step below |
| `session-skill` | `route` only |
| `builtin-agent`, `builtin-tool` | `route` only. The model reaches a built-in subagent through the Agent tool's `subagent_type` and a built-in tool by its name, never through the Skill tool, so nothing wraps one; neither is a command a person types, so nothing suggests one |
| verdict `defer` | `route`, and this wins over the class, including a model-disabled bundled skill. Nothing is baked from a defer row |

A `wrap` or `suggest` row carries an evidence line naming the observed invocation mode. Skill-tool
reach is per surface; the class rules are a floor.

## The Native step (wrap)

A `wrap` row bakes a body section, not a second description phrase. The heading is literal:

```text
## Native step: <name> (<class>)
```

In order, the section carries:

1. The gate token `resolves in this session`.
2. The identity check by class. Bundled: the name is in the listing; invoke by alias where the
   Skill tool resolves one; check the description as advisory. A description that reads as a
   different surface is a likely user or project shadow, so skip with a warning, except where
   the bundled surface itself defers to a project skill of the same name, as `run` does. A name
   with no description, which `name-only` and budget overflow both produce, is invoked with a
   stated "identity confirmed by name alone" warning. Plugin: the namespaced form, plus
   marketplace provenance when the CLI resolves it.
3. The mutation clause. A mutating surface may be wrapped only where the wrapping skill's own
   contract mutates the same thing, the invocation passes an explicit scope or report-only
   argument, the skill fingerprints what the surface may write before the step and diffs after,
   and an unexpected diff is reported as "mutation detected after a scoped invocation", with the
   run exiting degraded.
4. The invocation form, and what this skill adds before or after the native step.
5. The skip-and-report contract for `did not resolve in this session`, invocation refused (the
   report names the reason and never retries: not in the session's skills allowlist, disabled
   for model invocation by `disableBundledSkills` or `skillOverrides`, or a permission deny,
   which is alias-aware), identity mismatch, mutation detected, and resolved but degraded (the
   surface ran a weaker procedure and said so; the wrapper relays that disclosure and never
   restates the step as the full procedure). Each state names the axis line `settings or
   environment, plan, platform or provider, host surface` and the enable path.
6. A note that the wrapped body enters context once and stays there.
7. The bare `unattended` argument, declared by the caller, under which the skill records
   instead of asks and never invokes a mutating surface.

## The suggest sentence

A `suggest` row addresses the person, not the model. The sentence shape is:

```text
If /<name> is available in your session (<basis>), run it for <job>.
```

`<basis>` is a same-file four-part verification record per upstream-drift naming the surface's
own gate. For `/doctor` that gate is `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry,
because `/doctor` survives `disableBundledSkills`. For every other bundled skill the gate
includes `disableBundledSkills` as well. Place the sentence at the start of the run when the
surface covers everything the skill does, and at the end when coverage is partial. A
model-disabled bundled skill is suggested as `/<name>` exactly as a built-in command is. The
wording is "reserved for the person to run", never "cannot be invoked" as an absolute. An
unattended run records the sentence in output.

The suggest token `is available in your session (` differs from the route token `resolves in
this session` by design: the route token is a condition the model observes in its listing, and
the suggest token is one the person checks. It is not the rejected assertion phrasing `always
available`. Parity keys on the sentence shape, so unrelated prose that merely says "available
in your session" is not a suggest sentence.

## Versioning

Changing a required part of the description phrase, the canonical gate token, or an enforceability
verdict is a major change to this contract; additive guidance is minor; clarification is a patch.
Version history lives in [`CHANGELOG.md`](CHANGELOG.md), which landed with the first recorded
change; the doc's README-only original state reads as 1.0.

## External authority

- `https://code.claude.com/docs/en/skills.md`: description loading, the per-entry cap, and the
  listing budget's drop behavior.
- `https://code.claude.com/docs/en/settings-reference.md`,
  `https://code.claude.com/docs/en/env-vars.md`: `disableBundledSkills`, `skillOverrides`,
  `skillListingMaxDescChars`, `skillListingBudgetFraction`, and the env twins.
- `https://code.claude.com/docs/en/commands.md`,
  `https://code.claude.com/docs/en/cloud-environments.md`: plan/platform gating and per-host
  roster differences.

Upstream publishes no convention for deferring to its own surfaces (absence checked 2026-08-23
against the pages listed above and `https://code.claude.com/docs/llms.txt`), which is why this
repository owns one.
