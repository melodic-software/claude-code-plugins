# Purge Workflow (destructive — confirm-gated)

Delete the auto-memory files for the current repo. This is irreversible. Never delete before
the confirmation gate in Step 3.

## Step 1: Resolve EVERY candidate directory

The store may be relocated by `autoMemoryDirectory`, which is read from **any** settings scope
(user, project, local, policy, `--settings`). Miss that and you purge the wrong place. So:

1. Read `autoMemoryDirectory` from every present settings scope (managed / local / project /
   user — the snapshot in SKILL.md lists which files exist; Read each). Expand `~/` to `$HOME`.
2. Resolve the default via the snapshot / `scope-report.sh` (slug-derived
   `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<project>/memory/` — the config root honors
   `CLAUDE_CONFIG_DIR`, so a config root relocated by it is the *expected* tree, not a flag).
3. Build the candidate set = the highest-precedence `autoMemoryDirectory` override if any set,
   plus the default. Include the default even when an override exists (older writes may remain
   there). De-duplicate.

## Step 2: Capture the exact manifest (and flag relocations)

Enumerate the files ONCE into an explicit list, and delete exactly that captured list in Step 4
— never re-glob at deletion time (a re-glob reopens a time-of-check/time-of-use gap and can
delete files created between the manifest and the delete). Capture regular files only (`-type f`
skips symlinks, so a symlinked `*.md` is never followed):

```bash
config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # honors a relocated config root
manifest=$(mktemp)
for dir in <resolved absolute candidate dirs from Step 1>; do
  [[ -d "$dir" ]] || continue
  case "$dir" in
  "$config_root/projects/"*) : ;; # expected default (or CLAUDE_CONFIG_DIR-relocated) tree
  *) echo "UNEXPECTED RELOCATION: $dir is outside $config_root/projects/ (from autoMemoryDirectory)" ;;
  esac
  find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null
done | sort -u >"$manifest"
```

Present to the user:

- Each directory and the **resolved absolute path** of every file in `$manifest` (with count).
- **Explicitly flag any `UNEXPECTED RELOCATION` line**: a candidate dir outside the config root's
  `projects/` tree came from an `autoMemoryDirectory` override that a project/local settings file
  can set — confirm the user intends to delete from that absolute path before proceeding, since
  it could point at an unrelated directory.
- That this deletes auto-memory notes only — **not** CLAUDE.md, rules, transcripts, or history.
- If `$manifest` is empty, report that there is nothing to purge and stop (no-op).

## Step 3: Confirmation gate

Ask for explicit confirmation, quoting the concrete manifest (and any `UNEXPECTED RELOCATION`
paths), e.g.:

> This will permanently delete N auto-memory file(s): `<abs path>/MEMORY.md`,
> `<abs path>/debugging.md`, … This cannot be undone. Type "yes" to proceed.

Proceed only on an unambiguous yes. Anything else — abort and change nothing. Never infer
consent from the original request; the gate is a separate, explicit step.

## Step 4: Delete the captured manifest

After confirmation, delete exactly the paths captured in `$manifest` in Step 2 — do not
re-enumerate, do not `find ... -delete`, do not `rm -rf` any directory:

```bash
while IFS= read -r file; do
  [[ -n "$file" ]] && rm -- "$file"
done <"$manifest"
rm -f "$manifest"
```

`rm -- "$file"` on a symlink removes the link, not its target; combined with the `-type f`
capture in Step 2, nothing outside the enumerated regular files is touched. Remove a
now-empty memory directory only if the user explicitly asked to remove the folder itself;
otherwise leaving the empty directory is harmless.

## Step 5: Report and offer follow-through

- Confirm what was deleted (files, directories).
- Purge removes existing notes but does **not** stop new ones. If the user wants to stay
  stateless, point to `disable` (or run it now if they ask) so Claude doesn't immediately
  re-accumulate memory.
- If the user wants to be stateless everywhere, summarize the Claude Desktop / claude.ai
  account store steps in [desktop.md](desktop.md) — that store is server-side and cannot be
  deleted from here.
