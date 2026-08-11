# Phase 0 — fresh-docs mandate, discharged

Every fact the two skills ship is re-confirmed here against pages fetched **2026-08-10**, per
`CLAUDE.md`'s fresh-docs mandate. Facts carried from the 2026-08-09 local capture are not accepted as
verified; each row below says which page it came from, or says the page does not state it.

Pages fetched this session, all from the `docs/OFFICIAL-DOCS.md` index:

- <https://code.claude.com/docs/en/auto-mode-config>
- <https://code.claude.com/docs/en/settings>
- <https://code.claude.com/docs/en/permission-modes>
- <https://code.claude.com/docs/en/permissions>

## Confirmed — safe to ship

| Fact | Source | Wording |
|---|---|---|
| Scope precedence | settings | Managed (highest) → command line → local → project → user (lowest) |
| Rule evaluation order | permissions | "Rules are evaluated in order: deny, then ask, then allow. The first match in that order determines the outcome, and rule specificity doesn't change the order." |
| `autoMode` scope set | auto-mode-config | Read from `~/.claude/settings.json`, managed settings, and `--settings`/Agent SDK inline JSON. "The classifier doesn't read `autoMode` from project settings in `.claude/settings.json` or `.claude/settings.local.json`." |
| `autoMode` local-settings gate | auto-mode-config | "Before v2.1.207, the classifier also read `.claude/settings.local.json`" |
| Criterion 3's four drop classes | permission-modes | "On entering auto mode, broad allow rules that grant arbitrary code execution are dropped: Blanket `Bash(*)` or `PowerShell(*)`; Wildcarded interpreters like `Bash(python*)`; Package-manager run commands; `Agent` allow rules." Plus "Narrow rules like `Bash(npm test)` carry over. Dropped rules are restored when you leave auto mode." |
| `defaultMode: "auto"` gate | permission-modes | "Claude Code ignores `defaultMode: \"auto\"` in project and local settings." |
| `disableAutoMode` shape | permissions | "set `permissions.disableBypassPermissionsMode` or `permissions.disableAutoMode` to `\"disable\"` in any settings file" — the **string**, and **any** scope, confirming it is not managed-only |
| `:*` position rule | permissions | "The `:*` form is only recognized at the end of a pattern. In a pattern like `Bash(git:* push)`, the colon is treated as a literal character and won't match git commands." |
| Start-directory `settings.local.json` | settings | "Before v2.1.211, the file always lived in the starting directory. Claude Code still reads a `.claude/settings.local.json` that an earlier version left there. When both files set the same key, the repository root's value wins, **except that permission rules from both files stay in effect**." |
| Hook cannot override deny/ask | permissions | "Hook decisions don't bypass permission rules… a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `\"allow\"`" — independently corroborates the local four-leg experiment |
| No `allowManagedAutoModeRulesOnly` | all four pages | Zero occurrences. Affirmatively supported rather than merely absent: "A developer can extend `environment`, `allow`, `soft_deny`, and `hard_deny` with personal entries but can't remove entries that managed settings provide… a developer-added `allow` entry can override an organization `soft_deny` entry: the combination is additive, not a hard policy boundary," alongside "For actions that must never run regardless of user intent or classifier configuration, use `permissions.deny` in managed settings, which… can't be overridden." |

That last row **upgrades** the claim's status. The plan flagged it as resting on an unverified research
slice; it now rests on the governing page. Phase 6's caveat can be narrowed to the precise wording:
managed `autoMode` entries cannot be **removed**, but a developer `allow` **can** override an
organization `soft_deny`, so managed auto-mode rules are not a hard policy boundary.

## Corrections — the plan was wrong or incomplete

1. **Managed policy is not two JSON files, and on Windows it is partly the registry.** The settings
   page enumerates: macOS — the `com.anthropic.claudecode` managed-preferences domain (a plist),
   `/Library/Application Support/ClaudeCode/managed-settings.json`, and a
   `managed-settings.d/` directory; Linux and WSL — `/etc/claude-code/managed-settings.json` and
   `/etc/claude-code/managed-settings.d/`; Windows — `HKLM\SOFTWARE\Policies\ClaudeCode`,
   `HKCU\SOFTWARE\Policies\ClaudeCode`, `C:\Program Files\ClaudeCode\managed-settings.json`, and a
   `managed-settings.d/` directory. **Phase 1 cannot read the managed scope with `jq` over a fixed
   pair of paths.** It needs a per-OS reader covering a plist domain, a registry hive, and a
   drop-in directory whose file count is unknown ahead of time. This is the single largest scope
   change Phase 0 produced.
