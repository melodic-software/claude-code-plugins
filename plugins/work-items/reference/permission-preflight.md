# Permission preflight

The unattended `work` and `babysit-prs` lanes only run without mid-cycle permission prompts when
two things hold before the loop starts: the core git/gh working verbs are pre-approved, and the
out-of-tree worktree root is a trusted write directory. This reference is the source of truth for
what those preconditions are and how the loop-start check reports them. It is consumed by
`work` (wired at loop start) and applies verbatim to `source-control:babysit-prs`, which shares the
same grant and worktree-root needs.

## Why a preflight, not a fixer

The assistant **cannot self-apply** the remediation, for two independent reasons the repo's
[permission-rule-hygiene convention](../../../docs/conventions/permission-rule-hygiene/README.md)
documents in full:

- The auto-mode classifier routes any write to `.claude/` settings through itself and refuses an
  agent that tries to broaden its own `permissions.allow` — self-privilege-escalation is blocked.
- A `permissions` block shipped in a plugin's `settings.json` is inert; a plugin `settings.json`
  honors only the `agent` and `subagentStatusLine` keys.

So the operative grants live **operator-side**, and the loop-start step only **detects and reports**
the gap once, up front. It never edits settings, and never retries a permission/classifier denial
into broader grants (the never-self-retry posture — a denial is a stop, not a signal to widen).

## A denial this preflight cannot catch: the Step 0 `reclaim` asymmetry

`preflight.sh` only probes `permissions.allow`/`deny` **coverage** for a fixed git/gh verb set — it
does not, and should not, probe the tracker script's `claim`/`reclaim` verbs (see "The allow floor"
below for why a hand-maintained tracker-path rule doesn't fit that model). Work-loop self-observation
`#1381` recorded a denial this preflight has no way to surface: the seam `reclaim` verb was refused
by the auto-mode classifier while the sibling `claim` verb on the same script, invoked moments
later, was NOT — and at the time of writing, **neither** verb carries an explicit
`permissions.allow`/`deny` rule in the fleet's floor (`standards`
`components/claude-permissions/claude-permissions.json`). The asymmetry is therefore not an
allow-list coverage gap of the kind this doc otherwise describes; it reads as the classifier's own
heuristic judgment on the two commands.

Whether adding an explicit allow rule for the `reclaim` invocation would bypass that judgment is an
**open, unverified question** as of this writing — official docs describe `permissions.allow` rules
bypassing the classifier by default (`autoMode.classifyAllShell: false`), but also describe rules
matching "arbitrary-code-execution patterns" as routed through the classifier regardless, without
defining that pattern set precisely enough to say which side a script invocation (`work-item-tracker.sh
reclaim <id>`) falls on. Do not write a rule into the standards floor on the strength of this doc
alone; confirm the carve-out first. `/work-items:work`'s Step 0 treats a classifier denial of
`reclaim` as a non-blocking, report-once-and-skip condition (see `skills/work/SKILL.md` "Step 0") —
that is the current mitigation; a permission-rule fix, if one applies, still lives operator-side per
the pattern above.

## The allow floor — point at the standards component

Do not hand-maintain an allowlist here. The fleet's reviewed permission floor is the
`claude-permissions` component in the `melodic-software/standards` repository
(`components/claude-permissions/`): one canonical `permissions.allow` / `permissions.deny` set,
distributed as data and composed into each operator's live `~/.claude/settings.json` by the
dotfiles repository's chezmoi modify-template (union of the canonical floor with locally-accumulated
rules; the deny floor is never relaxed below the component).

What it covers, at a glance (read the component for the authoritative list):

- **allow** — the read-only git/gh inspection verbs plus the routine non-destructive working verbs
  an unattended loop needs without prompting: `git add` / `commit` / non-force `push` /
  `checkout` / `switch`, and `gh` PR and issue CRUD including `gh pr create` and
  `gh issue comment`. Rules are the narrow bare-command shape (`Bash(git commit *)`, not
  `Bash(git *)`) that survives auto mode; the broad interpreter-wildcard shapes are dropped on
  entering auto mode and are the anti-pattern the convention above flags.
