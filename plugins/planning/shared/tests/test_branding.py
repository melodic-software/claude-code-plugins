# test-scope: plugins/planning/.claude-plugin/plugin.json plugins/planning/lib/branding_helper.py plugins/planning/lib/view-settings.mjs plugins/planning/reference/html-tokens.css plugins/planning/shared/server.py plugins/planning/shared/web/app.css plugins/planning/shared/web/app.js plugins/planning/shared/web/index.html plugins/planning/shared/web/proto-pin.js plugins/planning/surface/question_shape.py
"""Shared interview server branding integration tests."""

from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from support import call, tmpdir

import server

for _git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"


def init_branded_repo(root: Path, yaml_body: str, assets: dict[str, bytes] | None = None) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "-C", str(root), "init", "-q", "-b", "main"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "Test"], check=True)
    conv = root / "docs" / "conventions"
    conv.mkdir(parents=True, exist_ok=True)
    (conv / "rendered-views.yaml").write_text(yaml_body, encoding="utf-8")
    for rel, content in (assets or {}).items():
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(content)
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    subprocess.run(["git", "-C", str(root), "-c", "commit.gpgsign=false", "commit", "-q", "-m", "seed"], check=True)
    return root


WOFF2_STUB = b"wOF2" + b"A" * 16


class TestSharedServerBranding(unittest.TestCase):
    def test_serves_shared_tokens_and_branding_css_and_logo_slot(self):
        base = tmpdir(self)
        repo = init_branded_repo(
            base / "repo",
            "branding:\n"
            "  palette:\n"
            "    light:\n"
            '      accent: "#1A4D2E"\n'
            "  type:\n"
            "    serif: \"'Brand Serif', Georgia, serif\"\n"
            "    fonts:\n"
            "      - family: Brand Serif\n"
            "        file: assets/brand.woff2\n"
            "        weight: '600'\n"
            "  logo:\n"
            "    label: Northwind Shared\n",
            {"assets/brand.woff2": WOFF2_STUB},
        )
        data_dir = repo / ".work" / "topic" / "shared" / "po"
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(repo)}):
            app = server.App(data_dir, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            port = app.guest_port

            code, _, tokens = call(port, "GET", "/html-tokens.css")
            self.assertEqual(code, 200)
            self.assertIn(b"--bg: var(--ivory);", tokens)

            code, _, brand_css = call(port, "GET", "/branding.css")
            self.assertEqual(code, 200)
            self.assertIn(b"--accent: #1A4D2E;", brand_css)
            self.assertIn(b".rv-brand", brand_css)
            self.assertIn(b"url('/branding-font/0.woff2') format('woff2')", brand_css)
            self.assertNotIn(b"data:font/", brand_css)

            code, font_headers, font_bytes = call(port, "GET", "/branding-font/0.woff2")
            self.assertEqual(code, 200)
            self.assertEqual(font_headers.get("Content-Type"), "font/woff2")
            self.assertEqual(font_headers.get("X-Content-Type-Options"), "nosniff")
            self.assertEqual(font_bytes, WOFF2_STUB)

            code, headers, index_html = call(port, "GET", "/")
            self.assertEqual(code, 200)
            self.assertEqual(headers.get("Content-Security-Policy"), server.PAGE_CSP)
            self.assertNotIn("font-src", headers.get("Content-Security-Policy", ""))
            self.assertIn(b'/html-tokens.css', index_html)
            self.assertIn(b'/branding.css', index_html)
            self.assertIn(b'/app.css', index_html)
            self.assertIn(b'/app.js', index_html)
            self.assertIn(b'class="rv-brand"', index_html)
            self.assertIn(b"Northwind Shared", index_html)
            self.assertNotIn(b"%%BRANDING_LOGO%%", index_html)
            self.assertNotIn(b"accent picker", index_html.lower())
            self.assertNotIn(b"palette picker", index_html.lower())

            code, _, app_js = call(port, "GET", "/app.js")
            self.assertEqual(code, 200)
            self.assertIn(b'E("div", "rv-theme")', app_js)
            self.assertIn(b'["system", "System"]', app_js)
            self.assertIn(b'["light", "Light"]', app_js)
            self.assertIn(b'["dark", "Dark"]', app_js)
            self.assertIn(b"b.dataset.rvTheme = k", app_js)
            self.assertIn(b'E("section", "rv-comment")', app_js)
            self.assertIn(b'discTa.id = "rv-comment-text"', app_js)
            self.assertIn(b'discTa.dataset.rvNote = "comment"', app_js)

            code, _, app_css = call(port, "GET", "/app.css")
            self.assertEqual(code, 200)
            self.assertIn(b".rv-theme", app_css)
            self.assertIn(b".rv-comment", app_css)

    def test_below_floor_palette_is_omitted_from_branding_css_and_logged(self):
        base = tmpdir(self)
        repo = init_branded_repo(
            base / "repo",
            "branding:\n"
            "  palette:\n"
            "    light:\n"
            '      bg: "#FFFFFF"\n'
            '      fg: "#CCCCCC"\n'
            '      accent: "#1A4D2E"\n',
        )
        data_dir = repo / ".work" / "topic" / "shared" / "po"
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(repo)}):
            app = server.App(data_dir, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            port = app.guest_port

            code, _, brand_css = call(port, "GET", "/branding.css")
            self.assertEqual(code, 200)
            self.assertIn(b"--accent: #1A4D2E;", brand_css)
            self.assertNotIn(b"#CCCCCC", brand_css.upper())

            notices = [
                n.get("text", "") if isinstance(n, dict) else str(n)
                for n in app.branding().get("notices") or ()
            ]
            self.assertTrue(any("fg" in t and "4.5" in t for t in notices), notices)
            log_text = (data_dir / "server.log").read_text(encoding="utf-8")
            self.assertIn("WARNING branding:", log_text)
            self.assertIn("fg", log_text)
            self.assertIn("4.5", log_text)

    def test_proto_pin_is_generated_ui_feedback_harness_copy(self):
        pin_js = (server.WEB / "proto-pin.js").read_text(encoding="utf-8")
        self.assertTrue(
            pin_js.startswith("// GENERATED from lib/ui-feedback/proto-pin.js"),
            pin_js.splitlines()[0] if pin_js else "",
        )
        self.assertIn("#4433cc", pin_js)
        self.assertIn("#a99bff", pin_js)

    def test_caches_branding_at_startup_without_spawning_per_request(self):
        base = tmpdir(self)
        data_dir = base / "data"
        cached = {"css": ":root { --accent: #1A4D2E; }", "slot_html": '<div class="rv-brand"></div>', "notices": []}
        with mock.patch.object(server._BRANDING_MOD, "resolve_branding", return_value=cached) as resolve_mock:
            app = server.App(data_dir, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            port = app.guest_port

            for _ in range(3):
                code, _, css = call(port, "GET", "/branding.css")
                self.assertEqual(code, 200)
                self.assertIn(b"--accent: #1A4D2E;", css)
                code, _, index_html = call(port, "GET", "/")
                self.assertEqual(code, 200)
                self.assertIn(b'class="rv-brand"', index_html)

            self.assertEqual(resolve_mock.call_count, 1)

    def test_default_unbranded_repo_serves_empty_branding_and_no_slot(self):
        base = tmpdir(self)
        data_dir = base / "data"
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
        with mock.patch.dict(os.environ, env, clear=True):
            app = server.App(data_dir, watch_tunnel=False)
            app.serve()
            self.addCleanup(app.shutdown)
            port = app.guest_port

            code, _, brand_css = call(port, "GET", "/branding.css")
            self.assertEqual(code, 200)
            self.assertEqual(brand_css, None)

            code, _, index_html = call(port, "GET", "/")
            self.assertEqual(code, 200)
            self.assertNotIn(b'class="rv-brand"', index_html)
            self.assertNotIn(b"%%BRANDING_LOGO%%", index_html)

    def test_managed_settings_and_dropins_override_user_settings_for_branding(self):
        base = tmpdir(self)
        cfg_dir = base / "user-cfg"
        cfg_dir.mkdir()
        (cfg_dir / "settings.json").write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "planning@melodic-software": {
                            "options": {"branding": json.dumps({"logo": {"label": "User Brand"}})}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        managed_dir = base / "managed"
        dropin_dir = managed_dir / "managed-settings.d"
        dropin_dir.mkdir(parents=True)
        (managed_dir / "managed-settings.json").write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "planning@melodic-software": {
                            "options": {"branding": json.dumps({"logo": {"label": "Managed Base"}})}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        (dropin_dir / "10-brand.json").write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "planning@melodic-software": {
                            "options": {"branding": json.dumps({"logo": {"label": "Managed Dropin"}})}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PLUGIN_OPTION_BRANDING"}
        env["CLAUDE_CONFIG_DIR"] = str(cfg_dir)
        with mock.patch.dict(os.environ, env, clear=True):
            got = server._BRANDING_MOD._installed_branding_option(managed_dir=managed_dir)
            self.assertEqual(json.loads(got), {"logo": {"label": "Managed Dropin"}})
            (dropin_dir / "10-brand.json").unlink()
            got_base = server._BRANDING_MOD._installed_branding_option(managed_dir=managed_dir)
            self.assertEqual(json.loads(got_base), {"logo": {"label": "Managed Base"}})


if __name__ == "__main__":
    unittest.main()
