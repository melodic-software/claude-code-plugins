# Update / drift protocol

This skill tracks one upstream dependency: **Dometrain's own `dometrain-grounding` skill
content** (`https://raw.githubusercontent.com/Dometrain/mcp/master/skills/dometrain-grounding/SKILL.md`).

It is not consumed verbatim as a live skill — this plugin's `grounding/` skill OWNS its own
usage surface. Upstream is advisory: watch for changes, evaluate, port anything worth keeping.

## The check action

```bash
# Report drift (no changes made) — the only mode /dometrain:sync ever runs
bash "${CLAUDE_PLUGIN_ROOT}/skills/sync/scripts/update.sh"
```

The script does three things:

1. **Fetch** — pulls `skills/dometrain-grounding/SKILL.md` from `Dometrain/mcp` master.
2. **Diff** — compares current upstream against `vendor/SKILL.md` (the plugin's baseline),
   stripping the baseline's own attribution comment first since upstream never carries it.
3. **Report** — prints "no drift" or the diff as "what Dometrain changed since the last review."

**The script does NOT auto-write changes into `grounding/SKILL.md`.** Dometrain's own prose
style, frontmatter shape, and structure differ from this plugin's conventions and would clobber
this plugin's additions (the standing untrusted-data instruction, this plugin's own
frontmatter). The human in the loop decides what to port.

## Roles: consumer vs plugin maintainer

- **Consumers** run `/dometrain:sync` for report-only drift visibility. A drift finding is input
  for an issue or PR against this plugin's marketplace repository — not something to patch in
  the installed copy, which is an ephemeral cache overwritten on plugin update.
- **Plugin maintainers** port upstream changes in a working clone of the marketplace repository
  (using the `--plugin-dir` local development loop), then refresh the baseline there:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/sync/scripts/update.sh" --refresh-baseline
  ```

  **On pinning `UPSTREAM_URL` to a commit SHA (considered, reverted):** an earlier revision of
  this script pinned the fetch to a fixed commit for supply-chain integrity. A second independent
  reviewer correctly caught the regression this caused: a pinned URL makes `check` compare the
  baseline against the same frozen commit forever, so `/dometrain:sync` can never detect real
  drift once Dometrain's `master` moves — defeating the report-only check's actual purpose. The
  human diff-review a maintainer performs before choosing to run `--refresh-baseline` is already
  the integrity gate; a URL pin adds ceremony without adding protection beyond that. Fetching
  live `master` (matching `context7`'s established precedent) is correct here.

  This overwrites `vendor/SKILL.md` with current upstream (re-add the attribution comment
  afterward — `--refresh-baseline` writes raw upstream content, which never carries it) and
  stamps `synced:` in `grounding/SKILL.md`'s frontmatter. It writes next to the script itself,
  so run it only in a working clone — never in the installed plugin cache. This flag is a raw
  CLI argument typed directly by a maintainer; `sync/SKILL.md`'s own dispatch never constructs
  or exposes it, so there is no model-reachable path to it.

## What to preserve when integrating upstream changes

When porting upstream additions, **keep** this plugin's customizations:

| Customization | Where it lives | Why |
|---|---|---|
| Frontmatter shape | `grounding/SKILL.md` | Plugin conventions (`user-invocable`, `argument-hint`, `disable-model-invocation`, `metadata`) |
| The `grounding`/`sync` skill split | Both skills | `update` must stay non-model-reachable — a CRITICAL stress-test finding for this plan |
| Standing untrusted-data instruction | `grounding/SKILL.md` | Prompt-injection defense this plugin adds; upstream's own skill doesn't carry it |
| `userConfig`-driven setup pointer | `grounding/SKILL.md`, README | This plugin's native secure-credential-storage UX, absent from upstream's env-var auth |

What to **adopt** from upstream (when present):

- New tools, or new topic coverage in the "When to consult Dometrain" catalog
- New citation or quota-etiquette conventions
- New error-handling or quota messages

## Escalation

If the drift check surfaces a substantive behavioral change — a new tool, a new auth model, a
new quota policy — research primary sources (Dometrain's README, release notes, the MCP server
card) before porting. Upstream's `SKILL.md` is not a changelog; it reflects the current state
only.

## What this action does NOT do

- **Does not auto-merge upstream content** — the maintainer approves every port.
- **Does not refresh the baseline automatically** — only on `--refresh-baseline` after manual
  integration, so the baseline stays honest about "what was last reviewed."
- **Does not run from the model's own initiative** — `sync/SKILL.md` is
  `disable-model-invocation: true`; only a human's explicit `/dometrain:sync` invocation reaches
  this script.