2. **Legacy Windows managed path is dead.** "The legacy Windows path
   `C:\ProgramData\ClaudeCode\managed-settings.json` is no longer supported as of v2.1.75." Reading it
   would report policy that is not in force.
3. **`.claude/settings.local.json` resolves through worktrees to the main checkout.** "Claude Code
   reads and writes this file at the root of the git repository, resolved through worktrees to the
   main checkout, so one file covers sessions started in any subdirectory or worktree." Three stated
   exceptions keep it in the start directory: outside a git repository, when the repository root is
   the home directory, and in Agent SDK sessions. Phase 1's scope discovery must resolve the worktree
   rather than assuming the current root — this very topic is being planned inside a worktree, so the
   case is live, not hypothetical.
4. **`autoMode.classifyAllShell` exists and no criterion covers it.** Requires v2.1.193 or later;
   when `true` it "suspend[s] every Bash and PowerShell allow rule while auto mode is active." That
   changes criterion 3's answer wholesale — with it on, narrow rules do **not** carry over. An audit
   reporting the drop set without reading this key can be exactly wrong. Gap to close in Phase 4.
5. **`claude auto-mode reset` needs v2.1.212+** and "removes the `autoMode` section from your user
   settings file," asking `Reset auto mode configuration to defaults?` unless `--yes` is passed. The
   standing prohibition on running it against the operator's config is reinforced, not relaxed.

## Open upstream discrepancies — criterion 10 caveats

- **`defaults --label` on a non-matching key.** The page states "sections with no match print as empty
  lists." The 2026-08-09 local capture measured the key **omitted entirely**. Both cannot be true.
  The defensive contract already tolerates a missing key, so the code is safe either way, but the
  divergence is now documented rather than folkloric and any finding derived from it carries the
  caveat.
- **`permissions.ask` under auto mode.** Issues #83766 and #42797 report ask patterns auto-approved.
  The page contradicts them: content-scoped ask rules "always force a permission prompt, even in auto
  mode… The classifier cannot auto-approve a matching action." The discrepancy stands; the caveat the
  Brief already requires stays.

## Not stated — must not ship as fact

- **The `v2.1.142` gate** on project-scope `defaultMode` ("project could set it before v2.1.142")
  appears on none of the four pages. Criterion 2 asserts it. Either relocate it to a page that states
  it, or ship the gate without the version number and caveat it.
- **Which scopes read `useAutoModeDuringPlan`.** The setting is confirmed to exist and to be on by
  default; no page states it is not read from shared project settings, which is what criterion 2's
  third item claims.
- **`Write(path)`-shaped rules "accepted but never consulted."** The permissions page states something
  adjacent but different: rules matching a tool's *primary content field* by parameter — `Bash(command:…)`,
  `Write(file_path:…)` — are ignored **and emit a startup warning**. That is a different mechanic with
  a different observable. Criterion 6's fourth item needs re-deriving against this wording before it
  ships.

The startup warning in that last item is itself useful: it is a readable signal carrying rule text,
one of the channels the Brief listed as unexplored.

## Addendum — 2026-08-10, managed-surface detail Phase 9 needed

