---
topic: skill-architecture-guidance
section: rename-mechanics
abstract: No alias, redirect, or migration path exists for a renamed skill command; the frontmatter `name:` field is the only stability seam and youtube-digest does not pin it, so a directory rename is a command rename today with five consumer surfaces that fail silently.
claims:
  - claim: "No author-defined alias, former-name, or redirect mechanism exists for any non-bundled skill."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "A user skill overriding a bundled skill does not inherit the bundled skill's aliases."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "For a plugin skill the frontmatter `name` sets the last segment of the command and the directory name is only the fallback, so pinning `name` decouples directory from command."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "youtube-digest/SKILL.md has no `name:` field, so its command derives from the directory name."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:plugins/knowledge/skills/youtube-digest/SKILL.md"
        tier: 0
        pool: "local repository (direct file read this turn)"
  - claim: "The marketplace `renames` map migrates plugin names only; there is no skill-level analogue and no skill-level displayName."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/plugin-marketplaces"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Consumer `Skill(name)` permission rules are documented as exact match, so they silently stop matching after a rename."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "An unresolvable skill name in a scheduled task reaches Claude as plain text instead of executing — a silent degradation."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/scheduled-tasks"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Agent SDK `skills:` allowlists take exact names and fail loudly (TS throw / Python ValueError) — the only non-silent rename failure."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "No semver or breaking-change guidance for component renames exists; plugin `version` is documented purely as a cache key."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "A community reproduction of the rename cliff was closed as not planned, corroborating the documented absence."
    confidence: MEDIUM
    tiers: [2]
    sources:
      - url: "https://github.com/anthropics/claude-code/issues/58102"
        tier: 2
        pool: "GitHub issue tracker (community report)"
produced_by: phase-3-falsification
---

# Rename mechanics — is renaming an installed skill a breaking change?

**Verdict: renaming the COMMAND is a hard break with no alias, no redirect, and no documented
migration path. Renaming the DIRECTORY is free — but only if `name:` is pinned in frontmatter, and
`youtube-digest` does not pin it today.**

## 1. The absence is established, not assumed

This is an absence claim, so the method matters. Checked in full: the complete skill frontmatter
reference table, the plugin manifest schema, the marketplace schema, `plugins.md`,
`plugin-dependencies.md`, `discover-plugins.md`, `commands.md`, `tools-reference.md`,
`permissions.md`, and the three Agent SDK pages.

**No `alias` / `aliases` / `former-name` / `displayName` / `redirect` field appears in the skill
frontmatter table**, whose complete field set is: `name, description, when_to_use, argument-hint,
arguments, disable-model-invocation, user-invocable, allowed-tools, disallowed-tools, model, effort,
context, agent, background, hooks, paths, shell, metadata, license, compatibility`.

Token grep over raw `skills.md`: `alias` 2 hits (both about **bundled** skills), `redirect` 0,
`rename`/`renamed` 0, `deprecat*` 0, `shim` 0, `former` 0.

Aliases are an Anthropic-internal property of bundled commands (`/review` → `/code-review`, `/cost` →
`/usage`, `/clear` → `/reset`,`/new`, …) and are **explicitly non-inheritable**:

> A skill at any of these levels also overrides a bundled skill with the same name, **but not the bundled skill's aliases**.

> For example, a `code-review` skill in your project's `.claude/skills/` replaces the bundled `/code-review`, and typing the bundled alias `/review` never runs your skill.

## 2. The one real stability seam — and a live gap in this repo

`skills.md`, "How a skill gets its command name":

> In a plugin skill, the frontmatter `name` replaces the directory name in the last segment of the command, so `my-plugin/skills/review/SKILL.md` with `name: fancy` becomes `/my-plugin:fancy`. The bare `/fancy` also invokes the skill unless another command already uses that name.

> In a personal or project skill, `name` sets only the display label shown in skill listings, and the command still comes from the directory name.

**Verified by direct read: `plugins/knowledge/skills/youtube-digest/SKILL.md` has no `name:` field.**
Its command therefore derives from the directory name — **a directory rename IS a command rename
today**.

**Pinning `name: youtube-digest` now decouples them**, making any future directory rename free and
consumer-invisible. It is the cheapest de-risking move available and is independent of which design
wins.

