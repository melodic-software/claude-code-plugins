# Rightsize instruction surfaces by incumbent-first arbitration, not blanket constraint deletion

- Status: accepted
- Date: 2026-07-25

## Context

A practitioner article on context engineering — *"The new rules of context engineering for Claude 5
models"*, Thariq, 2026-07-24, <https://x.com/trq212/status/2080710971228918066> — argued that
instruction surfaces accrete constraints a capable model no longer needs, and prescribed deleting
them so the model can use surrounding context and judgement instead. The source is named here rather
than restated because the digests that measured it are working material and prune with the contract
slice; a reader auditing this ADR's premises reads the article, not a copy of it. Thirteen blind
section digests measured that argument against this
repository's actual instruction surfaces — `CLAUDE.md`, `.claude/rules/`, 181 skill bodies, agent
definitions, hook text, output styles — each digest produced without sight of the others so agreement
between them would be evidence rather than echo.

Two forces shaped the outcome. First, roughly a third of the article's claims carry no authoritative
backing, so adopting them wholesale would trade measured constraints for a practitioner's stated
practice. Second, and more decisively, the digests kept rediscovering that a proposed remediation
already shipped somewhere in this repository — the strongest instance being a complete
evidence-tiered criteria catalog at
`plugins/claude-config/skills/audit-instructions/reference/criteria.md`, which nobody looking at the
discovery surface could see.

The competing posture was the article's own: delete constraints by default and let judgement fill the
gap. This repository had already chosen the opposite where safety is involved, so the real question
was where each posture applies rather than which wins outright.

## Decision

The operator ratified the full recommendation set on 2026-07-25. Each row below is binding on every
lane that follows. A lane that finds a locked decision wrong reports it and stops; it does not
re-decide.

### Scope and posture

| # | Decision | Consequence |
|---|---|---|
| D-1 | **Incumbent-first gate is binding.** No remediation ships until it proves no existing skill already covers it | Every lane's first work item is an incumbent search with `path:line` evidence |
| D-2 | **`UNBACKED` claims are report-only and opt-in.** Never auto-applied | Roughly a third of the article's claims. They ship marked, disabled by default, with a severity ceiling |
| D-3 | **No bulk sweep of `plugins/**`.** Findings land as checks in the plugin that already owns each surface | `claude-config`, `claude-memory`, `skill-quality` are the homes. No new router |
| D-4 | **This effort ships two things**: the criteria catalog, and the cross-surface instruction-conflict detector | The conflict detector is the one finding with no incumbent and no existing ticket |
| D-5 | **Verifier-subagent pattern stays, narrowed.** Drop blanket dispatch on mechanical behavior-preserving work; keep it where the verdict is subjective or blast radius is wide | Resolves the three-way tension between Opus 5 guidance, Claude Code best practices, and 23 implementing skills |
| D-6 | **`plugins/playbooks/skills/fable-5/**` is excluded** from this pass | PR #1261 is actively rewriting it |

### Sequencing

| # | Decision | Consequence |
|---|---|---|
| D-7 | **Fold the listing-budget material into issue #1271**, and adopt its `when_to_use` lever | #1271 already measured the defect and found the field this effort's agents missed. No second ticket |
| D-8 | **Sequence behind PR #1096** for anything touching `check-skill.sh` or `docs/PLUGIN-PHILOSOPHY.md` | Check 21 is taken. New criteria pick a free number against the post-merge file |
| D-9 | **Sequence the user-scope work behind dotfiles PRs #318 and #312**, and read #312's Opus 5 re-derivation as an input before measuring | Measuring `dot_claude/CLAUDE.md` while two PRs edit it produces a diff that reverts newer rules |
| D-10 | **Drop the stale dotfiles branch** `docs/claude-md-github-conventions` (+13 lines to `CLAUDE.md`, last commit 2026-07-15, no PR) | One fewer writer on the contested file |
| D-11 | **Reconcile with issue #1225 before building anything sweep-shaped** | Two repo-wide sweeps become two routers |

### Machine health (from `/doctor`, 2026-07-24)

