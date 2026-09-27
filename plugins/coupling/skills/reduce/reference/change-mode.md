# Change mode

The reactive pass: one value changed, or has to, and every place that states it must be found,
sorted, and either changed in a way that stops the next cascade or left alone on purpose. The
proactive pass finds the same connascence of value before anyone changes it; this one starts from
the change.

## Contents

- [Inventory](#inventory)
- [Site classes](#site-classes)
- [Reference forms](#reference-forms)
- [Apply](#apply)
- [Pitfalls](#pitfalls)

## Inventory

`scripts/value-sites.py find` does the deterministic part and the model does none of it by hand:

- **Files.** Tracked files from `git ls-files`; a root that is not a repository is refused. Binary
  files are skipped and counted.
- **Forms of the value.** A path-like value is written differently per file type, so the script
  searches every form: the value as given, with `/` and `\` swapped, and with each `\` doubled (JSON
  and string escapes). A drive followed by a path, such as `D:\data`, is also searched in its MSYS
  `/d/data` and WSL `/mnt/d/data` spellings; a bare drive is not, since `/d/` alone is any URL
  segment. A second, case-insensitive pass reports what only matches with case folded, tagged
  `case:` plus the form it matched (`case:exact`, `case:doubled`, `case:msys`), and `apply` writes
  the new value in that form.
- **Token boundary.** A value that starts or ends with a word character does not match inside a
  longer word: `D:` is not found inside `ID:`. An MSYS or WSL spelling does not match after a word
  character, `/`, `.`, `-`, or `~`, so a URL path segment is not read as a drive path.
- **Longest form wins.** When two forms overlap at one position, the longer one is the site and the
  shorter is not reported again.
- **Counted before read.** `--format summary` prints sites per file and per class, so the size of
  the change is known before any file is opened.

Each row is `class<TAB>path<TAB>line<TAB>col<TAB>form<TAB>reason<TAB>text`. The class comes from
path rules and the `reason` column says which rule fired. The rules are a default, not a verdict:
read the row, and reclassify it in the report with a stated reason when the file says otherwise.
A site reclassified away from its path class, in either direction, is edited with the Edit tool
after confirmation, never forced through `apply`. Filename and path-segment rules ignore case.
A repository without a record or contract convention lands mostly in `setup`, so review setup
rows before confirming: `apply` edits any listed setup site.

## Site classes

| Class | What it is | What happens |
|---|---|---|
| setup | Examples, help text, runbooks, script defaults, install and configuration docs, templates | Change the value and convert the site to a reference form so the next change does not reach it |
| record | Changelogs, decision records, evidence, measurements, logs | Leave. They record what was true then |
| contract | Approved plans, briefs, specs, published schemas | Never edit. Write a correction entry to the proposal file below, citing path and line |
| fixture | Test inputs and expected outputs | Flag for a person. Change only when a test pins a value the source of truth now owns |
| generated | Files whose header says they are generated or not to be edited | Never edit. Flag for a person with the generator input to change |

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

1. Run `find` and present the summary and every non-setup row.
2. Wait for explicit confirmation of the setup sites to change, the fixture sites (if any) the
   human chose to change, and each reference-form conversion.
3. Follow phases E and F of the skill (short-lived branch from the default branch, clean targets,
   listed-path staging, project build and test). The per-run budget does not cap a confirmed change
   set, since a half-applied value change leaves the repository stating two values. When the set
   exceeds the budget's hard cap, say so and wait for an explicit acknowledgement of the size;
   never truncate it. A value change is its own pull request, never mixed into a structure-only
   coupling pass.
4. Substitute the value with `value-sites.py apply`, which changes the value only, on the listed
   `path:line` sites only. It refuses a site that is not a tracked file inside the root (or is a
   symlink), record, contract, and generated sites, fixture sites unless `--allow-fixture` is
   given, a line that no longer carries the value, and any write that changes a file's
   control-byte count; one refusal means no file is written. Then make the confirmed
   reference-form conversions with the Edit tool.
5. Write contract corrections to the proposal file; never edit the contract.
6. Re-run `find` for the old value. Every remaining row must be a record, a contract, a generated
   file, or a fixture the human chose to leave; a remaining setup row means the change is not done.
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
  `D:\data.bak`; read those rows before confirming.
- **Moving anchors.** A contract under concurrent edit shifts its line numbers. `apply` re-reads each
  listed line at write time and refuses a site whose line no longer carries the value; cite
  contract anchors from a fresh read.
- **Write-time guards.** When a hook blocks heredoc writes, inline interpreter writes, or a temp
  path, write the script with the Write tool into the session scratchpad and run it from there.
  Never weaken the guard.
