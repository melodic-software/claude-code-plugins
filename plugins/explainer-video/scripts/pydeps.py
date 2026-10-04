#!/usr/bin/env python3
"""On-demand Python packages for the explainer-video plugin, per docs/conventions/on-demand-dependencies (Python).
Standard library only: it installs and launches the packages render.py imports.

usage: pydeps.py install [--data-dir DIR]             install requirements.txt unless already ready; the
                                                      SessionStart hook runs this, and so does the repair line
       pydeps.py run [--data-dir DIR] -- SCRIPT ...   run SCRIPT against the installed packages; never installs
       pydeps.py check [--data-dir DIR]               read-only PASS/FAIL rows: Python, ManimCE, ffmpeg, ffprobe

exit codes: install 0 ready or installed, 1 broken (reason and repair line on stderr);
            run 2 packages not installed (repair line on stderr), else the script's own code;
            check 0 every row passes, 1 a row fails

Both take --requirements FILE and --probe MODULE ... (defaults: ../requirements.txt, manim), which the tests use
to aim at a fixture lock. Whatever Python starts this script, it hands over to the first supported interpreter
on PATH, or on Windows listed by the py launcher, so the hook and every skill run resolve the same install directory.
"""
import argparse
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import sysconfig
import time
from pathlib import Path

PLUGIN = 'explainer-video'
PYTHONS = ((3, 12), (3, 13))   # moderngl and glcontext publish no 3.14 wheel, nor a free-threaded (cp313t) one
CANDIDATES = ('python3.13', 'python3.12', 'python3', 'python')
REQUIREMENTS = Path(__file__).resolve().parent.parent / 'requirements.txt'
PROBE = ('manim',)
# Built from their hash-pinned source archives because these platforms get no wheel: srt everywhere, pycairo on
# Linux and macOS, manimpango on Linux. Every other package is wheels only. Recorded in the convention's Exceptions.
BUILD_FROM_SOURCE = frozenset({'srt', 'pycairo', 'manimpango'})
PIP_TIMEOUT_S = 540   # under the hook's 600 s limit, so this timeout fires first and the failure path runs
STALE_PARTIAL_S = 2 * PIP_TIMEOUT_S
HANDED_OVER = 'EXPLAINER_VIDEO_PYDEPS_INTERPRETER'


class Broken(Exception):
    pass


def supported(version):
    return tuple(version[:2]) in PYTHONS


# Read at import: sysconfig loads its data lazily, keyed by sys.platform.
_FREE_THREADED = bool(sysconfig.get_config_var('Py_GIL_DISABLED'))


def free_threaded():
    return _FREE_THREADED


def wanted():
    return ' or '.join(f'{a}.{b}' for a, b in PYTHONS)


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


def pinned_names(requirements):
    return sorted({m.group(1).lower() for m in re.finditer(r'(?m)^([A-Za-z0-9][A-Za-z0-9._-]*)==',
                                                             Path(requirements).read_text(encoding='utf-8'))})


def binary_only(requirements):
    """Every pinned package except BUILD_FROM_SOURCE, for pip's --only-binary."""
    return [n for n in pinned_names(requirements) if n not in BUILD_FROM_SOURCE]


def _env(packages):
    """The installed set is the only third-party path: with `-S` (no site-packages) and no inherited PYTHONPATH,
    an ambient copy can neither satisfy the probe nor stand in for the locked set at run time."""
    return {**os.environ, 'PYTHONPATH': str(packages)}


