# guardrails

A Claude Code plugin bundling twelve **safety guards** that catch risky agent
actions the moment they happen — before a write lands or a bash command runs.
Each guard is independently toggleable, so you run exactly the subset you want.

## The guards

| Guard | Event / matcher | Behavior | What it catches |
|-------|-----------------|----------|-----------------|
| **secret-pattern-detection** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | High-confidence secret/credential patterns (AWS/GitHub/GitLab/Slack/Stripe/OpenAI keys, PEM private keys) in new file content. |
| **hardcoded-path-check** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | Hardcoded machine-specific paths — Windows drive-letter homes, macOS/Linux user homes, machine-specific repo checkout roots. |
| **block-no-verify** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and hook-manager disable env vars — a configurable prefix set defaulting to `lefthook`, `husky`, `pre_commit`, `simple_git_hooks` (e.g. `LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`), tunable via `block_no_verify_hook_manager_prefixes`, including inside compound `cd … && …` commands. |
| **block-dangerous-git** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Irreversible git operations: `push --force`/`-f` plus the equivalent leading-`+` refspec and `--mirror` forms, and the unsafe `--force-with-lease` spellings, in the two kinds git itself treats differently. **No expected value** (bare `--force-with-lease` or `=<refname>`) leases against the remote-tracking ref, which git documents as "trivially defeated" by a background fetch — blocked unless `--force-if-includes` is present, which git documents as the mitigation for exactly this form. **A movable `=<refname>:<expect>`** — `origin/main`, `HEAD`, a tag, an *abbreviated* object id, or hex of the wrong width for this repository's hash format, all of which git resolves at push time, and gitrevisions resolves a short hex word as a ref before trying it as an object-id prefix — is blocked unconditionally, because git declares `--force-if-includes` a no-op alongside an explicit `:<expect>`. A lease passes only when `<expect>` is immutable: a **literal** object id of the pushed repository's own hash width (detection never evaluates substitutions, so resolve it with `git rev-parse` as a separate step and pass the result) (40 hex under SHA-1, 64 under SHA-256, read from `git rev-parse --show-object-format` with the command's own `-C`/`--git-dir`/`--work-tree`/`--namespace` replayed onto it; undeterminable fails closed) or the empty string asserting the ref must not exist. The other width is a ref name there, not an object id — git ignores a ref whose name is full-width hex for its own format, but resolves one of the other width like any name. git scopes a pin to its own ref, so a bare fallback alongside a pinned entry still governs every other ref being updated; where the same ref carries several lease entries, git consults the first, and so does this guard. A trailing `--no-force-with-lease` cancels every previous lease, and a push dry-run disarms the check. Also blocked: `reset --hard`, `clean` with a force flag (any dry-run flag disarms), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, `:(top…)` — path-scoped forms and `restore --staged .` pass), and forced `checkout -f` / `switch --discard-changes`. Accepted unique-prefix abbreviations of the blocked long options match too. `branch -D` is deliberately not blocked (reflog-recoverable; sanctioned skill flows issue it). Per-repo/per-user allow-list via the `block_dangerous_git_allow` userConfig option (comma list, any subset of `push-force,push-lease-unsafe,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force`). |
| **block-hook-bypass** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Bash file-write workarounds that circumvent the Write/Edit hook gates — `cat > file`, `echo … > file`, and inline python code with file-write indicators (`python`/`python3`/`py`/`pypy`, with `-c` or reading the program from stdin as `python3 - <<PY`). Executable-token detection ignores quoted prose/commit text that merely mentions the pattern. |
| **cli-flag-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | Hallucinated CLI flags — a `--flag` written as a command that does not exist in the binary's actual `--help` output. Surfaces via `additionalContext`, never blocks. |
| **workflow-resilience-check** | PreToolUse · Workflow | **Advisory** (exit 0) | Un-throttled Workflow fan-out — a script calling `parallel()` / `pipeline()` with no wave-cap throttle (`inWaves` / `inWavesPipeline`) and no retry wrapper (`agentRetry`), which risks a burst 529 under wide Opus fan-out. Surfaces a resilience checklist via `additionalContext`, never blocks. **Opt-in — default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `workflow_resilience_check_enabled=true` to enable). |
| **block-noncanonical-commit** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | `git commit -m` whose message actually contains a newline — a multi-line `-m` flattens newlines unpredictably across shells; pipe it via `-F -` / `--file -` instead (narrowed in 0.20.0 per #2021: single-line `-m`, bare `git commit`, and repeated single-line `-m` paragraphs all pass). On the PowerShell tool a here-string `-m` value blocks too — its content is uninspectable and multi-line by construction of the form. Exempt: `--amend`, `-C`/`-c`/`--reuse-message`/`--reedit-message`, `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge/rebase/cherry-pick/revert is in progress. Resolves `bash -lc` wrappers and git aliases (inline `-c` and persisted config alike). |
| **block-convention-violation** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A commit subject or `gh pr create --title` that violates the team-tracked convention pattern declared in `.claude/source-control.md`. No tracked pattern means no enforcement. Same exemptions as `block-noncanonical-commit`. |
| **flag-commit-pr-skill-bypass** | PreToolUse · Bash \| PowerShell | **Advisory** (exit 0) | Any `gh pr create`, bypassing this marketplace's own `/source-control:pull-request create` skill. Only fires when the consuming project's own `.claude/settings.json` enables the `source-control` plugin — silent otherwise. Surfaces via `additionalContext`, never blocks. **Opt-in — default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `flag_commit_pr_skill_bypass_enabled=true` to enable). |
| **skill-reference-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | A `` `/plugin:skill` `` reference in markdown that does not resolve. Only fires inside a marketplace repo, and only for a plugin that repo's own manifests own — a reference to another marketplace is left alone. Resolves through manifest and frontmatter `name`, so a renamed directory still matches. Surfaces via `additionalContext`, never blocks. |
| **stale-path-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | A repo-relative path cited in a markdown inline code span that this repo's own history shows was **deleted** and that is gone from the working tree. The gate is provenance, not absence: the exact path must appear in `git log HEAD --no-renames --diff-filter=D --name-only`, so a path belonging to a consuming project's tree, an example, or a plan is never adjudicated. Names the surviving file when exactly one tracked path now carries that basename. Link destinations are out of scope. Surfaces via `additionalContext`, never blocks. |

