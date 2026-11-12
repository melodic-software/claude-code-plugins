<!-- Fill every <placeholder>; delete these comments. -->
<!-- A page source: name the page in the title and link it in the intro instead of the repository. -->
# Upstream source: <owner>/<repo> (<scope, when one is set>)

This page records what this repository takes from, adapts, already has, or rejects in
[<owner>/<repo>](https://github.com/<owner>/<repo>) (<license as read>). Rows hold our decisions
and our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/upstream-drift/README.md#what-a-row-may-describe);
read upstream at each row's link for what it says.

<!-- A repository source: the pin marker line and the trigger line, both in the forms the -->
<!-- convention's "Pinned git upstreams" section gives. Omit the marker's scope clause when no -->
<!-- --scope was set; never write it with an empty or root scope. -->
<pin marker line>

**Recheck trigger:** <the fixed wording from the convention's "Pinned git upstreams" section>

<!-- A page source: replace the two lines above with the convention's pointer record. -->
<!-- - **Pointer**: when <situation>, fetch <page URL with section anchor> live. -->

## Attribution table

**Stated**: the upstream gives this problem where the label's link points. **Inference**: we
derived it from the mechanism. Disposition is `take`, `adapt`, `already have` or `reject`, with the
reason.

<!-- A page source: the idea column names the page section and links its anchor. -->
<!-- Each cell follows the convention's "What a row may describe" section. -->
| Idea (link at the pin) | What it does | Upstream problem, motivation, goal | Our problem | Disposition |
|---|---|---|---|---|
| [`<unit>`](https://github.com/<owner>/<repo>/tree/<40-hex sha>/<path>) | <the mechanism, our sentence> | <our statement>. **Stated** ([source](https://github.com/<owner>/<repo>/blob/<40-hex sha>/<path>#L<line>)) or **Inference** | <our matching problem, citing the owning surface by path, or `none`> | **<disposition>:** <reason; for `already have`, our surface; for `adapt`, what changes> |

## License notice

<What the license file, the manifest field and the host each say, any disagreement, and that no
upstream text or code is copied. With no license found: ideas only.>

- **Pointer**: <the license file at the pin, or the place its absence was checked>
- **As of**: YYYY-MM-DD
- **Recheck trigger**: <the license file or manifest field changes, or a tracking issue changes state>
