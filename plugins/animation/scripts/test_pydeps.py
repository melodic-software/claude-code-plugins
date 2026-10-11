# test-scope: plugins/animation/skills/*/SKILL.md plugins/animation/skills/*/scripts/* plugins/animation/scripts/* plugins/animation/hooks/*.sh
"""pydeps.py: the hash-locked on-demand install (first install, no-op rerun, a failed install) and the run launcher.

The lock is a local wheel that provides the numpy and cv2 modules, installed with pip's own PIP_NO_INDEX and
PIP_FIND_LINKS, so no test reaches a package index. `python test_pydeps.py --make-wheel DIR` builds that wheel and
prints its sha256, for the hook suite (../hooks/install-python-deps.test.sh).
"""
import base64
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
SCRIPT = HERE / 'pydeps.py'
NAME, VERSION = 'fakedeps', '1.0'
MODULES = {'numpy/__init__.py': 'VALUE = 42\n', 'cv2/__init__.py': 'VALUE = 7\n'}


def make_wheel(folder):
    """A pure-python wheel providing the numpy and cv2 modules; returns (wheel path, sha256 hex)."""
    dist = f'{NAME}-{VERSION}.dist-info'
    files = {
        **MODULES,
        f'{dist}/METADATA': f'Metadata-Version: 2.1\nName: {NAME}\nVersion: {VERSION}\n',
        f'{dist}/WHEEL': 'Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n',
    }
    record = ''.join(
        f'{p},sha256={base64.urlsafe_b64encode(hashlib.sha256(c.encode()).digest()).rstrip(b"=").decode()},{len(c)}\n'
        for p, c in files.items()) + f'{dist}/RECORD,,\n'
    path = Path(folder) / f'{NAME}-{VERSION}-py3-none-any.whl'
    with zipfile.ZipFile(path, 'w') as z:
        for p, c in {**files, f'{dist}/RECORD': record}.items():
            z.writestr(p, c)
    return path, hashlib.sha256(path.read_bytes()).hexdigest()


def lock_text(digest):
    return f'{NAME}=={VERSION} \\\n    --hash=sha256:{digest}\n'


def have_pip():
    return subprocess.run([sys.executable, '-m', 'pip', '--version'], capture_output=True).returncode == 0


@unittest.skipUnless(sys.version_info >= (3, 12) and have_pip(), 'needs Python 3.12 or later with pip')
class OnDemandInstall(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.wheels = self.tmp / 'wheels'
        self.wheels.mkdir()
        self.data = self.tmp / 'data'
        _, digest = make_wheel(self.wheels)
        self.lock = self.tmp / 'requirements.txt'
        self.lock.write_text(lock_text(digest), encoding='utf-8')
        self.env = {**os.environ, 'PIP_NO_INDEX': '1', 'PIP_FIND_LINKS': str(self.wheels)}

    def pydeps(self, action, *args, env=None):
        return subprocess.run([sys.executable, str(SCRIPT), action, '--requirements', str(self.lock), *args],
                              capture_output=True, text=True, env=env or self.env)

    def installs(self):
        return sorted(p.name for p in (self.data / 'python').glob('*')) if (self.data / 'python').is_dir() else []

    def test_first_install_then_run_against_it(self):
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)
        self.assertEqual(len(self.installs()), 1)
        script = self.tmp / 'use.py'
        script.write_text('import numpy, cv2\nprint(numpy.VALUE, cv2.VALUE)\n', encoding='utf-8')
        r = self.pydeps('run', '--data-dir', str(self.data), '--', str(script), env={**self.env, 'PYTHONPATH': ''})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, '42 7'), r.stderr)

    def test_second_session_is_a_no_op(self):
        self.assertEqual(self.pydeps('install', '--data-dir', str(self.data)).stdout.strip(), 'installed')
        before = self.installs()
        # Aim pip at an empty folder: a second pip run could not find the wheel and would fail.
        empty = self.tmp / 'empty'
        empty.mkdir()
        r = self.pydeps('install', '--data-dir', str(self.data), env={**self.env, 'PIP_FIND_LINKS': str(empty)})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'ready'), r.stderr)
        self.assertEqual(self.installs(), before)

    def test_changed_lock_installs_beside_the_old_set(self):
        self.pydeps('install', '--data-dir', str(self.data))
        self.lock.write_text(self.lock.read_text(encoding='utf-8') + '# bumped\n', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual(r.stdout.strip(), 'installed', r.stderr)
        self.assertEqual(len(self.installs()), 2)

    def test_a_wrong_hash_fails_with_the_reason_and_a_repair_line_and_leaves_nothing(self):
        self.lock.write_text(lock_text('0' * 64), encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual(r.returncode, 1)
        self.assertIn('animation: pip install --require-hashes failed', r.stderr)
        self.assertRegex(r.stderr, r'Repair with: .*pydeps\.py.* install --data-dir')
        self.assertEqual(self.installs(), [])

    def test_a_lock_without_hashes_is_refused(self):
        self.lock.write_text(f'{NAME}=={VERSION}\n', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.installs(), [])

    def test_a_set_that_stops_loading_is_rebuilt(self):
        self.pydeps('install', '--data-dir', str(self.data))
        (installed,) = (self.data / 'python').glob('*')
        (installed / 'cv2' / '__init__.py').write_text('raise ImportError("broken")\n', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)

    def test_ambient_packages_do_not_satisfy_the_probe(self):
        self.pydeps('install', '--data-dir', str(self.data))
        (installed,) = (self.data / 'python').glob('*')
        shutil.rmtree(installed / 'cv2')
        ambient =self.tmp / 'ambient'
        for name in ('numpy', 'cv2'):
            (ambient / name).mkdir(parents=True)
            (ambient / name / '__init__.py').write_text('', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data), env={**self.env, 'PYTHONPATH': str(ambient)})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)

    def test_run_never_installs(self):
        script = self.tmp / 'use.py'
        script.write_text('print("ran")\n', encoding='utf-8')
        r = self.pydeps('run', '--data-dir', str(self.data), '--', str(script))
        self.assertEqual(r.returncode, 2)
        self.assertIn('SessionStart hook installs them, or run:', r.stderr)
        self.assertEqual(r.stdout, '')
        self.assertEqual(self.installs(), [])


