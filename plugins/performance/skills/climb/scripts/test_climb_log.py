"""Tests for climb_log.py: the attempt log and the keep rule."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("climb_log.py")
FIELDS = [
    "id",
    "hypothesis",
    "change",
    "before",
    "after",
    "delta",
    "tests",
    "verdict",
    "note",
]


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def attempt(log, **overrides):
    values = {
        "id": "a1",
        "hypothesis": "the site build parses each template once per page",
        "change": "parse each template once per build",
        "before": "412",
        "after": "3",
        "delta": "-409",
        "tests": "pass",
        "verdict": "kept",
        "note": "dropped sha none",
    }
    values.update(overrides)
    args = ["append", "--log", str(log)]
    for name in FIELDS:
        args += [f"--{name}", values[name]]
    return run(*args)


class AppendTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.log = Path(self._tmp.name) / "climb-log.tsv"

    def rows(self):
        lines = self.log.read_text(encoding="utf-8").splitlines()
        return [line.split("\t") for line in lines[1:]]

    def test_append_writes_one_row_of_nine_fields_in_order(self):
        result = attempt(self.log)
        self.assertEqual(result.returncode, 0, result.stderr)
        header = self.log.read_text(encoding="utf-8").splitlines()[0]
        self.assertEqual(header.split("\t"), FIELDS)
        self.assertEqual(
            self.rows(),
            [
                [
                    "a1",
                    "the site build parses each template once per page",
                    "parse each template once per build",
                    "412",
                    "3",
                    "-409",
                    "pass",
                    "kept",
                    "dropped sha none",
                ]
            ],
        )

    def test_second_append_adds_a_row_without_a_second_header(self):
        attempt(self.log)
        attempt(self.log, id="a2", tests="fail", verdict="reverted")
        self.assertEqual([row[0] for row in self.rows()], ["a1", "a2"])
        self.assertEqual(self.rows()[1][6:8], ["fail", "reverted"])

    def test_tests_column_rejects_a_verdict_value(self):
        result = attempt(self.log, tests="kept")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_verdict_column_rejects_a_tests_value(self):
        result = attempt(self.log, verdict="pass")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_unknown_verdict_exits_2(self):
        result = attempt(self.log, verdict="maybe")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_tab_in_a_field_exits_2_and_writes_nothing(self):
        attempt(self.log)
        before = self.log.read_bytes()
        result = attempt(self.log, id="a2", change="memoize\tthe parse")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.log.read_bytes(), before)

    def test_newline_in_a_field_exits_2_and_writes_nothing(self):
        result = attempt(self.log, note="line one\nline two")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_carriage_return_in_a_field_exits_2(self):
        result = attempt(self.log, hypothesis="skip unchanged pages\r")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_every_other_line_boundary_character_exits_2(self):
        # The characters str.splitlines() splits on besides \n and \r, per the
        # Python docs' table for str.splitlines.
        for char in ("\v", "\f", "\x1c", "\x1d", "\x1e", "\x85", " ", " "):
            with self.subTest(char=repr(char)):
                result = attempt(self.log, note=f"split{char}here")
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.log.exists())

    def test_log_stays_readable_after_a_refused_line_boundary(self):
        attempt(self.log)
        attempt(self.log, id="a2", change="cache\x85the parse")
        self.assertEqual(attempt(self.log, id="a3").returncode, 0)
        result = run("show", "--log", str(self.log))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [line.split("\t")[0] for line in result.stdout.splitlines()[1:]],
            ["a1", "a3"],
        )

    def test_a_tenth_field_exits_2_and_writes_nothing(self):
        args = ["append", "--log", str(self.log)]
        for name in FIELDS:
            args += [
                f"--{name}",
                "pass" if name == "tests" else "kept" if name == "verdict" else "x",
            ]
        result = run(*args, "extra")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_a_missing_field_exits_2(self):
        result = run("append", "--log", str(self.log), "--id", "a1")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_empty_required_field_exits_2(self):
        result = attempt(self.log, hypothesis="")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_empty_note_is_accepted(self):
        result = attempt(self.log, note="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.rows()[0][8], "")

    def test_missing_log_directory_exits_2(self):
        result = attempt(Path(self._tmp.name) / "absent" / "climb-log.tsv")
        self.assertEqual(result.returncode, 2)

    def test_log_whose_header_is_not_the_nine_fields_exits_2(self):
        self.log.write_text("id\tverdict\n", encoding="utf-8")
        result = attempt(self.log)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.log.read_text(encoding="utf-8"), "id\tverdict\n")


class EncodingAndEmptyLogTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.log = Path(self._tmp.name) / "climb-log.tsv"

    def append_with_bytes_note(self):
        args = ["append", "--log", str(self.log)]
        for name in FIELDS:
            value = {"tests": "pass", "verdict": "reverted"}.get(name, "x")
            args += [f"--{name}", b"bad \xff\xfe bytes" if name == "note" else value]
        return run(*args)

    @unittest.skipIf(sys.platform == "win32", "argv is bytes only on POSIX")
    def test_field_that_is_not_utf8_exits_2_and_creates_no_log(self):
        result = self.append_with_bytes_note()
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.log.exists())

    @unittest.skipIf(sys.platform == "win32", "argv is bytes only on POSIX")
    def test_field_that_is_not_utf8_leaves_an_existing_log_unchanged(self):
        attempt(self.log)
        before = self.log.read_bytes()
        self.assertEqual(self.append_with_bytes_note().returncode, 2)
        self.assertEqual(self.log.read_bytes(), before)

    def test_append_to_an_empty_log_writes_header_and_row(self):
        self.log.write_text("", encoding="utf-8")
        result = attempt(self.log)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0].split("\t"), FIELDS)
        self.assertEqual([line.split("\t")[0] for line in lines[1:]], ["a1"])

    def test_show_on_an_empty_log_prints_no_rows_and_exits_0(self):
        self.log.write_text("", encoding="utf-8")
        result = run("show", "--log", str(self.log))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")


class ShowTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.log = Path(self._tmp.name) / "climb-log.tsv"

    def test_show_prints_header_and_rows(self):
        attempt(self.log)
        attempt(self.log, id="a2", verdict="reverted", note="dropped 9f2c1ab")
        result = run("show", "--log", str(self.log))
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0].split("\t"), FIELDS)
        self.assertEqual([line.split("\t")[0] for line in lines[1:]], ["a1", "a2"])
        self.assertEqual(lines[2].split("\t")[8], "dropped 9f2c1ab")

    def test_show_before_any_attempt_prints_no_rows_and_exits_0(self):
        result = run("show", "--log", str(self.log))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("no attempts", result.stderr)

    def test_show_rejects_a_row_with_the_wrong_field_count(self):
        self.log.write_text("\t".join(FIELDS) + "\na1\tonly two\n", encoding="utf-8")
        result = run("show", "--log", str(self.log))
        self.assertEqual(result.returncode, 2)


class DecideTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.rule = Path(self._tmp.name) / "keep-rule.json"

    def write_rule(self, **rule):
        self.rule.write_text(json.dumps(rule), encoding="utf-8")

    def decide(self, before, after):
        return run(
            "decide", "--rule", str(self.rule), "--before", before, "--after", after
        )

    def test_lower_counter_beyond_the_floor_is_kept(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=2
        )
        result = self.decide("10", "7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "kept")

    def test_gain_equal_to_the_floor_is_reverted(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=2
        )
        self.assertEqual(self.decide("10", "8").stdout.strip(), "reverted")

    def test_no_change_with_a_zero_floor_is_reverted(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=0
        )
        self.assertEqual(self.decide("10", "10").stdout.strip(), "reverted")

    def test_move_in_the_wrong_direction_is_reverted(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=0
        )
        self.assertEqual(self.decide("10", "14").stdout.strip(), "reverted")

    def test_higher_direction_keeps_a_rise_beyond_the_floor(self):
        self.write_rule(
            counter="pages rendered per second", direction="higher", gain_floor=50
        )
        self.assertEqual(self.decide("1200", "1251").stdout.strip(), "kept")
        self.assertEqual(self.decide("1200", "1250").stdout.strip(), "reverted")

    def test_missing_rule_file_exits_2(self):
        result = self.decide("10", "7")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_rule_file_that_is_not_json_exits_2(self):
        self.rule.write_text("direction: lower\n", encoding="utf-8")
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_unknown_direction_exits_2(self):
        self.write_rule(
            counter="template parses per build", direction="down", gain_floor=0
        )
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_missing_counter_exits_2(self):
        self.write_rule(direction="lower", gain_floor=0)
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_negative_floor_exits_2(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=-1
        )
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_boolean_floor_exits_2(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=True
        )
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_floor_too_large_for_a_float_exits_2(self):
        self.rule.write_text(
            '{"counter": "template parses per build", "direction": "lower", '
            '"gain_floor": 1' + "0" * 400 + "}",
            encoding="utf-8",
        )
        result = self.decide("10", "7")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("out of range", result.stderr)

    def test_negative_floor_too_large_for_a_float_is_out_of_range(self):
        self.rule.write_text(
            '{"counter": "template parses per build", "direction": "lower", '
            '"gain_floor": -1' + "0" * 400 + "}",
            encoding="utf-8",
        )
        result = self.decide("10", "7")
        self.assertEqual(result.returncode, 2)
        self.assertIn("out of range", result.stderr)
        self.assertNotIn("too large", result.stderr)

    def test_unknown_rule_key_exits_2(self):
        self.write_rule(
            counter="template parses per build",
            direction="lower",
            gain_floor=0,
            target=3,
        )
        self.assertEqual(self.decide("10", "7").returncode, 2)

    def test_non_numeric_measurement_exits_2(self):
        self.write_rule(
            counter="template parses per build", direction="lower", gain_floor=0
        )
        self.assertEqual(self.decide("ten", "7").returncode, 2)
        self.assertEqual(self.decide("10", "nan").returncode, 2)


if __name__ == "__main__":
    unittest.main()
