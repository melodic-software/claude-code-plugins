import unittest

import media_captions
import media_timeline as mt

HOLD = {'min_seconds': 3.0, 'seconds_per_word': 0.3, 'extra_seconds': 1.0}


def board(**over):
    b = {'version': 1, 'title': 'T', 'chapters': [{'id': 'c1', 'title': 'Intro'}, {'id': 'c2', 'title': 'Code'}],
         'moments': [{'id': 'm1', 'chapter': 'c1', 'template': 'title', 'data': {}, 'narration': 'One two.',
                      'covers': []},
                     {'id': 'm2', 'chapter': 'c2', 'template': 'code-hunk', 'data': {'path': 'a.py', 'lines': []},
                      'narration': 'Three four five.', 'covers': ['a.py']}]}
    b.update(over)
    return b


class ParseTest(unittest.TestCase):
    def test_valid_board_parses(self):
        self.assertEqual([m['id'] for m in mt.parse(board())['moments']], ['m1', 'm2'])

    def test_rejections_name_the_moment(self):
        cases = {
            'unknown template': {'template': 'slide'},
            'undeclared chapter': {'chapter': 'c9'},
            'empty narration': {'narration': '  '},
        }
        for reason, change in cases.items():
            b = board()
            b['moments'][1].update(change)
            with self.subTest(reason), self.assertRaisesRegex(mt.StoryboardError, 'm2'):
                mt.parse(b)

    def test_also_changed_needs_covers(self):
        b = board()
        b['moments'][1].update(template='also-changed', covers=[])
        with self.assertRaisesRegex(mt.StoryboardError, 'covers'):
            mt.parse(b)

    def test_title_may_be_silent(self):
        b = board()
        b['moments'][0]['narration'] = ''
        self.assertEqual(len(mt.script(mt.parse(b)).strip().split('\n\n')), len(b['moments']) - 1)

    def test_wrong_version_rejected(self):
        with self.assertRaisesRegex(mt.StoryboardError, 'version'):
            mt.parse(board(version=2))

    def test_screenshot_paths_stay_inside_the_storyboard_folder(self):
        for image, sidecar in (('../x.png', 's.txt'), ('/etc/x.png', 's.txt'), ('x.png', '../s.txt'),
                               ('x.png', 'C:\\s.txt')):
            b = board()
            b['moments'][1].update(template='screenshot', data={'image': image, 'sidecar': sidecar})
            with self.subTest(image=image, sidecar=sidecar), self.assertRaisesRegex(mt.StoryboardError, 'relative'):
                mt.parse(b)

    def test_screenshot_needs_sidecar(self):
        b = board()
        b['moments'][1].update(template='screenshot', data={'image': 'shot.png'})
        with self.assertRaisesRegex(mt.StoryboardError, 'sidecar'):
            mt.parse(b)


class TimelineTest(unittest.TestCase):
    def test_holds_follow_paragraph_starts(self):
        words = {'words': [{'word': w, 'start': s, 'end': s + 0.3} for w, s in
                           [('One', 0.5), ('two.', 0.9), ('Three', 2.0), ('four', 2.4), ('five.', 2.8)]],
                 'duration': 4.0}
        tl = mt.timeline(mt.parse(board()), words)
        self.assertEqual([(h['start'], h['end']) for h in tl['holds']], [(0.0, 2.0), (2.0, 4.0)])
        self.assertEqual(tl['chapters'], [{'title': 'Intro', 'start_s': 0.0}, {'title': 'Code', 'start_s': 2.0}])
        self.assertEqual(tl['beats'], [(0, 2), (2, 3)])

    def test_silent_moment_inside_narrated_board_holds_minimum(self):
        b = mt.parse(board())
        b['moments'][0]['narration'] = ''
        words = {'words': [{'word': w, 'start': s, 'end': s + 0.3} for w, s in
                           [('Three', 0.2), ('four', 0.6), ('five.', 1.0)]], 'duration': 2.0}
        tl = mt.timeline(b, words, HOLD)
        self.assertEqual([(h['start'], h['end']) for h in tl['holds']], [(0.0, 3.0), (3.0, 5.0)])
        self.assertEqual(tl['audio'], [('silence', 3.0), ('narration', 0.0, 2.0)])
        self.assertEqual(tl['words']['words'][0]['start'], 3.2)

    def test_captions_only_holds_and_synthetic_words(self):
        tl = mt.timeline(mt.parse(board()), None, HOLD)
        self.assertEqual([round(h['end'] - h['start'], 3) for h in tl['holds']], [3.0, 3.0])
        self.assertEqual(len(tl['words']['words']), 5)
        self.assertEqual(tl['words']['words'][2]['start'], 3.0)

    def test_title_without_a_narration_field_lays_out(self):
        b = board()
        del b['moments'][0]['narration']
        tl = mt.timeline(mt.parse(b), None, HOLD)
        self.assertEqual(round(tl['holds'][0]['end'] - tl['holds'][0]['start'], 3), 3.0)

    def test_captions_only_gives_every_caption_its_minimum_time(self):
        b = board()
        b['moments'][1]['narration'] = 'Yes. Here are eight words to explain this change.'
        tl = mt.timeline(mt.parse(b), None, HOLD, {'max_words': 8, 'min_seconds': 0.834})
        cues = media_captions.captions(tl['words'], tl['beats'], 8, 0.834, 0.3)
        self.assertEqual(media_captions.caption_findings(cues, 0.834, 0.3)[0], [])
        self.assertEqual(cues[0], (0.0, 0.834, 'One two.'))
        self.assertLessEqual(cues[-1][1], tl['duration'])

    def test_script_text_is_one_paragraph_per_narrated_moment(self):
        self.assertEqual(mt.script(mt.parse(board())), 'One two.\n\nThree four five.\n')

    def test_words_must_match_script(self):
        with self.assertRaisesRegex(mt.StoryboardError, 'words.json'):
            mt.timeline(mt.parse(board()), {'words': [{'word': 'x', 'start': 0, 'end': 1}], 'duration': 1})


if __name__ == '__main__':
    unittest.main()
