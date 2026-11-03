#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p src config deploy tools .work/review-target/design

cat > Cargo.toml <<'EOF'
[package]
name = "wxarchive"
version = "0.9.3"
edition = "2021"

[dependencies]
chrono = { version = "0.4", features = ["serde"] }
flate2 = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
EOF

cat > src/record.rs <<'EOF'
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Reading {
    pub station: String,
    pub ts: NaiveDateTime,
    pub temp_c: f32,
    pub humidity_pct: f32,
    pub wind_ms: f32,
    pub pressure_hpa: f32,
}
EOF

cat > src/ingest.rs <<'EOF'
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, Write};
use std::path::Path;

use crate::record::Reading;

/// Appends each reading on stdin to its station's file for the day in `ts`.
pub fn run(archive_root: &Path) -> io::Result<u64> {
    let mut written = 0;
    for line in io::stdin().lock().lines() {
        let line = line?;
        let reading: Reading = match serde_json::from_str(&line) {
            Ok(reading) => reading,
            Err(err) => {
                eprintln!("skipping bad line: {err}");
                continue;
            }
        };
        let dir = archive_root.join(&reading.station);
        fs::create_dir_all(&dir)?;
        let day = reading.ts.format("%Y-%m-%d");
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(dir.join(format!("{day}.ndjson")))?;
        writeln!(file, "{line}")?;
        written += 1;
    }
    Ok(written)
}
EOF

cat > src/main.rs <<'EOF'
mod ingest;
mod record;

use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_default();
    let root = PathBuf::from(args.next().unwrap_or_else(|| "/srv/wx/archive".into()));
    match command.as_str() {
        "ingest" => match ingest::run(&root) {
            Ok(count) => {
                println!("wrote {count} readings");
                ExitCode::SUCCESS
            }
            Err(err) => {
                eprintln!("ingest: {err}");
                ExitCode::FAILURE
            }
        },
        other => {
            eprintln!("unknown command: {other}");
            ExitCode::from(2)
        }
    }
}
EOF

cat > config/stations.toml <<'EOF'
[[station]]
id = "harbour-01"
clock = "utc"
utc_offset_minutes = 0

[[station]]
id = "ridge-02"
clock = "utc"
utc_offset_minutes = 0

[[station]]
id = "valley-03"
clock = "local"
utc_offset_minutes = -300

[[station]]
id = "airfield-04"
clock = "utc"
utc_offset_minutes = 0

[[station]]
id = "lakeside-05"
clock = "local"
utc_offset_minutes = -360

[[station]]
id = "summit-06"
clock = "local"
utc_offset_minutes = -420
EOF

cat > deploy/crontab <<'EOF'
MAILTO=wx-ops@example.invalid
* * * * * flock -n /run/wx/ingest.lock sh -c 'wxfetch --since 2m | /opt/wx/bin/wxarchive ingest /srv/wx/archive'
17 3 * * * /opt/wx/bin/wx-backup /srv/wx/archive
EOF

cat > tools/plot_station.py <<'EOF'
#!/usr/bin/env python3
"""Print one station's hourly mean temperature for one UTC day."""
import argparse
import json
import tomllib
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


def utc_offset(stations_path, station):
    with open(stations_path, "rb") as handle:
        for entry in tomllib.load(handle)["station"]:
            if entry["id"] == station:
                return timedelta(minutes=entry["utc_offset_minutes"])
    raise SystemExit(f"unknown station {station}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--station", required=True)
    parser.add_argument("--day", required=True)
    parser.add_argument("--archive", default="/srv/wx/archive")
    parser.add_argument("--stations", default="/etc/wx/stations.toml")
    args = parser.parse_args()

    offset = utc_offset(args.stations, args.station)
    hours = defaultdict(list)
    with open(Path(args.archive) / args.station / f"{args.day}.ndjson", encoding="utf-8") as handle:
        for line in handle:
            reading = json.loads(line)
            at = datetime.fromisoformat(reading["ts"]) - offset
            hours[at.hour].append(reading["temp_c"])
    for hour in sorted(hours):
        values = hours[hour]
        print(f"{hour:02d}:00 {sum(values) / len(values):6.2f}")


