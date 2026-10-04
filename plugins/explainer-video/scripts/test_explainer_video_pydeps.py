"""pydeps.py: the hash-locked on-demand install (first install, no-op rerun, a failed install), the run launcher, and
the hand-over to a supported interpreter.

The lock is a local wheel that provides the manim module, installed with pip's own PIP_NO_INDEX and PIP_FIND_LINKS,
so no test reaches a package index. `python test_explainer_video_pydeps.py --make-wheel DIR` builds that wheel and prints its
sha256, for the hook suite (../hooks/install-python-deps.test.sh). Each run pins pydeps.PYTHONS to the Python
running the test, so the suite runs under any Python with pip.
"""
import base64
import builtins
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
import unittest.mock
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
SCRIPT = HERE / 'pydeps.py'
NAME, VERSION = 'fakedeps', '1.0'
MODULES = {'manim/__init__.py': 'VALUE = 42\n'}
_spec = importlib.util.spec_from_file_location('explainer_video_pydeps', SCRIPT)
pydeps = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pydeps)

# Run pydeps.main as if this Python were the supported one.
AS_SUPPORTED = ('import sys, pydeps; pydeps.PYTHONS = (tuple(sys.version_info[:2]),); '
                'sys.exit(pydeps.main(sys.argv[1:]))')


def make_wheel(folder):
    """A pure-python wheel providing the manim module; returns (wheel path, sha256 hex)."""
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


@unittest.skipUnless(have_pip(), 'needs pip')
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
        self.env = {**os.environ, 'PIP_NO_INDEX': '1', 'PIP_FIND_LINKS': str(self.wheels),
                    pydeps.HANDED_OVER: sys.executable}

    def pydeps(self, action, *args, env=None):
        return subprocess.run([sys.executable, '-c', AS_SUPPORTED, action, '--requirements', str(self.lock), *args],
                              capture_output=True, text=True, env=env or self.env, cwd=HERE)

    def installs(self):
        return sorted(p.name for p in (self.data / 'python').glob('*')) if (self.data / 'python').is_dir() else []

    def test_first_install_then_run_against_it(self):
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)
        self.assertEqual(len(self.installs()), 1)
        script = self.tmp / 'use.py'
        script.write_text('import manim\nprint(manim.VALUE)\n', encoding='utf-8')
        r = self.pydeps('run', '--data-dir', str(self.data), '--', str(script), env={**self.env, 'PYTHONPATH': ''})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, '42'), r.stderr)

    def test_second_session_is_a_no_op(self):
        self.assertEqual(self.pydeps('install', '--data-dir', str(self.data)).stdout.strip(), 'installed')
        before = self.installs()
        # Aim pip at an empty folder: a second pip run could not find the wheel and would fail.
        empty = self.tmp / 'empty'
        empty.mkdir()
        r = self.pydeps('install', '--data-dir', str(self.data), env={**self.env, 'PIP_FIND_LINKS': str(empty)})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'ready'), r.stderr)
        self.assertEqual(self.installs(), before)

    def test_a_wrong_hash_fails_with_the_reason_and_a_repair_line_and_leaves_nothing(self):
        self.lock.write_text(lock_text('0' * 64), encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual(r.returncode, 1)
        self.assertIn('explainer-video: pip install --require-hashes failed', r.stderr)
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
        (installed / 'manim' / '__init__.py').write_text('raise ImportError("broken")\n', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data))
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)

    def test_ambient_packages_do_not_satisfy_the_probe(self):
        self.pydeps('install', '--data-dir', str(self.data))
        (installed,) = (self.data / 'python').glob('*')
        shutil.rmtree(installed / 'manim')
        ambient = self.tmp / 'ambient' / 'manim'
        ambient.mkdir(parents=True)
        (ambient / '__init__.py').write_text('', encoding='utf-8')
        r = self.pydeps('install', '--data-dir', str(self.data), env={**self.env, 'PYTHONPATH': str(ambient.parent)})
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'installed'), r.stderr)

    def test_check_reports_the_install_and_never_installs(self):
        r = self.pydeps('check', '--data-dir', str(self.data))
        self.assertEqual(r.returncode, 1)
        self.assertRegex(r.stdout, r'(?m)^FAIL  ManimCE  not installed .*install --data-dir')
        self.assertEqual(self.installs(), [])
        self.pydeps('install', '--data-dir', str(self.data))
        r = self.pydeps('check', '--data-dir', str(self.data))
        self.assertRegex(r.stdout, r'(?m)^PASS  ManimCE  ')
        tools_ok = all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
        self.assertEqual(r.returncode, 0 if tools_ok else 1, r.stdout)

    def test_run_never_installs(self):
        script = self.tmp / 'use.py'
        script.write_text('print("ran")\n', encoding='utf-8')
        r = self.pydeps('run', '--data-dir', str(self.data), '--', str(script))
        self.assertEqual(r.returncode, 2)
        self.assertIn('SessionStart hook installs them, or run:', r.stderr)
        self.assertEqual(r.stdout, '')
        self.assertEqual(self.installs(), [])


