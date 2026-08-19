# Upstream source — AI Hero "Shipping" course section (Matt Pocock)

Single source of truth for everything in this marketplace derived from the **Shipping** section
(11 videos) of Matt Pocock's AI Hero crash course — a distinct upstream source from
[mattpocock/skills](https://github.com/mattpocock/skills), whose SSOT is
[`mattpocock-skills.md`](mattpocock-skills.md). Course content overlaps the skills repo but is
not release-tagged; verdict rows below are the durable record.

**Source basis (re-fetchable):** the course is Matt Pocock's AI Hero crash course, hosted at
<https://www.aihero.dev> (Shipping section, 11 lessons: How to Tackle Massive Tasks; Set Up Your
Issue Tracker; Write Great Specs With This Skill; Split Features Across Context Windows With
Tickets; Executing Your Tickets; Should You Keep Your Specs?; Rerouting; The Goal Command;
Enforcing Your Coding Standards; Ask Matt; Where You Go From Here). Capture method: lesson pages
pasted verbatim by the maintainer into the interview session on 2026-08-17 — course pages are
account-gated and not release-tagged, so the durable cross-check basis is the companion skills
repo pinned at `mattpocock/skills@068b6e0` (the same mechanisms, versioned).

**Audit state:** course section content captured 2026-08-17 (topic `pocock-shipping-breakdown`);
skills repo cross-audited at `main@068b6e0` (post-v1.2.3 unreleased). The two audit reports
(`upstream-bringover-audit.md`, candidates C1–C23; `seam-scrutiny-findings.md`, findings F1.x /
F3.x) are graduated to durable storage as comments on container #2933 — the memory-tier copies
under `.work/` are session-local and uncommitted per the topic-docs contract.

**Recheck trigger:** a mattpocock/skills release whose changeset names `to-spec`, `to-tickets`,
`implement`, `tdd`, `code-review`, `triage`, or `wayfinder` — the course's flow skills. Course
page updates are not observable events; the skills-repo release stream is the proxy.

## Spec container

