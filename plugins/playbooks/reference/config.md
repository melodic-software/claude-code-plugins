# playbooks: settings

The playbooks plugin's settings. Each key has two layers above its default:

1. the plugin's user config option of the same name (set per user, in `/plugin` or
   `pluginConfigs`);
2. the same key in the repository's `docs/conventions/playbooks.yaml`, which wins when set. Its
   schema is [`schemas/playbooks.schema.json`](../schemas/playbooks.schema.json).

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill resolves
each key in its own text, with no reader script, and reports one line naming the value and the
layer that supplied it.

**Root rule.** The repository file is read only when the working directory is inside a git working
tree whose root is neither `$HOME` nor an ancestor of it. Otherwise the repository layer is skipped
and the report says so.

**Unset and invalid values.** A literal, unexpanded `${user_config.<key>}` means the user config
layer is unset. A user config value equal to the default is reported as the default, since the two
cannot be told apart. A value outside the key's list, in either layer, is named with its layer and
resolves the default.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `described_problem` | `report`, `fix` | `report` | `/playbooks:fable-5`: the Communication section of its skill body and the "Assessment is a deliverable" section of `context/communication.md` | repository file over user config over default |

`described_problem` decides what happens when the user describes a problem without asking for a
change. `report` assesses, reports and offers the fix. `fix` makes the change and presents the
result. Under either value, a question or thinking out loud gets an assessment only, and a
destructive or outward-visible step waits for the user's consent. The model-adaptation chapters do
not read this key.
