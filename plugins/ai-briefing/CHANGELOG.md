# Changelog

All notable changes to the `ai-briefing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.16]

### Changed

- **Authoring-doctrine pass over `README.md`, `skills/generate/references/build-pipeline.md`, `skills/generate/references/slide-generation.md`.** Fixed pointers and cross-references that did not resolve; sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.7.15]

### Changed

- **Comment-residue cleanup (`/code-tidying:audit-comment-residue`).** History narration, plan/session references, and stale back-references in code comments rewritten as present-tense rationale or removed. Comment-only, no behavior change.

## [0.7.14]

### Changed

- **Comment triage pass (`/code-tidying:dissolve-comments`).** Removed zero-information comments
  in the `generate` skill's build pipeline (`run.js`, `emit-slides-data.js`, `lib/emit-slides.js`,
  `validate.js`): flow narration and call-site labels that restated the adjacent code. No behavior
  change.

## [0.7.13]

### Fixed

- **ASCII `->` window headers rendered a nonsense date range on the slides (#3364).**
  `emit-slides-data.js` parsed the briefing header window with
  `([0-9T:Z\-]+)\s*[→-]+\s*([0-9T:Z\-]+)`. That separator class matches `-` but not `>`, so
  on the ASCII spelling the engine backtracked and satisfied the split INSIDE the first
  timestamp: `2026-04-24T19:00:00Z -> 2026-05-05T20:30:00Z` parsed as `2026-04` and
  `24T19:00:00Z`, and `formatWindow` rendered garbage. The parse now anchors each endpoint on
  a full `YYYY-MM-DD` shape, which makes the mid-timestamp split structurally impossible
  rather than dependent on backtracking order, and accepts `→`, `->`, an en/em dash, and a
  bare hyphen as separators. Parsing and rendering moved to `lib/window.js` so they are unit
  testable; `emit-slides-data.js` runs `main()` on import and could not be exercised directly.

## [0.7.12]

### Changed

- **Long reference files carry a `## Contents` index.** 1 reference file in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.7.11]

### Changed

- **`generate`'s trailing `## References` list is a `Reference index. Load on demand` table.** Each
  row states the load condition rather than only the spoke's contents, so a reading agent can
  decide whether to spend the context without opening the file. The index also named a `--format`
  value the skill does not accept (`pptx`, which is an artifact of the `slides` path, not a flag
  value); it now names the real ones. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.7.10]

### Changed

- **generate: four run invariants now live in `SKILL.md` (docs-hygiene repo sweep, L1-derivability).**
  `## Default run` step 3 sets an explicit timeout on every outbound request and keeps partial
  failures visible. Step 7 requires every requested provider bucket to appear in the markdown
  briefing even when the window produced no items for it, orders the seen-item registry write
  after successful markdown emission, and states that re-running the same window is idempotent by
  the same normalized event identity step 5 deduplicates on. Three of the four existed only in
  `context/execution-flow.md`, which nothing loaded, so the behaviour they describe was unreachable
  doctrine. The fourth was half-present: `SKILL.md` already said partial collection stays visible,
  but not that outbound requests carry an explicit timeout.

### Removed

- **generate: `context/execution-flow.md`.** A second, unsynchronized copy of the run procedure
  that no routing table, reference list, or script cited, and that no gate compared against
  `SKILL.md`. A fresh-context spot-test found four rules with no counterpart anywhere in the skill;
  those were folded into `SKILL.md` before the file went, and the rest was already stated there.
  The `context/` directory held nothing else and was removed with it.

## [0.7.9]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Removed the dead
  `collectLinks()` helper from `output/build/lib/parse-briefing.js` (defined, never called);
  removed a false sentence from `output/build/lib/emit-slides.js`'s `balanceTiers` doc comment
  that described a nonexistent explicit-tier-marker override; deduplicated `output/build/validate.js`'s
  twice-inlined render-settle and section-overflow-scan snippets into shared `settleRender` and
  `collectSectionOverflows` helpers passed to `page.evaluate`, and corrected its stale
  `Screenshots:` summary line to name the `section-*.png` / `responsive-*.png` files it actually
  writes. No artifact bytes, exit codes, or contracts changed; suite 35/35 green, plus an
  independent refutation pass with a live Playwright smoke of the serialized helpers.

## [0.7.8]

### Changed

- **Instruction-surface de-slop (#2891, ai-briefing cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.
  The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.7.7]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.7.6]

### Added

