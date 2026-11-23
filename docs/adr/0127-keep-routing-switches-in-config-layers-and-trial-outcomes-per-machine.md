# Keep routing switches in config layers and trial outcomes per machine

- Status: accepted
- Date: 2026-11-23
- Related: [#18345](https://github.com/melodic-software/claude-code-plugins/pull/18345) and
  [#18395](https://github.com/melodic-software/claude-code-plugins/pull/18395) (the change);
  owner interview and answers, 2026-11-22 and 2026-11-23 (Q42, Q50, Q51, Q55, Q66, Q6 of
  2026-11-23); [ADR 0126](0126-route-vendors-on-a-consensus-of-independent-current-benchmarks.md)
  (what routing decides)

## Context

Vendor routing needs three settings: whether routing recommends at all, whether trials on the
user's own work run, and whether Claude may hand a task to Codex or Gemini on its own. The third
lets a session start another vendor's CLI with write access on the user's subscription, so whoever
can set it controls that. Trial outcomes (a pair proven or failed per work type) are written while
sessions run, and a dotfiles-managed file must never be written at run time.

## Decision

1. **Three switches: `vendors.routing`, `vendors.trials` and `vendors.auto_delegation`**, resolved
   through the multi-agent config layers. Shipped defaults: routing on, trials off,
   auto-delegation off (Q50, Q51), so an installer never has another plan used without opting in.
2. **`vendors.auto_delegation` is read only from the user layer** (2026-11-23, Q6: a per-user
   opt-in). A team or personal-override value, both files inside a repository, is ignored with a
   note. The user layer is the file `role_map_file` names, `~/.config/multi-agent/role-map.yaml`
   on the owner's machines (dotfiles manages it).
3. **Route reaches `external-agents run` only through `skills/route/scripts/delegate`.** The script
   checks the setting again, refuses a `--user-file` inside a git work tree, and fixes every flag
   but product, `--use task|investigate`, `--model` and `--effort`; route's skill grant names that
   one script.
4. **Trial outcomes live in a per-machine state file in the plugin's data folder, outside dotfiles**
   (Q42, Q55). Records exist only while a trial runs, and the write is safe for concurrent
   sessions.
5. **A pair is proven again on each machine** (Q66). Outcome files stay machine-neutral, so a later
   sync is a folder copy, and nothing outside the plugin writes them.

## Alternatives considered

- **(a) Settings and outcomes in dotfiles.** One copy for every machine, but routing would write a
  managed file at run time, which the owner's dotfiles rule forbids. Not chosen (Q55).
- **(b) Auto-delegation settable at the team layer.** A repository's own config could then turn on
  write runs on its contributors' plans. Not chosen (2026-11-23, Q6).
- **(c) A broad `external-agents run` grant in route.** It would pre-approve `--add-dir`,
  `--unsandboxed`, `--resume` and a chosen prompt file. Not chosen: narrowed to the gated script
  after security review on #18395.
- **(d) Share proof across machines now.** It needs a writer outside the plugin or a synced
  dotfiles file. Not chosen: trials repeat per machine until a sync mechanism is decided (Q66).

## Consequences

- A new machine starts with no proven pairs and reruns trials.
- Turning auto-delegation on is one line in the user's own file; no repository can do it for them.
- Widening `delegate`'s accepted flags loosens a security control and needs the owner's decision.
