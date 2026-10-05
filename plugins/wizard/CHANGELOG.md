# Changelog

All notable changes to the `wizard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.7] - 2026-10-04

### Fixed

- An env file that resolves into git metadata (`.env -> .git/config`, or a nested repository's
  `.git`) now gets the confirm-before-write prompt instead of counting as inside the project. A
  write there put the value in a world-readable file and let the repo pick a key name git reads as
  configuration. The prompt names the resolved path; a yes still writes.

## [0.6.6] - 2026-10-04

### Fixed

- `ask`, `ask_secret` and `write_env` refuse a key the shell already exports (`GH_TOKEN`,
  `BROWSER`, `GIT_SSH_COMMAND` and the like). Assigning it kept the export flag, so the wizard's
  value reached `gh`, `git` and the browser opener. The wizard stops with an error naming the key
  and leaves the shell's environment alone.

## [0.6.5] - 2026-10-04

### Fixed

- An env file reached through a symlinked parent directory (`ENV_FILE=sub/.env` with `sub` linked
  outside the project) now gets the same confirm-before-write prompt as a symlinked `.env`: the
  whole path is resolved before the inside-the-project check, not just its last component.
- `ask`, `ask_secret` and `write_env` refuse a key naming a variable the shell itself sets or reads
  (`PATH`, `IFS`, `HOME`, `PS4`, `BASH_ENV` and the rest of the bash manual's Shell Variables list),
  plus `LD_*` and `DYLD_*`, so a stage can no longer change how the rest of the wizard runs.

## [0.6.4] - 2026-10-04

### Fixed

- `write_env` now sets the shell variable it names, as `ask` and `ask_secret` do, so a stage can
  read back a value it wrote.
- `write_env` on a symlinked `.env` no longer replaces the link with a regular file holding the
  target's secrets. It writes through the link, so the target gets the key and keeps its mode.
  We chose this over resolving the link, which needs `realpath` (missing on older macOS) or a
  hand-rolled `readlink` loop, and whose rename would change the target's inode and mode. The cost
  is that a symlinked write is not atomic; a regular `.env` keeps the atomic rename from a `0600`
  temp file. A link whose target lies outside the project (a repo can ship `.env -> ~/.bashrc`)
  is followed with a portable `readlink` loop: the wizard prints the real destination and writes
  only after the human confirms, asking before any value is prompted for. The link is re-resolved
  on every call and a yes covers only that resolved target, so a link repointed mid-run asks
  again. A decline, or no terminal to answer, aborts with nothing written.
- A terminal without a `clear` capability (`TERM=dumb`, no terminfo) no longer stops every
  generated wizard silently before its first prompt: `tput` failures are non-fatal.
- `ask`, `ask_secret` and `write_env` now set a key named like one of their own locals (`key`,
  `value`, `input`, `tmp` and the rest) in the caller instead of in the helper. Their locals carry a
  `__wiz_` prefix, and a key naming library state (`ENV_FILE`, `SKIPPED`, `__wiz_*` and the rest)
  is refused, so `write_env ENV_FILE x` can no longer redirect later writes.

## [0.6.3] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.6.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.6.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.6.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5842](https://github.com/melodic-software/claude-code-plugins/issues/5842)).

## [0.5.1] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.5.0] - 2026-09-30

### Added

- **macOS Keychain and Linux `pass` rungs in `Resolve-UnattendedSecret`** ([#5315](https://github.com/melodic-software/claude-code-plugins/issues/5315)).
  The ladder is now environment, file, SecretManagement vault, the platform store (`security` on
  macOS, `pass` on Linux; skipped silently when the tool is absent, has no entry, or the name is a `pass` directory), then a hidden
  prompt. Tests cover each rung's presence, absence and precedence.

## [0.4.0] - 2026-09-29

### Added

- **`-Secrets` on `Invoke-UnattendedRun`** ([#5315](https://github.com/melodic-software/claude-code-plugins/issues/5315)).
  Declared secrets resolve once before the first stage, so the human answers every hidden prompt
  up front. An undeclared name still resolves at first use. The `cutover.result/1` envelope gains
  a names-only `secrets` field and dry-run `planned` gains a `secrets` count.
- **A credential-store rung in `Resolve-UnattendedSecret`**: environment, then file, then a
  `Microsoft.PowerShell.SecretManagement` vault (skipped silently when absent), then a hidden
  prompt. Only a string secret is used; a `PSCredential`, hashtable or `byte[]` secret is skipped
  with a warning. Declaring a name twice in `-Secrets` fails the run. A native macOS Keychain and
  `pass` rung are not yet supported.

## [0.3.0] - 2026-09-29

### Added

- **`Wait-ForState`** and **`Use-GuardedResource -TolerateTakeExit`** in the `/wizard:unattended`
  library ([#4199](https://github.com/melodic-software/claude-code-plugins/issues/4199)). Poll the
  outcome of a request instead of trusting its exit code: a request that exits nonzero while the
  state is reached becomes a warning, and the proof that follows is the only gate.
- **`-Irreversible` on `Invoke-UnattendedRun`**, an `irreversible_actions` field in the
  `cutover.result/1` envelope (schema string unchanged), and a `Confirm-Irreversible` that refuses
  an undeclared step or any step while a guarded resource is still held.
- **`Assert-ParsedState`** and **`Invoke-NativeUtf8`**: an empty parse is a stop, not "already
  absent", and `wsl.exe` output is read as UTF-8.
- **`-WhatIf` and `-Test` dry-run modes** on the unattended template. `-WhatIf` narrates the plan and
  its blast radius; `-Test` writes only the result directory, whose JSON gains `mode`, `planned`
  and `delta`.

### Changed

- `Use-GuardedResource` requires `-Prove` to emit a truthy last value or throw. A false result, no
  output or a nonzero native exit keeps the resource held instead of releasing it.
- `/wizard:unattended` documents its PowerShell 7 requirement in the hand-off and the README, and
  `Assert-NotInside` is documented as a `WSL_DISTRO_NAME` check only.

## [0.2.11] - 2026-09-28

### Added

- **`/wizard:unattended`** ([#4199](https://github.com/melodic-software/claude-code-plugins/issues/4199)).
  A sibling of `generate` for work that is fully scriptable and not agent-launchable. The agent
  authors a PowerShell script onto a fixed library and does not run it. The human launches it
  once. The library checks elevation in both directions, refuses to run inside the thing it
  restarts, resolves secrets from the environment, a file, then one prompt, records an idempotent
  step, fails closed on a prior script's result, preflights with a fix command, and releases a
  shared resource only after proof. The run writes `cutover.result/1` JSON and redacts secrets
  from the transcript.

## [0.2.10] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.2.9]

### Changed

- The wizard template shares one prompt line and one gh set helper between its ask and set functions, the testing cant-fail scanner folds its readability guards, config dedupe, and C# body-start detection into helpers, its suite gains run and count helpers, and the songwriting datamuse comments are trimmed, with byte-identical output.

## [0.2.8]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** This changelog was rewritten. Wording only, with no change to any generated-script shape, dispatch rule, or upstream reference. No heading was touched. The released sections corrected in place are 0.2.0 and 0.1.0: their wording changed, their facts did not.
- **`seam` stays in the 0.2.5 entry, because the sentence defines it.** It names the single `exec 3</dev/tty` open that `skills/generate/template.test.sh` pins and rewrites, which is a testing seam in the Feathers sense rather than a reflexive metaphor.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md` alongside the README and SKILL bodies it already covered.

