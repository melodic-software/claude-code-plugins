---
outcome: design-in-progress
tier: A
date: 2026-07-24
---

# Phase 6 — the checks and the sweep

Tasks #19 and #22–#27 (two new checks and four edits to existing ones, per the proportionality gate)
and #28 (the sweep). **The sweep is named `audit-pass`**, invoked as `/claude-config:audit-pass` —
see "Naming, resolved" below for what that choice paid.

## D1 — cross-surface instruction conflict

The deliverable's entire officially-backed payload. It ships as check **I12** in
`claude-config/skills/audit-instructions/reference/criteria.md`.

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

`behavioral`, not `mechanical`, in the host catalog's own vocabulary: deciding that two instructions
cannot both be satisfied is a judgement about meaning, not a pattern match. In the sweep's re-derived
tiers it is a **judged** finding, outside the diff-clean gate and inside the stability tolerance, per
[rerun-contract.md](rerun-contract.md) P4.

**That is no longer a mark against D1 specifically.** The first draft flagged it as a consequence
worth stating plainly — the payload not contributing to the headline property. Verification since
showed that *no* dispatched catalog check contributes: `audit-instructions` refines every candidate
through a lane subagent and re-judges every proposal in Phase C, so even `mechanical`-tagged checks
are model-gated. The determinism gate belongs to the derived tier — inventory, exclusion set,
shadowing, raw candidate rows — and D1's exclusion from it is the norm rather than a weakness.

### Detect

Two live instructions that cannot both be satisfied, where no official layering rule already
determines which one wins.

**The comparison set is every surface that can hold instruction text**, and the source's own headline
example is why: "leave documentation as appropriate" against "DO NOT add comments", with the system
prompt, a skill, and the user request clashing inside one request. That is a skill body contradicting
a higher surface, so any scoping that drops skill bodies drops the failure this check exists to
catch.

- `CLAUDE.md` at every scope — managed policy, user, project root, nested, `CLAUDE.local.md`
- `.claude/rules/`, both unscoped and `paths:`-scoped
- skill bodies
- agent definitions
- prompt-type hooks
- output styles

**The one exclusion is narrow and is not surface-wide.** Skills, subagents, and MCP servers override
**by name**: where two of them share a name at different scopes, exactly one is live and the other is
inert. That is a shadowed definition, not a conflict. Override-by-name says nothing about a skill's
*content* contradicting another surface's content, and the first draft of this scoping wrongly read
it as though it did.

**Shadowed definitions are reported, separately, and the split earns something.** A shadowing is
worth telling an operator about — it is usually unintentional, and an inert definition that looks
live is its own trap — but it is not the conflict D1 detects, and folding it in would inflate D1's
finding set with non-conflicts.

The split also buys a property the sweep needs. Detecting a shadowing is **name comparison across a
known precedence order: mechanical and fully deterministic**, where D1 proper is behavioral. So the
shadowing finding lands in the **mechanical** tier and contributes to the diff-clean gate, while D1's
conflict findings sit in the judged tier under the stability tolerance. Merging them would have
dragged a deterministic check into a non-deterministic section and weakened the determinism property
for nothing.

Reported at `info`, in its own section, naming the live definition and the shadowed one.

### Must NOT flag

Each of these is a real case drawn from this repository or from official documentation, per the
phase's own requirement that every check ship with at least one case it must not flag.

1. **A more-specific instruction narrowing a broader one.** `features-overview` states that for
   `CLAUDE.md` conflicts "Claude uses judgment to reconcile them, with more specific instructions
   typically taking precedence". A nested `CLAUDE.md` tightening a root rule for one subdirectory is
   the mechanism working, not a defect.
2. **A shadowed same-named skill, subagent, or MCP server.** Exactly one is live.
3. **Format-steering against behavior-steering.** "Prefer tables for comparisons" and "do not add
   explanatory prose to code" are not in conflict; they govern different things. This is the same
   distinction `audit-instructions` I9 already draws when it refuses to flag examples that steer
   output format, tone, or structure.
4. **A conditional and an unconditional instruction whose conditions are disjoint.** "In tests, mock
   the clock" and "in production code, never mock the clock" cannot both fire on one file.
5. **A managed-policy instruction and a lower-scope instruction that agree in substance but differ in
   wording.** Redundancy is I1's and `extract-ssot`'s concern, not this check's.

### Remediate

