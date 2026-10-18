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

- Writes to `.claude/` settings fall under Claude Code's protected-path handling, so an agent
  cannot grant itself the widening.
- A `permissions` block shipped in a plugin's `settings.json` does not take effect, so a plugin
  cannot ship the grant either.

The work lanes also treat an auto-mode classifier denial as landing on the Bash tool call itself:
the script never runs, so there is no exit code to read.

### The dated record for both claims

- **Pointer**: when checking whether an agent may write its own settings, fetch
  [permission modes § Protected paths](https://code.claude.com/docs/en/permission-modes#protected-paths)
  live; when checking when the classifier reviews a call, fetch
  [§ How auto mode evaluates actions](https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions)
  live; when checking which plugin `settings.json` keys take effect, fetch
  [plugins manifest reference § Settings](https://code.claude.com/docs/en/plugins/manifest-reference#settings)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: any of those sections changes, or a release note names protected paths, the
  auto-mode classifier, or plugin `settings.json` keys.

So the operative grants live **operator-side**, and the loop-start step only **detects and reports**
the gap once, up front. It never edits settings, and never retries a permission/classifier denial
into broader grants (the never-self-retry posture: a denial is a stop, not a signal to widen).

## A denial this preflight cannot catch: the Step 0 `reclaim` asymmetry

`preflight.sh` only probes `permissions.allow`/`deny` **coverage** for a fixed git/gh verb set. It
does not, and should not, probe the tracker script's `claim`/`reclaim` verbs (see "The allow floor"
below for why a hand-maintained tracker-path rule doesn't fit that model). Work-loop self-observation
`#1381` recorded a denial this preflight has no way to surface: the tracker script's `reclaim` verb was refused
by the auto-mode classifier while the sibling `claim` verb on the same script, invoked moments
later, was NOT. At the time of writing, **neither** verb carries an explicit
`permissions.allow`/`deny` rule in the fleet's floor (`standards`
`components/claude-permissions/claude-permissions.json`). The asymmetry is therefore not an
allow-list coverage gap of the kind this doc otherwise describes; it reads as the classifier's own
heuristic judgment on the two commands.

Whether adding an explicit allow rule for the `reclaim` invocation would bypass that judgment is
**not settled by this doc**: it turns on which allow-rule shapes auto mode suspends and whether the
`classifyAllShell` setting is on, and a script invocation (`work-item-tracker.sh reclaim <id>`)
has to be checked against that live. Do not write a rule into the standards floor on the strength
of this doc alone; confirm the carve-out first.

- **Pointer**: before adding a `reclaim` allow rule, fetch
  [settings reference § `autoMode.classifyAllShell`](https://code.claude.com/docs/en/settings-reference#automode-classifyallshell)
  and [permission modes § How auto mode evaluates actions](https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions)
  live. **As of**: 2026-10-11. **Recheck trigger**: either section changes which allow rules auto
  mode suspends, or a release note names `classifyAllShell`.

`/work-items:work`'s Step 0 treats a classifier denial of
`reclaim` as a non-blocking, report-once-and-skip condition (see
`${CLAUDE_PLUGIN_ROOT}/skills/work/SKILL.md` "Step 0").
That is the current mitigation; a permission-rule fix, if one applies, still lives operator-side per
the pattern above.

## The allow floor: point at the standards component

Do not hand-maintain an allowlist here. The fleet's reviewed permission floor is the
`claude-permissions` component in the `melodic-software/standards` repository
(`components/claude-permissions/`): one canonical `permissions.allow` / `permissions.deny` set,
distributed as data and composed into each operator's live `~/.claude/settings.json` by the
dotfiles repository's chezmoi modify-template (union of the canonical floor with locally-accumulated
rules; the deny floor is never relaxed below the component).

What it covers, at a glance (read the component for the authoritative list):

- **allow**: the read-only git/gh inspection verbs plus the routine non-destructive working verbs
  an unattended loop needs without prompting: `git add` / `commit` / non-force `push` /
  `checkout` / `switch`, and `gh` PR and issue CRUD including `gh pr create` and
  `gh issue comment`. Rules are the narrow bare-command shape (`Bash(git commit *)`, not
  `Bash(git *)`) so they keep working under auto mode; broad wildcard shapes are the anti-pattern
  the convention above flags. Which shapes auto mode sets aside is read live from the
  `classifyAllShell` pointer under "A denial this preflight cannot catch" above.
- **deny**: the destructive-verb safety floor (force-push, hard reset, `clean`, checkout/restore
  discards, forced branch deletion, `--no-verify` bypass), the `gh api` DELETE surface, hook-disable
  environment prefixes, and secret-material `Read()` patterns. Deny always wins over allow.

The preflight probes a small representative subset of the allow floor: `git add`, `git commit`,
`gh pr create`, `gh issue comment` (a commit flow stages before it commits, so `git add` is probed
too). It does not probe a push: the lane never runs `git push`, it pushes only with `bash
<plugin-root>/scripts/lane-push.sh …` (loop-lane convention, "Lane write identity"). That call
is interpreter-led, so no allow rule pre-approves it
([permission-rule-hygiene](../../../docs/conventions/permission-rule-hygiene/README.md)); the
permission mode decides it, the auto-mode classifier in an unattended lane. It reads the effective `permissions.allow` from the operator's user-global settings
and the project settings. It never runs a live permission probe. A verb counts as covered only by an
**open-glob** grant: `Bash(git commit *)` or `Bash(git commit:*)`. A **bare-exact** rule
(`Bash(git commit)`) is **not** coverage: it permits only the argumentless command, and a work-lane
invocation always carries arguments, so the real call would still prompt. When a gapped verb has
*only* a bare-exact grant, the gap message says so precisely. That grant does cover an argumentless
call but not the work lane's argument-carrying one, and the remedy is to add the open glob
(`git commit *`). A narrower, flag-scoped rule
(`Bash(git commit --amend)`) is likewise not coverage. A missing
verb means the floor is not composed in on this machine; the remediation is to apply the component
operator-side, not to add a one-off rule.

**Deny wins over allow.** The check follows the permission model's rule precedence
([permissions § Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions);
**As of**: 2026-10-11; **Recheck trigger**: that section changes how deny and allow rules rank), so
it first tests each probed verb against the effective **deny** rules: a deny rule of
the verb (bare, or its open-glob form) keeps the verb a gap (reported distinctly as *denied*, not
*missing*) even when an identical allow rule exists, since the lane still cannot run it. Deny matching
deliberately errs **wider** than coverage. It also counts the bare-exact spelling, because a
false *denied* report is safe whereas a missed one is not. It is still **exact-shape only**: it does
not simulate glob semantics, so a broader deny pattern that would match the verb at runtime (a
wildcard spanning it) is not caught here. That conservatism never false-flags the standard deny
floor, whose destructive-verb rules are flag-scoped (`git push --force …`) rather than the bare
`git commit` / `git add` shape.

**`settings.local.json` scope on the autonomous path.** The preflight treats the **main
checkout's** `.claude/settings.local.json` as shared by the repository's linked worktrees, because
that is where a "Yes, don't ask again" approval lands when Claude Code uses the repository root,
which it does from **v2.1.211** (the floor; the preflight never probes the running version and has
no version branch). It does not hold everywhere: the approval stays with the worktree it was granted
in on Windows, when the repository root is the user's home directory, and when the repository root
or its `.git` or `.claude` entry is not owned by the user. The preflight detects those three cases
(also outside a git repository, which cannot apply to a linked worktree):

- **Windows**: `uname -s` matching `MINGW*`, `MSYS*` or `CYGWIN*` (`PREFLIGHT_UNAME` injects it for
  tests).
- **Root equal to `$HOME`**: the verified main checkout's root, compared after the same path folding
  the coverage checks use.
- **Root not owned by the user**: the owner (`stat`) of the root, its `.git` or its `.claude` entry
  differs from `id -u` (`PREFLIGHT_UID` overrides the current uid for tests).

In any of those layouts only the **worktree's own** `settings.local.json` is credited; the main
checkout's file is not, and the report opens with a `per-worktree approvals layout (<causes>)` line.
Deny rules keep reading the main checkout's file, erring wide as everywhere else. When the layout
cannot be determined (an owner or the current uid is unreadable, or neither `HOME` nor `USERPROFILE`
is set) the main checkout's file is likewise not credited, the layer is reported `UNREAD LAYER`, and
the summary is `PREFLIGHT: INCOMPLETE`, never `OK`.

- **Pointer**: when checking where a saved approval lands and which sessions it reaches, fetch
  [permissions § Permission system](https://code.claude.com/docs/en/permissions#permission-system)
  and [worktrees § What worktrees share with the main checkout](https://code.claude.com/docs/en/worktrees#what-worktrees-share-with-the-main-checkout)
  live. **As of**: 2026-10-11. **Recheck trigger**: either section changes where "Yes, don't ask
  again" saves the rule, how it resolves through worktrees, or which cases keep it in the worktree.

Where the shared save applies, the main
checkout's local file is therefore part of a fresh worker worktree's effective settings, and the
preflight credits it in **every** mode, but only once it has **verified** which directory that is.

**Resolving the main checkout.** Candidates are proposed cheapest-first and each is put through one
predicate before it is trusted; a candidate that fails is discarded, never named. The predicate has
three legs, all required: the candidate's `--show-toplevel` is the candidate itself (it is a
toplevel, not a subdirectory of one), its `--git-common-dir` is our common dir (it belongs to *this*
repository), and its `--git-dir` is also our common dir (it is the **main** worktree, not a linked
one). The candidates:

1. **The probed checkout itself**, whose own git dir *is* the common dir. True whatever the git dir
   is named, so the **main checkout of** a `--separate-git-dir` or submodule layout resolves here.
   The probed checkout is `--project-root` when given, else the cwd.
2. **`core.worktree`** in the common dir's config, resolved relative to that dir. Git writes it for
   submodules, which is what makes a submodule's `<super>/.git/modules/<name>` common dir resolvable at
   all, since no parent-of-`.git` arithmetic can invert it.
3. **The conventional `<root>/.git` spelling**, the parent of the common dir.

Resolution has three outcomes, and the report distinguishes them:

- **Verified**: a candidate passed. Only then is a path named as the main checkout, and only then
  is its `settings.local.json` read. The header prints git's own spelling of the verified toplevel.
- **Bare**: the repository has no main working tree, so no main-local layer can exist. Nothing is
  missing and the summary stays `OK`.
- **Unresolved**: no candidate passed. The layer is **UNREAD**, the report says so on its own line
  with the reason, and the summary is `PREFLIGHT: INCOMPLETE …`, never a bare `OK`. It is printed in
  **every** mode, the interactive one included. The two headers that name a main checkout print
  only under `--worktree-root` or a distinct `--project-root`, so a plain run from a linked worktree
  would otherwise drop a main-local deny with no output at all. The exit code is still `0`: the
  script is report-only and findings never fail the run.

What a fresh worker does **not** inherit is a local file living inside some *other* linked
worktree, such as a rule an older harness saved there or a hand-placed file, which applies only to sessions started in
that worktree. Two cases:

- **Pre-dispatch**: `--worktree-root` is passed but no distinct `--project-root` (the worker is not
  yet created). The **coverage** reads (allow + `additionalDirectories`) span user-global + tracked
  project settings + the main checkout's local file; only a linked-worktree cwd's *own* local file
  is dropped, since the fresh worker would not inherit it and reading it would mask a worker-side
  gap. Run from the main checkout, nothing is dropped. The report header says which, naming the
  main checkout only when resolution verified it.
- **A named worker**: `--project-root <worker-worktree>` resolves to a checkout whose toplevel
  differs from the cwd. That is a real, existing checkout, so the preflight reads **its own**
  `settings.local.json` (legacy rules saved there still apply to sessions started there) plus the
  main checkout's shared local file; the header names the sources, under the same condition.

**Two residual limits apply to BOTH modes above.**

- **Older harness: MASKING.** On a Claude Code version before v2.1.211, which predates the
  repository-wide save, a worktree session loads its own local file, not the main
  checkout's, so crediting a main-local-only grant suppresses a gap the worker really hits. Nothing
  in the preflight detects it: it never probes the running Claude Code version, and versions below
  the floor are out of scope. This is a floor on
  the *harness*, not on the repository layout, so wherever the installed Claude Code saves
  repository-wide it is a documentation-completeness matter rather than a live defect.
  Observation: the machine this was verified against ran v2.1.222.
- **`--separate-git-dir` is ambiguous in git itself. It is NOT a preflight defect, and not maskable
  in silence.** For a repository created with `--separate-git-dir <path>/.git`, the main working tree is
  the directory holding the `.git` *file*, but git records no back-pointer to it. A recursive search
  of the whole common dir turns up only `worktrees/<name>/gitdir` entries, which point at *linked*
  worktrees; `core.worktree` is unset by every creation path (`git init --separate-git-dir` on a
  fresh directory, `git clone --separate-git-dir`, and `git init --separate-git-dir` over an existing
  repository). Git's own `git worktree list` therefore reports `<path>` as the main worktree, and
  reports it identically when run *from* that true working tree. That `<path>` is the parent of the
  separate git *directory*, not of the `.git` file, which lives in the true working tree and is the
  very link git does not record in reverse. `<path>`
  also satisfies all three legs of the verification predicate, byte for byte, exactly as a
  conventional `<root>` does; any test strong enough to reject it also rejects the conventional
  layout. So the preflight resolves to `<path>`: **git's own answer**, arrived at by verification
  rather than by string arithmetic. Where the operator intended a different directory to be the
  working tree, the layout is ambiguous at the git level and no consumer of git can do better.
  Two consequences: `--separate-git-dir "$HOME/.git"` makes `$HOME` the main checkout
  by git's reckoning, so the operator's own `~/.claude/settings.local.json` is genuinely in scope for
  that repository; and a spelling that is *not* `<something>/.git` (a separate git dir under any
  other name) yields no candidate at all. That is the **unresolved** outcome above, which is
  reported loudly rather than passed over.

The interactive/default path (no `--worktree-root`) keeps the cwd checkout's local settings in
scope. Deny always reads every local layer it resolves, in every mode, on the same err-wide rationale;
an unresolved main checkout is the one layer it cannot widen, which is why that case is reported
rather than absorbed.

## The trusted worktree root: `additionalDirectories`

The lanes rely on `acceptEdits` only for writes inside the workspace root and treat any write
**outside** it as one that prompts.

- **Pointer**: when checking which writes `acceptEdits` approves, fetch
  [permission modes § Auto-approve file edits with acceptEdits mode](https://code.claude.com/docs/en/permission-modes#auto-approve-file-edits-with-acceptedits-mode)
  live. **As of**: 2026-10-11. **Recheck trigger**: that section changes the scope of writes
  `acceptEdits` approves, or a release note names `acceptEdits`.

The autonomous lanes dispatch implementation subagents into their own out-of-tree
worktrees (lifecycle owned by `source-control:worktree`), so every edit in a worktree is an
out-of-workspace write that prompts unless the worktree root is registered as a trusted directory
via `permissions.additionalDirectories`.

The fleet convention is a dedicated worktree root **outside the repo**, not the OS temp dir
(`source-control:worktree` places worktrees under its configured external root rather than Claude
Code's default worktree location; `babysit-prs` defaults its `babysit_worktree_root` to the
`worktrees` subdirectory of the plugin data directory).

- **Pointer**: when comparing the fleet root with Claude Code's own placement, fetch
  [worktrees § Start Claude in a worktree](https://code.claude.com/docs/en/worktrees#start-claude-in-a-worktree)
  and [§ Replace worktree creation with a hook](https://code.claude.com/docs/en/worktrees#replace-worktree-creation-with-a-hook)
  live. **As of**: 2026-10-11. **Recheck trigger**: either section changes where worktrees are
  created by default, or a release note names worktree placement.

The exact root is operator-configurable and not yet a
single documented constant across the fleet (the interim loop stopgap trusts `~/.claude-loop-worktrees`),
so the preflight checks **coverage of whatever root the lane is configured to use**. It does not
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
the checkout the orchestrator runs in, and the cwd checkout's grants would otherwise mask a
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

- `NOTE (a) …`: the cwd is not a git repository. Informational: a lane operating in an out-of-tree
  worktree proceeds once `(c)` is covered; a lane that needs a checkout at the cwd cannot.
- `GAP (b) …`: a probed working verb is denied by a matching deny rule, has only a bare-exact
  (argumentless) allow, or is not covered at all (the message distinguishes the three). Remediate
  operator-side: resolve the deny rule, add the open glob, or compose the standards floor in (above).
- `GAP (c) …`: the worktree root is not covered by `additionalDirectories`. Add the entry (above).
- `NOTE (c) …`: no worktree root was passed, so coverage was not checked.
- `PREFLIGHT: UNREAD LAYER …`: the main checkout could not be verified, so its `settings.local.json`
  was not read and the findings are incomplete: a grant there is not credited (a verb may be
  over-reported) and a deny there is not reported at all. The summary is then
  `PREFLIGHT: INCOMPLETE …` rather than `OK`. Re-run from the main checkout, or pass `--project-root`
  naming it, to read that layer. The same line and summary report an undeterminable approvals
  layout (above), where the layer was read but not credited.
- `PREFLIGHT: per-worktree approvals layout (…)`: Windows, a root equal to `$HOME`, or a root not
  owned by the user, so only the worktree's own `settings.local.json` is credited.

`--count` prints just the integer GAP count (NOTEs excluded) for a scripted gate. An unread layer is
not a gap, so the count is unchanged by it. Read the summary line, not only the count. Surface any gap
**once, at loop start**, with the exact remediation, then proceed or degrade per the lane's
report-only posture. Never rediscover the gap as per-operation prompts mid-cycle.

The check itself is a single up-front, read-only invocation (`git rev-parse` plus `jq` reads of
settings files). It grants nothing and needs no allow rule of its own; a one-time classifier pass
for it at loop start is not the mid-cycle-prompt problem this step exists to remove.
