# Config-hook install (`scope=user`)

Installs the `commit-msg-convention` entry once for the user, as a git config hook that loads
under an `includeIf` the operator chooses. It then covers every clone and linked worktree the
condition matches, and runs beside lefthook, husky, the pre-commit framework or a
`core.hooksPath` setup, with no edit to any repository. Only the `commit-msg` entry installs
this way; `pre-commit-content` and `reference-verify` keep the `local` and `shared` scopes.

**Git floor: 2.54.** The install needs git 2.54 or later; a git below 2.54 ignores `hook.*` silently.
The block loads, the hook never runs, and nothing reports it. Pointer:
<https://git-scm.com/docs/git-hook/2.54.0#_configuration>, as of 2026-10-29; recheck trigger: a
git release that changes the `hook.<name>.*` keys.

## Where it lives

- **Stable copy:** `$XDG_CONFIG_HOME/git/checks/guardrails/`, which is
  `~/.config/git/checks/guardrails/` when `XDG_CONFIG_HOME` is unset. It holds
  `commit-msg-convention.sh`, `check-lib.sh`, the resolver assets and `hooks.gitconfig`, the
  include file with the hook block. It sits outside every repository, so removing a clone or a
  worktree leaves it in place. A plugin update reaches it only when the install reruns;
  `verify` reports the entry `stale` until then.
- **Friendly name:** `guardrails-commit-msg-convention`, the `<plugin>-<entry>` name the lefthook
  job uses too.

## Steps

1. **Condition.** Ask the operator which repositories the hook covers, as an `includeIf`
   condition: `gitdir:~/work/` covers every repository under `~/work/`, and its linked worktrees
   too, since `gitdir` matches a worktree's git directory inside its main repository. Use
   `gitdir/i:` on Windows. Pointer:
   <https://git-scm.com/docs/git-config#_conditional_includes>, as of 2026-10-29; recheck trigger:
   a git release that changes the `includeIf` keywords. When nobody can answer, stop and report:
   never pick a condition.
2. **Install.** Run `node "<installer>" config-hook --include-if '<condition>'` from a
   repository, `<installer>` being the `install.mjs` path the SKILL.md install steps run. It writes the stable copy and the include file
   and prints `dir`, `include`, one `installed` row per entry (`installed`, `refreshed`,
   `unchanged` or `refused`) and `decisions[]`.
3. **Decisions.** Apply each, then rerun until none is left that you chose to apply:

   | Kind | What you do |
   |---|---|
   | `include-if` | On the operator's yes, run `git config --global --add '<key>' '<value>'`: the global config is theirs. A rerun finds the line and returns no decision, so the user config holds one `includeIf` line and the include file one hook block. |
   | `include-if-unmatched` | The line is in the global config, but this repository's git does not load it: `condition` does not match `repo`. Show both and ask whether to change the condition. |
   | `git-too-old` | Report `version` and `floor`: this git ignores the hook block until it is upgraded. |
   | `modified` | `file` is a locally edited stable copy. Show how it differs; rerun with `--force` only on the operator's yes. |

4. **Verify.** In a covered repository, `git hook list commit-msg` lists
   `guardrails-commit-msg-convention`, and `install.mjs verify` reports `ok` for
   `commit-msg-convention`. A repository that also has the entry at `local` or `shared` scope runs
   it twice: offer to remove that registration, as the decline paragraph in `SKILL.md` describes.

## Skipping and removing

The only skip is the `checks.skipmissing` git config key, for one command and only while a
check's tool is missing (`git -c checks.skipmissing=<tool> commit ...`), as the check-placement
convention defines. This install adds no environment variable and no other skip.
`commit-msg-convention` needs no tool, so a failing subject is rewritten, never skipped.

To remove the install, run `git config --global --fixed-value --unset '<key>' '<value>'` with the
`include-if` decision's `key` and `value` (the condition may carry other includes), then delete the
stable copy's directory, on the operator's yes.
