# Topic Documents Convention

A versioned, marketplace-wide contract for where plugin-generated task
documents land in a consuming repository. One topic (a unit of work — a
feature, investigation, or change effort) owns one **slug**; the slug
names a slice in each of two tiers, and two graduation edges carry
content out of the working directory when it outgrows the task.

This directory is the source of truth: this README (tiers, resolution
order, slug spec, lifecycle), `topic-docs.schema.json` (the tracked
concern file's shape), `CHANGELOG.md` (version history), `examples/`
(one worked slice).

## Why this exists

Before this contract, four conventions coexisted (`.claude/notes/<slug>`,
`.claude/handoffs/`, `.claude/review/`, legacy `.work/<slug>`) and a
skill invoked outside any project root wrote into the user-global config
directory. Document kinds were placed by habit, not by nature: contract
documents that gates enforce against were gitignored (invisible to
worktrees, cloud clones, and reviewers), while write-only process logs
were persisted forever.

## The two tiers (and their neighbors)

Placement follows document **nature**, decided by one question: does
anything downstream *enforce against* this document?

| Tier | Location (default) | Git | Holds |
|---|---|---|---|
| Memory | `.work/<slug>/` | Never committed (self-ignoring) | `EXPLORE.md`, `RESEARCH.md`, `<stage>-checklist.md`, `baselines/`, raw captures and scratch |
| Memory, concern-scoped | `.work/handoffs/`, `.work/reviews/<branch-slug>/` | Never committed | session handoffs; review reports — their axes are session and branch, so they sit outside topic slices |
| Contract | `docs/topics/<slug>/` | Committed **on the task branch only**; pruned before merge | `PLAN.md` (Brief + Plan), `PRD.md`, `design/` (incl. the `design-threads.md` / `design-resolution.md` gate files), `verification/` (the distilled manifest) |
| Durable | knowledge-vault seam — default backend `docs/adr/`, `docs/specs/` | Committed, permanent | promotion targets |
| Machine state | `${CLAUDE_PLUGIN_DATA}`; `.claude/observability/` | Never committed | telemetry, caches |

Locations are the documented defaults; the tracked concern file's
`contract_dir` / `memory_dir` keys override the memory and contract
roots everywhere this contract or a binding names them.

`.claude/observability/` is the sole generated surface under `.claude/`
that **this contract** sanctions: hook scripts cannot read consumer
`CLAUDE.md` (they see env and files only) and `${CLAUDE_PLUGIN_DATA}` is
machine-global rather than per-project, so project-scoped telemetry has
no other home. This is an exception, not a precedent — and it scopes to
this contract only: the platform itself also generates under `.claude/`
(native subagent `memory: project|local` roots at
`.claude/agent-memory/` and `.claude/agent-memory-local/`), which is
Claude Code's surface to govern, not this contract's.

Two kinds are deliberately **absent**: `history.md` (append-only decision
log — git log, PR threads, and tracker comments provide this natively for
tracked contracts) and a default-persisted `brainstorm.md` (ideation is
conversation output; persisting is opt-in, into the memory tier).

### The single-home rule

Every fact has exactly one home. Any other surface — a handoff, a
summary, a map, a PR body — may only *reference* it (path, URL, or
context pointer), never restate it. An index is not a store.

## Visibility across execution contexts

Tier placement decides more than git hygiene: it decides **which
execution contexts can see a document at all**. A linked worktree, a
subagent worktree, a background session, and a cloud clone each
materialize a different slice of the repository, so a document's tier is
also its visibility guarantee. This section is normative — a change to
what a context may rely on seeing is a **major** contract change (see
Versioning).

### Context × tier visibility matrix

The worktree rows assume the consuming repo materializes both native
mechanisms below (`worktree.baseRef: "head"` and `.worktreeinclude`);
without them, every spawned worktree behaves as the default-base row.

| Context | Memory `<memory_dir>/<slug>/` | Contract `<contract_dir>/<slug>/` (branch tier) | Durable (vault backend) | Machine state (`${CLAUDE_PLUGIN_DATA}`) |
|---|---|---|---|---|
| Writing checkout (same session or another session in it) | visible | visible, including uncommitted edits | visible | visible |
| Worktree spawned from local HEAD (`worktree.baseRef: "head"`) | invisible, except `.worktreeinclude`-carried patterns (one-way copy at creation time) | committed state visible; uncommitted edits invisible | visible | visible (machine-global) |
| Worktree spawned from the default base (`origin/HEAD`) | invisible, except `.worktreeinclude`-carried patterns | invisible — task-branch commits absent | merged state only | visible |
| Sibling lane (worktree on another branch) | invisible | invisible | merged state only | visible |
| Cloud clone / CI checkout | invisible | pushed commits only | pushed state only | invisible |

Two consequences drive the rules below: a contract document is visible
to an isolated context only as **committed** state (commit plan updates
with their phase — the lifecycle already requires this), and a memory
document is visible **only in the checkout that wrote it** unless a
`.worktreeinclude` pattern carries it.

### Native mechanisms

Four native mechanisms, no custom machinery:

- **`worktree.baseRef: "head"`** — committed project
  `.claude/settings.json`. Spawned worktrees (including subagent
  worktrees) branch from local `HEAD` instead of `origin/HEAD`, so they
  carry the task branch's contract commits. Verified honored at
  project-settings scope on CC 2.1.212, including from linked worktrees
  (a linked-worktree session reads its *own* checkout's
  `.claude/settings.json`, and `"head"` resolves to that worktree's
  `HEAD`). Escape hatch: a personal `.claude/settings.local.json`
  (resolved to the main checkout, covering every worktree) silently
  overrides this machine-wide — no skill, gate, or audit may assume the
  setting is universally in force.
- **`.worktreeinclude`** — repository root, `.gitignore` syntax; only
  files that match a pattern *and* are gitignored are copied. The copy
  is **one-way at worktree-creation time**: later edits sync in neither
  direction, so carried files are read-only context, never a channel.
  Carry cross-checkout-useful memory files (stage ledgers,
  `EXPLORE.md` / `RESEARCH.md`); never baselines or raw scratch
  (machine-bound). Caveat: a `WorktreeCreate` hook replaces the default
  worktree creation entirely and `.worktreeinclude` is **not
  processed** — the hook script owns any copying.
- **By-value returns** — a worker running in its **own checkout**
  (subagent worktree, background session) returns its results **by
  value**; the orchestrating session writes the contract and durable
  tiers in the parent checkout. Workers never write those tiers from an
  isolated checkout — commits and promotions land where the lifecycle
  can see them. The boundary is the checkout, not the process: a forked
  subagent running in the parent's checkout may write the memory slice
  directly (its writes are already visible), and raw per-worker output
  may land in the parent checkout's memory slice when the orchestrator
  directs it there.
- **Tracker as the cross-lane index** — the work-item tracker is the
  awareness layer across lanes: branch files stay lane-local, and a
  session in another lane discovers state through tickets, which point
  (PR URLs, promoted-doc locations) per the single-home rule.
  Markdown-in-tickets as a primary artifact store is rejected: ticket
  bodies are not diffable, carry no review gate, and drift from code.

### Pointer discipline on durable surfaces

Durable surfaces — tickets, PR bodies, promoted docs — never point at
prunable or gitignored paths. The contract slice is deleted before
merge and the memory slice never leaves its checkout, so such pointers
dangle by design. Cite the PR, the promoted location, or distilled
values instead: a ticket sourced from a plan records the PR that
carried the plan, and a plan records distilled baseline numbers, never
the memory-slice path of the raw capture.

### Consumer adoption

Repository settings and root files never travel with
marketplace-installed plugins (plugins run from an isolated cache), so
each consuming repository materializes the two files itself:

```json
{
  "worktree": {
    "baseRef": "head"
  }
}
```

as committed `.claude/settings.json`, and a `.worktreeinclude` at the
repository root (substitute a non-default resolved `memory_dir` for
`.work`):

```text
.work/.gitignore
.work/*/EXPLORE.md
.work/*/EXPLORE-*.md
.work/*/RESEARCH.md
.work/*/RESEARCH-*.md
.work/*/*-checklist.md
```

The first line carries the memory root's self-ignore file so the copied
files are ignored in the new worktree from creation; without it they
surface as untracked until the self-ignore guard heals on the first
memory-tier write.

Also gitignore `.claude/worktrees/` so worktree contents never appear
as untracked files. Rollout caveats: pulling a commit that adds
`.claude/settings.json` into a clone already holding an untracked file
at that path fails with "untracked working tree file would be
overwritten" — move the local file aside, pull, then merge its values
back; on Windows, deep repository base paths can trip git's path limit
inside nested worktrees (`'$GIT_DIR' too big`) — keep the repository
base path short. Routing this materialization through a setup-skill
apply action is a recorded follow-on, not built today.

## The tracked concern file — `.claude/topic-docs.yaml`

The consumer-side single source of truth. Shape in
`topic-docs.schema.json`; every key optional, absent keys mean the
documented defaults:

```yaml
# .claude/topic-docs.yaml — committed, team-shared
contract_dir: docs/topics   # contract-slice root
memory_dir: .work           # memory-tier root
contract_tier: branch       # branch (default) | local
vault_backend: docs         # durable-tier backend; 'docs' = in-repo git mv
```

`vault_backend` names the knowledge-vault seam backend for the durable
tier. `docs` (the default) promotes via history-preserving `git mv` into
the in-repo `docs/` tree. Any other value names a backend the consuming
repo documents; promotion steps resolve this key and degrade to `docs`
when the named backend's tools are unavailable. GitBook specifically is
reserved but not enabled as a `vault_backend` value — see
`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md` — and is
usable today only in a mirror role governed by separately reviewed
automation that keeps git authoritative, not as a backend skills write
through. GitBook documents its Git Sync product as
[bidirectional](https://gitbook.com/docs/getting-started/git-sync), so
this convention does not configure it as a writer. Setup skills preserve
and offer every schema key — a re-run never drops one — while reporting
the GitBook value as deferred and using `docs` for durable writes.

`contract_tier: local` is the solo/offline mode: contract kinds join the
memory tier under `<memory_dir>/<slug>/` and the PR-description paste becomes
the only publication surface. The default is `branch` because sibling
worktrees, PR-babysit checkouts, and cloud clones see only committed
content.

## Resolution order

Identical in every consuming plugin. Earlier wins:

1. `.claude/topic-docs.yaml` present → use it.
2. A working-docs convention declared in the consumer's `CLAUDE.md` /
   `.claude/rules` → use it, and offer to persist it into the concern
   file (prose is an inference source, not the runtime authority).
3. An existing conforming layout inferred from the repo → confirm with
   the user, persist to the concern file.
4. Ask once — one question, recommended option first (`branch` default
   vs `local`). The asking skill persists the answer to the concern file.
5. The documented defaults (`docs/topics` + `.work`, `branch`).

**No project root** (no git toplevel or project marker): interactive →
ask (create under the current directory, or an explicit path);
non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/` with the
absolute path announced prominently and nothing persisted. Writes outside
a project root only ever target the plugin-data surface.

**Non-interactive / forked mode** (any context that cannot ask the user
or persist config — forked subagents, dispatched workers, headless
runs): skip the ask and persist rungs; take the resolved or documented
default and surface the assumption in the returned summary. A fork never
writes `.claude/topic-docs.yaml`. This rule is contract-owned; bindings
cite it rather than redefining it.

## Runtime guards

- **Committed-tier guard:** the first contract-slice write in a session
  runs `git check-ignore -v` on a **representative file path inside the
  slice** (e.g. `<contract_dir>/<slug>/PLAN.md`) — not the bare
  directory, which patterns like `docs/topics/**` do not match. If a
  consumer ignore rule matches, stop and surface the exact rule — never
  silently produce an uncommittable "committed" tier.
- **Self-ignore guard:** the session's first memory-tier write verifies
  the **resolved memory root** (whatever `memory_dir` names — never a
  hardcoded `.work`) contains a `.gitignore` with `*`, creating it
  (announced) when absent — fresh clones heal on first write. Once per
  session, matching the committed-tier guard's scope. A root-equivalent
  `memory_dir` (`.`, empty, or resolving to the repo root) is **invalid**
  — stop and surface it; healing there would write `*` into the
  consumer's root `.gitignore`, which the next rule forbids.
- No plugin ever edits the consumer's root `.gitignore`.

## Slug and filename spec

- Derivation precedence (one source wins): explicit argument → the
  Brief/PRD topic → the current branch name.
- Form: kebab-case `[a-z0-9-]`, ≤ 40 chars, truncated on a hyphen
  boundary; branch separators (`/`) map to `-`; no leading or trailing
  hyphen or dot.
- Windows-reserved base names (`con prn aux nul com1-9 lpt1-9`) take an
  `-x` suffix.
- Collision authority is the contract slice on the branch. Same derived
  slug + existing dir = **resume**. A genuinely new task disambiguates
  with a scope qualifier or an ISO date suffix — never a bare ordinal.
- Timestamps in filenames: ISO-basic UTC `YYYYMMDDTHHMMSSZ` (no colons).
- Reserved first-level names under the memory root: `handoffs`,
  `reviews`, `running-retros` (a topic slug that collides takes the `-x` suffix).
- The same slug names the topic in both tiers — that is the traceability
  bridge.

Stage-file naming: UPPERCASE files (`EXPLORE.md`, `RESEARCH.md`,
`PRD.md`, `PLAN.md`) are cross-stage contract/handoff documents;
kebab-case files (`<stage>-checklist.md`) are auxiliary process ledgers.
Folders are nouns (`design/`, `baselines/`, `verification/`). Repeated
rounds of a stage append dated sections; a genuinely distinct scope takes
a `<STAGE>-<scope>.md` sidecar.

## Contract-slice lifecycle (prune with pointer)

1. Contracts commit on the task branch as they lock — a phase's plan
   updates ride the same commit as its source changes.
2. At PR time the approved `PLAN.md` and the verification summary are
   pasted into the PR description inside `<details>` blocks (bodies cap
   near 64 KB — paste the contract, reference the rest).
3. Before merge, durable outcomes graduate: architectural decisions and
   specs through the **knowledge-vault seam** (default: history-preserving
   `git mv` into `docs/adr/` / `docs/specs/`; remote vault backends
   resolve through the same seam), and actionable follow-ups through the
   **work-item tracker seam**.
4. A final commit prunes the contract slice `<contract_dir>/<slug>/`
   (default `docs/topics/`), leaving context pointers (the PR body and
   the promoted-doc / tracker locations) in its place.
5. Enforcement: a required check that the net PR diff
   (`git diff --name-only base...head`) contains no path under the
   resolved `<contract_dir>/**` (default `docs/topics/**`). GitHub's PR
   view is the three-dot diff, so pruned files also vanish from the
   final review surface.

Hardening at the consumer's option: `.gitattributes`
`<contract_dir>/** linguist-generated` (default `docs/topics/**`;
collapses mid-review diff noise), a markdownlint carve-out for the
contract root, and secret scanning.
**Redaction bar (normative):** committed evidence is distilled — no raw
command captures, no machine-local absolute paths, no usernames or
credentials. Raw output stays in the memory slice `<memory_dir>/<slug>/`
(default `.work/`).

## Graduation edges (provider-neutral seams)

- **Ticket edge** — actionable work goes through the `work-items`
  plugin's provider-neutral tracker seam. Ticketing backends swap behind
  that contract; this convention never binds a backend.
- **Vault edge** — durable knowledge goes through the knowledge-vault
  seam: named verbs (publish, update, link-back), default backend the
  in-repo `docs/` tree (zero external dependencies), remote backends
  (e.g. Notion/Confluence-class systems) resolving through the concern
  file when a consumer configures one. GitBook via its MCP server is
  deferred as a write target — see
  `docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md` — and is
  usable today only in a mirror role governed by separately reviewed
  automation that keeps git authoritative. GitBook's documented Git Sync
  product is bidirectional, so skills neither configure it nor invoke
  GitBook API/MCP writes. Skills degrade gracefully: no enabled vault
  backend means the in-repo default, never a hard failure.

## Adoption (clean break)

The prior conventions (`.claude/notes/<slug>`, `.claude/handoffs/`,
`.claude/review/`, unscoped `.work/<slug>`) are retired outright — no
compatibility layer, no legacy knobs, no dual-read windows, no
migration tooling. Skills read and write only the resolved convention
locations. A repo holding content at a retired location moves it by
hand (or asks the session to); the audit-noise tooling flags stale
citations of retired paths as ghost refs.

## Implementers

Plugins with their own placement deltas carry a deltas-only binding
(`reference/topic-docs.md`); the rest adopt by reference — their
relationship to the contract is fully stated by their table row.

| Plugin | Writes | Tier(s) | Binding |
|---|---|---|---|
| discovery | `EXPLORE.md`, `RESEARCH.md` | memory | delta doc |
| planning | `PRD.md`, `PLAN.md` (Brief), `design/`, opt-in brainstorm persist | contract + memory | delta doc |
| implementation | `PLAN.md` (Plan/progress), `DEVIATIONS.md`, status summaries | contract + memory | delta doc |
| verification | `verification/` manifest; baselines, raw captures | contract + memory | delta doc |
| session-flow | handoffs; running-retro ledgers | memory (`handoffs/`, `running-retros/`) | delta doc |
| review | review reports | memory (`reviews/`) | delta doc |
| work-items | per-topic action ledger; tracker projections | memory; ticket edge | delta doc |
| toolchain | nothing of its own — its setup skill offers the concern file | — | delta doc |
| knowledge | ingest trees — **formal carve-out**: its work root resolves through its own `library_dir` seam, not `memory_dir`; slug conformance is form-only (charset/reserved names), and its nested `<epic>/<slug>/` sub-slices are sanctioned | memory (carved out) | by reference — the carve-out above is its entire delta |
| claude-ops | telemetry | machine state | by reference — machine state resolves no contract paths |
| docs-hygiene | (reader) audit-noise detector recognizes these shapes | — | by reference — reads shapes, writes nothing |

## Versioning

This contract is versioned in `CHANGELOG.md`. A change that moves a
tier, renames a key in `topic-docs.yaml`, alters the slug spec, or
**changes a visibility guarantee** (what an execution context may rely
on seeing, per the visibility matrix) is a **major** contract change,
and every implementer adopts it in the same release wave (clean break —
this contract carries no compatibility machinery). Additive guidance is
minor.