All absorption work is tracked under the spec container
[melodic-software/claude-code-plugins#2933](https://github.com/melodic-software/claude-code-plugins/issues/2933)
(sub-issues per lane). The container closes — archival by closure — when every lane lands and a
container close-out review against the spec passes.

## Verdict table

One row per lane; verdicts filled in as each lane's sub-issue closes. Statuses: ADOPTED /
PARTIAL / REJECTED / OPEN.

| Lane | Course concept | Candidates | Our surface | Verdict | Item |
|---|---|---|---|---|---|
| A | Spec lifecycle: /to-spec, spec-on-tracker, archive-your-specs | C1–C4 | planning:prd/plan + work-items:decompose | PARTIAL (C4 adopted gate-added; C3 partial; C1 already-present; C2 routed to #2936) | #2934 |
| B | /to-tickets deltas | C5–C8, C17 | work-items:decompose | ADOPTED | #2935 |
| C | /implement + /tdd wiring, zero-assembly chain | C9–C11 | implementation:implement, tdd:principles, testing:write | OPEN | #2936 |
| D | Two-axis review, spec lens, discovery ladder, preflight | C12–C16 | review:quality-gate | PARTIAL (C12+C14 adopted-corrected; C13+C16 already-present; C15 partial) | #2937 |
| E | Rerouting: tickets disposable, spec editable | — | work-items:decompose (re-decompose flow) | ADOPTED | #2949 |
| F | /goal vs tickets posture | — | planning:draft-goal-condition | OPEN | #2938 |
| W | Wayfinder deltas | C18–C20 | planning:wayfind | PARTIAL (C18+C19 adopted; C20 already-present) | #2939 |
| X | Invocation doctrine (skills-repo delta PRs #878/#880) | C21–C23 | playbooks:skill-authoring, skill-quality:check | ADOPTED | #2940 |
| Y | Macro/micro lifecycle orchestrator (interview Q18) | — | undecided (session-flow / work-items / new) | OPEN | #2948 |

Seam-scrutiny follow-ons (not course-derived, surfaced by the same audit): binding config
(#2941), contract hygiene (#2942), lease hardening (#2943), local-markdown docs (#2944),
multi-provider topology (#2945), Linear adapter (#2946), adapter-onboarding skill (#2950),
Jira write (#2951), Gitea/Forgejo adapter (#2952), provenance/map fixes (#2947).

## Lane A (#2934)

Interview rounds 1–4 locked the shape (2026-08-17): extend `work-items:decompose` +
`planning:plan close-out` — NOT a new to-spec skill; mandatory approval gate; opt-in and
consumer-configurable throughout.

- **C1 ALREADY-PRESENT**: no-interview pure-synthesis spec mode. `planning:interview`
  synthesizes directly when intent is clear (anti-re-interrogation is its documented smart
  default), and `planning:plan`'s empty-argument smart default finalizes an existing
  conversation plan without re-interviewing. No new entry path added.
- **C2 PARTIAL**: seam-sketch-before-spec accepted as doctrine direction but ROUTED to lane C
  (#2936), where it lands alongside C9 (the pre-agreed-seam gate — same doctrine family, one
  landing surface across planning:design / tdd:principles / testing:plan). The "ideal number
  of seams is one" numeric absolutism is REJECTED (folklore-figure posture).
- **C3 PARTIAL**: container body = the Brief **verbatim** (our spec template), plus an optional
  `## Testing decisions` section with prior-art test pointers — that section is the adopted
  delta. The "LONG, numbered, extremely extensive" directive stays excluded (worse-than-us
  list).
- **C4 ADOPTED (gate-added variant only)**: the spec publishes to the tracker as a `work-map`
  container with slices as native sub-items (`work-items:decompose` "Container lifecycle") —
  opt-in at approval, `decompose_container_publish` userConfig pre-select, container label
  remappable via binding `config.container_label`. Upstream's gate-free publish remains
  excluded.
- **Archive-your-specs** (course "Should You Keep Your Specs?"): ADOPTED as archival by
  closure — the container closes at ship after a close-out review against its body; a closed
  container stays findable but no spec sits in repo or open tracker for agents to trust over
  code. Pass-by-reference ADOPTED: `/work-items:work` reads the parent container body as
  quoted briefing data before executing a sub-item.

## Lane B (#2935)

- **C5 ADOPTED**: prefactor look-ahead at decompose time ("make the change easy, then make the easy change"); prefactor slices are blockers of the slices they unblock. Qualitative — no token folklore.
- **C6 ADOPTED**: "one fresh context window" granularity bar alongside S/M/L. Qualitative only; folklore token figures remain excluded-by-default.
- **C7 ADOPTED as fallback**: when expand-contract batches cannot land green alone, share an integration branch all blocking a final integrate-and-verify item. Default remains expand → migrate → contract (`decompose` §2b). Those items require a separate integration-branch workflow; `/work-items:work` still targets the default branch.
- **C8 ADOPTED**: "work the frontier" phrasing in the present/report step (unblocked slices first).
- **C17 ADOPTED**: PR-variant brief in `plugins/work-items/reference/agent-brief.md` (current-behavior-of-the-diff, finish-what-exists). Does not replace the bug/feature template.

## Lane D (#2937)

Design locked 2026-08-19 after adversarial validation (two fresh-context validators, rationale
withheld; three of five initial answers revised on evidence).

- **C12 ADOPTED-corrected**: `spec` mode — a 9th `quality-gate` lens judging the diff against its
  originating spec, in `plugins/review/skills/quality-gate/context/spec.md`. That file **owns** the
  finding-class enum (`missing` / `scope-creep` / `wrong`, each finding quoting its spec line);
  `self.md`'s fenced worker checklist keeps a shallow divergence check and does not restate the
  taxonomy, and the pointer to the owning file sits in orchestrator-facing escalation text, not
  inside the subagent template a fresh-context worker cannot act on. Fills the dangling consumer in
  `work-items:decompose` and `work-items:ship`, which both route container close-out to "the review
  plugin's spec-fidelity machinery."
- **C13 ALREADY-PRESENT + one targeted edit**: the course's two-axis intent is already implemented
  as `fanout`'s two-axis presentation (merged ranked queue plus a per-dimension regrouping). The
  originally proposed "never merge or rerank across axes" rule was **withdrawn** — it would negate
  the normalization pipeline `fanout` exists to run, and its second scope (invocations pairing spec
  with a quality mode) is unimplementable against `quality-gate`'s one-lens-per-invocation rule.
  Landed instead: `self.md`'s parallel-worker split tightened from "merge only after verification"
  to keep-separate presentation, and the **vocabulary recorded once** in
  `plugins/review/context/severity.md` — in this plugin `axis` means severity/confidence; a review
  perspective is a `lens`. Three incompatible senses were live before that note.
- **C14 ADOPTED-corrected**: spec-source discovery ladder in `context/spec.md` — `--spec <path|id>`
  → item refs harvested from branch commits / PR body → the topic's contract slice → ask → skip
  with a note. Corrections over the course's version: (1) the seam's normalized item object has
  **no `body` field**, so spec text comes from the **provider-mechanic read**; (2) a harvested bare
  `#N` is **validated** (strictly numeric; owner/repo to a repo-name shape) and then **promoted** to
  the qualified `<provider>:<owner>/<repo>#<number>` form, with the read scoped by `--repo` to that
  id's own repository — commit and PR text is attacker-influenceable through a fork PR, and a bare
  number would read a same-numbered issue in the *current* repo; (3) the contract-slice rung keys
  on the **topic slug**, not the branch slug — the branch axis is deliberately lossy. **Design
  correction found in PR review:** the item is read through a documented public seam or the provider
  mechanic, never by invoking the sibling plugin's seam CLI — `PLUGIN-PHILOSOPHY.md` forbids
  discovering another plugin's installation directory, and no namespaced item-fetch action exists
  today. So this is *not* the marketplace's first cross-plugin seam call; the provider-mechanic read
  is the operative path, the rung works with no tracker plugin installed, and parent linkage (whose
  authoritative source, `get-item`, is unreachable from here) degrades to best-effort or an explicit
  `--spec`.
  Recorded limit: the contract slice is pruned before merge, so that rung goes empty post-merge and
  recovery is best-effort — which is why the tracker item is the durable spec home.
- **C15 PARTIAL**: `fanout`'s fail-fast preflight ported into `quality-gate`, which had none. Two
  costs the course's version omits and this port carries: the gate is **mode-scoped** (`criteria`
  is a reference mode that legitimately runs on a clean tree and is exempt), and `quality-gate`'s
  narrow `allowed-tools` allowlist had to be **widened** with the git read verbs the gate needs or
  it stalls headless. A third, found in PR review: the port must **not** copy `fanout`'s
  untracked-only stop. `fanout` stops there because its surfaces receive only the merge-base diff,
  which cannot show an unstaged file; `quality-gate` hands untracked files to the reviewer directly,
  so a new-files-only branch is a real change set and stopping on it would report "nothing to
  review" about work that is plainly there.
- **C16 ALREADY-PRESENT**: both suppression halves — repo standards override a conflicting baseline
  smell, and skip what tooling already enforces — are carried in one sentence at
  `plugins/review/agents/code-reviewer.md`, corroborated in `quality-gate/context/criteria.md` and
  `code-review/SKILL.md`. No change.
- **CI code-review lane stays quality-only** (reasoned rejection, not a phantom exclusion): the
  original "deliberately excluded" clause was a no-op — no coupling to `quality-gate` existed to
  exclude. The lane is org-owned, already declares lane-splitting doctrine, and its scope rules
  foreclose absence-of-code findings. Revisitable on demand rather than silently narrowed.
- **Container close-out review split out** to #3027: its mechanism is broken
  four ways as originally specified (no seam verb yields a closing PR; "union of merge commits"
  is the empty set under this repo's squash-merge default; the integration-branch execution shape
  has no per-item PRs at all; a container-scoped basis conflicts with `quality-gate`'s singular
  review-diff-base contract) and it is structurally larger than a mode addition.

## Lane W (#2939)

- **C18 ADOPTED** in `planning:wayfind` only (not generalized to work-items): human-facing
  narration refers to items by title, with the number as a link or suffix.
- **C19 ADOPTED**: Out-of-scope is for scope, not sharpness; fog never graduates there; a
  wrongly scoped item is closed + one Out-of-scope line, with no Decisions-so-far pointer.
- **C20 ALREADY-PRESENT**: map body is a stable index not a mirror; Decisions-so-far is a
  pointer INDEX; Notes are links not recaps — recorded here, not restated in the skill docs.

## Lane E (#2949)

- **Rerouting recipe ADOPTED** (course "Rerouting" lesson) as a documented **re-decompose**
  flow in `work-items:decompose` — a usage pattern of existing seam verbs, not a new
  capability or skill: close unimplemented children not-planned with a superseding-direction
  comment, keep implemented children untouched, re-interview/edit the spec, regenerate the
  remaining slices through the normal draft→approve→publish steps, continue.
  `/work-items:ship` routes to it when slices no longer fit the spec.
- **Disposable-tickets / editable-spec doctrine ADOPTED** verbatim: slices are projections of
  the spec at decomposition time; when the spec moves, stale projections are closed and
  regenerated, never hand-patched.
- **Reroute boundary ADOPTED**: post-ship wrongness is a new idea → new spec (new container or
  topic), never a patch to the closed one — aligned with the archival-by-closure drift
  doctrine (Lane A). Added beyond the course: small drift is an ordinary body edit, not a
  reroute; claimed in-flight items are coordinated with, not closed from under their holder.
- **Both spec homes covered**: the flow works against the topic Brief (no container) and the
  tracker container body (Lane A's spec-on-tracker model).

## Decided at interview (2026-08-17, not per-lane)

- **Naming:** "work item" stays canonical; "ticket"/"issue" are documented first-class synonyms
  (trigger coverage landed via #2947). Rename of plugin/seam REJECTED.
- **Setup-by-interview** (course "Set Up Your Issue Tracker" / `setup-matt-pocock-skills`):
  remains REJECTED per the skills-repo SSOT — this marketplace configures via the tracker-seam
  binding + setup skills.
- **Adapter shipping model:** HYBRID — bundled hardened majors + consumer-side generator skill
  for the tail (#2950), gated on contract-version handshake and normalization-fidelity
  conformance.
- **Excluded by default** (course/skills practices we will not import): approval-gate-free spec
  publish; tracker reads without the item-content-trust boundary; folklore token figures
  (~150k smart zone, 100k ticket sizing); unverified sub-agent review findings;
  refactoring-excluded TDD loop; `research/<name>` branches (previously rejected).

## Cross-links

- Skills-repo SSOT: [`mattpocock-skills.md`](mattpocock-skills.md) (attribution table; tracked
  strands). The invocation-reach tracked strand's audit lands via lane X (#2940).
- Full v1.2 map: [`mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md). Staleness
  fixes and absorbed-under-different-name traceability landed via #2947.
