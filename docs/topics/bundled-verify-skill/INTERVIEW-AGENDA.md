# Interview agenda — packaging against the bundled `/verify`

Decision input for `/planning:interview`. Findings live in [RESEARCH.md](RESEARCH.md); this file is
only what has to be **decided**, with everything already settled marked as such so no round
re-argues it.

## How to run this

**One interview, not two.** `/planning:interview` takes `[action] [topic]` — free-form. It has no
input slot for a validation-answer-set artifact, and the verification-loops handoff in
`.work/claude-com-blog-building-verifi-baa0094f/interview-handoff.md` was built for that slice's own
graduation flow, not for ingestion here. So the four of its open questions that bear on this
decision are extracted below with their RECOMMENDED dispositions carried verbatim-in-substance.
Running two interviews would duplicate the frontier; running this one without the extractions would
re-argue settled ground.

The remaining 19 OQs and 12 profile amendments in that handoff are about the docpage-digest campaign
itself and are **out of scope here** — they still need their own sitting, and this agenda does not
consume, close, or supersede them.

Ledger: one per topic at `.work/bundled-verify-skill/interview-checklist.md` (the skill's default
memory slice).

## Settled — do not re-argue

Each of these is evidence-backed in RESEARCH.md and needs no round.

| Point | Basis |
|---|---|
| We cannot invoke `/verify` from a plugin skill | Tool-layer refusal, reproduced live on 2026-08-10 (RESEARCH §3) |
| `/verify` **can** invoke our plugin skills | Its body instructs it to; none of ours set `disable-model-invocation` |
| A plugin skill cannot shadow or wrap bundled `/verify` | Plugin skills are namespaced `plugin:name` and "cannot conflict with other levels" (docs) |
| Its `ls .claude/skills/` probe cannot see plugin skills | `verifier-` appears in no code path — prose convention only (RESEARCH §5.2) |
| A project `.claude/skills/verify/SKILL.md` at repo root **replaces**, not extends | Docs, v2.1.200+; concurs with handoff **OQ-05-1**, reached independently 2026-08-01 |
| Embedding into a bundled skill is off-limits; chaining is the alternative | The Claude Code team's own published position (blog source line 203, digest 05) |
| Say "bundled", not "built-in" | Handoff **OQ-05-4** — concur, adopted throughout |
| Name which sense of "skill chaining" is meant | Handoff **OQ-05-2** — three documented senses; ours is the blog's, human-triggered |
| Suggest `/verify`, never delegate to it | Already in `testing:run-e2e` and `verification:confirm`; now proven rather than inferred |

**One prior disposition the binary evidence refines.** Handoff **OQ-01-1** recommends carrying a
caveat that bundled `/verify` and `/code-review` are user-invoked only from v2.1.215. That is right,
and RESEARCH §3 narrows it: from 2.1.225 the restriction is the *default* rather than an absolute —
a runtime gate can re-enable model invocation, so two users on one version can differ. The caveat
should say "by default", not "only". This does not change any recommendation built on it.

## Live decisions

### D1 — Which shapes do we build, in what order? *(gated on the experiment)*

Options, from RESEARCH §6:

- **E — prompt shim.** Our skill composes a ready-to-run `/verify <briefing>` naming the installed
  verifier plugins and the detected surface; the user presses it. Writes nothing.
- **C — generator.** A skill that authors the consumer's `.claude/skills/verify/SKILL.md` (and/or
  `verifier-*` shims) so our verifiers are named on disk.
- **D — port the craft.** Take the discipline (§"Craft worth stealing") into `testing:run-e2e` /
  `verification:confirm` with no coupling to `/verify` at all.

**Relationship to prior recommendations, stated so the interview does not treat these as new
proposals.** The handoff already marks two closely-related artifacts **Build**:

- **CA-05-2** — "Wrapper-skill chaining template: reusable SKILL.md skeleton (invoke original, then
  verifier), with a note on shadowing for bundled skills." **Shape E is a refinement of CA-05-2**,
  not a competitor: same chaining posture, with the addition that the handoff could not have known —
  the chain link to a *bundled* skill has to be a user keystroke, so what our skill produces is a
  briefing, not an invocation.
- **CA-05-1** — "Verification-loop placement decision card (standalone / embedded / chained /
  on-every-PR), fold in OQ-05-1's shadowing route." Shape D's natural home. Marked *highest-value
  artifact in the slice*.