The seven blocking guards feed their stderr message back to Claude as
actionable fix guidance. The five advisory guards surface their findings the same
way but always allow the operation.

### Enforceability tiers

Ten guards are **deterministic** — their oracle is a mechanical test with no
judgment step. Two are **detect-then-judge**, where the oracle is mechanical but
the conclusion is a human verdict, never an auto-fix: `skill-reference-verify`,
because globbing a plugins tree is exact only inside a marketplace repo that owns
the referenced plugin; and `stale-path-verify`, because a path may be cited
deliberately as a deletion or completion record and be correct exactly as
written. `cli-flag-verify` is deterministic in its oracle but advisory in its
action, because a written claim can be deliberately forward-looking.

`stale-path-verify` detects **staleness, not hallucination**. An invented path was
never in the repository, so it never enters the deleted-path set and the guard
stays silent by construction. Separating a hallucinated path from a correctly
documented consumer-tree path needs a signal a repo-root oracle does not have —
both are absent locally and conventionally shaped — so that class is deliberately
out of scope until such a signal exists.

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
- **`block-dangerous-git` scope boundaries (not bypasses).** Three cases are
  often filed together; only one is a live bypass (#2151 item A — inherited
  `--git-dir`/`--work-tree` in a `!` alias body). The other two are
  **documented limits** of static argv matching:
  - **Shell `cd` relocation** — `cd <other-repo> && git push …` runs the
    push from a directory no `-C`/`--git-dir` names. Evaluating it requires
    arbitrary shell word expansion, which this guard deliberately does not
    do.
  - **False block from a non-repository base** — when the session root is
    not itself a repository, a shell `cd` into a repo and a pinned
    `--force-with-lease` can be blocked because the width probe cannot
    resolve a repository at the guard's computed base. That is fail-closed
    scope, not a bypass.