if __name__ == "__main__":
    main()
EOF

cat > .work/review-target/PLAN.md <<'EOF'
# Plan: compact the weather archive

## Brief

### Problem

`wxarchive ingest` appends each reading to one uncompressed file per station per day under
`/srv/wx/archive`. With six stations the file count is modest, but the network is growing to 120
stations this year and each file is several megabytes. The nightly `wx-backup` walk already takes
over two hours, and the volume will fill in about fourteen months at the planned station count.

### Goal

The archive stays small enough to back up nightly for five years at 120 stations, and the analysts'
tools keep working.

### Acceptance criteria

- AC1: Archived data takes at most a fifth of the space it takes today.
- AC2: `tools/plot_station.py` opens at most one archive file to read one station's readings for
  one day.
- AC3: After compaction every reading is present exactly once, and a reader never sees a segment the
  manifest does not list.
- AC4: The archive stays readable from Python with only the standard library, so analysts install
  nothing.

### Out-of-scope

- Re-reading or changing readings already sent to the national service.
- A query service or any network API over the archive.
- Sub-minute station sampling.

### Captured assumptions

- Quality bar: production
- One archive host. Ingest and compaction both run there from `deploy/crontab`.

## Proposal

### Recommendation

Move finished data into compressed hourly segments listed in a manifest.

- **Format:** gzip-compressed NDJSON, one reading per line, with the fields of `src/record.rs`
  unchanged.
- **Layout:** `/srv/wx/segments/YYYY/MM/DD/HH.ndjson.gz`, holding the readings of all stations for
  that hour, sorted by station and then `ts`.
- **Manifest:** `/srv/wx/segments/manifest.json`, an array of `{path, sha256, readings}`. A reader
  takes the manifest as the list of what exists.
- **Compaction:** a new `wxarchive compact` subcommand. It reads `manifest.json`, finds each hour
  that has ended and has no segment, builds that hour's segment from the station-day files, writes
  it through a temporary name and rename, appends the entry, and rewrites `manifest.json` through a
  temporary name and rename. Station-day files whose hours are all in segments are then deleted.

`tools/plot_station.py` reads the manifest to find what it needs for the requested day and filters
by station.

### Why this approach

A segment per hour keeps the file count flat as stations are added: about 8,760 files a year
whatever the network size, which is what `wx-backup` needs. In a test on last month's data from the
six current stations, gzip took the files to about 15 percent of their size, which meets AC1.

NDJSON keeps the line-at-a-time reading that the analysts' tools already do, and `gzip` and `json`
are both in the Python standard library, so AC4 holds with a two-line change in each tool. `flate2`
and `serde_json` are already in `Cargo.toml` for the Rust side.

### Alternatives considered

- **Parquet.** Smaller files and column pruning, but no reader in the Python standard library, so
  it fails AC4.
- **SQLite per month.** Single-file and queryable from the standard library, but a month's file is
  rewritten in place during compaction and defeats the incremental backup.
- **gzip the existing station-day files.** The smallest change, but at 120 stations it is over
  43,000 files a year, so the backup walk keeps growing.

### Load-bearing assumptions

- All stations report `ts` in UTC, so the hour in a reading's `ts` is the segment it belongs in.
- A reading arrives within an hour of its `ts`; `wxfetch` runs every minute and the station buffers
  hold less than that.
- A compaction pass over one full hour takes about eight minutes at 120 stations, from the same test
  scaled up.

### Rollout

1. Ship `wxarchive compact` and the reader change, with the tools preferring segments and using
   station-day files for anything not yet in the manifest.
2. Add `*/5 * * * * /opt/wx/bin/wxarchive compact` to `deploy/crontab`, so a finished hour reaches
   a segment promptly.
3. Backfill the last year, oldest first, by running compaction over a copy and comparing reading
   counts per station per day.
4. Point `wx-backup` at `/srv/wx/segments`.
EOF

cat > .work/review-target/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One new subcommand and an on-disk layout read by the existing tools.
EOF
