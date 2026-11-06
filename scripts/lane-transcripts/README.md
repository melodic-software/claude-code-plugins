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
| `pull` | Copies every new `lane-transcript-*` artifact, then prunes | 0 done, including one that missed an artifact; 1 failed, and `ALERT:` on stderr when no pull succeeded in 5 days (a pull that missed an artifact and is that stale exits 1 too) |
| `status` | Prints the last successful pull, its age, and the store's size and counts as JSON | 1 and `ALERT:` when no pull succeeded in 5 days |
| `query` | Prints the metrics rows matching every filter given, as JSONL with the transcript's absolute path | 0 |
| `prune` | Applies retention alone | 0 |

`query` filters: `--lane` (the workflow file's stem, or `lane/job-id`), `--model` (a substring of
any model the leg used), `--outcome`, `--since` and `--until` (`YYYY-MM-DD`, inclusive). For
anything else, read `metrics.jsonl` with `jq`. No command prints transcript text.

`--outcome` takes `error` (every leg whose result has `is_error: true`), `success` (a `success`
subtype on a leg that did not error), another result `subtype` such as `error_max_turns`, or
`no-result`. It reads `is_error`, so a row stored with `outcome: success` and `is_error: true`
answers to `error`; the printed row keeps the values it was stored with.

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
message's `models` (its `modelUsage` keys), `outcome` (`error` when `is_error` is true, else the
`subtype`), `subtype`, `is_error`, `api_error_status` (`null` when the result carries none),
`num_turns`, `duration_ms` and token counts, the transcript's size, and its path (`null` once
pruned).

## What a pull takes

Artifacts are listed one name at a time, since the repository-wide artifact listing answers 500
for this repository. A name is `lane-transcript-<job-id>-<attempt>`: `TRANSCRIPT_JOB_IDS` in
`pull.mjs` holds every job-id an upload step passes, by workflow, including the `ci-workflows`
reusables this repository calls with the transcript key, and the pull lists each with attempts 1
to 3. `pull.test.mjs` fails when a workflow that calls `upload-lane-transcript` or such a
reusable is missing from that list, or a local job-id with no expression in it is, so a new upload
step adds its job-id there; a job-id that changes inside a reusable is not checked. One gap:
`pr-run-activity-read.yml`'s reuse summary puts the issue number in its job-id, which no fixed
list can name, so the pull does not reach it. Each name is listed newest first, back to the last
successful pull less 6 hours (7 days on the first pull), by the artifact's own `created_at`, so a
re-run attempt of an older run is still pulled. It skips an artifact it already holds, an expired one, one over 64 MiB, and one whose
run's head repository is not this repository: the public key is public, so a fork's run could seal
a record. A zip must hold exactly `transcript.json.gz.sealed`. A record that does not open for the
key, the artifact's run id and its job id (moved, tampered with, or sealed under a rotated key) is
counted as `sealed_mismatch` and skipped. The summary line counts each kind.

A `gh` call that fails is tried 3 times, 2 and then 4 seconds apart. An artifact whose download,
unzip or run read still fails counts as `fetch_failed` and the pull goes on. It has no metrics row
and the last success stays where it was, so the next pull lists back far enough to fetch it. The
last success is therefore the last complete pull: an artifact that keeps failing holds it until
the artifact expires at 7 days, and the 5-day alert can fire first. `last_error` names the count
and the calls that failed (`artifact-zip`, `artifact-unzip`, `run-read`).

Four outcomes fail the pull and leave the last success where it was, so the 5-day alert can fire:
a rate limit on any `gh` call, which is not retried (`rate-limited`), a listing page that still
fails after its tries (`artifact-list`, since skipping it would lose artifacts for good),
`MAX_LIST_CALLS` listing calls spent before every name reached the cutoff (`call-cap`: two pages a
name plus 25%, at least 400, out of the 5,000 REST requests an hour a user token gets), and a
window where
records failed to open and none opened or was already held (`key-mismatch`: the vault key and the
repository variable differ).

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
umask 077 && node .github/actions/open-lane-output/keygen.mjs --private-key-fd 3 3>"$XDG_RUNTIME_DIR/lane-transcript.key" >"$XDG_RUNTIME_DIR/lane-transcript.pub" && az keyvault secret set --vault-name kv-melo-github-prod --name lane-transcript-private-key --file "$(wslpath -w "$XDG_RUNTIME_DIR/lane-transcript.key")" -o none && gh variable set LANE_TRANSCRIPT_PUBLIC_KEY -R melodic-software/claude-code-plugins <"$XDG_RUNTIME_DIR/lane-transcript.pub"; rm -f "$XDG_RUNTIME_DIR/lane-transcript.key" "$XDG_RUNTIME_DIR/lane-transcript.pub"
```

The variable is set only after the private key is stored, so CI never seals to a key nobody holds.
`-o none` matters: `az keyvault secret set` otherwise prints the stored value. To rotate, run the
same line; transcripts sealed under the old key count as `sealed_mismatch` until they expire.

## Daily task

A systemd user timer on the laptop, kept in dotfiles beside `worktree-reap.timer`, runs `pull`
daily with `Persistent=true`, so a day the laptop was off runs at the next boot. A non-zero exit
leaves the unit failed, which `systemctl --user --failed` shows. A timer that never fires raises
nothing; `status` is the check for that.
