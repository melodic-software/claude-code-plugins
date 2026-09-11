# D3 — Where unhobble state should live for a cloud-session run

Research memo. Evidence only; no recommendation. All web sources fetched **2026-09-11** with
WebFetch. Repo paths read at HEAD on 2026-09-11.

## Question

The unhobble contract puts `manifest.json`, `stumbles.md`, and `backups/` under
`${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/` (resolving to
`<CLAUDE_PLUGIN_DATA>/unhobble/<id>/`). This run is a Claude
Code on the web session with an ephemeral container, and the experiment must survive days across
multiple sessions (observe phase, then readd). Where should the state live: (i) plugin data dir
plus operator hand-carry, (ii) committed on the experiment branch, (iii) some other durable home?

## Findings

### 1. Cloud-session container lifecycle and what persists

**1.1 Each session gets a fresh VM.**
`https://code.claude.com/docs/en/cloud-environments` § "What's available in cloud sessions":
> "In Anthropic-hosted environments, each session gets a fresh virtual machine (VM) running
> Ubuntu 24.04 on x86_64 ... with your repository cloned and common toolchains pre-installed."

**1.2 Only committed repo content carries over; `~/.claude` explicitly does not.**
Same page, § "What carries over from your setup":
> "Cloud sessions start from a fresh clone of your repository. Anything you commit to the repo is
> available. Anything you've installed or configured only on your own machine isn't available in
> the session."

The same section's table marks `Your user ~/.claude/CLAUDE.md` — **Available in cloud sessions: No**
— "Lives on your machine, not in the repo", and the same for `~/.claude/skills/`, `~/.claude/agents/`,
`~/.claude/commands/`. The section closes:
> "To make your own configuration available in cloud sessions, commit it to the repo."

This is about *your machine's* `~/.claude` reaching the VM. It does not directly state whether the
VM's own `~/.claude` survives between sessions — see Finding 1.4 and Unverified claim U1.

**1.3 The VM is reclaimed on inactivity; a reopened session gets a fresh VM.**
`https://code.claude.com/docs/en/claude-code-on-the-web` § "Environment expired":
> "Cloud sessions stop after a period of inactivity and the session's VM is reclaimed."
> "Reopen the session from claude.ai/code to provision a fresh VM with your conversation history
> restored. Background work that was still running when the VM was reclaimed, such as subagents and
> shell commands, isn't restored."

What is named as restored is **conversation history**. The filesystem is not named as restored.

**1.4 The one filesystem that does persist is the environment cache — and it is a snapshot of the
setup script's output, not of session work.**
`cloud-environments` § "Environment caching":
> "The setup script runs the first time you start a session in an environment. After it completes,
> Anthropic snapshots the filesystem and reuses that snapshot as the starting point for later
> sessions."
> "The cache is a filesystem snapshot, so it keeps what the setup script writes to disk and loses
> anything that was only running."
> "The setup script runs again to rebuild the cache when you change the environment's setup script
> or allowed network hosts, and when the cache reaches its expiry after roughly seven days.
> Resuming an existing session never re-runs the setup script."

So the snapshot is taken **after the setup script completes**, before Claude starts working. Nothing
the session itself writes is documented as entering the snapshot, and the snapshot expires in about
seven days regardless.

**1.5 Resource ceiling, for completeness.** Same page § "Resource limits": "4 vCPUs", "16 GB of
RAM", "30 GB of disk". Not a constraint at this state size.

**1.6 Isolation.** `claude-code-on-the-web` § "Security and isolation": "each session runs in an
isolated, Anthropic-managed VM." Sessions are isolated from each other, so one session's disk is
not a channel to the next.

### 2. Plugin data directory: purpose, location, persistence, per-machine

**2.1 Location and resolution.**
`https://code.claude.com/docs/en/plugins-reference` § "Persistent data directory":
> "The `${CLAUDE_PLUGIN_DATA}` directory resolves to `~/.claude/plugins/data/{id}/`, where `{id}` is
> the plugin identifier with characters outside `a-z`, `A-Z`, `0-9`, `_`, and `-` replaced by `-`."

**2.2 What it promises.** Same page, env-var table:
> "`${CLAUDE_PLUGIN_DATA}` | Persistent directory that survives plugin updates, created on first
> reference | Installed dependencies such as `node_modules` or Python virtual environments,
> generated code, and caches"

The documented guarantee is scoped to **plugin updates**, not to machines or containers. The stated
use case is dependency/cache reuse:
> "A common use is installing language dependencies once and reusing them across sessions and plugin
> updates."

