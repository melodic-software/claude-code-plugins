import unittest
from pathlib import Path

import media_scan as ms   # needs redact.py importable: media-render.test.sh puts lib/ on PYTHONPATH

HERE = Path(__file__).resolve().parent
RULES = next((p for p in (HERE / 'vendor' / 'gitleaks' / 'gitleaks-rules.json',
                          HERE.parents[1] / 'vendor' / 'gitleaks' / 'gitleaks-rules.json',
                          HERE.parents[1] / 'plugins' / 'session-flow' / 'skills' / 'audit-sessions' / 'vendor'
                          / 'gitleaks' / 'gitleaks-rules.json') if p.is_file()), None)


class ScanTest(unittest.TestCase):
    def scan(self, texts, **kw):
        return ms.scan(texts, rules=RULES, host='buildbox-7', user='octo', **kw)

    def test_clean_text_passes(self):
        self.assertEqual(self.scan({'m1': 'Adds a retry to the upload step.'}).findings, [])

    def test_secret_home_path_and_host_are_found_with_their_source(self):
        token = 'ghp_' + 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8'
        home = '/' + 'home/' + 'octo/repo/x.py'   # assembled at run time, as the redact tests do
        r = self.scan({'m1': f'token {token}', 'm2': f'see {home}', 'm3': 'ran on buildbox-7'})
        self.assertEqual(sorted({f['source'] for f in r.findings}), ['m1', 'm2', 'm3'])
        self.assertIn({'source': 'm2', 'kind': 'home-path'}, r.findings)
        self.assertNotIn(token, str(r.findings))

    def test_a_label_already_in_the_text_does_not_hide_a_new_secret_of_its_kind(self):
        token = 'ghp_' + 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8'
        address = 'ops' + '@' + 'example.org'
        r = self.scan({'m1': f'<redacted:github-pat> then {token}', 'm2': f'<email> and {address}'})
        self.assertEqual(sorted({f['source'] for f in r.findings}), ['m1', 'm2'])

    def test_user_name_matches_alone_not_inside_a_handle(self):
        self.assertEqual(self.scan({'m1': 'reviewed by octo-cat'}).findings, [])
        self.assertEqual(len(self.scan({'m1': 'octo ran it'}).findings), 1)

    def test_a_stock_account_or_host_name_does_not_block_ordinary_words(self):
        for user, host, text in (('root', 'buildbox-7', 'the root cause'), ('runner', 'localhost', 'the test runner'),
                                 ('octo', 'localhost', 'served on localhost')):
            with self.subTest(user=user, host=host):
                self.assertEqual(ms.scan({'m1': text}, rules=RULES, host=host, user=user).findings, [])

    def test_missing_rules_fail_closed(self):
        r = ms.scan({'m1': 'fine'}, rules=Path('/nonexistent/rules.json'), host='h', user='u')
        self.assertTrue(r.fail_closed)
        self.assertFalse(r.ok)

    def test_extra_patterns_add_to_the_floor(self):
        r = self.scan({'m1': 'internal codename BLUEJAY'}, extra=[r'\bBLUEJAY\b'])
        self.assertEqual(len(r.findings), 1)


if __name__ == '__main__':
    unittest.main()