class Unsupported(unittest.TestCase):
    def test_an_unsupported_python_with_none_to_hand_over_to_says_which_it_needs(self):
        code = ('import sys, pydeps; pydeps.PYTHONS = ((2, 0),); pydeps.interpreter = lambda: None; '
                'sys.exit(pydeps.main(["install", "--data-dir", "/nowhere"]))')
        r = subprocess.run([sys.executable, '-c', code], cwd=HERE, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != pydeps.HANDED_OVER})
        self.assertEqual(r.returncode, 1)
        self.assertIn('explainer-video: Python 2.0 is required and none is on PATH', r.stderr)

    def test_a_free_threaded_build_of_a_supported_version_is_refused(self):
        code = ('import sys, pydeps; pydeps.PYTHONS = (tuple(sys.version_info[:2]),); pydeps.interpreter = lambda: None; '
                'pydeps.free_threaded = lambda: True; sys.exit(pydeps.main(["install", "--data-dir", "/nowhere"]))')
        r = subprocess.run([sys.executable, '-c', code], cwd=HERE, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != pydeps.HANDED_OVER})
        self.assertEqual(r.returncode, 1)
        self.assertIn(f'is required and none is on PATH (this is {sys.version_info[0]}.{sys.version_info[1]}t, ',
                      r.stderr)


class BuildFromSource(unittest.TestCase):
    def test_only_the_named_packages_may_build_from_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / 'requirements.txt'
            lock.write_text('Manim==0.21.0 \\\n    --hash=sha256:aa\npycairo==1.29.1 ; x \\\n    --hash=sha256:bb\n'
                            'srt==3.5.3 \\\n    --hash=sha256:cc\nnumpy==2.5.3\n', encoding='utf-8')
            self.assertEqual(pydeps.binary_only(lock), ['manim', 'numpy'])

    def test_the_shipped_lock_pins_every_source_build_with_a_hash(self):
        text = (PLUGIN / 'requirements.txt').read_text(encoding='utf-8')
        for name in pydeps.BUILD_FROM_SOURCE:
            self.assertRegex(text, rf'(?m)^{name}==\S+[^\n]*\\\n\s+--hash=sha256:[0-9a-f]{{64}}')


class DataDir(unittest.TestCase):
    def test_resolution_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)
            (config / 'plugins/data/explainer-video-market').mkdir(parents=True)
            env = {'CLAUDE_CONFIG_DIR': str(config), 'CLAUDE_PLUGIN_DATA': str(config / 'plugins/data/other-market')}
            old = {k: os.environ.get(k) for k in env}
            os.environ.update(env)
            try:
                self.assertEqual(pydeps.data_dir('/explicit'), Path('/explicit'))
                # a placeholder the host did not substitute, and another plugin's directory, are both ignored
                self.assertEqual(pydeps.data_dir('${CLAUDE_PLUGIN_DATA}'),
                                 config / 'plugins/data/explainer-video-market')
                os.environ['CLAUDE_PLUGIN_DATA'] = str(config / 'plugins/data/explainer-video-elsewhere')
                self.assertEqual(pydeps.data_dir(None), config / 'plugins/data/explainer-video-elsewhere')
            finally:
                for k, v in old.items():
                    os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)


