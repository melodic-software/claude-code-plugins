# Enablement and distribution

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278. Basis labels: `OBSERVED` /
`SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` / `INFERRED`.

This is the sidecar that decides whether anything else matters. The API is real;
the question is who can run it.

## The gate, read off the shipping binary

```js
var canLoadBuiltinHooksModules = () => !kS() && !Vr("hooks") && !mg();
var HOOKS_MODULES_FLAG          = "tengu_plugin_hooks_modules";
var hooksModulesFlagDefault     = () => !1;                                  // false
var hooksModulesRolloutOn       = () => a.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS
                                        ?? x(HOOKS_MODULES_FLAG, hooksModulesFlagDefault());
var canLoadUserHooksModules     = () => hooksModulesRolloutOn() && canLoadBuiltinHooksModules();
```

`BINARY` · HIGH · names bound in the module's own export map;
`repo-primary/RESEARCH-enablement-and-limits.md`, reproduced independently in
`repo-primary/VERIFICATION.md` rows 6.1–6.6 and in
`community-falsification/VERIFICATION.md` M1.

Reading it:

1. **The default is `false`.** `BINARY` · HIGH
2. **`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is an *override*, not the sole gate.**
   The `??` short-circuits before the gate is consulted. It is settable from
   `settings.json`'s `env` block, not only the shell. `BINARY` · HIGH
3. **Otherwise a server-side GrowthBook gate named `tengu_plugin_hooks_modules`
   decides.** The binary's own provenance strings: *"from a local override"* /
   *"from GrowthBook (this session's payload)"* / *"from GrowthBook (the disk
   cache of an earlier session)"* / *"from the default (GrowthBook is off for
   this session: a third-party provider, or telemetry opted out)"*. The binary
   caches an earlier session's payload to disk, so the gate can stay on across
   restarts. `BINARY` · HIGH
4. Where GrowthBook is off — **"a third-party provider"** or telemetry opted out
   — the gate falls to `false` and only the env var can enable it.
   `BINARY` · HIGH. **Naming that trio Bedrock / Vertex / Foundry is `INFERRED`**,
   interpolated from the 2.1.277 CHANGELOG entry about AGENTS.md, not read from
   this string. `repo-primary/VERIFICATION.md` row 6.5.

**Consequence: activation can happen without user action.** With the variable
unset, a rollout can turn hooks modules on. This is the M1 risk.
`BINARY` · HIGH · `community-falsification/VERIFICATION.md` M1.
Two limits on how far to read it, both visible in the same extract:

- The gate is **necessary, not sufficient**: `canLoadUserHooksModules` also
  requires `canLoadBuiltinHooksModules`, whose three predicates are minified.
- **"Server-side" is inference from the GrowthBook provenance strings, the
  exported `hooksModulesRolloutSource`, and third-party corroboration; the remote
  lookup itself was not observed.** `INFERRED` · HIGH-supported

## The two gates are not the same gate

| | Built-in mods (`diff`, `agents-md`, `sec-default`, `telemetry`) | A plugin you write |
|---|---|---|
| Predicate | `canLoadBuiltinHooksModules()` | `canLoadUserHooksModules()` |
| Rollout gate consulted? | **No** | **Yes** |
| Other conditions | `!kS() && !Vr("hooks") && !mg()` | the same, **plus** the rollout |

`BINARY` · HIGH. This is why AGENTS.md shipped to every user in 2.1.277 while a
user-authored hooks module did not. Confirmed directly by the live-session probe:
`agents-md@builtin` loaded as a hooks module in **both** the flag-set and
flag-unset arms. `OBSERVED` · HIGH · `official-docs-changelog/VERIFICATION.md`.

**What turns a built-in off** is the one part still unresolved. `agents-md`'s
README states *"No hooks setting or CLI mode turns it off (`disableAllHooks`,
`allowManagedHooksOnly` and `--bare` govern settings hooks and installed plugins,
not built-ins)"*, and the supported off-switch is `/plugin`. An earlier inference
mapping the `claude plugin test` refusal string
(*"disableAllHooks, allowManagedHooksOnly or a policy"*) onto
`canLoadBuiltinHooksModules` was **withdrawn** — that string sits on the
user-module path. `SOURCE` · HIGH for the off-switch; the predicate identities
remain unresolved. `repo-primary/RESEARCH-enablement-and-limits.md` (Conflict C4,
Gap G3).

A partial narrowing: the 2.1.277 CHANGELOG parenthetical *"(not yet on Bedrock,
Vertex or Foundry)"* about AGENTS.md is evidence that **a provider predicate sits
inside `canLoadBuiltinHooksModules`**, since that mod does not ride the rollout
gate. `INFERRED` · MEDIUM · `repo-primary/VERIFICATION.md` row 8.8.

## Observed on this machine

```
$ claude plugin test
error: unknown command 'test'
(Did you mean list?)

$ CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude plugin test --help
Usage: claude plugin test [dir]
…
```

Three arms, run with `env -u` as a real control: unset → unknown command;
`=0` → unknown command; `=1` → runs, exit 0. `OBSERVED` · HIGH ·
`official-docs-changelog/VERIFICATION.md` row 4. The subcommand is registered
conditionally on the gate and stays **hidden from `claude plugin --help` even
with the flag set**. `OBSERVED` · HIGH · `community-falsification/VERIFICATION.md`
row 10.

### The live-session load probe

A fresh-context verifier loaded a locally authored, non-marketplace hooks module
via `--plugin-dir` in a real headless session, with three independent evidence
channels. `OBSERVED` · HIGH · `official-docs-changelog/VERIFICATION.md`.

**Flag set →** LOADS:

```
[DEBUG] hooks module verify-probe@inline loaded (worker, environment 1, tier user); events: session.start
[DEBUG] plugin.register: verify-probe (user, verify-probe@inline), judged by core alone: admitted
[DEBUG] $.fs.write (verify-probe): …\markers\marker-fs.txt (48 bytes)
```

A `node:fs` channel in module scope left **no** marker — a hooks module cannot
reach raw `node:fs`; `$` was the only channel that worked.

**Flag unset →** DOES NOT LOAD:

```
[DEBUG] installed plugins' hooks modules not loaded: rollout flag (tengu_plugin_hooks_modules) is off,
        from the default (a cold GrowthBook cache, no payload yet); built-in plugins load regardless