- **A NUL byte in the payload blocks, whatever the command says.**
  `block-no-verify` and `block-dangerous-git` refuse any payload whose read
  fields carry a NUL, before they look at the command at all — including one
  that leaves no command text behind. The reason is that the text a guard can
  read is not dependably the text that would run: two behaviours were measured
  and they disagree — bash **discards** a NUL while parsing a command it reads,
  and Node's `child_process` **refuses** a NUL-bearing string outright — and
  which of them, if either, a hook payload reaches has not been traced. Refusing
  is the one verdict correct under all of them, and needs no such trace. A NUL is
  treated as malformed input rather than as an exotic-but-valid command.
- **`block-hook-bypass` string-matching floor.** Detection strips quoted literal
  spans before matching the executable token, so quoted prose or a commit
  message merely mentioning `cat >` / `python3 -c open(...)` is not flagged. The
  accepted residual: a write inside a command substitution in double quotes
  (`echo "$(python3 -c 'import pathlib …')"`) is **not** caught — the strip
  treats the quoted span as inert. Same friction-guard, not-a-sandbox posture as
  `block-no-verify`.
- **`block-hook-bypass` inspects one command string, and only the write forms
  listed above.** It reads `.tool_input.command`; it does not read the contents
  of a script that command invokes, so `bash build.sh` runs whatever writes
  `build.sh` performs. It is also producer-scoped by design, so a redirect whose
  producer is another program (`sort f > out`, `curl … > page.html`, `cat a b >
  c`) is allowed — only a content producer writing a real file
  (`cat > f` consuming stdin, `echo`/`printf > f`, inline python writes,
  the PowerShell write cmdlets, including `Tee-Object` and its `tee` alias on the
  PowerShell tool) is blocked. The python lane matches the interpreter FAMILY
  (`py`, `python`, `pypy`, with an optional version suffix — `py -c`, `python -c`,
  `python3.11 -c` are the same write as `python3 -c`), and since **0.28.0** it also
  covers a program read from stdin with an explicit `-` (`python3 - <<PY … PY`);
  `python3 <<PY` with **no** `-` is an accepted residual, because matching a bare
  trailing interpreter token would block `cat script.py | python3`. On the **Bash**
  tool, **`tee` / `tee -a` and inline writes via other interpreters (`node -e`,
  `perl -e`, `ruby -e`, `sed -i`, `dd of=`, `awk >`, …) are accepted residuals** —
  outside the modeled surface, not oversights. The block message carries a lane-specific scope note so a reader does
  not credit the guard with coverage it never claimed.
