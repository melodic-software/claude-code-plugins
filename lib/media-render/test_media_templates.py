import tempfile
import unittest
from pathlib import Path

import media_templates as tpl

SIZE = (1920, 1080)

HOSTILE = '<script>alert(1)</script>"\'&'


class TemplatesTest(unittest.TestCase):
    def render(self, template, data):
        return tpl.page({'template': template, 'data': data}, HOSTILE, HOSTILE, (1, 3), SIZE, 0.24)

    def test_every_template_escapes_storyboard_text(self):
        cases = {
            'title': {'subtitle': HOSTILE},
            'code-hunk': {'path': HOSTILE, 'lines': [{'n': 1, 'kind': '+', 'text': HOSTILE}], 'note': HOSTILE},
            'diagram': {'nodes': [{'label': HOSTILE, 'detail': HOSTILE}]},
            'before-after': {'before': {'label': HOSTILE, 'lines': [HOSTILE]}, 'after': {'lines': [HOSTILE]}},
            'risk-map': {'rows': [{'area': HOSTILE, 'level': HOSTILE, 'note': HOSTILE}]},
            'also-changed': {'files': [{'path': HOSTILE, 'summary': HOSTILE}]},
        }
        for template, data in cases.items():
            with self.subTest(template):
                out = self.render(template, data)
                self.assertNotIn('<script>', out)
                self.assertIn('&lt;script&gt;', out)

    def test_class_names_never_come_from_data(self):
        out = self.render('risk-map', {'rows': [{'area': 'a', 'level': 'x" onload="y'}]})
        self.assertIn('class="risk medium"', out)
        out = self.render('code-hunk', {'lines': [{'kind': 'evil', 'text': 't'}]})
        self.assertIn('<tr class="ctx">', out)

    def test_screenshot_inlines_image_and_rejects_other_files(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'shot.png').write_bytes(b'\x89PNG\r\n')
            Path(d, 'x.svg').write_text('<svg/>')
            out = tpl.page({'template': 'screenshot', 'data': {'image': 'shot.png', 'alt': 'a'}}, 't', 'c', (1, 1), SIZE, 0.24,
                           base_dir=d)
            self.assertIn('src="data:image/png;base64,', out)
            with self.assertRaises(ValueError):
                tpl.page({'template': 'screenshot', 'data': {'image': 'x.svg'}}, 't', 'c', (1, 1), SIZE, 0.24, base_dir=d)
            with tempfile.TemporaryDirectory() as other:
                Path(other, 'secret.png').write_bytes(b'\x89PNG\r\n')
                Path(d, 'link.png').symlink_to(Path(other, 'secret.png'))
                with self.assertRaisesRegex(ValueError, 'outside'):
                    tpl.page({'template': 'screenshot', 'data': {'image': 'link.png'}}, 't', 'c', (1, 1), SIZE, 0.24, base_dir=d)

    def test_custom_stylesheet_replaces_bundled_and_cannot_close_style(self):
        out = tpl.page({'template': 'title', 'data': {}}, 't', 'c', (1, 1), SIZE, 0.24, stylesheet='body{}</style><b>')
        self.assertIn('body{}<\\/style><b>', out)
        self.assertNotIn('--accent', out)

    def test_frame_text_lists_shown_strings_but_not_file_paths(self):
        text = tpl.frame_text({'data': {'image': 'shot.png', 'sidecar': 's.txt', 'caption': 'Login page'}}, 'T', 'C')
        self.assertIn('Login page', text.splitlines())
        self.assertNotIn('shot.png', text)
        self.assertNotIn('s.txt', text)

    def test_frame_text_includes_keys_a_mistyped_field_would_render(self):
        moment = {'template': 'diagram', 'data': {'note': {'ghp_KEYTOKEN': 1}}}
        self.assertIn('ghp_KEYTOKEN', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24))
        self.assertIn('ghp_KEYTOKEN', tpl.frame_text(moment, 't', 'c'))


if __name__ == '__main__':
    unittest.main()