[DEBUG] hooks module verify-probe@inline not loaded: the rollout flag … governs installed plugins
[DEBUG] sec-default@builtin not seated: installed plugins' hooks modules are off in this process
```

exit 0, stdout normal, **stderr carries nothing about plugins**. The plugin is
still discovered and its `hooks.json` still read.

## Silent-inert and silent-active

These are the two operational failure modes, and they are different.

**Silent-inert.** A mod can be installed, enabled, listed by `claude plugin list`
— and never invoked, with no signal anywhere but `--debug`. The one substantial
independent migration report (Practical Systems, 2026-09-17, Windows,
2.1.273/2.1.274) puts it plainly: *"Claude Code never calls `register()`. No
handlers, no commands, nothing"* and *"`claude plugin list` is telling the truth
and the truth is useless, because nothing in that output distinguishes a plugin
that ran from a plugin that was never invoked."* Cause in that case: the env var
was exported in one terminal only. `COMMUNITY` · HIGH, corroborated `OBSERVED` ·
`community-falsification/RESEARCH-field-evidence.md`.

The same report carries two secondary lessons worth copying: an exact-match
version canary *"red most of the time is one you learn to scroll past"*, and a
guard silently disarmed when `\b` became a literal backspace — caught only by a
test suite asserting **denials**. `COMMUNITY` · HIGH.

**Silent-active.** Because the env var is only an override, an *unset* variable
is not a guarantee of inert: the rollout gate decides. A mod can activate on a
path nobody tested. `BINARY` · HIGH · `community-falsification/VERIFICATION.md` M1.

Two independent third-party adopters already defend against exactly this:
`kunchenguid/firstmate` and `kunchenguid/compact-adviser` both state in their own
`hooks.json` that the module *"may load through CLAUDE_CODE_ENABLE_FUNCTION_HOOKS
or tengu_plugin_hooks_modules, but activates only when
CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is exactly 1 and is otherwise a complete
no-op."* `COMMUNITY` · HIGH.

**Ship-blocking recommendation carried from that lane:** any mod published from
this repo should be inert unless the env var is exactly `1`, and should emit a
liveness signal naming the deciding gate. The binary already exposes which gate
decided (`hooksModulesRolloutSource`). `COMMUNITY` `BINARY` · HIGH.

## Versions

- **No minimum version is stated by any official source.** `OBSERVED` · HIGH
- Staff named versions only as snapshots: *"a cheat sheet reference that
  enumerates some affordances on v267/v268 (today / tomorrow)"*, and a `mods/`
  commit message *"the declarations are 2.1.273's"*. Neither is a floor.
  `STAFF` · HIGH
- Community floors, all third-party and uncorroborated: aitmpl.com `>= 2.1.259`;
  `halluton/Mindful-Claude` "2.1.269 or later"; wavect.io names 2.1.273 as the
  version its inspected declarations identify, **not** a floor. claudefa.st
  states no floor. `COMMUNITY` · the earlier report of a "conflict" between two
  floors was **WRONG**: only one floor claim exists.
  `community-falsification/VERIFICATION.md` row 8.
- Earliest evidence of hooks modules actually loading: independent bug reporters
  on **2.1.263**. A third-party reverse-engineered changelog separately dates the
  **test runner** as absent in 2.1.270 and present in 2.1.271, so `claude plugin
  test` appears to arrive later than the module loader. `COMMUNITY` · MEDIUM
- Verified working here: **2.1.278**. `OBSERVED` · HIGH
- **Do not adopt a floor from these sources. Pin empirically.**

## Distribution

- **Anthropic's own mods are not marketplace-listed:** *"They are not listed in
  this repository's marketplace; the copies that matter are the ones already in
  your Claude Code."* `SOURCE` · HIGH
- A working third-party mod installs through the **existing** commands —
  `claude plugin marketplace add`, `claude plugin install`. **This install path
  comes from one community source (`halluton/Mindful-Claude`'s README), not from
  staff.** A case-insensitive grep of all 203 comments in #91870 for
  `marketplace | plugin install | plugin add | --plugin-dir` returned one false
  positive. `COMMUNITY` · HIGH · `x-threads/VERIFICATION.md` row 3.
- Staff corroborate only the hedged **intent** that packaging is unchanged:
  *"To the extent possible, we are intending function hooks to cleanly integrate
  with plugins as they exist today, as a new type of hook. Therefore
  dependencies, versions, etc. will all go unchanged."* `STAFF` · HIGH
- **No signing, no version pinning change, no new review gate.** The question was
  asked directly and answered with "unchanged". `STAFF` · HIGH ·
  `community-falsification/RESEARCH-security-supply-chain.md`
- Seven genuine third-party adopter repos ship hooks modules with tests, plus a
  distributed mods component library with an `npx` installer
  (`davila7/claude-code-templates`). `COMMUNITY` · HIGH ·
  `community-falsification/VERIFICATION.md` row 7.

**Net:** a published plugin depending on function hooks is not
installable-and-working for a normal user today, and no user action other than
setting an undocumented env var per process changes that.

## Documentation and changelog silence

| Corpus | Result | Basis |
|---|---|---|
| `code.claude.com/docs` — **all 197 English pages** via `llms-full.txt` (9,590,632 bytes) | **0 hits** for `function hook`, `hooks module`, `plugin-types`, `prependPlugins`, `appendPlugins`, `engine.create`, `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`, `sec-default`, `next.to(`, `"modules"` | `OBSERVED` HIGH |
| `CHANGELOG.md` at `main`, 7,158 lines, `## 2.1.278` … `## 0.2.21` | **0 hits** for the same terms, and word-bounded `mods?` → 0 | `OBSERVED` HIGH |
| Anthropic / Claude blog surfaces | nothing | `OBSERVED` HIGH |

`official-docs-changelog/VERIFICATION.md` rows 1–2, re-confirmed independently in
`surfaces-desktop/VERIFICATION.md` row 7 (which **upgraded** the docs half from
MEDIUM to HIGH because the full corpus, not the curated index, was grepped).

One disclosure to avoid a false precision claim: bare `plugin test` appears
**once** in `llms-full.txt`, as the English word *testing* on the
`plugin-marketplaces` page; `claude plugin test` → 0. Live controls in the same
file (`plugin-dir` 67, `CLAUDE_CODE_ENABLE_TELEMETRY` 24) prove the sweep works.

**The pattern, not an oversight:** `/diff` (2.1.260) and AGENTS.md (2.1.277) are
documented *features* whose implementations are mods. Anthropic ships the
feature, documents the feature, and never names the mechanism. A readiness check
based on `claude plugin --help` or on the docs returns a **false negative**.

The only Anthropic-authored artifacts carrying substantive content:

| URL | What it carries |
|---|---|
| `github.com/anthropics/claude-code/blob/main/mods/README.md` | Definition, the four mods and their seating, the testing kit, noun contracts, the early-access statement. ~6.3 KB. |
| `github.com/anthropics/claude-code/tree/main/mods` | The source of all four mods, `types/`, `tsconfig.json`. |
| `github.com/anthropics/claude-code/issues/91870` | Roadmap, product naming, the public env-var acknowledgement, an active bug-fix loop. Author badge `CONTRIBUTOR`. |
| The architecture PDF attached to #91870 | 10 pages, byline "Alice Poteat · August 2026 · Anthropic". See `architecture-pdf/`. |