class DataDir(unittest.TestCase):
    def test_resolution_order(self):
        sys.path.insert(0, str(HERE))
        try:
            import pydeps
        finally:
            sys.path.remove(str(HERE))
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)
            (config / 'plugins/data/animation-market').mkdir(parents=True)
            env = {'CLAUDE_CONFIG_DIR': str(config), 'CLAUDE_PLUGIN_DATA': str(config / 'plugins/data/other-market')}
            old = {k: os.environ.get(k) for k in env}
            os.environ.update(env)
            try:
                self.assertEqual(pydeps.data_dir('/explicit'), Path('/explicit'))
                # a placeholder the host did not substitute, and another plugin's directory, are both ignored
                self.assertEqual(pydeps.data_dir('${CLAUDE_PLUGIN_DATA}'), config / 'plugins/data/animation-market')
                os.environ['CLAUDE_PLUGIN_DATA'] = str(config / 'plugins/data/animation-elsewhere')
                self.assertEqual(pydeps.data_dir(None), config / 'plugins/data/animation-elsewhere')
            finally:
                for k, v in old.items():
                    os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)


class RepairLine(unittest.TestCase):
    def test_on_windows_it_is_a_powershell_5_1_command(self):
        sys.path.insert(0, str(HERE))
        try:
            import pydeps
        finally:
            sys.path.remove(str(HERE))
        real = sys.platform
        sys.platform = 'win32'
        try:
            line = pydeps.repair_line("D:\\data\\o'brien\\data")
        finally:
            sys.platform = real
        self.assertTrue(line.startswith("& '"), line)
        self.assertTrue(line.endswith("'--data-dir' 'D:\\data\\o''brien\\data'"), line)
        self.assertNotIn('&&', line)


@unittest.skipUnless(os.name == 'posix', 'fake interpreters are shell scripts')
class Launcher(unittest.TestCase):
    def test_an_older_python3_hands_over_to_the_interpreter_the_hook_chose(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, log = Path(tmp) / 'bin', Path(tmp) / 'log'
            fake.mkdir()
            (fake / 'python3').write_text('#!/bin/sh\nexit 1\n', encoding='utf-8')   # below the floor
            (fake / 'python').write_text(f'#!/bin/sh\n[ "$1" = -c ] && exit 0\necho "$@" > {log}\n', encoding='utf-8')
            for f in fake.iterdir():
                f.chmod(0o755)
            code = 'import sys, pydeps; pydeps.MIN_PYTHON = (99, 0); sys.exit(pydeps.main(["run", "--", "x.py"]))'
            env = {**os.environ, 'PATH': f'{fake}{os.pathsep}/usr/bin{os.pathsep}/bin'}
            r = subprocess.run([sys.executable, '-c', code], cwd=HERE, env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(log.read_text(encoding='utf-8').split(), [str(SCRIPT), 'run', '--', 'x.py'])


class NoRuntimeFetch(unittest.TestCase):
    """Nothing the skills or scripts run fetches a package; the install hook, through pydeps.py, is the only fetch."""
    FETCH = re.compile(r'\buv\s+(run|pip|tool|sync)\b|\buvx\b|\bpip3?\s+install\b|-m\s+pip\b|--with-requirements')
    OWNERS = {'pydeps.py', 'test_pydeps.py'}

    def test_no_skill_or_script_fetches_a_package(self):
        runnable = [*PLUGIN.glob('skills/**/SKILL.md'), *PLUGIN.glob('skills/**/scripts/*'),
                    *PLUGIN.glob('scripts/*'), *PLUGIN.glob('hooks/*.sh')]
        found = [f'{p.relative_to(PLUGIN)}: {m.group(0)}'
                 for p in runnable if p.is_file() and p.name not in self.OWNERS and not p.name.endswith('.test.sh')
                 for m in self.FETCH.finditer(p.read_text(encoding='utf-8', errors='replace'))]
        self.assertEqual(found, [])


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--make-wheel':
        print(make_wheel(sys.argv[2])[1])
    else:
        unittest.main()
