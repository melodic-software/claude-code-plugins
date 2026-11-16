#!/usr/bin/env bash
# An invoice worker started from a Procfile with a config file that names its queue, dead-letter
# directory and log. A job whose region has no tax rate fails, goes to the dead-letter directory with
# its error, and the worker still exits 0, so the run's own output shows nothing wrong.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore README.md Procfile config worker var
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p config worker var/queue

cat >README.md <<'MD'
# invoice-worker

Builds one invoice per queued order. The process list is in the Procfile.
MD

printf 'invoices: python3 -m worker.run --config config/worker.json\n' >Procfile
printf '__pycache__/\nout/\nvar/dead-letter/\nvar/log/\n' >.gitignore

cat >config/worker.json <<'JSON'
{
  "queue_dir": "var/queue",
  "out_dir": "out/invoices",
  "dead_letter_dir": "var/dead-letter",
  "log_file": "var/log/worker.log"
}
JSON

: >worker/__init__.py

cat >worker/tax.py <<'PY'
TAX_RATES = {
    "EN": 0.20,
    "SC": 0.20,
    "WA": 0.20,
}


def tax_for(region, amount):
    return round(amount * TAX_RATES[region], 2)
PY

cat >worker/run.py <<'PY'
import argparse
import json
import pathlib

from worker.tax import tax_for


def build_invoice(job):
    tax = tax_for(job["region"], job["amount"])
    return {"order": job["order"], "net": job["amount"], "tax": tax, "total": job["amount"] + tax}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    config = json.loads(pathlib.Path(parser.parse_args().config).read_text())
    out_dir = pathlib.Path(config["out_dir"])
    dead_dir = pathlib.Path(config["dead_letter_dir"])
    log_file = pathlib.Path(config["log_file"])
    for directory in (out_dir, dead_dir, log_file.parent):
        directory.mkdir(parents=True, exist_ok=True)
    with log_file.open("a") as log:
        for path in sorted(pathlib.Path(config["queue_dir"]).glob("*.json")):
            job = json.loads(path.read_text())
            try:
                invoice = build_invoice(job)
            except Exception as error:
                (dead_dir / path.name).write_text(path.read_text())
                (dead_dir / f"{path.stem}.error.txt").write_text(f"{type(error).__name__}: {error!r}\n")
                log.write(f"dead-letter {path.name}: {type(error).__name__}\n")
                continue
            (out_dir / path.name).write_text(json.dumps(invoice))
            log.write(f"invoiced {path.name}\n")
    print("worker finished")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

printf '{"order": "A-1001", "region": "EN", "amount": 120.0}\n' >var/queue/A-1001.json
printf '{"order": "A-1002", "region": "SC", "amount": 80.0}\n' >var/queue/A-1002.json
printf '{"order": "A-1003", "region": "NI", "amount": 95.0}\n' >var/queue/A-1003.json

g add -A
g commit -q -m "feat: build invoices from the order queue"
