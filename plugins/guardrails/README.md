# guardrails

A Claude Code plugin bundling eleven **safety guards** that catch risky agent
actions the moment they happen — before a write lands or a bash command runs.
Each guard is independently toggleable, so you run exactly the subset you want.

## The guards

| Guard | Event / matcher | Behavior | What it catches |
|-------|-----------------|----------|-----------------|
| **secret-pattern-detection** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | High-confidence secret/credential patterns (AWS/GitHub/GitLab/Slack/Stripe/OpenAI keys, PEM private keys) in new file content. |
| **hardcoded-path-check** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | Hardcoded machine-specific paths — Windows drive-letter homes, macOS/Linux user homes, machine-specific repo checkout roots. |
| **block-no-verify** | PreToolUse · Bash | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and hook-manager disable env vars — a configurable prefix set defaulting to `lefthook`, `husky`, `pre_commit`, `simple_git_hooks` (e.g. `LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`), tunable via `block_no_verify_hook_manager_prefixes`, including inside compound `cd … && …` commands. |
| **block-dangerous-git** | PreToolUse · Bash | **Blocks** (exit 2) | Irreversible git operations: `push --force`/`-f` plus the equivalent leading-`+` refspec and `--mirror` forms (never `--force-with-lease`; a push dry-run disarms), `reset --hard`, `clean` with a force flag (any dry-run flag disarms), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, `:(top…)` — path-scoped forms and `restore --staged .` pass), and forced `checkout -f` / `switch --discard-changes`. Accepted unique-prefix abbreviations of the blocked long options match too. `branch -D` is deliberately not blocked (reflog-recoverable; sanctioned skill flows issue it). Per-repo/per-user allow-list via the `block_dangerous_git_allow` userConfig option (comma list, any subset of `push-force,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force`). |
| **block-hook-bypass** | PreToolUse · Bash | **Blocks** (exit 2) | Bash file-write workarounds that circumvent the Write/Edit hook gates — `cat > file`, `echo … > file`, and `python3 -c` with file-write indicators. Executable-token detection ignores quoted prose/commit text that merely mentions the pattern. |
| **cli-flag-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | Hallucinated CLI flags — a `--flag` written as a command that does not exist in the binary's actual `--help` output. Surfaces via `additionalContext`, never blocks. |
| **workflow-resilience-check** | PreToolUse · Workflow | **Advisory** (exit 0) | Un-throttled Workflow fan-out — a script calling `parallel()` / `pipeline()` with no wave-cap throttle (`inWaves` / `inWavesPipeline`) and no retry wrapper (`agentRetry`), which risks a burst 529 under wide Opus fan-out. Surfaces a resilience checklist via `additionalContext`, never blocks. |
| **block-noncanonical-commit** | PreToolUse · Bash | **Blocks** (exit 2) | `git commit` that does not pipe its message via `-F -` / `--file -` — `-m` flattens newlines unpredictably across shells. Exempt: `--amend`, `-C`/`-c`/`--reuse-message`/`--reedit-message`, `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge/rebase/cherry-pick/revert is in progress. Resolves `bash -lc` wrappers and git aliases (inline `-c` and persisted config alike). |
| **block-convention-violation** | PreToolUse · Bash | **Blocks** (exit 2) | A commit subject or `gh pr create --title` that violates the team-tracked convention pattern declared in `.claude/source-control.md`. No tracked pattern means no enforcement. Same exemptions as `block-noncanonical-commit`. |
| **flag-commit-pr-skill-bypass** | PreToolUse · Bash | **Advisory** (exit 0) | Any `gh pr create`, bypassing this marketplace's own `/pull-request create` skill. Only fires when the consuming project's own `.claude/settings.json` enables the `source-control` plugin — silent otherwise. Surfaces via `additionalContext`, never blocks. |
| **skill-reference-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | A `` `/plugin:skill` `` reference in markdown that does not resolve. Only fires inside a marketplace repo, and only for a plugin that repo's own manifests own — a reference to another marketplace is left alone. Resolves through manifest and frontmatter `name`, so a renamed directory still matches. Surfaces via `additionalContext`, never blocks. |

The seven blocking guards feed their stderr message back to Claude as
actionable fix guidance. The four advisory guards surface their findings the same
way but always allow the operation.

### Enforceability tiers

Ten guards are **deterministic** — their oracle is a mechanical test with no
judgment step. `skill-reference-verify` is **detect-then-judge**: globbing a
plugins tree is exact only inside a marketplace repo that owns the referenced
plugin, so its finding is a prompt for a human verdict, never a determination and
never an auto-fix. `cli-flag-verify` is deterministic in its oracle but advisory in
its action, because a written claim can be deliberately forward-looking.

### Scope notes

- **Hook-manager coverage.** `block-no-verify` recognizes the disable env-var
  prefixes of a configurable manager set — `lefthook`, `husky`, `pre_commit`,
  and `simple_git_hooks` by default (`LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`,
  `SIMPLE_GIT_HOOKS=0`, …). Extend or narrow it with the
  `block_no_verify_hook_manager_prefixes` userConfig option (see Consumer seams).
  Independent of that set, the manager-agnostic `--no-verify` / `-n` and
  `core.hooksPath=` checks catch bypasses regardless of which manager runs the
  hooks.
- **Argv-grammar-faithful matching (and its residual).** `block-no-verify` and
  `block-dangerous-git` share one parser (in the bundled hook-utils library)
  that parses the command the way the shell builds argv — segmenting on
  unquoted operators and tokenizing each segment honoring `'…'`, `"…"`, `$'…'`
  (ANSI-C), and backslash escapes. Flags and pathspecs are matched on parsed
  argv words across quoting, escaping, wrappers (`env -i git …`, `nice git …`,
  `sudo -u x git …`), and git global options (`git -C <dir> commit …`) — so a
  `--no-verify` inside a quoted `-m` value stays a message, quoted prose never
  fires, and `checkout .github/x` never matches `checkout .`. The parser does
  **not** evaluate shell variable / command substitution (`$VAR`, `$(…)`,
  `$IFS`) — a determined author can construct an expansion-based bypass. An
  inline env prefix (`HOOK_..._ENABLED=false git push -f`) does **not** disable
  a hook — the prefix reaches only the spawned git process; disabling requires
  settings-level env (the settings.json write is the residual trust boundary).
  **These are friction guards against accidental/casual bypass, not a
  sandbox.** (A command longer than 16 KB is not parsed and is blocked
  fail-closed.)
- **`block-hook-bypass` string-matching floor.** Detection strips quoted literal
  spans before matching the executable token, so quoted prose or a commit
  message merely mentioning `cat >` / `python3 -c open(...)` is not flagged. The
  accepted residual: a write inside a command substitution in double quotes
  (`echo "$(python3 -c 'import pathlib …')"`) is **not** caught — the strip
  treats the quoted span as inert. Same friction-guard, not-a-sandbox posture as
  `block-no-verify`.
- **`flag-commit-pr-skill-bypass` is a nudge, not a gate.** Detection is a
  literal-stripped top-level regex match, not a full argv-grammar parser — it
  does not evaluate shell variable / command substitution, and a determined
  author can construct a form that evades it. It cannot tell "the skill ran
  this exact command" from "someone hand-typed the same shape", and for
  `gh pr create` there is no command-shape signature at all, so every direct
  call is flagged. It stays advisory and cannot become otherwise:
  `/pull-request create` issues that exact command itself, so blocking it would
  deadlock the skill being advertised. `create.md` also documents a legitimate
  inline fallback when skill discovery is broken.

- **`block-noncanonical-commit` gates shape, not skill invocation.** No hook can
  see which skill (if any) originated a Bash call, so "did you run `/commit`" is
  not an available condition — and shape is the better target regardless, since
  it enforces an outcome verifiable in `git log`. It deliberately does not
  require `--trailer`: `/commit` omits the trailer under a resolved
  `trailer_policy` of `none`, so demanding it would block the skill's own
  conformant output in repos whose convention forbids co-author trailers.

## Per-hook kill switches

Each guard is toggled by its own `userConfig` boolean (default **on**; set to
`false` for a clean no-op). This per-hook control is the bundle's core
contract — disable one guard without touching the others.

| Guard | Option |
|-------|--------|
| secret-pattern-detection | `secret_pattern_detection_enabled` |
| hardcoded-path-check | `hardcoded_path_check_enabled` |
| block-no-verify | `block_no_verify_enabled` |
| block-dangerous-git | `block_dangerous_git_enabled` |
| block-hook-bypass | `block_hook_bypass_enabled` |
| block-noncanonical-commit | `block_noncanonical_commit_enabled` |
| cli-flag-verify | `cli_flag_verify_enabled` |
| workflow-resilience-check | `workflow_resilience_check_enabled` |
| flag-commit-pr-skill-bypass | `flag_commit_pr_skill_bypass_enabled` |

Set them interactively with `/plugin configure guardrails`, or headless on the
install command:

```shell
claude plugin install guardrails@melodic-software --config hardcoded_path_check_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To turn guards off for a single repository, disable the whole
plugin in that project's `enabledPlugins` instead.