- **deny** — the destructive-verb safety floor (force-push, hard reset, `clean`, checkout/restore
  discards, forced branch deletion, `--no-verify` bypass), the `gh api` DELETE surface, hook-disable
  environment prefixes, and secret-material `Read()` patterns. Deny always wins over allow.

The preflight probes a small representative subset of the allow floor — `git add`, `git commit`,
`git push`, `gh pr create`, `gh issue comment` (a commit flow stages before it commits, so `git add`
is probed too) — reading the effective `permissions.allow` from the operator's user-global settings
and the project settings. It never runs a live permission probe. A verb counts as covered only by an
**open-glob** grant — `Bash(git commit *)` or `Bash(git commit:*)`. A **bare-exact** rule
(`Bash(git commit)`) is **not** coverage: it permits only the argumentless command, and a work-lane
invocation always carries arguments, so the real call would still prompt. When a gapped verb has
*only* a bare-exact grant, the gap message says so precisely — that grant does cover an argumentless
caller (e.g. the babysit fix cycle's plain `git push`) but not the work lane's argument-carrying
call, and the remedy is to add the open glob (`git push *`). A narrower, flag-scoped rule
(`Bash(git commit --amend)`, a force-with-lease-only push rule) is likewise not coverage. A missing
verb means the floor is not composed in on this machine; the remediation is to apply the component
operator-side, not to add a one-off rule.

**Deny wins over allow.** Because `permissions.deny` overrides `permissions.allow` in the permission
model, the check first tests each probed verb against the effective **deny** rules: a deny rule of
the verb (bare, or its open-glob form) keeps the verb a gap (reported distinctly as *denied*, not
*missing*) even when an identical allow rule exists — the lane still cannot run it. Deny matching
deliberately errs **wider** than coverage — it also counts the bare-exact spelling, because a
false *denied* report is safe whereas a missed one is not. It is still **exact-shape only**: it does
not simulate glob semantics, so a broader deny pattern that would match the verb at runtime (a
wildcard spanning it) is not caught here. That conservatism never false-flags the standard deny
floor, whose destructive-verb rules are flag-scoped (`git push --force …`) rather than the bare
`git push` / `git commit` / `git add` shape.

**`settings.local.json` scope on the autonomous path.** Since Claude Code v2.1.211, choosing
"Yes, don't ask again" saves the rule to `.claude/settings.local.json` at the repository root,
**resolved through worktrees to the main checkout**, and the rule applies to sessions anywhere in
that repository — every linked worktree included, however the worktree was created
([permissions](https://code.claude.com/docs/en/permissions#permission-system),
[worktrees](https://code.claude.com/docs/en/worktrees); both fetched 2026-08-04). The main
checkout's local file is therefore part of a fresh worker worktree's effective settings, and the
preflight reads it in **every** mode — but only once it has **verified** which directory that is.

**Resolving the main checkout.** Candidates are proposed cheapest-first and each is put through one
predicate before it is trusted; a candidate that fails is discarded, never named. The predicate has
three legs, all required: the candidate's `--show-toplevel` is the candidate itself (it is a
toplevel, not a subdirectory of one), its `--git-common-dir` is our common dir (it belongs to *this*
repository), and its `--git-dir` is also our common dir (it is the **main** worktree, not a linked
one). The candidates:

1. **The probed checkout itself** — its own git dir *is* the common dir. True whatever the git dir
   is named, so the **main checkout of** a `--separate-git-dir` or submodule layout resolves here.
   The probed checkout is `--project-root` when given, else the cwd.
2. **`core.worktree`** in the common dir's config, resolved relative to that dir. Git writes it for
   submodules, which is what makes a submodule's `<super>/.git/modules/<name>` common dir — which no
   parent-of-`.git` arithmetic can invert — resolvable at all.
3. **The conventional `<root>/.git` spelling** — the parent of the common dir.

Resolution has three outcomes, and the report distinguishes them:

- **Verified** — a candidate passed. Only then is a path named as the main checkout, and only then
  is its `settings.local.json` read. The header prints git's own spelling of the verified toplevel.
- **Bare** — the repository has no main working tree, so no main-local layer can exist. Nothing is
  missing and the summary stays `OK`.
- **Unresolved** — no candidate passed. The layer is **UNREAD**, the report says so on its own line
  with the reason, and the summary is `PREFLIGHT: INCOMPLETE …`, never a bare `OK`. It is printed in
  **every** mode, the interactive one included — the two headers that name a main checkout print
  only under `--worktree-root` or a distinct `--project-root`, so a plain run from a linked worktree
  would otherwise drop a main-local deny with no output at all. The exit code is still `0`: the
  script is report-only and findings never fail the run.

What a fresh worker does **not** inherit is a local file living inside some *other* linked
worktree — a pre-2.1.211 save, or a hand-placed file — which applies only to sessions started in
that worktree. Two cases:

- **Pre-dispatch** — `--worktree-root` is passed but no distinct `--project-root` (the worker is not
  yet created). The **coverage** reads (allow + `additionalDirectories`) span user-global + tracked
  project settings + the main checkout's local file; only a linked-worktree cwd's *own* local file
  is dropped, since the fresh worker would not inherit it and reading it would mask a worker-side
  gap. Run from the main checkout, nothing is dropped. The report header says which — naming the
  main checkout only when resolution verified it.
- **A named worker** — `--project-root <worker-worktree>` resolves to a checkout whose toplevel
  differs from the cwd. That is a real, existing checkout, so the preflight reads **its own**
  `settings.local.json` (legacy rules saved there still apply to sessions started there) plus the
  main checkout's shared local file; the header names the sources, under the same condition.

**Two residual limits apply to BOTH modes above.**

- **Pre-2.1.211 harness — MASKING.** There a worktree session loads its own local file, not the main
  checkout's, so crediting a main-local-only grant suppresses a gap the worker really hits. Nothing
  in the preflight detects it: it never probes the running Claude Code version. This is a floor on
  the *harness*, not on the repository layout — so wherever the installed Claude Code is v2.1.211 or
  later it is a documentation-completeness matter rather than a live defect (v2.1.222 on the machine
  this was verified against).
- **`--separate-git-dir` is ambiguous in git itself — NOT a preflight defect, and not maskable in
  silence.** For a repository created with `--separate-git-dir <path>/.git`, the main working tree is
  the directory holding the `.git` *file* — but git records no back-pointer to it. A recursive search
  of the whole common dir turns up only `worktrees/<name>/gitdir` entries, which point at *linked*
  worktrees; `core.worktree` is unset by every creation path (`git init --separate-git-dir` on a
  fresh directory, `git clone --separate-git-dir`, and `git init --separate-git-dir` over an existing
  repository). Git's own `git worktree list` therefore reports `<path>` — the parent of the separate
  git *directory*, not of the `.git` file, which lives in the true working tree and is the very link
  git does not record in reverse — as the main worktree, and reports it identically when run *from*
  that true working tree. `<path>`
  also satisfies all three legs of the verification predicate, byte for byte, exactly as a
  conventional `<root>` does; any test strong enough to reject it also rejects the conventional
  layout. So the preflight resolves to `<path>`: **git's own answer**, arrived at by verification
  rather than by string arithmetic. Where the operator intended a different directory to be the
  working tree, the layout is ambiguous at the git level and no consumer of git can do better.
  Two consequences worth knowing: `--separate-git-dir "$HOME/.git"` makes `$HOME` the main checkout
  by git's reckoning, so the operator's own `~/.claude/settings.local.json` is genuinely in scope for
  that repository; and a spelling that is *not* `<something>/.git` (a separate git dir under any
  other name) yields no candidate at all — that is the **unresolved** outcome above, which is
  reported loudly rather than passed over.

The interactive/default path (no `--worktree-root`) keeps the cwd checkout's local settings in
scope. Deny always reads every local layer it resolves, in every mode — the same err-wide rationale;
an unresolved main checkout is the one layer it cannot widen, which is why that case is reported
rather than absorbed.

## The trusted worktree root — `additionalDirectories`

`acceptEdits` auto-approves writes only inside the workspace root; it never auto-approves a write
**outside** it. The autonomous lanes dispatch implementation subagents into their own out-of-tree
worktrees (lifecycle owned by `source-control:worktree`), so every edit in a worktree is an
out-of-workspace write that prompts unless the worktree root is registered as a trusted directory
via `permissions.additionalDirectories`.

The fleet convention is a dedicated worktree root **sibling to the repo**, not the OS temp dir — a
`.worktrees/`-style directory (`source-control:worktree` creates worktrees under Claude Code's
default sibling layout; `babysit-prs` defaults its `babysit_worktree_root` to the `worktrees`
subdirectory of the plugin data directory). The exact root is operator-configurable and not yet a
single documented constant across the fleet (the interim loop stopgap trusts `~/.claude-loop-worktrees`),
so the preflight checks **coverage of whatever root the lane is configured to use** — it does not
hardcode a path. Register that root once, operator-side:

```jsonc
// ~/.claude/settings.json (or the project's .claude/settings.json)
{
  "permissions": {
    "additionalDirectories": ["<your out-of-tree worktree root>"]
  }
}
```

An entry covers the root when it equals the root or is an ancestor of it; a single sibling-root
entry therefore trusts every per-PR worktree created beneath it.

## Running the check

The `work` skill invokes the script at loop start; run it directly to preview the gaps:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/work/scripts/preflight.sh" --worktree-root <configured-worktree-root>
```

**Check the worktree the lane actually runs in.** A checkout's tracked `.claude/settings.json` can
differ per worktree (a different branch), so a fresh linked worktree can carry different grants than
the checkout the orchestrator runs in — and the cwd checkout's grants would otherwise mask a
worker-side gap. When the orchestrator dispatches a worker into a worktree, pass that worktree as
`--project-root` so its own project settings are the ones probed:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/work/scripts/preflight.sh" \
  --project-root <dispatched-worker-worktree> --worktree-root <configured-worktree-root>
```

`--project-root` defaults to the current checkout. A distinct one (a different toplevel) re-points
the project layer to that worker checkout and reads its own `settings.local.json`; without it, the
autonomous path drops a worktree cwd's own local file (see the `settings.local.json` scope note
above). User-global settings and the main checkout's shared `settings.local.json` apply everywhere
and are read regardless.

It is report-only and always exits `0`. Each output line is one of:

- `NOTE (a) …` — the cwd is not a git repository. Informational: a lane operating in an out-of-tree
  worktree proceeds once `(c)` is covered; a lane that needs a checkout at the cwd cannot.
- `GAP (b) …` — a probed working verb is denied by a matching deny rule, has only a bare-exact
  (argumentless) allow, or is not covered at all (the message distinguishes the three). Remediate
  operator-side: resolve the deny rule, add the open glob, or compose the standards floor in (above).
- `GAP (c) …` — the worktree root is not covered by `additionalDirectories`. Add the entry (above).
- `NOTE (c) …` — no worktree root was passed, so coverage was not checked.
- `PREFLIGHT: UNREAD LAYER …` — the main checkout could not be verified, so its `settings.local.json`
  was not read and the findings are incomplete: a grant there is not credited (a verb may be
  over-reported) and a deny there is not reported at all. The summary is then
  `PREFLIGHT: INCOMPLETE …` rather than `OK`. Re-run from the main checkout, or pass `--project-root`
  naming it, to read that layer.

`--count` prints just the integer GAP count (NOTEs excluded) for a scripted gate. An unread layer is
not a gap, so the count is unchanged by it — read the summary line, not only the count. Surface any gap
**once, at loop start**, with the exact remediation, then proceed or degrade per the lane's
report-only posture — never rediscover the gap as per-operation prompts mid-cycle.

The check itself is a single up-front, read-only invocation (`git rev-parse` plus `jq` reads of
settings files) — it grants nothing and needs no allow rule of its own; a one-time classifier pass
for it at loop start is not the mid-cycle-prompt problem this step exists to remove.
