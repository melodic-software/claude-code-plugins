"""Shared branding bridge for planning's Python interview servers.

Calls the plugin's bundled `lib/view-settings.mjs branding` resolver and renders
the fixed `.rv-brand` slot HTML/CSS matching `lib/html-branding.mjs`.
"""

from __future__ import annotations

import base64
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
VIEW_SETTINGS = PLUGIN_ROOT / "lib" / "view-settings.mjs"
TOKENS_FILE = PLUGIN_ROOT / "reference" / "html-tokens.css"
MANAGED_DIRS = {
    "darwin": Path("/Library/Application Support/ClaudeCode"),
    "linux": Path("/etc/claude-code"),
    "win32": Path("C:/Program Files/ClaudeCode"),
}
FONT_DATA_URL_RE = re.compile(r"url\(data:(font/(?:woff2|woff|ttf|otf));base64,([A-Za-z0-9+/=]+)\)")
FONT_EXT = {"font/woff2": "woff2", "font/woff": "woff", "font/ttf": "ttf", "font/otf": "otf"}

LOGO_SLOT_CSS = "\n".join(
    (
        ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
        ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
        ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
        ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
    )
)

EMPTY = {
    "css": "",
    "slot_html": "",
    "logo": {"kind": None, "label": None},
    "fonts": {},
    "notices": [],
    "has_overrides": False,
}


def logo_slot_html(logo: dict | None) -> str:
    if not isinstance(logo, dict):
        return ""
    kind = logo.get("kind")
    label = logo.get("label") or ""
    if not kind and not label:
        return ""
    parts: list[str] = []
    if kind == "svg" and logo.get("svg"):
        parts.append(str(logo["svg"]))
    elif kind == "image" and logo.get("dataUrl"):
        aria = html.escape(label or "Brand logo", quote=True)
        parts.append(f'<span class="rv-brand-mark rv-logo" role="img" aria-label="{aria}"></span>')
    if label:
        parts.append(f'<span class="rv-brand-label">{html.escape(label, quote=True)}</span>')
    return f'<div class="rv-brand">{"".join(parts)}</div>'


def logo_slot_css(logo: dict | None) -> str:
    if not isinstance(logo, dict):
        return ""
    if not logo.get("kind") and not logo.get("label"):
        return ""
    return LOGO_SLOT_CSS


def _managed_settings_files(managed_dir: Path | None = None) -> list[Path]:
    base = managed_dir if managed_dir is not None else MANAGED_DIRS.get(sys.platform)
    if base is None:
        return []
    files = [base / "managed-settings.json"]
    dropin = base / "managed-settings.d"
    try:
        if dropin.is_dir():
            names = sorted(
                p.name for p in dropin.iterdir() if p.name.endswith(".json") and not p.name.startswith(".")
            )
            files.extend(dropin / name for name in names)
    except OSError:
        pass
    return files


def _read_branding_from_file(settings_path: Path, plugin_id: str | None) -> str | None:
    try:
        if not settings_path.is_file():
            return None
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    configs = data.get("pluginConfigs") if isinstance(data, dict) else None
    if not isinstance(configs, dict):
        return None
    found = None
    for key in sorted(configs):
        if plugin_id is not None and key != plugin_id:
            continue
        if plugin_id is None and key != "planning" and not key.startswith("planning@"):
            continue
        entry = configs.get(key)
        opts = entry.get("options") if isinstance(entry, dict) else None
        val = opts.get("branding") if isinstance(opts, dict) else None
        if isinstance(val, str):
            found = val
    return found


def _installed_branding_option(managed_dir: Path | None = None) -> str | None:
    """Read `userConfig.branding` from env, user settings, and managed settings (managed wins)."""
    env_val = os.environ.get("CLAUDE_PLUGIN_OPTION_BRANDING")
    if env_val and not env_val.startswith("${user_config."):
        return env_val
    parts = PLUGIN_ROOT.as_posix().split("/")
    plugin_id = None
    user_settings = None
    if "cache" in parts:
        idx = len(parts) - 1 - parts[::-1].index("cache")
        if idx > 0 and parts[idx - 1] == "plugins" and len(parts) - idx == 4 and all(parts[idx + 1 :]):
            marketplace, name = parts[idx + 1], parts[idx + 2]
            plugin_id = f"{name}@{marketplace}"
            config_root = "/".join(parts[: idx - 1]) or "/"
            user_settings = Path(config_root) / "settings.json"
    if user_settings is None:
        cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR")
        if cfg_dir:
            user_settings = Path(cfg_dir) / "settings.json"
    resolved = _read_branding_from_file(user_settings, plugin_id) if user_settings is not None else None
    for managed_file in _managed_settings_files(managed_dir):
        val = _read_branding_from_file(managed_file, plugin_id)
        if val is not None:
            resolved = val
    return resolved or None


def resolve_branding(project_root: Path | str | None = None, *, option: str | None = None, team_ref: str | None = None) -> dict:
    """Resolve branding for `project_root` via `lib/view-settings.mjs branding`."""
    if not VIEW_SETTINGS.is_file():
        return dict(EMPTY)
    if option is None:
        option = _installed_branding_option()
    cmd = ["node", str(VIEW_SETTINGS), "branding"]
    if option:
        cmd.extend(["--option", option])
    if team_ref:
        cmd.extend(["--team-ref", team_ref])
    cwd = str(project_root) if project_root and Path(project_root).is_dir() else None
    env = os.environ.copy()
    if cwd:
        env["CLAUDE_PROJECT_DIR"] = cwd
    else:
        env.pop("CLAUDE_PROJECT_DIR", None)
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=10, check=False, env=env)
    except (OSError, subprocess.SubprocessError):
        return dict(EMPTY)
    if proc.returncode != 0:
        return dict(EMPTY)
    first = (proc.stdout.splitlines() or [""])[0]
    try:
        data = json.loads(first)
    except ValueError:
        return dict(EMPTY)
    logo = data.get("logo") if isinstance(data.get("logo"), dict) else {"kind": None, "label": None}
    slot_css = logo_slot_css(logo)
    raw_css = str(data.get("css") or "")
    fonts: dict[str, tuple[str, bytes]] = {}

    def _rewrite_font(match: re.Match[str]) -> str:
        media_type, b64 = match.group(1), match.group(2)
        ext = FONT_EXT[media_type]
        route = f"/branding-font/{len(fonts)}.{ext}"
        fonts[route] = (media_type, base64.b64decode(b64))
        return f"url('{route}')"

    raw_css = FONT_DATA_URL_RE.sub(_rewrite_font, raw_css)
    combined_css = "\n".join(part for part in (slot_css, raw_css) if part)
    return {
        "css": combined_css,
        "slot_html": logo_slot_html(logo),
        "logo": logo,
        "fonts": fonts,
        "notices": list(data.get("notices") or []),
        "has_overrides": bool(data.get("hasOverrides")),
    }
