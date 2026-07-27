# Hook config delivery — channel decision matrix for plugin userConfig values

Owner doc for **how a plugin delivers a `userConfig` value into a hook's decision logic**. The
`hook-*` family divides the concern space: [hook-precision](../hook-precision/README.md) owns what a
hook matches, [hook-observability](../hook-observability/README.md) owns how it surfaces status, and
[hook-telemetry](../hook-telemetry/README.md) owns what it emits. This doc owns the remaining leg:
which **channel** carries a user-configured scalar from settings to the hook process, chosen by rule
instead of ad hoc.

The fleet previously shipped three coexisting approaches with no documented rule — a plugin-hook argv
substitution (silently broken for unset defaults), a skill-belt env read (skill hooks never receive
it), and a floated SessionStart-file design (unbuilt). Each was individually plausible; together they
were the reuse-or-replace fragmentation this doc closes.

## Boundary — composes with config-cascade

[config-cascade](../config-cascade/README.md) owns the layering of **consumer-tracked config files**
(`.claude/<name>` surfaces: which layers exist and how they merge). This doc owns the delivery path
of **harness-prompted `userConfig` values** — the options a plugin declares in `plugin.json` and
Claude Code prompts for at enable time. They are different inputs with different trust properties: a
cascade layer is repo- or user-authored file content; a `userConfig` value is harness-mediated and
stored in scopes a repo cannot write. Whether a given knob should be `userConfig` or a tracked
cascade surface is a design call owned by the [plugin philosophy](../../PLUGIN-PHILOSOPHY.md); once
it is `userConfig`, this doc owns its route to hook logic. Which keys exist and what they mean stay
with each plugin's own docs.

## Verified upstream behavior (version-pinned)

Everything below was verified on **Claude Code 2.1.218** — doc-stated facts re-fetched from the live
official docs on 2026-07-24; behavioral facts proven by a controlled fresh-session probe (isolated
`claude -p --plugin-dir` runs with positive controls) on 2026-07-23. Latest CC at recheck: 2.1.218.
Existing state is not evidence of its own correctness: **recheck these facts** (triggers at the end
of this doc) before extending the matrix or relying on a row in new work.

