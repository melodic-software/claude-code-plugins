# Disable Workflow

Turn auto memory off durably. This edits a settings file, so confirm the target scope first
and never edit silently.

## Step 1: Confirm the scope

Ask which reach the user wants; recommend based on intent:

- **Machine-wide (RECOMMENDED for "make Claude stateless")** → user settings
  `~/.claude/settings.json`. Applies to every project on this machine.
- **This repo only** → project settings `<repo>/.claude/settings.json` (team-shared, committed)
  or local `<repo>/.claude/settings.local.json` (personal, gitignored). Ask which; local for a
  personal choice, project to disable it for everyone on the team.

Do not proceed until the scope is chosen.

## Step 2: Apply both levers

In the chosen settings file, set both. The env var is the authoritative lever (it overrides
`autoMemoryEnabled` per the docs); the setting is the persistent fallback that still holds and
keeps the `/memory` toggle consistent if the env var is later unset (see SKILL.md "Precedence"):

```json
{
  "autoMemoryEnabled": false,
  "env": {
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
  }
}
```

Merge into existing JSON — do not clobber other keys or an existing `env` block. Prefer a
deterministic merge over hand-editing. When `jq` is available, use it (it preserves every other
key and only adds/overwrites the two targets; it starts from `{}` when the file is absent):

```bash
settings="<chosen settings.json path>"
tmp=$(mktemp)
{ cat "$settings" 2>/dev/null || echo '{}'; } |
  jq '.autoMemoryEnabled = false
      | .env = ((.env // {}) + {"CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"})' >"$tmp" &&
  mv "$tmp" "$settings" || { rm -f "$tmp"; echo "jq merge failed — fall back to a careful manual edit"; }
```

`jq` reformats the file (2-space JSON) — acceptable for a machine-managed settings file. If `jq`
is unavailable, Read the file and edit it by hand: add/set exactly these two keys, leave every
other key and any existing `env` entries intact, and keep the trailing newline.

An even stronger, session-independent lever is a real **OS environment variable**
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` (e.g. `setx` on Windows, a shell profile export on
Unix). Offer it when the user wants disablement that survives outside Claude Code's settings;
it is OS-specific and outside a settings file, so present the command, don't run it blind.

## Step 3: Dotfile / config-management backfill

A user-scope `settings.json` is often tracked by a dotfile manager. If it is, a live edit
must be backfilled to the source of truth — do not leave the tracked file drifted, and never
run an `apply` that could revert your edit.

Detect and route generically (repo-agnostic — do not assume a specific manager):

```bash
command -v chezmoi >/dev/null 2>&1 && chezmoi managed "$HOME/.claude/settings.json" 2>/dev/null \
  && echo "TRACKED by chezmoi — backfill to the dotfiles source" \
  || echo "not chezmoi-tracked (check any other dotfile manager)"
```

If tracked, tell the user to backfill through their dotfiles repo's own flow (for chezmoi:
its `add-dotfile` / drift-reconcile path), not `chezmoi apply` from this session. If no
manager is detected, note that a manually managed settings file needs no backfill.

## Step 4: Confirm effect

- The `autoMemoryEnabled` change and `env` block take effect on the next session (env is read
  at startup; `/memory` also reflects the toggle). Tell the user a restart or new session
  applies it.
- Optionally re-run `status` to show the new posture.
- Disabling stops future writes; it does **not** delete existing memory files. If the user
  also wants the saved notes gone, point to `purge`.
