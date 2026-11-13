# Record plugin-acceptance security reviews

- Status: accepted; each later review or delta review amends this record with its own dated section
- Date: 2026-07-12
- Related: the review procedure and its criteria 1-7 in
  [Plugin-acceptance security review](../migration-playbook.md#plugin-acceptance-security-review);
  [ADR 0092](0092-carry-only-the-miro-mcp-server-in-a-plugin.md) (the MCP carry decision behind the
  miro record)

## Context

Every plugin accepted into this marketplace, and every version bump that adds a trust surface,
passes the plugin-acceptance security review in the migration playbook. A plugin touching
surfaces 2, 5, 6 or 7 needs a recorded accept or deny with its rationale. Each section below is one
such record: the plugin, the version reviewed, the verdict and the date. "Criterion N" and "(N)"
refer to the numbered criteria of that procedure.

## Decision

Accept each plugin below at the state its record describes. A record's own re-trigger names what
re-opens it; a version bump that adds a trust surface re-opens any of them.

### Review record: `miro` (first-party MCP server, ACCEPT, 2026-07-12)

The first-party trust accept behind the SHIP verdict in
[ADR 0092](0092-carry-only-the-miro-mcp-server-in-a-plugin.md):

- **Vendor / provenance.** First-party: a thin wrapper (authored in-house) over Miro's official REST
  API client (`@mirohq/miro-api`); `plugin.json` `author` = Melodic Software. Not a third-party remote
  MCP (Miro's own `mcp.miro.com` was rejected for having no board-delete tool, and for being a
  third-party remote-egress acceptance the playbook denies by default).
- **Transport.** Local `stdio`, a per-session `node dist/index.min.js` process; no listening port, no
  auto-connect to any remote MCP host.
- **Data egress.** Only the Miro REST calls the consumer's own tool invocations make, to
  `api.miro.com`, authenticated by the consumer's own token. No telemetry, no other outbound network.
- **Token scope.** `MIRO_API_TOKEN` → `userConfig` `miro_api_token`, `sensitive` (secure credential
  storage, never `settings.json`; where it lands:
  [Configuration ownership and scope](../plugin-philosophy.md#configuration-ownership-and-scope));
  the consumer supplies and scopes it. The server exits at startup if unset.
- **Opt-in.** `defaultEnabled: false`, so it installs disabled; the consumer enables it deliberately.

### Review record: `github` (ACCEPT, 2026-07-21)

Recorded here as the single SSOT (miro record precedent). Reviewed at `0.1.0`; a version bump adding a
new trust surface re-triggers this review.

- **Code execution (1).** No hooks, no scripts wired to any event. The plugin ships prompt
  artifacts only (skills + reference markdown) plus `github.test.sh`, a repo-CI contract test
  referenced by nothing in the manifest, so it is inert in a consumer install.
- **MCP servers (2).** None.
- **Consumer config (3).** One `userConfig` boolean (`offer_browser_automation`, non-sensitive,
  documented, default `true`). No credential options: authentication stays entirely in the
  consumer's own `gh` CLI login, and the plugin never prompts for, stores, or transports a token.
  Consumer-side routing/conventions files live at the documented `.claude/github/` project layers
  and `~/.claude/github/` user-global layer (sanctioned read per criterion 4's operator-home
  carve-out).
- **Cache isolation (4).** All intra-plugin references anchor at `${CLAUDE_PLUGIN_ROOT}` (skills)
  or resolve inside the plugin directory (reference cross-links). No `../` reach-outs beyond the
  plugin root, no constructed absolute paths.
- **Data egress (5).** Three channels, all consumer-initiated, no telemetry:
  - `api.github.com` via the consumer's **own** `gh` auth. Bare invocations are read-only by
    written contract (write-capability guard: no field/input flags, no non-GET method, no GraphQL
    `mutation`); writes exist only behind `--apply` → consumer-declared routing → per-step user
    confirm naming the exact command and its doc provenance.
  - Official GitHub docs (`docs.github.com` et al.) runtime fetches for grounding, the D4
    zero-vendored-knowledge posture; read-only, with a fetch-integrity rung and a
    refuse-recall-as-grounded branch.
  - **Browser automation over the consumer's authenticated GitHub session**, the heavy surface,
    accepted with layered gates: presence-gated (claude-in-chrome tool probe / playwright
    plugin-installed check), **never auto-fires**, each action individually offered and confirmed
    with the resolved settings URL, intended action, and mechanics provenance; post-write
    read-back verification where an API read exists; guided-manual + deep-link fallback always
    available. `offer_browser_automation: false` suppresses the offer, recorded honestly as an
    **advisory, model-honored gate layered under the per-action confirm, not a runtime-enforced
    kill switch**; the hard gate is the per-action user confirm. Accept rationale: some org-admin
    surfaces are UI-only, the session and credentials remain the user's own, and every action is
    user-in-loop; denying the surface would only push users to unassisted manual clicking with no
    provenance trail.
- **Prompt injection via ingested GitHub content (explicit item).** Everything fetched from GitHub
  (repo names, descriptions, issue/PR bodies, webhook URLs, custom property values) is declared
  **untrusted data, never instructions** as a standing instruction in both ingesting skills
  (`audit`, `advise`); an injected instruction must not trigger a write, browser action, or
  routing change. Evidence: anti-pattern eval cases (audit id 5, advise id 9). Defense in depth:
  every write path is already user-in-loop, so a successful steer still lands on a human confirm.
- **Provenance & third-party trust (6).** First-party authored (`author` = Melodic Software),
  MIT. No third-party SaaS delegation: the only vendor wired is GitHub itself, reached through the
  consumer's pre-existing `gh` relationship.
- **Main-thread / PATH (7).** No `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT.** Surfaces 1, 2 and 7 are absent, 3 and 4 conform, surface 5's browser-automation channel is
accepted with the layered gates above, and surface 6 is first-party.

### Review record: `dometrain` (ACCEPT, 2026-07-22)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review. Since 0.5.0 the
plugin ships no server and no `userConfig`; the update script stays in `dometrain`.

**This record is stale, and a re-review is owed (recorded 2026-08-28).** The plugin ships `0.2.7`.
Eleven releases landed between the reviewed version and the shipping one, and no record says
whether any of them added a trust surface, which is the condition the re-trigger above turns on.
Answering it takes a review, so it cannot be settled either way by reading this page. Until that
review runs, the ACCEPT below describes `0.1.0` and states nothing about what a consumer installs
today. The re-review was not performed when this note was written; it is logged as owed.

- **Code execution (1).** None. No hooks; `update/scripts/update.sh` is not wired to any event
  and is not model-reachable: `update/SKILL.md` carries `disable-model-invocation: true`, so it
  runs only on a maintainer's explicit `/dometrain:update` invocation.
- **MCP servers (2).** The remote server itself: third-party (Dometrain-hosted), `http`
  transport, Bearer auth via `userConfig.dometrain_api_key` (never hardcoded), `defaultEnabled:
  false`. **Data egress / prompt-injection:** search queries and lesson IDs are sent to
  `mcp.dometrain.com`; responses are curated lesson text, which IS a genuine
  indirect-prompt-injection surface. The risk is that returned text could steer Claude's use of
  *other* tools already in the session (Bash, Write, other MCP servers), not whether Dometrain's
  own tools are mutating (they are all read-only). Mitigated the same way this repo's `github`
  plugin already accepts this class of risk (its prompt-injection item): `grounding/SKILL.md` carries a standing
  instruction treating all `search_dometrain`/`search_code`/`get_lesson` results as untrusted
  reference data, never instructions, backed by an anti-pattern eval case. That is an advisory,
  model-honored defense, not a runtime-enforced one. Explicit trust decision: **ACCEPT**, third-party, rationale =
  read-only course-content grounding, no destructive tool surface, user's own
  paid-subscription-scoped token, `defaultEnabled: false`, standing untrusted-data instruction.
- **Consumer config (3).** One sensitive required `userConfig` string
  (`dometrain_api_key`), documented.
- **Cache isolation (4).** All skill/script paths resolve via `${CLAUDE_PLUGIN_ROOT}`-relative
  or script-own-location-relative paths (matching `context7`'s pattern); the `update.sh` upstream
  fetch reaches `raw.githubusercontent.com`, a documented, justified outbound call (criterion 5),
  not a `../` reach-out.
- **Data egress (5).** Two channels: (a) the MCP server itself, covered under (2); (b)
  `update/scripts/update.sh`'s fetch of Dometrain's public GitHub-raw skill content, read-only
  and never model-reachable: `update/SKILL.md`'s `disable-model-invocation: true` means only a
  human explicitly running `/dometrain:update` fires it, never the model on its own initiative and
  never from the installed plugin cache absent that explicit human action. No data leaves beyond
  the anonymous GET itself. No telemetry.
- **Provenance & third-party trust (6).** First-party plugin manifest/config (Melodic Software
  authored), but it wires TWO third-party trust surfaces: Dometrain's MCP server (the primary
  trust delegation, covered under (2)) and Dometrain's own public skill content as a
  vendored/reviewed text dependency (covered under (4)/(5)). Every sync is human-reviewed
  before a baseline refresh, never auto-applied, so the trust surface is bounded by that review
  gate, not blind ingestion. Note: this plugin's `grounding`/`update` skill split is a stronger
  enforcement of that boundary than this repo's existing `context7:lookup` precedent, which
  bundles an equivalent `update` action into a model-invocable skill, a pre-existing gap flagged
  during this review, not remediated here, tracked separately.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT.** Surfaces 1/7 absent; 2 accepted with the stated third-party rationale; 3/4
conform; 5 bounded to two justified, non-telemetry channels; 6 dual third-party surfaces both
gated (credential scope + human-reviewed sync).

### Review record: `context-usage` (ACCEPT, 2026-07-24)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review.

- **Code execution (1).** No hooks. Two bash scripts, neither wired to any event:
  `statusline-tee.sh` runs only when the OPERATOR wires it into their own `settings.json`
  statusline (the setup skill prints the edit, never applies it), and `context-zone.sh` runs only
  on explicit invocation. Both reviewed: no `eval`, no `curl | sh`, no outbound network; the one
  untrusted input that reaches the filesystem (`session_id` from statusline stdin) is sanitized to
  `[A-Za-z0-9_-]` before filename use; `captured_at` is format-gated to strict ISO-8601 UTC before
  being passed to `date -d`; no snapshot value is passed to `eval`, `sh -c`, or any code
  executor. Every failure path is transparent (wrapped statusline output
  and exit code unchanged). No kill-switch `userConfig` needed: nothing runs unless the operator
  wires it, and unwiring is the same one-line edit.
- **MCP servers (2).** None.
- **Consumer config (3).** No `userConfig`. The one machine file the plugin owns
  (`~/.claude/context-usage/zones.json`) is written only by the setup skill's explicit `apply`.
- **Cache isolation (4).** Skills reference bundled files via `${CLAUDE_PLUGIN_ROOT}`; no `../`
  reach-outs. Writes go only to `~/.claude/context-usage/`, the operator-home carve-out,
  deliberately outside `${CLAUDE_PLUGIN_DATA}` because the directory is a documented cross-plugin
  artifact location (per-session snapshots + zones SSOT) that sibling-plugin sessions read by path;
  `${CLAUDE_PLUGIN_DATA}` resolves per-plugin-identity and would hide that location. Same accepted
  pattern as `rate-limits`.
- **Data egress (5).** None. No network, no telemetry. Snapshot data (context-window token
  counts + session id) never leaves the machine. Residual local-integrity limitation, stated
  honestly: the contract dir's `chmod 700` is best-effort, a no-op on filesystems without POSIX
  modes (Windows ACL volumes under Git Bash), where another local user could read or forge
  snapshots. The reader contract therefore forbids consumers from attaching security decisions to
  zone words (routing hints only), and the resolver format-gates `captured_at` and requires the
  embedded session id to match, so forgery cannot ride a lenient parser.
- **Provenance & third-party trust (6).** First-party (Melodic Software authored), MIT, no
  third-party delegation.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT.** Surfaces 2/5/6/7 absent; 1 bounded to operator-wired transparent scripts
with sanitized untrusted input; 3 empty; 4 conforms under the documented operator-home
carve-out.

### Delta review: statusline shim (`context-usage` 0.2.0, `rate-limits` 0.2.0, ACCEPT, 2026-07-24)

Triggered by the review record's own rule: both plugins' `setup apply` now writes an EXECUTABLE
(`bin/statusline-shim.sh`) into the plugin's operator-home directory, where `apply` previously
wrote only data (`zones.json`) or nothing at all. Reviewed as a delta; the base records stand.

- **Code execution (1).** The write is a byte-identical copy of a reviewed, tested, bundled script,
  with no generation, no templating, and no operator-supplied content, so nothing enters it that was not
  already in the plugin. **The copy is inert until the operator wires it**: it is not
  on `PATH`, not a hook, and not referenced by any Claude Code surface, so the base record's
  justification for having no kill switch, "nothing runs unless the operator wires it, and
  unwiring is the same one-line edit", survives verbatim. The shim itself has no untrusted input
  (its only inputs are its own argv and the cache directory listing), performs no filesystem
  writes, and `exec`s either the resolved tee or the wrapped command. The resolution glob skips
  transient `temp_*` marketplace directories; the residual case, two distinct marketplaces both
  shipping a plugin of the same name, resolves to the most recently installed one and is
  documented in the script.
- **Consumer config (3).** Unchanged. The shim is not configurable and reads no config.
- **Cache isolation (4).** The write stays inside the same operator-home carve-out already accepted
  for these plugins (`~/.claude/context-usage/`, `~/.claude/rate-limits/`); each plugin's
  `apply` is explicitly forbidden from writing into the sibling's directory. `${CLAUDE_PLUGIN_DATA}`
  was considered and rejected as the shim's home: it is deleted on uninstall, which would leave a
  wired statusline pointing at a missing file, the exact 127-exit failure this change removes,
  and its per-plugin-identity path would hardcode the marketplace name into the operator's
  settings.
- **Main-thread / PATH (7).** Still none. `bin/` here is a plugin-owned operator-home subdirectory,
  NOT the plugin `bin/` component that joins the Bash tool's `PATH` (which stays rejected
  marketplace-wide); the shim is invoked only by absolute path from the operator's `statusLine`.
- **Surfaces 2, 5, 6.** Unchanged: no MCP servers, no network or telemetry of any kind, first-party
  MIT code.

**Verdict: ACCEPT.** The new surface is one inert, byte-identical copy of already-reviewed code
into an already-accepted directory, on explicit operator request, with the no-kill-switch
justification intact. Uninstall leaves the shim behind by design; it then degrades to running the
operator's statusline unchanged, and both setup skills document the two-step manual cleanup.

### Delta review: mods replace the status-line tees (`context-usage` 0.11.0, `rate-limits` 0.12.0, ACCEPT, 2026-10-03)

Triggered by the review record's own rule: the writer of both guards' contract files changes from
an operator-wired status-line tee to a mod, a hooks module (`hooks/register.tsx`) Claude Code runs
in its own process on every tool call and prompt, under
[ADR 0052](0052-adopt-claude-code-mods.md). The files, their paths and their readers' trust
class are unchanged. Reviewed as a delta; the base records and the shim delta stand as history.

- **Code execution (1).** New: in-process code on `tool.call`, `prompt.submit`, `session.*`,
  `turn.*`, `command.run` and `ui.render`, running whenever the plugin is enabled, where the tee ran
  only once the operator wired it. Neither mod uses `tool.check`, so neither can approve a call a
  rule or hook refused. context-usage's `tool.call` hook denies a call only in blocking mode, the
  capability its retired `PreToolUse` gate already had. Each mod starts one program, the bundled
  snapshot helper (`node lib/write-snapshot.mjs`, argv built by the mod, body on stdin), once per
  write; context-usage also starts the consumer's own `HOOK_TELEMETRY_SINK` when one is set. The
  untrusted input that reaches a path is still only the session id, accepted as `[A-Za-z0-9_-]+`;
  the helper validates `captured_at` and caps the body at 1 MiB. The kill switch, once unneeded
  because nothing ran unwired, is now the plugin's `/plugin` switch, plus each plugin's enable
  option (`context_usage_hooks_enabled`, `rate_limits_enabled`).
- **MCP servers (2).** None. Each mod registers a read-only `status` tool with `$.tool.register`;
  it is a local tool, not an MCP server, that takes no input and returns the session's figures and
  the guard's verdict as JSON.
- **Consumer config (3).** New: `userConfig` options (eight on context-usage, seven on
  rate-limits), read from settings; none names a path or a program.
- **Cache isolation (4).** Unchanged directories: writes stay in the accepted operator-home
  carve-out (`~/.claude/context-usage/context/<session_id>.json`,
  `~/.claude/rate-limits/rate-limits.json`), created owner-only (directory 0700, file 0600,
  best-effort where the filesystem has no POSIX modes). Setup no longer writes
  `bin/statusline-shim.sh`; its check detects a tee or shim left from an earlier version and
  prints the steps to unwire it, and never edits settings.
- **Data egress (5).** Unchanged: no network call. Telemetry goes only to a sink the consumer sets,
  on the same envelope as before.
- **Provenance & third-party trust (6).** Unchanged: first-party MIT code.
- **Main-thread / PATH (7).** Unchanged; the operator-home `bin/` the shim used is no longer
  written.

**Verdict: ACCEPT.** The new surface is in-process code with the user's permissions, which
ADR 0052 adopts for every mod. Its reach here is bounded: no `tool.check`, one bundled helper per
write, the same files in the same directories. Readers keep the base record's rules: the contract
files are untrusted data, the writer is not authenticated, and no zone or rate-limit verdict
drives a security decision.

### Review record: `plugin-quality` (ACCEPT, 2026-07-24)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review. Data
surfaces named exhaustively, because this plugin READS more than most, and that is its job.

- **Code execution (1).** No hooks, no scripts. Prompt artifacts only (skills, agent, references).
  The `auditor` agent carries Bash and Write, **named honestly**: neither is read-only. Bash is
  justified for `claude plugin validate` and config-resolution probes plus safe fixture
  reproductions; Write is scoped by standing instruction to the evidence-packet directory only
  (the dumb-zone contract needs the agent to persist its own `audit-notes.md` so the main thread
  can stay summary-only, surfaced by the dumb-zone smoke). Its standing instructions forbid mutation
  of the audited plugin, installs, writes outside the packet, and network beyond WebFetch.
  Untrusted-content posture (audited source is data, never instructions) is a standing
  instruction in BOTH the hub skill and the agent, backed by a prompt-injection anti-pattern eval.
  That is an advisory, model-honored defense.
- **MCP servers (2).** None.
- **Consumer config (3).** No `userConfig`. Tracked cascade surface `.claude/plugin-quality.md`
  (+ user-global `~/.claude/plugin-quality.md` and `.local` personal override, a sanctioned operator-home
  read per criterion 4's carve-out), keys documented in the plugin's `reference/config.md`.
- **Cache isolation (4).** Reads that leave the plugin's own directory, each justified: (a) the
  audited plugin's installed source under the plugin cache and its marketplace registration, which
  IS the audit subject; (b) `~/.claude/context-usage/context/<session_id>.json` +
  `~/.claude/context-usage/zones.json`, the context-usage reader contract's documented
  cross-plugin interface, consumed read-only per its inline-floor rule; (c) the documented config
  layers above. Writes: the evidence packet (session-derived data such as hook failures, transcript
  path, tool errors, and contract-lock notes) under `${CLAUDE_PLUGIN_DATA}/evidence/…` with a stated
  30-day retention, and, only on the markdown sinks, the emitted item file at the
  operator-chosen directory. No `../` reach-outs.
- **Data egress (5).** Exactly one network egress: `gh issue create`, gated by an unconditional
  full-draft + target-repo + ACTING-account confirm (no auto-file mode exists; the acting-account
  line exists because one machine can hold multiple GitHub identity domains). WebFetch in the
  auditor agent reaches official docs pages for claim grounding, all read-only GETs. No telemetry.
- **Provenance & third-party trust (6).** First-party (Melodic Software authored), MIT, no
  third-party delegation. The producer/consumer split (audit session never implements fixes in
  the audited repo) bounds the blast radius of a hostile audited plugin to the findings text
  itself, which the draft+confirm gate puts in front of the user before it leaves the machine.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT.** Surfaces 2/7 absent; 1 bounded to an honestly-named agent Bash grant under
standing instructions; 3/4 conform with every cross-boundary read justified where it crosses; 5 is a
single confirm-gated egress plus docs-only WebFetch; 6 first-party with the split as containment.

### Review record: `x` (ACCEPT, 2026-07-24)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review. This is a
**third-party trust delegation**, since the plugin's entire function is routing a URL through converters
operated by others, so surfaces 5 and 6 carry the weight here.

- **Code execution (1). Present, remediated, and the remediation is instruction-level.** No hooks,
  no scripts, no `bin/`; no `eval`, no `curl … | sh`. But the skill does interpolate untrusted input
  into a shell command line: the X URL becomes part of a `curl` request body. A first review draft
  claimed this was not shell interpolation of untrusted input; that claim was **false** and is
  retracted here. An adversarial pass demonstrated the breakout against a real `argv` dump: a URL
  containing an apostrophe terminates the body's quoting and contributes new `argv` words,
  yielding a second unconstrained URL and an `-o` arbitrary-write flag in the receiving process.
  Because `disable-model-invocation` is `false` and the description carries a research trigger, the
  URL can arrive from attacker-authored web content, closing an indirect-injection chain into a
  shell argument.

  Remediation: a mandatory gate ahead of step 1 anchors the input against post/article patterns,
  **refuses** on no match, and on match discards the input entirely and rebuilds the URL from
  captures restricted to `[A-Za-z0-9_]` and `[0-9]`, classes that cannot express a quote, space, or
  metacharacter. Only handle and id are captured: scheme, host, and query string are all discarded
  and re-emitted canonically, so the accepted input set (`http`/`https`, either case, `x.com` or
  `twitter.com`, optionally `www.` or `mobile.`) is wider than the emitted set, which is always one
  `https://x.com/…` URL. Widening what is *accepted* therefore does not widen what is *sent*. Rebuild-from-captures, not escaping, so the emitted command is quote-safe by
  construction. Every URL re-enters the gate, including ones offered at step 3 or surfaced by
  fetched content. Stated honestly: **the gate is model-honored, not runtime-enforced.** It is the
  primary defense, not a guarantee.

  No kill-switch `userConfig` needed: nothing runs unless the skill is invoked, and scope-level
  `enabledPlugins` is the off switch.

- **Tool pre-approval: no shell grant, and the prompt must stay legible.** An earlier draft
  pre-approved `Bash(curl … https://xtomd.com/api/*)` and a PowerShell mirror. **Removed.** A prefix
  rule cannot express "and no further flags": the trailing wildcard admits every appended argument,
  so the grant would have suppressed the prompt on exactly the injected command above. The
  permissions documentation warns against argument-constraining Bash patterns for this reason. The
  network call now prompts, showing the operator the exact command, the only runtime-enforced layer
  available without shipping a hook.

  Review then found that this backstop is only as good as what the prompt *displays*, and that an
  intermediate Windows design had quietly destroyed it. To dodge a PowerShell quoting-portability
  problem, the request had been moved into a curl config file; the prompt then showed
  `curl.exe -q -K <file>`, hiding the destination URL, the `data` reference, any `output` directive,
  and redirect behavior inside a model-authored file no operator approves. Should attacker-authored
  content push the model off the gate, the operator would see nothing dangerous, the control failing
  exactly when it is needed.

  Resolved by **declaring a narrower platform boundary rather than keeping an uninspectable path**:
  the skill ships one bash invocation, requiring Git Bash on Windows, with no PowerShell variant. Every
  PowerShell-portable form either breaks across `$PSNativeCommandArgumentPassing` modes or moves
  request detail out of the prompt. A stated prerequisite is the honest cost; an approval the operator
  cannot read is not. This is the cross-platform contract's declared-narrower-scope allowance, taken
  deliberately and recorded at the coupling site.

  `allowed-tools` retains only `WebFetch(domain:threadreaderapp.com)`, which involves no shell. A
  validating `PreToolUse` hook is the stronger control and is **deferred**, with re-introducing a
  shell grant as its trigger.
- **MCP servers (2).** None. The user's stated growth path includes a future MCP surface; that would
  be a new trust surface and re-triggers this review at that version.
- **Consumer config (3).** No `userConfig`. No credential exists to store, since both providers are
  unauthenticated.
- **Cache isolation (4). One bounded write per invocation.** A first draft claimed "no file reads or
  writes at all"; that was **wrong**, because the skill instructs redirecting the response to a file and
  reading the slice needed, which is a write plus a read carrying third-party content. Retracted and
  corrected: the redirect target is constrained to `${CLAUDE_PLUGIN_DATA}`, explicitly never an
  agent-chosen absolute path and never a path derived from fetched content. Review then found the
  redirect had been written as conditional on the response being a long article, which is unevaluable, since
  an X Article is routinely shared as an ordinary `/status/` link, which would have left the concrete
  documented command streaming an unbounded body to stdout. The redirect is now unconditional, so
  the write happens on every invocation rather than on an unknowable subset, and the file is deleted
  on every exit path. A later round found the spool path was double-quoted, which does not contain
  it: bash expands `$name`, runs a backtick or `$(…)` substitution, and consumes a backslash inside
  double quotes. Verified against a directory named ``lit$name-`whoami`.txt``: the variable expanded
  and the substitution executed. The path is now single-quoted at every shell site. Note the
  asymmetry with
  criterion 1: the *URL* is safe by construction because it is rebuilt from quote-free capture
  classes, but the *plugin-data path* comes from the environment, so it carries whatever the
  consumer's home directory contains and must be escaped rather than trusted. No `${CLAUDE_PLUGIN_ROOT}` references beyond the skill body, no
  consumer-repository reads, no `../` reach-outs.
- **Data egress (5). Present and accepted, conditional on the criterion-1 gate.** Per invocation
  the machine emits one datum: the gate's *rebuilt* URL `https://x.com/<handle>/status/<id>`, to
  `xtomd.com` (step 1) and, only on a chain fragment, `threadreaderapp.com` (step 2). No
  credentials, since neither endpoint takes auth. No repository content, no conversation text, no
  telemetry.

  A first draft asserted this unconditionally; that was **false as built**, because the pre-gate
  request body was attacker-steerable (criterion 1) and could carry `@file` contents or reach an
  attacker-chosen host. The claim is sound only downstream of the gate, and is recorded that way.

  Two residuals stated rather than glossed: rebuilding drops the query string, so `?s=`/`?t=` share
  tracking tokens are **not** transmitted. But the URL itself still identifies both the post and
  the reader's interest in it, and neither vendor publishes a retention policy, so assume every
  submitted URL is logged indefinitely. `--proto '=https'`, `--max-time`, and `--max-filesize` bound
  the transport; no `-L`, so no redirect-driven egress. The byte cap is best-effort rather than
  absolute: before curl 8.4.0 `--max-filesize` does not stop an unknown-length response, so a
  chunked reply can exceed it and `--max-time` is the bound that always holds. When either bound does
  fire it aborts rather than truncating cleanly, and review found the skill would have read the
  partial output: verified against curl 8.19.0, an over-cap transfer prints `200` on stdout while exiting
  `63`, leaving a partial spool whose Markdown prefix passes every content check. The exit status is
  now the first gate, ahead of the HTTP code and the body, and a nonzero exit deletes the spool
  unread. Two further rounds closed the remaining paths by which third-party bytes reach the session:
  success requires exactly `200`, since a non-followed `3xx` completes with exit `0` and a plaintext
  body that no Markdown check can reject; and the spool is read to a **fixed 256 KB cumulative
  ceiling** rather than unconditionally to EOF, because bounded slices cap each tool result but never
  their sum, so a response near the 5 MB cap could exhaust the session before the result was
  reported. The ceiling is a constant rather than a per-invocation budget, since an instruction to
  "set a budget" is satisfied by choosing the response's own size. Both were reachable by a hostile
  or malfunctioning converter, which is the threat this criterion assumes.

  A P1 in the same round corrected an over-application of the escaping above: the shell quoting had
  been extended to the `Read` tool, whose argument is a literal filesystem path that no shell parses.
  Quotes there become part of the filename, so every successful fetch would have failed to open its
  own spool. The path is escaped at the shell sites and raw at `Read`, so one path has two renderings.

  Those bounds are only enforceable because `-q` leads the invocation. Review surfaced that curl
  reads a default `.curlrc` "even when `--config` is used", skipping it only when `--disable` "is
  used as the first parameter on the command line" (curl's own manual, verified against the local
  binary). A consumer's ambient `.curlrc` setting `location` would otherwise re-enable redirect
  following and silently defeat the no-redirect egress claim, an environment-supplied bypass of a
  control this record asserts. The finding predates the removal of the Windows config-file path and
  applied there too.
- **Provenance & third-party trust (6). Present and accepted.** Two vendors, neither first-party:
  - `xtomd.com` publishes a `POST /api/markdown` endpoint under a documented public contract
    (`/llms.txt`, `/llms-full.txt`, and an OpenAPI 3.1.0 document at `/.well-known/openapi.json`),
    unauthenticated and free. **The operating entity is not identified** on the site, and no terms,
    jurisdiction, or retention policy is published, which is material for a trust delegation, and recorded
    as an unknown rather than passed over. Its docs instruct installing an `@xtomd/mcp-server` npm
    package that **does not exist** (registry `404`). That is not merely a documentation-quality
    caveat: the name is unregistered and claimable by anyone, so the vendor's own docs steer users
    into a standing dependency-confusion hazard. The plugin does not wire, install, or reference it,
    and the skill body instructs against hunting for it.
  - `threadreaderapp.com` is a long-running public thread-unroll service, fetched read-only over
    `WebFetch` with no key. Operator likewise not identified on the fetched surfaces; retention
    unstated.

  Both return **attacker-authored content**: X post bodies written by arbitrary third parties. This
  is the prompt-injection vector criterion 2 names, arriving through a different door. Containment
  lives in the skill body: returned bytes are data to report, never instructions, and fetched text
  may never introduce a URL, host, or file path, with dedicated eval coverage including a URL
  harvested from page content. Consistent with the `github`, `dometrain`, and `plugin-quality`
  records, this is **an advisory, model-honored defense, not a runtime-enforced one**; an earlier
  draft called it "mandatory" without that qualifier and is corrected here.

  Two residual risks stated rather than assumed away: a converter could return content that differs
  from the source post, and the plugin cannot detect that. Consumers get attribution and the gate's
  **rebuilt** URL, never the converter-echoed one, so a claim can be checked against the original
  without trusting a value the converter chose. And step 2's escalation is a decision
  made on the shape of step-1 output, which is third-party text; it is constrained to reusing the
  gate-captured id and can therefore change *whether* a second fetch happens, never *where* it goes.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Review history.** A first draft of this record reached ACCEPT on claims that an adversarial
fresh-context pass then falsified: criterion 1's "no shell interpolation of untrusted input",
criterion 4's "no file reads or writes at all", and criterion 5's unconditional no-credential-egress
assertion. The argument-injection breakout was demonstrated at `argv` level in both bash and
PowerShell and independently reproduced before remediation. Each retraction is recorded inline above
rather than silently rewritten, because a review record whose failures are edited out of history
teaches nothing to the next reviewer.

**Verdict: ACCEPT at the remediated state.** Surfaces 2/7 absent; 3 empty. Criterion 1 carries a
real shell-interpolation surface, remediated by a validate-and-rebuild gate whose model-honored
nature is stated rather than glossed, and backed by the deliberate absence of any Bash/PowerShell
pre-approval so the call prompts. Criterion 4 is one write bounded to `${CLAUDE_PLUGIN_DATA}`.
Criteria 5 and 6 are the substance: egress is a single rebuilt, query-stripped, already-public URL
with no credential, and the trust delegation buys a capability with no unauthenticated first-party
alternative. Both vendors are unidentified operators with unstated retention, recorded as a known
unknown rather than waved through, and the untrusted-content risk is contained by advisory instruction
that is labeled advisory.

**Recheck trigger:** a named trigger on an in-repo decision
([upstream-drift](../contracts/upstream-drift/README.md)). Re-introducing a Bash or PowerShell
pre-approval, shipping the deferred validating `PreToolUse` hook, or adding an MCP surface each
re-opens this review.

### Review record: `wizard` (ACCEPT, 2026-08-09)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review. Ported
from mattpocock/skills v1.2.3 (`main@84fdeff`, MIT), hardened; provenance SSOT
`docs/upstream/mattpocock-skills.md`. The weight here is a surface no prior record carries: the
plugin's **product is a model-generated executable**. The statusline-shim delta review (above)
accepted an executable write precisely because it was "a byte-identical copy of a reviewed,
tested, bundled script, with no generation, no templating". This plugin deliberately breaks that
precedent: the skill's whole capability is authoring per-procedure stages onto a bundled
library. That is accepted here as an explicit, recorded exception with the mitigations below,
not a quiet widening of the shim rationale.

- **Code execution (1). The generated-executable surface, accepted with layered conditions.**
  No hooks, no `bin/`, nothing event-wired; the plugin ships prompt artifacts plus one bundled
  bash template. The trust argument for generation, layered:
  - **The agent authors; it never executes.** The skill forbids running the wizard end-to-end
    (verification is `bash -n`/`shellcheck` plus a fresh-context static trace); the human runs
    the script in their own terminal. The template enforces the same doctrine mechanically:
    it aborts without a controlling TTY (`exec 3</dev/tty`, fail-closed), so neither an agent
    nor piped/pasted input can drive its gates.
  - **A human reads before anything is runnable.** The skill's verify step is stop-the-line:
    the full `STAGES` block is printed to the user and explicitly approved BEFORE `chmod +x`
    and before any run instruction. The generated content a human is asked to trust is exactly
    the content they are made to read.
  - **The generated region is bounded.** Model-authored content goes only below the `STAGES`
    marker; the library above it is fixed, reviewed here, and never hand-edited. Stage authoring
    composes reviewed helpers whose dangerous edges are hardened in the library itself:
    https-only `open_url` with the URL printed before dispatch (also closing a Windows UNC/NTLM
    leak via the `explorer.exe` branch); fail-closed `pause`/`confirm` (fatal on read failure,
    never `|| true`); key-name validation in every helper; single-quoted escaped `.env` values,
    `chmod 600` after every write, a gitignore assert, trap-cleaned same-filesystem mktemp;
    gh writes that resolve/echo/confirm the target repo before the first write, pass explicit
    `--repo`, pipe values via stdin (`set_secret` pipe, `set_var --body-file -`), refuse empty
    values, and surface stderr into the closing summary.
- **MCP servers (2).** None.
- **Consumer config (3).** No `userConfig`, no tracked config surface; setup-skill exemption
  recorded in the plugin README ((a)/(b)/(c) all absent for generation itself).
- **Cache isolation (4).** The skill references only its own bundled `template.sh` relatively;
  generated wizards are written into the consumer's project or scratch space at the user's
  direction, which is the deliverable, not a reach-out. No `../`, no constructed absolute paths.
- **Data egress (5).** None by the plugin. The generated script's egress is operator-visible and
  operator-driven: browser opens of https URLs printed before dispatch, and `gh` writes to a
  repo the human explicitly confirmed. Captured values flow terminal → `.env`/`gh` only; the
  closing summary prints names, never values. The skill's scoping step reads key NAMES only from
  a live `.env`, and states honestly that a value pasted into chat is in context.
- **Provenance & third-party trust (6).** Derived from mattpocock/skills (MIT) with the
  hardening deltas recorded in the plugin CHANGELOG; authored/maintained first-party (Melodic
  Software), MIT. No third-party service is wired: `gh` is the consumer's own authenticated CLI,
  optional, degrading to warn + summary when absent.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no plugin `bin/`.

**Verdict: ACCEPT.** Surfaces 2/3/7 absent; 1 is the recorded model-generated-executable
exception, bounded to the below-the-marker region and gated by the mandatory human
read-and-approve before `chmod +x`, with the library's fail-closed hardening as defense in
depth; 4 conforms; 5 is operator-driven with names-only output; 6 first-party over an MIT
upstream. **Conditions shipped, and this ACCEPT depends on all of them:** the human STAGES approval gate,
the agent-never-executes instruction, the TTY-only fail-closed library, https-only `open_url`,
and the hardened `.env`/gh write path. Removing or weakening any of them re-opens this review,
as does any move to have the agent execute a generated wizard.
