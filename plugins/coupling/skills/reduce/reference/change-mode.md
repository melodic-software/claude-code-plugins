# Change mode

The reactive pass: one value changed, or has to, and every place that states it must be found,
sorted, and either changed in a way that stops the next cascade or left alone on purpose. The
proactive pass finds the same connascence of value before anyone changes it; this one starts from
the change.

## Contents

- [Inventory](#inventory)
- [Site classes](#site-classes)
- [Enforced patterns](#enforced-patterns)
- [Reference forms](#reference-forms)
- [Apply](#apply)
- [Pitfalls](#pitfalls)

## Inventory

`scripts/value-sites.py find` does the deterministic part and the model does none of it by hand:

- **Files.** Tracked files from `git ls-files`; a root that is not a repository is refused. A file
  is skipped, not read, when it has a NUL byte in its first 8 KiB (`binary`), starts with a UTF-16
  or UTF-32 byte-order mark (`utf-16`, `utf-32`), or is a tracked path that resolves outside the
  root through a symlink or junction (`outside-root`). Each skip is a `skip<TAB>path<TAB>reason`
  row, and the summary counts them as `skipped`.
- **Forms of the value.** A path-like value is written differently per file type, so the script
  searches every form: the value as given, with `/` and `\` swapped, and with each `\` doubled (JSON
  and string escapes). A drive followed by a path, such as `D:\data`, is also searched in its MSYS
  `/d/data` and WSL `/mnt/d/data` spellings; a bare drive is not, since `/d/` alone is any URL
  segment. A second, case-insensitive pass reports what only matches with case folded, tagged
  `case:` plus the form it matched (`case:exact`, `case:doubled`, `case:msys`), and `apply` writes
  the new value in that form.
- **Token boundary.** A value that starts or ends with a word character does not match inside a
  longer word: `D:` is not found inside `ID:`. No match ends before `~` and a digit, since
  `D:\data~1` is an 8.3 short name for another directory. An MSYS or WSL spelling does not match
  after a word character, `/`, `.`, `-`, or `~`, so a URL path segment is not read as a drive path.
- **Longest form wins.** When two forms overlap at one position, the longer one is the site and the
  shorter is not reported again.
- **Counted before read.** `--format summary` prints sites per file and per class, so the size of
  the change is known before any file is opened.

Each row is `class<TAB>path<TAB>line<TAB>col<TAB>form<TAB>reason<TAB>anchor<TAB>text`. The
`anchor` is the first 12 hex digits of the SHA-256 of the line together with the line before and
the line after it (each without its terminator or a trailing CR), so it identifies the line's
content and its neighbours rather than its position; `path:line:col:anchor`
from a row is the site `apply` takes. The class comes from path rules applied to the path as
resolved inside the root, and the `reason` column says which rule fired. The rules are a default, not a verdict:
read the row, and reclassify it in the report with a stated reason when the file says otherwise.
A site reclassified away from its path class, in either direction, is edited with the Edit tool
after confirmation, never forced through `apply`. Filename and path-segment rules ignore case.
A repository without a record or contract convention lands mostly in `setup`, so review setup
rows before confirming: `apply` edits any listed setup site.

## Site classes

| Class | What it is | What happens |
|---|---|---|
| setup | Examples, help text, runbooks, script defaults, install and configuration docs, templates | Change the value and convert the site to a reference form so the next change does not reach it |
| record | Changelogs, release notes, decision records, evidence, incidents, logs (exact patterns under Enforced patterns) | Leave. They record what was true then |
| contract | Approved plans, briefs, specs, published schemas | Never edit. Write a correction entry to the proposal file below, citing path and line |
| fixture | Test inputs and expected outputs | Flag for a person. Change only when a test pins a value the source of truth now owns |
| generated | Files whose header says they are generated or not to be edited | Never edit. Flag for a person with the generator input to change |
| protected | CI config, agent settings, git hook directories and `hooks.json` manifests, lint and format configs, lock files, migrations (exact patterns under Enforced patterns); an application's own `hooks/` source folder is not included | Never edit here. Route to a person as its own change; phase E keeps these surfaces out of any batch |
| unknown | A file kind outside the `extension-allow` list under Enforced patterns (for example `LICENSE` or `Jenkinsfile.groovy`) | Never edit through `apply`. Read it; if it is text that states the value, reclassify it in the report and edit it with the Edit tool after confirmation |

The rules are a deny-list with a default-deny for unknown kinds, not an allow-list of setup paths:
the protected, record, contract, and generated lists name what must not be edited, and a file whose
kind the script does not recognize is denied rather than assumed to be setup. Setup is what is left.
The first rule that fires wins, in the order generated, protected, fixture, record, contract,
unknown, setup, so `tests/data.xyz` stays a fixture. Every name and segment compares
case-insensitively.

The script cannot see a vendored copy (a file synced from another location); reclassify it as
`generated` and change the source it is copied from.

A contract correction goes to `.work/coupling/contract-corrections.md`, beside the ledger in the
memory tier, one entry per site:

```markdown
## <path>:<line>

- current: <the line as read at write time>
- proposed: <the corrected line>
- reason: <the value change and its owner>
```

Read the line again when writing the entry; a contract under concurrent edit moves.

## Enforced patterns

`value-sites.py rules` prints this list, and the suite fails when the two differ. Kinds:
`marker` is text in a file's first five lines; `segment` is a directory name anywhere in the
path; `segments` is consecutive directory names; `name` is a filename glob; `root-name` is a
filename glob for a file at the repository root only; `extension-allow` lists the file kinds that
are not `unknown`. Rules apply in table order and the first match wins; everything compares
case-insensitively.

<!-- value-sites-rules:start -->

| Class | Kind | Pattern |
|---|---|---|
| generated | marker | `@generated`, `do not edit`, `auto-generated`, `autogenerated`, `generated by` |
| protected | segment | `.github`, `.gitlab`, `.azure-pipelines`, `.claude`, `.husky`, `.githooks`, `.circleci`, `.buildkite`, `.woodpecker`, `.gitea`, `.forgejo`, `migrations`, `migration`, `migrate`, `alembic`, `drizzle` |
| protected | segments | `db/changelog` |
| protected | name | `hooks.json`, `.gitlab-ci.yml`, `azure-pipelines.yml`, `azure-pipelines.yaml`, `jenkinsfile`, `.travis.yml`, `bitbucket-pipelines.yml`, `.drone.yml`, `appveyor.yml`, `*appveyor.yml`, `.woodpecker.yml`, `.woodpecker.y*ml`, `cloudbuild.yaml`, `ruff.toml`, `.ruff.toml`, `_typos.toml`, `.typos.toml`, `typos.toml`, `.pre-commit-config.yaml`, `.golangci.yml`, `.golangci.yaml`, `.golangci.*`, `.editorconfig`, `.shellcheckrc`, `.eslintrc*`, `eslint.config.*`, `.markdownlint*`, `.prettierrc*`, `prettier.config.*`, `.flake8`, `.pylintrc`, `.stylelintrc*`, `stylelint.config.*`, `biome.json`, `biome.json*`, `.yamllint*`, `.rubocop.yml`, `lefthook.yml`, `*lefthook.*`, `.lintstagedrc*`, `lint-staged.config.*`, `mypy.ini`, `.mypy.ini`, `*.lock`, `package-lock.json`, `npm-shrinkwrap.json`, `pnpm-lock.yaml`, `go.sum`, `packages.lock.json`, `*.lock.json`, `gradle.lockfile`, `*.lockfile` |
| protected | root-name | `action.yml`, `action.yaml` |
| fixture | segment | `test`, `tests`, `__tests__`, `fixtures`, `testdata`, `evals` |
| fixture | name | `*.test.*`, `test_*.py`, `*_test.*`, `*.Tests.ps1` |
| record | name | `CHANGELOG*`, `CHANGES*`, `NEWS*`, `HISTORY*`, `RELEASE-NOTES*`, `RELEASENOTES*`, `*.log`, `adr-*.md` |
| record | segment | `adr`, `adrs`, `decisions`, `evidence`, `records`, `postmortems`, `retros`, `incidents`, `release-notes`, `changelog.d`, `.changeset` |
| contract | name | `PLAN.md`, `BRIEF*`, `PRD*`, `*.schema.json`, `openapi*` |
| contract | segment | `specs`, `rfcs`, `proposals` |
| unknown | extension-allow | `*.adoc`, `*.bash`, `*.bat`, `*.cfg`, `*.cjs`, `*.cmd`, `*.conf`, `*.cs`, `*.css`, `*.env`, `*.example`, `*.go`, `*.gradle`, `*.hcl`, `*.htm`, `*.html`, `*.ini`, `*.j2`, `*.java`, `*.js`, `*.json`, `*.jsonc`, `*.jsx`, `*.kt`, `*.markdown`, `*.md`, `*.mjs`, `*.php`, `*.properties`, `*.ps1`, `*.psd1`, `*.psm1`, `*.py`, `*.rb`, `*.rs`, `*.rst`, `*.scss`, `*.sh`, `*.sql`, `*.template`, `*.tf`, `*.tmpl`, `*.toml`, `*.ts`, `*.tsx`, `*.txt`, `*.xml`, `*.yaml`, `*.yml`, `*.zsh`, `dockerfile`, `makefile`, `readme` |

<!-- value-sites-rules:end -->

## Reference forms

The owning source is the one place the value is allowed to live; every setup site points at it.
Pick the smallest form that stops the propagation, following the sequencing rule in
[`remediations.md`](remediations.md):

- **Config key with an environment pointer.** Examples and help text name the key or the variable,
  never the value.
- **Named constant.** Code and docs cite the constant by name.
- **Placeholder defined once.** A doc defines `<config>` or `<datadir>` in one table that says how
  to resolve it, then uses the placeholder throughout.
- **Template token.** Templates carry a token the renderer fills.
- **Generated snippet or extraction.** Prose that has to show the value is generated from the owner,
  or extracted by `/docs-hygiene:extract-ssot` when that plugin is installed.

Apply the "externalize only what varies" test from [`remediations.md`](remediations.md): a value
stated twice that never varies can stay literal. Converting a site that introduces a new owner (a
new config key, a new placeholder table) is a proposal the human confirms, not a default.

## Apply

Only `change apply` edits, and only after the human confirms the classified site list:

1. Run `find` and present the summary, every non-setup row, and every skip row.
2. Wait for explicit confirmation of the setup sites to change, the fixture sites (if any) the
   human chose to change, and each reference-form conversion.
3. Follow phases E and F of the skill (short-lived branch from the default branch, clean targets,
   listed-path staging, project build and test). The per-run budget does not cap a confirmed change
   set, since a half-applied value change leaves the repository stating two values. When the set
   exceeds the budget's hard cap, say so and wait for an explicit acknowledgement of the size;
   never truncate it. A value change is its own pull request, never mixed into a structure-only
   coupling pass.
4. Substitute the value with `value-sites.py apply`, which takes each confirmed site as
   `path:line:col:anchor` copied from its `find` row and replaces only the match that starts at
   that column; several matches on one line are several sites, and a bare `path:line` is a usage
   error. At write time it re-reads the line and its neighbours and refuses the run when the anchor
   differs from the given one or no match of the value starts at the column, so a line that moved or changed
   since `find` is never edited. It also refuses a site that is not a tracked file inside the root,
   a symlink or hardlink, a binary, UTF-16, or UTF-32 file, record, contract, generated, protected,
   and unknown sites, fixture sites unless `--allow-fixture` is given, a target that is not
   writable, and any write that changes a file's control-byte count. One refusal means no file is
   written. Each file is written to a temp file beside it and moved into place; if a write fails,
   the run's temp files are removed and every file already replaced gets its original bytes back.
   Then make the confirmed reference-form conversions with the Edit tool.
5. Write contract corrections to the proposal file; never edit the contract.
6. Re-run `find` for the old value. Every remaining row must be a record, a contract, a generated
   or protected file, or a fixture the human chose to leave; a remaining setup row means the change is not done.
   When `<new>` contains `<old>`, a re-run matches the new value too; check the rows' text for the
   new value instead of counting them.
7. Record each converted site and each flagged contract or fixture in the ledger as a
   connascence-of-value entry.

## Pitfalls

- **Escape sequences in replacement text.** `sed` and `perl -pi` read `\c`, `\n`, and similar in a
  replacement as escapes, so a backslash path writes control bytes. `apply` replaces bytes, never
  through a regex replacement string, and refuses to write a file whose control-byte count changed.
- **Shared prefixes.** When two literals share a prefix, the longer one must be matched first or the
  shorter rewrites part of it. `find` resolves overlapping forms longest first, and the token
  boundary keeps `D:\data` from matching inside `D:\data2`; when two different values are changing
  together, run the longer one first.
- **Token ends.** `-` and `.` end a token, so `D:\data` also matches the start of `D:\data-old` and
  `D:\data.bak`; read those rows before confirming. `~` followed by a digit does not end a token:
  `D:\data~1` is an 8.3 short name for a different directory, and `find` does not report it.
- **Moving lines.** A file under concurrent edit shifts its line numbers, and an identical line can
  move into a confirmed line number. `apply` checks each site's anchor, which covers the line and
  its two neighbours, and its column at write time and refuses the whole run when either no longer
  holds; run `find` again and confirm the new rows. Cite contract lines from a fresh read.
- **Write-time guards.** When a hook blocks heredoc writes, inline interpreter writes, or a temp
  path, write the script with the Write tool into the session scratchpad and run it from there.
  Never weaken the guard.