class RepairLine(unittest.TestCase):
    def test_on_windows_it_is_a_powershell_5_1_command(self):
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
    def test_any_python_hands_over_to_the_first_supported_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, log = Path(tmp) / 'bin', Path(tmp) / 'log'
            fake.mkdir()
            (fake / 'python3.13').write_text('#!/bin/sh\nexit 1\n', encoding='utf-8')   # not supported
            (fake / 'python3.12').write_text(f'#!/bin/sh\n[ "$1" = -c ] && exit 0\necho "$@" > {log}\n',
                                             encoding='utf-8')
            for f in fake.iterdir():
                f.chmod(0o755)
            code = 'import sys, pydeps; sys.exit(pydeps.main(["run", "--", "x.py"]))'
            env = {**{k: v for k, v in os.environ.items() if k != pydeps.HANDED_OVER},
                   'PATH': f'{fake}{os.pathsep}/usr/bin{os.pathsep}/bin'}
            r = subprocess.run([sys.executable, '-c', code], cwd=HERE, env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(log.read_text(encoding='utf-8').split(), [str(SCRIPT), 'run', '--', 'x.py'])

    def test_the_probe_and_the_handed_over_child_get_no_foreign_pythonhome_or_pythonpath(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, log = Path(tmp) / 'bin', Path(tmp) / 'log'
            fake.mkdir()
            (fake / 'python3.13').write_text('#!/bin/sh\nexit 1\n', encoding='utf-8')
            (fake / 'python3.12').write_text(
                f'#!/bin/sh\necho "$1 home=[$PYTHONHOME] path=[$PYTHONPATH] uv=[$UV_INTERNAL__PYTHONHOME] '
                f'over=[${pydeps.HANDED_OVER}]" >> {log}\n', encoding='utf-8')
            for f in fake.iterdir():
                f.chmod(0o755)
            # A real foreign home would break this test's own Python, so set it only for main()'s subprocesses.
            code = ('import os, sys, pydeps; '
                    'os.environ.update(PYTHONHOME="/opt/py314", PYTHONPATH="/opt/py314/lib", '
                    'UV_INTERNAL__PYTHONHOME="/opt/py314"); '
                    'sys.exit(pydeps.main(["run", "--", "x.py"]))')
            env = {**{k: v for k, v in os.environ.items() if k != pydeps.HANDED_OVER},
                   'PATH': f'{fake}{os.pathsep}/usr/bin{os.pathsep}/bin'}
            r = subprocess.run([sys.executable, '-c', code], cwd=HERE, env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(log.read_text(encoding='utf-8').splitlines(), [
                '-c home=[] path=[] uv=[] over=[]',
                f'{SCRIPT} home=[] path=[] uv=[] over=[{fake / "python3.12"}]',
            ])


class PyLauncher(unittest.TestCase):
    """Windows cannot run here, so shutil.which, subprocess.run and sys.platform are stubbed: a python.org install
    registers with the py launcher and puts no python3.13.exe on PATH."""
    PY = r'C:\Windows\py.exe'
    PY313 = r'C:\Program Files\Python313\python.exe'
    PY314 = r'C:\Users\<user>\AppData\Roaming\uv\python\cpython-3.14-windows-x86_64-none\python.exe'

    def discover(self, on_path, listing, supported, platform='win32', listing_rc=0):
        """supported: the paths whose probe passes, or {path: (version_info, Py_GIL_DISABLED)} to run the probe's
        own code against that interpreter's sys and sysconfig."""
        calls = []

        def which(name):
            return on_path.get(name)

        def probe(cmd):
            if not isinstance(supported, dict):
                return 0 if cmd[0] in supported else 1
            version, gil_disabled = supported[cmd[0]]
            fakes = {'sys': types.SimpleNamespace(version_info=version),
                     'sysconfig': types.SimpleNamespace(
                         get_config_var=lambda name: gil_disabled if name == 'Py_GIL_DISABLED' else None)}
            try:
                exec(cmd[2], {'__builtins__': {**vars(builtins), '__import__': lambda name, *_: fakes[name]}})
            except SystemExit as e:
                return 1 if e.code else 0
            return 0

        def run(cmd, env=None, **_):
            calls.append((cmd, env))
            if cmd[1:] == ['-0p']:
                return subprocess.CompletedProcess(cmd, listing_rc, listing, '')
            return subprocess.CompletedProcess(cmd, probe(cmd), b'', b'')

        real = (sys.platform, pydeps.shutil.which, pydeps.subprocess.run, dict(os.environ))
        sys.platform, pydeps.shutil.which, pydeps.subprocess.run = platform, which, run
        os.environ.update(PYTHONHOME=r'C:\uv\python\cpython-3.14', UV_INTERNAL__PYTHONHOME=r'C:\uv\python\cpython-3.14')
        try:
            return pydeps.interpreter(), calls
        finally:
            sys.platform, pydeps.shutil.which, pydeps.subprocess.run = real[:3]
            os.environ.clear()
            os.environ.update(real[3])

    def test_a_python_org_313_behind_a_314_on_path_resolves_through_the_launcher(self):
        listing = f' -V:3.14 *        {self.PY314}\n -V:3.13          {self.PY313}\n'
        found, calls = self.discover({'python3': self.PY314, 'python': self.PY314, 'py': self.PY}, listing,
                                     {self.PY313})
        self.assertEqual(found, self.PY313)
        self.assertEqual([c[0] for c in calls], [
            [self.PY314, '-c', unittest.mock.ANY], [self.PY314, '-c', unittest.mock.ANY],
            [self.PY, '-0p'], [self.PY314, '-c', unittest.mock.ANY], [self.PY313, '-c', unittest.mock.ANY]])
        for _, env in calls:
            self.assertFalse({'PYTHONHOME', 'UV_INTERNAL__PYTHONHOME'} & set(env), env)

    def test_it_reads_the_older_launcher_listing_and_never_launches_a_version_through_py(self):
        py312 = r'C:\Python312\python.exe'
        listing = f'Installed Pythons found by C:\\Windows\\py.exe Launcher for Windows\n -3.12-64 *     {py312}\n'
        found, calls = self.discover({'py': self.PY}, listing, {py312})
        self.assertEqual(found, py312)
        self.assertEqual([c[0][1:] for c in calls if c[0][0] == self.PY], [['-0p']])

    def test_a_supported_python_on_path_still_wins_and_the_launcher_is_not_asked(self):
        found, calls = self.discover({'python3.12': '/x/python3.12', 'py': self.PY}, '', {'/x/python3.12'})
        self.assertEqual(found, '/x/python3.12')
        self.assertNotIn(self.PY, [c[0][0] for c in calls])

    def test_only_windows_asks_the_launcher(self):
        found, calls = self.discover({'py': '/usr/bin/py'}, f' -V:3.13  {self.PY313}\n', {self.PY313}, platform='linux')
        self.assertIsNone(found)
        self.assertEqual(calls, [])

    def test_a_free_threaded_313_is_skipped_for_a_later_regular_one(self):
        py313t = r'C:\Program Files\Python313\python3.13t.exe'
        listing = f' -V:3.14 *        {self.PY314}\n -V:3.13t         {py313t}\n -V:3.13          {self.PY313}\n'
        runtimes = {self.PY314: ((3, 14, 0), 0), py313t: ((3, 13, 5), 1), self.PY313: ((3, 13, 5), 0)}
        found, calls = self.discover({'python': self.PY314, 'py': self.PY}, listing, runtimes)
        self.assertEqual(found, self.PY313)
        self.assertIn([py313t, '-c', unittest.mock.ANY], [c[0] for c in calls])

    def test_a_free_threaded_313_on_path_is_skipped(self):
        runtimes = {'/x/python3.13t': ((3, 13, 5), 1), '/x/python3.12': ((3, 12, 9), 0)}
        found, _ = self.discover({'python3.13': '/x/python3.13t', 'python3.12': '/x/python3.12'}, '', runtimes,
                                 platform='linux')
        self.assertEqual(found, '/x/python3.12')

    def test_a_failed_listing_finds_nothing(self):
        found, _ = self.discover({'py': self.PY}, f' -V:3.13  {self.PY313}\n', {self.PY313}, listing_rc=1)
        self.assertIsNone(found)

    def test_on_windows_the_message_names_the_launcher(self):
        code = ('import sys, pydeps; pydeps.PYTHONS = ((2, 0),); pydeps.interpreter = lambda: None; '
                'sys.platform = "win32"; sys.exit(pydeps.main(["install", "--data-dir", "/nowhere"]))')
        r = subprocess.run([sys.executable, '-c', code], cwd=HERE, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != pydeps.HANDED_OVER})
        self.assertEqual(r.returncode, 1)
        self.assertIn('Python 2.0 is required and none is on PATH or listed by the py launcher (py -0p)', r.stderr)


class ForeignEnv(unittest.TestCase):
    def test_a_different_interpreter_gets_no_pythonhome_pythonpath_or_uv_marker(self):
        env = {'PYTHONHOME': r'C:\uv\python\cpython-3.14', 'PYTHONPATH': '/elsewhere',
               'UV_INTERNAL__PYTHONHOME': r'C:\uv\python\cpython-3.14', 'PATH': '/bin', 'PYTHONUTF8': '1'}
        old = dict(os.environ)
        os.environ.clear()
        os.environ.update(env)
        try:
            got = pydeps._foreign_env({pydeps.HANDED_OVER: '/usr/bin/python3.13'})
        finally:
            os.environ.clear()
            os.environ.update(old)
        self.assertEqual(got, {'PATH': '/bin', 'PYTHONUTF8': '1', pydeps.HANDED_OVER: '/usr/bin/python3.13'})


class NoRuntimeFetch(unittest.TestCase):
    """Nothing the skills or scripts run fetches a package; the install hook, through pydeps.py, is the only fetch."""
    FETCH = re.compile(r'\buv\s+(run|pip|tool|sync)\b|\buvx\b|\bpip3?\s+install\b|-m\s+pip\b|--with-requirements')
    OWNERS = {'pydeps.py', 'test_explainer_video_pydeps.py'}

    def test_no_skill_or_script_fetches_a_package(self):
        runnable = [*PLUGIN.glob('skills/**/SKILL.md'), *PLUGIN.glob('skills/**/*.py'),
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
