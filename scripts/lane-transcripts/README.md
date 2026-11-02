# lane-transcripts

The transcript puller. CI keeps each lane leg's transcript for 7 days as a sealed artifact
([`upload-lane-transcript`](../../.github/actions/upload-lane-transcript/README.md)); this copies
them to a private sink outside CI, opens them with the private key, and keeps the sink's retention.
It runs daily on the laptop. Needs Node 22 or later, `gh` signed in, and `unzip`.

```bash
vault-exec --env LANE_TRANSCRIPT_PRIVATE_KEY=lane-transcript-private-key -- node scripts/lane-transcripts/pull.mjs pull
node scripts/lane-transcripts/pull.mjs status
node scripts/lane-transcripts/pull.mjs query --lane pr-verify --model opus --outcome success --since 2026-11-01
node scripts/lane-transcripts/pull.mjs prune
```

| Command | Does | Exit |
|---|---|---|
| `pull` | Copies every new `lane-transcript-*` artifact, then prunes | 0 done; 1 failed, and `ALERT:` on stderr when no pull succeeded in 5 days |
| `status` | Prints the last successful pull, its age, and the store's size and counts as JSON | 1 and `ALERT:` when no pull succeeded in 5 days |
| `query` | Prints the metrics rows matching every filter given, as JSONL with the transcript's absolute path | 0 |
| `prune` | Applies retention alone | 0 |

`query` filters: `--lane` (the workflow file's stem, or `lane/job-id`), `--model` (a substring of
any model the leg used), `--outcome` (the result message's `subtype`: `success`, `error_max_turns`,
..., or `no-result`), `--since` and `--until` (`YYYY-MM-DD`, inclusive). For anything else, read
`metrics.jsonl` with `jq`. No command prints transcript text.

## The sink

One value names it: `--sink DIR`, else `LANE_TRANSCRIPT_SINK`, else
`$XDG_DATA_HOME/lane-transcripts` (`~/.local/share/lane-transcripts`). Another sink, such as another
machine or object storage, is any directory it mounts at; nothing else changes. Directories are
0700 and files 0600.

```text
<sink>/transcripts/<YYYY-MM-DD>/<lane>/<run id>-<attempt>-<job id>.json.gz   the CLI messages, gzipped
<sink>/metrics.jsonl                                                       one row per transcript, no content
<sink>/state.json                                                          last success, last attempt, last error kind
```

A metrics row holds the artifact, run, attempt and job ids, lane, workflow name, event, branch,
the run's conclusion when pulled, `created_at` and `date`, the init message's `model`, the result
message's `models` (its `modelUsage` keys), `outcome`, `is_error`, `num_turns`, `duration_ms` and
token counts, the transcript's size, and its path (`null` once pruned).

## What a pull takes

Artifacts are listed newest first, back to the last successful pull less 6 hours (7 days on the
first pull). It skips an artifact it already holds, an expired one, one over 64 MiB, and one whose
run's head repository is not this repository: the public key is public, so a fork's run could seal
a record. A zip must hold exactly `transcript.json.gz.sealed`. A record that does not open for the
key, the artifact's run id and its job id (moved, tampered with, or sealed under a rotated key) is
counted as `sealed_mismatch` and skipped. The summary line counts each kind.

## Retention

Every pull, and `prune`, applies it in this order:

1. A transcript over 30 days old is deleted; its row stays, with `transcript: null`.
2. A metrics row over 365 days old is dropped.
3. While every file under the sink totals more than 5 GB (5,000,000,000 bytes), the oldest
   transcript is deleted.

A file no row names ages by its modification time.

## Key setup

The pair is X25519 in the [`seal-lane-output`](../../.github/actions/seal-lane-output/README.md#format)
format. The private key lives in Key Vault `kv-melo-github-prod` as `lane-transcript-private-key`,
which `vault-exec` reads once the dotfiles map `.chezmoidata/vault-secrets.yaml` lists it there.

From the repository root, on WSL (`az` is the Windows binary, so it reads the key file through a
`\\wsl.localhost` path; `$XDG_RUNTIME_DIR` is memory-backed):

```bash
umask 077 && { node .github/actions/open-lane-output/keygen.mjs --private-key-fd 3 | gh variable set LANE_TRANSCRIPT_PUBLIC_KEY -R melodic-software/claude-code-plugins; } 3>"$XDG_RUNTIME_DIR/lane-transcript.key" && az keyvault secret set --vault-name kv-melo-github-prod --name lane-transcript-private-key --file "$(wslpath -w "$XDG_RUNTIME_DIR/lane-transcript.key")" -o none; rm -f "$XDG_RUNTIME_DIR/lane-transcript.key"
```

`-o none` matters: `az keyvault secret set` otherwise prints the stored value. To rotate, run the
same line; transcripts sealed under the old key count as `sealed_mismatch` until they expire.

## Daily task

A systemd user timer on the laptop, kept in dotfiles beside `worktree-reap.timer`, runs `pull`
daily with `Persistent=true`, so a day the laptop was off runs at the next boot. A non-zero exit
leaves the unit failed, which `systemctl --user --failed` shows. A timer that never fires raises
nothing; `status` is the check for that.
