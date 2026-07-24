---
outcome: design-in-progress
tier: A
date: 2026-07-24
---

# Phase 6 — the checks and the sweep

Tasks #19 and #22–#27 (two new checks and four edits to existing ones, per the proportionality gate)
and #28 (the sweep). Naming is resolved separately and is carried here as `<sweep>` until it lands.

## D1 — cross-surface instruction conflict

The deliverable's entire officially-backed payload. It ships as check **I12** in
`claude-config/skills/audit-instructions/reference/criteria.md`.

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

`behavioral`, not `mechanical`: deciding that two instructions cannot both be satisfied is a
judgement about meaning, not a pattern match. That places it outside the diff-clean gate and inside
the stability tolerance, per [rerun-contract.md](rerun-contract.md) P4 — a consequence worth stating
plainly, because it means **the deliverable's primary check does not contribute to its headline
determinism property.** The mechanical part is the inventory, not the comparison.

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
conflict findings sit in the behavioral tier under the stability tolerance. Merging them would have
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
periodically to remove outdated or conflicting instructions." The docs prescribe the review and ship
no tool that performs it.

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

`/claude-config:<sweep>`. A skill in `claude-config`, not a new plugin.

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

- **Naming.** A ranked shortlist exists and the choice is the operator's; `<sweep>` stands until it
  lands. **What the naming pass settled regardless of which name wins is more important than the
  name.** `audit-instructions`' description opens with this exact surface list — "user + project
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
- **The suppression record's location and format.** Deliberately not decided here. This repository has
  config-cascade and consumer-config-layering conventions plus at least one live consumer-side config
  file, and inventing a new consumer surface against an existing convention is precisely the failure
  this work audits others for. Under research; the answer must come from the conventions and the
  existing population, not from what seems reasonable.
