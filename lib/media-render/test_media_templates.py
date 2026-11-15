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

    def test_a_diagram_draws_arrows_only_in_the_flow_layout(self):
        nodes = [{'label': 'a'}, {'label': 'b'}]
        self.assertIn('class=arrow', self.render('diagram', {'nodes': nodes}))
        for layout in ('stack', 'group'):
            with self.subTest(layout):
                out = self.render('diagram', {'nodes': nodes, 'layout': layout, 'center': HOSTILE})
                self.assertNotIn('class=arrow', out)
                self.assertIn(f'class="{layout}"', out)
                self.assertIn('class="center">&lt;script&gt;', out)
        self.assertIn('<div class="flow">', self.render('diagram', {'nodes': nodes, 'layout': 'x" onload="y'}))
        self.assertIn('<script>', tpl.frame_text({'template': 'diagram', 'data': {'center': '<script>'}}, 't', 'c'))

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

    def test_a_paged_list_keeps_only_its_slice_and_a_hunk_note_stays_on_the_last_frame(self):
        hunk = {'template': 'code-hunk', 'data': {'lines': [{'text': f'L{i}'} for i in range(5)], 'note': 'NOTE'}}
        self.assertEqual(tpl.entries(hunk), 5)
        first, last = tpl.subset(hunk, 0, 3), tpl.subset(hunk, 3, 5)
        self.assertEqual([ln['text'] for ln in first['data']['lines']], ['L0', 'L1', 'L2'])
        self.assertNotIn('note', first['data'])
        self.assertEqual(last['data']['note'], 'NOTE')
        self.assertEqual(len(hunk['data']['lines']), 5, 'subset changed the storyboard moment')
        self.assertEqual(tpl.entries({'template': 'diagram', 'data': {'nodes': [1, 2]}}), 0)

    def test_a_continuation_frame_says_so_and_an_unsplit_frame_does_not(self):
        moment = {'template': 'also-changed', 'data': {'files': [{'path': 'a'}]}}
        self.assertIn('>part 1 of 3<', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24, part=(1, 3)))
        self.assertIn('>continued, part 2 of 3<', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24, part=(2, 3)))
        for part in (None, (1, 1)):
            self.assertNotIn('class="part"', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24, part=part))

    def test_custom_stylesheet_replaces_bundled_and_cannot_close_style(self):
        out = tpl.page({'template': 'title', 'data': {}}, 't', 'c', (1, 1), SIZE, 0.24, stylesheet='body{}</style><b>')
        self.assertIn('body{}<\\/style><b>', out)
        self.assertNotIn('--accent', out)

    def test_frame_text_lists_shown_strings_but_not_file_paths(self):
        text = tpl.frame_text({'template': 'screenshot',
                               'data': {'image': 'shot.png', 'sidecar': 's.txt', 'caption': 'Login page'}}, 'T', 'C')
        self.assertIn('Login page', text.splitlines())
        self.assertNotIn('shot.png', text)
        self.assertNotIn('s.txt', text)

    def test_frame_text_includes_keys_a_mistyped_field_would_render(self):
        moment = {'template': 'diagram', 'data': {'note': {'ghp_KEYTOKEN': 1}}}
        self.assertIn('ghp_KEYTOKEN', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24))
        self.assertIn('ghp_KEYTOKEN', tpl.frame_text(moment, 't', 'c'))

    def test_frame_text_scans_a_nested_image_or_sidecar_value_the_frame_draws(self):
        for key in ('image', 'sidecar'):
            moment = {'template': 'diagram', 'data': {'note': {key: 'ghp_NESTED'}}}
            with self.subTest(key=key):
                self.assertIn('ghp_NESTED', tpl.page(moment, 't', 'c', (1, 1), SIZE, 0.24))
                self.assertIn('ghp_NESTED', tpl.frame_text(moment, 't', 'c'))


if __name__ == '__main__':
    unittest.main()
