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
and the project's `.claude/settings.json` / `settings.local.json`. It never runs a live permission
probe. A verb counts as covered only by an **open** grant — the bare verb (`Bash(git commit)`) or
its open-glob form (`Bash(git commit *)` / `Bash(git commit:*)`). A narrower, flag-scoped rule
(`Bash(git commit --amend)`, a force-with-lease-only push rule) is **not** coverage: the lane's
arbitrary `git commit` / `git push` would still prompt, so it is reported as a gap. A missing verb
means the floor is not composed in on this machine; the remediation is to apply the component
operator-side, not to add a one-off rule.

**Deny wins over allow.** Because `permissions.deny` overrides `permissions.allow` in the permission
model, the check first tests each probed verb against the effective **deny** rules: a deny rule of
the bare verb or its open-glob form keeps the verb a gap (reported distinctly as *denied*, not
*missing*) even when an identical allow rule exists — the lane still cannot run it. This deny match
is **exact-shape only**: it does not simulate glob semantics, so a broader deny pattern that would
match the verb at runtime (a wildcard spanning it) is not caught here. That conservatism is
deliberate — it never false-flags the standard deny floor, whose destructive-verb rules are
flag-scoped (`git push --force …`) rather than the bare `git push` / `git commit` / `git add` shape.

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

**Check the worktree the lane actually runs in.** Project `.claude/settings(.local).json` is
per-checkout, so a fresh linked worktree can carry different grants than the main checkout — and the
main checkout's grants would otherwise mask a worker-side gap. When the orchestrator dispatches a
worker into a worktree, pass that worktree as `--project-root` so its own project settings are the
ones probed:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/work/scripts/preflight.sh" \
  --project-root <dispatched-worker-worktree> --worktree-root <configured-worktree-root>
```

`--project-root` defaults to the current checkout. User-global settings apply everywhere and are
read regardless of it; only the project layer is re-pointed.

It is report-only and always exits `0`. Each output line is one of:

- `NOTE (a) …` — the cwd is not a git repository. Informational: a lane operating in an out-of-tree
  worktree proceeds once `(c)` is covered; a lane that needs a checkout at the cwd cannot.
- `GAP (b) …` — a probed working verb is denied by a matching deny rule, or is not covered by any
  allow rule (the message distinguishes the two). Remediate operator-side: resolve the deny rule, or
  compose the standards floor in (above).
- `GAP (c) …` — the worktree root is not covered by `additionalDirectories`. Add the entry (above).
- `NOTE (c) …` — no worktree root was passed, so coverage was not checked.

`--count` prints just the integer GAP count (NOTEs excluded) for a scripted gate. Surface any gap
**once, at loop start**, with the exact remediation, then proceed or degrade per the lane's
report-only posture — never rediscover the gap as per-operation prompts mid-cycle.

The check itself is a single up-front, read-only invocation (`git rev-parse` plus `jq` reads of
settings files) — it grants nothing and needs no allow rule of its own; a one-time classifier pass
for it at loop start is not the mid-cycle-prompt problem this step exists to remove.