- **`block-hook-bypass` has one target-scoped exemption beyond `/dev/null`, and
  it is off unless an operator turns it on.** `block_hook_bypass_scratch_roots`
  takes a comma-separated list of absolute directories whose contents are
  scratch — a session or job temp root, where a throwaway probe file is written
  that no formatter, secret scanner or path check would ever process. Empty is
  the default and exempts nothing. When set, the match is made on the
  **effective** stdout target (the last redirect wins, as with `/dev/null`) after
  lexical normalization, and containment is decided at a path-component
  boundary: `/tmp/scratchevil/f` is not under `/tmp/scratch`, a `..` escape is
  resolved away before the compare, `echo x > /tmp/scratch/f > real.txt` still
  blocks, and a relative, unexpanded (`$VAR`, `~`) or glob target is never
  exempt. A **quoted or escaped** operand is never exempt either, and that one
  fails closed rather than being documented: the quote strip drops a kept
  target's quotes, and the segment split would then read a `;`, `|`, `&` or space
  *inside* the operand as syntax, so `> "/tmp/scratch/a;/../../etc/passwd"` —
  one pathname to bash — would be judged on `/tmp/scratch/a`. Since **0.27.0**
  the operand is **marked** wherever that would happen, so it reaches the compare
  as one word and the decision is made on the whole thing: an operand carrying
  whitespace, `;`, `|`, `&`, `(`, `)`, a newline or a backslash escape exempts
  nothing, and a merely quoted operand is refused by this axis on its shipped
  floor. **Quotes and backslashes elsewhere in the command no longer matter.**
  Before 0.27.0 this test read the whole raw command tail after the first `>`
  *character*, so a quote in an unrelated later segment, or a `>` inside quoted
  content, cancelled the exemption for an earlier plain write. Both were friction
  rather than protection and both are gone — `echo x > /tmp/scratch/f && grep foo
  "notes.txt"` and `echo "a > b" > /tmp/scratch/f` are exempt again. The same
  truncation reached the `/dev/null` discard and predated this option (#2226);
  the same marking closes it, so a quoted `/dev/null` operand carrying a second
  fragment now **blocks** where it was allowed. Two residuals remain, both
  deliberate and both pinned: normalization is lexical, so symlinks out of a
  root are not followed, and the compare is case-insensitive because the segment
  scan runs over the lowercased command. Naming a root is accepting that root's
  contents.
- **`flag-commit-pr-skill-bypass` is a nudge, not a gate.** Detection is a
  literal-stripped top-level regex match, not a full argv-grammar parser — it
  does not evaluate shell variable / command substitution, and a determined
  author can construct a form that evades it. It cannot tell "the skill ran
  this exact command" from "someone hand-typed the same shape", and for
  `gh pr create` there is no command-shape signature at all, so every direct
  call is flagged. It stays advisory and cannot become otherwise:
  `/source-control:pull-request create` issues that exact command itself, so blocking it would
  deadlock the skill being advertised. `create.md` also documents a legitimate
  inline fallback when skill discovery is broken.

- **`block-noncanonical-commit` gates shape, not skill invocation.** No hook can
  see which skill (if any) originated a Bash call, so "did you run `/source-control:commit`" is
  not an available condition — and shape is the better target regardless, since
  it enforces an outcome verifiable in `git log`. It deliberately does not
  require `--trailer`: `/source-control:commit` omits the trailer under a resolved
  `trailer_policy` of `none`, so demanding it would block the skill's own
  conformant output in repos whose convention forbids co-author trailers.

## Per-hook kill switches

Each guard is toggled by its own `userConfig` boolean (default **on**, except
the two behavioral-class advisories `workflow-resilience-check` and
`flag-commit-pr-skill-bypass`, default **off** since 0.20.0 per #2021 — set to
`true` to opt in; set any switch to `false` for a clean no-op). This per-hook
control is the bundle's core contract — disable one guard without touching the
others.

| Guard | Option |
| ----- | ------ |
| secret-pattern-detection | `secret_pattern_detection_enabled` |
| hardcoded-path-check | `hardcoded_path_check_enabled` |
| block-no-verify | `block_no_verify_enabled` |
| block-dangerous-git | `block_dangerous_git_enabled` |
| block-hook-bypass | `block_hook_bypass_enabled` |
| block-noncanonical-commit | `block_noncanonical_commit_enabled` |
| block-convention-violation | `block_convention_gate_enabled` |
| cli-flag-verify | `cli_flag_verify_enabled` |
| skill-reference-verify | `skill_reference_verify_enabled` |
| stale-path-verify | `stale_path_verify_enabled` |
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

One further option tunes the hooks' shared plumbing rather than a single guard:

- **`stdin_read_timeout`** (number, default `2`, minimum `1`) — idle bound in
  seconds on reading the hook payload from stdin. Any byte arriving resets it,
  so a large or slowly-delivered payload is never cut off while it is still
  coming; it fires only once the pipe has gone silent for that long, at which
  point a blocking guard fails **closed** (`exit 2` with a `BLOCKED:` reason)
  rather than letting an unscanned tool call through. On a shell whose `read -t`
  accepts fractional values the bound is read in four slices, so a stall is
  declared within a quarter of the configured interval of it — that quarter is
  the limit of the approximation, and it errs toward waiting rather than toward
  calling a live producer dead. Where fractional timeouts are unavailable (Bash
  3.2, the macOS system shell) the bound is read as one window instead, and a
  producer that sends bytes and then goes silent can take up to **two** intervals
  to be declared stalled. A value this shell's
  `read -t` will not accept — or `0`, which would make the read consume nothing
  — falls back to the default rather than disabling the guards. You should not
  need to change it.

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
  (`claude gh dotnet docker kubectl terraform az aws`); override with the
  `cli_flag_verify_bins` option (`bin1,bin2,…`) and skip specific binaries
  with `cli_flag_verify_skip_bins`. `npm` is **excluded by default**, alongside
  `git` and `npx`: every npm config key is a flag on every subcommand
  (`npm <command> --key=value`), so per-subcommand `--help` is non-exhaustive by
  design and the authoritative list (`npm config ls -l`) prints `prefix = "…"`
  rather than `--prefix` — a generic `--help` parser cannot consume it, and
  verifying against one produces false "unknown flag" findings. Re-add it with
  `cli_flag_verify_bins` if your project wants it checked anyway.
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

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `secret_pattern_detection_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED` | Block writes containing high-confidence secret/credential patterns |
| `hardcoded_path_check_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED` | Block writes containing hardcoded machine-specific paths |
| `block_no_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED` | Block git hook-bypass attempts (--no-verify, core.hooksPath=, hook-manager env-var disables for a configurable set — lefthook/husky/pre-commit/simple-git-hooks by default) |
| `block_dangerous_git_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED` | Block irreversible git operations (push --force, push --force-with-lease leasing against a value git resolves at push time — either no expected value, or an expectation that is not an object id of the repository's own hash width — reset --hard, clean -f, worktree-wide checkout/restore discards) |
| `block_hook_bypass_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED` | Block Bash file-write workarounds that circumvent Write/Edit hook gates |
| `block_noncanonical_commit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED` | Block `git commit -m` when the message actually contains a newline (multi-line `-m` mangles across shells — pipe it via `-F -` instead; single-line `-m` passes); --amend, -C/-c, --fixup/--squash, -F <path>, and an in-progress merge/rebase are exempt |
| `block_convention_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED` | Block a commit subject or `gh pr create --title` that violates the team-tracked convention pattern in .claude/source-control.md (no tracked pattern = no enforcement; same exemptions as block-noncanonical-commit) |
| `cli_flag_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_ENABLED` | Advise on hallucinated CLI flags written to files (never blocks) |
| `skill_reference_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED` | Advise when markdown cites a /plugin:skill reference this repo owns but cannot resolve (never blocks) |
| `stale_path_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED` | Advise when markdown cites a repo-relative path this repo's own history shows was removed and that is gone from the working tree (never blocks) |
| `workflow_resilience_check_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED` | Advise on un-throttled Workflow fan-out (never blocks). Default off since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021) — set true to opt back in |
| `flag_commit_pr_skill_bypass_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED` | Advise when a direct gh pr create bypasses the source-control pull-request skill (never blocks). Default off since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021) — set true to opt back in |
| `cli_flag_verify_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` | Comma-separated binaries cli-flag-verify scans; empty uses the built-in default set |
| `cli_flag_verify_skip_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS` | Comma-separated binaries cli-flag-verify must never scan |
| `block_dangerous_git_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW` | Comma-separated forms block-dangerous-git permits: push-force, push-lease-unsafe, reset-hard, clean-force, checkout-dot, restore-dot, checkout-force; empty blocks all |
| `block_noncanonical_commit_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW` | Comma-separated form tokens to allow (currently: message-flag, which permits `-m` even when the message contains a newline) |
| `block_no_verify_hook_manager_prefixes` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES` | Comma-separated hook-manager env-var name prefixes block-no-verify treats as a bypass when set to 0/false (e.g. lefthook,husky); empty uses the built-in default set (lefthook, husky, pre_commit, simple_git_hooks) |
| `block_hook_bypass_scratch_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS` | Comma-separated ABSOLUTE directories block-hook-bypass exempts as scratch/temp write targets (e.g. /tmp/scratch,/d/jobtmp/session); empty (the default) exempts nothing and leaves the guard's shipped behaviour unchanged. Matching is on the effective stdout target after lexical normalization, at a path-component boundary — a sibling merely sharing the name prefix, a `..` escape out of a root, and a discard-then-real-file redirect all still block. A quoted or escaped OPERAND is never exempt: the operand is marked so it survives the quote strip and the segment split as one word, and an operand carrying whitespace, `;`, `\|`, `&`, `(`, `)`, a newline or a backslash escape exempts nothing. Quotes elsewhere in the command no longer matter. Symlinks are not followed |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin — how long a silent pipe is tolerated before a blocking guard fails closed |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure guardrails`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install guardrails@<marketplace> --config secret_pattern_detection_enabled=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "guardrails@<marketplace>": {
         "options": {
           "secret_pattern_detection_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
