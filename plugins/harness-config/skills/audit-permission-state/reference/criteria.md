# Effective-Permission Merge Criteria

## Contents

- [Scopes](#scopes)
- [The one thing that is not a contest](#the-one-thing-that-is-not-a-contest)
- [The one thing that is](#the-one-thing-that-is)
- [`precedence_basis` vocabulary](#precedence_basis-vocabulary)
- [Whole-tool rules](#whole-tool-rules)
- [Bounds every run states](#bounds-every-run-states)
- [The auto-mode entry diff](#the-auto-mode-entry-diff)
- [The permission-plane lint](#the-permission-plane-lint)
- [The `autoMode` block lane](#the-automode-block-lane)
- [Ask rules under auto mode: carry this caveat on any `ask` finding](#ask-rules-under-auto-mode-carry-this-caveat-on-any-ask-finding)
- [Managed policy, and what it does not buy](#managed-policy-and-what-it-does-not-buy)

Version: 1.1.0
Last updated: 2026-08-28

This file defines what `permission-merge.sh` may claim and which documented mechanic each claim
points at. It exists because an *effective* permission set is a precedence claim, and a precedence
claim with no cited mechanic is folklore. Each rule below is our decision in our words with a
pointer to the section that documents the mechanic; read the wording there. The reader's own record
contract lives in `SKILL.md`; the per-check grant vocabulary lives in the sibling
`audit-permission-grants`. Neither is restated here.

Pointers, both read 2026-08-11:
[settings precedence](https://code.claude.com/docs/en/settings#settings-precedence), and
[Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions) and
[Settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence) on the
permissions page.

---

## Scopes

| Scope | Why it is its own member |
| --- | --- |
| `managed` | Highest precedence. Four surfaces per OS, not one file. See below |
| `user` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Where Claude Code's own "Always allow" path writes, so it accumulates the most rules |
| `project` | `.claude/settings.json` at the repository root |
| `local` | `.claude/settings.local.json`, resolved **through worktrees to the main checkout**, so anchoring on the worktree root looks where the file is not. Four documented conditions keep it beside `settings.json` instead, and the reader resolves all four: no enclosing git repository, a repository root equal to `$HOME`, a Windows host, and a repository root, `.git` or `.claude` entry owned by another user |
| `startdir-local` | A pre-v2.1.211 copy left in the session's start directory. Not a fallback: when both exist the repository root wins on a shared key, **but permission rules from both stay in effect**, so both are live |

This table is the dated owner record for the `pre-v2.1.211` boundary. Every other site in this
plugin that names the boundary points here rather than restating it. The reader treats a
`settings.local.json` that a version before v2.1.211 left in the start directory as live beside the
root file: the root file wins any key both set, and the reader counts both files' permission rules.
It treats the Agent SDK's `resolveSettings()` helper as reading the start-directory file.

- **Pointer**: for where `settings.local.json` is read from, see
  [Where Claude Code keeps the local file in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository).
- **As of**: 2026-09-06, Claude Code 2.1.263
- **Recheck trigger**: that section names a different version boundary or drops the start-directory
  case, or a release note names where `settings.local.json` is read from.

### The four start-directory conditions, and the one that is not detectable

The four conditions in the Scopes table's `local` row are the ones the same section documents. All
four are deterministic and the reader resolves all four, naming which applied in the local-scope
basis line.

The Agent SDK helper above is **not** a fifth condition of the same kind. It is the
`resolveSettings()` helper, a standalone inspection function, not a class of running session.
Nothing observable inside a session distinguishes one that used the helper, and no documented
environment variable identifies an Agent SDK or headless run, so the reader states the limit rather
than guessing at it.

- **Pointer**: [Where Claude Code keeps the local file in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository)
  and [Environment variables](https://code.claude.com/docs/en/env-vars).
- **As of**: 2026-09-12
- **Recheck trigger**: either page documents an entrypoint variable or changes the condition list.

### Cloud sessions read a different scope set

The reader treats user settings and project local settings (`~/.claude/settings.json` and
`.claude/settings.local.json`) as not read in a cloud session. Of the managed sources, the reader
counts only server-managed settings there; device files and MDM profiles stay on the operator's
machine. So a user-scope record in a cloud session describes the container's file, never the
operator's, and reporting it without that framing invites the wrong conclusion.

The reader detects a cloud session only by `CLAUDE_CODE_REMOTE` set to `true`, the only entrypoint
variable it branches on. `CLAUDE_CODE_ENTRYPOINT` is not documented and is never read.

- **Pointer**: [Settings in cloud sessions](https://code.claude.com/docs/en/settings#settings-in-cloud-sessions)
  and the `CLAUDE_CODE_REMOTE` row of [Environment variables](https://code.claude.com/docs/en/env-vars).
- **As of**: 2026-09-12
- **Recheck trigger**: the cloud-session scope set changes or the variable is documented
  differently.

The managed scope is four surfaces. Two are the **portable core**, read on every OS: the per-OS
`managed-settings.json` and its `managed-settings.d/` drop-in directory. Their merge order is
documented rather than guessed, so the reader implements it instead of reporting an inventory:

The reader merges drop-in files by their own rule, not as a blanket "arrays concatenated, objects
deep-merged". `managed-settings.json` is the base; `*.json` files in the drop-in directory follow in
alphabetical order. The reader lets a later scalar overwrite an earlier one, unions arrays and
drops repeats, merges objects per key, and swaps in `fallbackModel`, `modelPicker`, and a
same-named `extraKnownMarketplaces` or `managedMcpServers` entry whole. It skips dotfiles.

- **Pointer**: [Split a file-based policy across teams](https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams).
- **As of**: 2026-09-28
- **Recheck trigger**: that section changes how two drop-in files combine a key.

The reader combines sources under `managedSourcesBehavior: "merge"` by key kind. Lists union. Locks
take the strictest value. Restriction allowlists and values taken whole come from the highest source
that sets them. `sandbox.credentials.awsPairs` and `sandbox.ripgrep` are values taken whole since
v2.1.257. Provided MCP server names union, and the higher source's entry wins on a name clash. A
named set of keys is read from the highest source only. `env` merges per variable.

- **Pointer**: [`managedSourcesBehavior`](https://code.claude.com/docs/en/settings-reference#managedsourcesbehavior)
  and [Compose every managed source](https://code.claude.com/docs/en/managed-settings#compose-every-managed-source).
- **As of**: 2026-09-28
- **Recheck trigger**: that table gains or drops a key kind.

Two are **declared optional platform integrations**: the Windows policy registry keys and the macOS managed-preferences
domain. Each is read where it is native and readable; where its tool is missing the surface reports
`skipped` with a notice and every other result is unaffected.

`HKCU` is not a peer of `HKLM`. The reader treats it as lowest policy priority, used only when no
admin-level source exists (pointer: [Compose every managed source](https://code.claude.com/docs/en/managed-settings#compose-every-managed-source)),
so the first key that **exists** ends the search and the rest are not consulted. An existing key
that yields nothing readable is reported unread, never as permission to fall through.

## The one thing that is not a contest

The reader treats permission rules as merging across scopes, never overriding (pointer:
[Settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence) and
[Lists merge instead of overriding](https://code.claude.com/docs/en/settings#lists-merge-instead-of-overriding)).

Every scope's rules are in effect at once. A rule text present in the **same list** at several scopes
therefore has no winner and no loser. The entries are all live and identical in outcome. Naming one
of them "the" origin would assert an override the documentation explicitly denies, so provenance for
that case is the whole contributor set.

`scopes=` lists contributors in the order the reader emitted them. That order is presentation only,
never a ranking.

## The one thing that is

The reader evaluates deny, then ask, then allow, and takes the first match, whatever a rule's
specificity. A deny at any scope beats an allow at any other scope, in both directions, because deny
rules from every scope are evaluated before allow rules (pointer:
[Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions) and
[Settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence)).

The winner is decided by **kind**, and the mechanic is scope-independent in both directions. An
implementation that ranked scopes here would get the cross-scope case exactly backwards: `user` is
the lowest scope and its deny still wins.

## `precedence_basis` vocabulary

Every `effective` record carries exactly one token. A record without one is a defect.

| Token | Emitted when | Mechanic it cites |
| --- | --- | --- |
| `uncontested` | the rule text appears once, in one kind, at one scope | none needed, since nothing contests it |
| `merged-across-scopes` | one kind, two or more scopes | rules merge across scopes rather than override |
| `evaluation-order` | two or more kinds for the same text | deny, then ask, then allow; first match wins, from any scope |
| `evaluation-order+merged-across-scopes` | both of the above | both, in that order |

An `inert` record is an entry that is not in force. It deliberately carries no basis, because a
basis on it would read as a claim about what is in force, and instead names what displaced it:

| Field | Meaning |
| --- | --- |
| `outranked_by=<kind>` | the same rule text exists in a kind that is evaluated earlier |
| `removed_by=deny@<tool>` | a whole-tool deny took the tool out of the model context, so this rule has nothing to act on |
| `outranked_by=ask@<tool>` | a whole-tool ask prompts for every call of that tool, so this scoped allow never applies |

## Whole-tool rules

The reader treats a deny rule that is a bare tool name as removing the tool from the model's
context, and a scoped deny rule as leaving the tool available and blocking matching calls (pointer:
[Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions)).

The tool token is the text before the first `(`; a rule that **is** its own token names the whole
tool. That test needs no pattern matcher, so it is computed rather than caveated.

- **A whole-tool deny makes every other rule for that tool inert**, whatever its kind. An inert deny
  is moot, not weakened. The tool is gone, so a second deny has nothing left to block. Reporting a
  scoped allow as effective underneath one would claim access to a tool that is not in context.
- **`EndConversation` is the documented exception**: the reader never treats a deny rule as removing
  it while any other tool remains, and never expects an ask rule to prompt for it. It is exempt from
  removal here.
- **A whole-tool ask outranks every scoped allow for that tool**, because it matches every call and
  ask is evaluated before allow.

Both cases print a `NOTE:` naming the tool, so the removal is announced rather than inferred from a
run of `inert` records.

## Bounds every run states

Neither is a limitation to apologize for; both change what a finding means.

- **The command-line scope has no file.** Without `allowManagedPermissionRulesOnly`, `--settings`,
  `--allowedTools`, and `--disallowedTools` rank above local, project, and user settings, and no file
  reader can see them. The merge is the effective set the settings **files** define. With the lock
  set in managed settings, the merge drops `--allowedTools` and every rule the user, project, local
  and `--settings` files carry, of all three kinds. It keeps `--disallowedTools` and deny or ask
  rules added during the session, also across a settings reload (v2.1.257+; earlier versions lost
  those command-line and session rules on the first reload). The merge applies the lock only
  when a managed `conf` record carries `allowManagedPermissionRulesOnly true`. Pointer:
  [`allowManagedPermissionRulesOnly`](https://code.claude.com/docs/en/settings-reference#allowmanagedpermissionrulesonly).
  As of: 2026-09-28. Recheck trigger: that entry changes what the lock ignores.
- **Rules are compared by exact text, and the error direction is known.** A deny like
  `Bash(aws *)` wins over each call it covers, a call that a narrower allow like `Bash(aws s3 ls)`
  also covers included (pointer: [Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions)).
  This merge does not evaluate pattern subsumption, so a narrow allow that a broader deny blocks is
  still reported effective. It over-reports allow; it never over-reports blocking.
- **A rule containing a literal newline or carriage return is reported, never split or stripped.**
  The records are line-oriented, so such a rule cannot be represented in one. Read line by line, a
  newline would yield two records, and the CRLF line-ending strip would silently delete a carriage
  return, turning `Bash(a\rb *)` into `Bash(ab *)`: rule strings present in no settings file, flowing
  downstream as real grants. Both are reachable through an ordinary settings file, so both are named
  as unrepresentable with no rule record emitted. The
  line-ending strip stays, because `jq` emits CRLF on Windows, so the in-string case is caught
  *before* it reaches the strip rather than by weakening it.
- **A surface that could not be read bounds the result.** `skipped`, `unreadable` and `invalid-json`
  each raise a caveat naming the surface. `absent` and `not-applicable` raise none: the reader looked
  and there was nothing, which is a complete answer.

## The auto-mode entry diff

The diff reports these allow rules as dropped on entering auto mode and restored on leaving it:
blanket `Bash(*)` or `PowerShell(*)`, wildcarded interpreters such as `Bash(python*)`, rules
letting a package manager run project scripts, any `Agent` allow rule, and any `Monitor` allow
rule (from v2.1.236; before that version a `Monitor` allow rule stayed in effect in auto mode). A
narrow rule such as `Bash(npm test)` carries over.

- **Pointer**: [How auto mode evaluates actions](https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions).
- **As of**: 2026-08-26
- **Recheck trigger**: a release note or that section adds, removes or narrows a dropped class.

### The precondition: which sessions enter auto mode at all

The diff applies only to a session whose starting mode resolves to `auto`. That turns on the CLI
version, how Claude Code is run, `disableAutoMode`, feature-flag fetching and the first session
after an upgrade, read at the pointer when the report is written; this file keeps no copy of that
table. Reporting the diff unconditionally hands a run that never enters auto mode a verdict for a
mode it never enters.

- **Pointer**: for which mode a session starts in, see
  [Which mode a session starts in](https://code.claude.com/docs/en/permission-modes#which-mode-a-session-starts-in)
  (correlate with [the announcement](https://claude.com/blog/auto-mode-default-in-claude-code), 2026-08-14).
- **As of**: 2026-10-01
- **Recheck trigger**: that section changes a starting mode, adds or removes a run shape, or moves
  a version floor.

Five documented classes, and every dropped rule is reported as exactly one of them: `blanket`,
`interpreter-wildcard`, `package-manager-run`, `agent`, `monitor`. The shell-shape patterns are not
defined here: they live in `lib/permission-patterns.sh`, shared with `audit-permission-grants` check
P1, so a class change lands once. `agent` and `monitor` are whole-tool classes with no shell pattern
to share, so the diff driver tests them on the tool token instead.

- **`monitor` is carried by this skill only.** `audit-permission-grants` check P1 flags `Agent`
  allow rules through its own `scan_agent` and has no `Monitor` equivalent, so a fragile `Monitor`
  grant is reported by the entry diff and not by that check. A clean P1 run is not evidence that a
  `Monitor` allow rule survives auto mode.
- **The `monitor` verdict is version-dependent and the diff says so.** Before v2.1.236 a `Monitor`
  allow rule stayed in effect, so reporting it dropped on an older version is inverted in the
  direction that matters: it tells an operator a live grant is already suspended. The script cannot
  read the running version, so whenever it classifies a `Monitor` rule it emits a `DIFF-NOTE`
  naming the v2.1.236 bound rather than asserting the verdict unqualified. Confirm the running
  version before acting on a `monitor` verdict.

- **Only allow rules are in scope.** Deny and ask are evaluated before the classifier in every mode.
- **`autoMode.classifyAllShell` (v2.1.193+) inverts the carry-over answer.** When true, the diff
  treats every Bash and PowerShell allow rule as suspended while auto mode is active, so a narrow
  `Bash(npm test)` does **not** carry over. A diff that cannot see this key can be exactly wrong,
  which is why the reader inventories it as a `conf` record. Pointer:
  [Route all shell commands through the classifier](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier).
- **The key is resolved only from scopes the classifier reads**: user settings, managed settings, and
  inline `--settings`/SDK JSON, never `.claude/settings.json` or `.claude/settings.local.json`. A
  project- or local-scope occurrence is reported as having no effect, never obeyed. Pointer:
  [Where the classifier reads configuration](https://code.claude.com/docs/en/auto-mode-config#where-the-classifier-reads-configuration).
- **A bare tool name is the broadest shell grant, not a surviving one.** `Bash` with no parentheses
  is strictly broader than `Bash(*)`, so it drops as `blanket`, the same treatment `Agent`'s bare
  form already had. Reporting it as kept would tell an operator their widest grant survives.
- **Three scopes set `autoMode`; this reader can open two.** Inline `--settings` and Agent SDK JSON
  have no file, and `classifyAllShell` set there **inverts every shell verdict**. Every run states
  that bound, because the merge's command-line caveat covers rules and not this key.
- **The reader treats `classifyAllShell: false` as the default**, not a type error. Only a value that
  is
  neither boolean is reported as malformed.
- **The oracle is corroboration, not the read path.** `--oracle` spawns a real session to capture the
  harness's own `Ignoring dangerous permission … (bypasses classifier)` narration. Those are
  undocumented `[DEBUG]` strings with no stability contract, so a capture that yields nothing is
  **unavailable** and the prediction stands. An empty capture is never an empty drop set. Its
  measured cost is stated at the flag rather than discovered afterwards.

  **What the oracle costs, measured.** Claude Code 2.1.225, Windows 11, by checksumming the settings
  files and taking a file-mtime census of the config directory either side of one
  `claude --debug-file <scratch> -p` run:

  | Question | Measured answer |
  | --- | --- |
  | Are settings files modified? | **No.** `settings.json` and `settings.local.json` byte-identical afterwards |
  | Is anything under the config root rewritten? | **Yes: `~/.claude.json`.** The harness's own state file; carries no `permissions` key, but it does change |
  | What new files appear? | A `projects/` entry for the working directory, a `session-env/` entry, per-session `security/` and `subagents/` state, a `backups/` entry |
  | Does a plain `-p` session emit drop lines? | **Yes: 216 of them, with no mode flag passed.** On a machine whose `defaultMode` may already have been `auto`, so this does **not** establish that drops require auto mode |

  A probe with `CLAUDE_CONFIG_DIR` pointed at a scratch directory **cannot authenticate**, because
  credentials live in the real config root, so a probe of this shape necessarily touches it. That is
  why the flag enumerates what it leaves behind rather than implying an isolation it cannot have.

  The narration `Ignoring dangerous permission <rule> from <path> (bypasses classifier)` delimits
  **neither field**, and both sides may legitimately contain the separator: a rule
  (`Bash(python3 import from x *)`) and a directory (`notes from work`). No fixed choice of first-
  or last-separator is right for both, so the split is resolved by which candidate leaves a
  well-formed tool token on the left. A line that resolves to zero candidates or several is
  **announced as unresolvable**, never silently split, because a wrong rule name in a divergence
  verdict is worse than an admitted gap.

## The permission-plane lint

Eleven checks over one question: the operator wrote something believing it takes effect, and it does
not. Several also emit a startup warning upstream; the added value here is reading every scope at
once, before a session, and naming the file the dead entry is in.

**The three `C2` gates never merge into one finding.** They cover different scope sets and carry
different version histories, so a merged count would let an operator fix one and believe they had
fixed all three.

| Check | Firing rule, in our words, and the pointer to its mechanic |
| --- | --- |
| `C2-autoMode` | Fires on an `autoMode` key in `.claude/settings.json` or `.claude/settings.local.json`, which the classifier does not read. Before v2.1.207 it also read local settings, so a local-scope finding says so rather than implying it never worked. Pointer: [Where the classifier reads configuration](https://code.claude.com/docs/en/auto-mode-config#where-the-classifier-reads-configuration) |
| `C2-defaultMode` | Fires on `permissions.defaultMode` `auto` or `bypassPermissions` in `.claude/settings.json` or `.claude/settings.local.json`, which we treat as ignored there (`bypassPermissions` from v2.1.257); user, `--settings` and managed settings read both, and `acceptEdits`, `plan`, `dontAsk`, `default`, and `manual` apply from any file in a terminal session. An ignored value still hides a user-scope one unless a higher-ranked settings file or `--permission-mode` sets a mode: `auto` falls to the built-in default, `bypassPermissions` to Manual, so the finding says to remove it from the named file. **Version for `auto`: unverified, so the lint states none.** No page stated a version for `auto` (checked: permission-modes, settings, settings-reference, auto-mode-config, managed-settings, changelog). **Pointer**: [`permissions.defaultMode`](https://code.claude.com/docs/en/settings-reference#permissions-defaultmode), [Common setups](https://code.claude.com/docs/en/permission-modes#common-setups), [Switch permission modes](https://code.claude.com/docs/en/permission-modes#switch-permission-modes), and the [2.1.257 changelog entry](https://code.claude.com/docs/en/changelog#2-1-257). **As of** 2026-09-29. **Recheck when** settings-reference or permission-modes changes which files honor `auto` or `bypassPermissions`, a page gives a version for `auto`, or the 2.1.257 changelog entry changes |
| `C2-planMode` | Fires on `useAutoModeDuringPlan` in `.claude/settings.json`, which we treat as not read from shared project settings. That covers `.claude/settings.json` only, so a local-settings occurrence is **not** claimed dead, since doing so would assert a restriction no page states. Pointer: [`useAutoModeDuringPlan`](https://code.claude.com/docs/en/settings-reference#useautomodeduringplan) |
| `C5-disableType` | Fires on `permissions.disableBypassPermissionsMode` or `permissions.disableAutoMode` set to anything other than the **string** `"disable"`, which is the only value we treat as a lock. Checked at both documented key paths, in every scope; it is not managed-only. Pointer: [`permissions.disableBypassPermissionsMode`](https://code.claude.com/docs/en/settings-reference#permissions-disablebypasspermissionsmode) and [`disableAutoMode`](https://code.claude.com/docs/en/settings-reference#disableautomode) |
| `C6-winPath` | Fires on a path rule whose path has a Windows drive-letter or UNC shape, since we treat Windows paths as normalized to POSIX form (`/c/...`) before matching, so the Windows spelling never matches. Pointer: [Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit). Tested on the **shape**, a drive-letter or UNC prefix, never on the backslash character. Tested on the shape because a character test fails in both directions: the doubled JSON-source spelling is decoded away by `jq -r`, so a test on it is dead in the real pipeline, and a bare backslash is ordinary in shell rules (a regex, an escape, `\n`), so a test on it turns every rule into a severity-`error` finding and drowns the single true one. A UNC path gets its own message: the drive-letter remedy is wrong advice for it |
| `C6-contentField` | Fires on a `Tool(param:value)` rule naming the tool's primary content field. The fields the lint checks, by tool: Bash and PowerShell `command`; Read, Edit, Write `file_path`; Grep, Glob `path`; NotebookEdit `notebook_path`; WebFetch `url`. We treat such a rule as ignored with a startup warning. Pointer: [Match by input parameter](https://code.claude.com/docs/en/permissions#match-by-input-parameter) |
| `C6-allowParam` | Fires on an **allow** rule in `Tool(param:value)` form, since we treat parameter matching as a deny-and-ask feature only; allow rules keep each tool's own specifier syntax. Pointer: [Match by input parameter](https://code.claude.com/docs/en/permissions#match-by-input-parameter). An operator writing one believes they narrowed a grant and has not. Fires only on parameters the page names for tools whose own syntax is a path or a command. `WebFetch(domain:host)` is the documented WebFetch form and `Bash(npm:*)` is a command prefix, so neither is distinguishable from a parameter by shape and neither fires |
| `C6-uncoveredPath` | Fires on a path rule whose tool is `Write`, `NotebookEdit`, `Glob`, or the retired `MultiEdit`, since we treat file access as decided by `Read(path)` and `Edit(path)` rules alone; such a rule is accepted, never consulted, and warned about at startup (v2.1.210+; a `Glob` rule passed in `--allowedTools` is the stated exception). Pointer: [Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) |
| `C6-colonStar` | Fires on a mid-pattern `:*`, as in `Bash(git:* push)`, since we treat `:*` as recognized only at the end of a pattern and a mid-pattern colon as a literal character. Pointer: [Wildcard patterns](https://code.claude.com/docs/en/permissions#wildcard-patterns). The mechanic is about **command-prefix** patterns, so a documented parameter form is exempt: WebFetch's `domain:` prefix takes `*` wildcards ([WebFetch](https://code.claude.com/docs/en/permissions#webfetch)), and firing on `WebFetch(domain:*.example.com)` called a documented, working rule broken. **Known gap:** in a deny or ask rule a mid-pattern `:*` with NO space after it, as in `Bash(git:*push)`, is not reported. It is structurally identical to the parameter form `Agent(model:*-haiku)`, so once the space is gone nothing in the rule text distinguishes them; the space was the only signal. The documented example is the space form, and the pages show no no-space mid-pattern rule anywhere. The exemption is by **grammar**, where in a deny or ask rule an `identifier:value` body is the parameter form, not by a list of parameter names: we treat parameter matching as working for any scalar parameter on any tool ([Match by input parameter](https://code.claude.com/docs/en/permissions#match-by-input-parameter)), so an allowlist could only ever chase it and would flag documented forms such as `Agent(model:*-haiku)` |
| `C6-malformed` | We accept two rule shapes, a bare tool name or a tool name with one parenthesized specifier; a parenthesis within the specifier counts as an ordinary character, which makes `Edit(./Finance (2024)/**)` one rule. Text after the closing parenthesis, as in `Bash(ls) x`, is a malformed Tool(content) rule: Claude Code reports it as invalid settings instead of matching it. An unclosed specifier is the same check. The lint used to keep only the token and treat `Bash(ls) x` as `Bash(ls)` |
| `C6-literalPath` | A Read or Edit path that is not a usable gitignore pattern, such as an unclosed `[`. As a deny or ask rule it protects only that literal path; as an allow rule it grants nothing. One such deny used to fail every file edit; that is not the current behavior |
| `C6-malformed` | We accept two rule shapes, a bare tool name or a tool name with one parenthesized specifier; a parenthesis within the specifier counts as an ordinary character, which makes `Edit(./Finance (2024)/**)` one rule. Text after the closing parenthesis, as in `Bash(ls) x`, is a malformed Tool(content) rule: Claude Code reports it as invalid settings instead of matching it. An unclosed specifier is the same check. The lint used to keep only the token and treat `Bash(ls) x` as `Bash(ls)` |
| `C6-literalPath` | A Read or Edit path that is not a usable gitignore pattern, such as an unclosed `[`. As a deny or ask rule it protects only that literal path; as an allow rule it grants nothing. One such deny used to fail every file edit; that is not the current behavior |

**`C5-disableType` is the highest-consequence check here.** A boolean is valid JSON, is accepted, and
does nothing, so the operator believes auto mode is locked out and it is not.

**False positives these checks are written to avoid**, each a legitimate documented shape:

- A **bare tool-name rule** (`deny: ["Write"]`) matches at the tool level everywhere; `C6-uncoveredPath`
  fires only on a *path* rule.
- `:*` **at the end** (`Bash(npm:*)`) is the working form; only mid-pattern use is dead.
- A parameter rule on a **non**-content field (`WebFetch(domain:example.com)`) is the working form.
- A POSIX-form absolute path (`//c/**/.env`) is the documented Windows spelling and must not trip
  `C6-winPath`.

**Advisory by contract: exit 0 whenever the lint ran.** Exit 2 means it could not run at all, never
"nothing found". A findings count of zero is printed as a summary line, so a clean plane is stated
rather than inferred from silence.

## The `autoMode` block lane

A different surface from the permission plane: four natural-language sections (`environment`,
`allow`, `soft_deny`, `hard_deny`) that an LLM classifier reads. Only mechanical checks live here.
Prose judgment belongs to `claude auto-mode critique`, which is surfaced rather than reimplemented.

| Check | What it means |
| --- | --- |
| `C4-defaults` | a customized section omits `"$defaults"`, which **replaces** the built-in list rather than adding to it. The finding names how many built-in entries are gone, because "you dropped 65 soft_deny rules" is actionable where "missing $defaults" is not |
| `C2b-contradiction` | the same label subject appears in `allow` and in a deny section |
| `C3-shadowed` | an entry whose subject is already in `hard_deny`, which cannot be overridden, so the entry can never change an outcome |

Comparison is by **label subject**, never by body text. The bodies are prose written for an LLM, and
no mechanical comparison of prose is defensible; a shared label across two sections is a mechanical
signal, and the finding says which two sections to reconcile rather than which one is right.

A section still carrying every built-in entry was **never customized**. The CLI expands `"$defaults"`
in its own output, so an expanded section and an omitted one differ only in what is missing. Firing on
the expanded case would report a discard that did not happen.

### The measured defensive contract

Every item below was measured on 2.1.225, not assumed. Each is a way this lane could have reported a
confident wrong answer.

| Defect | What the reader does |
| --- | --- |
| `claude auto-mode config` emits **raw control characters inside JSON string values**. `jq` and strict `json.loads` both reject it, exit status still 0 | parses non-strictly. The offending byte is a raw line feed inside a string, so no line-oriented POSIX filter can distinguish it from the pretty-printer's structural newlines, which is why this lane needs a real parser and why pure POSIX was tested and rejected |
| `defaults --label <x>` **omits** a non-matching key entirely rather than returning an empty list | tolerates a missing key as "no entries", never as an error |
| Entry labels carry a bracketed annotation **before** the colon, as in `Git Destructive [named+specifics …]: …` | splits at the first `[` when one precedes the colon, so the label is not truncated mid-annotation |
| **Exit status is never trustworthy.** `critique` returned 0 on a run producing no output at all | judges every capture by whether it yielded usable content. A run that produced nothing is `status=unavailable` with an explicit "NOT a clean bill", never success |
| A **section** can be present but not a list, as in `{"allow": "not-an-array"}` | reported `status=partial` with a note naming the section, never `read`. Returning an empty list for it would give a clean bill on a section no check could examine |
| A payload can **parse and still be the wrong shape**. A JSON array or string is valid JSON and has no sections | shape is checked before use. Exploding on the first field access would exit 0 with a traceback and no summary line, so a caller grepping `status=` would see nothing and a success exit; instead `status=unexpected-shape`, exactly one summary line, always |

`--critique` prints a cost notice before spawning, for the same reason the entry diff's oracle does:
an unpriced session spawn is the surprise an opt-in flag exists to prevent.

### Optional by declaration

`python3` is **required for an optional feature**, this lane only. Absent, the lane prints a visible
skip notice and exits 0, and every other stage of the skill is unaffected. Node is an equally capable
host and is deliberately not adopted: a second optional runtime doubles the declaration surface for
one feature.

`claude auto-mode reset` is never run. It strips the `autoMode` section from user settings.

## Ask rules under auto mode: carry this caveat on any `ask` finding

Any finding that rests on an `ask` rule prompting under auto mode carries this caveat, named, in our
words: we treat a content-scoped ask rule as checked ahead of the classifier, so an action it
matches always reaches a human prompt in auto mode and never gets a classifier approval.

That mechanic is documented on the auto mode config page, not the permissions page. The permissions
page covers the related case of an ask rule matching one subcommand of a compound command or a
subshell, which still prompts in auto mode; that compound and subshell path was fixed in v2.1.257.
It is not a claim that every ask-rule miss is fixed.

Upstream issue **#42797**, about auto mode ignoring `permissions.ask`, is closed. **#83766** remains
open and still reports `permissions.ask` patterns auto-approved under `defaultMode: "auto"`. This
plugin follows the auto-mode config page, the source with a stated contract. A reader acting on an
`ask` finding should know #83766 is still open.

**What this changes in practice:** an `ask` rule is reported here as outranking an `allow`, and as
surviving auto mode. Treat `ask` as a prompt you *expect*, not a guarantee you *rely on*, and use
`permissions.deny` where the outcome must hold. This is not a defect in the reader.

- **Pointer**: [Add a human checkpoint](https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint)
  and [Compound commands](https://code.claude.com/docs/en/permissions#compound-commands).
- **As of**: 2026-09-28
- **Recheck trigger**: #83766 closes, or the auto-mode config page changes whether a content-scoped
  ask rule always prompts.

## Managed policy, and what it does not buy

The reader treats a managed permission rule as one no lower scope, command line included, can
override (pointer: [Settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence)).

A managed rule cannot be removed by a lower scope. It does **not** follow that managed rules win every
contest: a deny at any scope still beats an allow at managed, because deny is evaluated first
everywhere.

### The conformance report

Two claims are both true and their interaction is what an administrator does not expect: managed
settings are the highest **scope**, and evaluation order (deny, then ask, then allow) applies **from
any scope**. So a lower-scope deny changes the outcome of a managed allow without overriding it.

| Verdict | What it rests on |
| --- | --- |
| `enforced deny` | a managed deny, which no other level can allow. The strongest thing an administrator can write |
| `enforced allow` / `enforced ask` | the managed rule is highest and nothing beneath it outranks its kind |
| `loosenable rule` | a lower scope carries an earlier-evaluated kind for the same rule text |
| `loosenable autoMode` | a managed `autoMode` block, which we treat as additive, not a policy boundary: developers may add their own entries to any of the four sections without being able to delete managed ones, and a developer's `allow` entry beats a managed `soft_deny` entry (pointer: [Where the classifier reads configuration](https://code.claude.com/docs/en/auto-mode-config#where-the-classifier-reads-configuration)). Permissions, hooks, MCP, sandbox-filesystem and sandbox-network each have an exclusivity lock; auto mode has none |
| `enforced` / `loosenable lockout` | `disableAutoMode` is a real lock only when it carries the documented string `"disable"` |

The remedy the `autoMode` finding names is `permissions.deny` in managed settings, for an action that
must never run whatever the user or the classifier configuration says, since no lower scope can
override it (pointer: [Where the classifier reads configuration](https://code.claude.com/docs/en/auto-mode-config#where-the-classifier-reads-configuration)).

**The report prescribes nothing.** It says what the consumer's policy does and does not achieve, and
every rule string it prints came from a file it read, a property the suite asserts positively rather
than by checking that some recommendation marker is absent. It ships no security floor of its own,
which keeps it neutral by construction rather than by restraint.

**Completeness bounds every claim.** Server-managed settings are cached at
`~/.claude/remote-settings.json`. The cache is user-writable and can be stale, so `managed` in this
report means the local admin surfaces; the cache is not folded in. The failure read is the
Organization policy line in `/status`. A `skipped` or `unreadable` surface gets its own note stating
that it is not evidence no policy is deployed there. An administrator reading silence as "no policy"
is the failure this report exists to prevent. Pointer:
[Fetch and caching behavior](https://code.claude.com/docs/en/server-managed-settings#fetch-and-caching-behavior).
As of: 2026-09-28. Recheck trigger: that page moves the cache path or the `/status` failure line.
