# Precomputed context: `!` dynamic-context injection

## Contents

- [What it is](#what-it-is)
- [When to precompute](#when-to-precompute)
- [Conventions we pin](#conventions-we-pin)
- [Mechanics not to get wrong (pointers, not copies)](#mechanics-not-to-get-wrong-pointers-not-copies)

Locally-owned Melodic Software guidance (not part of the upstream playbook). It states
*when* to precompute and the conventions we pin; it does **not** restate the syntax. The
authoritative reference is
[Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
in the skills docs. Read that for the exact `` !`command` `` inline and ` ```! ` fenced forms,
substitution variables, and the `shell:` / `disableSkillShellExecution` settings.

## What it is

`` !`command` `` and ` ```! ` blocks run at load time and their **output replaces the
placeholder before Claude sees the skill**. One deterministic command's result arrives already
inlined, saving a per-invocation tool round-trip. Each command is still permission-checked before it
runs; see [Grant every injected command](#grant-every-injected-command).

## When to precompute

Convert a context-gathering step to `!` injection when **all** hold:

- **Deterministic and read-only.** The command only observes state (e.g. `git status`,
  `git diff`, `ls`, a version probe). It must not mutate anything. Every injection runs on
  every invocation, including auto-invocation the author never sees.
- **Needed up front, every time.** The skill always wants this context before it reasons.
  One-off or branch-dependent lookups belong in the body as instructions, not injection.
- **Independent of Claude's judgment.** The command doesn't depend on a decision Claude makes
  first. Anything requiring a computed argument, another placeholder's output included, stays a
  normal tool call; the pass rules are in the section linked at the top of this page.
- **Cheap and bounded.** It returns fast and small, since every load waits for it and a large
  output may not arrive inline. For the timeout and output limits, fetch
  [How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run)
  live.
- **Grantable.** A narrow `allowed-tools` rule in the skill covers it, and it is not the kind of
  command a consumer's ask or deny rule plausibly matches (see
  [Grant every injected command](#grant-every-injected-command)).

Leave it as a body instruction when the step mutates state, is conditional on what Claude finds,
needs an argument Claude derives, is expensive, or cannot be granted that narrowly.

## Conventions we pin

These are Melodic Software conventions, not upstream doctrine. The permission convention carries
its own record; the others rely on this one:

- **Pointer**: when deciding how an injected command fails, times out, or reports stderr and large
  output, fetch
  [How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run) and
  [When an injected command fails](https://code.claude.com/docs/en/skills#when-an-injected-command-fails)
  live.

### Grant every injected command

We design every injected command for the default permission mode, where a command the permission
check refuses aborts the skill load. We therefore:

- **Pre-approve every injected line in the skill's own `allowed-tools`**, with a rule narrow enough
  to name that command, covering every subcommand on the line, the fallback and any output cap
  included, not only the probe.
- **Move a command out of `!` injection** into a body instruction Claude runs as a normal tool call
  when a consumer's deny or ask rule could plausibly match it, or when no narrow rule covers it.
- **Never treat the `|| echo` fallback below as the permission guard.** The grant is that guard.

- **Pointer**: when deciding whether an injected command will load under a consumer's rules or
  permission mode, fetch
  [Permission checks on injected commands](https://code.claude.com/docs/en/skills#permission-checks-on-injected-commands)
  live; for what an `allowed-tools` grant covers and when an organization setting makes Claude Code
  ignore it, fetch [Pre-approve tools for a skill](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill);
  for how a rule matches a line joined by `||` or `|`, fetch
  [Compound commands](https://code.claude.com/docs/en/permissions#compound-commands).

### Defensive fallback is mandatory

Which exits and timeouts count as a failed injected command is in the record above. Every injected
command must carry an explicit fallback, so a probe that
runs and fails degrades the rendered skill to a known string instead of preventing the skill from
loading at all. Permission refusals are the grant's job, not the fallback's (see above):

```
- Working tree: !`git status --short || echo "(git status unavailable)"`
```

Use the `|| echo "<fallback>"` form (or the `shell:`-appropriate equivalent) on every
`` !`command` `` and every line inside a ` ```! ` block.

### No brace group or subshell in an injected command

Write every injected command as a plain list: probes joined by `&&`, `||`, `;` and `|`, with no
brace group (`{ …; }`) and no subshell (`( … )`). A tool probe is the probe, `||`, and a fallback
word:

```text
- `jq`: !`command -v jq 2>/dev/null || echo absent`
```

We hold this rule because of what a headless probe in default permission mode observed. The shell
permission check refused every grouped row before it ran, so the skill rendered nothing: a brace
group with or without a quote inside it, and a subshell with or without one. A narrow
`allowed-tools` grant for the probe did not lift either refusal. A blanket `Bash` grant did let the
brace group through, but we never use one to rescue a group, because it breaks
[Grant every injected command](#grant-every-injected-command). The same row written as a plain list
rendered once its command was granted, with or without a quoted fallback word, and was refused
without the grant. `${VAR}` parameter expansion is not a group in this sense. The probe did not
cover an `if … fi` compound, so prefer a plain list there too.

- **Pointer**: when deciding whether a grouped or ungrouped injected command loads, read the probe
  command and its rows under "Probe evidence" in
  [pull request #7068](https://github.com/melodic-software/claude-code-plugins/pull/7068) and rerun
  them on the current release; for how the render treats a permission check result, fetch
  [Permission checks on injected commands](https://code.claude.com/docs/en/skills#permission-checks-on-injected-commands)
  live.
- **As of**: 2026-10-11 (Claude Code 2.1.296)
- **Recheck trigger**: a Claude Code release note changes which Bash shapes the permission check
  can analyze, or that section starts naming syntax the check refuses.

### Bind the fallback to the probe, not to the pipeline

`||` applies to the whole pipeline, and a pipeline's exit status is its last command's. So
`probe | head -20 || echo "(unavailable)"` never runs the fallback: `head` exits 0 whether the
probe produced twenty lines, one line, or nothing at all. The rendered value is an empty string,
and under a label like `Working tree status:` an empty string reads as a healthy result rather
than a failed probe.

Since no group can hold the probe and its fallback together, put a guard that fails on the
condition in front of the pipeline, and repeat the guard before the fallback:

```text
Working tree status (empty = clean, or git status failed after the check): !`git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git status --porcelain 2>/dev/null | head -20 || git rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "(not a git repository)"`
```

The list reads `((guard && probe | cap) || guard) || fallback`. When the guard fails, both copies
fail and the fallback renders. When the guard passes, the fallback never runs, whatever the
pipeline's status.

Two rules follow from the same reasoning:

- **A probe that exits 0 with empty output needs more than a fallback.** `git branch --show-current`
  succeeds and prints nothing on a detached HEAD, so `|| echo "unknown"` cannot fire there. Either
  pick a probe that fails on the condition (`git symbolic-ref --quiet --short HEAD`) or state in the
  label what an empty value means.
- **Say in the label what empty means**, so a reader can tell a clean tree from a probe that
  produced nothing.

Keep a pre-compute block that runs `git` free of `$`. The worktree-isolation guard blocks a Bash command when it
cannot verify from the command text that any git the command runs stays inside the worktree: a
command name computed at runtime, syntax it cannot parse, or an expansion such as `${!name}` or
`${ command; }` that could run a command the text does not spell out. Claude Code 2.1.257 stopped
refusing loops, `$VAR` reads, `"$(…)"`, and heredocs that never touch git, and 2.1.259 stopped
refusing common loops, xargs pipelines, and launcher-wrapped commands that cannot reach the main
checkout. Whether a plain `$VAR` read is accepted today is unsettled: a 2026-09-30 session had
`sed -n ... $F` refused, which may contradict the 2.1.257 fix (the report names no release), and no
probe has reconciled them (`/source-control:worktree` owns the record, under "Accepted command
shapes for body-time and subagent Bash"). The compose gate
(`scripts/check-skill-precompute-compose.sh`) already fires only when a pre-compute block holds a
git command and more than one injection line. A composed pre-compute block still leaves `$` out, other than a bare `$HOME` a probe has
shown the guard accepts, because a block that expands anything else is the shape the page still
refuses when the expansion can hide a command.

**Record.** Claim: the refusal cases in the paragraph above, including the two changelog fixes and the git-only scope of the compose gate.
Basis: <https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation> (Command
shape), the gather-block composition record in `/source-control:worktree`, and the Claude Code 2.1.257 and 2.1.259 changelog items for worktree-isolated Bash.
As of: 2026-09-28. Recheck: the Command shape bullet changes which expansions are refused, or a
release note again changes which Bash forms an isolated session accepts.

### Write for either `pipefail` setting; the repeated guard is correct under both

The skills docs specify the working directory, stderr merging, timeout, output size, and the
exit-code semantics of an injected command, but name no shell options. A headless probe rendered
a row as it would without `pipefail`, but no page promises that, so write a probe that renders the
same under both settings.

The repeated-guard form above does:

- **Without `pipefail`** the pipeline's status is `head`'s, 0, so the fallback stays silent and
  the capped output renders.
- **With `pipefail`** `head -N` closes the pipe once it has its N lines, the upstream stage takes
  SIGPIPE, and the pipeline exits 141. The second guard still passes, so the fallback stays silent
  here too, and a healthy at-cap render gains no spurious line.

A `guard && probe | filter | head -N || echo "(unavailable)"` shape without the second guard is
correct under exactly one setting: without `pipefail` a failed filter stage renders empty under a
label claiming the opposite, and with `pipefail` a healthy at-cap render gains a spurious
`(unavailable)` line.

The repeated guard has a price. Once the guard passes, the fallback is unreachable,
so a failure after the guard also renders empty: a filter binary off PATH, or a second `git`
invocation that fails after the guard's copy succeeded. The label carries that weight instead, and
must never assert a bare `empty = none`.

- **Pointer**: when deciding whether a row may rely on either `pipefail` setting, fetch
  [How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run)
  live; the probe row is under "Probe evidence" in
  [pull request #7068](https://github.com/melodic-software/claude-code-plugins/pull/7068).
- **As of**: 2026-10-11 (Claude Code 2.1.296)
- **Recheck trigger**: that section starts naming the shell options injections run under.

### Windows / `shell:` awareness

Which tool runs injected commands depends on `shell:` and the host: fetch
[How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run) and
the `shell` row of
[Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live.
Write injection commands portably, or declare `shell:`
explicitly, so a bash-only pipeline doesn't silently break on a PowerShell host, and pick a
`|| echo` fallback that is valid in the shell that will run it.

Grant a `shell: powershell` injection with a `PowerShell(...)` rule, not a `Bash(...)` rule. A
headless probe in default permission mode on native Windows injected a command that needs approval:
it was refused with no grant and with a `Bash(<cmd> *)` grant, and it passed the permission check
with a `PowerShell(<cmd> *)` grant. The probe set `shell: powershell` explicitly; it did not cover a
skill that reaches the PowerShell tool because bash is unavailable.

- **Pointer**: when deciding which rule form grants a PowerShell-run injection, read the probe table
  in [the probe record](https://github.com/melodic-software/claude-code-plugins/issues/6871#issuecomment-6632286031)
  and rerun it on the current release; for the rule syntax, fetch
  [PowerShell permission rules](https://code.claude.com/docs/en/permissions#powershell) live; for
  how the render treats a permission check result, fetch
  [Permission checks on injected commands](https://code.claude.com/docs/en/skills#permission-checks-on-injected-commands)
  live.
- **As of**: 2026-11-04 (Claude Code 2.1.316)
- **Recheck trigger**: a Claude Code release note changes how a `shell: powershell` injection is
  permission-checked, or the Permission checks on injected commands section starts naming which rule
  form covers a PowerShell-run injection.

## Mechanics not to get wrong (pointers, not copies)

- **Single pass.** Never design an injected command to emit a placeholder for another to expand;
  the pass rules are in the section linked at the top of this page.
- **Renders on every invocation path**: user `/name`, the Skill tool, and auto-invocation all
  preprocess. Keep injected output stable and small, since output that changes between
  invocations costs context again: fetch
  [Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle) live.
- **Kill switch.** `disableSkillShellExecution` puts placeholder text in place of every command
  (its wording is in the section linked at the top of this page). The skill must still make sense
  when that text appears in place of the output. Never make correctness depend on injection
  succeeding.
- **Plugin paths.** Reference bundled scripts with `${CLAUDE_SKILL_DIR}` (or
  `${CLAUDE_PLUGIN_ROOT}` for a plugin's own tree) and project files with `${CLAUDE_PROJECT_DIR}`
  so injection is path-independent; see the substitution table in the docs.
