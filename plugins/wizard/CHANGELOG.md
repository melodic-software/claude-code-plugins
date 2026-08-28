# Changelog

All notable changes to the `wizard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.1.0]

### Added

- **`generate` — author an interactive bash wizard for human-only steps**
  (`/wizard:generate`, model-invoked with an explicit non-trigger fence: never
  for steps the agent can perform itself). Ported from
  [mattpocock/skills](https://github.com/mattpocock/skills) v1.2.3
  (`main@84fdeff`, MIT) `wizard`, hardened; provenance SSOT:
  `docs/upstream/mattpocock-skills.md`. Hardening deltas over upstream:
  - **Human approval gate (stop-the-line):** the full `STAGES` block is printed
    to the user and explicitly approved BEFORE `chmod +x` or any run
    instruction — upstream verified and handed off without a human read gate.
  - **https-only `open_url`:** non-https URLs are refused with a visible
    warning, and the full URL prints before dispatch — also closes a Windows
    UNC/NTLM credential-leak path through the `explorer.exe` branch.
  - **TTY-only, fail-closed prompts:** all reads come from `/dev/tty` (fd 3),
    the script aborts with a clear message when no TTY exists, and a read
    failure in `pause`/`confirm`/`ask`/`ask_secret` is fatal — retiring a
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
    `ask`/`ask_secret`/`write_env`/`set_secret`/`set_var`/`_existing` — fail
    fast before a malformed name reaches the env file or a `gh` call.
  - **Readline on non-secret `ask` prompts** (`read -e`; kept off `ask_secret`)
    — fixes upstream issue #741's arrow-key breakage where safe.
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
    sidecar was not ported (no Codex target — SSOT precedent).
