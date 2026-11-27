"""Tests for redact.py over vendor/gitleaks/gitleaks-rules.json (beside LICENSE-gitleaks).

No secret, email, or home path is written literally here: each is assembled at run time, through
`"".join` so the compiler cannot fold the fragments into a whole token inside the .pyc.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import pytest

import redact
import transcript_sources

RULES_FILE = (
    Path(__file__).resolve().parents[4] / "vendor" / "gitleaks" / "gitleaks-rules.json"
)
AWS_EXAMPLE_KEY = "".join(("AKIA", "IOSFODNN7", "EXAMPLE"))


def test_every_shipped_rule_compiles() -> None:
    shipped = json.loads(RULES_FILE.read_text(encoding="utf-8"))["rules"]
    redactor = redact.load_redactor()
    assert redactor.skipped == {}
    assert not redactor.fail_closed
    assert redactor.rule_count == len(shipped)


def test_version_is_the_vendored_source_version() -> None:
    shipped = json.loads(RULES_FILE.read_text(encoding="utf-8"))
    assert redact.load_redactor().version == shipped["source_version"]


def test_documented_example_token_is_replaced_with_its_rule_id() -> None:
    text = f"export AWS_ACCESS_KEY_ID={AWS_EXAMPLE_KEY} then deploy"
    assert redact.load_redactor().redact(text) == (
        "export AWS_ACCESS_KEY_ID=<redacted:aws-access-token> then deploy"
    )


def test_a_match_ending_a_line_keeps_the_line_break_and_what_follows() -> None:
    matched = "".join(("ke", "y path: message.usage.cache_creation.ephemeral_5m_input_tokens"))
    text = f"drift {matched}\nnext line\n"
    redacted = redact.load_redactor().redact(text)
    assert redacted == "drift <redacted:generic-api-key>\nnext line\n"
    assert redacted.count("\n") == text.count("\n"), "a redaction never joins two lines"


def test_mid_pattern_case_flag_survives_vendoring() -> None:
    token = "".join(("lin_", "api_", "Ab3" * 13, "Z"))
    assert (
        redact.load_redactor().redact(f"key {token} here")
        == "key <redacted:linear-api-key> here"
    )


@pytest.mark.parametrize("prefix", ["oat01-", "oat02-"])
def test_bare_anthropic_oauth_token_is_redacted(prefix: str) -> None:
    token = "".join(("sk-ant-", prefix, "Qx7_-" * 19, "AA"))
    assert redact.load_redactor().redact(f"saw {token} successfully") == (
        "saw <redacted:anthropic-oauth-token> successfully"
    )


def test_stateless_github_app_token_with_a_dot_is_redacted_whole() -> None:
    token = "".join(("ghs_", "Ab3" * 14, ".", "eyJ", "x9_-Qz"))
    assert redact.load_redactor().redact(f"use {token} successfully") == (
        "use <redacted:github-app-token> successfully"
    )


USER = "al" + "ice"
BS = "\\"


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
    value = "hun" + "ter2"
    assert redact.load_redactor().redact(f"set {name}: {value} now") == (
        f"set {name}: <redacted:generic-assignment> now"
    )


SHORT = "hun" + "ter2"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('{"password": "' + SHORT + '"}', '{"password": <redacted:generic-assignment>}'),
        ("{'api_key':'" + SHORT + "'}", "{'api_key':<redacted:generic-assignment>}"),
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
        ("pw: " + SHORT, "pw: <redacted:generic-assignment>"),
        ("DB_PW=" + SHORT, "DB_PW=<redacted:generic-assignment>"),
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
    "password",
    ["p@ss" + "1", "p/ss" + "1", "p@s/s@" + "1"],
    ids=["at", "slash", "both"],
)
def test_url_credential_password_runs_to_the_last_at_before_the_host(password: str) -> None:
    raw = f"postgres://app:{password}@db:5432/x"
    assert redact.load_redactor().redact(f"use {raw} now") == (
        "use postgres://app:<redacted:url-credential>@db:5432/x now"
    )


@pytest.mark.parametrize(
    "text",
    ["a://b:" + "@/" * 2045, "a://b:" * 20_000],
    ids=["at-slash-dense", "schemes-without-at"],
)
def test_url_credential_pass_stays_fast_on_long_tokens(text: str) -> None:
    started = time.monotonic()
    redact.load_redactor().redact(text)
    assert time.monotonic() - started < 1.0


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("my password is " + SHORT, "my password is <redacted:prose-credential>"),
        ("the password " + SHORT + " works", "the password <redacted:prose-credential> works"),
        ("password - " + SHORT, "password - <redacted:prose-credential>"),
        ("the password is wrong", "the password is wrong"),
        ("token count is high", "token count is high"),
    ],
)
def test_prose_credential_with_digit_or_symbol_is_redacted(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


def test_url_credential_pass_stays_fast_on_a_long_hyphenated_token() -> None:
    text = "a-" * 20_000
    started = time.monotonic()
    assert redact.load_redactor().redact(text) == text
    assert time.monotonic() - started < 1.0


@pytest.mark.parametrize("breaks", ["\r", "\r\n", "\n"], ids=["cr", "crlf", "lf"])
def test_curl_rules_stay_fast_on_a_run_of_line_breaks(breaks: str) -> None:
    started = time.monotonic()
    assert redact.load_redactor().redact("curl " + breaks * 200) == "curl " + "\n" * 200
    assert time.monotonic() - started < 1.0


PEM_BEGIN = "-----BEGIN " + "RSA PRIVATE" + " KEY-----"
PEM_END = "-----END " + "RSA PRIVATE" + " KEY-----"
PEM_BODY = "\n".join(["Q" * 64] * 3)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (f"here it is\n{PEM_BEGIN}\n{PEM_BODY}\nand more", "here it is\n<redacted:private-key>"),
        (f"{PEM_BEGIN}\n{PEM_BODY}\n{PEM_END} then done", "<redacted:private-key> then done"),
    ],
    ids=["no-end", "complete"],
)
def test_private_key_block_is_redacted_with_or_without_its_end(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("mysql -uroot -p" + SHORT + " app", "mysql -uroot -p<redacted:cli-password> app"),
        ("mysqldump -h db -u admin -p" + SHORT + " app", "mysqldump -h db -u admin -p<redacted:cli-password> app"),
        ("mariadb -u admin -p'" + SHORT + " x' app", "mariadb -u admin -p<redacted:cli-password> app"),
        ("mysql -u root -p app", "mysql -u root -p app"),
        ("mysql -P3306 -h db", "mysql -P3306 -h db"),
        ("find . -name x -print", "find . -name x -print"),
        ("gcc -pedantic -Wall a.c", "gcc -pedantic -Wall a.c"),
        ("ssh -p2222 host", "ssh -p2222 host"),
    ],
)
def test_attached_database_client_password_is_redacted(raw: str, expected: str) -> None:
    assert redact.load_redactor().redact(raw) == expected


@pytest.mark.parametrize(
    "template",
    ["Authorization: Basic {}", '"Authorization": "Basic {}"', "{{'authorization': 'basic {}'}}"],
    ids=["unquoted", "double-quoted", "single-quoted"],
)
def test_basic_auth_header_is_redacted(template: str) -> None:
    credential = "".join(("YWRtaW46", "c2VjcmV0MTIz"))  # spellchecker:disable-line
    assert redact.load_redactor().redact(template.format(credential)) == template.format(
        "<redacted:basic-auth>"
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


HOME_A = "/" + "home/user-a"
FLEET = transcript_sources.resolve(
    json.dumps(
        {
            "schema": "transcript-sources/v1",
            "sources": [
                {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": HOME_A + "/.claude"},
                {"name": "host-a-win", "host": "host-a", "platform": "windows", "config_dir": "/mnt/c/" + "Users" + "/user-a/.claude"},
                {
                    "name": "host-b-wsl",
                    "host": "host-b",
                    "platform": "wsl",
                    "config_dir": "/srv/user-b/.claude",
                    "via": ["ssh", "-p", "2222", "user-b@host-b.tailnet-x.ts.net"],
                },
            ],
        }
    ),
    {},
)
NO_MACHINE: tuple[tuple[str, ...], tuple[str, ...]] = ((), ())


def publisher(**kwargs):
    kwargs.setdefault("machine", NO_MACHINE)
    kwargs.setdefault("extra", ())
    return redact.publish_redactor(FLEET, **kwargs)


def test_same_host_maps_to_the_same_placeholder_across_two_strings() -> None:
    p = publisher()
    assert p.redact("ran on host-b today") == "ran on <host-2> today"
    assert p.redact("host-b failed, host-a ok") == "<host-2> failed, <host-1> ok"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("host name HOST-A here", "host name <host-1> here"),
        ("ssh host-b.tailnet-x.ts.net", "ssh <host-2>"),
        ("source host-a-win read", "source <host-1:windows> read"),
        (f"open {HOME_A}/.claude/projects/x", "open <host-1:config>/projects/x"),
        ("open /srv/user-b/.claude", "open <host-2:config>"),
        ("logged in as user-b", "logged in as <user>"),
        ("user-a@host-b", "<user>@<host-2>"),
        (f"open {HOME_A}/.claude.json", "open ~/.claude.json"),
    ],
    ids=["host", "via-alias", "source-name", "config-dir", "remote-config-dir", "username", "ssh-destination", "home-path"],
)
def test_each_identifier_kind_is_replaced(raw: str, expected: str) -> None:
    assert publisher().redact(raw) == expected


@pytest.mark.parametrize(
    "raw",
    ["ghost-a stays", "host-ab stays", "v1.2.3.4 stays", "at 12:34:56 stays", "std::vector stays", "local stays"],
)
def test_text_that_only_resembles_an_identifier_is_kept(raw: str) -> None:
    assert publisher().redact(raw) == raw


def test_this_machines_names_map_to_the_local_hosts_placeholder() -> None:
    p = publisher(machine=(("desk-77.corp.example",), ("person-q",)))
    assert p.redact("on desk-77.corp.example and desk-77 as person-q") == "on <host-1> and <host-1> as <user>"


def test_extra_identifiers_get_a_typed_placeholder() -> None:
    p = publisher(extra=("project-zeta", "/opt/zeta"))
    assert p.redact("project-zeta at /opt/zeta/x") == "<identifier> at <identifier>/x"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("peer 100.64.0.7:22 up", "peer <ip>:22 up"),
        ("peer fd7a:115c:a1e0::7 up", "peer <ip> up"),
        ("mail jane.doe" + "@" + "mail.example.org now", "mail <email> now"),
        (f"key {AWS_EXAMPLE_KEY} here", "key <redacted:aws-access-token> here"),
    ],
    ids=["ipv4", "ipv6", "email", "secret"],
)
def test_typed_placeholders_for_ip_email_and_secret(raw: str, expected: str) -> None:
    assert publisher().redact(raw) == expected


def test_a_config_dir_two_hosts_share_gets_a_typed_placeholder() -> None:
    shared = transcript_sources.resolve(
        json.dumps(
            {
                "schema": "transcript-sources/v1",
                "sources": [
                    {"name": "a", "host": "host-a", "platform": "linux", "config_dir": "/srv/shared/.claude"},
                    {"name": "b", "host": "host-b", "platform": "linux", "config_dir": "/srv/shared/.claude", "via": ["ssh", "host-b"]},
                ],
            }
        ),
        {},
    )
    p = redact.publish_redactor(shared, machine=NO_MACHINE, extra=())
    assert p.redact("open /srv/shared/.claude/x") == "open <config>/x"


def test_default_sources_redact_the_local_config_dir_but_not_the_word_local() -> None:
    default = transcript_sources.resolve(None, {"CLAUDE_CONFIG_DIR": "/srv/user-c/.claude"}, platform="linux")
    p = redact.publish_redactor(default, machine=NO_MACHINE, extra=())
    assert p.redact("local copy in /srv/user-c/.claude/x") == "local copy in <host-1:config>/x"


def test_missing_rules_mark_the_publish_redactor_failing_closed(tmp_path: Path) -> None:
    assert publisher(path=tmp_path / "absent" / "rules.json").fail_closed
    assert not publisher().fail_closed


WIN_A = "C:" + BS + "Users" + BS + "user-a" + BS + ".claude"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("%2Fsrv%2Fuser-b%2Fx", "%2Fsrv%2F<user>%2Fx"),
        ("%5CUsers%5Cuser-a", "%5CUsers%5C<user>"),
        (BS + "nuser-a and " + BS + "thost-b", BS + "n<user> and " + BS + "t<host-2>"),
        ("host-a2 and host-aWsl", "<host-1>2 and <host-1>Wsl"),
        (WIN_A + BS + "x", "<host-1:config>" + BS + "x"),
        (WIN_A.replace(BS, "/"), "<host-1:config>"),
        ("/c/" + "Users" + "/user-a/.claude/x", "<host-1:config>/x"),
        (WIN_A.replace(BS, BS * 2), "<host-1:config>"),
        ("host-b.tail9.ts.net and host-a.lan", "<host-2> and <host-1>"),
        ("link fe80::1ff:fe23:4567:890a and 2001::1", "link <ip> and <ip>"),
    ],
    ids=["url-slash", "url-backslash", "json-escape", "digit-or-capital", "drive-backslash", "drive-slash", "git-bash",
         "json-backslash", "dns-suffix", "ipv6-short"],
)
def test_escaped_and_alternate_spellings_are_replaced(raw: str, expected: str) -> None:
    assert publisher().redact(raw) == expected


def test_a_config_dir_outside_home_drops_its_trailing_separator_and_names_its_user() -> None:
    sources = transcript_sources.resolve(
        json.dumps({"schema": "transcript-sources/v1", "sources": [
            {"name": "d", "host": "host-d", "platform": "linux", "config_dir": "/srv/user-d/.claude/"}]}),
        {},
    )
    p = redact.publish_redactor(sources, machine=NO_MACHINE)
    assert p.redact("open /srv/user-d/.claude as user-d") == "open <host-1:config> as <user>"


def test_an_extra_home_relative_path_is_caught_after_the_home_pass() -> None:
    p = publisher(extra=("~/acme-zeta",))
    assert p.redact(f"{HOME_A}/acme-zeta/file and ~/acme-zeta") == "<identifier>/file and <identifier>"


def test_an_absolute_extra_under_a_home_also_claims_its_home_relative_form() -> None:
    p = publisher(extra=(HOME_A + "/proj-z",))
    home_c = "/" + "home/user-c"
    assert p.redact("cd ~/proj-z and " + home_c + "/proj-z/f") == "cd <identifier> and <identifier>/f"


def test_a_bare_tailnet_name_is_replaced() -> None:
    assert publisher().redact("peer tail1234.ts.net and box.tail1234.ts.net up") == "peer <host> and <host> up"