| # | Fact | Basis |
|---|---|---|
| 1 | Plugin `hooks.json` hooks receive `${user_config.KEY}` in **exec form only**, substituted into `command` and each `args` element as a plain string; a shell-form command referencing it fails with an error instead of running (since 2.1.207) | doc-stated ([hooks](https://code.claude.com/docs/en/hooks)) |
| 2 | Configured values are exported to hook processes as `CLAUDE_PLUGIN_OPTION_<KEY>` (key uppercased) | doc-stated ([plugins-reference](https://code.claude.com/docs/en/plugins-reference#user-configuration)); scope narrowed by fact 4 |
| 3 | The declared `default` field ("Value used when the user provides nothing") is in the schema but **implemented for neither argv substitution nor env export**. An unset-but-defaulted `${user_config.*}` argv token **silently drops the entire hook entry** — not passed literally, not empty-substituted; the same unset key exports **no** env var | proven (probe T1); upstream [#46477](https://github.com/anthropics/claude-code/issues/46477) closed not-planned, [#39455](https://github.com/anthropics/claude-code/issues/39455) open, [#39827](https://github.com/anthropics/claude-code/issues/39827) closed not-planned; undocumented |
| 4 | Tamper split on the env channel: for a **configured** key, harness injection overwrites a repo `.claude/settings.json` `env` block (injection wins); for an **unconfigured** key nothing is injected and the repo's `env` block freely populates `CLAUDE_PLUGIN_OPTION_<KEY>` — and env carries no provenance, so a hook cannot tell the two apart | proven (probe T2/T2b); undocumented |
| 5 | `pluginConfigs` is written to user settings and read back from **user settings, the `--settings` flag, and managed settings only**; entries in a project's `.claude/settings.json` / `.claude/settings.local.json` are ignored (since 2.1.207) | doc-stated ([plugins-reference](https://code.claude.com/docs/en/plugins-reference#user-configuration)) |
| 6 | Skill- and agent-frontmatter hooks receive **neither** the argv substitution nor `CLAUDE_PLUGIN_OPTION_*` | evidence-strong (probe + field repro); CC docs silent |
| 7 | Skill/agent **body** `${user_config.KEY}` substitutes into model-visible content, non-sensitive values only | doc-stated ([plugins-reference](https://code.claude.com/docs/en/plugins-reference#user-configuration)) |
| 8 | Sensitive values are stored in the OS keychain (or `~/.claude/.credentials.json`), never in `settings.json` | doc-stated ([plugins-reference](https://code.claude.com/docs/en/plugins-reference#user-configuration)) |

## The channels

An open list — channels known and characterized today. A newly discovered delivery path extends this
list and the matrix; it does not fork a private convention.

- **A. Exec-argv substitution** — `${user_config.KEY}` in an exec-form hook's `command`/`args`.
- **B. Environment** — the hook script reads `CLAUDE_PLUGIN_OPTION_<KEY>`.
- **C. SessionStart resolver → data file** — a SessionStart plugin hook resolves the value once and
  persists it under `${CLAUDE_PLUGIN_DATA}`; other surfaces (including skill-frontmatter hooks) read
  the file.
- **D. `required:true` + argv** — declare the key required so no unset case exists, then use argv.
  Premise unproven — see [Open gaps](#open-gaps).
- **E. Skill/agent body substitution** — `${user_config.KEY}` in model-visible skill/agent content.
  Reaches the model, never a hook process: advisory only.
- **F. Direct settings read** — the hook script reads `pluginConfigs["<name>@<marketplace>"].options`
  itself from the user `settings.json` plus fixed-path managed settings (and `managed-settings.d/`
  drop-ins), locating the user file **only** from the tamper-resistant `${CLAUDE_PLUGIN_ROOT}` cache
  anchor — tamper-resistant because the harness substitutes it from the plugin's install cache under
  the user's own config dir, a path no repo file can redirect — never from an env-derived path
  (`CLAUDE_CONFIG_DIR`, `HOME`, `%ProgramFiles%`), because a repo `env` block reaches hook
  subprocesses and env carries no provenance. Shipped exemplar:
  disk-hygiene's shared kill-switch reader, `plugins/disk-hygiene/lib/killswitch_config.py`
  (see its `[0.9.0]` [CHANGELOG entry](../../../plugins/disk-hygiene/CHANGELOG.md) for the full
  trust analysis and residuals).

## The matrix

| Channel | Reaches skill-hook? | Unset-default behavior | Repo-tamper-resistant | Failure mode | Sensitive-safe | Machinery |
|---|---|---|---|---|---|---|
| A. Exec argv | no | **BROKEN — whole hook silently dropped (fact 3)** | yes (user/managed scopes) | **unsafe: silent non-enforcement** | on argv | none |
| B. Env | no | **not delivered (fact 3)** → in-script default required | **only when configured; a repo `env` block owns the unset case (fact 4)** | safe | yes | none |
| C. SessionStart → data file | **yes** | inherits fact 3 at resolve → in-script default required | yes, if the resolver itself uses a tamper-resistant channel (not bare env — fact 4) | safe | yes (configured values, via the resolver's env) | +hook, +file trust, +session-start timing |
| D. `required:true` + argv | no | n/a — no unset case | yes | safe | on argv | none (premise unproven) |
| E. Body substitution | (model, not a hook) | n/a | yes | advisory only | **no** | none |
| F. Direct settings read | **yes** | in-script default required (declared `default` inert everywhere) | yes (fact 5 + no env-derived paths) | safe — explicit fail direction per plugin | **no — sensitive values are not in `settings.json` (fact 8)** | +settings-file coupling, +managed-path table |

Residual on F (documented, accepted): a value supplied only via a session `--settings` file is honored
by the harness but invisible to a hook-side read — a runtime CLI flag no hook can observe.

## The decision rule

1. **Skill- or agent-frontmatter hook needs the value** → only **C** or **F** deliver one (fact 6).
   Otherwise the value reaches the model only (**E**) and the control is advisory.
2. **Plugin hook, mandatory value (no sensible default)** → **D** once its premise is proven (see
   Open gaps); until then treat the key as optional-with-default and use the rows below.
3. **Plugin hook, optional-with-default, safety- or security-critical** → **F** (or **C** with an
   F-grade resolver). Never **B**: the unset-default case is exactly where a protect-by-default
   switch lives, and there a repo `env` block owns the value (fact 4). Never bare argv (fact 3).
4. **Plugin hook, optional-with-default, non-safety** → **B** with an in-script default — acceptable
   only where a repo supplying its own value for an unset key is tolerable or intended.
5. **Sensitive value** → **B** or **C**; never argv (visible in process listings), never **E**
   (model-visible), and **F** cannot read them at all (fact 8).

**Meta-rule — do not enshrine the outage as law.** The standing preference is *the most
tamper-resistant channel that reliably delivers*. Argv is the most tamper-resistant delivery there
is; it is excluded today only because fact 3 makes it unreliable for optional-with-default keys.
If upstream implements `default` substitution, rows A/B/D change and this rule is re-derived — that
is a recheck trigger, not a rewrite of history.

## Enforcement

Rule "never bare argv" is CI-enforced, not just documented: `scripts/check-hook-userconfig-argv.sh`
fails the build on any `${user_config.*}` token inside a plugin hook configuration (the default
`hooks/hooks.json`, manifest-pointed hook files, and inline manifest `hooks` objects alike). MCP and
LSP server configs are out of scope — substitution there is sanctioned and unaffected by fact 3.

The gate flags **every** hook-config use, including a would-be channel D, because D's premise is
unproven. A ratified D adoption (after the Open-gaps probe) is recorded in
`scripts/hook-userconfig-argv-allowlist.txt`; stale allowlist entries fail the gate.

## Open gaps

- **G-required (channel D's premise).** That `required:true` forces a prompt and so removes the
  unset case is inferred from the schema (`required` — "validation fails when the field is empty")
  and upstream discussion, not doc-stated and not yet probed: the verification probe declared
  optional keys only. Cheap to settle — add a `required:true` key to the probe plugin and rerun the
  unset-key test. Until then D stays in the matrix as unproven and the CI gate has no allowlist
  entries.

## Adopters

Conformance is tracked as it exists on `main`, per the
[convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) discipline.

| Surface | Channel | Status |
|---|---|---|
| disk-hygiene kill switch (`disk_hygiene_enabled`), both guard surfaces | F (shared reader `lib/killswitch_config.py`) | conforms (0.9.0, #1242; closed #1019) |
| claude-ops + format-hook plugins (`CLAUDE_PLUGIN_OPTION_*` reads via `hook-utils.sh`) | B | non-safety concerns; conformance audit tracked by #1182 |

Issue #1182 is the adoption/tracking pointer for the remaining fleet audit; this doc is the
authority it points to.

## Recheck triggers

Stamp-and-trigger discipline: [upstream-drift](../upstream-drift/README.md). Recheck the facts
table (and re-derive the decision rule) when any of these fires:

- A Claude Code CHANGELOG entry touches `userConfig` substitution, the `default` field, or
  `CLAUDE_PLUGIN_OPTION_*` injection — facts 1–4; rows A/B/D.
- [#46477](https://github.com/anthropics/claude-code/issues/46477) reopens or `default`
  substitution ships — fact 3; the meta-rule's exclusion of argv falls away.
- The documented `pluginConfigs` read scopes change — fact 5; F's tamper claim.
- The managed-settings paths or precedence change — F's exemplar reader.
- CC docs begin specifying skill-hook value delivery — fact 6 moves from evidence-strong to
  doc-stated (or is contradicted).
