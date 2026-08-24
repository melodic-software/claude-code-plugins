# skill-quality

A Claude Code plugin for **skill-authoring QA**: it runs a static, deterministic contract gate over a
skill directory, reports the shared listing-budget estimate across a set of skills, and validates a
skill's `evals.json` against a bundled schema plus a deterministic eval-quality lint. No model
invocation anywhere. The same checks run identically in a session, a pre-commit hook, or CI.

The one failure static analysis catches best is a rewrite silently dropping a `description` trigger
phrase, which quietly degrades a skill's auto-invocation. Check 3 compares the trigger phrases against
`HEAD` and fails on a regression.

| Skill | What it does |
|---|---|
| `/skill-quality:check` | Runs the contract gate (`check`), reports the shared listing budget (`listing-budget`), or schema-validates and quality-lints evals (`validate-evals`) for one skill, a set of roots, or every skill. |
| `/skill-quality:setup` | `check` (default) resolves and verifies the skills directory; `apply` routes a non-default `skills_root` change through Claude Code. |

## Checks

`check` runs `check-skill.sh`. Twenty-five checks, reported as `FAIL:` (blocking) or `WARN:` (advisory):

- Frontmatter parses; `description` present; a declared `name` is kebab-case and matches the skill
  directory (in a plugin skill it also WARNs as redundant, because the field defaults to the directory).
- `description` + `when_to_use` within the 1536-char **per-skill** listing-entry cap (overflow
  truncates that entry). A different, narrower limit from the shared budget below.
- Trigger-keyword preservation vs `HEAD` (skipped for a new, uncommitted skill).
- `SKILL.md` under 500 lines (hard) / 200 lines (soft, advisory).
- Backtick- and link-cited skill-internal supporting files resolve. When a path that misses instead
  resolves under a sibling skill, the finding names that sibling and the
  `${CLAUDE_PLUGIN_ROOT}/skills/<sibling>/...` cross-skill form, while keeping the hand-verify
  caveat (the sibling hit is evidence, not proof: paths can collide).
- `markdownlint-cli2` clean (advisory-skips when `npx` is absent).
- `scripts/*.test.sh` pass where present.
- Vendored `vendor/` byte-identical vs `HEAD`; stale-tracking metadata keys preserved; sync age.
- Gotchas surface present; `description` carries `Use when` phrasing; no committed cache artifacts;
  action-router skills without evals WARN (FAIL with `--require-evals` for any shape unless a recorded skip exists in `scripts/evals-warrant-exemptions.txt`); companion spoke
  dirs are referenced.
- Precompute opportunity (advisory). A fenced shell block gathers read-only context the skill could
  inline at load time via [`!` injection](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  instead of a per-invocation tool call.
- `!`-injection portability. Bash-only syntax without a `shell:` declaration fails; portable-looking
  but undeclared warns; an injected command with no `|| <fallback>` continuation warns.
- Fresh-eyes declaration conformance. Same-context judgment language (a curated, advisory heuristic)
  expects fresh-context delegation wording or a `fresh-eyes-exempt` directive nearby; malformed or
  reason-less directives fail. Contract: `skills/check/reference/fresh-eyes-declarations.md`.
- `metadata.summary` within 100 Unicode codepoints. The key is the generated skill cheat
  sheet's row source; the cap keeps rows scannable. An absent key is no finding.
- Completion-criteria signal (advisory). A numbered procedure of three or more steps with
  no observable done-condition token.
- Explicit invocation mode. Marketplace plugin skills must state
  `disable-model-invocation`; elsewhere a missing key warns.
- Description/verb-contract polarity (advisory). The description lead contradicts the
  Naming verb contract or the body (read-only vs mutate). `--fix` in the listing is the
  compliant override shape.

`listing-budget` runs `check-listing-budget.sh`. An always-advisory report on the **shared** budget
every loaded skill draws from together (`skillListingBudgetFraction`, default 1% of the model's context
window). This is the aggregate limit `check`'s per-skill cap above does not cover: nothing else in the
gate checks it, so a marketplace's skill count can silently overflow the live listing with no local
signal. It never asserts a live value it cannot observe (the model's context window and a consumer's
settings are both unknowable statically). It reports against a documented, overridable default and
always exits 0.

Only **listing-eligible** skills are counted: `disable-model-invocation: true` keeps a skill's
description out of the model-visible listing entirely, so it spends none of the shared budget. A
consumer's `skillOverrides` can free further descriptions with `"name-only"`, which repository
content cannot reveal, so the reported figure is an upper bound for anyone who sets it.

```shell
/skill-quality:check my-skill                  # gate one skill
/skill-quality:check                           # gate every skill under the resolved root
/skill-quality:check validate-evals my-skill   # schema-check + quality-lint evals.json
/skill-quality:check listing-budget            # report the shared budget over the resolved root
/skill-quality:check listing-budget plugins/*/skills  # pool every plugin's root into one aggregate
```

## Skills directory is never baked in

The checker resolves the skills root through the convention-resolution ladder, first hit wins:

1. `${user_config.skills_root}`. Set only when your skills live outside `.claude/skills`.
2. `${CLAUDE_PROJECT_DIR}/.claude/skills`. The conventional default.

`CHECK_SKILL_SKILLS_ROOT` is honored as a one-run environment override the checker reads directly;
the setup skill neither writes nor persists it. When your skills live at the default location, no
configuration is needed:

```shell
/skill-quality:setup         # check (default): resolve + verify the skills directory (re-runnable)
/skill-quality:setup apply   # route a non-default skills_root change through Claude Code
```

## Evals schema + quality lint

`validate-evals` checks a skill's `evals/evals.json` against the bundled
`reference/evals.schema.json`. Every case requires `id`, `prompt`, and at least one non-empty
grading criterion: `expected_output`, `expectations`, or `assertions` (a case that cannot be
graded is not an eval); the rich form adds `name` (kebab-case) and `files`.
Evals are warranted, not mandatory. A skill shipping none is not a failure.

After the schema, `check-evals-quality.sh` (bash + jq) lints eval CONTENT deterministically.
`FAIL:` tier: duplicate case ids/names, empty criterion items, `files` fixture entries that
resolve to no path under the skill or evals directory. `WARN:` tier (advisory, exit 0): a case
carrying both `expectations` and `assertions`, identical prompt+files pairs, vague whole-item
phrasing ("the output is good"), a thin sole-criterion `expected_output`, a set with no
refusal/guardrail or anti-pattern case, and (Q4 prose) an empty `files` list with
path-shaped tokens in `prompt`/`expected_output` that resolve nowhere (silence with
`narration: true` or declare fixtures). It deliberately does not flag low case count. Run
`--help` on the script for the full Q1-Q9 list; without `jq` it exits 2 and the schema verdict
stands alone.

## Requirements

- A skills root via `CHECK_SKILL_SKILLS_ROOT`, `CLAUDE_PROJECT_DIR`, or a git repository
  (last-resort default `.claude/skills`). Git-backed checks (trigger preservation, vendor
  identity, stale metadata, committed artifacts) skip with a note outside a repo so
  marketplace plugin-cache installs (plain trees) still run the rest of the gate.
- `npx` (Node) is optional; without it the markdownlint check downgrades to a warning and the other
  twenty-four still gate.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `skills_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_SKILLS_ROOT` | Directory holding your skills (each a subdirectory with a SKILL.md). When unset, resolves to .claude/skills under the project root. Set this only when your skills live elsewhere. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure skill-quality@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install skill-quality@<marketplace> -s <scope> --config skills_root=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "skill-quality@<marketplace>": {
         "options": {
           "skills_root": <value>
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
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->
