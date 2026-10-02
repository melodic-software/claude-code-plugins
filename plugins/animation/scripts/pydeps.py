#!/usr/bin/env python3
"""On-demand Python packages for the animation plugin, per docs/conventions/on-demand-dependencies (Python).
Standard library only: it installs and launches the packages the other scripts import.

usage: pydeps.py install [--data-dir DIR]             install requirements.txt unless already ready; the
                                                      SessionStart hook runs this, and so does the repair line
       pydeps.py run [--data-dir DIR] -- SCRIPT ...   run SCRIPT against the installed packages; never installs

exit codes: install 0 ready or installed, 1 broken (reason and repair line on stderr);
            run 2 packages not installed (repair line on stderr), else the script's own code

Both take --requirements FILE and --probe MODULE ... (defaults: ../requirements.txt, numpy cv2), which
the tests use to aim at a fixture lock.
"""
import argparse
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

PLUGIN = 'animation'
MIN_PYTHON = (3, 12)   # numpy 2.5 requires it
REQUIREMENTS = Path(__file__).resolve().parent.parent / 'requirements.txt'
PROBE = ('numpy', 'cv2')
PIP_TIMEOUT_S = 240   # under the hook's 300 s limit, so this timeout fires first and the failure path runs
STALE_PARTIAL_S = 2 * PIP_TIMEOUT_S


class Broken(Exception):
    pass


def data_dir(flag=None):
    """The plugin data directory, in the convention's order: the flag, $CLAUDE_PLUGIN_DATA when its last
    segment names this plugin, then <config dir>/plugins/data/<plugin>-<marketplace>."""
    if flag and not flag.startswith('${'):
        return Path(flag)
    env = os.environ.get('CLAUDE_PLUGIN_DATA')
    if env and re.fullmatch(rf'{PLUGIN}(-.*)?', Path(env).name):
        return Path(env)
    config = Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home() / '.claude')
    found = sorted((config / 'plugins' / 'data').glob(f'{PLUGIN}-*'))
    if len(found) != 1:
        raise Broken('cannot tell where the plugin data directory is; pass --data-dir "${CLAUDE_PLUGIN_DATA}"')
    return found[0]


def env_dir(data, requirements):
    """<data>/python/<first 12 hex of the lock's sha256>-<interpreter tag>: a new lock or a different Python
    installs beside the old set instead of changing a directory a running session may be using."""
    key = hashlib.sha256(Path(requirements).read_bytes()).hexdigest()[:12]
    return Path(data) / 'python' / f'{key}-{sys.implementation.cache_tag}'


def _env(packages):
    """The installed set is the only third-party path: with `-S` (no site-packages) and no inherited PYTHONPATH,
    an ambient numpy or cv2 can neither satisfy the probe nor stand in for the locked set at run time."""
    return {**os.environ, 'PYTHONPATH': str(packages)}


def loads(packages, probe):
    """Readiness is a load probe: the packages must import, not merely be present."""
    r = subprocess.run([sys.executable, '-S', '-c', 'import ' + ', '.join(probe)],
                       env=_env(packages), capture_output=True, text=True)
    return r.returncode == 0


def repair_line(data):
    cmd = [sys.executable, str(Path(__file__).resolve()), 'install', '--data-dir', str(data)]
    if sys.platform == 'win32':   # Windows PowerShell 5.1: call operator, single quotes doubled
        return '& ' + ' '.join("'" + part.replace("'", "''") + "'" for part in cmd)
    return shlex.join(cmd)


def _drop_stale_partials(target):
    """A `.partial-*` sibling untouched for longer than any live install runs was left by a killed one."""
    if not target.parent.is_dir():
        return
    cutoff = time.time() - STALE_PARTIAL_S
    for path in target.parent.glob(f'{target.name}.partial-*'):
        try:
            if path.stat().st_mtime < cutoff:
                shutil.rmtree(path, ignore_errors=True)
        except OSError:
            pass   # a concurrent install renamed or removed it first