**2.3 It is deleted on uninstall.** Same section:
> "The data directory is deleted automatically when you uninstall the plugin from the last scope
> where it is installed."

**2.4 Per-machine by construction.** It sits under `~/.claude/` (Finding 2.1), and Finding 1.2
establishes `~/.claude` on your own machine does not reach a cloud session. No official page states
any cross-machine or cross-container replication of the data directory.

**2.5 The `plugins` overview page does not mention it at all.** Fetched
`https://code.claude.com/docs/en/plugins` (2026-09-11): the page covers manifests, skills, agents,
hooks, LSP, monitors, `settings.json`, `--plugin-dir`, marketplaces. It contains no mention of
`CLAUDE_PLUGIN_DATA`, a plugin data directory, or plugin state persistence. `plugins-reference` is
the sole official source for this.

**2.6 This repo already records the per-machine property.**
`<worktree>/plugins/claude-config/skills/unhobble/SKILL.md` § "State":
> "`${CLAUDE_PLUGIN_DATA}` is machine-global, so two checkouts sharing a basename ... would
> otherwise resolve to one directory".
Same framing in
`<worktree>/plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md:15`:
> "`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project".

### 3. Repo conventions (second tier)

**3.1 The memory tier is never committed, and is explicitly lost to a reclaimed container.**
`<worktree>/docs/conventions/topic-docs/README.md` § "The two tiers (and their
neighbors)" — the tier table rows:
> "| Memory | `.work/<slug>/` | Never committed (self-ignoring) | ... |"
> "| Contract | `docs/topics/<slug>/` | Committed **on the task branch only**; pruned before merge | ... |"
> "| Machine state | `${CLAUDE_PLUGIN_DATA}`; `.claude/observability/` | Never committed | telemetry;
> caches; durable machine-scoped state a later session reopens across projects |"

`<worktree>/.gitignore` carries the matching entry:
> "# Topic memory tier — never committed (docs/conventions/topic-docs/README.md \"Memory\")"
> ".work/"

**3.2 The convention's own visibility matrix marks machine state invisible to a cloud clone.**
Same README, § "Visibility across execution contexts", "Context × tier visibility matrix":
> "| Cloud clone / CI checkout | invisible | pushed commits only | pushed state only | invisible |"

The four columns are memory tier, contract tier, durable, and `${CLAUDE_PLUGIN_DATA}`. So the
repo's own normative contract already states: **in a cloud checkout, `${CLAUDE_PLUGIN_DATA}` is
invisible and only pushed commits carry.** The section is marked "This section is normative".

**3.3 `docs/CLOUD-SESSIONS.md` restates the same rule for this repo.**
`<worktree>/docs/CLOUD-SESSIONS.md` § "What this is":
> "runs each session in a fresh, isolated cloud VM with your repository cloned into it"
> "repo-committed `.claude/` config reaches cloud sessions; user-level `~/.claude` config never
> does."

**3.4 Sibling plugins in this marketplace treat "must survive a reclaimed container" as the trigger
for a tracked file.** `plugins/instruction-placement/reference/topic-docs.md` § "What survives what":
> "| A deleted memory root, a reclaimed container | lost | lost | kept — it is tracked, not memory tier |"
> "| A fresh clone | absent | absent | **present** |"
and:
> "The third and fifth rows are the whole reason the suppression surface exists. Git is the
> mechanism: a tracked file reaches another checkout because git moves it, and no `memory_dir`
> setting makes a memory-tier file do the same".