def _foreign_env(extra=None):
    """The environment for a different interpreter than this one. PYTHONHOME and PYTHONPATH name this interpreter's
    stdlib and module path, and a uv-managed Windows trampoline sets PYTHONHOME with a UV_INTERNAL__ marker beside
    it: passed on, a 3.12 or 3.13 child loads a 3.14 stdlib and dies on its first import."""
    keep = {k: v for k, v in os.environ.items()
            if k not in ('PYTHONHOME', 'PYTHONPATH') and not k.startswith('UV_INTERNAL__')}
    return {**keep, **(extra or {})}


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
    target.parent.mkdir(parents=True, exist_ok=True)
    _drop_stale_partials(target)
    partial = target.with_name(f'{target.name}.partial-{os.getpid()}')
    only_binary = binary_only(requirements)
    try:
        if target.exists():
            shutil.rmtree(target)   # present but not loading: rebuild it rather than trust it
        try:
            r = subprocess.run(
                [sys.executable, '-m', 'pip', 'install', '--require-hashes', '--no-deps',
                 *(['--only-binary', ','.join(only_binary)] if only_binary else []),
                 '--no-input', '--disable-pip-version-check', '--retries', '2', '--timeout', '30',
                 '--target', str(partial), '--requirement', str(requirements)],
                capture_output=True, text=True, timeout=PIP_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            raise Broken(f'pip install did not finish in {PIP_TIMEOUT_S} s')
        if r.returncode:
            tail = (r.stderr.strip().splitlines() or ['no output'])[-1]
            hint = ' (this Python has no pip: python -m ensurepip, or install your distribution\'s pip package)' \
                if 'No module named pip' in r.stderr else ''
            if re.search(r'pkg-config|cairo|pango|[Cc]ompiler', r.stderr):
                hint += (' (pycairo and manimpango build from source here: install a C compiler, pkg-config and '
                         'the cairo and pango development packages; see the plugin README)')
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


def check(data, requirements=REQUIREMENTS, probe=PROBE):
    """Read-only: one PASS/FAIL row per prerequisite of a render. Returns the exit code, 1 when any row fails."""
    target = env_dir(data, requirements)
    rows = [('PASS', f'Python {sys.version_info[0]}.{sys.version_info[1]}', sys.executable)]
    if target.is_dir() and loads(target, probe):
        rows.append(('PASS', 'ManimCE', str(target)))
    else:
        rows.append(('FAIL', 'ManimCE', f'not installed for {sys.implementation.cache_tag}; the SessionStart hook '
                                        f'installs it, or run: {repair_line(data)}'))
    for tool in ('ffmpeg', 'ffprobe'):
        found = shutil.which(tool)
        rows.append(('PASS', tool, found) if found else
                     ('FAIL', tool, 'not on PATH; install FFmpeg (https://ffmpeg.org/download.html), which ships both'))
    for row in rows:
        print('  '.join(row))
    return 1 if any(r[0] == 'FAIL' for r in rows) else 0


def _runs_supported(path):
    probe = (f'import sys, sysconfig; raise SystemExit(sys.version_info[:2] not in {PYTHONS} '
             'or bool(sysconfig.get_config_var("Py_GIL_DISABLED")))')
    try:
        return subprocess.run([path, '-c', probe], env=_foreign_env(), capture_output=True).returncode == 0
    except OSError:
        return False


def _launcher_listed():
    """On Windows, the python.exe paths the py launcher lists with `py -0p` (--list-paths), in its order. A
    python.org install registers there and puts no python3.13.exe on PATH. Listing, unlike `py -3.13`, launches
    nothing: the Python install manager installs a requested version when no runtime is installed yet."""
    launcher = shutil.which('py') if sys.platform == 'win32' else None
    if not launcher:
        return []
    try:
        r = subprocess.run([launcher, '-0p'], env=_foreign_env(), capture_output=True, text=True, errors='replace')
    except OSError:
        return []
    if r.returncode:
        return []
    return re.findall(r'(?im)^\s*-\S+\s+(?:\*\s+)?([a-z]:\\.*?\.exe)\b', r.stdout)


def interpreter():
    """The first supported interpreter: CANDIDATES on PATH in order, then on Windows each one the py launcher lists.
    The hook and every run hand over to it, so both resolve the same <interpreter tag> directory."""
    for name in CANDIDATES:
        found = shutil.which(name)
        if not found or ('windowsapps' in found.lower() and Path(found).stat().st_size == 0):
            continue
        if _runs_supported(found):
            return found
    return next((path for path in _launcher_listed() if _runs_supported(path)), None)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not os.environ.get(HANDED_OVER):
        chosen = interpreter()
        if chosen and Path(chosen).resolve() != Path(sys.executable).resolve():
            return subprocess.run([chosen, str(Path(__file__).resolve()), *argv],
                                  env=_foreign_env({HANDED_OVER: chosen})).returncode
    rest = argv[argv.index('--') + 1:] if '--' in argv else []
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('action', choices=('install', 'run', 'check'))
    ap.add_argument('--data-dir')
    ap.add_argument('--requirements', type=Path, default=REQUIREMENTS)
    ap.add_argument('--probe', nargs='+', default=PROBE)
    a = ap.parse_args(argv[:argv.index('--')] if '--' in argv else argv)
    if a.action == 'run' and not rest:
        ap.error('run needs a script after --')
    failed = 2 if a.action == 'run' else 1
    if not supported(sys.version_info) or free_threaded():
        where = 'on PATH or listed by the py launcher (py -0p)' if sys.platform == 'win32' else 'on PATH'
        this = f'{sys.version_info[0]}.{sys.version_info[1]}{"t" if free_threaded() else ""}'
        sys.stderr.write(f'{PLUGIN}: Python {wanted()} is required and none is {where} (this is '
                         f'{this}, {sys.executable}). Install one from '
                         'https://www.python.org/downloads/ and start a new session.\n')
        return failed
    try:
        data = data_dir(a.data_dir)
    except Broken as e:
        sys.stderr.write(f'{PLUGIN}: {e}\n')
        return failed
    if a.action == 'run':
        return run(data, rest, a.requirements)
    if a.action == 'check':
        return check(data, a.requirements, a.probe)
    try:
        print(install(data, a.requirements, a.probe))
        return 0
    except Broken as e:
        sys.stderr.write(f'{PLUGIN}: {e}\nRepair with: {repair_line(data)}\n')
        return 1


if __name__ == '__main__':
    sys.exit(main())
