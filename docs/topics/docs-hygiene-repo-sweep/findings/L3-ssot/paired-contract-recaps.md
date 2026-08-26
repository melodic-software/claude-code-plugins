# Cluster family: paired-contract-recaps (N=2 bucket)

Six clusters where exactly two files assert the same contract and neither is declared canonical.
Under the sweep's rule-of-one policy these are remedied in place. **None creates a new artifact.**

The N=2 bucket's defect is bifurcation risk: with no declared owner, the two copies drift and a
reader cannot tell which is authoritative. Where the two have already drifted, the remedy is
`name-an-owner` plus `normalize-wording`; where they are still byte-identical, `name-an-owner`
alone is enough to stop the drift before it starts.

Ranked by exposure, worst first.

---

## P1: `statusline-shim-durable-wiring` (ALREADY DRIFTED, highest exposure)

**Files.** `plugins/context-guard/skills/setup/SKILL.md` and
`plugins/rate-limit-guard/skills/setup/SKILL.md`.

**Extent.** 16 shared blocks totaling 764 words, the largest N=2 overlap in the corpus outside the
telemetry cluster.

**Declared owner.** None. Neither file references the other; neither names a canonical text.

**Verbatim, both files** (`plugins/context-guard/skills/setup/SKILL.md:19`,
`plugins/rate-limit-guard/skills/setup/SKILL.md:49`):

> **Why the shim exists (the durable-wiring rule).** `${CLAUDE_PLUGIN_ROOT}` is version-pinned and
> changes on every plugin update, and the old version directory is pruned about 14 days later
> (plugins reference, "Plugin cache and file access"). A statusline wired straight to
> `<plugin-root>/scripts/statusline-tee.sh` therefore stops teeing at the next version bump and, once
> the old directory is pruned, `bash <missing-path>` exits 127 and takes the operator's WHOLE
> statusline down with it. So the operator wires the **shim**, never the tee: the shim lives at a

Further shared blocks (first lines, with sites):

| Words | First line | Sites |
|---|---|---|
| 99 | `**Why the shim exists (the durable-wiring rule).** ...` | context-guard:19, rate-limit-guard:49 |
| 92 | `result (a no-op on Windows ACL volumes; the wiring invokes it through bash anyway)` | context-guard:381, rate-limit-guard:253 |
| 83 | `deleting the directory while the wiring still names the shim leaves settings.json invoking a` | context-guard:449, rate-limit-guard:281 |
| 81 | `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh (the installed copy is byte-identical by` | context-guard:44, rate-limit-guard:72 |
| 74 | `Windows note: the command must run under Git Bash. bash is invoked explicitly for exactly` | context-guard:360, rate-limit-guard:237 |

A further shared block sits in the two READMEs
(`plugins/context-guard/README.md:88`, `plugins/rate-limit-guard/README.md:60`, 92 words,
beginning `statusline edit (wrapping your existing command, or standalone) for you to apply. The
plugin`).

**Evidence of live drift.** The scripts these two skills document are no longer identical:

```text
220ba0b7792935f5389ecc42f0b47686  plugins/context-guard/scripts/statusline-shim.sh
5ea9e869da9affd461c21e61ff6e717e  plugins/rate-limit-guard/scripts/statusline-shim.sh```

Some of that difference is legitimate (each plugin tees a different payload). What is not
legitimate is that the prose describing the *shared* durable-wiring mechanic has no owner and no
guard, while the code it describes has already diverged.

**No guard covers this.** `scripts/cross-plugin-source-registry.txt` registers
`hooks/hook-utils.sh`, `reference/artifact-protocol.md`, `reference/standards-contract.md`,
`lib/managed-scope.sh`, and `lib/state-key.sh`. It does not register
`scripts/statusline-shim.sh`, and `scripts/check-cross-plugin-source-drift.sh` skips `SKILL.md`
by design (`skip_basenames=(SKILL.md plugin.json README.md CHANGELOG.md ...)`), so the prose is
outside every existing check.

**Remedy: `name-an-owner`.**

`rate-limit-guard` is the better owner. It is the plugin whose statusline tee is the primary
consumer surface, and its `reference/reader-contract.md` is already the cited provenance for the
rate-limit floor that three other skills inline.

1. Declare the canonical text in `plugins/rate-limit-guard/skills/setup/SKILL.md`. Add immediately
   before the `**Why the shim exists (the durable-wiring rule).**` paragraph at line 49:

```text
The durable-wiring rule below is the canonical statement for every plugin in this fleet that wires
a statusline shim. A sibling plugin carrying the same mechanic carries this text byte-identical and
varies only the plugin name and tee payload.```

2. In `plugins/context-guard/skills/setup/SKILL.md`, add immediately before the same paragraph at
   line 19:

```text
The durable-wiring rule below is inlined **verbatim** from its canonical statement
(`plugins/rate-limit-guard/skills/setup/SKILL.md` "Why the shim exists (the durable-wiring rule)"
in the marketplace repository), cited for provenance only, since an installed plugin cannot read a
sibling plugin's files at runtime. Only the plugin name and the tee payload vary.```