- Where both instructions are in surfaces the operator owns: reconcile, and say which one to change.
  Do not propose deleting either by default — a conflict is evidence that two intentions exist, and
  which one is correct is not derivable from the text.
- Where one side is **managed policy**: report as "conflicts with org policy at `<path>`" and
  **never propose an edit to the policy side, nor an edit to the lower side justified by the
  conflict alone.** `claudeMdExcludes` cannot reach the managed tier, so the lower surface may well
  be the correct thing to keep and the policy the thing to seek an exception to. That is an
  organizational decision, not a linting one.
- Where one side is a **chezmoi-managed user-scope file**: route as a recommendation through the
  dotfiles repository. Never an in-place edit.

### Source

Memory doc, "Consistency": "if two rules contradict each other, Claude may pick one arbitrarily.
Review your CLAUDE.md files, nested CLAUDE.md files in subdirectories, and `.claude/rules/`
periodically to remove outdated or conflicting instructions."

### An incumbent exists after all, and D1 is scoped around it

**"No tool performs this review" is false, and it was the premise of this whole check.**
`claude-memory/skills/audit/reference/criteria.md` ships **C6: Consistency [FAIL]** — *"Do any
instructions contradict each other across CLAUDE.md, CLAUDE.local.md, and rules files?"*, with
"FAIL for contradictions (Claude picks one arbitrarily)" — citing the **same official line** this
plan cites as evidence that nothing performs the review. Found by cross-vendor review; verified
verbatim. It is the third time this work has made a negative claim about a body nobody read, and the
first time it happened to the deliverable's only officially-backed payload.

**What survives, and why it is still the article's headline case.** C6 compares *within the memory
layer only* — `CLAUDE.md`, `CLAUDE.local.md`, and rules files. It does not reach skill bodies, agent
definitions, prompt-type hooks, or output styles, it does not compare *across* layers, and it does
not know about the managed-policy tier. The source article's own example — "leave documentation as
appropriate" against "DO NOT add comments", system prompt versus skill versus request — is a
**cross-layer** conflict, which no incumbent detects.

**So D1 is scoped by routing, using the convention this catalog already runs.** I1–I5 route
memory-layer findings to `claude-memory:audit` when it is installed and fall back to official
guidance when it is not. I12 takes the same shape:

- **A contradiction wholly inside the memory layer** routes to `claude-memory:audit` C6. I12 does not
  report it, so the sweep emits one finding, not two from two plugins with no reconciliation rule.
- **A contradiction with at least one side outside the memory layer** — a skill body, an agent
  definition, a prompt-type hook, an output style — is I12's, and is unowned by anything today.
- **Anything involving the managed-policy tier** is I12's, read-only, per the remediation above.
- **When `claude-memory` is not installed**, I12 states that memory-layer contradictions go
  unchecked and names the skill that performs them, per the design boundary's report-the-gap floor.

**Consequences recorded rather than absorbed quietly.** `coverage-matrix.md`'s S3 verdict is
`GAP` and should be `PARTIAL` with C6 named as the incumbent. The proportionality gate's "no
incumbent compares two instruction surfaces against each other" is true only outside the memory
layer. D1 remains a detector and remains the payload — the cross-layer case is real, unowned, and
officially prescribed — but its scope is smaller than the gate recorded.

### The inventory D1 depends on, and the native-first gate

D1 cannot compare surfaces it cannot see, and the plan forbids building a filesystem walk without
first ruling on the native mechanisms. Each is adopted, rejected with a reason, or deferred with a
trigger:

| Mechanism | Ruling |
|---|---|
| `InstructionsLoaded` hook | **Adopt where available.** It logs "exactly which instruction files are loaded, when they load, and why" — a deterministic enumeration of the live surface, which is strictly better than inferring one from the filesystem |
| `/context` | **Adopt as ground truth for what actually loaded**, and treat any filesystem-derived inventory as a candidate set rather than an answer. Startup scope depends on the launch directory: starting from a subdirectory loads that directory's `CLAUDE.md` plus every ancestor's, so a walk that ignores launch directory is wrong by construction |
| `claudeMdExcludes` | **Adopt as a remediation option**, with its documented floor stated: managed policy files cannot be excluded, and the setting is static rather than per-task |
| `/doctor` | **Defer to it** for the trim-and-migrate half; see the prerequisite contract below |
| `debug-your-config`'s wider surface | **Adopt as the native-first inventory list** — `/context`, `/memory`, `/skills`, `/hooks`, `/mcp`, `/permissions`, `/doctor`, `/status`, plus `claude --safe-mode` and `CLAUDE_CONFIG_DIR` for clean-room comparison. The gate is this list, not `/doctor` alone |