## [0.2.7]

### Changed

- **`generate`:** add `argument-hint: "<procedure to wizardize>"` so autocomplete
  shows that the skill takes free-text procedure input (#3542).

## [0.2.6]

### Changed

- **`generate`: explicit `user-invocable: true`.** The documented default, now declared for
  fleet-wide explicit-key consistency; no behavior change.

## [0.2.5]

### Added

- **`template.sh` gets a contract suite.** `plugins/wizard/skills/generate/template.test.sh`, 144
  assertions over the hardened wizard library: fail-closed prompts at EOF, the `_drain_tty` paste
  defense (with a control case proving the fixture really does carry a bypass payload), key-name
  validation, `.env` upsert and quote round-tripping through a real shell read, owner-only file
  mode, the once-only gitignore warning, https-only `open_url`, `gh` secret and variable values
  traveling over stdin and never argv, resolve-the-repo-once, every `gh` degradation path, the
  names-only closing summary, and the `_cleanup` if-form that keeps a clean run exiting 0 under
  `set -e`. The template is a runnable wizard, so each case extracts the library half above the
  `STAGES` marker and rewrites its one `exec 3</dev/tty` to a fixture file; the suite pins that
  marker and that single `/dev/tty` open so the seam cannot drift off the shipped code path, and
  proves the no-TTY guard on the unmodified file. Closes the gap where the file mapped to no test
  suite at all under `scripts/affected-tests.sh`, which the repo treats as an error rather than as
  nothing to run.

## [0.2.4]

### Changed

- **Authoring-doctrine pass over `README.md`.** Fixed sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.2.3]