## Consumer seams

The guards scope and tune themselves to **your** repository — they ship no
repo-specific policy of their own:

- **Project scoping.** `secret-pattern-detection` and `hardcoded-path-check`
  only police files under `$CLAUDE_PROJECT_DIR`; a write into a sibling repo is
  that repo's concern. With no active project (`CLAUDE_PROJECT_DIR` unset) —
  or a project dir that is **not a git working tree** (a home-directory
  session, say; Claude Code sets the project dir for any directory) — the two
  diverge by threat model: `hardcoded-path-check` skips entirely — such a
  target (a `$HOME` dotfile, a machine-local `.claude/*.conf`) is
  machine-local, not a portable repo artifact, and outside a work tree the
  gitignore allowlist below could never exempt it — while secret scanning
  fails **closed** and scans anyway (secrets are dangerous anywhere).
- **Gitignore is the allowlist.** `hardcoded-path-check` skips any file
  `git check-ignore` matches against your `$CLAUDE_PROJECT_DIR` — put
  machine-local files (`settings.local.json`, `.venv/`, …) in your
  `.gitignore` and they are exempt automatically. (Applies within an active
  project; with none, the hook already skips per the scoping rule above.)
- **Secret allowlist.** A generic built-in allowlist exempts dependency caches
  (`.venv/`, `node_modules/`), `.env.example` / `.sample` / `.template`
  placeholders, `tests/fixtures` / `tests/testdata` trees, `settings.local.json`,
  `CLAUDE.local.md`, and hook scripts.
