# L1-derivability — `J-toolchain-platform`

137 files. `actionlint`, `bash-format`, `biome-format`, `computer-use`, `desktop-notification`,
`eol-normalizer`, `go-format`, `instruction-placement`, `kindle-dedrm`, `machine-health`,
`mcp-tools`, `playwright`, `plugin-quality`, `powershell-format`, `ruff-format`, `skill-quality`,
`toolchain`, `wizard`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 129 |
| `out-of-scope: functional artifact` | 8 |

No deletions, no pointer conversions, no cache verdicts.

Roll-up for the 129 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs and plugin READMEs. The dominant content class is external-tool behavior (formatter and
linter invocation contracts, Windows cmdlet and elevation semantics, MCP server discovery), which is
external-fact ownership by definition: the repository does not contain `shfmt`, `ruff`, Biome,
PSScriptAnalyzer, or the Windows API. Eight files are functional artifacts
(`plugins/machine-health/skills/audit/tests/fixtures/windows/**` and the `**/evals/fixtures/**`
trees) and take no verdict.

## Four files checked closely and kept

**The four `NOT_IMPLEMENTED.md` files** (`references/linux/`, `references/macos/`,
`scripts/linux/`, `scripts/macos/` under `plugins/machine-health/skills/audit/`) read like
placeholders and are not. Each owns a runtime constraint plus a removal condition. From
`plugins/machine-health/skills/audit/scripts/linux/NOT_IMPLEMENTED.md`:

> **Do not attempt to execute any script from `scripts/windows/` on Linux.** Those scripts call
> Windows-only cmdlets and fail noisily.

and

> **Never assume sudo.** Elevation-required checks return `UNKNOWN` with `needs_admin: true`. No
> interactive prompts, no `sudo -n` (can still prompt under certain policies).

and the exit condition:

> Remove this file once the folder has a working orchestrator and all eight seeded checks have Linux
> analogs (or explicit "not applicable" decisions).

A safety constraint plus a recorded removal trigger. `keep-owns-facts` on all four.

**`plugins/machine-health/skills/audit/TODO.md`** is `keep-owns-facts` despite its misleading name.
Lines 3-5:

> **This file holds no state and owns no policy.** Approval state lives at
> `<StateBase>/state/approvals.json` (machine-local, under the plugin data directory). Runtime
> proposals accumulate in `<StateBase>/TODO.md`, not here.

The negative claim is the owned fact: it stops an agent from writing approval state into the skill
directory, a mistake the filename actively invites. The rest of the file is already a pointer, so no
conversion is needed.

**`plugins/machine-health/skills/audit/README.md`** is `keep-owns-facts` and carries an L5 route.
It owns architecture rationale that no file states ("Adding a new OS should be 'populate two
folders,' not 'refactor the skill'") and the dual-invocation contract for check scripts. Its
`## What's here` block at lines 8-25, however, is a hand-maintained ASCII directory tree, which is
the one genuinely derivable, genuinely high-drift block found in this group. Route the tree to
`audit-noise`; keep the file.

**`plugins/firecrawl/skills/update/UPSTREAM.md`** is out-of-scope, a functional artifact. Its own
first two lines:

> `<!-- firecrawl update state — do not edit by hand. -->`
> `<!-- Written by the skill's scripts/update.sh --apply. -->`

Machine-written state that the update action reads, not prose a reader learns from.

## Cross-lane observations

- L3-ssot: `plugins/context7/skills/lookup/context/update.md:20-27` enumerates what its sibling
  `scripts/update.sh` does, and the script's own header at lines 3-16 owns modes and exit codes. The
  doc keeps (it owns the "this plugin OWNS its skill surface, upstream is advisory" policy), but the
  enumeration is a restatement.
- A counter-example worth preserving as the house pattern:
  `plugins/claude-ops/skills/lanes/context/restart-consumer.md:4-7` states outright that "The
  executable contract … lives in the `--help` header of `scripts/restart-consumer.sh`; this file is
  the operator- and reviewer-facing rationale, not a copy of it." That is the shape that makes a
  script-adjacent doc non-derivable on purpose.