def install(data, requirements=REQUIREMENTS, probe=PROBE):
    """Install the hash-locked packages into env_dir unless it already loads. Returns 'ready' or 'installed';
    raises Broken with the reason."""
    target = env_dir(data, requirements)
    if target.is_dir() and loads(target, probe):
        return 'ready'
    if sys.version_info < MIN_PYTHON:
        raise Broken(f'Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or later is required, this is '
                     f'{sys.version_info[0]}.{sys.version_info[1]} ({sys.executable})')
    target.parent.mkdir(parents=True, exist_ok=True)
    _drop_stale_partials(target)
    partial = target.with_name(f'{target.name}.partial-{os.getpid()}')
    try:
        if target.exists():
            shutil.rmtree(target)   # present but not loading: rebuild it rather than trust it
        try:
            r = subprocess.run(
                [sys.executable, '-m', 'pip', 'install', '--require-hashes', '--only-binary', ':all:', '--no-deps',
                 '--no-input', '--disable-pip-version-check', '--retries', '2', '--timeout', '30',
                 '--target', str(partial), '--requirement', str(requirements)],
                capture_output=True, text=True, timeout=PIP_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            raise Broken(f'pip install did not finish in {PIP_TIMEOUT_S} s')
        if r.returncode:
            tail = (r.stderr.strip().splitlines() or ['no output'])[-1]
            hint = ' (this Python has no pip: python -m ensurepip, or install your distribution\'s pip package)' \
                if 'No module named pip' in r.stderr else ''
            raise Broken(f'pip install --require-hashes failed: {tail}{hint}')
        if not loads(partial, probe):
            raise Broken(f'the installed packages do not import ({", ".join(probe)})')
        try:
            os.replace(partial, target)
        except OSError:
            if not (target.is_dir() and loads(target, probe)):   # a concurrent install may have won the rename
                raise Broken(f'could not move the installed packages into {target}')
        return 'installed'
    finally:
        shutil.rmtree(partial, ignore_errors=True)


def run(data, script_args, requirements=REQUIREMENTS):
    """Run a script with the installed packages on PYTHONPATH. Never installs: that is the hook's job."""
    target = env_dir(data, requirements)
    if not target.is_dir():
        sys.stderr.write(f'{PLUGIN}: the Python packages are not installed for {sys.implementation.cache_tag}. '
                         'Start a new Claude Code session, whose SessionStart hook installs them, or run: '
                         f'{repair_line(data)}\n')
        return 2
    return subprocess.run([sys.executable, '-S', *script_args], env=_env(target)).returncode


def floor_interpreter():
    """The interpreter the SessionStart hook installed under: the first of python3, python at the floor. A launcher
    started by an older `python3` hands over to it, so both resolve the same <interpreter tag> directory."""
    for name in ('python3', 'python'):
        found = shutil.which(name)
        if not found or (Path(found).stat().st_size == 0 and 'windowsapps' in found.lower()):
            continue
        floor = f'import sys; raise SystemExit(sys.version_info < {MIN_PYTHON})'
        if subprocess.run([found, '-c', floor], capture_output=True).returncode == 0:
            return found
    return None


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if sys.version_info < MIN_PYTHON and (other := floor_interpreter()):
        return subprocess.run([other, str(Path(__file__).resolve()), *argv]).returncode
    rest = argv[argv.index('--') + 1:] if '--' in argv else []
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('action', choices=('install', 'run'))
    ap.add_argument('--data-dir')
    ap.add_argument('--requirements', type=Path, default=REQUIREMENTS)
    ap.add_argument('--probe', nargs='+', default=PROBE)
    a = ap.parse_args(argv[:argv.index('--')] if '--' in argv else argv)
    if a.action == 'run' and not rest:
        ap.error('run needs a script after --')
    try:
        data = data_dir(a.data_dir)
    except Broken as e:
        sys.stderr.write(f'{PLUGIN}: {e}\n')
        return 1 if a.action == 'install' else 2
    if a.action == 'run':
        return run(data, rest, a.requirements)
    try:
        print(install(data, a.requirements, a.probe))
        return 0
    except Broken as e:
        sys.stderr.write(f'{PLUGIN}: {e}\nRepair with: {repair_line(data)}\n')
        return 1


if __name__ == '__main__':
    sys.exit(main())