**Output styles are the inventory's hardest case and the reason a filesystem walk alone fails.** They
modify the system prompt directly, default to *removing* Claude Code's built-in software-engineering
instructions unless `keep-coding-instructions: true`, and `force-for-plugin` lets a plugin override
the operator's own `outputStyle` selection. An inventory that walks files and reads settings would
miss the override entirely and would report the operator's selection as live when it is not.

## The other checks

Each is specified in its task; the design constraints that cut across them are here.

- **D2** extends I9's Remediate line with the interface destination. The `OPINION` label attaches to
  the advice, not to the detection — I9 fires on backed grounds and D2 changes only what the operator
  is told to do about it.
- **D3** is a new locality check beside I3, on a different axis: I3 is load *timing*, D3 is
  definition-site *locality*. `OPINION`-tier, default-off.
- **D4** puts a stopping condition on I6 and I8, `claude-config`-local, enabled by default because it
  withholds rather than emits.
- **D6** tightens I3's Remediate line for non-memory surfaces, and its memory half joins D7's C3
  revision. **Its premise is verified, not assumed** — path scoping genuinely defers load
  (first-party repro, 2.1.219), and the four costs it must price are recorded in
  `official-corroboration.md`, including the one no incumbent has: an `@import` *inside* a
  path-scoped rule inlines at session start and defeats the rule.
- **D7** and D6's memory half are one consolidated C3 revision in `claude-memory:audit`.

**No remediation anywhere proposes an `@path` import as a context saving.** The live memory page
states it three times, including "splitting into `@path` imports helps organization but doesn't
reduce context, since imported files load at launch". Every split remediation must name a
load-deferring destination — a skill, or a `paths:`-scoped rule — and price what that destination
costs after compaction.

## The sweep

`/claude-config:audit-pass`. A skill in `claude-config`, not a new plugin.

### Why it is a component and not a runbook

The checks are delegated; the run semantics are not, and the run semantics are the product. Invoking
the incumbents by hand yields none of the exclusion set, the three-scope inventory, finding identity,
suppression memory, resumability, or a single human gate per run. Argued in full in
[proportionality-gate.md](proportionality-gate.md).

### Posture

Bare invocation is **read-only**, per the fixed verb meanings — mutation only behind an explicit
override. The Brief settles on fix-capable, and the convention already sanctions that as an `audit`
verb with an explicit autofix argument, which preserves the safer bare invocation.

### The exclusion set is derived, never hardcoded

Three classes a fix-capable pass would corrupt, all verified present:

- **Registered byte-identical cluster copies** — derived from `scripts/cross-plugin-source-registry.txt`
  at run time, not transcribed. 13 `hook-utils.sh` copies, 4 `artifact-protocol.md`, 2
  `standards-contract.md` today, and the registry is the authority when that changes.
- **Vendored upstream materializations** — the `vendor/` rule, six `SKILL.md` files today.
- **Worktrees** — from `git worktree list` plus gitignore-awareness. A git-tracked enumeration
  excludes them for free where a filesystem walk does not.

**Suppression interacts with this set and the interaction is a hard error, not a warning.** An inline
suppression marker inside a registered cluster copy would make it differ from its siblings and break
the sync path. The run refuses and names the canonical source instead.

### `/doctor` — prerequisite contract, not a hand-wave

- **Version floor:** the trim requires Claude Code v2.1.206 or later.
- **Presence is a three-part prerequisite**, not just a version: the v2.1.205 built-in-to-bundled-skill
  cutover, the `DISABLE_DOCTOR_COMMAND` environment variable, and a `skillOverrides` entry of
  `"doctor": "off"`.
- **Absence classification: optional capability, not required-for-correctness.** When `/doctor` is
  absent the sweep **names it as the missing capability and states what goes unchecked** — the whole
  `CLAUDE.md` trim-and-migrate half, for which this work deliberately builds no replacement. That is
  the design boundary's floor, and it is met by reporting rather than by silently degrading.
- **It is interactive** — it "reports findings first and asks for confirmation before changing
  anything" — so it cannot be driven by an unattended run. The handoff is an operator instruction,
  never a dispatch.