Same page (<https://code.claude.com/docs/en/settings>), re-fetched while building Phase 9's shared
managed-scope enumeration. These four facts were not in the original pass and each changes what a
reader must do:

| Fact | Wording |
|---|---|
| Drop-in merge order **is** documented | "Following the systemd convention, `managed-settings.json` is merged first as the base, then all `*.json` files in the drop-in directory are sorted alphabetically and merged on top. Later files override earlier ones for scalar values, arrays are concatenated and de-duplicated, and objects are deep-merged. Hidden files starting with `.` are ignored." |
| The Windows policy key holds JSON in one **value** | `HKLM\SOFTWARE\Policies\ClaudeCode` "registry key with a `Settings` value (REG_SZ or REG_EXPAND_SZ) containing JSON" — a reader wants that value, not the key's subkeys |
| `HKCU` is **not** a peer of `HKLM` | `HKCU\SOFTWARE\Policies\ClaudeCode` is "lowest policy priority, only used when no admin-level source exists". Merging both would report policy that is not in force |
| A managed source exists that no local reader can see | "Server-managed settings: delivered remotely at sign-in from Anthropic's servers via the claude.ai admin console or from a self-hosted Claude apps gateway" |

Consequences carried into the plan:

- Phase 1 can state drop-in merge results as **decided**, not caveated — the ordering is documented.
  The `$defaults`-style caveat the Brief's decidability bound calls for does not apply here.
- Phase 1's Windows registry leg reads the `Settings` value and consults `HKCU` **only when no
  admin-level key exists** — key existence, not value readability, ends the search. Measured
  2026-08-11: `reg query <key> /v Settings` returns the same exit code and the same message for a
  missing key and for a present key with no such value, so keying the search on the `/v` form would
  let an `HKLM` key with an unreadable value fall through and report user-level policy as the managed
  policy. A bare `reg query <key>` does distinguish the two (exit 0 when the key exists), so that is
  the existence probe; an existing key that yields nothing readable is reported unread.
- Phase 6's managed-conformance report carries a standing caveat that server-managed settings are a
  managed source with no local path, so "the deployed managed policy" always means the local
  surfaces. A report that omits this implies a completeness it cannot have.

## Addendum — 2026-08-11, the merge semantics Phase 2 rests on

Phase 2 claims an *effective* permission set. Nothing in the table above says how rules from two
scopes combine, so the two governing sections were re-fetched before any merge was written
(<https://code.claude.com/docs/en/settings> §How scopes interact and
<https://code.claude.com/docs/en/permissions> §Settings precedence). Verbatim:

| Fact | Wording |
|---|---|
| Permission rules **merge**, they do not override | "For example, if your user settings set `spinnerTipsEnabled` to `true` and project settings set it to `false`, the project value applies. Permission rules behave differently because they merge across scopes rather than override, and a few security-sensitive settings honor a restrictive value from certain scopes that otherwise couldn't override them." |
| Managed permission rules cannot be overridden | "Permission rules follow the same settings precedence as all other Claude Code settings, with managed settings highest: no other level, including command line arguments, can override a managed permission rule." |
| Deny wins from **any** scope, in both directions | "If a tool is denied at any level, no other level can allow it… The same holds across settings scopes: if user settings allow a permission and project settings deny it, the deny rule blocks it. The reverse is also true: a user-level deny blocks a project-level allow, because deny rules from any scope are evaluated before allow rules." |
| A broad deny beats a narrower allow | "A broad deny rule like `Bash(aws *)` blocks every matching call, including calls that also match a narrower allow rule like `Bash(aws s3 ls)`, so a deny rule can't carry allowlist exceptions. The same precedence applies between ask and allow." |
| The command-line scope is a real scope | "**Command line arguments**: temporary session overrides" — ranked second, above local, project and user |
| `/permissions` already shows rules and their source file | "You can view and manage Claude Code's tool permissions with `/permissions`. This UI lists all permission rules and the `settings.json` file each rule comes from." |

Consequences carried into the plan:

- **There is no same-kind winner to elect.** Because rules merge rather than override, a rule text
  present in the same list at two scopes has both entries in effect; naming one as *the* origin would
  be a precedence claim no page supports. Provenance for that case is the full contributor set. A
  winner exists only **across kinds**, and the mechanic that elects it is evaluation order, which the
  wording above makes explicitly scope-independent in both directions.
- **The start-directory copy never needs ranking against project settings.** That rank is undocumented,
  and with no same-kind election it is never consulted.
- **Pattern subsumption is a known false-positive class, not an unknown.** A merge over exact rule text
  reports `Bash(aws s3 ls)` as an effective allow even where `Bash(aws *)` is denied, because the page
  documents that the broad deny wins. The direction is known — over-reporting allow — so the caveat
  states it rather than pleading undecidability.
- **The command-line scope is invisible to any file reader**, so an effective-set claim is bounded to
  what the settings files define. This is a second invisible source alongside server-managed settings.
- **`/permissions` is prior art and the skill must stop overclaiming.** It lists rules with their
  source file interactively. It does not resolve deny-over-allow across scopes, does not distinguish a
  scope that was empty from one that could not be read, and is not scriptable. The skill's framing is
  narrowed to that difference rather than claiming there is no way to see rules at all.

## Version constants cleared for use

`v2.1.75`, `v2.1.193`, `v2.1.198`, `v2.1.200`, `v2.1.203`, `v2.1.207`, `v2.1.208`, `v2.1.211`,
`v2.1.212` — each appears verbatim on a page fetched above. **`v2.1.142` is not cleared.**
