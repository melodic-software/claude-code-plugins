# changelog: read-only actions and the read marker

The three read-only actions (`fetch`, `diff`, `status`) and the read marker they share. SKILL.md
keeps the action-router table and the `apply` pipeline; these stop short of any edit and live here.

## The read marker

The read marker is the one line that records the newest Claude Code release this repository has
been read against. It lives in the repository's upstream ledger for Claude Code releases:

```markdown
**Last audited upstream state:** changelog through `2.1.263` (published 2026-09-06), read as raw
markdown on 2026-09-08.
```

The script reads the version inside the backticks after `changelog through`; the rest of the line
is prose for the human reader and carries the as-of date the
[upstream-drift convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/upstream-drift/README.md)
requires. Git history of the ledger records when the line moved.

Where the ledger lives, first hit wins:

1. `CLAUDE_OPS_CHANGELOG_LEDGER`, used verbatim when set.
2. `docs/upstream/claude-code.md` under the repository root (the git toplevel, or the working
   directory outside a repository).

Who moves it: an `apply` that finishes a range moves the marker to the top of that range in its
last commit, in a subject of the form `chore(<scope>): address Claude Code v<A>..<B> changelog`. A
repository with no ledger yet gets one from its first `apply`, or from a person after the
docs-conformance recheck the cap recommends.

When no ledger carries a marker, the script falls back to the highest version named in a commit
SUBJECT of that form on the current branch. Commit bodies are never read: a body that says
"verified against Claude Code v2.1.252" is a recency stamp on a doc, not an apply, and reading
bodies reports applies that never happened.

## Range and cap

The default range for `diff` and `apply` is every release newer than the marker, oldest first, up
to the newest published release. An explicit `vA..vB` is inclusive at both ends and ignores the
marker; a single `vX` is that one release.

The replay cap is ten releases or 300 core items (bullet lines in a release block, `[VSCode]` lines
excluded), overridable with `--cap-releases` and `--cap-items` or the
`CLAUDE_OPS_CHANGELOG_CAP_RELEASES` and `CLAUDE_OPS_CHANGELOG_CAP_ITEMS` environment variables. Beyond
the cap, replaying items costs more than it returns: the current docs already carry the cumulative
state, so the honest move is a docs-conformance recheck of the components against them, then a
marker set at the newest published release and a `diff` from there. `diff` and `apply` stop at an
exceeded cap with that recommendation instead of fanning out.

## The status script

Every read-only action starts from one script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/changelog/scripts/changelog-status.sh" [--range vA..vB] [--changelog <file>]
```

It prints `key: value` lines: `last-applied`, `source` (`ledger:<path>`, `git-subject`, or `none`),
`ledger` (path and presence), `installed` (from `claude --version`), `latest`, `range`, `releases`
(oldest first), `cap`, and when they apply `recommend` and `warn`. Its `--help` lists every line and
flag. Without `--changelog` it fetches the raw changelog itself by the route below; pass
`--changelog <file>` to reuse a copy already fetched, and `--no-fetch` to read the marker alone.

## Fetch route

The changelog page is `https://code.claude.com/docs/en/changelog.md`, the raw-markdown channel. Read
it by rung 1 of the upstream-drift convention's fetch route: `curl` the `.md` to a file and search
the file locally. A summarizing fetch truncates a page this long and a truncated read supports no
absence claim, so never report a version "absent from the changelog" from anything but a complete
local copy. The script and this action both check the body's first heading, which reads
`# Claude Code changelog`; a retired slug can serve another page's bytes under a 200, and a body
with a different heading is not the changelog.

Page-specific shape, the only facts this skill keeps about the page:

- One release is one `<Update label="X.Y.Z" description="<Month D, YYYY>">` block closed by
  `</Update>`; the newest release is the first block.
- Items are `*` bullet lines inside a block. Lines tagged `[VSCode]` belong to the extension and
  do not count as core items.
- A release with no user-visible change carries the single line
  `Bug fixes and reliability improvements`.

Slice a release or range out of the local copy with the block boundaries:

```bash
curl -fsSL https://code.claude.com/docs/en/changelog.md -o "$TMPDIR/changelog.md"
awk '/<Update label="2.1.261"/,/^<\/Update>/' "$TMPDIR/changelog.md"
```

## Action: fetch

Read-only. Display changelog content.

1. Resolve the target: a `vA..vB` range, a single `vX`, or nothing, which means the newest release.
2. Fetch by the route above and slice the target releases out of the local copy.
3. Display each release under its version and date. No edits, no triage.

## Action: diff

Read-only dry run of `apply`. It answers "is this range worth an `apply`?"

1. Run the status script, with `--range` when the user gave one, or with the range the pasted
   text's release blocks name when the input is pasted text (pasted text with no version skips
   the script's cap). Show the `range`, `cap`, and any `warn` line.
2. If `cap` reads `exceeded`, stop here and relay the `recommend` line. Do not fan out over items;
   the recommendation is the output.
3. Otherwise run Phase 0 (ingest) over the releases the `releases` line names, then Phase 1
   (explore) and Phase 2 (research) from SKILL.md, and stop before the interview.

Output: the triage table showing what would need to change, with enriched research. No file edits.

## Action: status

Read-only. Run the status script and relay its lines in this order, each in one sentence:

1. `last-applied` with its `source`. When the source is `git-subject`, say the marker came from a
   commit subject and that the ledger is absent at the reported path. When it is `none`, say no
   read marker exists and relay the `recommend` line.
2. `installed` against `latest`, and the `warn` line when present.
3. `range` and `cap`. Within budget, name the default range an `apply` would take. Exceeded, relay
   the `recommend` line as the next step.

Never derive an applied version from a commit body, a doc's verification stamp, or a plugin
CHANGELOG entry: the ledger line and the commit subject are the only two sources. Never propose a
tracking file other than the ledger.