- **Its output is excluded from both finding tiers.** A prompt-based delegate cannot contribute to a
  determinism gate.

### Dispatch

- Every sibling-plugin invocation is **presence-gated with a documented fallback**, per
  `docs/conventions/seam-phrasing/`. A bare unguarded cross-plugin reference is a defect.
- Nothing crosses a plugin boundary except an invocation — no shared criteria file, per
  [seam-resolution.md](seam-resolution.md).
- **Order:** inventory all three scopes first, then run checks, then apply. Inventorying only the
  project scope would let D1 apply fixes against half the picture — it cannot see a project↔user
  conflict from a project-only inventory.
- **Budget.** `audit-instructions` already gates near 20 dispatches. Whether this sweep exceeds a
  session's ceiling and must become a dynamic workflow is measured at Phase 10 against the real
  corpus, not guessed here. What is fixed now is that the run persists incrementally and resumes, so
  exceeding the ceiling degrades into a resumed run rather than a lost one.

### `OPINION` discovery

Every run reports, in one line, how many `OPINION`-tier checks were available, were not run, and the
exact argument that enables them. Without it the tier is shipped-but-unreachable — built at real cost
in Phase 8's gates and evals, and never seen by anyone who does not already know it exists.

### Verification is designed in, not left to the invoker

The sweep's apply-verify step and each check's self-check are author-verifier arrangements, so each
names its fresh-context **non-fork** checkpoint — a fork inherits the parent conversation and is not
independent. The cross-vendor advisor is presence-gated per `docs/conventions/seam-phrasing/`, with a
same-vendor fresh subagent as the stated fallback.

### D6 needs a synthetic fixture

Measured, not assumed: this repository has **zero** `@`-imports, **zero** nested `CLAUDE.md`, **zero**
files under `.claude/rules/`, and **zero** files carrying `paths:` frontmatter. D6's target defects
therefore have no instances here, and a green dogfood run would be evidence the repository is clean
rather than evidence the check works. The fixture is a Phase 6 obligation precisely so Phase 10 does
not mistake one for the other.

## The report and the lanes

Constrained by [rerun-contract.md](rerun-contract.md); specified here now that the dispatch order is
fixed.

**Two files, because incremental persistence and a sectioned report want different shapes.**

- **During the run:** `findings.partial.jsonl` — one JSON object per finding, appended as each lane
  completes. Append-only is what makes §5's incremental persistence real rather than aspirational; a
  single JSON document would have to be rewritten whole on every append, which is exactly the
  operation an interrupted run leaves half-done.
- **At the end:** `findings.json` — a single document assembled from the partial, carrying
  `schemaVersion`, the run and target identity, the version of every catalog consulted, and then the
  finding sections: `mechanical`, `behavioral`, `suppressed`, `delegated` (`/doctor`'s output, which
  is diffed by nobody), and `skipped` — every surface excluded, **with its reason**. A silent
  exclusion reads as coverage; that section is what stops it.

**Resume reads the partial, not the report.** A lane is complete when its terminating record is in
the JSONL, which makes the completion state derivable from the artifact rather than tracked beside
it and able to disagree with it.

**Lanes are (check × surface class), not (check) and not (file).** Per-check lanes would serialize a
check across the whole tree and make a mid-run interruption expensive; per-file lanes would multiply
manifest overhead by the corpus size. Surface class is also the granularity the exclusion set and the
three-scope inventory already work at, so the lane key falls out of structure that exists rather than
being imposed on it.

## Open in this phase

