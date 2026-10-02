"""Tests for redact.py over vendor/gitleaks/gitleaks-rules.json (beside LICENSE-gitleaks).

No secret, email, or home path is written literally here: each is assembled at run time, through
`"".join` so the compiler cannot fold the fragments into a whole token inside the .pyc.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import redact

RULES_FILE = (
    Path(__file__).resolve().parents[2] / "vendor" / "gitleaks" / "gitleaks-rules.json"
)
# AWS's documented example access key id.
AWS_EXAMPLE_KEY = "".join(("AKIA", "IOSFODNN7", "EXAMPLE"))


def test_every_shipped_rule_compiles() -> None:
    shipped = json.loads(RULES_FILE.read_text(encoding="utf-8"))["rules"]
    redactor = redact.load_redactor()
    assert redactor.skipped == {}
    assert not redactor.fail_closed
    assert redactor.rule_count == len(shipped)


def test_documented_example_token_is_replaced_with_its_rule_id() -> None:
    text = f"export AWS_ACCESS_KEY_ID={AWS_EXAMPLE_KEY} then deploy"
    assert redact.load_redactor().redact(text) == (
        "export AWS_ACCESS_KEY_ID=<redacted:aws-access-token> then deploy"
    )


def test_mid_pattern_case_flag_survives_vendoring() -> None:
    # linear-api-key is `lin_api_(?i)[a-z0-9]{40}` upstream; mixed case must still match.
    token = "".join(("lin_", "api_", "Ab3" * 13, "Z"))
    assert (
        redact.load_redactor().redact(f"key {token} here")
        == "key <redacted:linear-api-key> here"
    )


USER = "al" + "ice"
BS = "\\"


# The home-path spellings docs/conventions/windows-path-emit names, plus WSL and JSON-escaped forms.
@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("/" + "home/" + USER + "/src/a.py", "~/src/a.py"),
        ("/" + "Users/" + USER + "/src", "~/src"),
        ("C:" + BS + "Users" + BS + USER + BS + "src", "~" + BS + "src"),
        ("C:" + "/Users/" + USER + "/src", "~/src"),
        ("/c" + "/Users/" + USER + "/src", "~/src"),
        ("/mnt/c" + "/Users/" + USER + "/src", "~/src"),
        ("c:" + BS + "users" + BS + USER, "~"),
        ("D:" + "/USERS/" + USER + "/x", "~/x"),
        ("C:" + BS * 2 + "Users" + BS * 2 + USER + BS * 2 + "x", "~" + BS * 2 + "x"),
        ("C:" + BS + "Users" + BS + "Jane Doe" + BS + "src", "~" + BS + "src"),
    ],
)
def test_home_prefix_becomes_tilde(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(f"open {raw} now") == f"open {expected} now"


def test_bare_home_dir_ending_a_phrase_keeps_the_prose() -> None:
    raw = "/" + "home/" + USER
    assert (
        redact.load_redactor().redact(f"cd {raw} first, then '{raw}'")
        == "cd ~ first, then '~'"
    )


@pytest.mark.parametrize("name", ["password", "API_KEY", "Secret", "token"])
def test_short_assigned_value_is_caught_by_the_generic_assignment_pass(
    name: str,
) -> None:
    # Shorter than the 10 characters gitleaks' generic-api-key needs, so only this pass catches it.
    value = "hun" + "ter2"
    assert redact.load_redactor().redact(f"set {name}: {value} now") == (
        f"set {name}: <redacted:generic-assignment> now"
    )


SHORT = "hun" + "ter2"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # A JSON-quoted key puts a closing quote between the key and the separator.
        ('{"password": "' + SHORT + '"}', '{"password": <redacted:generic-assignment>}'),
        ("{'api_key':'" + SHORT + "'}", "{'api_key':<redacted:generic-assignment>}"),
        # A quoted value with spaces is redacted to its closing quote, not to the first space.
        (
            'password="correct horse ' + 'battery staple" ok',
            "password=<redacted:generic-assignment> ok",
        ),
        ("pwd=" + SHORT + " ok", "pwd=<redacted:generic-assignment> ok"),
        ("DB_PASSWD: " + SHORT, "DB_PASSWD: <redacted:generic-assignment>"),
    ],
)
def test_generic_assignment_covers_quoted_keys_and_values(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("password:: " + SHORT, "password:: <redacted:generic-assignment>"),
        ('password => "' + SHORT + '"', "password => <redacted:generic-assignment>"),
        ("password := " + SHORT, "password := <redacted:generic-assignment>"),
        ("DB_PASS=" + SHORT, "DB_PASS=<redacted:generic-assignment>"),
        ("passphrase: " + SHORT, "passphrase: <redacted:generic-assignment>"),
        ("bypass: yes", "bypass: yes"),
    ],
)
def test_generic_assignment_separators_and_keywords(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


@pytest.mark.parametrize(
    ("scheme", "host"),
    [("postgres", "h/db"), ("https", "host/"), ("mysql", "localhost:3306/app"), ("redis", "cache:6379")],
)
def test_url_credentials_are_redacted(scheme: str, host: str) -> None:
    raw = f"{scheme}://admin:{SHORT}@{host}"
    assert redact.load_redactor().redact(f"use {raw} now") == (
        f"use {scheme}://admin:<redacted:url-credential>@{host} now"
    )


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("my password is " + SHORT, "my password is <redacted:prose-credential>"),
        ("the password " + SHORT + " works", "the password <redacted:prose-credential> works"),
        ("password - " + SHORT, "password - <redacted:prose-credential>"),
        # A value with no digit or symbol reads as prose and stays.
        ("the password is wrong", "the password is wrong"),
        ("token count is high", "token count is high"),
    ],
)
def test_prose_credential_with_digit_or_symbol_is_redacted(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


def test_basic_auth_header_is_redacted() -> None:
    credential = "".join(("YWRtaW46", "c2VjcmV0MTIz"))  # spellchecker:disable-line
    assert redact.load_redactor().redact(f"Authorization: Basic {credential}") == (
        "Authorization: Basic <redacted:basic-auth>"
    )


def test_bearer_credential_is_redacted() -> None:
    credential = "".join(("abcd", "EFGH", "1234", ".xyz"))
    assert redact.load_redactor().redact(f"Authorization: Bearer {credential} sent") == (
        "Authorization: Bearer <redacted:bearer> sent"
    )


def test_email_becomes_placeholder() -> None:
    address = "jane.doe+ci" + "@" + "mail.example.co.uk"
    assert (
        redact.load_redactor().redact(f"mail {address}, thanks")
        == "mail <email>, thanks"
    )


def write_rules(path: Path, *rules: dict) -> Path:
    path.write_text(
        json.dumps({"rules": list(rules), "excluded": []}), encoding="utf-8"
    )
    return path


def test_rule_that_does_not_compile_is_skipped_counted_and_fails_closed(
    tmp_path: Path,
) -> None:
    rules = write_rules(
        tmp_path / "rules.json",
        {"id": "ok", "regex": "abc", "keywords": []},
        {"id": "broken", "regex": "(", "keywords": []},
    )
    redactor = redact.load_redactor(rules)
    assert list(redactor.skipped) == ["broken"]
    assert redactor.rule_count == 1
    assert redactor.fail_closed
    assert redactor.excerpt("abc", 240) is None


def test_excerpt_truncates_after_redacting() -> None:
    # Cut first, a token straddling the limit would leave its head ("AKIA...") in the excerpt.
    text = "a" * 10 + " " + AWS_EXAMPLE_KEY
    assert redact.load_redactor().excerpt(text, 16) == "aaaaaaaaaa <reda"


@pytest.mark.parametrize(
    "content",
    [
        None,
        "not json",
        json.dumps({"rules": [], "excluded": []}),
        json.dumps({"rules": [{"id": "x"}]}),
    ],
    ids=["missing", "malformed", "empty", "rule-without-regex"],
)
def test_unusable_rules_file_fails_closed(tmp_path: Path, content: str | None) -> None:
    rules = tmp_path / "rules.json"
    if content is not None:
        rules.write_text(content, encoding="utf-8")
    redactor = redact.load_redactor(rules)
    assert redactor.fail_closed
    assert redactor.excerpt("plain text", 240) is None


def test_url_path_segment_named_users_is_not_a_home() -> None:
    text = "see example.org/api/users/" + USER
    assert redact.load_redactor().redact(text) == text
