---
description: "Checks or scaffolds this repository's code-tidying configuration: tracked project tidy lanes and the optional HARD-exclusion overrides file. Use when 'set up code-tidying' is asked or the tidy skill reports no project lanes."
argument-hint: "[check|apply] [<lane>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and scaffold the consuming repo's tracked lane definitions at `.claude/tidy-lanes/<lane>.md`,
so `/code-tidying:tidy` resolves project-specific scope globs and watch-for patterns instead of the
generic bundled lanes. A project lane at `${CLAUDE_PROJECT_DIR}/.claude/tidy-lanes/<lane>.md` layers
over the bundled lane of the same name: one declaring `## Merge semantics` merges per section with
the bundled lane, one without it resolves project-only (the `tidy` skill's Lane resolution).

Project lanes are optional: with none, tidy uses the bundled lanes, so their absence is an INFO,
never a FAIL. The skill follows the uniform setup contract (`docs/plugin-philosophy.md` "Setup is
explicit and repeatable" in the marketplace repository): no argument or `check` inspects
read-only; `apply` runs the check, scaffolds or retunes lanes, then re-runs `check`; `apply <lane>`
targets one lane. Re-running reads the existing lane files and proposes changes against them rather
than overwriting a consumer lane blind.

## Lanes vs. templates

- **Bundled lanes** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/*.md`: `shell-tooling`, `docs-prose`)
  cover surfaces that look the same in most repos and resolve with **no config**. A project override
  is worth writing only when this repo's tooling or doc directories differ from their defaults.
- **Bundled templates** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/*.template.md`) are
  `<placeholder>` scaffolds for lanes that are project-specific by design: code the repo has but no
  generic lane can name. Turning the fitting templates into real lane files is this skill's main
  job.

Never tell the user to "copy the bundled lanes": scaffold from templates, and override a bundled
lane only when its defaults miss this repo's layout.

The plugin's second tracked file is `${CLAUDE_PROJECT_DIR}/.claude/code-tidying/exclusion-overrides.md`,
optional and absent by default: root-relative globs that lift GLOBAL HARD **path** exclusions for
every run in this repository, the subtracting mirror of the consumer-declared protections that add
to them. `check` validates it; `apply` writes it only when the user asks. Contract, shape,
precedence, and what no channel lifts: the `tidy` skill's
[exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md) section 4.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Modify nothing, and do not run a
tidy sweep (that is `/code-tidying:tidy`).

1. **Project lanes present.** List `.claude/tidy-lanes/*.md`. None → INFO: tidy resolves the
   bundled lanes; `apply` scaffolds project lanes when this repo's layout diverges from them.
2. **Lane structure.** Each lane carries `## Scope`, `## Watch-for patterns`,
   `## Lane-specific extra exclusions`, `## Verification commands`, `## Conventional Commits type`,
   and `## Preferred research sources`; a missing section is FAIL. Exception: a lane that declares
   `## Merge semantics` **and** shares its name with one of `${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/*.md`
   inherits every section it omits, so report which sections it inherits instead. The exemption
   belongs to the declaration, not the heading: confirm the section either adopts the bundled lane's
   declaration by reference (the shape `apply` writes, `Merge semantics: per the bundled lane's
   declaration`) or states a disposition for every required section the lane omits. An empty,
   unrelated, or silent-on-an-omitted-section declaration is FAIL (malformed merge declaration;
   remediation: adopt the bundled declaration by reference or state the missing dispositions). FAIL
   too when the lane overrides a section the bundled lane keys at `###` granularity
   (`shell-tooling`'s `Verification commands` and `Preferred research sources`) without keying its
   own entries under those `###` language headings, since unkeyed entries name no language to
   replace. Framing prose above the first `###` is fine.
3. **No unreplaced placeholders.** A leftover template `<placeholder>` is a broken scope glob or
   watch-for pattern: FAIL, naming the file and the token.
4. **Tracked, not ignored.** Per lane file, run both halves of the tracked-file pair:
   `git check-ignore -v <file>` (non-empty means a `.gitignore` pattern excludes the lane: FAIL with
   the pattern, since a directory can be tracked while a pattern excludes one `.md` inside it) AND
   `git ls-files --error-unmatch <file>` (non-zero means un-ignored but untracked: report "commit it
   to share with the team", downgraded to INFO only when the user confirms a deliberately private,
   uncommitted lane).
5. **Bundled lanes and templates.** INFO: list them as the scaffold sources `apply` can use.
6. **HARD-exclusion overrides.** Absent is the normal state: INFO naming the file and what it does.
   Present: check it against section 4 of the exclusions reference: an `## Overrides` heading with
   one fenced block, one root-relative glob per line. FAIL an absolute path or an entry containing
   `..`, naming the line. FAIL a glob matching the overrides file itself or the `.claude/tidy-lanes/`
   definitions beside it: the file cannot lift its own protection. FAIL a glob that also matches a
   path this repo's `CLAUDE.md` / `.claude/rules` declare protected, naming both declarations: the
   protection wins and the override is dead text. Run both halves of the tracked-file pair on it as
   for a lane file (`git check-ignore -v` reports no match, `git ls-files --error-unmatch` exits 0),
   since it is a team statement that counts only when committed. Report the globs it lifts.
7. **`hard_exclusions` posture.** Report the stored `userConfig` value. `enforce` (default) is PASS.
   `advisory` is INFO, not a FAIL, a deliberate operator posture, and the report line states what it
   does: every GLOBAL HARD **path** entry is reported instead of blocking, in every run this operator
   makes. If the value changed this session, say the
   running session's behavior is not yet established: the stored value is current, the session lags.

## `apply` (idempotent)

Run `check`, then resolve each lane by the convention ladder: config present → use it; absent →
infer from the repo and persist; cannot infer → ask and offer to persist; else a safe default (skip
that lane, no empty file). Proceed non-interactively wherever the invocation and the repo make the
answer unambiguous; ask only where a lane's scope genuinely needs the user's call.

1. **Read existing lanes first.** If any exist, summarize each (name, scope globs, watch-for count)
   and propose changes against that baseline. **Never overwrite an existing consumer lane without
   explicit confirmation in this conversation.**
2. **Explore the repo to draft candidate lanes** before asking anything. Map the four template
   patterns against what actually exists, reading real directory names and extensions and assuming
   no stack, and skip any pattern the repo has no surface for:
   - **apps** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/apps-lane.template.md`): user-facing
     web/API/CLI app roots and their sibling test projects.
   - **dependency-root** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/dependency-root-lane.template.md`):
     shared, domain, or core library roots that downstream code depends on.
   - **host-wiring** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/host-wiring-lane.template.md`):
     composition roots, DI wiring, logging, registration, service defaults.
   - **polyglot-services** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/polyglot-services-lane.template.md`):
     non-primary-language services, MCP servers, sidecars.
   - **bundled-lane override**: a project override of `shell-tooling` or `docs-prose` only when the
     repo's tooling or doc directories diverge from the bundled scope globs.
   Under `apply <lane>`, scope this to that lane.
3. **Interview, one lane at a time**, recommendation first and the highest-blast-radius lane
   first. Present each candidate with its inferred globs and source template; let the user accept,
   edit the globs, or drop it. Offer a custom lane last ("any other glob-scoped slice this repo
   should tidy on its own rotation?").
4. **Fill each accepted lane from real repo values.** Read its source in full, then replace every
   `<placeholder>` (templates) or bundled default (overrides):
   - **Template-pattern lanes** start from the exact template file presented in step 2
     (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/<pattern>-lane.template.md`).
   - **Bundled-lane overrides** have no template: read `${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/<lane>.md`
     and write **only** the sections this repo diverges on (usually `## Scope`, sometimes extra
     exclusions) plus a `## Merge semantics` section adopting the bundled lane's declaration. Where
     the bundled lane keys a section at `###` granularity, key the override the same way.
   - **Custom lanes** start from the closest template, or, when none fits, a new file with the same
     six sections. Never emit a lane missing a section.
   Fill scope globs from real paths, watch-for patterns tuned to the stack, lane-specific exclusions
   for this repo's unverifiable surfaces, verification commands from the project's own CLAUDE.md,
   rules, or CI config (never invented), the Conventional Commits type, and preferred research
   sources. Leave no `<placeholder>` behind.
5. **Write the lane files** the user confirmed at `.claude/tidy-lanes/<lane>.md`; no empty
   scaffolds.
6. **Verify after remediation.** Re-run the `check` probes on each written file: required sections,
   no leftover placeholder, and both halves of the tracked-file pair. A `git check-ignore -v` match
   means a `.gitignore` pattern excludes the lane: surface it and offer to fix `.gitignore` before
   reporting success. A non-zero `git ls-files --error-unmatch` is the expected state right after a
   fresh write: report "written but untracked: commit it to share with the team", never success,
   since these lanes are team-shared and reach the team only once committed. tidy resolves a lane
   only from `.claude/tidy-lanes/<lane>.md` (then the bundled lane of that name), with no
   user-global or `*.local.*` overlay (a declared deviation from the config-cascade contract). Never
   point a developer at a `*.local.*` variant tidy would not load; a private lane uses a lane name
   the team does not track, kept uncommitted (never add it to the index).
7. **Offer the overrides file only when the repo asked for one**: the conversation named a path the
   plugin keeps dropping, or `check` reported a malformed existing file. Absent is correct for almost
   every repository, and an empty overrides file is the empty scaffold step 5 forbids. Write
   `${CLAUDE_PROJECT_DIR}/.claude/code-tidying/exclusion-overrides.md` in the section 4 shape (an
   `## Overrides` heading, one fenced block, one root-relative glob per line, `#` comments) with only
   globs the user named, preserving any prose already in the file. Re-run the step 6 probes on it,
   report it as written but untracked until committed, and state plainly what it loosens.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Personal configuration (`userConfig`)

Not `apply` surface: Claude Code owns the storage, and this contract forbids setup to write
`pluginConfigs`, so `check` reports the observed value and routes the change. Reconfigure through
Claude Code's native flow, per the marketplace's
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md)
(which owns the verified-version record): interactive `/plugin configure code-tidying@<marketplace>`
any time, or headless:

```shell
claude plugin install code-tidying@<marketplace> -s <scope> --config hard_exclusions=advisory
```

Against an installed plugin this prints `already installed` and still writes the value. Pass the
scope `claude plugin list` reports. The running session is not re-read, so start a fresh session
before expecting the new behavior. `hard_exclusions` takes `enforce` (default, every GLOBAL HARD path
entry blocks) or `advisory` (every one is reported and none blocks); any other value is read as
`enforce`. The full option table is in the plugin README.

## Output

Tracked `.claude/tidy-lanes/<lane>.md` file(s) in the consuming repo, plus a one-paragraph summary
of which lanes were written, the source of each (template or bundled lane), and how to re-run this
setup to add or retune lanes. When an overrides file was written or already exists, the summary
names it and the globs it lifts.

## Boundaries

- Never runs a tidy sweep (`/code-tidying:tidy`); `check` only inspects config.
- Never writes the plugin cache, Claude Code user settings, `pluginConfigs`, or machine-local
  state: lane configuration lives in the consumer's tracked `.claude/tidy-lanes/`, never in the
  plugin directory or a plugin data directory.
- Ships no template copies: lanes scaffold from `${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/`, so
  they cannot drift from the source.

## Gotchas

- **Do not uninstall to reconfigure.** It drops this plugin's entire stored `pluginConfigs`
  entry; the install command's `already installed` short-circuit is about the install, not the
  config write.
- **A copied bundled section is frozen** at its copy-time value, while an omitted one keeps
  inheriting bundled improvements. Write only the sections that diverge.
- **Gitignoring a path the team already tracks does not make it personal**: indexed files remain
  visible to Git regardless of `.gitignore`.
