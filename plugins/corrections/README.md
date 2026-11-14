# corrections

A Claude Code plugin that turns a recurring correction into a check that
enforces it. A check is only worth recording once it is proven to fail on the
mistake it targets and to pass on the current code.

| Skill | What it does |
|---|---|
| `/corrections:codify "<description>" [#PR]` | Counts how often the mistake recurs, picks the strongest enforcement-ladder rung, places the lesson by scope, and proposes a check proven with `prove-check.sh` |
| `/corrections:codify findings <findings-file>` | Takes each row of one review findings file through the same steps, ending in one proposal per row |
| `/corrections:codify reviews [--pr <n> [--repo <owner/repo>]]` | Mines recent merged pull requests' review comments, through `/source-control:pull-request review-comments`, and takes each lesson that recurs through the same steps; with `--pr`, one chosen pull request (open ones too), whose every lesson goes on labeled as from one PR, still for your approval; with `--repo` naming another repository than the checkout, it lists the lessons and proposes nothing |
| `/corrections:codify preferences [--scope machine\|project] [--since <day>]` | With the `session-flow` plugin installed, reads your typed turns through `/session-flow:audit-sessions excerpts-only`, counts each preference by distinct session, and proposes each one you confirm as a line for a user-scope file, never a repository file |
| `/corrections:codify note [--applied] "<observation>" [#PR \| <commit>]` | Appends one observation, or with `--applied` one change already made, to the findings buffer |
| `/corrections:codify group [--by <field>[,<field>...]] [--since <UTC ISO-8601>]` | Reads the buffer and groups its rows by the named fields (default `producer`) and by mistake, naming the keys, each mistake's count next to the threshold; writes nothing |

`codify` counts at `recurrence.min_occurrences` occurrences (default 2, at most 1000; set it in
`corrections.yaml` in the convention home, default `docs/conventions`, or `corrections.local.yaml`
there for yourself), or at once on a person's direct "codify this". A person's
invocation writes the proposal; a model invocation only proposes. It asks before installing any
blocking check, and reports a check whose proof did not fail on the old ref and pass on the new one as
unproven. A proposal states the existing violations of its check or rule and offers their cleanup
in the same change; `ratchet_offer` (default on) adds the `/toolchain:ratchet` offer on a counting
rung when they are too many for that, and `review_mining_prs` (default 20, from 2 to 200) sets how
many merged pull requests `reviews` reads without `--pr`. Each is a plugin option, and `corrections.yaml` wins over it.

| Script | What it does |
|---|---|
| `scripts/prove-check.sh` | Runs a proposed check in temporary worktrees at two refs and exits 0 only when it fails at the old ref and passes at the new one |
| `scripts/codify-settings.mjs` | Prints `recurrence.min_occurrences`, `ratchet_offer` and `review_mining_prs` and the layer that set each, resolved through the config cascade (schema `schemas/corrections.schema.json`) |
| `scripts/group-findings.mjs [--by <field>[,<field>...]] [--since <UTC ISO-8601>] [--rows]` | Runs `buffer.sh read` and prints its rows grouped by the named top-level fields (default `producer`): the keys first, then each group with its row and occurrence counts (distinct `source_id`) and its members |

## prove-check

```shell
plugins/corrections/scripts/prove-check.sh --check '<command>' --old <ref> [--new <ref>]
```

Run it from inside the repository the refs belong to. It runs `<command>`
through `bash -c` in a temporary worktree at `<old>`, which must exit
non-zero, and in one at `<new>` (default `HEAD`), which must exit 0. It prints
both exit codes, sends the check's own output to stderr, and removes both
worktrees on every exit path.

| Exit | Meaning |
|---|---|
| 0 | The proof holds: the check fails at `<old>` and passes at `<new>` |
| 1 | The proof fails: the check passes at `<old>`, or fails at `<new>` |
| 2 | Usage or environment error (bad argument, unknown ref, not a repository) |

A check that exits 126 or 127 at `<old>` counts as failing, as any non-zero
exit does, but the script warns on stderr: the command probably did not run.

Run `scripts/prove-check.test.sh` to exercise it against a fixture repository.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install corrections@melodic-software
```

## Configuration

`note` writes findings-buffer rows, by default to `findings-buffer/` in the git common directory:
one file per clone, shared by its worktrees, never committed. No network.

The two `findings_buffer_adapter_*` options bind one repository's own findings-buffer adapter, in
user scope, where a repository cannot write. `buffer.sh` reads them from your user settings and
managed settings only, never from the environment or a session's `--settings` file, so setting them
either way has no effect. A plugin loaded outside the plugin cache (`--plugin-dir`) has no user settings to read,
so there only managed settings can set them.
`findings_buffer_adapter_repository` is that
repository's git common directory (`git rev-parse --path-format=absolute --git-common-dir` in its
main checkout) and `findings_buffer_adapter_path` the adapter directory relative to the checkout
root. The binding applies in that repository's main checkout and its worktrees, and in no other
repository, even one with the same layout, and wins over the repository's own binding file. The
adapter must resolve inside the current checkout, outside any repository nested in it. The
repository's `findings-buffer.yaml` and `findings-buffer.local.yaml` still name only adapters the
plugin ships. See `tools/findings-buffer/CONTRACT.md` "Core".

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `ratchet_offer` | boolean | `true` | When on (default), a /corrections:codify proposal on a rung that counts violations offers /toolchain:ratchet once the rule exists, for existing violations too many to clean up in the same change. Off leaves the offer out. A repository's <home>/corrections.yaml wins over this option. |
| `review_mining_prs` | number<br>*min 2, max 200* | `20` | How many recent merged pull requests /corrections:codify reviews reads for review comments; default 20, from 2 to 200. A repository's <home>/corrections.yaml wins over this option. |
| `findings_buffer_adapter_repository` | directory | *(none)* | Git common directory (git rev-parse --path-format=absolute --git-common-dir) of the one repository whose own findings-buffer adapter you trust. Applies in that repository's checkout and worktrees only. Unset: only adapters the plugin ships run. |
| `findings_buffer_adapter_path` | string | *(none)* | That repository's adapter directory, relative to the checkout root, holding executable append.sh and read.sh and a capabilities.json with schema_version 1.x. Set both options or neither. A path out of the checkout or into a nested repository is refused. |

### How to set these

Set the options above for `corrections@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
