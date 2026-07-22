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

## Step 3: Confirmation gate (with backup offer)

Ask for explicit confirmation, quoting the concrete manifest (and any `UNEXPECTED RELOCATION`
paths), and offer an opt-in backup in the same question, e.g.:

> This will permanently delete N auto-memory file(s): `<abs path>/MEMORY.md`,
> `<abs path>/debugging.md`, … This cannot be undone. I can first copy these exact files to
> `<memory_dir>.bak-<UTC-timestamp>/` as a snapshot. If the backup fails, the deletion is
> cancelled too (you can re-confirm a plain delete afterwards). Type "yes" to delete, or
> "yes, with backup" to snapshot first.

Proceed only on an unambiguous yes. Anything else — abort and change nothing. Never infer
consent from the original request; the gate is a separate, explicit step.

**A bundled or earlier multi-option answer does NOT satisfy this gate.** Consent that rode
along in an upstream flow — an `/interview` round where "purge" was one bullet of a bundled
answer, a numbered menu selection (`"1"`) whose option happened to include the purge, or a
"go stateless and purge" given before the manifest existed — is materially weaker than this
gate's bar. The gate must restate the concrete, now-known scope (file count, directories)
and receive a fresh confirmation that references that scope specifically.

Worked anti-pattern: the user answers "go stateless and purge" in an early interview round;
later the manifest turns out to be 198 files. A follow-up menu offers "1) purge all 198
2) keep topic files", and the user replies `"1"`. That `"1"` is a menu selection made while
weighing other bundled concerns — not a scope-referencing confirmation of an irreversible
delete. Correct handling: raise this gate anyway, quote the 198 files and their directories,
and require a fresh "yes" (or "yes, with backup") before deleting anything.

## Step 4: Optional backup, then delete the captured manifest

**Backup first when the user opted in** ("yes, with backup"). Copy exactly the files
captured in `$manifest` — same no-re-glob discipline as the delete; never copy a directory
recursively. Each source directory gets its own sibling snapshot `<dir>.bak-<UTC>/`:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
total=$(grep -c . "$manifest")
copied=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  dest="$(dirname -- "$file").bak-$ts"
  mkdir -p -- "$dest" || { echo "BACKUP FAILED (mkdir): $dest" >&2; break; }
  cp -- "$file" "$dest/" || { echo "BACKUP FAILED (cp): $file" >&2; break; }
  copied=$((copied + 1))
done <"$manifest"
if [[ "$copied" -ne "$total" ]]; then
  echo "Backup incomplete ($copied/$total) — ABORTING: delete nothing." >&2
fi
```

Proceed to the delete ONLY when `copied == total`. On any shortfall (full disk,
permissions), abort the purge, report the partial snapshot's path, and change nothing —
the user can re-confirm a plain no-backup delete afterwards if they still want it.
`cp -- "$file"` on a manifest entry copies a regular file only (the Step 2 capture was
`-type f`); the backup lives beside the memory dir, outside it, so it is never re-matched
by a future purge's `-maxdepth 1` enumeration of the memory dir itself.

After confirmation (and the backup, when requested), delete exactly the paths captured in
`$manifest` in Step 2 — do not re-enumerate, do not `find ... -delete`, do not `rm -rf`
any directory:

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
- If a backup was taken, report its absolute path(s) (`<dir>.bak-<UTC>/`) and note the
  snapshot is the user's to keep or delete — the skill never auto-prunes it.
- Purge removes existing notes but does **not** stop new ones. If the user wants to stay
  stateless, point to `disable` (or run it now if they ask) so Claude doesn't immediately
  re-accumulate memory.
- If the user wants to be stateless everywhere, summarize the Claude Desktop / claude.ai
  account store steps in [desktop.md](desktop.md) — that store is server-side and cannot be
  deleted from here.