3. Bring the five shared blocks to byte-identity, taking the `rate-limit-guard` wording where they
   differ. Apply the same treatment to the README pair, naming
   `plugins/rate-limit-guard/README.md` canonical.

4. `code-extract-advisory`: propose registering the shim-script pair for a dedicated drift check in
   the family of `scripts/sync-hook-utils.sh`, or record in
   `scripts/cross-plugin-source-registry.txt` that the two shims are deliberately non-identical and
   why. Out of scope for a docs sweep; recorded so the reconciliation can route it.

**ROI.** HIGH.

---

## P2: `loop-lane-usage-sample-framing`

**Files.** `plugins/source-control/skills/babysit-loop/SKILL.md:399` and
`plugins/work-items/skills/work-loop/SKILL.md:156`.

**Extent.** 407 words across 2 blocks.

**Verbatim, both** (`plugins/source-control/skills/babysit-loop/SKILL.md:399`):

> covering the interval *preceding* its reporting cycle, and the three properties bounding what the
> data supports, is the convention's (§4, "Per-cycle usage sample"), held by citation.

**Verdict.** The larger of the two blocks is the `## Rate-limit guard floor (inlined)` section,
which is deliberate and correctly declared. See `refused-deliberate-duplication.md` cluster R6.
The residual is the framing sentence above, which already cites the loop-lane convention §4 by
heading. Identify form (d).

`REFUSE-already-cites-canonical`. Rostered so the reconciliation does not re-open it after seeing
the 407-word overlap in a mechanical report.

---

## P3: `toolchain-remote-resolution-snippet`

**Files.** `plugins/toolchain/skills/check/SKILL.md:66` and
`plugins/toolchain/skills/lint/SKILL.md:74`.

**Extent.** 117 words, one byte-identical `bash` fenced block, same plugin.

**Verbatim, both:**

```bash
REMOTE="" DEFAULT_BRANCH=""
TRACKED=$(git config "branch.$(git branch --show-current | tr -d '\r').remote" 2>/dev/null | tr -d '\r')
[[ "$TRACKED" == "." ]] && TRACKED=""
CANDIDATES=$( { [[ -n "$TRACKED" ]] && echo "$TRACKED"; git remote | grep -qx origin && echo origin; git remote; } | awk 'NF && !seen[$0]++' )```

**Declared owner.** None.

**Remedy: `name-an-owner`, with a code escape-hatch flag.**

The two skills are in one plugin, so a `reference/` file inside that plugin is reachable from both
at runtime. Recommended shape:

1. Move the block to `plugins/toolchain/reference/remote-resolution.md` under an H2
   `## Resolving the remote and default branch`. This is `edit-existing-rule` territory only if
   such a reference already exists; at time of audit `plugins/toolchain/` has no `reference/`
   directory, so this would be a **new file**. The Rule of Three is not met (N=2), so **this
   option is refused** under the sweep's standing rule.
2. Therefore: declare `plugins/toolchain/skills/check/SKILL.md` canonical (the check skill is the
   read-only one and the lint skill invokes the same probe) and add to
   `plugins/toolchain/skills/lint/SKILL.md` immediately above the fence at line 72:

```text
The block below is inlined **verbatim** from `SKILL.md` of `/toolchain:check`
("Resolving the remote and default branch"), cited for provenance only. A second wording is a
second contract.```

That requires the heading to exist in the check skill. If `check` does not carry an H2 over that
block, add one reading exactly `### Resolving the remote and default branch` and cite that.

3. `code-extract-advisory`: the honest answer is that this is a shell function wanting a shared
   script under `plugins/toolchain/scripts/`, where the language-native mechanism (`source`) would
   dedup it for real. Flagged, not prescribed. Markdown-side, the citation is what is available.

**ROI.** MEDIUM.

---

## P4: `prototype-throwaway-constraints`

**Files.** `plugins/prototype/skills/explore-directions/SKILL.md:101` and
`plugins/prototype/skills/pressure-test/SKILL.md:79`.

**Extent.** 69 words, byte-identical, same plugin.

**Verbatim, both:**

> - **Synthetic data only.** A throwaway prototype binds synthetic data, never real or captured
>   values.
> - **No remote fetch by construction.** Vendor everything inline so the page opens straight from
>   `file://`. No external scripts, fonts, or data fetches. Enforce this rather than trusting it:
>   emit a restrictive CSP meta tag in the page `<head>` so the browser blocks any remote resource:

**Declared owner.** None.

**Remedy: `name-an-owner`.** These are safety constraints, which is the class where a second
wording is most costly. Declare `plugins/prototype/skills/explore-directions/SKILL.md` canonical
(it is the entry skill; `pressure-test` runs against what it produced) and add to
`plugins/prototype/skills/pressure-test/SKILL.md` immediately above the bullet list at line 78:

