#!/usr/bin/env python3
"""The Kokoro-82M model, tokenizer and English voices that kokoro-assets.json pins: where they live under the plugin
data directory, which are missing, and fetching them with every file's sha256 checked. Standard library only.

usage: assets.py status [--data-dir DIR] [--model-dir DIR]   print the asset directory, then one line per missing
                                                             file; exit 1 if any
       assets.py fetch [--data-dir DIR] [--model-dir DIR]    download the missing files from the pinned revision
                                                             (/speech:setup apply)

--model-dir is the plugin's model_dir option: the folder that holds the kokoro-<revision> set in place of
<data>/models. Empty, or a placeholder the skill left unsubstituted, means unset.

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


def models_root(data, model_dir=None):
    """(folder, source): the model_dir option when set, else <data>/models."""
    if model_dir and model_dir.strip() and not model_dir.startswith('${'):
        return Path(model_dir.strip()).expanduser(), 'model_dir option'
    return Path(data) / 'models', 'plugin data directory'


def assets_dir(data, m=None, model_dir=None):
    """<models root>/kokoro-<first 12 of the revision>: a new pin downloads beside the old set."""
    m = m or manifest()
    return models_root(data, model_dir)[0] / f'kokoro-{m["revision"][:12]}'


def missing(data, m=None, model_dir=None):
    """Pinned files absent from the asset directory or of the wrong size (a full hash runs only on download)."""
    m = m or manifest()
    root = assets_dir(data, m, model_dir)
    return [rel for rel, meta in m['files'].items()
            if not ((root / rel).is_file() and (root / rel).stat().st_size == meta['size'])]


def voices(m=None):
    m = m or manifest()
    return sorted(Path(rel).stem for rel in m['files'] if rel.startswith('voices/'))


def fetch(data, m=None, log=sys.stderr, model_dir=None):
    """Download each missing file; raise RuntimeError naming the first file that fails or does not match its hash."""
    m = m or manifest()
    root = assets_dir(data, m, model_dir)
    for rel in missing(data, m, model_dir):
        meta = m['files'][rel]
        url = f'{m["source"]}/resolve/{m["revision"]}/{rel}'
        target = root / rel
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            raise RuntimeError(f'{rel}: the model folder {target.parent} could not be created: {e}') from e
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
    ap.add_argument('--model-dir')
    a = ap.parse_args(argv)
    try:
        data = pydeps.data_dir(a.data_dir)
    except pydeps.Broken as e:
        sys.stderr.write(f'speech: {e}\n')
        return 2
    if a.action == 'fetch':
        try:
            fetch(data, model_dir=a.model_dir)
        except RuntimeError as e:
            sys.stderr.write(f'speech: {e}\n')
            return 1
    gaps = missing(data, model_dir=a.model_dir)
    print(assets_dir(data, model_dir=a.model_dir))
    for rel in gaps:
        print(f'missing {rel}')
    return 1 if gaps else 0


if __name__ == '__main__':
    sys.exit(main())