- **Naming — resolved. `audit-pass`.** Operator's choice, 2026-07-24, from a 32-candidate five-lens
  tournament. What it claims: one bounded, coordinated, ordered, resumable pass over a named target.
  **What it pays, recorded so nobody re-litigates it:** the qualifier is thin; "pass" invites a
  pass/fail reading the design explicitly disclaims; the sibling family's object-prior lets it
  misparse as "audit the pass"; and in compiler usage a *pass* is a member of a sequence while the
  coordinator is the *pass manager*, so the term names one level down. Those are underspecification,
  not misdescription — which is why it beat `audit-battery`, `audit-campaign`, and `audit-cycle`,
  each of whose verified field meaning actively contradicts the design.

  **The runner-up was `audit-combined`**, and it is worth knowing why it lost: ISO 19011's *combined
  audit* — one audit at a single auditee covering two or more otherwise-separate management systems
  — is literally this artifact's coordination difference, the only candidate whose established field
  meaning matched rather than approximated. It lost on readability, and because the accuracy it
  bought is the same distinction the description is already committed to carrying.

  **An earlier framing was rejected and should not come back.** The operator's own first instinct —
  "auditing the instructions to make sure they are aligned with the latest guidance" — produced no
  survivor across eight candidates. It mispoints: D1, this skill's entire officially-backed payload,
  detects two of the *target's own* instructions that cannot both be satisfied, which is internal
  self-consistency consulting **no external guidance at all**. "Alignment with current guidance" is a
  property of the criteria catalogs' recheck triggers, which live in the plugins this sweep
  delegates to — so the framing names what is delegated. It is also
  `re-anchor:recheck-against-upstream`'s trigger space nearly verbatim. Also killed on merit:
  `audit-sweep`, this document's own former placeholder, because a security sweep is *one* test
  across *many* assets — the inverse of this — and `audit-universe`, which is the rejected `estate`
  wearing an audit hat.

  **What the naming pass settled regardless of the name is still the load-bearing part.** `audit-instructions`' description opens with this exact surface list — "user + project
  `CLAUDE.md`, `.claude/rules`, skill bodies, agent definitions, prompt-type hooks, output styles" —
  character for character. So **the surface cannot be the distinguisher, and no name can carry the
  distinction alone.** The picker labels rows by short name and readers scan the description's first
  clause, so this skill's description **must open with the run semantics** — a coordinated
  cross-scope pass over a named target, fix-capable behind an explicit override — and must not open
  with the surface. If it opens with the surface, the two skills are indistinguishable in the picker
  no matter which name is chosen. The three real differences a name or description can carry: scope
  (`audit-instructions` says "locally-owned"; this adds the read-only managed-policy tier and routes
  user scope as recommendations), posture (report-only versus fix-capable behind an override), and
  run semantics.

  Also settled: **no leaf-name collision exists for any candidate** — checked by exact match against
  all 125 unique leaf names in the tree — so **no `skill-leaf-name-registry.txt` entry is needed, and
  adding one speculatively would fail `--check`**, because an entry that no longer collides is itself
  a failure mode. And `docs/CATALOG-TAXONOMY.md` does not reach this decision: its form rule governs
  category values, which are the deliberate inverse of the skill-name grammar, and `claude-config`
  stays filed under `claude-code` either way.
- **The suppression record — resolved.** It is **two artifacts, not one**, and the split is already
  codified: `config-cascade` states that it "governs layering and precedence only. Which keys a
  config surface has, what they mean, and how they are validated belong to that concern's own owner
  doc under `docs/conventions/<concern>/`". So an **owner doc** under `docs/conventions/` declares
  the keys and the merge form, and the **instance** — this repository's actual suppressions — lives
  at `.claude/audit-pass.md`, the team layer of the three-layer cascade.

  Decided with it:

  - **Per-entry keyed by finding id**, never a list. A closed list is "taken whole, never unioned",
    so one personal suppression would silently discard every team suppression. The conforming shape
    is `plugin-quality`'s repo-map merge — a later layer's entry for X wins for X only.
  - **Policy-floor inversion: the team layer wins on conflict.** A personal overlay suppressing a
    finding the team never accepted is exactly the "personal layer weakens a team standard" shape the
    sanctioned inversion exists for. Declared next to the keys, as the convention requires.
  - **Reason and date required on every entry.** This has **no precedent** on any suppress path here
    — the closest analogue stores bare ids — and the precedent is not transferable: that mechanism
    justifies its bare form by arguing its opt-out can only cause junk to be missed, never removed. A
    findings suppression can hide a real defect and cannot make that argument.
  - **Claude-specific today, and the caveat is recorded.** Every surface in the audit set is a Claude
    Code artifact, so a finding about one belongs under `.claude/`. `AGENTS.md` is the case that
    would break that — cross-vendor by construction, and not currently in the partition. If it enters
    scope (task #56), the location argument must be re-derived rather than inherited.
  - **One in-repo precedent went the other way and is not being followed:** `review` declined to add
    a config surface for smell suppression, letting it ride existing project docs. Rejected here
    because a suppression that cannot be keyed cannot be checked for staleness, and a stale
    suppression is how a corpus quietly loses a check.
