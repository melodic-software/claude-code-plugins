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
- **Cheap and bounded.** It returns fast and small. A slow or large-output command taxes every
  load; `!` timeout/output-size behavior is undocumented (see below), so don't lean on it.

Leave it as a body instruction when the step mutates state, is conditional on what Claude finds,
needs an argument Claude derives, or is expensive.

## Conventions we pin

These are Melodic Software conventions, not upstream doctrine. **Recheck trigger:** the skills
docs begin documenting `!` failure/timeout/stderr semantics — revisit both conventions then.

### Defensive fallback is mandatory

The skills docs (verified 2026-07-20) do **not** document what happens when an injected command
fails, times out, or writes to stderr — so we assume the worst: a failure could inline an error
string, partial output, or nothing into the prompt. Every injected command must therefore carry
an explicit fallback so the rendered skill degrades to a known string rather than a surprise:

```
- Working tree: !`git status --short || echo "(git status unavailable)"`
```

Use the `|| echo "<fallback>"` form (or the `shell:`-appropriate equivalent) on every
`` !`command` `` and every line inside a ` ```! ` block.

### Windows / `shell:` awareness

`shell:` defaults to `bash`; on Windows without Git Bash the PowerShell tool runs injected
commands instead (see the docs). Write injection commands portably, or declare `shell:`
explicitly, so a bash-only pipeline doesn't silently break on a PowerShell host — and pick a
`|| echo` fallback that is valid in the shell that will actually run it.

## Mechanics not to get wrong (pointers, not copies)

- **Single pass.** Substitution runs once over the file; injected output is inserted as plain
  text and never re-scanned. A command cannot emit a placeholder for a later pass.
- **Renders on every invocation path** — user `/name`, the Skill tool, and auto-invocation all
  preprocess. When injected output changes between invocations, Claude Code re-appends the full
  rendered content (v2.1.202+), so keep injected output stable and small.
- **Kill switch.** `disableSkillShellExecution` replaces each command with
  `[shell command execution disabled by policy]`. The skill must still make sense when that
  string appears in place of the output — never make correctness depend on injection succeeding.
- **Plugin paths.** Reference bundled scripts with `${CLAUDE_SKILL_DIR}` (or
  `${CLAUDE_PLUGIN_ROOT}` for a plugin's own tree) and project files with `${CLAUDE_PROJECT_DIR}`
  so injection is path-independent; see the substitution table in the docs.