Recommended entering position: **E first** (cheap, non-destructive, no consumer footprint), **D
independently** (it depends on nothing), **C only if D2 resolves the destruction hazard**. Do not
lock D1 before the experiment result — a negative result collapses E into D.

### D2 — If C: at what level, and how is the root hazard handled?

Root emission **deletes the consumer's bundled `/verify`** and everything in RESEARCH §4 stops
applying to that repo. Package-level emission (`apps/x/.claude/skills/verify/SKILL.md`) is additive
instead — nested same-named skills coexist under a directory-qualified name.

Sub-questions: package-level only? Root behind an explicit consent step? Or root allowed but the
generated file must restate the discipline it replaces?

### D3 — Do we generate `verifier-*` shims into consumer repos?

A one-line `.claude/skills/verifier-<surface>/SKILL.md` that re-invokes `/testing:run-e2e` makes our
machinery reachable from bundled `/verify`'s probe for *any* entry point, including a bare `/verify`
we are not in the loop for. Cost: generated files in every consumer repo, and a second thing to keep
in sync.

Note the entry-point discriminator (RESEARCH §6): E covers the case where the user enters through
our skill; only an on-disk artifact covers the case where they do not.

### D4 — Which plugin owns whatever we build?

`testing` (owns `run-e2e` and the surface-driving machinery) · `verification` (owns the
verdict/evidence vocabulary and the `/verify` references today) · `claude-config` (owns writing into
a consumer's `.claude/`). The generator behavior argues `claude-config`; the domain argues `testing`;
the existing references sit in `verification`.

### D5 — Do we vendor the extracted bundled SKILL.md?

The decoded 2.1.226 text (SKILL.md + both examples, ~16 KB) is reproducible from the recipe in
RESEARCH §Provenance and is currently **not committed** — it is Anthropic's bundled prompt and this
is a public repo. Precedent exists (`plugins/playbooks/skills/boris/vendor/SKILL.md`). Answerable in
one word; independent of every other decision here.

### D6 — Which craft items actually land, and where?

RESEARCH §"Craft worth stealing" ranks seven. The two with the clearest home:

- **BLOCKED as a shared verdict word.** We have the concept and lack the vocabulary:
  `run-e2e` emits a "verification-environment gap report"; `confirm` has only `CONFIRMED` /
  `NEEDS WORK`. One word would align them. This is a cross-skill vocabulary change, so it needs a
  decision rather than a drive-by edit.
- **"What FAIL looks like" sections** in `context/` spokes — symptom → likely cause. Cheap, additive,
  no cross-skill coordination.

## Explicit non-actions

Stated so they are not re-raised as open:

- **The `run-e2e` / `confirm` invocability wording is not being changed.** "User-invoked only from
  v2.1.215" was exactly right for 2.1.215–2.1.224 and the operational guidance it carries
  (suggest, never delegate) is correct and now proven. Reword only if either file is reopened for
  another reason.
- **The 19 out-of-scope OQs and 12 profile amendments** in the verification-loops handoff are
  untouched by this agenda and still pending.

## Blocking input — the experiment

D1 cannot be locked without it. See RESEARCH §"Shape E in detail" and Open Question 6.

**Where:** any repo with this marketplace installed **and** a diff that has a runtime surface. This
worktree does not qualify — it is docs-only, and `/verify` would correctly report SKIP.

**What to type** (adapt the first clause to the actual change):

> `/verify` the <change> on this branch. This repo has `/testing:run-e2e` — orchestrator + Playwright
> with an evidence contract and recording config at `.claude/testing/e2e.md` — and
> `/playwright:playwright`. Use them as your handle rather than cold-starting. They are plugin
> skills, so they will not appear in `ls .claude/skills/`.

**What decides the answer** — three observations, in the report it produces:

1. **Method line** — does it name `/testing:run-e2e`, or does it describe a cold start?
2. **Did it actually invoke it** (a Skill call in the transcript), or only mention it?
3. **Evidence shape** — does the report carry our evidence contract's artifacts (screenshots,
   console, network), or only its own pane captures?

**Reading the result:** 1+2 yes → shape E works, D1 resolves to E-first. 1 yes / 2 no → it accepts
the briefing but won't delegate; E degrades to a better-worded suggestion, still worth shipping.
Both no → E collapses into D, and C becomes the only route to real integration.
