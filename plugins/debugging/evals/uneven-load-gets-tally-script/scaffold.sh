#!/usr/bin/env bash
# A thumbnail service whose six workers share one queue. replay.py replays last night's queue
# (queue/last-night.jsonl) against a local simulation of the cluster, in a fresh arrival order each
# pass, and exits 1 when a worker passes its memory limit. pick_worker routes by album, and the
# four albums of large RAW photos all land on workers 2 and 5.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore README.md thumbs queue replay.py
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p thumbs queue

cat >README.md <<'MD'
# thumbs

Six workers render thumbnails from one shared queue.

Replay last night's queue against the local cluster simulation:

    python3 replay.py            # a fresh arrival order each pass
    python3 replay.py --seed 7   # a fixed order

Each line is one job and the worker it went to. Exit 1 means a worker passed its memory limit.
MD

printf '__pycache__/\n' >.gitignore

cat >thumbs/__init__.py <<'PY'
PY

cat >thumbs/dispatch.py <<'PY'
import zlib

WORKERS = 6


def pick_worker(job):
    """Send every job of one album to the same worker, so its cache stays warm."""
    return zlib.crc32(job["album"].encode()) % WORKERS
PY

cat >thumbs/cluster.py <<'PY'
MEMORY_LIMIT_MB = 512


class Worker:
    """A worker keeps each rendered thumbnail set in memory until the nightly flush."""

    def __init__(self, index):
        self.index = index
        self.held_mb = 0
        self.dead = False

    def take(self, job):
        if self.dead:
            return False
        self.held_mb += job["mb"]
        if self.held_mb > MEMORY_LIMIT_MB:
            self.dead = True
        return True
PY

cat >replay.py <<'PY'
import argparse
import json
import random
import sys

from thumbs.cluster import MEMORY_LIMIT_MB, Worker
from thumbs.dispatch import WORKERS, pick_worker


def main():
    parser = argparse.ArgumentParser(description="Replay last night's queue")
    parser.add_argument("--seed", type=int, default=None)
    args = parser.parse_args()
    with open("queue/last-night.jsonl", encoding="utf-8") as handle:
        jobs = [json.loads(line) for line in handle if line.strip()]
    random.Random(args.seed).shuffle(jobs)
    workers = [Worker(i) for i in range(WORKERS)]
    lost = 0
    for job in jobs:
        worker = workers[pick_worker(job)]
        if not worker.take(job):
            lost += 1
            continue
        print(f"job {job['id']} album={job['album']} size={job['mb']}MB -> worker {worker.index}")
        if worker.dead:
            print(f"worker {worker.index} OOM-killed at {worker.held_mb} MB (limit {MEMORY_LIMIT_MB} MB)")
    print(f"replayed {len(jobs)} jobs, {lost} lost")
    return 1 if any(w.dead for w in workers) else 0


if __name__ == "__main__":
    sys.exit(main())
PY

python3 -I - <<'PY'
import json
import random

rng = random.Random(20261106)
albums = [(name, 12, 30, 44) for name in ("raw-wedding-0611", "raw-studio-1104", "raw-portraits-1106", "raw-derby-1107")]
albums += [(name, 20, 2, 6) for name in ("phone-dinner", "phone-dogs", "phone-kids", "phone-park", "phone-office", "phone-cafe", "phone-market", "phone-zoo", "phone-hike")]
jobs = []
for name, count, low, high in albums:
    for _ in range(count):
        jobs.append({"album": name, "mb": rng.randint(low, high)})
rng.shuffle(jobs)
with open("queue/last-night.jsonl", "x", encoding="utf-8") as handle:
    for number, job in enumerate(jobs, start=1):
        handle.write(json.dumps({"id": f"{number:04d}", **job}) + "\n")
PY

g add -A
g commit -q -m "feat: route thumbnail jobs by album for cache locality"
