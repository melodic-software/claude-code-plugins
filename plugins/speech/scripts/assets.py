#!/usr/bin/env python3
"""The Kokoro-82M model, tokenizer and English voices that kokoro-assets.json pins: where they live under the plugin
data directory, which are missing, and fetching them with every file's sha256 checked. Standard library only.

usage: assets.py status [--data-dir DIR]   print the asset directory, then one line per missing file; exit 1 if any
       assets.py fetch [--data-dir DIR]    download the missing files from the pinned revision (/speech:setup apply)

A file is written as <name>.partial, hashed while it downloads, and renamed into place only when its sha256 matches,
so an interrupted or tampered download never looks present.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

import pydeps

MANIFEST = Path(__file__).resolve().parent / 'kokoro-assets.json'
CHUNK = 1 << 20


def manifest(path=MANIFEST):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def assets_dir(data, m=None):
    """<data>/models/kokoro-<first 12 of the revision>: a new pin downloads beside the old set."""
    m = m or manifest()
    return Path(data) / 'models' / f'kokoro-{m["revision"][:12]}'


def missing(data, m=None):
    """Pinned files absent from the asset directory or of the wrong size (a full hash runs only on download)."""
    m = m or manifest()
    root = assets_dir(data, m)
    return [rel for rel, meta in m['files'].items()
            if not ((root / rel).is_file() and (root / rel).stat().st_size == meta['size'])]


def voices(m=None):
    m = m or manifest()
    return sorted(Path(rel).stem for rel in m['files'] if rel.startswith('voices/'))


def fetch(data, m=None, log=sys.stderr):
    """Download each missing file; raise RuntimeError naming the first file that fails or does not match its hash."""
    m = m or manifest()
    root = assets_dir(data, m)
    for rel in missing(data, m):
        meta = m['files'][rel]
        url = f'{m["source"]}/resolve/{m["revision"]}/{rel}'
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_name(target.name + '.partial')
        log.write(f'speech: downloading {rel} ({meta["size"] / 1e6:.1f} MB)\n')
        digest = hashlib.sha256()
        try:
            with urllib.request.urlopen(url, timeout=60) as response, open(partial, 'wb') as out:
                while block := response.read(CHUNK):
                    digest.update(block)
                    out.write(block)
            if digest.hexdigest() != meta['sha256']:
                raise RuntimeError(f'{rel}: sha256 {digest.hexdigest()} does not match the pinned {meta["sha256"]}')
            os.replace(partial, target)
        except OSError as e:
            raise RuntimeError(f'{rel}: download from {url} failed: {e}') from e
        finally:
            partial.unlink(missing_ok=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('action', choices=('status', 'fetch'))
    ap.add_argument('--data-dir')
    a = ap.parse_args(argv)
    try:
        data = pydeps.data_dir(a.data_dir)
    except pydeps.Broken as e:
        sys.stderr.write(f'speech: {e}\n')
        return 2
    if a.action == 'fetch':
        try:
            fetch(data)
        except RuntimeError as e:
            sys.stderr.write(f'speech: {e}\n')
            return 1
    gaps = missing(data)
    print(assets_dir(data))
    for rel in gaps:
        print(f'missing {rel}')
    return 1 if gaps else 0


if __name__ == '__main__':
    sys.exit(main())