### Changed

- **The hardened-template guarantees are a list.** 99 words and eight clause interrupters, already
  punctuated as a list with semicolons. Docs-hygiene sweep, L8-write-for-humans.

## [0.2.2]

### Changed

- **Instruction-surface de-slop (#2891, wizard cluster).** Rewrote this plugin's `README.md`
  and every `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. YAML frontmatter description/summary left unchanged so
  the cheatsheet stays valid. No generated options block.

## [0.2.1]

### Added

- **`generate`: first eval suite (#2968).** Five cases pinning repo-first scoping, the names-only
  read of a live `.env`, the human-approval gate before `chmod +x`, the off-limits library above the
  `STAGES` marker, and `gh` absence degrading rather than failing. Required because the skill gate
  demands evals for any skill whose SKILL.md changes.

### Changed

- **Explicit `disable-model-invocation` on `generate` (#2968).** The skill now states the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.2.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.1.0]

### Added

- **`generate`: author an interactive bash wizard for human-only steps**
  (`/wizard:generate`, model-invoked with an explicit non-trigger fence: never
  for steps the agent can perform itself). Ported from
  [mattpocock/skills](https://github.com/mattpocock/skills) v1.2.3
  (`main@84fdeff`, MIT) `wizard`, hardened; provenance SSOT:
  `docs/upstream/mattpocock-skills.md`. Hardening deltas over upstream:
  - **Human approval gate (stop-the-line):** the full `STAGES` block is printed
    to the user and explicitly approved BEFORE `chmod +x` or any run
    instruction. Upstream verified and handed off without a human read gate.
  - **https-only `open_url`:** non-https URLs are refused with a visible
    warning, and the full URL prints before dispatch. This also closes a
    Windows UNC/NTLM credential-leak path through the `explorer.exe` branch.
  - **TTY-only, fail-closed prompts:** all reads come from `/dev/tty` (fd 3),
    the script aborts with a clear message when no TTY exists, and a read
    failure in `pause`/`confirm`/`ask`/`ask_secret` is fatal. That retires a
    verified multi-line-paste bypass of the confirmation gates and `pause`'s
    fail-open at EOF (upstream `read || true`).
  - **Hardened `.env` writes:** values stored single-quoted with embedded
    quotes escaped; `chmod 600` after every write; a loud warning plus summary
    entry when `ENV_FILE` is not gitignored in a git repo; the mktemp rewrite
    staged alongside `ENV_FILE` (same-filesystem atomic rename) with trap-based
    cleanup; `_existing` strips one matched pair of surrounding quotes when
    offering re-run defaults.
  - **Hardened `gh` writes:** the target repo is resolved once via
    `gh repo view --json nameWithOwner`, echoed, and confirmed before the first
    CI write; every `gh` call passes explicit `--repo`; `set_var` pipes its
    value via `--body-file -` (stdin, never argv); empty values are refused
    (warn + summary, `gh` never called); `gh` stderr surfaces into the closing
    summary instead of `>/dev/null`.
  - **Key-name validation** (`^[A-Za-z_][A-Za-z0-9_]*$`) at the top of
    `ask`/`ask_secret`/`write_env`/`set_secret`/`set_var`/`_existing`, failing
    fast before a malformed name reaches the env file or a `gh` call.
  - **Readline on non-secret `ask` prompts** (`read -e`; kept off
    `ask_secret`), fixing upstream issue #741's arrow-key breakage where safe.
  - **Names-only live-`.env` scoping:** the authoring step reads key names only
    from a live `.env` (`grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' .env`), never
    values, and the skill states the secrets-and-context property honestly
    (runtime capture never reaches the model; a value pasted into chat is in
    context).
  - **Fresh-context static trace:** the verify step delegates the value-flow
    trace to a fresh-context subagent per the marketplace's fresh-eyes rules;
    `bash -n`/`shellcheck` stay deterministic gates.
  - Kept from upstream: stage-by-stage UX with screen clears, hidden secret
    entry, idempotent upserts with re-run defaults, `gh`-absence graceful
    degradation (warn + SKIPPED, optional-feature class), names-only closing
    summary, ephemeral-by-default doctrine. The Codex `agents/openai.yaml`
    sidecar was not ported (no Codex target, per SSOT precedent).
