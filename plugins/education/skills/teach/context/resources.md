# Resources Format

`RESOURCES.md` serves four readers in a workspace:

| Reader | Uses the file to |
|---|---|
| `explain` and `exercise`, while writing | Find the source behind each claim. A claim with no row here gets a fetched, admitted source first; model recall is never the source |
| The coach, when a question turns on practical judgment | Send the learner to a community in the Wisdom table, after giving its own best answer |
| SKILL.md "Staleness" | Re-fetch the row a stale lesson or `reference.md` cites inline, and update from it |
| The next search for sources | Start from the Not Yet Covered list |

The two tables follow the pedagogy's layers ([pedagogy.md](pedagogy.md)): something to read or
watch is Knowledge; somewhere the learner tries skills on other people is Wisdom.

## Admitting a row

A source gets a row only when it passes every test below.

1. **Fetched this turn.** A fetch in this session showed the page says what the row will claim. A
   title remembered from training is a lead to fetch, not a row. In codebase mode a file Read this
   turn passes without a fetch (see "Codebase mode").
2. **Someone accountable stands behind it.** It passes when it comes from the project or standards
   body that owns the subject, from published peer-reviewed research, or from a named practitioner
   whose work others in the field cite. A page whose purpose is selling a product fails, however
   instructional it looks.
3. **For a community: moderated, and on the mission's questions.** A forum, list, class or club
   passes when someone enforces its standards and its members answer the kind of question the
   mission raises.
4. **The "Go here when" cell can be filled.** If you cannot name the question that should send the
   learner to it, the row is not ready; a later session cannot use a link it has no reason to open.

## Upkeep

- **Re-run admission when a lesson touches a row.** A row that would fail any of the four tests
  today comes out of the table in that session. The table has no ranking to demote it to, and a
  short table the learner trusts serves the mission better than a long one.
- **Name the holes.** A mission area with no source that passes admission goes on the Not Yet
  Covered list.
- **Record a declined community.** When the learner says they will not join communities, put that
  line at the top of the Wisdom section, and later sessions stop offering them.

## Template

```markdown
# Resources: {Topic}

## Knowledge Sources

| Source | Covers | Go here when |
|---|---|---|
| [{Title}]({URL}), {author}, {kind: book, course, docs page, paper} | {subject} | {the question that sends the learner here} |

## Wisdom Communities

| Community | Go here for |
|---|---|
| [{Name}]({URL}) | {the help the learner gets there} |

## Not Yet Covered

- {A mission area with no admitted source yet}
```

Example Wisdom rows, one from a PostgreSQL query-plan workspace and one from a sailing workspace:

| Community | Go here for |
|---|---|
| [PostgreSQL project bug tracker and its triage threads]({URL}) | Checking whether a planner behavior you hit is a known defect before you design around it |
| [Class association's published race protest decisions archive]({URL}) | Reading how rules disputes about right of way were decided, to test your own reading of a rule |

A workspace written before this layout may use bulleted entries under other headings; read it by
meaning and convert it when the file is next edited.

## Codebase mode

For `/education:teach codebase`, the file also records what SKILL.md "Codebase mode" discovery
found, so later sessions reuse it instead of surveying the repository again:

```markdown
## Repo Sources

- {path to a convention or architecture doc}: {the rule it sets}
- {path to a source module or library}: {the pattern it shows}
- {path to a reference implementation or example}: {why it is the one to copy}
- {path to representative tests}: {the behavior they pin down}
```

Repo Sources are files Read this turn, so they are primary sources, ranked above any external page,
and need no fetch. A `RESOURCES.md` holding only Repo Sources is complete; add Knowledge or Wisdom
rows only when the mission reaches past the repository.