> **Scope correction to a claim that surfaced during research.** The `plugins-reference.md` warning
> that an unset `name` falls back to *"the install directory name, which for marketplace-installed
> plugins is a version string that changes on every update"* applies **only to a plugin-root
> `SKILL.md` in a plugin with no `skills/` directory** — verified at raw `plugins-reference.md:39`
> (*"If a plugin has no `skills/` directory and no `skills` manifest field, a `SKILL.md` at the plugin
> root is loaded as a single skill"*). It does **not** apply to `skills/<dir>/SKILL.md`.
> `youtube-digest` is not exposed to that bug.

## 3. Consumer experience on a command rename

No deprecation notice, no "moved" message, no tombstone. The update flow is version-cache-keyed only:

> Claude Code uses the plugin's version as the cache key that determines whether an update is available.

> Claude Code checks for marketplace and plugin updates after your session starts… If any plugins were updated, you'll see a notification prompting you to run `/reload-plugins`, or the new versions load on your next launch.

**INFERRED** from the documented absence: after reload the old `/plugin:old-name` is simply gone — it
stops autocompleting and returns an unknown-command error, with nothing connecting it to the new name.

**COMMUNITY corroboration (non-authoritative):** `anthropics/claude-code#58102` — a reporter renamed a
plugin skill folder, updated frontmatter `name`, bumped the marketplace version, and got "Unknown
command". **Closed as not planned**, no maintainer reply on aliases or migration. Also
`#50486`, a namespacing request that explicitly asked for *"existing unprefixed invocations continuing
to work for backwards compatibility (or a migration path documented)"* — the namespacing shipped
(v2.1.216); the migration path did not.

## 4. Blast radius — worst failure mode first

Every surface except the last fails **silently**. INFERRED from documented behaviors.

| # | Surface | Failure |
|---|---|---|
| 1 | **Cloud routines** | Stored prompts are cloud-persisted and cross-device; silently invalidated with no notice on any surface. Each routine run starts as a fresh remote session |
| 2 | **Scheduled tasks / `/loop`** | An unresolvable name *"reach[es] Claude as plain text instead of executing"* — degradation, not an error. Session-scoped tasks are restored on `--resume`, so a stale name can persist |
| 3 | **Consumer `Skill(name)` permission rules** | Documented as **exact match**; silently stop matching. **A deny rule failing open is the security-relevant direction** |
| 4 | **Agent SDK `skills:` allowlists** | The only **loud** failure — *"In the TypeScript SDK, `query()` throws before starting the Claude Code process… In the Python SDK, `query()` raises `ValueError`"* |
| 5 | Docs, cross-skill prose, bare-`/name` squatting | Cosmetic to moderate; renaming changes which bare name the plugin squats and can newly collide or newly release |

Additional name-stability facts worth knowing before renaming: the folder name `synced` is reserved;
`help`/`feedback` reservation differs in non-interactive sessions; name comparison for synced skills
*"ignores case, spacing, and invisible characters, and treats compatibility forms such as fullwidth
letters and dash variants as their plain equivalents"* — so a rename differing only in case or
hyphenation is not a distinct name.

## 5. `renames` exists — but is PLUGIN-scoped, not skill-scoped

`plugin-marketplaces.md`, "Rename or remove a plugin", documents real machinery:

> A plugin's `name` is its stable identifier. Users reference it in `enabledPlugins`, `pluginConfigs`, and `/plugin install` commands, so changing it breaks every existing install. To change the label shown in the UI without breaking installs, set `displayName` and keep `name` unchanged.

> If you must change a plugin's `name`… add a top-level `renames` entry so existing users migrate instead of seeing a `plugin-not-found` error. Automatic migration requires Claude Code v2.1.193 or later.

> Treat `renames` as append-only history: keep old entries in place even after you expect every user to have migrated. Claude Code follows chains.

Behavior: loads under the new name, shows `Renamed to "x" in the "y" marketplace`, and **rewrites the
old key to the new key in user, project, and local settings** for both `enabledPlugins` and
`pluginConfigs`. `claude plugin validate .` rejects cycles. Managed/policy settings are read-only, so
the notice recurs there until an administrator updates them.

**None of it reaches skill or command names.** There is **no skill-level `displayName`**. And a
*plugin* rename via `renames` **silently re-prefixes every skill command it ships** — which `renames`
does not address.

## 6. Shim / forwarding skill

Undocumented, unmentioned, unprohibited. Zero hits for `shim`, forwarding, or "use X instead" as a
skill-authoring pattern anywhere official. **No community convention exists either** — no plugin repo
demonstrating one was found.

Documented costs if used anyway:

- It is **model-mediated, not a redirect** — costs a turn, is non-deterministic, and relays arguments only if written to.
- It keeps **squatting the old bare name** (which may be exactly the collision being escaped).
- **Consumers cannot hide it:** *"Plugin skills are not affected by `skillOverrides`. Manage those through `/plugin` instead."*

If shipped, set `disable-model-invocation: true` so it fires only on explicit user invocation.

## 7. No versioning guidance for component renames

`version` is documented purely as a **cache key** — a five-step resolution order with no meaning
assigned to major/minor/patch. **No `changelog` field** exists in the plugin manifest or the
marketplace schema. Semver appears only in `plugin-dependencies.md`, and only for *dependency ranges*.

The closest official acknowledgment that a component rename breaks consumers is
`plugin-dependencies.md`, about MCP tools:

> Without a version constraint, the next time the platform team tags a release that **renames an MCP tool**, auto-update moves every engineer's `secrets-vault` to the new version and `deploy-kit` breaks.

**INFERRED:** Anthropic's documented posture on component renames is *"consumers should pin"*, not
*"publishers should provide compatibility"*.

## 8. Practical bottom line

- **Pin `name:` in the plugin `SKILL.md` now**, before it is needed. It is the only documented decoupling and it converts a directory rename from breaking to free.
- **A command-name change has no compatibility mechanism.** Treat it as a hard break, version it as such, and announce it out-of-band — the product gives no in-band channel.
- The rename's real cost is **not** the mechanical reference sweep. It is five consumer surfaces, four of which fail silently.