```text
The throwaway-prototype constraints below are inlined **verbatim** from their canonical statement
in `/prototype:explore-directions`, cited for provenance only. A second wording is a second
contract.```

If `plugins/prototype/README.md` carries a section stating these constraints, prefer that as owner
instead: a plugin-root README is reachable from both skills and is the more natural home for a
plugin-wide safety rule. Confirm at apply time.

**ROI.** MEDIUM. Small text, high consequence class.

---

## P5: `github-read-only-posture`

**Files.** `plugins/github/skills/advise/SKILL.md` and `plugins/github/skills/audit/SKILL.md`.

**Extent.** 293 words across 4 blocks, same plugin.

**Verbatim, both** (`plugins/github/skills/advise/SKILL.md:80`,
`plugins/github/skills/audit/SKILL.md:83`):

> A bare invocation of this skill performs zero mutations, stated in write-capability terms:
>
> - No `gh api` call carries `-f`/`-F`/`--field`/`--raw-field`/`--input`, except `gh api graphql`,
>   where field flags supply the query document and variables.
> - No `--method`/`-X` with any value other than `GET`.

Other shared blocks: `plugins/github/skills/advise/SKILL.md:92` /
`plugins/github/skills/audit/SKILL.md:95` (90 words, browser-automation offer), and
`plugins/github/skills/advise/SKILL.md:104` / `plugins/github/skills/audit/SKILL.md:107`
(73 words, untrusted-content spine).

**Verdict, split.**

- The untrusted-content block is **refused**: `docs/conventions/untrusted-content/README.md`
  "The inline form adopters carry" mandates it be carried inline at every adopting site. See
  `refused-deliberate-duplication.md` cluster R5.
- The read-only posture and the browser-automation offer have no declared owner and are not covered
  by that convention.

**Remedy for the two uncovered blocks: `name-an-owner`.** `plugins/github/reference/` already
exists and holds `change-routing.md` and `browser-automation.md`, both reachable from both skills at
runtime. The browser-automation block should cite `plugins/github/reference/browser-automation.md`
by heading rather than restating it. Confirm at apply time which heading covers the offer ladder,
then replace the restatement at both sites with:

```text
When the method ladder lands on a UI-only surface, the browser-automation offer follows
[`reference/browser-automation.md`](../../reference/browser-automation.md) "<exact heading>".```

For the read-only posture, declare `plugins/github/skills/audit/SKILL.md` canonical (the audit skill
is the one whose whole contract is read-only) and add the provenance line to
`plugins/github/skills/advise/SKILL.md:80`.

**ROI.** MEDIUM.

---

## P6: `marketplace-bootstrap-placeholders`

**Files.** `plugins/dometrain/skills/setup/SKILL.md:73` and
`plugins/miro/skills/setup/SKILL.md:59`.

**Extent.** 261 words across 5 blocks, byte-identical, two different plugins.

**Verbatim, both:**

> Both placeholders are bootstrap inputs, not lookups: before the first install there is no record
> to read them from. `<marketplace>` is the name the catalog registers under when it is added, and
> `<scope>` is the scope the bootstrap chooses: `user`, `project`, or `local`. `marketplace add`
> and `install` default to `user` when the flag is omitted, while `enable` auto-detects. Carry the
> same `<scope>` through all three. Note the asymmetry: `marketplace add` spells it `--scope` only,
> while `install` and `enable` also accept the `-s` short form.

**Declared owner.** None in either file.

**Owner that should be cited.** `docs/PLUGIN-PHILOSOPHY.md` `## Configuration ownership and scope`
covers `userConfig` but not the marketplace bootstrap asymmetry. `docs/MIGRATION-PLAYBOOK.md`
carries adjacent material at lines 1362 and 1417. Neither states this rule.

**Remedy: `edit-existing-rule` plus `normalize-wording`.** The `--scope` versus `-s` asymmetry is an
empirical claim about the CLI, exactly the class `context/lessons.md` "Lesson 12" says must not be
silently canonicalized. Two steps:

1. Verify the asymmetry against the current CLI before touching either file. If it still holds,
   add it to `docs/PLUGIN-PHILOSOPHY.md` under `## Setup is explicit and repeatable`, stamped with
   the CLI version verified against, in the same form the file already uses for the
   `already installed` claim.
2. Keep the operable text inline at both sites (portability) and add a provenance-only citation to
   the new clause in each.

**ROI.** LOW-MEDIUM. Only two sites, but the claim is empirical and unversioned in both, which is
the failure mode Lesson 12 exists to prevent.

---

## Cross-lane observations

- P3 and P5 both propose citations across skills within one plugin. Whether a `SKILL.md` may cite a
  sibling skill's `SKILL.md` by heading, versus routing through a plugin-level `reference/` file, is
  an encapsulation question. L4 owns it. Where P5 can route to
  `plugins/github/reference/browser-automation.md` instead, it should.
- P1 proposes a cross-plugin provenance citation naming another plugin's `skills/setup/SKILL.md`.
  Same question, flagged for L4.
