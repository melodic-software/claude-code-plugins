# Precomputed context — `!` dynamic-context injection

Locally-owned Melodic Software guidance (not part of the upstream playbook). It states
*when* to precompute and the conventions we pin; it does **not** restate the syntax — the
authoritative reference is
[Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
in the skills docs. Read that for the exact `` !`command` `` inline and ` ```! ` fenced forms,
substitution variables, and the `shell:` / `disableSkillShellExecution` settings.

## What it is

`` !`command` `` and ` ```! ` blocks run at load time and their **output replaces the
placeholder before Claude sees the skill** — preprocessing, not a tool call Claude makes. One
deterministic command's result arrives already inlined, saving a per-invocation tool round-trip.

## When to precompute

Convert a context-gathering step to `!` injection when **all** hold:

- **Deterministic and read-only.** The command only observes state (e.g. `git status`,
  `git diff`, `ls`, a version probe). It must not mutate anything — every injection runs on
  every invocation, including auto-invocation the author never sees.
- **Needed up front, every time.** The skill always wants this context before it reasons.
  One-off or branch-dependent lookups belong in the body as instructions, not injection.
- **Independent of Claude's judgement.** The command doesn't depend on a decision Claude makes
  first. Injection is a single pass — output is not re-scanned, so one placeholder cannot feed
  another (see the docs); anything requiring a computed argument stays a normal tool call.
- **Cheap and bounded.** It returns fast and small. Every injected command runs under the Bash
  tool's default two-minute timeout, and output past the inline ceiling arrives as a file path plus
  a short preview rather than as text, so a slow or large-output command either delays every load
  or hands Claude a path instead of the data
  ([How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run)).

Leave it as a body instruction when the step mutates state, is conditional on what Claude finds,
needs an argument Claude derives, or is expensive.

## Conventions we pin

These are Melodic Software conventions, not upstream doctrine. They rest on the failure, timeout,
stderr, and output-size semantics the skills page documents under
[How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run) and
[When an injected command fails](https://code.claude.com/docs/en/skills#when-an-injected-command-fails),
read 2026-09-02. **Recheck trigger:** a re-read of either section no longer matching the claims
below, or the page documenting the shell options injections run under.

### Defensive fallback is mandatory

A failed injected command aborts the whole skill invocation: Claude never sees the skill content for
that invocation. With the default `bash` shell any non-zero exit counts as a failure, except exit code
1 from the search and comparison commands the docs list. A command the Bash tool cannot background is
killed at the two-minute timeout and aborts the same way. stderr merges into stdout and lands in the
injected text
([When an injected command fails](https://code.claude.com/docs/en/skills#when-an-injected-command-fails),
read 2026-09-02). Every injected command must therefore carry an explicit fallback, so a probe that
cannot run degrades the rendered skill to a known string instead of preventing the skill from loading
at all:

```
- Working tree: !`git status --short || echo "(git status unavailable)"`
```

Use the `|| echo "<fallback>"` form (or the `shell:`-appropriate equivalent) on every
`` !`command` `` and every line inside a ` ```! ` block.

### Bind the fallback to the probe, not to the pipeline

`||` applies to the whole pipeline, and a pipeline's exit status is its last command's. So
`probe | head -20 || echo "(unavailable)"` never runs the fallback: `head` exits 0 whether the
probe produced twenty lines, one line, or nothing at all. The rendered value is an empty string,
and under a label like `Working tree status:` an empty string reads as a healthy result rather
than a failed probe.

Put the fallback in a brace group with the probe, and apply the cap outside it:

```text
Working tree status (empty = clean): !`{ git status --porcelain 2>/dev/null || echo "(git status unavailable)"; } | head -20`
```

Two rules follow from the same reasoning:

- **A probe that exits 0 with empty output needs more than a fallback.** `git branch --show-current`
  succeeds and prints nothing on a detached HEAD, so `|| echo "unknown"` cannot fire there. Either
  pick a probe that fails on the condition (`git symbolic-ref --quiet --short HEAD`) or state in the
  label what an empty value means.
- **Say in the label what empty means**, so a reader can tell a clean tree from a probe that
  produced nothing.

Keep the brace group free of `$`. The worktree-isolation guard cannot verify a composed pre-compute
block that expands anything other than bare `$HOME`, and the skill then fails to load from an
isolated agent. The guard's exact trigger is not pinned down, so leaving `$` out of the group is the
form that is safe under every reading.

### `pipefail` is an open question; the brace group is correct either way

Whether Claude Code runs `!` injections under `set -o pipefail` is **unsettled**. The skills docs
specify the working directory, stderr merging, timeout, output size, and the exit-code semantics
of an injected command, but name no shell options. Assume either setting, and write a probe that
renders the same under both.

The brace-group form above does. Its fallback fires on the probe's own exit status and its cap
sits outside the group, so no downstream stage can change what renders.

A `guard && probe | filter | head -N || echo "(unavailable)"` shape does not. It is correct under
exactly one setting, and which one it needs depends on the state:

- **Without `pipefail`** the pipeline's status is `head`'s, so the trailing `|| echo` never fires
  and a failed filter stage renders empty under a label claiming the opposite.
- **With `pipefail`** `head -N` closes the pipe once it has its N lines, the upstream stage takes
  SIGPIPE, and the pipeline exits 141, so a healthy at-cap render gains a spurious
  `(unavailable)` line.

The brace group buys that at a price worth naming. Its final `:` makes the outer `||` unreachable,
so a failure INSIDE the group also renders empty: a filter binary off PATH, or a second `git`
invocation that fails after the guard's copy succeeded. The label carries that weight instead, and
must never assert a bare `empty = none`.

### Windows / `shell:` awareness

`shell:` defaults to `bash`; on Windows without Git Bash the PowerShell tool runs injected
commands instead (see the docs). Write injection commands portably, or declare `shell:`
explicitly, so a bash-only pipeline doesn't silently break on a PowerShell host — and pick a
`|| echo` fallback that is valid in the shell that will actually run it.

## Mechanics not to get wrong (pointers, not copies)

- **Single pass.** Substitution runs once over the file; injected output is inserted as plain
  text and never re-scanned. A command cannot emit a placeholder for a later pass.
- **Renders on every invocation path**: user `/name`, the Skill tool, and auto-invocation all
  preprocess. When injected output changes between invocations, Claude Code appends the full
  rendered content again ([Skills](https://code.claude.com/docs/en/skills), read 2026-09-02), so
  keep injected output stable and small.
- **Kill switch.** `disableSkillShellExecution` replaces each command with
  `[shell command execution disabled by policy]`. The skill must still make sense when that
  string appears in place of the output — never make correctness depend on injection succeeding.
- **Plugin paths.** Reference bundled scripts with `${CLAUDE_SKILL_DIR}` (or
  `${CLAUDE_PLUGIN_ROOT}` for a plugin's own tree) and project files with `${CLAUDE_PROJECT_DIR}`
  so injection is path-independent; see the substitution table in the docs.
