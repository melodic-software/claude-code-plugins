"""assets.py and check.py: fetching pinned files with their hashes checked, and the read-only prerequisite report.

Fetch tests serve a fixture manifest from a file:// source, so nothing reaches the network.
"""
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import assets  # noqa: E402
import check  # noqa: E402

sys.modules.pop("pydeps", None)

REVISION = 'abc123abc123abc123'


class Served(unittest.TestCase):
    """A fixture manifest served from a file:// source."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.data = self.tmp / 'data'
        served = self.tmp / 'served' / 'resolve' / REVISION
        self.files = {'tokenizer.json': b'{"model": {"vocab": {}}}', 'voices/af_test.bin': b'\x00' * 64}
        for rel, body in self.files.items():
            (served / rel).parent.mkdir(parents=True, exist_ok=True)
            (served / rel).write_bytes(body)
        self.manifest = {
            'source': (self.tmp / 'served').as_uri(),
            'revision': REVISION,
            'files': {rel: {'sha256': hashlib.sha256(b).hexdigest(), 'size': len(b)} for rel, b in self.files.items()},
        }


class Fetch(Served):
    def test_fetch_downloads_every_missing_file_then_nothing_is_missing(self):
        self.assertEqual(sorted(assets.missing(self.data, self.manifest)), sorted(self.files))
        assets.fetch(self.data, self.manifest, log=io.StringIO())
        self.assertEqual(assets.missing(self.data, self.manifest), [])
        root = assets.assets_dir(self.data, self.manifest)
        self.assertEqual(root.name, f'kokoro-{REVISION[:12]}')
        self.assertEqual((root / 'voices/af_test.bin').read_bytes(), self.files['voices/af_test.bin'])

    def test_a_hash_mismatch_keeps_nothing(self):
        self.manifest['files']['tokenizer.json']['sha256'] = '0' * 64
        with self.assertRaisesRegex(RuntimeError, 'tokenizer.json: sha256'):
            assets.fetch(self.data, self.manifest, log=io.StringIO())
        root = assets.assets_dir(self.data, self.manifest)
        self.assertFalse((root / 'tokenizer.json').exists())
        self.assertEqual(list(root.glob('*.partial')), [])

    def test_an_unreachable_file_names_the_file_and_url(self):
        self.manifest['files']['voices/gone.bin'] = {'sha256': '0' * 64, 'size': 1}
        with self.assertRaisesRegex(RuntimeError, r'voices/gone.bin: download from .*gone.bin failed'):
            assets.fetch(self.data, self.manifest, log=io.StringIO())

    def test_a_file_of_the_wrong_size_counts_as_missing(self):
        assets.fetch(self.data, self.manifest, log=io.StringIO())
        (assets.assets_dir(self.data, self.manifest) / 'tokenizer.json').write_bytes(b'{}')
        self.assertEqual(assets.missing(self.data, self.manifest), ['tokenizer.json'])


class ModelDir(Served):
    """The model_dir option moves the kokoro-<revision> set; unset, the path is <data>/models as before."""

    def test_unset_keeps_the_data_directory_path(self):
        for unset in (None, '', '   ', '${user_config.model_dir}'):
            with self.subTest(unset=unset):
                self.assertEqual(assets.assets_dir(self.data, self.manifest, unset),
                                 self.data / 'models' / f'kokoro-{REVISION[:12]}')
                self.assertEqual(assets.models_root(self.data, unset)[1], 'plugin data directory')

    def test_set_downloads_there_and_check_passes_against_it(self):
        shared = self.tmp / 'shared-models'
        assets.fetch(self.data, self.manifest, log=io.StringIO(), model_dir=str(shared))
        self.assertTrue((shared / f'kokoro-{REVISION[:12]}' / 'tokenizer.json').is_file())
        self.assertFalse((self.data / 'models').exists())
        self.assertEqual(assets.missing(self.data, self.manifest, str(shared)), [])
        self.assertEqual(sorted(assets.missing(self.data, self.manifest)), sorted(self.files))
        with mock.patch.object(assets, 'manifest', lambda: self.manifest):
            status, _, detail = check.model_row(self.data, str(shared))
        self.assertEqual(status, 'PASS')
        self.assertIn(str(shared), detail)
        self.assertIn('model_dir option', detail)


class PinnedManifest(unittest.TestCase):
    def test_the_shipped_pin_holds_the_model_tokenizer_and_english_voices(self):
        m = assets.manifest()
        self.assertRegex(m['revision'], r'^[0-9a-f]{40}$')
        self.assertIn('onnx/model.onnx', m['files'])
        self.assertIn('tokenizer.json', m['files'])
        self.assertIn('af_heart', assets.voices(m))
        self.assertTrue(all(v[:2] in ('af', 'am', 'bf', 'bm') for v in assets.voices(m)))
        for rel, meta in m['files'].items():
            self.assertRegex(meta['sha256'], r'^[0-9a-f]{64}$', rel)


class Check(unittest.TestCase):
    def prerequisites(self, entries):
        path = Path(tempfile.mkdtemp()) / 'prerequisites.json'
        self.addCleanup(lambda: path.unlink())
        path.write_text(json.dumps({'requires': entries}), encoding='utf-8')
        return path

    def entry(self, **kw):
        return {'id': 'espeak-ng', 'kind': 'cli', 'need': 'required', 'for': ['skill:narrate'],
                'detect': {'any': ['espeak-ng']}, 'degrade': 'Narration stops.',
                'install': {'apt': 'espeak-ng', 'winget': 'eSpeak-NG.eSpeak-NG'}, 'check': '/speech:check', **kw}

    def test_a_missing_tool_fails_with_its_degrade_line_and_install_hints(self):
        rows = check.declared_rows(self.prerequisites([self.entry()]), which=lambda name: None)
        self.assertEqual(len(rows), 1)
        status, name, detail = rows[0]
        self.assertEqual((status, name), ('FAIL', 'espeak-ng'))
        self.assertIn('Narration stops.', detail)
        self.assertIn('apt: espeak-ng; winget: eSpeak-NG.eSpeak-NG', detail)

    def test_a_found_tool_passes(self):
        rows = check.declared_rows(self.prerequisites([self.entry()]), which=lambda name: f'/bin/{name}')
        self.assertEqual(rows, [('PASS', 'espeak-ng', '/bin/espeak-ng')])

    def test_a_version_below_the_floor_fails(self):
        entry = self.entry(id='python', kind='runtime', detect={
            'any': ['python3'], 'version': {'args': ['-c', 'print("Python 3.10.1")'], 'pattern': r'Python ([0-9.]+)',
                                            'min': '3.12'}})
        rows = check.declared_rows(self.prerequisites([entry]), which=lambda name: sys.executable)
        self.assertEqual(rows[0][0], 'FAIL')
        self.assertIn('is 3.10.1, below 3.12', rows[0][2])

    def test_kinds_other_than_cli_and_runtime_are_left_to_their_own_rows(self):
        entry = self.entry(id='numpy', kind='python-pkg', detect={'any': ['python3'], 'import': 'numpy'})
        self.assertEqual(check.declared_rows(self.prerequisites([entry]), which=lambda name: None), [])

    def test_the_shipped_file_declares_espeak_ng_with_hints_and_never_an_install_step(self):
        entries = {e['id']: e for e in json.loads(check.PREREQUISITES.read_text(encoding='utf-8'))['requires']}
        self.assertIn('espeak-ng', entries)
        self.assertIn('GPL', entries['espeak-ng']['degrade'])
        self.assertTrue({'apt', 'brew', 'winget'} <= set(entries['espeak-ng']['install']))
        self.assertEqual(entries['python']['detect']['version']['min'], '3.12')

    def test_an_empty_data_dir_fails_the_package_and_model_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(check.package_row(Path(tmp))[0], 'FAIL')
            status, _, detail = check.model_row(Path(tmp))
        self.assertEqual(status, 'FAIL')
        self.assertIn('/speech:setup apply install-model', detail)


if __name__ == '__main__':
    unittest.main()