| # | Decision | Consequence |
|---|---|---|
| D-12 | **Fix the `guardrails` PreToolUse root cause.** p50 12–19s blocking every Bash call, ~1,464 runs in six days; a sibling guard in the same event class runs at 2ms | Not a matcher narrowing, not a disable. Root cause |
| D-13 | **Remove the zero-usage plugins** except `plugin-quality`, `context-guard` (both shipped the same day) and `visualization` (one hit under a different leaf name) | ~16 plugins, ~7.4k est. resident tokens |

### Operator-reserved calls (ratified 2026-07-25, second round)

These are the questions the section agents explicitly declined to answer, plus the scope boundary.

| # | Decision | Consequence |
|---|---|---|
| D-14 | **Execution scope is the collision set plus this effort** — the four sequencing blockers (#1096, #1261, dotfiles #318/#312), the two tickets folded into (#1271, #1225), the two machine-health fixes (D-12, D-13), and this effort's two deliverables. Roughly ten lanes | Not the 24-PR / 255-issue backlog. The 12 stale and draft PRs are **not** in scope; they need their own triage pass |
| D-15 | **Arbitration stays the repo's default posture.** Deletion is adopted only where a constraint has no current safety rationale | Overrides the article's blanket delete-constraints posture. A lane proposing a deletion must state the constraint's rationale and why it no longer holds |
| D-16 | **The fresh-docs mandate narrows in scope, not in substance** — it binds changes touching a plugin manifest, marketplace schema, hook contract, or documented harness behavior | Prose and mechanical edits are out. The mandate stays non-negotiable within its scope |
| D-17 | **Auto-memory: move `autoMemoryEnabled` from `claudeSettings.force` to `claudeSettings.seed`, seeded `false`** | Two decisions, both taken. The tier move ends the silent-revert trap; `seed` writes only when absent, so this machine keeps its current value and every fresh machine starts off. Overrides the S7 agent's `true` recommendation on tracked-drift grounds — the capability unlock is available per machine by toggle |
| D-18 | **Cut `CLAUDE.md:13-30`** (the doc-URL table) to a pointer at `docs/OFFICIAL-DOCS.md` | Verified strict subset; 29.6% of the file; line 30 already points at the superset. Accepted risk: the mandate's force must come from the rule, not from the URLs being pre-loaded |
| D-19 | **Vendored `skill-authoring` guidance governs authoring mechanics; this effort's carve-out governs what stays constrained** | Different axes. Where they genuinely collide, upstream wins and the divergence is recorded — a vendored file is never hand-edited |

### Standing constraints these decisions inherit

- **`~/.claude/settings.json` is chezmoi-managed** — verified: its source is
  `dot_claude/modify_settings.json`. D-13's plugin disables are therefore a **dotfiles change**, made
  on a feature-branch worktree of `melodic-software/dotfiles`, never an in-place edit. The same holds
  for `~/.claude/CLAUDE.md`.
- **`.work/` never leaves its checkout.** Anything a later lane must read is stated in this ADR, in
  a companion ADR, or on the tracker — never cited to a working-directory path.
- **The parallel branch** `docs/context-engineering-claude-5-topic` is still being worked by another
  session. This pass runs independently by operator ruling; the collision is resolved deliberately at
  merge, not by folding.

## Consequences

**Every lane pays an incumbent search before it builds.** D-1 makes the search a precondition rather
than a courtesy, and the pass proved the cost is worth paying: one of this effort's two deliverables
dissolved into an extension of a catalog that already existed. The corresponding burden is that a
careless search is now load-bearing — a false negative authorizes duplicate machinery, which is
exactly what happened three times before the C6 incumbent was found.

**No new router exists to own instruction-surface findings.** D-3 routes every finding into the
plugin that already owns the surface, so there is no single place to look for "all instruction-surface
checks" and each owning plugin's advertised scope has to stretch to cover what lands in it. The gain
is that a standing hygiene-sweep composer keeps working, because it composes existing plugins rather
than depending on a new one.

**Constraints are arbitrated, not deleted.** D-15 keeps this repository's safety constraints in place
and admits the article's deletion posture only where a constraint has no current safety rationale.
Removing a constraint now costs an argument about why its rationale no longer holds; the benefit is
that no safety gate is removed by a sweep acting on an unbacked claim.

**Unbacked claims can ship without being trusted.** D-2 gives roughly a third of the article's claims
a home — marked, disabled by default, severity-capped — instead of forcing a binary adopt-or-discard
call on material that is real practitioner experience but unverified.

**Findings that must actually fail CI need a different home.** The plugins that own these surfaces
are model-invoked and report-only, so nothing landing in them blocks a merge. A deterministic finding
follows the `scripts/check-*.sh` + `.test.sh` + `ci.yml` lane shape documented on
[#445](https://github.com/melodic-software/claude-code-plugins/issues/445) instead.

**Three of the nineteen decisions did not survive measurement.** The errata below record what broke
and what still binds. They are kept in this ADR rather than folded into the decisions themselves,
because an accepted ADR is a historical record: the ratified text stays as ratified, and the
correction sits beside it.

## Execution status and errata

Recorded 2026-07-25 at the end of the first execution pass. **The nineteen decisions above are
preserved verbatim as ratified.** Nothing in this section re-decides any of them. Where a decision's
supporting evidence did not survive first-hand verification, the correction is recorded here and the
decision's own text is left untouched.

Three decisions did not survive contact with measurement. In each case the lane reported and stopped
rather than re-deciding, which is what this contract requires of it.

### D-12 — errata: the supporting evidence is invalid; the directive stands

D-12 cites *"a sibling guard in the same event class runs at 2ms"* as its control. **That control
never ran.** Both disk-hygiene comparators failed at launch:

- `destructive_guard.py --mode engine-gate` — all 16 recorded runs are `hook_non_blocking_error`,
  `exitCode: 1`, stderr `Failed to run: Plugin option "disk_hygiene_enabled" isn't set.` The 2 ms is
  config validation refusing to launch, before any process is spawned. `python3 -c 'pass'` costs
  396 ms on this host, so 2 ms was never physically achievable.
- `destructive-guard.sh` — all 57 recorded runs are `hook_non_blocking_error`, stderr
  `execvpe(/bin/bash) failed: No such file or directory` (routed to WSL, which has no `/bin/bash`).

**The real root cause is worse than the decision assumed.** The guardrails hooks are not slow — they
never finish. They are killed at their declared `timeout`, and a killed PreToolUse hook yields
`outcome:"cancelled"` with no `permissionDecision`, so **the tool call proceeds unguarded**. Across
15,845 cancelled runs the fraction finishing under their declared timeout is `0.0000`. Guardrails
PreToolUse timeout rate is 94–100%; machine-wide it is 79.7%. `block-dangerous-git` enforced on ~0%
of calls.

**D-12's directive — fix the root cause, not a matcher narrowing, not a disable — is unaffected and
still binding.** Only its citation is corrected.

Two caveats: the fail-open behavior was read from the decompiled v2.1.219 binary and is **not yet
confirmed against official documentation**; and a second defect follows — **disk-hygiene's
destructive-operation guard has been silently unenforced for the entire measured window**, which
needs its own ticket and is not this effort's to fix.

The underlying evidence is raw capture — transcript scans and hook-event tallies — which the
topic-docs redaction bar keeps out of committed material, so it never left the checkout that produced
it. **The measurements restated above are the committed record**, and anyone re-deriving them starts
from the transcripts rather than from any file.

### D-13 — DEFERRED, not executed: the removal set is empty

Measured against 5,888 transcripts over 30 days — a corpus ~15× larger in file count than the one
behind the original `/doctor` pass, which makes a zero-usage finding stronger evidence, not weaker.

**No seeded plugin qualifies for removal.** All ten zero-invocation seeded plugins are
`PostToolUse` / `PreToolUse` / `Notification` hook plugins. A hook that succeeds silently writes
nothing to the transcript, so "zero usage" is the expected reading for a *correctly functioning,
heavily used* formatter. Their only skill is `setup`, invoked once at install time. Direct proof:
`guardrails` blocked three of the measuring agent's own tool calls during the run.

**Method objection.** The `/doctor` pass measured *invocation* and concluded *usage*. For hook
plugins those are unrelated quantities, and that single error accounts for ten of the sixteen.

**The stated saving does not hold either.** ~7.4k resident tokens versus a measured upper bound of
~0.9–1.1k, and likely ~0 — none of these plugins' `setup` skills appears in the session's skill
listing at all. Executing D-13 would have disabled formatting, linting, EOL normalization, desktop
notifications and the safety guard layer across every machine in exchange for approximately nothing.

**The prescribed mechanism also does not deliver the stated consequence.** `seed` writes only when a
key is absent, and every seeded plugin key already exists live, so editing the seed changes fresh
machines only — it would not have reclaimed a token on this machine. Confirmed against the installer
at `.chezmoiscripts/run_onchange_install-claude-plugins.ps1.tmpl:22-26`, which skips `false` entries
and never uninstalls.

**Status: deferred pending operator re-decision.** Nothing was committed. Any revival must classify
each plugin by **surface type** — hook versus skill/command — before treating a zero as meaningful.

### D-17 — DEFERRED, not executed: correct diagnosis, unexecutable prescription

The diagnosis is **confirmed**: `force` deep-merges with the repo value always winning
(`dot_claude/modify_settings.json:28`), and `seed` writes only when the key is absent
(`:175-182`). The silent-revert trap D-17 names is real.

**The prescribed move cannot be made.** `seed` is structurally two-level — the template ranges over
each section's entries, so every member must be a map — while `autoMemoryEnabled` is a **top-level
scalar** sibling of `model` and `env`. Reproducing the loop verbatim on chezmoi v2.70.5 yields:

```text
chezmoi: template: stdin:5:26: executing "stdin" at <$entries>: range can't iterate over false
```

That is a hard template error, not a silent no-op, and `modify_settings.json` is evaluated on every
`chezmoi apply` — so the move would **abort apply fleet-wide**, on the file carrying the permission
deny list and the destructive-removal guard.

**Status: deferred pending operator re-decision.** Delivering D-17's intent requires a root-cause fix
to the seed loop so it handles a top-level scalar; that changes merge behavior for every owned key
and is its own lane. **Urgency is low**: the live value is already `false`, so the move is a no-op on
this machine either way — D-17 was always a capability unlock, not a behavior change.

### D-6 — exclusion kept after its premise cleared

PR #1261, the reason `plugins/playbooks/skills/fable-5/**` was excluded, **merged 2026-07-25
00:38:24Z**. The operator ratified keeping the exclusion for this pass rather than lifting it
mid-fan-out. The follow-up covering that subtree is filed as
[#1324](https://github.com/melodic-software/claude-code-plugins/issues/1324).

### D-9, D-10 — satisfied, with one permanent loss

D-9's blockers both merged (#318 at 00:08:55Z, #312 at 01:01:46Z), and `main` became #312's merge
commit, so the user-scope work was measured only after every competing writer landed. The
stacked-branch mechanism became unexecutable and was replaced by basing on `main`; the substance was
satisfied in full.

D-10's branch `docs/claude-md-github-conventions` was **already gone** from local refs and the remote
when the lane checked. The decision is satisfied — but the requirement to read its 13 lines before
dropping it could not be honored, so **that content is unrecoverable and its salvage value is
permanently unknown.** Recorded as a real loss, not a clean success.

### The collision register was incomplete while presenting itself as complete

The pass maintained a register of in-flight work colliding with this effort. It **under-counted
writers** on `dot_claude/CLAUDE.md`: it listed three, and **PR #319 was a fourth** — open and editing
that file mid-pass, absent from the register, merged before colliding.

The register itself was working material and is not preserved. The generalizable lesson is what
survives, and it is the part that matters: **a collision register is a point-in-time snapshot, and
this one was demonstrably incomplete while presented as complete. Re-derive collisions from
`gh pr list` at the moment you need them rather than trusting a recorded snapshot.**

### A rename invalidated the pass's recorded paths

PR #1276 merged 2026-07-25T02:13:33Z, after every measurement in this pass was captured. It renamed
the plugin `re-anchor` to **`discipline`** and the skill `sweep-all-disciplines` to **`sweep-all`**
across 45 files. Verified against the tree: `plugins/re-anchor` does not exist;
`plugins/discipline/skills/` carries `sweep-all`.

**Standing instruction for the deferred lanes.** L2, L3 and L4 resume against targets this pass
recorded under the old paths, including targets restated in the PR that carried this effort's working
material. Any such path resolves nowhere today. Read `plugins/re-anchor/` as `plugins/discipline/`,
and `re-anchor:sweep-all-disciplines` as `discipline:sweep-all` — and re-measure the line numbers
rather than trusting them, because the rename moved content the old measurements never saw.

The failure mode this creates is the dangerous one: an incumbent search run against a stale path
silently finds nothing and looks conclusive — the same false-negative shape as the `SKILL.md`-scoped
search recorded below, arriving by a different route.

### Lane execution status

Every lane reached a published outcome. Five were interrupted mid-build by a session usage limit at
02:52–02:54 and resumed afterwards; each row below names the PR or issue that carries its result.

| Lane | Decisions | Outcome |
|---|---|---|
| L0 | design docs | **PR #1323** — this ADR is its durable outcome |
| L1 | D-7 | **PR #1286**, closed unmerged; the measurement folds into #1271 per D-7, and the gate defects it found are #1404 |
| L2 | D-4 | **PR #1343** — Phase B2 of `audit-instructions`, built against C6 rather than duplicating it |
| L3 | D-4, D-2 | **PR #1349** — checks I12–I14 folded into the incumbent catalog |
| L4 | D-12 | **PR #1385**, closed unmerged after fresh-context verification; timeout half landed as #1379, recovery tracked as #1403 |
| L5 | D-13, D-17 | **stopped by design**; both decisions refuted, nothing committed |
| L7 | D-9, D-10 | **dotfiles PR #321**, merged |
| L8 | D-18, D-16 | **PR #1282**, merged |
| L10 | D-11 | **PR #1280** — ADR 0005, the sweep boundary; fresh-eyes verified |

### Per-lane outcomes, including the explicit deferrals

Recorded so that no lane's status rests on an unwritten assumption. Each entry states what shipped
or what is deferred, why, and — where anything remains — the concrete trigger that unblocks it.

**L0 — design docs and contract.** Resolved. The work is published as PR #1323, disclosing the
deliberate collision with `docs/context-engineering-claude-5-topic`, and its durable outcome is this
ADR. One consequence of the delay is permanent and worth recording: while the working material sat on
no remote, L2 could not reach the conflict definition it needed and duplicated it instead. That
definition is now carried in this ADR precisely so no later lane has to. The D-6 fable-5 follow-up is
filed as [#1324](https://github.com/melodic-software/claude-code-plugins/issues/1324).

**L2 — cross-surface conflict detector (D-4). Resumed and published as PR #1343.** Its incumbent
search originally covered `plugins/**/SKILL.md` only and so missed C6, the same false negative every
prior search hit; the search was redone across `plugins/**` at all depths, C6 was found, and the
build was re-scoped around reuse rather than re-implementation. It ships as Phase B2 of
`claude-config:audit-instructions` with `reference/conflict-criteria.md` and an advisory
`scripts/conflict-scan.sh` pre-scan. **Nothing in it needs re-deriving from a lost checkout.**

**L3 — criteria catalog (D-4, D-2). Resumed and published as PR #1349.** The fold verdict was
independently verified sound and the fold was executed: checks **I12–I14** extend the incumbent
`reference/criteria.md` rather than standing up a second catalog, and D-2's `UNBACKED` requirement is
satisfied by mapping onto the catalog's existing `OPINION` authority value with an `info` severity
ceiling — no fourth authority value, and the axis stays a closed three-value set. **The claim set D-2
refers to is therefore already folded**; it does not need to survive as a separate list, which is the
outcome the fold was for.

**L4 — guardrails root-cause fix (D-12). Published as PR #1385, verified, and closed unmerged.** The
timeout half of the fix landed separately as #1379, which also carries the primary-source empirical
reproduction of the fail-open. The spawn-reduction half did not: a fresh-context verification found
the change modified eight guards on the safety layer with zero added tests, on a Windows-only defect
that CI — every lane `runs-on: ubuntu-24.04` — cannot exercise, so a green check was uninformative
about it. Four contract-test regressions were measured, two of them fail-open on blocking guards.
**Recovery is tracked as #1403**, which carries the five correction preconditions and the control
design for attributing those regressions. Raising a timeout narrows the fail-open window rather than
closing it, so the performance work still matters.

**Why the deferrals read the way they do.** All four lanes terminated on a session usage limit at
02:52–02:54, not at a stopping point of their own choosing, and their work was deliberately left
uncommitted rather than sealed behind a fabricated checkpoint. Every lane above has since been
resumed and published, so **nothing in this effort now depends on an unreachable checkout** — each
entry cites a PR or an issue a reader can open.

**Verification debt.** D-5's fresh-context review reached L10 (#1280) and L4 (#1385), and #1385 was
closed on the strength of it. PRs #1282 and #321 merged without it. That debt is recorded here rather
than assumed discharged.

### D-1's incumbent gate — the pass's dominant finding, and its blind spot

The gate fired hard, as this effort's own digests predicted. Its sharpest result: **D-4's criteria
catalog must fold**, because a complete incumbent already exists at
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` v1.0.0, carrying exactly
D-2's three axes plus eleven seeded checks.

**But the gate itself has a demonstrated blind spot.** Three independent searches — the boundary
lane, two automated PR reviewers, and the building lane — all concluded "no incumbent" for the
conflict detector. All three were wrong: `claude-memory:audit` ships check **C6 Consistency [FAIL]**
at `plugins/claude-memory/skills/audit/reference/criteria.md:107-119`. Each search was scoped to
`SKILL.md` files or to frontmatter descriptions, and **C6 lives in a `reference/` catalog**, invisible
from the discovery surface — that skill's own `description` never mentions contradiction.

**Any future incumbent search under D-1 must cover `plugins/**` at all depths and all file types.**
Scoping to `SKILL.md` produces a false negative that looks conclusive.

## The conflict definition D-4 ships against

D-4 commits this repository to a cross-surface instruction-conflict detector. A detector is only as
good as its definition of the thing it detects, and this pass produced one that is
checker-implementable rather than impressionistic. It is carried here because it is the single piece
of the pass's working material that a later lane cannot reconstruct cheaply — L2 already had to
re-derive it once, from material it could not reach, and duplicated it.

Two properties of the harness shape every criterion. A skill body can only conflict with another
skill body if both are invoked in one session, so cross-skill-body pairs are **conditional** conflicts
rather than guaranteed ones. And because skill descriptions are dropped under listing-budget pressure
starting with the least-invoked skills, *which* description-layer directives are co-resident is
nondeterministic and history-dependent — **a checker must not assume a description it can read on disk
is in the model's context.**

### Two directives conflict when all five gates hold

1. **Co-residency** — their surfaces can be simultaneously resident. Guaranteed pairs: any two of
   {user `CLAUDE.md`, repo `CLAUDE.md`, `.claude/rules/*` without `paths`, `MEMORY.md`}. Conditional
   pairs: anything involving a skill body, a bundled reference file, or a path-scoped rule.
2. **Same observable** — both constrain the *same decidable act*, identified by a (verb, object,
   trigger) triple, not by topic similarity. `AskUserQuestion`-vs-inline-prose is one observable;
   "emoji in a GitHub reaction" and "emoji in user-facing prose" are two.
3. **Opposed polarity** — for at least one input satisfying both triggers, the two prescribed actions
   cannot both be taken. Mandate-vs-prohibition, or two mutually exclusive mandated renderings of one
   act.
4. **No arbitration** — neither directive, nor any third resident text, names which wins. An explicit
   precedence sentence resolves the pair and removes it from the finding set.
5. **Non-vacuous trigger overlap** — a realistic prompt exists that fires both. Guard rails scoped to
   disjoint conditions (interactive vs autonomous session, code vs prose) do not overlap.

### Sub-types, by remediation route

Types A–C are sub-types **of the five-gate definition above** — each one passes all five gates and
differs only in remediation route.

- **Type A — direct contradiction.** Both absolute, opposite polarity. Fix: delete one or arbitrate.
- **Type B — modality collision.** One absolute ("never", "DO NOT"), one conditional ("as
  appropriate", "when warranted"), same act. **The highest-yield type**: the absolute side reads as a
  hard rule while the conditional side reads as license, and neither author sees the other. Fix: make
  the absolute conditional, or make the conditional's escape hatch explicit.
- **Type C — unarbitrated co-authority.** Two surfaces each assert ownership of one decision with no
  precedence statement. Fix: add one precedence sentence at the higher surface.
**Split-brain is a separate check, not a fourth sub-type.** Two instruction files that govern the
same behavior while **only one is ever loaded** fail gate 1 by construction: they are never
simultaneously resident, so no input prescribes incompatible actions and nothing arbitrates because
nothing collides. Listing it as a conflict sub-type would make it unreachable — an implementation
applying the gates faithfully discards every instance.

It is still worth detecting, and its observable is different: **divergence between two surfaces that
are never co-resident**, which is drift rather than conflict. It carries its own criteria (no
polarity test, no arbitration test — mere disagreement is the finding), its own severity (invisible
in-session, so it surfaces only under audit), and its own fix: import or symlink so both are
resident, or delete the orphan. A detector ships it as a distinct check with a distinct name; it must
not be folded into the conflict set the five gates define.

### Must-not-flag — the false positives that defeat a naive detector

These are the shapes that look like conflicts on keyword overlap and are not. A detector that flags
them is worse than no detector, because each one trains its reader to dismiss the report.

- **Different observable, shared keyword.** `plugins/guardrails/hooks/block-hook-bypass.sh` blocks
  `cat > file` and `echo|printf > file` writes, against harness guidance to use a heredoc for
  multi-line strings. Gate 2 fails: the hook's observable is *writing a file via shell redirection*,
  the guidance's is *passing a multi-line string to a command's stdin*. `git commit -F -` heredocs are
  unaffected, which `plugins/source-control/skills/commit/SKILL.md` depends on. This is a
  correctly-scoped alignment that reads as a collision.
- **Different object, same verb.**
  `plugins/source-control/skills/babysit-prs/reference/loop.md:501` ("Never skip emoji reactions")
  against a no-emoji output rule — the objects are a GitHub reaction API call and assistant prose.
- **An absolute carrying its own exception, beside a directive presupposing that exception.** The
  live instance in the operator's user-global instructions pairs "never use the `AskUserQuestion` tool
  **unless explicitly asked to use it**" with "when asking the user a question (inline **or via
  `AskUserQuestion`**), include your recommendation". The second is surface-agnostic and is satisfied
  by the first's own exception case, so no input prescribes incompatible actions (gate 3 fails) and
  the absolute arbitrates itself (gate 4 fails). Keyword co-occurrence plus an apparent
  mandate/prohibition shape makes this the most tempting false positive in the instruction set. It is
  described by shape rather than cited by line, because that file is machine-local, actively edited,
  and outside this repository.

### The partial incumbent this definition must be built against

`claude-memory:audit` already ships check **C6 Consistency** at
`plugins/claude-memory/skills/audit/reference/criteria.md`, which detects contradiction **inside the
memory layer**. Under D-1 and this repository's reuse-or-replace posture, that slice is reused or
extended, never re-implemented.

**The reuse boundary is what C6 operationally covers, not what its description claims**, and the two
differ: its discovery step is `find . -maxdepth 1` over `CLAUDE.md`/`CLAUDE.local.md` plus
`find .claude/rules`, and its cross-file step tests `CLAUDE.md` against `.claude/rules/` for
contradiction but `CLAUDE.md` against `CLAUDE.local.md` only for redundancy. So the one pair it
covers is root project `CLAUDE.md` versus project `.claude/rules/`, and **the novel scope is every
contradiction pair outside that** — including three same-layer pairs a "cross-layer" framing would
silently drop (root versus nested `CLAUDE.md`, `CLAUDE.md` versus `CLAUDE.local.md` for
contradiction, user-global versus project rules) as well as the cross-layer ones (a repo rule against
a skill body, a skill's stated default against its plugin README, agent definitions, hook text,
output styles).

**Where it lands: a new phase in `claude-config`'s `audit-instructions` skill.** Stated here directly
so this ADR does not depend on another to be actionable; the full option analysis and the cost that
placement carries — Phase A must first gain a plugin-source surface, since it enumerates only the
user and project `.claude/**` roots today — are recorded in ADR 0005 on the sweep boundary.