- **CLI-flag tuning.** `cli-flag-verify` checks a default binary set
  (`claude gh dotnet docker npm kubectl terraform az aws`); override with the
  `cli_flag_verify_bins` option (`bin1,bin2,…`) and skip specific binaries
  with `cli_flag_verify_skip_bins`.
- **Hook-manager prefixes.** `block-no-verify` reads its recognized
  hook-manager disable-env-var prefixes from `block_no_verify_hook_manager_prefixes`
  (comma list, default `lefthook, husky, pre_commit, simple_git_hooks`). Add a
  manager your project uses, or narrow the set. Values are reduced to identifier
  characters before use, so a consumer value can never inject regex metacharacters.
  The manager-agnostic `--no-verify` / `-n` and `core.hooksPath=` checks run
  regardless of this list.
- **Skill-availability gating.** `flag-commit-pr-skill-bypass` resolves
  `enabledPlugins` the way Claude Code merges it across scopes — user-global
  (`$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`) as the
  base, the project's `.claude/settings.json` overriding it, and
  `.claude/settings.local.json` overriding that (a local override counts only
  for a key the project already declares — CC ignores a local-only key per
  [anthropics/claude-code#27247](https://github.com/anthropics/claude-code/issues/27247)).
  Each exact `source-control@…` key is resolved independently; if ANY resolves
  enabled the advisory fires. So a plugin enabled **only** at user-global (a
  common install) still triggers it — the project need not carry its own
  `settings.json`. Missing/uncertain state (no key enabled at any scope, no jq)
  fails quiet — never advises toward a skill that is not enabled for the session.

## Telemetry (opt-in)

Every guard emits one structured [hook-telemetry](../../docs/conventions/hook-telemetry/README.md)
envelope per run to whatever `HOOK_TELEMETRY_SINK` names — carrying `status`
(`blocked` on a guard block, `ok` otherwise), `duration_ms`, and a privacy-safe
`data` payload (category **labels** only — never a secret value, matched path,
or full command). Unset `HOOK_TELEMETRY_SINK` → no-op; the guards behave exactly
as before.

## Requirements

- **bash 5.0+** and **jq** — the guards' runtime. Without **jq**, each guard
  fails **open** (disabled) and prints a one-line stderr notice — never a silent
  disable.
- On Windows, **Git Bash** (the hooks run via Git Bash's bash).
- `cli-flag-verify` runs `<bin> --help` for the binaries it scans; findings
  require those binaries on PATH (missing binaries are skipped, never flagged).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install guardrails@melodic-software
```

Then verify the runtime prerequisites and live guard surface with
`/guardrails:setup check`; `/guardrails:setup apply` resolves anything the
check reports with guidance.

## License

MIT (SPDX-License-Identifier: MIT).