- **`generate`: assert the link-skip predicate is wired, not merely truthy (#3110).**
  Gate 4 hands `shouldSkipLinkCheck` to linkinator's `linksToSkip`, which awaits
  it. A predicate resolving to something merely truthy, or answering the same way
  for every input, would make linkinator skip every URL and the validator report
  success having checked nothing — and no existing test distinguished "checked
  and passed" from "skipped everything and passed". The suite now asserts strict
  boolean resolution and that the verdicts differ by input.

### Changed

- **`generate`: the IPv4 registry claim is dated (#3110).** `url-policy.js`
  described its non-global IPv4 block list as "complete against the registry";
  IANA can add a row, so the comment now names the date the registry was
  fetched. Comment only — no behavior change.

## [0.7.5]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). `apply` also
  now separates the write from its effect: the stored value changes immediately, but the running
  session's hooks keep the `CLAUDE_PLUGIN_OPTION_*` they were handed at session start, so
  verification means rerunning `check` in a FRESH session — a same-session rerun reports the old
  value, which is not a failed write. It never asserts an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.7.4]

### Changed

- **`generate`: the two external-renderer fallbacks name the Skill tool (#3002).** In
  `references/slide-generation.md`, the `/document-skills:pptx` and
  `/frontend-design:frontend-design` invocations now say "via the Skill tool". Wording only — the
  in-tree-builder-first order and the presence gates are unchanged. Follows the invocation-mode
  rubric's cross-skill phrasing rule, now unconditional after the fleet sweep.

## [0.7.3]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.7.2]

### Added

- **`generate` gains a public test entry surface (#2701).** The new `scripts/run-tests.sh` facade
  (`install`/`test`/`all`) delegates into the private `output/build/` npm package; CI and repo
  docs now invoke the facade instead of running npm directly inside the private subdirectory.
  The build package itself is unchanged.

## [0.7.1]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.7.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.3]

### Security

- **Source-URL schemes are allowlisted at every deck sink.** A shared
  `lib/url-policy.js` seam now exposes `isAllowedUrlScheme`, reused at schema
  validation and at each href/hyperlink sink. `http:`, `https:`, `mailto:`, and
  `tel:` — the schemes a legitimate briefing may contain, inert at every sink —
  are preserved and continue to render as working links. **Every other scheme is
  now rejected**: the `javascript:`, `data:`, and `file:` attack vectors that
  could inject script into the HTML deck or embed a local-file hyperlink in the
  PPTX, and — as deliberate fail-closed hardening — rarer schemes such as `ftp:`
  that the previous permissive `z.string().url()` accepted. Two layers: the Zod
  schema hard-fails a deck containing a disallowed scheme (loud fail-closed on an
  attack indicator), and the HTML and PPTX builders drop the individual unsafe
  link (defense-in-depth on the `--skip-emit` rebuild path).
- **Link-reachability checks refuse non-global hosts (SSRF guard).**
  `shouldSkipLinkCheck` now skips URLs whose literal host falls in any
  non-global block of the IANA special-purpose registries, not just RFC1918:
  loopback, private, link-local, shared address space (CGN), benchmarking,
  documentation TEST-NETs, IETF protocol assignments, multicast, and reserved
  (127/8, 10/8, 100.64/10, 172.16/12, 192.168/16, 169.254/16, 0/8, 192.0.0/24,
  192.0.2/24, 198.18/15, 198.51.100/24, 203.0.113/24, 192.88.99/24 deprecated
  6to4 relay anycast, 224/4, 240/4,
  `localhost`/`*.localhost`) — the IPv4 list is complete against the registry;
  the only rows omitted are those it marks globally reachable (the AS112, AMT,
  PCP and TURN anycast assignments). A deny list is the correct shape for IPv4,
  unlike IPv6 below: global unicast is not one prefix but 1.0.0.0 through
  223.255.255.255 minus the carve-outs, so the two ends are handled by range and
  the middle needs the registry's blocks enumerated either way. Matching relies
  on WHATWG URL canonicalization of
  decimal/hex/octal/integer IPv4. IPv6 is judged by ALLOWLIST rather than by an
  enumerated deny list: only globally reachable unicast space (`2000::/3`)
  survives, and the IANA IPv6 Special-Purpose Address Registry's non-global
  blocks inside it are carved back out (`2001::/23` IETF protocol assignments —
  Teredo, benchmarking `2001:2::/48`, ORCHIDv2, AMT and the anycast singletons —
  plus `2001:db8::/32` and `3fff::/20` documentation and `2002::/16` 6to4, which
  wraps an arbitrary IPv4 tunnel endpoint). So `::`/`::1`, `fc00::/7`,
  `fe80::/10`, `ff00::/8`, `100::/64`, `100:0:0:1::/64`, `5f00::/16` and every
  unassigned or newly registered block are refused by default rather than read
  as public — closing the class of bypass a deny list reopens each time a
  prefix nobody enumerated turns out to be routable. RFC 8215's local-use
  translation prefix `64:ff9b:1::/48` is refused outright, while IPv4-mapped and
  NAT64 `64:ff9b::/96` forms are judged by their embedded IPv4 address. Literal
  parsing also accepts RFC 4291 form 3 (a trailing dotted quad), which a
  resolver can answer with and which reading as hex silently misread
  (`192.168.1.1` as `0x192`). A DNS-name
  host is additionally resolved at gate time (every A/AAAA record) and refused
  when ANY resolved address is non-global, so a hostname whose record points
  at, e.g., the cloud metadata address is never handed to the checker; an
  unresolvable or unreadable answer fails closed. Residual: the checker
  performs its own resolution at fetch time, so a rebind between this gate and
  the fetch, or a redirect hop to a private target inside the checker, remains
  outside this gate.

## [0.6.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  applied to the other affected plugins in this release wave.

## [0.6.1]

### Changed

- **Setup now documents how to change `active_profile`, not only how it is read.** The skill
  resolved the key and reported the profile path, but named no route to a different stored value,
  so a consumer whose configured profile was wrong for the repository had nothing to act on and the
  `--profile` override looked like the only lever. `check` step 1 now names all three: the
  interactive `/plugin configure ai-briefing` flow, which is the only surface that changes the
  stored value; the headless `--config` path, with the caveat that it seeds on a fresh install only
  and is ignored once installed, so reconfiguring headlessly is uninstall-then-reinstall; and the
  per-run `--profile` for a one-off that should not touch stored config. This skill still never
  writes `pluginConfigs`.

## [0.6.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract.** The read-only `check`
  action verifies the resolved profile, `sources.md`, optional overlays, and the
  build-toolchain state (PASS/FAIL/INFO); `apply` scaffolds the profile. The
  verify-plus-install fusion behind `--with-build-deps` is split into an explicit
  `apply install-build-deps` subaction that runs the same locked build-toolchain
  install flow unchanged. `--profile <name>` still selects the profile for either
  action. README invocation references updated to the subaction.

## [0.5.2]

### Changed

- **Freshness rider on the Playwright environment matrix** (fleet conformance
  wave: volatile platform facts carry a verified-date + official link). The
  README matrix is dated and re-verified against Playwright's system
  requirements; the setup skill no longer restates the version matrix and
  defers to the linked page as authoritative.

## [0.5.1]

### Changed

- README states the POSIX-shell requirement of the `setup --with-build-deps`
  install step with its Windows path (Git Bash; the script's platform gate
  already accepts MINGW/MSYS/CYGWIN) — cross-platform declaration wave. The
  Node build pipeline is unchanged and remains shell-free.

## [0.5.0]

### Changed

- Renamed the `ai-briefing` skill → `generate`. Update any `/ai-briefing:ai-briefing` invocations to
  `/ai-briefing:generate`; the plugin ID (`ai-briefing`) is unchanged, only the skill's leaf name
  moved. `scripts/validate-plugin-contracts.mjs` retargeted to `skills/generate` for its
  active-profile and build-root checks.

## [0.4.0]

### Added

- Engine behavioral evals in `skills/ai-briefing/evals/evals.json`, covering: `retro` action
  routing and per-item acted/noted/skipped scoring against an archived briefing; `search`
  action full-text matching across archives; markdown-only output when `--format slides`/`html`
  is not explicitly requested; merge-not-append behavior when folding newly collected items into
  an already-open briefing window; the apolitical filter, pragmatic-use ranking lens, and
  profile-provided impact-lens annotation (via `references/audience-defaults.md`); and graceful,
  visibly-surfaced degradation when an optional collection source is unreachable, without
  aborting the run.
- Three supporting fixtures under `skills/ai-briefing/evals/fixtures/`: `archive-sample.md`,
  `open-window-sample.md`, and `candidate-items-sample.md` — neutral, synthetic AI-industry
  content with no real company, person, or consumer-specific references.