The durable half is a **tracked file under `.claude/`**: `.claude/instruction-placement.md`
(`plugins/instruction-placement/reference/consumer-config.md` § "`suppressions`": "persisted so it
survives the branch switches, other worktrees, removed memory roots, and reclaimed containers that
lose the memory-tier findings artifact"). `overengineering` uses the same split —
`plugins/overengineering/reference/topic-docs.md` § "What this plugin writes":
> "Both artifacts are therefore lane-local and **ephemeral by design** — a branch switch, a removed
> worktree, or a reclaimed container loses them. That is acceptable for evidence, verdicts, and a
> comparison baseline, all of which a run recomputes or recaptures, and is exactly why operator
> judgments are not kept here."
Its durable half is the tracked `.claude/overengineering.md`.

**3.5 No sibling skill offers a branch-committed state option today.** Grep across
`plugins/claude-config/skills/*/SKILL.md`: `audit-instructions`, `audit-prompting-postures`,
`audit-pass`, and `unhobble` all persist to `${CLAUDE_PLUGIN_DATA}`;
`plugins/claude-config/skills/audit/SKILL.md:108-113` writes `.work/claude-config-audit/findings.json`
(memory tier). No skill in `claude-config`, `overengineering`, or `instruction-placement` documents a
committed-state or repo-path alternative for its *run state*. The only tracked writes any of them make
are consumer **config/judgment** files (`.claude/overengineering.md`, `.claude/instruction-placement.md`),
and both are ask-gated.

**3.6 Committed-on-the-task-branch is a named tier, with a lifecycle.** The contract tier
(Finding 3.1) is exactly "committed on the task branch only; pruned before merge"; the README's
"Contract-slice lifecycle (prune with pointer)" section owns the pruning rule. `docs/topics/` does
not currently exist in the repo, but it is the documented default `contract_dir`, and
`scripts/docs-only-paths.txt` contains exactly one entry: `docs/topics/`.

### 4. What the unhobble "State" section promises — and what it does not say

`plugins/claude-config/skills/unhobble/SKILL.md` lines 52-71. It promises, verbatim:

- The location: "`${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/`".
- Identity discipline: "The manifest therefore records the canonical checkout identity, the resolved
  absolute worktree path and, when a remote exists, the origin URL, and every later phase verifies
  it matches the current checkout before acting; a mismatch aborts with the conflicting path named."
- No reuse: "`snapshot` never reuses an existing experiment directory: a fresh run mints a fresh id,
  and resuming an open experiment means passing its phase commands from inside the same checkout its
  manifest names."
- The three artifacts: `manifest.json`, `stumbles.md`, `backups/` ("pre-strip copies of any
  non-git-tracked file modified").

**It does not say state must not be committed.** There is no prohibition on a repo path anywhere in
the file. `## What this skill does NOT do` lists four items, none about state location. So
committing is **unaddressed, not forbidden** — with three contract-adjacent frictions:

- **F1.** The manifest records "the resolved absolute worktree path" and "every later phase verifies
  it matches the current checkout". A committed manifest carrying `<worktree>`
  aborts any later phase run from a different path (a local checkout, a differently-rooted container).
- **F2.** `backups/` holds pre-strip copies of non-tracked files, explicitly "e.g. settings hook
  entries" — i.e. `.claude/settings.local.json`-class content, which this repo gitignores
  (`.gitignore`: `.claude/settings.local.json`, `.claude/**/*.local.*`). Committing backups commits
  content the repo has decided not to track.
- **F3.** Phase 2 already commits: "One commit, message `experiment: strip instruction surfaces for
  unhobble baseline`." The branch is already the carrier for the *stripped surfaces*; the state dir
  is the only part the contract routes elsewhere.

### 5. CI gates that would act on a committed state file

From `<worktree>/.github/workflows/ci.yml`, the `lint` job (lines 269-560) plus
the changelog-parity steps (lines 885-930).

**5.1 Always-on, diff-scoped, no path allowlist in this repo's configs.** The ci.yml comment at
line 269 states markdownlint / typos / editorconfig / gitleaks / eol-renormalize / comment-hygiene /
machine-specific-paths "read the changed docs themselves and run on every diff". Their configs carry
no repo-path scoping:

- `.markdownlint-cli2.jsonc` — `"ignores"` is only `**/node_modules/**`, `**/.venv/**`, `**/bin/**`,
  `**/obj/**`; the file's own comment says "Globs are passed by the caller (CLI / CI), not declared
  here." So a `.md` anywhere (including `.claude/**` and `docs/**`) is linted. MD013 is off, MD024
  siblings-only, MD004 dash bullets, MD003 ATX. A `stumbles.md` table is fine; watch MD012/MD047-class
  defaults (all rules on unless listed).
- `_typos.toml` — no path scoping; "typos already respects .gitignore and skips binary files". Free
  prose in `stumbles.md` is spell-checked.
- `.editorconfig-checker.json` — `Exclude` is build/dependency dirs only. So `.editorconfig` applies:
  `[*]` requires `insert_final_newline`, `trim_trailing_whitespace`, `charset = utf-8`;
  `[*.{json,jsonc,yml,yaml,toml}]` sets `indent_size = 2` (but `IndentSize` is **disabled** in
  `.editorconfig-checker.json`, so indent width is not gated); `[*.{md,markdown}]` sets
  `trim_trailing_whitespace = false`.
- `.gitleaks.toml` — `[extend] useDefault = true`, no repo-specific rules. CI runs it with
  `scan-mode: git`, `redact: true`. This is the gate `backups/` (F2) collides with: pre-strip copies
  of settings files are exactly the class of content the default ruleset scans for.
- **machine-specific-paths** (`ci.yml:484-486`) — a dedicated gate for absolute host paths. The
  manifest's "resolved absolute worktree path" (F1) is precisely its target; the step's `with:`
  block is a hand-maintained exception list for fixtures that must carry such paths.

**5.2 changelog-parity fires on any path under `plugins/<name>/`.**
`scripts/check-changelog-parity.sh` case arms include `plugins/*/*` (line 480), and the error text at
line 639 reads: "still carries $head_version while this change set modifies files under
plugins/$name/ — bump the manifest and add a new '## [$head_version]' release entry instead of
editing in place." So state committed under `plugins/claude-config/` would demand a version bump plus
a changelog entry **per experiment write**. State under `.claude/…` or `docs/…` does not (the other
in-scope arm is `docs/conventions/*/CHANGELOG.md`, line 484).

**5.3 The em-dash gate is an allowlist, so a new path is unenforced.**
`scripts/em-dash-purged-paths.txt` lists specific plugin READMEs and `SKILL.md` globs. Neither
`.claude/unhobble/**` nor a `docs/` state path appears, so `check-purged-em-dashes.sh` would not gate
free prose there. (Adding an entry is optional and would then require the file to stay purged.)

**5.4 `docs/topics/` is the only docs-only allowlist entry.** `scripts/docs-only-paths.txt` contains
exactly `docs/topics/`. A diff confined there lets the path-scoped linters (actionlint, the four
check-jsonschema steps, the manifest duplicate-key detector) report an honest not-applicable success
(`ci.yml:269-278`, `ci.yml:1227`). ShellCheck, exec-bit, hook-wiring-liveness and purged-em-dashes
stay unconditional. The always-on lints in 5.1 still run.

**5.5 Ignore status of candidate paths** (`git check-ignore`, run 2026-09-11 at repo root):
`.claude/unhobble/manifest.json` → not ignored (would be tracked);
`docs/unhobble/manifest.json` → not ignored; `docs/topics/foo/PLAN.md` → not ignored;
`.work/x/y.md` → **ignored**. The repo has no `.claude/topic-docs.yaml`, so `memory_dir` is the
default `.work/`.

## Consensus table

| Claim | Official docs | Repo conventions | Sibling skills | Verdict |
|---|---|---|---|---|
| Each cloud session gets a fresh VM | Yes (1.1) | Yes (3.3) | — | Consensus |
| VM is reclaimed on inactivity; reopen provisions a fresh VM | Yes (1.3) | implied (3.2) | "reclaimed container loses them" (3.4) | Consensus |
| Only committed repo content reaches a cloud session | Yes (1.2) | Yes (3.2, 3.3) | — | Consensus |
| `${CLAUDE_PLUGIN_DATA}` is `~/.claude/plugins/data/{id}/` | Yes (2.1) | Yes (2.6) | Yes (2.6) | Consensus |
| Its persistence guarantee is "survives plugin updates", not machines | Yes (2.2) | — | — | Consensus (docs make no cross-machine claim) |
| `${CLAUDE_PLUGIN_DATA}` is invisible to a cloud clone | not stated | **Yes, normative** (3.2) | Yes (3.4) | Repo-only; official docs silent |
| A state need that must outlive a container goes to a tracked file | — | Yes (3.1 tiers) | Yes (3.4) | Consensus within repo |
| unhobble state may be committed | — | unaddressed | no precedent for run state (3.5) | No source forbids it; no source sanctions it |
| Conversation history survives VM reclamation | Yes (1.3) | — | — | Consensus |
| Session **filesystem** survives VM reclamation | not stated; "fresh VM" (1.3) | "reclaimed container loses them" (3.4) | — | Disagreement is absent, but official wording is indirect — see U1 |

## Unverified claims

- **U1.** No official page says in so many words "the session's filesystem is discarded when the VM
  is reclaimed" or "`~/.claude` on the VM does not persist between sessions". The conclusion
  rests on three indirect statements: "each session gets a fresh virtual machine" (1.1), "provision a
  fresh VM with your conversation history restored" (1.3, which enumerates history and not disk), and
  the caching section's statement that the reused snapshot is the one taken after the **setup
  script** completes (1.4). Treat "cloud-session writes to `~/.claude` are lost" as **strongly
  supported by inference, not a verbatim official guarantee.** A cheap empirical check exists:
  write a sentinel file under `~/.claude/plugins/data/` and look for it in the next session.
- **U2.** Whether the ~7-day environment-cache snapshot could incidentally carry a session's writes
  is not addressed either way; the wording ("keeps what the setup script writes to disk") points
  against it, and the ~7-day expiry caps it regardless. Unverified.
- **U3.** The exact glob each `melodic-software/ci-workflows` composite action (markdown, typos,
  gitleaks, editorconfig, machine-specific-paths, comment-hygiene) passes was not read — that repo
  is external and was not fetched. Path-scope conclusions in 5.1 come from this repo's configs and
  the ci.yml comments, not from the composites' source.
- **U4.** Whether `<worktree>` is a stable absolute path across successive cloud
  VMs for this repository is not documented; F1's severity depends on it.

## Options the evidence supports, with the constraints each carries

### (i) Plugin data dir per the contract, operator hand-carries a copy

- Contract-conformant: no deviation to record, no manifest/identity rules bent (Finding 4).
- The state is lost at VM reclamation on the evidence of 1.1/1.3/1.4 plus 3.2/3.4 (subject to U1).
  Every cross-session continuity step is a manual operator action with no gate behind it: a missed
  copy is a silently lost `stumbles.md`, which SKILL.md Phase 3 calls "the experiment's entire
  evidentiary output".
- The observe phase spans days and multiple sessions (SKILL.md Phase 3: "days of real work"), so the
  hand-carry is not one-off; it is per-session, in both directions (restore before, capture after).
- No CI gate touches it. No changelog, no lint, no secret scan.
- F1 still bites if the operator carries the state to a machine whose checkout path differs from the
  recorded absolute worktree path: "a mismatch aborts with the conflicting path named".

### (ii) Committed on the experiment branch under a repo path

- Matches the repo's contract tier verbatim — "Committed **on the task branch only**; pruned before
  merge" (3.1) — and is the only mechanism the repo's own normative matrix says reaches a cloud
  clone ("pushed commits only", 3.2). Phase 2 already commits to this branch (F3).
- Deviates from the skill's documented State location. Not forbidden (Finding 4), but no sibling
  skill has a committed run-state precedent (3.5); the tracked-file precedents that do exist are
  ask-gated consumer *config*, not run state.
- Gates, by path:
  - under `plugins/claude-config/…` — adds changelog-parity (5.2): a version bump plus a changelog
    entry on every state write. Highest friction.
  - under `.claude/unhobble/…` or `docs/…` — no changelog-parity; markdownlint, typos, editorconfig,
    gitleaks, machine-specific-paths all still apply (5.1, 5.5).
  - under `docs/topics/<slug>/` — additionally the sole docs-only allowlist entry (5.4), so
    path-scoped linters report not-applicable; and the tier already has a documented prune-before-merge
    lifecycle (3.6).
- Two specific collisions: **machine-specific-paths** vs the manifest's recorded absolute worktree
  path (F1, 5.1), and **gitleaks** vs `backups/` holding pre-strip copies of settings files the repo
  otherwise gitignores (F2, 5.1). Both are properties of what the contract says the state *contains*,
  not of the choice to commit per se; a split (commit `stumbles.md` + a path-free manifest, leave
  `backups/` in the plugin data dir) would address both but is itself a contract deviation.
- `stumbles.md` free prose enters the spell-check and markdown lanes on every push (5.1); the em-dash
  gate does not apply unless a path is added to the allowlist (5.3).

### (iii) Another durable home

The evidence surfaced these, unranked:

- **A tracked file under `.claude/`**, the shape both `instruction-placement` and `overengineering`
  already use for the judgment half of their state (3.4): `.claude/instruction-placement.md`,
  `.claude/overengineering.md`. Precedent is for durable *operator judgments*, not raw run state,
  and both are ask-gated writes. Same gate profile as the `.claude/…` row above; not ignored (5.5).
- **The forge as the store**: the ledger in a PR body or a tracker issue on the experiment branch.
  The topic-docs README rejects this shape generally — § "Native mechanisms": "Markdown-in-tickets as
  a primary artifact store is rejected: ticket bodies are not diffable, carry no review gate, and
  drift from code." No CI gate touches it; no repo precedent endorses it.
- **Run the observe phase off cloud** (a local or self-hosted checkout), leaving the contract
  location intact and the durability problem out of scope. SKILL.md Phase 2 already requires "a
  fresh session after stripping" and Phase 3 requires days of real work, neither of which binds the
  work to this surface. Constraint: F1's identity check then pins every later phase to that one
  machine's checkout path.
- **Environment setup script / cache**: ruled out by 1.4 — the snapshot is built from the setup
  script's writes and expires in roughly seven days, which is shorter than the observe window the
  skill describes.
