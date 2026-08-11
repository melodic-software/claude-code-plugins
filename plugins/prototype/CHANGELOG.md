# Changelog

All notable changes to the `prototype` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.0]

### Fixed

- **Both skills' ecosystem-detector grant was inert, and the fix everyone reaches for first would
  have made it dead instead.** `explore-directions` and `pressure-test` each granted
  `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh:*)`. `${CLAUDE_PLUGIN_ROOT}` is not
  one of the substitutions Claude Code performs in `allowed-tools` — only `${CLAUDE_SKILL_DIR}` and
  `${CLAUDE_PROJECT_DIR}` are — so the rule stayed a literal string, never matched, and the
  pre-computed ecosystem line fell through to a prompt or the classifier on every invocation.

  The obvious repair — drop `bash` from the rule — is wrong, and that correction is the part worth
  recording. `bash` is not one of the wrappers Claude Code strips before matching a Bash rule (that
  set is `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, and `noglob`), so a rule
  without `bash` stops matching the moment the body still says `bash <path>`. Dropping it alone would
  have turned an inert grant into a dead one while making the diff look like a fix. The change is
  therefore **paired**: the body invokes the script directly, and the rule names that same string,
  `Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)`. Quoting is part of the pairing — an
  unquoted rule does not match a body path wrapped in quotes, so the body's quotes came off too.

### Added

- **A skill-local entry point for the shared ecosystem detector**, one per skill, at
  `skills/<skill>/scripts/detect-ecosystems.sh`. `${CLAUDE_SKILL_DIR}` resolves to the skill's own
  subdirectory rather than the plugin root, so a grant that must reach a bundled script has to name a
  path underneath it. The detector stays single-sourced at `scripts/detect-ecosystems.sh`; each entry
  point is a self-locating wrapper that `exec`s it. Self-locating rather than
  `${CLAUDE_PLUGIN_ROOT}`-resolving because that variable is not exported into the Bash tool's
  environment, so expanding it inside a script yields an empty string.

- **`scripts/allowed-tools-pairing.test.sh`**, asserting the contract the fix establishes: no
  interpreter-led grant and no `${CLAUDE_PLUGIN_ROOT}` in `allowed-tools`, every bundled-script
  invocation in skill markdown unquoted and free of a `bash` wrapper, and every granted script
  present, executable, and actually invoked by a body — a grant nothing runs is dead weight.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.0]

### Added

- **`pressure-test` gains an audience-routed HTML demo shell.** The TUI stays the
  default; when the driver is a non-developer (a designer, PM, or domain expert)
  or no terminal fits the handoff, the disposable shell over the same portable
  pure logic module is a single self-contained `file://` HTML page — domain-language
  labels, a labelled state panel re-rendered on every click, free-play buttons
  (one per action), and guided-walkthrough scenarios that reset to a known
  initial state. The page reuses `explore-directions`' HTML-substrate constraint
  set: restrictive CSP meta tag (no remote origins by construction), ephemeral
  placement via the platform temp primitive (`mktemp -d` private run directory /
  `%LOCALAPPDATA%\Temp`), synthetic data only, and discard after the markdown
  capture — the validated logic module remains the only artifact that outlives
  the prototype. Adapted from mattpocock/skills v1.2.3 @ `84fdeff`,
  `skills/engineering/prototype/LOGIC.md` (the shareable-HTML shell); upstream's
  throwaway-branch "primary source" capture of the prototype was rejected
  (contradicts this plugin's delete-when-done discipline) — rejection recorded
  in `docs/upstream/mattpocock-skills.md`.

## [0.4.0]

### Changed

- **`explore-directions`: the visual axis is additive, not out of scope.** Structure remains the
  floor ("a recolor alone is not a variant"), but the skill no longer de-scopes visual direction:
  on open-ended briefs current models settle into one default house aesthetic, and generic
  steering only swaps palettes (Sonnet 5 / Opus 4.8 prompting guides, "Design and frontend
  defaults"). The HTML mockup substrate — which has no project styling system to pin the
  aesthetic — now requires each variant to declare its visual direction (background hex, accent
  hex, typeface, one-line rationale) and differ from siblings on that axis as well as
  structurally; the real-stack path declares a direction wherever the project's styling system
  leaves room. Eval 3's second expectation now scores "recolors are not the only difference"
  instead of treating color variety as beneath the exercise. The flip-between-variants delivery is
  unchanged — no propose-then-pick gate was added.

## [0.3.3]

### Changed

- **`explore-directions` mockup placement conforms to the topic-docs ephemeral
  tier.** The self-contained HTML mockup resolves one deterministic location via
  the platform temp primitive — a private run directory from
  `mktemp -d "${TMPDIR:-/tmp}/explore-directions-XXXXXX"` on Unix/Linux/Git Bash
  with the page inside it, a user-scoped temp under `%LOCALAPPDATA%\Temp` on
  Windows — instead of an "OS temp **or** gitignored scratch location"
  OR-branch, whose gitignored option put the throwaway file inside the repo. The
  handed-back path is never deleted.

  The temp root rides in the positional TEMPLATE rather than in a flag.
  `-p` (which GNU also spells `--tmpdir`) is documented in both dialects but does
  not mean the same thing: GNU treats the template as relative to that directory
  and lets the flag beat `TMPDIR`, while BSD/macOS consult it only as a fallback
  for `-t` when `TMPDIR` is unset — so with a bare template and no `-t` the flag
  does nothing there and the template resolves against the current directory,
  silently writing into the consumer's repo. GNU additionally marks `-t`
  deprecated. The `XXXXXX` is also **trailing**: BSD `mktemp` substitutes only
  trailing Xs, so `explore-directions-XXXXXX.html` cannot be created at all on
  macOS. Naming the page inside a generated directory is what preserves the
  `.html` extension without an unportable suffix on the template.

## [0.3.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.0]

### Changed

- **BREAKING: both skills renamed** (fleet conformance wave — naming grammar, verb-first
  skill names). `/prototype:logic` is now `/prototype:pressure-test`; `/prototype:ui` is
  now `/prototype:explore-directions`. Update any saved invocations. Skill behavior,
  triggers, and evals are unchanged; only the leaf names and namespace tokens changed.

## [0.2.4]

### Changed

- README declares the Bash requirement of the bundled ecosystem-detection
  script with its Windows path (Git Bash) and documents the no-Bash degrade
  (detection reports "none detected"; the skills read the host project
  directly) — cross-platform declaration wave.

## [0.2.3]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.2.2]

### Changed

- Synced the composition table's sibling-skill routes to the reorganized plugin
  taxonomy: `/improve-architecture:improve-architecture` is now `/architecture:improve`.

## [0.2.1]

### Added

- **Composition table.** The shared discipline now maps the prototype to its upstream and
  downstream workflow skills — `/planning:prd`, `/improve-architecture:improve-architecture`,
  `/planning:architect`, and `/implementation:implement` — each invoked only when the sibling
  plugin is installed.
- **Named handoff capability in the auto-invoke gate.** The gate's "checkpointing your current
  work first" now names `/session-flow:handoff` (when installed) as the checkpoint capability.
