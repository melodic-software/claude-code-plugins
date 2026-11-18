# Ecosystem discovery for explore

How the explore skill finds the per-ecosystem facts its Dimensions 3–6 need (project structure,
test discovery, configuration and build state, environment). The skill ships no list of
ecosystems, test globs, build files, import tokens or version commands: each comes from the
repository being explored.

## Resolve from the repository

Resolve each key below through the plugin's copy of the ecosystem-resolution steps,
[`reference/ecosystem-resolution.md`](../../../reference/ecosystem-resolution.md): the record,
then what the repository states, then what its files imply. A dispatched explorer is an
unattended run, so it asks nothing and writes no record. An inline run may ask once (step 5) but
offers no record, since explore writes only its artifact set.

| Key | Dimension | What it finds |
|---|---|---|
| Ecosystems in play | 3 | the languages and build systems the repository's build, manifest and lock files show |
| Test locations | 4 | the test files or projects, from the repository's test layout and its test tool's config; for an ecosystem that keeps tests inside source files, the in-file marker that tool reads |
| Build configs | 5 | the build, package and config files to read for "Configuration and build state" |
| Dependency token | 3 | the import or reference token that maps the dependency graph across source and project files |
| Runtime version command | 6 | the command that reports the installed runtime version |

A runtime version the repository pins in a file is read from that file (`verified: read`), which is
a declared requirement, not the installed version. The installed-version probe runs only when the
record or the repository's instructions state its command; otherwise it is a gap.

When a key does not resolve, skip the probe that needs it and name the key, what was read, and any
tied candidates as a gap in the artifact. Never substitute a list or command shipped with the
skill.

## Compose the toolchain seam

When the `toolchain` plugin is enabled, also compose `/toolchain:check`'s ecosystem detection and
command-resolution seam for the signals it owns, rather than keeping a second inventory of them.
Gate and fallback follow `docs/contracts/seam-phrasing/README.md`: when `toolchain` is not
enabled, the resolution above is the whole procedure. Read *resolved* state: an
ecosystem present but `enabled: false` is not configured for exploration either.

| Explore need | Source when `toolchain` is enabled |
|---|---|
| Which ecosystems are in play | Resolved `globs` (and covered-ecosystem set), **plus** any ecosystem the repository's own files show that the seam does not cover |
| Project / workspace roots (Dimension 3 adjacency) | Resolved `project-discovery` / `anchor` |
| Build / package / config files to read (Dimension 5) | Build configs, resolved as above. Seam `globs` / `project-discovery` / `anchor` classify changed files and locate roots; they are not an exhaustive configuration inventory |
| Runtime / toolchain presence (Dimension 6) | Runtime version command, resolved as above. Resolved `install-hint` is free-form install prose, not a version probe |

Where the repository's own conventions differ from anything the seam reports (a custom test layout,
a nonstandard workspace file), the repository's conventions win.
