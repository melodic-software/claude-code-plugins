# Disable Workflow

Turn auto memory off durably. This edits a settings file, so confirm the target scope first
and never edit silently.

## Step 1: Confirm the scope

Ask which reach the user wants; recommend based on intent:

- **Machine-wide (RECOMMENDED for "make Claude stateless")** → user settings at
  `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`. Applies to every project on this machine.
  Honor `CLAUDE_CONFIG_DIR`: when it is set, the user config root (and this file) live under it,
  not `~/.claude` — the SKILL.md snapshot reports the resolved path.
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
settings="<chosen settings.json path>"   # user scope: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
mkdir -p "$(dirname "$settings")"          # project/local .claude/ may not exist yet
tmp=$(mktemp)
{ cat "$settings" 2>/dev/null || echo '{}'; } |
  jq '.autoMemoryEnabled = false
      | .env = ((.env // {}) + {"CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"})' >"$tmp" &&
  mv "$tmp" "$settings" || { rm -f "$tmp"; echo "jq merge failed — fall back to a careful manual edit"; }
```

The `mkdir -p` matters for a repo/local scope whose `.claude/` directory does not exist yet —
without it the `mv` fails. `jq` reformats the file (2-space JSON) — acceptable for a
machine-managed settings file. If `jq` is unavailable, Read the file and edit it by hand
(creating the parent directory first): add/set exactly these two keys, leave every other key
and any existing `env` entries intact, and keep the trailing newline.

An even stronger, session-independent lever is a real **OS environment variable**
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` (e.g. `setx` on Windows, a shell profile export on
Unix). Offer it when the user wants disablement that survives outside Claude Code's settings;
it is OS-specific and outside a settings file, so present the command, don't run it blind.

## Step 3: Dotfile / config-management backfill

A user-scope `settings.json` is often tracked by a dotfile manager. If it is, a live edit
must be backfilled to the source of truth — do not leave the tracked file drifted, and never
run an `apply` that could revert your edit.

Detect and route generically (repo-agnostic — no single manager assumed). Three concrete
detectors — chezmoi and yadm track real files and answer path queries; GNU stow (and
similar) manages via symlinks, so a symlinked settings file is the discriminator:

```bash
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
tracked=""
command -v chezmoi >/dev/null 2>&1 &&
  [[ -n "$(chezmoi managed "$settings" 2>/dev/null)" ]] && tracked="chezmoi"
[[ -z "$tracked" ]] && command -v yadm >/dev/null 2>&1 &&
  yadm ls-files --error-unmatch "$settings" >/dev/null 2>&1 && tracked="yadm"
[[ -z "$tracked" && -L "$settings" ]] &&
  tracked="symlink -> $(readlink "$settings") (GNU stow or a similar symlink manager)"
if [[ -n "$tracked" ]]; then
  echo "TRACKED by $tracked — backfill to the dotfiles source"
else
  fp=""
  [[ -e "$HOME/.chezmoiroot" || -d "$HOME/.local/share/chezmoi" ]] && fp="$fp chezmoi"
  [[ -d "$HOME/.local/share/yadm" ]] && fp="$fp yadm"
  [[ -e "$HOME/.stow-local-ignore" ]] && fp="$fp stow"
  [[ -d "$HOME/.dotbot" || -e "$HOME/install.conf.yaml" ]] && fp="$fp dotbot"
  if [[ -n "$fp" ]]; then
    echo "manager fingerprint present but binary/tracking not confirmed:$fp — verify manually before editing"
  else
    echo "no dotfile manager detected — manually managed settings file, no backfill needed"
  fi
fi
```

The fingerprint fallback matters when a manager's artifacts exist but its binary is not on
PATH (fresh shell, partial install): report it as unconfirmed rather than silently
concluding the file is unmanaged. If tracked, tell the user to backfill through their
dotfiles repo's own flow (chezmoi: its `add-dotfile` / drift-reconcile path; yadm:
`yadm add` + commit; stow: edit the file inside the stow package — the symlink already
points there), never an `apply`/`restow` from this session that could revert the live
edit. If nothing is detected, note that a manually managed settings file needs no backfill.

## Step 4: Confirm effect

- The `autoMemoryEnabled` change and `env` block take effect on the next session (env is read
  at startup; `/memory` also reflects the toggle). Tell the user a restart or new session
  applies it.
- Optionally re-run `status` to show the new posture.
- Disabling stops future writes; it does **not** delete existing memory files. If the user
  also wants the saved notes gone, point to `purge`.
